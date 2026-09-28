from pathlib import Path
def edit(path, fn):
 p=Path(path);p.write_text(fn(p.read_text(encoding='utf-8')),encoding='utf-8')

def monitor(s):
 s=s.replace("import 'dart:convert';", "import 'dart:convert';\nimport '../models/booking_intent.dart';\nimport 'app_config.dart';\nimport 'booking_service.dart';\nimport 'foreground_monitor.dart';")
 s=s.replace('  MonitorService({required this.proService});', '''  final bool backgroundWorker;
  BookingIntent bookingIntent = const BookingIntent();
  MonitorService({required this.proService, this.backgroundWorker = false});
  bool get _nativeMonitoring => !backgroundWorker && !kIsWeb && defaultTargetPlatform == TargetPlatform.android && ForegroundMonitor.initialized;
  Future<void> clearSearch() async {
    stopMonitoring();
    await _persistence;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(preferenceKey);
    _dateOfJourney = '';
    _lastTrains = [];
    notifyListeners();
  }
''')
 s=s.replace('    final prefs = await SharedPreferences.getInstance();\n    await prefs.reload();\n    final raw', '    await AppConfig.instance.reloadCache();\n    _intervalSeconds = AppConfig.instance.pollSeconds;\n    final prefs = await SharedPreferences.getInstance();\n    await prefs.reload();\n    final raw',1)
 s=s.replace("      _isMonitoring = data['active'] == true;", "      _isMonitoring = data['active'] == true;\n      bookingIntent = BookingIntent.fromJson(Map<String, dynamic>.from(data['bookingIntent'] ?? {}));")
 s=s.replace("      'expires': _expiresAt?.toIso8601String(),", "      'expires': _expiresAt?.toIso8601String(),\n      'bookingIntent': bookingIntent.toJson(),")
 s=s.replace('      try {\n        if (active)', '      try {\n        if (backgroundWorker) return;\n        if (active)',1)
 s=s.replace('    String? targetSeatClass,\n  }) {', '    String? targetSeatClass,\n    BookingIntent intent = const BookingIntent(),\n  }) {',1)
 s=s.replace('    _fromCity = fromCity;', '    bookingIntent = intent;\n    _intervalSeconds = AppConfig.instance.pollSeconds;\n    _fromCity = fromCity;',1)
 s=s.replace('DateTime.now().add(const Duration(hours: 1))', "DateTime.now().add(Duration(seconds: AppConfig.instance.number('free_monitor_seconds')))")
 s=s.replace('    final remaining = maxFreeSeconds - _elapsedMonitoringSeconds;', '    final remaining = _expiresAt?.difference(DateTime.now()).inSeconds ?? 0;')
 s=s.replace('(_elapsedMonitoringSeconds / maxFreeSeconds)', "(_elapsedMonitoringSeconds / AppConfig.instance.number('free_monitor_seconds'))")
 s=s.replace('    _checkTimer = Timer.periodic(\n      Duration(seconds: _intervalSeconds),\n      (_) => _executeCheck(),\n    );', '''    _checkTimer = Timer.periodic(
      Duration(seconds: _nativeMonitoring ? 5 : _intervalSeconds),
      (_) => _nativeMonitoring ? restore(startTimers: false) : _executeCheck(),
    );''')
 s=s.replace('    if (!_isMonitoring || _checking || _disposed) return;', '''    if (!_isMonitoring || _checking || _disposed) return;
    if (_nativeMonitoring) return;
    _intervalSeconds = AppConfig.instance.pollSeconds;''')
 target='        _lastTrains = response.trains;'
 s=s.replace(target,'''        if (bookingIntent.autoReserve && await BookingService.pending() == null) {
          final chosen = bookingIntent.choose(response.trains, train: _targetTrain, seatClass: _targetSeatClass);
          if (chosen != null) {
            try {
              final reservation = await BookingService.reserve(
                train: chosen.$1, seat: chosen.$2, from: _fromCity, to: _toCity,
                date: _dateOfJourney, auth: session,
                quantity: bookingIntent.quantity, maxFare: bookingIntent.maxFare,
              );
              await _notificationService.showReservation(reservation);
            } catch (error) {
              _lastError = error.toString();
              _addLog('Automatic reservation needs attention: $error', isError: true);
              await _notificationService.triggerSeatAvailableAlert(
                trainName: chosen.$1.tripNumber, seatType: chosen.$2.type,
                seatCount: chosen.$2.seatCounts.online, travelDate: _dateOfJourney,
                bookingLink: NotificationService.bookingUrl(_fromCity, _toCity, _dateOfJourney, chosen.$2.type),
              );
            }
          }
        }
''' +target)
 s=s.replace('Next in ${_intervalSeconds}s (2 min).','Next in ${_intervalSecondsSeconds}s.'.replace('_intervalSecondsSeconds','_intervalSeconds'))
 s=s.replace('⏱️ 1-Hour Free monitoring limit reached! Upgrade to Pro for 24/7 server monitoring.', 'Monitoring time limit reached. Start a new search to continue.')
 return s
edit('lib/services/monitor_service.dart', monitor)

def login(s):
 s=s.replace("import '../services/web_session_service.dart';", "import '../services/web_session_service.dart';\nimport '../services/secure_store.dart';")
 s=s.replace("          window.__railInterceptorActive = true;",'''          window.__railInterceptorActive = true;
          try {
            var handshake = JSON.parse(localStorage.getItem('handshake_data') || '{}');
            var cfg = handshake.data || handshake;
            var hold = cfg.release_time_interval_in_minutes;
            if (hold > 0) window.RailBridge.postMessage(JSON.stringify({type: 'HOLD_CONFIG', seconds: Math.ceil(hold / 60) * 60}));
          } catch (_) {}
''')
 s=s.replace("      if (type == 'CREDENTIALS') {", """      if (type == 'HOLD_CONFIG') {
        final seconds = map['seconds'];
        if (seconds is int && seconds > 0 && seconds <= 3600) await SecureStore.write('rail_hold_seconds', '$seconds');
        return;
      }
      if (type == 'CREDENTIALS') {""")
 return s
edit('lib/views/webview_login_screen.dart',login)

def api(s):
 s=s.replace("import 'app_config.dart';", "import 'app_config.dart';\nimport 'secure_store.dart';")
 pos=s.index('    if (response.statusCode != 200)',s.index('static Future<SeatLayoutResponse>'))
 s=s[:pos]+'''    final actionToken = response.headers['x-action-token'];
    if (actionToken != null) await SecureStore.write('rail_action_token', actionToken);
'''+s[pos:]
 return s
edit('lib/services/api_service.dart',api)

for path in ['lib/views/search_screen.dart','lib/views/monitor_dashboard_screen.dart']:
 def logout(s):
  s=s.replace("import 'package:webview_flutter/webview_flutter.dart';", "import '../services/web_session_service.dart';\nimport '../services/booking_service.dart';\nimport '../services/secure_store.dart';\nimport '../services/notification_service.dart';")
  if path.endswith('/search_screen.dart'):
   s=s.replace("import '../services/api_service.dart';", "import '../services/api_service.dart';\nimport '../services/monitor_service.dart';\nimport '../services/app_config.dart';")
   start=s.index('  final List<String> _popularStations = [');end=s.index("  String _fromCity",start)
   s=s[:start]+"  List<String> get _popularStations => AppConfig.instance.strings('stations');\n  List<String> get _seatClasses => AppConfig.instance.strings('seat_classes');\n\n"+s[end:]
   s=s.replace("String _selectedClass = 'SNIGDHA';", "String _selectedClass = 'ALL';")
   s=s.replace('  Future<void> _handleLogout() async {', '  Future<void> _handleLogout() async {\n    await context.read<MonitorService>().clearSearch();')
   s=s.replace('      Navigator.pushReplacement(\n        context,\n        MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)),\n      );', '      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)), (_) => false);')
  else:
   s=s.replace("import '../services/api_service.dart';", "import '../services/app_config.dart';")
   s=s.replace('      context.read<MonitorService>().stopMonitoring();','      await context.read<MonitorService>().clearSearch();')
   start=s.index('                // Quick test trigger');end=s.index('\n              ],',start)
   s=s[:start]+s[end:]
   s=s.replace("'Scanning Bangladesh Railway every 15s. The moment any seat is released or cancelled, instant booking will appear here.'", "'Checking every ${AppConfig.instance.pollSeconds ~/ 60} minutes while monitoring is active. Android may delay checks.'")
   s=s.replace("'নোটিফায়ার প্রতি ১৫ সেকেন্ড পর পর স্বয়ংক্রিয়ভাবে চেক করছে। কোনো যাত্রী টিকিট বাতিল করা মাত্র সাথে সাথে এখানে বুকিং অপশন দেখা যাবে।'", "'প্রতি ${AppConfig.instance.pollSeconds ~/ 60} মিনিটে পরীক্ষা করা হবে। Android পরীক্ষা বিলম্বিত করতে পারে।'")
  s=s.replace('await WebViewCookieManager().clearCookies();','await WebSessionService.clear();')
  s=s.replace('await AuthSession.clearSavedUserCredentials();', "await BookingService.clear();\n    await SecureStore.delete('rail_action_token');\n    await SecureStore.delete('rail_hold_seconds');\n    await NotificationService().clearAlerts();")
  return s
 edit(path,logout)
