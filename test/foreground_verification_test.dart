import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/foreground_monitor.dart';

class _Service extends ServiceInstance {
  final events = <String, StreamController<Map<String, dynamic>?>>{};
  final sent = <(String, Map<String, dynamic>?)>[];
  void Function(String, Map<String, dynamic>?)? peer;

  @override
  Stream<Map<String, dynamic>?> on(String method) => events
      .putIfAbsent(method, () => StreamController.broadcast(sync: true))
      .stream;
  @override
  void invoke(String method, [Map<String, dynamic>? args]) {
    sent.add((method, args));
    peer?.call(method, args);
  }

  @override
  Future<void> stopSelf() async {}
  Future<void> close() async {
    for (final stream in events.values) {
      await stream.close();
    }
  }
}

void main() {
  test(
    'Worker accepts only its own fresh token and releases listeners',
    () async {
      final service = _Service();
      addTearDown(service.close);
      service.peer = (method, args) {
        if (method != 'verification-request') return;
        service.events['verification-ack']!.add({'id': args!['id']});
        service.events['verification-result']!.add({
          'id': 'other-booking',
          'token': 'wrong',
        });
        service.events['verification-result']!.add({
          'id': args['id'],
          'token': 'fresh-token',
          'presented': true,
        });
      };
      expect(
        await ForegroundMonitor.requestVerificationToken(service, 'Train'),
        ('fresh-token', true),
      );
      expect(service.sent.map((e) => e.$1), [
        'verification-request',
        'verification-cancel',
      ]);
      expect(service.events.values.every((e) => !e.hasListener), isTrue);
    },
  );

  test(
    'Missing UI falls back promptly without a seat-layout request',
    () async {
      final service = _Service();
      addTearDown(service.close);
      final future = ForegroundMonitor.requestVerificationToken(
        service,
        'Train',
        ackTimeout: const Duration(milliseconds: 20),
      );
      expect(await future, (null, false));
      expect(service.events.values.every((e) => !e.hasListener), isTrue);
    },
  );

  test('Timed out interaction cancels exactly the original request', () async {
    final service = _Service();
    addTearDown(service.close);
    service.peer = (method, args) {
      if (method == 'verification-request') {
        service.events['verification-ack']!.add({
          'id': args!['id'],
          'presented': true,
        });
      }
    };
    final future = ForegroundMonitor.requestVerificationToken(
      service,
      'Train',
      responseTimeout: const Duration(milliseconds: 20),
    );
    expect(await future, (null, true));
    expect(service.sent.last.$1, 'verification-cancel');
    expect(service.sent.last.$2?['id'], service.sent.first.$2?['id']);
    expect(service.events.values.every((e) => !e.hasListener), isTrue);
  });
}
