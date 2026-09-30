import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';

/// Destination item for the bottom navigation bar.
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

/// A floating, rounded navigation bar. The active destination is a sleek
/// emerald "coach" that glides along a fine rail, its two small wheels
/// turning with the distance travelled. The coach has a front (nose with a
/// headlight) and a tail (with a red tail light) and faces the direction it
/// is travelling.
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
    with SingleTickerProviderStateMixin {
  static const double _barHeight = 70;
  static const double _sidePad = 6;

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;

  double _from = 0;
  double _target = 0;
  double _current = 0;
  double _lastWheelPos = 0;
  double _wheelAngle = 0;
  double _dir = 1; // 1 = facing right, -1 = facing left

  @override
  void initState() {
    super.initState();
    _from = _target = _current = _lastWheelPos = widget.selectedIndex.toDouble();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  }

  @override
  void didUpdateWidget(TrainNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _dir = widget.selectedIndex > oldWidget.selectedIndex ? 1 : -1;
      _from = _current;
      _target = widget.selectedIndex.toDouble();
      _lastWheelPos = _from;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index != widget.selectedIndex) HapticFeedback.selectionClick();
    widget.onDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = widget.destinations.length;
    final barColor = isDark ? AppColors.darkCard : Colors.white;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              height: _barHeight,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.cardBorder(isDark)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.10),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final slot = (constraints.maxWidth - _sidePad * 2) / count;

                    return AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, _) {
                        final t = _ctrl.isAnimating ? _curve.value : 1.0;
                        _current = _from + (_target - _from) * t;
                        _wheelAngle += (_current - _lastWheelPos) * slot / 4.0;
                        _lastWheelPos = _current;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Fine rail running under the whole bar
                            Positioned(
                              left: 18,
                              right: 18,
                              bottom: 6,
                              height: 3,
                              child: CustomPaint(
                                painter: _RailPainter(
                                  color: AppColors.textMuted(isDark).withValues(alpha: 0.30),
                                ),
                              ),
                            ),

                            // Sliding active coach
                            Positioned(
                              left: _sidePad + _current * slot + 4,
                              top: 7,
                              width: slot - 8,
                              height: 50,
                              child: IgnorePointer(
                                child: _ActiveCoach(
                                  wheelAngle: _wheelAngle,
                                  isDark: isDark,
                                  barColor: barColor,
                                  direction: _dir,
                                ),
                              ),
                            ),

                            // Destinations
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: _sidePad),
                                child: Row(
                                  children: List.generate(count, (i) {
                                    final dist = (_current - i).abs();
                                    final factor = (1.0 - dist).clamp(0.0, 1.0);
                                    return Expanded(
                                      child: _NavItem(
                                        destination: widget.destinations[i],
                                        index: i,
                                        activeFactor: factor,
                                        isDark: isDark,
                                        barColor: barColor,
                                        onTap: () => _select(i),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active coach (gradient pill + nose/tail + lights + wheels)
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveCoach extends StatelessWidget {
  final double wheelAngle;
  final bool isDark;
  final Color barColor;
  final double direction; // 1 = facing right, -1 = facing left

  const _ActiveCoach({
    required this.wheelAngle,
    required this.isDark,
    required this.barColor,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: direction),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, f, _) {
        // f: -1 (facing left) ... 1 (facing right)
        final t = (f + 1) / 2; // 0 = left, 1 = right

        // Long sloped nose at the front, blunt squared tail at the back.
        const noseTop = 26.0, noseBottom = 16.0;
        const tailTop = 10.0, tailBottom = 7.0;
        final radius = BorderRadius.only(
          topRight: Radius.circular(lerpDouble(tailTop, noseTop, t)!),
          bottomRight: Radius.circular(lerpDouble(tailBottom, noseBottom, t)!),
          topLeft: Radius.circular(lerpDouble(noseTop, tailTop, t)!),
          bottomLeft: Radius.circular(lerpDouble(noseBottom, tailBottom, t)!),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: isDark ? 0.34 : 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
            // Soft top sheen
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.24),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.55],
                  ),
                ),
              ),
            ),
            // Headlight (front)
            Positioned.fill(
              child: Align(
                alignment: Alignment(f * 0.93, 0.05),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFF4C2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFE27A).withValues(alpha: 0.85),
                        blurRadius: 8,
                        spreadRadius: 1.5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Tail light (back)
            Positioned.fill(
              child: Align(
                alignment: Alignment(-f * 0.93, 0.05),
                child: Container(
                  width: 3.5,
                  height: 9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: const Color(0xFFFF5A5F),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5A5F).withValues(alpha: 0.6),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: -5,
              child: _Wheel(angle: wheelAngle, isDark: isDark, fill: barColor),
            ),
            Positioned(
              right: 16,
              bottom: -5,
              child: _Wheel(angle: wheelAngle, isDark: isDark, fill: barColor),
            ),
          ],
        );
      },
    );
  }
}

class _Wheel extends StatelessWidget {
  final double angle;
  final bool isDark;
  final Color fill;
  const _Wheel({required this.angle, required this.isDark, required this.fill});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 9,
      height: 9,
      child: Transform.rotate(
        angle: angle,
        child: CustomPaint(painter: _WheelPainter(isDark: isDark, fill: fill)),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final bool isDark;
  final Color fill;
  _WheelPainter({required this.isDark, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final steel = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);

    canvas.drawCircle(c, r - 0.6, Paint()..color = fill);
    canvas.drawCircle(
      c,
      r - 0.7,
      Paint()
        ..color = steel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    final spoke = Paint()
      ..color = steel.withValues(alpha: 0.9)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r + 1.6, c.dy), Offset(c.dx + r - 1.6, c.dy), spoke);
    canvas.drawLine(Offset(c.dx, c.dy - r + 1.6), Offset(c.dx, c.dy + r - 1.6), spoke);
    canvas.drawCircle(c, 1, Paint()..color = AppColors.primaryDark);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.isDark != isDark || old.fill != fill;
}

class _RailPainter extends CustomPainter {
  final Color color;
  _RailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 0.7), Offset(size.width, 0.7), rail);

    final sleeper = Paint()
      ..color = color.withValues(alpha: color.a * 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double x = 2; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, 0.7), Offset(x, size.height), sleeper);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Destination item
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final TrainDestination destination;
  final int index;
  final double activeFactor; // 0 = inactive, 1 = fully active
  final bool isDark;
  final Color barColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.index,
    required this.activeFactor,
    required this.isDark,
    required this.barColor,
    required this.onTap,
  });

  static const Color _activeInk = Color(0xFF04261C);

  Widget _icon(bool selected, Color color) {
    final custom = selected && destination.selectedIcon != null
        ? destination.selectedIcon
        : destination.icon;
    if (custom != null) {
      return IconTheme(
        data: IconThemeData(color: color, size: 22),
        child: custom,
      );
    }

    final label = destination.label.toLowerCase();
    final IconData data;
    if (label.contains('search') || index == 0) {
      data = Icons.search_rounded;
    } else if (label.contains('ticket') || label.contains('monitor') || index == 1) {
      data = selected ? Icons.confirmation_number_rounded : Icons.confirmation_number_outlined;
    } else if (label.contains('trip') || label.contains('alert') || index == 2) {
      data = selected ? Icons.luggage_rounded : Icons.luggage_outlined;
    } else {
      data = selected ? Icons.person_rounded : Icons.person_outline_rounded;
    }
    return Icon(data, size: 22, color: color);
  }

  Widget _badge() {
    final base = destination.badgeColor;
    // A badge in the brand colour would vanish on the emerald coach.
    final dot = Color.lerp(
      base,
      base == AppColors.primary ? _activeInk : base,
      activeFactor,
    )!;
    final ring = Color.lerp(barColor, AppColors.primary, activeFactor)!;
    final text = destination.badgeText;

    if (text != null && text.isNotEmpty) {
      return Container(
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dot,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ring, width: 1.5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      );
    }

    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dot,
        border: Border.all(color: ring, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inactive = AppColors.textMuted(isDark);
    final color = Color.lerp(inactive, _activeInk, activeFactor)!;
    final selected = activeFactor > 0.5;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 13),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: 1 + 0.08 * activeFactor,
                    child: _icon(selected, color),
                  ),
                  if (destination.showBadge)
                    Positioned(top: -4, right: -7, child: _badge()),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.2,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}