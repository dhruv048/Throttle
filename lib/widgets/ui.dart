import 'package:flutter/material.dart';
import '../theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.titleSpan,
    this.right,
  });

  final String eyebrow;
  final String title;
  final InlineSpan? titleSpan;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: RiseIn(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: labelMono(size: 11).copyWith(letterSpacing: 2.75),
                  ),
                  const SizedBox(height: 4),
                  titleSpan != null
                      ? Text.rich(titleSpan!, style: displayStyle(size: 34))
                      : Text(title, style: displayStyle(size: 34)),
                ],
              ),
            ),
            if (right != null) right!,
          ],
        ),
      ),
    );
  }
}

class RiseIn extends StatefulWidget {
  const RiseIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _opacity = CurvedAnimation(parent: _c, curve: const Cubic(0.32, 0.72, 0, 1));
    _offset = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_opacity);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.highlight = false,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool highlight;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class LabelMono extends StatelessWidget {
  const LabelMono(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: labelMono(color: color));
  }
}

class StatBlock extends StatelessWidget {
  const StatBlock({super.key, required this.value, required this.label, this.valueSize = 24});

  final String value;
  final String label;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: displayStyle(size: valueSize)),
        const SizedBox(height: 4),
        LabelMono(label),
      ],
    );
  }
}

class BlinkDot extends StatefulWidget {
  const BlinkDot({super.key, this.size = 6});

  final double size;

  @override
  State<BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<BlinkDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
      ),
    );
  }
}

class SheenButton extends StatelessWidget {
  const SheenButton({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            child,
            const Positioned.fill(child: IgnorePointer(child: _SheenSweep())),
          ],
        ),
      ),
    );
  }
}

class _SheenSweep extends StatefulWidget {
  const _SheenSweep();

  @override
  State<_SheenSweep> createState() => _SheenSweepState();
}

class _SheenSweepState extends State<_SheenSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FractionallySizedBox(
            alignment: Alignment(-1.3 + _c.value * 3.6, 0),
            widthFactor: 0.35,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0x59FFFFFF), Colors.transparent],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
