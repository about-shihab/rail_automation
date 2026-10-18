import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/session_recovery.dart';
import 'package:rail_automation/widgets/session_recovery_host.dart';

import 'support/fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS session recovery keeps WebKit identity and captures the new session',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await AuthSession.saveUserCredentials('01700000000', 'test-password');
      final webview = FakeWebViewPlatform();
      WebViewPlatform.instance = webview;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          builder: (_, child) => SessionRecoveryHost(child: child!),
          home: const Scaffold(body: Text('Search')),
        ),
      );
      final recovery = SessionRecovery.instance.recover(
        rejectedToken: 'expired',
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(webview.controller.loads, 1);
      expect(webview.controller.userAgentOverridesAtLoad.single, isEmpty);
      final decision = await webview.controller.delegate!.navigationRequest!(
        NavigationRequest(
          url: 'https://challenges.cloudflare.com/widget',
          isMainFrame: false,
        ),
      );
      expect(decision, NavigationDecision.navigate);
      webview.controller.send(
        jsonEncode({
          'type': 'AUTH_SUCCESS',
          'token': 'fresh-session',
          'deviceId': 'device',
          'deviceKey': 'key',
          'user': {},
        }),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect((await recovery).token, 'fresh-session');
      expect(webview.controller.userAgentOverrides, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
