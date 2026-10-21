import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';

/// A seat-browser continuation, never an authorization to reserve or pay.
/// Tokens and credentials are deliberately excluded from this saved context.
class SeatLayoutContinuation {
  const SeatLayoutContinuation({
    required this.id,
    required this.train,
    required this.seat,
    required this.from,
    required this.to,
    required this.date,
    required this.account,
    required this.createdAt,
  });

  static const storageKey = 'pending_seat_layout_v1';
  final String id, from, to, date, account;
  final TrainTrip train;
  final SeatType seat;
  final DateTime createdAt;

  static String accountFor(AuthSession auth) =>
      auth.phoneNumber?.isNotEmpty == true ? auth.phoneNumber! : auth.deviceId;

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({
        'id': id,
        'train': train.toJson(),
        'seat': seat.toJson(),
        'from': from,
        'to': to,
        'date': date,
        'account': account,
        'createdAt': createdAt.toUtc().toIso8601String(),
      }),
    );
  }

  static Future<SeatLayoutContinuation?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final started = DateTime.parse(value['createdAt'] as String);
      final age = DateTime.now().difference(started);
      if (age.isNegative || age >= const Duration(minutes: 30)) return null;
      final seat = SeatType.fromJson(
        Map<String, dynamic>.from(value['seat'] as Map),
      );
      if (seat.tripId == null || seat.tripRouteId == null) return null;
      return SeatLayoutContinuation(
        id: value['id'] as String,
        train: TrainTrip.fromJson(
          Map<String, dynamic>.from(value['train'] as Map),
        ),
        seat: seat,
        from: value['from'] as String,
        to: value['to'] as String,
        date: value['date'] as String,
        account: value['account'] as String,
        createdAt: started,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> clear(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(storageKey);
    if (raw == null) return false;
    try {
      if ((jsonDecode(raw) as Map)['id'] != id) return false;
    } catch (_) {
      return false;
    }
    await prefs.remove(storageKey);
    return true;
  }
}
