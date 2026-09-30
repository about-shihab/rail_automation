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
  Future<void> clearSearch() async {
    stopMonitoring();
    await _persistence;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(preferenceKey);
    _dateOfJourney = '';
    _lastTrains = [];
    _lastError = null;
    _lastBookingError = null;
    notifyListeners();
  }

  static const preferenceKey = 'active_ticket_search';
  String? _searchId;
  DateTime? _expiresAt;
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
      _targetTrain = data['train'] as String?;
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
      _isMonitoring = data['active'] == true;
      bookingIntent = BookingIntent.fromJson(
        Map<String, dynamic>.from(data['bookingIntent'] ?? {}),
      );
      final result = prefs.getString('ticket_results_$_searchId');
      if (result != null) {
        _lastTrains = (jsonDecode(result) as List)
            .map((e) => TrainTrip.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _seatsFoundCount = _lastTrains
            .where((t) => _targetTrain == null || t.tripNumber == _targetTrain)
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
      'train': _targetTrain,
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
  String? _targetTrain; // If null, monitors all trains on route
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
  String? get targetTrain => _targetTrain;
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
            r'422|turnstile|verification|cft_response',
            caseSensitive: false,
          ).hasMatch(_lastBookingError!)) ||
      (_lastError != null &&
          RegExp(
            r'422|turnstile|cft_response',
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

  int get elapsedMonitoringSeconds => _elapsedMonitoringSeconds;
  bool get isLimitReached => _isLimitReached;

  int get remainingFreeSeconds {
    if (proService.isPro) return -1; // Unlimited
    final remaining = _expiresAt?.difference(DateTime.now()).inSeconds ?? 0;
    return remaining > 0 ? remaining : 0;
  }

  double get freeProgressFraction {
    if (proService.isPro) return 1.0;
    return (_elapsedMonitoringSeconds /
            AppConfig.instance.number('free_monitor_seconds'))
        .clamp(0.0, 1.0);
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
    BookingIntent intent = const BookingIntent(),
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

    bookingIntent = intent;
    _intervalSeconds = AppConfig.instance.pollSeconds;
    _fromCity = fromCity;
    _toCity = toCity;
    _dateOfJourney = dateOfJourney;
    _targetTrain = targetTrain;
    _targetSeatClass =
        targetSeatClass == null ||
            targetSeatClass.trim().isEmpty ||
            targetSeatClass.trim().toUpperCase() == 'ALL' ||
            targetSeatClass.trim().toUpperCase() == 'RANDOM'
        ? null
        : targetSeatClass.trim().toUpperCase();
    _generation++;
    _searchId = DateTime.now().microsecondsSinceEpoch.toString();
    _expiresAt = proService.isPro
        ? null
        : DateTime.now().add(
            Duration(
              seconds: AppConfig.instance.number('free_monitor_seconds'),
            ),
          );
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
      '${proService.isPro ? " [PRO UNLIMITED]" : " [1-HOUR FREE LIMIT]"}',
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

      // Check 1-hour limit for free users
      if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
        _isLimitReached = true;
        stopMonitoring();
        _addLog(
          'Monitoring time limit reached. Start a new search to continue.',
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
        await _saveAndSchedule();
        _addLog(
          '⏱️ 5-minute reservation window expired. Live reservation and alerts cleared.',
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
      if (bookingIntent.autoReserve) {
        final pendingReservation = await BookingService.pending();
        if (pendingReservation != null) {
          final expiry = DateTime.tryParse('${pendingReservation['expiresAt'] ?? ''}');
          final isExpired = expiry != null && !expiry.isAfter(DateTime.now());
          if (isExpired) {
            // Automatically clear timed out reservation
            await BookingService.clear();
            _lastReservationExpired = true;
            // Each auto-book books only one time; user must explicitly re-autobook
            bookingIntent = bookingIntent.copyWith(autoReserve: false);
            await _saveAndSchedule();
            _addLog(
              '⏱️ Reservation timed out waiting for OTP. Cleared automatically. User must re-auto book.',
              isAlert: true,
            );
            notifyListeners();
          } else {
            await OtpVerifier.listen();
            return;
          }
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
        if (bookingIntent.autoReserve &&
            await BookingService.pending() == null) {
          final chosen = bookingIntent.choose(
            response.trains,
            train: _targetTrain,
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
              await _saveAndSchedule();
              await _notificationService.showReservation(reservation);
              await OtpVerifier.listen();
              notifyListeners();
              return;
            } catch (error) {
              if (_disposed ||
                  !_isMonitoring ||
                  generation != _generation ||
                  !await _savedSearchIsActive()) {
                return;
              }
              final clean = error
                  .toString()
                  .replaceAll('Exception: ', '')
                  .replaceAll('StateError: ', '');
              _lastError = clean;
              _lastBookingError = clean;
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

              final isTurnstile = RegExp(
                r'422|turnstile|cft_response|verification',
                caseSensitive: false,
              ).hasMatch(clean);

              if (isTurnstile) {
                // Security check should be triggered only ONCE per booking attempt
                if (!_turnstileRequestedForBooking) {
                  _turnstileRequestedForBooking = true;
                  await _notificationService.triggerTurnstileRequiredAlert(
                    trainName: chosen.$1.tripNumber,
                    seatType: chosen.$2.type,
                  );
                }
              } else {
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
          if (_targetTrain != null &&
              _targetTrain!.isNotEmpty &&
              train.tripNumber.toLowerCase() != _targetTrain!.toLowerCase()) {
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
                // Only alert for the specific targeted train; never broadcast for all trains
                if (_targetTrain == null || _targetTrain!.isEmpty) continue;
                await _notificationService.triggerSeatAvailableAlert(
                  trainName: train.tripNumber,
                  seatType: seat.displayName,
                  seatCount: seat.seatCounts.online,
                  travelDate: _dateOfJourney,
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
    super.dispose();
  }
}
