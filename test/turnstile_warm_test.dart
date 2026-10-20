import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/turnstile_gate.dart';
import 'package:rail_automation/services/turnstile_session.dart';
import 'package:rail_automation/widgets/turnstile_host.dart';

import 'support/fake_inapp_webview.dart';

import 'package:rail_automation/widgets/ticket_processing_overlay.dart';

void main() {
  late FakeInAppWebViewPlatform platform;
  setUp(() {
    platform = FakeInAppWebViewPlatform();
    InAppWebViewPlatform.instance = platform;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        builder: (context, child) => TurnstileHost(child: child!),
        home: const Scaffold(),
      ),
    );
    await tester.pump();
  }

  testWidgets('Cold notification refresh waits for browser attachment', (
    tester,
  ) async {
    final session = TurnstileSession();
    final result = session.generateWhenAttached();
    expect(session.generating, isFalse);
    var executions = 0;
    session.attach((source) async {
      if (source.contains('window.__railBegin(')) {
        executions++;
      } else {
        session.receive({'status': 'READY'});
      }
    });
    await tester.pump();
    expect(executions, 1);
    session.receive({
      'status': 'SUCCESS',
      'requestId': 1,
      'token': 'cold-token',
    });
    expect(await result, 'cold-token');
    session.detach();
    await tester.pump();
  });

  testWidgets('Cancelling before attachment never starts a later check', (
    tester,
  ) async {
    final session = TurnstileSession();
    final result = session.generateWhenAttached();
    session.cancel();
    var executions = 0;
    session.attach((_) async => executions++);
    await tester.pump();
    expect(await result, isNull);
    expect(executions, 0);
    session.detach();
    await tester.pump();
  });

  testWidgets('Idle browser is preloaded once without generating tokens', (
    tester,
  ) async {
    await mount(tester);
    await tester.pump(const Duration(minutes: 6));
    expect(platform.creations, 1);
    expect(platform.controller.executions, 0);
    expect(TurnstileSession.instance.phase, TurnstilePhase.idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Consecutive bookings use new tokens in the same warm browser', (
    tester,
  ) async {
    await mount(tester);
    final tokens = <String?>[];
    Future<void> book() => TurnstileGate.instance.guardSeatLayout<void>(
      run: (token) async => tokens.add(token),
    );
    final first = book();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(platform.controller.executions, 1);
    expect(find.text('Checking access'), findsNothing);
    expect(find.byType(TicketProcessingOverlay), findsNothing);
    platform.controller.send('{"status":"SUCCESS","token":"first-token"}');
    await tester.pump();
    await first;
    expect(tokens, ['first-token']);

    // Start before the previous overlay's reverse transition disposes it.
    final second = book();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(TurnstileSession.instance.generating, isTrue);
    platform.controller.send('{"status":"SUCCESS","token":"second-token"}');
    await tester.pump();
    await second;
    expect(tokens, ['first-token', 'second-token']);
    expect(platform.controller.executions, 2);
    expect(platform.creations, 1);
    expect(await TurnstileGate.instance.cachedToken(), isNull);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Returning to an interactive check reuses its pending execution',
    (tester) async {
      await mount(tester);
      final silent = TurnstileSession.instance.generate();
      await tester.pump();
      platform.controller.send('{"status":"INTERACTIVE"}');
      final visible = TurnstileGate.instance.acquire(forceFresh: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Verify to continue'), findsOneWidget);
      expect(platform.controller.executions, 1);
      expect(platform.creations, 1);
      platform.controller.send('{"status":"SUCCESS","token":"one-token"}');
      await tester.pump();
      expect(await silent, 'one-token');
      expect(await visible, 'one-token');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'A silent result arriving during promotion does not execute again',
    (tester) async {
      await mount(tester);
      final silent = TurnstileSession.instance.generate();
      await tester.pump();
      final visible = TurnstileGate.instance.acquire(forceFresh: true);
      platform.controller.send('{"status":"SUCCESS","token":"just-in-time"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(await silent, 'just-in-time');
      expect(await visible, 'just-in-time');
      expect(platform.controller.executions, 1);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Cancelled callbacks cannot satisfy the next booking', (
    tester,
  ) async {
    await mount(tester);
    final session = TurnstileSession.instance;
    final first = session.generate();
    await tester.pump();
    final oldId = platform.controller.requestId;
    session.cancel();
    expect(await first, isNull);
    final second = session.generate();
    await tester.pump();
    platform.controller.send(
      '{"status":"SUCCESS","requestId":$oldId,"token":"late-token"}',
    );
    expect(session.generating, isTrue);
    platform.controller.send('{"status":"SUCCESS","token":"new-token"}');
    expect(await second, 'new-token');
    expect(platform.creations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'iOS keeps silent execution hidden and only reveals a genuine challenge',
    (tester) async {
      platform.origin = '';
      platform.loadUrl = 'about:blank';
      await mount(tester);
      final tokens = <String?>[];
      final layout = TurnstileGate.instance.guardSeatLayout<void>(
        run: (token) async => tokens.add(token),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(platform.controller.executions, 1);
      expect(find.text('Human verification').hitTestable(), findsNothing);
      expect(find.text('Checking access'), findsNothing);
      platform.controller.send('{"status":"INTERACTIVE"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Human verification').hitTestable(), findsOneWidget);
      platform.controller.send(
        '{"status":"SUCCESS","bridgeId":"untrusted","token":"wrong"}',
      );
      platform.controller.send(
        '{"status":"SUCCESS","token":"iframe-token"}',
        isMainFrame: false,
      );
      expect(TurnstileSession.instance.generating, isTrue);
      expect(tokens, isEmpty);
      platform.controller.send('{"status":"SUCCESS","token":"ios-cft"}');
      await tester.pump();
      await layout;
      expect(tokens, ['ios-cft']);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('cold iOS requests wait for document load before executing JS', (
    tester,
  ) async {
    platform.autoFinishLoad = false;
    await mount(tester);
    final result = TurnstileGate.instance.acquire(forceFresh: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(TurnstileSession.instance.attached, isFalse);
    expect(platform.controller.scripts, isEmpty);
    platform.parameters.onLoadStart?.call(
      platform.parameters.controllerFromPlatform!(platform.controller),
      WebUri('https://eticket.railway.gov.bd/'),
    );
    platform.finishLoad();
    await tester.pump();
    expect(platform.controller.executions, 1);
    platform.controller.send('{"status":"SUCCESS","token":"after-load"}');
    await tester.pump();
    expect(await result, 'after-load');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets(
    'an error before the overlay loads offers retry instead of spinning',
    (tester) async {
      await mount(tester);
      TurnstileSession.instance.fail(
        'Security check unavailable. Please retry.',
      );
      final result = NotificationService.navigatorKey.currentState!
          .push<String>(
            MaterialPageRoute(
              builder: (_) => TicketProcessingOverlay(
                tokenRequest: Future<String?>.value(null),
              ),
            ),
          );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('Security check unavailable. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Checking access'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'Android retains early attachment, original script and origin checks',
    (tester) async {
      platform.autoFinishLoad = false;
      await mount(tester);
      expect(TurnstileSession.instance.attached, isTrue);
      platform.finishLoad();
      await tester.pump();
      final preload = platform.controller.scripts.single;
      expect(preload, TurnstileSession.bootstrap);
      expect(preload, isNot(contains('bridgeId')));
      final result = TurnstileGate.instance.acquire(forceFresh: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Human verification').hitTestable(), findsNothing);
      platform.controller.origin = '';
      platform.controller.send('{"status":"SUCCESS","token":"wrong-origin"}');
      expect(TurnstileSession.instance.generating, isTrue);
      platform.controller.origin = 'https://eticket.railway.gov.bd/';
      platform.controller.send('{"status":"SUCCESS","token":"android-cft"}');
      await tester.pump();
      expect(await result, 'android-cft');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );
}
