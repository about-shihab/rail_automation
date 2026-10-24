import 'dart:async';
import 'dart:math' as math;

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

// ─── Design tokens (local to this screen) ──────────────────────────────────────
const _kGreen = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF3B82F6);

Color _surface(bool dark) => dark ? const Color(0xFF131D24) : Colors.white;
Color _surfaceAlt(bool dark) =>
    dark ? const Color(0xFF0F1A1E) : const Color(0xFFF6F8FA);
Color _outline(bool dark) =>
    dark ? Colors.white.withValues(alpha: 0.09) : const Color(0xFFE5E9EE);

BoxDecoration _cardDeco(bool dark, {Color? accent, double radius = 22}) {
  return BoxDecoration(
    color: _surface(dark),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: accent != null ? accent.withValues(alpha: 0.45) : _outline(dark),
      width: accent != null ? 1.4 : 1,
    ),
    boxShadow: [
      BoxShadow(
        color: (accent ?? Colors.black).withValues(alpha: dark ? 0.18 : 0.07),
        blurRadius: 22,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  required String no,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: _kRed),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r == true;
}

/// Redesigned Monitor Dashboard.
/// One clear status at a time, plain-language steps, big actions.
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

  /// One looping 0→1 controller drives radar rings, moving train and glows.
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CreditService().addListener(_onStateChanged);
    BookingActivity.instance.addListener(_onStateChanged);

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (!isTest) {
      _anim.repeat();
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
    _anim.dispose();
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

  Future<void> _confirmStopAndClear() async {
    final lang = LanguageService.of(context);
    final ok = await _confirm(
      context,
      title: lang.tr('Stop searching?', 'অনুসন্ধান বন্ধ করবেন?'),
      body: lang.tr(
        'We will stop looking for your ticket and clear this search.',
        'আপনার টিকেটের অনুসন্ধান বন্ধ হবে এবং এই সার্চ মুছে যাবে।',
      ),
      yes: lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
      no: lang.tr('Keep searching', 'চালিয়ে যান'),
    );
    if (ok && mounted) await _handleStopAndClear();
  }

  Future<void> _confirmClearReservation() async {
    final lang = LanguageService.of(context);
    final ok = await _confirm(
      context,
      title: lang.tr('Clear this reservation?', 'রিজার্ভেশন মুছবেন?'),
      body: lang.tr(
        'Your held seat will be forgotten in the app. You may lose the seat.',
        'অ্যাপ থেকে সংরক্ষিত আসনের রেকর্ড মুছে যাবে। আসনটি হারাতে পারেন।',
      ),
      yes: lang.tr('Clear', 'মুছুন'),
      no: lang.tr('Cancel', 'বাতিল'),
    );
    if (ok && mounted) {
      await BookingService.clear();
      await _refresh();
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
    final legFrom = isFirstLeg ? canonicalStation(fromCity) : canonicalStation(journey.leg2From);
    final legTo = isFirstLeg ? canonicalStation(journey.leg1To) : canonicalStation(toCity);
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

    // Pick the single most important thing to show.
    late final String stateKey;
    late final Widget content;

    if (isReservationExpired) {
      stateKey = 'expired';
      content = _ReservationExpiredCard(
        fromCity: fromCity,
        toCity: toCity,
        trainName: trainName,
        seatClass: m.targetSeatClass,
        dateOfJourney: dateOfJourney,
        reason: m.bookingFailureReason,
        isOtpFailure: p?['status'] == 'awaitingOtp',
        isPaymentFailure: p?['status'] == 'readyForPayment',
        isDark: isDark,
        onRetrySearch: () => AppShell.goTo(context, AppShell.tabSearch),
        onReAutoBook: () async => await m.reAutoBook(),
        onClear: _handleStopAndClear,
        onDismiss: () => m.dismissBookingFailure(),
      );
    } else if (hasReservation) {
      stateKey = 'reservation';
      content = _ReservationCard(
        reservation: p,
        isDark: isDark,
        anim: _anim,
        onPayNow: _handlePayNow,
        onClear: _confirmClearReservation,
        onTimeout: () async {
          await BookingService.clear();
          await _refresh();
        },
      );
    } else if (hasActiveMonitor) {
      stateKey = 'monitor';
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1) Compact status + route (small, so via tickets stay on screen)
          _MonitorSection(
            m: m,
            fromCity: fromCity,
            toCity: toCity,
            isDark: isDark,
            anim: _anim,
            onStop: () => m.pauseMonitoring(),
            onResume: () => m.resumeMonitoring(),
            onClear: _confirmStopAndClear,
          ),
          const SizedBox(height: 14),
          // 2) Via / split tickets – always visible right below
          _ViaSection(
            journeys: m.recentViaJourneys.isNotEmpty
                ? m.recentViaJourneys
                : m.viaJourneys,
            isSearching: m.isSearchingVia,
            fromCity: fromCity,
            toCity: toCity,
            isDark: isDark,
            anim: _anim,
            onBookLeg: (journey, isFirstLeg) => _handleBookViaLeg(
              journey: journey,
              isFirstLeg: isFirstLeg,
              fromCity: fromCity,
              toCity: toCity,
            ),
          ),
          if (isZeroCredits) ...[
            const SizedBox(height: 14),
            _ZeroCreditBanner(
              isDark: isDark,
              onBuy: () => RechargeCreditDialog.show(context),
            ),
          ],
          const SizedBox(height: 14),
          // 3) Explanation of the flow
          _NextStepsCard(m: m, isDark: isDark, anim: _anim),
        ],
      );
    } else if (isZeroCredits) {
      stateKey = 'zero';
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ZeroCreditBanner(
            isDark: isDark,
            onBuy: () => RechargeCreditDialog.show(context),
          ),
          const SizedBox(height: 14),
          _EmptyMonitorView(isDark: isDark, anim: _anim),
        ],
      );
    } else {
      stateKey = 'empty';
      content = _EmptyMonitorView(isDark: isDark, anim: _anim);
    }

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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(stateKey), child: content),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// App bar
// ═══════════════════════════════════════════════════════════════════════════════
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
    final low = credits <= 0;

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
              const Expanded(
                child: Text(
                  'Rail Pro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => RechargeCreditDialog.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: low ? _kAmber : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: low
                          ? const Color(0xFFD97706)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        low ? Icons.add_circle_rounded : Icons.stars_rounded,
                        size: 15,
                        color: low ? Colors.black87 : AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        low
                            ? '0 • Buy'
                            : '$credits ${lang.tr("Credits", "ক্রেডিট")}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: low ? Colors.black87 : Colors.white,
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

// ═══════════════════════════════════════════════════════════════════════════════
// Shared building blocks
// ═══════════════════════════════════════════════════════════════════════════════

/// Animated radar: expanding rings around a centre icon.
class _RadarBeacon extends StatelessWidget {
  final Animation<double> anim;
  final Color color;
  final IconData icon;
  final bool active;
  final double size;

  const _RadarBeacon({
    required this.anim,
    required this.color,
    required this.icon,
    this.active = true,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: anim,
            builder: (context, child) => CustomPaint(
              size: Size.square(size),
              painter: _RadarPainter(anim.value, color, active),
            ),
          ),
          Container(
            width: size * 0.52,
            height: size * 0.52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withValues(alpha: 0.75)],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.28),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool active;

  _RadarPainter(this.t, this.color, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(c, maxR * 0.98, base);
    canvas.drawCircle(c, maxR * 0.72, base);

    if (!active) return;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: (1 - p) * 0.4);
      canvas.drawCircle(c, maxR * (0.3 + 0.7 * p), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.t != t || old.color != color || old.active != active;
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool dot;

  const _StatusChip({required this.text, required this.color, this.dot = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, active, pending }

class _StepData {
  final String label;
  final IconData icon;
  final _StepState state;
  const _StepData(this.label, this.icon, this.state);
}

/// Horizontal step tracker with a glowing active step.
class _ProgressSteps extends StatelessWidget {
  final List<_StepData> steps;
  final bool isDark;
  final Animation<double> anim;
  final Color accent;

  const _ProgressSteps({
    required this.steps,
    required this.isDark,
    required this.anim,
    this.accent = _kGreen,
  });

  @override
  Widget build(BuildContext context) {
    final track = isDark ? const Color(0xFF26333D) : const Color(0xFFE2E8F0);
    return LayoutBuilder(
      builder: (ctx, cons) {
        final n = steps.length;
        final colW = cons.maxWidth / n;
        return Stack(
          children: [
            Positioned(
              left: colW / 2,
              right: colW / 2,
              top: 14,
              child: Row(
                children: List.generate(n - 1, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: steps[i].state == _StepState.done ? accent : track,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Row(
              children: steps.map((s) {
                return Expanded(child: _stepColumn(s, track));
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _stepColumn(_StepData s, Color track) {
    final done = s.state == _StepState.done;
    final active = s.state == _StepState.active;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: anim,
          builder: (context, child) {
            final glow = active ? 0.5 + 0.5 * math.sin(anim.value * 2 * math.pi) : 0.0;
            return Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? accent
                    : (active ? accent.withValues(alpha: 0.16) : track),
                border: active
                    ? Border.all(color: accent, width: 2)
                    : null,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.15 + 0.3 * glow),
                          blurRadius: 6 + 8 * glow,
                          spreadRadius: 1 + 2 * glow,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                done ? Icons.check_rounded : s.icon,
                size: done ? 17 : 15,
                color: done
                    ? Colors.white
                    : (active ? accent : AppColors.textMuted(isDark)),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            s.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: (done || active) ? FontWeight.w800 : FontWeight.w500,
              color: (done || active)
                  ? AppColors.textPrimary(isDark)
                  : AppColors.textMuted(isDark),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, cons) {
        final n = math.max(1, (cons.maxWidth / 9).floor());
        return Row(
          children: List.generate(
            n,
            (_) => Expanded(
              child: Container(
                height: 1.4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ticket-style divider with side cut-outs.
class _TearLine extends StatelessWidget {
  final bool isDark;
  const _TearLine({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.scaffoldBg(isDark);
    return SizedBox(
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: _DashedLine(color: _outline(isDark).withValues(alpha: 1)),
          ),
          Positioned(
            left: -11,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            ),
          ),
          Positioned(
            right: -11,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Departure ───🚆──➔ Arrival with a train moving along the track.
class _RouteTrack extends StatelessWidget {
  final String from;
  final String to;
  final bool isDark;
  final Animation<double> anim;
  final bool moving;
  final Color accent;

  const _RouteTrack({
    required this.from,
    required this.to,
    required this.isDark,
    required this.anim,
    this.moving = true,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: _station(
            lang.tr('FROM', 'থেকে'),
            from,
            CrossAxisAlignment.start,
            Icons.trip_origin_rounded,
            accent,
          ),
        ),
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 34,
            child: LayoutBuilder(
              builder: (_, cons) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Center(child: _DashedLine(color: accent.withValues(alpha: 0.4))),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: anim,
                      builder: (_, child) {
                        final t = moving ? anim.value : 0.5;
                        return Align(
                          alignment: Alignment(t * 1.7 - 0.85, 0),
                          child: child,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_railway_filled_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: _station(
            lang.tr('TO', 'গন্তব্য'),
            to,
            CrossAxisAlignment.end,
            Icons.location_on_rounded,
            _kRed,
          ),
        ),
      ],
    );
  }

  Widget _station(
    String label,
    String city,
    CrossAxisAlignment align,
    IconData icon,
    Color iconColor,
  ) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textMuted(isDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            color: AppColors.textPrimary(isDark),
          ),
        ),
      ],
    );
  }
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _surfaceAlt(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outline(isDark)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1) Active / scheduled / paused search
// ═══════════════════════════════════════════════════════════════════════════════
class _MonitorSection extends StatelessWidget {
  final MonitorService m;
  final String fromCity;
  final String toCity;
  final bool isDark;
  final Animation<double> anim;
  final VoidCallback onStop;
  final VoidCallback onClear;
  final VoidCallback? onResume;

  const _MonitorSection({
    required this.m,
    required this.fromCity,
    required this.toCity,
    required this.isDark,
    required this.anim,
    required this.onStop,
    required this.onClear,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final trainsList = m.targetTrains.join(', ');
    final isLive = m.isMonitoring && !m.isScheduled;

    final color = isLive
        ? AppColors.primary
        : (m.isScheduled ? _kBlue : const Color(0xFF94A3B8));

    final statusText = m.isScheduled
        ? lang.tr('SCHEDULED', 'নির্ধারিত')
        : m.isMonitoring
            ? lang.tr('LIVE', 'চলছে')
            : lang.tr('PAUSED', 'স্থগিত');

    final title = m.isScheduled
        ? lang.tr('Search scheduled', 'অনুসন্ধান নির্ধারিত')
        : m.isMonitoring
            ? lang.tr("We're finding your ticket", 'আমরা আপনার টিকেট খুঁজছি')
            : lang.tr('Search is paused', 'অনুসন্ধান স্থগিত');

    final subtitle = m.isScheduled
        ? (m.scheduledStartLabel?.isNotEmpty == true
            ? lang.tr(
                'Starts ${m.scheduledStartLabel} (BD Time)',
                'শুরু: ${m.scheduledStartLabel} (বাংলাদেশ সময়)',
              )
            : lang.tr(
                'Starts when tickets open',
                'টিকেট ছাড়া মাত্রই শুরু হবে',
              ))
        : m.isMonitoring
            ? lang.tr(
                'Relax. We will grab the seat and alert you.',
                'নিশ্চিন্তে থাকুন। সিট পেলেই ধরব ও জানাব।',
              )
            : lang.tr(
                'Tap Resume to search again.',
                'আবার খুঁজতে "চালু করুন" চাপুন।',
              );

    final qty = m.bookingIntent.quantity;
    final auto = m.bookingIntent.autoReserve;
    final seatClassLabel = m.targetSeatClass?.isNotEmpty == true
        ? m.targetSeatClass!
        : lang.tr('Any class', 'যেকোনো ক্লাস');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [color.withValues(alpha: 0.2), const Color(0xFF111B22)]
              : [color.withValues(alpha: 0.12), Colors.white],
        ),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.14 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status + quick actions
          Row(
            children: [
              _StatusChip(text: statusText, color: color),
              const Spacer(),
              _MiniAction(
                icon: m.isMonitoring ? Icons.pause_rounded : Icons.play_arrow_rounded,
                label: m.isMonitoring
                    ? lang.tr('Pause', 'স্থগিত')
                    : lang.tr('Resume', 'চালু'),
                color: m.isMonitoring ? AppColors.textPrimary(isDark) : AppColors.primary,
                isDark: isDark,
                onTap: m.isMonitoring
                    ? onStop
                    : (onResume ?? () => m.resumeMonitoring()),
              ),
              const SizedBox(width: 8),
              _MiniAction(
                icon: Icons.stop_rounded,
                label: lang.tr('Stop', 'বন্ধ'),
                color: _kRed,
                isDark: isDark,
                onTap: onClear,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Radar + title
          Row(
            children: [
              _RadarBeacon(
                anim: anim,
                color: color,
                active: isLive,
                size: 62,
                icon: m.isScheduled
                    ? Icons.schedule_rounded
                    : (isLive ? Icons.search_rounded : Icons.pause_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.5,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppColors.textSecondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Route + details
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface(isDark).withValues(alpha: isDark ? 0.55 : 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _outline(isDark)),
            ),
            child: Column(
              children: [
                _RouteTrack(
                  from: fromCity,
                  to: toCity,
                  isDark: isDark,
                  anim: anim,
                  moving: isLive,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniTag(
                      icon: Icons.calendar_today_rounded,
                      label: m.dateOfJourney,
                      isDark: isDark,
                    ),
                    _MiniTag(
                      icon: Icons.airline_seat_recline_extra_rounded,
                      label: seatClassLabel,
                      isDark: isDark,
                    ),
                    _MiniTag(
                      icon: Icons.people_alt_rounded,
                      label: lang.tr('$qty seat${qty > 1 ? 's' : ''}', '$qtyটি আসন'),
                      isDark: isDark,
                    ),
                    _MiniTag(
                      icon: auto ? Icons.bolt_rounded : Icons.notifications_active_rounded,
                      label: auto
                          ? lang.tr('Auto-book', 'অটো-বুক')
                          : lang.tr('Loud alarm', 'অ্যালার্ম'),
                      color: auto ? _kGreen : _kBlue,
                      isDark: isDark,
                    ),
                    _MiniTag(
                      icon: Icons.radar_rounded,
                      label: lang.tr('${m.totalChecksCount} checks', '${m.totalChecksCount} বার চেক'),
                      isDark: isDark,
                    ),
                  ],
                ),
                if (trainsList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.train_rounded, size: 15, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${lang.tr("Watching", "নজরে")}: ',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          trainsList,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: _surface(isDark).withValues(alpha: isDark ? 0.6 : 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color color;

  const _MiniTag({
    required this.icon,
    required this.label,
    required this.isDark,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// "What happens next" – kept below the via-ticket section.
class _NextStepsCard extends StatelessWidget {
  final MonitorService m;
  final bool isDark;
  final Animation<double> anim;

  const _NextStepsCard({required this.m, required this.isDark, required this.anim});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final isLive = m.isMonitoring && !m.isScheduled;
    final color = isLive
        ? AppColors.primary
        : (m.isScheduled ? _kBlue : AppColors.primary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(isDark, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lang.tr('What happens next', 'এরপর কী হবে'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 14),
          _ProgressSteps(
            isDark: isDark,
            anim: anim,
            accent: color,
            steps: [
              _StepData(
                lang.tr('Searching', 'খোঁজা হচ্ছে'),
                Icons.search_rounded,
                isLive ? _StepState.active : _StepState.pending,
              ),
              _StepData(lang.tr('Seat locked', 'সিট লক'), Icons.lock_rounded,
                  _StepState.pending),
              _StepData(lang.tr('Verify OTP', 'ওটিপি'), Icons.sms_rounded,
                  _StepState.pending),
              _StepData(lang.tr('Pay in 5 min', '৫ মিনিটে পেমেন্ট'),
                  Icons.payments_rounded, _StepState.pending),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt(isDark),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: _kBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.tr(
                      'You can keep the app in the background. We will sound a loud alert as soon as a seat is found.',
                      'অ্যাপ ব্যাকগ্রাউন্ডে রেখে অন্য কাজ করতে পারেন। সিট পেলেই জোরে অ্যালার্ম বাজবে।',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: AppColors.textSecondary(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2) Seat reserved – OTP / Pay
// ═══════════════════════════════════════════════════════════════════════════════
class _ReservationCard extends StatelessWidget {
  final Map<String, dynamic> reservation;
  final bool isDark;
  final Animation<double> anim;
  final VoidCallback onPayNow;
  final VoidCallback onClear;
  final VoidCallback onTimeout;

  const _ReservationCard({
    required this.reservation,
    required this.isDark,
    required this.anim,
    required this.onPayNow,
    required this.onClear,
    required this.onTimeout,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Success hero ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF059669), Color(0xFF10B981)],
            ),
            boxShadow: [
              BoxShadow(
                color: _kGreen.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: Icon(
                  isReady ? Icons.celebration_rounded : Icons.sms_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isReady
                          ? lang.tr('Seat reserved! 🎉', 'আসন সংরক্ষিত! 🎉')
                          : lang.tr('Almost there…', 'প্রায় হয়ে গেছে…'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isReady
                          ? lang.tr(
                              'Pay now before the timer runs out.',
                              'টাইমার শেষ হওয়ার আগে পেমেন্ট করুন।',
                            )
                          : lang.tr(
                              'Verifying your OTP. Please wait.',
                              'আপনার ওটিপি যাচাই করা হচ্ছে। অপেক্ষা করুন।',
                            ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Timer + steps ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDeco(isDark, accent: _kGreen, radius: 20),
          child: Column(
            children: [
              _CountdownRing(
                reservation: reservation,
                isDark: isDark,
                onTimeout: onTimeout,
              ),
              const SizedBox(height: 16),
              _ProgressSteps(
                isDark: isDark,
                anim: anim,
                steps: [
                  _StepData(lang.tr('Seat found', 'আসন পাওয়া'),
                      Icons.search_rounded, _StepState.done),
                  _StepData(lang.tr('Seat locked', 'সিট লক'),
                      Icons.lock_rounded, _StepState.done),
                  _StepData(
                    lang.tr('OTP verified', 'ওটিপি যাচাই'),
                    Icons.sms_rounded,
                    isReady ? _StepState.done : _StepState.active,
                  ),
                  _StepData(
                    lang.tr('Pay ticket', 'পেমেন্ট'),
                    Icons.payments_rounded,
                    isReady ? _StepState.active : _StepState.pending,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Ticket ──
        Container(
          decoration: _cardDeco(isDark),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.confirmation_number_rounded,
                            size: 16, color: _kGreen),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            trainName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary(isDark),
                            ),
                          ),
                        ),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted(isDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _RouteTrack(
                      from: from,
                      to: to,
                      isDark: isDark,
                      anim: anim,
                      moving: false,
                      accent: _kGreen,
                    ),
                  ],
                ),
              ),
              _TearLine(isDark: isDark),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (seatClass.isNotEmpty)
                          Expanded(
                            child: _InfoCell(
                              icon: Icons.airline_seat_recline_extra_rounded,
                              label: lang.tr('Class', 'ক্লাস'),
                              value: seatClass,
                              isDark: isDark,
                              color: _kGreen,
                            ),
                          ),
                        if (seatClass.isNotEmpty && coach.isNotEmpty)
                          const SizedBox(width: 8),
                        if (coach.isNotEmpty)
                          Expanded(
                            child: _InfoCell(
                              icon: Icons.directions_transit_rounded,
                              label: lang.tr('Coach', 'বগি'),
                              value: coach,
                              isDark: isDark,
                              color: _kGreen,
                            ),
                          ),
                      ],
                    ),
                    if (seatNumbers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InfoCell(
                        icon: Icons.event_seat_rounded,
                        label: lang.tr('Seat numbers', 'সিট নম্বর'),
                        value: seatNumbers,
                        isDark: isDark,
                        color: _kGreen,
                      ),
                    ],
                    if (totalFare > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lang.tr('Total fare', 'মোট ভাড়া'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(isDark),
                            ),
                          ),
                          Text(
                            '৳${totalFare.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: _kGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Pay ──
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _kGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
            shadowColor: _kGreen.withValues(alpha: 0.5),
          ),
          onPressed: onPayNow,
          icon: const Icon(Icons.payment_rounded, size: 20),
          label: Text(
            lang.tr('Pay Now', 'পেমেন্ট করুন'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 4),
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
    );
  }
}

/// Circular countdown for the 5-minute payment window.
class _CountdownRing extends StatefulWidget {
  final Map<String, dynamic> reservation;
  final bool isDark;
  final VoidCallback onTimeout;

  const _CountdownRing({
    required this.reservation,
    required this.isDark,
    required this.onTimeout,
  });

  @override
  State<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<_CountdownRing> {
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
    final color = _secondsLeft > 120
        ? _kGreen
        : (_secondsLeft > 60 ? _kAmber : _kRed);

    return Row(
      children: [
        SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: widget.isDark
                      ? const Color(0xFF26333D)
                      : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                '$m:$s',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lang.tr('Time left to pay', 'পেমেন্টের বাকি সময়'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary(widget.isDark),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _secondsLeft <= 60
                    ? lang.tr('Hurry! The seat will be released soon.',
                        'তাড়াতাড়ি করুন! আসন শীঘ্রই ছেড়ে দেওয়া হবে।')
                    : lang.tr('Your seat is held for you until the timer ends.',
                        'টাইমার শেষ না হওয়া পর্যন্ত আসনটি আপনার জন্য ধরা আছে।'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: AppColors.textSecondary(widget.isDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3) Hold expired
// ═══════════════════════════════════════════════════════════════════════════════
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
    this.onRetrySearch,
    this.onReAutoBook,
    this.onClear,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    final headline = isOtpFailure
        ? lang.tr('Hold Expired — OTP Not Verified', 'সময় শেষ — ওটিপি যাচাই হয়নি')
        : (isPaymentFailure
            ? lang.tr('Hold Expired — Payment Timed Out', 'সময় শেষ — পেমেন্টের সময় শেষ')
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1014) : const Color(0xFFFFF5F6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kRed.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _kRed.withValues(alpha: 0.1),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _surface(isDark).withValues(alpha: isDark ? 0.5 : 0.9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${fromCity ?? "Origin"} ➔ ${toCity ?? "Destination"}${dateOfJourney != null && dateOfJourney!.isNotEmpty ? " · $dateOfJourney" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary(isDark),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 20, color: AppColors.textMuted(isDark)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                lang.tr('5-Minute Time Limit Reached', '৫ মিনিটের সময়সীমা সমাপ্ত'),
                style: const TextStyle(
                  color: _kRed,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kRed.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.hourglass_bottom_rounded,
                  size: 34, color: _kRed),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB91C1C),
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            details,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onRetrySearch,
            icon: const Icon(Icons.search_rounded, size: 20),
            label: Text(
              lang.tr('Retry New Search', 'নতুন অনুসন্ধান করুন'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onReAutoBook,
                  icon: const Icon(Icons.bolt_rounded, size: 17),
                  label: Text(
                    lang.tr('Re-Auto Book', 'পুনরায় অটো-বুক'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kRed,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    side: BorderSide(color: _kRed.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onClear,
                  icon: const Icon(Icons.stop_rounded, size: 17),
                  label: Text(
                    lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
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

// ═══════════════════════════════════════════════════════════════════════════════
// 4) Zero credits
// ═══════════════════════════════════════════════════════════════════════════════
class _ZeroCreditBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback onBuy;

  const _ZeroCreditBanner({required this.isDark, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF33200A), const Color(0xFF1F1708)]
              : [const Color(0xFFFFF4D6), const Color(0xFFFFFBEB)],
        ),
        border: Border.all(color: _kAmber.withValues(alpha: 0.5), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAmber.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.stars_rounded, color: _kAmber, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add credits to continue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang.tr(
                        '1 credit = 1 successfully booked ticket.',
                        '১ ক্রেডিট = ১টি সফল টিকেট।',
                      ),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _kAmber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onBuy,
            icon: const Icon(Icons.add_circle_rounded, size: 19),
            label: const Text(
              'Buy Credit',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5) Empty state
// ═══════════════════════════════════════════════════════════════════════════════
class _EmptyMonitorView extends StatelessWidget {
  final bool isDark;
  final Animation<double> anim;

  const _EmptyMonitorView({required this.isDark, required this.anim});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: _cardDeco(isDark, radius: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _RadarBeacon(
              anim: anim,
              color: AppColors.primary,
              icon: Icons.confirmation_number_rounded,
              size: 96,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            lang.tr('No ticket search yet', 'এখনো কোনো টিকেট সার্চ নেই'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: AppColors.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            lang.tr(
              'Train full? Tell us your trip once. Rail Pro keeps checking and grabs a seat the second one opens up.',
              'ট্রেনের টিকেট শেষ? একবার আপনার যাত্রার তথ্য দিন। রেল প্রো সারাক্ষণ খুঁজবে এবং সিট খালি হওয়ামাত্র ধরে ফেলবে।',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 20),

          // How it works
          _howRow(
            1,
            Icons.search_rounded,
            _kBlue,
            lang.tr('Choose your train', 'ট্রেন বেছে নিন'),
            lang.tr('Pick route, date and class', 'রুট, তারিখ ও ক্লাস দিন'),
          ),
          _howRow(
            2,
            Icons.radar_rounded,
            AppColors.primary,
            lang.tr('We watch 24/7', 'আমরা সারাক্ষণ নজরে রাখি'),
            lang.tr('Even split routes via other stations', 'ভায়া স্টেশনের বিকল্প রুটও দেখি'),
          ),
          _howRow(
            3,
            Icons.notifications_active_rounded,
            _kAmber,
            lang.tr('Loud alert + auto-book', 'জোরে অ্যালার্ম + অটো-বুক'),
            lang.tr('Works even if your phone is locked', 'ফোন লক থাকলেও কাজ করে'),
          ),
          _howRow(
            4,
            Icons.payments_rounded,
            _kGreen,
            lang.tr('Pay within 5 minutes', '৫ মিনিটের মধ্যে পেমেন্ট'),
            lang.tr('Confirm OTP and pay to get the ticket', 'ওটিপি দিয়ে পেমেন্ট করলেই টিকেট'),
            isLast: true,
          ),

          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => AppShell.goTo(context, AppShell.tabSearch),
            icon: const Icon(Icons.search_rounded, size: 20),
            label: Text(
              lang.tr('Search Trains', 'ট্রেন অনুসন্ধান'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howRow(
    int n,
    IconData icon,
    Color color,
    String title,
    String subtitle, {
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 38,
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: _outline(isDark),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted(isDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 6) Via / split-route tickets – always visible while a search is active
// ═══════════════════════════════════════════════════════════════════════════════
class _ViaSection extends StatelessWidget {
  final List<IntermediateJourney> journeys;
  final bool isSearching;
  final String fromCity;
  final String toCity;
  final bool isDark;
  final Animation<double> anim;
  final void Function(IntermediateJourney journey, bool isFirstLeg) onBookLeg;

  const _ViaSection({
    required this.journeys,
    required this.isSearching,
    required this.fromCity,
    required this.toCity,
    required this.isDark,
    required this.anim,
    required this.onBookLeg,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final found = journeys.isNotEmpty;
    final top = journeys.take(3).toList();
    final accent = found ? _kGreen : _kBlue;

    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.alt_route_rounded, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    found
                        ? lang.tr('Another way to travel found!', 'যাওয়ার আরেকটি উপায় পাওয়া গেছে!')
                        : lang.tr('Split-route tickets', 'ভায়া / স্প্লিট টিকেট'),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: found ? _kGreen : AppColors.textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    found
                        ? lang.tr(
                            'No direct seat, but 2 short tickets get you there.',
                            'সরাসরি সিট নেই, তবে ২টি ছোট টিকেটে পৌঁছাতে পারবেন।',
                          )
                        : lang.tr(
                            'If the direct train is full, we also check routes via other stations.',
                            'সরাসরি ট্রেন ভরা থাকলে অন্য স্টেশন হয়েও খুঁজি।',
                          ),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: AppColors.textSecondary(isDark),
                    ),
                  ),
                ],
              ),
            ),
            if (found)
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: _kGreen),
                child: Text(
                  '${journeys.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (found)
          ...top.map((j) => _journeyBlock(context, j, lang))
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _surfaceAlt(isDark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _outline(isDark)),
            ),
            child: Row(
              children: [
                if (isSearching)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_kBlue),
                    ),
                  )
                else
                  Icon(Icons.hourglass_empty_rounded,
                      size: 16, color: AppColors.textMuted(isDark)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSearching
                        ? lang.tr('Checking split routes now…', 'এখন বিকল্প রুট খোঁজা হচ্ছে…')
                        : lang.tr(
                            'No split routes right now. They will appear here the moment one opens up.',
                            'এখন কোনো বিকল্প রুট নেই। পেলেই এখানে দেখাবে।',
                          ),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final glow = found ? 0.5 + 0.5 * math.sin(anim.value * 2 * math.pi) : 0.0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: found
                ? (isDark ? const Color(0xFF0D1E18) : const Color(0xFFF0FDF6))
                : _surface(isDark),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: found
                  ? _kGreen.withValues(alpha: 0.4 + 0.35 * glow)
                  : _outline(isDark),
              width: found ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (found ? _kGreen : Colors.black)
                    .withValues(alpha: found ? 0.1 + 0.12 * glow : (isDark ? 0.18 : 0.06)),
                blurRadius: found ? 20 + 8 * glow : 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: inner,
    );
  }

  Widget _journeyBlock(
    BuildContext context,
    IntermediateJourney journey,
    LanguageService lang,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outline(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                journey.isOverlapping ? Icons.shuffle_rounded : Icons.place_rounded,
                size: 15,
                color: _kGreen,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  journey.isOverlapping
                      ? '${lang.tr("Overlap Split", "ওভারল্যাপ স্প্লিট")}: ${journey.leg2From} - ${journey.leg1To}'
                      : '${lang.tr("Change at", "বদল করুন")} ${journey.via}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
              ),
              if (journey.isOverlapping) ...[
                const SizedBox(width: 6),
                _StatusChip(
                  text: lang.tr('SAME TRAIN', 'একই ট্রেন'),
                  color: _kBlue,
                  dot: false,
                ),
              ],
              const Spacer(),
              _StatusChip(
                text: '${journey.seats} ${lang.tr("SEATS", "আসন")}',
                color: _kGreen,
                dot: false,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _legRow(
            legNumber: 1,
            from: fromCity,
            to: journey.leg1To,
            trainNumber: journey.first.tripNumber,
            seat: journey.firstSeat,
            date: journey.firstDate,
            onBook: () => onBookLeg(journey, true),
            lang: lang,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.more_vert_rounded, size: 15, color: AppColors.textMuted(isDark)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    journey.layoverText(isBangla: lang.isBangla),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _legRow(
            legNumber: 2,
            from: journey.leg2From,
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

  Widget _legRow({
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceAlt(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outline(isDark)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: _kGreen),
            child: Text(
              '$legNumber',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$from ➔ $to',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$trainNumber · ${seat.displayName} · ${seat.seatCounts.online} ${lang.tr("seats", "আসন")}${fareNum > 0 ? " · ৳${fareNum.toStringAsFixed(0)}" : ""}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onBook,
            child: Text(
              lang.tr('Book', 'বুক'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
