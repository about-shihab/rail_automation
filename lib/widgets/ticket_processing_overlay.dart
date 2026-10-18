import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_theme.dart';
import '../services/turnstile_session.dart';

/// Full-screen in-app overlay shown while a booking is being processed.
///
/// Cloudflare Turnstile runs inside it in `interaction-only` mode:
///  * most of the time it solves invisibly → the user only sees the animation
///  * only if Cloudflare really needs a click, the checkbox slides in
///
/// Pops with the solved token (String) or null when cancelled.
/// Normally opened through `TurnstileGate`, not directly.
class TicketProcessingOverlay extends StatefulWidget {
  const TicketProcessingOverlay({
    super.key,
    this.contextLabel = '',
    this.tokenRequest,
  });

  /// e.g. "SUBARNA EXPRESS · SNIGDHA"
  final String contextLabel;
  final Future<String?>? tokenRequest;

  @override
  State<TicketProcessingOverlay> createState() =>
      _TicketProcessingOverlayState();
}

enum _Phase { connecting, interactive, success, error }

class _TicketProcessingOverlayState extends State<TicketProcessingOverlay>
    with TickerProviderStateMixin {
  static const double _sceneH = 168;

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  final _session = TurnstileSession.instance;
  _Phase _phase = _Phase.connecting;
  String? _error;
  bool _started = false;
  bool _hasPendingRequest = false;
  Future<String?>? _suppliedRequest;

  bool get _animate => !MediaQuery.disableAnimationsOf(context);
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _suppliedRequest = widget.tokenRequest;
    _session.addListener(_onSessionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animate && _phase == _Phase.connecting) {
      _loop.repeat();
      _pulse.repeat(reverse: true);
    } else {
      _loop.stop();
      _pulse.stop();
    }
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleMicrotask(() {
          if (mounted) unawaited(_load());
        });
      });
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    if (_hasPendingRequest) _session.cancel();
    _loop.dispose();
    _pulse.dispose();
    _burst.dispose();
    super.dispose();
  }

  // ── Logic ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (_isIos || _session.generating) _onSessionChanged();
    _hasPendingRequest = true;
    final supplied = _suppliedRequest;
    _suppliedRequest = null;
    final token = await (supplied ?? _session.generateWhenAttached());
    _hasPendingRequest = false;
    // Return immediately: animation must never delay submitting a fresh token.
    if (mounted && token != null) Navigator.of(context).pop(token);
    if (mounted && token == null) {
      if (_isIos) {
        _fail(_session.error ?? 'Security check is not ready. Please retry.');
      } else if (!_session.attached) {
        _fail('Security check is not ready. Please reopen the app.');
      }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    _loop.stop();
    _pulse.stop();
    setState(() {
      _phase = _Phase.error;
      _error = message;
    });
  }

  void _onSessionChanged() {
    if (!mounted) return;
    switch (_session.phase) {
      case TurnstilePhase.interactive:
        setState(() => _phase = _Phase.interactive);
      case TurnstilePhase.connecting:
        setState(() => _phase = _Phase.connecting);
      case TurnstilePhase.success:
        setState(() => _phase = _Phase.success);
      case TurnstilePhase.error:
        _fail(_session.error ?? 'Verification failed. Please retry.');
      case TurnstilePhase.idle:
        break;
    }
  }

  void _retry() {
    HapticFeedback.selectionClick();
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    if (_animate) {
      _loop.repeat();
      _pulse.repeat(reverse: true);
    }
    unawaited(_load());
  }

  void _cancel() {
    if (_phase == _Phase.success) return;
    if (_hasPendingRequest) _session.cancel();
    Navigator.of(context).pop();
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  Color get _accent => switch (_phase) {
    _Phase.success => AppColors.success,
    _Phase.error => AppColors.error,
    _ => AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Blurred scrim – swallows touches so nothing underneath is hit.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 520),
                      curve: Curves.easeOutBack,
                      builder: (_, v, child) => Opacity(
                        opacity: v.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, 28 * (1 - v)),
                          child: Transform.scale(
                            scale: 0.92 + 0.08 * v,
                            child: child,
                          ),
                        ),
                      ),
                      child: _ticket(isDark),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticket(bool isDark) {
    return PhysicalShape(
      clipper: const _TicketClipper(notchY: _sceneH),
      color: AppColors.surface(isDark),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: _sceneH, child: _scene()),
              _body(isDark),
            ],
          ),
          Positioned(
            left: 20,
            right: 20,
            top: _sceneH - 0.5,
            height: 1,
            child: CustomPaint(
              painter: _DashPainter(AppColors.cardBorder(isDark)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scene() {
    final ok = _phase == _Phase.success;
    final err = _phase == _Phase.error;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_loop, _pulse, _burst]),
            builder: (_, _) => CustomPaint(
              painter: _ScenePainter(
                loop: _loop.value,
                pulse: _pulse.value,
                burst: _burst.value,
                success: ok,
                error: err,
                accent: _accent,
              ),
            ),
          ),
        ),
        // Header: boarding-pass chip + train label + close
        Positioned(
          left: 16,
          top: 12,
          right: 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.confirmation_number_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'TICKET PROCESSING',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.contextLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.contextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!ok)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cancel',
                  onPressed: _cancel,
                ),
            ],
          ),
        ),
        // "VERIFIED" stamp slams onto the scene on success
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: AnimatedOpacity(
              opacity: ok ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: AnimatedScale(
                scale: ok ? 1 : 2.6,
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutBack,
                child: Transform.rotate(angle: -0.12, child: const _Stamp()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(bool isDark) {
    final accent = _accent;
    final interactive = _phase == _Phase.interactive;
    final showChallenge =
        interactive ||
        (defaultTargetPlatform == TargetPlatform.iOS &&
            _phase == _Phase.connecting);

    final title = switch (_phase) {
      _Phase.connecting => 'Checking access',
      _Phase.interactive => 'Verify to continue',
      _Phase.success => 'Verified!',
      _Phase.error => 'Couldn\u2019t verify',
    };
    final subtitle = switch (_phase) {
      _Phase.connecting => 'Please wait…',
      _Phase.interactive => 'Complete the check below.',
      _Phase.success => 'Loading available seats\u2026',
      _Phase.error => _error ?? 'Something went wrong.',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(a),
                child: c,
              ),
            ),
            child: Column(
              key: ValueKey(_phase),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: _phase == _Phase.success
                  ? 1
                  : (_phase == _Phase.error ? 0 : (_animate ? null : 0.4)),
              minHeight: 5,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
          ),
          // iOS needs a painted WKWebView while checking, before Cloudflare
          // requests interaction. Keep Android's existing compact flow.
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: showChallenge ? 14 : 0),
              child: Column(
                children: [
                  ClipRect(
                    child: Align(
                      heightFactor: showChallenge ? 1 : 0,
                      child: SizedBox(
                        height: 170,
                        child: Center(
                          child: CompositedTransformTarget(
                            link: _session.challengeLink,
                            child: const SizedBox(width: 150, height: 170),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_phase == _Phase.error) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Small widgets
// ═════════════════════════════════════════════════════════════════════════════

class _Stamp extends StatelessWidget {
  const _Stamp();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.success, width: 2.5),
      boxShadow: [
        BoxShadow(
          color: AppColors.success.withValues(alpha: 0.45),
          blurRadius: 18,
        ),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, color: AppColors.success, size: 22),
        SizedBox(width: 6),
        Text(
          'VERIFIED',
          style: TextStyle(
            color: AppColors.success,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ],
    ),
  );
}

class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper({required this.notchY});
  final double notchY;
  static const double radius = 24, notchR = 11;

  @override
  Path getClip(Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final left = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, notchY), radius: notchR));
    final right = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(size.width, notchY), radius: notchR),
      );
    return Path.combine(
      PathOperation.difference,
      Path.combine(PathOperation.difference, body, left),
      right,
    );
  }

  @override
  bool shouldReclip(covariant _TicketClipper old) => old.notchY != notchY;
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + 6, size.width), 0.5),
        p,
      );
      x += 12;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// Night-train scene
// ═════════════════════════════════════════════════════════════════════════════

/// Seamless parallax loop: every layer's offset is `loop * period * n`, so the
/// pattern is identical at loop = 0 and loop = 1 (no jump when it repeats and
/// the train "stops" cleanly when the loop is animated to 1.0 on success).
class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.loop,
    required this.pulse,
    required this.burst,
    required this.success,
    required this.error,
    required this.accent,
  });

  final double loop, pulse, burst;
  final bool success, error;
  final Color accent;

  static const _bW = [24.0, 20.0, 28.0, 26.0, 22.0, 20.0]; // sum 140
  static const _bH = [30.0, 48.0, 26.0, 58.0, 38.0, 20.0];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final groundY = h - 34;

    // Sky
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          const [Color(0xFF04101F), Color(0xFF0A3B3A), Color(0xFF0F5C4D)],
          const [0, 0.66, 1],
        ),
    );

    // Moon glow
    final moon = Offset(w * 0.84, h * 0.34);
    canvas.drawCircle(
      moon,
      22 + 3 * pulse,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(moon, 8, Paint()..color = const Color(0xFFEFF7F5));

    // Stars
    final rnd = math.Random(7);
    for (var i = 0; i < 26; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h * 0.5;
      final r = 0.6 + rnd.nextDouble() * 0.9;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(pulse * math.pi * 2 + i));
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: tw * 0.8),
      );
    }

    // Far skyline (slow)
    const farP = 140.0;
    final farOff = loop * farP;
    final far = Paint()..color = const Color(0xFF0B2A33);
    for (var k = -1; k <= (w / farP).ceil() + 1; k++) {
      var x = k * farP - farOff;
      for (var i = 0; i < _bW.length; i++) {
        canvas.drawRect(
          Rect.fromLTWH(x, groundY - _bH[i], _bW[i] - 2, _bH[i]),
          far,
        );
        // a few lit windows
        if (i.isEven) {
          canvas.drawRect(
            Rect.fromLTWH(x + 5, groundY - _bH[i] + 8, 3, 3),
            Paint()
              ..color = const Color(0xFFFBBF24)
                  .withValues(alpha: 0.35 + 0.35 * pulse),
          );
        }
        x += _bW[i];
      }
    }

    // Ground
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, w, h - groundY),
      Paint()..color = const Color(0xFF06131C),
    );

    // Telegraph poles (fast, same speed as sleepers)
    const poleP = 96.0;
    final poleOff = loop * poleP * 3;
    final pole = Paint()
      ..color = const Color(0xFF1B3B4A)
      ..strokeWidth = 2;
    for (var k = -1; k <= (w / poleP).ceil() + 1; k++) {
      final x = k * poleP - poleOff + 30;
      canvas.drawLine(Offset(x, groundY + 2), Offset(x, groundY - 40), pole);
      canvas.drawLine(
        Offset(x - 7, groundY - 36),
        Offset(x + 7, groundY - 36),
        pole,
      );
    }

    // Rail + sleepers
    const sleeperP = 24.0;
    final sleeperOff = loop * sleeperP * 12;
    final sleeper = Paint()..color = const Color(0xFF2A4658);
    for (var k = -1; k <= (w / sleeperP).ceil() + 1; k++) {
      final x = k * sleeperP - sleeperOff;
      canvas.drawRect(Rect.fromLTWH(x, groundY + 7, 12, 4), sleeper);
    }
    canvas.drawRect(
      Rect.fromLTWH(0, groundY + 4, w, 2.4),
      Paint()..color = const Color(0xFF9DB6C4),
    );

    // Speed lines
    if (!success && !error) {
      final lr = math.Random(3);
      for (var i = 0; i < 7; i++) {
        final baseX = lr.nextDouble() * w;
        final y = groundY - 52 + lr.nextDouble() * 52;
        final len = 16 + lr.nextDouble() * 26;
        final x = ((baseX - loop * w * 2) % w + w) % w;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + len, y),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.16)
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    _train(canvas, w, groundY);

    // Success burst: sparkles + shock ring above the train
    if (success && burst > 0 && burst < 1) {
      final c = Offset(w / 2, groundY - 30);
      final e = Curves.easeOutCubic.transform(burst);
      canvas.drawCircle(
        c,
        10 + 90 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = AppColors.success.withValues(alpha: (1 - burst) * 0.8),
      );
      for (var i = 0; i < 16; i++) {
        final a = i * math.pi * 2 / 16 + 0.3;
        final r = 14 + 84 * e * (0.7 + 0.3 * ((i % 3) / 2));
        final p = c + Offset(math.cos(a), math.sin(a)) * r;
        canvas.drawCircle(
          p,
          (1 - burst) * (i.isEven ? 3.2 : 2.2),
          Paint()
            ..color = (i % 3 == 0 ? AppColors.gold : AppColors.accent)
                .withValues(alpha: 1 - burst),
        );
      }
    }

    if (error) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppColors.error.withValues(alpha: 0.14),
      );
    }
  }

  void _train(Canvas canvas, double w, double groundY) {
    const engineW = 64.0, coachW = 56.0, gap = 4.0;
    const totalW = engineW + 3 * (coachW + gap);
    final scale = math.min(1.0, (w - 24) / totalW);
    final moving = !error && !(success && burst > 0.6);
    final bob = moving ? math.sin(loop * math.pi * 2 * 12) * 0.7 : 0.0;

    canvas.save();
    canvas.translate((w - totalW * scale) / 2, groundY - 2 + bob);
    canvas.scale(scale);

    final body = Paint()..color = const Color(0xFF16384A);
    final stripe = Paint()..color = accent;
    final wheel = Paint()..color = const Color(0xFF0A1722);
    final spoke = Paint()
      ..color = const Color(0xFF9DB6C4)
      ..strokeWidth = 1.3;
    final glow = Paint()
      ..color = const Color(0xFFFBBF24).withValues(alpha: 0.55 + 0.35 * pulse);

    // Coaches (left → right), then engine at the front (right)
    var x = 0.0;
    for (var c = 0; c < 3; c++) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, -26, coachW, 26),
        const Radius.circular(5),
      );
      canvas.drawRRect(r, body);
      canvas.drawRect(Rect.fromLTWH(x + 2, -8, coachW - 4, 3), stripe);
      for (var i = 0; i < 4; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 6 + i * 12.5, -21, 8, 8),
            const Radius.circular(2),
          ),
          glow,
        );
      }
      _wheel(canvas, Offset(x + 11, 2), 4.5, wheel, spoke);
      _wheel(canvas, Offset(x + coachW - 11, 2), 4.5, wheel, spoke);
      // coupling
      canvas.drawRect(
        Rect.fromLTWH(x + coachW, -5, gap, 2),
        Paint()..color = const Color(0xFF9DB6C4),
      );
      x += coachW + gap;
    }

    // Engine
    final nose = Path()
      ..moveTo(x, -30)
      ..lineTo(x + engineW - 14, -30)
      ..quadraticBezierTo(x + engineW, -28, x + engineW, -14)
      ..lineTo(x + engineW, 0)
      ..lineTo(x, 0)
      ..close();
    canvas.drawPath(nose, Paint()..color = AppColors.primaryDark);
    canvas.drawRect(Rect.fromLTWH(x, -9, engineW, 3), stripe);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 8, -24, 20, 10),
        const Radius.circular(2.5),
      ),
      glow,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 33, -24, 14, 10),
        const Radius.circular(2.5),
      ),
      glow,
    );
    for (final dx in [10.0, 30.0, 50.0]) {
      _wheel(canvas, Offset(x + dx, 2), 5.2, wheel, spoke);
    }

    // Headlight + beam
    final head = Offset(x + engineW - 3, -12);
    if (!error) {
      final beam = Path()
        ..moveTo(head.dx, head.dy)
        ..lineTo(head.dx + 70, head.dy - 14)
        ..lineTo(head.dx + 70, head.dy + 16)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.linear(head, Offset(head.dx + 70, head.dy), [
            Colors.white.withValues(alpha: 0.38 + 0.12 * pulse),
            Colors.white.withValues(alpha: 0),
          ]),
      );
    }
    canvas.drawCircle(head, 3.2, Paint()..color = Colors.white);

    canvas.restore();
  }

  void _wheel(Canvas canvas, Offset c, double r, Paint fill, Paint spoke) {
    canvas.drawCircle(c, r, fill);
    final a = loop * math.pi * 2 * 8;
    for (var i = 0; i < 3; i++) {
      final ang = a + i * math.pi / 3;
      final d = Offset(math.cos(ang), math.sin(ang)) * (r - 0.8);
      canvas.drawLine(c - d, c + d, spoke);
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter o) =>
      o.loop != loop ||
      o.pulse != pulse ||
      o.burst != burst ||
      o.success != success ||
      o.error != error ||
      o.accent != accent;
}
