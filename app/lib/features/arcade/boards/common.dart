import 'package:flutter/material.dart';

import '../../../core/models.dart';

/// Every board gets the match and a way to send a move. Boards only render
/// and collect input; the server decides what's legal.
typedef SendMove = Future<void> Function(Map<String, dynamic> move);

abstract class BoardWidget extends StatelessWidget {
  const BoardWidget({super.key, required this.match, required this.send});

  final MatchInfo match;
  final SendMove send;

  bool get myTurn => match.active && match.yourTurn;

  /// Maps the server's seat number to "mine" or "theirs".
  bool isMine(Object? seat) => seat == match.seat;
}

/// The same match-and-move bundle for boards that keep their own state.
class Turn {
  const Turn(this.match, this.send);

  final MatchInfo match;
  final SendMove send;

  bool get myTurn => match.active && match.yourTurn;
  bool isMine(Object? seat) => seat == match.seat;
}
