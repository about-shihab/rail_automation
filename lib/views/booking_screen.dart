import '../services/railway_credentials_rejected.dart';
import 'webview_login_screen.dart';

import 'dart:convert';

import '../services/booking_service.dart';
import '../services/rail_api_client.dart';
import '../services/api_service.dart';
import '../models/purchased_ticket.dart';
import '../services/secure_store.dart';
import '../services/web_session_service.dart';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/auth_session.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/fancy_train_loader.dart';

class BookingScreen extends StatefulWidget {
  static int _openScreens = 0;
  static bool get isOpen => _openScreens > 0;
  final String url;
  const BookingScreen({super.key, required this.url});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _bootstrapping = true;
  bool _failed = false;
  String _failureMessage =
      'Please check your internet connection and try again.';
  bool _checkoutRedirected = false;
  Future<List<PurchasedTicket>?>? _historyBeforeCheckout;
  bool _checkingPayment = false;

  @override
  void initState() {
    super.initState();
    BookingScreen._openScreens++;
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      var loadedSession = await AuthSession.load();
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
      final reservation = await BookingService.pending();
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

      final userRaw = await SecureStore.read('rail_user');
      final cftToken = await SecureStore.read('rail_cft_token');
      final values = <String, String>{
        'token': session.token.startsWith('Bearer ')
            ? session.token.substring(7)
            : session.token,
        'uudid': session.deviceId,
        'ssdk': session.deviceKey,
        'user': ?userRaw,
        if (cftToken != null && cftToken.isNotEmpty) 'cft_token': cftToken,
      };
      Map<String, dynamic> storage = {};
      if (reservation != null &&
          ['awaitingOtp', 'readyForPayment'].contains(reservation['status'])) {
        final user = userRaw == null
            ? <String, dynamic>{}
            : jsonDecode(userRaw) as Map<String, dynamic>;
        final phone =
            user['phone_number']?.toString() ?? session.phoneNumber ?? '';
        if (phone.isNotEmpty && reservation['expiresAt'] != null) {
          storage = BookingService.webStorage(reservation, phone);
        }
      }

      if (isReadyForPayment && storage.isEmpty) {
        throw StateError('Reservation phone or checkout data is missing.');
      }

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (url) async {
              if (!WebSessionService.isRailwayUrl(url)) {
                // Payment providers must remain visible during checkout.
                if (mounted) {
                  setState(() {
                    _loading = false;
                    _bootstrapping = false;
                  });
                }
                return;
              }

              if (!bootstrapped &&
                  url.contains('/rail-pro-checkout-bootstrap')) {
                bootstrapped = true;
                if (session.isValid) {
                  try {
                    await _controller?.runJavaScript('''
                    (function() {
                      Object.entries(${jsonEncode(values)}).forEach(([k,v]) => {
                        localStorage.setItem(k, v);
                      });
                      Object.entries(${jsonEncode(storage)}).forEach(([k,v]) => {
                        sessionStorage.setItem(k, String(v));
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

      if (!mounted) return;
      setState(() => _controller = controller);
      // A blank document on the Railway origin lets us restore storage before
      // the site's router executes. Loading /login first races its redirects.
      await controller.loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body></body></html>',
        baseUrl: 'https://eticket.railway.gov.bd/rail-pro-checkout-bootstrap',
      );
    } catch (error) {
      if (mounted && RailwayCredentialsRejected.isError(error)) {
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
    }
  }

  bool _completedHandled = false;

  Future<void> _checkPaymentSuccess(String url) async {
    if (_completedHandled || _checkingPayment) return;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (!path.contains('success') &&
        !path.contains('confirmation') &&
        !path.contains('ticket-history')) {
      return;
    }
    _checkingPayment = true;
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
      if (!paid) return;
      final done = await BookingService.completeSuccessfulBooking(
        reservation: reservation,
      );
      _completedHandled = done;
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
    } finally {
      _checkingPayment = false;
    }
  }

  @override
  void dispose() {
    BookingScreen._openScreens--;
    super.dispose();
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
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              if (_controller != null) {
                setState(() {
                  _loading = true;
                  _failed = false;
                });
                _controller!.reload();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_checkoutRedirected)
            MaterialBanner(
              content: const Text(
                'Railway returned to search. Your reservation is still saved. Retry checkout; if it has expired, reserve seats again.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _checkoutRedirected = false;
                      _bootstrapping = true;
                      _loading = true;
                      _failed = false;
                    });
                    _initWebView();
                  },
                  child: const Text('Retry checkout'),
                ),
              ],
            ),
          // Progress bar
          if (_loading)
            LinearProgressIndicator(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
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
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 72,
                            color: AppColors.error.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Unable to load page',
                            style: TextStyle(
                              color: AppColors.textPrimary(isDark),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _failureMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary(isDark),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 28),
                          PrimaryButton(
                            label: 'Try Again',
                            icon: Icons.refresh_rounded,
                            onPressed: () {
                              setState(() {
                                _failed = false;
                                _loading = true;
                                _bootstrapping = true;
                              });
                              _initWebView();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      WebViewWidget(controller: _controller!),
                      if (_loading || _bootstrapping)
                        Positioned.fill(
                          child: Container(
                            color: isDark
                                ? const Color(0xFF09090B)
                                : Colors.white,
                            child: const FancyTrainLoader(
                              message: 'Opening secure checkout…',
                              subMessage: '',
                              stage: JourneyAnimationStage.payment,
                              showCard: true,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
