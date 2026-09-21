import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/auth_session.dart';
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
    _loadSavedCredentials();
    _initWebView();
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
            onPageStarted: (url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (url) async {
              if (mounted) setState(() => _isLoading = false);
              await _installInterceptors();
              await _insertSavedCredentials(silent: true);
              await _checkLiveSession();
            },
            onWebResourceError: (error) {
              if (mounted) setState(() => _isLoading = false);
            },
          ),
        );

      if (widget.clearSession) {
        // Clear cookies first, then load the login page
        WebViewCookieManager().clearCookies().whenComplete(() {
          _controller!.runJavaScript('localStorage.clear(); sessionStorage.clear();').catchError((_) {});
          _controller!.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));
        });
      } else {
        _controller!.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));
      }
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
                  if (t && window.RailBridge) {
                    window.RailBridge.postMessage(JSON.stringify({
                      type: 'AUTH_SUCCESS',
                      token: t,
                      deviceId: devId,
                      deviceKey: devKey,
                      user: usr,
                      cookie: document.cookie || ''
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
                if (t && window.RailBridge) {
                  window.RailBridge.postMessage(JSON.stringify({
                    type: 'AUTH_SUCCESS',
                    token: t,
                    deviceId: devId,
                    deviceKey: devKey,
                    user: usr,
                    cookie: document.cookie || ''
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
                if (window.RailBridge) {
                  window.RailBridge.postMessage(JSON.stringify({
                    type: 'STORAGE_TOKEN',
                    token: t,
                    deviceId: devId,
                    deviceKey: devKey,
                    user: usr,
                    cookie: document.cookie || '',
                    currentPath: pathname
                  }));
                }
              }
            } catch(e) {}
          }, 1500);
        })();
      ''';
      await _controller!.runJavaScript(script);
    } catch (_) {}
  }

  bool _hasNavigated = false;

  void _handleBridgeMessage(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type']?.toString();

      if (type == 'AUTH_SUCCESS' || type == 'STORAGE_TOKEN') {
        final token = map['token']?.toString() ?? '';
        final deviceId = map['deviceId']?.toString() ?? '';
        final deviceKey = map['deviceKey']?.toString() ?? '';
        final cookie = map['cookie']?.toString() ?? '';
        final currentPath = map['currentPath']?.toString() ?? '';

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
          return JSON.stringify({
            token: t,
            deviceId: devId,
            deviceKey: devKey,
            user: usr,
            cookie: cookie
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
        _saveAndNavigate(
          token: rawToken,
          deviceId: map['deviceId']?.toString() ?? '',
          deviceKey: map['deviceKey']?.toString() ?? '',
          cookie: map['cookie']?.toString() ?? '',
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
    final phone = phoneNumber ??
        payload?['phone_number']?.toString() ??
        payload?['username']?.toString() ??
        _savedPhone;
    final name = displayName ?? payload?['display_name']?.toString();
    final mail = email ?? payload?['email']?.toString();

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
              final pwd = passController.text.trim();
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
    if (_controller == null) return;
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
            if (fill(pSelectors[i], '$_savedPhone')) break;
          }

          var passSelectors = [
            '#password',
            'input[name="password"]',
            'input[formcontrolname="password"]',
            'input[type="password"]'
          ];
          for (var j = 0; j < passSelectors.length; j++) {
            if (fill(passSelectors[j], '$_savedPassword')) break;
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) =>
        monitorService.dateOfJourney.isNotEmpty
          ? const MonitorDashboardScreen() : const SearchScreen()),
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
        backgroundColor: AppColors.appBarGreen,
        elevation: 2,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white24,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.confirmation_number, color: Colors.white, size: 20),
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
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          // Language switcher
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: langService.toggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                langService.isBangla ? 'EN' : 'বাং',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          IconButton(
            tooltip: isDark ? 'লাইট মোড' : 'ডার্ক মোড',
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            onPressed: themeService.toggleTheme,
          ),
          IconButton(
            tooltip: langService.t('autofill_btn'),
            icon: const Icon(Icons.edit_note, color: Colors.white),
            onPressed: () => _insertSavedCredentials(silent: false),
          ),
          IconButton(
            tooltip: 'রিফ্রেশ',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else
            const Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.85),
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
