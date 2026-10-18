import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_shell.dart';

import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/auth_session.dart';
import '../services/web_login_support.dart';
import '../services/web_session_service.dart';
import '../services/secure_store.dart';
import '../services/theme_service.dart';
import '../services/language_service.dart';
import '../services/monitor_service.dart';
import '../services/railway_credentials_rejected.dart';
import '../widgets/fancy_train_loader.dart';
import '../utils/app_theme.dart';

class WebviewLoginScreen extends StatefulWidget {
  /// Set [clearSession] to true when navigating here after a session expiry
  /// so that WebView cookies and localStorage are wiped before loading.
  final bool clearSession;
  final String? initialPhone;
  final String? initialPassword;

  /// When true the screen pops with `true` after a successful login instead of
  /// replacing the whole stack (used when re-logging in mid-session).
  final bool popOnSuccess;

  /// Explanation shown above the page (e.g. "password not accepted").
  final String? notice;

  const WebviewLoginScreen({
    super.key,
    this.clearSession = false,
    this.initialPhone,
    this.initialPassword,
    this.popOnSuccess = false,
    this.notice,
  });

  static int _open = 0;

  /// True while a login screen is on screen (prevents stacking a second one).
  static bool get isShowing => _open > 0;

  @override
  State<WebviewLoginScreen> createState() => _WebviewLoginScreenState();
}

class _WebviewLoginScreenState extends State<WebviewLoginScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String _savedPhone = '';
  String _savedPassword = '';
  Timer? _sessionRetry;
  Timer? _loadingTimeoutTimer;

  @override
  void dispose() {
    WebviewLoginScreen._open--;
    _sessionRetry?.cancel();
    _loadingTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WebviewLoginScreen._open++;
    _prepareWebView();
  }

  Future<void> _prepareWebView() async {
    try {
      await _loadSavedCredentials();
      if (widget.clearSession) {
        await AuthSession.clear();
        await SecureStore.delete('rail_action_token');
        await WebSessionService.clear();
      }
      if (mounted) await _initWebView();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Saved values only pre-fill the form. They are never submitted from here:
  /// the visible login is where the user types (or corrects) their login.
  Future<void> _loadSavedCredentials() async {
    final creds = await AuthSession.getSavedUserCredentials();
    if (mounted) {
      setState(() {
        _savedPhone = widget.initialPhone ?? creds['phone'] ?? '';
        _savedPassword = widget.initialPassword ?? creds['password'] ?? '';
      });
    }
  }

  Future<void> _initWebView() async {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'RailBridge',
          onMessageReceived: (JavaScriptMessage msg) {
            _handleBridgeMessage(msg.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) async {
              if (_hasNavigated) return NavigationDecision.prevent;
              // WKWebView also delegates iframe navigations. Turnstile needs
              // its HTTPS challenge frame and local blank/srcdoc frames, but
              // these must never replace the Railway login page.
              if (!request.isMainFrame) {
                final uri = Uri.tryParse(request.url);
                if ((uri?.scheme == 'https' &&
                        uri?.host == 'challenges.cloudflare.com' &&
                        uri?.port == 443) ||
                    request.url == 'about:blank' ||
                    request.url == 'about:srcdoc') {
                  return NavigationDecision.navigate;
                }
              }
              if (!WebSessionService.isRailwayUrl(request.url)) {
                return NavigationDecision.prevent;
              }
              if (request.isMainFrame &&
                  Uri.tryParse(request.url)?.path == '/booking/train/search') {
                await _checkLiveSession();
                if (_hasNavigated) return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageStarted: (url) {
              _sessionRetry?.cancel();
              _loadingTimeoutTimer?.cancel();
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (url) async {
              if (!WebSessionService.isRailwayUrl(url)) {
                if (mounted) setState(() => _isLoading = false);
                return;
              }
              await _installInterceptors();
              await _prefillSavedCredentials();
              await _checkLiveSession();
              if (mounted && !_hasNavigated) {
                _sessionRetry?.cancel();
                _sessionRetry = Timer(const Duration(milliseconds: 500), () {
                  if (mounted && !_hasNavigated) _checkLiveSession();
                });
              }
              // Show the form as soon as it has been pre-filled (or wait for auto-login).
              final hasCreds =
                  _savedPhone.isNotEmpty && _savedPassword.isNotEmpty;
              final timeoutMs = (widget.clearSession && hasCreds) ? 8000 : 700;
              _loadingTimeoutTimer?.cancel();
              _loadingTimeoutTimer = Timer(
                Duration(milliseconds: timeoutMs),
                () {
                  if (mounted && !_hasNavigated && _isLoading) {
                    setState(() => _isLoading = false);
                  }
                },
              );
            },
            onWebResourceError: (error) {
              if (mounted) setState(() => _isLoading = false);
            },
          ),
        );

      await WebSessionService.configureLoginBrowser(_controller!);
      if (!mounted) return;
      await _controller!.loadRequest(Uri.parse(RailLoginScript.loginUrl));
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _installInterceptors() async {
    if (_controller == null) return;
    try {
      await _controller!.runJavaScript(RailLoginScript.interceptors);
    } catch (_) {}
  }

  bool _hasNavigated = false;
  bool _checkingSession = false;

  Future<void> _handleBridgeMessage(String raw) async {
    if (!mounted || _hasNavigated) return;
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
        case 'CREDENTIALS':
          // What the user typed; stored only after Railway accepts it.
          _savedPhone = map['phone']?.toString() ?? '';
          _savedPassword = map['password']?.toString() ?? '';
        case 'AUTH_ERROR':
          // Railway refused this login: never keep a password it rejected.
          if (RailwayCredentialsRejected.isResponse(
            map['body']?.toString() ?? '',
          )) {
            await AuthSession.clearSavedPassword();
          }
        case 'AUTH_SUCCESS' || 'STORAGE_TOKEN':
          await _saveAndNavigate(WebLoginPayload.fromMap(map));
      }
    } catch (_) {}
  }

  Future<void> _checkLiveSession() async {
    if (!mounted || _controller == null || _hasNavigated || _checkingSession) {
      return;
    }
    _checkingSession = true;
    try {
      if (!WebSessionService.isRailwayUrl(await _controller!.currentUrl())) {
        return;
      }
      // Checked on ANY Railway page, including the login page itself, so a
      // token stored right after sign-in redirects immediately.
      final res = await _controller!.runJavaScriptReturningResult(
        RailLoginScript.readSession,
      );
      final payload = WebLoginPayload.fromJsResult(res);
      if (payload != null) await _saveAndNavigate(payload);
    } catch (_) {
    } finally {
      _checkingSession = false;
    }
  }

  /// Stores the new session AND the credentials that just worked, so the next
  /// token expiry can be handled silently with the up-to-date login.
  Future<void> _saveAndNavigate(WebLoginPayload payload) async {
    if (_hasNavigated || !mounted || !payload.hasUsableToken) return;
    _hasNavigated = true;
    _sessionRetry?.cancel();
    _loadingTimeoutTimer?.cancel();
    setState(() => _isLoading = true);
    try {
      await WebLoginPersistence.save(
        payload,
        fallbackPhone: _savedPhone,
        fallbackPassword: _savedPassword,
      );
      _navigateToSearch();
    } catch (_) {
      _hasNavigated = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Pre-fills whatever login is saved. When recovering an expired session
  /// ([clearSession] is true), it automatically submits and solves Turnstile;
  /// otherwise it pre-fills and lets the user tap sign-in.
  Future<void> _prefillSavedCredentials() async {
    if (_controller == null ||
        (_savedPhone.isEmpty && _savedPassword.isEmpty)) {
      return;
    }
    if (!WebSessionService.isRailwayUrl(await _controller!.currentUrl())) {
      return;
    }
    try {
      final shouldSubmit =
          widget.clearSession &&
          _savedPhone.isNotEmpty &&
          _savedPassword.isNotEmpty;
      await _controller!.runJavaScript(
        RailLoginScript.autofill(
          _savedPhone,
          _savedPassword,
          submit: shouldSubmit,
        ),
      );
    } catch (_) {}
  }

  void _navigateToSearch() {
    if (!mounted) return;
    final monitorService = context.read<MonitorService>();
    monitorService.clearErrors();
    if (widget.popOnSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            const AppShell(initialTab: AppShell.tabSearch),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = Provider.of<ThemeService>(context);
    final langService = Provider.of<LanguageService>(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.appBarGradientStart,
                AppColors.appBarGradientEnd,
              ],
            ),
          ),
        ),
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.train_rounded, color: Colors.white, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              langService.t('app_name'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              langService.t('app_subtitle'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          // Language switcher
          GestureDetector(
            onTap: langService.toggleLanguage,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                langService.isBangla ? 'EN' : 'বাং',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: Colors.white,
            ),
            onPressed: themeService.toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.notice != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF4E5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.notice!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF7C2D12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!)
                else
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: (isDark ? AppColors.darkBg : Colors.white)
                          .withValues(alpha: 0.88),
                      child: FancyTrainLoader(
                        message: langService.tr(
                          'Signing in…',
                          'সাইন ইন হচ্ছে…',
                        ),
                        subMessage: '',
                        stage: JourneyAnimationStage.verifying,
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
