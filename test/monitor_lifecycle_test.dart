import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';

void main() {
  testWidgets(
    'leaving app joins an active check and never rearms suspended polling',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        MonitorService.preferenceKey: jsonEncode({
          'id': 'lifecycle-search',
          'from': 'Dhaka',
          'to': 'Chattogram',
          'date': DateFormat('dd-MMM-yyyy')
              .format(DateTime.now().add(const Duration(days: 1))),
          'active': true,
          'expires': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        }),
      });
      await AuthSession.save(
        AuthSession(token: 'live-test-session', deviceKey: 'key'),
      );
      final pro = ProService();
      final monitor = MonitorService(proService: pro);
      final response = Completer<http.Response>();
      var searches = 0;
      await http.runWithClient(
        () async {
          await monitor.restore(startTimers: false);
          final first = monitor.checkNow();
          monitor.suspendForegroundTimers();
          final continuation = monitor.checkNow();
          expect(identical(first, continuation), isTrue);
          for (var i = 0; i < 10 && searches == 0; i++) {
            await tester.pump();
          }
          expect(searches, 1);
          response.complete(http.Response('{"data":{"trains":[]}}', 200));
          await tester.pump();
          await first;
          await tester.pump(const Duration(minutes: 10));
          expect(
            searches,
            1,
            reason: 'Completing a check after pause must not restart a timer',
          );
        },
        () => MockClient((_) {
          searches++;
          return response.future;
        }),
      );
      monitor.dispose();
      pro.dispose();
    },
  );
}
