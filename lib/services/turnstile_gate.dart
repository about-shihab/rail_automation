import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/ticket_processing_overlay.dart';
import 'app_config.dart';
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
  static const _siteKey = 'rail_cft_site_key';

  /// Cloudflare Turnstile tokens are valid for 5 minutes.
  static const maxTokenAge = Duration(minutes: 5);

  static bool isChallengeError(Object error) => error is SeatLayoutChallenge;

  Future<String?>? _inflight;
  String? _inflightSiteKey;
  Future<void>? _warming;
  final _submittedTokens = <String, DateTime>{};

  @visibleForTesting
  void resetSubmittedTokensForTesting() => _submittedTokens.clear();
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

  bool get _canRefreshWhileOpen =>
      canShowUi || (workerAcquire != null && NotificationService().appVisible);

  // ── Token cache ──────────────────────────────────────────────────────────

  Future<String?> cachedToken() async {
    final token = await SecureStore.read(_tokenKey);
    final ts = int.tryParse(await SecureStore.read(_timeKey) ?? '');
    if (token == null || token.isEmpty || ts == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    final siteKey = await SecureStore.read(_siteKey);
    if (age < 0 ||
        age >= (maxTokenAge - const Duration(seconds: 30)).inMilliseconds ||
        siteKey != _keyFor('', null) ||
        _submittedTokens.containsKey(token)) {
      await invalidate();
      return null;
    }
    return token;
  }

  Future<void> invalidate() async {
    await SecureStore.delete(_tokenKey);
    await SecureStore.delete(_timeKey);
    await SecureStore.delete(_siteKey);
  }

  Future<void> storeToken(String token, {String? siteKey}) async {
    if (token.trim().isEmpty || _submittedTokens.containsKey(token)) return;
    await SecureStore.write(_tokenKey, token);
    await SecureStore.write(
      _timeKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await SecureStore.write(_siteKey, siteKey ?? _keyFor('', null));
    // A late warming/notification callback must not put a submitted token back.
    if (_submittedTokens.containsKey(token)) await invalidate();
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
    if (!canShowUi || isShowing || _warming != null || _layoutAccess != null) {
      return;
    }
    late final Future<void> warming;
    warming =
        () async {
          try {
            final siteKey = _keyFor('', null);
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
              siteKey: siteKey,
            );
            if (token != null && token.isNotEmpty) {
              await storeToken(token, siteKey: siteKey);
            }
          } catch (_) {
            // Silent background warm; keep app undisturbed
          }
        }().whenComplete(() {
          if (identical(_warming, warming)) _warming = null;
        });
    _warming = warming;
    unawaited(warming);
  }

  String _keyFor(String label, String? explicitKey) {
    final purpose = label == 'Railway login' ? 'sign_in' : 'seat_layout';
    return explicitKey ??
        AppConfig.instance.siteKey(purpose) ??
        (purpose == 'sign_in'
            ? '0x4AAAAAAB5VTjZ90pUxRuXR'
            : TurnstileSession.defaultSiteKey);
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
    final targetKey = _keyFor(label, siteKey);
    final running = _inflight;
    if (running != null) {
      if (_inflightSiteKey == targetKey) return running;
      // Login and seat-layout tokens belong to different widgets. Sharing a
      // pending challenge across these purposes submits a token for the wrong key.
      return running.then(
        (_) => acquire(
          label: label,
          forceFresh: true,
          siteKey: targetKey,
          allowPrompt: allowPrompt,
        ),
      );
    }

    late final Future<String?> f;
    f = _acquire(label, forceFresh, targetKey, allowPrompt).whenComplete(() {
      if (identical(_inflight, f)) {
        _inflight = null;
        _inflightSiteKey = null;
        _route = null;
        _navigator = null;
      }
    });
    _inflight = f;
    _inflightSiteKey = targetKey;
    return f;
  }

  Future<String?> _acquire(
    String label,
    bool forceFresh, [
    String? siteKey,
    bool allowPrompt = true,
  ]) async {
    // Capture a pending silent execution before any async storage/navigation.
    final targetKey = _keyFor(label, siteKey);
    final session = TurnstileSession.instance;
    final pending = session.generating
        ? session.generate(targetKey)
        : (forceFresh && workerAcquire == null && canShowUi
              ? session.generateWhenAttached(targetKey)
              : null);
    if (forceFresh) {
      await invalidate();
    } else {
      final cached = label == 'Railway login' ? null : await takeCachedToken();
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
  /// An unused prepared token with at least 30 seconds of lifetime is consumed
  /// immediately. Explicit rejection gets one fresh-token retry while open.
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
    // The warming owner must finish storing its result before it can be taken.
    // Joining acquire() directly lets that owner cache a token AFTER submission.
    final warming = _warming;
    if (warming != null) await warming;
    for (var attempt = 0; attempt < 2; attempt++) {
      final handedOff = attempt == 0 ? await takeCachedToken() : null;
      workerPromptPresented = false;
      final token =
          handedOff ??
          (canShowUi || workerAcquire != null
              ? await acquire(
                  label: label,
                  forceFresh: true,
                  allowPrompt: allowPrompt,
                )
              : null);
      if (token == null || token.trim().isEmpty) {
        throw SeatLayoutChallenge(
          verificationAttempted:
              attempt > 0 ||
              workerPromptPresented ||
              (allowPrompt && canShowUi),
          requiresForeground: !_canRefreshWhileOpen,
        );
      }
      final now = DateTime.now();
      _submittedTokens.removeWhere(
        (_, sentAt) => now.difference(sentAt) >= maxTokenAge,
      );
      if (_submittedTokens.containsKey(token)) {
        await invalidate();
        if (attempt == 0) continue;
        throw SeatLayoutChallenge(
          verificationAttempted: true,
          requiresForeground: !_canRefreshWhileOpen,
        );
      }
      // Claim before I/O: a timeout can still mean Railway consumed the token.
      _submittedTokens[token] = now;
      try {
        return await run(token);
      } on SeatLayoutChallenge catch (error) {
        await invalidate();
        if (error.tokenRejected && attempt == 0) {
          if (!_canRefreshWhileOpen) {
            throw const SeatLayoutChallenge(
              verificationAttempted: true,
              tokenRejected: true,
              requiresForeground: true,
            );
          }
          // Refresh only for an explicit token rejection. 429s, network errors
          // and all booking mutations retain their own backoff/outcome rules.
          continue;
        }
        throw SeatLayoutChallenge(
          verificationAttempted: true,
          tokenRejected: error.tokenRejected,
          requiresForeground: error.requiresForeground || !_canRefreshWhileOpen,
        );
      }
    }
    throw const SeatLayoutChallenge(verificationAttempted: true);
  }
}
