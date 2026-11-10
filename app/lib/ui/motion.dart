import 'package:flutter/material.dart';

/// True when the phone asks for less motion. Decorative animations are
/// skipped then; content still appears at once.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and lifts a list item into place. Items further down the list start
/// a little later, so a list arrives like a team walking out. Only the first
/// [maxStaggered] items animate; the rest are simply shown.
class EntranceFade extends StatefulWidget {
  const EntranceFade({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Position in its list, for the stagger.
  final int index;

  static const maxStaggered = 8;
  static const _step = Duration(milliseconds: 40);
  static const _duration = Duration(milliseconds: 300);

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final delay = EntranceFade._step * widget.index.clamp(0, EntranceFade.maxStaggered);
    final total = delay + EntranceFade._duration;
    _controller = AnimationController(vsync: this, duration: total);
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (widget.index >= EntranceFade.maxStaggered || reduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, child) => Opacity(
      opacity: _progress.value,
      child: Transform.translate(offset: Offset(0, 18 * (1 - _progress.value)), child: child),
    ),
    child: widget.child,
  );
}

/// Springs its child up from nothing, for trophies and other moments.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.duration = const Duration(milliseconds: 700)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
    duration: duration,
    curve: Curves.elasticOut,
    builder: (context, v, child) => Transform.scale(scale: v, child: child),
    child: child,
  );
}
