import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/musevee_palette.dart';

/// Lightweight GPU-accelerated tactile scale wrapper (`pressedScale` dip + Mograph
/// `Curves.easeOutBack` spring rebound on release) for transport buttons,
/// playlist/folder cards, and interactive controls.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double pressedScale;
  final Duration duration;
  final Duration releaseDuration;
  final Curve curve;
  final Curve releaseCurve;
  final HitTestBehavior behavior;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.pressedScale = 0.94,
    this.duration = const Duration(milliseconds: 90),
    this.releaseDuration = const Duration(milliseconds: 240),
    this.curve = Curves.easeOutCubic,
    this.releaseCurve = Curves.easeOutBack,
    this.behavior = HitTestBehavior.deferToChild,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    final target = widget.enabled && value;
    if (_isPressed == target || !mounted) return;
    setState(() => _isPressed = target);
  }

  @override
  void didUpdateWidget(covariant PressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _isPressed) {
      _isPressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = AnimatedScale(
      scale: (_isPressed && widget.enabled) ? widget.pressedScale : 1.0,
      duration: _isPressed ? widget.duration : widget.releaseDuration,
      curve: _isPressed ? widget.curve : widget.releaseCurve,
      child: widget.child,
    );

    if (widget.onTap != null) {
      // Keep GestureDetector mounted at the root even when enabled toggles so
      // child cover images are never unmounted and remounted (blink/flicker).
      return GestureDetector(
        behavior: widget.behavior,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: widget.enabled ? widget.onTap : null,
        child: content,
      );
    }

    // Passive mode: scale feedback only, lets the child's own gesture handle taps.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: content,
    );
  }
}

/// Passive Mograph tap feedback wrapper that never intercepts child gestures
/// (`IconButton`, `TextButton`, `InkWell`, `PopupMenuButton`, `ListTile`):
/// - Pointer down: crisp tactile squash (`pressedScale`, `85ms easeOutCubic`).
/// - Pointer up: `Curves.easeOutBack` spring rebound (`260ms`) plus optional
///   directional impulse [tapOffsetKick] and micro-tilt [tapRotationRad].
class MographSpringTap extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final double tapRotationRad;
  final Offset tapOffsetKick;
  final bool enabled;

  const MographSpringTap({
    super.key,
    required this.child,
    this.pressedScale = 0.86,
    this.tapRotationRad = 0.0,
    this.tapOffsetKick = Offset.zero,
    this.enabled = true,
  });

  @override
  State<MographSpringTap> createState() => _MographSpringTapState();
}

class _MographSpringTapState extends State<MographSpringTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _kickController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _kickController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _kickController.dispose();
    super.dispose();
  }

  void _handlePointerDown() {
    if (!widget.enabled || _isPressed || !mounted) return;
    setState(() => _isPressed = true);
  }

  void _handlePointerUp() {
    if (!mounted) return;
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
    if (widget.enabled &&
        (widget.tapRotationRad != 0.0 || widget.tapOffsetKick != Offset.zero)) {
      _kickController.forward(from: 0.0);
    }
  }

  void _handlePointerCancel() {
    if (_isPressed && mounted) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body = AnimatedScale(
      scale: (_isPressed && widget.enabled) ? widget.pressedScale : 1.0,
      duration: _isPressed
          ? const Duration(milliseconds: 85)
          : const Duration(milliseconds: 250),
      curve: _isPressed ? Curves.easeOutCubic : Curves.easeOutBack,
      child: widget.child,
    );

    if (widget.tapRotationRad != 0.0 || widget.tapOffsetKick != Offset.zero) {
      body = AnimatedBuilder(
        animation: _kickController,
        builder: (context, child) {
          final t = _kickController.value;
          // Smooth damped single-cycle wave returning strictly to 0 at t = 0 & t = 1.
          // Always keep Transform nodes in the tree so RenderObject depth never mutates.
          final wave =
              (t == 0.0 || t == 1.0) ? 0.0 : math.sin(t * math.pi * 1.35) * (1.0 - t);
          Widget transformed = child!;
          if (widget.tapRotationRad != 0.0) {
            transformed = Transform.rotate(
              angle: wave * widget.tapRotationRad,
              child: transformed,
            );
          }
          if (widget.tapOffsetKick != Offset.zero) {
            transformed = Transform.translate(
              offset: widget.tapOffsetKick * wave * 1.6,
              child: transformed,
            );
          }
          return transformed;
        },
        child: body,
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handlePointerDown(),
      onPointerUp: (_) => _handlePointerUp(),
      onPointerCancel: (_) => _handlePointerCancel(),
      child: body,
    );
  }
}

/// One-shot Mograph spring pop + rotation kick whenever [stateKey] changes
/// (e.g., Play/Pause, Favorite Heart, Shuffle, Repeat Mode, or selection count).
class MographStatePop extends StatefulWidget {
  final Object? stateKey;
  final Widget child;
  final double scaleBoost;
  final double rotationKickRad;
  final Duration duration;

  const MographStatePop({
    super.key,
    required this.stateKey,
    required this.child,
    this.scaleBoost = 0.18,
    this.rotationKickRad = 0.0,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<MographStatePop> createState() => _MographStatePopState();
}

class _MographStatePopState extends State<MographStatePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void didUpdateWidget(covariant MographStatePop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.stateKey != oldWidget.stateKey) {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final bool isSettled = t == 0.0 || t == 1.0;
        final springT = isSettled ? 1.0 : Curves.easeOutBack.transform(t);
        final swell = isSettled ? 0.0 : math.sin(t * math.pi) * (1.0 - (t * 0.35));
        final scale = (1.0 + (swell * widget.scaleBoost)).clamp(0.7, 1.45);
        Widget result = Transform.scale(
          scale: scale,
          child: child,
        );
        if (widget.rotationKickRad != 0.0) {
          result = Transform.rotate(
            angle: (1.0 - springT) * widget.rotationKickRad,
            child: result,
          );
        }
        return result;
      },
      child: widget.child,
    );
  }
}

/// Reusable Mograph [AnimatedSwitcher] transition (scale spring + fade, optional
/// rotation twist or directional slide) for icon toggles and panel switches.
class MographAnimatedSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final double beginScale;
  final double rotationTurns;
  final Offset slideOffset;
  final AlignmentGeometry alignment;
  final StackFit stackFit;

  const MographAnimatedSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.reverseDuration = const Duration(milliseconds: 140),
    this.beginScale = 0.72,
    this.rotationTurns = 0.0,
    this.slideOffset = Offset.zero,
    this.alignment = Alignment.center,
    this.stackFit = StackFit.loose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      // Keep parent animation linear ([0, 1]) so Interval/Fade never receives
      // an overshot value from Curves.easeOutBack.
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: stackFit,
        alignment: alignment,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final fade = animation.drive(
          CurveTween(curve: const Interval(0.0, 0.72, curve: Curves.easeOutCubic)),
        );
        Widget transitioned = child;
        if (beginScale != 1.0) {
          transitioned = ScaleTransition(
            scale: animation.drive(
              Tween<double>(begin: beginScale, end: 1.0).chain(
                CurveTween(curve: Curves.easeOutBack),
              ),
            ),
            child: transitioned,
          );
        }
        if (rotationTurns != 0.0) {
          transitioned = RotationTransition(
            turns: animation.drive(
              Tween<double>(begin: rotationTurns, end: 0.0).chain(
                CurveTween(curve: Curves.easeOutBack),
              ),
            ),
            child: transitioned,
          );
        }
        if (slideOffset != Offset.zero) {
          transitioned = SlideTransition(
            position: animation.drive(
              Tween<Offset>(begin: slideOffset, end: Offset.zero).chain(
                CurveTween(curve: Curves.easeOutCubic),
              ),
            ),
            child: transitioned,
          );
        }
        return FadeTransition(opacity: fade, child: transitioned);
      },
      child: child,
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
  final Color? color;
  final double size;

  const AnimatedEqualizerIcon({
    super.key,
    required this.isPlaying,
    this.color,
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
    final resolvedColor = widget.color ?? context.palette.nowPlayingPrimary;
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
                color: resolvedColor,
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

/// Mograph vector-morphing Play <-> Pause icon (`AnimatedIcons.play_pause`)
/// with a spring scale bounce + subtle micro-rotation when toggling states.
class MographPlayPauseIcon extends StatefulWidget {
  final bool isPlaying;
  final double size;
  final Color? color;
  final bool enableBounceAndRotation;

  const MographPlayPauseIcon({
    super.key,
    required this.isPlaying,
    required this.size,
    this.color,
    this.enableBounceAndRotation = true,
  });

  @override
  State<MographPlayPauseIcon> createState() => _MographPlayPauseIconState();
}

class _MographPlayPauseIconState extends State<MographPlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _morphProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
    _morphProgress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant MographPlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
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
    final resolvedColor = widget.color ?? context.palette.textPrimary;
    return RepaintBoundary(
      child: AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _morphProgress,
        size: widget.size,
        color: resolvedColor,
      ),
    );
  }
}


