import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/main.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/views/booking_screen.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProService pro;
  late MonitorService monitor;

  Future<void> savedSearch({
    String? seat,
    String? train,
    bool expired = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'br_auth_session': jsonEncode({
        'token': 'valid-test-token',
        'deviceId': 'device',
        'deviceKey': 'key',
      }),
      MonitorService.preferenceKey: jsonEncode({
        'id': 'search-1',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': '23-Sep-2026',
        'seat': seat,
        'train': train,
        'active': true,
        'expires': DateTime.now()
            .add(Duration(hours: expired ? -1 : 1))
            .toIso8601String(),
      }),
    });
    pro = ProService();
    monitor = MonitorService(proService: pro);
    await monitor.restore(startTimers: false);
  }

  tearDown(() {
    monitor.dispose();
    pro.dispose();
  });

  test(
    'Whole-route request sends SNIGDHA and evaluates all returned classes',
    () async {
      await savedSearch();
      await http.runWithClient(
        () => monitor.checkNow(),
        () => MockClient((request) async {
          expect(request.url.queryParameters['seat_class'], 'SNIGDHA');
          return http.Response(
            jsonEncode({
              'data': {
                'trains': ApiService.getMockResponse().trains
                    .map((t) => t.toJson())
                    .toList(),
              },
            }),
            200,
          );
        }),
      );
      expect(monitor.seatsFoundCount, 50);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('ticket_availability_search-1'),
        contains('F_SEAT'),
      );
      expect(prefs.getString('ticket_results_search-1'), isNotNull);
      expect(ApiService.requestSeatClass(' all '), 'SNIGDHA');
      expect(ApiService.requestSeatClass(''), 'SNIGDHA');
    },
  );

  test('Specific train and class only count matching seats', () async {
    await savedSearch(train: 'CHATTALA EXPRESS (802)', seat: 'S_CHAIR');
    await http.runWithClient(
      () => monitor.checkNow(),
      () => MockClient((request) async {
        expect(request.url.queryParameters['seat_class'], 'S_CHAIR');
        return http.Response(
          jsonEncode({
            'data': {
              'trains': ApiService.getMockResponse().trains
                  .map((t) => t.toJson())
                  .toList(),
            },
          }),
          200,
        );
      }),
    );
    expect(monitor.seatsFoundCount, 21);
    final count = monitor.logs.where((log) => log.isAlert).length;
    await http.runWithClient(
      () => monitor.checkNow(),
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'trains': ApiService.getMockResponse().trains
                  .map((t) => t.toJson())
                  .toList(),
            },
          }),
          200,
        ),
      ),
    );
    expect(monitor.logs.where((log) => log.isAlert).length, count);
  });

  test('Expired saved search does not call the API', () async {
    await savedSearch(expired: true);
    var calls = 0;
    await http.runWithClient(
      () => monitor.checkNow(),
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect(calls, 0);
    expect(monitor.isLimitReached, isTrue);
    expect(monitor.isMonitoring, isFalse);
  });

  test('Stopping while a response is pending discards the result', () async {
    await savedSearch();
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final check = http.runWithClient(
      () => monitor.checkNow(),
      () => MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    await started.future;
    monitor.stopMonitoring();
    response.complete(
      http.Response(
        jsonEncode({
          'data': {
            'trains': ApiService.getMockResponse().trains
                .map((t) => t.toJson())
                .toList(),
          },
        }),
        200,
      ),
    );
    await check;
    expect(monitor.seatsFoundCount, 0);
    expect(monitor.lastTrains, isEmpty);
  });

  testWidgets('Saved search is home; a queued notification opens booking', (
    tester,
  ) async {
    await savedSearch();
    final url = NotificationService.bookingUrl(
      'Dhaka',
      "Cox's Bazar",
      '23-Sep-2026',
      'SNIGDHA',
    );
    NotificationService().openBooking(url);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pro),
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider(create: (_) => ThemeService()),
        ],
        child: const BangladeshRailApp(startLoggedIn: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BookingScreen), findsOneWidget);
    expect(tester.widget<BookingScreen>(find.byType(BookingScreen)).url, url);
    NotificationService.navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MonitorDashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
