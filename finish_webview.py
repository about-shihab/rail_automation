from pathlib import Path
p=Path('lib/views/booking_screen.dart');s=p.read_text(encoding='utf-8')
s="import 'dart:convert';\nimport '../services/booking_service.dart';\nimport '../services/secure_store.dart';\nimport '../services/web_session_service.dart';\n"+s
s=s.replace('      final session = await AuthSession.load();','''      final session = await AuthSession.load();
      if (!WebSessionService.isRailwayUrl(widget.url)) throw StateError('Invalid Railway booking link');
      final reservation = await BookingService.pending();
      bool bootstrapped = false;''')
start=s.index('              // Inject token');end=s.index('\n            },\n            onWebResourceError',start)
s=s[:start]+'''              if (!WebSessionService.isRailwayUrl(url) || bootstrapped) return;
              bootstrapped = true;
              if (session != null && session.isValid) {
                final userRaw = await SecureStore.read('rail_user');
                final values = <String, String>{
                  'token': session.token.startsWith('Bearer ') ? session.token.substring(7) : session.token,
                  'uudid': session.deviceId, 'ssdk': session.deviceKey,
                  if (userRaw != null) 'user': userRaw,
                };
                Map<String, dynamic> storage = {};
                if (reservation != null && ['awaitingOtp', 'readyForPayment'].contains(reservation['status'])) {
                  final user = userRaw == null ? <String, dynamic>{} : jsonDecode(userRaw) as Map<String, dynamic>;
                  final phone = user['phone_number']?.toString() ?? session.phoneNumber ?? '';
                  if (phone.isNotEmpty && reservation['expiresAt'] != null) {
                    storage = BookingService.webStorage(reservation, phone);
                  }
                }
                await _controller?.runJavaScript(
                  'Object.entries(${jsonEncode(values)}).forEach(([k,v]) => localStorage.setItem(k,v));'
                  'Object.entries(${jsonEncode(storage)}).forEach(([k,v]) => sessionStorage.setItem(k,String(v)));'
                );
                await _controller?.loadRequest(Uri.parse(widget.url));
              }
''' +s[end:]
s=s.replace("      await controller.loadRequest(Uri.parse(widget.url));", "      await controller.loadRequest(Uri.parse('https://eticket.railway.gov.bd/login'));")
s=s.replace("'eticket.railway.gov.bd • 5-Min Holding Window'", "'Complete booking securely with Bangladesh Railway'")
p.write_text(s,encoding='utf-8')

p=Path('lib/views/webview_login_screen.dart');s=p.read_text(encoding='utf-8')
s=s.replace('        if (token.isNotEmpty && !AuthSession.isDummyToken(token)) {', "        if (user.isNotEmpty) await SecureStore.write('rail_user', jsonEncode(user));\n        if (token.isNotEmpty && !AuthSession.isDummyToken(token)) {")
s=s.replace('  bool _hasNavigated = false;', '  bool _hasNavigated = false;')
p.write_text(s,encoding='utf-8')

# Existing widget/unit tests use the plugin test store; production never falls back to plaintext.
for p in Path('test').glob('*.dart'):
 s=p.read_text(encoding='utf-8')
 if 'SharedPreferences.setMockInitialValues' in s:
  s="import 'package:flutter_secure_storage/flutter_secure_storage.dart';\n"+s
  s=s.replace('SharedPreferences.setMockInitialValues(', 'FlutterSecureStorage.setMockInitialValues({});\n    SharedPreferences.setMockInitialValues(')
  p.write_text(s,encoding='utf-8')

for path in ['lib/views/search_screen.dart','lib/views/monitor_dashboard_screen.dart']:
 p=Path(path);s=p.read_text(encoding='utf-8').replace("await SecureStore.delete('rail_hold_seconds');", "await SecureStore.delete('rail_hold_seconds');\n    await SecureStore.delete('rail_user');")
 p.write_text(s,encoding='utf-8')
