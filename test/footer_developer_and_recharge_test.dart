import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthSession.save(
      AuthSession(token: 'search-session', deviceKey: 'device'),
    );
  });

  test('mailto uri encodes spaces as %20 instead of +', () {
    String encodeQueryParameters(Map<String, String> params) {
      return params.entries
          .map((MapEntry<String, String> e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
    }

    final uri = Uri(
      scheme: 'mailto',
      path: 'contact@railpro.com',
      query: encodeQueryParameters(<String, String>{
        'subject': 'Rail Pro Credit Recharge Request',
        'body': 'Hello Admin,\n\nI would like to recharge credits for Rail Pro.',
      }),
    );

    final uriString = uri.toString();
    expect(uriString, contains('subject=Rail%20Pro%20Credit%20Recharge%20Request'));
    expect(uriString, isNot(contains('Rail+Pro+Credit+Recharge+Request')));
    expect(uriString, contains('Hello%20Admin'));
    expect(uriString, isNot(contains('Hello+Admin')));
  });

  testWidgets('App footer renders customized developer name from AppConfig',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConfig.cacheKey,
      '{"developer_name": "Custom Engineering Team"}',
    );
    await AppConfig.instance.reloadCache();

    expect(AppConfig.instance.developerName, 'Custom Engineering Team');

    final themeService = ThemeService();
    final languageService = LanguageService();
    final creditService = CreditService();
    final fbUserService = FirebaseUserService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeService),
          ChangeNotifierProvider.value(value: languageService),
          ChangeNotifierProvider.value(value: creditService),
          ChangeNotifierProvider.value(value: fbUserService),
        ],
        child: const MaterialApp(
          home: ProfileTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify footer contains the configured developer name
    expect(
      find.textContaining('Developed by Custom Engineering Team'),
      findsOneWidget,
    );
  });
}
