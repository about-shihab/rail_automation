import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/booking_activity.dart';
import '../services/booking_service.dart';
import '../services/credit_service.dart';
import '../services/language_service.dart';
import '../services/monitor_service.dart';
import '../models/auth_session.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import '../services/intermediate_station_search.dart';
import '../services/login_flow.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';
import '../utils/railway_stations.dart';
import '../widgets/scenic_rail_header.dart';
import 'app_shell.dart';
import 'booking_screen.dart';
import 'recharge_credit_dialog.dart';
import 'reservation_screen.dart';
import 'seat_booking_screen.dart';

/// Redesigned Monitor Dashboard Screen.
/// Compact, fancy, intuitive and responsive across all device sizes.
class MonitorDashboardScreen extends StatefulWidget {
  const MonitorDashboardScreen({super.key});

  @override
  State<MonitorDashboardScreen> createState() => _MonitorDashboardScreenState();
}

class _MonitorDashboardScreenState extends State<MonitorDashboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _refreshTimer;
  Map<String, dynamic>? _reservation;
  bool _reading = false;
  bool _openingReservation = false;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CreditService().addListener(_onStateChanged);
    BookingActivity.instance.addListener(_onStateChanged);

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!isTest) {
      _pulseCtrl.repeat(reverse: true);
    }

    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CreditService().removeListener(_onStateChanged);
    BookingActivity.instance.removeListener(_onStateChanged);
    _refreshTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final value = await BookingService.pending();
      if (!mounted) return;

      if (value != null) {
        final started = DateTime.tryParse('${value['startedAt'] ?? ''}');
        final expiry = DateTime.tryParse('${value['expiresAt'] ?? ''}');
        final now = DateTime.now();
        final isReady = value['status'] == 'readyForPayment';

        final is5MinElapsed = isReady
            ? (expiry != null && !now.isBefore(expiry))
            : ((started != null && now.difference(started).inMinutes >= 5) ||
                (expiry != null && !now.isBefore(expiry)));

        if (is5MinElapsed) {
          await BookingService.clear();
          if (mounted) {
            context.read<MonitorService>().markReservationExpired();
            setState(() => _reservation = null);
          }
          return;
        }

        final m = context.read<MonitorService>();
        if (!m.lastReservationExpired &&
            m.bookingFailureReason == null &&
            value['status'] == 'awaitingOtp' &&
            !ReservationScreen.isActive &&
            !_openingReservation &&
            mounted) {
          final elapsedSeconds =
              started != null ? now.difference(started).inSeconds : 0;
          if (value['autoVerify'] != true || elapsedSeconds >= 20) {
            _openingReservation = true;
            Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(builder: (_) => const ReservationScreen()))
                .then((_) {
              _openingReservation = false;
              _refresh();
            });
          }
        }
      } else if (_reservation != null) {
        // Expired or cleared externally
        if (mounted) {
          context.read<MonitorService>().markReservationExpired();
        }
      }

      if (mounted) {
        setState(() => _reservation = value);
      }
    } catch (_) {
      // Keep resilient
    } finally {
      _reading = false;
    }
  }

  Future<void> _handleStopAndClear() async {
    final m = context.read<MonitorService>();
    await BookingService.clear();
    await m.clearSearch();
    if (mounted) {
      setState(() => _reservation = null);
    }
  }

  Future<void> _handlePayNow() async {
    HapticFeedback.mediumImpact();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingScreen(url: BookingService.tripInfoUrl),
      ),
    );
    await _refresh();
  }

  Future<void> _handleBookViaLeg({
    required IntermediateJourney journey,
    required bool isFirstLeg,
    required String fromCity,
    required String toCity,
  }) async {
    HapticFeedback.lightImpact();
    final baseTrain = isFirstLeg ? journey.first : journey.second;
    final legSeat = isFirstLeg ? journey.firstSeat : journey.secondSeat;
    final legFrom = isFirstLeg ? canonicalStation(fromCity) : journey.canonicalVia;
    final legTo = isFirstLeg ? journey.canonicalVia : canonicalStation(toCity);
    final legDate = isFirstLeg ? journey.firstDate : journey.secondDate;

    // Single-ticket TrainTrip instance: prevents parallel multi-ticket requests and server hang
    final legTrain = TrainTrip(
      tripNumber: baseTrain.tripNumber,
      departureDateTime: baseTrain.departureDateTime,
      departureFullDate: baseTrain.departureFullDate,
      departureDateTimeJd: baseTrain.departureDateTimeJd,
      arrivalDateTime: baseTrain.arrivalDateTime,
      travelTime: baseTrain.travelTime,
      originCityName: legFrom,
      destinationCityName: legTo,
      trainModel: baseTrain.trainModel,
      isOpenForAll: baseTrain.isOpenForAll,
      seatTypes: [legSeat],
      boardingPoints: baseTrain.boardingPoints,
    );

    var auth = await AuthSession.load();
    if (auth == null || !auth.isValid) {
      final ok = await LoginFlow.openManualLogin();
      if (!ok) return;
      auth = await AuthSession.load();
      if (auth == null || !auth.isValid) return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatBookingScreen(
          train: legTrain,
          seatType: legSeat,
          fromCity: legFrom,
          toCity: legTo,
          dateOfJourney: legDate,
          authSession: auth!,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MonitorService>();
    CreditService? creditProvider;
    try {
      creditProvider = Provider.of<CreditService>(context, listen: true);
    } catch (_) {}
    final credits = creditProvider?.credits ?? CreditService().credits;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final p = _reservation;
    final expiry = DateTime.tryParse('${p?['expiresAt'] ?? ''}');
    final isExpired = expiry != null && !expiry.isAfter(DateTime.now());
    final hasReservation = p != null && !isExpired;

    final isReservationExpired = (p != null && isExpired) ||
        (!m.isMonitoring &&
            (m.lastReservationExpired ||
                (m.bookingFailureReason != null &&
                    m.bookingFailureReason!.isNotEmpty)));

    final hasActiveMonitor = m.isMonitoring || m.dateOfJourney.isNotEmpty;
    final isZeroCredits = credits <= 0 && !hasReservation;

    // Effective route strings (from monitor or reservation)
    final fromCity = (p?['from']?.toString().isNotEmpty == true)
        ? p!['from'].toString()
        : (m.fromCity.isNotEmpty ? m.fromCity : 'Dhaka');
    final toCity = (p?['to']?.toString().isNotEmpty == true)
        ? p!['to'].toString()
        : (m.toCity.isNotEmpty ? m.toCity : 'Chattogram');
    final dateOfJourney = (p?['date']?.toString().isNotEmpty == true)
        ? p!['date'].toString()
        : m.dateOfJourney;
    final trainName = (p?['train']?['trip_number']?.toString().isNotEmpty == true)
        ? p!['train']['trip_number'].toString()
        : (m.targetTrains.isNotEmpty ? m.targetTrains.join(', ') : 'Train');

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: _ScenicMonitorAppBar(
        credits: credits,
        isMonitoring: m.isMonitoring,
        isScheduled: m.isScheduled,
        isDark: isDark,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Reservation Expired Card
              if (isReservationExpired) ...[
                _ReservationExpiredCard(
                  fromCity: fromCity,
                  toCity: toCity,
                  trainName: trainName,
                  seatClass: m.targetSeatClass,
                  dateOfJourney: dateOfJourney,
                  reason: m.bookingFailureReason,
                  isOtpFailure: p?['status'] == 'awaitingOtp',
                  isPaymentFailure: p?['status'] == 'readyForPayment',
                  isDark: isDark,
                  pulseCtrl: _pulseCtrl,
                  onRetrySearch: () => AppShell.goTo(context, AppShell.tabSearch),
                  onReAutoBook: () async => await m.reAutoBook(),
                  onClear: _handleStopAndClear,
                  onDismiss: () => m.dismissBookingFailure(),
                ),
                const SizedBox(height: 12),
              ]
              // 2. Ticket Processing / Reserved Payment Step Card (Never blank)
              else if (hasReservation) ...[
                _TicketProcessingStepCard(
                  reservation: p,
                  isDark: isDark,
                  pulseCtrl: _pulseCtrl,
                  onPayNow: _handlePayNow,
                  onClear: () async {
                    await BookingService.clear();
                    await _refresh();
                  },
                ),
                const SizedBox(height: 12),
              ]
              // 3. Cockpit Search / Monitor Active HUD
              else if (hasActiveMonitor) ...[
                _CockpitMonitorHud(
                  m: m,
                  fromCity: fromCity,
                  toCity: toCity,
                  isDark: isDark,
                  pulseCtrl: _pulseCtrl,
                  onStop: () => m.stopMonitoring(),
                  onClear: _handleStopAndClear,
                ),
                // ── In-Between / Via Station Discovered Tickets ──
                if (m.recentViaJourneys.isNotEmpty || m.viaJourneys.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ViaTicketsMonitorCard(
                    viaJourneys: m.recentViaJourneys.isNotEmpty
                        ? m.recentViaJourneys
                        : m.viaJourneys,
                    fromCity: fromCity,
                    toCity: toCity,
                    dateOfJourney: dateOfJourney,
                    isDark: isDark,
                    pulseCtrl: _pulseCtrl,
                    onBookLeg: (journey, isFirstLeg) => _handleBookViaLeg(
                      journey: journey,
                      isFirstLeg: isFirstLeg,
                      fromCity: fromCity,
                      toCity: toCity,
                    ),
                  ),
                ],
                if (isZeroCredits) ...[
                  const SizedBox(height: 12),
                  _ZeroCreditBanner(
                    isDark: isDark,
                    onBuy: () => RechargeCreditDialog.show(context),
                  ),
                ],
                const SizedBox(height: 12),
              ]
              // 4. Zero Credits Warning Banner (when idle/empty)
              else if (isZeroCredits) ...[
                _ZeroCreditBanner(
                  isDark: isDark,
                  onBuy: () => RechargeCreditDialog.show(context),
                ),
              ]
              // 5. Empty State
              else ...[
                _EmptyMonitorView(isDark: isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scenic App Bar ────────────────────────────────────────────────────────────
class _ScenicMonitorAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int credits;
  final bool isMonitoring;
  final bool isScheduled;
  final bool isDark;

  const _ScenicMonitorAppBar({
    required this.credits,
    required this.isMonitoring,
    this.isScheduled = false,
    required this.isDark,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    return ScenicRailHeader(
      compact: true,
      sceneOpacity: 0.85,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              const AppBrandIcon(size: 34),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rail Pro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Credits Pill (Amber 0 • Buy when zero)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => RechargeCreditDialog.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: credits <= 0
                        ? const Color(0xFFF59E0B)
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: credits <= 0
                          ? const Color(0xFFD97706)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        credits <= 0
                            ? Icons.monetization_on_rounded
                            : Icons.stars_rounded,
                        size: 14,
                        color: credits <= 0 ? Colors.black87 : AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        credits <= 0
                            ? '0 • Buy'
                            : '$credits ${lang.tr("Credits", "ক্রেডিট")}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: credits <= 0 ? Colors.black87 : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Zero Credit Banner ────────────────────────────────────────────────────────
class _ZeroCreditBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback onBuy;

  const _ZeroCreditBanner({
    required this.isDark,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF291804) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Add credits to continue',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: onBuy,
              child: const Text(
                'Buy Credit',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ticket Processing / Reserved Step Card ────────────────────────────────────
class _TicketProcessingStepCard extends StatelessWidget {
  final Map<String, dynamic> reservation;
  final bool isDark;
  final AnimationController pulseCtrl;
  final VoidCallback onPayNow;
  final VoidCallback onClear;

  const _TicketProcessingStepCard({
    required this.reservation,
    required this.isDark,
    required this.pulseCtrl,
    required this.onPayNow,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final status = reservation['status'] as String? ?? 'readyForPayment';
    final isReady = status == 'readyForPayment';

    final train = reservation['train'] as Map<String, dynamic>?;
    final trainName = train?['trip_number']?.toString() ??
        train?['train_name']?.toString() ??
        'Train';
    final from = canonicalStation('${reservation['from'] ?? ''}');
    final to = canonicalStation('${reservation['to'] ?? ''}');
    final date = '${reservation['date'] ?? ''}';

    final rawSeats = reservation['seats'] as List?;
    final coach = reservation['coach_names']?.toString() ??
        (rawSeats?.firstOrNull is Map
            ? rawSeats!.first['floor_name']?.toString() ?? ''
            : '');
    final seatNumbers = rawSeats != null
        ? rawSeats
            .map((s) => s is Map ? s['seat_number']?.toString() ?? '' : '')
            .where((s) => s.isNotEmpty)
            .join(', ')
        : '';
    final seatClass = rawSeats?.firstOrNull is Map
        ? (rawSeats!.first['selected_seat_class']?.toString() ?? '')
        : (reservation['seatClass'] is Map
            ? reservation['seatClass']['type']?.toString() ?? ''
            : '');

    final totalFare = reservation['total_fare'] != null
        ? double.tryParse('${reservation['total_fare']}') ?? 0.0
        : (rawSeats != null
            ? rawSeats.fold<double>(
                0.0,
                (sum, s) =>
                    sum +
                    (s is Map ? (double.tryParse('${s['fare']}') ?? 0.0) : 0.0),
              )
            : 0.0);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131F1C) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.tr('Ticket Processing Steps', 'টিকেট প্রক্রিয়াকরণ ধাপ'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    Text(
                      isReady
                          ? lang.tr('Seat reserved! Complete payment now.', 'আসন সংরক্ষিত হয়েছে! মূল্য পরিশোধ করুন।')
                          : lang.tr('OTP checking in progress…', 'ওটিপি যাচাই করা হচ্ছে…'),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4-Step Progress Indicator
          _StepIndicator(isReady: isReady, isDark: isDark),
          const SizedBox(height: 14),

          // 5-Minute Countdown Timer Bar
          _PaymentCountdownBar(
            reservation: reservation,
            isDark: isDark,
            onTimeout: onClear,
          ),
          const SizedBox(height: 14),

          // Ticket Details Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        trainName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(isDark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (totalFare > 0)
                      Text(
                        '৳${totalFare.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF10B981),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$from ➔ $to · $date',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (seatClass.isNotEmpty)
                      _InfoBadge(
                        label: seatClass,
                        icon: Icons.airline_seat_recline_extra_rounded,
                        isDark: isDark,
                      ),
                    if (coach.isNotEmpty)
                      _InfoBadge(
                        label: '${lang.tr("Coach", "বগি")}: $coach',
                        icon: Icons.directions_transit_rounded,
                        isDark: isDark,
                      ),
                    if (seatNumbers.isNotEmpty)
                      _InfoBadge(
                        label: '${lang.tr("Seat", "সিট")}: $seatNumbers',
                        icon: Icons.event_seat_rounded,
                        isDark: isDark,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Primary Pay Now Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            onPressed: onPayNow,
            icon: const Icon(Icons.payment_rounded, size: 20),
            label: Text(
              lang.tr('Pay Now', 'পেমেন্ট করুন'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),

          // Clear Record Action
          Center(
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: Text(
                lang.tr('Clear record', 'রেকর্ড মুছুন'),
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted(isDark),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 4-Step Indicator ──────────────────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final bool isReady;
  final bool isDark;

  const _StepIndicator({required this.isReady, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    final steps = [
      lang.tr('Seat Found', 'আসন প্রাপ্ত'),
      lang.tr('Locked', 'সংরক্ষিত'),
      lang.tr('OTP Verified', 'ওটিপি যাচাই'),
      lang.tr('Pay Ticket', 'পেমেন্ট'),
    ];

    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          final completed = isReady || index < 4;
          return Expanded(
            child: Container(
              height: 2,
              color: completed
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
            ),
          );
        }
        final stepIdx = index ~/ 2;
        final completed = (stepIdx < 3) || (stepIdx == 3 && isReady);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: completed
                    ? const Color(0xFF10B981)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              child: Center(
                child: Icon(
                  completed ? Icons.check_rounded : Icons.circle,
                  size: completed ? 14 : 6,
                  color: completed ? Colors.white : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              steps[stepIdx],
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: completed ? FontWeight.bold : FontWeight.normal,
                color: completed
                    ? (isDark ? Colors.white : Colors.black87)
                    : AppColors.textMuted(isDark),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─── 5-Min Countdown Timer Bar ─────────────────────────────────────────────────
class _PaymentCountdownBar extends StatefulWidget {
  final Map<String, dynamic> reservation;
  final bool isDark;
  final VoidCallback onTimeout;

  const _PaymentCountdownBar({
    required this.reservation,
    required this.isDark,
    required this.onTimeout,
  });

  @override
  State<_PaymentCountdownBar> createState() => _PaymentCountdownBarState();
}

class _PaymentCountdownBarState extends State<_PaymentCountdownBar> {
  Timer? _timer;
  int _secondsLeft = 300;

  @override
  void initState() {
    super.initState();
    _calcRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calcRemaining());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _calcRemaining() {
    final expiry = DateTime.tryParse('${widget.reservation['expiresAt'] ?? ''}');
    if (expiry != null) {
      final diff = expiry.difference(DateTime.now()).inSeconds;
      if (diff <= 0) {
        _timer?.cancel();
        if (mounted) {
          setState(() => _secondsLeft = 0);
          widget.onTimeout();
        }
        return;
      }
      if (mounted && diff != _secondsLeft) {
        setState(() => _secondsLeft = diff);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    final progress = (_secondsLeft / 300).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 4),
                Text(
                  lang.tr('5-Minute Time Limit Reached', '৫ মিনিটের সময়সীমা সমাপ্ত'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted(widget.isDark),
                  ),
                ),
              ],
            ),
            Text(
              '$m:$s',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: widget.isDark
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
          ),
        ),
      ],
    );
  }
}

// ─── Cockpit Monitor Active HUD Card ───────────────────────────────────────────
class _CockpitMonitorHud extends StatelessWidget {
  final MonitorService m;
  final String fromCity;
  final String toCity;
  final bool isDark;
  final AnimationController pulseCtrl;
  final VoidCallback onStop;
  final VoidCallback onClear;

  const _CockpitMonitorHud({
    required this.m,
    required this.fromCity,
    required this.toCity,
    required this.isDark,
    required this.pulseCtrl,
    required this.onStop,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final trainsList = m.targetTrains.join(', ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route Header with distinct fromCity and toCity Text widgets
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.tr('DEPARTURE', 'প্রস্থান'),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted(isDark),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fromCity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.east_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      lang.tr('ARRIVAL', 'গন্তব্য'),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted(isDark),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toCity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Sub-bar with Date & Status
          Row(
            children: [
              Expanded(
                child: Text(
                  '${m.dateOfJourney} • ${m.targetSeatClass?.isNotEmpty == true ? m.targetSeatClass! : "ALL"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary(isDark),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: m.isScheduled
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                      : m.isMonitoring
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.isScheduled
                            ? const Color(0xFF3B82F6)
                            : m.isMonitoring
                                ? const Color(0xFF10B981)
                                : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      m.isScheduled
                          ? lang.tr('SCHEDULED', 'নির্ধারিত')
                          : m.isMonitoring
                              ? lang.tr('ACTIVE', 'সক্রিয়')
                              : lang.tr('IDLE', 'স্থগিত'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: m.isScheduled
                            ? const Color(0xFF3B82F6)
                            : m.isMonitoring
                                ? const Color(0xFF10B981)
                                : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Scheduled Notice Banner
          if (m.isScheduled) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        lang.tr('Search scheduled', 'অনুসন্ধান নির্ধারিত'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                  if (m.scheduledStartLabel?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      lang.tr(
                        'Starts ${m.scheduledStartLabel} (Bangladesh time) · 10 days before your journey',
                        'শুরু: ${m.scheduledStartLabel} (বাংলাদেশ সময়) · যাত্রার ১০ দিন আগে',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Selected Target Trains
          if (trainsList.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2832) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.directions_railway_filled_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trainsList,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(isDark),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Controls Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                  ),
                  onPressed: onStop,
                  icon: Icon(
                    m.isMonitoring ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 16,
                  ),
                  label: Text(
                    m.isMonitoring
                        ? lang.tr('Pause', 'স্থগিত')
                        : lang.tr('Resume', 'চালু করুন'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                    ),
                  ),
                  onPressed: onClear,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: Text(
                    lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Reservation Expired Card ──────────────────────────────────────────────────
class _ReservationExpiredCard extends StatelessWidget {
  final String? fromCity;
  final String? toCity;
  final String? trainName;
  final String? seatClass;
  final String? dateOfJourney;
  final String? reason;
  final bool isOtpFailure;
  final bool isPaymentFailure;
  final bool isDark;
  final AnimationController? pulseCtrl;
  final VoidCallback? onRetrySearch;
  final VoidCallback? onReAutoBook;
  final VoidCallback? onClear;
  final VoidCallback onDismiss;

  const _ReservationExpiredCard({
    this.fromCity,
    this.toCity,
    this.trainName,
    this.seatClass,
    this.dateOfJourney,
    this.reason,
    this.isOtpFailure = false,
    this.isPaymentFailure = false,
    required this.isDark,
    this.pulseCtrl,
    this.onRetrySearch,
    this.onReAutoBook,
    this.onClear,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    final headline = isOtpFailure
        ? lang.tr(
            'Hold Expired — OTP Not Verified',
            'সময় শেষ — ওটিপি যাচাই হয়নি',
          )
        : (isPaymentFailure
            ? lang.tr(
                'Hold Expired — Payment Timed Out',
                'সময় শেষ — পেমেন্টের সময় শেষ',
              )
            : lang.tr(
                'Seat Hold Expired — Seats Released',
                'আসন সংরক্ষণের মেয়াদ শেষ — আসন মুক্ত',
              ));

    final isStandardReason = reason == null ||
        reason!.isEmpty ||
        reason!.contains('Seats were reserved') ||
        reason!.contains('5 minutes') ||
        reason!.contains('held seats') ||
        reason!.contains('Held seats') ||
        reason!.contains('timed out') ||
        reason!.contains('সমাপ্ত') ||
        reason!.contains('সময়সীমা') ||
        reason!.contains('আসন মুক্ত') ||
        reason!.contains('release');

    final details = isStandardReason
        ? lang.tr(
            'Seats were reserved, but OTP was not verified or payment was not completed within 5 minutes. Held seats were released by Bangladesh Railway.',
            'রেলওয়ে সিস্টেমে আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই বা পেমেন্ট সম্পন্ন না হওয়ায় বাংলাদেশ রেলওয়ে আসনটি ছেড়ে দিয়েছে।',
          )
        : friendlyErrorMessage(reason, isBangla: lang.isBangla);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E0E13) : const Color(0xFFFFF1F3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${fromCity ?? "Origin"} ➔ ${toCity ?? "Destination"}${dateOfJourney != null ? " · $dateOfJourney" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: onDismiss,
                child: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                lang.tr('5-Minute Time Limit Reached', '৫ মিনিটের সময়সীমা সমাপ্ত'),
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB91C1C),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            details,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted(isDark),
            ),
          ),
          const SizedBox(height: 14),

          // Primary Retry Search Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: onRetrySearch,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              lang.tr('Retry New Search', 'নতুন অনুসন্ধান করুন'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),

          // Action row: Re-Auto Book & Stop & Clear
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onPressed: onReAutoBook,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: Text(
                    lang.tr('Re-Auto Book', 'পুনরায় অটো-বুক'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    side: BorderSide(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                    ),
                  ),
                  onPressed: onClear,
                  icon: const Icon(Icons.stop_rounded, size: 15),
                  label: Text(
                    lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty Monitor View ────────────────────────────────────────────────────────
class _EmptyMonitorView extends StatelessWidget {
  final bool isDark;

  const _EmptyMonitorView({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.radar_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            lang.tr('No Active Monitor', 'কোনো সক্রিয় মনিটর নেই'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            lang.tr(
              'Search for train tickets and tap Auto-book or Watch to monitor available seats automatically in real time.',
              'ট্রেন সার্চ করে অটো-বুক বা নজরদারি বাটনে চাপুন, খালি সিট পাওয়া মাত্র স্বয়ংক্রিয়ভাবে জানিয়ে দেওয়া হবে।',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted(isDark),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: () => AppShell.goTo(context, AppShell.tabSearch),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              lang.tr('Search Trains', 'ট্রেন অনুসন্ধান'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Compact Info Badge Helper ─────────────────────────────────────────────────
class _InfoBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;

  const _InfoBadge({
    required this.label,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── In-Between / Via Tickets Monitor Card ─────────────────────────────────────
class _ViaTicketsMonitorCard extends StatelessWidget {
  final List<IntermediateJourney> viaJourneys;
  final String fromCity;
  final String toCity;
  final String dateOfJourney;
  final bool isDark;
  final AnimationController pulseCtrl;
  final void Function(IntermediateJourney journey, bool isFirstLeg) onBookLeg;

  const _ViaTicketsMonitorCard({
    required this.viaJourneys,
    required this.fromCity,
    required this.toCity,
    required this.dateOfJourney,
    required this.isDark,
    required this.pulseCtrl,
    required this.onBookLeg,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final topJourneys = viaJourneys.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1E18) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (_, child) => Transform.scale(
                  scale: 0.94 + 0.08 * pulseCtrl.value,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.alt_route_rounded,
                      color: Color(0xFF10B981),
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.tr(
                        'Alternative Via Route Found',
                        'বিকল্প ভায়া রুট পাওয়া গেছে',
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      lang.tr(
                        'Book single ticket for each leg (up to 4 seats)',
                        'প্রতিটি অংশের জন্য পৃথক একক টিকিট বুক করুন (সর্বোচ্চ ৪ সিট)',
                      ),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Discovered Via Route Items
          ...topJourneys.map((j) => _buildViaRouteGroup(context, j, lang)),
        ],
      ),
    );
  }

  Widget _buildViaRouteGroup(
    BuildContext context,
    IntermediateJourney journey,
    LanguageService lang,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14241E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Transfer headline
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${lang.tr("Via", "ভায়া")} ${journey.via}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${journey.seats} ${lang.tr("seats available", "আসন খালি")}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Two Single Tickets
          _buildLegTicketCard(
            context: context,
            legNumber: 1,
            from: fromCity,
            to: journey.via,
            trainNumber: journey.first.tripNumber,
            seat: journey.firstSeat,
            date: journey.firstDate,
            onBook: () => onBookLeg(journey, true),
            lang: lang,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const SizedBox(width: 20),
                Icon(
                  Icons.south_rounded,
                  size: 13,
                  color: AppColors.textMuted(isDark),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    journey.layoverText(isBangla: lang.isBangla),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildLegTicketCard(
            context: context,
            legNumber: 2,
            from: journey.via,
            to: toCity,
            trainNumber: journey.second.tripNumber,
            seat: journey.secondSeat,
            date: journey.secondDate,
            onBook: () => onBookLeg(journey, false),
            lang: lang,
          ),
        ],
      ),
    );
  }

  Widget _buildLegTicketCard({
    required BuildContext context,
    required int legNumber,
    required String from,
    required String to,
    required String trainNumber,
    required SeatType seat,
    required String date,
    required VoidCallback onBook,
    required LanguageService lang,
  }) {
    final fareNum = double.tryParse(seat.fare) ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D2E28) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${lang.tr("Leg", "অংশ")} $legNumber',
              style: const TextStyle(
                color: Color(0xFF10B981),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$from ➔ $to',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$trainNumber · ${seat.displayName}: ${seat.seatCounts.online} ${lang.tr("seats", "আসন")}${fareNum > 0 ? " · ৳${fareNum.toStringAsFixed(0)}" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: onBook,
            child: Text(
              '${lang.tr("Book", "বুক")} $legNumber',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
