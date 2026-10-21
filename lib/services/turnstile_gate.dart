import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/ticket_processing_overlay.dart';
import 'notification_service.dart';
import 'secure_store.dart';
import 'seat_layout_challenge.dart';
import 'turnstile_session.dart';

/// Coordinates in-app verification for seat-layout reads.
/// Tokens are solved silently in the background while the app is open and are
/// valid for 5 minutes so users are not repeatedly prompted.
class TurnstileGate {
  bool get isPresenting => _route?.isActive ?? false;
  TurnstileGate._();
  static final TurnstileGate instance = TurnstileGate._();

  static const _tokenKey = 'rail_cft_token';
  static const _timeKey = 'rail_cft_token_time';

  /// Cloudflare Turnstile tokens are valid for 5 minutes.
  static const maxTokenAge = Duration(minutes: 5);

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

  Timer? _refreshTimer;

  /// Starts refreshing the turnstile token periodically in the background while
  /// the app is in the foreground, ensuring a fresh 5-minute token is always ready.
  void startBackgroundRefresh() {
    _refreshTimer?.cancel();
    warmInBackground();
    _refreshTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (canShowUi) {
        warmInBackground();
      }
    });
  }

  /// Stops background refresh when the app is paused or inactive.
  void stopBackgroundRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Silently solve a verification token in the background while the app is open.
  /// Valid for 5 minutes. Never presents any UI unless an interaction is required.
  void warmInBackground() {
    if (!canShowUi || isShowing) return;
    unawaited(() async {
      try {
        final existing = await cachedToken();
        if (existing != null && existing.isNotEmpty) {
          final ts = int.tryParse(await SecureStore.read(_timeKey) ?? '');
          if (ts != null) {
            final age = DateTime.now().millisecondsSinceEpoch - ts;
            // Token is still fresh (valid for more than 1 minute remaining)
            if (age < const Duration(seconds: 240).inMilliseconds) return;
          }
        }
        final token = await acquire(
          label: 'Verification',
          forceFresh: true,
          allowPrompt: false,
        );
        if (token != null && token.isNotEmpty) {
          await storeToken(token);
        }
      } catch (_) {
        // Silent background warm; keep app undisturbed
      }
    }());
  }

  // ── Acquire ──────────────────────────────────────────────────────────────

  /// Returns a usable token.
  ///  * [forceFresh] false → a still-valid cached token is returned instantly,
  ///    no UI at all.
  ///  * [forceFresh] true → execute the preloaded widget for this booking.
  ///  * [allowPrompt] false → do not present interactive dialog if human check required.
  /// Returns null when the user cancelled or the UI isn't available.
  Future<String?> acquire({
    String label = '',
    bool forceFresh = false,
    String? siteKey,
    bool allowPrompt = true,
  }) {
    final running = _inflight;
    if (running != null) return running; // one prompt, many waiters

    late final Future<String?> f;
    f = _acquire(label, forceFresh, siteKey, allowPrompt).whenComplete(() {
      if (identical(_inflight, f)) {
        _inflight = null;
        _route = null;
        _navigator = null;
      }
    });
    _inflight = f;
    return f;
  }

  Future<String?> _acquire(
    String label,
    bool forceFresh, [
    String? siteKey,
    bool allowPrompt = true,
  ]) async {
    // Capture a pending silent execution before any async storage/navigation.
    final targetKey =
        siteKey ??
        (label == 'Railway login' ? '0x4AAAAAAB5VTjZ90pUxRuXR' : null);
    final session = TurnstileSession.instance;
    final pending = session.generating
        ? session.generate(targetKey)
        : (forceFresh && workerAcquire == null && canShowUi
              ? session.generateWhenAttached(targetKey)
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

    final request = pending ?? session.generateWhenAttached(targetKey);
    // Execute in the retained browser without navigating or interrupting the
    // current screen. Only an actual interactive challenge needs an overlay.
    final interactive = Completer<void>();
    void watchInteraction() {
      if (session.phase == TurnstilePhase.interactive &&
          !interactive.isCompleted) {
        interactive.complete();
      }
    }

    session.addListener(watchInteraction);
    if (session.phase == TurnstilePhase.interactive &&
        !interactive.isCompleted) {
      interactive.complete();
    }
    try {
      watchInteraction();
      final result = await Future.any<({bool interactive, String? token})>([
        request.then((token) => (interactive: false, token: token)),
        interactive.future.then((_) => (interactive: true, token: null)),
      ]);
      if (!result.interactive) return result.token;
      if (!allowPrompt || !canShowUi) {
        session.cancel();
        return null;
      }
      return await _showInteraction(label, request);
    } finally {
      session.removeListener(watchInteraction);
    }
  }

  Future<String?> _showInteraction(
    String label,
    Future<String?> request,
  ) async {
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
    if (_route == null && _inflight != null) {
      TurnstileSession.instance.cancel();
    }
    final r = _route;
    final n = _navigator;
    if (r != null && n != null && n.mounted && r.isActive) {
      try {
        n.removeRoute(r);
      } catch (_) {}
    }
  }

  /// Generate just before the seat-layout read.
  /// If a valid token was already pre-solved in the background (< 5 min),
  /// it is used immediately without showing any challenge to the user.
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
    final handedOff = await takeCachedToken();
    workerPromptPresented = false;
    final token =
        handedOff ??
        (allowPrompt || workerAcquire != null
            ? await acquire(
                label: label,
                forceFresh: true,
                allowPrompt: allowPrompt,
              )
            : null);
    if (token == null) {
      throw SeatLayoutChallenge(
        verificationAttempted:
            workerPromptPresented || (allowPrompt && canShowUi),
      );
    }
    try {
      final res = await run(token);
      if (canShowUi && _refreshTimer != null) {
        warmInBackground();
      }
      return res;
    } on SeatLayoutChallenge {
      await invalidate();
      throw const SeatLayoutChallenge(verificationAttempted: true);
    }
  }
}
