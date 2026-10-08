import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/journey_schedule.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late ProService pro;
  late MonitorService monitor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 8, 6);
    pro = ProService();
    monitor = MonitorService(
      proService: pro,
      backgroundWorker: true,
      now: () => now,
    );
  });
  tearDown(() {
    monitor.dispose();
    pro.dispose();
  });

  Future<void> saveSearch({
    String date = '19-Oct-2026',
    String expires = '2026-10-19T12:00:00Z',
    List<String> trains = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      MonitorService.preferenceKey,
      jsonEncode({
        'id': 'scheduled-journey',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': date,
        'expires': expires,
        'active': true,
        'startedAt': '2026-10-01T06:00:00Z',
        'trains': trains,
        'seat': 'S_CHAIR',
        'bookingIntent': {
          'autoReserve': false,
          'quantity': 2,
          'targetTrains': trains,
        },
      }),
    );
    await monitor.restore(startTimers: false);
  }

  test(
    '10-day window uses Bangladesh calendar midnight and includes day 10',
    () {
      final opening = DateTime.utc(2026, 10, 8, 18); // 9 Oct, 00:00 Bangladesh.
      expect(JourneySchedule.salesOpenAt('19-Oct-2026'), opening);
      expect(
        JourneySchedule.isOutsideWindow(
          '19-Oct-2026',
          now: opening.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        JourneySchedule.isOutsideWindow('19-Oct-2026', now: opening),
        isFalse,
      );
      expect(JourneySchedule.isOutsideWindow('18-Oct-2026', now: now), isFalse);
      expect(JourneySchedule.isOutsideWindow('19-Oct-2026', now: now), isTrue);
      expect(
        JourneySchedule.salesOpenAt('05-Jan-2027'),
        DateTime.utc(2026, 12, 25, 18),
      );
      expect(
        JourneySchedule.salesOpenAt('10-Mar-2028'),
        DateTime.utc(2028, 2, 28, 18),
      );
      expect(JourneySchedule.salesOpenAt('31-Feb-2026'), isNull);
    },
  );

  test(
    'departure formats resolve to Bangladesh time and preserve explicit zones',
    () {
      final expected = DateTime.utc(2026, 10, 19, 1, 45);
      expect(
        MonitorService.parseDepartureDateTime(
          departureDateTimeJd: 'Mon, 19 Oct 2026, 07:45 AM',
        ),
        expected,
      );
      expect(
        MonitorService.parseDepartureDateTime(
          departureDateTimeJd: '2026-10-19T07:45:00',
        ),
        expected,
      );
      expect(
        MonitorService.parseDepartureDateTime(
          departureDateTimeJd: '2026-10-19T07:45:00+06:00',
        ),
        expected,
      );
      expect(
        MonitorService.parseDepartureDateTime(
          dateOfJourney: '19-Oct-2026',
          departureDateTime: '19 Oct, 07:45 am',
        ),
        expected,
      );
    },
  );

  test('restored future schedule skips all API calls and preserves booking options', () async {
    await saveSearch(trains: ['TRAIN (701)']);
    expect(monitor.isScheduled, isTrue);
    expect(monitor.nextCheckDelay(), const Duration(hours: 12));
    expect(monitor.bookingIntent.quantity, 2);
    expect(monitor.targetSeatClass, 'S_CHAIR');
    var requests = 0;
    await http.runWithClient(
      () async {
        await monitor.checkNow();
        await monitor.restore(startTimers: false);
        await monitor.checkNow();
      },
      () => MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    expect(requests, 0);
    expect(monitor.totalChecksCount, 0);
    expect(monitor.isMonitoring, isTrue);
    expect(monitor.targetTrains, ['TRAIN (701)']);
  });

  test('search starts when its saved journey enters the window', () async {
    await saveSearch();
    await AuthSession.save(
      AuthSession(token: 'test-session', deviceKey: 'key'),
    );
    var requests = 0;
    await http.runWithClient(
      () async {
        await monitor.checkNow();
        expect(requests, 0);
        now = DateTime.utc(2026, 10, 8, 18);
        expect(monitor.isScheduled, isFalse);
        await monitor.checkNow();
      },
      () => MockClient((request) async {
        requests++;
        expect(request.url.queryParameters['date_of_journey'], '19-Oct-2026');
        return http.Response('{"data":{"trains":[]}}', 200);
      }),
    );
    expect(requests, 1);
    expect(monitor.totalChecksCount, 1);
  });

  test('restoring near departure never extends the saved deadline', () async {
    final departure = now.add(const Duration(minutes: 20));
    await saveSearch(date: '08-Oct-2026', expires: departure.toIso8601String());
    expect(monitor.departureAt, departure);
    expect(monitor.isMonitoring, isTrue);
    now = departure;
    await monitor.restore(startTimers: false);
    expect(monitor.departureAt, departure);
    expect(monitor.isMonitoring, isFalse);
    expect(monitor.isLimitReached, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(MonitorService.preferenceKey)!)['active'],
      isFalse,
    );
  });

  test(
    'search remains active beyond legacy maximum hours until departure',
    () async {
      await saveSearch(date: '09-Oct-2026', expires: '2026-10-09T12:00:00Z');
      expect(monitor.isMonitoring, isTrue);
      expect(monitor.isScheduled, isFalse);
      expect(monitor.remainingFreeSeconds, const Duration(hours: 30).inSeconds);
    },
  );

  test('multiple selected trains end at the last departure', () async {
    await saveSearch(
      date: '08-Oct-2026',
      expires: '2026-10-08T17:59:59Z',
      trains: ['EARLY (701)', 'LATE (702)'],
    );
    await AuthSession.save(
      AuthSession(token: 'test-session', deviceKey: 'key'),
    );
    await http.runWithClient(
      () => monitor.checkNow(),
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'trains': [
                {
                  'trip_number': 'EARLY (701)',
                  'departure_date_time_jd': '2026-10-08T05:00:00Z',
                  'seat_types': [],
                },
                {
                  'trip_number': 'LATE (702)',
                  'departure_date_time_jd': '2026-10-08T09:00:00Z',
                  'seat_types': [],
                },
              ],
            },
          }),
          200,
        ),
      ),
    );
    expect(monitor.isMonitoring, isTrue);
    expect(monitor.departureAt, DateTime.utc(2026, 10, 8, 9));
  });
}
