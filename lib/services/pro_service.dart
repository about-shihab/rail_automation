import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_session.dart';

class ProService extends ChangeNotifier {
  static const String _prefProKey = 'br_user_is_pro';
  static const int freeMonitoringSecondsLimit = 3600; // 1 Hour (60 minutes)

  bool _isPro = false;
  bool _isServerSyncing = false;
  String? _serverMonitorTaskId;

  bool get isPro => _isPro;
  bool get isServerSyncing => _isServerSyncing;
  String? get serverMonitorTaskId => _serverMonitorTaskId;

  ProService() {
    _loadProStatus();
  }

  Future<void> _loadProStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = prefs.getBool(_prefProKey) ?? false;
    notifyListeners();
  }

  Future<void> setProStatus(bool value) async {
    _isPro = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefProKey, value);
    notifyListeners();
  }

  /// Sends session and target train info to cloud server for 24/7 background checking
  Future<bool> startServerCloudMonitoring({
    required AuthSession session,
    required String fromCity,
    required String toCity,
    required String dateOfJourney,
    String? targetTrain,
    String? targetSeatClass,
  }) async {
    if (!_isPro) return false;

    _isServerSyncing = true;
    notifyListeners();

    try {
      // Simulate/Send session payload to backend server
      // In production, this calls: POST https://your-server-api.com/v1/monitor/start
      await Future.delayed(const Duration(milliseconds: 1200));
      _serverMonitorTaskId = 'SRV-TASK-${DateTime.now().millisecondsSinceEpoch}';
      _isServerSyncing = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isServerSyncing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stopServerCloudMonitoring() async {
    _serverMonitorTaskId = null;
    notifyListeners();
  }
}
