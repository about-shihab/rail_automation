import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/intermediate_station_search.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/views/intermediate_station_screen.dart';

void main() {
  final train = TrainTrip.fromJson({
    'trip_number': 'TEST (100)',
    'train_model': '100',
    'seat_types': [
      {'type': 'S_CHAIR', 'trip_id': 1, 'trip_route_id': 2},
    ],
  });
  final route = [
    {'city': 'From', 'departure_time': '23:00'},
    {'city': 'Via', 'arrival_time': '23:58', 'departure_time': '00:05'},
    {'city': 'To', 'arrival_time': '02:00'},
  ];
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    TrainRouteCache.clear();
    await LanguageService.instance.setLanguage(AppLanguage.en);
    await AuthSession.save(
      AuthSession(token: 'test-session', deviceKey: 'key'),
    );
  });
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: LanguageService.instance,
        child: MaterialApp(
          home: IntermediateStationScreen(
            train: train,
            from: 'From',
            to: 'To',
            date: '21-Oct-2026',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'route errors show a retry and both tabs stay usable on an iPhone-sized screen',
    (tester) async {
      var routes = 0;
      await http.runWithClient(
        () async {
          await show(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Station seats'));
          await tester.pumpAndSettle();
          expect(find.text('Retry loading stops'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(routes, 1);
          await tester.tap(find.text('Retry loading stops'));
          await tester.pumpAndSettle();
          expect(find.text('Complete Train Route Stops'), findsOneWidget);
          expect(find.byType(DropdownButton<RouteStation>), findsNWidgets(2));
          expect(routes, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((_) async {
          routes++;
          return routes == 1
              ? http.Response('{}', 503)
              : http.Response(
                  jsonEncode({
                    'data': {'routes': route},
                  }),
                  200,
                );
        }),
      );
    },
  );

  testWidgets(
    'switching to station seats cancels the scan and reuses loaded stops',
    (tester) async {
      var routeRequests = 0;
      var searches = 0;
      final response = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await show(tester);
          for (var i = 0; i < 60 && searches == 0; i++) {
            await tester.pump();
          }
          expect(searches, 1);
          expect(find.text('Stop search'), findsOneWidget);
          await tester.tap(find.text('Station seats'));
          await tester.pump(const Duration(milliseconds: 400));
          response.complete(http.Response('{"data":{"trains":[]}}', 200));
          await tester.pumpAndSettle();
          expect(routeRequests, 1);
          expect(searches, 1);
          expect(find.text('Complete Train Route Stops'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('train-routes')) {
            routeRequests++;
            return http.Response(
              jsonEncode({
                'data': {'routes': route},
              }),
              200,
            );
          }
          searches++;
          return response.future;
        }),
      );
    },
  );

  testWidgets('rate limiting shows a countdown and disables retries', (
    tester,
  ) async {
    var requests = 0;
    await http.runWithClient(
      () async {
        await show(tester);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Station seats'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Requests paused'), findsOneWidget);
        final retry = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('Retry loading stops'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              )
              .first,
        );
        expect(retry.onPressed, isNull);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((_) async {
        requests++;
        return http.Response(
          'Too many requests',
          429,
          headers: {'retry-after': '30'},
        );
      }),
    );
  });
}
