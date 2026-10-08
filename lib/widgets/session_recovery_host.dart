import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/language_service.dart';
import '../services/login_recovery_required.dart';
import '../services/railway_credentials_rejected.dart';
import '../services/session_recovery.dart';
import '../services/web_login_support.dart';
import '../services/web_session_service.dart';
import '../services/secure_store.dart';
import '../utils/app_theme.dart';
import 'fancy_train_loader.dart';

/// Mounted once above the Navigator. While [SessionRecovery] has a job it covers
/// the whole app with a loading screen and signs in underneath it using a real
/// WebView, then disappears. Failures are handed back to the caller, which opens
/// the visible login screen.
class SessionRecoveryHost extends StatefulWidget {
  const SessionRecoveryHost({super.key, required this.child});
  final Widget child;

  @override
  State<SessionRecoveryHost> createState() => _SessionRecoveryHostState();
}

class _SessionRecoveryHostState extends State<SessionRecoveryHost> {
  final _service = SessionRecovery.instance;

  @override
  void initState() {
    super.initState();
    _service.hostAttached = true;
  }

  @override
  void dispose() {
    _service.hostAttached = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final job = _service.job;
          if (job == null) return const SizedBox.shrink();
          return Positioned.fill(
            child: _RecoveryRunner(key: ValueKey(job.id), job: job),
          );
        },
      ),
    ],
  );
}

class _RecoveryRunner extends StatefulWidget {
  const _RecoveryRunner({super.key, required this.job});
  final RecoveryJob job;

  @override
  State<_RecoveryRunner> createState() => _RecoveryRunnerState();
}

class _RecoveryRunnerState extends State<_RecoveryRunner> {
  final _service = SessionRecovery.instance;
  WebViewController? _controller;
  Timer? _poll;
  bool _done = false;
  bool _checking = false;

  RecoveryJob get job => widget.job;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _done = true;
    _poll?.cancel();
    super.dispose();
  }

  void _fail(Object error) {
    if (_done) return;
    _done = true;
    _poll?.cancel();
    _service.fail(job, error);
  }

  Future<void> _start() async {
    try {
      // Start from a signed-out web view so a stale or revoked web session can
      // never be mistaken for a fresh login.
      await WebSessionService.clear();
      if (!mounted || _done) return;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
        )
        ..addJavaScriptChannel(
          'RailBridge',
          onMessageReceived: (m) => _onBridge(m.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (_done) return NavigationDecision.prevent;
              // Sub-frames (Cloudflare Turnstile) must load.
              if (!request.isMainFrame) return NavigationDecision.navigate;
              return WebSessionService.isRailwayUrl(request.url)
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
            onPageFinished: _onPageFinished,
            onWebResourceError: (error) {
              final type = error.errorType;
              final offline =
                  type == WebResourceErrorType.hostLookup ||
                  type == WebResourceErrorType.connect ||
                  type == WebResourceErrorType.timeout;
              if (offline && error.isForMainFrame != false) {
                _fail(
                  const LoginRecoveryRequired(
                    'No connection to Railway. Please sign in again.',
                  ),
                );
              }
            },
          ),
        );
      setState(() => _controller = controller);
      await controller.loadRequest(Uri.parse(RailLoginScript.loginUrl));
    } catch (_) {
      _fail(
        const LoginRecoveryRequired(
          'Could not start Railway login. Please sign in again.',
        ),
      );
    }
  }

  Future<void> _onPageFinished(String url) async {
    final c = _controller;
    if (c == null || _done || !WebSessionService.isRailwayUrl(url)) return;
    try {
      await c.runJavaScript(RailLoginScript.interceptors);
      await c.runJavaScript(
        RailLoginScript.autofill(job.phone, job.password, submit: true),
      );
    } catch (_) {}
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _checkStorage());
  }

  Future<void> _checkStorage() async {
    final c = _controller;
    if (c == null || _done || _checking) return;
    _checking = true;
    try {
      if (!WebSessionService.isRailwayUrl(await c.currentUrl())) return;
      final result = await c.runJavaScriptReturningResult(
        RailLoginScript.readSession,
      );
      final payload = WebLoginPayload.fromJsResult(result);
      if (payload != null) await _maybeFinish(payload);
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  Future<void> _onBridge(String raw) async {
    if (_done || !mounted) return;
    if (!WebSessionService.isRailwayUrl(await _controller?.currentUrl())) {
      return;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      switch (map['type']) {
        case 'HOLD_CONFIG':
          final seconds = map['seconds'];
          if (seconds is int && seconds > 0 && seconds <= 3600) {
            await SecureStore.write('rail_hold_seconds', '$seconds');
          }
        case 'AUTH_SUCCESS' || 'STORAGE_TOKEN':
          await _maybeFinish(WebLoginPayload.fromMap(map));
        case 'AUTH_ERROR':
          final body = map['body']?.toString() ?? '';
          if (RailwayCredentialsRejected.isResponse(body)) {
            _fail(const RailwayCredentialsRejected());
          } else {
            _fail(
              LoginRecoveryRequired(
                'Railway sign-in failed (${map['status']}). '
                'Please sign in again.',
              ),
            );
          }
      }
    } catch (_) {}
  }

  Future<void> _maybeFinish(WebLoginPayload payload) async {
    if (_done || !payload.hasUsableToken) return;
    final bare = payload.token.startsWith('Bearer ')
        ? payload.token.substring(7)
        : payload.token;
    // The token Railway just rejected is not a recovery.
    if (bare == job.rejectedToken) return;
    _done = true;
    _poll?.cancel();
    try {
      final session = await WebLoginPersistence.save(
        payload,
        previous: job.previous,
        fallbackPhone: job.phone,
        fallbackPassword: job.password,
      );
      _service.complete(job, session);
    } catch (_) {
      _service.fail(
        job,
        const LoginRecoveryRequired(
          'Could not save the new Railway session. Please sign in again.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The real login page runs here, fully laid out but covered.
        if (_controller != null) WebViewWidget(controller: _controller!),
        // Opaque cover: swallows every touch and hides the page.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Material(
            color: isDark ? AppColors.darkBg : Colors.white,
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: FancyTrainLoader(
                      message: lang.tr(
                        'Refreshing your session…',
                        'সেশন নতুন করা হচ্ছে…',
                      ),
                      subMessage: lang.tr(
                        'Signing in to Railway automatically',
                        'রেলওয়েতে স্বয়ংক্রিয়ভাবে সাইন ইন হচ্ছে',
                      ),
                      stage: JourneyAnimationStage.verifying,
                      showCard: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextButton(
                      onPressed: () => _fail(
                        const LoginRecoveryRequired(
                          'Automatic sign-in cancelled.',
                        ),
                      ),
                      child: Text(
                        lang.tr('Sign in manually', 'নিজে সাইন ইন করুন'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
