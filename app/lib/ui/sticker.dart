import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The core building block: a card with an ink outline and a solid offset
/// shadow that "presses in" when tapped, like a sticker on a page.
class Sticker extends StatefulWidget {
  const Sticker({
    super.key,
    required this.child,
    this.color,
    this.onTap,
    this.radius = 22,
    this.depth = 5,
    this.tilt = 0,
    this.padding = const EdgeInsets.all(18),
    this.pattern,
  });

  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;
  final double depth;

  /// Rotation in degrees, for a hand-placed look.
  final double tilt;
  final EdgeInsetsGeometry padding;

  /// Optional background pattern painted under the content.
  final StickerPattern? pattern;

  @override
  State<Sticker> createState() => _StickerState();
}

class _StickerState extends State<Sticker> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final line = DuoColors.line(context);
    final fill = widget.color ?? Theme.of(context).colorScheme.surfaceContainerLowest;
    final press = _down ? widget.depth : 0.0;
    final radius = BorderRadius.circular(widget.radius);

    Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      transform: Matrix4.translationValues(press, press, 0),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: line, width: 2),
        boxShadow: [BoxShadow(color: line, offset: Offset(widget.depth - press, widget.depth - press))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius - 2),
        child: CustomPaint(
          painter: widget.pattern == null ? null : _PatternPainter(widget.pattern!, line.withValues(alpha: 0.09)),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );

    if (widget.onTap != null) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap!();
        },
        child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
      );
    }
    if (widget.tilt != 0) body = Transform.rotate(angle: widget.tilt * math.pi / 180, child: body);
    return Padding(
      padding: EdgeInsets.only(right: widget.depth, bottom: widget.depth),
      child: body,
    );
  }
}

/// A sticker-style primary button that shows a spinner and blocks re-taps
/// while [onPressed] runs.
class StickerButton extends StatefulWidget {
  const StickerButton({super.key, required this.label, required this.onPressed, this.color, this.emoji});

  final String label;
  final Future<void> Function()? onPressed;
  final Color? color;
  final String? emoji;

  @override
  State<StickerButton> createState() => _StickerButtonState();
}

class _StickerButtonState extends State<StickerButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !_busy;
    final text = Theme.of(context).textTheme.titleMedium?.copyWith(color: DuoColors.ink, fontWeight: FontWeight.w800);
    return Opacity(
      opacity: widget.onPressed == null ? 0.45 : 1,
      child: Sticker(
        color: widget.color ?? DuoColors.tomato,
        radius: 40,
        depth: 4,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        onTap: enabled ? _run : null,
        child: Center(
          child: _busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: DuoColors.ink),
                )
              : Text(widget.emoji == null ? widget.label : '${widget.label}  ${widget.emoji}', style: text),
        ),
      ),
    );
  }
}

/// A little rounded label, e.g. "🧃 siblings".
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DuoColors.line(context), width: 1.5),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: DuoColors.ink)),
    );
  }
}

enum StickerPattern { dots, stripes, waves, grid, stars, zigzag }

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.pattern, this.color);

  final StickerPattern pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    switch (pattern) {
      case StickerPattern.dots:
        for (double y = 10; y < size.height; y += 22) {
          for (double x = (y ~/ 22).isEven ? 10 : 21; x < size.width; x += 22) {
            canvas.drawCircle(Offset(x, y), 3, fill);
          }
        }
      case StickerPattern.stripes:
        for (double x = -size.height; x < size.width; x += 18) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
        }
      case StickerPattern.waves:
        for (double y = 14; y < size.height; y += 20) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 24) {
            path.quadraticBezierTo(x + 6, y - 6, x + 12, y);
            path.quadraticBezierTo(x + 18, y + 6, x + 24, y);
          }
          canvas.drawPath(path, paint);
        }
      case StickerPattern.grid:
        for (double x = 0; x < size.width; x += 24) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint..strokeWidth = 1.5);
        }
        for (double y = 0; y < size.height; y += 24) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case StickerPattern.stars:
        final rnd = math.Random(7);
        for (var i = 0; i < (size.width * size.height / 900).clamp(8, 60); i++) {
          final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
          const r = 4.0;
          canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), paint);
          canvas.drawLine(c.translate(0, -r), c.translate(0, r), paint);
        }
      case StickerPattern.zigzag:
        for (double y = 12; y < size.height; y += 22) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 16) {
            path.lineTo(x + 8, y - 6);
            path.lineTo(x + 16, y);
          }
          canvas.drawPath(path, paint);
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.pattern != pattern || old.color != color;
}

/// A quick burst of emoji that float up and fade: the celebration moment.
class EmojiBurst extends StatefulWidget {
  const EmojiBurst({super.key, required this.emojis, this.count = 18});

  final List<String> emojis;
  final int count;

  @override
  State<EmojiBurst> createState() => _EmojiBurstState();
}

class _EmojiBurstState extends State<EmojiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No flying emoji for people who asked for reduced motion.
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false) && !_c.isAnimating && _c.value == 0) _c.forward();
  }

  final _rnd = math.Random();
  late final _particles = List.generate(
    widget.count,
    (i) => (
      emoji: widget.emojis[i % widget.emojis.length],
      x: _rnd.nextDouble(),
      drift: (_rnd.nextDouble() - 0.5) * 0.3,
      delay: _rnd.nextDouble() * 0.35,
      size: 18 + _rnd.nextDouble() * 18,
      spin: (_rnd.nextDouble() - 0.5) * 2,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(
            children: [
              for (final p in _particles)
                if (_c.value > p.delay)
                  Builder(
                    builder: (context) {
                      final t = ((_c.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
                      final eased = Curves.easeOutCubic.transform(t);
                      return Positioned(
                        left: (p.x + p.drift * eased) * box.maxWidth,
                        top: box.maxHeight * (0.85 - 0.75 * eased),
                        child: Opacity(
                          opacity: (1 - t).clamp(0, 1),
                          child: Transform.rotate(
                            angle: p.spin * eased,
                            child: Text(p.emoji, style: TextStyle(fontSize: p.size)),
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
