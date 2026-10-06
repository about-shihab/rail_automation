import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../views/booking_screen.dart';
import 'booking_service.dart';
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
  }) => AndroidNotificationDetails(
    channel,
    channelName,
    icon: 'ic_stat_rail',
    largeIcon: const DrawableResourceAndroidBitmap('ic_notification_brand'),
    color: color,
    importance: Importance.high,
    priority: Priority.high,
    sound: seatAlert
        ? const RawResourceAndroidNotificationSound('seat_found')
        : null,
    onlyAlertOnce: seatAlert,
    visibility: NotificationVisibility.private,
    category: category ?? AndroidNotificationCategory.status,
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
    actions: actions,
    styleInformation: BigTextStyleInformation(body, contentTitle: title),
  );

  void openBooking(String? payload) {
    if (payload == null) return;
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
    // Sequence Rule: When OTP is sent / ready for payment, clean previous verification alert
    await cancelVerificationAndSearchAlerts();

    // Automatic SMS verification owns this step; alert only when payment is ready.
    if (state['status'] == 'awaitingOtp' && state['autoVerify'] == true) {
      try {
        await _notificationsPlugin.cancel(id: idOtp);
      } catch (_) {}
      return;
    }

    final expiry = DateTime.tryParse(state['expiresAt'] ?? '');
    final ready = state['status'] == 'readyForPayment';
    final trainName =
        state['train']?['trip_number']?.toString() ??
        state['train']?['train_name']?.toString() ??
        'Train';
    final seatType = state['seatClass']?['type']?.toString() ?? '';
    final bn = await prefersBangla();
    final title = ready
        ? (bn ? 'আসন সংরক্ষিত · পেমেন্ট করুন' : 'Seats held · Pay now')
        : (bn ? 'ওটিপি যাচাই করুন' : 'Verify your OTP');
    final description = ready
        ? (bn
              ? 'সময় শেষ হওয়ার আগে পেমেন্ট করুন।'
              : 'Pay before the hold expires.')
        : (bn
              ? 'ফোনে পাঠানো ওটিপি যাচাই করুন।'
              : 'Verify the OTP sent to your phone.');
    final body =
        "${[trainName, if (seatType.isNotEmpty) seatType].join(' · ')}\n$description";
    final androidDetails = _alertDetails(
      channel: 'br_reservations',
      channelName: 'Reserved tickets',
      title: title,
      body: body,
      stage: ready ? (bn ? 'পেমেন্ট' : 'Payment') : (bn ? 'ওটিপি' : 'OTP'),
      color: ready ? const Color(0xFFD39A26) : const Color(0xFF008CBA),
      expiry: expiry,
      category: AndroidNotificationCategory.reminder,
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
  }

  /// Sequence Rule: After complete purchase, clear OTP notification and show success notification
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
    final title = bn ? 'টিকিট নিশ্চিত হয়েছে' : 'Ticket confirmed';
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
        const channels = [
          AndroidNotificationChannel(
            'br_seat_found_v2',
            'Seats found',
            description: 'Tap to book, with train whistle and Bangla voice',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound('seat_found'),
            playSound: true,
            enableVibration: true,
          ),
          AndroidNotificationChannel(
            'br_broadcast_alerts',
            'System Announcements',
            description: 'Announcements and updates from administrator',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
          AndroidNotificationChannel(
            'br_verification_alerts_v2',
            'Human Verification',
            description: 'Notifications when human verification is required to reserve seats',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
          AndroidNotificationChannel(
            'br_reservations',
            'Reserved tickets',
            description: 'Reservation and OTP alerts',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
          AndroidNotificationChannel(
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

  Future<void> requestPermissions() async {
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
    }
  }

  Future<void> triggerSeatAvailableAlert({
    required String trainName,
    required String seatType,
    required int seatCount,
    required String travelDate,
    String? bookingLink,
    bool needsHumanVerification = false,
  }) async {
    if (appVisible ||
        (navigatorKey.currentState != null &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed)) {
      return;
    }
    final bn = await prefersBangla();
    final title = bn
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
      title: title,
      body: body,
      stage: bn ? 'আসন' : 'Seats',
      color: const Color(0xFF009B78),
      actions: [
        AndroidNotificationAction(
          'book',
          bn ? 'বুক করুন' : 'Book now',
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
        payload: bookingLink ?? 'https://eticket.railway.gov.bd/',
        notificationDetails: notificationDetails,
      );
    } catch (_) {}
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
      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _notificationsPlugin.show(
        id: notifId,
        title: title,
        body: body,
        payload: 'rail://trips',
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
    if (nav != null && nav.mounted) {
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
}
