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
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/services/notification_service.dart';
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
        child: MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          home: const WebviewLoginScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('iOS login keeps the native WebKit user agent', (tester) async {
    await showLogin(tester);
    expect(webview.controller.loads, 1);
    expect(webview.controller.userAgentOverridesAtLoad.single, isEmpty);
    webview.controller.delegate!.pageFinished!(
      'https://eticket.railway.gov.bd/login',
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(webview.controller.userAgentOverrides, isEmpty);
    expect(webview.cookieClears, 0);
    expect(webview.storageClears, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('Android login configures its user agent before loading', (
    tester,
  ) async {
    await showLogin(tester);
    final overrides = webview.controller.userAgentOverridesAtLoad.single;
    expect(overrides, hasLength(1));
    expect(overrides.single, contains('Android 14'));
    expect(overrides.single, contains('Chrome/130.0.0.0'));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

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
    await SecureStore.write(
      'rail_login_attempt_at',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
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
    expect(await SecureStore.read('rail_login_attempt_at'), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'manual relogin clears stale session but keeps saved credentials',
    (tester) async {
      await AuthSession.save(
        AuthSession(token: 'stale-token', deviceId: 'device', deviceKey: 'key'),
      );
      await AuthSession.saveUserCredentials('01700000000', 'test-password');
      await SecureStore.write('rail_action_token', 'stale-action');
      await showLogin(tester);
      NotificationService().openBooking('rail://login');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(await AuthSession.load(), isNull);
      expect(await SecureStore.read('rail_action_token'), isNull);
      expect(
        (await AuthSession.getSavedUserCredentials())['phone'],
        '01700000000',
      );
      expect(
        (await AuthSession.getSavedUserCredentials())['password'],
        'test-password',
      );
      expect(webview.cookieClears, 1);
      expect(webview.cacheClears, 1);
      expect(webview.storageClears, 1);
      expect(webview.controller.url, 'https://eticket.railway.gov.bd/login');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('login allows Cloudflare verification frames on iOS', (
    tester,
  ) async {
    await showLogin(tester);
    final navigate = webview.controller.delegate!.navigationRequest!;
    for (final url in [
      'https://challenges.cloudflare.com/turnstile/v0/widget',
      'about:blank',
      'about:srcdoc',
    ]) {
      expect(
        await navigate(NavigationRequest(url: url, isMainFrame: false)),
        NavigationDecision.navigate,
        reason: 'Verification iframe must load: $url',
      );
      expect(
        await navigate(NavigationRequest(url: url, isMainFrame: true)),
        NavigationDecision.prevent,
        reason: 'Verification must not replace the login page: $url',
      );
    }
    for (final isMainFrame in [true, false]) {
      expect(
        await navigate(
          NavigationRequest(
            url: 'https://eticket.railway.gov.bd/login',
            isMainFrame: isMainFrame,
          ),
        ),
        NavigationDecision.navigate,
      );
      for (final url in [
        'https://untrusted.example/login',
        'https://challenges.cloudflare.com.evil.test/widget',
        'http://challenges.cloudflare.com/widget',
        'https://challenges.cloudflare.com:444/widget',
        'javascript:alert(1)',
      ]) {
        expect(
          await navigate(NavigationRequest(url: url, isMainFrame: isMainFrame)),
          NavigationDecision.prevent,
          reason: 'Untrusted navigation must stay blocked: $url',
        );
      }
    }
    expect(webview.controller.url, 'https://eticket.railway.gov.bd/login');
    expect(await AuthSession.load(), isNull);
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
