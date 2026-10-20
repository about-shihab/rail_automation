import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/rail_api_client.dart';
import 'package:rail_automation/services/secure_store.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const keychain = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final secureValues = <String, String>{};
  final calls = <MethodCall>[];
  var locked = false;
  var permission = true;
  var rejectShow = false;
  late FlutterSecureStoragePlatform originalStorage;
  final session = AuthSession(
    token: 'valid-session',
    deviceId: 'device',
    deviceKey: 'key',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AuthSession.iosBackgroundExecution = false;
    originalStorage = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = MethodChannelFlutterSecureStorage();
    IOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    secureValues.clear();
    calls.clear();
    locked = false;
    permission = true;
    rejectShow = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(keychain, (
      call,
    ) async {
      final options = Map<String, dynamic>.from(call.arguments['options']);
      final slot = '${options['accountName']}:${call.arguments['key']}';
      if (locked &&
          options['accessibility'] == 'unlocked' &&
          secureValues.containsKey(slot)) {
        throw PlatformException(code: 'errSecInteractionNotAllowed');
      }
      switch (call.method) {
        case 'read':
          return secureValues[slot];
        case 'write':
          if (options['accountName'] == 'rail_pro_background_session') {
            expect(options['accessibility'], 'first_unlock_this_device');
          }
          secureValues[slot] = call.arguments['value'];
          return null;
        case 'delete':
          secureValues.remove(slot);
          return null;
        default:
          fail('Unexpected Keychain operation: ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(notifications, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'checkPermissions') return {'isEnabled': permission};
      if (call.method == 'show' && rejectShow) {
        throw PlatformException(code: 'delivery_failed');
      }
      return null;
    });
  });
  tearDown(() {
    AuthSession.iosBackgroundExecution = false;
    debugDefaultTargetPlatformOverride = null;
    FlutterSecureStoragePlatform.instance = originalStorage;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(keychain, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      notifications,
      null,
    );
  });

  test('iOS worker initializes notifications without prompting and posts seat banners', () async {
    await NotificationService().triggerSeatAvailableAlert(
      trainName: 'SONAR BANGLA',
      seatType: 'SNIGDHA',
      seatCount: 2,
      travelDate: '20-Oct-2026',
    );
    final initialization =
        calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
    expect(initialization['requestAlertPermission'], isFalse);
    expect(initialization['requestSoundPermission'], isFalse);
    final alert = calls.lastWhere((c) => c.method == 'show').arguments as Map;
    expect(alert['id'], NotificationService.idSeatFound);
    expect(alert['platformSpecifics'], containsPair('presentBanner', true));
    expect(alert['platformSpecifics'], containsPair('presentList', true));
    expect(alert['platformSpecifics'], containsPair('presentSound', true));
    permission = false;
    await expectLater(
      NotificationService().triggerSeatAvailableAlert(
        trainName: 'SONAR BANGLA',
        seatType: '',
        seatCount: 2,
        travelDate: '',
      ),
      throwsStateError,
    );
  });

  test('iOS search status is separate, quiet and removable', () async {
    await NotificationService().showIosSearchStatus(
      from: 'Dhaka',
      to: 'Chattogram',
      date: '20-Oct-2026',
    );
    final status = calls.lastWhere((c) => c.method == 'show').arguments as Map;
    expect(status['id'], NotificationService.idIosSearchStatus);
    expect(status['title'], 'Train search enabled');
    expect(status['body'], contains('when iOS allows'));
    expect(status['payload'], 'rail://search-status');
    expect(status['platformSpecifics'], containsPair('presentSound', false));
    await NotificationService().cancelIosSearchStatus();
    expect(calls.last.method, 'cancel');
    expect(calls.last.arguments, NotificationService.idIosSearchStatus);
  });

  test('existing iOS login migrates securely for locked-screen work without copying passwords', () async {
    await SecureStore.write('br_auth_session', jsonEncode(session.toJson()));
    await AuthSession.saveUserCredentials('01700000000', 'private-password');
    await AuthSession.prepareIosBackgroundAccess();
    locked = true;
    AuthSession.iosBackgroundExecution = true;
    expect((await AuthSession.load())!.token, session.token);
    expect((await RailApiClient.current(session)).token, session.token);
    expect(
      secureValues.entries
          .where((e) => e.key.startsWith('rail_pro_background_session:'))
          .single
          .value,
      isNot(contains('private-password')),
    );
    await expectLater(
      AuthSession.getSavedUserCredentials(),
      throwsA(isA<PlatformException>()),
    );
    locked = false;
    AuthSession.iosBackgroundExecution = false;
    await AuthSession.clear();
    expect(await AuthSession.load(background: true), isNull);
  });

  test('locked iOS search alerts on seats and retries a failed notification on the next refresh', () async {
    await AuthSession.save(session);
    await SecureStore.write('rail_action_token', 'locked-action-token');
    await SecureStore.write('rail_pending_reservation_v1', '{"status":"readyForPayment"}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      MonitorService.preferenceKey,
      jsonEncode({
        'id': 'ios-search',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': DateFormat('dd-MMM-yyyy')
            .format(DateTime.now().add(const Duration(days: 1))),
        'active': true,
        'expires': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
      }),
    );
    final pro = ProService();
    final monitor = MonitorService(proService: pro, backgroundWorker: true);
    addTearDown(monitor.dispose);
    addTearDown(pro.dispose);
    AuthSession.iosBackgroundExecution = true;
    locked = true;
    await monitor.restore(startTimers: false);
    rejectShow = true;
    await http.runWithClient(
      () async {
        await monitor.checkNow();
        final availability = jsonDecode(
          prefs.getString('ticket_availability_ios-search')!,
        ) as Map;
        expect(availability.values.every((v) => v == 0), isTrue);
        final failed = calls.where((c) => c.method == 'show').length;
        expect(failed, greaterThan(0));
        rejectShow = false;
        await monitor.checkNow();
        expect(
          calls.where((c) => c.method == 'show').length,
          greaterThan(failed),
        );
        final delivered = jsonDecode(
          prefs.getString('ticket_availability_ios-search')!,
        ) as Map;
        expect(delivered.values.any((v) => v > 0), isTrue);
      },
      () => MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer valid-session');
        expect(request.url.path, endsWith('/search-trips-v2'));
        expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-action-token')));
        return http.Response(
          jsonEncode({
            'data': {
              'trains': ApiService.getMockResponse().trains
                  .map(
                    (t) => {
                      ...t.toJson(),
                      'departure_date_time_jd': DateTime.now()
                          .add(const Duration(days: 1))
                          .toUtc()
                          .toIso8601String(),
                    },
                  )
                  .toList(),
            },
          }),
          200,
        );
      }),
    );
  });

  test('iOS status methods do nothing on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await NotificationService().showIosSearchStatus(
      from: 'Dhaka',
      to: 'Chattogram',
      date: '20-Oct-2026',
    );
    await NotificationService().cancelIosSearchStatus();
    await AuthSession.prepareIosBackgroundAccess();
    expect(calls, isEmpty);
    expect(secureValues, isEmpty);
  });
}
