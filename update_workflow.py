from pathlib import Path

p=Path('lib/models/auth_session.dart')
s=p.read_text(encoding='utf-8').replace("import 'package:shared_preferences/shared_preferences.dart';", "import '../services/secure_store.dart';")
s=s.replace('final rnd = math.Random();','final rnd = math.Random.secure();')
s=s.replace('// Give a 1-day grace period to absorb any timezone or device clock skew\n      return DateTime.now().isAfter(expDate.add(const Duration(days: 1)));','return !DateTime.now().isBefore(expDate);')
s=s.replace("        'password': password,\n",'')
s=s.replace('    final prefs = await SharedPreferences.getInstance();\n','')
s=s.replace('await prefs.setString(', 'await SecureStore.write(').replace('await prefs.remove(', 'await SecureStore.delete(')
s=s.replace("prefs.getString(_prefPhoneKey)","await SecureStore.read(_prefPhoneKey)").replace("prefs.getString(_prefPasswordKey)","await SecureStore.read(_prefPasswordKey)").replace("prefs.getString(_prefKey)","await SecureStore.read(_prefKey)")
p.write_text(s,encoding='utf-8')

p=Path('lib/services/api_service.dart'); s=p.read_text(encoding='utf-8')
s=s.replace("import 'dart:convert';", "import 'dart:convert';\nimport 'app_config.dart';")
s=s.replace("? 'SNIGDHA'", "? AppConfig.instance.string('default_seat_class')")
s=s.replace('const Duration(seconds: 15)',"Duration(seconds: AppConfig.instance.number('request_timeout_seconds'))")
start=s.index('    try {\n      final response = await http', s.index('static Future<SeatLayoutResponse>'))
end=s.index('\n  /// Provides realistic seat layout',start)
s=s[:start]+'''    if (authSession.cookie?.isNotEmpty == true) headers['Cookie'] = authSession.cookie!;
    final response = await http.get(uri, headers: headers).timeout(
      Duration(seconds: AppConfig.instance.number('request_timeout_seconds')),
    );
    if (response.statusCode != 200) {
      throw Exception('Seat layout request failed (${response.statusCode}). Retry or open the official booking page.');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['data'] is! Map || decoded['data']['seatLayout'] is! List) {
      throw const FormatException('Invalid seat layout response');
    }
    return SeatLayoutResponse.fromJson(decoded);
  }
''' +s[end:]
p.write_text(s,encoding='utf-8')

p=Path('lib/views/webview_login_screen.dart');s=p.read_text(encoding='utf-8')
s=s.replace("import '../models/auth_session.dart';", "import '../models/auth_session.dart';\nimport '../services/web_session_service.dart';")
s=s.replace('    _loadSavedCredentials();\n    _initWebView();','    _prepareWebView();')
at=s.index('  Future<void> _loadSavedCredentials()')
s=s[:at]+'''  Future<void> _prepareWebView() async {
    try {
      await _loadSavedCredentials();
      if (widget.clearSession) await WebSessionService.clear();
      if (mounted) _initWebView();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

'''+s[at:]
s=s.replace('          NavigationDelegate(','''          NavigationDelegate(
            onNavigationRequest: (request) => WebSessionService.isRailwayUrl(request.url)
                ? NavigationDecision.navigate : NavigationDecision.prevent,''',1)
s=s.replace('              await _installInterceptors();', '              if (!WebSessionService.isRailwayUrl(url)) return;\n              await _installInterceptors();')
start=s.index('      if (widget.clearSession) {');end=s.index('\n    } catch',start)
s=s[:start]+"      _controller!.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));"+s[end:]
s=s.replace('          window.__railInterceptorActive = true;','''          window.__railInterceptorActive = true;
          function captureCredentials() {
            var phone = document.querySelector('input[name="mobile_number"], input[type="tel"], #mobile_number');
            var pass = document.querySelector('input[type="password"]');
            if (phone && pass && phone.value && pass.value) {
              window.RailBridge.postMessage(JSON.stringify({type: 'CREDENTIALS', phone: phone.value, password: pass.value}));
            }
          }
          document.addEventListener('input', captureCredentials, true);
          document.addEventListener('submit', captureCredentials, true);''')
s=s.replace('  void _handleBridgeMessage(String raw) {\n    try {','''  Future<void> _handleBridgeMessage(String raw) async {
    if (!WebSessionService.isRailwayUrl(await _controller?.currentUrl())) return;
    try {''')
s=s.replace("      final type = map['type']?.toString();", """      final type = map['type']?.toString();
      if (type == 'CREDENTIALS') {
        _savedPhone = map['phone']?.toString() ?? '';
        _savedPassword = map['password']?.toString() ?? '';
        return;
      }""")
s=s.replace("final pwd = passController.text.trim();","final pwd = passController.text;")
s=s.replace("fill(pSelectors[i], '$_savedPhone')", "fill(pSelectors[i], ${jsonEncode(_savedPhone)})").replace("fill(passSelectors[j], '$_savedPassword')", "fill(passSelectors[j], ${jsonEncode(_savedPassword)})")
s=s.replace('    if (_controller == null) return;\n    if (_savedPhone', "    if (_controller == null || !WebSessionService.isRailwayUrl(await _controller!.currentUrl())) return;\n    if (_savedPhone")
p.write_text(s,encoding='utf-8')
