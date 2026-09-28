import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/secure_store.dart';
import '../utils/app_theme.dart';

class TurnstileSheet extends StatefulWidget {
  const TurnstileSheet({super.key});

  /// Shows the Turnstile verification sheet and returns the token if successful.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TurnstileSheet(),
    );
  }

  @override
  State<TurnstileSheet> createState() => _TurnstileSheetState();
}

class _TurnstileSheetState extends State<TurnstileSheet> {
  WebViewController? _controller;
  bool _loading = true;
  String? _statusText = 'Contacting Railway security...';
  Timer? _timeoutTimer;

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
              el.style.padding = '10px';
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
                // Try visible sitekey if invisible fails
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
    _initController();
    _timeoutTimer = Timer(const Duration(seconds: 18), () {
      if (mounted && _loading) {
        setState(() {
          _statusText = 'Verification is taking longer than usual. You can continue on the official booking page.';
        });
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _initController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..addJavaScriptChannel(
        'TurnstileBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          try {
            final raw = msg.message;
            if (raw.contains('SUCCESS')) {
              // Extract token
              final regex = RegExp(r'"token"\s*:\s*"([^"]+)"');
              final match = regex.firstMatch(raw);
              final token = match?.group(1);
              if (token != null && token.isNotEmpty && mounted) {
                SecureStore.write('rail_cft_token', token);
                Navigator.of(context).pop(token);
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
                _statusText = 'Verifying security check...';
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
    final bg = isDark ? const Color(0xFF1E2430) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Railway Security Check',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                    Text(
                      'Cloudflare verification required to view seats',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 140,
              child: Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!),
                  if (_loading)
                    Container(
                      color: bg,
                      child: const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _statusText ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open Official Booking Page Instead'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
