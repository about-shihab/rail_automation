import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/railway_stations.dart';
import 'rail_api_config.dart';

/// Public operational settings only. Credentials never belong in this table.
class AppConfig extends ChangeNotifier {
  static final instance = AppConfig();
  static const cacheKey = 'rail_app_config_v1';
  static final defaults = <String, dynamic>{
    'poll_interval_seconds': 120,
    'request_timeout_seconds': 15,
    'free_monitor_seconds': 3600,
    'low_availability_threshold': 4,
    'max_seats': 4,
    'default_seat_class': 'SNIGDHA',
    'seat_classes': [
      'ALL',
      'SNIGDHA',
      'S_CHAIR',
      'AC_S',
      'AC_B',
      'F_SEAT',
      'F_BERTH',
      'SHOVON',
    ],
    'stations': railwayStations,
    'sms_senders': ['RAILWAY', 'SHOHOZ', 'BANGLADESH RAILWAY'],
    'otp_length': 6,
    'otp_window_seconds': 180,
    'login_retry_interval_seconds': 60,
    // Seat-search scheduling (see SearchScheduler).
    'search_jitter_percent': 10,
    'search_backoff_multiplier': 2.0,
    'search_max_backoff_seconds': 300,
    'search_near_departure_minutes': 0,
    'search_near_departure_interval_seconds': 0,
    // Reservation hold (Railway keeps a seat for 5 minutes) and what to do
    // when it expires unpaid.
    'reservation_timeout_minutes': 5,
    'resume_search_after_expiry': true,
    'admin_push_enabled': false,
    // Non-secret request headers / Turnstile keys, overridable from the DB.
    'api_headers': <String, dynamic>{},
    'turnstile_site_keys': <String, dynamic>{},
    'api_operations': <String, dynamic>{},
  };
  Map<String, dynamic> _values = Map.of(defaults);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? syncError;
  int number(String key) => _values[key] as int;
  String string(String key) => _values[key] as String;
  List<String> strings(String key) => List<String>.from(_values[key]);
  bool boolean(String key) => _values[key] == true;
  double decimal(String key) => (_values[key] as num).toDouble();
  int get pollSeconds => number('poll_interval_seconds');

  /// Seconds between seat searches. A value on the `search_trips` operation
  /// wins over the global `poll_interval_seconds`.
  int get searchIntervalSeconds {
    final value = apiOperation('search_trips')['poll_interval_seconds'];
    return value is int ? value : pollSeconds;
  }

  Map<String, dynamic> apiOperation(String key) =>
      Map<String, dynamic>.from(_values['api_operations'][key] ?? {});

  Map<String, String> get apiHeaders =>
      Map<String, String>.from(_values['api_headers'] as Map);

  /// Turnstile site key for [purpose], or null to use the built-in default.
  String? siteKey(String purpose) =>
      (_values['turnstile_site_keys'] as Map)[purpose] as String?;

  static Map<String, dynamic> validate(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.of(defaults);
    const limits = <String, (int, int)>{
      'poll_interval_seconds': (10, 86400),
      'request_timeout_seconds': (5, 120),
      'free_monitor_seconds': (60, 86400),
      'low_availability_threshold': (1, 10),
      'max_seats': (1, 4),
      'otp_length': (4, 8),
      'otp_window_seconds': (30, 600),
      'login_retry_interval_seconds': (10, 3600),
      'search_jitter_percent': (0, 50),
      'search_max_backoff_seconds': (10, 3600),
      'search_near_departure_minutes': (0, 1440),
      'search_near_departure_interval_seconds': (0, 3600),
      'reservation_timeout_minutes': (1, 15),
    };

    // Check for minutes-based time limit aliases from DB (e.g. time_limit_minutes: 60 or time_limit: 60)
    int? timeLimitSecs;
    if (input.containsKey('time_limit_minutes')) {
      final v = input['time_limit_minutes'];
      final m = v is num ? v.toInt() : int.tryParse('$v');
      if (m != null && m > 0) timeLimitSecs = m * 60;
    } else if (input.containsKey('free_monitor_minutes')) {
      final v = input['free_monitor_minutes'];
      final m = v is num ? v.toInt() : int.tryParse('$v');
      if (m != null && m > 0) timeLimitSecs = m * 60;
    } else if (input.containsKey('time_limit')) {
      final v = input['time_limit'];
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n != null && n > 0) {
        timeLimitSecs = n <= 180 ? n * 60 : n;
      }
    }
    if (timeLimitSecs != null &&
        timeLimitSecs >= 60 &&
        timeLimitSecs <= 86400) {
      result['free_monitor_seconds'] = timeLimitSecs;
    }

    for (final entry in limits.entries) {
      if (entry.key == 'free_monitor_seconds' && timeLimitSecs != null) {
        continue;
      }
      final raw = input[entry.key];
      final val = raw is num
          ? raw.toInt()
          : (raw is String ? int.tryParse(raw) : null);
      if (val != null && val >= entry.value.$1 && val <= entry.value.$2) {
        result[entry.key] = val;
      }
    }
    for (final key in ['seat_classes', 'stations', 'sms_senders']) {
      final value = input[key];
      if (value is List &&
          value.isNotEmpty &&
          value.every((e) => e is String && e.trim().isNotEmpty)) {
        result[key] = value.cast<String>().toSet().toList();
      }
    }
    final seat = input['default_seat_class'];
    if (seat is String &&
        seat != 'ALL' &&
        (result['seat_classes'] as List).contains(seat)) {
      result['default_seat_class'] = seat;
    }
    final multiplier = input['search_backoff_multiplier'];
    final multiplierValue = multiplier is num
        ? multiplier.toDouble()
        : (multiplier is String ? double.tryParse(multiplier) : null);
    if (multiplierValue != null &&
        multiplierValue >= 1.0 &&
        multiplierValue <= 4.0) {
      result['search_backoff_multiplier'] = multiplierValue;
    }
    if (input['resume_search_after_expiry'] is bool) {
      result['resume_search_after_expiry'] =
          input['resume_search_after_expiry'];
    }
    if (input['admin_push_enabled'] is bool) {
      result['admin_push_enabled'] = input['admin_push_enabled'];
    }
    result['api_headers'] = RailApiConfig.validateHeaders(input['api_headers']);
    result['turnstile_site_keys'] = RailApiConfig.validateSiteKeys(
      input['turnstile_site_keys'],
    );
    result['api_operations'] = RailApiConfig.validate(input['api_operations']);
    return result;
  }

  final Map<String, Map<String, dynamic>> _documents = {};
  Map<String, dynamic> get _rawFirestoreData => {
    ...?_documents['workflow'],
    ...?_documents['settings'],
  };
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _settingsSubscription;

  Future<void> _updateFromDoc(String source, Map<String, dynamic>? data) async {
    _documents[source] = data ?? {};
    _values = validate(_rawFirestoreData);
    syncError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, jsonEncode(_values));
    notifyListeners();
  }

  /// Actively fetch configuration from Firestore when app opens
  Future<void> syncFromFirestore() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final firestore = FirebaseFirestore.instance;
      // Fetch workflow doc & settings doc
      final workflowDoc = await firestore
          .collection('app_config')
          .doc('workflow')
          .get();
      final settingsDoc = await firestore
          .collection('app_config')
          .doc('settings')
          .get();

      _documents['workflow'] = workflowDoc.data() ?? {};
      _documents['settings'] = settingsDoc.data() ?? {};

      _values = validate(_rawFirestoreData);
      syncError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(_values));
      notifyListeners();
    } catch (e) {
      debugPrint('[AppConfig] Firestore sync error: $e');
    }
  }

  Future<void> initialize() async {
    await reloadCache();
    if (Firebase.apps.isEmpty) return;

    unawaited(syncFromFirestore());

    if (_subscription != null) return;
    _subscription = FirebaseFirestore.instance
        .collection('app_config')
        .doc('workflow')
        .snapshots()
        .listen(
          (doc) {
            unawaited(_updateFromDoc('workflow', doc.data()));
          },
          onError: (_) {
            syncError =
                'Using cached settings; database settings are unavailable.';
            notifyListeners();
          },
        );

    _settingsSubscription?.cancel();
    _settingsSubscription = FirebaseFirestore.instance
        .collection('app_config')
        .doc('settings')
        .snapshots()
        .listen((doc) {
          unawaited(_updateFromDoc('settings', doc.data()));
        }, onError: (_) {});
  }

  Future<void> reloadCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      _values = validate(
        jsonDecode(prefs.getString(cacheKey) ?? '{}') as Map<String, dynamic>,
      );
    } catch (_) {
      _values = Map.of(defaults);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _settingsSubscription?.cancel();
    super.dispose();
  }
}
