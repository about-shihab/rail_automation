import 'package:flutter/material.dart';

import '../views/reservation_screen.dart';
import '../views/booking_screen.dart';
import '../models/auth_session.dart';
import 'booking_service.dart';
import 'sms_service.dart';
import 'notification_service.dart';

class OtpVerifier {
  static bool _verifying = false;
  static Future<void> _manualFallback(String id) async {
    final current = await BookingService.pending();
    if (current?['id'] != id || current?['status'] != 'awaitingOtp') {
      return;
    }
    current!['autoVerify'] = false;
    await BookingService.save(current);
    await NotificationService().showReservation(current);

    // Sequence Rule: If auto OTP verification fails or is unavailable, show OTP enter screen immediately!
    if (!ReservationScreen.isActive) {
      final nav = NotificationService.navigatorKey.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(builder: (_) => const ReservationScreen()),
        );
      }
    }
  }

  static Future<void> listen({bool force = false}) async {
    final state = await BookingService.pending();
    if (state?['status'] != 'awaitingOtp' || state?['autoVerify'] != true) {
      return;
    }
    await SmsService().startListening(
      forceRestart: force,
      onUnavailable: () async => _manualFallback('${state!['id']}'),
      onOtpReceived: (otp) async {
        if (_verifying) return;
        _verifying = true;
        try {
          final auth = await AuthSession.load();
          if (auth == null) {
            await _manualFallback('${state!['id']}');
            return;
          }
          final updated = await BookingService.verifyOtp(otp, auth);
          SmsService().stopListening();
          await NotificationService().showReservation(updated);
          // ReservationScreen owns its transition; monitoring can open checkout
          // directly when the UI is foregrounded. Never launch it over other apps.
          if (WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed &&
              !ReservationScreen.isActive &&
              !BookingScreen.isOpen) {
            NotificationService().openBooking(BookingService.tripInfoUrl);
          }
        } catch (_) {
          // Keep manual verification available; do not log the code or SMS.
          SmsService().stopListening();
          await _manualFallback('${state!['id']}');
        } finally {
          _verifying = false;
        }
      },
    );
  }
}
