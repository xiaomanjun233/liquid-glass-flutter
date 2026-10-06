import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'backdrop.dart';
import 'diagnostics.dart';

bool containsKyantSource(KyantBackdrop root, KyantBackdrop source) {
  if (identical(root, source)) return true;
  if (root is KyantCombinedBackdrop) {
    return root.sources.any((s) => containsKyantSource(s, source));
  }
  if (root is KyantTransformedBackdrop) {
    return containsKyantSource(root.source, source);
  }
  return false;
}

class KyantEmptyBackdrop extends ChangeNotifier implements KyantBackdrop {
  @override
  ui.Image? get image => null;
  @override
  Rect get rect => Rect.zero;
  @override
  Matrix4 get imageToGlobal => Matrix4.identity();
  @override
  int get revision => 0;
}

/// Ordered source-over composition. Owns only the composed image, never inputs.
class KyantCombinedBackdrop extends ChangeNotifier implements KyantBackdrop {
  KyantCombinedBackdrop(List<KyantBackdrop> sources, {this.pixelRatio = 1})
    : sources = List.unmodifiable(sources) {
    for (final source in this.sources) {
      source.addListener(_changed);
    }
  }
  final List<KyantBackdrop> sources;
  final double pixelRatio;
  ui.Image? _image;
  bool _dirty = true;
  Rect _rect = Rect.zero;
  @override
  int revision = 0;
  void _changed() {
    _dirty = true;
    revision++;
    notifyListeners();
  }

  void _resolve() {
    if (!_dirty) return;
    _dirty = false;
    Rect bounds = Rect.zero;
    final frames = <(ui.Image, Matrix4)>[];
    for (final source in sources) {
      final frame = source.image;
      if (frame == null) continue;
      bounds = bounds.isEmpty
          ? source.rect
          : bounds.expandToInclude(source.rect);
      frames.add((frame, source.imageToGlobal));
    }
    final previous = _image;
    _image = null;
    _rect = bounds;
    if (!bounds.isEmpty) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(pixelRatio)
        ..translate(-bounds.left, -bounds.top);
      for (final frame in frames) {
        canvas.save();
        canvas.transform(frame.$2.storage);
        canvas.drawImage(frame.$1, Offset.zero, Paint());
        canvas.restore();
      }
      final picture = recorder.endRecording();
      _image = picture.toImageSync(
        math.max(1, (bounds.width * pixelRatio).ceil()),
        math.max(1, (bounds.height * pixelRatio).ceil()),
      );
      picture.dispose();
      KyantDiagnostics.imageCreated(_image!.width, _image!.height);
    }
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
        KyantDiagnostics.imageDisposed();
      });
    }
  }

  @override
  ui.Image? get image {
    _resolve();
    return _image;
  }

  @override
  Rect get rect {
    _resolve();
    return _rect;
  }

  @override
  Matrix4 get imageToGlobal {
    _resolve();
    return Matrix4.identity()
      ..translateByDouble(_rect.left, _rect.top, 0, 1)
      ..scaleByDouble(1 / pixelRatio, 1 / pixelRatio, 1, 1);
  }

  @override
  void dispose() {
    for (final source in sources) {
      source.removeListener(_changed);
    }
    if (_image != null) {
      _image!.dispose();
      KyantDiagnostics.imageDisposed();
    }
    super.dispose();
  }
}

/// A caller-controlled affine transform of a source, without a new GPU image.
class KyantTransformedBackdrop extends ChangeNotifier implements KyantBackdrop {
  KyantTransformedBackdrop(this.source, Matrix4 transform)
    : _transform = Matrix4.copy(transform),
      _provider = null,
      _repaint = null {
    source.addListener(_changed);
  }
  KyantTransformedBackdrop.dynamic(
    this.source, {
    required Matrix4 Function() transform,
    required Listenable repaint,
  }) : _transform = Matrix4.identity(),
       _provider = transform,
       _repaint = repaint {
    source.addListener(_changed);
    repaint.addListener(_changed);
  }
  final KyantBackdrop source;
  final Matrix4 Function()? _provider;
  final Listenable? _repaint;
  Matrix4 _transform;
  Matrix4 get _current => _provider?.call() ?? _transform;
  @override
  int revision = 0;
  set transform(Matrix4 value) {
    if (_transform == value) return;
    _transform = Matrix4.copy(value);
    _changed();
  }

  void _changed() {
    revision++;
    notifyListeners();
  }

  @override
  ui.Image? get image => source.image;
  @override
  Matrix4 get imageToGlobal =>
      Matrix4.copy(_current)..multiply(source.imageToGlobal);
  @override
  Rect get rect => MatrixUtils.transformRect(_current, source.rect);
  @override
  void dispose() {
    _repaint?.removeListener(_changed);
    source.removeListener(_changed);
    super.dispose();
  }
}

class KyantCanvasBackdrop extends StatelessWidget {
  const KyantCanvasBackdrop({
    super.key,
    required this.controller,
    required this.painter,
    required this.size,
  });
  final KyantBackdropController controller;
  final CustomPainter painter;
  final Size size;
  @override
  Widget build(BuildContext context) => KyantBackdropSource(
    controller: controller,
    repaint: painter,
    child: CustomPaint(size: size, painter: painter),
  );
}
