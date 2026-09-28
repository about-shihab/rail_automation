import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/secure_store.dart';

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
  bool _verified = false;
  bool _requiresInteractiveClick = false;
  String _statusText = 'Solving Railway security challenge in background...';
  int _statusStep = 0;
  Timer? _stepTimer;
  Timer? _timeoutTimer;
  Timer? _interactiveCheckTimer;
  late final AnimationController _pulseController;

  static const String _turnstileScript = '''
    (function() {
      // 1. Inject styling to completely hide the underlying website (forms, headers, footers, logos)
      try {
        var style = document.createElement('style');
        style.innerHTML = `
          * { box-sizing: border-box !important; }
          html, body {
            background: transparent !important;
            background-color: transparent !important;
            margin: 0 !important;
            padding: 0 !important;
            overflow: hidden !important;
            display: flex !important;
            justify-content: center !important;
            align-items: center !important;
            width: 100% !important;
            height: 100% !important;
          }
          /* Strictly hide all Bangladesh Railway login page forms, headers, footers, banners */
          body > *:not(#cf-turnstile-container) {
            display: none !important;
          }
          #cf-turnstile-container {
            display: flex !important;
            justify-content: center !important;
            align-items: center !important;
            margin: 0 auto !important;
            padding: 4px !important;
            background: transparent !important;
          }
          iframe {
            margin: 0 auto !important;
          }
        `;
        document.head.appendChild(style);
      } catch(_) {}

      function initTurnstile() {
        if (window.turnstile) {
          try {
            var el = document.getElementById('cf-turnstile-container');
            if (!el) {
              el = document.createElement('div');
              el.id = 'cf-turnstile-container';
              document.body.prepend(el);
            }
            window.turnstile.render('#cf-turnstile-container', {
              sitekey: '0x4AAAAAACNkZ_TxQr_zpcZW',
              theme: 'dark',
              callback: function(token) {
                if (window.TurnstileBridge) {
                  window.TurnstileBridge.postMessage(JSON.stringify({status: 'SUCCESS', token: token}));
                }
              },
              'error-callback': function(code) {
                try {
                  window.turnstile.render('#cf-turnstile-container', {
                    sitekey: '0x4AAAAAAB5VTjZ90pUxRuXR',
                    theme: 'dark',
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

            // Check if interactive iframe is present
            setTimeout(function() {
              var iframe = document.querySelector('#cf-turnstile-container iframe');
              if (iframe && window.TurnstileBridge) {
                window.TurnstileBridge.postMessage(JSON.stringify({status: 'INTERACTIVE_READY'}));
              }
            }, 1200);

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
      duration: const Duration(milliseconds: 1400),
    );
    if (!isTest) {
      _pulseController.repeat(reverse: true);
    }

    _initController();

    // Rotate telemetry status steps to inform the user
    _stepTimer = Timer.periodic(const Duration(milliseconds: 2200), (t) {
      if (!mounted || _verified) {
        t.cancel();
        return;
      }
      setState(() {
        _statusStep = (_statusStep + 1) % 4;
        switch (_statusStep) {
          case 0:
            _statusText = 'Solving Railway security challenge in background...';
            break;
          case 1:
            _statusText = 'Bypassing Cloudflare Turnstile bot protection...';
            break;
          case 2:
            _statusText = 'Verifying security token with Railway gateway...';
            break;
          case 3:
            _statusText = 'Finalizing verification • Reserving requested seats...';
            break;
        }
      });
    });

    // If Cloudflare requires manual tap, reveal ONLY the checkbox after 4 seconds
    _interactiveCheckTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_verified) {
        setState(() {
          _requiresInteractiveClick = true;
          _statusText = 'Please tap "Verify you are human" below if prompted.';
        });
      }
    });

    _timeoutTimer = Timer(const Duration(seconds: 22), () {
      if (mounted && !_verified) {
        setState(() {
          _statusText = 'Taking longer than expected. Tap Retry to reload.';
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stepTimer?.cancel();
    _timeoutTimer?.cancel();
    _interactiveCheckTimer?.cancel();
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
                HapticFeedback.heavyImpact();
                await SecureStore.write('rail_cft_token', token);
                await SecureStore.write(
                  'rail_cft_token_time',
                  DateTime.now().millisecondsSinceEpoch.toString(),
                );
                setState(() {
                  _verified = true;
                  _statusText = 'Security verified! Reserving your seat now...';
                });
                await Future.delayed(const Duration(milliseconds: 350));
                if (mounted) Navigator.of(context).pop(token);
              }
            } else if (raw.contains('INTERACTIVE_READY') && mounted && !_verified) {
              setState(() {
                _requiresInteractiveClick = true;
                _statusText = 'Tap the checkbox below to complete verification.';
              });
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
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
    // High-contrast modern charcoal / cyber aesthetic inspired by SUST_Codex_2026
    const bgDark = Color(0xFF09090B);
    const cardDark = Color(0xFF121217);
    const borderDark = Color(0xFF27272A);
    const primaryGlow = Color(0xFF00D59B);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? bgDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: _verified
                ? primaryGlow
                : (isDark ? primaryGlow.withValues(alpha: 0.4) : primaryGlow.withValues(alpha: 0.6)),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryGlow.withValues(alpha: isDark ? 0.22 : 0.12),
            blurRadius: 36,
            offset: const Offset(0, -8),
          ),
          const BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, -4)),
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
            width: 40,
            height: 4.5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black12,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Glowing Cyber Badge & Live Indicator
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
                        width: 46 + p * 6,
                        height: 46 + p * 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_verified ? primaryGlow : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.12 + p * 0.14),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _verified
                              ? primaryGlow.withValues(alpha: 0.2)
                              : primaryGlow.withValues(alpha: 0.12),
                          border: Border.all(
                            color: _verified ? primaryGlow : primaryGlow.withValues(alpha: 0.8),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          _verified
                              ? Icons.check_circle_rounded
                              : Icons.shield_rounded,
                          color: _verified ? primaryGlow : primaryGlow,
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
                          _verified ? 'Security Solved!' : 'Securing Your Seats...',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16.5,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryGlow.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: primaryGlow.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: primaryGlow,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'CLOUDFLARE',
                                style: TextStyle(
                                  color: primaryGlow,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _verified
                          ? 'Token acquired. Directing to instant reservation.'
                          : 'Bypassing Railway Turnstile security in background.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
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

          const SizedBox(height: 18),

          // Main Card: PURE LOADING EXPERIENCE (No website or login form shown!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? cardDark : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _verified
                    ? primaryGlow
                    : (isDark ? borderDark : const Color(0xFFE2E8F0)),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                if (!_verified) ...[
                  // Pulse wave & radar spinner
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(primaryGlow),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              _statusText,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // Telemetry Checklist (SUST_Codex_2026 style)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? bgDark.withValues(alpha: 0.6) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildStepRow(
                          icon: Icons.check_circle_rounded,
                          color: primaryGlow,
                          title: 'Train & Seats Selected',
                          done: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 6),
                        _buildStepRow(
                          icon: Icons.sync_rounded,
                          color: const Color(0xFF38BDF8),
                          title: 'Cloudflare Turnstile Verification',
                          done: false,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 6),
                        _buildStepRow(
                          icon: Icons.radio_button_unchecked_rounded,
                          color: isDark ? Colors.white30 : Colors.black26,
                          title: 'Seat Allocation & Payment Lock',
                          done: false,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // If interactive click is required by Cloudflare, display ONLY the isolated centered checkbox
                  if (_requiresInteractiveClick && _controller != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      height: 80,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: WebViewWidget(controller: _controller!),
                      ),
                    ),
                  ] else ...[
                    // Keep WebView offstage/hidden in background so the user NEVER sees the web page!
                    if (_controller != null)
                      SizedBox(
                        width: 0.1,
                        height: 0.1,
                        child: Opacity(
                          opacity: 0.0,
                          child: WebViewWidget(controller: _controller!),
                        ),
                      ),
                  ],
                ] else ...[
                  // Verified State
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle_rounded, color: primaryGlow, size: 28),
                      SizedBox(width: 10),
                      Text(
                        'SECURITY VERIFIED • PROCEEDING',
                        style: TextStyle(
                          color: primaryGlow,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Action row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Verification'),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.black54,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  setState(() {
                    _statusText = 'Restarting Railway security challenge...';
                    _statusStep = 0;
                  });
                  _controller?.reload();
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('Open Railway Page'),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFF67E8F9) : const Color(0xFF0284C7),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required IconData icon,
    required Color color,
    required String title,
    required bool done,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: done ? FontWeight.w600 : FontWeight.w500,
              color: done
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
          ),
        ),
      ],
    );
  }
}
