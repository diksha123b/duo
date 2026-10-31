import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// The colours a pet can be.
const petColors = {
  'peach': Color(0xFFFFC4A3),
  'mint': DuoColors.mint,
  'sky': DuoColors.sky,
  'grape': DuoColors.grape,
  'sunflower': DuoColors.sunflower,
};

/// Accessories, by id, as shown in the dress-up sheet.
const petOutfits = {
  'bow': ('🎀', 'bow'),
  'flower': ('🌼', 'flower'),
  'cap': ('🧢', 'cap'),
  'party': ('🎉', 'party hat'),
  'tophat': ('🎩', 'top hat'),
  'crown': ('👑', 'crown'),
};

/// The pair's pet, drawn in code. It breathes (or wobbles, as an egg), blinks,
/// changes face with its mood, wears its outfit, and squishes with a puff of
/// hearts whenever [pats] goes up.
class PetSprite extends StatefulWidget {
  const PetSprite({
    super.key,
    required this.stage,
    required this.mood,
    required this.color,
    this.outfit,
    this.progress = 0,
    this.pats = 0,
    this.size = 120,
  });

  final PetStage stage;
  final PetMood mood;
  final Color color;
  final String? outfit;

  /// Progress through the level; an egg cracks more as it nears hatching.
  final double progress;

  /// Bump to play the pat animation.
  final int pats;
  final double size;

  @override
  State<PetSprite> createState() => _PetSpriteState();
}

class _PetSpriteState extends State<PetSprite> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _pat = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void didUpdateWidget(PetSprite old) {
    super.didUpdateWidget(old);
    if (widget.pats != old.pats && !_still) _pat.forward(from: 0);
  }

  @override
  void dispose() {
    _idle.dispose();
    _pat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_idle, _pat]),
        builder: (context, _) => CustomPaint(
          painter: _PetPainter(
            t: _idle.value,
            pat: _pat.isAnimating ? _pat.value : 0,
            stage: widget.stage,
            mood: widget.mood,
            color: widget.color,
            outfit: widget.outfit,
            progress: widget.progress,
            line: DuoColors.line(context),
          ),
        ),
      ),
    );
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter({
    required this.t,
    required this.pat,
    required this.stage,
    required this.mood,
    required this.color,
    required this.outfit,
    required this.progress,
    required this.line,
  });

  final double t;
  final double pat;
  final PetStage stage;
  final PetMood mood;
  final Color color;
  final String? outfit;
  final double progress;
  final Color line;

  Paint get _stroke => Paint()
    ..color = line
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final wave = math.sin(t * 2 * math.pi);
    // A quick squash-and-stretch when patted.
    final squish = math.sin(pat * math.pi) * 0.14;
    final base = Offset(s / 2, s * 0.96);

    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(1 + squish, 1 - squish);
    if (stage == PetStage.egg) {
      // Eggs wobble from side to side, more as they get close to hatching.
      canvas.rotate(wave * (0.04 + progress * 0.08));
      _egg(canvas, s);
    } else {
      // Sleepy pets breathe slowly and low; awake ones bob.
      canvas.translate(0, mood == PetMood.sleepy ? wave * s * 0.008 : -wave.abs() * s * 0.025);
      _creature(canvas, s, wave);
    }
    canvas.restore();

    if (pat > 0) _hearts(canvas, s);
  }

  void _egg(Canvas canvas, double s) {
    final w = s * 0.52, h = s * 0.66;
    final rect = Rect.fromLTWH(-w / 2, -h, w, h);
    final shell = Path()..addOval(rect);
    canvas.drawPath(shell.shift(Offset(s * 0.025, s * 0.02)), Paint()..color = line);
    canvas.drawPath(shell, Paint()..color = const Color(0xFFFFFBF2));
    // Spots in the pet's colour hint at who's inside.
    canvas.save();
    canvas.clipPath(shell);
    final spot = Paint()..color = color;
    canvas.drawCircle(Offset(-w * 0.22, -h * 0.62), w * 0.13, spot);
    canvas.drawCircle(Offset(w * 0.2, -h * 0.4), w * 0.17, spot);
    canvas.drawCircle(Offset(-w * 0.12, -h * 0.2), w * 0.1, spot);
    canvas.restore();
    canvas.drawPath(shell, _stroke..strokeWidth = s * 0.022);

    // Cracks appear as the egg nears hatching.
    final cracks = (progress * 4).floor().clamp(0, 3);
    if (cracks > 0) {
      final y = -h * 0.58;
      final zig = Path()..moveTo(-w * 0.32, y);
      final steps = 2 + cracks * 2;
      for (var i = 1; i <= steps; i++) {
        zig.lineTo(-w * 0.32 + w * 0.64 * i / 8, y + (i.isOdd ? -h * 0.06 : h * 0.03));
      }
      canvas.drawPath(zig, _stroke..strokeWidth = s * 0.015);
    }
  }

  void _creature(Canvas canvas, double s, double wave) {
    final scale = switch (stage) {
      PetStage.baby => 0.56,
      PetStage.kid => 0.7,
      _ => 0.8,
    };
    final w = s * scale, h = w * 0.86;
    final top = -h - s * 0.04;
    final body = Rect.fromLTWH(-w / 2, top, w, h);
    final stroke = _stroke..strokeWidth = s * 0.022;
    final fill = Paint()..color = color;
    final shadow = Paint()..color = line;
    final drop = Offset(s * 0.025, s * 0.02);

    // Ears: little nubs on babies, pointy ones once they grow.
    for (final side in [-1.0, 1.0]) {
      final ear = stage == PetStage.baby
          ? (Path()..addOval(Rect.fromCircle(center: Offset(side * w * 0.3, top + h * 0.08), radius: w * 0.11)))
          : (Path()
              ..moveTo(side * w * 0.14, top + h * 0.12)
              ..quadraticBezierTo(side * w * 0.36, top - h * 0.28, side * w * 0.44, top + h * 0.22)
              ..close());
      canvas.drawPath(ear.shift(drop), shadow);
      canvas.drawPath(ear, fill);
      canvas.drawPath(ear, stroke);
    }

    // A curly tail for grown-ups, wagging when happy.
    if (stage == PetStage.grown) {
      final wag = mood == PetMood.happy ? wave * w * 0.04 : 0.0;
      final tail = Path()
        ..moveTo(w * 0.42, top + h * 0.75)
        ..quadraticBezierTo(w * 0.6 + wag, top + h * 0.72, w * 0.56 + wag, top + h * 0.5)
        ..quadraticBezierTo(w * 0.53 + wag, top + h * 0.4, w * 0.48 + wag, top + h * 0.5);
      canvas.drawPath(tail, _stroke..strokeWidth = s * 0.05);
      canvas.drawPath(
        tail,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.028,
      );
    }

    // Body.
    final blob = RRect.fromRectAndCorners(
      body,
      topLeft: Radius.elliptical(w * 0.5, h * 0.55),
      topRight: Radius.elliptical(w * 0.5, h * 0.55),
      bottomLeft: Radius.elliptical(w * 0.42, h * 0.4),
      bottomRight: Radius.elliptical(w * 0.42, h * 0.4),
    );
    canvas.drawRRect(blob.shift(drop), shadow);
    canvas.drawRRect(blob, fill);
    // A lighter tummy on kids and grown-ups.
    if (stage != PetStage.baby) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, top + h * 0.74), width: w * 0.5, height: h * 0.36),
        Paint()..color = Colors.white.withValues(alpha: 0.45),
      );
    }
    canvas.drawRRect(blob, stroke);

    // Feet.
    if (stage != PetStage.baby) {
      for (final side in [-1.0, 1.0]) {
        final foot = Rect.fromCenter(center: Offset(side * w * 0.22, top + h), width: w * 0.24, height: h * 0.13);
        canvas.drawOval(foot, fill);
        canvas.drawOval(foot, stroke);
      }
    }

    _face(canvas, w, h, top);
    if (outfit != null) _outfit(canvas, w, h, top);
  }

  void _face(Canvas canvas, double w, double h, double top) {
    final stroke = _stroke..strokeWidth = w * 0.035;
    final eyeY = top + h * 0.42;
    final gap = w * (stage == PetStage.baby ? 0.17 : 0.15);
    final blinking = (t % 1) > 0.95;
    final eyeR = w * (stage == PetStage.baby ? 0.075 : 0.06);
    for (final side in [-1.0, 1.0]) {
      final e = Offset(side * gap, eyeY);
      if (mood == PetMood.sleepy || blinking) {
        canvas.drawArc(Rect.fromCenter(center: e, width: eyeR * 2.2, height: eyeR * 1.4), 0, math.pi, false, stroke);
      } else {
        canvas.drawCircle(e, eyeR, Paint()..color = line);
        canvas.drawCircle(e.translate(eyeR * 0.35, -eyeR * 0.35), eyeR * 0.35, Paint()..color = Colors.white);
      }
    }
    // Cheeks.
    final blush = Paint()..color = DuoColors.tomato.withValues(alpha: mood == PetMood.happy ? 0.45 : 0.25);
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * gap * 1.75, eyeY + h * 0.12), width: w * 0.12, height: w * 0.07),
        blush,
      );
    }
    // Mouth.
    final m = Offset(0, eyeY + h * 0.14);
    switch (mood) {
      case PetMood.happy:
        canvas.drawArc(Rect.fromCenter(center: m, width: w * 0.14, height: w * 0.1), 0.2, math.pi - 0.4, false, stroke);
      case PetMood.hungry:
        // A little "o": waiting to be fed.
        canvas.drawOval(Rect.fromCenter(center: m.translate(0, h * 0.02), width: w * 0.07, height: w * 0.08), stroke);
      case PetMood.sleepy:
        canvas.drawLine(m.translate(-w * 0.04, h * 0.02), m.translate(w * 0.04, h * 0.02), stroke);
        _text(canvas, 'z', Offset(w * 0.42, top - h * 0.02 + math.sin(t * 2 * math.pi) * 3), w * 0.18);
        _text(canvas, 'z', Offset(w * 0.56, top - h * 0.2 + math.sin(t * 2 * math.pi + 1) * 3), w * 0.13);
    }
  }

  void _outfit(Canvas canvas, double w, double h, double top) {
    if (outfit == 'party') {
      // A striped party hat, tipped to one side.
      canvas.save();
      canvas.translate(w * 0.12, top + h * 0.06);
      canvas.rotate(0.3);
      final hat = Path()
        ..moveTo(-w * 0.13, 0)
        ..lineTo(0, -h * 0.32)
        ..lineTo(w * 0.13, 0)
        ..close();
      canvas.drawPath(hat, Paint()..color = DuoColors.tomato);
      canvas.save();
      canvas.clipPath(hat);
      for (var i = 1; i <= 3; i++) {
        canvas.drawLine(
          Offset(-w * 0.2, -h * 0.085 * i),
          Offset(w * 0.2, -h * 0.085 * i + h * 0.04),
          Paint()
            ..color = DuoColors.sunflower
            ..strokeWidth = h * 0.04,
        );
      }
      canvas.restore();
      canvas.drawPath(hat, _stroke..strokeWidth = w * 0.03);
      canvas.drawCircle(Offset(0, -h * 0.34), w * 0.05, Paint()..color = DuoColors.sunflower);
      canvas.drawCircle(Offset(0, -h * 0.34), w * 0.05, _stroke..strokeWidth = w * 0.025);
      canvas.restore();
      return;
    }
    final emoji = petOutfits[outfit]?.$1;
    if (emoji == null) return;
    final (dx, dy, size) = switch (outfit) {
      'bow' || 'flower' => (w * 0.26, top + h * 0.12, w * 0.3),
      _ => (0.0, top - h * 0.02, w * 0.42),
    };
    _text(canvas, emoji, Offset(dx, dy), size);
  }

  void _hearts(Canvas canvas, double s) {
    final rise = Curves.easeOut.transform(pat);
    for (final (i, dx) in [-0.28, 0.0, 0.28].indexed) {
      final p = (rise - i * 0.08).clamp(0.0, 1.0);
      if (p == 0) continue;
      final c = Offset(s / 2 + dx * s, s * (0.42 - p * 0.36));
      final r = s * 0.05 * (1 - p * 0.3);
      final heart = Path()
        ..moveTo(c.dx, c.dy + r)
        ..cubicTo(c.dx - r * 2, c.dy - r * 0.4, c.dx - r * 0.6, c.dy - r * 1.6, c.dx, c.dy - r * 0.5)
        ..cubicTo(c.dx + r * 0.6, c.dy - r * 1.6, c.dx + r * 2, c.dy - r * 0.4, c.dx, c.dy + r);
      canvas.drawPath(heart, Paint()..color = DuoColors.tomato.withValues(alpha: 1 - p * 0.8));
    }
  }

  void _text(Canvas canvas, String text, Offset center, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: line, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PetPainter old) =>
      old.t != t ||
      old.pat != pat ||
      old.stage != stage ||
      old.mood != mood ||
      old.color != color ||
      old.outfit != outfit ||
      old.progress != progress ||
      old.line != line;
}
