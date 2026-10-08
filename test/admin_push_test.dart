import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/admin_push_service.dart';
import 'package:rail_automation/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'initialize' ? true : null;
        });
    await NotificationService().initialize(background: true);
    await NotificationService().clearSeenIds();
    calls.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  RemoteMessage announcement(String id) => RemoteMessage(
    data: {'kind': 'admin_announcement', 'notification_id': id},
    notification: const RemoteNotification(
      title: 'Notice',
      body: 'Admin message',
    ),
  );

  test(
    'foreground push displays one system alert with announcement tap route',
    () async {
      final message = announcement('foreground');
      await AdminPushService.deliver(message);
      await AdminPushService.deliver(message);
      final shows = calls.where((call) => call.method == 'show').toList();
      expect(shows, hasLength(1));
      final args = shows.single.arguments as Map;
      expect(args['title'], 'Notice');
      expect(args['payload'], 'rail://announcement/foreground');
      expect(
        (args['platformSpecifics'] as Map)['channelId'],
        'br_broadcast_alerts',
      );
    },
  );

  test('OS-displayed background push is acknowledged without a duplicate local alert', () async {
    final message = announcement('closed');
    await AdminPushService.deliver(message, alreadyDisplayed: true);
    await AdminPushService.deliver(message);
    expect(calls.where((call) => call.method == 'show'), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('seen_firebase_notifications'),
      contains('closed'),
    );
  });

  test(
    'push handler ignores seat/booking messages and invalid announcement IDs',
    () async {
      final seat = const RemoteMessage(
        data: {'kind': 'seat_found', 'notification_id': 'seat'},
      );
      await AdminPushService.deliver(seat);
      await AdminPushService.deliver(
        const RemoteMessage(
          data: {'kind': 'admin_announcement', 'notification_id': 'bad/id'},
        ),
      );
      expect(calls.where((call) => call.method == 'show'), isEmpty);
      expect(AdminPushService.tapPayload(seat), isNull);
      expect(
        AdminPushService.tapPayload(announcement('valid')),
        'rail://announcement/valid',
      );
    },
  );

  test('phone normalization and stable IDs work across a restart', () {
    expect(AdminPushService.normalizePhone('+8801813570430'), '01813570430');
    expect(AdminPushService.normalizePhone('570430'), '');
    final id = NotificationService.announcementNotificationId('document1');
    expect(id, NotificationService.announcementNotificationId('document1'));
    expect(id, greaterThan(100000));
    expect(
      id,
      isNot(NotificationService.announcementNotificationId('document2')),
    );
  });
}
