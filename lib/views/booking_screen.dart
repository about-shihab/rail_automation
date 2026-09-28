import 'dart:convert';
import '../services/booking_service.dart';
import '../services/secure_store.dart';
import '../services/web_session_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/auth_session.dart';
import '../utils/app_theme.dart';

class BookingScreen extends StatefulWidget {
  final String url;
  const BookingScreen({super.key, required this.url});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      final session = await AuthSession.load();
      if (!WebSessionService.isRailwayUrl(widget.url)) throw StateError('Invalid Railway booking link');
      final reservation = await BookingService.pending();
      bool bootstrapped = false;

      // Sync cookies from session if available
      if (session?.cookie != null && session!.cookie!.isNotEmpty) {
        final cookies = session.cookie!.split(';');
        for (final c in cookies) {
          final parts = c.split('=');
          if (parts.length >= 2) {
            final name = parts[0].trim();
            final value = parts.sublist(1).join('=').trim();
            if (name.isNotEmpty && value.isNotEmpty) {
              await WebViewCookieManager().setCookie(
                WebViewCookie(
                  name: name,
                  value: value,
                  domain: 'eticket.railway.gov.bd',
                  path: '/',
                ),
              );
            }
          }
        }
      }

      // If already ready for payment, direct straight to trip-info checkout
      final isReadyForPayment = reservation != null && reservation['status'] == 'readyForPayment';
      final targetUrl = isReadyForPayment ? BookingService.tripInfoUrl : widget.url;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) { if (mounted) setState(() => _loading = true); },
            onPageFinished: (url) async {
              if (mounted) setState(() => _loading = false);
              if (!WebSessionService.isRailwayUrl(url) || bootstrapped) return;
              bootstrapped = true;
              if (session != null && session.isValid) {
                final userRaw = await SecureStore.read('rail_user');
                final cftToken = await SecureStore.read('rail_cft_token');
                final values = <String, String>{
                  'token': session.token.startsWith('Bearer ') ? session.token.substring(7) : session.token,
                  'uudid': session.deviceId,
                  'ssdk': session.deviceKey,
                  'user': ?userRaw,
                  if (cftToken != null && cftToken.isNotEmpty) 'cft_token': cftToken,
                };
                Map<String, dynamic> storage = {};
                if (reservation != null && ['awaitingOtp', 'readyForPayment'].contains(reservation['status'])) {
                  final user = userRaw == null ? <String, dynamic>{} : jsonDecode(userRaw) as Map<String, dynamic>;
                  final phone = user['phone_number']?.toString() ?? session.phoneNumber ?? '';
                  if (phone.isNotEmpty && reservation['expiresAt'] != null) {
                    storage = BookingService.webStorage(reservation, phone);
                  }
                }
                await _controller?.runJavaScript('''
                  (function() {
                    Object.entries(${jsonEncode(values)}).forEach(([k,v]) => {
                      try { localStorage.setItem(k, v); } catch(_) {}
                    });
                    Object.entries(${jsonEncode(storage)}).forEach(([k,v]) => {
                      try { sessionStorage.setItem(k, String(v)); } catch(_) {}
                    });
                  })();
                ''');
                await _controller?.loadRequest(Uri.parse(targetUrl));
              }
            },
            onWebResourceError: (error) {
              if (mounted && error.isForMainFrame == true) {
                setState(() { _failed = true; _loading = false; });
              }
            },
          ),
        );

      setState(() => _controller = controller);
      await controller.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));
    } catch (_) {
      if (mounted) setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: GradientAppBar(
        title: 'Complete Booking',
        subtitle: 'Secure payment via Bangladesh Railway',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              if (_controller != null) {
                setState(() { _loading = true; _failed = false; });
                _controller!.reload();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          if (_loading)
            LinearProgressIndicator(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 3,
            ),
          Expanded(
            child: _failed || _controller == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 72, color: AppColors.error.withValues(alpha: 0.7)),
                          const SizedBox(height: 20),
                          Text('Unable to load page', style: TextStyle(
                            color: AppColors.textPrimary(isDark), fontWeight: FontWeight.bold, fontSize: 18,
                          )),
                          const SizedBox(height: 8),
                          Text('Please check your internet connection and try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13)),
                          const SizedBox(height: 28),
                          PrimaryButton(
                            label: 'Try Again',
                            icon: Icons.refresh_rounded,
                            onPressed: () {
                              setState(() { _failed = false; _loading = true; });
                              _initWebView();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : WebViewWidget(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
