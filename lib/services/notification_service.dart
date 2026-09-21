import 'package:flutter/material.dart';

import '../views/booking_screen.dart';

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

  void openBooking(String? payload) {
    if (payload == null) return;
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

  void openPendingBooking() => openBooking(_pendingBooking);

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
          openBooking(details.payload);
        },
      );
      _isInitialized = true;
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
  }) async {
    // Show system notification
    final body = '$travelDate • $seatCount আসন / seats • $seatType\nবুক করতে চাপুন • Tap to book';
    final androidDetails = AndroidNotificationDetails(
      'br_seat_alerts',
      'Train Seat Availability Alerts',
      channelDescription:
          'Alerts when train seats become available for booking',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Seat Alert',
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
        title: 'টিকেট পাওয়া গেছে! • Seats found! $trainName',
        body: body,
        payload: bookingLink ?? 'https://eticket.railway.gov.bd/',
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
