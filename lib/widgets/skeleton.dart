import 'package:flutter/material.dart';

import '../theme.dart';
import 'ui.dart';

/// Placeholder colour for content that is still loading.
const _bone = Color(0xFFE9E6E0);
const _shine = Color(0xFFF6F4F0);

/// Sweeps a soft highlight across its [child]'s skeleton shapes, so the
/// screen reads as "loading" rather than empty. Never wrap real data in it.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              colors: const [_bone, _shine, _bone],
              stops: const [0.35, 0.5, 0.65],
              begin: const Alignment(-1, -0.2),
              end: const Alignment(1, 0.2),
              transform: _Slide(_c.value * 2 - 1),
            ).createShader(bounds),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.percent);

  final double percent;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * percent, 0, 0);
}

/// One placeholder shape. Put several inside a [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  const SkeletonBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 999;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _bone,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Mirrors [RideCard]'s layout so nothing jumps when the real card arrives.
class RideCardSkeleton extends StatelessWidget {
  const RideCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  SkeletonBox.circle(size: 36),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120, height: 13),
                      SizedBox(height: 6),
                      SkeletonBox(width: 160, height: 10),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SkeletonBox(width: 190, height: 18),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 52, height: 22),
                          SizedBox(height: 6),
                          SkeletonBox(width: 34, height: 9),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SkeletonBox(height: 160, radius: 0),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: SkeletonBox(width: 80, height: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list of [count] ride-card placeholders.
class RideListSkeleton extends StatelessWidget {
  const RideListSkeleton({super.key, this.count = 2});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: RideCardSkeleton(),
          ),
      ],
    );
  }
}

/// A person row (avatar, two lines, button) for lists of riders.
class PersonRowSkeleton extends StatelessWidget {
  const PersonRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.all(12),
        child: Shimmer(
          child: Row(
            children: [
              SkeletonBox.circle(size: 44),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 130, height: 13),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 10),
                  ],
                ),
              ),
              SkeletonBox(width: 72, height: 32, radius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic page placeholder (header + content cards), e.g. while the app
/// works out who is signed in.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              children: const [
                Shimmer(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 110, height: 10),
                            SizedBox(height: 10),
                            SkeletonBox(width: 220, height: 30),
                          ],
                        ),
                      ),
                      SkeletonBox.circle(size: 36),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                AppCard(
                  padding: EdgeInsets.all(16),
                  child: Shimmer(child: SkeletonBox(height: 64)),
                ),
                SizedBox(height: 24),
                RideListSkeleton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A photo from the network: shimmers while it downloads, shows a neutral
/// placeholder if it can't load.
class NetworkPhoto extends StatelessWidget {
  const NetworkPhoto(this.url,
      {super.key, this.fit = BoxFit.cover, this.fallback});

  final String url;
  final BoxFit fit;

  /// Shown if the image fails; defaults to a plain panel.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Shimmer(
              child: SkeletonBox(height: double.infinity, radius: 0)),
      errorBuilder: (_, __, ___) =>
          fallback ?? const ColoredBox(color: AppColors.panel),
    );
  }
}
