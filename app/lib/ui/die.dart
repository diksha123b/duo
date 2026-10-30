import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A chunky die with real pips. Each time [count] changes it tumbles
/// through random faces and lands on [value], so a fresh roll always
/// animates, even when the same number comes up twice.
class Die extends StatefulWidget {
  const Die({
    super.key,
    required this.value,
    required this.count,
    required this.color,
    this.size = 72,
    this.onTap,
    this.glowing = false,
  });

  /// 1–6, or null before the first roll.
  final int? value;
  final int count;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  /// Pulses to say "tap me".
  final bool glowing;

  @override
  State<Die> createState() => _DieState();
}

class _DieState extends State<Die> with TickerProviderStateMixin {
  late final AnimationController _roll = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _rnd = math.Random();
  int _face = 1;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _roll.addListener(() {
      // Flick through random faces while tumbling, slowing down as it lands.
      final t = _roll.value;
      if (t < 0.8 && _rnd.nextDouble() < 0.35 + 0.4 * (1 - t)) setState(() => _face = _rnd.nextInt(6) + 1);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(Die old) {
    super.didUpdateWidget(old);
    if (widget.count != old.count && widget.value != null && !_still) _roll.forward(from: 0);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.glowing && !_still) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _roll.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: AnimatedBuilder(
          animation: Listenable.merge([_roll, _pulse]),
          builder: (context, _) {
            final rolling = _roll.isAnimating;
            final t = Curves.easeOutBack.transform(_roll.value);
            final face = rolling ? _face : widget.value;
            final line = DuoColors.line(context);
            return Transform.translate(
              // A little hop while tumbling.
              offset: Offset(0, rolling ? -math.sin(_roll.value * math.pi) * widget.size * 0.35 : 0),
              child: Transform.rotate(
                angle: rolling ? (1 - t) * math.pi * 2.5 : 0,
                child: Transform.scale(
                  scale: 1 + _pulse.value * 0.08,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(widget.size * 0.22),
                      border: Border.all(color: line, width: 2.5),
                      boxShadow: [
                        BoxShadow(color: line, offset: const Offset(4, 4)),
                        if (widget.glowing)
                          BoxShadow(
                            color: DuoColors.tomato.withValues(alpha: 0.25 + 0.35 * _pulse.value),
                            blurRadius: 14,
                            spreadRadius: 3,
                          ),
                      ],
                    ),
                    child: face == null
                        ? Center(
                            child: Text(
                              '?',
                              style: TextStyle(
                                fontSize: widget.size * 0.45,
                                fontWeight: FontWeight.w900,
                                color: DuoColors.ink.withValues(alpha: 0.35),
                              ),
                            ),
                          )
                        : CustomPaint(painter: _PipsPainter(face)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PipsPainter extends CustomPainter {
  _PipsPainter(this.face);

  final int face;

  // Pip positions on a 3×3 grid (0..2), per face.
  static const _layouts = {
    1: [(1, 1)],
    2: [(0, 0), (2, 2)],
    3: [(0, 0), (1, 1), (2, 2)],
    4: [(0, 0), (2, 0), (0, 2), (2, 2)],
    5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
    6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 4;
    final r = size.width * 0.09;
    final pip = Paint()..color = DuoColors.ink;
    for (final (x, y) in _layouts[face]!) {
      canvas.drawCircle(Offset(step * (x + 1), step * (y + 1)), r, pip);
    }
  }

  @override
  bool shouldRepaint(_PipsPainter old) => old.face != face;
}
