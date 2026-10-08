import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_service.dart';
import 'app_config.dart';
import 'firebase_user_service.dart';

class AdminConfigSnapshot {
  final Map<String, dynamic> workflow;
  final Map<String, dynamic> settings;

  AdminConfigSnapshot(this.workflow, this.settings);

  Map<String, dynamic> get raw => {...workflow, ...settings};
  Map<String, dynamic> get values => AppConfig.validate(raw);
}

/// Edits the document that owns each setting, respecting settings overrides.
class AdminConfigService {
  final AdminService _admin = AdminService();

  void _requireAdmin() {
    if (!_admin.isAdmin) throw AdminException('Admin access required');
  }

  FirebaseFirestore get _db {
    final db = FirebaseUserService().firestore;
    if (db == null) throw AdminException('Firebase is not available');
    return db;
  }

  Future<AdminConfigSnapshot> load() async {
    _requireAdmin();
    return _db.runTransaction((transaction) async {
      final workflow = await transaction.get(
        _db.collection('app_config').doc('workflow'),
      );
      final settings = await transaction.get(
        _db.collection('app_config').doc('settings'),
      );
      return AdminConfigSnapshot(workflow.data() ?? {}, settings.data() ?? {});
    });
  }

  static bool sameValue(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && sameValue(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => sameValue(a[i], b[i]));
    }
    return a == b;
  }

  /// Reject invalid values rather than silently replacing them with defaults.
  static Map<String, dynamic> validateChanges(Map<String, dynamic> changes) {
    final validated = AppConfig.validate(changes);
    for (final entry in changes.entries) {
      if (!validated.containsKey(entry.key) ||
          !sameValue(entry.value, validated[entry.key])) {
        throw AdminException(
          'Invalid ${entry.key}. Check its limits, API URL, headers, or payload. '
          'Sensitive payload values must use {{placeholders}}.',
        );
      }
    }
    return {for (final key in changes.keys) key: validated[key]};
  }

  static void checkConflicts(
    AdminConfigSnapshot before,
    AdminConfigSnapshot current,
    Iterable<String> keys,
  ) {
    for (final key in keys) {
      // Compare raw values so changes of document ownership are also detected.
      if (before.settings.containsKey(key) !=
              current.settings.containsKey(key) ||
          !sameValue(before.raw[key], current.raw[key])) {
        throw AdminException(
          'Configuration changed while you were editing. Reload and try again.',
        );
      }
    }
  }

  Future<void> save(
    AdminConfigSnapshot before,
    Map<String, dynamic> changes,
  ) async {
    _requireAdmin();
    final patch = validateChanges(changes);
    if (patch.isEmpty) return;
    final workflowRef = _db.collection('app_config').doc('workflow');
    final settingsRef = _db.collection('app_config').doc('settings');
    await _db.runTransaction((transaction) async {
      _requireAdmin();
      final workflow = await transaction.get(workflowRef);
      final settings = await transaction.get(settingsRef);
      final current = AdminConfigSnapshot(
        workflow.data() ?? {},
        settings.data() ?? {},
      );
      checkConflicts(before, current, patch.keys);
      final workflowPatch = <String, dynamic>{};
      final settingsPatch = <String, dynamic>{};
      for (final entry in patch.entries) {
        final destination = current.settings.containsKey(entry.key)
            ? settingsPatch
            : workflowPatch;
        destination[entry.key] = entry.value;
      }
      // Explicit top-level merge fields replace edited maps, while preserving
      // unrelated config fields (and allowing removal inside an edited map).
      if (workflowPatch.isNotEmpty) {
        transaction.set(
          workflowRef,
          workflowPatch,
          SetOptions(mergeFields: workflowPatch.keys.toList()),
        );
      }
      if (settingsPatch.isNotEmpty) {
        transaction.set(
          settingsRef,
          settingsPatch,
          SetOptions(mergeFields: settingsPatch.keys.toList()),
        );
      }
    });
    await AppConfig.instance.syncFromFirestore();
  }
}
