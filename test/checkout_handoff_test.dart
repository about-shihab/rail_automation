import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/sms_service.dart';
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/models/purchased_ticket.dart';
import 'package:rail_automation/views/booking_screen.dart';

import 'support/fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWebViewPlatform webview;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
    await AuthSession.save(
      AuthSession(
        token: 'checkout-session',
        deviceKey: 'device-key',
        phoneNumber: '01700000000',
      ),
    );
    final train = ApiService.getMockResponse().trains[1];
    await BookingService.save({
      'id': 'checkout-test',
      'status': 'readyForPayment',
      'credit_deducted': true,
      'train': train.toJson(),
      'seatClass': train.seatTypes.first.toJson(),
      'coach': {'seat_fare': 450},
      'seats': [
        {'ticket_id': 101},
      ],
      'from': 'Dhaka',
      'to': 'Chattogram',
      'date': '08-Oct-2026',
      'otp': '123456',
    });
  });

  testWidgets(
    'restores reservation before Railway router, keeps gateways visible',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          expect(
            webview.controller.htmlBaseUrl,
            endsWith('/rail-pro-checkout-bootstrap'),
          );
          expect(
            webview.controller.loads,
            0,
            reason: 'No login or search page loads before restoration',
          );
          expect(
            webview.controller.scripts.first,
            contains('initialPurchaseData01700000000'),
          );
          // Railway uses localStorage.user.phone_number to find this exact key.
          final script = webview.controller.scripts.first;
          final localValues = jsonDecode(
            script.split('Object.entries(')[1].split(').forEach')[0],
          );
          final user = jsonDecode(localValues['user']);
          final sessionValues = jsonDecode(
            script.split('Object.entries(')[2].split(').forEach')[0],
          );
          expect(user['phone_number'], '01700000000');
          expect(
            jsonDecode(
              sessionValues['initialPurchaseData${user['phone_number']}'],
            )['reservedSeats'],
            isNotEmpty,
          );

          expect(
            webview.controller.scripts.first,
            contains('continue_booking_otp_verified'),
          );
          expect(
            webview.controller.scripts.last,
            contains('window.location.replace'),
          );
          expect(
            webview.controller.scripts.last,
            contains('/booking/train/trip-info'),
          );
          webview.controller.delegate!.pageFinished!(
            'https://payment.example/checkout',
          );
          await tester.pump();
          expect(
            find.text('Loading secure checkout & payment...'),
            findsNothing,
          );
          expect(find.text('Confirmed'), findsNothing);
          webview.controller.delegate!.pageFinished!(
            'https://eticket.railway.gov.bd/booking/train/search',
          );
          await tester.pump();
          expect(find.text('Retry checkout'), findsOneWidget);
          expect(
            (await BookingService.pending())?['status'],
            'readyForPayment',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (_) async => http.Response(jsonEncode({'data': []}), 200),
        ),
      );
    },
  );

  test(
    'checkout normalizes mobile-only identity and preserves the profile',
    () async {
      await SecureStore.write(
        'rail_user',
        jsonEncode({
          'mobile_number': '01700000000',
          'display_name': 'Test user',
          'id': 123,
        }),
      );
      final user = await BookingService.checkoutUser(
        (await AuthSession.load())!,
      );
      expect(user['phone_number'], '01700000000');
      expect(user['id'], 123);
      expect(user['display_name'], 'Test user');
    },
  );

  test('OTP response updates the identity used by checkout', () async {
    final state = (await BookingService.pending())!;
    state['status'] = 'awaitingOtp';
    await BookingService.save(state);
    await SecureStore.write('rail_user', jsonEncode({'id': 123}));
    await http.runWithClient(
      () async {
        await BookingService.verifyOtp('123456', (await AuthSession.load())!);
        final user = await BookingService.checkoutUser(
          (await AuthSession.load())!,
        );
        expect(user['phone_number'], '01700000000');
        expect(user['display_name'], 'Verified user');
        expect(user['id'], 123);
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'success': true,
              'user': {'name': 'Verified user', 'mobile': '01700000000'},
            },
          }),
          200,
        ),
      ),
    );
  });

  testWidgets('success URL alone never confirms or clears unpaid reservation', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: BookingScreen(url: BookingService.tripInfoUrl),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        webview.controller.delegate!.pageFinished!(
          'https://eticket.railway.gov.bd/payment/success',
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect((await BookingService.pending())?['status'], 'readyForPayment');
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () =>
          MockClient((_) async => http.Response(jsonEncode({'data': []}), 200)),
    );
  });

  test('automatic and manual verification share one OTP mutation', () async {
    final state = (await BookingService.pending())!;
    state['status'] = 'awaitingOtp';
    await BookingService.save(state);
    final auth = (await AuthSession.load())!;
    var mutations = 0;
    await http.runWithClient(
      () async {
        final results = await Future.wait([
          BookingService.verifyOtp('123456', auth),
          BookingService.verifyOtp('123456', auth),
        ]);
        expect(
          results.every((state) => state['status'] == 'readyForPayment'),
          isTrue,
        );
        expect(mutations, 1);
      },
      () => MockClient((_) async {
        mutations++;
        return http.Response(
          jsonEncode({
            'data': {'success': true},
          }),
          200,
        );
      }),
    );
  });

  test('missing order status is never assumed paid', () {
    expect(PurchasedTicket.fromJson({'pnr': 'PNR'}).isConfirmed, isFalse);
  });

  test('consented unrelated OTP is rejected without inventing a sender', () {
    expect(
      SmsService.extractOtp('', 'Your banking OTP is 123456', ['RAILWAY'], 6),
      isNull,
    );
    expect(
      SmsService.extractOtp('', 'Bangladesh Railway OTP is 123456', [
        'RAILWAY',
      ], 6),
      '123456',
    );
  });
}
