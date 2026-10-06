// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
// Copyright 2025 Kyant. Apache-2.0; see LICENSE and NOTICE.
// LiquidBottomTabs / DampedDragAnimation adapted to Flutter.
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../kyant_glass.dart';

class KyantTab {
  const KyantTab({required this.label, this.icon});
  final String label;
  final IconData? icon;
}

/// Two backdrop domains: the page behind the container, then the container
/// and its glyphs behind the moving lens. Neither source includes its consumer.
class LiquidBottomTabs extends StatefulWidget {
  const LiquidBottomTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    required this.tint,
    required this.accent,
    required this.foreground,
    this.width = 200,
    this.height = 64,
    this.fontSize = 12,
    this.contentSpacing = 2,
    this.backdrop,
    this.blur = 2,
    this.lensHeight = 10,
    this.lensAmount = 40,
    this.indicatorHeight = 12,
    this.indicatorAmount = 17,
  }) : assert(tabs.length >= 2),
       assert(selected >= 0 && selected < tabs.length);
  final List<KyantTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color tint, accent, foreground;
  final double width,
      height,
      fontSize,
      contentSpacing,
      blur,
      lensHeight,
      lensAmount,
      indicatorHeight,
      indicatorAmount;
  final KyantBackdrop? backdrop;

  @override
  State<LiquidBottomTabs> createState() => _LiquidBottomTabsState();
}

class _LiquidBottomTabsState extends State<LiquidBottomTabs>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _value = AnimationController.unbounded(
    vsync: this,
    value: widget.selected.toDouble(),
  );
  late final _press = AnimationController.unbounded(vsync: this);
  late final _sx = AnimationController.unbounded(vsync: this, value: 1);
  late final _sy = AnimationController.unbounded(vsync: this, value: 1);
  late final _shift = AnimationController.unbounded(vsync: this);
  late final _motion = Listenable.merge([_value, _press, _sx, _sy, _shift]);
  late final _glyphMotion = Listenable.merge([_value, _press]);
  final _glyphBackdrop = KyantBackdropController();
  double _target = 0;
  int? _pointer;
  int _generation = 0;
  bool _dragging = false;
  late final Ticker _dragTicker = createTicker(_dragTick);
  Duration? _lastDragTick;
  double _dragVelocity = 0;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);
  double get _tabWidth => (widget.width - 8) / widget.tabs.length;

  @override
  void initState() {
    super.initState();
    _target = widget.selected.toDouble();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _glyphBackdrop.captureOnNative =
        KyantRenderSettings.of(context) == KyantPipeline.explicit;
  }

  Future<void> _spring(
    AnimationController animation,
    double target,
    double stiffness,
    double ratio, {
    double? velocity,
  }) async {
    if (_reduce) {
      animation.value = target;
      return;
    }
    try {
      await animation
          .animateWith(
            SpringSimulation(
              SpringDescription.withDampingRatio(
                mass: 1,
                stiffness: stiffness,
                ratio: ratio,
              ),
              animation.value,
              target,
              velocity ?? animation.velocity,
              tolerance: const Tolerance(distance: .001, velocity: .01),
            ),
          )
          .orCancel;
    } on TickerCanceled {
      /* A newer pointer takes over with the current velocity. */
    }
  }

  void _pressed() {
    _spring(_press, 1, 1000, 1);
    _spring(_sx, 78 / 56, 250, .6);
    _spring(_sy, 78 / 56, 250, .7);
  }

  void _dragTick(Duration elapsed) {
    if (!_dragging) return;
    final dt = _lastDragTick == null
        ? 1 / 60
        : ((elapsed - _lastDragTick!).inMicroseconds / 1000000).clamp(
            1 / 240,
            .04,
          );
    _lastDragTick = elapsed;
    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 1),
      _value.value,
      _target,
      _dragVelocity,
    );
    _dragVelocity = simulation.dx(dt);
    _value.value = _reduce ? _target : simulation.x(dt);
  }

  void _release() {
    _spring(_press, 0, 1000, 1);
    _spring(_sx, 1, 250, .6);
    _spring(_sy, 1, 250, .7);
    _spring(_shift, 0, 300, 1);
  }

  void _settle(int index, {bool notify = true}) {
    final generation = ++_generation;
    _target = index.toDouble();
    _pressed();
    if (notify && index != widget.selected) widget.onChanged(index);
    _spring(_value, _target, 1000, 1, velocity: _dragVelocity).then((_) {
      if (mounted && generation == _generation && _pointer == null) _release();
    });
  }

  @override
  void didUpdateWidget(LiquidBottomTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        oldWidget.selected != widget.selected &&
        _target != widget.selected) {
      _settle(widget.selected, notify: false);
    }
  }

  void _cancel() {
    _dragTicker.stop();
    _lastDragTick = null;
    _pointer = null;
    _dragging = false;
    _settle(widget.selected, notify: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dragTicker.dispose();
    for (final c in [_value, _press, _sx, _sy, _shift]) {
      c.dispose();
    }
    _glyphBackdrop.dispose();
    super.dispose();
  }

  Widget _buildShell(BuildContext context) => KyantBackdropSource(
    controller: _glyphBackdrop,
    repaint: _motion,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: KyantGlass(
        backdrop: widget.backdrop,
        radius: widget.height / 2,
        blur: widget.blur,
        refractionHeight: widget.lensHeight,
        refractionAmount: widget.lensAmount,
        dispersion: 1,
        highlight: .07,
        tint: widget.tint,
        child: AnimatedBuilder(
          animation: _glyphMotion,
          builder: (context, _) {
            final p = _reduce ? 0.0 : _press.value.clamp(0.0, 1.0);
            final index = _value.value.clamp(0.0, widget.tabs.length - 1.0);
            return Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  for (var i = 0; i < widget.tabs.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: widget.selected == i,
                        button: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _settle(i),
                            borderRadius: BorderRadius.circular(100),
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            child: Center(
                              child: Transform.scale(
                                scale:
                                    1 +
                                    .2 *
                                        p *
                                        (1 - (index - i).abs()).clamp(0.0, 1.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (widget.tabs[i].icon != null) ...[
                                      SizedBox.square(
                                        dimension: 24,
                                        child: Center(
                                          child: Icon(
                                            widget.tabs[i].icon,
                                            size: 24,
                                            color: Color.lerp(
                                              widget.foreground,
                                              widget.accent,
                                              (1 - (index - i).abs()).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: widget.contentSpacing),
                                    ],
                                    Text(
                                      widget.tabs[i].label,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: widget.fontSize,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                        color: Color.lerp(
                                          widget.foreground,
                                          widget.accent,
                                          (1 - (index - i).abs()).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (_pointer != null) return;
      _pointer = event.pointer;
      _generation++;
      _pressed();
    },
    onPointerUp: (event) {
      if (_pointer != event.pointer) return;
      _pointer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pointer == null && !_value.isAnimating) _release();
      });
    },
    onPointerCancel: (event) {
      if (_pointer == event.pointer) _cancel();
    },
    child: GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) {
        _dragVelocity = _value.velocity;
        _value.stop();
        _dragging = true;
        _target = _value.value.clamp(0.0, widget.tabs.length - 1.0);
        _lastDragTick = null;
        _dragTicker.start();
      },
      onHorizontalDragUpdate: (event) {
        final direction = Directionality.of(context) == TextDirection.ltr
            ? 1
            : -1;
        _target = (_target + direction * event.delta.dx / _tabWidth).clamp(
          0.0,
          widget.tabs.length - 1.0,
        );
        _shift.value += event.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        _dragTicker.stop();
        _lastDragTick = null;
        _dragging = false;
        _settle(_target.round());
      },
      onHorizontalDragCancel: _cancel,
      child: AnimatedBuilder(
        animation: _motion,
        child: _buildShell(context),
        builder: (context, shell) {
          final p = _reduce ? 0.0 : _press.value.clamp(0.0, 1.0);
          final index = _value.value.clamp(0.0, widget.tabs.length - 1.0);
          final velocity = ((_dragging ? _dragVelocity : _value.velocity) / 10)
              .clamp(-.27, .27);
          final fraction = (_shift.value / widget.width).clamp(-1.0, 1.0);
          final shift =
              4 * fraction.sign * Curves.easeOut.transform(fraction.abs());
          final ltr = Directionality.of(context) == TextDirection.ltr;
          final visualIndex = ltr ? index : widget.tabs.length - 1 - index;
          final scale = 1 + 16 / widget.width * p;
          final width = _tabWidth + 8 * p;
          final height = widget.height - 8 + 4 * p;
          return Transform.translate(
            offset: Offset(shift, 0),
            child: Transform.scale(
              scale: scale,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: shell!),
                    Positioned(
                      left: 4 + visualIndex * _tabWidth - 4 * p,
                      top: (widget.height - height) / 2,
                      width: width,
                      height: height,
                      child: IgnorePointer(
                        child: Transform(
                          key: const ValueKey('kyant-dock-lens'),
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(
                            _reduce ? 1 : _sx.value / (1 - velocity * .75),
                            _reduce ? 1 : _sy.value * (1 - velocity * .25),
                            1,
                          ),
                          child: KyantGlass(
                            backdrop: _glyphBackdrop,
                            radius: height / 2,
                            blur: 0,
                            refractionHeight: widget.indicatorHeight * p,
                            refractionAmount: widget.indicatorAmount * p,
                            dispersion: 1,
                            highlight: .07 * p,
                            tint:
                                (Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white
                                        : Colors.black)
                                    .withValues(alpha: .10 * (1 - p) + .03 * p),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
