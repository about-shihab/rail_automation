import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../services/booking_service.dart';
import '../services/credit_service.dart';
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
import '../widgets/turnstile_sheet.dart';

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

  late final AnimationController _queueCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    CreditService().addListener(_onCreditChanged);
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _queueCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    if (!isTest) {
      _queueCtrl.repeat();
      _pulseCtrl.repeat(reverse: true);
    }
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  void _onCreditChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final value = await BookingService.pending();
      if (mounted) setState(() => _reservation = value);
      await _checkSession();
    } finally {
      _reading = false;
    }
  }

  bool _turnstileShowing = false;

  Future<void> _checkSession() async {
    if (_sessionExpired || !mounted) return;
    final m = context.read<MonitorService>();
    if (m.needsLogin) {
      final session = await AuthSession.load();
      if (session != null && session.isValid) {
        // Current saved session is completely valid; clear the stale error
        m.clearErrors();
        return;
      }
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
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (ctx, anim, sec) => const WebviewLoginScreen(clearSession: true),
      transitionsBuilder: (ctx, a, sec, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut), child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  @override
  void dispose() {
    CreditService().removeListener(_onCreditChanged);
    _refreshTimer?.cancel();
    _queueCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _newSearch() async {
    await context.read<MonitorService>().clearSearch();
    if (mounted) AppShell.goTo(context, AppShell.tabSearch);
  }

  void _goHome() {
    AppShell.goTo(context, AppShell.tabSearch);
  }

  Future<void> _handleSolveTurnstile() async {
    final token = await TurnstileSheet.show(context);
    if (token != null && token.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Security token captured. Retrying auto-booking...'),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.read<MonitorService>().onTurnstileSolved(token);
    }
  }

  void _showWalkthroughGuide() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF091424) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(
            top: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 28, offset: Offset(0, -6)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto-Booking & Security Guide',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'High-speed automated seat reservation system',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: isDark ? Colors.white70 : Colors.black54,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildGuideCard(
              icon: Icons.notifications_active_rounded,
              title: 'Over-The-App Security Solve',
              desc: 'When seats are detected, the Cloudflare verification popup can trigger over any app you are using so you never miss tickets.',
              color: AppColors.primary,
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _buildGuideCard(
              icon: Icons.shield_rounded,
              title: 'Silent Background Handshake',
              desc: 'We never show the raw login website to you. Only the minimal security handshake runs cleanly in the background with real-time status loading.',
              color: AppColors.accent,
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _buildGuideCard(
              icon: Icons.timer_outlined,
              title: '5-Minute Reservation Guarantee',
              desc: 'Once seats are reserved, Bangladesh Railway locks them for 5 minutes. Proceed to checkout to finalize your payment.',
              color: AppColors.gold,
              isDark: isDark,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1E33) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3A55) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSearch = m.dateOfJourney.isNotEmpty;
    final p = _reservation;
    final expiry = DateTime.tryParse('${p?['expiresAt'] ?? ''}');
    final expired = expiry != null && !expiry.isAfter(DateTime.now());
    final ready = p?['status'] == 'readyForPayment' && !expired;
    final otp = p?['status'] == 'awaitingOtp' && !expired;
    final step = _step(m, p);
    final isActive = m.isMonitoring && p == null && !m.needsLogin;
    final exactError = m.lastBookingError ?? (!m.isMonitoring ? m.lastError : null);

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
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── 1. Master Train Cockpit HUD Card ──
                        _CockpitHudCard(
                          fromCity: fromCity,
                          toCity: toCity,
                          trainName: m.targetTrain,
                          seatClass: m.targetSeatClass,
                          dateOfJourney: m.dateOfJourney,
                          step: step,
                          isActive: isActive,
                          ready: ready,
                          otp: otp,
                          credits: credit.credits,
                          remainingTime: m.isMonitoring && m.remainingFreeSeconds >= 0
                              ? m.remainingTimeFormatted
                              : null,
                          queueCtrl: _queueCtrl,
                          pulseCtrl: _pulseCtrl,
                          isDark: isDark,
                        ),

                        const SizedBox(height: 12),

                        // ── Exact Error Banner (if any) ──
                        if (exactError != null && exactError.isNotEmpty) ...[
                          _ErrorBanner(
                            message: exactError,
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
                              MaterialPageRoute(builder: (_) => const ReservationScreen()),
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
                          onToggle: m.isMonitoring
                              ? m.stopMonitoring
                              : () => m.startMonitoring(
                                  fromCity: m.fromCity,
                                  toCity: m.toCity,
                                  dateOfJourney: m.dateOfJourney,
                                  targetTrain: m.targetTrain,
                                  targetSeatClass: m.targetSeatClass,
                                  intent: m.bookingIntent,
                                ),
                          pulseCtrl: _pulseCtrl,
                          isDark: isDark,
                        ),
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

  const _TopBar({
    this.onGuide,
    required this.credits,
    required this.isMonitoring,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.appBarGradientStart,
            AppColors.appBarGradientEnd,
            Color(0xFF00A07A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Train Icon Badge
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.train_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),

              // Title and Live Status Indicator
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rail Ticket',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
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
                            color: isMonitoring ? AppColors.accent : Colors.white60,
                            boxShadow: isMonitoring
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withValues(alpha: 0.8),
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
                            isMonitoring ? 'LIVE RADAR' : 'STANDBY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
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
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                        color: credits <= 0 ? const Color(0xFFF59E0B) : AppColors.gold,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        credits <= 0 ? '0 • Buy' : '$credits',
                        style: TextStyle(
                          color: credits <= 0 ? const Color(0xFFFDE68A) : Colors.white,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.help_outline_rounded, color: Colors.white, size: 13),
                        SizedBox(width: 4),
                        Text(
                          'Guide',
                          style: TextStyle(
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
            colors: [
              Color(0xFF060D1A),
              Color(0xFF091629),
              Color(0xFF060D1A),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF0F5FF),
              Color(0xFFE4EDFC),
              Color(0xFFF0F5FF),
            ],
          );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..shader = bgGradient.createShader(Rect.fromLTWH(0, 0, s.width, s.height)),
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
            colors: [col.withValues(alpha: alpha), col.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    final glowAlpha = isDark ? 0.07 : 0.04;
    drawOrb(Offset(s.width * 0.15, s.height * 0.20), AppColors.primary, 130, glowAlpha);
    drawOrb(Offset(s.width * 0.85, s.height * 0.55), AppColors.accent, 110, glowAlpha * 0.8);
    drawOrb(Offset(s.width * 0.50, s.height * 0.06), const Color(0xFF00A07A), 160, glowAlpha * 1.2);
  }

  @override
  bool shouldRepaint(_RailwayHorizonPainter o) => o.t != t || o.isDark != isDark;
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
  final AnimationController queueCtrl;
  final AnimationController pulseCtrl;
  final bool isDark;

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
    required this.queueCtrl,
    required this.pulseCtrl,
    required this.isDark,
  });

  String get _statusTitle {
    if (credits <= 0) return 'ZERO CREDITS • RECHARGE REQUIRED';
    if (ready) return 'SEATS RESERVED • READY TO PAY';
    if (otp) return 'AWAITING OTP VERIFICATION';
    switch (step) {
      case _BookingStep.searching:
        return 'SCANNING COACH BERTH INVENTORY';
      case _BookingStep.reserving:
        return 'HOLDING SEATS • RESERVING...';
      case _BookingStep.verifying:
        return 'VERIFYING SECURITY TOKENS';
      case _BookingStep.paying:
        return 'READY FOR PAYMENT GATEWAY';
      case _BookingStep.done:
        return 'RESERVATION COMPLETE';
    }
  }

  Color get _statusColor {
    if (credits <= 0) return AppColors.warning;
    if (ready) return AppColors.gold;
    if (otp) return AppColors.warning;
    if (step == _BookingStep.reserving) return AppColors.accent;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
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
                      'DEPARTURE',
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
                              color: isDark ? AppColors.primary : AppColors.primaryDark,
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
                                      ? AppColors.primary.withValues(alpha: 0.6)
                                      : AppColors.primaryDark.withValues(alpha: 0.5))
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
                    Text(
                      'ARRIVAL',
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
                text: dateOfJourney.isEmpty ? 'Live' : dateOfJourney,
                isDark: isDark,
              ),
              _hudPill(
                icon: Icons.directions_railway_filled_rounded,
                text: trainName ?? 'All Trains',
                isDark: isDark,
              ),
              _hudPill(
                icon: (seatClass == null ||
                        seatClass == 'ALL' ||
                        seatClass == 'RANDOM')
                    ? Icons.shuffle_rounded
                    : Icons.airline_seat_recline_extra_rounded,
                text: (seatClass == null ||
                        seatClass == 'ALL' ||
                        seatClass == 'RANDOM')
                    ? 'Random (Any Class)'
                    : seatClass!,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: isDark ? const Color(0xFF1E3A55) : const Color(0xFFE2EBF5)),
          const SizedBox(height: 12),

          // ── C. Illuminated Queue / Scanner Chamber ──
          Container(
            height: 186,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF081220) : const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF173049) : const Color(0xFFD9E6F5),
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
                  message: _statusTitle,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.35 + pulseCtrl.value * 0.25),
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
                                color: _statusColor.withValues(alpha: 0.6 + pulseCtrl.value * 0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          credits <= 0
                              ? 'ZERO CREDITS • RECHARGE'
                              : (isActive ? 'ACTIVE QUEUE SEARCH' : 'SEARCH PAUSED'),
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
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
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
                            ? remainingTime!
                            : '$remainingTime remaining',
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

  Widget _hudPill({required IconData icon, required String text, required bool isDark}) {
    return Container(
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
          Icon(icon, size: 12, color: isDark ? AppColors.primary : AppColors.primaryDark),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(isDark),
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
    final stages = [
      (Icons.radar_rounded, 'Scanning', step == _BookingStep.searching && p == null, p != null || step.index > _BookingStep.searching.index),
      (Icons.event_seat_rounded, 'Booking', step == _BookingStep.reserving, step.index > _BookingStep.reserving.index || ready || otp),
      (Icons.shield_outlined, 'Verifying', step == _BookingStep.verifying || otp, ready),
      (Icons.credit_card_rounded, 'Paying', step == _BookingStep.paying || ready, false),
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
                  'RESERVATION LINE STATUS',
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
                      _CoachCoupler(
                        done: done,
                        active: active,
                        isDark: isDark,
                      ),
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
          cardBg = primaryColor.withValues(alpha: 0.12 + pulseCtrl.value * 0.08);
          borderColor = primaryColor.withValues(alpha: 0.5 + pulseCtrl.value * 0.4);
          iconColor = primaryColor;
        } else {
          cardBg = isDark ? const Color(0xFF0F1E33) : const Color(0xFFF3F7FC);
          borderColor = isDark ? const Color(0xFF1E3A55) : const Color(0xFFD9E6F5);
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
                border: Border.all(color: borderColor, width: active ? 1.5 : 1.0),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.18 + pulseCtrl.value * 0.15),
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
                fontWeight: (done || active) ? FontWeight.w700 : FontWeight.w500,
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
  const _CoachCoupler({required this.done, required this.active, required this.isDark});

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

// ─── Train Master Action Controls ────────────────────────────────────────────
class _TrainActionButtons extends StatelessWidget {
  final MonitorService m;
  final Map<String, dynamic>? p;
  final bool ready, otp, expired, hasSearch;
  final int credits;
  final VoidCallback onReservation, onRailway, onSignIn, onToggle;
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
    required this.onToggle,
    required this.pulseCtrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // If credits are 0 in DB, user is shown ONLY the Buy Credit button
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
            p != null
                ? 'Credit balance is 0. Buy credit to confirm your booked ticket.'
                : 'Credit balance is 0. Please buy credit to activate auto-booking.',
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
        if (p != null && expired)
          _MasterButton(
            label: 'Timeout • Re-Auto Book',
            icon: Icons.refresh_rounded,
            gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            textColor: Colors.black,
            onTap: () async {
              await m.reAutoBook();
            },
          )
        else if (p != null)
          _MasterButton(
            label: ready ? 'Pay Now' : (otp ? 'Enter OTP' : 'View Reservation'),
            icon: ready
                ? Icons.payment_rounded
                : (otp ? Icons.sms_rounded : Icons.confirmation_number_outlined),
            gradientColors: ready
                ? const [Color(0xFFFBBF24), Color(0xFFD97706)]
                : (otp
                    ? const [Color(0xFF38BDF8), Color(0xFF0284C7)]
                    : [AppColors.primary, AppColors.primaryDark]),
            textColor: ready ? Colors.black : Colors.white,
            onTap: onReservation,
          )
        else if (m.lastReservationExpired)
          _MasterButton(
            label: 'Re-Auto Book Seats',
            icon: Icons.auto_mode_rounded,
            gradientColors: [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            onTap: () async {
              await m.reAutoBook();
            },
          )
        else if (m.needsLogin)
          _MasterButton(
            label: 'Sign In Again',
            icon: Icons.login_rounded,
            gradientColors: const [Color(0xFFFF5252), Color(0xFFD32F2F)],
            textColor: Colors.white,
            onTap: onSignIn,
          )
        else if (hasSearch)
          _MasterButton(
            label: m.isMonitoring ? 'Stop Search' : 'Resume Search',
            icon: m.isMonitoring ? Icons.stop_rounded : Icons.play_arrow_rounded,
            gradientColors: m.isMonitoring
                ? [AppColors.primary, AppColors.primaryDark]
                : const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            textColor: Colors.black,
            pulseAura: m.isMonitoring,
            pulseCtrl: pulseCtrl,
            onTap: onToggle,
          )
        else
          _MasterButton(
            label: 'Search Tickets',
            icon: Icons.search_rounded,
            gradientColors: [AppColors.primary, AppColors.primaryDark],
            textColor: Colors.black,
            onTap: () => AppShell.goTo(context, AppShell.tabSearch),
          ),

        // ── Secondary Action Button ──
        if (hasSearch && p == null && !m.needsLogin) ...[
          const SizedBox(height: 10),
          _SecondaryTrainButton(
            label: 'Railway Site',
            icon: Icons.open_in_new_rounded,
            onTap: onRailway,
            isDark: isDark,
          ),
        ],
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

  const _SecondaryTrainButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F1E33) : const Color(0xFFEFF5FC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF1E3A55) : const Color(0xFFD9E6F5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary(isDark)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Auto-Booking Error (Exact):',
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.security_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Solve Cloudflare Security',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                  color: AppColors.error.withValues(alpha: 0.28 + ctrl.value * 0.22),
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
            'Session expired',
            style: TextStyle(
              color: AppColors.textPrimary(isDark),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Clearing cache & redirecting...',
            style: TextStyle(
              color: AppColors.textMuted(isDark),
              fontSize: 13,
            ),
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
