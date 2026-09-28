import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/secure_store.dart';
import '../utils/app_theme.dart';

class TurnstileSheet extends StatefulWidget {
  const TurnstileSheet({super.key});

  static bool _isShowing = false;
  static bool get isShowing => _isShowing;

  /// Shows the Turnstile verification popup over the app and returns the token if successful.
  static Future<String?> show(BuildContext context) async {
    if (_isShowing) return null;
    _isShowing = true;
    try {
      HapticFeedback.heavyImpact();
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (_) => const TurnstileSheet(),
      );
      return result;
    } finally {
      _isShowing = false;
    }
  }

  @override
  State<TurnstileSheet> createState() => _TurnstileSheetState();
}

class _TurnstileSheetState extends State<TurnstileSheet>
    with SingleTickerProviderStateMixin {
  WebViewController? _controller;
  bool _loading = true;
  bool _verified = false;
  String? _statusText = 'Initializing Railway security verification...';
  Timer? _timeoutTimer;
  late final AnimationController _pulseController;

  static const String _turnstileScript = '''
    (function() {
      function initTurnstile() {
        if (window.turnstile) {
          try {
            var el = document.getElementById('cf-turnstile-container');
            if (!el) {
              el = document.createElement('div');
              el.id = 'cf-turnstile-container';
              el.style.display = 'flex';
              el.style.justifyContent = 'center';
              el.style.alignItems = 'center';
              el.style.padding = '8px';
              document.body.prepend(el);
            }
            window.turnstile.render('#cf-turnstile-container', {
              sitekey: '0x4AAAAAACNkZ_TxQr_zpcZW',
              theme: 'auto',
              callback: function(token) {
                if (window.TurnstileBridge) {
                  window.TurnstileBridge.postMessage(JSON.stringify({status: 'SUCCESS', token: token}));
                }
              },
              'error-callback': function(code) {
                try {
                  window.turnstile.render('#cf-turnstile-container', {
                    sitekey: '0x4AAAAAAB5VTjZ90pUxRuXR',
                    theme: 'auto',
                    callback: function(tok) {
                      if (window.TurnstileBridge) {
                        window.TurnstileBridge.postMessage(JSON.stringify({status: 'SUCCESS', token: tok}));
                      }
                    }
                  });
                } catch(e) {
                  if (window.TurnstileBridge) {
                    window.TurnstileBridge.postMessage(JSON.stringify({status: 'ERROR', message: code}));
                  }
                }
              }
            });
          } catch(e) {
            if (window.TurnstileBridge) {
              window.TurnstileBridge.postMessage(JSON.stringify({status: 'ERROR', message: e.toString()}));
            }
          }
        } else {
          var script = document.createElement('script');
          script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTsApiLoaded';
          window.onTsApiLoaded = initTurnstile;
          document.head.appendChild(script);
        }
      }

      if (document.readyState === 'complete' || document.readyState === 'interactive') {
        initTurnstile();
      } else {
        window.addEventListener('DOMContentLoaded', initTurnstile);
      }
    })();
  ''';

  @override
  void initState() {
    super.initState();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!isTest) {
      _pulseController.repeat(reverse: true);
    }

    _initController();
    _timeoutTimer = Timer(const Duration(seconds: 18), () {
      if (mounted && _loading) {
        setState(() {
          _statusText = 'Verification taking longer than usual. You can retry or open the booking page.';
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _initController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'TurnstileBridge',
        onMessageReceived: (JavaScriptMessage msg) async {
          try {
            final raw = msg.message;
            if (raw.contains('SUCCESS')) {
              final regex = RegExp(r'"token"\s*:\s*"([^"]+)"');
              final match = regex.firstMatch(raw);
              final token = match?.group(1);
              if (token != null && token.isNotEmpty && mounted) {
                HapticFeedback.mediumImpact();
                await SecureStore.write('rail_cft_token', token);
                await SecureStore.write(
                  'rail_cft_token_time',
                  DateTime.now().millisecondsSinceEpoch.toString(),
                );
                setState(() {
                  _verified = true;
                  _statusText = 'Security verified! Reserving your seat now...';
                });
                await Future.delayed(const Duration(milliseconds: 400));
                if (mounted) Navigator.of(context).pop(token);
              }
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _loading = false;
                _statusText = 'Tap the Turnstile checkbox below to verify.';
              });
              _controller?.runJavaScript(_turnstileScript);
            }
          },
        ),
      );

    _controller = controller;
    controller.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF08101E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(
            color: _verified
                ? const Color(0xFF00D59B)
                : (isDark ? const Color(0xFF00D59B).withValues(alpha: 0.35) : const Color(0xFF00D59B).withValues(alpha: 0.45)),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D59B).withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
          const BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Glowing Shield & Urgent Ticket Found Notice
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final p = _pulseController.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 44 + p * 6,
                        height: 44 + p * 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_verified ? const Color(0xFF00D59B) : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.14 + p * 0.12),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _verified
                              ? const Color(0xFF00D59B).withValues(alpha: 0.22)
                              : AppColors.primary.withValues(alpha: 0.18),
                          border: Border.all(
                            color: _verified ? const Color(0xFF00D59B) : AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          _verified
                              ? Icons.check_circle_rounded
                              : Icons.security_rounded,
                          color: _verified ? const Color(0xFF00D59B) : AppColors.primary,
                          size: 22,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Ticket Found!',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            color: AppColors.textPrimary(isDark),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D59B).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF00D59B).withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'URGENT',
                            style: TextStyle(
                              color: Color(0xFF00D59B),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Solve Cloudflare Turnstile to lock in your seats immediately',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(isDark),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: isDark ? Colors.white70 : Colors.black54,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // WebView Container with sleek framed border
          Container(
            height: 156,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF050B14) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _verified
                    ? const Color(0xFF00D59B)
                    : (isDark ? const Color(0xFF1E3A55) : const Color(0xFFCBDCF0)),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!),
                  if (_loading)
                    Container(
                      color: isDark ? const Color(0xFF050B14) : const Color(0xFFF8FAFC),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D59B)),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Loading security challenge...',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_verified)
                    Container(
                      color: const Color(0xFF050B14).withValues(alpha: 0.94),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Color(0xFF00D59B), size: 24),
                            SizedBox(width: 8),
                            Text(
                              'VERIFIED • RESERVING SEAT',
                              style: TextStyle(
                                color: Color(0xFF00D59B),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Status caption
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_verified)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF00D59B),
                  ),
                ),
              Flexible(
                child: Text(
                  _statusText ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _verified
                        ? const Color(0xFF00D59B)
                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Alternative action link
          TextButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open Official Booking Page Instead'),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFF67E8F9) : const Color(0xFF0284C7),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
