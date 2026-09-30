import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';

/// Professional, state-of-the-art animated loader depicting a user waiting in a queue looking for tickets.
/// Features an illuminated Bangladesh Railway smart counter, queuing passengers with detailed silhouettes,
/// the radiant "YOU" indicator, a floating holographic VIP ticket with active dual-beam laser berth scanner,
/// perspective floor grid, and dynamic queue progress tracking.
class FancyTrainLoader extends StatefulWidget {
  final String? message;
  final String? subMessage;
  final double height;
  final bool showCard;

  const FancyTrainLoader({
    super.key,
    this.message,
    this.subMessage,
    this.height = 200,
    this.showCard = false,
  });

  @override
  State<FancyTrainLoader> createState() => _FancyTrainLoaderState();
}

class _FancyTrainLoaderState extends State<FancyTrainLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _statusCycleIndex = 0;

  static const List<String> _defaultStatusCycles = [
    'Standing in reservation queue...',
    'Scanning coach berth inventory...',
    'Searching Bangladesh Railway servers...',
    'Checking real-time seat availability...',
    'Preparing auto-reservation queue token...',
  ];

  @override
  void initState() {
    super.initState();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (!isTest) {
      _controller.repeat();
    }

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || _controller.value > 0.98) {
        if (mounted) {
          setState(() {
            _statusCycleIndex = (_statusCycleIndex + 1) % _defaultStatusCycles.length;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.of(context, listen: false);
    final primaryMsg = widget.message ?? lang.t('loading_tickets');
    final secondaryMsg = widget.subMessage ?? _defaultStatusCycles[_statusCycleIndex];

    final painterHeight = (widget.height * 0.68).clamp(96.0, 150.0);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── 1. The Queue & Holographic Scanner Canvas ──
        SizedBox(
          height: painterHeight,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _QueueTicketPainter(
                  progress: _controller.value,
                  isDark: isDark,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 6),

        // ── 2. Dynamic Status & Queue Pipeline Tracker ──
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final alpha = (0.80 + 0.20 * math.sin(_controller.value * 2 * math.pi)).clamp(0.6, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: alpha,
                  child: Text(
                    primaryMsg,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  child: Text(
                    secondaryMsg,
                    key: ValueKey<String>(secondaryMsg),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                // Modern 3-stage queue pipeline indicator
                _QueuePipelineBar(progress: _controller.value, isDark: isDark),
              ],
            );
          },
        ),
      ],
    );

    if (!widget.showCard) {
      return Center(child: content);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF071220).withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? const Color(0xFF00D59B).withValues(alpha: 0.30)
                : const Color(0xFF00D59B).withValues(alpha: 0.38),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D59B).withValues(alpha: isDark ? 0.16 : 0.08),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
            if (isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: content,
      ),
    );
  }
}

/// Sleek 3-stage queue pipeline tracker showing Queue Position -> Berth Scan -> Auto Hold.
class _QueuePipelineBar extends StatelessWidget {
  final double progress;
  final bool isDark;

  const _QueuePipelineBar({required this.progress, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF00D59B);
    final inactiveColor = isDark ? const Color(0xFF1E3A55) : const Color(0xFFCBDCF0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stage 1: Queue Position (Active/Checked)
        _buildDot(active: true, activeColor: activeColor, inactiveColor: inactiveColor),
        _buildLine(active: true, activeColor: activeColor, inactiveColor: inactiveColor),
        // Stage 2: Scanning Berths (Pulsing)
        _buildDot(
          active: true,
          pulsing: true,
          progress: progress,
          activeColor: const Color(0xFF00F0FF),
          inactiveColor: inactiveColor,
        ),
        _buildLine(
          active: progress > 0.5,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
        // Stage 3: Auto-Hold Ready
        _buildDot(
          active: progress > 0.85,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        ),
      ],
    );
  }

  Widget _buildDot({
    required bool active,
    bool pulsing = false,
    double progress = 0.0,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final size = pulsing ? (6.0 + 1.5 * math.sin(progress * 2 * math.pi)) : 6.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? activeColor : inactiveColor,
        boxShadow: active
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: pulsing ? 0.8 : 0.4),
                  blurRadius: pulsing ? 6 : 3,
                )
              ]
            : null,
      ),
    );
  }

  Widget _buildLine({
    required bool active,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return Container(
      width: 28,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.6) : inactiveColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Custom painter rendering a stunning futuristic queue waiting scene:
/// Perspective floor grid, glowing stanchions, velvet cord, queuing passenger silhouettes,
/// radiant "YOU" user avatar with floating badge, Bangladesh Railway smart kiosk,
/// floating VIP train ticket with active dual-laser scan & radar sonar waves.
class _QueueTicketPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _QueueTicketPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final floorY = h * 0.78;

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Ambient Background & Perspective Horizon Grid
    // ─────────────────────────────────────────────────────────────────────────
    final bgGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.45, -0.2),
        radius: 0.95,
        colors: [
          (isDark ? const Color(0xFF00D59B) : const Color(0xFF10B981))
              .withValues(alpha: isDark ? 0.18 : 0.10),
          (isDark ? const Color(0xFF00F0FF) : const Color(0xFF0EA5E9))
              .withValues(alpha: isDark ? 0.08 : 0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgGlow);

    // Floor surface gradient
    final floorRect = Rect.fromLTWH(0, floorY, w, h - floorY);
    final floorSurfacePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFF0A192D), const Color(0xFF050D18)]
            : [const Color(0xFFE2EAF4), const Color(0xFFD0DFEF)],
      ).createShader(floorRect);
    canvas.drawRect(floorRect, floorSurfacePaint);

    // Perspective floor lines running toward vanishing point at right
    final gridLinePaint = Paint()
      ..color = (isDark ? const Color(0xFF00F0FF) : const Color(0xFF0284C7))
          .withValues(alpha: isDark ? 0.12 : 0.08)
      ..strokeWidth = 0.8;

    final vpX = w * 0.85;
    final vpY = floorY - 30;
    for (int i = 0; i < 6; i++) {
      final startX = w * (i * 0.16);
      canvas.drawLine(Offset(startX, h), Offset(vpX, vpY), gridLinePaint);
    }

    // Main floor horizon line with cyan neon edge
    final horizonPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          (isDark ? const Color(0xFF00D59B) : const Color(0xFF059669)).withValues(alpha: 0.7),
          (isDark ? const Color(0xFF00F0FF) : const Color(0xFF0284C7)).withValues(alpha: 0.9),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, floorY, w, 2))
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(0, floorY), Offset(w, floorY), horizonPaint);

    // Flowing queue lane chevron arrows along floor (> > >)
    final chevronPaint = Paint()
      ..color = (isDark ? const Color(0xFF00D59B) : const Color(0xFF059669))
          .withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final chevronOffset = (progress * 28.0) % 28.0;
    for (double cx = w * 0.08 + chevronOffset; cx < w * 0.70; cx += 28.0) {
      final cPath = Path()
        ..moveTo(cx - 3, floorY + 4)
        ..lineTo(cx, floorY + 6.5)
        ..lineTo(cx - 3, floorY + 9);
      canvas.drawPath(cPath, chevronPaint);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Queue Floor Spots & Guidance Stanchions
    // ─────────────────────────────────────────────────────────────────────────
    final posPads = [w * 0.14, w * 0.33, w * 0.52];
    for (int i = 0; i < posPads.length; i++) {
      final px = posPads[i];
      final isUserSpot = (i == 2);

      if (isUserSpot) {
        // User spot: Glowing concentric holographic radar pads
        final userRingAlpha = (0.5 + 0.4 * math.sin(progress * 4 * math.pi)).clamp(0.2, 1.0);
        final userSpotPaint = Paint()
          ..color = const Color(0xFF00D59B).withValues(alpha: userRingAlpha * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, floorY + 5), width: 34, height: 10),
          userSpotPaint,
        );

        // Inner glowing fill
        final innerGlow = Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF00D59B).withValues(alpha: 0.25),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCenter(center: Offset(px, floorY + 5), width: 32, height: 10));
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, floorY + 5), width: 32, height: 10),
          innerGlow,
        );
      } else {
        // Waiting spot ellipse
        final spotPaint = Paint()
          ..color = (isDark ? const Color(0xFF1E3A55) : const Color(0xFFCBDCF0))
              .withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, floorY + 5), width: 26, height: 8),
          spotPaint,
        );
      }
    }

    // Stanchions (Posts & Velvet Rope)
    _drawStanchionsAndRope(canvas, w, floorY);

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Bangladesh Railway Smart Kiosk / Counter (Right Side)
    // ─────────────────────────────────────────────────────────────────────────
    final kioskLeft = w * 0.74;
    final kioskRight = w * 0.96;
    final kioskTop = h * 0.12;
    _drawSmartKiosk(canvas, kioskLeft, kioskRight, kioskTop, floorY);

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Queuing Passengers
    // ─────────────────────────────────────────────────────────────────────────
    final wave = math.sin(progress * 2 * math.pi);
    final stepBob = (math.sin(progress * 4 * math.pi)).abs() * 2.2;

    // --- Passenger 3 (Rear, position ~ w * 0.14) ---
    _drawStylizedPassenger(
      canvas: canvas,
      x: w * 0.14 + (wave * 1.2),
      floorY: floorY,
      height: 38.0,
      width: 13.0,
      color: isDark ? const Color(0xFF475569) : const Color(0xFF64748B),
      isUser: false,
      hasBackpack: true,
      hasHeadphones: true,
      bob: stepBob * 0.3,
    );

    // --- Passenger 2 (Middle, position ~ w * 0.33) ---
    _drawStylizedPassenger(
      canvas: canvas,
      x: w * 0.33 + (wave * 1.6),
      floorY: floorY,
      height: 41.0,
      width: 14.0,
      color: isDark ? const Color(0xFF38BDF8).withValues(alpha: 0.85) : const Color(0xFF0284C7),
      isUser: false,
      hasSuitcase: true,
      bob: stepBob * 0.6,
    );

    // --- Passenger 1: THE USER ("YOU", at counter position ~ w * 0.52) ---
    final userX = w * 0.52 + (wave * 0.8);
    _drawStylizedPassenger(
      canvas: canvas,
      x: userX,
      floorY: floorY,
      height: 44.0,
      width: 15.0,
      color: const Color(0xFF00D59B),
      isUser: true,
      bob: stepBob,
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Floating Holographic VIP Ticket & Active Dual-Laser Berth Scanner
    // ─────────────────────────────────────────────────────────────────────────
    final ticketX = w * 0.65;
    final ticketHover = math.sin(progress * 2 * math.pi) * 3.5;
    final ticketY = h * 0.38 + ticketHover;
    _drawHolographicTicketAndScanner(canvas, ticketX, ticketY, kioskLeft, kioskTop);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper: Stanchions & Velvet Catenary Guide Rope
  // ───────────────────────────────────────────────────────────────────────────
  void _drawStanchionsAndRope(Canvas canvas, double w, double floorY) {
    final postColor = const Color(0xFFF59E0B);
    final postGlow = const Color(0xFFFDE68A);

    void drawPost(double px) {
      // Base
      final baseRect = Rect.fromCenter(center: Offset(px, floorY), width: 10, height: 4);
      canvas.drawOval(baseRect, Paint()..color = postColor);

      // Shaft
      final shaftRect = Rect.fromLTWH(px - 1.5, floorY - 26, 3, 26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(shaftRect, const Radius.circular(1.5)),
        Paint()
          ..shader = LinearGradient(
            colors: [postGlow, postColor, const Color(0xFF92400E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(shaftRect),
      );

      // Finial Ball
      canvas.drawCircle(Offset(px, floorY - 27), 3.0, Paint()..color = postGlow);
      // Neon collar ring
      canvas.drawCircle(
        Offset(px, floorY - 24),
        1.6,
        Paint()..color = const Color(0xFF00F0FF),
      );
    }

    final post1X = w * 0.05;
    final post2X = w * 0.69;
    drawPost(post1X);
    drawPost(post2X);

    // Velvet Catenary Rope
    final ropePath = Path()
      ..moveTo(post1X, floorY - 22)
      ..quadraticBezierTo(w * 0.37, floorY - 12 + math.sin(progress * 2 * math.pi) * 1.5, post2X, floorY - 22);

    // Rope ambient glow
    canvas.drawPath(
      ropePath,
      Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Rope core
    canvas.drawPath(
      ropePath,
      Paint()
        ..color = const Color(0xFFD97706)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper: Bangladesh Railway Smart Kiosk / Counter
  // ───────────────────────────────────────────────────────────────────────────
  void _drawSmartKiosk(
      Canvas canvas, double left, double right, double top, double floorY) {
    final width = right - left;
    final height = floorY - top;

    final kioskRect = Rect.fromLTWH(left, top, width, height);

    // Kiosk Body Outer Shell
    final shellPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF132238), const Color(0xFF091424)]
            : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
      ).createShader(kioskRect);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        kioskRect,
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
      ),
      shellPaint,
    );

    // Kiosk Outer Neon Border
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        kioskRect,
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
      ),
      Paint()
        ..color = (isDark ? const Color(0xFF00D59B) : const Color(0xFF059669))
            .withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Canopy Roof with Bangladesh Railway Emerald Header
    final canopyRect = Rect.fromLTWH(left - 3, top - 3, width + 6, 19);
    final canopyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF00E699), Color(0xFF059669), Color(0xFF047857)],
      ).createShader(canopyRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(canopyRect, const Radius.circular(7)),
      canopyPaint,
    );

    // Canopy LED line with headlights
    canvas.drawLine(
      Offset(left + 4, top + 6),
      Offset(right - 4, top + 6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // Panoramic Service Window
    final winRect = Rect.fromLTWH(left + 6, top + 22, width - 12, height - 38);
    final winPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF00F0FF).withValues(alpha: isDark ? 0.25 : 0.16),
          const Color(0xFF00D59B).withValues(alpha: isDark ? 0.12 : 0.08),
        ],
      ).createShader(winRect);

    canvas.drawRRect(RRect.fromRectAndRadius(winRect, const Radius.circular(6)), winPaint);

    // Digital Oscilloscope Terminal Screen inside counter
    final termRect = Rect.fromLTWH(left + 10, top + 28, width - 20, 20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(termRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF021714),
    );

    // Animated sine frequency waveform on counter terminal screen
    final wavePath = Path();
    final waveStartY = top + 38;
    wavePath.moveTo(left + 12, waveStartY);
    for (double wx = 0; wx < width - 24; wx += 2.0) {
      final s = math.sin((wx * 0.4) + (progress * 6 * math.pi));
      wavePath.lineTo(left + 12 + wx, waveStartY + s * 4.5);
    }
    canvas.drawPath(
      wavePath,
      Paint()
        ..color = const Color(0xFF00E699).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Counter Desk Ledge
    final ledgeRect = Rect.fromLTWH(left - 5, floorY - 14, width + 10, 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(ledgeRect, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A55), const Color(0xFF0F2035)]
              : [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)],
        ).createShader(ledgeRect),
    );

    // Illuminated desk edge LED
    canvas.drawLine(
      Offset(left - 4, floorY - 14),
      Offset(right + 4, floorY - 14),
      Paint()
        ..color = const Color(0xFF00F0FF).withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );

    // Overhead High-Precision Laser Scanner Projector Turret
    final turretRect = Rect.fromCenter(center: Offset(left + 2, top + 2), width: 8, height: 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(turretRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF00F0FF),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper: Stylized Passenger Silhouettes & "YOU" Indicator
  // ───────────────────────────────────────────────────────────────────────────
  void _drawStylizedPassenger({
    required Canvas canvas,
    required double x,
    required double floorY,
    required double height,
    required double width,
    required Color color,
    required bool isUser,
    bool hasBackpack = false,
    bool hasHeadphones = false,
    bool hasSuitcase = false,
    double bob = 0.0,
  }) {
    final headRadius = width * 0.38;
    final topY = floorY - height + bob;
    final headCenter = Offset(x, topY + headRadius);

    // 1. Soft Elliptical Floor Contact Shadow
    final shadowRect = Rect.fromCenter(
      center: Offset(x, floorY + 2),
      width: width * 1.8,
      height: 5.0,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.40 : 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // 2. Head
    final headPaint = Paint()..color = color;
    canvas.drawCircle(headCenter, headRadius, headPaint);

    // Headphone headband & ear cups
    if (hasHeadphones) {
      final hpPath = Path()
        ..addArc(
          Rect.fromCircle(center: headCenter, radius: headRadius + 1.2),
          -math.pi * 0.9,
          math.pi * 0.8,
        );
      canvas.drawPath(
        hpPath,
        Paint()
          ..color = const Color(0xFF00F0FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      // Glowing neon ear cup
      canvas.drawCircle(
        Offset(x - headRadius - 0.5, headCenter.dy + 1),
        1.6,
        Paint()..color = const Color(0xFF00F0FF),
      );
    }

    // 3. Torso & Jacket
    final torsoTop = headCenter.dy + headRadius + 1.5;
    final torsoHeight = height * 0.48;
    final torsoRect = Rect.fromLTWH(x - width / 2, torsoTop, width, torsoHeight);

    final torsoRRect = RRect.fromRectAndCorners(
      torsoRect,
      topLeft: Radius.circular(width * 0.45),
      topRight: Radius.circular(width * 0.45),
      bottomLeft: const Radius.circular(3),
      bottomRight: const Radius.circular(3),
    );

    final bodyShader = isUser
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0xFF00E699), Color(0xFF059669)],
          ).createShader(torsoRect)
        : null;

    final torsoPaint = Paint()
      ..color = color
      ..shader = bodyShader;
    canvas.drawRRect(torsoRRect, torsoPaint);

    // 4. Legs
    final legsTop = torsoTop + torsoHeight;
    final legWidth = width * 0.36;
    final legHeight = floorY - legsTop;

    final legPaint = Paint()
      ..color = isUser
          ? const Color(0xFF034A38)
          : (isDark ? const Color(0xFF1E293B) : const Color(0xFF475569));

    // Left leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - width / 2 + 1, legsTop, legWidth, legHeight),
        const Radius.circular(2),
      ),
      legPaint,
    );
    // Right leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + width / 2 - legWidth - 1, legsTop, legWidth, legHeight),
        const Radius.circular(2),
      ),
      legPaint,
    );

    // 5. Accessories
    if (hasBackpack) {
      final packRect = Rect.fromLTWH(x - width / 2 - 3.5, torsoTop + 2, 4.0, torsoHeight * 0.75);
      canvas.drawRRect(
        RRect.fromRectAndRadius(packRect, const Radius.circular(2.5)),
        Paint()..color = const Color(0xFF0F172A),
      );
    }

    if (hasSuitcase) {
      final caseX = x + width / 2 + 2;
      final caseRect = Rect.fromLTWH(caseX, floorY - 14, 8, 14);
      // Trolley handle
      canvas.drawLine(
        Offset(caseX + 4, floorY - 14),
        Offset(caseX + 4, floorY - 21),
        Paint()
          ..color = const Color(0xFF94A3B8)
          ..strokeWidth = 1.2,
      );
      // Suitcase body
      canvas.drawRRect(
        RRect.fromRectAndRadius(caseRect, const Radius.circular(2.5)),
        Paint()..color = const Color(0xFFF59E0B),
      );
    }

    // 6. Radiant "YOU" Floating Holographic Beacon (For the User)
    if (isUser) {
      final badgeCenterY = topY - 13.0;

      // Overhead halo ring
      final haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF00E699).withValues(alpha: 0.8);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, topY - 2.5), width: 15, height: 4.5),
        haloPaint,
      );

      // Glowing badge ambient aura
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, badgeCenterY), width: 34, height: 16),
          const Radius.circular(8),
        ),
        Paint()
          ..color = const Color(0xFF00D59B).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Badge capsule body
      final badgeRect = Rect.fromCenter(center: Offset(x, badgeCenterY), width: 32, height: 14);
      final badgePaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF00E699), Color(0xFF059669)],
        ).createShader(badgeRect);
      canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(7)), badgePaint);

      // Live pulsating beacon white dot inside badge
      final beaconAlpha = (0.6 + 0.4 * math.sin(progress * 6 * math.pi)).clamp(0.2, 1.0);
      canvas.drawCircle(
        Offset(x - 8, badgeCenterY),
        2.0,
        Paint()..color = Colors.white.withValues(alpha: beaconAlpha),
      );

      // Downward pointer arrow directed at user head
      final arrowPath = Path()
        ..moveTo(x - 3, badgeCenterY + 7)
        ..lineTo(x + 3, badgeCenterY + 7)
        ..lineTo(x, badgeCenterY + 10.5)
        ..close();
      canvas.drawPath(arrowPath, badgePaint);

      // Sharp "YOU" Typography
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'YOU',
          style: TextStyle(
            color: Color(0xFF022C22),
            fontSize: 7.8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2 + 3.0, badgeCenterY - textPainter.height / 2),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper: Floating Holographic VIP Ticket & Active Dual Laser Scanner
  // ───────────────────────────────────────────────────────────────────────────
  void _drawHolographicTicketAndScanner(
      Canvas canvas, double ticketX, double ticketY, double kioskLeft, double kioskTop) {
    const ticketW = 54.0;
    const ticketH = 32.0;

    final ticketRect = Rect.fromCenter(
      center: Offset(ticketX, ticketY),
      width: ticketW,
      height: ticketH,
    );

    // 1. Conical Volumetric Holographic Beam from kiosk turret down to ticket
    final beamPath = Path()
      ..moveTo(kioskLeft + 2, kioskTop + 2)
      ..lineTo(ticketX - ticketW * 0.65, ticketY + ticketH * 0.65)
      ..lineTo(ticketX + ticketW * 0.65, ticketY + ticketH * 0.65)
      ..close();

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          const Color(0xFF00F0FF).withValues(alpha: 0.35),
          const Color(0xFF00D59B).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(ticketX - ticketW, kioskTop, ticketW * 2, ticketH + 40));
    canvas.drawPath(beamPath, beamPaint);

    // 2. Active Radar Sonar Rings expanding from ticket center
    final radarP = (progress * 2) % 1.0;
    final radarRadius = 14.0 + radarP * 36.0;
    final radarAlpha = (1.0 - radarP).clamp(0.0, 0.7);
    canvas.drawCircle(
      Offset(ticketX, ticketY),
      radarRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0xFF00F0FF).withValues(alpha: radarAlpha * 0.6),
    );

    // 3. Golden VIP Ticket Ambient Bloom Glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(ticketRect, const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // 4. Ticket Body (Rich Golden Amber Gradient)
    final ticketRRect = RRect.fromRectAndRadius(ticketRect, const Radius.circular(6));
    final ticketPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFDE68A),
          Color(0xFFF59E0B),
          Color(0xFFB45309),
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(ticketRect);
    canvas.drawRRect(ticketRRect, ticketPaint);

    // 5. Classic Ticket Punch Notches (Circular cutouts on left and right)
    final notchPaint = Paint()
      ..color = isDark ? const Color(0xFF071220) : Colors.white;
    canvas.drawCircle(Offset(ticketRect.left, ticketY), 3.4, notchPaint);
    canvas.drawCircle(Offset(ticketRect.right, ticketY), 3.4, notchPaint);

    // 6. Miniature Train Icon / Emblem on Ticket
    final trainRect = Rect.fromCenter(
      center: Offset(ticketX - 13, ticketY - 5),
      width: 11,
      height: 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trainRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF451A03),
    );
    // Headlight on mini train
    canvas.drawCircle(Offset(ticketX - 9, ticketY - 5), 1.2, Paint()..color = const Color(0xFFFDE68A));

    // 7. VIP Berth Badge Tag
    final badgeTag = Rect.fromLTWH(ticketX - 4, ticketY - 9, 20, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeTag, const Radius.circular(1.5)),
      Paint()..color = const Color(0xFF78350F),
    );

    // 8. Barcode / QR Matrix Lines on Ticket
    final stripePaint = Paint()
      ..color = const Color(0xFF78350F).withValues(alpha: 0.85)
      ..strokeWidth = 1.3;
    for (int s = 0; s < 5; s++) {
      final sx = ticketX - 3 + s * 4.4;
      canvas.drawLine(Offset(sx, ticketY - 1), Offset(sx, ticketY + 9), stripePaint);
    }

    // 9. Diagonal Holographic Light Sheen sweeping across ticket
    final sheenP = (progress * 1.6) % 1.0;
    final sheenX = ticketRect.left + (ticketW + 20) * sheenP - 10;
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.5),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(sheenX - 8, ticketRect.top, 16, ticketH));
    canvas.save();
    canvas.clipRRect(ticketRRect);
    canvas.drawRect(Rect.fromLTWH(sheenX - 8, ticketRect.top, 16, ticketH), sheenPaint);
    canvas.restore();

    // 10. Active Cyber Laser Berth Scanner (Sweeping Line across Ticket)
    final scanLineOffset = math.sin(progress * 4 * math.pi);
    final scanY = ticketY + (ticketH * 0.40) * scanLineOffset;

    // Laser bloom
    canvas.drawLine(
      Offset(ticketRect.left + 3, scanY),
      Offset(ticketRect.right - 3, scanY),
      Paint()
        ..color = const Color(0xFF00F0FF).withValues(alpha: 0.90)
        ..strokeWidth = 2.8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Laser core (intense white/cyan)
    canvas.drawLine(
      Offset(ticketRect.left + 3, scanY),
      Offset(ticketRect.right - 3, scanY),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.3,
    );

    // Laser focal spark point moving horizontally along the laser beam
    final laserSpotX = ticketX + math.cos(progress * 8 * math.pi) * (ticketW * 0.35);
    canvas.drawCircle(
      Offset(laserSpotX, scanY),
      2.5,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );

    // 11. Orbiting Diamond Sparkles
    final sparkPaint = Paint()..color = const Color(0xFF67E8F9);
    for (int p = 0; p < 5; p++) {
      final sparkP = (progress + p * 0.20) % 1.0;
      final angle = p * (2 * math.pi / 5) + sparkP * 2 * math.pi;
      final dist = 24.0 + sparkP * 14.0;
      final sx = ticketX + math.cos(angle) * dist;
      final sy = ticketY + math.sin(angle) * dist * 0.65;
      final sAlpha = (1.0 - sparkP).clamp(0.0, 1.0);

      canvas.drawCircle(
        Offset(sx, sy),
        1.3,
        sparkPaint..color = const Color(0xFF67E8F9).withValues(alpha: sAlpha * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _QueueTicketPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}
