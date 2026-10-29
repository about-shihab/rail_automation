import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter-side service to check and request Android overlay permission
/// (SYSTEM_ALERT_WINDOW / "Display over other apps").
class OverlayService {
  static const _channel = MethodChannel('com.example.rail_automation/overlay');

  /// Returns true if the SYSTEM_ALERT_WINDOW permission is already granted.
  static Future<bool> canDrawOverlays() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends the user to Android Settings to grant overlay permission.
  /// Returns true if granted after they return.
  static Future<bool> requestPermission() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows a small, visible card over other apps with its own verification
  /// widget. The user solves the check in place. Returns the token, or null if
  /// the overlay is unavailable, closed by the user, or timed out.
  static Future<String?> solveVerification({
    required String siteKey,
    required String title,
    required String message,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (!isAndroid || !await canDrawOverlays()) return null;
    try {
      final token = await _channel
          .invokeMethod<String>('showVerification', {
            'siteKey': siteKey,
            'title': title,
            'message': message,
          })
          .timeout(
            timeout,
            onTimeout: () {
              unawaited(hideVerification());
              return null;
            },
          );
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// Removes the verification card, if shown.
  static Future<void> hideVerification() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('hideVerification');
    } catch (_) {}
  }

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
