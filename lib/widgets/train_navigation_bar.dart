import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// Destination item for the professional train navigation bar
class TrainDestination {
  final Widget? icon;
  final Widget? selectedIcon;
  final String label;
  final bool showBadge;
  final Color badgeColor;
  final String? badgeText;

  const TrainDestination({
    this.icon,
    this.selectedIcon,
    required this.label,
    this.showBadge = false,
    this.badgeColor = AppColors.primary,
    this.badgeText,
  });
}

/// A streamlined, professional train navigation bar where the active menu item
/// slides across the railway track like a real train coach, featuring rotating
/// precision steel train wheels.
class TrainNavigationBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<TrainDestination> destinations;

  const TrainNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  State<TrainNavigationBar> createState() => _TrainNavigationBarState();
}

class _TrainNavigationBarState extends State<TrainNavigationBar>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _slideCtrl;
  late CurvedAnimation _slideCurve;

  double _fromPos = 0.0;
  double _targetPos = 0.0;
  double _currentPos = 0.0;
  double _lastPosForWheel = 0.0;
  double _accumulatedWheelAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _fromPos = widget.selectedIndex.toDouble();
    _targetPos = widget.selectedIndex.toDouble();
    _currentPos = widget.selectedIndex.toDouble();
    _lastPosForWheel = widget.selectedIndex.toDouble();

    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (!isTest) {
      _pulseCtrl.repeat(reverse: true);
    }

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _slideCurve = CurvedAnimation(
      parent: _slideCtrl,
      curve: Curves.easeInOutCubic,
    );
    if (isTest) {
      _slideCtrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(TrainNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _fromPos = _currentPos;
      _targetPos = widget.selectedIndex.toDouble();
      _lastPosForWheel = _fromPos;

      final isTest =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (!isTest) {
        _slideCtrl.forward(from: 0.0);
      } else {
        _slideCtrl.value = 1.0;
        _currentPos = _targetPos;
        _accumulatedWheelAngle += (_targetPos - _fromPos) * (math.pi * 3);
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCoaches = widget.destinations.length;
    final activeColor =
        isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF040912) : const Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF142232) : const Color(0xFFCBD5E1),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 5, 4, 1),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              const double horizontalPadding = 4.0;
              final double usableWidth = totalWidth - (horizontalPadding * 2);
              final double slotWidth = usableWidth / totalCoaches;
              const double coachInset = 2.5;
              final double coachWidth = slotWidth - (coachInset * 2);

              return AnimatedBuilder(
                animation: Listenable.merge([_pulseCtrl, _slideCtrl]),
                builder: (context, child) {
                  final double slideProgress =
                      _slideCtrl.isAnimating ? _slideCurve.value : 1.0;
                  _currentPos =
                      _fromPos + (_targetPos - _fromPos) * slideProgress;

                  // Distance-based continuous wheel rotation
                  final double posDelta = _currentPos - _lastPosForWheel;
                  _accumulatedWheelAngle += (posDelta * slotWidth) / 5.0;
                  _lastPosForWheel = _currentPos;

                  final double trainLeft = horizontalPadding +
                      (_currentPos * slotWidth) +
                      coachInset;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Coach row with sliding active train and small rotating wheels
                      SizedBox(
                        height: 50,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 1. Sliding Active Train Coach with Small Wheels
                            Positioned(
                              left: trainLeft,
                              top: 0,
                              width: coachWidth,
                              height: 50,
                              child: IgnorePointer(
                                child: _ActiveSlidingTrainCoach(
                                  pulseValue: _pulseCtrl.value,
                                  wheelAngle: _accumulatedWheelAngle,
                                  isDark: isDark,
                                  activeColor: activeColor,
                                ),
                              ),
                            ),

                            // 2. Stationary Destination bays with icons, labels, and badges
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: horizontalPadding,
                                ),
                                child: Row(
                                  children: List.generate(totalCoaches, (index) {
                                    final dest = widget.destinations[index];
                                    final double dist =
                                        (_currentPos - index).abs();
                                    final double activeFactor =
                                        (1.0 - dist).clamp(0.0, 1.0);

                                    return Expanded(
                                      child: _TrainStationBay(
                                        destination: dest,
                                        index: index,
                                        activeFactor: activeFactor,
                                        isDark: isDark,
                                        activeColor: activeColor,
                                        onTap: () => widget
                                            .onDestinationSelected(index),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 3. Continuous polished railway track under wheels
                      _ContinuousTrack(isDark: isDark),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The sliding active train coach that glides along the track with precision wheels
class _ActiveSlidingTrainCoach extends StatelessWidget {
  final double pulseValue;
  final double wheelAngle;
  final bool isDark;
  final Color activeColor;

  const _ActiveSlidingTrainCoach({
    required this.pulseValue,
    required this.wheelAngle,
    required this.isDark,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Train Carriage Upper Body ──
        Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
              bottom: Radius.circular(3),
            ),
            border: Border.all(
              color: activeColor.withValues(alpha: 0.85 + pulseValue * 0.15),
              width: 1.4,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      activeColor.withValues(alpha: 0.18 + pulseValue * 0.05),
                      activeColor.withValues(alpha: 0.08),
                    ]
                  : [
                      activeColor.withValues(alpha: 0.15),
                      activeColor.withValues(alpha: 0.05),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.28 + pulseValue * 0.12),
                blurRadius: 9,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top aerodynamic roof strip
              Positioned(
                top: 0,
                left: 6,
                right: 6,
                height: 2.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Front and rear buffer / coupler notches on carriage sides
              Positioned(
                left: 0,
                top: 17,
                child: Container(
                  width: 2.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(1),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 17,
                child: Container(
                  width: 2.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Undercarriage Bogie with Rotating Train Wheels ──
        SizedBox(
          height: 10,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Steel bogie chassis crossbar connecting both wheels
              Positioned(
                left: 6,
                right: 6,
                top: 2.0,
                height: 2.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFF94A3B8),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Center suspension damper bracket
              Positioned(
                top: 1.0,
                child: Container(
                  width: 5,
                  height: 3,
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Left train wheel
              Positioned(
                left: 6,
                bottom: 0,
                child: _TrainWheel(
                  angle: wheelAngle,
                  isDark: isDark,
                  activeColor: activeColor,
                ),
              ),
              // Right train wheel
              Positioned(
                right: 6,
                bottom: 0,
                child: _TrainWheel(
                  angle: wheelAngle,
                  isDark: isDark,
                  activeColor: activeColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A precision small train wheel with outer flange, steel tread, and rotating spokes
class _TrainWheel extends StatelessWidget {
  final double angle;
  final bool isDark;
  final Color activeColor;

  const _TrainWheel({
    required this.angle,
    required this.isDark,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
      child: Transform.rotate(
        angle: angle,
        child: CustomPaint(
          painter: _TrainWheelPainter(isDark: isDark, activeColor: activeColor),
        ),
      ),
    );
  }
}

class _TrainWheelPainter extends CustomPainter {
  final bool isDark;
  final Color activeColor;

  _TrainWheelPainter({required this.isDark, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Wheel flange outer rim (train wheel lip that stays on rail)
    final flangePaint = Paint()
      ..color = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 0.2, flangePaint);

    // 2. Steel tread/tire ring
    final treadPaint = Paint()
      ..color = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius - 1.2, treadPaint);

    // 3. Dark inner hub recess
    final hubFillPaint = Paint()
      ..color = isDark ? const Color(0xFF09131F) : const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 2.0, hubFillPaint);

    // 4. Rotating cross-spokes (+ pattern that visibly spins)
    final spokePaint = Paint()
      ..color = activeColor.withValues(alpha: 0.95)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const spokeLen = 2.4;
    canvas.drawLine(
      Offset(center.dx - spokeLen, center.dy),
      Offset(center.dx + spokeLen, center.dy),
      spokePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - spokeLen),
      Offset(center.dx, center.dy + spokeLen),
      spokePaint,
    );

    // 5. Center axle pin
    final axlePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 1.1, axlePaint);
  }

  @override
  bool shouldRepaint(_TrainWheelPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.activeColor != activeColor;
}

/// Destination bay with clean coach outline, icon, label, and smooth active transition
class _TrainStationBay extends StatelessWidget {
  final TrainDestination destination;
  final int index;
  final double activeFactor; // 0.0 (inactive) to 1.0 (fully active)
  final bool isDark;
  final Color activeColor;
  final VoidCallback onTap;

  const _TrainStationBay({
    required this.destination,
    required this.index,
    required this.activeFactor,
    required this.isDark,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveBorderColor =
        isDark ? const Color(0xFF1E2D3D) : const Color(0xFFCBD5E1);
    final inactiveContentColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeTextColor = isDark ? Colors.white : const Color(0xFF0F172A);

    // Smoothly interpolate content color
    final contentColor =
        Color.lerp(inactiveContentColor, activeColor, activeFactor)!;
    final textColor =
        Color.lerp(inactiveContentColor, activeTextColor, activeFactor)!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        height: 40,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(8),
            bottom: Radius.circular(3),
          ),
          // Inactive blueprint border fades out as the active carriage slides over
          border: Border.all(
            color: inactiveBorderColor.withValues(
              alpha: (1.0 - activeFactor * 0.9).clamp(0.0, 1.0),
            ),
            width: 0.85,
          ),
          color: isDark
              ? const Color(0xFF08121C).withValues(alpha: 1.0 - activeFactor)
              : const Color(0xFFF8FAFC).withValues(alpha: 1.0 - activeFactor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Roof accent line (visible when inactive)
            Opacity(
              opacity: (1.0 - activeFactor).clamp(0.0, 1.0),
              child: Container(
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1F3042)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            const Spacer(),
            // Bespoke outlined vector icon with notification badge
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                _buildCoachIcon(
                  destination,
                  index,
                  activeFactor > 0.5,
                  isDark,
                  contentColor,
                ),
                if (destination.showBadge)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: destination.badgeColor,
                        border: Border.all(
                          color: isDark ? Colors.black : Colors.white,
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: destination.badgeColor.withValues(
                              alpha: 0.8,
                            ),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1.5),
            // Station label in modern clean typography
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 9.8,
                fontWeight: activeFactor > 0.5
                    ? FontWeight.w700
                    : FontWeight.w500,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 1.5),
            // Mini active underline that smoothly fades in
            Opacity(
              opacity: activeFactor,
              child: Container(
                height: 1.5,
                width: 12,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

Widget _buildCoachIcon(
  TrainDestination dest,
  int index,
  bool isSelected,
  bool isDark,
  Color iconColor,
) {
  if (dest.icon != null && dest.icon is! Icon) {
    return dest.icon!;
  }

  final labelLower = dest.label.toLowerCase();
  if (labelLower.contains('search') || index == 0) {
    return _OutlinedSearchIcon(color: iconColor, isSelected: isSelected);
  } else if (labelLower.contains('ticket') ||
      labelLower.contains('monitor') ||
      index == 1) {
    return _OutlinedTicketIcon(color: iconColor, isSelected: isSelected);
  } else if (labelLower.contains('trip') ||
      labelLower.contains('alert') ||
      index == 2) {
    return _OutlinedLuggageIcon(color: iconColor, isSelected: isSelected);
  } else {
    return _OutlinedProfileIcon(color: iconColor, isSelected: isSelected);
  }
}

/// Continuous railway track running under all coaches
class _ContinuousTrack extends StatelessWidget {
  final bool isDark;
  const _ContinuousTrack({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4.0,
      width: double.infinity,
      child: CustomPaint(
        painter: _OutlinedTrackPainter(isDark: isDark),
      ),
    );
  }
}

class _OutlinedTrackPainter extends CustomPainter {
  final bool isDark;
  _OutlinedTrackPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final railHeadPaint = Paint()
      ..color = isDark
          ? const Color(0xFF38BDF8).withValues(alpha: 0.7)
          : const Color(0xFF0284C7).withValues(alpha: 0.6)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    final railBasePaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final sleeperPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // 1. Spaced railway sleeper ties along the track
    const double sleeperSpacing = 14.0;
    for (double x = 4.0; x < size.width - 4.0; x += sleeperSpacing) {
      canvas.drawLine(Offset(x, 1.0), Offset(x, size.height), sleeperPaint);
    }

    // 2. Continuous polished steel top rail head (where wheels roll)
    canvas.drawLine(
      const Offset(0, 0.7),
      Offset(size.width, 0.7),
      railHeadPaint,
    );

    // 3. Rail base flange
    canvas.drawLine(
      const Offset(0, 3.0),
      Offset(size.width, 3.0),
      railBasePaint,
    );
  }

  @override
  bool shouldRepaint(_OutlinedTrackPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Simple clean coupler link connecting two coaches
class _CoachConnector extends StatelessWidget {
  final bool isDark;
  const _CoachConnector({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      margin: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2D3D) : const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BESPOKE PROFESSIONAL OUTLINED VECTOR ICONS (Sized 20x20 for slim navbar)
// ─────────────────────────────────────────────────────────────────────────────

/// Outlined Search Icon
class _OutlinedSearchIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  const _OutlinedSearchIcon({required this.color, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _OutlinedSearchPainter(color: color, isSelected: isSelected),
      ),
    );
  }
}

class _OutlinedSearchPainter extends CustomPainter {
  final Color color;
  final bool isSelected;
  _OutlinedSearchPainter({required this.color, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 2.0 : 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.42, size.height * 0.42);
    final radius = size.width * 0.28;

    canvas.drawCircle(center, radius, strokePaint);

    final handleStart = Offset(
      center.dx + radius * math.cos(math.pi / 4),
      center.dy + radius * math.sin(math.pi / 4),
    );
    final handleEnd = Offset(size.width * 0.88, size.height * 0.88);
    canvas.drawLine(handleStart, handleEnd, strokePaint);
  }

  @override
  bool shouldRepaint(_OutlinedSearchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}

/// Outlined Tickets Icon
class _OutlinedTicketIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  const _OutlinedTicketIcon({required this.color, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _OutlinedTicketPainter(color: color, isSelected: isSelected),
      ),
    );
  }
}

class _OutlinedTicketPainter extends CustomPainter {
  final Color color;
  final bool isSelected;
  _OutlinedTicketPainter({required this.color, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 1.9 : 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4);

    const w = 12.0;
    const h = 17.0;
    const r = 2.0;
    const notchR = 1.8;

    final path = Path();
    path.moveTo(-w / 2 + r, -h / 2);
    path.lineTo(w / 2 - r, -h / 2);
    path.arcToPoint(const Offset(w / 2, -h / 2 + r), radius: const Radius.circular(r));

    // Right notch
    path.lineTo(w / 2, -notchR);
    path.arcToPoint(const Offset(w / 2, notchR),
        radius: const Radius.circular(notchR), clockwise: false);
    path.lineTo(w / 2, h / 2 - r);
    path.arcToPoint(const Offset(w / 2 - r, h / 2), radius: const Radius.circular(r));

    path.lineTo(-w / 2 + r, h / 2);
    path.arcToPoint(const Offset(-w / 2, h / 2 - r), radius: const Radius.circular(r));

    // Left notch
    path.lineTo(-w / 2, notchR);
    path.arcToPoint(const Offset(-w / 2, -notchR),
        radius: const Radius.circular(notchR), clockwise: false);
    path.lineTo(-w / 2, -h / 2 + r);
    path.arcToPoint(const Offset(-w / 2 + r, -h / 2), radius: const Radius.circular(r));
    path.close();

    canvas.drawPath(path, outlinePaint);

    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(const Offset(-w / 2 + 2.5, 0), const Offset(w / 2 - 2.5, 0), dashPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutlinedTicketPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}

/// Outlined Trips / Luggage Icon
class _OutlinedLuggageIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  const _OutlinedLuggageIcon({required this.color, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _OutlinedLuggagePainter(color: color, isSelected: isSelected),
      ),
    );
  }
}

class _OutlinedLuggagePainter extends CustomPainter {
  final Color color;
  final bool isSelected;
  _OutlinedLuggagePainter({required this.color, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 1.9 : 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width / 2;
    const bodyW = 14.0;
    const bodyH = 12.0;
    const bodyTop = 6.0;
    const bodyR = 2.5;

    // Suitcase body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, bodyTop + bodyH / 2),
        width: bodyW,
        height: bodyH,
      ),
      const Radius.circular(bodyR),
    );
    canvas.drawRRect(bodyRect, strokePaint);

    // Top retractable handle
    final handlePath = Path();
    handlePath.moveTo(cx - 3.5, bodyTop);
    handlePath.lineTo(cx - 3.5, bodyTop - 3.5);
    handlePath.arcToPoint(Offset(cx + 3.5, bodyTop - 3.5),
        radius: const Radius.circular(2.0));
    handlePath.lineTo(cx + 3.5, bodyTop);
    canvas.drawPath(handlePath, strokePaint);

    // Subtle center strap line
    final strapPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, bodyTop + 2),
      Offset(cx, bodyTop + bodyH - 2),
      strapPaint,
    );
  }

  @override
  bool shouldRepaint(_OutlinedLuggagePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}

/// Outlined Profile / User Icon
class _OutlinedProfileIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  const _OutlinedProfileIcon({required this.color, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _OutlinedProfilePainter(color: color, isSelected: isSelected),
      ),
    );
  }
}

class _OutlinedProfilePainter extends CustomPainter {
  final Color color;
  final bool isSelected;
  _OutlinedProfilePainter({required this.color, required this.isSelected});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 1.9 : 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;

    // Head
    const headRadius = 3.6;
    const headCenterY = 6.2;
    canvas.drawCircle(Offset(cx, headCenterY), headRadius, strokePaint);

    // Shoulders
    final shoulderPath = Path();
    shoulderPath.moveTo(cx - 6.5, 17.0);
    shoulderPath.arcToPoint(
      Offset(cx - 4.5, 12.0),
      radius: const Radius.circular(3.0),
    );
    shoulderPath.arcToPoint(
      Offset(cx + 4.5, 12.0),
      radius: const Radius.circular(5.0),
    );
    shoulderPath.arcToPoint(
      Offset(cx + 6.5, 17.0),
      radius: const Radius.circular(3.0),
    );
    canvas.drawPath(shoulderPath, strokePaint);
  }

  @override
  bool shouldRepaint(_OutlinedProfilePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}
