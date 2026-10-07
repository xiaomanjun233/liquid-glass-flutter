import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Repaints a sampled material after a retained ancestor changes its transform.
/// The child should paint in this render object's repaint boundary, rather than
/// introduce another boundary of its own.
class KyantTransformObserver extends SingleChildRenderObjectWidget {
  const KyantTransformObserver({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _TransformObserver();
}

class _TransformObserver extends RenderProxyBox {
  VoidCallback? _removeCompositionCallback;
  List<double>? _paintTransform;
  bool _scheduled = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintTransform = List.of(getTransformTo(null).storage);
    _removeCompositionCallback?.call();
    _removeCompositionCallback = context.addCompositionCallback(_didComposite);
    super.paint(context, offset);
  }

  void _didComposite(Layer layer) {
    if (!attached || !layer.attached || _scheduled || !_transformChanged) {
      return;
    }
    _scheduled = true;
    // Composition callbacks are read-only. Invalidate after scene assembly,
    // and only if the next ordinary paint has not already caught the change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (attached && _transformChanged) markNeedsPaint();
    });
  }

  bool get _transformChanged =>
      !listEquals(_paintTransform, getTransformTo(null).storage);

  @override
  void dispose() {
    _removeCompositionCallback?.call();
    _removeCompositionCallback = null;
    super.dispose();
  }
}
