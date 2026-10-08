import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../views/booking_screen.dart';
import '../views/announcement_screen.dart';
import 'login_flow.dart';
import 'booking_service.dart';
import 'booking_activity.dart';
import 'turnstile_gate.dart';
import '../views/reservation_screen.dart';
import '../views/app_shell.dart';
import 'monitor_service.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  static final navigatorKey = GlobalKey<NavigatorState>();
  String? _pendingBooking;
  // Workers receive this from the live UI before each monitoring tick.
  bool appVisible = false;

  static String bookingUrl(String from, String to, String date, String seat) =>
      Uri.https('eticket.railway.gov.bd', '/booking/train/search', {
        'fromcity': from,
        'tocity': to,
        'doj': date,
        'class': seat,
      }).toString();

  static const int idSeatFound = 800;
  static const int idHumanCheck = 801;
  static const int idOtp = 802;
  static const int idPurchaseSuccess = 803;

  /// Read the persisted locale again so background-isolate alerts follow changes.
  static Future<bool> prefersBangla() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString('app_language_code') != 'en';
    } catch (_) {
      return true;
    }
  }

  AndroidNotificationDetails _alertDetails({
    required String channel,
    required String channelName,
    required String title,
    required String body,
    required String stage,
    required Color color,
    List<AndroidNotificationAction> actions = const [],
    DateTime? expiry,
    AndroidNotificationCategory? category,
    bool seatAlert = false,
    bool onlyAlertOnce = false,
  }) => AndroidNotificationDetails(
    channel,
    channelName,
    icon: 'ic_stat_rail',
    largeIcon: const DrawableResourceAndroidBitmap('ic_notification_brand'),
    color: color,
    importance: Importance.max,
    priority: Priority.max,
    sound: seatAlert
        ? const RawResourceAndroidNotificationSound('seat_found')
        : null,
    onlyAlertOnce: onlyAlertOnce,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 800, 400, 800]),
    visibility: NotificationVisibility.public,
    category: seatAlert
        ? AndroidNotificationCategory.alarm
        : (category ?? AndroidNotificationCategory.status),
    subText: stage,
    groupKey: 'rail_pro.booking',
    showWhen: expiry != null,
    when: expiry?.millisecondsSinceEpoch,
    usesChronometer: expiry != null,
    chronometerCountDown: expiry != null,
    timeoutAfter: expiry
        ?.difference(DateTime.now())
        .inMilliseconds
        .clamp(1, 3600000),
    autoCancel: true,
    fullScreenIntent: false,
    actions: actions,
    styleInformation: BigTextStyleInformation(body, contentTitle: title),
  );

  void openBooking(String? payload) {
    if (payload == null) return;
    final announcement = Uri.tryParse(payload);
    if (announcement?.scheme == 'rail' &&
        announcement?.host == 'announcement' &&
        announcement!.pathSegments.length == 1) {
      final navigator = navigatorKey.currentState;
      if (navigator == null || !navigator.mounted) {
        _pendingBooking = payload;
        return;
      }
      _pendingBooking = null;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => AnnouncementScreen(
            notificationId: announcement.pathSegments.single,
          ),
        ),
      );
      return;
    }
    if (payload == 'rail://login') {
      final navigator = navigatorKey.currentState;
      if (navigator == null || !navigator.mounted) {
        _pendingBooking = payload;
        return;
      }
      _pendingBooking = null;
      unawaited(LoginFlow.recoverNow());
      return;
    }
    if (payload == 'rail://booking-progress') {
      if (navigatorKey.currentState == null ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        _pendingBooking = payload;
      } else {
        _pendingBooking = null;
        // Bring the app forward without starting a competing manual booking.
        // The active booking loader and normal reservation flow own navigation.
        unawaited(_openActiveReservation());
      }
      return;
    }
    if (payload == 'rail://trips') {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _pendingBooking = payload;
        return;
      }
      _pendingBooking = null;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const AppShell(initialTab: AppShell.tabTrips),
        ),
        (_) => false,
      );
      return;
    }
    if (payload == 'rail://reservation') {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _pendingBooking = payload;
        return;
      }
      _pendingBooking = null;
      navigator.push(
        MaterialPageRoute(builder: (_) => const ReservationScreen()),
      );
      return;
    }
    if (payload == 'rail://turnstile') {
      final life = WidgetsBinding.instance.lifecycleState;
      if (life != null && life != AppLifecycleState.resumed) {
        _pendingBooking = payload;
        return;
      }
      _pendingBooking = null;
      _handleTurnstileRequest(payload);
      return;
    }
    final uri = Uri.tryParse(payload);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'eticket.railway.gov.bd') {
      return;
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingBooking = payload;
      return;
    }
    _pendingBooking = null;
    navigator.push(
      MaterialPageRoute(builder: (_) => BookingScreen(url: payload)),
    );
  }

  Future<void> clearAlerts() async {
    _pendingBooking = null;
    if (_isInitialized) await _notificationsPlugin.cancelAll();
  }

  Future<void> _openActiveReservation() async {
    if (BookingActivity.instance.busy || TurnstileGate.instance.isShowing) {
      return;
    }
    final pending = await BookingService.pending();
    final navigator = navigatorKey.currentState;
    if (navigator == null ||
        !navigator.mounted ||
        BookingActivity.instance.busy ||
        TurnstileGate.instance.isShowing) {
      return;
    }
    if (pending?['status'] == 'awaitingOtp' ||
        pending?['status'] == 'readyForPayment') {
      if (!ReservationScreen.isActive) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const ReservationScreen()),
        );
      }
    } else {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const AppShell(initialTab: AppShell.tabMonitor),
        ),
      );
    }
  }

  /// Cancels previous human check or seat alert notifications to maintain clean sequence
  Future<void> cancelVerificationAndSearchAlerts() async {
    try {
      await _notificationsPlugin.cancel(id: idHumanCheck);
      await _notificationsPlugin.cancel(id: idSeatFound);
      await _notificationsPlugin.cancel(id: 99991);
    } catch (_) {}
  }

  /// Cancels all reservation & OTP related alerts
  Future<void> cancelReservationAlerts() async {
    try {
      await _notificationsPlugin.cancel(id: idOtp);
      await _notificationsPlugin.cancel(id: idHumanCheck);
      await _notificationsPlugin.cancel(id: idSeatFound);
      await _notificationsPlugin.cancel(id: 99991);
    } catch (_) {}
  }

  Future<void> showReservation(Map<String, dynamic> state) async {
    final trainName =
        state['train']?['trip_number']?.toString() ??
        state['train']?['train_name']?.toString() ??
        'Train';
    final seatType = state['seatClass']?['type']?.toString() ?? '';
    await cancelVerificationAndSearchAlerts();

    final expiry = DateTime.tryParse(state['expiresAt'] ?? '');
    final ready = state['status'] == 'readyForPayment';
    final bn = await prefersBangla();
    final title = ready
        ? (bn ? 'আসন সংরক্ষিত · পেমেন্ট করুন' : 'Seats held · Pay now')
        : (bn
              ? 'আপনার টিকেট বুকিং কনফার্ম হয়েছে'
              : 'Your seat reservation is confirmed');
    final description = ready
        ? (bn
              ? 'ওটিপি যাচাই হয়েছে। বুকিং সম্পূর্ণ করতে সময় শেষ হওয়ার আগে টিকেট কিনুন।'
              : 'OTP verified. Purchase your ticket before the hold expires to complete booking.')
        : (bn
              ? (state['autoVerify'] == true
                    ? 'স্বয়ংক্রিয় ওটিপি যাচাইয়ের অপেক্ষায়। প্রয়োজনে অ্যাপ খুলে ওটিপি দিন। পেমেন্ট এখনও বাকি।'
                    : 'অ্যাপ খুলে ফোনে পাঠানো ওটিপি যাচাই করুন, তারপর টিকেট কিনুন।')
              : (state['autoVerify'] == true
                    ? 'Waiting for automatic OTP verification. Open the app to enter it manually if needed. Payment is still required.'
                    : 'Open the app to verify your OTP, then purchase your ticket.'));
    final body =
        "${[trainName, if (seatType.isNotEmpty) seatType].join(' · ')}\n$description";
    final androidDetails = _alertDetails(
      channel: 'br_reservations_v3',
      channelName: 'Reserved tickets (High Alert)',
      title: title,
      body: body,
      stage: ready ? (bn ? 'পেমেন্ট' : 'Payment') : (bn ? 'ওটিপি' : 'OTP'),
      color: ready ? const Color(0xFFD39A26) : const Color(0xFF008CBA),
      expiry: expiry,
      seatAlert: true,
      category: AndroidNotificationCategory.alarm,
      actions: [
        AndroidNotificationAction(
          'purchase',
          ready
              ? (bn ? 'পেমেন্ট করুন' : 'Pay now')
              : (bn ? 'ওটিপি যাচাই' : 'Verify OTP'),
          showsUserInterface: true,
        ),
      ],
    );

    try {
      await _notificationsPlugin.show(
        id: idOtp,
        title: title,
        body: body,
        payload: ready ? BookingService.tripInfoUrl : 'rail://reservation',
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Sequence Rule: After complete purchase, clear OTP notification and show success notification
  Future<void> showLoginRequired() async {
    final bn = await prefersBangla();
    final title = bn ? 'আবার লগইন করুন' : 'Railway login required';
    final body = bn
        ? 'সেশন মেয়াদোত্তীর্ণ বা বাতিল হয়েছে। অ্যাপ খুলে লগইন যাচাই করুন।'
        : 'Your session expired or was invalidated. Open the app to verify login.';
    try {
      await _notificationsPlugin.show(
        id: 804,
        title: title,
        body: body,
        payload: 'rail://login',
        notificationDetails: NotificationDetails(
          android: _alertDetails(
            channel: 'br_login_recovery',
            channelName: 'Railway login',
            title: title,
            body: body,
            stage: 'Login',
            color: const Color(0xFF008CBA),
            onlyAlertOnce: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> clearLoginAlert() async {
    try {
      await _notificationsPlugin.cancel(id: 804);
    } catch (_) {}
  }

  /// Explain the transition from fast foreground polling to durable jobs.
  Future<void> showBackgroundSearchContinues() async {
    final bn = await prefersBangla();
    final title = bn ? 'আসন খোঁজা চলবে' : 'Seat search continues';
    final body = bn
        ? 'ট্রেন ছাড়ার সময় পর্যন্ত পর্যায়ক্রমে আসন খোঁজা চলবে। আরও ঘন ঘন খুঁজতে Rail Pro খুলুন।'
        : 'Scheduled checks continue until train departure. Open Rail Pro for more frequent seat checks.';
    try {
      await _notificationsPlugin.show(
        id: 805,
        title: title,
        body: body,
        payload: 'rail://trips',
        notificationDetails: NotificationDetails(
          android: _alertDetails(
            channel: 'br_search_paused',
            channelName: 'Search paused',
            title: title,
            body: body,
            stage: bn ? 'অনুসন্ধান' : 'Monitoring',
            color: const Color(0xFFD39A26),
            onlyAlertOnce: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> showPurchaseSuccessAlert({
    required String trainName,
    String? pnr,
  }) async {
    try {
      await _notificationsPlugin.cancel(id: idOtp);
      await _notificationsPlugin.cancel(id: idHumanCheck);
      await _notificationsPlugin.cancel(id: idSeatFound);
      await _notificationsPlugin.cancel(id: 772);
      await _notificationsPlugin.cancel(id: 99991);
    } catch (_) {}

    final bn = await prefersBangla();
    final title = bn ? 'আপনার টিকেট বুকিং কনফার্ম হয়েছে' : 'Ticket confirmed';
    final body =
        "$trainName${(pnr != null && pnr.isNotEmpty) ? '\nPNR · $pnr' : ''}";
    final androidDetails = _alertDetails(
      channel: 'br_booking_success',
      channelName: 'Booking Success',
      title: title,
      body: body,
      stage: bn ? 'নিশ্চিত' : 'Confirmed',
      color: const Color(0xFF009B78),
      actions: [
        AndroidNotificationAction(
          'view_ticket',
          bn ? 'টিকিট দেখুন' : 'View ticket',
          showsUserInterface: true,
        ),
      ],
    );

    try {
      await _notificationsPlugin.show(
        id: idPurchaseSuccess,
        title: title,
        body: body,
        payload: 'rail://trips',
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  void openPendingBooking() => openBooking(_pendingBooking);

  // ── Turnstile: in-app overlay ─────────────────────────────────────────────

  /// Notification tap → bring the in-app "processing ticket" overlay up, but
  /// only if a human check is really still pending.
  Future<void> _handleTurnstileRequest(String payload) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) {
      _pendingBooking = payload; // replay once the UI is up
      return;
    }
    try {
      final monitor = navigator.context.read<MonitorService>();
      // An already restored pending check can start on the notification tap.
      if (!monitor.needsTurnstile) await monitor.restore(startTimers: false);
      if (monitor.needsTurnstile) await monitor.resolveTurnstile();
    } catch (_) {}
  }

  Future<void> initialize({bool background = false}) async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('ic_stat_rail');
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: !background,
      requestBadgePermission: !background,
      requestSoundPermission: !background,
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          if (details.actionId == 'verify_human' ||
              details.actionId == 'solve_turnstile' ||
              details.payload == 'rail://turnstile') {
            openBooking('rail://turnstile');
          } else {
            openBooking(details.payload);
          }
        },
      );
      _isInitialized = true;
      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImpl != null) {
        final channels = [
          const AndroidNotificationChannel(
            'br_seat_found_v2',
            'Seats found',
            description: 'Tap to book, with train whistle and Bangla voice',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('seat_found'),
            playSound: true,
            enableVibration: true,
          ),
          const AndroidNotificationChannel(
            'br_broadcast_alerts',
            'System Announcements',
            description: 'Announcements and updates from administrator',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
          const AndroidNotificationChannel(
            'br_verification_alerts_v2',
            'Human Verification',
            description: 'Notifications when human verification is required to reserve seats',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
          const AndroidNotificationChannel(
            'br_reservations',
            'Reserved tickets',
            description: 'Reservation and OTP alerts',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('seat_found'),
            playSound: true,
            enableVibration: true,
          ),
          const AndroidNotificationChannel(
            'br_booking_success',
            'Booking Success',
            description: 'Ticket purchase confirmation alerts',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        ];
        for (final ch in channels) {
          await androidImpl.createNotificationChannel(ch);
        }
      }
      if (!background) {
        final launch = await _notificationsPlugin
            .getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) {
          _pendingBooking = launch?.notificationResponse?.payload;
        }
      }
    } catch (_) {
      // Running on windows/web or testing environment
      _isInitialized = false;
    }
  }

  Future<bool> requestPermissions() async {
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  Future<bool> areNotificationsEnabled() async {
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      final enabled = await androidImpl.areNotificationsEnabled();
      return enabled ?? false;
    }
    return true;
  }

  Future<void> triggerSeatAvailableAlert({
    required String trainName,
    required String seatType,
    required int seatCount,
    required String travelDate,
    String? bookingLink,
    bool needsHumanVerification = false,
    bool automaticBooking = false,
    bool reservationHeld = false,
  }) async {
    final bn = await prefersBangla();
    final title = reservationHeld
        ? (bn
              ? 'আসন সংরক্ষিত · বুকিং চলছে'
              : 'Seats held · Booking in progress')
        : automaticBooking
        ? (bn
              ? 'আসন পাওয়া গেছে · বুকিং চলছে'
              : 'Seat found · Booking in progress')
        : bn
        ? 'আসন পাওয়া গেছে · বুক করতে চাপুন'
        : 'Seat found · Tap to book';
    final number = bn
        ? '$seatCount'.split('').map((c) => '০১২৩৪৫৬৭৮৯'[int.parse(c)]).join()
        : '$seatCount';
    final description = [
      if (seatType.isNotEmpty) seatType,
      if (travelDate.isNotEmpty) travelDate,
      if (seatCount > 0)
        '$number ${bn ? 'আসন' : (seatCount == 1 ? 'seat' : 'seats')}',
    ].join(' · ');
    final body = '$trainName\n$description';
    final androidDetails = _alertDetails(
      channel: 'br_seat_found_v2',
      channelName: 'Seats found',
      seatAlert: true,
      onlyAlertOnce: true,
      title: title,
      body: body,
      stage: bn ? 'আসন' : 'Seats',
      color: const Color(0xFF009B78),
      actions: [
        AndroidNotificationAction(
          'book',
          automaticBooking
              ? (bn ? 'অগ্রগতি দেখুন' : 'View progress')
              : (bn ? 'বুক করুন' : 'Book now'),
          showsUserInterface: true,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _notificationsPlugin.show(
        id: idSeatFound,
        title: title,
        body: body,
        payload: automaticBooking
            ? 'rail://booking-progress'
            : bookingLink ?? 'https://eticket.railway.gov.bd/',
        notificationDetails: notificationDetails,
      );
      debugPrint(
        '🔔 [NotificationService] ✅ Successfully posted SEAT FOUND alert for $trainName ($seatType: $seatCount seats)',
      );
    } catch (e) {
      debugPrint(
        '🚨 [NotificationService] Standard seat alert error: $e. Falling back to default high alert...',
      );
      try {
        await _notificationsPlugin.show(
          id: idSeatFound,
          title: title,
          body: body,
          payload: automaticBooking
              ? 'rail://booking-progress'
              : bookingLink ?? 'https://eticket.railway.gov.bd/',
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'br_broadcast_alerts',
              'System Announcements',
              importance: Importance.max,
              priority: Priority.max,
              enableVibration: true,
              styleInformation: BigTextStyleInformation(
                body,
                contentTitle: title,
              ),
            ),
          ),
        );
      } catch (err) {
        debugPrint(
          '🚨 [NotificationService] ❌ Fallback alert also failed: $err',
        );
      }
    }

    // In-app visual notification if app is currently in foreground
    final nav = navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      try {
        ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF009B78),
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> triggerTurnstileRequiredAlert({
    required String trainName,
    required String seatType,
  }) async {
    // Booking continuation replaces the seat alert instead of creating a second alert.
    try {
      await _notificationsPlugin.cancel(id: idHumanCheck);
    } catch (_) {}
    await triggerSeatAvailableAlert(
      trainName: trainName,
      seatType: seatType,
      seatCount: 0,
      travelDate: '',
      bookingLink: 'rail://turnstile',
    );
  }

  Future<void> testNotification() async {
    await triggerSeatAvailableAlert(
      trainName: 'MAHANAGAR PROVATI (704)',
      seatType: 'SNIGDHA',
      seatCount: 4,
      travelDate: '23-Sep-2026',
    );
  }

  StreamSubscription? _fbNotificationSub;
  DateTime? _appStartTime;
  String? _listeningPhone;
  bool _isListening = false;
  final Set<String> _seenNotificationDocIds = <String>{};
  bool _seenIdsLoaded = false;

  Future<void> _loadSeenIds() async {
    if (_seenIdsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('seen_firebase_notifications') ?? [];
      _seenNotificationDocIds.addAll(list);
      _seenIdsLoaded = true;
    } catch (_) {}
  }

  Future<void> _saveSeenId(String docId) async {
    _seenNotificationDocIds.add(docId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _seenNotificationDocIds.toList();
      final toSave = list.length > 200 ? list.sublist(list.length - 200) : list;
      await prefs.setStringList('seen_firebase_notifications', toSave);
    } catch (_) {}
  }

  Future<void> clearSeenIds() async {
    _seenNotificationDocIds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('seen_firebase_notifications');
    } catch (_) {}
  }

  static String _normalizePhone(String? raw) {
    if (raw == null) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('880') && digits.length >= 13) {
      return digits.substring(2);
    }
    return digits;
  }

  bool _matchesPhone(String? userPhone, String? target, String? targetPhone) {
    if (target == 'all') return true;
    final u = _normalizePhone(userPhone);
    if (u.isEmpty) return false;
    final t1 = _normalizePhone(target);
    final t2 = _normalizePhone(targetPhone);
    return (t1.isNotEmpty && (t1 == u || t1.endsWith(u) || u.endsWith(t1))) ||
        (t2.isNotEmpty && (t2 == u || t2.endsWith(u) || u.endsWith(t2)));
  }

  /// Starts listening to broadcast or user-specific notifications from Firestore 'notifications' table
  void startListeningToFirebaseNotifications(String? phone) async {
    final cleanPhone = phone?.trim();
    if (_isListening && _listeningPhone == cleanPhone) {
      return;
    }
    _fbNotificationSub?.cancel();
    _listeningPhone = cleanPhone;
    _isListening = true;
    _appStartTime ??= DateTime.now();

    await _loadSeenIds();
    debugPrint(
      '[NotificationService] Listening to notifications for user: "$cleanPhone"',
    );

    try {
      _fbNotificationSub = FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .listen(
            (snap) async {
              for (final change in snap.docChanges) {
                if (change.type == DocumentChangeType.added) {
                  final docId = change.doc.id;
                  // Strict duplicate check: NEVER display the same notification ID twice
                  if (_seenNotificationDocIds.contains(docId)) {
                    continue;
                  }

                  final data = change.doc.data();
                  if (data == null) continue;
                  // Push announcements are displayed by FCM (including while
                  // closed). Replaying them here would create duplicate alerts.
                  if (data['delivery'] == 'push') continue;
                  final target = data['target']?.toString() ?? 'all';
                  final targetPhone = data['targetPhone']?.toString();
                  final ts = data['createdAt'];
                  final createdDate = ts is Timestamp ? ts.toDate() : null;

                  // If createdDate is null (pending server timestamp), it was just created right now
                  final isRecent =
                      createdDate == null ||
                      !createdDate.isBefore(
                        _appStartTime!.subtract(const Duration(minutes: 30)),
                      );

                  if (!isRecent) {
                    await _saveSeenId(docId);
                    continue;
                  }

                  final isForUser = _matchesPhone(
                    cleanPhone,
                    target,
                    targetPhone,
                  );

                  if (isForUser) {
                    await _saveSeenId(docId);
                    final title = data['title']?.toString() ?? 'Announcement';
                    final body = data['body']?.toString() ?? '';
                    debugPrint(
                      '🔔 [NotificationService] Displaying notification: "$title" - "$body"',
                    );
                    await showBroadcastNotification(title: title, body: body);
                  }
                }
              }
            },
            onError: (err) {
              debugPrint(
                '[NotificationService] Firestore notifications error: $err',
              );
            },
          );
    } catch (e) {
      debugPrint('[NotificationService] startListening error: $e');
    }
  }

  Future<void> showBroadcastNotification({
    required String title,
    required String body,
    String? documentId,
  }) async {
    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'br_broadcast_alerts',
        'System Announcements',
        channelDescription: 'Announcements and updates from administrator',
        icon: 'ic_stat_rail',
        largeIcon: const DrawableResourceAndroidBitmap('ic_notification_brand'),
        color: const Color(0xFF009B78),
        visibility: NotificationVisibility.private,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      final notifId = documentId == null
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : announcementNotificationId(documentId);
      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: body,
        payload: documentId == null
            ? 'rail://trips'
            : Uri(
                scheme: 'rail',
                host: 'announcement',
                pathSegments: [documentId],
              ).toString(),
        notificationDetails: notificationDetails,
      );
      debugPrint(
        '[NotificationService] ✅ Successfully posted system notification',
      );
    } catch (e) {
      debugPrint(
        '[NotificationService] ❌ Failed to show system notification: $e',
      );
    }

    // Also trigger in-app banner for instant visual response
    final nav = navigatorKey.currentState;
    if (nav != null &&
        nav.mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0284C7),
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Stable across isolates/restarts and separate from fixed booking alert IDs.
  static int announcementNotificationId(String documentId) {
    var hash = 0x811c9dc5;
    for (final char in documentId.codeUnits) {
      hash = ((hash ^ char) * 0x01000193) & 0x3fffffff;
    }
    return 100000 + hash;
  }

  Future<void> deliverAdminAnnouncement({
    required String documentId,
    required String title,
    required String body,
    bool alreadyDisplayed = false,
  }) async {
    await _loadSeenIds();
    if (_seenNotificationDocIds.contains(documentId)) return;
    await _saveSeenId(documentId);
    if (!alreadyDisplayed) {
      await showBroadcastNotification(
        title: title,
        body: body,
        documentId: documentId,
      );
    }
  }
}
