import 'package:flutter/material.dart';

import '../../../ui/arcade_style.dart';
import '../../../ui/die.dart';
import '../../../ui/theme.dart';
import 'common.dart';

// The classic 15×15 ludo board. These cells mirror the server's track
// numbering exactly: index 0 is seat 0's start square, seat 1 starts at 26.
const _track = [
  (6, 1), (6, 2), (6, 3), (6, 4), (6, 5), //
  (5, 6), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6),
  (0, 7), (0, 8),
  (1, 8), (2, 8), (3, 8), (4, 8), (5, 8),
  (6, 9), (6, 10), (6, 11), (6, 12), (6, 13), (6, 14),
  (7, 14), (8, 14),
  (8, 13), (8, 12), (8, 11), (8, 10), (8, 9),
  (9, 8), (10, 8), (11, 8), (12, 8), (13, 8), (14, 8),
  (14, 7), (14, 6),
  (13, 6), (12, 6), (11, 6), (10, 6), (9, 6),
  (8, 5), (8, 4), (8, 3), (8, 2), (8, 1), (8, 0),
  (7, 0), (6, 0),
];
const _start = [0, 26];
const _safe = {0, 8, 13, 21, 26, 34, 39, 47};
const _homeColumn = [
  [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5)],
  [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9)],
];
const _bases = [
  [(1.5, 1.5), (1.5, 3.5), (3.5, 1.5), (3.5, 3.5)],
  [(10.5, 10.5), (10.5, 12.5), (12.5, 10.5), (12.5, 12.5)],
];

/// Board cell (row, col) of a token, from its progress.
(double, double) _cellOf(int seat, int token, int progress) {
  if (progress < 0) return _bases[seat][token];
  if (progress == 56) {
    // Finished tokens huddle in the centre.
    return (7.0 + (seat == 0 ? -0.35 : 0.35) * (token.isEven ? 1 : -1), 7.0 + (token < 2 ? -0.3 : 0.3));
  }
  if (progress >= 51) {
    final (r, c) = _homeColumn[seat][progress - 51];
    return (r.toDouble(), c.toDouble());
  }
  final (r, c) = _track[(_start[seat] + progress) % 52];
  return (r.toDouble(), c.toDouble());
}

class LudoBoard extends BoardWidget {
  const LudoBoard({super.key, required super.match, required super.send, this.otherName = 'them'});

  final String otherName;

  @override
  Widget build(BuildContext context) {
    final v = match.view;
    final tokens = (v['tokens'] as List).map((t) => (t as List).cast<int>()).toList();
    final movable = (v['movable'] as List).cast<int>().toSet();
    final roll = v['roll'] as int?;
    final last = v['last'] as Map?;
    final text = Theme.of(context).textTheme;
    final colors = [match.seat == 0 ? youColor : themColor, match.seat == 1 ? youColor : themColor];

    // Each player's latest roll; both dice are always on screen for both players.
    final dice = (v['dice'] as List? ?? const [null, null]).map((d) => d as Map?).toList();
    final mine = dice[match.seat];
    final theirs = dice[1 - match.seat];
    final who = last == null ? '' : (isMine(last['seat']) ? 'you' : otherName);
    final String status;
    if (myTurn && roll != null) {
      status = roll == 6 ? 'a six! 🎉 move a glowing token' : 'you rolled $roll! tap a glowing token';
    } else if (myTurn) {
      status = last?['passed'] == true && !isMine(last!['seat'])
          ? '$otherName rolled ${last['roll']} and couldn’t move. your turn!'
          : 'your turn. tap your die!';
    } else if (last == null) {
      status = 'six to leave base · land on them to send them home';
    } else if (last['captured'] == true) {
      status = '$who sent a token home! 💥';
    } else if (last['passed'] == true) {
      status = '$who rolled ${last['roll']} and couldn’t move';
    } else {
      status = match.active ? '$otherName is rolling…' : '';
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, box) {
              final cell = box.maxWidth / 15;
              return Stack(
                children: [
                  CustomPaint(
                    size: Size.square(box.maxWidth),
                    painter: _LudoPainter(colors: colors, line: DuoColors.line(context)),
                  ),
                  for (var seat = 0; seat < 2; seat++)
                    for (var t = 0; t < 4; t++)
                      Builder(
                        builder: (context) {
                          final (r, c) = _cellOf(seat, t, tokens[seat][t]);
                          final canMove = isMine(seat) && movable.contains(t);
                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutBack,
                            left: c * cell + cell * 0.12,
                            top: r * cell + cell * 0.12,
                            width: cell * 0.76,
                            height: cell * 0.76,
                            child: GestureDetector(
                              onTap: canMove ? () => send({'type': 'move', 'token': t}) : null,
                              child: AnimatedScale(
                                scale: canMove ? 1.2 : 1,
                                duration: const Duration(milliseconds: 250),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colors[seat],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: canMove ? DuoColors.tomato : DuoColors.ink,
                                      width: canMove ? 3 : 2,
                                    ),
                                    boxShadow: const [BoxShadow(color: DuoColors.ink, offset: Offset(1.5, 1.5))],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiePanel(
              label: 'you',
              die: mine,
              color: youColor,
              active: myTurn,
              // Your die is the roll button.
              onTap: myTurn && roll == null ? () => send({'type': 'roll'}) : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(status, textAlign: TextAlign.center, style: text.titleMedium),
              ),
            ),
            _DiePanel(label: otherName.toLowerCase(), die: theirs, color: themColor, active: match.active && !myTurn),
          ],
        ),
      ],
    );
  }
}

class _LudoPainter extends CustomPainter {
  _LudoPainter({required this.colors, required this.line});

  final List<Color> colors;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    Rect at(num r, num c, [num h = 1, num w = 1]) => Rect.fromLTWH(c * cell, r * cell, w * cell, h * cell);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      Paint()..color = const Color(0xFFFFFBF2),
    );
    // Bases: seat 0 top-left, seat 1 bottom-right; the other corners are decorative.
    final corners = [(0, 0, colors[0]), (9, 9, colors[1]), (0, 9, DuoColors.mint), (9, 0, DuoColors.grape)];
    for (final (r, c, color) in corners) {
      final rect = at(r, c, 6, 6).deflate(4);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)), Paint()..color = color);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)), stroke..strokeWidth = 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(cell * 0.8), const Radius.circular(10)),
        Paint()..color = Colors.white,
      );
    }
    for (var i = 0; i < _track.length; i++) {
      final (r, c) = _track[i];
      final rect = at(r, c);
      final fill = i == _start[0]
          ? colors[0]
          : i == _start[1]
          ? colors[1]
          : _safe.contains(i)
          ? DuoColors.sunflower.withValues(alpha: 0.6)
          : Colors.white;
      canvas.drawRect(rect, Paint()..color = fill);
      canvas.drawRect(rect, stroke..strokeWidth = 1);
      if (_safe.contains(i) && i != _start[0] && i != _start[1]) {
        final tp = TextPainter(
          text: TextSpan(
            text: '★',
            style: TextStyle(fontSize: cell * 0.6, color: line.withValues(alpha: 0.5)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
    }
    for (var seat = 0; seat < 2; seat++) {
      for (final (r, c) in _homeColumn[seat]) {
        canvas.drawRect(at(r, c), Paint()..color = colors[seat].withValues(alpha: 0.7));
        canvas.drawRect(at(r, c), stroke..strokeWidth = 1);
      }
    }
    // Home: the centre square.
    final home = at(6, 6, 3, 3);
    canvas.drawRect(home, Paint()..color = DuoColors.sunflower);
    canvas.drawRect(home, stroke..strokeWidth = 2);
    final tp = TextPainter(
      text: TextSpan(
        text: '🏠',
        style: TextStyle(fontSize: cell * 1.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, home.center - Offset(tp.width / 2, tp.height / 2));
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)), stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_LudoPainter old) => old.colors != colors || old.line != line;
}

/// One player's die with their name, kept on screen for both players.
class _DiePanel extends StatelessWidget {
  const _DiePanel({required this.label, required this.die, required this.color, required this.active, this.onTap});

  final String label;
  final Map? die;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = die?['value'] as int?;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Text(label, style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          AnimatedOpacity(
            opacity: active || value != null ? 1 : 0.5,
            duration: const Duration(milliseconds: 250),
            child: Die(
              value: value,
              count: die?['count'] as int? ?? 0,
              color: color,
              size: 68,
              glowing: onTap != null,
              onTap: onTap,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            onTap != null ? 'tap to roll' : (value == null ? 'no roll yet' : 'rolled $value'),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
