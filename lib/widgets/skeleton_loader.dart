import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// High-performance animated shimmer effect for skeleton loading screens.
/// Disables animation in unit/widget test environments to avoid test timeouts.
class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SkeletonShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1300),
  });

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    final isTest =
        WidgetsBinding.instance.runtimeType.toString().toLowerCase().contains('test');
    if (!isTest) {
      _controller = AnimationController(vsync: this, duration: widget.duration)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);
    final highlightColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF8FAFC);

    if (_controller == null) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final t = _controller!.value;
            return LinearGradient(
              begin: Alignment(-1.0 + (3.0 * t), -0.2),
              end: Alignment(0.0 + (3.0 * t), 0.2),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.1, 0.5, 0.9],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A single rounded placeholder shape ("bone") for skeleton loaders.
class SkeletonBone extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBone({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
    this.margin,
  });

  const SkeletonBone.circle({
    super.key,
    required double size,
    this.margin,
  })  : width = size,
        height = size,
        borderRadius = size / 2;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton card simulating a train search result card.
class SkeletonTrainCard extends StatelessWidget {
  const SkeletonTrainCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Train name + Train number badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              SkeletonBone(width: 140, height: 18, borderRadius: 6),
              SkeletonBone(width: 60, height: 20, borderRadius: 10),
            ],
          ),
          const SizedBox(height: 16),
          // Route and time row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBone(width: 70, height: 18, borderRadius: 4),
                  SizedBox(height: 6),
                  SkeletonBone(width: 50, height: 12, borderRadius: 4),
                ],
              ),
              const SkeletonBone(width: 80, height: 14, borderRadius: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  SkeletonBone(width: 70, height: 18, borderRadius: 4),
                  SizedBox(height: 6),
                  SkeletonBone(width: 50, height: 12, borderRadius: 4),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Class badges
          Row(
            children: const [
              SkeletonBone(width: 75, height: 32, borderRadius: 10),
              SizedBox(width: 8),
              SkeletonBone(width: 75, height: 32, borderRadius: 10),
              SizedBox(width: 8),
              SkeletonBone(width: 75, height: 32, borderRadius: 10),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton grid simulating a train coach seat layout.
class SkeletonSeatGrid extends StatelessWidget {
  final int rows;

  const SkeletonSeatGrid({super.key, this.rows = 8});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SkeletonShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // Coach tabs placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (i) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: SkeletonBone(width: 56, height: 34, borderRadius: 12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Coach header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.cardBg(isDark),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  SkeletonBone(width: 90, height: 14, borderRadius: 4),
                  SkeletonBone(width: 60, height: 14, borderRadius: 4),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Seats layout (2 on left, aisle, 2 on right)
            ...List.generate(
              rows,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SkeletonBone(width: 44, height: 44, borderRadius: 10),
                    SizedBox(width: 8),
                    SkeletonBone(width: 44, height: 44, borderRadius: 10),
                    SizedBox(width: 40), // Aisle
                    SkeletonBone(width: 44, height: 44, borderRadius: 10),
                    SizedBox(width: 8),
                    SkeletonBone(width: 44, height: 44, borderRadius: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton simulating a purchased ticket card in Trips screen.
class SkeletonTicketCard extends StatelessWidget {
  const SkeletonTicketCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              SkeletonBone(width: 120, height: 16, borderRadius: 4),
              SkeletonBone(width: 70, height: 22, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBone(width: 80, height: 14, borderRadius: 4),
                  SizedBox(height: 4),
                  SkeletonBone(width: 60, height: 12, borderRadius: 4),
                ],
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.black12, size: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  SkeletonBone(width: 80, height: 14, borderRadius: 4),
                  SizedBox(height: 4),
                  SkeletonBone(width: 60, height: 12, borderRadius: 4),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              SkeletonBone(width: 90, height: 12, borderRadius: 4),
              SkeletonBone(width: 50, height: 16, borderRadius: 4),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton simulating the active reservation screen card.
class SkeletonReservationCard extends StatelessWidget {
  const SkeletonReservationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SkeletonShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Timer pill
            const SkeletonBone(width: 140, height: 38, borderRadius: 19),
            const SizedBox(height: 24),
            // Train summary box
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardBg(isDark),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder(isDark)),
              ),
              child: Column(
                children: [
                  const SkeletonBone(width: 180, height: 22, borderRadius: 6),
                  const SizedBox(height: 12),
                  const SkeletonBone(width: 120, height: 14, borderRadius: 4),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      SkeletonBone(width: 70, height: 32, borderRadius: 8),
                      SkeletonBone(width: 70, height: 32, borderRadius: 8),
                      SkeletonBone(width: 70, height: 32, borderRadius: 8),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // OTP input placeholder
            const SkeletonBone(width: 220, height: 50, borderRadius: 12),
            const SizedBox(height: 24),
            // Action button placeholder
            const SkeletonBone(width: double.infinity, height: 52, borderRadius: 16),
          ],
        ),
      ),
    );
  }
}

/// Reusable list of train cards wrapped in SkeletonShimmer.
class SkeletonTrainList extends StatelessWidget {
  final int count;

  const SkeletonTrainList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        itemBuilder: (context, index) => const SkeletonTrainCard(),
      ),
    );
  }
}

/// Reusable list of ticket cards wrapped in SkeletonShimmer.
class SkeletonTicketList extends StatelessWidget {
  final int count;

  const SkeletonTicketList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        itemBuilder: (context, index) => const SkeletonTicketCard(),
      ),
    );
  }
}
