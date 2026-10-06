// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
// Kyant 2.0.0 catalog controls adapted to Flutter. Apache-2.0; see NOTICE.
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../kyant_glass.dart';

class LiquidButton extends StatelessWidget {
  const LiquidButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.backdrop,
    this.radius = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  });
  final Widget child;
  final VoidCallback? onPressed;
  final KyantBackdrop? backdrop;
  final double radius;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => KyantGlassControl(
    radius: radius,
    enabled: onPressed != null,
    child: KyantGlass(
      radius: radius,
      backdrop: backdrop,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: child,
      ),
    ),
  );
}

class LiquidToggle extends StatelessWidget {
  const LiquidToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.backdrop,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final KyantBackdrop? backdrop;
  @override
  Widget build(BuildContext context) => _LiquidTrack(
    value: value ? 1 : 0,
    toggle: true,
    onChanged: onChanged == null ? null : (v) => onChanged!(v >= .5),
    backdrop: backdrop,
  );
}

class LiquidSlider extends StatelessWidget {
  const LiquidSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.backdrop,
  }) : assert(max > min),
       assert(value >= min && value <= max);
  final double value, min, max;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final KyantBackdrop? backdrop;
  @override
  Widget build(BuildContext context) => _LiquidTrack(
    value: (value - min) / (max - min),
    toggle: false,
    backdrop: backdrop,
    onChanged: onChanged == null
        ? null
        : (v) => onChanged!(min + v * (max - min)),
    onChangeEnd: onChangeEnd == null
        ? null
        : (v) => onChangeEnd!(min + v * (max - min)),
  );
}

class _LiquidTrack extends StatefulWidget {
  const _LiquidTrack({
    required this.value,
    required this.toggle,
    required this.onChanged,
    this.onChangeEnd,
    this.backdrop,
  });
  final double value;
  final bool toggle;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final KyantBackdrop? backdrop;
  @override
  State<_LiquidTrack> createState() => _LiquidTrackState();
}

class _LiquidTrackState extends State<_LiquidTrack>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _value = AnimationController.unbounded(
    vsync: this,
    value: widget.value,
  );
  late final _press = AnimationController.unbounded(vsync: this);
  late final _sx = AnimationController.unbounded(vsync: this, value: 1);
  late final _sy = AnimationController.unbounded(vsync: this, value: 1);
  late final Ticker _ticker = createTicker(_tick);
  late final Listenable _motion = Listenable.merge([_value, _press, _sx, _sy]);
  final _track = KyantBackdropController();
  final _thumbKey = GlobalKey();
  late final _mappedTrack = KyantTransformedBackdrop.dynamic(
    _track,
    transform: _trackTransform,
    repaint: _motion,
  );
  KyantCombinedBackdrop? _combined;
  KyantBackdrop? _parent;
  double _target = 0, _velocity = 0, _travel = 1;
  Duration? _last;
  bool _dragging = false;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);
  bool get _ltr => Directionality.of(context) == TextDirection.ltr;
  Matrix4 _trackTransform() {
    final box = _thumbKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Matrix4.identity();
    final world = box.getTransformTo(null);
    if (world.determinant().abs() < 1e-10) return Matrix4.identity();
    final p = _press.value.clamp(0.0, 1.0);
    final end = widget.toggle ? .75 : 1.0;
    return Matrix4.copy(world)
      ..translateByDouble(20, 12, 0, 1)
      ..scaleByDouble(2 / 3 + (end - 2 / 3) * p, end * p, 1, 1)
      ..translateByDouble(-20, -12, 0, 1)
      ..multiply(Matrix4.inverted(world));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connect();
  }

  void _connect() {
    _track.captureOnNative =
        KyantRenderSettings.of(context) == KyantPipeline.explicit;
    final parent = widget.backdrop ?? KyantBackdropScope.maybeOf(context);
    if (parent != _parent ||
        _combined == null ||
        _combined!.pixelRatio != MediaQuery.devicePixelRatioOf(context)) {
      _combined?.dispose();
      _parent = parent;
      _combined = KyantCombinedBackdrop([
        ?parent,
        _mappedTrack,
      ], pixelRatio: MediaQuery.devicePixelRatioOf(context));
    }
  }

  @override
  void didUpdateWidget(_LiquidTrack old) {
    super.didUpdateWidget(old);
    _connect();
    if (!_dragging && old.value != widget.value) {
      _spring(_value, widget.value, 1000, 1);
    }
    if (old.onChanged != null && widget.onChanged == null) _cancel();
  }

  void _spring(
    AnimationController c,
    double target,
    double stiffness,
    double damping,
  ) {
    if (_reduce) {
      c.value = target;
      return;
    }
    c.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness,
          ratio: damping,
        ),
        c.value,
        target,
        c.velocity,
        tolerance: const Tolerance(distance: .001, velocity: .01),
      ),
    );
  }

  void _pressed(bool value) {
    _spring(_press, value ? 1 : 0, 1000, 1);
    _spring(_sx, value ? 1.5 : 1, 250, .6);
    _spring(_sy, value ? 1.5 : 1, 250, .7);
  }

  void _tick(Duration elapsed) {
    final dt = _last == null
        ? 1 / 60
        : ((elapsed - _last!).inMicroseconds / 1e6).clamp(1 / 240, .04);
    _last = elapsed;
    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 1),
      _value.value,
      _target,
      _velocity,
    );
    _velocity = simulation.dx(dt);
    _value.value = _reduce ? _target : simulation.x(dt);
  }

  void _commit(double value) {
    final next = value.clamp(0.0, 1.0);
    _spring(_value, next, 1000, 1);
    widget.onChanged?.call(next);
    widget.onChangeEnd?.call(next);
  }

  void _cancel() {
    _dragging = false;
    _ticker.stop();
    _last = null;
    _spring(_value, widget.value, 1000, 1);
    _pressed(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _combined?.dispose();
    _mappedTrack.dispose();
    _track.dispose();
    for (final c in [_value, _press, _sx, _sy]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.toggle
        ? (dark ? const Color(0xFF30D158) : const Color(0xFF34C759))
        : (dark ? const Color(0xFF0091FF) : const Color(0xFF0088FF));
    final trackColor = dark ? const Color(0x5C787880) : const Color(0x33787878);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.toggle
            ? 64.0
            : (constraints.hasBoundedWidth ? constraints.maxWidth : 240.0);
        _travel = widget.toggle ? 20 : width;
        return Semantics(
          enabled: enabled,
          toggled: widget.toggle ? widget.value >= .5 : null,
          slider: !widget.toggle,
          value: widget.toggle ? null : '${(widget.value * 100).round()}%',
          increasedValue: widget.toggle
              ? null
              : '${((widget.value + .05).clamp(0, 1) * 100).round()}%',
          decreasedValue: widget.toggle
              ? null
              : '${((widget.value - .05).clamp(0, 1) * 100).round()}%',
          onTap: widget.toggle && enabled
              ? () => _commit(widget.value >= .5 ? 0 : 1)
              : null,
          onIncrease: !widget.toggle && enabled
              ? () => _commit(widget.value + .05)
              : null,
          onDecrease: !widget.toggle && enabled
              ? () => _commit(widget.value - .05)
              : null,
          child: Focus(
            canRequestFocus: enabled,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent || !enabled) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.enter) {
                if (widget.toggle) _commit(widget.value >= .5 ? 0 : 1);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _commit(widget.value + (_ltr ? .05 : -.05));
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _commit(widget.value + (_ltr ? -.05 : .05));
              } else {
                return KeyEventResult.ignored;
              }
              return KeyEventResult.handled;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled ? (_) => _pressed(true) : null,
              onTapCancel: enabled ? () => _pressed(false) : null,
              onTapUp: enabled
                  ? (e) {
                      final v = widget.toggle
                          ? (widget.value >= .5 ? 0.0 : 1.0)
                          : (_ltr
                                ? e.localPosition.dx / width
                                : 1 - e.localPosition.dx / width);
                      _commit(v);
                      _pressed(false);
                    }
                  : null,
              onHorizontalDragStart: enabled
                  ? (_) {
                      _dragging = true;
                      _target = _value.value;
                      _velocity = _value.velocity;
                      _value.stop();
                      _last = null;
                      _pressed(true);
                      _ticker.start();
                    }
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (e) {
                      _target =
                          (_target + (_ltr ? 1 : -1) * e.delta.dx / _travel)
                              .clamp(0.0, 1.0);
                      if (!widget.toggle) widget.onChanged!(_target);
                    }
                  : null,
              onHorizontalDragEnd: enabled
                  ? (_) {
                      _dragging = false;
                      _ticker.stop();
                      _last = null;
                      _commit(
                        widget.toggle ? (_target >= .5 ? 1 : 0) : _target,
                      );
                      _pressed(false);
                    }
                  : null,
              onHorizontalDragCancel: enabled ? _cancel : null,
              child: SizedBox(
                width: width,
                height: 48,
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) {
                    final p = _reduce ? 0.0 : _press.value.clamp(0.0, 1.0);
                    final v = _value.value.clamp(0.0, 1.0);
                    final x = widget.toggle
                        ? 2 + 20 * v
                        : (width * v - 20).clamp(-10.0, width - 30);
                    final velocity =
                        (_dragging ? _velocity : _value.velocity) /
                        (widget.toggle ? 50 : 10);
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        KyantBackdropSource(
                          controller: _track,
                          child: SizedBox(
                            width: width,
                            height: widget.toggle ? 28 : 6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(100),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: widget.toggle
                                        ? Color.lerp(trackColor, accent, v)!
                                        : trackColor,
                                  ),
                                  if (!widget.toggle)
                                    Align(
                                      alignment: _ltr
                                          ? Alignment.centerLeft
                                          : Alignment.centerRight,
                                      child: FractionallySizedBox(
                                        widthFactor: v,
                                        child: ColoredBox(color: accent),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _ltr ? x : width - 40 - x,
                          top: 12,
                          width: 40,
                          height: 24,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(
                              _reduce
                                  ? 1
                                  : _sx.value /
                                        (1 - (velocity * .75).clamp(-.2, .2)),
                              _reduce
                                  ? 1
                                  : _sy.value *
                                        (1 - (velocity * .25).clamp(-.2, .2)),
                              1,
                            ),
                            child: KyantGlass(
                              key: _thumbKey,
                              backdrop:
                                  _track.captureOnNative ||
                                      !KyantGlass.supportsLiveRefraction
                                  ? _combined
                                  : null,
                              radius: 12,
                              blur: 8 * (1 - p),
                              refractionHeight: (widget.toggle ? 5 : 10) * p,
                              refractionAmount: (widget.toggle ? 10 : 14) * p,
                              dispersion: 1,
                              tint: Colors.white.withValues(alpha: 1 - p),
                              highlightStyle: KyantHighlight.ambient(
                                width: .5 / 1.5,
                                blur: .25 / 1.5,
                                alpha: p,
                              ),
                              shadow: const KyantShadow(
                                radius: 4,
                                offset: Offset(0, 4 / 6),
                                color: Color(0x0D000000),
                              ),
                              innerShadow: KyantShadow.inner(
                                radius: 4 * p,
                                offset: Offset(0, 4 * p),
                                alpha: p,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
