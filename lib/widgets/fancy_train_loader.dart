import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/language_service.dart';

class FancyTrainLoader extends StatefulWidget {
  final String? message;
  final double height;
  final bool showCard;

  const FancyTrainLoader({
    super.key,
    this.message,
    this.height = 200,
    this.showCard = false,
  });

  @override
  State<FancyTrainLoader> createState() => _FancyTrainLoaderState();
}

class _FancyTrainLoaderState extends State<FancyTrainLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
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
    final displayMsg = widget.message ?? lang.t('loading_tickets');

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: widget.height * 0.72,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _TrainTrackPainter(
                  progress: _controller.value,
                  isDark: isDark,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final alpha = (0.7 + 0.3 * math.sin(_controller.value * 2 * math.pi)).clamp(0.4, 1.0);
            return Opacity(
              opacity: alpha,
              child: Text(
                displayMsg,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
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
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? const Color(0xFF10B981).withValues(alpha: 0.25) : const Color(0xFF10B981).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}

class _TrainTrackPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _TrainTrackPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w / 2;

    // Horizon and ground vanishing points
    final horizonY = h * 0.38;
    final bottomY = h * 0.95;

    // 1. Perspective Railway Tracks
    final leftRailTopX = centerX - w * 0.08;
    final leftRailBottomX = centerX - w * 0.38;
    final rightRailTopX = centerX + w * 0.08;
    final rightRailBottomX = centerX + w * 0.38;

    // Draw glowing track ballast (bed)
    final ballastPath = Path()
      ..moveTo(leftRailTopX - 10, horizonY)
      ..lineTo(rightRailTopX + 10, horizonY)
      ..lineTo(rightRailBottomX + 25, bottomY)
      ..lineTo(leftRailBottomX - 25, bottomY)
      ..close();

    final ballastPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          isDark ? const Color(0xFF064E3B).withValues(alpha: 0.25) : const Color(0xFFD1FAE5).withValues(alpha: 0.4),
        ],
      ).createShader(Rect.fromLTWH(0, horizonY, w, bottomY - horizonY));
    canvas.drawPath(ballastPath, ballastPaint);

    // 2. Sleepers / Ties speeding towards the viewer
    const int sleeperCount = 8;
    final sleeperPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < sleeperCount; i++) {
      // Exponential distribution for realistic 3D perspective
      final t = ((i / sleeperCount) + progress) % 1.0;
      final factor = math.pow(t, 2.2).toDouble();
      final y = horizonY + (bottomY - horizonY) * factor;

      final lx = leftRailTopX + (leftRailBottomX - leftRailTopX) * factor;
      final rx = rightRailTopX + (rightRailBottomX - rightRailTopX) * factor;

      final strokeW = 1.5 + 4.5 * factor;
      final alpha = (0.2 + 0.8 * factor).clamp(0.0, 1.0);

      sleeperPaint
        ..strokeWidth = strokeW
        ..color = (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
            .withValues(alpha: alpha * 0.7);

      canvas.drawLine(
        Offset(lx - 8 * factor, y),
        Offset(rx + 8 * factor, y),
        sleeperPaint,
      );
    }

    // 3. Glowing Steel Rails
    final railGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..color = const Color(0xFF10B981).withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final railPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.3),
          const Color(0xFF34D399),
          const Color(0xFF6EE7B7),
        ],
      ).createShader(Rect.fromLTWH(0, horizonY, w, bottomY - horizonY));

    // Left Rail
    canvas.drawLine(Offset(leftRailTopX, horizonY), Offset(leftRailBottomX, bottomY), railGlowPaint);
    canvas.drawLine(Offset(leftRailTopX, horizonY), Offset(leftRailBottomX, bottomY), railPaint);

    // Right Rail
    canvas.drawLine(Offset(rightRailTopX, horizonY), Offset(rightRailBottomX, bottomY), railGlowPaint);
    canvas.drawLine(Offset(rightRailTopX, horizonY), Offset(rightRailBottomX, bottomY), railPaint);

    // 4. Aerodynamic Bangladesh Railway High-Speed Train
    // Bouncing oscillation
    final bounce = math.sin(progress * 4 * math.pi) * 2.5;
    final trainY = horizonY - 12 + bounce;
    final trainW = 54.0;
    final trainH = 46.0;
    final trainRect = Rect.fromCenter(
      center: Offset(centerX, trainY),
      width: trainW,
      height: trainH,
    );

    // Headlight volumetric light cones
    final headlightPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          const Color(0xFFFDE68A).withValues(alpha: 0.45),
          const Color(0xFFF59E0B).withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(centerX - 45, trainY, 90, 80));

    final lightBeamPath = Path()
      ..moveTo(centerX - 14, trainY + 12)
      ..lineTo(centerX - 42, bottomY - 10)
      ..lineTo(centerX + 42, bottomY - 10)
      ..lineTo(centerX + 14, trainY + 12)
      ..close();
    canvas.drawPath(lightBeamPath, headlightPaint);

    // Train Body (Emerald Green with Rounded aerodynamic curvature)
    final bodyRRect = RRect.fromRectAndCorners(
      trainRect,
      topLeft: const Radius.circular(24),
      topRight: const Radius.circular(24),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF047857),
          Color(0xFF065F46),
          Color(0xFF064E3B),
        ],
      ).createShader(trainRect);

    canvas.drawRRect(bodyRRect, bodyPaint);

    // Gold / Amber accent racing stripe
    final stripePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFFF59E0B);
    canvas.drawLine(
      Offset(centerX - trainW * 0.42, trainY + 10),
      Offset(centerX + trainW * 0.42, trainY + 10),
      stripePaint,
    );

    // Windshield (Sleek aerodynamic cockpit glass)
    final windshieldRect = Rect.fromCenter(
      center: Offset(centerX, trainY - 6),
      width: trainW * 0.68,
      height: trainH * 0.38,
    );
    final windshieldRRect = RRect.fromRectAndRadius(windshieldRect, const Radius.circular(8));
    final windshieldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF67E8F9),
          Color(0xFF0E7490),
          Color(0xFF155E75),
        ],
      ).createShader(windshieldRect);
    canvas.drawRRect(windshieldRRect, windshieldPaint);

    // Glass glare reflection
    final glarePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(centerX - 10, trainY - 11),
      Offset(centerX - 2, trainY - 3),
      glarePaint,
    );

    // Dual Headlights (glowing yellow dots)
    final lightDotPaint = Paint()
      ..color = const Color(0xFFFEF08A)
      ..style = PaintingStyle.fill;
    final lightDotGlow = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(Offset(centerX - 15, trainY + 14), 4.5, lightDotGlow);
    canvas.drawCircle(Offset(centerX - 15, trainY + 14), 3.0, lightDotPaint);

    canvas.drawCircle(Offset(centerX + 15, trainY + 14), 4.5, lightDotGlow);
    canvas.drawCircle(Offset(centerX + 15, trainY + 14), 3.0, lightDotPaint);

    // Front Rail Cowcatcher / Pilot grill
    final cowcatcherPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(centerX - 18, trainY + 22),
      Offset(centerX, trainY + 26),
      cowcatcherPaint,
    );
    canvas.drawLine(
      Offset(centerX, trainY + 26),
      Offset(centerX + 18, trainY + 22),
      cowcatcherPaint,
    );

    // 5. Dynamic Speed particles
    final particlePaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (int p = 0; p < 5; p++) {
      final pProgress = (progress + p * 0.2) % 1.0;
      final px = centerX + (p.isEven ? -1 : 1) * (20 + p * 14) * (1.0 + pProgress);
      final py = trainY - 8 - (pProgress * 30);
      final radius = 1.0 + (1.0 - pProgress) * 2.5;
      canvas.drawCircle(Offset(px, py), radius, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrainTrackPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}
