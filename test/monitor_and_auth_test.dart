import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthSession tests', () {
    test('Dummy token is identified and rejected by isValid', () {
      const dummyToken =
          'eyJhbGciOiJSUzI1NiIsInR5cCI6ImF0K2p3dCJ9.eyJuYmYiOjE3ODk4ODI4MDYsImV4cCI6MTc4OTkyNjAwNiwiaXNzIjoiaHR0cDovL3RyYWluLWlhbS5zaG9ob3ouY29tIn0.VQjKASL57tJCcHIIwY8BPk5du-ltBjvdHg7TgA6i7GeWw4pWJN8ecmEkvIe1XgCYXYJE1w-Japj9IX8PxKa243_rlFD5E6mP4IL_ad9TcQQcovBSRB6dCU93_JBiGNNa0zOulKAfGGiHZI5iOPN2bQ5wi6WfJ978wBV9gWrsN23jtDUMqvNz4jBs2oqnVuP3eAnxg_lMdx9tGQXc4vfXUhkAUCdGjLCWZkp5HkbCLyo0t7Cd4sl2OOTxe0H-8DYDYEM0u26wKoaEBqC7HvVBtHC2XxYLkdPxGyjfxxGX1Z3wfY6Por_wNqonrh3ybszy85gPxD-y8xXO8wT08S5hZg';

      expect(AuthSession.isDummyToken(dummyToken), true);

      final session = AuthSession(
        token: dummyToken,
        deviceId: 'dev123',
        deviceKey: 'key123',
      );

      expect(session.isValid, false);
    });

    test('AuthSession.load() automatically clears dummy token', () async {
      const dummyToken =
          'eyJhbGciOiJSUzI1NiIsInR5cCI6ImF0K2p3dCJ9.eyJuYmYiOjE3ODk4ODI4MDYsImV4cCI6MTc4OTkyNjAwNiwiaXNzIjoiaHR0cDovL3RyYWluLWlhbS5zaG9ob3ouY29tIn0.VQjKASL57tJCcHIIwY8BPk5du-ltBjvdHg7TgA6i7GeWw4pWJN8ecmEkvIe1XgCYXYJE1w-Japj9IX8PxKa243_rlFD5E6mP4IL_ad9TcQQcovBSRB6dCU93_JBiGNNa0zOulKAfGGiHZI5iOPN2bQ5wi6WfJ978wBV9gWrsN23jtDUMqvNz4jBs2oqnVuP3eAnxg_lMdx9tGQXc4vfXUhkAUCdGjLCWZkp5HkbCLyo0t7Cd4sl2OOTxe0H-8DYDYEM0u26wKoaEBqC7HvVBtHC2XxYLkdPxGyjfxxGX1Z3wfY6Por_wNqonrh3ybszy85gPxD-y8xXO8wT08S5hZg';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'br_auth_session',
        '{"token":"$dummyToken","deviceId":"d","deviceKey":"k","isLoggedIn":true}',
      );

      final loaded = await AuthSession.load();
      expect(loaded, isNull);

      final cleared = prefs.getString('br_auth_session');
      expect(cleared, isNull);
    });
  });

  group('Ticket search dashboard', () {
    testWidgets(
      'Dashboard shows journey UI without logs or polling controls',
      (WidgetTester tester) async {
        final proService = ProService();
        final themeService = ThemeService();
        final monitorService = MonitorService(proService: proService);
        final creditService = CreditService();

        // Verify default interval is 120s
        expect(monitorService.intervalSeconds, 120);

        final languageService = LanguageService();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: proService),
              ChangeNotifierProvider.value(value: themeService),
              ChangeNotifierProvider.value(value: languageService),
              ChangeNotifierProvider.value(value: creditService),
              ChangeNotifierProvider.value(value: monitorService),
            ],
            child: const MaterialApp(home: MonitorDashboardScreen()),
          ),
        );

        // Verify the dashboard rendered successfully with header
        expect(find.text('Rail Ticket'), findsOneWidget);
        // Verify Live Stats Strip is NOT shown
        expect(find.text('Total Checks'), findsNothing);
        expect(find.text('মোট চেক'), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(find.textContaining('120s'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        monitorService.dispose();
      },
    );
  });
}
