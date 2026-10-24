import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/credit_transaction.dart';
import 'firebase_user_service.dart';
import 'app_config.dart';

class AdminException implements Exception {
  final String message;
  AdminException(this.message);
  @override
  String toString() => message;
}

/// Lightweight view of a `users/{phone}` document for the admin list.
class AdminUser {
  final String phone;
  final String displayName;
  final String email;
  final int credits;
  final bool isActive;
  final bool isAdmin;
  final bool isBlocked;
  final DateTime? lastActiveAt;

  const AdminUser({
    required this.phone,
    required this.displayName,
    required this.email,
    required this.credits,
    required this.isActive,
    required this.isAdmin,
    required this.isBlocked,
    required this.lastActiveAt,
  });

  factory AdminUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final last = d['lastActiveAt'];
    return AdminUser(
      phone: doc.id,
      displayName: d['displayName']?.toString() ?? '',
      email: d['email']?.toString() ?? '',
      credits: (d['credits'] is num) ? (d['credits'] as num).toInt() : 0,
      isActive: d['isActive'] == true,
      isAdmin:
          d['is_admin'] == true ||
          d['role']?.toString().toLowerCase() == 'admin',
      isBlocked: d['is_blocked'] == true,
      lastActiveAt: last is Timestamp ? last.toDate() : null,
    );
  }
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String target; // 'all' or specific phone
  final String? targetPhone;
  final String? sentBy;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    this.targetPhone,
    this.sentBy,
    this.createdAt,
  });

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['createdAt'];
    return AppNotification(
      id: doc.id,
      title: d['title']?.toString() ?? '',
      body: d['body']?.toString() ?? '',
      target: d['target']?.toString() ?? 'all',
      targetPhone: d['targetPhone']?.toString(),
      sentBy: d['sentBy']?.toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class AdminActivityLog {
  final String id;
  final String phone;
  final String action;
  final String details;
  final DateTime? timestamp;

  const AdminActivityLog({
    required this.id,
    required this.phone,
    required this.action,
    required this.details,
    this.timestamp,
  });

  factory AdminActivityLog.fromMap(
    String id,
    String phone,
    Map<String, dynamic> data,
  ) {
    final rawTs = data['timestamp'];
    DateTime? dt;
    if (rawTs is Timestamp) {
      dt = rawTs.toDate();
    } else if (rawTs is String) {
      dt = DateTime.tryParse(rawTs);
    }
    return AdminActivityLog(
      id: id,
      phone: phone,
      action: data['action']?.toString() ?? 'ACTIVITY',
      details: data['details']?.toString() ?? '',
      timestamp: dt,
    );
  }
}

enum RequestState { pending, approved, rejected }

/// Admin-only operations. Every method re-checks the admin role locally.
///
/// IMPORTANT: this is a client-side check only (see notes on Firestore rules).
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();
  factory AdminService() => instance;

  static const _approvedWords = {
    'approved',
    'success',
    'completed',
    'accept',
    'accepted',
  };
  static const _rejectedWords = {
    'rejected',
    'declined',
    'failed',
    'cancelled',
    'canceled',
  };

  /// Same interpretation of `status` as CreditService uses on the user side.
  static RequestState stateOf(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (_approvedWords.contains(s)) return RequestState.approved;
    if (_rejectedWords.contains(s)) return RequestState.rejected;
    return RequestState.pending;
  }

  bool get isAdmin => FirebaseUserService().isAdmin;

  FirebaseFirestore get _db {
    final fs = FirebaseUserService().firestore;
    if (fs == null) throw AdminException('Firebase is not available');
    return fs;
  }

  String get _adminPhone => FirebaseUserService().currentPhone ?? 'unknown';

  void _requireAdmin() {
    if (!isAdmin) throw AdminException('Admin access required');
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<List<AdminUser>> watchUsers() {
    return _db.collection('users').limit(500).snapshots().map((snap) {
      final list = snap.docs.map(AdminUser.fromDoc).toList();
      list.sort((a, b) {
        final at = a.lastActiveAt, bt = b.lastActiveAt;
        if (at == null && bt == null) return a.phone.compareTo(b.phone);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return list;
    });
  }

  Stream<List<CreditTransaction>> watchRequests() {
    return _db
        .collection('recharge_requests')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final d = doc.data();
            d['id'] = doc.id;
            return CreditTransaction.fromJson(d);
          }).toList(),
        );
  }

  Stream<int> watchPendingCount() {
    return _db
        .collection('recharge_requests')
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map((s) => s.size);
  }

  // ── User Activity Logs ────────────────────────────────────────────────────

  Stream<List<AdminActivityLog>> watchUserLogs(String phone) {
    return _db
        .collection('users')
        .doc(phone)
        .collection('activity_logs')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isNotEmpty) {
        return snap.docs
            .map((d) => AdminActivityLog.fromMap(d.id, phone, d.data()))
            .toList();
      }
      try {
        final userDoc = await _db.collection('users').doc(phone).get();
        final recent = userDoc.data()?['recentActivity'];
        if (recent is List) {
          final list = <AdminActivityLog>[];
          for (var i = 0; i < recent.length; i++) {
            final item = recent[i];
            if (item is Map) {
              list.add(AdminActivityLog.fromMap(
                'recent_$i',
                phone,
                Map<String, dynamic>.from(item),
              ));
            }
          }
          list.sort((a, b) {
            if (a.timestamp == null && b.timestamp == null) return 0;
            if (a.timestamp == null) return 1;
            if (b.timestamp == null) return -1;
            return b.timestamp!.compareTo(a.timestamp!);
          });
          return list;
        }
      } catch (_) {}
      return <AdminActivityLog>[];
    });
  }

  Stream<List<AdminActivityLog>> watchAllActivityLogs() {
    try {
      return _db
          .collectionGroup('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(150)
          .snapshots()
          .map((snap) => snap.docs.map((d) {
                final phone = d.reference.parent.parent?.id ?? '';
                return AdminActivityLog.fromMap(d.id, phone, d.data());
              }).toList())
          .handleError((_) => const <AdminActivityLog>[]);
    } catch (_) {
      return Stream.value(const <AdminActivityLog>[]);
    }
  }

  // ── Credit adjustment ─────────────────────────────────────────────────────

  /// [delta] > 0 adds credits, < 0 removes them. Balance never goes below 0.
  Future<int> adjustCredit({
    required String phone,
    required int delta,
    String? note,
  }) async {
    _requireAdmin();
    if (delta == 0) throw AdminException('Enter an amount greater than 0');

    final userRef = _db.collection('users').doc(phone);
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) throw AdminException('User not found');
      final current = (snap.data()?['credits'] is num)
          ? (snap.data()!['credits'] as num).toInt()
          : 0;
      final next = current + delta;
      if (next < 0) {
        throw AdminException('Balance cannot go below 0 (current: $current)');
      }

      tx.update(userRef, {
        'credits': next,
        'lastCreditAdjustedAt': FieldValue.serverTimestamp(),
      });
      tx.set(_db.collection('credit_adjustments').doc(), {
        'phone': phone,
        'delta': delta,
        'before': current,
        'after': next,
        'note': (note ?? '').trim(),
        'adminPhone': _adminPhone,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(userRef.collection('activity_logs').doc(), {
        'action': delta > 0 ? 'ADMIN_CREDIT_ADDED' : 'ADMIN_CREDIT_REMOVED',
        'details':
            'Admin ${delta > 0 ? 'added' : 'removed'} ${delta.abs()} credit(s). '
            'Balance: $current → $next'
            '${(note ?? '').trim().isEmpty ? '' : ' · ${note!.trim()}'}',
        'timestamp': FieldValue.serverTimestamp(),
      });
      return next;
    });
  }

  // ── Recharge requests ─────────────────────────────────────────────────────

  /// Approves a pending request and credits the user in ONE transaction.
  /// `applied: true` is set at the same time, so the user's device will not
  /// credit the same request a second time.
  Future<void> approveRequest(String requestId) async {
    _requireAdmin();
    final reqRef = _db.collection('recharge_requests').doc(requestId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(reqRef);
      if (!snap.exists) throw AdminException('Request not found');
      final d = snap.data()!;

      if (stateOf(d['status']?.toString()) != RequestState.pending) {
        throw AdminException('This request was already processed');
      }
      if (d['applied'] == true) {
        throw AdminException('Credits were already applied for this request');
      }
      final credits = (d['credits'] is num) ? (d['credits'] as num).toInt() : 0;
      if (credits <= 0) throw AdminException('Request has no credits to add');

      final phone = FirebaseUserService.normalizePhone(d['phone']?.toString());
      if (phone.isEmpty) throw AdminException('Request has no valid phone');
      final userRef = _db.collection('users').doc(phone);

      tx.update(reqRef, {
        'status': 'Approved',
        'applied': true,
        'appliedAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': _adminPhone,
      });
      tx.set(userRef, {
        'credits': FieldValue.increment(credits),
        'lastCreditRechargedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(userRef.collection('activity_logs').doc(), {
        'action': 'RECHARGE_APPROVED',
        'details':
            'Admin approved recharge ${d['trxId'] ?? requestId}: +$credits credits',
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectRequest(String requestId) async {
    _requireAdmin();
    final reqRef = _db.collection('recharge_requests').doc(requestId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(reqRef);
      if (!snap.exists) throw AdminException('Request not found');
      if (stateOf(snap.data()?['status']?.toString()) != RequestState.pending) {
        throw AdminException('This request was already processed');
      }
      tx.update(reqRef, {
        'status': 'Rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': _adminPhone,
      });
    });
  }

  // ── Block / Unblock User ──────────────────────────────────────────────────

  Future<void> toggleBlockUser({
    required String phone,
    required bool block,
    String? reason,
  }) async {
    _requireAdmin();
    final cleanPhone = FirebaseUserService.normalizePhone(phone);
    if (cleanPhone.isEmpty) throw AdminException('Invalid phone number');

    final userRef = _db.collection('users').doc(cleanPhone);
    final userSnap = await userRef.get();
    if (!userSnap.exists) throw AdminException('User not found');

    await userRef.set({
      'is_blocked': block,
      'blockedAt': block ? FieldValue.serverTimestamp() : null,
      'blockedBy': block ? _adminPhone : null,
      'blockedReason': block ? (reason ?? 'Blocked by administrator') : null,
    }, SetOptions(merge: true));

    await userRef.collection('activity_logs').doc().set({
      'action': block ? 'USER_BLOCKED' : 'USER_UNBLOCKED',
      'details': block
          ? 'Admin blocked user. Reason: ${reason ?? 'Not specified'}'
          : 'Admin unblocked user',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Stream<List<AppNotification>> watchNotifications() {
    return _db
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromDoc).toList());
  }

  Future<void> sendNotification({
    required String title,
    required String body,
    required String target, // 'all' or phone number
    String? targetPhone,
  }) async {
    _requireAdmin();
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty) throw AdminException('Title cannot be empty');
    if (cleanBody.isEmpty) throw AdminException('Message body cannot be empty');
    if (utf8.encode(cleanTitle).length > 256 ||
        utf8.encode(cleanBody).length > 2500) {
      throw AdminException(
        'Announcement is too long. Please shorten the title or message.',
      );
    }

    String? normalizedTargetPhone;
    if (target != 'all') {
      normalizedTargetPhone = FirebaseUserService.normalizePhone(
        targetPhone ?? target,
      );
      if (normalizedTargetPhone.isEmpty) {
        throw AdminException('Target phone number is invalid');
      }
    }

    await _db.collection('notifications').add({
      'title': cleanTitle,
      'body': cleanBody,
      'target': target == 'all' ? 'all' : normalizedTargetPhone,
      'targetPhone': target == 'all' ? null : normalizedTargetPhone,
      'sentBy': _adminPhone,
      'delivery': AppConfig.instance.boolean('admin_push_enabled')
          ? 'push'
          : 'firestore',
      'kind': 'admin_announcement',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNotification(String notificationId) async {
    _requireAdmin();
    if (notificationId.isEmpty) return;
    await _db.collection('notifications').doc(notificationId).delete();
  }

  Future<void> clearAllNotifications() async {
    _requireAdmin();
    final snap = await _db.collection('notifications').get();
    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
