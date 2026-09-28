import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/railway_stations.dart';

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
    'seat_classes': ['ALL', 'SNIGDHA', 'S_CHAIR', 'AC_S', 'AC_B', 'F_SEAT', 'F_BERTH', 'SHOVON'],
    'stations': railwayStations,
    'sms_senders': ['RAILWAY', 'SHOHOZ', 'BANGLADESH RAILWAY'],
    'otp_length': 6,
    'otp_window_seconds': 180,
  };
  Map<String, dynamic> _values = Map.of(defaults);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? syncError;
  int number(String key) => _values[key] as int;
  String string(String key) => _values[key] as String;
  List<String> strings(String key) => List<String>.from(_values[key]);
  int get pollSeconds => number('poll_interval_seconds');

  static Map<String, dynamic> validate(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.of(defaults);
    const limits = <String, (int, int)>{
      'poll_interval_seconds': (60, 86400),
      'request_timeout_seconds': (5, 120),
      'free_monitor_seconds': (60, 86400),
      'low_availability_threshold': (1, 4),
      'max_seats': (1, 4),
      'otp_length': (4, 8),
      'otp_window_seconds': (30, 600),
    };
    for (final entry in limits.entries) {
      final value = input[entry.key];
      if (value is int && value >= entry.value.$1 && value <= entry.value.$2) {
        result[entry.key] = value;
      }
    }
    for (final key in ['seat_classes', 'stations', 'sms_senders']) {
      final value = input[key];
      if (value is List && value.isNotEmpty && value.every((e) => e is String && e.trim().isNotEmpty)) {
        result[key] = value.cast<String>().toSet().toList();
      }
    }
    final seat = input['default_seat_class'];
    if (seat is String && seat != 'ALL' && (result['seat_classes'] as List).contains(seat)) {
      result['default_seat_class'] = seat;
    }
    return result;
  }

  Future<void> initialize() async {
    await reloadCache();
    if (Firebase.apps.isEmpty || _subscription != null) return;
    _subscription = FirebaseFirestore.instance.collection('app_config').doc('workflow').snapshots().listen((doc) async {
      _values = validate(doc.data() ?? {});
      syncError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(_values));
      notifyListeners();
    }, onError: (_) {
      syncError = 'Using cached settings; database settings are unavailable.';
      notifyListeners();
    });
  }

  Future<void> reloadCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      _values = validate(jsonDecode(prefs.getString(cacheKey) ?? '{}') as Map<String, dynamic>);
    } catch (_) {
      _values = Map.of(defaults);
    }
  }
}
