import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/auth_session.dart';
import '../services/web_session_service.dart';
import '../services/secure_store.dart';
import '../services/theme_service.dart';
import '../services/language_service.dart';
import '../services/monitor_service.dart';
import '../services/firebase_user_service.dart';
import '../widgets/fancy_train_loader.dart';
import 'monitor_dashboard_screen.dart';
import '../utils/app_theme.dart';
import 'search_screen.dart';

class WebviewLoginScreen extends StatefulWidget {
  /// Set [clearSession] to true when navigating here after a session expiry
  /// so that WebView cookies and localStorage are wiped before loading.
  final bool clearSession;
  final String? initialPhone;
  final String? initialPassword;

  const WebviewLoginScreen({
    super.key,
    this.clearSession = false,
    this.initialPhone,
    this.initialPassword,
  });

  @override
  State<WebviewLoginScreen> createState() => _WebviewLoginScreenState();
}

class _WebviewLoginScreenState extends State<WebviewLoginScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String _savedPhone = '';
  String _savedPassword = '';

  @override
  void initState() {
    super.initState();
    _prepareWebView();
  }

  Future<void> _prepareWebView() async {
    try {
      await _loadSavedCredentials();
      if (widget.clearSession) await WebSessionService.clear();
      if (mounted) _initWebView();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await AuthSession.getSavedUserCredentials();
    if (mounted) {
      setState(() {
        _savedPhone = widget.initialPhone ?? creds['phone'] ?? '';
        _savedPassword = widget.initialPassword ?? creds['password'] ?? '';
      });
    }
  }

  void _initWebView() {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        )
        ..addJavaScriptChannel(
          'RailBridge',
          onMessageReceived: (JavaScriptMessage msg) {
            _handleBridgeMessage(msg.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) => WebSessionService.isRailwayUrl(request.url)
                ? NavigationDecision.navigate : NavigationDecision.prevent,
            onPageStarted: (url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (url) async {
              if (mounted) setState(() => _isLoading = false);
              if (!WebSessionService.isRailwayUrl(url)) return;
              await _installInterceptors();
              await _insertSavedCredentials(silent: true);
              await _checkLiveSession();
            },
            onWebResourceError: (error) {
              if (mounted) setState(() => _isLoading = false);
            },
          ),
        );

      _controller!.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _installInterceptors() async {
    if (_controller == null) return;
    try {
      const script = '''
        (function() {
          if (window.__railInterceptorActive) return;
          window.__railInterceptorActive = true;
          try {
            var handshake = JSON.parse(localStorage.getItem('handshake_data') || '{}');
            var cfg = handshake.data || handshake;
            var hold = cfg.release_time_interval_in_minutes;
            if (hold > 0) window.RailBridge.postMessage(JSON.stringify({type: 'HOLD_CONFIG', seconds: Math.ceil(hold / 60) * 60}));
          } catch (_) {}

          function captureCredentials() {
            var phone = document.querySelector('input[name="mobile_number"], input[type="tel"], #mobile_number');
            var pass = document.querySelector('input[type="password"]');
            if (phone && pass && phone.value && pass.value) {
              window.RailBridge.postMessage(JSON.stringify({type: 'CREDENTIALS', phone: phone.value, password: pass.value}));
            }
          }
          document.addEventListener('input', captureCredentials, true);
          document.addEventListener('submit', captureCredentials, true);

          function getDeviceId() {
            return localStorage.getItem('x-device-id') ||
                   localStorage.getItem('x_device_id') ||
                   localStorage.getItem('uudid') ||
                   localStorage.getItem('uuid') ||
                   localStorage.getItem('device_id') ||
                   localStorage.getItem('deviceId') || '';
          }

          function getDeviceKey() {
            return localStorage.getItem('x-device-key') ||
                   localStorage.getItem('x_device_key') ||
                   localStorage.getItem('ss') ||
                   localStorage.getItem('ssdk') ||
                   localStorage.getItem('device_key') ||
                   localStorage.getItem('deviceKey') || '';
          }

          function getToken() {
            return localStorage.getItem('token') ||
                   localStorage.getItem('user_token') ||
                   localStorage.getItem('access_token') || '';
          }

          function getTurnstileToken() {
            try {
              var el = document.querySelector('input[name="cf-turnstile-response"]') ||
                       document.querySelector('input[name="cft_response"]') ||
                       document.querySelector('[name*="turnstile"]');
              if (el && el.value && el.value.length > 20) return el.value;
              if (window.turnstile && typeof window.turnstile.getResponse === 'function') {
                var resp = window.turnstile.getResponse();
                if (resp && resp.length > 20) return resp;
              }
            } catch (_) {}
            return '';
          }

          // XHR Interception
          var origOpen = XMLHttpRequest.prototype.open;
          var origSend = XMLHttpRequest.prototype.send;
          var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;

          XMLHttpRequest.prototype.open = function(method, url) {
            this._reqUrl = url;
            this._reqHeaders = {};
            return origOpen.apply(this, arguments);
          };

          XMLHttpRequest.prototype.setRequestHeader = function(h, v) {
            if (this._reqHeaders) this._reqHeaders[h] = v;
            return origSetHeader.apply(this, arguments);
          };

          XMLHttpRequest.prototype.send = function(body) {
            var self = this;
            this.addEventListener('load', function() {
              try {
                var url = self._reqUrl || '';
                if (url.indexOf('sign-in') !== -1 || url.indexOf('auth') !== -1 || url.indexOf('login') !== -1) {
                  var res = JSON.parse(self.responseText);
                  var t = (res && res.data && res.data.token) || (res && res.token) || getToken();
                  var h = self._reqHeaders || {};
                  var devId = h['x-device-id'] || h['X-Device-Id'] || getDeviceId();
                  var devKey = h['x-device-key'] || h['X-Device-Key'] || getDeviceKey();
                  var usr = (res && res.data && res.data.user) || (res && res.user) || localStorage.getItem('user') || '{}';
                  var cft = getTurnstileToken();
                  if (t && window.RailBridge) {
                    window.RailBridge.postMessage(JSON.stringify({
                      type: 'AUTH_SUCCESS',
                      token: t,
                      deviceId: devId,
                      deviceKey: devKey,
                      user: usr,
                      cookie: document.cookie || '',
                      cftToken: cft
                    }));
                  }
                }
              } catch(e) {}
            });
            return origSend.apply(this, arguments);
          };

          // Fetch Interception
          var origFetch = window.fetch;
          window.fetch = async function() {
            var url = arguments[0];
            var opts = arguments[1] || {};
            var resp = await origFetch.apply(this, arguments);
            try {
              var strUrl = typeof url === 'string' ? url : (url.url || '');
              if (strUrl.indexOf('sign-in') !== -1 || strUrl.indexOf('auth') !== -1 || strUrl.indexOf('login') !== -1) {
                var clone = resp.clone();
                var json = await clone.json();
                var t = (json && json.data && json.data.token) || (json && json.token) || getToken();
                var h = opts.headers || {};
                var devId = h['x-device-id'] || h['X-Device-Id'] || getDeviceId();
                var devKey = h['x-device-key'] || h['X-Device-Key'] || getDeviceKey();
                var usr = (json && json.data && json.data.user) || (json && json.user) || localStorage.getItem('user') || '{}';
                var cft = getTurnstileToken();
                if (t && window.RailBridge) {
                  window.RailBridge.postMessage(JSON.stringify({
                    type: 'AUTH_SUCCESS',
                    token: t,
                    deviceId: devId,
                    deviceKey: devKey,
                    user: usr,
                    cookie: document.cookie || '',
                    cftToken: cft
                  }));
                }
              }
            } catch(e) {}
            return resp;
          };

          // Active token watcher
          setInterval(function() {
            try {
              var t = getToken();
              var pathname = window.location.pathname || '';
              if (t && t.length > 30) {
                var devId = getDeviceId();
                var devKey = getDeviceKey();
                var usr = localStorage.getItem('user') || '{}';
                var cft = getTurnstileToken();
                if (window.RailBridge) {
                  window.RailBridge.postMessage(JSON.stringify({
                    type: 'STORAGE_TOKEN',
                    token: t,
                    deviceId: devId,
                    deviceKey: devKey,
                    user: usr,
                    cookie: document.cookie || '',
                    currentPath: pathname,
                    cftToken: cft
                  }));
                }
              }
            } catch(e) {}
          }, 1500);

          // Dedicated Turnstile token watcher
          setInterval(function() {
            try {
              var cft = getTurnstileToken();
              if (cft && cft.length > 20 && cft !== window.__lastSentCft) {
                window.__lastSentCft = cft;
                if (window.RailBridge) {
                  window.RailBridge.postMessage(JSON.stringify({
                    type: 'CFT_TOKEN',
                    token: cft
                  }));
                }
              }
            } catch (_) {}
          }, 1500);
        })();
      ''';
      await _controller!.runJavaScript(script);
    } catch (_) {}
  }

  bool _hasNavigated = false;

  Future<void> _handleBridgeMessage(String raw) async {
    if (!WebSessionService.isRailwayUrl(await _controller?.currentUrl())) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type']?.toString();
      if (type == 'HOLD_CONFIG') {
        final seconds = map['seconds'];
        if (seconds is int && seconds > 0 && seconds <= 3600) await SecureStore.write('rail_hold_seconds', '$seconds');
        return;
      }
      if (type == 'CREDENTIALS') {
        _savedPhone = map['phone']?.toString() ?? '';
        _savedPassword = map['password']?.toString() ?? '';
        return;
      }

      if (type == 'CFT_TOKEN') {
        final cft = map['token']?.toString() ?? '';
        if (cft.isNotEmpty && cft.length > 20) {
          await SecureStore.write('rail_cft_token', cft);
          await SecureStore.write('rail_cft_token_time', DateTime.now().toIso8601String());
        }
        return;
      }

      if (type == 'AUTH_SUCCESS' || type == 'STORAGE_TOKEN') {
        final token = map['token']?.toString() ?? '';
        final deviceId = map['deviceId']?.toString() ?? '';
        final deviceKey = map['deviceKey']?.toString() ?? '';
        final cookie = map['cookie']?.toString() ?? '';
        final currentPath = map['currentPath']?.toString() ?? '';
        final cftToken = map['cftToken']?.toString() ?? '';

        if (cftToken.isNotEmpty && cftToken.length > 20) {
          await SecureStore.write('rail_cft_token', cftToken);
          await SecureStore.write('rail_cft_token_time', DateTime.now().toIso8601String());
        }

        // Avoid premature auto-navigation from background storage while user is still on the login page
        if (type == 'STORAGE_TOKEN' && currentPath.contains('login')) {
          return;
        }

        final userRaw = map['user'];
        Map<String, dynamic> user = {};
        if (userRaw is String && userRaw.isNotEmpty) {
          try {
            user = jsonDecode(userRaw) as Map<String, dynamic>;
          } catch (_) {}
        } else if (userRaw is Map<String, dynamic>) {
          user = userRaw;
        }

        if (user.isNotEmpty) await SecureStore.write('rail_user', jsonEncode(user));
        if (token.isNotEmpty && !AuthSession.isDummyToken(token)) {
          _saveAndNavigate(
            token: token,
            deviceId: deviceId,
            deviceKey: deviceKey,
            cookie: cookie,
            phoneNumber: user['mobile_number']?.toString() ??
                user['phone_number']?.toString() ??
                user['username']?.toString(),
            displayName: user['display_name']?.toString() ?? user['name']?.toString(),
            email: user['email']?.toString(),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _checkLiveSession() async {
    if (!mounted || _controller == null || _hasNavigated) return;
    try {
      final currentUrl = await _controller!.currentUrl() ?? '';
      // If user is currently on the login page, allow them to log in fresh
      if (currentUrl.contains('/login')) return;

      final res = await _controller!.runJavaScriptReturningResult('''
        (function() {
          var t = localStorage.getItem('token') || '';
          var devId = localStorage.getItem('x-device-id') || localStorage.getItem('uudid') || '';
          var devKey = localStorage.getItem('x-device-key') || localStorage.getItem('ss') || localStorage.getItem('ssdk') || '';
          var usr = localStorage.getItem('user') || '{}';
          var cookie = document.cookie || '';
          var cft = '';
          try {
            var el = document.querySelector('input[name="cf-turnstile-response"]') ||
                     document.querySelector('input[name="cft_response"]') ||
                     document.querySelector('[name*="turnstile"]');
            if (el && el.value && el.value.length > 20) cft = el.value;
            if (!cft && window.turnstile && typeof window.turnstile.getResponse === 'function') {
              cft = window.turnstile.getResponse() || '';
            }
          } catch (_) {}
          return JSON.stringify({
            token: t,
            deviceId: devId,
            deviceKey: devKey,
            user: usr,
            cookie: cookie,
            cftToken: cft
          });
        })()
      ''');

      final rawStr = res.toString();
      final cleanJson = rawStr.startsWith('"') && rawStr.endsWith('"')
          ? jsonDecode(rawStr)
          : rawStr;
      final map = jsonDecode(cleanJson.toString()) as Map<String, dynamic>;
      final rawToken = map['token']?.toString() ?? '';

      if (rawToken.isNotEmpty && !AuthSession.isDummyToken(rawToken)) {
        final userRaw = map['user'];
        Map<String, dynamic> user = {};
        if (userRaw is String && userRaw.isNotEmpty) {
          try {
            user = jsonDecode(userRaw) as Map<String, dynamic>;
          } catch (_) {}
        } else if (userRaw is Map<String, dynamic>) {
          user = userRaw;
        }

        final cftToken = map['cftToken']?.toString() ?? '';
        if (cftToken.isNotEmpty && cftToken.length > 20) {
          await SecureStore.write('rail_cft_token', cftToken);
          await SecureStore.write('rail_cft_token_time', DateTime.now().toIso8601String());
        }

        _saveAndNavigate(
          token: rawToken,
          deviceId: map['deviceId']?.toString() ?? '',
          deviceKey: map['deviceKey']?.toString() ?? '',
          cookie: map['cookie']?.toString() ?? '',
          phoneNumber: user['mobile_number']?.toString() ??
              user['phone_number']?.toString() ??
              user['mobile']?.toString() ??
              user['phone']?.toString() ??
              user['username']?.toString(),
          displayName: user['display_name']?.toString() ??
              user['name']?.toString() ??
              user['passenger_name']?.toString(),
          email: user['email']?.toString(),
        );
      }
    } catch (_) {}
  }

  Future<void> _saveAndNavigate({
    required String token,
    required String deviceId,
    required String deviceKey,
    String? cookie,
    String? phoneNumber,
    String? displayName,
    String? email,
  }) async {
    if (_hasNavigated) return;
    _hasNavigated = true;

    final payload = AuthSession.decodeJwtPayload(token);
    final phone = (phoneNumber != null && phoneNumber.isNotEmpty)
        ? phoneNumber
        : (payload?['mobile_number']?.toString() ??
            payload?['phone_number']?.toString() ??
            payload?['mobile']?.toString() ??
            payload?['phone']?.toString() ??
            payload?['username']?.toString() ??
            _savedPhone);
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (payload?['display_name']?.toString() ??
            payload?['name']?.toString() ??
            payload?['passenger_name']?.toString());
    final mail = (email != null && email.isNotEmpty)
        ? email
        : payload?['email']?.toString();

    // Persist user's own phone for future autofill
    if (phone.isNotEmpty) {
      await AuthSession.saveUserCredentials(
        phone,
        _savedPassword.isNotEmpty ? _savedPassword : null,
      );
    }

    final session = AuthSession(
      token: token,
      deviceId: deviceId,
      deviceKey: deviceKey,
      cookie: cookie,
      phoneNumber: phone,
      displayName: name,
      email: mail,
      isLoggedIn: true,
    );
    await AuthSession.save(session);
    unawaited(FirebaseUserService().syncUserOnLogin(session));
    _navigateToSearch();
  }

  Future<void> _showSaveCredentialsDialog() async {
    final phoneController = TextEditingController(text: _savedPhone);
    final passController = TextEditingController(text: _savedPassword);
    final lang = Provider.of<LanguageService>(context, listen: false);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.t('save_credentials')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              lang.t('saved_credentials_msg'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: lang.t('mobile_number'),
                prefixIcon: const Icon(Icons.phone),
                hintText: '01XXXXXXXXX',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: lang.t('password'),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lang.isBangla ? 'বাতিল' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () async {
              final p = phoneController.text.trim();
              final pwd = passController.text;
              if (p.isNotEmpty) {
                await AuthSession.saveUserCredentials(p, pwd);
                setState(() {
                  _savedPhone = p;
                  _savedPassword = pwd;
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _insertSavedCredentials(silent: false);
              }
            },
            child: Text(
              lang.isBangla ? 'সংরক্ষণ ও পূরণ' : 'Save & Fill',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _insertSavedCredentials({bool silent = false}) async {
    if (_controller == null || !WebSessionService.isRailwayUrl(await _controller!.currentUrl())) return;
    if (_savedPhone.trim().isEmpty) {
      if (!silent && mounted) {
        _showSaveCredentialsDialog();
      }
      return;
    }

    try {
      final jsCode = '''
        (function() {
          function fill(selector, val) {
            var el = document.querySelector(selector);
            if (el) {
              el.focus();
              el.value = val;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            }
            return false;
          }

          var pSelectors = [
            '#mobile_number',
            'input[name="mobile_number"]',
            'input[formcontrolname="mobile_number"]',
            'input[type="tel"]',
            'input[placeholder*="Mobile"]'
          ];
          for (var i = 0; i < pSelectors.length; i++) {
            if (fill(pSelectors[i], ${jsonEncode(_savedPhone)})) break;
          }

          var passSelectors = [
            '#password',
            'input[name="password"]',
            'input[formcontrolname="password"]',
            'input[type="password"]'
          ];
          for (var j = 0; j < passSelectors.length; j++) {
            if (fill(passSelectors[j], ${jsonEncode(_savedPassword)})) break;
          }
        })();
      ''';

      await _controller!.runJavaScript(jsCode);

      if (!silent && mounted) {
        final lang = Provider.of<LanguageService>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text('${lang.t('autofill_done')}: $_savedPhone'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  void _navigateToSearch() {
    if (!mounted) return;
    final monitorService = context.read<MonitorService>();
    monitorService.clearErrors();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AppShell(
        initialTab: monitorService.dateOfJourney.isNotEmpty
          ? AppShell.tabMonitor : AppShell.tabSearch)),
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
              colors: [AppColors.appBarGradientStart, AppColors.appBarGradientEnd],
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
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              langService.t('app_subtitle'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
            tooltip: langService.t('autofill_btn'),
            icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
            onPressed: () => _insertSavedCredentials(silent: false),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: (isDark ? AppColors.darkBg : Colors.white).withValues(alpha: 0.88),
                child: FancyTrainLoader(
                  message: langService.t('loading_tickets'),
                  showCard: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
