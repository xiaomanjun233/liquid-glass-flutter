import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'diagnostics.dart';

abstract class KyantBackdrop implements Listenable {
  ui.Image? get image;
  Rect get rect;
  Matrix4 get imageToGlobal;
  int get revision;
}

/// An explicit underlay for renderers without ImageFilter.shader (Web).
/// Chrome consumers are siblings of [KyantBackdropSource], never its children.
/// Captures only the configured region, without Dart-side pixel readback.
/// Snapshot implementation and readback costs depend on the Flutter renderer.
class KyantBackdropController extends ChangeNotifier implements KyantBackdrop {
  KyantBackdropController({
    this.frameInterval = Duration.zero,
    this.pixelRatio,
    this.captureHeight,
    this.captureBottomHeight,
    this.captureOnNative = false,
    this.maxCaptureWidth,
  });
  final Duration frameInterval;

  /// Null captures at the source view's physical pixel density.
  final double? pixelRatio;
  double? captureHeight;
  final double? captureBottomHeight;
  bool captureOnNative;

  /// Optional explicit quality limit. Full device density is the default.
  final double? maxCaptureWidth;
  ui.Image? _image;
  Rect _rect = Rect.zero;
  @override
  ui.Image? get image => _image;
  @override
  Rect get rect => _rect;
  Matrix4 _imageToGlobal = Matrix4.identity();
  @override
  Matrix4 get imageToGlobal => Matrix4.copy(_imageToGlobal);
  @override
  int revision = 0;

  bool _disposed = false, _capturing = false, _scheduled = false;
  bool _dirtyDuringCapture = false;
  GlobalKey? _boundary;
  Timer? _timer;
  int _requestEpoch = 0;
  final _clock = Stopwatch()..start();
  int _lastCapture = -120;

  void request(GlobalKey boundary) {
    if ((!kIsWeb && !captureOnNative) || _disposed) {
      return;
    }
    _boundary = boundary;
    if (_capturing) {
      _dirtyDuringCapture = true;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    final epoch = _requestEpoch;
    final delay = math.max(
      0,
      frameInterval.inMilliseconds -
          (_clock.elapsedMilliseconds - _lastCapture),
    );
    void schedule() {
      _timer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (epoch == _requestEpoch) _capture();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    // A zero-delay Timer would miss this frame's post-paint callback and
    // unnecessarily reduce a 60Hz producer to updates every other frame.
    if (delay == 0) {
      schedule();
    } else {
      _timer = Timer(Duration(milliseconds: delay), schedule);
    }
  }

  void _detach(GlobalKey boundary) {
    if (!identical(_boundary, boundary)) return;
    _boundary = null;
    _requestEpoch++;
    _timer?.cancel();
    _timer = null;
    _scheduled = false;
    _dirtyDuringCapture = false;
  }

  Future<void> _capture() async {
    _scheduled = false;
    if ((!kIsWeb && !captureOnNative) || _disposed || _capturing) return;
    final boundary = _boundary?.currentContext?.findRenderObject();
    if (boundary is! _BackdropBoundary ||
        !boundary.attached ||
        !boundary.canCapture) {
      return;
    }
    if (boundary.size.isEmpty) {
      final previous = _image;
      _image = null;
      _rect = Rect.zero;
      _imageToGlobal = Matrix4.identity();
      if (previous != null) {
        revision++;
        notifyListeners();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previous.dispose();
          KyantDiagnostics.imageDisposed();
        });
      }
      return;
    }
    _capturing = true;
    _lastCapture = _clock.elapsedMilliseconds;
    try {
      final height = math.min(
        captureBottomHeight ?? captureHeight ?? boundary.size.height,
        boundary.size.height,
      );
      final top = captureBottomHeight == null
          ? 0.0
          : boundary.size.height - height;
      final region = Rect.fromLTWH(0, top, boundary.size.width, height);
      final context = _boundary!.currentContext!;
      final requestedRatio =
          pixelRatio ??
          MediaQuery.maybeDevicePixelRatioOf(context) ??
          View.of(context).devicePixelRatio;
      final ratio = maxCaptureWidth == null
          ? requestedRatio
          : math.min(requestedRatio, maxCaptureWidth! / boundary.size.width);
      final globalRect = MatrixUtils.transformRect(
        boundary.getTransformTo(null),
        region,
      );
      final next = boundary.capture(region, ratio);
      KyantDiagnostics.imageCreated(next.width, next.height);
      if (_disposed) {
        next.dispose();
        KyantDiagnostics.imageDisposed();
        return;
      }
      final previous = _image;
      _image = next;
      _rect = globalRect;
      _imageToGlobal = boundary.getTransformTo(null)
        ..translateByDouble(region.left, region.top, 0, 1)
        ..scaleByDouble(1 / ratio, 1 / ratio, 1, 1);
      revision++;
      notifyListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
        if (previous != null) KyantDiagnostics.imageDisposed();
      });
    } finally {
      _capturing = false;
      if (_dirtyDuringCapture && !_disposed && _boundary != null) {
        _dirtyDuringCapture = false;
        request(_boundary!);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestEpoch++;
    _boundary = null;
    _timer?.cancel();
    _image?.dispose();
    if (_image != null) KyantDiagnostics.imageDisposed();
    _image = null;
    super.dispose();
  }
}

class KyantBackdropSource extends StatefulWidget {
  const KyantBackdropSource({
    super.key,
    required this.controller,
    required this.child,
    this.repaint,
  });
  final KyantBackdropController controller;
  final Widget child;

  /// Pass animations/scroll controllers that change retained descendant layers.
  /// Listeners invalidate captures without rebuilding the source widget.
  final Listenable? repaint;

  /// Used by consumers to reject sampling a source which contains themselves.
  static List<KyantBackdropController> producersOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ProducerDomain>()?.sources ??
      const [];
  @override
  State<KyantBackdropSource> createState() => _KyantBackdropSourceState();
}

class _KyantBackdropSourceState extends State<KyantBackdropSource> {
  final _boundary = GlobalKey();
  void _invalidate() => widget.controller.request(_boundary);
  @override
  void initState() {
    super.initState();
    widget.repaint?.addListener(_invalidate);
  }

  @override
  void didUpdateWidget(KyantBackdropSource old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._detach(_boundary);
    }
    if (old.repaint != widget.repaint) {
      old.repaint?.removeListener(_invalidate);
      widget.repaint?.addListener(_invalidate);
    }
    _invalidate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invalidate();
  }

  @override
  void dispose() {
    widget.repaint?.removeListener(_invalidate);
    widget.controller._detach(_boundary);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // View.of does not subscribe to metric changes. Retained content still
    // needs a new physical-density snapshot when its MediaQuery DPR changes.
    MediaQuery.maybeDevicePixelRatioOf(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        widget.controller.request(_boundary);
        return false;
      },
      child: _ProducerDomain(
        sources: [
          ...KyantBackdropSource.producersOf(context),
          widget.controller,
        ],
        child: _BackdropRepaintBoundary(
          key: _boundary,
          onCapture: _invalidate,
          child: widget.child,
        ),
      ),
    );
  }
}

class _ProducerDomain extends InheritedWidget {
  const _ProducerDomain({required this.sources, required super.child});
  final List<KyantBackdropController> sources;
  @override
  bool updateShouldNotify(_ProducerDomain old) =>
      !listEquals(sources, old.sources);
}

/// The boundary owns its layer and exposes a cropped image snapshot without
/// calling protected RenderObject members from a controller.
class _BackdropRepaintBoundary extends SingleChildRenderObjectWidget {
  const _BackdropRepaintBoundary({
    super.key,
    required this.onCapture,
    required super.child,
  });
  final VoidCallback onCapture;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BackdropBoundary(onCapture);
  @override
  void updateRenderObject(
    BuildContext context,
    _BackdropBoundary renderObject,
  ) {
    renderObject.onCapture = onCapture;
  }
}

class _BackdropBoundary extends RenderRepaintBoundary {
  _BackdropBoundary(this.onCapture);
  VoidCallback onCapture;
  VoidCallback? _removeCompositionCallback;
  List<double>? _lastTransform;

  // A source snapshot assembles a scene too, including nested source layers.
  // None of those callbacks may enqueue another capture of that same scene.
  static int _snapshotDepth = 0;

  bool get canCapture => hasSize && layer is OffsetLayer && layer!.attached;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _lastTransform = List.of(getTransformTo(null).storage);
    onCapture();
  }

  void _didComposite(Layer observedLayer) {
    if (_snapshotDepth != 0 || !attached || !observedLayer.attached) return;
    final transform = getTransformTo(null).storage;
    if (listEquals(_lastTransform, transform)) return;
    _lastTransform = List.of(transform);
    onCapture();
  }

  @override
  OffsetLayer updateCompositedLayer({
    required covariant OffsetLayer? oldLayer,
  }) {
    if (oldLayer != null) return oldLayer;
    final next = OffsetLayer();
    _removeCompositionCallback = next.addCompositionCallback(_didComposite);
    return next;
  }

  ui.Image capture(Rect region, double pixelRatio) {
    _snapshotDepth++;
    try {
      return (layer! as OffsetLayer).toImageSync(
        region,
        pixelRatio: pixelRatio,
      );
    } finally {
      _snapshotDepth--;
    }
  }

  @override
  void dispose() {
    _removeCompositionCallback?.call();
    _removeCompositionCallback = null;
    super.dispose();
  }
}

/// Place only the consumers in this scope, beside their backdrop source.
class KyantBackdropScope extends InheritedWidget {
  const KyantBackdropScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final KyantBackdrop controller;
  static KyantBackdrop? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KyantBackdropScope>()
      ?.controller;
  @override
  bool updateShouldNotify(KyantBackdropScope oldWidget) =>
      oldWidget.controller != controller;
}
