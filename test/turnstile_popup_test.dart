import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/widgets/turnstile_sheet.dart';
import 'package:rail_automation/widgets/ticket_processing_overlay.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/turnstile_gate.dart';
import 'package:rail_automation/services/turnstile_session.dart';
import 'package:rail_automation/services/seat_layout_challenge.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:rail_automation/widgets/turnstile_host.dart';

import 'support/fake_inapp_webview.dart';

import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/utils/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeInAppWebViewPlatform webview;
  setUp(() async {
    webview = FakeInAppWebViewPlatform();
    InAppWebViewPlatform.instance = webview;
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    final validExp =
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'exp': validExp})),
    );
    final testJwt = 'header.$payload.signature';
    final auth = AuthSession(
      token: testJwt,
      deviceKey: 'test_device_key',
      phoneNumber: '01712345678',
      isLoggedIn: true,
    );
    await AuthSession.save(auth);
  });

  testWidgets(
    'Notification tap starts silently and only prompts for interaction',
    (tester) async {
      final monitor = MonitorService(proService: ProService());
      addTearDown(monitor.dispose);
      monitor.setErrorForTesting(
        bookingError: '422 Turnstile verification required',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<MonitorService>.value(
          value: monitor,
          child: MaterialApp(
            navigatorKey: NotificationService.navigatorKey,
            builder: (context, child) => TurnstileHost(child: child!),
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pump();
      NotificationService().openBooking('rail://turnstile');
      expect(TurnstileSession.instance.generating, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Checking access'), findsNothing);
      expect(find.byType(TicketProcessingOverlay), findsNothing);
      expect(webview.creations, 1);
      expect(webview.controller.executions, 1);
      // Repeated delivery joins the ongoing check rather than executing again.
      NotificationService().openBooking('rail://turnstile');
      await tester.pump();
      expect(webview.controller.executions, 1);
      webview.controller.send('{"status":"INTERACTIVE"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('Search, OTP and ordinary 422 errors never request a human check', () {
    final monitor = MonitorService(proService: ProService());
    addTearDown(monitor.dispose);
    monitor.setErrorForTesting(error: 'Turnstile verification required');
    expect(monitor.needsTurnstile, isFalse);
    for (final message in [
      'OTP verification not completed',
      'Invalid passenger (422)',
    ]) {
      monitor.setErrorForTesting(bookingError: message);
      expect(monitor.needsTurnstile, isFalse);
      expect(TurnstileGate.isChallengeError(StateError(message)), isFalse);
    }
  });

  testWidgets(
    'pending worker challenge opens on return without a notification tap',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        MonitorService.preferenceKey,
        jsonEncode({
          'id': 'pending-check',
          'from': 'Dhaka',
          'to': 'Chattogram',
          'date': '08-Oct-2026',
          'active': false,
        }),
      );
      await prefs.setString('ticket_verification_pending-check', 'pending');
      final monitor = MonitorService(proService: ProService());
      addTearDown(monitor.dispose);
      await monitor.restore(startTimers: false);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TurnstileHost(child: child!),
          navigatorKey: NotificationService.navigatorKey,
          home: const Scaffold(),
        ),
      );
      monitor.resumePendingTurnstile();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      webview.controller.send('{"status":"INTERACTIVE"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(TicketProcessingOverlay), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      monitor.resumePendingTurnstile();
      await tester.pump();
      expect(
        find.byType(TicketProcessingOverlay),
        findsNothing,
        reason: 'Cancelling requires an explicit retry, not repeated popups',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Concurrent callers share one overlay; cancellation does not reopen it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TurnstileHost(child: child!),
          navigatorKey: NotificationService.navigatorKey,
          home: const Scaffold(),
        ),
      );
      final first = TurnstileGate.instance.acquire(forceFresh: true);
      final second = TurnstileGate.instance.acquire(forceFresh: true);
      expect(identical(first, second), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      webview.controller.send('{"status":"INTERACTIVE"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(TicketProcessingOverlay), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(await first, isNull);
      expect(await second, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(TicketProcessingOverlay), findsNothing);
    },
  );

  testWidgets(
    'Rejected tokens get one automatic refresh without repeated prompts',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TurnstileHost(child: child!),
          navigatorKey: NotificationService.navigatorKey,
          home: const Scaffold(),
        ),
      );
      var reads = 0;
      final future = TurnstileGate.instance.guardSeatLayout<void>(
        run: (_) async {
          reads++;
          throw const SeatLayoutChallenge(tokenRejected: true);
        },
      );
      final assertion = expectLater(
        future,
        throwsA(isA<SeatLayoutChallenge>()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(reads, 0);
      webview.controller.send('{"status":"SUCCESS","token":"fresh-token"}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(reads, 1);
      expect(webview.controller.executions, 2);
      webview.controller.send('{"status":"SUCCESS","token":"refreshed-token"}');
      await tester.pump();
      await tester.pumpAndSettle();
      await assertion;
      expect(reads, 2);
      expect(find.byType(TicketProcessingOverlay), findsNothing);
      expect(await TurnstileGate.instance.cachedToken(), isNull);
    },
  );

  group('Turnstile Verification Popup Tests', () {
    testWidgets(
      'TurnstileDialog pops up directly over the app when show() is called',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => TurnstileHost(child: child!),
            navigatorKey: NotificationService.navigatorKey,
            theme: AppThemes.lightTheme,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => TurnstileDialog.show(context),
                    child: const Text('Launch Verification'),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(TurnstileDialog.isShowing, isFalse);
        expect(find.byType(TicketProcessingOverlay), findsNothing);

        // Tap to trigger popup
        await tester.tap(find.text('Launch Verification'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // Dialog must be visible on screen over the app
        expect(TurnstileDialog.isShowing, isTrue);
        webview.controller.send('{"status":"INTERACTIVE"}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(TicketProcessingOverlay), findsOneWidget);
        expect(find.text('Verify to continue'), findsOneWidget);
        expect(find.text('TICKET PROCESSING'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);

        // Tap close button in header to dismiss
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(TicketProcessingOverlay), findsNothing);
        expect(TurnstileDialog.isShowing, isFalse);
      },
    );

    testWidgets(
      'TurnstileSheet.show forwards to TurnstileDialog over the app',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => TurnstileHost(child: child!),
            navigatorKey: NotificationService.navigatorKey,
            theme: AppThemes.lightTheme,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => TurnstileSheet.show(context),
                    child: const Text('Trigger TurnstileSheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Trigger TurnstileSheet'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(TurnstileSheet.isShowing, isTrue);
        webview.controller.send('{"status":"INTERACTIVE"}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(TicketProcessingOverlay), findsOneWidget);

        // Tap close button in header
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(find.byType(TicketProcessingOverlay), findsNothing);
        expect(TurnstileSheet.isShowing, isFalse);
      },
    );

    test(
      'Only a booking challenge needs verification; solving clears it',
      () async {
        final monitor = MonitorService(proService: ProService());

        expect(monitor.needsTurnstile, isFalse);

        // Set booking error containing 422 Turnstile requirement
        monitor.setErrorForTesting(
          bookingError: 'Seat layout rejected (422): Cloudflare Turnstile verification required',
        );
        expect(monitor.needsTurnstile, isTrue);

        // Solving turnstile provides token and clears error
        await monitor.onTurnstileSolved('mock_cft_token_123');
        addTearDown(monitor.dispose);
        expect(monitor.needsTurnstile, isFalse);
        expect(monitor.lastBookingError, isNull);
      },
    );

    testWidgets(
      'AppShell displays top security verification alert bar when needsTurnstile is true',
      (WidgetTester tester) async {
        final monitor = MonitorService(proService: ProService());
        addTearDown(monitor.dispose);
        CreditService().setCreditsForTesting(5);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<MonitorService>.value(value: monitor),
              ChangeNotifierProvider<CreditService>.value(
                value: CreditService(),
              ),
              ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
              ChangeNotifierProvider<LanguageService>.value(
                value: LanguageService(),
              ),
              ChangeNotifierProvider<FirebaseUserService>.value(
                value: FirebaseUserService(),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => TurnstileHost(child: child!),
              navigatorKey: NotificationService.navigatorKey,
              theme: AppThemes.lightTheme,
              home: const AppShell(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // No alert bar initially
        expect(find.text('Security check · Continue'), findsNothing);

        // Trigger Turnstile requirement
        monitor.setErrorForTesting(
          bookingError: '422 Turnstile verification required',
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Alert bar is now visible over the app
        expect(find.text('Security check · Continue'), findsOneWidget);

        // Tap alert bar to trigger the Turnstile dialog popup
        await tester.tap(find.text('Security check · Continue'));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        webview.controller.send('{"status":"INTERACTIVE"}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(TicketProcessingOverlay), findsOneWidget);
        // Dismiss dialog
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump(const Duration(milliseconds: 300));

        // Solve turnstile
        await monitor.onTurnstileSolved('token_abc');
        await tester.pump(const Duration(milliseconds: 300));

        // Alert bar disappears
        expect(find.text('Security check · Continue'), findsNothing);
      },
    );
  });
}
