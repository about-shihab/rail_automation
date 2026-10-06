import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/ticket_processing_overlay.dart';
import 'notification_service.dart';
import 'secure_store.dart';
import 'seat_layout_challenge.dart';
import 'turnstile_session.dart';

/// Coordinates one in-app verification overlay for a pending seat-layout read.
/// Unsubmitted tokens may be cached briefly; submitted tokens are consumed.
class TurnstileGate {
  bool get isPresenting => _route?.isActive ?? false;
  TurnstileGate._();
  static final TurnstileGate instance = TurnstileGate._();

  static const _tokenKey = 'rail_cft_token';
  static const _timeKey = 'rail_cft_token_time';

  /// Cloudflare tokens live 300 s. Refresh a little early so a token never
  /// expires halfway through a booking request.
  static const maxTokenAge = Duration(seconds: 240);

  static bool isChallengeError(Object error) => error is SeatLayoutChallenge;

  Future<String?>? _inflight;
  PageRoute<String>? _route;
  NavigatorState? _navigator;
  bool _takingToken = false;
  Future<void>? _layoutAccess;

  /// Set by the foreground-service isolate. The rendered browser belongs to
  /// the UI engine, so workers request a token instead of creating a WebView.
  Future<String?> Function(String label)? workerAcquire;
  bool workerPromptPresented = false;

  bool get isShowing => _inflight != null;

  /// The overlay can only be drawn when the Flutter UI is alive and in front.
  bool get canShowUi {
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return false;
    final life = WidgetsBinding.instance.lifecycleState;
    return life == null || life == AppLifecycleState.resumed;
  }

  // ── Token cache ──────────────────────────────────────────────────────────

  Future<String?> cachedToken() async {
    final token = await SecureStore.read(_tokenKey);
    final ts = int.tryParse(await SecureStore.read(_timeKey) ?? '');
    if (token == null || token.isEmpty || ts == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age < 0 || age > maxTokenAge.inMilliseconds) {
      await invalidate();
      return null;
    }
    return token;
  }

  Future<void> invalidate() async {
    await SecureStore.delete(_tokenKey);
    await SecureStore.delete(_timeKey);
  }

  Future<void> storeToken(String token) async {
    await SecureStore.write(_tokenKey, token);
    await SecureStore.write(
      _timeKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Remove before sending: a timeout does not prove the server left it unused.
  Future<String?> takeCachedToken() async {
    if (_takingToken) return null;
    _takingToken = true;
    try {
      final token = await cachedToken();
      await invalidate();
      return token;
    } finally {
      _takingToken = false;
    }
  }

  // ── Acquire ──────────────────────────────────────────────────────────────

  /// Returns a usable token.
  ///  * [forceFresh] false → a still-valid cached token is returned instantly,
  ///    no UI at all.
  ///  * [forceFresh] true → execute the preloaded widget for this booking.
  /// Returns null when the user cancelled or the UI isn't available
  /// (app in background → caller should fall back to a notification).
  Future<String?> acquire({String label = '', bool forceFresh = false}) {
    final running = _inflight;
    if (running != null) return running; // one prompt, many waiters

    late final Future<String?> f;
    f = _acquire(label, forceFresh).whenComplete(() {
      if (identical(_inflight, f)) {
        _inflight = null;
        _route = null;
        _navigator = null;
      }
    });
    _inflight = f;
    return f;
  }

  Future<String?> _acquire(String label, bool forceFresh) async {
    // Capture a pending silent execution before any async storage/navigation.
    // It may finish while the overlay is mounting; its result still belongs
    // to this request and must not start a second challenge.
    final session = TurnstileSession.instance;
    final pending = session.generating
        ? session.generate()
        : (forceFresh && workerAcquire == null && canShowUi
              ? session.generateWhenAttached()
              : null);
    if (forceFresh) {
      await invalidate();
    } else {
      final cached = await cachedToken();
      if (cached != null) return cached;
    }
    final worker = workerAcquire;
    if (worker != null) return worker(label);
    if (!canShowUi) return null;

    final request = pending ?? session.generateWhenAttached();
    final nav = NotificationService.navigatorKey.currentState!;
    HapticFeedback.mediumImpact();

    final route = PageRouteBuilder<String>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) =>
          TicketProcessingOverlay(contextLabel: label, tokenRequest: request),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
    _route = route;
    _navigator = nav;

    final token = await nav.push<String>(route);
    if (token == null || token.isEmpty) return null;
    return token;
  }

  /// Closes the overlay without a result (e.g. booking finished another way).
  void dismiss() {
    final r = _route;
    final n = _navigator;
    if (r != null && n != null && n.mounted && r.isActive) {
      try {
        n.removeRoute(r);
      } catch (_) {}
    }
  }

  /// Generate just before the seat-layout read and submit exactly once.
  /// Never wrap reservation or OTP mutations. Rejections require an explicit
  /// user retry; a rejected fresh token must not trigger another challenge.
  Future<T> guardSeatLayout<T>({
    String label = '',
    bool allowPrompt = true,
    required Future<T> Function(String? token) run,
  }) {
    final result = (_layoutAccess ?? Future<void>.value()).then(
      (_) => _readLayout(label: label, allowPrompt: allowPrompt, run: run),
    );
    late final Future<void> finished;
    finished = result
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (identical(_layoutAccess, finished)) _layoutAccess = null;
        });
    _layoutAccess = finished;
    return result;
  }

  Future<T> _readLayout<T>({
    required String label,
    required bool allowPrompt,
    required Future<T> Function(String? token) run,
  }) async {
    // A cached token here is an unsubmitted handoff from the foreground UI,
    // never a token generated during idle monitoring.
    final handedOff = await takeCachedToken();
    workerPromptPresented = false;
    final token =
        handedOff ??
        (allowPrompt || workerAcquire != null
            ? await acquire(label: label, forceFresh: true)
            : null);
    if (token == null) {
      throw SeatLayoutChallenge(
        verificationAttempted:
            workerPromptPresented || (allowPrompt && canShowUi),
      );
    }
    try {
      return await run(token);
    } on SeatLayoutChallenge {
      throw const SeatLayoutChallenge(verificationAttempted: true);
    }
  }
}
