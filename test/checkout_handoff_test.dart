import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/sms_service.dart';
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/services/web_session_service.dart';
import 'package:rail_automation/models/purchased_ticket.dart';
import 'package:rail_automation/views/booking_screen.dart';

import 'support/fake_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWebViewPlatform webview;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    await LanguageService.instance.setLanguage(AppLanguage.en);
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('checkout sets unified browser identity for payment: $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final checkout = WebViewController();
        await WebSessionService.configurePaymentBrowser(checkout);
        if (platform == TargetPlatform.android) {
          expect(
            webview.controller.userAgentOverrides.last,
            WebSessionService.checkoutUserAgent,
          );
        } else {
          expect(webview.controller.userAgentOverrides, isEmpty);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('checkout location timeout is scoped to iOS: $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(
                home: BookingScreen(url: BookingService.tripInfoUrl),
              ),
            );
            await tester.pump(const Duration(milliseconds: 50));
            webview.controller.delegate!.pageFinished!(
              BookingService.tripInfoUrl,
            );
            await tester.pump();
            expect(
              webview.controller.scripts.contains(
                WebSessionService.iosCheckoutLocationScript,
              ),
              platform == TargetPlatform.iOS,
            );
            final count = webview.controller.scripts.length;
            webview.controller.delegate!.pageFinished!(
              'https://payment.example/checkout',
            );
            await tester.pump();
            expect(
              webview.controller.scripts.length,
              count,
              reason: 'Do not inject into payment providers',
            );
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
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('gateway return cannot restore consumed checkout tokens', (
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
        final controller = webview.controller;
        expect(
          controller.scripts.first,
          isNot(contains('sessionStorage.removeItem =')),
        );
        final count = controller.scripts.length;
        controller.delegate!.pageStarted!(BookingService.tripInfoUrl);
        controller.delegate!.pageFinished!(BookingService.tripInfoUrl);
        await tester.pump();
        expect(
          controller.scripts.length,
          count + 1,
          reason: 'The website owns action-token rotation after bootstrap',
        );
        expect(
          controller.scripts.last,
          WebSessionService.checkoutAppearanceScript,
        );
        await controller.delegate!.navigationRequest!(
          NavigationRequest(
            url: 'https://payment.example/checkout',
            isMainFrame: false,
          ),
        );
        await controller.delegate!.navigationRequest!(
          NavigationRequest(
            url: 'https://payment.example/checkout',
            isMainFrame: true,
          ),
        );
        controller.delegate!.pageFinished!(
          'https://eticket.railway.gov.bd/booking/train/search',
        );
        await tester.pump();
        expect(
          controller.scripts.length,
          count + 1,
          reason: 'Do not resurrect a consumed reservation on gateway return',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () =>
          MockClient((_) async => http.Response(jsonEncode({'data': []}), 200)),
    );
  });

  testWidgets('missing payment app uses the intent web fallback', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    try {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          final decision =
              await webview.controller.delegate!.navigationRequest!(
                NavigationRequest(
                  url:
                      'intent://pay#Intent;scheme=bkash;'
                      'S.browser_fallback_url=https%3A%2F%2Fpayment.example%2Fcheckout;end',
                  isMainFrame: true,
                ),
              );
          expect(decision, NavigationDecision.prevent);
          expect(webview.controller.url, 'https://payment.example/checkout');
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (_) async => http.Response(jsonEncode({'data': []}), 200),
        ),
      );
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('Android keeps the payment gateway in-app so bKash pops up', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launches = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          launches.add(call);
          return true;
        });
    try {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          final navigate = webview.controller.delegate!.navigationRequest!;
          const gateway = 'https://train-pay.shohoz.com/bkash/test-order';
          expect(
            await navigate(NavigationRequest(url: gateway, isMainFrame: false)),
            NavigationDecision.navigate,
          );
          expect(launches, isEmpty);
          expect(
            await navigate(NavigationRequest(url: gateway, isMainFrame: true)),
            NavigationDecision.navigate,
          );
          expect(launches, isEmpty, reason: 'bKash should pop up in-app without opening another tab');
          await tester.pump(const Duration(milliseconds: 50));
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('payment gateways stay in-app so bKash pops up without opening another tab', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      for (final url in [
        'https://train-pay.shohoz.com/bkash/order',
        BookingService.tripInfoUrl,
        'http://train-pay.shohoz.com/bkash/order',
        'https://train-pay.shohoz.com.example.org/bkash/order',
      ]) {
        expect(WebSessionService.usesAndroidPaymentBrowser(url), isFalse);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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
    expect(
      SmsService.extractOtp('', 'Bangladesh Railway OTP is 7549', [
        'RAILWAY',
      ], 4),
      '7549',
    );
  });

  test('isPaymentGatewayUrl recognizes bKash, Nagad, Rocket, Upay, and Cards', () {
    for (final url in [
      'https://train-pay.shohoz.com/bkash/order123',
      'https://train-pay.shohoz.com/nagad/order123',
      'https://train-pay.shohoz.com/rocket/order123',
      'https://train-pay.shohoz.com/upay/order123',
      'https://train-pay.shohoz.com/cards/order123',
      'https://payment.mynagad.com/pay',
      'https://client.pay.bka.sh/checkout',
      'https://securepay.sslcommerz.com/gwprocess/v4',
      'https://upaybd.com/payment',
    ]) {
      expect(WebSessionService.isPaymentGatewayUrl(url), isTrue, reason: url);
    }

    for (final nonGateway in [
      'http://train-pay.shohoz.com/bkash/order',
      'https://eticket.railway.gov.bd/booking/train/trip-info',
      'https://example.com/checkout',
      'https://train-pay.shohoz.com.example.org/bkash/order',
    ]) {
      expect(WebSessionService.isPaymentGatewayUrl(nonGateway), isFalse, reason: nonGateway);
    }
  });

  testWidgets(
    'callback with /booking/train/status and trxid confirms booking via purchase history',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));

          // Simulate gateway redirecting back to Railway status callback
          webview.controller.delegate!.pageFinished!(
            'https://eticket.railway.gov.bd/booking/train/status?booking_id=85520214&trxid=1M7H8V4F4B1ZFQFT',
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('Your ticket is confirmed!'), findsOneWidget);
          expect(find.text('View Ticket in Trips'), findsOneWidget);
          expect(await BookingService.pending(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.contains('purchase-history')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'order_id': 85520214,
                    'order_status': 1,
                    'pnr': 'PNR998877',
                    'trip_id': 8606141,
                    'trip_number': 'SUBORNO EXPRESS (701)',
                    'journey_date': '08-Oct-2026',
                    'booking_date': '08-Oct-2026',
                    'origin_city_id': 1,
                    'user_id': 123,
                    'refund_validity_info': {},
                  }
                ]
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }),
      );
    },
  );

  testWidgets(
    'callback with /booking/train/status and error shows cancellation message',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));

          webview.controller.delegate!.pageFinished!(
            'https://eticket.railway.gov.bd/booking/train/status?booking_id=85520214&error=User%20Cancel',
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('User Cancel'), findsOneWidget);
          expect(
            (await BookingService.pending())?['status'],
            'readyForPayment',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((_) async => http.Response(jsonEncode({'data': []}), 200)),
      );
    },
  );
}
