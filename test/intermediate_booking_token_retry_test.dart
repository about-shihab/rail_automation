import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/intermediate_station_search.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/turnstile_gate.dart';
import 'package:rail_automation/views/intermediate_station_screen.dart';
import 'package:rail_automation/views/seat_booking_screen.dart';
import 'package:rail_automation/widgets/turnstile_host.dart';

import 'support/fake_inapp_webview.dart';

void main() {
  testWidgets(
    'the overnight intermediate leg refreshes a rejected token and loads its own seats',
    (tester) async {
      SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
      FlutterSecureStorage.setMockInitialValues({});
      TrainRouteCache.clear();
      await AppConfig.instance.reloadCache();
      await LanguageService.instance.setLanguage(AppLanguage.en);
      await AuthSession.save(
        AuthSession(
          token: 'test-session',
          deviceId: 'device',
          deviceKey: 'key',
        ),
      );
      final browser = FakeInAppWebViewPlatform();
      InAppWebViewPlatform.instance = browser;
      Map<String, dynamic> train(int route, int seats) => {
        'trip_number': 'TEST (100)',
        'train_model': '100',
        'departure_date_time': '23:00',
        'arrival_date_time': '02:00',
        'seat_types': [
          {
            'type': 'S_CHAIR',
            'trip_id': 11,
            'trip_route_id': route,
            'fare': '250',
            'seat_counts': {'online': seats},
          },
        ],
      };
      final layouts = <http.Request>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: LanguageService.instance,
              child: MaterialApp(
                navigatorKey: NotificationService.navigatorKey,
                builder: (_, child) => TurnstileHost(child: child!),
                home: IntermediateStationScreen(
                  train: TrainTrip.fromJson(train(100, 0)),
                  from: 'From',
                  to: 'To',
                  date: '21-Oct-2026',
                  seatClass: 'S_CHAIR',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await TurnstileGate.instance.storeToken('rejected-prepared-token');
          final secondLeg = find.text('Book (S_CHAIR)').last;
          await tester.ensureVisible(secondLeg);
          await tester.pumpAndSettle();
          await tester.tap(secondLeg);
          for (var i = 0; i < 100 && browser.controller.executions == 0; i++) {
            await tester.pump();
          }
          expect(layouts, hasLength(1));
          expect(browser.controller.executions, 1);
          browser.controller.send(
            '{"status":"SUCCESS","token":"new-intermediate-token"}',
          );
          for (var i = 0; i < 100 && layouts.length < 2; i++) {
            await tester.pump();
          }
          await tester.pumpAndSettle();
          final screen = tester.widget<SeatBookingScreen>(
            find.byType(SeatBookingScreen),
          );
          expect(screen.fromCity, 'Via');
          expect(screen.toCity, 'To');
          expect(screen.dateOfJourney, '22-Oct-2026');
          expect(layouts.map((r) => r.url.queryParameters['trip_route_id']), [
            '102',
            '102',
          ]);
          expect(layouts.map((r) => r.url.queryParameters['cft_response']), [
            'rejected-prepared-token',
            'new-intermediate-token',
          ]);
          expect(find.text('KA-1'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('train-routes')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'routes': [
                    {'city': 'From', 'departure_time': '23:00'},
                    {
                      'city': 'Via',
                      'arrival_time': '23:58',
                      'departure_time': '00:05',
                    },
                    {'city': 'To', 'arrival_time': '02:00'},
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('search-trips-v2')) {
            final first = request.url.queryParameters['from_city'] == 'From';
            return http.Response(
              jsonEncode({
                'data': {
                  'trains': [train(first ? 101 : 102, 2)],
                },
              }),
              200,
            );
          }
          layouts.add(request);
          if (layouts.length == 1) {
            return http.Response('{"message":"Invalid cft_response"}', 422);
          }
          return http.Response(
            jsonEncode({
              'data': {
                'seatLayout': [
                  {
                    'floor_name': 'KA',
                    'seat_floor': 1,
                    'seat_fare': '250',
                    'layout': [
                      [
                        {
                          'seat_number': 'KA-1',
                          'ticket_id': 91,
                          'seat_availability': 1,
                        },
                      ],
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
