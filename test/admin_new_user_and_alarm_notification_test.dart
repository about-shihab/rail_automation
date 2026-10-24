import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/admin_service.dart';
import 'package:rail_automation/services/notification_service.dart';

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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<dynamic, dynamic> latest() =>
      calls.lastWhere((call) => call.method == 'show').arguments as Map;

  group('Alarm notification tests', () {
    test('seat alert notification is configured like a long persistent alarm', () async {
      await NotificationService().triggerSeatAvailableAlert(
        trainName: 'SUBORNO EXPRESS (701)',
        seatType: 'SNIGDHA',
        seatCount: 3,
        travelDate: '26-Oct-2026',
      );

      final notification = latest();
      final details = notification['platformSpecifics'] as Map;

      // 1. Audio stream set to USAGE_ALARM so it sounds at alarm volume
      expect(details['audioAttributesUsage'], AudioAttributesUsage.alarm.value);

      // 2. FLAG_INSISTENT (4) loops the audio continuously until user interacts
      expect(details['additionalFlags'], Int32List.fromList([4]));

      // 3. Android notification category set to alarm
      expect(details['category'], 'alarm');

      // 4. Loud custom train whistle sound configured
      expect(details['sound'], 'seat_found');

      // 5. Vibration pattern configured for long repeating pulses
      expect(details['enableVibration'], isTrue);
      expect((details['vibrationPattern'] as Int64List).length, greaterThan(6));
    });

    test('via seat alert notification is also configured like an alarm', () async {
      await NotificationService().triggerViaSeatAvailableAlert(
        trainName: 'SUBORNO EXPRESS (701)',
        viaStation: 'Akhaura',
        fromCity: 'Dhaka',
        toCity: 'Chattogram',
        travelDate: '26-Oct-2026',
        seatType: 'SNIGDHA',
        seatCount: 2,
      );

      final notification = latest();
      final details = notification['platformSpecifics'] as Map;

      expect(details['audioAttributesUsage'], AudioAttributesUsage.alarm.value);
      expect(details['additionalFlags'], Int32List.fromList([4]));
      expect(details['category'], 'alarm');
      expect(details['sound'], 'seat_found');
    });
  });

  group('Admin new user tests', () {
    test('AdminUser correctly identifies new users registered within 7 days', () {
      final now = DateTime.now();

      final newUser = AdminUser(
        phone: '01711111111',
        displayName: 'New Traveler',
        email: 'new@example.com',
        credits: 5,
        isActive: true,
        isAdmin: false,
        isBlocked: false,
        lastActiveAt: now,
        createdAt: now.subtract(const Duration(hours: 3)),
      );

      final oldUser = AdminUser(
        phone: '01822222222',
        displayName: 'Veteran Traveler',
        email: 'old@example.com',
        credits: 20,
        isActive: true,
        isAdmin: false,
        isBlocked: false,
        lastActiveAt: now,
        createdAt: now.subtract(const Duration(days: 30)),
      );

      expect(newUser.isNewUser, isTrue);
      expect(oldUser.isNewUser, isFalse);
    });
  });
}

