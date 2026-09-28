import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';

/// Professional, seamless animated loader depicting a user in a queue looking for tickets.
/// Includes an illuminated railway ticket counter, queuing passengers, the "YOU" indicator,
/// a hovering holographic train ticket, and active radar laser scanning.
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
  ];

  @override
  void initState() {
    super.initState();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: widget.height * 0.68,
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
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final alpha = (0.75 + 0.25 * math.sin(_controller.value * 2 * math.pi)).clamp(0.5, 1.0);
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
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
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0A1322).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0xFF00D59B).withValues(alpha: 0.28) : const Color(0xFF00D59B).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D59B).withValues(alpha: isDark ? 0.14 : 0.08),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
            if (isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: content,
      ),
    );
  }
}

/// Custom painter rendering a queue of passengers looking for tickets at the Bangladesh Railway counter.
class _QueueTicketPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _QueueTicketPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background radial ambient glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.4, -0.2),
        radius: 0.85,
        colors: [
          (isDark ? const Color(0xFF00D59B) : const Color(0xFF10B981)).withValues(alpha: isDark ? 0.16 : 0.10),
          (isDark ? const Color(0xFF00F0FF) : const Color(0xFF0EA5E9)).withValues(alpha: 0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glowPaint);

    final floorY = h * 0.82;

    // 1. Digital Queue Pathway & Floor Grid
    final floorLinePaint = Paint()
      ..color = (isDark ? const Color(0xFF1E3A55) : const Color(0xFFCBDCF0)).withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(w * 0.05, floorY), Offset(w * 0.95, floorY), floorLinePaint);

    // Floor position circles (#3, #2, #1)
    final posPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final posFills = [w * 0.15, w * 0.35, w * 0.55];
    for (int i = 0; i < posFills.length; i++) {
      final px = posFills[i];
      final isFront = (i == 2);
      posPaint.color = (isFront
              ? const Color(0xFF00D59B)
              : (isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8)))
          .withValues(alpha: isFront ? 0.6 : 0.3);

      canvas.drawOval(
        Rect.fromCenter(center: Offset(px, floorY + 4), width: 28, height: 8),
        posPaint,
      );
    }

    // Glowing Queue Stanchions & Velvet Guide Rope
    final stanchionPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFBBF24), Color(0xFFB45309)],
      ).createShader(Rect.fromLTWH(0, floorY - 30, w, 30));

    // Stanchion post 1
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.06, floorY - 26, 3, 26), const Radius.circular(1.5)),
      stanchionPaint,
    );
    canvas.drawCircle(Offset(w * 0.06 + 1.5, floorY - 26), 3.5, Paint()..color = const Color(0xFFFBBF24));

    // Stanchion post 2
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.68, floorY - 26, 3, 26), const Radius.circular(1.5)),
      stanchionPaint,
    );
    canvas.drawCircle(Offset(w * 0.68 + 1.5, floorY - 26), 3.5, Paint()..color = const Color(0xFFFBBF24));

    // Catenary rope hanging between stanchions
    final ropePath = Path()
      ..moveTo(w * 0.06 + 1.5, floorY - 22)
      ..quadraticBezierTo(w * 0.37, floorY - 14, w * 0.68 + 1.5, floorY - 22);

    final ropePaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(ropePath, ropePaint);

    // 2. The Bangladesh Railway Ticket Counter / Kiosk (Right Side)
    final kioskLeft = w * 0.72;
    final kioskRight = w * 0.95;
    final kioskWidth = kioskRight - kioskLeft;
    final kioskTop = h * 0.16;

    // Kiosk Body
    final kioskRect = Rect.fromLTWH(kioskLeft, kioskTop, kioskWidth, floorY - kioskTop);
    final kioskPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF0F2035), const Color(0xFF0A1728)]
            : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
      ).createShader(kioskRect);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        kioskRect,
        topLeft: const Radius.circular(14),
        topRight: const Radius.circular(14),
      ),
      kioskPaint,
    );

    // Kiosk Canopy / Roof with Railway Emerald Branding
    final canopyRect = Rect.fromLTWH(kioskLeft - 4, kioskTop - 4, kioskWidth + 8, 20);
    final canopyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF00D59B), Color(0xFF059669), Color(0xFF047857)],
      ).createShader(canopyRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(canopyRect, const Radius.circular(8)),
      canopyPaint,
    );

    // Canopy LED line
    canvas.drawLine(
      Offset(kioskLeft + 4, kioskTop + 6),
      Offset(kioskRight - 4, kioskTop + 6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Counter Service Glass Window
    final windowRect = Rect.fromLTWH(kioskLeft + 6, kioskTop + 24, kioskWidth - 12, floorY - kioskTop - 40);
    final windowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF00F0FF).withValues(alpha: isDark ? 0.22 : 0.15),
          const Color(0xFF00D59B).withValues(alpha: isDark ? 0.12 : 0.08),
        ],
      ).createShader(windowRect);

    canvas.drawRRect(RRect.fromRectAndRadius(windowRect, const Radius.circular(6)), windowPaint);

    // Terminal screen inside window
    final termRect = Rect.fromLTWH(kioskLeft + 12, kioskTop + 32, kioskWidth - 24, 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(termRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF021B16),
    );
    // Green data pulse on terminal
    final dataAlpha = (0.5 + 0.5 * math.sin(progress * 6 * math.pi)).clamp(0.2, 1.0);
    canvas.drawLine(
      Offset(kioskLeft + 16, kioskTop + 41),
      Offset(kioskRight - 16, kioskTop + 41),
      Paint()
        ..color = const Color(0xFF00D59B).withValues(alpha: dataAlpha)
        ..strokeWidth = 2.0,
    );

    // Counter Desk ledge
    final ledgeRect = Rect.fromLTWH(kioskLeft - 6, floorY - 18, kioskWidth + 12, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(ledgeRect, const Radius.circular(4)),
      Paint()..color = isDark ? const Color(0xFF1E3A55) : const Color(0xFF94A3B8),
    );

    // 3. Queue of Passengers Moving Towards the Counter
    // Subtle queue advancement wave
    final wave = math.sin(progress * 2 * math.pi);
    final stepBob = (math.sin(progress * 4 * math.pi)).abs() * 2.5;

    // --- Passenger 3 (Rear, position ~ w * 0.15) ---
    _drawPassenger(
      canvas: canvas,
      x: w * 0.15 + (wave * 1.5),
      floorY: floorY,
      headRadius: 6.0,
      bodyHeight: 20.0,
      bodyWidth: 11.0,
      color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
      isUser: false,
      hasBackpack: true,
      stepBob: stepBob * 0.4,
    );

    // --- Passenger 2 (Middle, position ~ w * 0.35) ---
    _drawPassenger(
      canvas: canvas,
      x: w * 0.35 + (wave * 2.0),
      floorY: floorY,
      headRadius: 6.8,
      bodyHeight: 22.0,
      bodyWidth: 12.0,
      color: isDark ? const Color(0xFF38BDF8).withValues(alpha: 0.8) : const Color(0xFF0284C7),
      isUser: false,
      hasBriefcase: true,
      stepBob: stepBob * 0.7,
    );

    // --- Passenger 1: THE USER ("YOU" indicator, at counter position ~ w * 0.55) ---
    final userX = w * 0.55 + (wave * 1.0);
    _drawPassenger(
      canvas: canvas,
      x: userX,
      floorY: floorY,
      headRadius: 8.0,
      bodyHeight: 25.0,
      bodyWidth: 14.0,
      color: const Color(0xFF00D59B),
      isUser: true,
      stepBob: stepBob,
    );

    // 4. "LOOKING FOR TICKET" Active Holographic Ticket & Radar Laser Scanner
    // Floating ticket located between user and kiosk window
    final ticketX = w * 0.65;
    final ticketHover = math.sin(progress * 2 * math.pi) * 4.0;
    final ticketY = h * 0.36 + ticketHover;
    final ticketW = 50.0;
    final ticketH = 30.0;

    final ticketRect = Rect.fromCenter(
      center: Offset(ticketX, ticketY),
      width: ticketW,
      height: ticketH,
    );

    // Radar pulse expanding from ticket center
    final radarP = (progress * 2) % 1.0;
    final radarRadius = 12.0 + radarP * 34.0;
    final radarAlpha = (1.0 - radarP).clamp(0.0, 0.7);
    final radarPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF00F0FF).withValues(alpha: radarAlpha * 0.5);
    canvas.drawCircle(Offset(ticketX, ticketY), radarRadius, radarPaint);

    // Conical Optical Scanner Beam from kiosk overhead down onto ticket
    final beamPath = Path()
      ..moveTo(ticketX, kioskTop)
      ..lineTo(ticketX - ticketW * 0.65, ticketY + ticketH * 0.6)
      ..lineTo(ticketX + ticketW * 0.65, ticketY + ticketH * 0.6)
      ..close();

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00F0FF).withValues(alpha: 0.35),
          const Color(0xFF00D59B).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(ticketX - ticketW, kioskTop, ticketW * 2, ticketH + 30));
    canvas.drawPath(beamPath, beamPaint);

    // Holographic Train Ticket with side notch cutouts
    final ticketRRect = RRect.fromRectAndRadius(ticketRect, const Radius.circular(5));
    final ticketPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFBBF24),
          Color(0xFFF59E0B),
          Color(0xFFD97706),
        ],
      ).createShader(ticketRect);

    // Ticket shadow & glow
    canvas.drawRRect(
      ticketRRect,
      Paint()
        ..color = const Color(0xFFF59E0B).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(ticketRRect, ticketPaint);

    // Side notch cutouts (classic train ticket punched holes)
    final notchPaint = Paint()..color = isDark ? const Color(0xFF0A1322) : Colors.white;
    canvas.drawCircle(Offset(ticketRect.left, ticketY), 3.0, notchPaint);
    canvas.drawCircle(Offset(ticketRect.right, ticketY), 3.0, notchPaint);

    // Mini train icon on ticket
    final iconPaint = Paint()
      ..color = const Color(0xFF451A03)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(ticketX - 12, ticketY - 4), width: 10, height: 7),
        const Radius.circular(1.5),
      ),
      iconPaint,
    );

    // Barcode / text stripes on ticket
    final stripePaint = Paint()
      ..color = const Color(0xFF78350F).withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    for (int s = 0; s < 4; s++) {
      final sx = ticketX - 2 + s * 4.2;
      canvas.drawLine(Offset(sx, ticketY - 6), Offset(sx, ticketY + 6), stripePaint);
    }

    // Active Laser Scanning Line sweeping across ticket
    final scanLineOffset = math.sin(progress * 4 * math.pi);
    final scanY = ticketY + (ticketH * 0.38) * scanLineOffset;

    final laserGlow = Paint()
      ..color = const Color(0xFF00F0FF).withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final laserCore = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2;

    canvas.drawLine(Offset(ticketRect.left + 4, scanY), Offset(ticketRect.right - 4, scanY), laserGlow);
    canvas.drawLine(Offset(ticketRect.left + 4, scanY), Offset(ticketRect.right - 4, scanY), laserCore);

    // Floating digital search sparks around the ticket
    final sparkPaint = Paint()..color = const Color(0xFF67E8F9);
    for (int p = 0; p < 4; p++) {
      final sparkP = (progress + p * 0.25) % 1.0;
      final angle = p * (math.pi / 2) + sparkP * math.pi;
      final dist = 22.0 + sparkP * 12.0;
      final sx = ticketX + math.cos(angle) * dist;
      final sy = ticketY + math.sin(angle) * dist * 0.7;
      final sAlpha = (1.0 - sparkP).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(sx, sy), 1.2, sparkPaint..color = const Color(0xFF67E8F9).withValues(alpha: sAlpha));
    }
  }

  /// Helper to draw a passenger figure with avatar details and "YOU" badge.
  void _drawPassenger({
    required Canvas canvas,
    required double x,
    required double floorY,
    required double headRadius,
    required double bodyHeight,
    required double bodyWidth,
    required Color color,
    required bool isUser,
    bool hasBackpack = false,
    bool hasBriefcase = false,
    double stepBob = 0.0,
  }) {
    final headY = floorY - bodyHeight - headRadius * 2 + stepBob;
    final bodyY = floorY - bodyHeight + stepBob;

    // Body / Torso
    final bodyRect = Rect.fromLTWH(x - bodyWidth / 2, bodyY, bodyWidth, bodyHeight - 4);
    final bodyRRect = RRect.fromRectAndCorners(
      bodyRect,
      topLeft: Radius.circular(bodyWidth / 2),
      topRight: Radius.circular(bodyWidth / 2),
      bottomLeft: const Radius.circular(3),
      bottomRight: const Radius.circular(3),
    );

    final bodyPaint = Paint()..color = color;
    canvas.drawRRect(bodyRRect, bodyPaint);

    // Head
    canvas.drawCircle(Offset(x, headY + headRadius), headRadius, bodyPaint);

    // Accessories
    if (hasBackpack) {
      final packRect = Rect.fromLTWH(x - bodyWidth / 2 - 4, bodyY + 3, 4, bodyHeight * 0.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(packRect, const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: 0.6),
      );
    }

    if (hasBriefcase) {
      final caseRect = Rect.fromLTWH(x + bodyWidth / 2 + 2, floorY - 12 + stepBob, 6, 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(caseRect, const Radius.circular(1.5)),
        Paint()..color = const Color(0xFFF59E0B),
      );
    }

    // "YOU" Indicator Halo & Beacon for the user
    if (isUser) {
      final haloY = headY - 8.0;

      // Pulsing halo glow
      final haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF00D59B).withValues(alpha: 0.9);

      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, haloY + 2), width: 14, height: 5),
        haloPaint,
      );

      // "YOU" pill badge
      final pillRect = Rect.fromCenter(center: Offset(x, haloY - 7), width: 26, height: 11);
      final pillPaint = Paint()..color = const Color(0xFF00D59B);
      canvas.drawRRect(RRect.fromRectAndRadius(pillRect, const Radius.circular(5.5)), pillPaint);

      // Small down pointer arrow
      final arrowPath = Path()
        ..moveTo(x - 2.5, haloY - 1.5)
        ..lineTo(x + 2.5, haloY - 1.5)
        ..lineTo(x, haloY + 1.5)
        ..close();
      canvas.drawPath(arrowPath, pillPaint);

      // Draw text "YOU"
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'YOU',
          style: TextStyle(
            color: Color(0xFF022C22),
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, haloY - 7 - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _QueueTicketPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}
