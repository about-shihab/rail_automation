import 'rail_api_client.dart';
import 'railway_credentials_rejected.dart';

import 'dart:async';
import 'dart:convert';

import '../models/booking_intent.dart';
import 'app_config.dart';
import 'app_update_service.dart';
import 'booking_service.dart';
import 'credit_service.dart';
import 'foreground_monitor.dart';
import 'otp_verifier.dart';
import 'search_scheduler.dart';
import 'journey_schedule.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_type.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';
import 'background_monitor.dart';
import 'firebase_user_service.dart';
import 'secure_store.dart';
import 'trip_history_service.dart';
import '../models/trip_record.dart';

import 'package:flutter/material.dart';

import 'turnstile_gate.dart';
import 'seat_layout_challenge.dart';
import 'intermediate_station_search.dart';
import '../views/reservation_screen.dart';
import '../utils/friendly_error.dart';

class MonitorLog {
  final DateTime time;
  final String message;
  final bool isAlert;
  final bool isError;
  final IntermediateJourney? viaJourney;

  MonitorLog({
    required this.time,
    required this.message,
    this.isAlert = false,
    this.isError = false,
    this.viaJourney,
  });
}

class MonitorService extends ChangeNotifier {
  final NotificationService _notificationService = NotificationService();
  final ProService proService;

  final bool backgroundWorker;
  bool get _iosBackgroundSearch =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      (backgroundWorker || AuthSession.useBackgroundStorage);
  BookingIntent bookingIntent = const BookingIntent();
  final DateTime Function() _now;
  MonitorService({
    required this.proService,
    this.backgroundWorker = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  bool get _nativeMonitoring =>
      !backgroundWorker &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      ForegroundMonitor.initialized &&
      backgroundError == null;
  Timer? _autoClearSearchTimer;
  final SearchScheduler _scheduler = SearchScheduler();
  String? _lastReservationId;
  bool _resumeAutoReserve = false;

  /// Watches the reservation hold after an automatic booking. When the hold
  /// closes unpaid, the search resumes (if enabled in the database and the
  /// train has not departed); when it was paid or cancelled, it is cleared.
  void _scheduleReservationExpiryWatch([Duration? after]) {
    _autoClearSearchTimer?.cancel();
    _autoClearSearchTimer = Timer(
      after ??
          Duration(minutes: BookingService.reservationTimeoutMinutes) +
              const Duration(seconds: 5),
      () => unawaited(_onReservationWindowClosed()),
    );
  }

  bool get _canResumeSearch =>
      _fromCity.isNotEmpty &&
      _toCity.isNotEmpty &&
      _dateOfJourney.isNotEmpty &&
      _expiresAt != null &&
      _expiresAt!.isAfter(DateTime.now());

  Future<void> _onReservationWindowClosed() async {
    if (_disposed) return;
    // pending() lazily expires a stale hold and marks it EXPIRED in history.
    if (await BookingService.pending() != null) {
      _scheduleReservationExpiryWatch(const Duration(seconds: 30));
      return;
    }
    final id = _lastReservationId;
    final status = id == null ? null : TripHistoryService().statusOf(id);
    final expiredUnpaid = status == TripBookingStatus.expired;
    if (expiredUnpaid &&
        _canResumeSearch &&
        AppConfig.instance.boolean('resume_search_after_expiry')) {
      await _resumeAfterExpiry();
      return;
    }
    await BookingService.clear();
    markReservationExpired();
    _addLog(
      '⏱️ Reservation window closed. OTP was not verified or payment timed out.',
      isAlert: true,
    );
  }

  Future<void> _resumeAfterExpiry() async {
    await BookingService.clear();
    _lastReservationExpired = true;
    _lastReservationId = null;
    final reAutoBook = _resumeAutoReserve && CreditService().credits > 0;
    _addLog(
      '⏱️ Reservation expired unpaid. Resuming seat search automatically.',
      isAlert: true,
    );
    startMonitoring(
      fromCity: _fromCity,
      toCity: _toCity,
      dateOfJourney: _dateOfJourney,
      targetTrains: List<String>.of(_targetTrains),
      targetSeatClass: _targetSeatClass,
      intent: bookingIntent.copyWith(autoReserve: reAutoBook),
      departureTime: _expiresAt,
    );
  }

  Future<void> clearSearch() async {
    _autoClearSearchTimer?.cancel();
    stopMonitoring();
    await _persistence;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_verificationKey);
    _turnstileRequestedForBooking = false;
    _turnstileWaitingForUi = false;
    await TurnstileGate.instance.invalidate();
    TurnstileGate.instance.dismiss();
    await prefs.remove(preferenceKey);
    _fromCity = '';
    _toCity = '';
    _dateOfJourney = '';
    _targetTrains = [];
    _targetTrain = null;
    _targetSeatClass = null;
    bookingIntent = const BookingIntent();
    _lastTrains = [];
    _viaJourneys = [];
    _recentViaJourneys = [];
    _lastViaSearchAt = null;
    _lastNotifiedViaKey = null;
    _isSearchingVia = false;
    _lastError = null;
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    _lastReservationExpired = false;
    _lastBookingFailureReason = null;
    _elapsedMonitoringSeconds = 0;
    _totalChecksCount = 0;
    _seatsFoundCount = 0;
    try {
      await BookingService.clear();
      await NotificationService().cancelReservationAlerts();
    } catch (_) {}
    _addLog('Monitoring stopped and cleared by user.');
    notifyListeners();
  }

  void pauseMonitoring() {
    stopMonitoring();
  }

  void resumeMonitoring() {
    if (_dateOfJourney.isEmpty) return;
    startMonitoring(
      fromCity: _fromCity.isEmpty ? 'Dhaka' : _fromCity,
      toCity: _toCity.isEmpty ? 'Chattogram' : _toCity,
      dateOfJourney: _dateOfJourney,
      targetTrain: _targetTrain,
      targetSeatClass: _targetSeatClass,
      intent: bookingIntent,
      departureTime: _expiresAt,
    );
  }

  static const preferenceKey = 'active_ticket_search';
  String? _searchId;
  DateTime? _expiresAt;
  DateTime? _startedAt;
  bool _checking = false;
  bool _foregroundSuspended = false;
  Future<void>? _activeCheck;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _persistence = Future.value();
  String? backgroundError;

  Future<void> restore({bool startTimers = true}) async {
    await AppConfig.instance.reloadCache();
    _intervalSeconds = AppConfig.instance.searchIntervalSeconds;
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
        _targetTrains = (data['trains'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (data['train'] is String &&
          (data['train'] as String).isNotEmpty) {
        final t = data['train'] as String;
        _targetTrains = t
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        _targetTrains = [];
      }
      _targetTrain = _targetTrains.isNotEmpty
          ? _targetTrains.join(', ')
          : (data['train'] as String?);
      final rawSeat = data['seat'] as String?;
      _targetSeatClass =
          (rawSeat == null ||
              rawSeat.trim().isEmpty ||
              rawSeat.trim().toUpperCase() == 'ALL' ||
              rawSeat.trim().toUpperCase() == 'RANDOM')
          ? null
          : rawSeat.trim().toUpperCase();
      _searchId = data['id'] as String;
      final verification = prefs.getString(_verificationKey);
      _turnstileRequestedForBooking = verification != null;
      _turnstileWaitingForUi = verification == 'pending';
      _bookingNeedsVerification =
          verification == 'pending' || verification == 'presented';
      _lastBookingError =
          verification == 'pending' || verification == 'presented'
          ? const SeatLayoutChallenge().toString()
          : null;
      final status = prefs.getString('ticket_status_$_searchId');
      if (status != null) {
        final savedStatus = jsonDecode(status) as Map<String, dynamic>;
        _lastError = savedStatus['error'] as String?;
        if (verification == 'solved' &&
            _lastError != null &&
            _challengeRx.hasMatch(_lastError!)) {
          _lastError = null;
        }
        _lastCheckedAt = DateTime.tryParse(savedStatus['checkedAt'] ?? '');
      }
      _expiresAt = DateTime.tryParse(data['expires'] ?? '');
      _startedAt = DateTime.tryParse(data['startedAt'] ?? '');
      if (_expiresAt == null) {
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
      final viaResult = prefs.getString('via_results_$_searchId');
      if (viaResult != null) {
        try {
          final list = (jsonDecode(viaResult) as List).map((e) {
            final map = Map<String, dynamic>.from(e);
            return IntermediateJourney(
              via: map['via'] ?? '',
              viaCity: map['viaCity'] ?? '',
              firstDate: map['firstDate'] ?? '',
              secondDate: map['secondDate'] ?? '',
              first: TrainTrip.fromJson(Map<String, dynamic>.from(map['first'])),
              second: TrainTrip.fromJson(Map<String, dynamic>.from(map['second'])),
              firstSeat: SeatType.fromJson(Map<String, dynamic>.from(map['firstSeat'])),
              secondSeat: SeatType.fromJson(Map<String, dynamic>.from(map['secondSeat'])),
            );
          }).toList();
          _viaJourneys = list;
          _recentViaJourneys = list;
        } catch (_) {}
      }
      if (_expiresAt != null && !_now().isBefore(_expiresAt!)) {
        _isMonitoring = false;
        _isLimitReached = true;
        if (data['active'] == true) await _saveAndSchedule();
      }
      if (_isMonitoring && startTimers) {
        _foregroundSuspended = false;
        if (_nativeMonitoring) {
          try {
            await BackgroundMonitor.schedule(startsAt: scheduledStartAt);
          } catch (_) {
            backgroundError = 'Keep the app open to continue searching';
          }
        } else if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            !backgroundWorker) {
          try {
            await BackgroundMonitor.schedule(startsAt: scheduledStartAt);
            await _notificationService.showIosSearchStatus(
              from: _fromCity,
              to: _toCity,
              date: _dateOfJourney,
              scheduled: isScheduled,
            );
            backgroundError = null;
          } catch (error) {
            backgroundError = error is StateError
                ? error.message.toString()
                : 'Keep Rail Pro open until background searching reconnects.';
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

  Future<void> _saveAndSchedule({bool replaceSchedule = false}) async {
    final active = _isMonitoring;
    final startsAt = scheduledStartAt;
    final data = jsonEncode({
      'id': _searchId,
      'from': _fromCity,
      'to': _toCity,
      'date': _dateOfJourney,
      'train': _targetTrains.isNotEmpty
          ? _targetTrains.join(', ')
          : _targetTrain,
      'trains': _targetTrains,
      'seat': _targetSeatClass,
      'active': _isMonitoring,
      'expires': _expiresAt?.toIso8601String(),
      'startsAt': scheduledStartAt?.toIso8601String(),
      'startedAt': _startedAt?.toIso8601String(),
      'bookingIntent': bookingIntent.toJson(),
    });
    _persistence = _persistence.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, data);
      try {
        if (backgroundWorker) return;
        if (active) {
          await BackgroundMonitor.schedule(
            startsAt: startsAt,
            replaceSchedule: replaceSchedule,
          );
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
            final saved = jsonDecode(data) as Map<String, dynamic>;
            await _notificationService.showIosSearchStatus(
              from: saved['from'] as String,
              to: saved['to'] as String,
              date: saved['date'] as String,
              scheduled: startsAt != null && startsAt.isAfter(_now()),
            );
            backgroundError = null;
          }
        } else {
          await BackgroundMonitor.cancel();
        }
      } catch (error) {
        backgroundError =
            !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.iOS &&
                error is StateError
            ? error.message.toString()
            : 'অ্যাপ খোলা রাখুন • Keep the app open to continue searching';
        notifyListeners();
      }
    });
    await _persistence;
  }

  Future<void> checkNow() => _executeCheck();

  void suspendForegroundTimers() {
    _foregroundSuspended = true;
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
  List<IntermediateJourney> _viaJourneys = [];
  List<IntermediateJourney> _recentViaJourneys = [];
  DateTime? _lastViaSearchAt;
  String? _lastNotifiedViaKey;
  bool _isSearchingVia = false;
  final List<MonitorLog> _logs = [];

  // Monitoring lasts until departure; waiting for sales does not count as checks.
  int _elapsedMonitoringSeconds = 0;
  bool _isLimitReached = false;

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get isSearchingVia => _isSearchingVia;
  DateTime? get departureAt => _expiresAt;
  DateTime? get scheduledStartAt => JourneySchedule.salesOpenAt(_dateOfJourney);
  bool get isScheduled =>
      _isMonitoring &&
      scheduledStartAt != null &&
      _now().isBefore(scheduledStartAt!);
  String? get scheduledStartLabel => scheduledStartAt == null
      ? null
      : JourneySchedule.formatStart(scheduledStartAt!);
  int get intervalSeconds => _intervalSeconds;
  int get secondsUntilNextCheck => _secondsUntilNextCheck;
  String get fromCity => _fromCity;
  String get toCity => _toCity;
  String get dateOfJourney => _dateOfJourney;
  List<String> get targetTrains => List.unmodifiable(_targetTrains);
  String? get targetTrain {
    if (_targetTrains.isNotEmpty) {
      return _targetTrains.length == 1
          ? _targetTrains.first
          : _targetTrains.join(', ');
    }
    return _targetTrain;
  }

  bool isTrainMonitored(String trainName) {
    if (!_isMonitoring) return false;
    final clean = trainName.trim().toLowerCase();
    if (_targetTrains.isEmpty &&
        (_targetTrain == null ||
            _targetTrain == 'ALL' ||
            _targetTrain!.isEmpty)) {
      return true;
    }
    return _targetTrains.any((t) => _matchTrain(t, clean)) ||
        (_targetTrain != null && _matchTrain(_targetTrain!, clean));
  }

  static bool _matchTrain(String target, String candidate) {
    final t = target.trim().toLowerCase();
    final c = candidate.trim().toLowerCase();
    if (t == c || t == 'all') return true;
    final numT = RegExp(r'\b\d{3,4}\b').firstMatch(t)?.group(0);
    final numC = RegExp(r'\b\d{3,4}\b').firstMatch(c)?.group(0);
    if (numT != null && numC != null && numT == numC) return true;
    final nameT = t.replaceAll(RegExp(r'\s*\(\d+\)'), '').trim();
    final nameC = c.replaceAll(RegExp(r'\s*\(\d+\)'), '').trim();
    if (nameT.isNotEmpty && nameT == nameC) return true;
    return c.contains(t) || t.contains(c);
  }

  void addTrainToMonitoring(String trainName) {
    final clean = trainName.trim();
    if (clean.isEmpty) return;
    _lastReservationExpired = false;
    _lastBookingFailureReason = null;
    _lastReservationId = null;
    _lastError = null;
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    unawaited(BookingService.clear());

    if (!_targetTrains.any((t) => t.toLowerCase() == clean.toLowerCase())) {
      _targetTrains.add(clean);
      _targetTrain = _targetTrains.join(', ');
      bookingIntent = bookingIntent.copyWith(targetTrains: _targetTrains);
      _refreshDepartureDeadline();
      _addLog(
        '➕ Added $clean to active auto-booking (Total: ${_targetTrains.length} trains)',
      );
    }
    if (!_isMonitoring) {
      _isMonitoring = true;
      _restartTimer();
      _startSecondTicker();
      unawaited(checkNow());
    }
    unawaited(_saveAndSchedule());
    notifyListeners();
  }

  void removeTrainFromMonitoring(String trainName) {
    final clean = trainName.trim();
    _targetTrains.removeWhere((t) => t.toLowerCase() == clean.toLowerCase());
    _targetTrain = _targetTrains.isNotEmpty ? _targetTrains.join(', ') : null;
    bookingIntent = bookingIntent.copyWith(targetTrains: _targetTrains);
    _refreshDepartureDeadline();
    _addLog(
      '➖ Removed $clean from active auto-booking (Remaining: ${_targetTrains.length} trains)',
    );
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
  bool _turnstileWaitingForUi = false;
  bool _resolvingTurnstile = false;
  bool _bookingNeedsVerification = false;
  bool _recheckAfterVerification = false;
  String get _verificationKey => 'ticket_verification_$_searchId';

  /// Only real Cloudflare challenges. (The old pattern also matched the word
  /// "verification", so e.g. "OTP verification not completed" popped a human
  /// check.)
  static final RegExp _challengeRx = RegExp(
    r'turnstile|cft_response|human check',
    caseSensitive: false,
  );
  bool _lastReservationExpired = false;
  bool get lastReservationExpired => _lastReservationExpired;
  String? _lastBookingFailureReason;
  String? get bookingFailureReason => _lastBookingFailureReason;

  void markReservationExpired({String? reason}) {
    _lastReservationExpired = true;
    _lastBookingFailureReason = reason ?? 'Seats were reserved, but OTP was not verified or payment was not completed within 5 minutes. Held seats were released by Bangladesh Railway.';
    bookingIntent = bookingIntent.copyWith(autoReserve: false);
    stopMonitoring();
    notifyListeners();
  }

  void dismissBookingFailure() {
    _lastReservationExpired = false;
    _lastBookingFailureReason = null;
    unawaited(BookingService.clear());
    notifyListeners();
  }

  void clearBookingError() {
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    notifyListeners();
  }

  Future<void> onTurnstileSolved(String token) async {
    if (token.isEmpty) return;
    await TurnstileGate.instance.storeToken(token);
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    _lastError = null;
    _turnstileRequestedForBooking = true;
    _turnstileWaitingForUi = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_verificationKey, 'solved');
    await _notificationService.cancelVerificationAndSearchAlerts();
    notifyListeners();
    if (_nativeMonitoring) {
      await ForegroundMonitor.start();
    } else if (_checking || _activeCheck != null) {
      _recheckAfterVerification = true;
    } else {
      await checkNow();
    }
  }

  String _turnstileLabel() => [
    if (targetTrain?.isNotEmpty == true) targetTrain!,
    if (targetSeatClass?.isNotEmpty == true) targetSeatClass!,
  ].join(' · ');

  Future<void> resolveTurnstile({String? label}) async {
    if (_resolvingTurnstile ||
        !needsTurnstile ||
        !TurnstileGate.instance.canShowUi) {
      return;
    }
    _resolvingTurnstile = true;
    final searchId = _searchId;
    final generation = _generation;
    try {
      _turnstileWaitingForUi = false;
      _turnstileRequestedForBooking = true;
      // Start the warm browser and loading view before persistence or alert cleanup.
      final verification = TurnstileGate.instance.acquire(
        label: label ?? _turnstileLabel(),
        forceFresh: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_verificationKey, 'presented');
      await _notificationService.cancelVerificationAndSearchAlerts();
      final token = await verification;
      if (_disposed || searchId != _searchId || generation != _generation) {
        await TurnstileGate.instance.invalidate();
        return;
      }
      if (token != null && token.isNotEmpty) await onTurnstileSolved(token);
    } finally {
      _resolvingTurnstile = false;
    }
  }

  /// A background request survives an app restart. Presented or cancelled
  /// requests remain available for an explicit retry, never another popup.
  void resumePendingTurnstile() {
    if (_turnstileWaitingForUi && needsTurnstile) {
      unawaited(resolveTurnstile());
    }
  }

  Future<void> _raiseTurnstile(String label, String train, String seat) async {
    final prefs = await SharedPreferences.getInstance();
    _turnstileWaitingForUi = true;
    await prefs.setString(_verificationKey, 'pending');
    if (!backgroundWorker && TurnstileGate.instance.canShowUi) {
      unawaited(resolveTurnstile(label: label));
    } else {
      await _notificationService.triggerTurnstileRequiredAlert(
        trainName: train,
        seatType: seat,
      );
    }
  }

  Future<void> reAutoBook() async {
    if (CreditService().credits <= 0) {
      _lastError = 'Cannot auto-book: 0 credits remaining. Please buy credits.';
      notifyListeners();
      return;
    }
    await BookingService.clear();
    _lastReservationExpired = false;
    _lastBookingFailureReason = null;
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    _turnstileRequestedForBooking = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_verificationKey);
    await TurnstileGate.instance.invalidate();
    bookingIntent = bookingIntent.copyWith(autoReserve: true);
    if (!_isMonitoring) {
      _isMonitoring = true;
      _restartTimer();
      _startSecondTicker();
    }
    await _saveAndSchedule();
    notifyListeners();
    await checkNow();
  }

  void clearErrors() {
    _lastError = null;
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    _lastReservationExpired = false;
    _lastBookingFailureReason = null;
    unawaited(BookingService.clear());
    notifyListeners();
  }

  void setErrorForTesting({String? error, String? bookingError}) {
    if (error != null) _lastError = error;
    if (bookingError != null) {
      _lastBookingError = bookingError;
      _bookingNeedsVerification = _challengeRx.hasMatch(bookingError);
    }
    notifyListeners();
  }

  bool get needsTurnstile => _bookingNeedsVerification;
  bool get needsLogin => RailwayCredentialsRejected.isError(_lastError);
  String get userStatus {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        backgroundError != null) {
      return backgroundError!;
    }
    if (isScheduled) {
      return 'Scheduled · starts $scheduledStartLabel (Bangladesh time)';
    }
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
  List<IntermediateJourney> get viaJourneys => List.unmodifiable(_viaJourneys);
  List<IntermediateJourney> get recentViaJourneys =>
      List.unmodifiable(_recentViaJourneys.isNotEmpty ? _recentViaJourneys : _viaJourneys);
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
      final iso = DateTime.tryParse(s);
      if (iso != null) {
        return iso.isUtc ? iso : JourneySchedule.railwayTime(iso);
      }
      final withoutDay = s.replaceAll(RegExp(r'^[A-Za-z]+,\s*'), '').trim();
      for (final pattern in [
        'dd MMM yyyy, hh:mm a',
        'dd MMM yyyy, HH:mm',
        'EEE, dd MMM yyyy, hh:mm a',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-ddTHH:mm:ss',
      ]) {
        try {
          return JourneySchedule.railwayTime(
            DateFormat(pattern, 'en_US').parseStrict(withoutDay),
          );
        } catch (_) {}
        try {
          return JourneySchedule.railwayTime(
            DateFormat(pattern, 'en_US').parseStrict(s),
          );
        } catch (_) {}
      }
    }

    DateTime? baseDate;
    if (dateOfJourney != null && dateOfJourney.trim().isNotEmpty) {
      for (final pattern in ['dd-MMM-yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy']) {
        try {
          baseDate = DateFormat(
            pattern,
            'en_US',
          ).parseStrict(dateOfJourney.trim());
          break;
        } catch (_) {}
      }
    }
    if (baseDate == null &&
        departureFullDate != null &&
        departureFullDate.trim().isNotEmpty) {
      for (final pattern in ['yyyy-MM-dd', 'dd-MMM-yyyy']) {
        try {
          baseDate = DateFormat(
            pattern,
            'en_US',
          ).parseStrict(departureFullDate.trim());
          break;
        } catch (_) {}
      }
    }

    if (baseDate != null) {
      if (departureDateTime != null && departureDateTime.trim().isNotEmpty) {
        final match = RegExp(
          r'(\d{1,2}):(\d{2})\s*(am|pm)?',
          caseSensitive: false,
        ).firstMatch(departureDateTime);
        if (match != null) {
          int hour = int.parse(match.group(1)!);
          final minute = int.parse(match.group(2)!);
          final period = match.group(3)?.toLowerCase();
          if (period == 'pm' && hour < 12) hour += 12;
          if (period == 'am' && hour == 12) hour = 0;
          return JourneySchedule.railwayTime(
            DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute),
          );
        }
      }
      return JourneySchedule.railwayTime(
        DateTime(baseDate.year, baseDate.month, baseDate.day, 23, 59, 59),
      );
    }
    return null;
  }

  int get elapsedMonitoringSeconds => _elapsedMonitoringSeconds;
  bool get isLimitReached => _isLimitReached;

  int get remainingFreeSeconds {
    final remaining = _expiresAt?.difference(_now()).inSeconds ?? 0;
    return remaining > 0 ? remaining : 0;
  }

  double get freeProgressFraction {
    if (_expiresAt == null) return 1.0;
    final totalSecs = _expiresAt!.difference(_startedAt ?? _now()).inSeconds;
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
    final journeyDeparture =
        departureTime ??
        parseDepartureDateTime(
          departureDateTimeJd: departureDateTimeJd,
          departureDateTime: departureDateTime,
          dateOfJourney: dateOfJourney,
        );
    if (journeyDeparture == null || !journeyDeparture.isAfter(_now())) {
      _lastError = 'Choose a journey that has not departed.';
      notifyListeners();
      return;
    }
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
      _targetTrains = targetTrains
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      _targetTrain = _targetTrains.join(', ');
    } else if (targetTrain != null &&
        targetTrain.trim().isNotEmpty &&
        targetTrain.toUpperCase() != 'ALL') {
      _targetTrains = targetTrain
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      _targetTrain = _targetTrains.join(', ');
    } else {
      _targetTrains = [];
      _targetTrain = null;
    }

    bookingIntent = intent.copyWith(targetTrains: _targetTrains);
    _scheduler.reset();
    _intervalSeconds = AppConfig.instance.searchIntervalSeconds;
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
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foregroundSuspended =
        lifecycle != null && lifecycle != AppLifecycleState.resumed;
    _turnstileRequestedForBooking = false;
    _turnstileWaitingForUi = false;

    // ── Search time limit: until train departure time ──
    _expiresAt = journeyDeparture;
    _startedAt = _now();
    _elapsedMonitoringSeconds = 0;
    _lastTrains = [];
    _viaJourneys = [];
    _recentViaJourneys = [];
    _lastViaSearchAt = null;
    _lastNotifiedViaKey = null;
    _isSearchingVia = false;
    backgroundError = null;
    _isMonitoring = true;
    _totalChecksCount = 0;
    _seatsFoundCount = 0;
    _lastError = null;
    _lastBookingError = null;
    _bookingNeedsVerification = false;
    _lastReservationExpired = false;
    _lastBookingFailureReason = null;
    _lastReservationId = null;
    _isLimitReached = false;
    unawaited(BookingService.clear());

    _addLog(
      '${isScheduled ? "Scheduled search from $scheduledStartLabel (Bangladesh time)" : "Started monitoring"}: $fromCity ➔ $toCity ($dateOfJourney) '
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
    unawaited(
      _saveAndSchedule(replaceSchedule: true).then((_) => _executeCheck()),
    );
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

      if (!isScheduled) _elapsedMonitoringSeconds++;
      if (_secondsUntilNextCheck > 0) {
        _secondsUntilNextCheck--;
      } else {
        _secondsUntilNextCheck = _intervalSeconds;
      }

      // Check if train departure time reached
      if (_expiresAt != null && !_now().isBefore(_expiresAt!)) {
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
      if (_isMonitoring &&
          bookingIntent.autoReserve &&
          CreditService().credits <= 0) {
        stopMonitoring();
        _lastError =
            'Auto-booking paused: 0 credits remaining. Please buy credits.';
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
          (started != null &&
              now.difference(started).inSeconds >=
                  BookingService.reservationTimeoutMinutes * 60) ||
          (expires != null && !now.isBefore(expires));

      if (isExpired) {
        final id = map['id']?.toString() ?? '';
        await TripHistoryService().updateTripStatus(
          id,
          TripBookingStatus.expired,
          failureReason:
              'Reservation timed out after ${BookingService.reservationTimeoutMinutes} minutes',
        );
        await BookingService.clear();
        await _notificationService.clearAlerts();
        _turnstileRequestedForBooking = false;
        markReservationExpired();
        _addLog(
          '⏱️ Reservation hold expired. OTP was not verified or payment timed out.',
          isAlert: true,
        );
        return;
      }
    } catch (_) {}
  }

  void _restartTimer() => _scheduleNext();

  /// How long to wait before the next search: DB interval, near-departure
  /// boost, error backoff and jitter (see [SearchScheduler]).
  Duration nextCheckDelay() {
    if (isScheduled) return scheduledStartAt!.difference(_now());
    final scheduled = _scheduler.nextDelay(departure: _expiresAt, now: _now());
    final cooldown = RailApiClient.cooldownRemaining;
    return cooldown > scheduled ? cooldown : scheduled;
  }

  /// Single-shot timer, re-armed after every check, so a changed database
  /// interval takes effect on the very next cycle. The background service
  /// isolate drives its own schedule via [nextCheckDelay].
  void _scheduleNext({Duration? overrideDelay}) {
    _checkTimer?.cancel();
    _checkTimer = null;
    if (!_isMonitoring ||
        _disposed ||
        backgroundWorker ||
        _foregroundSuspended) {
      return;
    }
    final delay = overrideDelay ?? nextCheckDelay();
    _intervalSeconds = delay.inSeconds < 1 ? 1 : delay.inSeconds;
    _secondsUntilNextCheck = _intervalSeconds;
    _checkTimer = Timer(delay, _executeCheck);
  }

  Future<void> _executeCheck() {
    final running = _activeCheck;
    if (running != null) return running;
    late final Future<void> request;
    request = _executeAndSchedule().whenComplete(() {
      if (identical(_activeCheck, request)) _activeCheck = null;
      if (_recheckAfterVerification && !_disposed) {
        _recheckAfterVerification = false;
        scheduleMicrotask(checkNow);
      }
    });
    _activeCheck = request;
    return request;
  }

  Future<void> _executeAndSchedule() async {
    try {
      await _runCheck();
    } finally {
      _scheduleNext();
    }
  }

  Future<void> _runCheck() async {
    if (!_isMonitoring || _checking || _disposed) return;
    if (_expiresAt != null && !_now().isBefore(_expiresAt!)) {
      _isLimitReached = true;
      stopMonitoring();
      return;
    }
    // Neither manual refresh nor a restored background job may search early.
    if (isScheduled) return;
    final policyGeneration = _generation;
    await AppUpdateService.instance.reloadCache();
    if (!_isMonitoring ||
        _checking ||
        _disposed ||
        policyGeneration != _generation) {
      return;
    }
    if (AppUpdateService.instance.required) {
      _lastError = 'Rail Pro আপডেট করুন • Update Rail Pro to continue';
      notifyListeners();
      return;
    }
    if (_nativeMonitoring) {
      await restore(startTimers: false);
      if (!_isMonitoring || isScheduled) return;
      resumePendingTurnstile();
      // The background service ends itself at Android's session cap. Bring it
      // back whenever the app can legally start it, so searching never stalls
      // silently while the screen still says "monitoring".
      if (_isMonitoring && !await ForegroundMonitor.isRunning) {
        try {
          await ForegroundMonitor.start();
        } catch (_) {
          /* Not allowed from the background; the user was notified. */
        }
      }
      return;
    }
    _intervalSeconds = AppConfig.instance.searchIntervalSeconds;
    if (_expiresAt != null && !_now().isBefore(_expiresAt!)) {
      _isLimitReached = true;
      stopMonitoring();
      return;
    }
    _checking = true;
    final generation = _generation;
    try {
      // Check for held or pending reservation
      // A saved active search is sufficient for a read-only iOS refresh.
      // Booking state uses locked Keychain storage and belongs to foreground UI.
      final pendingReservation = _iosBackgroundSearch
          ? null
          : await BookingService.pending();
      if (pendingReservation != null) {
        final expiry = DateTime.tryParse(
          '${pendingReservation['expiresAt'] ?? ''}',
        );
        final isExpired = expiry != null && !expiry.isAfter(DateTime.now());
        if (isExpired) {
          await BookingService.clear();
          markReservationExpired();
          _addLog(
            '⏱️ Reservation hold expired. OTP was not verified or payment timed out.',
            isAlert: true,
          );
          return;
        } else {
          stopMonitoring();
          _scheduleReservationExpiryWatch();
          await OtpVerifier.listen();
          return;
        }
      }
      var session = await AuthSession.load(
        background: backgroundWorker || _iosBackgroundSearch,
      );
      if (session == null) {
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
            silent: true,
          );
        } catch (apiErr) {
          final errStr = apiErr.toString().replaceAll("Exception: ", "");
          _lastError = errStr;
          _scheduler.recordFailure(apiErr);
          _addLog(
            'Check failed: $errStr. Retrying with backoff '
            '(failure #${_scheduler.consecutiveFailures}).',
            isError: true,
          );
          notifyListeners();
          return;
        }

        session = await RailApiClient.current(session);
        if (!_isMonitoring || generation != _generation || _disposed) return;
        if (!await _savedSearchIsActive()) return;
        _lastError = null;
        _lastTrains = response.trains;
        final monitored = response.trains
            .where((t) => isTrainMonitored(t.tripNumber))
            .toList();
        // A multi-train search continues until its last selected departure.
        // If a selected train is absent, retain the journey-day fallback until
        // its timetable becomes available instead of ending at another train.
        final allTargetsReturned = _targetTrains.every(
          (target) => monitored.any((t) => _matchTrain(target, t.tripNumber)),
        );
        if (monitored.isNotEmpty && allTargetsReturned) {
          final departures = monitored
              .map(_departureForTrain)
              .whereType<DateTime>()
              .toList();
          if (departures.length == monitored.length) {
            departures.sort();
            if (departures.last != _expiresAt) {
              _expiresAt = departures.last;
              await _saveAndSchedule();
            }
          }
        }
        if (_expiresAt != null && !_now().isBefore(_expiresAt!)) {
          _isLimitReached = true;
          stopMonitoring();
          return;
        }
        final upcomingTrains = response.trains.where((t) {
          final departure = _departureForTrain(t);
          return departure == null || departure.isAfter(_now());
        }).toList();
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
        for (final train in upcomingTrains) {
          if (!isTrainMonitored(train.tripNumber)) {
            continue;
          }

          for (final seat in train.seatTypes) {
            if (_targetSeatClass != null &&
                _targetSeatClass!.isNotEmpty &&
                _targetSeatClass != 'ALL' &&
                _targetSeatClass != 'RANDOM') {
              final allowed = _targetSeatClass!
                  .split(',')
                  .map((s) => s.trim().toUpperCase())
                  .where((s) => s.isNotEmpty)
                  .toSet();
              if (allowed.isNotEmpty &&
                  !allowed.contains(seat.type.trim().toUpperCase())) {
                continue;
              }
            }

            final key = '${train.tripNumber}:${seat.type}';
            current[key] = seat.seatCounts.online;
            if (seat.seatCounts.online > 0) {
              foundSeats = true;
              _seatsFoundCount += seat.seatCounts.online;
              if ((previous[key] as num? ?? 0) > 0) continue;
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
                await _notificationService.triggerSeatAvailableAlert(
                  trainName: train.tripNumber,
                  seatType: seat.displayName,
                  seatCount: seat.seatCounts.online,
                  travelDate: _dateOfJourney,
                  needsHumanVerification: true,
                  automaticBooking:
                      bookingIntent.autoReserve && !_iosBackgroundSearch,
                  bookingLink: NotificationService.bookingUrl(
                    _fromCity,
                    _toCity,
                    _dateOfJourney,
                    seat.type,
                  ),
                );
              } catch (err) {
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
                  // A failed iOS delivery must not suppress the next alert just
                  // because seats remained available between refreshes.
                  current[key] = 0;
                }
                _addLog('Seat notification alert error: $err', isError: true);
              }
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
          final viaInterval = AppConfig.instance.viaSearchIntervalMinutes;
          final shouldCheckVia = _lastViaSearchAt == null ||
              DateTime.now().difference(_lastViaSearchAt!).inMinutes >= viaInterval;
          if (shouldCheckVia && !_isSearchingVia) {
            unawaited(_runViaSearch(session, upcomingTrains));
          }
        } else {
          if (_viaJourneys.isNotEmpty) {
            _viaJourneys = [];
    _recentViaJourneys = [];
    _lastViaSearchAt = null;
    _lastNotifiedViaKey = null;
    _isSearchingVia = false;
            notifyListeners();
          }
        }
        if (!_isMonitoring ||
            _disposed ||
            generation != _generation ||
            !await _savedSearchIsActive()) {
          return;
        }
        if (!_iosBackgroundSearch &&
            bookingIntent.autoReserve &&
            await BookingService.pending() == null) {
          final chosen = bookingIntent.choose(
            upcomingTrains,
            train: _targetTrain,
            targetTrains: _targetTrains,
            seatClass: _targetSeatClass,
          );
          if (chosen == null) {
            _lastBookingError = null;
            _scheduler.recordSuccess();
            return;
          }

          if (_turnstileRequestedForBooking &&
              await TurnstileGate.instance.cachedToken() == null) {
            return;
          }

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
                  (_departureForTrain(chosen.$1)?.isAfter(_now()) ?? true) &&
                  generation == _generation &&
                  await _savedSearchIsActive(),
              allowVerificationPrompt: !backgroundWorker,
            );

            // ── SUCCESS: OTP sent, seats held ─────────────────────
            _turnstileRequestedForBooking = false;
            _lastReservationExpired = false;
            _lastError = null;
            _lastBookingError = null;
            // Each auto-book books only ONE time. Disable autoReserve so it never re-books without explicit user re-autobook
            _resumeAutoReserve = bookingIntent.autoReserve;
            _lastReservationId = reservation['id']?.toString();
            bookingIntent = bookingIntent.copyWith(autoReserve: false);
            stopMonitoring();
            await _saveAndSchedule();
            await _notificationService.showReservation(reservation);
            await OtpVerifier.listen();
            _scheduleReservationExpiryWatch();
            // Sequence Rule: after OTP is sent, directly present user with verify & pay process
            final nav = NotificationService.navigatorKey.currentState;
            if (nav != null && nav.mounted) {
              nav.push(
                MaterialPageRoute(builder: (_) => const ReservationScreen()),
              );
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

            final isTurnstile = error is SeatLayoutChallenge;
            if (isTurnstile) {
              _bookingNeedsVerification = true;
              if (error.requiresForeground) {
                final label = '${chosen.$1.tripNumber} · ${chosen.$2.type}';
                await SecureStore.write('rail_turnstile_context', label);
                if (!_turnstileWaitingForUi) {
                  await _raiseTurnstile(
                    label,
                    chosen.$1.tripNumber,
                    chosen.$2.type,
                  );
                }
                _turnstileRequestedForBooking = true;
                notifyListeners();
                return;
              }
              if (error.verificationAttempted) {
                _turnstileRequestedForBooking = true;
                _turnstileWaitingForUi = false;
              }
              if (_turnstileRequestedForBooking) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_verificationKey, 'presented');
                await _notificationService.cancelVerificationAndSearchAlerts();
              }
              _addLog(
                'To complete booking, open app for ${chosen.$1.tripNumber}',
              );
              // Security check is raised only ONCE per booking attempt
              if (!_turnstileRequestedForBooking) {
                _turnstileRequestedForBooking = true;
                final label = '${chosen.$1.tripNumber} · ${chosen.$2.type}';
                await SecureStore.write('rail_turnstile_context', label);
                await _raiseTurnstile(
                  label,
                  chosen.$1.tripNumber,
                  chosen.$2.type,
                );
              }
              notifyListeners();
              return;
            }

            // One attempt per monitoring cycle. The shared limiter and
            // scheduler choose the next safe check instead of looping here.
            _scheduler.recordFailure(error);
            _lastBookingError = friendlyErrorMessage(error);
            _lastError = _lastBookingError;
            _addLog('Auto-booking paused: $_lastBookingError', isError: true);
            if (await BookingService.pending() != null) {
              // Keep a partial/unknown reservation for review; never replay it.
              stopMonitoring();
              _scheduleReservationExpiryWatch();
            } else if (_isMonitoring && bookingIntent.autoReserve) {
              // User requirement: if one booking failed, retry another booking after 3-4s
              _scheduleNext(overrideDelay: const Duration(milliseconds: 3500));
            }
            notifyListeners();
            return;
          }
        }
        _scheduler.recordSuccess();
      } catch (e) {
        _scheduler.recordFailure(e);
        _lastError = friendlyErrorMessage(e);
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

  Future<void> _runViaSearch(AuthSession session, List<TrainTrip> trains) async {
    if (_isSearchingVia || !_isMonitoring || _disposed) return;
    _isSearchingVia = true;
    _lastViaSearchAt = DateTime.now();
    notifyListeners();
    try {
      final targets = trains.where((t) => isTrainMonitored(t.tripNumber)).toList();
      if (targets.isEmpty) return;

      final allVia = <IntermediateJourney>[];
      for (final train in targets) {
        if (!_isMonitoring || _disposed) break;
        final results = await IntermediateStationSearch.search(
          train: train,
          from: _fromCity,
          to: _toCity,
          date: _dateOfJourney,
          auth: session,
          seatClass: _targetSeatClass,
          cancelled: () => !_isMonitoring || _disposed,
        );
        allVia.addAll(results);
        if (allVia.isNotEmpty) break;
      }

      if (_disposed || !_isMonitoring) return;

      if (allVia.isNotEmpty) {
        _viaJourneys = allVia;
        _recentViaJourneys = allVia;
        notifyListeners();

        try {
          final viaJson = allVia
              .map(
                (j) => {
                  'via': j.via,
                  'viaCity': j.viaCity,
                  'firstDate': j.firstDate,
                  'secondDate': j.secondDate,
                  'first': j.first.toJson(),
                  'second': j.second.toJson(),
                  'firstSeat': j.firstSeat.toJson(),
                  'secondSeat': j.secondSeat.toJson(),
                },
              )
              .toList();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('via_results_$_searchId', jsonEncode(viaJson));
        } catch (_) {}

        final best = allVia.first;
        final viaKey =
            '${best.first.tripNumber}:${best.canonicalVia}:${best.firstSeat.type}:${best.seats}';
        if (_lastNotifiedViaKey != viaKey) {
          _lastNotifiedViaKey = viaKey;
          _addLog(
            '🔍 VIA TICKET FOUND! ${best.first.tripNumber} via ${best.via} has ${best.seats} [${best.firstSeat.type}] seats!',
            isAlert: true,
            viaJourney: best,
          );
          try {
            await _notificationService.triggerViaSeatAvailableAlert(
              trainName: best.first.tripNumber,
              viaStation: best.via,
              fromCity: _fromCity,
              toCity: _toCity,
              travelDate: _dateOfJourney,
              seatType: best.firstSeat.displayName,
              seatCount: best.seats,
            );
          } catch (e) {
            _addLog('Via seat notification error: $e', isError: true);
          }
        }
      }
    } catch (e) {
      _addLog('Via search check: ${friendlyErrorMessage(e)}');
    } finally {
      _isSearchingVia = false;
      notifyListeners();
    }
  }

  void _addLog(
    String message, {
    bool isAlert = false,
    bool isError = false,
    IntermediateJourney? viaJourney,
  }) {
    _logs.insert(
      0,
      MonitorLog(
        time: DateTime.now(),
        message: message,
        isAlert: isAlert,
        isError: isError,
        viaJourney: viaJourney,
      ),
    );
    if (_logs.length > 200) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  DateTime? _departureForTrain(TrainTrip train) => parseDepartureDateTime(
    departureDateTimeJd: train.departureDateTimeJd,
    departureDateTime: train.departureDateTime,
    departureFullDate: train.departureFullDate,
    dateOfJourney: _dateOfJourney,
  );

  void _refreshDepartureDeadline() {
    final matching = _lastTrains
        .where((t) => isTrainMonitored(t.tripNumber))
        .toList();
    final complete = _targetTrains.every(
      (target) => matching.any((t) => _matchTrain(target, t.tripNumber)),
    );
    final departures =
        matching.map(_departureForTrain).whereType<DateTime>().toList()..sort();
    _expiresAt =
        complete &&
            departures.isNotEmpty &&
            departures.length == matching.length
        ? departures.last
        : parseDepartureDateTime(dateOfJourney: _dateOfJourney);
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
