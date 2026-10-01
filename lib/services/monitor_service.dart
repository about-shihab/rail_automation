import 'dart:async';
import 'dart:convert';

import '../models/booking_intent.dart';
import 'app_config.dart';
import 'booking_service.dart';
import 'credit_service.dart';
import 'foreground_monitor.dart';
import 'otp_verifier.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/auth_session.dart';
import '../models/train_trip.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';
import 'background_monitor.dart';
import 'firebase_user_service.dart';
import 'secure_store.dart';
import 'trip_history_service.dart';
import '../models/trip_record.dart';
import 'package:flutter/material.dart';
import '../widgets/turnstile_sheet.dart';
import '../views/reservation_screen.dart';
import 'overlay_service.dart';
import '../utils/friendly_error.dart';

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

  final bool backgroundWorker;
  BookingIntent bookingIntent = const BookingIntent();
  MonitorService({required this.proService, this.backgroundWorker = false});
  bool get _nativeMonitoring =>
      !backgroundWorker &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      ForegroundMonitor.initialized &&
      backgroundError == null;
  Timer? _autoClearSearchTimer;

  void _scheduleAutoClearSearchAfter5Minutes() {
    _autoClearSearchTimer?.cancel();
    _autoClearSearchTimer = Timer(const Duration(minutes: 5), () async {
      await clearSearch();
      _addLog('⏱️ 5 minutes passed after booking/OTP. Search cleared automatically.', isAlert: true);
    });
  }

  Future<void> clearSearch() async {
    _autoClearSearchTimer?.cancel();
    stopMonitoring();
    await _persistence;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(preferenceKey);
    _dateOfJourney = '';
    _lastTrains = [];
    _lastError = null;
    _lastBookingError = null;
    try {
      await BookingService.clear();
      await NotificationService().cancelReservationAlerts();
    } catch (_) {}
    notifyListeners();
  }

  static const preferenceKey = 'active_ticket_search';
  String? _searchId;
  DateTime? _expiresAt;
  DateTime? _startedAt;
  bool _checking = false;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _persistence = Future.value();
  String? backgroundError;

  Future<void> restore({bool startTimers = true}) async {
    await AppConfig.instance.reloadCache();
    _intervalSeconds = AppConfig.instance.pollSeconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(preferenceKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _fromCity = data['from'] as String;
      _toCity = data['to'] as String;
      _dateOfJourney = data['date'] as String;
      if (data['trains'] is List) {
        _targetTrains = (data['trains'] as List).map((e) => e.toString()).toList();
      } else if (data['train'] is String && (data['train'] as String).isNotEmpty) {
        final t = data['train'] as String;
        _targetTrains = t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      } else {
        _targetTrains = [];
      }
      _targetTrain = _targetTrains.isNotEmpty ? _targetTrains.join(', ') : (data['train'] as String?);
      final rawSeat = data['seat'] as String?;
      _targetSeatClass = (rawSeat == null ||
              rawSeat.trim().isEmpty ||
              rawSeat.trim().toUpperCase() == 'ALL' ||
              rawSeat.trim().toUpperCase() == 'RANDOM')
          ? null
          : rawSeat.trim().toUpperCase();
      _searchId = data['id'] as String;
      final status = prefs.getString('ticket_status_$_searchId');
      if (status != null) {
        final savedStatus = jsonDecode(status) as Map<String, dynamic>;
        _lastError = savedStatus['error'] as String?;
        _lastCheckedAt = DateTime.tryParse(savedStatus['checkedAt'] ?? '');
      }
      _expiresAt = DateTime.tryParse(data['expires'] ?? '');
      if (_expiresAt == null || _expiresAt!.difference(DateTime.now()).inHours <= 1) {
        final dep = parseDepartureDateTime(dateOfJourney: _dateOfJourney);
        if (dep != null && dep.isAfter(DateTime.now())) {
          _expiresAt = dep;
        }
      }
      _isMonitoring = data['active'] == true;
      bookingIntent = BookingIntent.fromJson(
        Map<String, dynamic>.from(data['bookingIntent'] ?? {}),
      );
      if (_targetTrains.isNotEmpty && bookingIntent.targetTrains.isEmpty) {
        bookingIntent = bookingIntent.copyWith(targetTrains: _targetTrains);
      }
      final result = prefs.getString('ticket_results_$_searchId');
      if (result != null) {
        _lastTrains = (jsonDecode(result) as List)
            .map((e) => TrainTrip.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _seatsFoundCount = _lastTrains
            .where((t) => isTrainMonitored(t.tripNumber))
            .expand((t) => t.seatTypes)
            .where(
              (s) =>
                  _targetSeatClass == null ||
                  _targetSeatClass == 'ALL' ||
                  _targetSeatClass == 'RANDOM' ||
                  s.type.toUpperCase() == _targetSeatClass!.toUpperCase(),
            )
            .fold(0, (sum, seat) => sum + seat.seatCounts.online);
      }
      if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
        _isMonitoring = false;
        _isLimitReached = true;
      }
      if (_isMonitoring && startTimers) {
        if (_nativeMonitoring) {
          try {
            await BackgroundMonitor.schedule();
          } catch (_) {
            backgroundError = 'Keep the app open to continue searching';
          }
        }
        _restartTimer();
        _startSecondTicker();
        unawaited(checkNow());
      }
      notifyListeners();
    } catch (_) {
      /* Ignore an incomplete saved search. */
    }
  }

  Future<void> _saveAndSchedule() async {
    final active = _isMonitoring;
    final data = jsonEncode({
      'id': _searchId,
      'from': _fromCity,
      'to': _toCity,
      'date': _dateOfJourney,
      'train': _targetTrains.isNotEmpty ? _targetTrains.join(', ') : _targetTrain,
      'trains': _targetTrains,
      'seat': _targetSeatClass,
      'active': _isMonitoring,
      'expires': _expiresAt?.toIso8601String(),
      'bookingIntent': bookingIntent.toJson(),
    });
    _persistence = _persistence.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, data);
      try {
        if (backgroundWorker) return;
        if (active) {
          await BackgroundMonitor.schedule();
        } else {
          await BackgroundMonitor.cancel();
        }
      } catch (_) {
        backgroundError =
            'অ্যাপ খোলা রাখুন • Keep the app open to continue searching';
        notifyListeners();
      }
    });
    await _persistence;
  }

  Future<void> checkNow() => _executeCheck();

  void suspendForegroundTimers() {
    _checkTimer?.cancel();
    _secondTicker?.cancel();
  }

  bool _isMonitoring = false;
  int _intervalSeconds = 120; // Default: 2 minutes periodically as requested
  int _secondsUntilNextCheck = 120;
  Timer? _checkTimer;
  Timer? _secondTicker;

  String _fromCity = 'Dhaka';
  String _toCity = 'Chattogram';
  String _dateOfJourney = '';
  List<String> _targetTrains = [];
  String? _targetTrain; // If null/empty, monitors all trains on route
  String? _targetSeatClass; // If null, monitors any seat class

  DateTime? _lastCheckedAt;
  int _totalChecksCount = 0;
  int _seatsFoundCount = 0;
  String? _lastError;
  String? _lastBookingError;
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
  List<String> get targetTrains => List.unmodifiable(_targetTrains);
  String? get targetTrain {
    if (_targetTrains.isNotEmpty) {
      return _targetTrains.length == 1 ? _targetTrains.first : _targetTrains.join(', ');
    }
    return _targetTrain;
  }

  bool isTrainMonitored(String trainName) {
    if (!_isMonitoring) return false;
    final clean = trainName.trim().toLowerCase();
    if (_targetTrains.isEmpty && (_targetTrain == null || _targetTrain == 'ALL' || _targetTrain!.isEmpty)) {
      return true;
    }
    return _targetTrains.any((t) => t.trim().toLowerCase() == clean) ||
        (_targetTrain != null && _targetTrain!.trim().toLowerCase() == clean);
  }

  void addTrainToMonitoring(String trainName) {
    final clean = trainName.trim();
    if (clean.isEmpty) return;
    if (!_targetTrains.any((t) => t.toLowerCase() == clean.toLowerCase())) {
      _targetTrains.add(clean);
      _targetTrain = _targetTrains.join(', ');
      bookingIntent = bookingIntent.copyWith(targetTrains: _targetTrains);
      _addLog('➕ Added $clean to active auto-booking (Total: ${_targetTrains.length} trains)');
      unawaited(_saveAndSchedule());
      notifyListeners();
    }
  }

  void removeTrainFromMonitoring(String trainName) {
    final clean = trainName.trim();
    _targetTrains.removeWhere((t) => t.toLowerCase() == clean.toLowerCase());
    _targetTrain = _targetTrains.isNotEmpty ? _targetTrains.join(', ') : null;
    bookingIntent = bookingIntent.copyWith(targetTrains: _targetTrains);
    _addLog('➖ Removed $clean from active auto-booking (Remaining: ${_targetTrains.length} trains)');
    unawaited(_saveAndSchedule());
    notifyListeners();
  }

  String? get targetSeatClass => _targetSeatClass;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  int get totalChecksCount => _totalChecksCount;
  int get seatsFoundCount => _seatsFoundCount;
  String? get lastError => _lastError;
  String? get lastBookingError => _lastBookingError;

  bool _turnstileRequestedForBooking = false;
  bool _lastReservationExpired = false;
  bool get lastReservationExpired => _lastReservationExpired;

  void clearBookingError() {
    _lastBookingError = null;
    _turnstileRequestedForBooking = false;
    notifyListeners();
  }

  void onTurnstileSolved(String token) {
    _turnstileRequestedForBooking = false;
    _lastBookingError = null;
    if (_lastError != null &&
        RegExp(r'422|turnstile|cft_response', caseSensitive: false).hasMatch(_lastError!)) {
      _lastError = null;
    }
    notifyListeners();
    unawaited(SecureStore.write('rail_cft_token', token));
    unawaited(SecureStore.write(
      'rail_cft_token_time',
      DateTime.now().millisecondsSinceEpoch.toString(),
    ));
    unawaited(OverlayService.dismiss());
    TurnstileDialog.dismiss();
    checkNow();
  }

  Future<void> reAutoBook() async {
    if (CreditService().credits <= 0) {
      _lastError = 'Cannot auto-book: 0 credits remaining. Please buy credits.';
      notifyListeners();
      return;
    }
    await BookingService.clear();
    _lastReservationExpired = false;
    _lastBookingError = null;
    _turnstileRequestedForBooking = false;
    bookingIntent = bookingIntent.copyWith(autoReserve: true);
    await _saveAndSchedule();
    notifyListeners();
    await checkNow();
  }

  void clearErrors() {
    _lastError = null;
    _lastBookingError = null;
    _turnstileRequestedForBooking = false;
    notifyListeners();
  }

  void setErrorForTesting({String? error, String? bookingError}) {
    if (error != null) _lastError = error;
    if (bookingError != null) _lastBookingError = bookingError;
    notifyListeners();
  }
  bool get needsTurnstile =>
      (_lastBookingError != null &&
          RegExp(
            r'422|turnstile|verification|human check|cft_response',
            caseSensitive: false,
          ).hasMatch(_lastBookingError!)) ||
      (_lastError != null &&
          RegExp(
            r'422|turnstile|verification|human check|cft_response',
            caseSensitive: false,
          ).hasMatch(_lastError!));
  bool get needsLogin =>
      _lastError != null &&
      RegExp(
        r'login|logged in|session expired|401|authenticate',
        caseSensitive: false,
      ).hasMatch(_lastError!);
  String get userStatus {
    if (backgroundError != null) {
      return 'Keep the app open while we reconnect background searching.';
    }
    if (needsLogin) {
      return 'Sign in to Railway again so we can continue your search.';
    }
    if (_lastError != null &&
        RegExp(
          r'403|422|verification|seat.layout',
          caseSensitive: false,
        ).hasMatch(_lastError!)) {
      return 'Railway needs verification before we can reserve a seat. Continue securely with Railway.';
    }
    if (_lastError != null) {
      return 'We couldn’t complete the last check. We’ll try again while your search is active.';
    }
    return 'We’re checking for your seats. We’ll notify you when your booking needs attention.';
  }

  Future<bool> _savedSearchIsActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(preferenceKey);
    if (raw == null) return false;
    final saved = jsonDecode(raw) as Map<String, dynamic>;
    return saved['id'] == _searchId && saved['active'] == true;
  }

  List<TrainTrip> get lastTrains => List.unmodifiable(_lastTrains);
  List<MonitorLog> get logs => List.unmodifiable(_logs);

  /// Parses departure date and time from various Bangladesh Railway formats.
  static DateTime? parseDepartureDateTime({
    String? departureDateTimeJd,
    String? departureDateTime,
    String? dateOfJourney,
    String? departureFullDate,
  }) {
    if (departureDateTimeJd != null && departureDateTimeJd.trim().isNotEmpty) {
      final s = departureDateTimeJd.trim();
      final withoutDay = s.replaceAll(RegExp(r'^[A-Za-z]+,\s*'), '').trim();
      for (final pattern in [
        'dd MMM yyyy, hh:mm a',
        'dd MMM yyyy, HH:mm',
        'EEE, dd MMM yyyy, hh:mm a',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-ddTHH:mm:ss',
      ]) {
        try {
          return DateFormat(pattern).parse(withoutDay);
        } catch (_) {}
        try {
          return DateFormat(pattern).parse(s);
        } catch (_) {}
      }
    }

    DateTime? baseDate;
    if (dateOfJourney != null && dateOfJourney.trim().isNotEmpty) {
      for (final pattern in ['dd-MMM-yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy']) {
        try {
          baseDate = DateFormat(pattern).parse(dateOfJourney.trim());
          break;
        } catch (_) {}
      }
    }
    if (baseDate == null && departureFullDate != null && departureFullDate.trim().isNotEmpty) {
      for (final pattern in ['yyyy-MM-dd', 'dd-MMM-yyyy']) {
        try {
          baseDate = DateFormat(pattern).parse(departureFullDate.trim());
          break;
        } catch (_) {}
      }
    }

    if (baseDate != null) {
      if (departureDateTime != null && departureDateTime.trim().isNotEmpty) {
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(am|pm)?', caseSensitive: false)
            .firstMatch(departureDateTime);
        if (match != null) {
          int hour = int.parse(match.group(1)!);
          final minute = int.parse(match.group(2)!);
          final period = match.group(3)?.toLowerCase();
          if (period == 'pm' && hour < 12) hour += 12;
          if (period == 'am' && hour == 12) hour = 0;
          return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
        }
      }
      return DateTime(baseDate.year, baseDate.month, baseDate.day, 23, 59, 59);
    }
    return null;
  }

  int get elapsedMonitoringSeconds => _elapsedMonitoringSeconds;
  bool get isLimitReached => _isLimitReached;

  int get remainingFreeSeconds {
    final remaining = _expiresAt?.difference(DateTime.now()).inSeconds ?? 0;
    return remaining > 0 ? remaining : 0;
  }

  double get freeProgressFraction {
    if (_expiresAt == null) return 1.0;
    final totalSecs = _expiresAt!.difference(_startedAt ?? DateTime.now()).inSeconds;
    if (totalSecs <= 0) return 1.0;
    final remaining = remainingFreeSeconds;
    return (1.0 - (remaining / totalSecs)).clamp(0.0, 1.0);
  }

  String get remainingTimeFormatted {
    final seconds = remainingFreeSeconds;
    if (seconds <= 0) return 'Departed';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (days > 0) {
      return '${days}d ${hours}h remaining';
    }
    if (hours > 0) {
      return '${hours}h ${mins.toString().padLeft(2, '0')}m remaining';
    }
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
    List<String>? targetTrains,
    String? targetSeatClass,
    BookingIntent intent = const BookingIntent(),
    DateTime? departureTime,
    String? departureDateTime,
    String? departureDateTimeJd,
  }) {
    // ── SINGLE ACTIVE NOTIFIER RULE ──────────────────────────────────────────
    // If a previous monitoring session is running, stop it first before
    // starting the new one. This ensures only ONE notifier is ever active.
    if (_isMonitoring) {
      _generation++;
      _checkTimer?.cancel();
      _checkTimer = null;
      _secondTicker?.cancel();
      _secondTicker = null;
      _isMonitoring = false;
      _addLog(
        '⚠️ Previous notifier stopped — starting new search.',
        isAlert: true,
      );
    }

    if (intent.autoReserve && CreditService().credits <= 0) {
      _lastError = 'Cannot auto-book: 0 credits remaining. Please buy credits.';
      notifyListeners();
      return;
    }

    if (targetTrains != null && targetTrains.isNotEmpty) {
      _targetTrains = targetTrains.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      _targetTrain = _targetTrains.join(', ');
    } else if (targetTrain != null && targetTrain.trim().isNotEmpty && targetTrain.toUpperCase() != 'ALL') {
      _targetTrains = targetTrain.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      _targetTrain = _targetTrains.join(', ');
    } else {
      _targetTrains = [];
      _targetTrain = null;
    }

    bookingIntent = intent.copyWith(targetTrains: _targetTrains);
    _intervalSeconds = AppConfig.instance.pollSeconds;
    _fromCity = fromCity;
    _toCity = toCity;
    _dateOfJourney = dateOfJourney;
    _targetSeatClass =
        targetSeatClass == null ||
            targetSeatClass.trim().isEmpty ||
            targetSeatClass.trim().toUpperCase() == 'ALL' ||
            targetSeatClass.trim().toUpperCase() == 'RANDOM'
        ? null
        : targetSeatClass.trim().toUpperCase();
    _generation++;
    _searchId = DateTime.now().microsecondsSinceEpoch.toString();

    // ── Search time limit: until train departure time ──
    DateTime? calculatedDeparture = departureTime;
    if (calculatedDeparture == null) {
      if (_targetTrains.isNotEmpty && _lastTrains.isNotEmpty) {
        final matched = _lastTrains.where((t) => isTrainMonitored(t.tripNumber)).firstOrNull;
        if (matched != null) {
          departureDateTimeJd ??= matched.departureDateTimeJd;
          departureDateTime ??= matched.departureDateTime;
        }
      }
      calculatedDeparture = parseDepartureDateTime(
        departureDateTimeJd: departureDateTimeJd,
        departureDateTime: departureDateTime,
        dateOfJourney: dateOfJourney,
      );
    }
    // Default search time: until train departure time
    _expiresAt = calculatedDeparture ?? DateTime.now().add(const Duration(hours: 24));
    _startedAt = DateTime.now();
    _elapsedMonitoringSeconds = 0;
    _lastTrains = [];
    backgroundError = null;
    _isMonitoring = true;
    _totalChecksCount = 0;
    _seatsFoundCount = 0;
    _lastError = null;
    _lastBookingError = null;
    _isLimitReached = false;

    _addLog(
      'Started monitoring: $fromCity ➔ $toCity ($dateOfJourney) '
      '| Train: ${_targetTrain ?? "ALL"} | Class: ${_targetSeatClass ?? "ANY"}'
      ' [UNTIL TRAIN DEPARTURE]',
    );

    unawaited(
      FirebaseUserService().syncNotifierState(
        isMonitoring: true,
        fromCity: fromCity,
        toCity: toCity,
        dateOfJourney: dateOfJourney,
        targetTrain: targetTrain,
        targetSeatClass: targetSeatClass,
      ),
    );

    notifyListeners();
    unawaited(_saveAndSchedule().then((_) => _executeCheck()));
    _restartTimer();
    _startSecondTicker();
  }

  void stopMonitoring() {
    _generation++;
    _checkTimer?.cancel();
    _checkTimer = null;
    _secondTicker?.cancel();
    _secondTicker = null;
    _isMonitoring = false;
    unawaited(_saveAndSchedule());
    unawaited(FirebaseUserService().syncNotifierState(isMonitoring: false));
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

      // Check if train departure time reached
      if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
        _isLimitReached = true;
        stopMonitoring();
        _addLog(
          'Train departure time reached. Monitoring ended.',
          isAlert: true,
        );
      }

      // Check 5-minute reservation validity and auto-clear if expired
      unawaited(_checkReservationExpiry());

      // If admin reduces credits to 0 in DB while monitoring is active, pause auto-booking!
      if (_isMonitoring && bookingIntent.autoReserve && CreditService().credits <= 0) {
        stopMonitoring();
        _lastError = 'Auto-booking paused: 0 credits remaining. Please buy credits.';
        _addLog(
          '⚠️ 0 credits remaining. Auto-booking stopped. Please recharge credits.',
          isAlert: true,
        );
        notifyListeners();
      }

      notifyListeners();
    });
  }

  Future<void> _checkReservationExpiry() async {
    final raw = await SecureStore.read(BookingService.storageKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final started = DateTime.tryParse(map['startedAt'] ?? '');
      final expires = DateTime.tryParse(map['expiresAt'] ?? '');
      final now = DateTime.now();
      final bool isExpired =
          (started != null && now.difference(started).inSeconds >= 300) ||
          (expires != null && !now.isBefore(expires));

      if (isExpired) {
        final id = map['id']?.toString() ?? '';
        await TripHistoryService().updateTripStatus(
          id,
          TripBookingStatus.expired,
          failureReason: 'Reservation timed out after 5 minutes',
        );
        await BookingService.clear();
        await _notificationService.clearAlerts();
        _lastReservationExpired = true;
        _turnstileRequestedForBooking = false;
        bookingIntent = bookingIntent.copyWith(autoReserve: false);
        await clearSearch();
        _addLog(
          '⏱️ 5 minutes passed after booking/OTP. Search cleared automatically.',
          isAlert: true,
        );
        notifyListeners();
      }
    } catch (_) {}
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
    if (!_isMonitoring || _checking || _disposed) return;
    _intervalSeconds = AppConfig.instance.pollSeconds;
    if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
      _isLimitReached = true;
      stopMonitoring();
      return;
    }
    _checking = true;
    final generation = _generation;
    try {
      // Check for held or pending reservation
      final pendingReservation = await BookingService.pending();
      if (pendingReservation != null) {
        final expiry = DateTime.tryParse('${pendingReservation['expiresAt'] ?? ''}');
        final isExpired = expiry != null && !expiry.isAfter(DateTime.now());
        if (isExpired) {
          await BookingService.clear();
          _lastReservationExpired = true;
          bookingIntent = bookingIntent.copyWith(autoReserve: false);
          await clearSearch();
          _addLog(
            '⏱️ 5 minutes passed after booking/OTP. Search cleared automatically.',
            isAlert: true,
          );
          notifyListeners();
          return;
        } else {
          stopMonitoring();
          _scheduleAutoClearSearchAfter5Minutes();
          await OtpVerifier.listen();
          return;
        }
      }
      final session = await AuthSession.load();
      if (session == null || !session.isValid) {
        _lastError =
            'Not logged in. Please authenticate with Railway credentials.';
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

        if (!_isMonitoring || generation != _generation || _disposed) return;
        if (!await _savedSearchIsActive()) return;
        _lastError = null;
        _lastTrains = response.trains;
        if (_targetTrains.isNotEmpty || _targetTrain != null) {
          final matched = response.trains.where((t) => isTrainMonitored(t.tripNumber)).firstOrNull;
          if (matched != null) {
            final dep = parseDepartureDateTime(
              departureDateTimeJd: matched.departureDateTimeJd,
              departureDateTime: matched.departureDateTime,
              dateOfJourney: _dateOfJourney,
            );
            if (dep != null && dep != _expiresAt) {
              _expiresAt = dep;
              unawaited(_saveAndSchedule());
            }
          }
        }
        if (bookingIntent.autoReserve &&
            await BookingService.pending() == null) {
          final chosen = bookingIntent.choose(
            response.trains,
            train: _targetTrain,
            targetTrains: _targetTrains,
            seatClass: _targetSeatClass,
          );
          if (chosen != null) {
            try {
              final reservation = await BookingService.reserve(
                train: chosen.$1,
                seat: chosen.$2,
                from: _fromCity,
                to: _toCity,
                date: _dateOfJourney,
                auth: session,
                quantity: bookingIntent.quantity,
                maxFare: bookingIntent.maxFare,
                autoVerify: bookingIntent.autoVerify,
                isAutoBook: true,
                canReserve: () async =>
                    !_disposed &&
                    _isMonitoring &&
                    generation == _generation &&
                    await _savedSearchIsActive(),
              );
              _turnstileRequestedForBooking = false;
              _lastReservationExpired = false;
              // Each auto-book books only ONE time. Disable autoReserve so it never re-books without explicit user re-autobook
              bookingIntent = bookingIntent.copyWith(autoReserve: false);
              stopMonitoring();
              await _saveAndSchedule();
              await _notificationService.showReservation(reservation);
              await OtpVerifier.listen();
              _scheduleAutoClearSearchAfter5Minutes();
              // Sequence Rule: after OTP is sent, directly present user with verify & pay process
              final nav = NotificationService.navigatorKey.currentState;
              if (nav != null && nav.mounted) {
                nav.push(MaterialPageRoute(builder: (_) => const ReservationScreen()));
              }
              notifyListeners();
              return;
            } catch (error) {
              if (_disposed ||
                  !_isMonitoring ||
                  generation != _generation ||
                  !await _savedSearchIsActive()) {
                return;
              }
              final clean = friendlyErrorMessage(error);
              _lastError = clean;
              _lastBookingError = clean;

              final isTurnstile = RegExp(
                r'422|turnstile|cft_response|verification|human check',
                caseSensitive: false,
              ).hasMatch(error.toString()) || RegExp(
                r'422|turnstile|cft_response|verification|human check',
                caseSensitive: false,
              ).hasMatch(clean);

              if (isTurnstile) {
                _addLog('Human check needed to reserve seats for ${chosen.$1.tripNumber}');
                // Security check should be triggered only ONCE per booking attempt
                if (!_turnstileRequestedForBooking) {
                  _turnstileRequestedForBooking = true;
                  // Save context so overlay/dialog can show "TRAIN · SEAT"
                  await SecureStore.write(
                    'rail_turnstile_context',
                    '${chosen.$1.tripNumber} · ${chosen.$2.type}',
                  );
                  await _notificationService.triggerTurnstileRequiredAlert(
                    trainName: chosen.$1.tripNumber,
                    seatType: chosen.$2.type,
                  );
                }
                notifyListeners();
                return;
              }

              _addLog(
                'Automatic reservation needs attention: $clean',
                isError: true,
              );
              try {
                await TripHistoryService().recordTrip(
                  TripRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    trainName: chosen.$1.tripNumber,
                    fromCity: _fromCity,
                    toCity: _toCity,
                    dateOfJourney: _dateOfJourney,
                    seatClass: chosen.$2.type,
                    seatNumbers: [],
                    coachName: '',
                    totalFare: double.tryParse(chosen.$2.fare) ?? 0.0,
                    status: TripBookingStatus.failed,
                    failureReason: clean,
                    createdAt: DateTime.now(),
                    isAutoBook: true,
                  ),
                );
              } catch (_) {}
              notifyListeners();

              final prefs = await SharedPreferences.getInstance();
                final alertKey = 'ticket_attention_$_searchId';
                if (prefs.getBool(alertKey) != true) {
                  await _notificationService.triggerSeatAvailableAlert(
                    trainName: chosen.$1.tripNumber,
                    seatType: chosen.$2.type,
                    seatCount: chosen.$2.seatCounts.online,
                    travelDate: _dateOfJourney,
                    bookingLink: NotificationService.bookingUrl(
                      _fromCity,
                      _toCity,
                      _dateOfJourney,
                      chosen.$2.type,
                    ),
                  );
                  await prefs.setBool(alertKey, true);
                }
            }
          }
        }
        _lastTrains = response.trains;
        _seatsFoundCount = 0;
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final saved = prefs.getString(preferenceKey);
        if (saved == null ||
            jsonDecode(saved)['id'] != _searchId ||
            jsonDecode(saved)['active'] != true) {
          return;
        }
        final previous = Map<String, dynamic>.from(
          jsonDecode(prefs.getString('ticket_availability_$_searchId') ?? '{}'),
        );
        final current = <String, int>{};

        // Evaluate availability
        bool foundSeats = false;
        for (final train in response.trains) {
          if (!isTrainMonitored(train.tripNumber)) {
            continue;
          }

          for (final seat in train.seatTypes) {
            if (_targetSeatClass != null &&
                _targetSeatClass!.isNotEmpty &&
                _targetSeatClass != 'ALL' &&
                _targetSeatClass != 'RANDOM' &&
                seat.type.toUpperCase() != _targetSeatClass!.toUpperCase()) {
              continue;
            }

            final key = '${train.tripNumber}:${seat.type}';
            current[key] = seat.seatCounts.online;
            if (seat.seatCounts.online > 0) {
              foundSeats = true;
              _seatsFoundCount += seat.seatCounts.online;
              if (previous[key] == seat.seatCounts.online) continue;
              _addLog(
                '🎉 SEATS FOUND! ${train.tripNumber} has ${seat.seatCounts.online} [${seat.type}] seats!',
                isAlert: true,
              );
              unawaited(
                FirebaseUserService().logSeatsFound(
                  trainName: train.tripNumber,
                  seatType: seat.type,
                  seatCount: seat.seatCounts.online,
                ),
              );

              try {
                if (bookingIntent.autoReserve) continue;
                if (!isTrainMonitored(train.tripNumber)) continue;
                await _notificationService.triggerSeatAvailableAlert(
                  trainName: train.tripNumber,
                  seatType: seat.displayName,
                  seatCount: seat.seatCounts.online,
                  travelDate: _dateOfJourney,
                  needsHumanVerification: true,
                  bookingLink: NotificationService.bookingUrl(
                    _fromCity,
                    _toCity,
                    _dateOfJourney,
                    seat.type,
                  ),
                );
              } catch (_) {}
            }
          }
        }
        await prefs.setString(
          'ticket_availability_$_searchId',
          jsonEncode(current),
        );
        await prefs.setString(
          'ticket_results_$_searchId',
          jsonEncode(response.trains.map((t) => t.toJson()).toList()),
        );

        if (!foundSeats) {
          _addLog(
            '#$_totalChecksCount checked at ${_formatTime(_lastCheckedAt!)}: No online seats yet. Next in ${_intervalSeconds}s.',
          );
        }
      } catch (e) {
        _lastError = e.toString();
        _addLog('Check error: $e', isError: true);
      }

      notifyListeners();
    } finally {
      _checking = false;
      if (!_disposed &&
          generation == _generation &&
          await _savedSearchIsActive()) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'ticket_status_$_searchId',
          jsonEncode({
            'error': _lastError,
            'checkedAt': _lastCheckedAt?.toIso8601String(),
          }),
        );
        notifyListeners();
      }
    }
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
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _checkTimer?.cancel();
    _secondTicker?.cancel();
    _autoClearSearchTimer?.cancel();
    super.dispose();
  }
}
