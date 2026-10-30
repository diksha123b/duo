import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Endlessly drifts its [children] sideways, like a shop-window ticker.
/// Stands still when the system asks for reduced motion.
class Marquee extends StatefulWidget {
  const Marquee({super.key, required this.children, this.height = 120, this.speed = 30, this.gap = 12});

  final List<Widget> children;
  final double height;

  /// Logical pixels per second.
  final double speed;
  final double gap;

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // The list repeats its children; jump back by one copy to loop seamlessly.
    final half = pos.maxScrollExtent / 2;
    var next = pos.pixels + widget.speed * dt;
    if (half > 0 && next >= half) next -= half;
    _scroll.jumpTo(next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [...widget.children, ...widget.children, ...widget.children, ...widget.children];
    return SizedBox(
      height: widget.height,
      child: IgnorePointer(
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.none,
          itemCount: items.length,
          separatorBuilder: (_, _) => SizedBox(width: widget.gap),
          itemBuilder: (_, i) => Center(child: items[i]),
        ),
      ),
    );
  }
}
