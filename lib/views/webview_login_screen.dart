import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/auth_session.dart';
import '../services/theme_service.dart';
import '../utils/app_theme.dart';
import 'search_screen.dart';

class WebviewLoginScreen extends StatefulWidget {
  const WebviewLoginScreen({super.key});

  @override
  State<WebviewLoginScreen> createState() => _WebviewLoginScreenState();
}

class _WebviewLoginScreenState extends State<WebviewLoginScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  final String _savedPhone = '01813570430';
  final String _savedPassword = r'7nL*2!fk@sNCfxC';

  @override
  void initState() {
    super.initState();
    _initWebView();
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
        )
        ..loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));
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
    _navigateToSearch();
  }

  Future<void> _insertSavedCredentials({bool silent = false}) async {
    if (_controller == null) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text('স্বয়ংক্রিয় তথ্য পূরণ সম্পন্ন: $_savedPhone'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  void _navigateToSearch() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = Provider.of<ThemeService>(context);

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
          children: const [
            Text(
              'টিকেট আছে',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              'বাংলাদেশ রেলওয়ে লগইন',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'লাইট মোড চালু করুন' : 'ডার্ক মোড চালু করুন',
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            onPressed: themeService.toggleTheme,
          ),
          IconButton(
            tooltip: 'স্বয়ংক্রিয় তথ্য পূরণ',
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
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Color(0xFF34D399),
              ),
            ),
        ],
      ),
    );
  }
}
