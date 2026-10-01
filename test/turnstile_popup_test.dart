import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/widgets/turnstile_sheet.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final validExp = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': validExp})));
    final testJwt = 'header.$payload.signature';
    final auth = AuthSession(
      token: testJwt,
      deviceKey: 'test_device_key',
      phoneNumber: '01712345678',
      isLoggedIn: true,
    );
    await AuthSession.save(auth);
  });

  group('Turnstile Verification Popup Tests', () {
    testWidgets('TurnstileDialog pops up directly over the app when show() is called',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.byType(TurnstileDialog), findsNothing);

      // Tap to trigger popup
      await tester.tap(find.text('Launch Verification'));
      await tester.pump();

      // Dialog must be visible on screen over the app
      expect(TurnstileDialog.isShowing, isTrue);
      expect(find.byType(TurnstileDialog), findsOneWidget);
      expect(find.text('Processing Ticket • Boarding'), findsOneWidget);
      expect(find.text('BOARDING PASS'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap close button in header to dismiss
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TurnstileDialog), findsNothing);
      expect(TurnstileDialog.isShowing, isFalse);
    });

    testWidgets('TurnstileSheet.show forwards to TurnstileDialog over the app',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
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

      expect(TurnstileSheet.isShowing, isTrue);
      expect(find.byType(TurnstileDialog), findsOneWidget);

      // Tap close button in header
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TurnstileDialog), findsNothing);
      expect(TurnstileSheet.isShowing, isFalse);
    });

    test('MonitorService needsTurnstile flags 422 and onTurnstileSolved clears it', () {
      final monitor = MonitorService(proService: ProService());

      expect(monitor.needsTurnstile, isFalse);

      // Set booking error containing 422 Turnstile requirement
      monitor.setErrorForTesting(
        bookingError: 'Seat layout rejected (422): Cloudflare Turnstile verification required',
      );
      expect(monitor.needsTurnstile, isTrue);

      // Solving turnstile provides token and clears error
      monitor.onTurnstileSolved('mock_cft_token_123');
      expect(monitor.needsTurnstile, isFalse);
      expect(monitor.lastBookingError, isNull);
    });

    testWidgets('AppShell displays top security verification alert bar when needsTurnstile is true',
        (WidgetTester tester) async {
      final monitor = MonitorService(proService: ProService());
      CreditService().setCreditsForTesting(5);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MonitorService>.value(value: monitor),
            ChangeNotifierProvider<CreditService>.value(value: CreditService()),
            ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
            ChangeNotifierProvider<LanguageService>.value(value: LanguageService()),
            ChangeNotifierProvider<FirebaseUserService>.value(value: FirebaseUserService()),
          ],
          child: MaterialApp(
            theme: AppThemes.lightTheme,
            home: const AppShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // No alert bar initially
      expect(find.text('Human verification required • Tap to continue booking'), findsNothing);

      // Trigger Turnstile requirement
      monitor.setErrorForTesting(
        bookingError: '422 Turnstile verification required',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Alert bar is now visible over the app
      expect(find.text('Human verification required • Tap to continue booking'), findsOneWidget);

      // Tap alert bar to trigger the Turnstile dialog popup
      await tester.tap(find.text('Human verification required • Tap to continue booking'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TurnstileDialog), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      // Solve turnstile
      monitor.onTurnstileSolved('token_abc');
      await tester.pump(const Duration(milliseconds: 300));

      // Alert bar disappears
      expect(find.text('Human verification required • Tap to continue booking'), findsNothing);
    });
  });
}
