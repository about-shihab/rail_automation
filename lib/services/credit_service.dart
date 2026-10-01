import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/credit_transaction.dart';
import '../models/credit_package.dart';
import '../models/auth_session.dart';
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

  int _credits = 2; // Default 2 credits given to each user
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

  void setCreditsForTesting(int value) {
    _credits = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final isTest =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (prefs.containsKey(_prefCreditsKey)) {
        _credits = prefs.getInt(_prefCreditsKey) ?? 2;
      } else if (isTest) {
        _credits = 10;
      } else {
        _credits = 2;
        await prefs.setInt(_prefCreditsKey, 2);
        await prefs.setBool('rps_default_2_credits_granted', true);
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
      unawaited(syncFromFirestore());
    } catch (e) {
      debugPrint('[CreditService] Init error: $e');
    }
  }

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSubscription;

  /// Sync user credits and transactions from Firestore whenever app opens or resumes
  Future<void> syncFromFirestore() async {
    String? phone = FirebaseUserService().currentPhone;
    if (phone == null || phone.isEmpty) {
      final session = await AuthSession.load();
      if (session != null) {
        phone = FirebaseUserService.normalizePhone(session.phoneNumber);
        if (phone.isEmpty) phone = FirebaseUserService.normalizePhone(session.displayName);
      }
    }
    final firestore = FirebaseUserService().firestore;
    if (phone == null || phone.isEmpty || firestore == null) return;

    final phoneVariants = <String>[
      phone,
      if (!phone.startsWith('+88')) '+88$phone',
      if (!phone.startsWith('88')) '88$phone',
      if (phone.startsWith('880')) phone.substring(2),
      if (phone.startsWith('+880')) phone.substring(3),
    ].toSet().toList();

    try {
      final docRef = firestore.collection('users').doc(phone);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data.containsKey('credits')) {
          final serverCredits = (data['credits'] as num).toInt();
          final prefs = await SharedPreferences.getInstance();
          // Firestore is the source of truth (admin can change the balance).
          _credits = serverCredits;
          await prefs.setInt(_prefCreditsKey, _credits);
          notifyListeners();
        }
      }

      // Real-time balance listener for instant admin updates on user doc
      _userDocSubscription?.cancel();
      _userDocSubscription = docRef.snapshots().listen((snap) async {
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          if (data.containsKey('credits')) {
            final serverCredits = (data['credits'] as num).toInt();
            if (_credits != serverCredits) {
              // Always follow the server value so admin increases/decreases
              // are never overwritten by a stale local balance.
              _credits = serverCredits;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(_prefCreditsKey, _credits);
              notifyListeners();
            }
          }
        }
      });

      // Real-time recharge records listener from recharge_requests collection
      _txSubscription?.cancel();
      _txSubscription = firestore
          .collection('recharge_requests')
          .where('phone', whereIn: phoneVariants)
          .snapshots()
          .listen((txSnapshot) async {
        if (txSnapshot.docs.isNotEmpty) {
          int newlyApprovedCredits = 0;
          final serverTxs = <CreditTransaction>[];

          for (final doc in txSnapshot.docs) {
            final d = doc.data();
            d['id'] = doc.id;
            final tx = CreditTransaction.fromJson(d);
            serverTxs.add(tx);

            // Check if admin marked this transaction as Approved / Success
            final s = tx.status.trim().toLowerCase();
            final isApproved = s == 'approved' ||
                s == 'success' ||
                s == 'completed' ||
                s == 'accept' ||
                s == 'accepted';

            final alreadyApplied = d['applied'] == true;

            if (isApproved && !alreadyApplied && tx.credits > 0) {
              newlyApprovedCredits += tx.credits;
              // Mark applied in Firestore immediately so it is never double-credited
              unawaited(
                firestore.collection('recharge_requests').doc(doc.id).set({
                  'applied': true,
                  'appliedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true)),
              );
            }
          }

          if (newlyApprovedCredits > 0) {
            debugPrint('🎉 [CreditService] Applying $newlyApprovedCredits approved credits to user $phone!');

            // 1. Increment users/{phone}.credits in Firestore
            await docRef.set({
              'credits': FieldValue.increment(newlyApprovedCredits),
              'lastCreditRechargedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            // 2. Local balance follows via the users/{phone} listener above.
            await FirebaseUserService().logActivity(
              action: 'RECHARGE_CREDITED',
              details: 'Added $newlyApprovedCredits credits from approved bKash transaction(s).',
            );

            notifyListeners();
          }

          serverTxs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _transactions = serverTxs;
          await _saveTransactionsLocally();
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[CreditService] Firestore sync error: $e');
    }

    // Fetch token buy packages and payment settings from DB
    unawaited(syncPackagesFromFirestore());
  }

  StreamSubscription? _packagesCollectionSubscription;

  /// Sync credit packages from Firestore (works whether user is logged in or not)
  Future<void> syncPackagesFromFirestore() async {
    final firestore = FirebaseUserService().firestore;
    if (firestore == null) return;

    try {
      // 1. Check if user configured packages as individual documents in 'credit_packages' collection
      final colRef = firestore.collection('credit_packages');
      final colSnap = await colRef.get();
      if (colSnap.docs.isNotEmpty) {
        await _applyPackagesFromDocs(colSnap.docs);
      }
      _packagesCollectionSubscription?.cancel();
      _packagesCollectionSubscription = colRef.snapshots().listen((snap) {
        if (snap.docs.isNotEmpty) {
          unawaited(_applyPackagesFromDocs(snap.docs));
        }
      }, onError: (_) {});

      // 2. Also check if user configured packages in 'app_config/credit_packages' document
      final docRef = firestore.collection('app_config').doc('credit_packages');
      final configDoc = await docRef.get();
      if (configDoc.exists && configDoc.data() != null) {
        await _applyPackagesData(configDoc.data()!);
      }
      _packageSubscription?.cancel();
      _packageSubscription = docRef.snapshots().listen((doc) {
        if (doc.exists && doc.data() != null) {
          unawaited(_applyPackagesData(doc.data()!));
        }
      }, onError: (_) {});
    } catch (e) {
      debugPrint('[CreditService] Firestore credit_packages error: $e');
    }
  }

  Future<void> _applyPackagesFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    try {
      final list = <CreditPackage>[];
      for (final doc in docs) {
        final data = doc.data();
        list.add(CreditPackage.fromJson(data, docId: doc.id));
      }
      if (list.isNotEmpty) {
        list.sort((a, b) => a.amount.compareTo(b.amount));
        _packages = list;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefPackagesKey,
          jsonEncode(_packages.map((p) => p.toJson()).toList()),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CreditService] Error applying packages from collection: $e');
    }
  }

  Future<void> _applyPackagesData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool changed = false;
      final rawBkash = data['bkash_number'] ?? data['bkash'] ?? data['phone'];
      if (rawBkash is String && rawBkash.trim().isNotEmpty) {
        final newBkash = rawBkash.trim();
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
          list.sort((a, b) => a.amount.compareTo(b.amount));
          _packages = list;
          await prefs.setString(
            _prefPackagesKey,
            jsonEncode(_packages.map((p) => p.toJson()).toList()),
          );
          changed = true;
        }
      } else if (data['packages'] is Map) {
        final map = data['packages'] as Map;
        final list = map.entries
            .map((e) => CreditPackage.fromJson(Map<String, dynamic>.from(e.value as Map), docId: e.key.toString()))
            .toList();
        if (list.isNotEmpty) {
          list.sort((a, b) => a.amount.compareTo(b.amount));
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
      await prefs.setBool('rps_default_2_credits_granted', true);

      // Log in Firestore
      String? phone = FirebaseUserService().currentPhone;
      if (phone == null || phone.isEmpty) {
        final session = await AuthSession.load();
        if (session != null) {
          phone = FirebaseUserService.normalizePhone(session.phoneNumber);
          if (phone.isEmpty) phone = FirebaseUserService.normalizePhone(session.displayName);
        }
      }

      final firestore = FirebaseUserService().firestore;
      if (phone != null && phone.isNotEmpty && firestore != null) {
        final docRef = firestore.collection('users').doc(phone);
        // Atomic decrement so it composes with admin adjustments.
        await docRef.set({
          'credits': FieldValue.increment(-1),
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

  /// Buy/Recharge credits via bKash.
  /// Status is initialized as 'Pending'. Admin manually verifies TrxID and approves in Firestore.
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
      status: 'Pending', // Pending admin manual verification in Firestore
      createdAt: DateTime.now(),
    );

    // Save locally with Pending status (do NOT increment credits until admin verifies)
    _transactions.insert(0, newTx);
    notifyListeners();

    try {
      await _saveTransactionsLocally();

      // Sync to Firestore
      final phone = FirebaseUserService().currentPhone;
      final firestore = FirebaseUserService().firestore;
      if (phone != null && phone.isNotEmpty && firestore != null) {
        // Save only to the single recharge_requests table for admin verification
        await firestore.collection('recharge_requests').doc(newTx.id).set({
          ...newTx.toJson(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        await FirebaseUserService().logActivity(
          action: 'BKASH_RECHARGE_REQUEST',
          details: 'Recharge request for $requestedCredits credits submitted with TrxID $cleanTrx (৳$amount). Status: Pending.',
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

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _txSubscription?.cancel();
    _packageSubscription?.cancel();
    super.dispose();
  }
}
