import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'monitor_service.dart';
import 'turnstile_gate.dart';

/// Finish one read when leaving the app. iOS grants a short window, not a
/// persistent service; subsequent searches belong to BGTaskScheduler.
class IosSearchContinuation {
  static const _channel = MethodChannel('com.example.rail_automation/overlay');
  static bool _running = false;

  static Future<void> run(MonitorService monitor) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !monitor.isMonitoring ||
        _running) {
      return;
    }
    _running = true;
    int? lease;
    try {
      lease = await _channel.invokeMethod<int>('beginSearchBackgroundTask');
      if (lease == null) return;
      // iOS suspends the browser right after this window, so get a fresh
      // token now; it stays valid ~5 minutes for background checks.
      await TurnstileGate.instance.prepareForBackground();
      await monitor.checkNow().timeout(const Duration(seconds: 20));
    } catch (_) {
      // The saved periodic search remains scheduled if iOS denies runtime,
      // the network stalls, or protected data is unavailable before first unlock.
    } finally {
      if (lease != null) {
        try {
          await _channel.invokeMethod<void>('endSearchBackgroundTask', {
            'id': lease,
          });
        } catch (_) {}
      }
      _running = false;
    }
  }
}
