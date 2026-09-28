import 'dart:async';
import 'package:flutter/material.dart';
import '../models/auth_session.dart';
import '../services/booking_service.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';
import 'booking_screen.dart';

class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key});

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  final _otpCtrl = TextEditingController();
  Map<String, dynamic>? _state;
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  Future<void> _load() async {
    final state = await BookingService.pending();
    if (mounted) setState(() => _state = state);
  }

  Future<void> _verify({bool resend = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final auth = await AuthSession.load();
      if (auth == null) throw StateError('Please log in again.');
      if (resend) {
        await BookingService.resendOtp(auth);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OTP resent successfully'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final state = await BookingService.verifyOtp(_otpCtrl.text.trim(), auth);
        await NotificationService().showReservation(state);
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Clear Booking Record?'),
        content: const Text('First check payment or release held seats on the official site. Clearing does not cancel a Railway reservation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await BookingService.clear();
      await NotificationService().clearAlerts();
      await _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = _state;
    final expiry = DateTime.tryParse(state?['expiresAt'] ?? '');
    final secondsLeft = expiry?.difference(DateTime.now()).inSeconds;
    final expired = secondsLeft != null && secondsLeft <= 0;
    final ready = state?['status'] == 'readyForPayment';
    final awaitingOtp = state?['status'] == 'awaitingOtp';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: GradientAppBar(
        title: 'Reservation',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: state == null
          ? _buildEmptyState(isDark)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Status Banner ────────────────────────────────────────
                _buildStatusBanner(state, ready, expired, awaitingOtp, isDark),
                const SizedBox(height: 16),

                // ── Timer ────────────────────────────────────────────────
                if (secondsLeft != null && !expired && !ready)
                  _buildTimer(secondsLeft, isDark),
                if (secondsLeft != null && !expired && !ready)
                  const SizedBox(height: 16),

                // ── Booking Details ──────────────────────────────────────
                _buildDetailsCard(state, isDark),
                const SizedBox(height: 16),

                // ── OTP Section ──────────────────────────────────────────
                if (awaitingOtp && !expired) ...[
                  _buildOtpSection(isDark),
                  const SizedBox(height: 16),
                ],

                // ── Error ────────────────────────────────────────────────
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Action Button ────────────────────────────────────────
                PrimaryButton(
                  label: ready && !expired ? 'Pay Now' : 'Open Booking',
                  icon: ready && !expired ? Icons.payment_rounded : Icons.open_in_new_rounded,
                  loading: _busy,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BookingScreen(url: BookingService.tripInfoUrl)),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Clear Button ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Clear record'),
                    onPressed: _clearBooking,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.confirmation_number_outlined, size: 72, color: AppColors.textMuted(isDark)),
          const SizedBox(height: 16),
          Text('No Pending Reservation', style: TextStyle(
            color: AppColors.textPrimary(isDark), fontSize: 18, fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 8),
          Text('Book a train ticket to see your reservation here.',
            style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(
    Map<String, dynamic> state, bool ready, bool expired, bool awaitingOtp, bool isDark,
  ) {
    String label;
    Color color;
    IconData icon;

    if (expired) {
      label = 'Reservation Expired';
      color = AppColors.error;
      icon = Icons.timer_off_rounded;
    } else if (ready) {
      label = 'OTP Verified — Ready to Pay';
      color = AppColors.primary;
      icon = Icons.check_circle_rounded;
    } else if (awaitingOtp) {
      label = 'Awaiting OTP Verification';
      color = AppColors.warning;
      icon = Icons.sms_rounded;
    } else if (state['status'] == 'needsReview') {
      label = 'Needs Review — Check Official Site';
      color = AppColors.error;
      icon = Icons.warning_rounded;
    } else {
      label = 'Reserving Seat...';
      color = AppColors.info;
      icon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildTimer(int secondsLeft, bool isDark) {
    final mins = secondsLeft ~/ 60;
    final secs = secondsLeft % 60;
    final fraction = (secondsLeft / 600).clamp(0.0, 1.0);
    final timerColor = secondsLeft < 120 ? AppColors.error : AppColors.warning;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.timer_rounded, color: timerColor, size: 18),
              const SizedBox(width: 8),
              Text('Time to Complete Payment', style: TextStyle(
                color: AppColors.textPrimary(isDark), fontWeight: FontWeight.bold, fontSize: 13,
              )),
              const Spacer(),
              Text(
                '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                style: TextStyle(color: timerColor, fontWeight: FontWeight.bold, fontSize: 20, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: timerColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(timerColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(Map<String, dynamic> state, bool isDark) {
    final seats = (state['seats'] as List? ?? []).map((s) => s['seat_number']).join(', ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.train_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${state['train']['trip_number']}', style: TextStyle(
                    color: AppColors.textPrimary(isDark), fontWeight: FontWeight.bold, fontSize: 15,
                  )),
                  Text('${state['from']} → ${state['to']} • ${state['date']}',
                    style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12)),
                ],
              )),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              StatusBadge(label: state['seatClass']['type'], color: AppColors.info, icon: Icons.airline_seat_recline_extra_rounded),
              if (seats.isNotEmpty)
                StatusBadge(label: seats, color: AppColors.primary, icon: Icons.event_seat_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtpSection(bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text('OTP Verification', style: TextStyle(
                color: AppColors.textPrimary(isDark), fontWeight: FontWeight.bold, fontSize: 14,
              )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'If SMS access is enabled, OTPs are verified automatically. You can also enter it below.',
            style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
            textAlign: TextAlign.center,
            maxLength: 8,
            decoration: InputDecoration(
              hintText: '------',
              hintStyle: TextStyle(color: AppColors.textMuted(isDark), letterSpacing: 8, fontSize: 22),
              counterText: '',
              filled: true,
              fillColor: AppColors.inputFill(isDark),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.inputBorder(isDark)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.inputBorder(isDark)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Verify OTP',
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : _verify,
                  height: 46,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(isDark),
                  side: BorderSide(color: AppColors.cardBorder(isDark)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: _busy ? null : () => _verify(resend: true),
                child: const Text('Resend', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
