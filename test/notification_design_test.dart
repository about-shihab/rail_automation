import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/booking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          return null;
        });
    await NotificationService().initialize(background: true);
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Map<dynamic, dynamic> latest() =>
      calls.lastWhere((call) => call.method == 'show').arguments as Map;

  test(
    'reservation notification preserves payment routing and real expiry',
    () async {
      final expiry = DateTime.now().add(const Duration(minutes: 4));
      final state = {
        'expiresAt': expiry.toIso8601String(),
        'status': 'readyForPayment',
        'train': {'trip_number': 'SONAR BANGLA EXPRESS (788)'},
        'seatClass': {'type': 'SNIGDHA'},
      };
      await NotificationService().showReservation(state);
      var notification = latest();
      final details = notification['platformSpecifics'] as Map;
      expect(notification['title'], 'Seats held · Pay now');
      expect(notification['payload'], BookingService.tripInfoUrl);
      expect(details['icon'], 'ic_stat_rail');
      expect(details['largeIcon'], 'ic_notification_brand');
      expect(details['chronometerCountDown'], isTrue);
      expect(details['when'], expiry.millisecondsSinceEpoch);
      expect(details['timeoutAfter'], greaterThan(0));
      expect((details['actions'] as List).first['showsUserInterface'], isTrue);
      state['status'] = 'awaitingOtp';
      await NotificationService().showReservation(state);
      notification = latest();
      expect(notification['title'], 'Verify your OTP');
      expect(notification['payload'], 'rail://reservation');
    },
  );

  test('automatic OTP verification does not post a manual OTP alert', () async {
    await NotificationService().showReservation({
      'status': 'awaitingOtp',
      'autoVerify': true,
    });
    expect(latest()['id'], NotificationService.idSeatFound);
    expect(latest()['title'], 'Seats held · Booking in progress');
    expect(latest()['payload'], 'rail://booking-progress');
    expect(
      calls.where(
        (call) =>
            call.method == 'show' &&
            (call.arguments as Map)['id'] == NotificationService.idOtp,
      ),
      isEmpty,
    );
    expect(
      calls.where(
        (call) =>
            call.method == 'cancel' &&
            (call.arguments as Map)['id'] == NotificationService.idSeatFound,
      ),
      isEmpty,
    );
    await NotificationService().showReservation({
      'status': 'readyForPayment',
      'autoVerify': true,
    });
    expect(latest()['title'], 'Seats held · Pay now');
  });

  test('seat alerts are delivered even while the app is visible', () async {
    NotificationService().appVisible = true;
    try {
      await NotificationService().triggerTurnstileRequiredAlert(
        trainName: 'DEMO',
        seatType: 'SNIGDHA',
      );
      expect(latest()['id'], NotificationService.idSeatFound);
      expect(latest()['payload'], 'rail://turnstile');
    } finally {
      NotificationService().appVisible = false;
    }
  });

  test('automatic booking seat alert opens progress instead of a competing booking', () async {
    await NotificationService().triggerSeatAvailableAlert(
      trainName: 'DEMO',
      seatType: 'SNIGDHA',
      seatCount: 2,
      travelDate: '23-Sep-2026',
      automaticBooking: true,
    );
    expect(latest()['payload'], 'rail://booking-progress');
    expect(latest()['title'], 'Seat found · Booking in progress');
    final details = latest()['platformSpecifics'] as Map;
    expect(details['sound'], 'seat_found');
    expect((details['actions'] as List).first['title'], 'View progress');
  });

  test('alerts follow saved Bangla language and retain destinations', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language_code', 'bn');
    await NotificationService().triggerTurnstileRequiredAlert(
      trainName: 'SONAR BANGLA EXPRESS (788)',
      seatType: 'SNIGDHA',
    );
    var notification = latest();
    expect(notification['title'], 'আসন পাওয়া গেছে · বুক করতে চাপুন');
    expect(notification['payload'], 'rail://turnstile');
    expect(notification['id'], NotificationService.idSeatFound);
    final seatDetails = notification['platformSpecifics'] as Map;
    expect(seatDetails['channelId'], 'br_seat_found_v2');
    expect(seatDetails['sound'], 'seat_found');
    expect(seatDetails['onlyAlertOnce'], isTrue);
    expect(
      (notification['platformSpecifics'] as Map)['fullScreenIntent'],
      isFalse,
    );
    await NotificationService().triggerSeatAvailableAlert(
      trainName: 'SONAR BANGLA EXPRESS (788)',
      seatType: 'SNIGDHA',
      seatCount: 2,
      travelDate: '08-Oct-2026',
    );
    notification = latest();
    expect(notification['title'], 'আসন পাওয়া গেছে · বুক করতে চাপুন');
    expect(notification['body'], contains('২ আসন'));
    await NotificationService().showPurchaseSuccessAlert(
      trainName: 'SONAR BANGLA EXPRESS (788)',
      pnr: 'DEMO-PNR',
    );
    notification = latest();
    expect(notification['title'], 'টিকিট নিশ্চিত হয়েছে');
    expect(notification['payload'], 'rail://trips');
    expect(notification['body'], contains('DEMO-PNR'));
    expect(
      calls.any(
        (c) =>
            c.method == 'cancel' &&
            (c.arguments as Map)['id'] == NotificationService.idOtp,
      ),
      isTrue,
    );
  });
}
