import '../services/login_flow.dart';
import 'webview_login_screen.dart';

import 'dart:convert';

import '../services/booking_service.dart';
import '../services/rail_api_client.dart';
import '../services/api_service.dart';
import '../models/purchased_ticket.dart';
import '../services/secure_store.dart';
import '../services/web_session_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/auth_session.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';

class BookingScreen extends StatefulWidget {
  static int _openScreens = 0;
  static bool get isOpen => _openScreens > 0;
  final String url;
  const BookingScreen({super.key, required this.url});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  bool _loading = true;
  bool _bootstrapping = true;
  bool _failed = false;
  String _failureMessage =
      'Please check your internet connection and try again.';
  bool _checkoutRedirected = false;
  Future<List<PurchasedTicket>?>? _historyBeforeCheckout;
  bool _checkingPayment = false;
  int _searchRecoveryAttempts = 0;
  bool _gatewayOpened = false;
  bool _paymentBrowserOpened = false;
  bool _openingPaymentBrowser = false;
  bool _initializing = false;
  int _progress = 0;
  String _host = 'eticket.railway.gov.bd';
  String? _paymentMessage;

  @override
  void initState() {
    super.initState();
    BookingScreen._openScreens++;
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (_initializing || _gatewayOpened) return;
    _initializing = true;
    try {
      final initial = await Future.wait<Object?>([
        AuthSession.load(),
        BookingService.pending(),
      ]);
      var loadedSession = initial[0] as AuthSession?;
      if (loadedSession == null) {
        throw StateError("Please log in again before checkout.");
      }
      loadedSession = await RailApiClient.current(loadedSession);
      if (!loadedSession.isValid) {
        loadedSession = await RailApiClient.refresh(loadedSession);
      }
      final session = loadedSession;
      if (!WebSessionService.isRailwayUrl(widget.url)) {
        throw StateError('Invalid Railway booking link');
      }
      final reservation = initial[1] as Map<String, dynamic>?;
      bool bootstrapped = false;
      _historyBeforeCheckout ??=
          ApiService.getPurchaseHistory(authSession: session)
              .then<List<PurchasedTicket>?>(
                (tickets) => tickets,
                onError: (Object _) => null,
              );

      // Sync cookies from session if available
      if (session.cookie != null && session.cookie!.isNotEmpty) {
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
      final isReadyForPayment =
          reservation != null && reservation['status'] == 'readyForPayment';
      final targetUrl = isReadyForPayment
          ? BookingService.tripInfoUrl
          : widget.url;

      final checkoutData = await Future.wait<Object?>([
        BookingService.checkoutUser(session),
        SecureStore.read('rail_cft_token'),
        SecureStore.read('rail_action_token'),
      ]);
      final user = checkoutData[0] as Map<String, dynamic>;
      final cftToken = checkoutData[1] as String?;
      final values = <String, String>{
        'token': session.token.startsWith('Bearer ')
            ? session.token.substring(7)
            : session.token,
        'uudid': session.deviceId,
        'ssdk': session.deviceKey,
        'user': jsonEncode(user),
        if (cftToken != null && cftToken.isNotEmpty) 'cft_token': cftToken,
      };
      Map<String, dynamic> storage = {};
      if (reservation != null &&
          ['awaitingOtp', 'readyForPayment'].contains(reservation['status'])) {
        final phone = user['phone_number']?.toString() ?? '';
        if (phone.isNotEmpty && reservation['expiresAt'] != null) {
          storage = BookingService.webStorage(reservation, phone);
        }
      }

      if (isReadyForPayment && storage.isEmpty) {
        throw StateError('Reservation phone or checkout data is missing.');
      }
      final actionToken = checkoutData[2] as String?;
      if (actionToken?.isNotEmpty == true) storage['atk'] = actionToken;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted && progress != _progress) {
                setState(() => _progress = progress);
              }
            },
            onNavigationRequest: (request) async {
              final scheme =
                  Uri.tryParse(request.url)?.scheme.toLowerCase() ?? '';
              if (request.isMainFrame &&
                  (scheme == 'http' || scheme == 'https') &&
                  !WebSessionService.isRailwayUrl(request.url)) {
                _gatewayOpened = true;
              }
              if (request.isMainFrame &&
                  WebSessionService.usesAndroidPaymentBrowser(request.url)) {
                await _openPaymentBrowser(Uri.parse(request.url));
                return NavigationDecision.prevent;
              }
              if (scheme == 'http' ||
                  scheme == 'https' ||
                  scheme == 'about' ||
                  scheme == 'data' ||
                  scheme == 'blob' ||
                  scheme == 'javascript') {
                return NavigationDecision.navigate;
              }
              // Payment apps (bKash, Nagad, Rocket, banks) redirect to
              // intent:// or custom schemes. A WebView cannot load those, so
              // hand them to the OS instead of failing with "Payment Cancelled".
              await _openExternalPaymentLink(request.url);
              return NavigationDecision.prevent;
            },
            onPageStarted: (url) {
              if (mounted) {
                setState(() {
                  _loading = true;
                  _progress = 0;
                  _host = Uri.tryParse(url)?.host ?? _host;
                });
              }
            },
            onPageFinished: (url) async {
              if (!WebSessionService.isRailwayUrl(url)) {
                // Payment gateway (train-pay.shohoz.com) or other external pages
                // load inside the WebView. Keep them visible.
                if (mounted) {
                  setState(() {
                    _loading = false;
                    _bootstrapping = false;
                  });
                }
                // If we returned from the payment gateway to a success page,
                // check whether the booking was confirmed.
                if (WebSessionService.isPaymentGatewayUrl(url)) {
                  _gatewayOpened = true;
                } else {
                  await _checkPaymentSuccess(url);
                }
                return;
              }

              if (!bootstrapped &&
                  (url.contains('/rail-pro-checkout-bootstrap') ||
                      url == 'about:blank' ||
                      url.startsWith('data:') ||
                      WebSessionService.isRailwayUrl(url))) {
                bootstrapped = true;
                if (session.isValid) {
                  try {
                    await _controller?.runJavaScript('''
                    (function() {
                      Object.entries(${jsonEncode(values)}).forEach(([k,v]) => {
                        localStorage.setItem(k, v);
                        try { sessionStorage.setItem(k, v); } catch(e){}
                      });
                      Object.entries(${jsonEncode(storage)}).forEach(([k,v]) => {
                        sessionStorage.setItem(k, String(v));
                        try { localStorage.setItem(k, String(v)); } catch(e){}
                      });

                    })();
                  ''');
                    await _controller?.runJavaScript(
                      'window.location.replace(${jsonEncode(targetUrl)});',
                    );
                    return;
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        _failed = true;
                        _loading = false;
                        _bootstrapping = false;
                      });
                    }
                    return;
                  }
                }
              }

              final uri = Uri.tryParse(url);
              final isSearchRedirect =
                  !_gatewayOpened &&
                  isReadyForPayment &&
                  (uri?.path == '/booking/train/search' ||
                      uri?.path == '/' ||
                      uri?.path.isEmpty == true);

              // Auto-recover if redirected to search on mobile
              if (isSearchRedirect && _searchRecoveryAttempts < 2) {
                _searchRecoveryAttempts++;
                try {
                  await _controller?.runJavaScript('''
                    (function() {
                      try {
                        var vals = ${jsonEncode(values)};
                        for (var k in vals) {
                          try { localStorage.setItem(k, vals[k]); } catch(e){}
                          try { sessionStorage.setItem(k, vals[k]); } catch(e){}
                        }
                        var stor = ${jsonEncode(storage)};
                        for (var s in stor) {
                          try { localStorage.setItem(s, String(stor[s])); } catch(e){}
                          try { sessionStorage.setItem(s, String(stor[s])); } catch(e){}
                        }
                        window.location.replace(${jsonEncode(BookingService.tripInfoUrl)});
                      } catch(e) {
                        window.location.href = ${jsonEncode(BookingService.tripInfoUrl)};
                      }
                    })();
                  ''');
                } catch (_) {}
              }

              if (defaultTargetPlatform == TargetPlatform.iOS &&
                  !url.contains('/rail-pro-checkout-bootstrap')) {
                await _controller?.runJavaScript(
                  WebSessionService.iosCheckoutLocationScript,
                );
              }

              if (uri?.path == '/booking/train/trip-info') {
                await _controller?.runJavaScript(
                  WebSessionService.checkoutAppearanceScript,
                );
              }

              // Finished loading target booking / payment page
              if (mounted) {
                setState(() {
                  _bootstrapping = false;
                  _loading = false;
                  _checkoutRedirected =
                      isReadyForPayment &&
                      Uri.tryParse(url)?.path == '/booking/train/search';
                });
                await _checkPaymentSuccess(url);
              }
            },
            onWebResourceError: (error) {
              if (mounted && error.isForMainFrame == true) {
                setState(() {
                  _failed = true;
                  _loading = false;
                  _bootstrapping = false;
                });
              }
            },
          ),
        );

      await WebSessionService.configurePaymentBrowser(controller);
      if (!mounted) return;
      setState(() => _controller = controller);
      // Restore once; the website then owns token rotation and reservation
      // cleanup when it creates the payment order.
      // A blank document on the Railway origin lets us restore storage before
      // the site's router executes. Loading /login first races its redirects.
      await controller.loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" '
        'content="width=device-width, initial-scale=1"></head><body></body></html>',
        baseUrl: 'https://eticket.railway.gov.bd/rail-pro-checkout-bootstrap',
      );
    } catch (error) {
      if (mounted && LoginFlow.needsLogin(error)) {
        await AuthSession.clear();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WebviewLoginScreen(clearSession: true),
          ),
        );
        return;
      }
      if (mounted) {
        setState(() {
          _failureMessage = friendlyErrorMessage(error);
          _failed = true;
          _loading = false;
          _bootstrapping = false;
        });
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _openPaymentBrowser(Uri uri) async {
    // An order URL must not be opened twice by overlapping navigation events.
    if (_openingPaymentBrowser || _paymentBrowserOpened) return;
    _openingPaymentBrowser = true;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!mounted) return;
      setState(() {
        _paymentBrowserOpened = opened;
        _loading = false;
        _bootstrapping = false;
        if (!opened) {
          _failed = true;
          _failureMessage =
              'Could not open the payment browser. '
              'Check payment status before trying again.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
          _bootstrapping = false;
          _failureMessage =
              'Could not open the payment browser. '
              'Check payment status before trying again.';
        });
      }
    } finally {
      _openingPaymentBrowser = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _paymentBrowserOpened) {
      _checkPaymentSuccess('', checkHistory: true);
    }
  }

  Future<void> _openExternalPaymentLink(String raw) async {
    try {
      var target = raw;
      Uri? browserFallback;
      if (raw.toLowerCase().startsWith('intent:')) {
        final fallback = RegExp(r'S\.browser_fallback_url=([^;]+)')
            .firstMatch(raw)
            ?.group(1);
        if (fallback != null) {
          final candidate = Uri.tryParse(Uri.decodeComponent(fallback));
          if (candidate?.scheme == 'https' || candidate?.scheme == 'http') {
            browserFallback = candidate;
          }
        }
        final scheme = RegExp(r';scheme=([^;]+)').firstMatch(raw)?.group(1);
        if (scheme != null) {
          target = raw
              .replaceFirst(
                RegExp(r'^intent:', caseSensitive: false),
                '$scheme:',
              )
              .split('#Intent')
              .first;
        } else if (fallback != null) {
          target = Uri.decodeComponent(fallback);
        }
      }
      final uri = Uri.tryParse(target);
      if (uri == null) return;
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        await _controller?.loadRequest(uri);
        return;
      }
      var opened = false;
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Android throws when the provider's app is not installed.
      }
      if (!opened && browserFallback != null) {
        await _controller?.loadRequest(browserFallback);
        return;
      }
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the payment app. Install it or choose another payment method.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the payment app.')),
        );
      }
    }
  }

  bool _completedHandled = false;

  Future<void> _checkPaymentSuccess(
    String url, {
    bool checkHistory = false,
    bool userInitiated = false,
  }) async {
    if (_completedHandled || _checkingPayment) return;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (!checkHistory &&
        !path.contains('success') &&
        !path.contains('confirmation') &&
        !path.contains('ticket-history')) {
      return;
    }
    _checkingPayment = true;
    if (mounted) setState(() => _paymentMessage = null);
    try {
      final before = await _historyBeforeCheckout;
      final session = await AuthSession.load();
      final reservation = await BookingService.pending();
      if (before == null ||
          session == null ||
          reservation?['status'] != 'readyForPayment') {
        return;
      }
      final tripId = int.tryParse('${reservation!['seatClass']['trip_id']}');
      final tickets = await ApiService.getPurchaseHistory(authSession: session);
      final oldIds = before.map((ticket) => ticket.orderId).toSet();
      final paid = tickets.any(
        (ticket) =>
            ticket.isConfirmed &&
            !ticket.isRefunded &&
            ticket.pnr.isNotEmpty &&
            ticket.tripId == tripId &&
            !oldIds.contains(ticket.orderId),
      );
      if (!paid) {
        if (mounted && userInitiated) {
          setState(
            () => _paymentMessage = 'Payment is not confirmed yet. Check again after completing payment.',
          );
        }
        return;
      }
      final done = await BookingService.completeSuccessfulBooking(
        reservation: reservation,
      );
      _completedHandled = done;
      if (mounted) setState(() {});
      if (done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Railway confirmed your payment. Ticket ready in Trips.',
            ),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (_) {
      // Keep the reservation available when confirmation cannot be established.
      if (mounted && userInitiated) {
        setState(
          () => _paymentMessage =
              'Could not check payment. Please try again shortly.',
        );
      }
    } finally {
      _checkingPayment = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BookingScreen._openScreens--;
    super.dispose();
  }

  void _retry() {
    if (_gatewayOpened) {
      _checkPaymentSuccess('', checkHistory: true, userInitiated: true);
      return;
    }
    setState(() {
      _failed = false;
      _checkoutRedirected = false;
      _loading = true;
      _bootstrapping = true;
      _progress = 0;
    });
    _initWebView();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.of(context);
    // LanguageService can also be used without a Provider (notification routes).
    final ink = AppColors.textPrimary(dark);
    final muted = AppColors.textSecondary(dark);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(dark),
      appBar: AppBar(
        backgroundColor: AppColors.surface(dark),
        foregroundColor: ink,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lang.tr('Secure checkout', 'নিরাপদ চেকআউট'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              lang.tr('Complete your journey', 'আপনার যাত্রা নিশ্চিত করুন'),
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: lang.tr('Checkout options', 'চেকআউটের বিকল্প'),
            onSelected: (_) => _retry(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'refresh',
                child: Text(
                  _gatewayOpened
                      ? lang.tr('Check payment', 'পেমেন্ট যাচাই করুন')
                      : lang.tr('Reload checkout', 'চেকআউট আবার খুলুন'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface(dark),
                border: Border(
                  bottom: BorderSide(color: AppColors.cardBorder(dark)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  _step('1', lang.tr('Review', 'তথ্য'), true, dark),
                  Expanded(
                    child: Divider(
                      indent: 12,
                      endIndent: 12,
                      color: AppColors.cardBorder(dark),
                    ),
                  ),
                  _step(
                    '2',
                    lang.tr('Payment', 'পেমেন্ট'),
                    _gatewayOpened,
                    dark,
                  ),
                  Expanded(
                    child: Divider(
                      indent: 12,
                      endIndent: 12,
                      color: AppColors.cardBorder(dark),
                    ),
                  ),
                  _step(
                    '3',
                    lang.tr('Ticket', 'টিকিট'),
                    _completedHandled,
                    dark,
                  ),
                ],
              ),
            ),
            if (!_paymentBrowserOpened && !_failed)
              Container(
                color: AppColors.surface(dark),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.primaryDark,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _host == 'eticket.railway.gov.bd'
                            ? 'Bangladesh Railway'
                            : _host,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                    Text(
                      lang.tr('OFFICIAL CHECKOUT', 'অফিশিয়াল চেকআউট'),
                      style: TextStyle(
                        color: muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ),
            if (_loading && !_paymentBrowserOpened && !_failed)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
                color: AppColors.primaryDark,
                backgroundColor: AppColors.cardBorder(dark),
              ),
            if (_checkoutRedirected)
              Padding(
                padding: const EdgeInsets.all(12),
                child: MaterialBanner(
                  content: Text(
                    lang.tr(
                      'Railway returned to search. Reopen checkout if your seat hold is still active.',
                      'রেলওয়ে অনুসন্ধান পাতায় ফিরিয়েছে। আসন সংরক্ষিত থাকলে চেকআউট আবার খুলুন।',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: _retry,
                      child: Text(lang.tr('Retry checkout', 'আবার খুলুন')),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  if (_controller != null)
                    Offstage(
                      offstage:
                          _paymentBrowserOpened || _failed || _bootstrapping,
                      child: WebViewWidget(controller: _controller!),
                    ),
                  if (_paymentBrowserOpened)
                    _paymentReturn(dark, lang)
                  else if (_failed)
                    _statusPanel(
                      dark: dark,
                      icon: Icons.wifi_off_rounded,
                      title: lang.tr('Let’s reconnect.', 'আবার সংযোগ করুন।'),
                      description: _failureMessage,
                      action: lang.tr(
                        _gatewayOpened ? 'Check payment' : 'Try Again',
                        _gatewayOpened
                            ? 'পেমেন্ট যাচাই করুন'
                            : 'আবার চেষ্টা করুন',
                      ),
                      onPressed: _retry,
                    )
                  else if (_bootstrapping || _controller == null)
                    _statusPanel(
                      dark: dark,
                      icon: Icons.lock_outline_rounded,
                      title: lang.tr(
                        'Preparing your checkout',
                        'চেকআউট প্রস্তুত হচ্ছে',
                      ),
                      description: lang.tr(
                        'Connecting your reservation to Bangladesh Railway…',
                        'আপনার সংরক্ষণ বাংলাদেশ রেলওয়ের সাথে যুক্ত হচ্ছে…',
                      ),
                      loading: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String number, String label, bool active, bool dark) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryDark : AppColors.cardBorder(dark),
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary(dark),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: active
              ? AppColors.textPrimary(dark)
              : AppColors.textMuted(dark),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  Widget _paymentReturn(bool dark, LanguageService lang) => _statusPanel(
    dark: dark,
    icon: _completedHandled
        ? Icons.check_circle_outline_rounded
        : Icons.open_in_browser_rounded,
    title: _completedHandled
        ? lang.tr('Your ticket is confirmed.', 'আপনার টিকিট নিশ্চিত হয়েছে।')
        : lang.tr('Finish in your browser.', 'ব্রাউজারে পেমেন্ট শেষ করুন।'),
    description: _completedHandled
        ? lang.tr(
            'Your ticket is ready in Trips.',
            'ট্রিপস থেকে আপনার টিকিট দেখুন।',
          )
        : lang.tr(
            'Complete payment in the secure browser tab, then return here. We’ll confirm your ticket with Railway.',
            'নিরাপদ ব্রাউজার ট্যাবে পেমেন্ট শেষ করে এখানে ফিরুন। আমরা রেলওয়ে থেকে আপনার টিকিট যাচাই করব।',
          ),
    action: _completedHandled
        ? null
        : lang.tr('Check payment', 'পেমেন্ট যাচাই করুন'),
    onPressed: () =>
        _checkPaymentSuccess('', checkHistory: true, userInitiated: true),
    loading: _checkingPayment,
    message: _paymentMessage,
  );

  Widget _statusPanel({
    required bool dark,
    required IconData icon,
    required String title,
    required String description,
    String? action,
    VoidCallback? onPressed,
    bool loading = false,
    String? message,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(icon, size: 36, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 26),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary(dark),
                fontSize: 14,
                height: 1.6,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 26),
            if (action != null)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: loading ? null : onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          action,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              )
            else if (loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryDark,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
