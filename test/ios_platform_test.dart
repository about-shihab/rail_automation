import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/app_update_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/sms_service.dart';
import 'package:rail_automation/services/ticket_download_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const app = MethodChannel('com.example.rail_automation/overlay');
  const sms = MethodChannel('com.example.rail_automation/sms');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [notifications, app, sms]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('iOS reports actual notification authorization and denial', () async {
    var allowed = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(notifications, (
      call,
    ) async {
      if (call.method == 'requestPermissions') {
        expect(call.arguments, containsPair('alert', true));
        expect(call.arguments, containsPair('sound', true));
        expect(call.arguments, containsPair('badge', true));
        return allowed;
      }
      if (call.method == 'checkPermissions') return {'isEnabled': allowed};
      fail('Unexpected notification call: ${call.method}');
    });
    expect(await NotificationService().requestPermissions(), isFalse);
    expect(await NotificationService().areNotificationsEnabled(), isFalse);
    allowed = true;
    expect(await NotificationService().requestPermissions(), isTrue);
    expect(await NotificationService().areNotificationsEnabled(), isTrue);
  });

  test(
    'iOS update download survives cache roundtrip without becoming an APK',
    () {
      final manifest = {
        'version': '1.0.4',
        'build_number': 5,
        'minimum_build_number': 3,
        'apk_url': 'https://rail.example/android.apk?download=1',
        'ipa_url': 'https://rail.example/ios.ipa?download=1',
      };
      final policy = UpdatePolicy.parse(manifest)!;
      final cached = UpdatePolicy.parse(
        jsonDecode(jsonEncode(policy.toJson())),
      )!;
      expect(cached.download.toString(), manifest['ipa_url']);
      manifest.remove('ipa_url');
      expect(
        UpdatePolicy.parse(manifest)!.download.path,
        '/about-shihab/rail-pro/releases/latest',
      );
    },
  );

  test(
    'iOS saves PDF bytes through the native viewer and reports failures',
    () async {
      final bytes = Uint8List.fromList('%PDF-1.4'.codeUnits);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(app, (
        call,
      ) async {
        expect(call.method, 'saveAndOpenPdf');
        expect(call.arguments['bytes'], bytes);
        expect(call.arguments['fileName'], 'ticket.pdf');
        return '/Documents/Tickets/ticket.pdf';
      });
      expect(
        await TicketDownloadService.saveAndOpenTicketPdf(
          bytes: bytes,
          fileName: 'ticket.pdf',
        ),
        '/Documents/Tickets/ticket.pdf',
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(app, (_) async {
        throw PlatformException(code: 'pdf_save_failed');
      });
      expect(
        await TicketDownloadService.saveAndOpenTicketPdf(
          bytes: bytes,
          fileName: 'ticket.pdf',
        ),
        isNull,
      );
    },
  );

  test(
    'iOS OTP falls back immediately without invoking Android SMS consent',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(sms, (_) async {
        fail('iOS must not call the Android SMS plugin');
      });
      expect(SmsService.supported, isFalse);
      expect(await SmsService().prepareListening(), isFalse);
      expect(await SmsService().requestSmsPermission(), isFalse);
      expect(await SmsService().promptPendingConsent(), isFalse);
      var manualFallback = false;
      await SmsService().startListening(
        onUnavailable: () => manualFallback = true,
      );
      expect(manualFallback, isTrue);
    },
  );
}
