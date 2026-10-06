import 'package:flutter/widgets.dart';

import '../services/turnstile_gate.dart';

/// Backwards-compatible facade. The old centred pop-up dialog is gone; every
/// request now goes through [TurnstileGate] and is rendered by the in-app
/// `TicketProcessingOverlay`. Prefer calling the gate directly in new code.
class TurnstileDialog {
  const TurnstileDialog._();

  static bool get isShowing => TurnstileGate.instance.isShowing;

  static void dismiss() => TurnstileGate.instance.dismiss();

  static Future<String?> show(
    BuildContext context, {
    String contextLabel = '',
  }) =>
      TurnstileGate.instance.acquire(label: contextLabel, forceFresh: true);
}

/// Alias kept for existing callers.
class TurnstileSheet {
  const TurnstileSheet._();

  static bool get isShowing => TurnstileDialog.isShowing;

  static Future<String?> show(BuildContext context, {String contextLabel = ''}) =>
      TurnstileDialog.show(context, contextLabel: contextLabel);
}
