import 'dart:async';

import 'package:flutter/foundation.dart';

enum BookingActivityStage { searching, tickets, layout, reserving, verifying }

/// Tracks actual work, including nested calls, without delaying or retrying it.
class BookingActivity extends ChangeNotifier {
  static final instance = BookingActivity();
  final _operations = <Object, BookingActivityStage>{};
  BookingActivityStage? _workerStage;
  bool _notificationPending = false;
  bool _disposed = false;

  void _changed() {
    if (_notificationPending || _disposed) return;
    _notificationPending = true;
    // Requests can start in a descendant screen's initState. Notify after the
    // current build so the app-wide loader never dirties an ancestor mid-build.
    scheduleMicrotask(() {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  bool _reservationActive = false;

  bool get isReservationActive => _reservationActive;
  set isReservationActive(bool value) {
    if (_reservationActive != value) {
      _reservationActive = value;
      if (value) {
        _workerStage = null;
        _operations.removeWhere((_, stage) =>
            stage == BookingActivityStage.reserving ||
            stage == BookingActivityStage.verifying);
      }
      _changed();
    }
  }

  bool get hasForegroundOperations => _operations.isNotEmpty;
  bool get busy => _operations.isNotEmpty || _workerStage != null;
  BookingActivityStage get stage =>
      _operations.isNotEmpty ? _operations.values.last : _workerStage!;

  void setWorkerStage(BookingActivityStage? stage) {
    if (_workerStage == stage) return;
    _workerStage = stage;
    _changed();
  }

  void clearWorkerStage() {
    if (_workerStage != null) {
      _workerStage = null;
      _changed();
    }
  }

  void reset() {
    _operations.clear();
    _workerStage = null;
    _changed();
  }

  Future<T> run<T>(
    BookingActivityStage stage,
    Future<T> Function() work,
  ) async {
    final id = Object();
    _operations[id] = stage;
    _changed();
    try {
      return await work();
    } finally {
      _operations.remove(id);
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
