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
/// Captures only the configured region; consumers never read CPU pixels.
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
    final delay = math.max(
      0,
      frameInterval.inMilliseconds -
          (_clock.elapsedMilliseconds - _lastCapture),
    );
    void schedule() {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
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

  Future<void> _capture() async {
    _scheduled = false;
    if (_disposed || _capturing) return;
    final boundary = _boundary?.currentContext?.findRenderObject();
    if (boundary is! _BackdropBoundary ||
        !boundary.attached ||
        boundary.size.isEmpty) {
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
      final requestedRatio =
          pixelRatio ?? View.of(_boundary!.currentContext!).devicePixelRatio;
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
    if (old.repaint != widget.repaint) {
      old.repaint?.removeListener(_invalidate);
      widget.repaint?.addListener(_invalidate);
    }
    _invalidate();
  }

  @override
  void dispose() {
    widget.repaint?.removeListener(_invalidate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
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
            child: _PaintObserver(
              onPaint: () => widget.controller.request(_boundary),
              child: widget.child,
            ),
          ),
        ),
      );
}

class _ProducerDomain extends InheritedWidget {
  const _ProducerDomain({required this.sources, required super.child});
  final List<KyantBackdropController> sources;
  @override
  bool updateShouldNotify(_ProducerDomain old) =>
      !listEquals(sources, old.sources);
}

/// The boundary owns its layer and exposes a cropped GPU snapshot without
/// calling protected RenderObject members from a controller.
class _BackdropRepaintBoundary extends SingleChildRenderObjectWidget {
  const _BackdropRepaintBoundary({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _BackdropBoundary();
}

class _BackdropBoundary extends RenderRepaintBoundary {
  ui.Image capture(Rect region, double pixelRatio) =>
      (layer! as OffsetLayer).toImageSync(region, pixelRatio: pixelRatio);
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

class _PaintObserver extends SingleChildRenderObjectWidget {
  const _PaintObserver({required this.onPaint, required super.child});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ObservePaint(onPaint);
  @override
  void updateRenderObject(BuildContext context, _ObservePaint renderObject) =>
      renderObject.onPaint = onPaint;
}

class _ObservePaint extends RenderProxyBox {
  _ObservePaint(this.onPaint);
  VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
