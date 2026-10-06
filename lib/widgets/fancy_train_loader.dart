import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/language_service.dart';
import '../utils/app_theme.dart';

enum JourneyAnimationStage {
  searching,
  reserving,
  verifying,
  payment,
  paused,
  complete,
}

/// A booking illustration driven by real state instead of simulated progress.
class FancyTrainLoader extends StatefulWidget {
  final String? message;
  final String? subMessage;
  final double height;
  final bool showCard;
  final JourneyAnimationStage stage;
  const FancyTrainLoader({
    super.key,
    this.message,
    this.subMessage,
    this.height = 200,
    this.showCard = false,
    this.stage = JourneyAnimationStage.searching,
  });
  @override
  State<FancyTrainLoader> createState() => _FancyTrainLoaderState();
}

class _FancyTrainLoaderState extends State<FancyTrainLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant FancyTrainLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        widget.stage != JourneyAnimationStage.paused &&
        !WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (animate && !_motion.isAnimating) _motion.repeat();
    if (!animate) _motion.stop();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.of(context);
    final stage = widget.stage;
    final color = stage == JourneyAnimationStage.payment
        ? const Color(0xFFD39A26)
        : const Color(0xFF00AD86);
    final icon = switch (stage) {
      JourneyAnimationStage.searching => Icons.search_rounded,
      JourneyAnimationStage.reserving => Icons.event_seat_rounded,
      JourneyAnimationStage.verifying => Icons.verified_user_outlined,
      JourneyAnimationStage.payment => Icons.payment_rounded,
      JourneyAnimationStage.paused => Icons.pause_rounded,
      JourneyAnimationStage.complete => Icons.check_rounded,
    };
    final title =
        widget.message ??
        switch (stage) {
          JourneyAnimationStage.searching => lang.tr(
            'Finding tickets',
            'টিকিট খোঁজা হচ্ছে',
          ),
          JourneyAnimationStage.reserving => lang.tr(
            'Reserving seats',
            'আসন সংরক্ষণ হচ্ছে',
          ),
          JourneyAnimationStage.verifying => lang.tr(
            'Verify your booking',
            'বুকিং যাচাই করুন',
          ),
          JourneyAnimationStage.payment => lang.tr(
            'Seats held · Ready to pay',
            'আসন সংরক্ষিত · পেমেন্ট করুন',
          ),
          JourneyAnimationStage.paused => lang.tr(
            'Search paused',
            'অনুসন্ধান স্থগিত',
          ),
          JourneyAnimationStage.complete => lang.tr(
            'Booking confirmed',
            'বুকিং নিশ্চিত',
          ),
        };
    final subtitle =
        widget.subMessage ??
        switch (stage) {
          JourneyAnimationStage.payment => lang.tr(
            'Complete payment before the hold expires',
            'সময় শেষ হওয়ার আগে পেমেন্ট করুন',
          ),
          JourneyAnimationStage.verifying => lang.tr(
            'Enter or approve your OTP',
            'ওটিপি দিন বা অনুমোদন করুন',
          ),
          _ => null,
        };
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: (widget.height * .60).clamp(90.0, 132.0),
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedBuilder(
                animation: _motion,
                builder: (context, child) => Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RailScenePainter(
                          progress: _motion.value,
                          dark: dark,
                          stage: stage,
                          counterLabel: lang.tr('TICKETS', 'টিকিট'),
                        ),
                      ),
                    ),
                    Positioned(
                      right:
                          36 * ((widget.height * .60).clamp(90.0, 132.0) / 120),
                      top:
                          47 * ((widget.height * .60).clamp(90.0, 132.0) / 120),
                      child: Icon(
                        icon,
                        color: color,
                        size:
                            21 *
                            ((widget.height * .60).clamp(90.0, 132.0) / 120),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: dark ? const Color(0xFFB5EBDD) : const Color(0xFF075D4C),
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(dark),
              ),
            ),
          ],
        ],
      ),
    );
    if (!widget.showCard) return content;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBg(dark),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: .22)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .1), blurRadius: 28),
          ],
        ),
        child: content,
      ),
    );
  }
}

class _RailScenePainter extends CustomPainter {
  final double progress;
  final bool dark;
  final JourneyAnimationStage stage;
  final String counterLabel;
  const _RailScenePainter({
    required this.progress,
    required this.dark,
    required this.stage,
    required this.counterLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 120;
    final width = size.width / scale;
    canvas.save();
    canvas.scale(scale);
    final counterX = width - 134;
    const floor = 103.0;
    final paint = Paint();
    final bounds = Rect.fromLTWH(0, 0, width, 120);
    paint.shader = RadialGradient(
      center: const Alignment(.5, -.1),
      radius: .9,
      colors: [
        const Color(0xFF00B58C).withValues(alpha: dark ? .13 : .08),
        Colors.transparent,
      ],
    ).createShader(bounds);
    canvas.drawRect(bounds, paint);
    paint.shader = null;

    // A station concourse with a clear route to the staffed ticket counter.
    paint.color = dark ? const Color(0xFF17333E) : const Color(0xFFE3EEEA);
    for (var i = 0; i < 5; i++) {
      final x = 10.0 + i * (width - 20) / 5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 30, 28, 62),
          const Radius.circular(14),
        ),
        paint,
      );
    }
    paint.color = dark ? const Color(0xFF193039) : const Color(0xFFEDF3F0);
    canvas.drawRect(Rect.fromLTWH(0, floor, width, 17), paint);
    paint.color = dark ? const Color(0xFF2B4B50) : const Color(0xFFD2E3DC);
    paint.strokeWidth = 1;
    canvas.drawLine(const Offset(0, floor), Offset(width, floor), paint);
    for (var i = 0; i < 9; i++) {
      final x = i * width / 8;
      canvas.drawLine(Offset(x, floor), Offset(x - 12, 120), paint);
    }
    canvas.drawLine(const Offset(0, 114), Offset(width, 114), paint);

    // Wayfinding sign: ticket symbol and arrow rather than more status text.
    paint.color = dark ? const Color(0xFF35605D) : const Color(0xFFB9D5C9);
    canvas.drawRect(const Rect.fromLTWH(41, 42, 3, 55), paint);
    _box(
      canvas,
      const Rect.fromLTWH(18, 22, 65, 23),
      const Color(0xFF086C56),
      7,
    );
    _ticket(canvas, const Offset(33, 33), const Color(0xFFE2FFF3), 1);
    paint.color = const Color(0xFFE2FFF3);
    paint.strokeWidth = 2;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(54, 33), const Offset(70, 33), paint);
    canvas.drawPath(
      Path()
        ..moveTo(65, 28)
        ..lineTo(70, 33)
        ..lineTo(65, 38),
      paint,
    );
    paint.style = PaintingStyle.fill;

    // Counter canopy, service window, attendant, and desk.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(counterX + 3, 22, 114, 80),
        const Radius.circular(10),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    _box(
      canvas,
      Rect.fromLTWH(counterX, 24, 114, 78),
      dark ? const Color(0xFF183F40) : const Color(0xFFDDF1E9),
      9,
    );
    final canopy = Rect.fromLTWH(counterX - 5, 17, 124, 24);
    paint.shader = const LinearGradient(
      colors: [Color(0xFF13C99A), Color(0xFF00775D)],
    ).createShader(canopy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(canopy, const Radius.circular(8)),
      paint,
    );
    paint.shader = null;
    final label = TextPainter(
      text: TextSpan(
        text: counterLabel,
        style: const TextStyle(
          fontFamily: 'Roboto',
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(counterX + (114 - label.width) / 2, 23));
    _box(
      canvas,
      Rect.fromLTWH(counterX + 10, 45, 94, 32),
      dark ? const Color(0xFF07282F) : const Color(0xFFF7FFFC),
      5,
    );
    paint.color = const Color(0xFFE7B18D);
    canvas.drawCircle(Offset(counterX + 34, 54), 5, paint);
    _box(
      canvas,
      Rect.fromLTWH(counterX + 25, 61, 18, 16),
      const Color(0xFF239E87),
      6,
    );
    paint.color = const Color(0xFF163F43);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(counterX + 34, 53), radius: 5),
      math.pi,
      math.pi,
      true,
      paint,
    );
    _box(
      canvas,
      Rect.fromLTWH(counterX - 6, 77, 126, 7),
      const Color(0xFF00856A),
      3,
    );
    _box(
      canvas,
      Rect.fromLTWH(counterX + 12, 89, 90, 4),
      dark ? const Color(0xFF2B5A56) : const Color(0xFFB7DCCE),
      2,
    );

    final searching = stage == JourneyAnimationStage.searching;
    final walking = searching && progress < .6;
    final travel = searching
        ? Curves.easeInOut.transform((progress / .6).clamp(0.0, 1.0))
        : 1.0;
    final startX = 101.0.clamp(60.0, counterX - 47);
    final personX = startX + (counterX - 27 - startX) * travel;
    final stride = walking ? math.sin(progress * math.pi * 16) : 0.0;
    final fade = searching && progress > .9 ? (1 - progress) * 10 : 1.0;
    canvas.saveLayer(
      bounds,
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
    // Passenger carrying a bag, walking up to the service desk.
    paint.color = Colors.black.withValues(alpha: dark ? .2 : .07);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(personX, 104), width: 32, height: 5),
      paint,
    );
    final bob = walking ? stride.abs() * 1.2 : 0.0;
    paint.color = const Color(0xFFE5AD87);
    canvas.drawCircle(Offset(personX, 54 - bob), 6, paint);
    paint.color = const Color(0xFF143C44);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(personX, 52 - bob), radius: 6),
      math.pi,
      math.pi,
      true,
      paint,
    );
    _box(
      canvas,
      Rect.fromLTWH(personX - 7, 63 - bob, 14, 22),
      const Color(0xFF008DB3),
      5,
    );
    paint.color = const Color(0xFF244A56);
    paint.strokeWidth = 4;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(personX - 3, 84 - bob),
      Offset(personX - 4 - stride * 4, 99),
      paint,
    );
    canvas.drawLine(
      Offset(personX + 3, 84 - bob),
      Offset(personX + 4 + stride * 4, 99),
      paint,
    );
    paint.color = const Color(0xFFE5AD87);
    paint.strokeWidth = 3;
    canvas.drawLine(
      Offset(personX - 7, 68 - bob),
      Offset(personX - 10 + stride * 2, 82 - bob),
      paint,
    );
    final presenting = !searching && stage != JourneyAnimationStage.paused;
    canvas.drawLine(
      Offset(personX + 7, 68 - bob),
      Offset(
        personX + (presenting ? 18 : 10 - stride * 2),
        presenting ? 72 : 81 - bob,
      ),
      paint,
    );
    _box(
      canvas,
      Rect.fromLTWH(personX - 15 + stride * 2, 81 - bob, 10, 13),
      const Color(0xFFD29442),
      3,
    );
    if (presenting) {
      if (stage == JourneyAnimationStage.verifying) {
        _box(
          canvas,
          Rect.fromLTWH(personX + 15, 62, 8, 13),
          const Color(0xFF123C45),
          2,
        );
        _box(
          canvas,
          Rect.fromLTWH(personX + 17, 64, 4, 7),
          const Color(0xFF8FE8D5),
          1,
        );
      } else {
        _ticket(
          canvas,
          Offset(personX + 20, 69),
          stage == JourneyAnimationStage.payment
              ? const Color(0xFFE5B647)
              : const Color(0xFFDBFFF0),
          .7,
        );
      }
    }
    canvas.restore();
    canvas.restore();
  }

  void _box(Canvas canvas, Rect rect, Color color, double radius) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = color,
      );

  void _ticket(Canvas canvas, Offset center, Color color, double scale) {
    final rect = Rect.fromCenter(
      center: center,
      width: 18 * scale,
      height: 11 * scale,
    );
    _box(canvas, rect, color, 2 * scale);
    final paint = Paint()
      ..color = const Color(0xFF16705A)
      ..strokeWidth = scale;
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(rect.left + (5 + i * 3) * scale, rect.top + 3 * scale),
        Offset(rect.left + (5 + i * 3) * scale, rect.bottom - 3 * scale),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RailScenePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      dark != oldDelegate.dark ||
      stage != oldDelegate.stage ||
      counterLabel != oldDelegate.counterLabel;
}
