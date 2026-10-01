import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'secure_store.dart';

/// Flutter-side interface for the Android SYSTEM_ALERT_WINDOW overlay.
///
/// Usage:
///   final granted = await OverlayService.requestPermission();
///   if (granted) {
///     final token = await OverlayService.showTurnstile(contextLabel: 'SUBARNA EXPRESS · SNIGDHA');
///   }
class OverlayService {
  static const _channel = MethodChannel('com.example.rail_automation/overlay');

  static bool _isShowing = false;
  static bool get isShowing => _isShowing;

  /// Returns true if the SYSTEM_ALERT_WINDOW permission is already granted.
  static Future<bool> canDrawOverlays() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends the user to Android settings to grant overlay permission.
  /// Returns true if granted after they return.
  static Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the Turnstile challenge as a system-alert-window overlay (works
  /// even when the app is in the background / other apps are in front).
  ///
  /// [contextLabel] is shown as subtitle, e.g. "SUBARNA EXPRESS · SNIGDHA".
  ///
  /// Returns the solved token string, or null if the user cancelled.
  static Future<String?> showTurnstile({String contextLabel = ''}) async {
    if (!_isAndroid) return null;
    if (_isShowing) return null;
    _isShowing = true;
    try {
      final token = await _channel.invokeMethod<String>(
        'showTurnstileOverlay',
        {'contextLabel': contextLabel},
      );
      if (token != null && token.isNotEmpty) {
        await SecureStore.write('rail_cft_token', token);
        await SecureStore.write(
          'rail_cft_token_time',
          DateTime.now().millisecondsSinceEpoch.toString(),
        );
        return token;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _isShowing = false;
    }
  }

  /// Dismisses the overlay without a result (e.g. timeout / navigation).
  static Future<void> dismiss() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('dismissTurnstileOverlay');
    } catch (_) {}
    _isShowing = false;
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
