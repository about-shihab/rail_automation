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

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
