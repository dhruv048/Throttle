import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// Starts what's typed with a capital letter ("yamaha" → "Yamaha"), even if
/// the keyboard didn't, e.g. when pasting. Pair with
/// [TextCapitalization.words] so the keyboard capitalises each word too.
class CapitalizeFirstFormatter extends TextInputFormatter {
  const CapitalizeFirstFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final i = text.indexOf(RegExp(r'\S'));
    if (i < 0) return newValue;
    final upper = text[i].toUpperCase();
    if (upper == text[i]) return newValue;
    return newValue.copyWith(
        text: text.replaceRange(i, i + 1, upper),
        selection: newValue.selection);
  }
}

/// A dashed rounded-rectangle outline, for "add something" slots.
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({this.radius = 16});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = math.min(dist + dash, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRRectPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

/// Closes the keyboard, wherever it's open.
void hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.titleSpan,
    this.titleWidget,
    this.right,
  });

  final String eyebrow;
  final String title;
  final InlineSpan? titleSpan;

  /// Replaces the title text entirely (e.g. a loading skeleton).
  final Widget? titleWidget;
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
                  titleWidget ??
                      (titleSpan != null
                          ? Text.rich(titleSpan!, style: displayStyle(size: 34))
                          : Text(title, style: displayStyle(size: 34))),
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
  Timer? _start;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _opacity =
        CurvedAnimation(parent: _c, curve: const Cubic(0.32, 0.72, 0, 1));
    _offset = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(_opacity);
    // Cancelled if it goes away first, so no timer outlives it.
    _start = Timer(widget.delay, _c.forward);
  }

  @override
  void dispose() {
    _start?.cancel();
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
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
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
  const StatBlock(
      {super.key,
      required this.value,
      required this.label,
      this.valueSize = 24});

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

class _BlinkDotState extends State<BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
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
        decoration: const BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle),
      ),
    );
  }
}

/// A glossy, tappable surface: every 2 s light glints across it, and it
/// presses in slightly under a finger.
class SheenButton extends StatefulWidget {
  const SheenButton({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 16,
  });

  final Widget child;
  final VoidCallback onTap;

  /// Corner radius of [child], so the light stays on its surface.
  final double radius;

  @override
  State<SheenButton> createState() => _SheenButtonState();
}

class _SheenButtonState extends State<SheenButton>
    with SingleTickerProviderStateMixin {
  /// A glint every 2 s: 1 s of light, then 1 s of calm.
  static const _sweep = Duration(seconds: 1);
  static const _calm = Duration(seconds: 1);

  late final AnimationController _glint =
      AnimationController(vsync: this, duration: _sweep)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _queueGlint();
        });
  Timer? _next;
  bool _running = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only while on screen (tabs stay alive in an IndexedStack) and when the
    // rider hasn't asked for reduced motion.
    final run = TickerMode.valuesOf(context).enabled &&
        Visibility.of(context) &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (run == _running) return;
    _running = run;
    if (run) {
      _queueGlint();
    } else {
      _next?.cancel();
      _glint.value = 0;
    }
  }

  /// The next glint, after the calm. Nothing animates (or repaints) in
  /// between.
  void _queueGlint() {
    _next?.cancel();
    if (!_running) return;
    _next = Timer(_calm, () {
      if (mounted && _running) _glint.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _glint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: Duration(milliseconds: _pressed ? 90 : 180),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (down) => setState(() => _pressed = down),
          borderRadius: radius,
          child: Stack(
            children: [
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GlintPainter(_glint, radius)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Light glinting off a glossy surface: a slanted streak with a bright core,
/// a soft halo and a faint second reflection trailing behind, wrapped in a
/// hint of the brand orange glow. The core is added to what's underneath
/// (like real light) rather than laid over it, so lettering and colours
/// brighten instead of turning grey.
class _GlintPainter extends CustomPainter {
  _GlintPainter(this.progress, this.radius) : super(repaint: progress);

  final Animation<double> progress;
  final BorderRadius radius;

  /// Lean of the streak from vertical (~22°).
  static const _tilt = 0.38;

  /// Warm daylight.
  static const _light = Color(0xFFFFF5EA);

  /// Brightness across the streak, trailing edge (0) to leading edge (1).
  static const _stops = <double>[
    0, .14, .22, .27, .33, .41, .46, .5, .54, .6, .7, 1, //
  ];
  static const _levels = <double>[
    0, .025, .085, .025, .035, .12, .28, .4, .28, .1, .025, 0, //
  ];

  /// Strength of the orange glow across the streak: either side of a whiter
  /// centre, like light with a coloured aura.
  static const _glowStops = <double>[0, .18, .33, .43, .5, .57, .67, .82, 1];
  static const _glowLevels = <double>[0, .03, .11, .15, .06, .15, .11, .03, 0];

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1 || size.isEmpty) return;

    final width = (size.width * 0.45).clamp(110.0, 220.0);
    // The core crosses edge to edge (slant included), so the light is on the
    // surface for the whole sweep.
    final slant = size.height / 2 * math.tan(_tilt);
    final x = ui.lerpDouble(
        -slant, size.width + slant, Curves.easeInOutSine.transform(t))!;
    final center = Offset(x, size.height / 2);
    final across = Offset(math.cos(_tilt), math.sin(_tilt)) * (width / 2);
    // Full strength, with a quick fade in and out at the edges.
    final strength = _fade(t / 0.15) * _fade((1 - t) / 0.15);

    Shader streak(Color color, List<double> levels, List<double> stops) =>
        ui.Gradient.linear(
          center - across,
          center + across,
          [for (final l in levels) color.withValues(alpha: l * strength)],
          stops,
        );

    final surface = Offset.zero & size;
    canvas.save();
    // Just inside the edge, so a border stays crisp under the light.
    canvas.clipRRect(radius.toRRect(surface).deflate(1));
    canvas.drawRect(
      surface,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = streak(_light, _levels, _stops),
    );
    // After the light, which would otherwise wash it back to white. Multiply
    // tints white like coloured light but leaves the lettering crisp.
    canvas.drawRect(
      surface,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = streak(AppColors.primary, _glowLevels, _glowStops),
    );
    canvas.restore();
  }

  static double _fade(double v) => Curves.easeOut.transform(v.clamp(0, 1));

  @override
  bool shouldRepaint(covariant _GlintPainter old) =>
      old.progress != progress || old.radius != radius;
}
