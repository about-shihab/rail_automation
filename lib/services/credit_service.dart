import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/credit_transaction.dart';
import '../models/credit_package.dart';
import 'firebase_user_service.dart';

class CreditService extends ChangeNotifier {
  static final CreditService _instance = CreditService._internal();
  factory CreditService() => _instance;
  CreditService._internal();

  static const String _prefCreditsKey = 'rps_user_credits';
  static const String _prefTransactionsKey = 'rps_credit_transactions';
  static const String _prefPackagesKey = 'rps_credit_packages_cache';
  static const String _prefBkashNumberKey = 'rps_bkash_number_cache';
  static const String defaultBkashNumber = '01813570430';

  static const List<CreditPackage> defaultPackages = [
    CreditPackage(id: 'pkg_10', amount: 50.0, credits: 10, label: '১০ ক্রেডিট (৳৫০)'),
    CreditPackage(id: 'pkg_25', amount: 100.0, credits: 25, label: '২৫ ক্রেডিট (৳১০০)', popular: true),
    CreditPackage(id: 'pkg_60', amount: 200.0, credits: 60, label: '৬০ ক্রেডিট (৳২০০)'),
  ];

  int _credits = 10; // Default 10 credits for every user
  List<CreditTransaction> _transactions = [];
  List<CreditPackage> _packages = defaultPackages;
  String _bkashNumber = defaultBkashNumber;
  bool _isInitialized = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _packageSubscription;

  int get credits => _credits;
  List<CreditTransaction> get transactions => List.unmodifiable(_transactions);
  List<CreditPackage> get packages => List.unmodifiable(_packages);
  String get bkashNumber => _bkashNumber;
  bool get hasCredits => _credits > 0;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_prefCreditsKey)) {
        // Initial setup for new user: 10 credits
        await prefs.setInt(_prefCreditsKey, 10);
        _credits = 10;
      } else {
        _credits = prefs.getInt(_prefCreditsKey) ?? 10;
      }

      // Load cached packages from DB if present
      final cachedPackages = prefs.getString(_prefPackagesKey);
      if (cachedPackages != null) {
        try {
          final list = (jsonDecode(cachedPackages) as List)
              .map((e) => CreditPackage.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          if (list.isNotEmpty) _packages = list;
        } catch (_) {}
      }
      _bkashNumber = prefs.getString(_prefBkashNumberKey) ?? defaultBkashNumber;

      final rawList = prefs.getStringList(_prefTransactionsKey);
      if (rawList != null) {
        _transactions = rawList.map((item) {
          try {
            return CreditTransaction.fromJson(jsonDecode(item) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<CreditTransaction>().toList();
      }

      notifyListeners();
      unawaited(_syncFromFirestore());
    } catch (e) {
      debugPrint('[CreditService] Init error: $e');
    }
  }

  /// Sync user credits and transactions from Firestore if available
  Future<void> _syncFromFirestore() async {
    final phone = FirebaseUserService().currentPhone;
    final firestore = FirebaseUserService().firestore;
    if (phone == null || phone.isEmpty || firestore == null) return;

    try {
      final docRef = firestore.collection('users').doc(phone);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data.containsKey('credits')) {
          final serverCredits = (data['credits'] as num).toInt();
          _credits = serverCredits;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_prefCreditsKey, _credits);
          notifyListeners();
        }
      }

      // Fetch transaction records from subcollection
      final txSnapshot = await docRef
          .collection('credit_transactions')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      if (txSnapshot.docs.isNotEmpty) {
        final serverTxs = txSnapshot.docs.map((doc) {
          final d = doc.data();
          d['id'] = doc.id;
          return CreditTransaction.fromJson(d);
        }).toList();

        _transactions = serverTxs;
        await _saveTransactionsLocally();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CreditService] Firestore sync error: $e');
    }

    // Fetch token buy packages and payment settings from DB (Firestore: app_config/credit_packages)
    try {
      final configDoc = await firestore.collection('app_config').doc('credit_packages').get();
      if (configDoc.exists && configDoc.data() != null) {
        await _applyPackagesData(configDoc.data()!);
      }
      _packageSubscription?.cancel();
      _packageSubscription = firestore
          .collection('app_config')
          .doc('credit_packages')
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          unawaited(_applyPackagesData(doc.data()!));
        }
      }, onError: (_) {});
    } catch (e) {
      debugPrint('[CreditService] Firestore credit_packages error: $e');
    }
  }

  Future<void> _applyPackagesData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool changed = false;
      if (data['bkash_number'] is String && (data['bkash_number'] as String).trim().isNotEmpty) {
        final newBkash = (data['bkash_number'] as String).trim();
        if (newBkash != _bkashNumber) {
          _bkashNumber = newBkash;
          await prefs.setString(_prefBkashNumberKey, _bkashNumber);
          changed = true;
        }
      }
      if (data['packages'] is List) {
        final list = (data['packages'] as List)
            .map((item) => CreditPackage.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (list.isNotEmpty) {
          _packages = list;
          await prefs.setString(
            _prefPackagesKey,
            jsonEncode(_packages.map((p) => p.toJson()).toList()),
          );
          changed = true;
        }
      }
      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CreditService] Error applying package data: $e');
    }
  }

  /// Deduct 1 credit for booking
  Future<bool> deductBookingCredit({required String trainName, required String seatInfo}) async {
    if (_credits < 1) {
      return false;
    }

    _credits -= 1;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefCreditsKey, _credits);

      // Log in Firestore
      final phone = FirebaseUserService().currentPhone;
      final firestore = FirebaseUserService().firestore;
      if (phone != null && phone.isNotEmpty && firestore != null) {
        final docRef = firestore.collection('users').doc(phone);
        await docRef.set({
          'credits': _credits,
          'lastCreditUsedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseUserService().logActivity(
          action: 'CREDIT_USED',
          details: 'Used 1 credit for booking $trainName ($seatInfo). Remaining: $_credits',
        );
      }
    } catch (e) {
      debugPrint('[CreditService] deductBookingCredit error: $e');
    }

    return true;
  }

  /// Buy/Recharge credits via bKash
  Future<bool> submitBkashRecharge({
    required String bkashSender,
    required String trxId,
    required double amount,
    required int requestedCredits,
  }) async {
    final cleanTrx = trxId.trim().toUpperCase();
    if (cleanTrx.isEmpty) return false;

    // Check duplicate TrxID
    if (_transactions.any((tx) => tx.trxId.toUpperCase() == cleanTrx)) {
      return false;
    }

    final newTx = CreditTransaction(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      phone: FirebaseUserService().currentPhone ?? 'anonymous',
      bkashSender: bkashSender.trim(),
      trxId: cleanTrx,
      amount: amount,
      credits: requestedCredits,
      status: 'Approved', // Auto-credited immediately for seamless UX
      createdAt: DateTime.now(),
    );

    _credits += requestedCredits;
    _transactions.insert(0, newTx);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefCreditsKey, _credits);
      await _saveTransactionsLocally();

      // Sync to Firestore
      final phone = FirebaseUserService().currentPhone;
      final firestore = FirebaseUserService().firestore;
      if (phone != null && phone.isNotEmpty && firestore != null) {
        final docRef = firestore.collection('users').doc(phone);
        await docRef.set({
          'credits': _credits,
          'lastRechargeAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await docRef.collection('credit_transactions').doc(newTx.id).set(newTx.toJson());

        await FirebaseUserService().logActivity(
          action: 'BKASH_RECHARGE',
          details: 'Recharged $requestedCredits credits via bKash TrxID $cleanTrx (৳$amount). New balance: $_credits',
        );
      }
    } catch (e) {
      debugPrint('[CreditService] submitBkashRecharge error: $e');
    }

    return true;
  }

  Future<void> _saveTransactionsLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _transactions.map((tx) => jsonEncode(tx.toJson())).toList();
    await prefs.setStringList(_prefTransactionsKey, jsonList);
  }
}
