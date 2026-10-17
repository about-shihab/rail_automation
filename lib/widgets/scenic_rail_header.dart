import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/language_service.dart';
import '../utils/app_theme.dart';

/// A rich, animated panoramic header featuring a train journeying through
/// lush nature, rolling hills, clouds, and a gleaming railway line.
///
/// Adapts seamlessly to light and dark themes, respects reduced-motion
/// accessibility settings, and is optimized with a dedicated [RepaintBoundary].
class ScenicRailHeader extends StatefulWidget {
  /// Custom height for the header scene. If null, expands to fill parent.
  final double? height;

  /// Whether this is displayed in compact mode (e.g., standard AppBar).
  final bool compact;

  /// Optional child placed on top of the animation (e.g. title / actions).
  final Widget? child;

  /// Custom bottom border radius for the header backdrop.
  final double radius;

  /// Opacity multiplier for the scene elements (useful when overlaying text).
  final double sceneOpacity;

  /// Whether to enable subtle interactive haptic / steam toot on tap.
  final bool interactive;

  const ScenicRailHeader({
    super.key,
    this.height,
    this.compact = false,
    this.child,
    this.radius = 0,
    this.sceneOpacity = 1.0,
    this.interactive = true,
  });

  @override
  State<ScenicRailHeader> createState() => _ScenicRailHeaderState();
}

class _ScenicRailHeaderState extends State<ScenicRailHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _tootActive = false;
  double _tootX = 0;
  double _tootY = 0;

  @override
  void initState() {
    super.initState();
    // 14 seconds for a majestic, smooth, cinematic train pass
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant ScenicRailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    final disable =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (disable) {
      if (_motion.isAnimating) _motion.stop();
      _motion.value = 0.35; // Freeze at a scenic vantage point for tests/reduced motion
    } else {
      if (!_motion.isAnimating) _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.interactive) return;
    HapticFeedback.lightImpact();
    setState(() {
      _tootActive = true;
      _tootX = details.localPosition.dx;
      _tootY = details.localPosition.dy;
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _tootActive = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.vertical(bottom: Radius.circular(widget.radius));

    final scene = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          return CustomPaint(
            painter: _ScenicRailPainter(
              progress: _motion.value,
              isDark: isDark,
              compact: widget.compact,
              opacity: widget.sceneOpacity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        // 1. The scenic rail & nature animation canvas
        Positioned.fill(child: scene),

        // 2. Subtle top scrim for maximum typography and icon contrast
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.38 : 0.26),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isDark ? 0.35 : 0.16),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 2b. Lateral contrast scrim behind left-aligned title & subtitle
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.65 : 0.45),
                    Colors.black.withValues(alpha: isDark ? 0.40 : 0.22),
                    Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 0.70, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 3. Glowing bottom rail hairline
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0),
                    AppColors.accent.withValues(alpha: 0.6),
                    const Color(0xFF00FFB2).withValues(alpha: 0.7),
                    AppColors.accent.withValues(alpha: 0.6),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 4. Interactive Toot / Express Badge overlay
        if (_tootActive)
          Positioned(
            left: math.max(10, _tootX - 55),
            top: math.max(6, _tootY - 34),
            child: IgnorePointer(
              child: _ExpressTootBadge(isDark: isDark),
            ),
          ),

        // 5. Foreground content (if any)
        if (widget.child != null) Positioned.fill(child: widget.child!),
      ],
    );

    if (widget.interactive) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: _handleTapDown,
        child: content,
      );
    }

    if (widget.radius > 0) {
      content = ClipRRect(borderRadius: r, child: content);
    }

    if (widget.height != null) {
      return SizedBox(height: widget.height, child: content);
    }

    return content;
  }
}

/// Floating playful steam badge on header tap
class _ExpressTootBadge extends StatelessWidget {
  final bool isDark;
  const _ExpressTootBadge({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, val, child) {
        return Opacity(
          opacity: val.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -10 * val),
            child: Transform.scale(
              scale: 0.8 + 0.2 * val,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F3830) : const Color(0xFF004D3A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00FFB2).withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00FFB2).withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.train_rounded,
              size: 13,
              color: Color(0xFF00FFB2),
            ),
            const SizedBox(width: 5),
            Text(
              lang.tr('Choo-Choo! • Express', 'ছুটছে রেল • এক্সপ্রেস'),
              style: const TextStyle(
                fontFamily: 'Roboto',
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// High-performance custom painter for the animated rail & nature landscape.
class _ScenicRailPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final bool compact;
  final double opacity;

  // Cached paint objects to avoid garbage collection churn in 60fps paint loop
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

  _ScenicRailPainter({
    required this.progress,
    required this.isDark,
    required this.compact,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final width = size.width;
    final height = size.height;

    // ── 1. Sky & Atmosphere ─────────────────────────────────────────────────
    _paintSky(canvas, width, height);

    // ── 2. Distant Mist & Mountains ─────────────────────────────────────────
    _paintDistantHills(canvas, width, height);

    // ── 3. Midground Rolling Lush Hills & Trees ─────────────────────────────
    _paintMidgroundHillsAndTrees(canvas, width, height);

    // ── 4. Floating Clouds & Birds ──────────────────────────────────────────
    _paintCloudsAndBirds(canvas, width, height);

    // ── 5. Railway Track Line & Sleepers ────────────────────────────────────
    final trackY = compact ? height * 0.90 : height * 0.78;
    _paintRailwayTrack(canvas, width, trackY);

    // ── 6. Overhead Poles & Signal Light ────────────────────────────────────
    _paintRailwaySignalsAndPoles(canvas, width, trackY);

    // ── 7. Moving Train (Locomotive + Passenger Coaches) ────────────────────
    _paintMovingTrain(canvas, width, height, trackY);
  }

  void _paintSky(Canvas canvas, double width, double height) {
    final skyRect = Rect.fromLTWH(0, 0, width, height);
    final skyGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [
              Color(0xFF021310),
              Color(0xFF04241F),
              Color(0xFF0A3730),
              Color(0xFF084137),
            ]
          : const [
              AppColors.appBarGradientStart,
              Color(0xFF006C54),
              AppColors.appBarGradientEnd,
              Color(0xFF00A07A),
            ],
      stops: const [0.0, 0.35, 0.75, 1.0],
    );

    _fillPaint.shader = skyGradient.createShader(skyRect);
    canvas.drawRect(skyRect, _fillPaint);
    _fillPaint.shader = null;

    if (isDark) {
      // Midnight Moon & Stars
      final moonCenter = Offset(width * 0.88, height * 0.26);
      // Soft moon halo
      _fillPaint.color = const Color(0xFF64FFDA).withValues(alpha: 0.12 * opacity);
      canvas.drawCircle(moonCenter, 14, _fillPaint);
      _fillPaint.color = Colors.white.withValues(alpha: 0.85 * opacity);
      canvas.drawCircle(moonCenter, 7, _fillPaint);

      // Crescent shadow on moon
      _fillPaint.color = const Color(0xFF04241F);
      canvas.drawCircle(Offset(moonCenter.dx + 3.2, moonCenter.dy - 1.5), 6.0, _fillPaint);

      // Twinkling Stars
      final starOffsets = [
        Offset(width * 0.12, height * 0.18),
        Offset(width * 0.22, height * 0.32),
        Offset(width * 0.38, height * 0.14),
        Offset(width * 0.52, height * 0.25),
        Offset(width * 0.68, height * 0.16),
        Offset(width * 0.78, height * 0.35),
      ];
      for (var i = 0; i < starOffsets.length; i++) {
        final st = starOffsets[i];
        final tw = 0.35 + 0.45 * math.sin(progress * math.pi * 4 + i * 1.8).abs();
        _fillPaint.color = Colors.white.withValues(alpha: tw * opacity);
        canvas.drawCircle(st, i % 2 == 0 ? 1.2 : 0.8, _fillPaint);
      }
    } else {
      // Sun rays & golden dawn bloom
      final sunCenter = Offset(width * 0.86, height * 0.22);
      final sunGradient = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [
          Colors.white.withValues(alpha: 0.28 * opacity),
          const Color(0xFFFFD54F).withValues(alpha: 0.12 * opacity),
          Colors.transparent,
        ],
      );
      _fillPaint.shader = sunGradient.createShader(Rect.fromCircle(center: sunCenter, radius: 45));
      canvas.drawCircle(sunCenter, 45, _fillPaint);
      _fillPaint.shader = null;
    }
  }

  void _paintCloudsAndBirds(Canvas canvas, double width, double height) {
    // 3 Soft organic clouds drifting horizontally
    final cloudColor = (isDark ? const Color(0xFF80CBC4) : Colors.white)
        .withValues(alpha: (isDark ? 0.07 : 0.16) * opacity);
    _fillPaint.color = cloudColor;

    final cloudY = height * 0.24;
    for (var i = 0; i < 3; i++) {
      final speed = 0.15 + i * 0.08;
      final rawX = (progress * speed + i * 0.38) % 1.0;
      final cx = rawX * (width + 120) - 60;
      final cy = cloudY + (i == 1 ? 8 : -4);

      // Cloud puffs
      canvas.drawCircle(Offset(cx, cy), 11, _fillPaint);
      canvas.drawCircle(Offset(cx + 10, cy - 3), 14, _fillPaint);
      canvas.drawCircle(Offset(cx + 22, cy), 10, _fillPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 6, cy - 1, 38, 12),
          const Radius.circular(6),
        ),
        _fillPaint,
      );
    }

    // Birds in gentle flight formation
    final birdRawX = ((progress * 0.35 + 0.6) % 1.0);
    final bx = birdRawX * (width + 80) - 40;
    final by = height * 0.20;
    final wing = math.sin(progress * math.pi * 16) * 2.5;

    _strokePaint.color = (isDark ? const Color(0xFF80CBC4) : Colors.white)
        .withValues(alpha: 0.45 * opacity);
    _strokePaint.strokeWidth = 1.1;
    _strokePaint.strokeCap = StrokeCap.round;

    void drawBird(double x, double y, double scale) {
      final p = Path()
        ..moveTo(x - 5 * scale, y + wing * scale)
        ..quadraticBezierTo(x - 2 * scale, y - 2 * scale, x, y)
        ..quadraticBezierTo(x + 2 * scale, y - 2 * scale, x + 5 * scale, y + wing * scale);
      canvas.drawPath(p, _strokePaint);
    }

    drawBird(bx, by, 0.8);
    drawBird(bx - 12, by + 4, 0.65);
    drawBird(bx - 22, by + 1, 0.6);
  }

  void _paintDistantHills(Canvas canvas, double width, double height) {
    final hillY = compact ? height * 0.65 : height * 0.58;
    final path = Path()..moveTo(0, height);
    path.lineTo(0, hillY);

    path.quadraticBezierTo(
      width * 0.22,
      hillY - 14,
      width * 0.45,
      hillY - 4,
    );
    path.quadraticBezierTo(
      width * 0.72,
      hillY + 8,
      width,
      hillY - 12,
    );
    path.lineTo(width, height);
    path.close();

    _fillPaint.color = isDark
        ? const Color(0xFF042F28).withValues(alpha: 0.55 * opacity)
        : const Color(0xFF005844).withValues(alpha: 0.45 * opacity);
    canvas.drawPath(path, _fillPaint);
  }

  void _paintMidgroundHillsAndTrees(Canvas canvas, double width, double height) {
    final hillY = compact ? height * 0.80 : height * 0.68;
    final path = Path()..moveTo(0, height);
    path.lineTo(0, hillY + 6);

    path.quadraticBezierTo(
      width * 0.28,
      hillY + (compact ? 6 : 12),
      width * 0.55,
      hillY - (compact ? 4 : 8),
    );
    path.quadraticBezierTo(
      width * 0.82,
      hillY - (compact ? 10 : 20),
      width,
      hillY,
    );
    path.lineTo(width, height);
    path.close();

    _fillPaint.color = isDark
        ? const Color(0xFF084136).withValues(alpha: (compact ? 0.65 : 0.85) * opacity)
        : const Color(0xFF007559).withValues(alpha: (compact ? 0.60 : 0.80) * opacity);
    canvas.drawPath(path, _fillPaint);

    // In compact mode, keep trees away from left text area so typography is 100% clean
    final treeLocations = compact
        ? [
            Offset(width * 0.62, hillY - 4),
            Offset(width * 0.75, hillY - 8),
            Offset(width * 0.88, hillY - 3),
          ]
        : [
            Offset(width * 0.08, hillY + 5),
            Offset(width * 0.16, hillY + 8),
            Offset(width * 0.35, hillY + 4),
            Offset(width * 0.48, hillY - 6),
            Offset(width * 0.68, hillY - 14),
            Offset(width * 0.74, hillY - 16),
            Offset(width * 0.90, hillY - 6),
          ];

    final treeScale = compact ? 0.65 : 1.0;
    for (var i = 0; i < treeLocations.length; i++) {
      final loc = treeLocations[i];
      if (i % 3 == 0) {
        _drawPalmTree(canvas, loc.dx, loc.dy, 18 * treeScale);
      } else if (i % 2 == 0) {
        _drawPineTree(canvas, loc.dx, loc.dy, 16 * treeScale);
      } else {
        _drawLushRoundTree(canvas, loc.dx, loc.dy, 15 * treeScale);
      }
    }
  }

  void _drawPalmTree(Canvas canvas, double x, double y, double h) {
    // Curved trunk
    _strokePaint.color = (isDark ? const Color(0xFF37474F) : const Color(0xFF4E342E))
        .withValues(alpha: 0.85 * opacity);
    _strokePaint.strokeWidth = 1.8;
    final trunk = Path()
      ..moveTo(x, y)
      ..quadraticBezierTo(x + 3, y - h * 0.5, x + 2, y - h);
    canvas.drawPath(trunk, _strokePaint);

    // Radiating green palm fronds
    final top = Offset(x + 2, y - h);
    _strokePaint.color = (isDark ? const Color(0xFF1DE9B6) : const Color(0xFF69F0AE))
        .withValues(alpha: 0.8 * opacity);
    _strokePaint.strokeWidth = 1.4;

    final frondAngles = [-1.8, -1.2, -0.6, 0.6, 1.2, 1.8];
    for (final angle in frondAngles) {
      final ex = top.dx + math.cos(angle) * 9;
      final ey = top.dy + math.sin(angle) * 5 + 2;
      final frond = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(top.dx + math.cos(angle) * 5, top.dy - 3, ex, ey);
      canvas.drawPath(frond, _strokePaint);
    }
  }

  void _drawPineTree(Canvas canvas, double x, double y, double h) {
    // Pine trunk
    _strokePaint.color = const Color(0xFF3E2723).withValues(alpha: 0.8 * opacity);
    _strokePaint.strokeWidth = 1.6;
    canvas.drawLine(Offset(x, y), Offset(x, y - h * 0.35), _strokePaint);

    // Tiered green foliage
    _fillPaint.color = (isDark ? const Color(0xFF00BFA5) : const Color(0xFF00E676))
        .withValues(alpha: 0.75 * opacity);
    final topY = y - h;
    for (var i = 0; i < 3; i++) {
      final tierY = topY + i * (h * 0.26);
      final tierWidth = 5.0 + i * 2.8;
      final pinePath = Path()
        ..moveTo(x, tierY - 2)
        ..lineTo(x - tierWidth, tierY + 6)
        ..lineTo(x + tierWidth, tierY + 6)
        ..close();
      canvas.drawPath(pinePath, _fillPaint);
    }
  }

  void _drawLushRoundTree(Canvas canvas, double x, double y, double h) {
    // Short trunk
    _strokePaint.color = const Color(0xFF4E342E).withValues(alpha: 0.8 * opacity);
    _strokePaint.strokeWidth = 1.8;
    canvas.drawLine(Offset(x, y), Offset(x, y - h * 0.4), _strokePaint);

    // Layered leaf canopy
    _fillPaint.color = (isDark ? const Color(0xFF00897B) : const Color(0xFF00C853))
        .withValues(alpha: 0.8 * opacity);
    final cx = x;
    final cy = y - h * 0.7;
    canvas.drawCircle(Offset(cx, cy), 6.5, _fillPaint);
    canvas.drawCircle(Offset(cx - 4, cy + 2), 5.5, _fillPaint);
    canvas.drawCircle(Offset(cx + 4, cy + 2), 5.5, _fillPaint);
  }

  void _paintRailwayTrack(Canvas canvas, double width, double trackY) {
    // Embankment gravel ballast bed
    final ballastRect = Rect.fromLTWH(0, trackY - 2, width, 16);
    _fillPaint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [Color(0xFF1B312B), Color(0xFF10211D)]
          : const [Color(0xFF26463E), Color(0xFF142B25)],
    ).createShader(ballastRect);
    canvas.drawRect(ballastRect, _fillPaint);
    _fillPaint.shader = null;

    // Ballast texture stippling
    _fillPaint.color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    for (var x = 8.0; x < width; x += 22) {
      canvas.drawCircle(Offset(x, trackY + 7), 1.0, _fillPaint);
      canvas.drawCircle(Offset(x + 10, trackY + 11), 0.8, _fillPaint);
    }

    // Wooden/Concrete Sleepers (Ties)
    const sleeperSpacing = 14.0;
    const sleeperWidth = 3.8;
    const sleeperHeight = 9.0;
    final sleeperColor = isDark ? const Color(0xFF37474F) : const Color(0xFF455A64);

    _fillPaint.color = sleeperColor.withValues(alpha: 0.85);
    for (var x = 0.0; x < width + sleeperSpacing; x += sleeperSpacing) {
      final sRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, trackY, sleeperWidth, sleeperHeight),
        const Radius.circular(1.0),
      );
      canvas.drawRRect(sRect, _fillPaint);
    }

    // Dual Metallic Steel Rails (Top rail & lower rail)
    final railGlow = isDark ? const Color(0xFF64FFDA) : const Color(0xFFB9F6CA);

    // Top steel rail
    _strokePaint.color = railGlow.withValues(alpha: 0.9 * opacity);
    _strokePaint.strokeWidth = 1.6;
    canvas.drawLine(Offset(0, trackY + 1.2), Offset(width, trackY + 1.2), _strokePaint);

    // Specular highlight on top rail (gleaming steel finish)
    _strokePaint.color = Colors.white.withValues(alpha: 0.75 * opacity);
    _strokePaint.strokeWidth = 0.7;
    canvas.drawLine(Offset(0, trackY + 0.8), Offset(width, trackY + 0.8), _strokePaint);

    // Bottom steel rail
    _strokePaint.color = railGlow.withValues(alpha: 0.75 * opacity);
    _strokePaint.strokeWidth = 1.4;
    canvas.drawLine(Offset(0, trackY + 6.8), Offset(width, trackY + 6.8), _strokePaint);
  }

  void _paintRailwaySignalsAndPoles(Canvas canvas, double width, double trackY) {
    // Overhead Telegraph / Catenary Poles (In compact mode, keep away from left text area)
    const poleSpacing = 120.0;
    _strokePaint.color = (isDark ? const Color(0xFF546E7A) : const Color(0xFF78909C))
        .withValues(alpha: (compact ? 0.40 : 0.60) * opacity);
    _strokePaint.strokeWidth = compact ? 1.0 : 1.4;

    final poleTop = trackY - (compact ? 16 : 24);
    final startPx = compact ? width * 0.58 : 24.0;
    for (var px = startPx; px < width + poleSpacing; px += poleSpacing) {
      // Upright pole
      canvas.drawLine(Offset(px, trackY + 4), Offset(px, poleTop), _strokePaint);
      // Crossarm
      canvas.drawLine(Offset(px - 4, poleTop + 2), Offset(px + 4, poleTop + 2), _strokePaint);

      // Catenary overhead wire sagging between poles
      if (px + poleSpacing < width + 60) {
        _strokePaint.strokeWidth = 0.7;
        _strokePaint.color = Colors.white.withValues(alpha: 0.20 * opacity);
        final wire = Path()
          ..moveTo(px, poleTop + 2)
          ..quadraticBezierTo(
            px + poleSpacing / 2,
            poleTop + (compact ? 5 : 8),
            px + poleSpacing,
            poleTop + 2,
          );
        canvas.drawPath(wire, _strokePaint);
        _strokePaint.strokeWidth = compact ? 1.0 : 1.4;
      }
    }

    // Signal Mast with Glowing Green LED (indicating clear line)
    final sigX = width * 0.92;
    _strokePaint.color = const Color(0xFF37474F);
    _strokePaint.strokeWidth = 2.0;
    canvas.drawLine(Offset(sigX, trackY + 4), Offset(sigX, trackY - (compact ? 12 : 18)), _strokePaint);

    // Signal target head
    _fillPaint.color = Colors.black;
    canvas.drawCircle(Offset(sigX, trackY - (compact ? 12 : 18)), compact ? 3.5 : 4.5, _fillPaint);

    // Radiant Green Light (with soft breathing pulse)
    final pulse = 0.75 + 0.25 * math.sin(progress * math.pi * 10);
    _fillPaint.color = const Color(0xFF00E676).withValues(alpha: 0.3 * pulse * opacity);
    canvas.drawCircle(Offset(sigX, trackY - (compact ? 12 : 18)), compact ? 6.0 : 9.0, _fillPaint);
    _fillPaint.color = const Color(0xFF00FFB2).withValues(alpha: pulse * opacity);
    canvas.drawCircle(Offset(sigX, trackY - (compact ? 12 : 18)), compact ? 1.8 : 2.5, _fillPaint);
  }

  void _paintMovingTrain(Canvas canvas, double width, double height, double trackY) {
    // Train geometry scaled cleanly for compact vs expanded viewports
    final locoLen = compact ? 38.0 : 56.0;
    final coachLen = compact ? 30.0 : 46.0;
    final gap = compact ? 2.5 : 3.5;
    final bodyHeight = compact ? 9.5 : 15.0;
    final totalTrainLen = locoLen + gap + coachLen + gap + coachLen;

    final travelDist = width + totalTrainLen + 60;
    // Train glides from left to right smoothly
    final trainHeadX = (progress * travelDist) - 30;
    final locoX = trainHeadX - locoLen;
    final coach1X = locoX - gap - coachLen;
    final coach2X = coach1X - gap - coachLen;

    final bodyY = trackY - bodyHeight - 1.5;

    // Headlight Beam Cone (shining brightly forward onto rails)
    if (trainHeadX > -40 && trainHeadX < width + 180) {
      final beamLength = compact ? 85.0 : 120.0;
      final beamPath = Path()
        ..moveTo(trainHeadX + 2, bodyY + 6)
        ..lineTo(trainHeadX + beamLength, bodyY - 10)
        ..lineTo(trainHeadX + beamLength, trackY + 8)
        ..close();

      _fillPaint.shader = ui.Gradient.linear(
        Offset(trainHeadX + 2, bodyY + 6),
        Offset(trainHeadX + beamLength, bodyY + 6),
        [
          const Color(0xFFFFFFFF).withValues(alpha: (isDark ? 0.75 : 0.45) * opacity),
          const Color(0xFFFFF9C4).withValues(alpha: (isDark ? 0.35 : 0.18) * opacity),
          Colors.transparent,
        ],
        [0.0, 0.4, 1.0],
      );
      canvas.drawPath(beamPath, _fillPaint);
      _fillPaint.shader = null;
    }

    // ── A. Draw Locomotive ──────────────────────────────────────────────────
    if (locoX + locoLen > -30 && locoX < width + 30) {
      _drawLocomotive(canvas, locoX, bodyY, locoLen, bodyHeight, trackY);
    }

    // ── B. Draw Coupler Gangways ─────────────────────────────────────────────
    _drawGangway(canvas, locoX - gap, bodyY + 4, gap, bodyHeight - 7);
    _drawGangway(canvas, coach1X - gap, bodyY + 4, gap, bodyHeight - 7);

    // ── C. Draw Coach 1 ─────────────────────────────────────────────────────
    if (coach1X + coachLen > -30 && coach1X < width + 30) {
      _drawCoach(canvas, coach1X, bodyY, coachLen, bodyHeight, trackY, isTail: false);
    }

    // ── D. Draw Coach 2 (Rear with glowing red tail lamp) ───────────────────
    if (coach2X + coachLen > -30 && coach2X < width + 30) {
      _drawCoach(canvas, coach2X, bodyY, coachLen, bodyHeight, trackY, isTail: true);
    }

    // ── E. Trailing Speed Vapor Wisps ───────────────────────────────────────
    if (locoX > 0 && locoX < width) {
      final wispProgress = (progress * 12) % 1.0;
      for (var i = 1; i <= 3; i++) {
        final wx = locoX - 4 - (i * 12 + wispProgress * 8);
        final wy = bodyY - 2 - (i * 3 + wispProgress * 4);
        final wAlpha = (0.28 - i * 0.08) * opacity;
        if (wAlpha > 0) {
          _fillPaint.color = Colors.white.withValues(alpha: wAlpha);
          canvas.drawCircle(Offset(wx, wy), 2.2 + i * 1.0, _fillPaint);
        }
      }
    }
  }

  void _drawLocomotive(
    Canvas canvas,
    double x,
    double y,
    double len,
    double h,
    double trackY,
  ) {
    // Streamlined aerodynamic nose path
    final locoBody = Path()
      ..moveTo(x, y + h)
      ..lineTo(x, y + 2)
      ..lineTo(x + len - 16, y + 2)
      ..quadraticBezierTo(x + len - 6, y + 3, x + len, y + h * 0.65)
      ..lineTo(x + len, y + h)
      ..close();

    // Body base paint: Bangladesh Railway deep forest emerald / racing teal
    _fillPaint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [Color(0xFF00E676), Color(0xFF00796B), Color(0xFF004D40)]
          : const [Color(0xFF00C853), Color(0xFF00897B), Color(0xFF004D3A)],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromLTWH(x, y, len, h));
    canvas.drawPath(locoBody, _fillPaint);
    _fillPaint.shader = null;

    // Golden racing / speed waistline
    _strokePaint.color = const Color(0xFFFFD54F).withValues(alpha: 0.95);
    _strokePaint.strokeWidth = 1.5;
    canvas.drawLine(Offset(x, y + h * 0.62), Offset(x + len - 3, y + h * 0.62), _strokePaint);

    // Modern cockpit driver windshield (sloped forward)
    final cabPath = Path()
      ..moveTo(x + len - 22, y + 4)
      ..lineTo(x + len - 10, y + 5)
      ..lineTo(x + len - 4, y + h * 0.52)
      ..lineTo(x + len - 22, y + h * 0.52)
      ..close();
    _fillPaint.color = const Color(0xFF102A27);
    canvas.drawPath(cabPath, _fillPaint);

    // Warm cab interior glow
    _fillPaint.color = const Color(0xFFFFF59D).withValues(alpha: 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + len - 18, y + 6, 8, 4),
        const Radius.circular(1),
      ),
      _fillPaint,
    );

    // Aerodynamic roof unit & pantograph
    _fillPaint.color = const Color(0xFFCFD8DC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 10, y - 1.5, 20, 2.5),
        const Radius.circular(1),
      ),
      _fillPaint,
    );

    // Front high-beam LED headlight lens
    _fillPaint.color = Colors.white;
    canvas.drawCircle(Offset(x + len - 1.0, y + h * 0.68), 2.2, _fillPaint);
    _fillPaint.color = const Color(0xFFFFF59D);
    canvas.drawCircle(Offset(x + len - 1.0, y + h * 0.68), 1.3, _fillPaint);

    // Wheel Bogies (4 rotating wheels)
    _drawWheel(canvas, x + 10, trackY + 1);
    _drawWheel(canvas, x + 20, trackY + 1);
    _drawWheel(canvas, x + len - 22, trackY + 1);
    _drawWheel(canvas, x + len - 12, trackY + 1);
  }

  void _drawCoach(
    Canvas canvas,
    double x,
    double y,
    double len,
    double h,
    double trackY, {
    required bool isTail,
  }) {
    final coachRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + 2, len, h - 2),
      const Radius.circular(2.5),
    );

    // Coach body gradient
    _fillPaint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? const [Color(0xFF00BFA5), Color(0xFF00695C)]
          : const [Color(0xFF00B0FF), Color(0xFF00775D)],
      stops: const [0.0, 1.0],
    ).createShader(coachRect.outerRect);
    canvas.drawRRect(coachRect, _fillPaint);
    _fillPaint.shader = null;

    // Red/gold accent band across coach
    _strokePaint.color = const Color(0xFFFF5252).withValues(alpha: 0.9);
    _strokePaint.strokeWidth = 1.2;
    canvas.drawLine(Offset(x, y + h * 0.68), Offset(x + len, y + h * 0.68), _strokePaint);

    // 3 Glowing Passenger Windows per coach
    const winCount = 3;
    final winWidth = (len - 14) / winCount;
    for (var w = 0; w < winCount; w++) {
      final wx = x + 4 + w * (winWidth + 2.5);
      final winRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(wx, y + 4.5, winWidth - 1, 5.0),
        const Radius.circular(1.2),
      );

      // Warm interior passenger illumination
      _fillPaint.color = isDark ? const Color(0xFFFFE082) : const Color(0xFFE0F7FA);
      canvas.drawRRect(winRect, _fillPaint);

      // Window divider / passenger silhouette
      _fillPaint.color = isDark ? const Color(0xFF424242) : const Color(0xFF00695C);
      canvas.drawCircle(Offset(wx + winWidth * 0.5, y + 6.8), 1.1, _fillPaint);
    }

    // Tail Lamp on the rear coach
    if (isTail) {
      _fillPaint.color = const Color(0xFFFF1744);
      canvas.drawCircle(Offset(x + 1.2, y + h * 0.68), 1.8, _fillPaint);
      _fillPaint.color = const Color(0xFFFF1744).withValues(alpha: 0.4);
      canvas.drawCircle(Offset(x + 1.2, y + h * 0.68), 4.5, _fillPaint);
    }

    // Wheel Bogies (4 wheels per coach)
    _drawWheel(canvas, x + 8, trackY + 1);
    _drawWheel(canvas, x + 17, trackY + 1);
    _drawWheel(canvas, x + len - 17, trackY + 1);
    _drawWheel(canvas, x + len - 8, trackY + 1);
  }

  void _drawGangway(Canvas canvas, double x, double y, double w, double h) {
    _fillPaint.color = const Color(0xFF263238);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(1)),
      _fillPaint,
    );
  }

  void _drawWheel(Canvas canvas, double cx, double cy) {
    final r = compact ? 2.0 : 3.0;
    // Wheel Rim
    _fillPaint.color = const Color(0xFF263238);
    canvas.drawCircle(Offset(cx, cy), r, _fillPaint);

    // Metallic tread
    _strokePaint.color = const Color(0xFFCFD8DC);
    _strokePaint.strokeWidth = compact ? 0.6 : 0.8;
    canvas.drawCircle(Offset(cx, cy), r * 0.9, _strokePaint);

    // Spinning axle hub
    final angle = progress * math.pi * 32;
    _strokePaint.color = Colors.white;
    _strokePaint.strokeWidth = 0.6;
    canvas.drawLine(
      Offset(cx - math.cos(angle) * 1.8, cy - math.sin(angle) * 1.8),
      Offset(cx + math.cos(angle) * 1.8, cy + math.sin(angle) * 1.8),
      _strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenicRailPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.compact != compact ||
        oldDelegate.opacity != opacity;
  }
}
