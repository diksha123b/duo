import 'package:flutter/material.dart';

import '../../../ui/arcade_style.dart';
import '../../../ui/theme.dart';
import 'common.dart';

class DotsAndBoxesBoard extends BoardWidget {
  const DotsAndBoxesBoard({super.key, required super.match, required super.send});

  @override
  Widget build(BuildContext context) {
    final v = match.view;
    final size = v['size'] as int;
    final h = (v['h'] as List).cast<int?>();
    final vert = (v['v'] as List).cast<int?>();
    final boxes = (v['boxes'] as List).cast<int?>();

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final step = box.maxWidth / (size + 0.6);
          final pad = step * 0.3;
          Offset dot(int r, int c) => Offset(pad + c * step, pad + r * step);

          void onTap(TapUpDetails d) {
            if (!myTurn) return;
            // Find the undrawn line closest to the tap.
            ({String dir, int r, int c})? best;
            var bestDist = step * 0.4;
            for (var r = 0; r <= size; r++) {
              for (var c = 0; c < size; c++) {
                if (h[r * size + c] != null) continue;
                final mid = (dot(r, c) + dot(r, c + 1)) / 2;
                final dist = (d.localPosition - mid).distance;
                if (dist < bestDist) (bestDist, best) = (dist, (dir: 'h', r: r, c: c));
              }
            }
            for (var r = 0; r < size; r++) {
              for (var c = 0; c <= size; c++) {
                if (vert[r * (size + 1) + c] != null) continue;
                final mid = (dot(r, c) + dot(r + 1, c)) / 2;
                final dist = (d.localPosition - mid).distance;
                if (dist < bestDist) (bestDist, best) = (dist, (dir: 'v', r: r, c: c));
              }
            }
            if (best != null) send({'dir': best.dir, 'r': best.r, 'c': best.c});
          }

          return GestureDetector(
            onTapUp: onTap,
            child: CustomPaint(
              size: Size.square(box.maxWidth),
              painter: _DotsPainter(
                size: size,
                h: h,
                v: vert,
                boxes: boxes,
                dot: dot,
                step: step,
                mine: match.seat,
                line: DuoColors.line(context),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.size,
    required this.h,
    required this.v,
    required this.boxes,
    required this.dot,
    required this.step,
    required this.mine,
    required this.line,
  });

  final int size;
  final List<int?> h;
  final List<int?> v;
  final List<int?> boxes;
  final Offset Function(int, int) dot;
  final double step;
  final int mine;
  final Color line;

  Color _of(int seat) => seat == mine ? youColor : themColor;

  @override
  void paint(Canvas canvas, Size _) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final owner = boxes[r * size + c];
        if (owner != null) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromPoints(dot(r, c), dot(r + 1, c + 1)).deflate(5), const Radius.circular(8)),
            Paint()..color = _of(owner),
          );
        }
      }
    }
    final ghost = Paint()
      ..color = line.withValues(alpha: 0.12)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    void seg(Offset a, Offset b, int? owner) => canvas.drawLine(
      a,
      b,
      owner == null
          ? ghost
          : (Paint()
              ..color = line
              ..strokeWidth = 6
              ..strokeCap = StrokeCap.round),
    );
    for (var r = 0; r <= size; r++) {
      for (var c = 0; c < size; c++) {
        seg(dot(r, c), dot(r, c + 1), h[r * size + c]);
      }
    }
    for (var r = 0; r < size; r++) {
      for (var c = 0; c <= size; c++) {
        seg(dot(r, c), dot(r + 1, c), v[r * (size + 1) + c]);
      }
    }
    for (var r = 0; r <= size; r++) {
      for (var c = 0; c <= size; c++) {
        canvas.drawCircle(dot(r, c), 7, Paint()..color = line);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => true;
}
