import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

enum BuddyMood { happy, waiting, celebrating, sleepy }

/// Duo's mascots: two round buddies leaning on each other. Drawn in code so
/// they scale crisply, gently bob, and change face with [mood].
class Buddies extends StatefulWidget {
  const Buddies({
    super.key,
    this.size = 120,
    this.mood = BuddyMood.happy,
    this.left = DuoColors.bubblegum,
    this.right = DuoColors.sky,
  });

  final double size;
  final BuddyMood mood;
  final Color left;
  final Color right;

  @override
  State<Buddies> createState() => _BuddiesState();
}

class _BuddiesState extends State<Buddies> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  // Respect the system "reduce motion" setting: still buddies, no bobbing.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.5,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _BuddiesPainter(
            t: _c.value,
            mood: widget.mood,
            left: widget.left,
            right: widget.right,
            line: DuoColors.line(context),
          ),
        ),
      ),
    );
  }
}

class _BuddiesPainter extends CustomPainter {
  _BuddiesPainter({required this.t, required this.mood, required this.left, required this.right, required this.line});

  final double t;
  final BuddyMood mood;
  final Color left;
  final Color right;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final wave = math.sin(t * 2 * math.pi);
    // Celebrating buddies hop; others breathe.
    final bounce = mood == BuddyMood.celebrating ? -(wave.abs()) * h * 0.08 : wave * h * 0.015;
    final r = h * 0.36;

    _buddy(canvas, Offset(size.width * 0.36, h * 0.58 + bounce), r, left, faceRight: true, phase: 0);
    _buddy(canvas, Offset(size.width * 0.64, h * 0.60 - bounce), r * 0.94, right, faceRight: false, phase: 0.5);

    if (mood == BuddyMood.sleepy || mood == BuddyMood.waiting) {
      final tp = TextPainter(
        text: TextSpan(
          text: mood == BuddyMood.sleepy ? 'z' : '…',
          style: TextStyle(fontSize: h * 0.16, color: line, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width * 0.82, h * 0.08 + wave * 4));
    }
    if (mood == BuddyMood.celebrating || mood == BuddyMood.happy) {
      // A small heart between them.
      final c = Offset(size.width * 0.5, h * 0.14 + wave * 3);
      final s = h * 0.06;
      final heart = Path()
        ..moveTo(c.dx, c.dy + s)
        ..cubicTo(c.dx - s * 2, c.dy - s * 0.4, c.dx - s * 0.6, c.dy - s * 1.6, c.dx, c.dy - s * 0.5)
        ..cubicTo(c.dx + s * 0.6, c.dy - s * 1.6, c.dx + s * 2, c.dy - s * 0.4, c.dx, c.dy + s);
      canvas.drawPath(heart, Paint()..color = DuoColors.tomato);
      canvas.drawPath(
        heart,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _buddy(Canvas canvas, Offset c, double r, Color color, {required bool faceRight, required double phase}) {
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;

    // Body: a slightly squashed blob.
    final body = Rect.fromCenter(center: c, width: r * 2.1, height: r * 1.9);
    canvas.drawOval(body.shift(Offset(r * 0.08, r * 0.08)), Paint()..color = line);
    canvas.drawOval(body, Paint()..color = color);
    canvas.drawOval(body, stroke);

    // Eyes look toward the other buddy.
    final look = faceRight ? r * 0.12 : -r * 0.12;
    final eyeY = c.dy - r * 0.15;
    final blinking = ((t + phase) % 1) > 0.94;
    for (final dx in [-r * 0.32, r * 0.32]) {
      final e = Offset(c.dx + dx + look, eyeY);
      if (mood == BuddyMood.sleepy || blinking) {
        canvas.drawLine(e.translate(-r * 0.1, 0), e.translate(r * 0.1, 0), stroke);
      } else if (mood == BuddyMood.celebrating) {
        // Happy closed-eye arcs: ^ ^
        canvas.drawArc(Rect.fromCenter(center: e, width: r * 0.24, height: r * 0.2), math.pi, math.pi, false, stroke);
      } else {
        canvas.drawCircle(e, r * 0.1, Paint()..color = line);
        canvas.drawCircle(e.translate(r * 0.035, -r * 0.035), r * 0.03, Paint()..color = Colors.white);
      }
    }

    // Cheeks.
    final blush = Paint()..color = DuoColors.tomato.withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx - r * 0.55 + look, c.dy + r * 0.12), width: r * 0.3, height: r * 0.16),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(c.dx + r * 0.55 + look, c.dy + r * 0.12), width: r * 0.3, height: r * 0.16),
      blush,
    );

    // Mouth.
    final m = Offset(c.dx + look, c.dy + r * 0.2);
    switch (mood) {
      case BuddyMood.celebrating:
        final mouth = Path()
          ..moveTo(m.dx - r * 0.2, m.dy - r * 0.04)
          ..quadraticBezierTo(m.dx, m.dy + r * 0.36, m.dx + r * 0.2, m.dy - r * 0.04)
          ..close();
        canvas.drawPath(mouth, Paint()..color = line);
      case BuddyMood.waiting || BuddyMood.sleepy:
        canvas.drawCircle(m.translate(0, r * 0.04), r * 0.06, stroke);
      case BuddyMood.happy:
        canvas.drawArc(
          Rect.fromCenter(center: m, width: r * 0.36, height: r * 0.26),
          0.2,
          math.pi - 0.4,
          false,
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_BuddiesPainter old) =>
      old.t != t || old.mood != mood || old.left != left || old.right != right || old.line != line;
}
