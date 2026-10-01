import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../views/booking_screen.dart';
import 'booking_service.dart';
import '../views/reservation_screen.dart';
import '../views/app_shell.dart';
import '../widgets/turnstile_sheet.dart';
import 'monitor_service.dart';
import 'overlay_service.dart';
import 'secure_store.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  static final navigatorKey = GlobalKey<NavigatorState>();
  String? _pendingBooking;

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

  void openBooking(String? payload) {
    if (payload == null) return;
    if (payload == 'rail://trips') {
      final navigator = navigatorKey.currentState;
      if (navigator == null) { _pendingBooking = payload; return; }
      _pendingBooking = null;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell(initialTab: AppShell.tabTrips)),
        (_) => false,
      );
      return;
    }
    if (payload == 'rail://reservation') {
      final navigator = navigatorKey.currentState;
      if (navigator == null) { _pendingBooking = payload; return; }
      _pendingBooking = null;
      navigator.push(MaterialPageRoute(builder: (_) => const ReservationScreen()));
      return;
    }
    if (payload == 'rail://turnstile') {
      // Try the system-overlay first (works when another app is in front).
      // Fall back to in-app dialog when overlay permission is not granted.
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

    final expiry = DateTime.tryParse(state['expiresAt'] ?? '');
    final ready = state['status'] == 'readyForPayment';
    final trainName = state['train']?['trip_number']?.toString() ??
        state['train']?['train_name']?.toString() ??
        'Train';
    final seatType = state['seatClass']?['type']?.toString() ?? '';
    final title = ready ? 'OTP Verified • Pay Now' : 'Verify OTP & Pay';
    final body = ready
        ? '$trainName • $seatType\nOTP verified! Tap to pay & confirm ticket.'
        : '$trainName • $seatType\nOTP sent to mobile. Tap to verify & pay.';

    final androidDetails = AndroidNotificationDetails(
      'br_reservations',
      'Reserved tickets',
      importance: Importance.max,
      priority: Priority.high,
      when: expiry?.millisecondsSinceEpoch,
      usesChronometer: expiry != null,
      chronometerCountDown: expiry != null,
      timeoutAfter: expiry?.difference(DateTime.now()).inMilliseconds.clamp(1, 3600000),
      actions: [
        AndroidNotificationAction(
          'purchase',
          ready ? 'Pay now' : 'Verify & Pay',
          showsUserInterface: true,
        ),
      ],
      styleInformation: BigTextStyleInformation(body),
    );

    await _notificationsPlugin.show(
      id: idOtp,
      title: title,
      body: body,
      payload: ready ? BookingService.tripInfoUrl : 'rail://reservation',
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
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

    final pnrStr = (pnr != null && pnr.isNotEmpty) ? 'PNR: $pnr • ' : '';
    final body = '$trainName • ${pnrStr}Payment completed. Ticket confirmed!';

    final androidDetails = AndroidNotificationDetails(
      'br_booking_success',
      'Booking Success',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      actions: [
        const AndroidNotificationAction('view_ticket', 'View Ticket', showsUserInterface: true),
      ],
      styleInformation: BigTextStyleInformation(body),
    );

    try {
      await _notificationsPlugin.show(
        id: idPurchaseSuccess,
        title: 'Ticket Booked Successfully! 🚆',
        body: body,
        payload: 'rail://trips',
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    } catch (_) {}
  }

  void openPendingBooking() => openBooking(_pendingBooking);

  // ── Turnstile: overlay-first, in-app fallback ────────────────────────────

  /// Attempt to show the Turnstile challenge as a system window overlay that
  /// floats over any app. Falls back to an in-app modal dialog if the
  /// SYSTEM_ALERT_WINDOW permission has not been granted.
  void _handleTurnstileRequest(String payload) {
    if (TurnstileDialog.isShowing || OverlayService.isShowing) return;
    // Read stored context label if available (set before triggering notification)
    SecureStore.read('rail_turnstile_context').then((label) async {
      if (TurnstileDialog.isShowing || OverlayService.isShowing) return;
      final contextLabel = label ?? '';
      // Try overlay path first
      final canOverlay = await OverlayService.canDrawOverlays();
      if (canOverlay) {
        final token = await OverlayService.showTurnstile(contextLabel: contextLabel);
        if (token != null && token.isNotEmpty) {
          _onTurnstileSolved(token);
        }
        return;
      }
      // Fall back: bring app to foreground and show in-app dialog
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        _pendingBooking = payload;
        return;
      }
      if (!navigator.mounted) return;
      TurnstileDialog.show(navigator.context, contextLabel: contextLabel).then((token) {
        if (token != null && token.isNotEmpty) _onTurnstileSolved(token);
      });
    });
  }

  void _onTurnstileSolved(String token) {
    final navigator = navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    try {
      navigator.context.read<MonitorService>().onTurnstileSolved(token);
    } catch (_) {}
  }

  Future<void> initialize({bool background = false}) async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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
        const verificationChannel = AndroidNotificationChannel(
          'br_verification_alerts',
          'Human Verification',
          description:
              'Notifications when human verification is required to reserve seats',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        await androidImpl.createNotificationChannel(verificationChannel);
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
    final String title;
    final String body;
    if (needsHumanVerification) {
      title = 'Seat found — Action needed';
      body = '$trainName · $seatType · $travelDate\nTap to complete booking now.';
    } else {
      title = 'Seats available — $trainName';
      body = '$seatCount seat${seatCount == 1 ? '' : 's'} · $seatType · $travelDate';
    }
    final androidDetails = AndroidNotificationDetails(
      'br_seat_alerts',
      'Seat Availability',
      channelDescription: 'Alerts when train seats become available for booking',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: needsHumanVerification ? 'Seat found — action needed' : 'Seats available',
      actions: const [AndroidNotificationAction('book', 'Book now', showsUserInterface: true)],
      styleInformation: BigTextStyleInformation(body),
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
        id: '$trainName:$seatType:$travelDate'.codeUnits.fold<int>(
          0, (value, char) => (value * 31 + char) & 0x7fffffff),
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
    // Sequence Rule: When human check is needed, clear any previous alerts
    try {
      await _notificationsPlugin.cancel(id: idSeatFound);
      await _notificationsPlugin.cancel(id: idOtp);
      await _notificationsPlugin.cancel(id: idPurchaseSuccess);
      await _notificationsPlugin.cancel(id: 772);
      await _notificationsPlugin.cancel(id: 99991);
    } catch (_) {}

    final body = '$trainName • $seatType\nTap to verify and continue booking.';
    final androidDetails = AndroidNotificationDetails(
      'br_verification_alerts',
      'Human Verification',
      channelDescription:
          'Notifications when human verification is required to reserve seats',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Seat found — Human check needed',
      actions: const [
        AndroidNotificationAction(
          'verify_human',
          'Verify now',
          showsUserInterface: true,
        ),
      ],
      styleInformation: BigTextStyleInformation(body),
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
        id: idHumanCheck,
        title: 'Seat Found! Human Check Needed',
        body: body,
        payload: 'rail://turnstile',
        notificationDetails: notificationDetails,
      );
    } catch (_) {}
  }

  Future<void> testNotification() async {
    await triggerSeatAvailableAlert(
      trainName: 'MAHANAGAR PROVATI (704)',
      seatType: 'SNIGDHA',
      seatCount: 4,
      travelDate: '23-Sep-2026',
    );
  }
}
