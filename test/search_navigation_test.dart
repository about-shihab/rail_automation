import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/views/train_selection_screen.dart';
import 'package:rail_automation/widgets/booking_activity_overlay.dart';
import 'package:rail_automation/widgets/fancy_train_loader.dart';
import 'package:rail_automation/widgets/journey_search_button.dart';

void main() {
  late MonitorService monitor;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_language_code': 'en',
      'rps_last_from_station': 'Dhaka',
      'rps_last_to_station': 'Chattogram',
    });
    FlutterSecureStorage.setMockInitialValues({});
    await LanguageService.instance.setLanguage(AppLanguage.en);
    await AuthSession.save(
      AuthSession(
        token: 'test-session',
        deviceKey: 'key',
        phoneNumber: '01700000000',
      ),
    );
    CreditService().setCreditsForTesting(5);
    monitor = MonitorService(proService: ProService());
    const channel = MethodChannel('com.example.rail_automation/sms');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
  });
  tearDown(() {
    monitor.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.rail_automation/sms'),
          null,
        );
  });

  Future<void> showApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          builder: (_, child) => BookingActivityOverlay(child: child!),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'single search loader and available-train auto-book opens Tickets',
    (tester) async {
      final search = Completer<http.Response>();
      final check = Completer<http.Response>();
      final train = TrainTrip.fromJson({
        ...ApiService.getMockResponse().trains[1].toJson(),
        'departure_date_time_jd': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
      });
      var searches = 0;
      await http.runWithClient(
        () async {
          await showApp(tester);
          await tester.tap(find.byType(JourneySearchButton));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(FancyTrainLoader), findsOneWidget);
          expect(
            find.byKey(const ValueKey('booking-api-barrier')),
            findsOneWidget,
          );
          search.complete(
            http.Response(
              jsonEncode({
                'data': {
                  'trains': [train.toJson()],
                },
              }),
              200,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(FancyTrainLoader), findsNothing);
          expect(find.byType(TrainSelectionScreen), findsOneWidget);
          await tester.ensureVisible(find.text('Auto-book').first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.text('Auto-book').first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Random Class (Any Available)'));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.ensureVisible(find.text('Start'));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.text('Start'));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));
          expect(AppShell.tab.value, AppShell.tabMonitor);
          expect(find.byType(TrainSelectionScreen), findsNothing);
          expect(monitor.targetTrains, contains(train.tripNumber));
          check.complete(
            http.Response(
              jsonEncode({
                'data': {'trains': []},
              }),
              200,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(monitor.isMonitoring, isTrue);
          // Adding another train to this active route must also leave results.
          final added = ApiService.getMockResponse().trains.first;
          NotificationService.navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => TrainSelectionScreen(
                searchResponse: TripSearchResponse(trains: [added]),
                fromCity: monitor.fromCity,
                toCity: monitor.toCity,
                dateOfJourney: monitor.dateOfJourney,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.ensureVisible(find.text('Auto-book').first);
          await tester.tap(find.text('Auto-book').first);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 500));
          expect(AppShell.tab.value, AppShell.tabMonitor);
          expect(find.byType(TrainSelectionScreen), findsNothing);
          expect(monitor.targetTrains, contains(added.tripNumber));
          monitor.suspendForegroundTimers();
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('search-trips-v2')) {
            searches++;
            return searches == 1 ? search.future : check.future;
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }),
      );
    },
  );
}
