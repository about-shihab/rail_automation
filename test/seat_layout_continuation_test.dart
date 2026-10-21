import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/seat_layout_continuation.dart';
import 'package:rail_automation/services/turnstile_gate.dart';
import 'package:rail_automation/views/seat_booking_screen.dart';
import 'package:rail_automation/widgets/turnstile_host.dart';

import 'support/fake_inapp_webview.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final auth = AuthSession(
    token: 'test-session',
    deviceId: 'device',
    deviceKey: 'key',
  );
  final train = ApiService.getMockResponse().trains[1];
  final seat = train.seatTypes.first;
  SeatLayoutContinuation request({
    String id = 'second-leg',
    DateTime? created,
  }) => SeatLayoutContinuation(
    id: id,
    train: train,
    seat: seat,
    from: 'Via',
    to: 'To',
    date: '22-Oct-2026',
    account: SeatLayoutContinuation.accountFor(auth),
    createdAt: created ?? DateTime.now(),
  );
  setUp(() async {
    IOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    await AppConfig.instance.reloadCache();
    await LanguageService.instance.setLanguage(AppLanguage.en);
    await AuthSession.save(auth);
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'checkPermissions') return {'isEnabled': true};
      return null;
    });
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TurnstileGate.instance.workerAcquire = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'saved context keeps the second leg and excludes tokens and credentials',
    () async {
      await request().save();
      final loaded = (await SeatLayoutContinuation.load())!;
      expect(loaded.from, 'Via');
      expect(loaded.date, '22-Oct-2026');
      expect(loaded.seat.tripRouteId, seat.tripRouteId);
      final raw = (await SharedPreferences.getInstance()).getString(
        SeatLayoutContinuation.storageKey,
      )!;
      expect(raw, isNot(contains('test-session')));
      expect(raw, isNot(contains('cft_response')));
      expect(raw, isNot(contains('password')));
      expect(await SeatLayoutContinuation.clear('different-request'), isFalse);
      expect(await SeatLayoutContinuation.load(), isNotNull);
      expect(await SeatLayoutContinuation.clear('second-leg'), isTrue);
    },
  );

  test('old continuations expire instead of loading stale trip IDs', () async {
    await request(created: DateTime.now().subtract(const Duration(minutes: 31)))
        .save();
    expect(await SeatLayoutContinuation.load(), isNull);
  });

  test('notification carries the selected leg and a native continuation destination', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final saved = request();
    expect(await NotificationService().showSeatLayoutRequired(saved), isTrue);
    final alert = calls.lastWhere((c) => c.method == 'show').arguments as Map;
    expect(alert['id'], NotificationService.idSeatLayout);
    expect(alert['payload'], 'rail://seat-layout?id=second-leg');
    expect(alert['body'], contains('Via → To'));
    expect(alert['body'], contains('22-Oct-2026'));
    expect(alert['platformSpecifics'], containsPair('presentBanner', true));
  });

  Future<void> mount(
    WidgetTester tester, {
    Widget home = const Scaffold(),
  }) async {
    InAppWebViewPlatform.instance = FakeInAppWebViewPlatform();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        builder: (_, child) => TurnstileHost(child: child!),
        home: home,
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'notification restores the native second-leg seat browser after a restart',
    (tester) async {
      await request().save();
      var layouts = 0;
      TurnstileGate.instance.workerAcquire = (_) async => 'resume-fresh-token';
      await http.runWithClient(
        () async {
          await mount(tester);
          NotificationService().openBooking('rail://seat-layout?id=second-leg');
          for (var i = 0; i < 100 && layouts == 0; i++) {
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(layouts, 1);
          final screen = tester.widget<SeatBookingScreen>(
            find.byType(SeatBookingScreen),
          );
          expect(screen.fromCity, 'Via');
          expect(screen.dateOfJourney, '22-Oct-2026');
          expect(screen.seatType.tripRouteId, seat.tripRouteId);
          expect(await SeatLayoutContinuation.load(), isNull);
          expect(
            calls.any(
              (c) =>
                  c.method == 'cancel' &&
                  (c.arguments is int ? c.arguments : c.arguments['id']) ==
                      NotificationService.idSeatLayout,
            ),
            isTrue,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
        () => MockClient((_) async {
          layouts++;
          return http.Response('{"data":{"seatLayout":[]}}', 200);
        }),
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'a paused seat browser notifies once and resumes loading on return',
    (tester) async {
      final response = Completer<http.Response>();
      var layouts = 0;
      var tokens = 0;
      TurnstileGate.instance.workerAcquire = (_) async =>
          'foreground-token-${++tokens}';
      await http.runWithClient(
        () async {
          await mount(
            tester,
            home: SeatBookingScreen(
              train: train,
              seatType: seat,
              fromCity: 'Via',
              toCity: 'To',
              dateOfJourney: '22-Oct-2026',
              authSession: auth,
            ),
          );
          for (var i = 0; i < 100 && layouts == 0; i++) {
            await tester.pump();
          }
          expect(layouts, 1);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();
          response.complete(
            http.Response('{"message":"Invalid cft_response"}', 422),
          );
          for (var i = 0; i < 30; i++) {
            await tester.pump();
          }
          expect(layouts, 1);
          final saved = await SeatLayoutContinuation.load();
          expect(saved?.from, 'Via');
          expect(
            calls.where(
              (c) =>
                  c.method == 'show' &&
                  (c.arguments is int ? c.arguments : c.arguments['id']) ==
                      NotificationService.idSeatLayout,
            ),
            hasLength(1),
          );
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          for (var i = 0; i < 100 && layouts < 2; i++) {
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(layouts, 2);
          expect(await SeatLayoutContinuation.load(), isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
        () => MockClient((_) async {
          layouts++;
          return layouts == 1
              ? response.future
              : http.Response('{"data":{"seatLayout":[]}}', 200);
        }),
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'a different signed-in account cannot resume the saved booking leg',
    (tester) async {
      await request().save();
      await AuthSession.save(
        AuthSession(
          token: 'other-account',
          deviceId: 'other-device',
          deviceKey: 'key',
        ),
      );
      await mount(tester);
      NotificationService().openBooking('rail://seat-layout?id=second-leg');
      await tester.pumpAndSettle();
      expect(find.byType(SeatBookingScreen), findsNothing);
      expect(await SeatLayoutContinuation.load(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
