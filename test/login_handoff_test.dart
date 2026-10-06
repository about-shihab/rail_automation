import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/views/webview_login_screen.dart';

import 'support/fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWebViewPlatform webview;
  late MonitorService monitor;
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
    monitor = MonitorService(proService: ProService());
  });
  tearDown(() => monitor.dispose());

  Future<void> showLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: LanguageService()),
          ChangeNotifierProvider.value(value: ThemeService()),
          ChangeNotifierProvider.value(value: CreditService()),
          ChangeNotifierProvider.value(value: TripHistoryService()),
          ChangeNotifierProvider.value(value: FirebaseUserService()),
        ],
        child: const MaterialApp(home: WebviewLoginScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('stored session on login immediately opens native Search once', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      MonitorService.preferenceKey,
      jsonEncode({
        'id': 'saved-search',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': '08-Oct-2026',
        'active': false,
      }),
    );
    await monitor.restore(startTimers: false);
    await showLogin(tester);
    final message = jsonEncode({
      'type': 'STORAGE_TOKEN',
      'token': 'fresh-login-token',
      'deviceId': 'device',
      'deviceKey': 'key',
      'user': {},
      'currentPath': '/login',
    });
    webview.controller.send(message);
    // A website redirect and duplicate bridge event must not reset the handoff.
    webview.controller.delegate!.pageStarted!(
      'https://eticket.railway.gov.bd/booking/train/search',
    );
    webview.controller.send(message);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WebviewLoginScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(AppShell.tab.value, AppShell.tabSearch);
    expect((await AuthSession.load())?.token, 'fresh-login-token');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expired or off-origin bridge sessions never complete login', (
    tester,
  ) async {
    await showLogin(tester);
    final expired =
        'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': 1})))}.s';
    webview.controller.send(
      jsonEncode({'type': 'AUTH_SUCCESS', 'token': expired}),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(WebviewLoginScreen), findsOneWidget);
    webview.controller.url = 'https://untrusted.example/login';
    webview.controller.send(
      jsonEncode({'type': 'AUTH_SUCCESS', 'token': 'fresh-login-token'}),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(await AuthSession.load(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
