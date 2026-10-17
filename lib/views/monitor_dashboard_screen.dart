import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';

import 'package:provider/provider.dart';

import '../services/booking_service.dart';
import '../services/credit_service.dart';
import '../services/language_service.dart';
import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import '../services/secure_store.dart';
import '../services/web_session_service.dart';
import '../utils/app_theme.dart';
import 'booking_screen.dart';
import 'recharge_credit_dialog.dart';
import 'reservation_screen.dart';
import 'webview_login_screen.dart';
import '../widgets/fancy_train_loader.dart';
import '../widgets/scenic_rail_header.dart';
import '../services/turnstile_gate.dart';
import '../utils/friendly_error.dart';

enum _BookingStep { searching, reserving, verifying, paying, done }

class MonitorDashboardScreen extends StatefulWidget {
  const MonitorDashboardScreen({super.key});
  @override
  State<MonitorDashboardScreen> createState() => _MonitorDashboardScreenState();
}

class _MonitorDashboardScreenState extends State<MonitorDashboardScreen>
    with TickerProviderStateMixin {
  Timer? _refreshTimer;
  Map<String, dynamic>? _reservation;
  bool _reading = false;
  bool _sessionExpired = false;
  bool _redirecting = false;
  bool _openingReservation = false;

  late final AnimationController _queueCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    CreditService().addListener(_onCreditChanged);
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    _queueCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!isTest) {
      _queueCtrl.repeat();
      _pulseCtrl.repeat(reverse: true);
    }
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refresh(),
    );
  }

  void _onCreditChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final value = await BookingService.pending();
      if (value != null) {
        final started = DateTime.tryParse('${value['startedAt'] ?? ''}');
        final expiry = DateTime.tryParse('${value['expiresAt'] ?? ''}');
        final now = DateTime.now();
        final is5MinElapsed =
            (started != null && now.difference(started).inMinutes >= 5) ||
            (expiry != null && !now.isBefore(expiry));
        if (is5MinElapsed) {
          await BookingService.clear();
          if (mounted) {
            context.read<MonitorService>().markReservationExpired();
            setState(() => _reservation = null);
          }
          return;
        }
        if (value['status'] == 'awaitingOtp' && !ReservationScreen.isActive && !_openingReservation && mounted) {
          final elapsedSeconds = started != null ? now.difference(started).inSeconds : 0;
          if (value['autoVerify'] != true || elapsedSeconds >= 20) {
            _openingReservation = true;
            Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(builder: (_) => const ReservationScreen()))
                .then((_) => _openingReservation = false);
          }
        }
      } else if (_reservation != null) {
        // Reservation expired / removed externally after 5 minutes
        if (mounted) {
          context.read<MonitorService>().markReservationExpired();
          setState(() => _reservation = null);
        }
      }
      if (mounted) setState(() => _reservation = value);
      await _checkSession();
    } finally {
      _reading = false;
    }
  }

  Future<void> _checkSession() async {
    if (_sessionExpired || !mounted) return;
    final m = context.read<MonitorService>();
    if (m.needsLogin) {
      setState(() => _sessionExpired = true);
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted && !_redirecting) {
        _redirecting = true;
        await _doSessionExpiry();
      }
      return;
    }
  }

  Future<void> _doSessionExpiry() async {
    try {
      await WebSessionService.clear();
      await SecureStore.delete('rail_token');
      await SecureStore.delete('rail_cft_token');
      await SecureStore.delete('rail_cft_token_time');
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, sec) =>
            const WebviewLoginScreen(clearSession: true),
        transitionsBuilder: (ctx, a, sec, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    CreditService().removeListener(_onCreditChanged);
    _refreshTimer?.cancel();
    _queueCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSolveTurnstile() async {
    if (TurnstileGate.instance.isShowing) return;
    await context.read<MonitorService>().resolveTurnstile();
  }

  void _showWalkthroughGuide() {
    final lang = LanguageService.of(context, listen: false);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(lang.tr('Security check', 'নিরাপত্তা যাচাই')),
              subtitle: Text(
                lang.tr(
                  'Checks run automatically. Tap only if asked.',
                  'যাচাই স্বয়ংক্রিয়। প্রয়োজন হলে ট্যাপ করুন।',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: Text(lang.tr('Verify OTP', 'ওটিপি যাচাই')),
              subtitle: Text(
                lang.tr(
                  'Use Google SMS consent or enter the code.',
                  'Google-এর অনুমতি দিন অথবা কোড লিখুন।',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.payment_outlined),
              title: Text(lang.tr('Pay on Railway', 'রেলওয়েতে পেমেন্ট')),
              subtitle: Text(
                lang.tr(
                  'Complete payment before the hold expires.',
                  'সংরক্ষণের মেয়াদ শেষ হওয়ার আগে পেমেন্ট করুন।',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleStopAndClear() async {
    final lang = LanguageService.of(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lang.tr('Stop & Clear Search?', 'অনুসন্ধান বন্ধ ও মুছবেন?'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          lang.tr(
            'This will stop monitoring and clear all journey details from your monitor.',
            'এটি অনুসন্ধান সম্পূর্ণরূপে বন্ধ করবে এবং মনিটর স্ক্রিন থেকে যাত্রার তথ্য মুছে ফেলবে।',
          ),
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.tr('Cancel', 'বাতিল')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final m = context.read<MonitorService>();
      await m.clearSearch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.tr(
                      'Search stopped and monitor cleared',
                      'অনুসন্ধান বন্ধ এবং মনিটর খালি করা হয়েছে',
                    ),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF1E293B),
          ),
        );
      }
    }
  }

  void _handlePauseSearch() {
    final m = context.read<MonitorService>();
    final lang = LanguageService.of(context, listen: false);
    m.pauseMonitoring();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.tr('Search paused', 'অনুসন্ধান স্থগিত করা হয়েছে')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleResumeSearch() {
    final m = context.read<MonitorService>();
    final lang = LanguageService.of(context, listen: false);
    m.resumeMonitoring();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang.tr('Search resumed', 'অনুসন্ধান আবার চালু করা হয়েছে'),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  _BookingStep _step(MonitorService m, Map<String, dynamic>? p) {
    if (p == null) return _BookingStep.searching;
    final s = p['status']?.toString() ?? '';
    if (s == 'readyForPayment') return _BookingStep.paying;
    if (s == 'awaitingOtp') return _BookingStep.verifying;
    return _BookingStep.reserving;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MonitorService>();
    final credit = CreditService();
    final lang = LanguageService.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSearch = m.dateOfJourney.isNotEmpty;
    final p = _reservation;
    final expiry = DateTime.tryParse('${p?['expiresAt'] ?? ''}');
    final expired = expiry != null && !expiry.isAfter(DateTime.now());
    final ready = p?['status'] == 'readyForPayment' && !expired;
    final otp = p?['status'] == 'awaitingOtp' && !expired;
    final step = _step(m, p);
    final isActive =
        m.isMonitoring && !m.isScheduled && p == null && !m.needsLogin;
    final exactError =
        m.lastBookingError ?? (!m.isMonitoring ? m.lastError : null);
    final isReservationExpired = !m.isMonitoring &&
        (m.lastReservationExpired || (p != null && expired) || (m.bookingFailureReason != null && m.bookingFailureReason!.isNotEmpty));

    if (_sessionExpired) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg(isDark),
        body: _ExpiredOverlay(ctrl: _pulseCtrl),
      );
    }

    final fromCity = m.fromCity.isEmpty ? 'Dhaka' : m.fromCity;
    final toCity = m.toCity.isEmpty ? 'Chattogram' : m.toCity;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      extendBodyBehindAppBar: false,
      appBar: _TopBar(
        onGuide: _showWalkthroughGuide,
        credits: credit.credits,
        isMonitoring: m.isMonitoring,
        isScheduled: m.isScheduled,
      ),
      body: Stack(
        children: [
          // ── Background Train Track Horizon Canvas (Seamless with theme) ──
          Positioned.fill(
            child: _BgCanvas(ctrl: _queueCtrl, isDark: isDark),
          ),

          // ── Main Content Area ──
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 30,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasSearch || credit.credits <= 0) ...[
                          if (isReservationExpired)
                            _ReservationExpiredCard(
                              fromCity: fromCity,
                              toCity: toCity,
                              trainName: m.targetTrain,
                              seatClass: m.targetSeatClass,
                              dateOfJourney: m.dateOfJourney,
                              reason: m.bookingFailureReason,
                              isOtpFailure: p?['status'] == 'awaitingOtp',
                              isPaymentFailure: p?['status'] == 'readyForPayment',
                              isDark: isDark,
                              pulseCtrl: _pulseCtrl,
                              onRetrySearch: () => AppShell.goTo(context, AppShell.tabSearch),
                              onReAutoBook: () async => await m.reAutoBook(),
                              onClear: _handleStopAndClear,
                              onDismiss: () => m.dismissBookingFailure(),
                            )
                          else ...[
                            // ── 1. Master Train Cockpit HUD Card ──
                            _CockpitHudCard(
                              fromCity: fromCity,
                              toCity: toCity,
                              trainName: m.targetTrain,
                              seatClass: m.targetSeatClass,
                              dateOfJourney: m.dateOfJourney,
                              step: step,
                              isActive: isActive,
                              scheduledStart: m.isScheduled
                                  ? m.scheduledStartLabel
                                  : null,
                              ready: ready,
                              otp: otp,
                              credits: credit.credits,
                              remainingTime:
                                  m.isMonitoring && m.remainingFreeSeconds >= 0
                                  ? m.remainingTimeFormatted
                                  : null,
                              queueCtrl: _queueCtrl,
                              pulseCtrl: _pulseCtrl,
                              isDark: isDark,
                              onClear: _handleStopAndClear,
                            ),

                            const SizedBox(height: 12),

                          // ── Exact Error Banner (if any) ──
                          if (exactError != null && exactError.isNotEmpty && !isReservationExpired) ...[
                            _ErrorBanner(
                              message: friendlyErrorMessage(exactError, isBangla: lang.isBangla),
                              onVerifyTurnstile: _handleSolveTurnstile,
                              onDismiss: () => m.clearBookingError(),
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // ── 2. Coupled Train Coach Route Tracker (4 Steps) ──
                          _TrainCoachTracker(
                            step: step,
                            ready: ready,
                            otp: otp,
                            p: p,
                            pulseCtrl: _pulseCtrl,
                            isDark: isDark,
                          ),

                          const SizedBox(height: 14),

                          // ── 2b. 5-Min Payment Countdown Timer ──
                          if (p != null && !expired)
                            _PaymentTimerBar(
                              reservation: p,
                              isDark: isDark,
                              onTimeout: () async {
                                await BookingService.clear();
                                if (context.mounted) {
                                  context.read<MonitorService>().markReservationExpired();
                                }
                              },
                            ),

                          if (p != null && !expired) const SizedBox(height: 14),

                          // ── 3. Train Master Throttle Actions ──
                          _TrainActionButtons(
                            m: m,
                            p: p,
                            ready: ready,
                            otp: otp,
                            expired: expired,
                            hasSearch: hasSearch,
                            credits: credit.credits,
                            onReservation: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ReservationScreen(),
                                ),
                              );
                              await _refresh();
                            },
                            onRailway: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingScreen(
                                  url: NotificationService.bookingUrl(
                                    m.fromCity,
                                    m.toCity,
                                    m.dateOfJourney,
                                    m.targetSeatClass ?? 'SNIGDHA',
                                  ),
                                ),
                              ),
                            ),
                            onSignIn: _doSessionExpiry,
                            onPause: _handlePauseSearch,
                            onResume: _handleResumeSearch,
                            onClear: _handleStopAndClear,
                            pulseCtrl: _pulseCtrl,
                            isDark: isDark,
                          ),
                        ],
                      ] else ...[
                          // ── Cleared / Empty Monitor State ──
                          _EmptyMonitorView(
                            isDark: isDark,
                            pulseCtrl: _pulseCtrl,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Seamless App Bar ──────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onGuide;
  final int credits;
  final bool isMonitoring;
  final bool isScheduled;

  const _TopBar({
    this.onGuide,
    required this.credits,
    required this.isMonitoring,
    this.isScheduled = false,
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const AppBrandIcon(size: 38),
              const SizedBox(width: 10),

              // Title and Live Status Indicator
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rail Pro',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 6,
                            offset: Offset(0, 1.2),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isMonitoring
                                ? AppColors.accent
                                : Colors.white60,
                            boxShadow: isMonitoring
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withValues(
                                        alpha: 0.8,
                                      ),
                                      blurRadius: 5,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isScheduled
                                ? lang.tr('SCHEDULED', 'নির্ধারিত')
                                : isMonitoring
                                ? lang.tr('LIVE RADAR', 'লাইভ রাডার')
                                : lang.tr('STANDBY', 'স্ট্যান্ডবাই'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              shadows: const [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Credit Pill
              GestureDetector(
                onTap: () => RechargeCreditDialog.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: credits <= 0
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: credits <= 0
                          ? const Color(0xFFF59E0B)
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        color: credits <= 0
                            ? const Color(0xFFF59E0B)
                            : AppColors.gold,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        credits <= 0 ? '0 • Buy' : '$credits',
                        style: TextStyle(
                          color: credits <= 0
                              ? const Color(0xFFFDE68A)
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Guide Action Button
              if (onGuide != null)
                GestureDetector(
                  onTap: onGuide,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.help_outline_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          lang.tr('Guide', 'নির্দেশিকা'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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

// ─── Animated Railway Horizon Canvas ──────────────────────────────────────────
class _BgCanvas extends StatelessWidget {
  final AnimationController ctrl;
  final bool isDark;
  const _BgCanvas({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ctrl,
    builder: (context, child) => CustomPaint(
      painter: _RailwayHorizonPainter(t: ctrl.value, isDark: isDark),
    ),
  );
}

class _RailwayHorizonPainter extends CustomPainter {
  final double t;
  final bool isDark;
  _RailwayHorizonPainter({required this.t, required this.isDark});

  @override
  void paint(Canvas canvas, Size s) {
    // 1. Atmosphere Gradient matching theme
    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF060D1A), Color(0xFF091629), Color(0xFF060D1A)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F5FF), Color(0xFFE4EDFC), Color(0xFFF0F5FF)],
          );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()
        ..shader = bgGradient.createShader(
          Rect.fromLTWH(0, 0, s.width, s.height),
        ),
    );

    // 2. High-speed Railway Perspective Speed Tracks
    final railColor = isDark
        ? AppColors.primary.withValues(alpha: 0.08)
        : AppColors.primaryDark.withValues(alpha: 0.05);
    final railPaint = Paint()
      ..color = railColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dl = 26.0;
    const gl = 16.0;
    const tl = dl + gl;
    final off = t * tl;
    final lx = s.width * 0.28;
    final rx = s.width * 0.72;

    for (double y = -tl + off; y < s.height + tl; y += tl) {
      canvas.drawLine(Offset(lx, y), Offset(lx, y + dl), railPaint);
      canvas.drawLine(Offset(rx, y), Offset(rx, y + dl), railPaint);
    }

    // Horizontal Sleepers
    final sleeperPaint = Paint()
      ..color = isDark
          ? AppColors.primary.withValues(alpha: 0.035)
          : AppColors.primaryDark.withValues(alpha: 0.03)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (double y = -36 + off * 0.5; y < s.height + 36; y += 36) {
      canvas.drawLine(Offset(lx - 12, y), Offset(rx + 12, y), sleeperPaint);
    }

    // 3. Ambient Railway Beacon Orbs
    void drawOrb(Offset center, Color col, double r, double alpha) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              col.withValues(alpha: alpha),
              col.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    final glowAlpha = isDark ? 0.07 : 0.04;
    drawOrb(
      Offset(s.width * 0.15, s.height * 0.20),
      AppColors.primary,
      130,
      glowAlpha,
    );
    drawOrb(
      Offset(s.width * 0.85, s.height * 0.55),
      AppColors.accent,
      110,
      glowAlpha * 0.8,
    );
    drawOrb(
      Offset(s.width * 0.50, s.height * 0.06),
      const Color(0xFF00A07A),
      160,
      glowAlpha * 1.2,
    );
  }

  @override
  bool shouldRepaint(_RailwayHorizonPainter o) =>
      o.t != t || o.isDark != isDark;
}

// ─── Cleared / Empty Monitor State ───────────────────────────────────────────
class _EmptyMonitorView extends StatelessWidget {
  final bool isDark;
  final AnimationController pulseCtrl;

  const _EmptyMonitorView({required this.isDark, required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.cardBorder(isDark), width: 1.2),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.primaryDark.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.radar_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            lang.tr('Monitor Cleared', 'মনিটর খালি রয়েছে'),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(isDark),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lang.tr(
              'No active journey is being monitored right now.\nSearch trains to start live seat monitoring or auto-booking.',
              'বর্তমানে কোনো অনুসন্ধান সক্রিয় নেই।\nআসন লাইভ মনিটরিং করতে ট্রেন অনুসন্ধান ও অটো-বুকিং শুরু করুন।',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textMuted(isDark),
            ),
          ),
          const SizedBox(height: 24),
          _MasterButton(
            label: lang.tr('Search Tickets', 'টিকেট খুঁজুন'),
            icon: Icons.search_rounded,
            gradientColors: const [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            onTap: () => AppShell.goTo(context, AppShell.tabSearch),
          ),
        ],
      ),
    );
  }
}

// ─── Master Train Cockpit HUD Card ───────────────────────────────────────────
class _CockpitHudCard extends StatelessWidget {
  final String fromCity;
  final String toCity;
  final String? trainName;
  final String? seatClass;
  final String dateOfJourney;
  final _BookingStep step;
  final bool isActive;
  final bool ready;
  final bool otp;
  final int credits;
  final String? remainingTime;
  final String? scheduledStart;
  final AnimationController queueCtrl;
  final AnimationController pulseCtrl;
  final bool isDark;
  final VoidCallback? onClear;

  const _CockpitHudCard({
    required this.fromCity,
    required this.toCity,
    this.trainName,
    this.seatClass,
    required this.dateOfJourney,
    required this.step,
    required this.isActive,
    required this.ready,
    required this.otp,
    required this.credits,
    this.remainingTime,
    this.scheduledStart,
    required this.queueCtrl,
    required this.pulseCtrl,
    required this.isDark,
    this.onClear,
  });

  String _statusTitle(LanguageService lang) {
    if (scheduledStart != null) {
      return lang.tr('Search scheduled', 'অনুসন্ধান নির্ধারিত');
    }
    if (ready) {
      return lang.tr(
        'Seats held · Ready to pay',
        'আসন সংরক্ষিত • পেমেন্ট প্রস্তুত',
      );
    }
    if (otp) {
      return lang.tr('Verify your booking', 'ওটিপি যাচাইয়ের অপেক্ষায়');
    }
    if (credits <= 0) return 'Add credits to continue';
    switch (step) {
      case _BookingStep.searching:
        return lang.tr('Finding available seats', 'কোচ ও আসন স্ক্যান চলছে');
      case _BookingStep.reserving:
        return lang.tr('Reserving your seats', 'আসন বুকিং চলছে...');
      case _BookingStep.verifying:
        return lang.tr('Checking access', 'নিরাপত্তা টোকেন যাচাই হচ্ছে');
      case _BookingStep.paying:
        return lang.tr('Ready to pay', 'পেমেন্ট গেটওয়ে প্রস্তুত');
      case _BookingStep.done:
        return lang.tr('Booking confirmed', 'সংরক্ষণ সম্পন্ন');
    }
  }

  Color get _statusColor {
    if (ready) return AppColors.gold;
    if (otp) return AppColors.warning;
    if (credits <= 0) return AppColors.warning;
    if (step == _BookingStep.reserving) return AppColors.accent;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.cardBorder(isDark), width: 1.2),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: _statusColor.withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── A. High-Speed Train Route Header ──
          Row(
            children: [
              // Origin Station
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
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Animated Route Rail with Bullet Train Icon
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 90,
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: queueCtrl,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset((queueCtrl.value - 0.5) * 20, 0),
                            child: Icon(
                              Icons.train_rounded,
                              size: 20,
                              color: isDark
                                  ? AppColors.primary
                                  : AppColors.primaryDark,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: List.generate(7, (i) {
                          return Expanded(
                            child: Container(
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              color: (i % 2 == 0)
                                  ? (isDark
                                        ? AppColors.primary.withValues(
                                            alpha: 0.6,
                                          )
                                        : AppColors.primaryDark.withValues(
                                            alpha: 0.5,
                                          ))
                                  : Colors.transparent,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),

              // Destination Station
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
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
                        if (onClear != null) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: onClear,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: AppColors.textMuted(isDark),
                              ),
                            ),
                          ),
                        ],
                      ],
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
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── B. Journey Badges Strip ──
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _hudPill(
                icon: Icons.calendar_today_rounded,
                text: dateOfJourney.isEmpty
                    ? lang.tr('Live', 'লাইভ')
                    : dateOfJourney,
                isDark: isDark,
              ),
              _hudPill(
                icon: Icons.directions_railway_filled_rounded,
                text: trainName ?? lang.tr('All Trains', 'সকল ট্রেন'),
                isDark: isDark,
              ),
              _hudPill(
                icon:
                    (seatClass == null ||
                        seatClass == 'ALL' ||
                        seatClass == 'RANDOM')
                    ? Icons.shuffle_rounded
                    : Icons.airline_seat_recline_extra_rounded,
                text:
                    (seatClass == null ||
                        seatClass == 'ALL' ||
                        seatClass == 'RANDOM')
                    ? lang.tr('Random (Any Class)', 'যেকোনো শ্রেণি')
                    : seatClass!,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? const Color(0xFF1E3A55) : const Color(0xFFE2EBF5),
          ),
          const SizedBox(height: 12),

          // ── C. Illuminated Queue / Scanner Chamber ──
          if (scheduledStart != null) ...[
            Text(
              lang.tr(
                'Starts $scheduledStart (Bangladesh time) · 10 days before your journey',
                'শুরু: $scheduledStart (বাংলাদেশ সময়) · যাত্রার ১০ দিন আগে',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            constraints: const BoxConstraints(minHeight: 172),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF081220) : const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF173049)
                    : const Color(0xFFD9E6F5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Fancy animated ticket loader depicting queue & illuminated counter
                FancyTrainLoader(
                  height: 176,
                  showCard: false,
                  subMessage: ready || otp ? null : '',
                  message: scheduledStart != null
                      ? _statusTitle(lang)
                      : !isActive && !ready && !otp && credits > 0
                      ? lang.tr('Search paused', 'অনুসন্ধান স্থগিত')
                      : _statusTitle(lang),
                  stage: ready
                      ? JourneyAnimationStage.payment
                      : otp
                      ? JourneyAnimationStage.verifying
                      : !isActive || credits <= 0
                      ? JourneyAnimationStage.paused
                      : switch (step) {
                          _BookingStep.searching =>
                            JourneyAnimationStage.searching,
                          _BookingStep.reserving =>
                            JourneyAnimationStage.reserving,
                          _BookingStep.verifying =>
                            JourneyAnimationStage.verifying,
                          _BookingStep.paying => JourneyAnimationStage.payment,
                          _BookingStep.done => JourneyAnimationStage.complete,
                        },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── D. Status Beacon & Remaining Countdown ──
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // Live Pulse Status Chip
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusColor.withValues(
                          alpha: 0.35 + pulseCtrl.value * 0.25,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _statusColor,
                            boxShadow: [
                              BoxShadow(
                                color: _statusColor.withValues(
                                  alpha: 0.6 + pulseCtrl.value * 0.4,
                                ),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (ready || otp)
                              ? (ready
                                    ? lang.tr(
                                        'READY TO PAY',
                                        'পেমেন্ট প্রস্তুত',
                                      )
                                    : lang.tr('AWAITING OTP', 'ওটিপি যাচাই'))
                              : (credits <= 0
                                    ? 'ZERO CREDITS • RECHARGE'
                                    : (scheduledStart != null
                                          ? lang.tr('SCHEDULED', 'নির্ধারিত')
                                          : isActive
                                          ? lang.tr(
                                              'SEARCHING',
                                              'সক্রিয় অনুসন্ধান',
                                            )
                                          : lang.tr(
                                              'SEARCH PAUSED',
                                              'অনুসন্ধান স্থগিত',
                                            ))),
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Countdown Timer
              if (remainingTime != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: AppColors.textMuted(isDark),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        remainingTime!.contains('remaining')
                            ? (lang.isBangla
                                  ? remainingTime!.replaceAll(
                                      'remaining',
                                      'বাকি',
                                    )
                                  : remainingTime!)
                            : '$remainingTime ${lang.tr("remaining", "বাকি")}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hudPill({
    required IconData icon,
    required String text,
    required bool isDark,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132238) : const Color(0xFFEFF5FC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF1F3856) : const Color(0xFFD6E4F5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? AppColors.primary : AppColors.primaryDark,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Coupled Train Coach Route Tracker (4 Steps) ──────────────────────────────
class _TrainCoachTracker extends StatelessWidget {
  final _BookingStep step;
  final bool ready, otp;
  final Map<String, dynamic>? p;
  final AnimationController pulseCtrl;
  final bool isDark;

  const _TrainCoachTracker({
    required this.step,
    required this.ready,
    required this.otp,
    required this.p,
    required this.pulseCtrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final stages = [
      (
        Icons.radar_rounded,
        lang.tr('Scanning', 'স্ক্যানিং'),
        step == _BookingStep.searching && p == null,
        p != null || step.index > _BookingStep.searching.index,
      ),
      (
        Icons.event_seat_rounded,
        lang.tr('Booking', 'বুকিং'),
        step == _BookingStep.reserving,
        step.index > _BookingStep.reserving.index || ready || otp,
      ),
      (
        Icons.shield_outlined,
        lang.tr('Verifying', 'যাচাই'),
        step == _BookingStep.verifying || otp,
        ready,
      ),
      (
        Icons.credit_card_rounded,
        lang.tr('Paying', 'পেমেন্ট'),
        step == _BookingStep.paying || ready,
        false,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.linear_scale_rounded,
                  size: 16,
                  color: isDark ? AppColors.primary : AppColors.primaryDark,
                ),
                const SizedBox(width: 6),
                Text(
                  lang.tr('RESERVATION LINE STATUS', 'বুকিং লাইনের অগ্রগতি'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: stages.asMap().entries.map((entry) {
              final i = entry.key;
              final (icon, label, active, done) = entry.value;

              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _CoachNode(
                        coachNumber: i + 1,
                        icon: icon,
                        label: label,
                        active: active,
                        done: done,
                        pulseCtrl: pulseCtrl,
                        isDark: isDark,
                      ),
                    ),
                    if (i < stages.length - 1)
                      _CoachCoupler(done: done, active: active, isDark: isDark),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CoachNode extends StatelessWidget {
  final int coachNumber;
  final IconData icon;
  final String label;
  final bool active, done;
  final AnimationController pulseCtrl;
  final bool isDark;

  const _CoachNode({
    required this.coachNumber,
    required this.icon,
    required this.label,
    required this.active,
    required this.done,
    required this.pulseCtrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? AppColors.primary : AppColors.primaryDark;

    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (context, child) {
        final Color cardBg;
        final Color borderColor;
        final Color iconColor;

        if (done) {
          cardBg = primaryColor.withValues(alpha: 0.16);
          borderColor = primaryColor.withValues(alpha: 0.55);
          iconColor = primaryColor;
        } else if (active) {
          cardBg = primaryColor.withValues(
            alpha: 0.12 + pulseCtrl.value * 0.08,
          );
          borderColor = primaryColor.withValues(
            alpha: 0.5 + pulseCtrl.value * 0.4,
          );
          iconColor = primaryColor;
        } else {
          cardBg = isDark ? const Color(0xFF0F1E33) : const Color(0xFFF3F7FC);
          borderColor = isDark
              ? const Color(0xFF1E3A55)
              : const Color(0xFFD9E6F5);
          iconColor = AppColors.textMuted(isDark);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Train Coach Contour Box
            Container(
              height: 44,
              width: 50,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: active ? 1.5 : 1.0,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: primaryColor.withValues(
                            alpha: 0.18 + pulseCtrl.value * 0.15,
                          ),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Coach window contour line at top
                  Positioned(
                    top: 3,
                    left: 6,
                    right: 6,
                    height: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),

                  // Main icon or done checkmark
                  done
                      ? Icon(Icons.check_rounded, color: primaryColor, size: 20)
                      : Icon(icon, color: iconColor, size: 19),

                  // Coach wheels dots at bottom
                  Positioned(
                    bottom: 2,
                    left: 8,
                    right: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: borderColor.withValues(alpha: 0.5),
                          ),
                        ),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: borderColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),

            // Label
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: (done || active)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: (done || active)
                    ? AppColors.textPrimary(isDark)
                    : AppColors.textMuted(isDark),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CoachCoupler extends StatelessWidget {
  final bool done, active, isDark;
  const _CoachCoupler({
    required this.done,
    required this.active,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? AppColors.primary : AppColors.primaryDark;
    return Container(
      width: 14,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: done
            ? primaryColor
            : active
            ? primaryColor.withValues(alpha: 0.6)
            : (isDark ? const Color(0xFF1E3A55) : const Color(0xFFD9E6F5)),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

// ─── 5-Minute Payment Countdown Timer Bar ────────────────────────────────────
class _PaymentTimerBar extends StatefulWidget {
  final Map<String, dynamic> reservation;
  final bool isDark;
  final VoidCallback onTimeout;

  const _PaymentTimerBar({
    required this.reservation,
    required this.isDark,
    required this.onTimeout,
  });

  @override
  State<_PaymentTimerBar> createState() => _PaymentTimerBarState();
}

class _PaymentTimerBarState extends State<_PaymentTimerBar>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 5 * 60; // 5 minutes
  Timer? _ticker;
  late AnimationController _pulseCtrl;
  int _secondsLeft = _totalSeconds;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _computeSecondsLeft();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _computeSecondsLeft();
    });
  }

  void _computeSecondsLeft() {
    if (!mounted) return;
    final started = DateTime.tryParse(
      '${widget.reservation['startedAt'] ?? ''}',
    );
    final expiry = DateTime.tryParse(
      '${widget.reservation['expiresAt'] ?? ''}',
    );

    int secs;
    if (expiry != null) {
      secs = expiry.difference(DateTime.now()).inSeconds;
    } else if (started != null) {
      final elapsed = DateTime.now().difference(started).inSeconds;
      secs = _totalSeconds - elapsed;
    } else {
      secs = _totalSeconds;
    }

    if (secs <= 0 && !_expired) {
      _expired = true;
      _ticker?.cancel();
      _pulseCtrl.stop();
      widget.onTimeout();
    }

    if (!_expired) {
      setState(() => _secondsLeft = secs.clamp(0, _totalSeconds));
      // Pulse animation in the last 60 seconds
      if (secs <= 60 && !_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) return const SizedBox.shrink();

    final progress = (_secondsLeft / _totalSeconds).clamp(0.0, 1.0);
    final mins = _secondsLeft ~/ 60;
    final secs = _secondsLeft % 60;
    final isUrgent = _secondsLeft <= 60;
    final isWarning = _secondsLeft <= 120;

    final timerColor = isUrgent
        ? AppColors.error
        : isWarning
        ? const Color(0xFFF59E0B)
        : AppColors.primary;

    final lang = LanguageService.of(context);

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final glow = isUrgent ? (_pulseCtrl.value * 0.25) : 0.0;
        return Container(
          decoration: BoxDecoration(
            color: timerColor.withValues(alpha: 0.08 + glow),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: timerColor.withValues(alpha: 0.35 + glow),
              width: 1.2,
            ),
            boxShadow: isUrgent
                ? [
                    BoxShadow(
                      color: timerColor.withValues(alpha: 0.18 + glow),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUrgent ? Icons.timer_off_rounded : Icons.timer_rounded,
                    color: timerColor,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    lang.tr(
                      'Complete purchase within',
                      'টিকেট ক্রয় সম্পন্ন করুন',
                    ),
                    style: TextStyle(
                      color: timerColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  const Spacer(),
                  // Countdown digits
                  Text(
                    '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: timerColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Progress bar (drains left to right)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: timerColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                ),
              ),
              if (isUrgent) ...[
                const SizedBox(height: 6),
                Text(
                  lang.tr(
                    '⚠ Seats will be released if not paid in time!',
                    '⚠ সময়ের মধ্যে পরিশোধ না করলে আসন বাতিল হবে!',
                  ),
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Train Master Action Controls ────────────────────────────────────────────
class _TrainActionButtons extends StatelessWidget {
  final MonitorService m;
  final Map<String, dynamic>? p;
  final bool ready, otp, expired, hasSearch;
  final int credits;
  final VoidCallback onReservation, onRailway, onSignIn;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onClear;
  final AnimationController pulseCtrl;
  final bool isDark;

  const _TrainActionButtons({
    required this.m,
    required this.p,
    required this.ready,
    required this.otp,
    required this.expired,
    required this.hasSearch,
    required this.credits,
    required this.onReservation,
    required this.onRailway,
    required this.onSignIn,
    this.onPause,
    this.onResume,
    this.onClear,
    required this.pulseCtrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);

    // If a ticket is reserved or awaiting OTP/payment, user can ALWAYS proceed to pay even with 0 credits
    if (p != null && !expired) {
      return Column(
        children: [
          _MasterButton(
            label: ready
                ? lang.tr('Pay Now', 'পেমেন্ট করুন')
                : (otp
                      ? lang.tr('Enter OTP', 'ওটিপি দিন')
                      : lang.tr('View Reservation', 'বুকিং দেখুন')),
            icon: ready
                ? Icons.payment_rounded
                : (otp
                      ? Icons.sms_rounded
                      : Icons.confirmation_number_outlined),
            gradientColors: ready
                ? const [Color(0xFFFBBF24), Color(0xFFD97706)]
                : (otp
                      ? const [Color(0xFF38BDF8), Color(0xFF0284C7)]
                      : [AppColors.primary, AppColors.primaryDark]),
            textColor: ready ? Colors.black : Colors.white,
            onTap: onReservation,
          ),
          const SizedBox(height: 10),
          _SecondaryTrainButton(
            label: lang.tr('Railway Site', 'রেলওয়ে সাইট'),
            icon: Icons.open_in_new_rounded,
            onTap: onRailway,
            isDark: isDark,
          ),
        ],
      );
    }

    // If credits are 0 in DB and no active reservation, user is shown ONLY the Buy Credit button
    if (credits <= 0) {
      return Column(
        children: [
          _MasterButton(
            label: 'Buy Credit',
            icon: Icons.bolt_rounded,
            gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            textColor: Colors.black,
            pulseAura: true,
            pulseCtrl: pulseCtrl,
            onTap: () => RechargeCreditDialog.show(context),
          ),
          const SizedBox(height: 10),
          Text(
            'Credit balance is 0. Please buy credit to activate auto-booking.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted(isDark),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // ── Primary Action Button ──
        if (!m.isMonitoring && ((p != null && expired) || m.lastReservationExpired)) ...[
          _MasterButton(
            label: lang.tr(
              'Retry New Search',
              'নতুন অনুসন্ধান করুন',
            ),
            icon: Icons.search_rounded,
            gradientColors: [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            pulseAura: true,
            pulseCtrl: pulseCtrl,
            onTap: () => AppShell.goTo(context, AppShell.tabSearch),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SecondaryTrainButton(
                  label: lang.tr(
                    'Re-Auto Book',
                    'পুনরায় অটো-বুক',
                  ),
                  icon: Icons.refresh_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: () async {
                    await m.reAutoBook();
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryTrainButton(
                  label: lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFEF4444),
                  onTap: onClear ?? () {},
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ] else if (p != null)
          _MasterButton(
            label: ready
                ? lang.tr('Pay Now', 'পেমেন্ট করুন')
                : (otp
                      ? lang.tr('Enter OTP', 'ওটিপি দিন')
                      : lang.tr('View Reservation', 'বুকিং দেখুন')),
            icon: ready
                ? Icons.payment_rounded
                : (otp
                      ? Icons.sms_rounded
                      : Icons.confirmation_number_outlined),
            gradientColors: ready
                ? const [Color(0xFFFBBF24), Color(0xFFD97706)]
                : (otp
                      ? const [Color(0xFF38BDF8), Color(0xFF0284C7)]
                      : [AppColors.primary, AppColors.primaryDark]),
            textColor: ready ? Colors.black : Colors.white,
            onTap: onReservation,
          )
        else if (!m.isMonitoring && m.lastReservationExpired)
          _MasterButton(
            label: lang.tr('Re-Auto Book Seats', 'পুনরায় অটো-বুক করুন'),
            icon: Icons.auto_mode_rounded,
            gradientColors: [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            onTap: () async {
              await m.reAutoBook();
            },
          )
        else if (m.needsLogin)
          _MasterButton(
            label: lang.tr('Sign In Again', 'পুনরায় সাইন ইন করুন'),
            icon: Icons.login_rounded,
            gradientColors: const [Color(0xFFFF5252), Color(0xFFD32F2F)],
            textColor: Colors.white,
            onTap: onSignIn,
          )
        else if (hasSearch) ...[
          _MasterButton(
            label: m.isMonitoring
                ? lang.tr('Pause Search', 'অনুসন্ধান বিরতি')
                : lang.tr('Resume Search', 'অনুসন্ধান চালু'),
            icon: m.isMonitoring
                ? Icons.pause_circle_filled_rounded
                : Icons.play_arrow_rounded,
            gradientColors: m.isMonitoring
                ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                : const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            textColor: m.isMonitoring ? Colors.black : Colors.white,
            pulseAura: m.isMonitoring,
            pulseCtrl: pulseCtrl,
            onTap: m.isMonitoring ? (onPause ?? () {}) : (onResume ?? () {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SecondaryTrainButton(
                  label: lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFEF4444),
                  onTap: onClear ?? () {},
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryTrainButton(
                  label: lang.tr('Railway Site', 'রেলওয়ে সাইট'),
                  icon: Icons.open_in_new_rounded,
                  onTap: onRailway,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ] else
          _MasterButton(
            label: lang.tr('Search Tickets', 'টিকেট খুঁজুন'),
            icon: Icons.search_rounded,
            gradientColors: [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            onTap: () => AppShell.goTo(context, AppShell.tabSearch),
          ),
      ],
    );
  }
}

class _MasterButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradientColors;
  final Color textColor;
  final bool pulseAura;
  final AnimationController? pulseCtrl;
  final VoidCallback onTap;

  const _MasterButton({
    required this.label,
    required this.icon,
    required this.gradientColors,
    required this.textColor,
    this.pulseAura = false,
    this.pulseCtrl,
    required this.onTap,
  });

  @override
  State<_MasterButton> createState() => _MasterButtonState();
}

class _MasterButtonState extends State<_MasterButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _pressCtrl,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 - _pressCtrl.value * 0.025,
            child: Container(
              height: 52,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: widget.gradientColors.first.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 20, color: widget.textColor),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SecondaryTrainButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _SecondaryTrainButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textPrimary(isDark);
    final effectiveIconColor = color ?? AppColors.textSecondary(isDark);
    final borderColor = color != null
        ? color!.withValues(alpha: isDark ? 0.45 : 0.35)
        : (isDark ? const Color(0xFF1E3A55) : const Color(0xFFD9E6F5));
    final bgColor = color != null
        ? color!.withValues(alpha: isDark ? 0.12 : 0.06)
        : (isDark ? const Color(0xFF0F1E33) : const Color(0xFFEFF5FC));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: effectiveIconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

// ─── Exact Error Display ─────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onVerifyTurnstile;
  final VoidCallback? onDismiss;
  final bool isDark;

  const _ErrorBanner({
    required this.message,
    this.onVerifyTurnstile,
    this.onDismiss,
    required this.isDark,
  });

  bool get _isTurnstile =>
      message.contains('422') ||
      message.toLowerCase().contains('turnstile') ||
      message.toLowerCase().contains('verification required');

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF260D12) : const Color(0xFFFFF0F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.12),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lang.tr('Booking paused', 'বুকিং স্থগিত'),
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFFB4AB) : AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          SelectableText(
            message,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 11.5,
              height: 1.3,
            ),
            maxLines: 3,
          ),
          if (_isTurnstile && onVerifyTurnstile != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onVerifyTurnstile,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.security_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lang.tr('Verify Human', 'নিরাপত্তা যাচাই'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Session Expired Overlay ──────────────────────────────────────────────────
class _ExpiredOverlay extends StatelessWidget {
  final AnimationController ctrl;
  const _ExpiredOverlay({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: ctrl,
            builder: (context, child) => Container(
              width: 82 + ctrl.value * 8,
              height: 82 + ctrl.value * 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.error.withValues(
                    alpha: 0.28 + ctrl.value * 0.22,
                  ),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.lock_reset_rounded,
                color: AppColors.error.withValues(alpha: 0.8),
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            lang.tr('Session expired', 'সেশনের মেয়াদ শেষ'),
            style: TextStyle(
              color: AppColors.textPrimary(isDark),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lang.tr(
              'Clearing cache & redirecting...',
              'ক্যাশে মুছে পুনরায় লোড হচ্ছে...',
            ),
            style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 13),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              color: AppColors.error.withValues(alpha: 0.8),
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Fancy Whole-Page Reservation Expired / Failure Alert View ───────────────
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
    final String headline = isOtpFailure
        ? lang.tr('Hold Expired — OTP Not Verified', 'সময় শেষ — ওটিপি যাচাই হয়নি')
        : (isPaymentFailure
            ? lang.tr('Hold Expired — Payment Timed Out', 'সময় শেষ — পেমেন্টের সময় শেষ')
            : lang.tr('Seat Hold Expired — Seats Released', 'আসন সংরক্ষণের মেয়াদ শেষ — আসন মুক্ত'));

    final bool isStandardReason = reason == null ||
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

    final String details = isStandardReason
        ? (isOtpFailure
            ? lang.tr(
                'Seats were reserved, but OTP was not verified within 5 minutes. Bangladesh Railway has released the held seats.',
                'রেলওয়ে সিস্টেমে আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই না হওয়ায় আসনটি ছেড়ে দেওয়া হয়েছে।',
              )
            : (isPaymentFailure
                ? lang.tr(
                    'Seats were reserved and verified, but payment was not completed within the 5-minute limit. The seats have been released.',
                    'আসন সংরক্ষিত ও ওটিপি যাচাই হয়েছিল, কিন্তু ৫ মিনিটে পেমেন্ট সম্পন্ন না হওয়ায় টিকিটটি বাতিল হয়ে গেছে।',
                  )
                : lang.tr(
                    'Seats were reserved, but OTP was not verified or payment was not completed within 5 minutes. Held seats were released by Bangladesh Railway.',
                    'রেলওয়ে সিস্টেমে আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই বা পেমেন্ট সম্পন্ন না হওয়ায় বাংলাদেশ রেলওয়ে আসনটি ছেড়ে দিয়েছে।',
                  )))
        : friendlyErrorMessage(reason, isBangla: lang.isBangla);

    final origin = fromCity?.isNotEmpty == true ? fromCity! : 'Origin';
    final destination = toCity?.isNotEmpty == true ? toCity! : 'Destination';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E0E13) : const Color(0xFFFFF1F3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.45 : 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top Route Pill & Dismiss ──
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.train_rounded,
                        size: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '$origin → $destination',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (dateOfJourney?.isNotEmpty == true) ...[
                        const SizedBox(width: 6),
                        Text('•', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
                        const SizedBox(width: 6),
                        Text(
                          dateOfJourney!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Animated Pulsing Hero Graphic ──
          Center(
            child: AnimatedBuilder(
              animation: pulseCtrl ?? const AlwaysStoppedAnimation(0.0),
              builder: (context, _) {
                final pulse = pulseCtrl?.value ?? 0.0;
                return Container(
                  width: 92 + pulse * 10,
                  height: 92 + pulse * 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08 + pulse * 0.06),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.25 + pulse * 0.2),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15 + pulse * 0.1),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFEF4444).withValues(alpha: 0.22),
                            const Color(0xFFB91C1C).withValues(alpha: 0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.timer_off_rounded,
                        size: 34,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 14),

          // ── 5-Minute Timeout Capsule Tag ──
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history_toggle_off_rounded, size: 14, color: Color(0xFFEF4444)),
                  const SizedBox(width: 5),
                  Text(
                    lang.tr('5-Minute Hold Expired', '৫ মিনিটের সময়সীমা সমাপ্ত'),
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Headline ──
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB91C1C),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 10),

          // ── Descriptive Explanation ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16090D) : const Color(0xFFFFF6F7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.25 : 0.15),
              ),
            ),
            child: Text(
              details,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Action Buttons (Fancy & Prominent) ──
          _MasterButton(
            label: lang.tr(
              'Retry New Search',
              'নতুন অনুসন্ধান করুন',
            ),
            icon: Icons.search_rounded,
            gradientColors: [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            pulseAura: true,
            pulseCtrl: pulseCtrl,
            onTap: onRetrySearch ?? () => AppShell.goTo(context, AppShell.tabSearch),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _SecondaryTrainButton(
                  label: lang.tr(
                    'Re-Auto Book',
                    'পুনরায় অটো-বুক',
                  ),
                  icon: Icons.refresh_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: onReAutoBook ?? () {},
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecondaryTrainButton(
                  label: lang.tr('Stop & Clear', 'বন্ধ ও মুছুন'),
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFEF4444),
                  onTap: onClear ?? () {},
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


