import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/views/train_selection_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthSession(token: 'test-token', deviceKey: 'key');
  Map<String, dynamic> seat(String type, int id, int count) => {
    'type': type,
    'trip_id': id,
    'trip_route_id': 100 + count,
    'fare': '200',
    'seat_counts': {'online': count, 'offline': 20},
  };
  Map<String, dynamic> train(List<Map<String, dynamic>> seats) => {
    'trip_number': 'TEST (100)',
    'train_model': '100',
    'seat_types': seats,
  };
  final routes = [
    {'city': 'Before', 'departure_time': '21:00'},
    {'city': 'From', 'arrival_time': '22:00', 'departure_time': '23:00'},
    {'city': 'Via', 'arrival_time': '23:58', 'departure_time': '00:05'},
    {'city': 'To', 'arrival_time': '02:00'},
    {'city': 'After', 'departure_time': '03:00'},
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'sold-out train opens intermediate search and correct second-leg booking results',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AuthSession.save(auth);
      await LanguageService.instance.setLanguage(AppLanguage.en);
      CreditService().setCreditsForTesting(5);
      final pro = ProService();
      final monitor = MonitorService(proService: pro);
      final original = TrainTrip.fromJson(train([seat('S_CHAIR', 1, 0)]));
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: LanguageService.instance),
                ChangeNotifierProvider.value(value: CreditService()),
                ChangeNotifierProvider.value(value: monitor),
              ],
              child: MaterialApp(
                home: TrainSelectionScreen(
                  searchResponse: TripSearchResponse(trains: [original]),
                  fromCity: 'From',
                  toCity: 'To',
                  dateOfJourney: '21-Oct-2026',
                  initialClass: 'S_CHAIR',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Search via intermediate station'));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(find.text('From → Via → To'), findsOneWidget);
          expect(find.textContaining('two separate tickets'), findsOneWidget);
          await tester.tap(find.text('View leg 2: Via → To'));
          await tester.pumpAndSettle();
          final screen = tester.widget<TrainSelectionScreen>(
            find.byType(TrainSelectionScreen).last,
          );
          expect(screen.fromCity, 'Via');
          expect(screen.toCity, 'To');
          expect(screen.dateOfJourney, '22-Oct-2026');
          expect(
            screen.searchResponse.trains.single.seatTypes.single.tripRouteId,
            102,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/train-routes')) {
            return http.Response(
              jsonEncode({
                'data': {'routes': routes},
              }),
              200,
            );
          }
          final first = request.url.queryParameters['from_city'] == 'From';
          return http.Response(
            jsonEncode({
              'data': {
                'trains': [
                  train([seat('S_CHAIR', 1, first ? 4 : 2)]),
                ],
              },
            }),
            200,
          );
        }),
      );
      monitor.dispose();
      pro.dispose();
    },
  );

  testWidgets(
    'shows simple loading indicator while lazy loading via station',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await AuthSession.save(auth);
      await LanguageService.instance.setLanguage(AppLanguage.en);
      CreditService().setCreditsForTesting(5);
      final pro = ProService();
      final monitor = MonitorService(proService: pro);
      final original = TrainTrip.fromJson(train([seat('S_CHAIR', 1, 0)]));

      final completer = Completer<http.Response>();

      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: LanguageService.instance),
                ChangeNotifierProvider.value(value: CreditService()),
                ChangeNotifierProvider.value(value: monitor),
              ],
              child: MaterialApp(
                home: TrainSelectionScreen(
                  searchResponse: TripSearchResponse(trains: [original]),
                  fromCity: 'From',
                  toCity: 'To',
                  dateOfJourney: '21-Oct-2026',
                  initialClass: 'S_CHAIR',
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            find.textContaining('via'),
            findsWidgets,
          );
          completer.complete(
            http.Response(jsonEncode({'data': {'routes': routes}}), 200),
          );
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/train-routes')) {
            return completer.future;
          }
          return http.Response(
            jsonEncode({'data': {'trains': []}}),
            200,
          );
        }),
      );
      monitor.dispose();
      pro.dispose();
    },
  );
}
