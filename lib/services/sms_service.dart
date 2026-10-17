import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'app_config.dart';

class SmsService {
  static final SmsService _instance = SmsService._();
  factory SmsService() => _instance;
  SmsService._();
  static const _methods = MethodChannel('com.example.rail_automation/sms');
  static const _events = EventChannel('com.example.rail_automation/sms_stream');
  StreamSubscription<dynamic>? _subscription;
  DateTime? _startedAt;
  Timer? _timeout;
  bool _starting = false;
  Future<bool> requestSmsPermission() async {
    try {
      return await _methods.invokeMethod<bool>('requestSmsPermission') ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      return await _methods.invokeMethod<bool>('hasSmsPermission') ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> promptPendingConsent() async {
    try {
      return await _methods.invokeMethod<bool>('promptPendingConsent') ?? false;
    } catch (_) {
      return false;
    }
  }

  static String? extractOtp(
    String sender,
    String body,
    List<String> allowedSenders,
    int digits,
  ) {
    const bnDigits = {
      '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
      '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
    };
    final normalizedBody = body.split('').map((c) => bnDigits[c] ?? c).join();
    final senderUpper = sender.trim().toUpperCase();
    final bodyUpper = normalizedBody.toUpperCase();

    final matchesSender =
        (senderUpper.isNotEmpty &&
            allowedSenders.any((s) => s.toUpperCase() == senderUpper)) ||
        allowedSenders.any((s) => bodyUpper.contains(s.toUpperCase())) ||
        bodyUpper.contains('RAILWAY') ||
        bodyUpper.contains('SHOHOZ') ||
        bodyUpper.contains('রেলওয়ে') ||
        bodyUpper.contains('রেলওয়ে') ||
        bodyUpper.contains('সহজ') ||
        bodyUpper.contains('ETICKET') ||
        bodyUpper.contains('E-TICKET') ||
        bodyUpper.contains('BDRAIL') ||
        bodyUpper.contains('BD RAIL');

    if (!matchesSender) return null;

    final hasOtpKeyword = RegExp(
      r'otp|verification|verify|code|pin|ওটিপি|যাচাই|কোড|পিন',
      caseSensitive: false,
    ).hasMatch(normalizedBody);

    if (!hasOtpKeyword) return null;

    final nearKeyword = RegExp(
      '(?:otp|verification|verify|code|pin|ওটিপি|যাচাই|কোড|পিন)[^\\d]{0,15}([0-9]{$digits})(?![0-9])',
      caseSensitive: false,
    ).firstMatch(normalizedBody);
    if (nearKeyword != null && nearKeyword.group(1) != null) {
      return nearKeyword.group(1);
    }

    final beforeKeyword = RegExp(
      '(?<![0-9])([0-9]{$digits})[^\\d]{0,15}(?:is your|হলো|হল|is the|otp|code|ওটিপি)',
      caseSensitive: false,
    ).firstMatch(normalizedBody);
    if (beforeKeyword != null && beforeKeyword.group(1) != null) {
      return beforeKeyword.group(1);
    }

    return RegExp('(?<![0-9])([0-9]{$digits})(?![0-9])')
        .firstMatch(normalizedBody)
        ?.group(1);
  }

  Future<void> startListening({
    void Function(String)? onOtpReceived,
    void Function()? onUnavailable,
    bool forceRestart = false,
  }) async {
    if (_starting) return;
    if (_subscription != null) {
      if (!forceRestart) return;
      stopListening();
    }
    _starting = true;
    try {
      if (!await hasPermission()) {
        onUnavailable?.call();
        return;
      }
      _startedAt = DateTime.now();
      final timeoutSec = min(AppConfig.instance.number('otp_window_seconds'), 25);
      _timeout = Timer(
        Duration(seconds: timeoutSec),
        () {
          stopListening();
          onUnavailable?.call();
        },
      );
      _subscription = _events.receiveBroadcastStream().listen(
        (event) {
          if (event is! Map || _startedAt == null) return;
          if (DateTime.now().difference(_startedAt!).inSeconds >
              AppConfig.instance.number('otp_window_seconds')) {
            return;
          }
          final otp = extractOtp(
            '${event['sender']}',
            '${event['body']}',
            AppConfig.instance.strings('sms_senders'),
            AppConfig.instance.number('otp_length'),
          );
          if (otp != null) onOtpReceived?.call(otp);
        },
        onError: (_) {
          stopListening();
          onUnavailable?.call();
        },
      );
    } catch (_) {
      stopListening();
      onUnavailable?.call();
    } finally {
      _starting = false;
    }
  }

  void stopListening() {
    _timeout?.cancel();
    _timeout = null;
    _subscription?.cancel();
    _subscription = null;
    _startedAt = null;
  }
}
