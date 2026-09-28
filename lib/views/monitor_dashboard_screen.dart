import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../services/booking_service.dart';
import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import '../services/secure_store.dart';
import '../services/web_session_service.dart';
import '../utils/app_theme.dart';
import 'booking_screen.dart';
import 'reservation_screen.dart';
import 'search_screen.dart';
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

    if (m.needsTurnstile && !_turnstileShowing && !TurnstileSheet.isShowing) {
      _triggerAutoTurnstile();
    }
  }

  void _triggerAutoTurnstile() {
    if (_turnstileShowing || TurnstileSheet.isShowing || !mounted) return;
    _turnstileShowing = true;
    _handleSolveTurnstile().whenComplete(() {
      _turnstileShowing = false;
    });
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
    _refreshTimer?.cancel();
    _queueCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _newSearch() async {
    await context.read<MonitorService>().clearSearch();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _goHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
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
      context.read<MonitorService>().clearBookingError();
      await context.read<MonitorService>().checkNow();
    }
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

    if (m.needsTurnstile && !_turnstileShowing && !TurnstileSheet.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && m.needsTurnstile && !_turnstileShowing && !TurnstileSheet.isShowing) {
          _triggerAutoTurnstile();
        }
      });
    }

    if (_sessionExpired) {
      return Scaffold(
        backgroundColor: AppColors.darkBg,
        body: _ExpiredOverlay(ctrl: _pulseCtrl),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFF050E1C),
      extendBodyBehindAppBar: true,
      appBar: _TopBar(onNew: _newSearch),
      body: Stack(children: [
        Positioned.fill(child: _BgCanvas(ctrl: _queueCtrl)),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final centerH = (h * 0.54).clamp(180.0, 420.0);
              final stepsH = (h * 0.20).clamp(70.0, 150.0);
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: h),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 6),
                      ClipRect(
                        child: SizedBox(
                          height: centerH,
                          child: _CenterAnim(
                            qCtrl: _queueCtrl,
                            pCtrl: _pulseCtrl,
                            step: step,
                            isActive: isActive,
                            from: m.fromCity,
                            to: m.toCity,
                            ready: ready,
                            otp: otp,
                            errorMessage: exactError,
                            onVerifyTurnstile: _handleSolveTurnstile,
                            onDismissError: () => m.clearBookingError(),
                          ),
                        ),
                      ),
                      ClipRect(
                        child: SizedBox(
                          height: stepsH,
                          child: _Steps(step: step, p: p, ready: ready, otp: otp, ctrl: _pulseCtrl),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: _Buttons(
                          m: m,
                          p: p,
                          ready: ready,
                          otp: otp,
                          expired: expired,
                          hasSearch: hasSearch,
                          onHome: _goHome,
                          onReservation: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReservationScreen()));
                            await _refresh();
                          },
                          onRailway: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => BookingScreen(url: NotificationService.bookingUrl(
                              m.fromCity, m.toCity, m.dateOfJourney, m.targetSeatClass ?? 'SNIGDHA',
                            )),
                          )),
                          onSignIn: _doSessionExpiry,
                          onToggle: m.isMonitoring
                              ? m.stopMonitoring
                              : () => m.startMonitoring(
                                  fromCity: m.fromCity, toCity: m.toCity,
                                  dateOfJourney: m.dateOfJourney, targetTrain: m.targetTrain,
                                  targetSeatClass: m.targetSeatClass, intent: m.bookingIntent),
                        ),
                      ),
                      if (m.isMonitoring && m.remainingFreeSeconds >= 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (context, child) => Text(
                              m.remainingTimeFormatted,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.38 + _pulseCtrl.value * 0.22), fontSize: 11, letterSpacing: 0.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onNew;
  const _TopBar({required this.onNew});
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: Colors.transparent, elevation: 0,
    leading: const SizedBox.shrink(), centerTitle: false,
    title: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.train_rounded, color: AppColors.primary, size: 16),
        ),
        const SizedBox(width: 8),
        const Flexible(
          child: Text(
            'Rail Ticket',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    actions: [
      GestureDetector(
        onTap: onNew,
        child: Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white70, size: 14),
            SizedBox(width: 4),
            Text('New', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ],
  );
}

// ─── Animated Background Canvas ───────────────────────────────────────────────
class _BgCanvas extends StatelessWidget {
  final AnimationController ctrl;
  const _BgCanvas({required this.ctrl});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ctrl,
    builder: (context, child) => CustomPaint(painter: _BgPainter(t: ctrl.value)),
  );
}

class _BgPainter extends CustomPainter {
  final double t;
  _BgPainter({required this.t});
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF050E1C), Color(0xFF060D18), Color(0xFF030A14)],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));

    // Moving tracks
    final tp = Paint()..color = AppColors.primary.withValues(alpha: 0.07)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    const dl = 24.0; const gl = 16.0; const tl = dl + gl;
    final off = t * tl;
    final lx = s.width * 0.35; final rx = s.width * 0.65;
    for (double y = -tl + off; y < s.height + tl; y += tl) {
      canvas.drawLine(Offset(lx, y), Offset(lx, y + dl), tp);
      canvas.drawLine(Offset(rx, y), Offset(rx, y + dl), tp);
    }
    final cp = Paint()..color = AppColors.primary.withValues(alpha: 0.04)..strokeWidth = 1..style = PaintingStyle.stroke;
    for (double y = -32 + off * 0.5; y < s.height + 32; y += 32) {
      canvas.drawLine(Offset(lx - 10, y), Offset(rx + 10, y), cp);
    }
    // Orbs
    void orb(Offset c, Color col, double r, double a) => canvas.drawCircle(c, r,
      Paint()..shader = RadialGradient(colors: [col.withValues(alpha: a), col.withValues(alpha: 0)])
        .createShader(Rect.fromCircle(center: c, radius: r)));
    orb(Offset(s.width * 0.18, s.height * 0.22), const Color(0xFF00C896), 110, 0.06);
    orb(Offset(s.width * 0.82, s.height * 0.58), const Color(0xFF3DEFE9), 85, 0.04);
    orb(Offset(s.width * 0.5, s.height * 0.08), const Color(0xFF005A3F), 160, 0.07);
  }
  @override
  bool shouldRepaint(_BgPainter o) => o.t != t;
}

// ─── Center Animation ─────────────────────────────────────────────────────────
// ─── Center Animation ─────────────────────────────────────────────────────────
class _CenterAnim extends StatelessWidget {
  final AnimationController qCtrl, pCtrl;
  final _BookingStep step;
  final bool isActive, ready, otp;
  final String from, to;
  final String? errorMessage;
  final VoidCallback? onVerifyTurnstile;
  final VoidCallback? onDismissError;

  const _CenterAnim({
    required this.qCtrl,
    required this.pCtrl,
    required this.step,
    required this.isActive,
    required this.from,
    required this.to,
    required this.ready,
    required this.otp,
    this.errorMessage,
    this.onVerifyTurnstile,
    this.onDismissError,
  });

  IconData get _icon {
    if (ready) return Icons.confirmation_number_rounded;
    if (otp) return Icons.sms_rounded;
    switch (step) {
      case _BookingStep.searching: return Icons.manage_search_rounded;
      case _BookingStep.reserving: return Icons.event_seat_rounded;
      case _BookingStep.verifying: return Icons.chat_bubble_outline_rounded;
      case _BookingStep.paying: return Icons.credit_card_rounded;
      case _BookingStep.done: return Icons.check_circle_rounded;
    }
  }

  String get _label {
    if (ready) return 'READY TO PAY';
    if (otp) return 'AWAITING OTP';
    switch (step) {
      case _BookingStep.searching: return 'SCANNING SEATS';
      case _BookingStep.reserving: return 'RESERVING SEAT';
      case _BookingStep.verifying: return 'VERIFYING OTP';
      case _BookingStep.paying: return 'CONFIRM PAYMENT';
      case _BookingStep.done: return 'COMPLETE';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showQueue = isActive && !ready && !otp;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (showQueue) ...[
        SizedBox(
          height: 156,
          child: FancyTrainLoader(
            message: step == _BookingStep.reserving
                ? 'HOLDING SEATS • RESERVING...'
                : 'WAITING IN QUEUE • LOOKING FOR TICKET',
            height: 156,
            showCard: false,
          ),
        ),
        const SizedBox(height: 8),
      ] else ...[
        AnimatedBuilder(
          animation: Listenable.merge([pCtrl, qCtrl]),
          builder: (context, child) {
            final pulse = pCtrl.value;
            return Transform.scale(
              scale: isActive ? (0.97 + pulse * 0.055) : 1.0,
              child: Stack(alignment: Alignment.center, children: [
                if (isActive) ...[
                  Container(width: 140 + pulse * 14, height: 140 + pulse * 14,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: (ready ? AppColors.gold : AppColors.primary).withValues(alpha: 0.04 + pulse * 0.04), width: 1))),
                  Container(width: 116 + pulse * 10, height: 116 + pulse * 10,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: (ready ? AppColors.gold : AppColors.primary).withValues(alpha: 0.08 + pulse * 0.08), width: 1.5))),
                ],
                Container(width: 90, height: 90,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      ready ? AppColors.gold.withValues(alpha: 0.25) : AppColors.primary.withValues(alpha: 0.22 + pulse * 0.12),
                      ready ? AppColors.gold.withValues(alpha: 0.08) : AppColors.primaryDark.withValues(alpha: 0.06),
                    ]),
                    border: Border.all(
                      color: ready ? AppColors.gold : AppColors.primary.withValues(alpha: 0.35 + pulse * 0.25),
                      width: 1.5,
                    ),
                    boxShadow: [BoxShadow(
                      color: (ready ? AppColors.gold : AppColors.primary).withValues(alpha: 0.14 + pulse * 0.14),
                      blurRadius: 20 + pulse * 16, spreadRadius: 2,
                    )]),
                  child: Icon(_icon, color: ready ? AppColors.gold : AppColors.primary, size: 38)),
              ]),
            );
          },
        ),
        const SizedBox(height: 14),
      ],

      // Route pill with animated dots
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(from.isEmpty ? 'From' : from, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedBuilder(
              animation: qCtrl,
              builder: (context, child) => Row(mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final a = ((qCtrl.value - i / 3.0) % 1.0 + 1.0) % 1.0;
                  return Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(width: 4, height: 4, decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: (0.12 + a * 0.88).clamp(0.0, 1.0)),
                    )));
                })),
            ),
          ),
          Text(to.isEmpty ? 'To' : to, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),

      if (!showQueue) ...[
        const SizedBox(height: 12),
        // Pulsing label
        AnimatedBuilder(
          animation: pCtrl,
          builder: (context, child) => Text(_label, style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42 + pCtrl.value * 0.38),
            fontSize: 11, letterSpacing: 2.0, fontWeight: FontWeight.w600,
          )),
        ),
      ],

      // Exact Error Notice
      if (errorMessage != null && errorMessage!.isNotEmpty) ...[
        const SizedBox(height: 10),
        _ErrorBanner(
          message: errorMessage!,
          onVerifyTurnstile: onVerifyTurnstile,
          onDismiss: onDismissError,
        ),
      ],
    ]);
  }
}

// ─── Exact Error Display ─────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onVerifyTurnstile;
  final VoidCallback? onDismiss;

  const _ErrorBanner({
    required this.message,
    this.onVerifyTurnstile,
    this.onDismiss,
  });

  bool get _isTurnstile =>
      message.contains('422') ||
      message.toLowerCase().contains('turnstile') ||
      message.toLowerCase().contains('verification required');

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF260D12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.12),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 15),
            const SizedBox(width: 5),
            const Expanded(
              child: Text('Auto-Booking Error (Exact):',
                style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ),
            if (onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          SelectableText(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.3),
            maxLines: 3,
          ),
          if (_isTurnstile && onVerifyTurnstile != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onVerifyTurnstile,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.security_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 5),
                  Text('Solve Cloudflare Security', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Step Indicators ─────────────────────────────────────────────────────────
class _Steps extends StatelessWidget {
  final _BookingStep step;
  final Map<String, dynamic>? p;
  final bool ready, otp;
  final AnimationController ctrl;
  const _Steps({required this.step, required this.p, required this.ready, required this.otp, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.search_rounded, 'Scanning',
          step == _BookingStep.searching && p == null,
          p != null || step.index > _BookingStep.searching.index),
      (Icons.event_seat_rounded, 'Booking',
          step == _BookingStep.reserving,
          step.index > _BookingStep.reserving.index || ready || otp),
      (Icons.chat_bubble_outline_rounded, 'Verifying',
          step == _BookingStep.verifying || otp,
          ready),
      (Icons.credit_card_rounded, 'Paying',
          step == _BookingStep.paying || ready,
          false),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final i = e.key;
          final (icon, label, active, done) = e.value;
          return Expanded(child: Row(children: [
            Expanded(child: _StepDot(icon: icon, label: label, active: active, done: done, ctrl: ctrl)),
            if (i < steps.length - 1) _StepLine(done: done, active: active),
          ]));
        }).toList(),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active, done;
  final AnimationController ctrl;
  const _StepDot({required this.icon, required this.label, required this.active, required this.done, required this.ctrl});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ctrl,
    builder: (context, child) {
      final Color bg, border, ic;
      if (done) { bg = AppColors.primary.withValues(alpha: 0.15); border = AppColors.primary.withValues(alpha: 0.45); ic = AppColors.primary; }
      else if (active) { bg = AppColors.primary.withValues(alpha: 0.09 + ctrl.value * 0.09); border = AppColors.primary.withValues(alpha: 0.28 + ctrl.value * 0.32); ic = AppColors.primary; }
      else { bg = Colors.white.withValues(alpha: 0.04); border = Colors.white.withValues(alpha: 0.08); ic = Colors.white.withValues(alpha: 0.2); }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(duration: const Duration(milliseconds: 300),
          width: 42, height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg,
            border: Border.all(color: border, width: 1.5),
            boxShadow: active ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.09 + ctrl.value * 0.16), blurRadius: 14, spreadRadius: 2)] : null),
          child: done ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 18) : Icon(icon, color: ic, size: 18)),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(
          color: (done || active) ? Colors.white.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.2),
          fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      ]);
    },
  );
}

class _StepLine extends StatelessWidget {
  final bool done, active;
  const _StepLine({required this.done, required this.active});
  @override
  Widget build(BuildContext context) => Container(
    width: 16, height: 1.5,
    margin: const EdgeInsets.only(bottom: 22),
    decoration: BoxDecoration(gradient: LinearGradient(colors: done
        ? [AppColors.primary, AppColors.primary]
        : active
        ? [AppColors.primary, Colors.white.withValues(alpha: 0.07)]
        : [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0.07)])),
  );
}

// ─── Action Buttons ───────────────────────────────────────────────────────────
class _Buttons extends StatelessWidget {
  final MonitorService m;
  final Map<String, dynamic>? p;
  final bool ready, otp, expired, hasSearch;
  final VoidCallback onHome, onReservation, onRailway, onSignIn, onToggle;
  const _Buttons({
    required this.m, required this.p,
    required this.ready, required this.otp,
    required this.expired, required this.hasSearch,
    required this.onHome, required this.onReservation,
    required this.onRailway, required this.onSignIn, required this.onToggle,
  });
  @override
  Widget build(BuildContext context) => Column(children: [
    if (p != null)
      _PrimaryBtn(label: ready ? 'Pay Now' : otp ? 'Enter OTP' : 'View Reservation',
        icon: ready ? Icons.payment_rounded : otp ? Icons.sms_rounded : Icons.confirmation_number_outlined,
        gold: ready, onTap: onReservation)
    else if (m.needsLogin)
      _PrimaryBtn(label: 'Sign In Again', icon: Icons.login_rounded, gold: false, onTap: onSignIn)
    else if (hasSearch)
      _PrimaryBtn(
        label: m.isMonitoring ? 'Stop Search' : 'Resume Search',
        icon: m.isMonitoring ? Icons.stop_rounded : Icons.play_arrow_rounded,
        gold: false, filled: true, onTap: onToggle)
    else
      _PrimaryBtn(label: 'Search Tickets', icon: Icons.search_rounded, gold: false, onTap: onHome),
    const SizedBox(height: 8),
    Row(children: [
      if (hasSearch && p == null && !m.needsLogin) ...[
        Expanded(child: _SecBtn(label: 'Railway Site', icon: Icons.open_in_new_rounded, onTap: onRailway)),
        const SizedBox(width: 8),
      ],
      Expanded(child: _SecBtn(label: 'Home', icon: Icons.home_rounded, onTap: onHome)),
    ]),
  ]);
}

class _PrimaryBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool gold;
  final bool filled;
  final VoidCallback onTap;
  const _PrimaryBtn({required this.label, required this.icon, required this.gold, this.filled = true, required this.onTap});
  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _a;
  @override
  void initState() { super.initState(); _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); }
  @override
  void dispose() { _a.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final col = widget.gold ? AppColors.gold : AppColors.primary;
    return GestureDetector(
      onTapDown: (_) => _a.forward(),
      onTapUp: (_) { _a.reverse(); widget.onTap(); },
      onTapCancel: () => _a.reverse(),
      child: AnimatedBuilder(animation: _a, builder: (context, child) => Transform.scale(
        scale: 1.0 - _a.value * 0.025,
        child: Container(
          width: double.infinity, height: 52,
          decoration: BoxDecoration(
            gradient: widget.filled ? LinearGradient(colors: widget.gold
              ? [const Color(0xFFFBBF24), const Color(0xFFD97706)]
              : [AppColors.primary, AppColors.primaryDark]) : null,
            color: widget.filled ? null : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.filled ? Colors.transparent : col.withValues(alpha: 0.25), width: 1.5),
            boxShadow: widget.filled ? [BoxShadow(
              color: col.withValues(alpha: 0.28 - _a.value * 0.12),
              blurRadius: 16 - _a.value * 8, spreadRadius: 1, offset: const Offset(0, 4))] : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon, size: 18, color: widget.filled ? Colors.black87 : Colors.white70),
            const SizedBox(width: 8),
            Text(widget.label, style: TextStyle(
              color: widget.filled ? Colors.black87 : Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.2)),
          ]),
        ),
      )),
    );
  }
}

class _SecBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SecBtn({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.38)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ─── Session Expired Overlay ──────────────────────────────────────────────────
class _ExpiredOverlay extends StatelessWidget {
  final AnimationController ctrl;
  const _ExpiredOverlay({required this.ctrl});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    AnimatedBuilder(animation: ctrl, builder: (context, child) => Container(
      width: 82 + ctrl.value * 8, height: 82 + ctrl.value * 8,
      decoration: BoxDecoration(shape: BoxShape.circle,
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.28 + ctrl.value * 0.22), width: 1.5)),
      child: Icon(Icons.lock_reset_rounded, color: AppColors.error.withValues(alpha: 0.8), size: 34))),
    const SizedBox(height: 20),
    const Text('Session expired', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 8),
    Text('Clearing cache & redirecting...', style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 13)),
    const SizedBox(height: 28),
    SizedBox(width: 180, child: LinearProgressIndicator(
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      color: AppColors.error.withValues(alpha: 0.6), minHeight: 2)),
  ]));
}
