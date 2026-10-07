import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/views/booking_screen.dart';
import 'package:rail_automation/views/reservation_screen.dart';

import 'support/fake_webview.dart';

void main() {
  testWidgets(
    'verified OTP opens trip-info with matching user and held seats',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
      FlutterSecureStorage.setMockInitialValues({});
      await LanguageService.instance.setLanguage(AppLanguage.en);
      final platform = FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      await AuthSession.save(
        AuthSession(
          token: 'test-session',
          deviceKey: 'key',
          phoneNumber: '01700000000',
        ),
      );
      await SecureStore.write(
        'rail_user',
        jsonEncode({'mobile_number': '01700000000', 'id': 123}),
      );
      final train = ApiService.getMockResponse().trains[1];
      await BookingService.save({
        'id': 'otp-navigation',
        'status': 'awaitingOtp',
        'credit_deducted': true,
        'autoVerify': false,
        'train': train.toJson(),
        'seatClass': train.seatTypes.first.toJson(),
        'coach': {'seat_fare': 450},
        'seats': [
          {'ticket_id': 101, 'seat_number': 'KA-1'},
        ],
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': '10-Oct-2026',
      });
      var verified = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: LanguageService.instance,
              child: const MaterialApp(home: ReservationScreen()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.enterText(find.byType(TextField), '123456');
          await tester.ensureVisible(find.text('Verify OTP'));
          await tester.tap(find.text('Verify OTP'));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));
          expect(verified, 1);
          expect(find.byType(BookingScreen), findsOneWidget);
          expect(find.byType(ReservationScreen), findsNothing);
          expect(
            platform.controller.scripts.last,
            contains(BookingService.tripInfoUrl),
          );
          final script = platform.controller.scripts.first;
          final localValues = jsonDecode(
            script.split('Object.entries(')[1].split(').forEach')[0],
          );
          final sessionValues = jsonDecode(
            script.split('Object.entries(')[2].split(').forEach')[0],
          );
          final user = jsonDecode(localValues['user']);
          expect(user['phone_number'], '01700000000');
          expect(user['display_name'], 'Verified user');
          expect(
            sessionValues['initialPurchaseData${user['phone_number']}'],
            isNotNull,
          );
          expect(sessionValues['continue_booking_otp_verified'], '1');
          expect(sessionValues['confirm_booking_otp'], '123456');
          expect(
            (await BookingService.pending())?['status'],
            'readyForPayment',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('verify-otp')) {
            verified++;
            return http.Response(
              jsonEncode({
                'data': {
                  'success': true,
                  'user': {'name': 'Verified user', 'mobile': '01700000000'},
                },
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }),
      );
    },
  );
}
