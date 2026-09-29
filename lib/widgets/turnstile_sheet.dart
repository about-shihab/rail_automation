import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/secure_store.dart';
import '../utils/app_theme.dart';

/// Modal popup dialog that displays Bangladesh Railway's Cloudflare Turnstile verification
/// directly over the active app screen so the user can verify with one tap.
class TurnstileDialog extends StatefulWidget {
  const TurnstileDialog({super.key});

  static bool _isShowing = false;
  static bool get isShowing => _isShowing;

  /// Shows the Turnstile verification popup dialog over the entire app.
  static Future<String?> show(BuildContext context) async {
    if (_isShowing) return null;
    _isShowing = true;
    try {
      HapticFeedback.mediumImpact();
      return await showDialog<String>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        builder: (_) => const TurnstileDialog(),
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  State<TurnstileDialog> createState() => _TurnstileDialogState();
}

/// Backwards-compatible alias for existing callers.
class TurnstileSheet extends StatelessWidget {
  const TurnstileSheet({super.key});

  static bool get isShowing => TurnstileDialog.isShowing;
  static Future<String?> show(BuildContext context) => TurnstileDialog.show(context);

  @override
  Widget build(BuildContext context) => const TurnstileDialog();
}

enum _Phase { loading, ready, success, error }

class _TurnstileDialogState extends State<TurnstileDialog> {
  static const _loginUrl = 'https://eticket.railway.gov.bd/login';

  late final WebViewController _controller;
  _Phase _phase = _Phase.loading;
  String? _error;
  Timer? _loadTimeout;
  bool _dark = false;

  // Raw string: no Dart interpolation. __THEME__ is substituted at runtime.
  static const _script = r'''
(function () {
  function post(o) { try { TurnstileBridge.postMessage(JSON.stringify(o)); } catch (e) {} }
  if (window.__rsTs) { if (window.__rsRender) window.__rsRender(); return; }
  window.__rsTs = true;
  var KEYS = ['0x4AAAAAACNkZ_TxQr_zpcZW', '0x4AAAAAAB5VTjZ90pUxRuXR'];
  var keyIdx = 0, widgetId = null;
  var st = document.createElement('style');
  st.textContent = 'html,body{background:transparent!important;overflow:hidden!important}' +
    'body{display:none!important}' +
    '#rs-ts{position:fixed;left:0;top:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center}';
  document.head.appendChild(st);
  var box = document.createElement('div');
  box.id = 'rs-ts';
  document.documentElement.appendChild(box);

  function render() {
    if (widgetId !== null) { try { turnstile.remove(widgetId); } catch (e) {} widgetId = null; }
    box.innerHTML = '';
    try {
      widgetId = turnstile.render(box, {
        sitekey: KEYS[keyIdx],
        theme: '__THEME__',
        retry: 'auto',
        'refresh-expired': 'auto',
        callback: function (t) { post({ status: 'SUCCESS', token: t }); },
        'error-callback': function (c) {
          if (keyIdx < KEYS.length - 1) { keyIdx++; setTimeout(render, 300); }
          else { post({ status: 'ERROR', message: String(c) }); }
          return true;
        },
        'expired-callback': function () { post({ status: 'READY' }); },
        'timeout-callback': function () { post({ status: 'READY' }); }
      });
      post({ status: 'READY' });
    } catch (e) { post({ status: 'ERROR', message: String(e) }); }
  }
  window.__rsRender = render;

  if (window.turnstile && window.turnstile.render) { render(); return; }
  var s = document.createElement('script');
  s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  s.async = true;
  s.onload = render;
  s.onerror = function () { post({ status: 'ERROR', message: 'Could not reach Cloudflare' }); };
  document.head.appendChild(s);
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('TurnstileBridge', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!mounted || _phase == _Phase.success) return;
          _controller.runJavaScript(
              _script.replaceAll('__THEME__', _dark ? 'dark' : 'light'));
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            _fail('No connection to Railway. Check your internet and retry.');
          }
        },
      ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final d = Theme.of(context).brightness == Brightness.dark;
    if (_phase == _Phase.loading && _loadTimeout == null) {
      _dark = d;
      _load();
    }
  }

  void _load() {
    _loadTimeout?.cancel();
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    _controller.loadRequest(Uri.parse(_loginUrl));
    _loadTimeout = Timer(const Duration(seconds: 25), () {
      if (mounted && _phase == _Phase.loading) {
        _fail('Verification is taking too long. Tap Retry.');
      }
    });
  }

  void _fail(String msg) {
    _loadTimeout?.cancel();
    if (!mounted || _phase == _Phase.success) return;
    setState(() {
      _phase = _Phase.error;
      _error = msg;
    });
  }

  Future<void> _onMessage(JavaScriptMessage msg) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    switch (data['status']) {
      case 'READY':
        _loadTimeout?.cancel();
        if (_phase != _Phase.success) setState(() => _phase = _Phase.ready);
        break;
      case 'SUCCESS':
        final token = data['token'] as String?;
        if (token == null || token.isEmpty) return;
        _loadTimeout?.cancel();
        HapticFeedback.heavyImpact();
        await SecureStore.write('rail_cft_token', token);
        await SecureStore.write(
            'rail_cft_token_time', DateTime.now().millisecondsSinceEpoch.toString());
        if (!mounted) return;
        setState(() => _phase = _Phase.success);
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop(token);
        break;
      case 'ERROR':
        _fail('Verification failed to load (${data['message'] ?? 'unknown'}). Tap Retry.');
        break;
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = _phase == _Phase.success;
    final isErr = _phase == _Phase.error;

    final title = switch (_phase) {
      _Phase.success => 'Verification Passed!',
      _Phase.error => 'Verification Needed',
      _ => 'Security Verification',
    };
    final subtitle = switch (_phase) {
      _Phase.loading => 'Connecting to Bangladesh Railway security check…',
      _Phase.ready => 'Please tap the verification box below to continue booking.',
      _Phase.success => 'Security check passed! Resuming auto-booking…',
      _Phase.error => _error ?? 'Something went wrong. Please tap Retry.',
    };

    return PopScope(
      canPop: true,
      child: Center(
        child: SingleChildScrollView(
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            elevation: 0,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: AppColors.surface(isDark),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: ok
                      ? AppColors.success
                      : isErr
                          ? AppColors.error
                          : AppColors.primary.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (ok
                            ? AppColors.success
                            : isErr
                                ? AppColors.error
                                : AppColors.primary)
                        .withValues(alpha: 0.22),
                    blurRadius: 30,
                    spreadRadius: 2,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (ok
                                  ? AppColors.success
                                  : isErr
                                      ? AppColors.error
                                      : AppColors.primary)
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          ok
                              ? Icons.check_circle_rounded
                              : isErr
                                  ? Icons.error_outline_rounded
                                  : Icons.shield_rounded,
                          color: ok
                              ? AppColors.success
                              : isErr
                                  ? AppColors.error
                                  : AppColors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary(isDark),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (ok ? AppColors.success : AppColors.primary)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Turnstile',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: ok
                                          ? AppColors.success
                                          : AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Bangladesh Railway Verification',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Information banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder(isDark)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.textMuted(isDark),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppColors.textSecondary(isDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Turnstile Challenge WebView box
                  Container(
                    height: 105,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.cardBg(isDark),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ok
                            ? AppColors.success
                            : isErr
                                ? AppColors.error
                                : AppColors.cardBorder(isDark),
                        width: ok ? 2.0 : 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: Opacity(
                              opacity: _phase == _Phase.ready ? 1 : 0,
                              child: WebViewWidget(controller: _controller),
                            ),
                          ),
                          if (_phase == _Phase.loading)
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.6),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Loading verification…',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted(isDark),
                                  ),
                                ),
                              ],
                            ),
                          if (ok)
                            const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: AppColors.success, size: 40),
                                SizedBox(height: 4),
                                Text(
                                  'Verified!',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          if (isErr)
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.wifi_off_rounded,
                                    color: AppColors.textMuted(isDark), size: 28),
                                const SizedBox(height: 4),
                                Text(
                                  'Failed to connect',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted(isDark),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: ok ? null : _load,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
