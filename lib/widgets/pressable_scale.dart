import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight GPU-accelerated tactile scale wrapper (`0.95` scale over `100ms`)
/// for transport buttons, playlist cards, and primary interactive controls.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;
  final HitTestBehavior behavior;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.95,
    this.duration = const Duration(milliseconds: 100),
    this.behavior = HitTestBehavior.deferToChild,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value || !mounted) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = AnimatedScale(
      scale: _isPressed ? widget.pressedScale : 1.0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    if (widget.onTap != null) {
      return GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: content,
      );
    }

    // Passive mode: scale feedback only, lets the child's own gesture handle taps.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: content,
    );
  }
}

/// Preserves all tab subtrees in memory via [IndexedStack] while animating
/// tab switches with a crisp `200ms` `Curves.easeOutCubic` Crossfade + Directional Slide (`dx: ±0.03`).
class AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(_fadeAnimation);
  }

  @override
  void didUpdateWidget(covariant AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.index != oldWidget.index) {
      final direction = widget.index > oldWidget.index ? 1.0 : -1.0;
      _fadeAnimation = Tween<double>(
        begin: 0.76,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ),
      );
      _slideAnimation = Tween<Offset>(
        begin: Offset(0.03 * direction, 0.0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ),
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: IndexedStack(
          index: widget.index,
          children: widget.children,
        ),
      ),
    );
  }
}

/// Lightweight 4-bar live equalizer indicator wrapped in [RepaintBoundary].
/// - When [isPlaying] is `true`, bars oscillate organically with distinct phase offsets.
/// - When [isPlaying] is `false`, bars settle into a low flat resting state.
class AnimatedEqualizerIcon extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;

  const AnimatedEqualizerIcon({
    super.key,
    required this.isPlaying,
    this.color = const Color(0xFF3898EC),
    this.size = 17.0,
  });

  @override
  State<AnimatedEqualizerIcon> createState() => _AnimatedEqualizerIconState();
}

class _AnimatedEqualizerIconState extends State<AnimatedEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedEqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _EqualizerBarsPainter(
                progress: _controller.value,
                isPlaying: widget.isPlaying,
                color: widget.color,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EqualizerBarsPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final Color color;

  const _EqualizerBarsPainter({
    required this.progress,
    required this.isPlaying,
    required this.color,
  });

  static const List<double> _phases = [0.0, 1.55, 3.15, 4.70];
  static const List<double> _minHeights = [0.22, 0.28, 0.24, 0.26];
  static const List<double> _amplitudes = [0.58, 0.68, 0.50, 0.62];
  static const List<double> _pausedHeights = [0.24, 0.36, 0.22, 0.30];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const barCount = 4;
    final totalWidth = size.width;
    final maxBarHeight = size.height * 0.88;
    final barWidth = (totalWidth * 0.165).clamp(2.0, 3.5);
    final gap = (totalWidth - (barWidth * barCount)) / (barCount + 1);
    final bottomY = size.height * 0.94;

    for (int i = 0; i < barCount; i++) {
      final double factor;
      if (!isPlaying) {
        factor = _pausedHeights[i];
      } else {
        final angle = (progress * 2 * math.pi) + _phases[i];
        // Smooth, relaxed sine wave normalized to [0.0, 1.0]
        final wave = (math.sin(angle) + 1.0) * 0.5;
        factor = (_minHeights[i] + (wave * _amplitudes[i])).clamp(0.20, 0.96);
      }

      final barHeight = (maxBarHeight * factor).clamp(2.5, maxBarHeight);
      final left = gap + i * (barWidth + gap);
      final top = bottomY - barHeight;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(1.4),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerBarsPainter oldDelegate) {
    return oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color ||
        (isPlaying && oldDelegate.progress != progress);
  }
}

