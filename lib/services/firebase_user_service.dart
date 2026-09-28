import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_options.dart';
import '../models/auth_session.dart';
import 'pro_service.dart';

/// Service responsible for managing user data in Firebase Firestore:
/// - Stores and syncs user profiles in the 'users' collection (keyed by phone number).
/// - Tracks active / inactive user status and timestamps.
/// - Records timestamped activity logs (both in subcollection and recent array).
/// - Synchronizes Pro user status from Firestore in real-time.
class FirebaseUserService extends ChangeNotifier {
  static final FirebaseUserService _instance = FirebaseUserService._internal();
  factory FirebaseUserService() => _instance;
  FirebaseUserService._internal();

  bool _isFirebaseReady = false;
  String? _currentPhone;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  ProService? _proService;

  bool get isFirebaseReady => _isFirebaseReady;
  String? get currentPhone => _currentPhone;
  FirebaseFirestore? get firestore => _isFirebaseReady ? FirebaseFirestore.instance : null;

  /// Initialize Firebase with user project configuration
  Future<void> initialize({ProService? proService}) async {
    _proService = proService;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _isFirebaseReady = true;
      debugPrint('[FirebaseUserService] Firebase initialized successfully.');
    } catch (e) {
      _isFirebaseReady = false;
      debugPrint('[FirebaseUserService] Firebase initialize skipped or offline: $e');
    }
  }

  void attachProService(ProService proService) {
    _proService = proService;
  }

  /// Clean phone number to safe document key (e.g. 01813570430)
  static String normalizePhone(String? raw) {
    if (raw == null) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('880') && digits.length >= 13) {
      return digits.substring(2); // Remove country code 88
    }
    return digits;
  }

  /// Sync user on successful login
  Future<void> syncUserOnLogin(AuthSession session) async {
    String phone = normalizePhone(session.phoneNumber);
    if (phone.isEmpty) {
      phone = normalizePhone(session.displayName);
    }
    if (phone.isEmpty && session.email != null && session.email!.contains('@')) {
      phone = session.email!.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    }
    if (phone.isEmpty) {
      final dev = session.deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      phone = dev.isNotEmpty ? 'user_$dev' : 'user_active';
    }

    _currentPhone = phone;
    _startListeningToUserDoc(phone);

    if (!_isFirebaseReady) {
      debugPrint('[FirebaseUserService] Firebase not initialized. Retrying initialize...');
      await initialize(proService: _proService);
    }

    if (!_isFirebaseReady) {
      debugPrint('🚨 [FirebaseUserService] syncUserOnLogin skipped: Firebase is not available.');
      return;
    }

    try {
      debugPrint('🚀 [FirebaseUserService] Writing user "$phone" to Firestore "users" collection...');
      final docRef = FirebaseFirestore.instance.collection('users').doc(phone);
      final snapshot = await docRef.get();

      final now = FieldValue.serverTimestamp();
      final loginLog = {
        'action': 'LOGIN',
        'details': 'User logged in via Bangladesh Railway portal',
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (!snapshot.exists) {
        // Create new user profile in Firestore
        await docRef.set({
          'phone': phone,
          'displayName': session.displayName ?? '',
          'email': session.email ?? '',
          'isPro': false, // Admin can toggle this in Firebase console
          'isActive': true,
          'createdAt': now,
          'lastActiveAt': now,
          'lastLoginAt': now,
          'recentActivity': [loginLog],
        }, SetOptions(merge: true));
        debugPrint('✅ [FirebaseUserService] Successfully created user "$phone" in Firestore!');
      } else {
        // Update existing user profile
        final data = snapshot.data();
        final currentPro = data?['isPro'] == true;
        _proService?.updateProStatus(currentPro);

        await docRef.update({
          'isActive': true,
          'lastActiveAt': now,
          'lastLoginAt': now,
          if (session.displayName != null && session.displayName!.isNotEmpty)
            'displayName': session.displayName,
          if (session.email != null && session.email!.isNotEmpty)
            'email': session.email,
          'recentActivity': FieldValue.arrayUnion([loginLog]),
        });
        debugPrint('✅ [FirebaseUserService] Successfully updated user "$phone" in Firestore!');
      }

      // Record in dedicated activity_logs subcollection
      await _writeSubcollectionLog(phone, action: 'LOGIN', details: 'User logged in');
      notifyListeners();
    } catch (e) {
      debugPrint('🚨 [FirebaseUserService] syncUserOnLogin error: $e');
    }
  }

  /// Start real-time Firestore listener on the user document
  void _startListeningToUserDoc(String phone) {
    if (!_isFirebaseReady) return;

    _userDocSubscription?.cancel();
    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(phone)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          final isPro = data?['isPro'] == true;
          _proService?.updateProStatus(isPro);
          notifyListeners();
        }
      },
      onError: (err) {
        debugPrint('[FirebaseUserService] User doc listener error: $err');
      },
    );
  }

  /// Update active / inactive status of user
  Future<void> setUserActive(bool isActive) async {
    final phone = _currentPhone;
    if (phone == null || phone.isEmpty || !_isFirebaseReady) return;

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(phone);
      await docRef.set({
        'isActive': isActive,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await logActivity(
        action: isActive ? 'USER_ACTIVE' : 'USER_INACTIVE',
        details: isActive ? 'App opened / active in foreground' : 'App paused / sent to background',
      );
    } catch (e) {
      debugPrint('[FirebaseUserService] setUserActive error: $e');
    }
  }

  /// Sync currently active notifier details
  Future<void> syncNotifierState({
    required bool isMonitoring,
    String? fromCity,
    String? toCity,
    String? dateOfJourney,
    String? targetTrain,
    String? targetSeatClass,
  }) async {
    final phone = _currentPhone;
    if (phone == null || phone.isEmpty || !_isFirebaseReady) return;

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(phone);
      if (isMonitoring) {
        await docRef.set({
          'isActive': true,
          'lastActiveAt': FieldValue.serverTimestamp(),
          'currentNotifier': {
            'isMonitoring': true,
            'from': fromCity ?? '',
            'to': toCity ?? '',
            'date': dateOfJourney ?? '',
            'train': targetTrain ?? 'ALL',
            'seatClass': targetSeatClass ?? 'ALL',
            'startedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));

        await logActivity(
          action: 'MONITORING_START',
          details: 'Searching $fromCity -> $toCity on $dateOfJourney (Train: ${targetTrain ?? "ALL"}, Seat: ${targetSeatClass ?? "ALL"})',
        );
      } else {
        await docRef.set({
          'currentNotifier': {
            'isMonitoring': false,
            'stoppedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));

        await logActivity(
          action: 'MONITORING_STOP',
          details: 'Monitoring stopped by user or completed',
        );
      }
    } catch (e) {
      debugPrint('[FirebaseUserService] syncNotifierState error: $e');
    }
  }

  /// Log when seats are found
  Future<void> logSeatsFound({
    required String trainName,
    required String seatType,
    required int seatCount,
  }) async {
    await logActivity(
      action: 'SEATS_FOUND',
      details: 'Found $seatCount seat(s) for $trainName ($seatType)',
    );
  }

  /// Log arbitrary activity to Firestore
  Future<void> logActivity({
    required String action,
    required String details,
  }) async {
    final phone = _currentPhone;
    if (phone == null || phone.isEmpty || !_isFirebaseReady) return;

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(phone);
      final logEntry = {
        'action': action,
        'details': details,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await docRef.set({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'recentActivity': FieldValue.arrayUnion([logEntry]),
      }, SetOptions(merge: true));

      await _writeSubcollectionLog(phone, action: action, details: details);
    } catch (e) {
      debugPrint('[FirebaseUserService] logActivity error: $e');
    }
  }

  Future<void> _writeSubcollectionLog(
    String phone, {
    required String action,
    required String details,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .collection('activity_logs')
          .add({
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Clear session and stop listener
  Future<void> clearSession() async {
    if (_currentPhone != null && _isFirebaseReady) {
      await logActivity(action: 'LOGOUT', details: 'User signed out or cleared session');
      await setUserActive(false);
    }
    _userDocSubscription?.cancel();
    _userDocSubscription = null;
    _currentPhone = null;
    _proService?.updateProStatus(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }
}
