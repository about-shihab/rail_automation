import 'dart:async';
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
  Future<bool> requestSmsPermission() async {
    try { return await _methods.invokeMethod<bool>('requestSmsPermission') ?? true; }
    catch (_) { return true; }
  }
  Future<bool> hasPermission() async {
    try { return await _methods.invokeMethod<bool>('hasSmsPermission') ?? true; }
    catch (_) { return true; }
  }
  static String? extractOtp(String sender, String body, List<String> allowedSenders, int digits) {
    final senderUpper = sender.trim().toUpperCase();
    final bodyUpper = body.toUpperCase();
    final matchesSender = allowedSenders.any((s) => s.toUpperCase() == senderUpper) ||
        allowedSenders.any((s) => bodyUpper.contains(s.toUpperCase()));
    if (!matchesSender) return null;
    if (!RegExp(r'otp|verification|verify|ওটিপি|যাচাই', caseSensitive: false).hasMatch(body)) return null;
    return RegExp('(?<![0-9])([0-9]{$digits})(?![0-9])').firstMatch(body)?.group(1);
  }
  Future<void> startListening({void Function(String)? onOtpReceived}) async {
    if (_subscription != null || !await hasPermission()) return;
    _startedAt = DateTime.now();
    _subscription = _events.receiveBroadcastStream().listen((event) {
      if (event is! Map || _startedAt == null) return;
      if (DateTime.now().difference(_startedAt!).inSeconds > AppConfig.instance.number('otp_window_seconds')) return;
      final otp = extractOtp('${event['sender']}', '${event['body']}', AppConfig.instance.strings('sms_senders'), AppConfig.instance.number('otp_length'));
      if (otp != null) onOtpReceived?.call(otp);
    }, onError: (_) { stopListening(); });
  }
  void stopListening() { _subscription?.cancel(); _subscription = null; _startedAt = null; }
}
