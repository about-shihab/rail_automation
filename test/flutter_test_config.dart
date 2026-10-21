import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/rail_api_client.dart';
import 'package:rail_automation/services/rail_request_pacer.dart';
import 'package:rail_automation/services/turnstile_gate.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Most tests use an in-memory Railway server. Keep the production queue,
  // without wall-clock spacing between mock responses. Pacing regressions
  // exercise the real 1.5-second policy with an injected clock separately.
  setUp(() {
    RailApiClient.requestPacer = RailRequestPacer(
      minimumSpacing: Duration.zero,
    );
    TurnstileGate.instance.resetSubmittedTokensForTesting();
  });
  await testMain();
}
