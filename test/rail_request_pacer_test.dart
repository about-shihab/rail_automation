import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/rail_api_client.dart';
import 'package:rail_automation/services/rail_request_pacer.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 21);
  final waits = <Duration>[];
  Future<void> wait(Duration duration) async {
    waits.add(duration);
    now = now.add(duration);
  }

  RailRequestPacer pacer() => RailRequestPacer(now: () => now, delay: wait);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'different operations share spacing and wait for the previous response',
    () async {
      final clock = _Clock();
      final pacer = clock.pacer();
      final response = Completer<int>();
      final started = <DateTime>[];
      final first = pacer.run(
        operation: 'search_trips',
        send: () {
          started.add(clock.now);
          return response.future;
        },
      );
      final second = pacer.run(
        operation: 'reserve_seat',
        send: () async {
          started.add(clock.now);
          return 2;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(started, hasLength(1));
      response.complete(1);
      expect(await Future.wait([first, second]), [1, 2]);
      expect(
        started.last.difference(started.first),
        const Duration(milliseconds: 1500),
      );
    },
  );

  test('operation-specific spacing is respected and failed slots release the queue', () async {
    final clock = _Clock();
    final pacer = clock.pacer();
    await expectLater(
      pacer.run<void>(
        operation: 'search',
        send: () async {
          throw const SocketException('offline');
        },
      ),
      throwsA(isA<SocketException>()),
    );
    await pacer.run(
      operation: 'search',
      minInterval: const Duration(seconds: 5),
      send: () async => 1,
    );
    expect(clock.waits, [const Duration(seconds: 5)]);
  });

  test(
    'numeric and HTTP-date Retry-After values include server clock skew',
    () {
      final clock = _Clock();
      final pacer = clock.pacer();
      expect(
        pacer.rateLimited({'retry-after': '65'}),
        clock.now.add(const Duration(seconds: 65)),
      );
      final other = clock.pacer();
      expect(
        other.rateLimited({
          'date': 'Wed, 21 Oct 2026 10:00:00 GMT',
          'retry-after': 'Wed, 21 Oct 2026 10:02:00 GMT',
        }),
        clock.now.add(const Duration(minutes: 2)),
      );
    },
  );

  test('missing or invalid Retry-After backs off and never shortens an existing pause', () {
    final clock = _Clock();
    final pacer = clock.pacer();
    pacer.rateLimited({});
    expect(pacer.cooldownRemaining, const Duration(seconds: 30));
    clock.now = clock.now.add(const Duration(seconds: 30));
    pacer.rateLimited({'retry-after': 'invalid'});
    expect(pacer.cooldownRemaining, const Duration(seconds: 60));
    pacer.rateLimited({'retry-after': '1'});
    expect(pacer.cooldownRemaining, const Duration(seconds: 60));
  });

  test(
    'a rate-limited response prevents all queued operations from sending',
    () async {
      final clock = _Clock();
      final pacer = clock.pacer();
      var sent = 0;
      Future<void> send(String operation) => pacer.run(
        operation: operation,
        send: () async {
          sent++;
          throw RailwayRateLimited(pacer.rateLimited({'retry-after': '45'}));
        },
      );
      await Future.wait([
        expectLater(send('search'), throwsA(isA<RailwayRateLimited>())),
        expectLater(send('train_routes'), throwsA(isA<RailwayRateLimited>())),
        expectLater(send('reserve_seat'), throwsA(isA<RailwayRateLimited>())),
      ]);
      expect(sent, 1);
      clock.now = clock.now.add(const Duration(seconds: 45));
      expect(
        await pacer.run(operation: 'search', send: () async => 'resumed'),
        'resumed',
      );
    },
  );

  group('RailApiClient cooldown integration', () {
    final auth = AuthSession(
      token: 'test-session',
      deviceId: 'device',
      deviceKey: 'key',
    );
    late _Clock clock;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await AppConfig.instance.reloadCache();
      clock = _Clock();
      RailApiClient.requestPacer = clock.pacer();
    });
    Future<http.Response> request(String operation) => RailApiClient.request(
      operation: operation,
      method: operation == 'search_trips' || operation == 'seat_layout'
          ? 'GET'
          : 'POST',
      payload: {},
      auth: auth,
    );

    test('429 is never retried, blocks other endpoints, and survives a client restart', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConfig.cacheKey,
        jsonEncode({
          'api_operations': {
            'search_trips': {'retries': 3},
          },
        }),
      );
      await AppConfig.instance.reloadCache();
      var calls = 0;
      await http.runWithClient(
        () async {
          await expectLater(
            request('search_trips'),
            throwsA(isA<RailwayRateLimited>()),
          );
          await expectLater(
            request('train_routes'),
            throwsA(isA<RailwayRateLimited>()),
          );
          RailApiClient.requestPacer = clock.pacer();
          await expectLater(
            request('handshake'),
            throwsA(isA<RailwayRateLimited>()),
          );
          expect(calls, 1);
          clock.now = clock.now.add(const Duration(seconds: 90));
          expect((await request('search_trips')).statusCode, 200);
          expect(calls, 2);
        },
        () => MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response(
                  'Too many requests',
                  429,
                  headers: {'retry-after': '90'},
                )
              : http.Response('{}', 200);
        }),
      );
    });

    test(
      'one-use seat-layout reads do not replay tokens on server errors',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AppConfig.cacheKey,
          jsonEncode({
            'api_operations': {
              'seat_layout': {'retries': 3},
            },
          }),
        );
        await AppConfig.instance.reloadCache();
        var calls = 0;
        await http.runWithClient(
          () async {
            expect((await request('seat_layout')).statusCode, 503);
            expect(calls, 1);
          },
          () => MockClient((_) async {
            calls++;
            return http.Response('{}', 503);
          }),
        );
      },
    );
  });
}
