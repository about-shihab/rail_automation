import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_config.dart';

import '../models/auth_session.dart';
import '../services/api_service.dart';
import '../services/booking_activity.dart';
import '../services/booking_service.dart';
import '../services/credit_service.dart';
import '../services/otp_verifier.dart';
import '../services/sms_service.dart';
import '../services/language_service.dart';
import '../models/trip_record.dart';
import '../services/trip_history_service.dart';
import '../services/notification_service.dart';
import '../services/monitor_service.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';
import 'app_shell.dart';
import 'booking_screen.dart';

class ReservationScreen extends StatefulWidget {
  static int _openScreens = 0;
  static bool get isActive => _openScreens > 0;
  const ReservationScreen({super.key});

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  final _otpCtrl = TextEditingController();
  Map<String, dynamic>? _state;
  Timer? _timer;
  bool _busy = false;
  bool _loadingState = false;
  bool _paymentOpened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ReservationScreen._openScreens++;
    BookingActivity.instance.isReservationActive = true;
    BookingActivity.instance.clearWorkerStage();
    _load();
    OtpVerifier.listen();
    _promptGoogleOtpPermissionIfNeeded();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  Future<void> _promptGoogleOtpPermissionIfNeeded() async {
    final state = await BookingService.pending();
    if (state != null && state['status'] == 'awaitingOtp') {
      if (state['autoVerify'] == true) {
        final hasPermission = await SmsService().requestSmsPermission();
        final hasConsent = await SmsService().promptPendingConsent();
        if (!hasPermission && !hasConsent) {
          state['autoVerify'] = false;
          await BookingService.save(state);
          if (mounted) setState(() => _state = state);
        }
      }
      unawaited(_checkClipboardForOtp());
    }
  }

  Future<void> _checkClipboardForOtp() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty || _otpCtrl.text.isNotEmpty || !mounted || _busy) return;
      final digits = AppConfig.instance.number('otp_length');
      final extracted = SmsService.extractOtp(
        '',
        text,
        AppConfig.instance.strings('sms_senders'),
        digits,
      ) ?? (RegExp('^\\d{$digits}\$').hasMatch(text) ? text : null);

      if (extracted != null && extracted.isNotEmpty && mounted && !_busy) {
        _otpCtrl.text = extracted;
        _verify();
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_loadingState || !mounted) return;
    _loadingState = true;
    try {
      final previousStatus = _state?['status'] as String?;
      final state = await BookingService.pending();
      if (state != null && state['credit_deducted'] != true) {
        state['credit_deducted'] = true;
        await BookingService.save(state);
        final trainName =
            state['train']?['trip_number']?.toString() ??
            state['train']?['train_name']?.toString() ??
            'Train';
        final coach = (state['coach_names'] as String?)?.isNotEmpty == true
            ? (state['coach_names'] as String)
            : (state['coach']?['floor_name']?.toString() ??
                  state['coach']?['seat_floor']?.toString() ??
                  '');
        final seats =
            (state['seats'] as List?)
                ?.map((s) => s['seat_number']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .join(', ') ??
            '';
        final seatInfo = coach.isNotEmpty ? '$coach ($seats)' : seats;
        await CreditService().deductBookingCredit(
          trainName: trainName,
          seatInfo: seatInfo,
        );
      }
      if (mounted) setState(() => _state = state);
      if (state?['status'] == 'readyForPayment') {
        unawaited(_checkPaymentStatus());
      }
      // If OTP was auto-verified in the background, navigate straight to payment
      if (mounted &&
          !_busy &&
          !_paymentOpened &&
          !BookingScreen.isOpen &&
          previousStatus == 'awaitingOtp' &&
          state?['status'] == 'readyForPayment') {
        _paymentOpened = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BookingScreen(url: BookingService.tripInfoUrl),
          ),
        );
      }
    } finally {
      _loadingState = false;
    }
  }

  bool _checkingPayment = false;

  Future<void> _checkPaymentStatus({bool userInitiated = false}) async {
    if (_checkingPayment) return;
    final state = _state;
    if (state == null || state['status'] != 'readyForPayment') return;
    _checkingPayment = true;
    if (userInitiated && mounted) setState(() {});
    try {
      final auth = await AuthSession.load();
      if (auth == null) return;
      final tickets = await ApiService.getPurchaseHistory(
        authSession: auth,
        silent: true,
      );
      final tripId = int.tryParse('${state['seatClass']?['trip_id']}');
      final trainName = state['train']?['trip_number']?.toString() ??
          state['train']?['train_name']?.toString() ?? '';
      final doj = state['date']?.toString() ?? '';

      final confirmed = tickets.where((t) => t.isConfirmed && !t.isRefunded && t.pnr.isNotEmpty).firstWhere(
        (t) {
          if (tripId != null && t.tripId == tripId) return true;
          if (trainName.isNotEmpty &&
              t.trainName.toLowerCase().contains(trainName.toLowerCase())) {
            return true;
          }
          if (doj.isNotEmpty && t.journeyDate.contains(doj)) return true;
          return false;
        },
        orElse: () => tickets.firstWhere(
          (t) => t.isConfirmed && !t.isRefunded && t.pnr.isNotEmpty && tripId != null && t.tripId == tripId,
          orElse: () => tickets.first,
        ),
      );

      final matches = confirmed.isConfirmed &&
          !confirmed.isRefunded &&
          confirmed.pnr.isNotEmpty &&
          ((tripId != null && confirmed.tripId == tripId) ||
              (trainName.isNotEmpty &&
                  confirmed.trainName.toLowerCase().contains(trainName.toLowerCase())));

      if (matches) {
        final done = await BookingService.completeSuccessfulBooking(
          reservation: state,
        );
        if (done) {
          await NotificationService().showPurchaseSuccessAlert(
            trainName: trainName.isNotEmpty ? trainName : confirmed.trainName,
            pnr: confirmed.pnr,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.read<LanguageService>().tr(
                    'Payment confirmed by ticket! PNR: ${confirmed.pnr}',
                    'টিকিট অনুযায়ী পেমেন্ট নিশ্চিত হয়েছে! PNR: ${confirmed.pnr}',
                  ),
                ),
                backgroundColor: const Color(0xFF009B78),
                behavior: SnackBarBehavior.floating,
              ),
            );
            await _load();
          }
        }
      } else if (userInitiated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LanguageService>().tr(
                'Payment not confirmed yet. Please complete payment or check again in a moment.',
                'পেমেন্ট এখনো নিশ্চিত হয়নি। পেমেন্ট সম্পন্ন করে কিছুক্ষণ পর আবার চেষ্টা করুন।',
              ),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
    } finally {
      _checkingPayment = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _verify({bool resend = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = await AuthSession.load();
      if (auth == null) throw StateError('Please log in again.');
      if (resend) {
        final current = await BookingService.pending();
        if (current != null) {
          current['autoVerify'] = true;
          await BookingService.save(current);
          if (mounted) setState(() => _state = current);
        }
        await OtpVerifier.listen(force: true);
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
        final state = await BookingService.verifyOtp(
          _otpCtrl.text.trim(),
          auth,
        );
        await NotificationService().showReservation(state);
        if (mounted && !_paymentOpened) {
          _paymentOpened = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BookingScreen(url: BookingService.tripInfoUrl),
            ),
          );
          return;
        }
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
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
        content: const Text(
          'First check payment or release held seats on the official site. Clearing does not cancel a Railway reservation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
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
    ReservationScreen._openScreens--;
    BookingActivity.instance.isReservationActive = ReservationScreen.isActive;
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = context.watch<LanguageService>();
    final state = _state;
    final expiry = DateTime.tryParse(state?['expiresAt'] ?? '');
    final secondsLeft = expiry?.difference(DateTime.now()).inSeconds;
    final expired = secondsLeft != null && secondsLeft <= 0;
    final ready = state?['status'] == 'readyForPayment';
    final awaitingOtp = state?['status'] == 'awaitingOtp';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: GradientAppBar(
        title: lang.tr('Reservation', 'সংরক্ষণ'),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: state == null
          ? _buildEmptyState(isDark, lang)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Status Banner ────────────────────────────────────────
                _buildStatusBanner(
                  state,
                  ready,
                  expired,
                  awaitingOtp,
                  isDark,
                  lang,
                ),
                const SizedBox(height: 16),

                // ── Timer ────────────────────────────────────────────────
                if (secondsLeft != null && !expired)
                  _buildTimer(secondsLeft, isDark, lang),
                if (secondsLeft != null && !expired) const SizedBox(height: 16),

                // ── Booking Details ──────────────────────────────────────
                _buildDetailsCard(state, isDark),
                const SizedBox(height: 16),

                // ── OTP Section ──────────────────────────────────────────
                if (awaitingOtp && !expired) ...[
                  _buildOtpSection(isDark, lang),
                  const SizedBox(height: 16),
                ],

                // ── Error ────────────────────────────────────────────────
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Hold Expired Alert Banner ────────────────────────────
                if (expired) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF260D12) : const Color(0xFFFFF0F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.timer_off_rounded,
                          color: Color(0xFFEF4444),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            awaitingOtp
                                ? lang.tr(
                                    'The 5-minute hold timed out before OTP was verified. Held seats have been released by Bangladesh Railway.',
                                    '৫ মিনিটের সময়সীমা পার হওয়ায় ওটিপি যাচাই করা সম্ভব হয়নি। আসনটি রেলওয়ে সিস্টেম মুক্ত করে দিয়েছে।',
                                  )
                                : lang.tr(
                                    'The 5-minute payment hold timed out. Held seats were released back to public availability.',
                                    '৫ মিনিটের পেমেন্ট সময় শেষ হয়ে গেছে। আসনটি পুনরায় সাধারণের জন্য উন্মুক্ত করা হয়েছে।',
                                  ),
                            style: TextStyle(
                              color: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB91C1C),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Action Buttons ───────────────────────────────────────
                if (expired) ...[
                  PrimaryButton(
                    label: lang.tr('Retry New Search', 'নতুন অনুসন্ধান করুন'),
                    icon: Icons.search_rounded,
                    loading: _busy,
                    onPressed: () {
                      AppShell.goTo(context, AppShell.tabSearch);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF59E0B),
                            side: const BorderSide(color: Color(0xFFF59E0B)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            lang.tr('Re-Auto Book', 'পুনরায় অটো-বুক'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            final monitor = context.read<MonitorService>();
                            final nav = Navigator.of(context);
                            await monitor.reAutoBook();
                            if (!mounted) return;
                            nav.pop();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: Text(
                            lang.tr('Clear record', 'রেকর্ড মুছুন'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _clearBooking,
                        ),
                      ),
                    ],
                  ),
                ] else if (awaitingOtp) ...[
                  PrimaryButton(
                    label: lang.tr(
                      'Verify OTP & Proceed to Payment',
                      'ওটিপি যাচাই ও পেমেন্টে যান',
                    ),
                    icon: Icons.check_circle_rounded,
                    loading: _busy,
                    onPressed: _busy ? null : _verify,
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: Text(
                      lang.tr(
                        'Open Railway Booking Page',
                        'রেলওয়ে বুকিং পেজ খুলুন',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BookingScreen(url: BookingService.tripInfoUrl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(lang.tr('Clear record', 'রেকর্ড মুছুন')),
                      onPressed: _clearBooking,
                    ),
                  ),
                ] else ...[
                  PrimaryButton(
                    label: ready
                        ? lang.tr('Pay Now', 'পেমেন্ট করুন')
                        : lang.tr('Open Booking', 'বুকিং খুলুন'),
                    icon: ready
                        ? Icons.payment_rounded
                        : Icons.open_in_new_rounded,
                    loading: _busy,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BookingScreen(url: BookingService.tripInfoUrl),
                      ),
                    ),
                  ),
                  if (ready) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF009B78),
                        side: const BorderSide(color: Color(0xFF009B78)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: _checkingPayment
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF009B78),
                              ),
                            )
                          : const Icon(Icons.verified_rounded, size: 18),
                      label: Text(
                        lang.tr(
                          'Check Payment Confirmation by Ticket',
                          'টিকিট অনুযায়ী পেমেন্ট নিশ্চিতকরণ যাচাই',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _checkingPayment
                          ? null
                          : () => _checkPaymentStatus(userInitiated: true),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(lang.tr('Clear record', 'রেকর্ড মুছুন')),
                      onPressed: _clearBooking,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark, LanguageService lang) {
    final recentExpired = TripHistoryService().trips.cast<TripRecord?>().firstWhere(
      (t) =>
          t != null &&
          t.status == TripBookingStatus.expired &&
          DateTime.now().difference(t.createdAt).inMinutes < 15,
      orElse: () => null,
    );

    if (recentExpired != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_off_rounded,
                  size: 48,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                lang.tr(
                  'Seat Hold Expired — Seats Released',
                  'সময় শেষ — আসন মুক্ত করা হয়েছে',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                lang.tr(
                  'Seats on ${recentExpired.trainName} were reserved, but OTP verification or payment timed out in 5 minutes. Bangladesh Railway has released the held seats.',
                  '${recentExpired.trainName} ট্রেনের আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই বা পেমেন্ট সম্পন্ন না হওয়ায় আসনটি ছেড়ে দেওয়া হয়েছে।',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary(isDark),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: lang.tr('Retry New Search', 'নতুন অনুসন্ধান করুন'),
                icon: Icons.search_rounded,
                onPressed: () => AppShell.goTo(context, AppShell.tabSearch),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF59E0B),
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  lang.tr('Re-Auto Book Seats', 'পুনরায় অটো-বুক করুন'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final monitor = context.read<MonitorService>();
                  final nav = Navigator.of(context);
                  await monitor.reAutoBook();
                  if (!mounted) return;
                  nav.pop();
                },
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 72,
            color: AppColors.textMuted(isDark),
          ),
          const SizedBox(height: 16),
          Text(
            lang.tr('No Pending Reservation', 'কোনো অপেক্ষমান বুকিং নেই'),
            style: TextStyle(
              color: AppColors.textPrimary(isDark),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lang.tr(
              'Book a train ticket to see your reservation here.',
              'এখানে আপনার সংরক্ষণ দেখতে ট্রেনের টিকিট বুক করুন।',
            ),
            style: TextStyle(
              color: AppColors.textSecondary(isDark),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(
    Map<String, dynamic> state,
    bool ready,
    bool expired,
    bool awaitingOtp,
    bool isDark,
    LanguageService lang,
  ) {
    String label;
    Color color;
    IconData icon;

    if (expired) {
      label = awaitingOtp
          ? lang.tr('Hold Expired — OTP Not Verified', 'সময় শেষ — ওটিপি যাচাই হয়নি')
          : (ready
              ? lang.tr('Hold Expired — Payment Timed Out', 'সময় শেষ — পেমেন্টের সময় শেষ')
              : lang.tr('Seat Hold Expired — Seats Released', 'আসন সংরক্ষণের মেয়াদ শেষ — আসন মুক্ত'));
      color = AppColors.error;
      icon = Icons.timer_off_rounded;
    } else if (ready) {
      label = lang.tr(
        'OTP Verified — Ready to Pay',
        'ওটিপি যাচাই সম্পন্ন — পেমেন্ট প্রস্তুত',
      );
      color = AppColors.primary;
      icon = Icons.check_circle_rounded;
    } else if (awaitingOtp) {
      label = lang.tr('Awaiting OTP Verification', 'ওটিপি যাচাইয়ের অপেক্ষায়');
      color = AppColors.warning;
      icon = Icons.sms_rounded;
    } else if (state['status'] == 'needsReview') {
      label = lang.tr(
        'Needs Review — Check Official Site',
        'পুনরীক্ষণ প্রয়োজন — অফিসিয়াল সাইট দেখুন',
      );
      color = AppColors.error;
      icon = Icons.warning_rounded;
    } else {
      label = lang.tr('Reserving Seat...', 'আসন বুকিং চলছে...');
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
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer(int secondsLeft, bool isDark, LanguageService lang) {
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
              Text(
                lang.tr(
                  'Time to Complete Payment',
                  'পেমেন্ট সম্পন্ন করার সময় বাকি',
                ),
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: timerColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
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
    final seats = (state['seats'] as List? ?? [])
        .map((s) => s['seat_number'])
        .join(', ');
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
                child: const Icon(
                  Icons.train_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${state['train']['trip_number']}',
                      style: TextStyle(
                        color: AppColors.textPrimary(isDark),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${state['from']} → ${state['to']} • ${state['date']}',
                      style: TextStyle(
                        color: AppColors.textSecondary(isDark),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(
                label: state['seatClass']['type'],
                color: AppColors.info,
                icon: Icons.airline_seat_recline_extra_rounded,
              ),
              if (seats.isNotEmpty)
                StatusBadge(
                  label: seats,
                  color: AppColors.primary,
                  icon: Icons.event_seat_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _enableGoogleOtpVerifier() async {
    final ok = await SmsService().requestSmsPermission();
    if (ok) {
      final current = await BookingService.pending();
      if (current != null) {
        current['autoVerify'] = true;
        await BookingService.save(current);
        await OtpVerifier.listen();
        await NotificationService().showReservation(current);
        if (mounted) {
          setState(() => _state = current);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.read<LanguageService>().tr(
                  'Google OTP Verifier enabled. Auto-verifying upon SMS arrival.',
                  'গুগল ওটিপি ভেরিফায়ার চালু হয়েছে। এসএমএস এলে যাচাই করা হবে।',
                ),
              ),
              backgroundColor: const Color(0xFF009B78),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Widget _buildOtpSection(bool isDark, LanguageService lang) {
    final isAutoVerify = _state?['autoVerify'] == true;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                lang.tr('OTP Verification', 'ওটিপি যাচাইকরণ'),
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (isAutoVerify)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF009B78).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF009B78), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            lang.tr('Google Auto-Verify', 'গুগল অটো-যাচাই'),
                            style: const TextStyle(
                              color: Color(0xFF009B78),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () async {
                        final current = await BookingService.pending();
                        if (current != null) {
                          current['autoVerify'] = false;
                          await BookingService.save(current);
                          if (mounted) setState(() => _state = current);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          lang.tr('Manual', 'ম্যানুয়াল'),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                InkWell(
                  onTap: _enableGoogleOtpVerifier,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          lang.tr('Allow Google OTP', 'গুগল ওটিপি অনুমতি'),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!isAutoVerify)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang.tr(
                        'Auto OTP verification unavailable. Enter the 6-digit OTP from your SMS manually below.',
                        'স্বয়ংক্রিয় ওটিপি যাচাই সম্ভব নয়। অনুগ্রহ করে এসএমএস দেখে নিচে ৬ সংখ্যার ওটিপি লিখুন।',
                      ),
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              lang.tr(
                'Waiting for Railway OTP SMS... or enter code manually below.',
                'রেলওয়ে ওটিপি এসএমএসের অপেক্ষায়... অথবা নিচে কোড লিখুন।',
              ),
              style: TextStyle(
                color: AppColors.textSecondary(isDark),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 14),
          AutofillGroup(
            child: TextField(
              autofocus: !isAutoVerify,
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              onChanged: (val) {
                final digits = AppConfig.instance.number('otp_length');
                const bnDigits = {
                  '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
                  '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
                };
                final normalized = val.trim().split('').map((c) => bnDigits[c] ?? c).join();
                if (normalized != val) {
                  _otpCtrl.text = normalized;
                  _otpCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: normalized.length),
                  );
                }
                if (normalized.length == digits && !_busy) {
                  _verify();
                }
              },
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              textAlign: TextAlign.center,
              maxLength: 8,
              decoration: InputDecoration(
                hintText: '------',
                hintStyle: TextStyle(
                  color: AppColors.textMuted(isDark),
                  letterSpacing: 8,
                  fontSize: 22,
                ),
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
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: lang.tr('Verify OTP', 'ওটিপি যাচাই করুন'),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
                onPressed: _busy ? null : () => _verify(resend: true),
                child: Text(
                  lang.tr('Resend', 'পুনরায় পাঠান'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
