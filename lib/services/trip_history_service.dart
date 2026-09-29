import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trip_record.dart';
import 'firebase_user_service.dart';

class TripHistoryService extends ChangeNotifier {
  static final TripHistoryService _instance = TripHistoryService._internal();
  factory TripHistoryService() => _instance;
  TripHistoryService._internal();

  static const String _prefTripsKey = 'rail_trip_history_v1';
  List<TripRecord> _trips = [];
  bool _isInitialized = false;

  List<TripRecord> get trips => List.unmodifiable(_trips);

  List<TripRecord> get successfulTrips => _trips
      .where((t) =>
          t.status == TripBookingStatus.successful ||
          t.status == TripBookingStatus.awaitingOtp)
      .toList();

  List<TripRecord> get failedTrips => _trips
      .where((t) =>
          t.status == TripBookingStatus.failed ||
          t.status == TripBookingStatus.expired)
      .toList();

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefTripsKey);
      if (raw != null) {
        _trips = raw.map((item) {
          try {
            return TripRecord.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        }).whereType<TripRecord>().toList();
      }
      notifyListeners();
      unawaited(_syncFromFirestore());
    } catch (e) {
      debugPrint('[TripHistoryService] Init error: $e');
    }
  }

  Future<void> _syncFromFirestore() async {
    final phone = FirebaseUserService().currentPhone;
    final firestore = FirebaseUserService().firestore;
    if (phone == null || phone.isEmpty || firestore == null) return;
    try {
      final snap = await firestore
          .collection('users')
          .doc(phone)
          .collection('trips')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      if (snap.docs.isNotEmpty) {
        final serverTrips = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return TripRecord.fromJson(data);
        }).toList();

        // Merge keeping latest
        for (final st in serverTrips) {
          final idx = _trips.indexWhere((t) => t.id == st.id);
          if (idx >= 0) {
            _trips[idx] = st;
          } else {
            _trips.add(st);
          }
        }
        _trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _saveLocally();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TripHistoryService] Firestore sync error: $e');
    }
  }

  Future<void> recordTrip(TripRecord record) async {
    final idx = _trips.indexWhere((t) => t.id == record.id);
    if (idx >= 0) {
      _trips[idx] = record;
    } else {
      _trips.insert(0, record);
    }
    notifyListeners();
    await _saveLocally();

    // Sync to Firestore in background
    unawaited(_syncRecordToFirestore(record));
  }

  Future<void> updateTripStatus(
    String id,
    TripBookingStatus status, {
    String? failureReason,
  }) async {
    if (id.isEmpty) return;
    final idx = _trips.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      final updated = _trips[idx].copyWith(
        status: status,
        failureReason: failureReason ?? _trips[idx].failureReason,
      );
      _trips[idx] = updated;
      notifyListeners();
      await _saveLocally();
      unawaited(_syncRecordToFirestore(updated));
    }
  }

  Future<void> _syncRecordToFirestore(TripRecord record) async {
    final phone = FirebaseUserService().currentPhone;
    final firestore = FirebaseUserService().firestore;
    if (phone == null || phone.isEmpty || firestore == null) return;
    try {
      await firestore
          .collection('users')
          .doc(phone)
          .collection('trips')
          .doc(record.id)
          .set(record.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TripHistoryService] Sync error: $e');
    }
  }

  Future<void> _saveLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _trips.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_prefTripsKey, list);
    } catch (e) {
      debugPrint('[TripHistoryService] Save error: $e');
    }
  }

  Future<void> clearHistory() async {
    _trips.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTripsKey);
    } catch (_) {}
  }
}
