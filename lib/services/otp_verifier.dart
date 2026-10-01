import 'package:flutter/material.dart';
import '../models/auth_session.dart';
import '../views/booking_screen.dart';
import 'booking_service.dart';
import 'sms_service.dart';
import 'notification_service.dart';

class OtpVerifier {
  static bool _verifying = false;
  static Future<void> listen() async {
    final state = await BookingService.pending();
    if (state?['status'] != 'awaitingOtp' || state?['autoVerify'] != true) return;
    await SmsService().startListening(onOtpReceived: (otp) async {
      if (_verifying) return;
      _verifying = true;
      try {
        final auth = await AuthSession.load();
        if (auth == null || !auth.isValid) return;
        final updated = await BookingService.verifyOtp(otp, auth);
        SmsService().stopListening();
        await NotificationService().showReservation(updated);
        // Auto-navigate to the payment screen now that OTP is verified
        final navigator = NotificationService.navigatorKey.currentState;
        if (navigator != null && navigator.mounted) {
          navigator.pushReplacement(
            MaterialPageRoute(
              builder: (_) => BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
        }
      } catch (_) {
        // Keep manual verification available; do not log the code or SMS.
      } finally { _verifying = false; }
    });
  }
}
