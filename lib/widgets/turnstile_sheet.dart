import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/overlay_service.dart';
import '../services/secure_store.dart';
import '../utils/app_theme.dart';

/// Modal popup dialog that displays Bangladesh Railway's Cloudflare Turnstile verification
/// directly over the active app screen so the user can verify with one tap.
class TurnstileDialog extends StatefulWidget {
  /// Optional context shown as subtitle, e.g. "SUBARNA EXPRESS · SNIGDHA".
  /// When set the dialog shows "Human check needed" as title.
  final String contextLabel;

  const TurnstileDialog({super.key, this.contextLabel = ''});

  static bool _isShowing = false;
  static bool get isShowing => _isShowing;
  static BuildContext? _activeContext;

  static void dismiss() {
    if (_isShowing && _activeContext != null && _activeContext!.mounted) {
      try {
        Navigator.of(_activeContext!, rootNavigator: true).pop();
      } catch (_) {}
    }
    _isShowing = false;
  }

  /// Shows the Turnstile verification popup dialog over the entire app.
  static Future<String?> show(
    BuildContext context, {
    String contextLabel = '',
  }) async {
    // Only one Turnstile prompt (overlay OR in-app dialog) allowed at any time
    if (_isShowing || OverlayService.isShowing) return null;
    _isShowing = true;
    try {
      HapticFeedback.mediumImpact();
      return await showDialog<String>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        builder: (dialogCtx) {
          _activeContext = dialogCtx;
          return TurnstileDialog(contextLabel: contextLabel);
        },
      );
    } finally {
      _isShowing = false;
      _activeContext = null;
    }
  }

  @override
  State<TurnstileDialog> createState() => _TurnstileDialogState();
}

/// Backwards-compatible alias for existing callers.
class TurnstileSheet extends StatelessWidget {
  const TurnstileSheet({super.key});

  static bool get isShowing => TurnstileDialog.isShowing;
  static Future<String?> show(BuildContext context, {String contextLabel = ''}) =>
      TurnstileDialog.show(context, contextLabel: contextLabel);

  @override
  Widget build(BuildContext context) => const TurnstileDialog();
}

enum _Phase { loading, ready, success, error }

class _TurnstileDialogState extends State<TurnstileDialog> with SingleTickerProviderStateMixin {
  static const _loginUrl = 'https://eticket.railway.gov.bd/login';

  WebViewController? _controller;
  _Phase _phase = _Phase.loading;
  String? _error;
  Timer? _loadTimeout;
  bool _dark = false;
  late final AnimationController _boardingCtrl;
  late final Animation<double> _boardingAnim;

  bool get _hasContext => widget.contextLabel.isNotEmpty;

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
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _boardingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (!isTest) {
      _boardingCtrl.repeat();
    }
    _boardingAnim = CurvedAnimation(parent: _boardingCtrl, curve: Curves.easeInOut);

    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel('TurnstileBridge', onMessageReceived: _onMessage)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted || _phase == _Phase.success) return;
            _controller?.runJavaScript(
                _script.replaceAll('__THEME__', _dark ? 'dark' : 'light'));
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) {
              _fail('No connection to Railway. Check your internet and retry.');
            }
          },
        ));
    } catch (_) {}
  }

  @override
  void dispose() {
    _boardingCtrl.dispose();
    _loadTimeout?.cancel();
    super.dispose();
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
    try {
      _controller?.loadRequest(Uri.parse(_loginUrl));
    } catch (_) {}
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = _phase == _Phase.success;
    final isErr = _phase == _Phase.error;

    final title = switch (_phase) {
      _Phase.success => 'Ticket Reserved • Ready to Pay!',
      _Phase.error   => 'Verification Needed',
      _              => 'Processing Ticket • Boarding',
    };
    final subtitle = switch (_phase) {
      _Phase.loading => 'Connecting to Bangladesh Railway security check…',
      _Phase.ready   => _hasContext
          ? 'Select your seat type to continue — ${widget.contextLabel}'
          : 'Please tap the verification box below to continue booking.',
      _Phase.success => 'Security check passed! Resuming auto-booking…',
      _Phase.error   => _error ?? 'Something went wrong. Please tap Retry.',
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
                                  : Icons.train_rounded,
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
                                    ok ? 'CONFIRMED' : 'BOARDING PASS',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
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
                              'Bangladesh Railway Reservation • Platform 1',
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
                  const SizedBox(height: 12),
                  // Animated train boarding graphic (makes user feel processing ticket)
                  _TrainBoardingGraphic(
                    animation: _boardingAnim,
                    isVerified: ok,
                    isDark: isDark,
                    contextLabel: widget.contextLabel,
                  ),
                  _TicketDivider(isDark: isDark),
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
                          if (_controller != null)
                            Positioned.fill(
                              child: Opacity(
                                opacity: _phase == _Phase.ready ? 1 : 0,
                                child: WebViewWidget(controller: _controller!),
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

class _TicketDivider extends StatelessWidget {
  final bool isDark;
  const _TicketDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white24 : Colors.black12;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final boxWidth = constraints.constrainWidth();
                const dashWidth = 5.0;
                const dashSpace = 4.0;
                final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(dashCount, (_) {
                    return SizedBox(
                      width: dashWidth,
                      height: 1.2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: color),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainBoardingGraphic extends StatelessWidget {
  final Animation<double> animation;
  final bool isVerified;
  final bool isDark;
  final String contextLabel;

  const _TrainBoardingGraphic({
    required this.animation,
    required this.isVerified,
    required this.isDark,
    this.contextLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 118,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF071A12), const Color(0xFF0F2E23), const Color(0xFF08140F)]
                    : [const Color(0xFF1B3B2B), const Color(0xFF28543E), const Color(0xFF153324)],
              ),
              border: Border.all(
                color: isVerified
                    ? AppColors.success.withValues(alpha: 0.7)
                    : AppColors.primary.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Stack(
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 118),
                  painter: _TrainBoardingPainter(
                    t: animation.value,
                    isVerified: isVerified,
                    isDark: isDark,
                  ),
                ),
                // Top status pill (processing ticket / boarded)
                Positioned(
                  top: 8,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isVerified
                            ? AppColors.success.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isVerified ? AppColors.success : const Color(0xFFFFB300),
                            boxShadow: [
                              BoxShadow(
                                color: (isVerified ? AppColors.success : const Color(0xFFFFB300))
                                    .withValues(alpha: 0.8),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isVerified ? 'TICKET BOARDED' : 'PROCESSING TICKET',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: isVerified ? AppColors.success : const Color(0xFFFFD54F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Top right train / context badge
                Positioned(
                  top: 8,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.train_rounded, color: Colors.white70, size: 11),
                        const SizedBox(width: 4),
                        Text(
                          contextLabel.isNotEmpty
                              ? contextLabel.toUpperCase()
                              : 'BANGLADESH RAILWAY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrainBoardingPainter extends CustomPainter {
  final double t; // 0.0 to 1.0
  final bool isVerified;
  final bool isDark;

  _TrainBoardingPainter({
    required this.t,
    required this.isVerified,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final groundY = h - 14.0;
    final platformEdgeX = w * 0.44;
    final trainLeftX = w * 0.38;
    final doorLeftX = w * 0.60;
    final doorRightX = w * 0.74;

    // 1. Station platform overhead lamp light cone
    final lampX = w * 0.22;
    final lampY = 16.0;
    final lightPath = Path()
      ..moveTo(lampX, lampY)
      ..lineTo(lampX - 45, groundY - 14)
      ..lineTo(lampX + 55, groundY - 14)
      ..close();
    canvas.drawPath(
      lightPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFE082).withValues(alpha: 0.22),
            const Color(0xFFFFE082).withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(lampX - 45, lampY, 100, groundY - 14 - lampY)),
    );

    // Lamp fixture
    final lampPaint = Paint()..color = const Color(0xFFD4AF37);
    canvas.drawLine(
      Offset(lampX, 0),
      Offset(lampX, lampY),
      Paint()..color = const Color(0xFF6B7280)..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(lampX, lampY), 3.5, lampPaint);
    canvas.drawCircle(
      Offset(lampX, lampY),
      6.0,
      Paint()..color = const Color(0xFFFFE082).withValues(alpha: 0.4),
    );

    // 2. Track & Rails
    final ballastPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Rect.fromLTWH(0, groundY - 4, w, h - groundY + 4), ballastPaint);

    final railPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, groundY), Offset(w, groundY), railPaint);
    canvas.drawLine(Offset(0, groundY + 6), Offset(w, groundY + 6), railPaint);

    // Sleepers (ties)
    final sleeperPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 2.5;
    for (double sx = 6; sx < w; sx += 18) {
      canvas.drawLine(Offset(sx, groundY - 2), Offset(sx, groundY + 8), sleeperPaint);
    }

    // 3. Bangladesh Railway Train Coach (Green & Red)
    final coachTop = 26.0;
    final coachBottom = groundY - 4.0;
    final coachRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(trainLeftX, coachTop, w + 30, coachBottom),
      topLeft: const Radius.circular(10),
      bottomLeft: const Radius.circular(4),
    );

    // Coach body
    final coachPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF006A4E), Color(0xFF004D38)],
      ).createShader(Rect.fromLTRB(trainLeftX, coachTop, w + 30, coachBottom));
    canvas.drawRRect(coachRect, coachPaint);

    // Crimson red Bangladesh Railway stripe
    final stripeRect = Rect.fromLTRB(trainLeftX, 52, w + 30, 58);
    canvas.drawRect(stripeRect, Paint()..color = const Color(0xFFE53935));

    // Roof curve & AC pods
    final roofRect = Rect.fromLTRB(trainLeftX - 1, coachTop - 3, w + 30, coachTop + 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(3)),
      Paint()..color = const Color(0xFF1F2937),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(trainLeftX + 25, coachTop - 5, 28, 4), const Radius.circular(2)),
      Paint()..color = const Color(0xFF374151),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(trainLeftX + 85, coachTop - 5, 34, 4), const Radius.circular(2)),
      Paint()..color = const Color(0xFF374151),
    );

    // Windows with warm light glow
    void drawWindow(double wx) {
      final winRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(wx, 36, 26, 14),
        const Radius.circular(3.5),
      );
      canvas.drawRRect(winRect, Paint()..color = const Color(0xFF0F172A));
      canvas.drawRRect(
        winRect.deflate(1.2),
        Paint()..color = const Color(0xFFFEF08A),
      );
      canvas.drawCircle(Offset(wx + 9, 43), 2.5, Paint()..color = const Color(0xFF004D38).withValues(alpha: 0.6));
      canvas.drawRect(Rect.fromLTWH(wx + 6.5, 45.5, 5, 3), Paint()..color = const Color(0xFF004D38).withValues(alpha: 0.6));
    }

    drawWindow(trainLeftX + 16);
    if (doorRightX + 10 < w) {
      drawWindow(doorRightX + 10);
    }

    // Doorway opening (illuminated passenger entrance)
    final doorRect = Rect.fromLTRB(doorLeftX, coachTop + 4, doorRightX, coachBottom);
    canvas.drawRRect(
      RRect.fromRectAndRadius(doorRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFFFFBEB),
    );
    // Doorway entrance shadow & steps
    canvas.drawRect(
      Rect.fromLTRB(doorLeftX, coachBottom - 6, doorRightX, coachBottom),
      Paint()..color = const Color(0xFF78350F).withValues(alpha: 0.35),
    );
    canvas.drawLine(
      Offset(doorLeftX, coachBottom - 5),
      Offset(doorRightX, coachBottom - 5),
      Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 2.0,
    );
    canvas.drawLine(
      Offset(doorLeftX, coachBottom - 2),
      Offset(doorRightX, coachBottom - 2),
      Paint()..color = const Color(0xFF64748B)..strokeWidth = 2.0,
    );

    // Warm door light cast onto platform
    final doorLightPath = Path()
      ..moveTo(doorLeftX, coachBottom - 2)
      ..lineTo(doorLeftX - 18, groundY - 14)
      ..lineTo(doorRightX + 4, groundY - 14)
      ..lineTo(doorRightX, coachBottom - 2)
      ..close();
    canvas.drawPath(
      doorLightPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFEF08A).withValues(alpha: 0.45),
            const Color(0xFFFEF08A).withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromLTWH(doorLeftX - 18, coachBottom - 2, 40, 20)),
    );

    // Train bogie wheels
    final wheelPaint = Paint()..color = const Color(0xFF475569);
    final wheelRimPaint = Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    void drawWheel(double wx) {
      canvas.drawCircle(Offset(wx, groundY - 1), 6, wheelPaint);
      canvas.drawCircle(Offset(wx, groundY - 1), 6, wheelRimPaint);
      canvas.drawCircle(Offset(wx, groundY - 1), 2, Paint()..color = const Color(0xFFCBD5E1));
    }
    drawWheel(trainLeftX + 18);
    drawWheel(trainLeftX + 34);
    if (doorRightX + 30 < w) {
      drawWheel(doorRightX + 22);
      drawWheel(doorRightX + 38);
    }

    // 4. Station Platform
    final platformTopY = groundY - 14.0;
    final platformPath = Path()
      ..moveTo(0, platformTopY)
      ..lineTo(platformEdgeX, platformTopY)
      ..lineTo(platformEdgeX, groundY + 2)
      ..lineTo(0, groundY + 2)
      ..close();
    canvas.drawPath(
      platformPath,
      Paint()..color = isDark ? const Color(0xFF263238) : const Color(0xFF37474F),
    );

    // Platform tactile yellow warning edge
    canvas.drawRect(
      Rect.fromLTRB(platformEdgeX - 6, platformTopY, platformEdgeX, platformTopY + 3),
      Paint()..color = const Color(0xFFFFCA28),
    );
    // Platform paver lines
    final paverPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    for (double px = 14; px < platformEdgeX - 8; px += 20) {
      canvas.drawLine(Offset(px, platformTopY), Offset(px, groundY + 2), paverPaint);
    }

    // 5. Passenger Entering the Train (Animation)
    final startX = w * 0.08;
    final targetX = doorLeftX + (doorRightX - doorLeftX) * 0.45;

    double passengerX;
    double passengerY;
    double opacity = 1.0;
    bool isSteppingUp = false;
    bool isInsideTrain = false;

    if (t < 0.62) {
      // Walking on platform towards door
      final progress = t / 0.62;
      passengerX = startX + (targetX - startX) * progress;
      final walkBob = (math.sin(t * 28.0).abs() * 2.2);
      passengerY = platformTopY - walkBob;
    } else if (t < 0.82) {
      // Stepping up into train doorway
      isSteppingUp = true;
      final stepProgress = (t - 0.62) / 0.20;
      passengerX = targetX;
      passengerY = platformTopY - (stepProgress * 10.0);
    } else if (t < 0.94) {
      // Inside train doorway
      isInsideTrain = true;
      passengerX = targetX;
      passengerY = platformTopY - 10.0;
    } else {
      // Reset fade
      final fadeProgress = (t - 0.94) / 0.06;
      opacity = (1.0 - fadeProgress).clamp(0.0, 1.0);
      passengerX = targetX;
      passengerY = platformTopY - 10.0;
    }

    if (isVerified) {
      passengerX = targetX;
      passengerY = platformTopY - 10.0;
      isInsideTrain = true;
      opacity = 1.0;
    }

    // Draw passenger silhouette
    final passengerColor = (isInsideTrain
        ? const Color(0xFF004D38)
        : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFFF8FAFC))
    ).withValues(alpha: opacity);

    final pPaint = Paint()..color = passengerColor;

    // Head
    canvas.drawCircle(Offset(passengerX, passengerY - 24), 3.8, pPaint);
    // Torso / Jacket
    final torsoRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(passengerX, passengerY - 14), width: 7.5, height: 13),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(torsoRect, pPaint);

    // Backpack / Travel bag
    final bagPaint = Paint()
      ..color = (isInsideTrain ? const Color(0xFF065F46) : const Color(0xFFF59E0B)).withValues(alpha: opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(passengerX - 6.5, passengerY - 18, 4.0, 7.5),
        const Radius.circular(1.5),
      ),
      bagPaint,
    );

    // Legs animation
    final legPaint = Paint()
      ..color = passengerColor
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    if (!isInsideTrain) {
      final legSwing = isSteppingUp ? (math.sin(t * 15.0) * 2.0) : (math.sin(t * 28.0) * 4.5);
      canvas.drawLine(
        Offset(passengerX - 1.5, passengerY - 7),
        Offset(passengerX - 1.5 + legSwing, passengerY),
        legPaint,
      );
      canvas.drawLine(
        Offset(passengerX + 1.5, passengerY - 7),
        Offset(passengerX + 1.5 - legSwing, passengerY),
        legPaint,
      );
    }

    // Golden ticket/star sparkle when passenger enters or verified
    if (isInsideTrain || isVerified) {
      final sparkleX = targetX;
      final sparkleY = coachTop + 14.0;
      final sparkleRadius = isVerified ? 9.0 : 6.0;
      final haloPaint = Paint()
        ..color = (isVerified ? AppColors.success : const Color(0xFFFFD54F)).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(sparkleX, sparkleY), sparkleRadius * 1.5, haloPaint);

      final starPaint = Paint()
        ..color = isVerified ? AppColors.success : const Color(0xFFFFD54F)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(sparkleX, sparkleY), sparkleRadius * 0.7, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrainBoardingPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.isVerified != isVerified ||
        oldDelegate.isDark != isDark;
  }
}
