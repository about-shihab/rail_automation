import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          // Handle tap on notification
        },
      );
      _isInitialized = true;
    } catch (_) {
      // Running on windows/web or testing environment
      _isInitialized = false;
    }
  }

  Future<void> requestPermissions() async {
    final androidImpl = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
    }
  }

  Future<void> triggerSeatAvailableAlert({
    required String trainName,
    required String seatType,
    required int seatCount,
    required String travelDate,
  }) async {
    // Play haptic feedback buzzer
    try {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());
      Future.delayed(const Duration(milliseconds: 600), () => HapticFeedback.heavyImpact());
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}

    // Show system notification
    const androidDetails = AndroidNotificationDetails(
      'br_seat_alerts',
      'Train Seat Availability Alerts',
      channelDescription: 'Alerts when train seats become available for booking',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Seat Alert',
      styleInformation: BigTextStyleInformation(''),
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _notificationsPlugin.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '🚨 SEATS AVAILABLE: $trainName',
        body: '$seatCount $seatType seat(s) available for $travelDate! Book now before they are sold out!',
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
