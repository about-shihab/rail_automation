import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/auth_session.dart';
import '../models/train_trip.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';

class MonitorLog {
  final DateTime time;
  final String message;
  final bool isAlert;
  final bool isError;

  MonitorLog({
    required this.time,
    required this.message,
    this.isAlert = false,
    this.isError = false,
  });
}

class MonitorService extends ChangeNotifier {
  final NotificationService _notificationService = NotificationService();
  final ProService proService;

  MonitorService({required this.proService});

  bool _isMonitoring = false;
  int _intervalSeconds = 120; // Default: 2 minutes periodically as requested
  int _secondsUntilNextCheck = 120;
  Timer? _checkTimer;
  Timer? _secondTicker;

  String _fromCity = 'Dhaka';
  String _toCity = 'Chattogram';
  String _dateOfJourney = '';
  String? _targetTrain; // If null, monitors all trains on route
  String? _targetSeatClass; // If null, monitors any seat class

  DateTime? _lastCheckedAt;
  int _totalChecksCount = 0;
  int _seatsFoundCount = 0;
  String? _lastError;
  List<TrainTrip> _lastTrains = [];
  final List<MonitorLog> _logs = [];

  // 1-Hour Monitoring Limit variables
  int _elapsedMonitoringSeconds = 0;
  static const int maxFreeSeconds = 3600; // 1 Hour (60 minutes)
  bool _isLimitReached = false;

  // Getters
  bool get isMonitoring => _isMonitoring;
  int get intervalSeconds => _intervalSeconds;
  int get secondsUntilNextCheck => _secondsUntilNextCheck;
  String get fromCity => _fromCity;
  String get toCity => _toCity;
  String get dateOfJourney => _dateOfJourney;
  String? get targetTrain => _targetTrain;
  String? get targetSeatClass => _targetSeatClass;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  int get totalChecksCount => _totalChecksCount;
  int get seatsFoundCount => _seatsFoundCount;
  String? get lastError => _lastError;
  List<TrainTrip> get lastTrains => List.unmodifiable(_lastTrains);
  List<MonitorLog> get logs => List.unmodifiable(_logs);

  int get elapsedMonitoringSeconds => _elapsedMonitoringSeconds;
  bool get isLimitReached => _isLimitReached;

  int get remainingFreeSeconds {
    if (proService.isPro) return -1; // Unlimited
    final remaining = maxFreeSeconds - _elapsedMonitoringSeconds;
    return remaining > 0 ? remaining : 0;
  }

  double get freeProgressFraction {
    if (proService.isPro) return 1.0;
    return (_elapsedMonitoringSeconds / maxFreeSeconds).clamp(0.0, 1.0);
  }

  String get remainingTimeFormatted {
    if (proService.isPro) return 'UNLIMITED (PRO)';
    final seconds = remainingFreeSeconds;
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} remaining';
  }

  void setInterval(int seconds) {
    _intervalSeconds = seconds.clamp(10, 300);
    notifyListeners();
    if (_isMonitoring) {
      _restartTimer();
    }
  }

  void startMonitoring({
    required String fromCity,
    required String toCity,
    required String dateOfJourney,
    String? targetTrain,
    String? targetSeatClass,
  }) {
    _fromCity = fromCity;
    _toCity = toCity;
    _dateOfJourney = dateOfJourney;
    _targetTrain = targetTrain;
    _targetSeatClass = targetSeatClass;
    _isMonitoring = true;
    _totalChecksCount = 0;
    _seatsFoundCount = 0;
    _lastError = null;
    _isLimitReached = false;

    _addLog(
      'Started monitoring: $fromCity ➔ $toCity ($dateOfJourney) '
      '| Train: ${_targetTrain ?? "ALL"} | Class: ${_targetSeatClass ?? "ANY"}'
      '${proService.isPro ? " [PRO UNLIMITED]" : " [1-HOUR FREE LIMIT]"}',
    );

    notifyListeners();
    _executeCheck();
    _restartTimer();
    _startSecondTicker();
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _secondTicker?.cancel();
    _secondTicker = null;
    _isMonitoring = false;
    _addLog('Monitoring stopped by user.');
    notifyListeners();
  }

  void _startSecondTicker() {
    _secondTicker?.cancel();
    _secondsUntilNextCheck = _intervalSeconds;
    _secondTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }

      _elapsedMonitoringSeconds++;
      if (_secondsUntilNextCheck > 0) {
        _secondsUntilNextCheck--;
      } else {
        _secondsUntilNextCheck = _intervalSeconds;
      }

      // Check 1-hour limit for free users
      if (!proService.isPro && _elapsedMonitoringSeconds >= maxFreeSeconds) {
        _isLimitReached = true;
        stopMonitoring();
        _addLog(
          '⏱️ 1-Hour Free monitoring limit reached! Upgrade to Pro for 24/7 server monitoring.',
          isAlert: true,
        );
      }

      notifyListeners();
    });
  }

  void _restartTimer() {
    _checkTimer?.cancel();
    _secondsUntilNextCheck = _intervalSeconds;
    _checkTimer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (_) => _executeCheck(),
    );
  }

  Future<void> _executeCheck() async {
    final session = await AuthSession.load();
    if (session == null || !session.isValid) {
      _lastError = 'Not logged in. Please authenticate with Railway credentials.';
      _addLog('Check skipped: No valid login session found.', isError: true);
      notifyListeners();
      return;
    }

    _secondsUntilNextCheck = _intervalSeconds;

    try {
      _lastCheckedAt = DateTime.now();
      _totalChecksCount++;

      TripSearchResponse response;
      try {
        response = await ApiService.searchTrips(
          fromCity: _fromCity,
          toCity: _toCity,
          dateOfJourney: _dateOfJourney,
          seatClass: _targetSeatClass,
          authSession: session,
        );
      } catch (apiErr) {
        final errStr = apiErr.toString().replaceAll("Exception: ", "");
        _lastError = errStr;
        _addLog(
          'Check failed: $errStr. Retrying in ${_intervalSeconds}s.',
          isError: true,
        );
        notifyListeners();
        return;
      }

      _lastTrains = response.trains;
      _lastError = null;

      // Evaluate availability
      bool foundSeats = false;
      for (final train in response.trains) {
        if (_targetTrain != null &&
            _targetTrain!.isNotEmpty &&
            !train.tripNumber.toLowerCase().contains(_targetTrain!.toLowerCase())) {
          continue;
        }

        for (final seat in train.seatTypes) {
          if (_targetSeatClass != null &&
              _targetSeatClass!.isNotEmpty &&
              _targetSeatClass != 'ALL' &&
              seat.type.toUpperCase() != _targetSeatClass!.toUpperCase()) {
            continue;
          }

          if (seat.seatCounts.online > 0) {
            foundSeats = true;
            _seatsFoundCount += seat.seatCounts.online;
            _addLog(
              '🎉 SEATS FOUND! ${train.tripNumber} has ${seat.seatCounts.online} [${seat.type}] seats!',
              isAlert: true,
            );

            try {
              await _notificationService.triggerSeatAvailableAlert(
                trainName: train.tripNumber,
                seatType: seat.displayName,
                seatCount: seat.seatCounts.online,
                travelDate: _dateOfJourney,
              );
            } catch (_) {}
          }
        }
      }

      if (!foundSeats) {
        _addLog(
          '#$_totalChecksCount checked at ${_formatTime(_lastCheckedAt!)}: No online seats yet. Next in ${_intervalSeconds}s (2 min).',
        );
      }
    } catch (e) {
      _lastError = e.toString();
      _addLog('Check error: $e', isError: true);
    }

    notifyListeners();
  }

  void _addLog(String message, {bool isAlert = false, bool isError = false}) {
    _logs.insert(
      0,
      MonitorLog(
        time: DateTime.now(),
        message: message,
        isAlert: isAlert,
        isError: isError,
      ),
    );
    if (_logs.length > 200) {
      _logs.removeLast();
    }
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _secondTicker?.cancel();
    super.dispose();
  }
}
