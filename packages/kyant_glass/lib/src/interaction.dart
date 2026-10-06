// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
// Copyright 2025 Kyant. Apache-2.0; see LICENSE and NOTICE.
// InteractiveHighlight and LiquidButton motion adapted for Flutter.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

final _pressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 300,
  ratio: .5,
);

/// Press expansion and pointer-follow deformation shared by glass controls.
/// Listener observes pointers without claiming a TextField's gesture arena.
class KyantGlassControl extends StatefulWidget {
  const KyantGlassControl({
    super.key,
    required this.child,
    this.enabled = true,
    this.expansion = 4,
    this.radius = 100,
  });
  final Widget child;
  final bool enabled;
  final double expansion, radius;

  @override
  State<KyantGlassControl> createState() => _KyantGlassControlState();
}

class _KyantGlassControlState extends State<KyantGlassControl>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _press = AnimationController.unbounded(vsync: this);
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  int? _pointer;
  Offset _start = Offset.zero;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _spring(AnimationController controller, double target) {
    if (_reduce) {
      controller.value = target;
    } else {
      controller.animateWith(
        SpringSimulation(
          _pressSpring,
          controller.value,
          target,
          controller.velocity,
          tolerance: const Tolerance(distance: .001, velocity: .01),
        ),
      );
    }
  }

  void _release() {
    _pointer = null;
    _spring(_press, 0);
    _spring(_x, 0);
    _spring(_y, 0);
  }

  @override
  void didUpdateWidget(KyantGlassControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) _release();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _release();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _press.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x.clamp(-12.0, 12.0));
    return (e - 1) / (e + 1);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (!widget.enabled || _pointer != null) return;
      _pointer = event.pointer;
      _start = event.localPosition;
      _x.value = _y.value = 0;
      _spring(_press, 1);
    },
    onPointerMove: (event) {
      if (event.pointer != _pointer) return;
      final offset = event.localPosition - _start;
      _x.value = offset.dx;
      _y.value = offset.dy;
    },
    onPointerUp: (event) {
      if (event.pointer == _pointer) _release();
    },
    onPointerCancel: (event) {
      if (event.pointer == _pointer) _release();
    },
    child: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: Listenable.merge([_press, _x, _y]),
        child: widget.child,
        builder: (context, child) {
          final render = context.findRenderObject();
          final size = render is RenderBox && render.hasSize
              ? render.size
              : constraints.biggest;
          if (!size.isFinite || size.shortestSide <= 0) return child!;
          final p = _reduce ? 0.0 : _press.value.clamp(0.0, 1.15);
          final offset = Offset(_x.value, _y.value);
          final scale = 1 + widget.expansion / size.height * p;
          final angle = math.atan2(offset.dy, offset.dx);
          final dragScale = widget.expansion / size.height;
          final sx =
              scale +
              dragScale *
                  (math.cos(angle) * offset.dx / size.longestSide).abs() *
                  math.min(size.width / size.height, 1);
          final sy =
              scale +
              dragScale *
                  (math.sin(angle) * offset.dy / size.longestSide).abs() *
                  math.min(size.height / size.width, 1);
          final translation = Offset(
            size.shortestSide * _tanh(.05 * offset.dx / size.shortestSide),
            size.shortestSide * _tanh(.05 * offset.dy / size.shortestSide),
          );
          return Transform.translate(
            offset: _reduce ? Offset.zero : translation,
            child: Transform(
              key: const ValueKey('kyant-press-transform'),
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                _reduce ? 1 : sx,
                _reduce ? 1 : sy,
                1,
              ),
              child: CustomPaint(
                foregroundPainter: _PointerLight(
                  point: _start + offset,
                  progress: p,
                  radius: widget.radius,
                ),
                child: child,
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _PointerLight extends CustomPainter {
  const _PointerLight({
    required this.point,
    required this.progress,
    required this.radius,
  });
  final Offset point;
  final double progress, radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= .001) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final center = Offset(
      point.dx.clamp(0, size.width),
      point.dy.clamp(0, size.height),
    );
    final reach = size.shortestSide * 1.5;
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Colors.white.withValues(alpha: .08 * progress),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: .15 * progress),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: reach)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PointerLight oldDelegate) =>
      point != oldDelegate.point ||
      progress != oldDelegate.progress ||
      radius != oldDelegate.radius;
}
