import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Configure from the painted global bounds, before serializing the filter.
/// The backdrop texture may be larger than these bounds.
class KyantShaderBackdrop extends SingleChildRenderObjectWidget {
  const KyantShaderBackdrop({
    super.key,
    required this.shader,
    required this.configure,
    this.configureGeometry,
    this.filterBuilder,
    this.backdropKey,
    super.child = const SizedBox.expand(),
  });
  final ui.FragmentShader shader;
  final void Function(ui.FragmentShader shader, Rect globalBounds) configure;
  final void Function(Matrix4 transform, Size size)? configureGeometry;
  final ui.ImageFilter Function()? filterBuilder;
  final BackdropKey? backdropKey;

  @override
  RenderObject createRenderObject(BuildContext context) => _ShaderBackdrop(
    shader,
    configure,
    configureGeometry,
    filterBuilder,
    backdropKey,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    final target = renderObject as _ShaderBackdrop;
    target
      ..shader = shader
      ..configure = configure
      ..configureGeometry = configureGeometry
      ..filterBuilder = filterBuilder
      ..backdropKey = backdropKey
      ..markNeedsPaint();
  }
}

class _ShaderBackdrop extends RenderProxyBox {
  _ShaderBackdrop(
    this.shader,
    this.configure,
    this.configureGeometry,
    this.filterBuilder,
    this.backdropKey,
  );
  ui.FragmentShader shader;
  void Function(ui.FragmentShader, Rect) configure;
  void Function(Matrix4, Size)? configureGeometry;
  ui.ImageFilter Function()? filterBuilder;
  BackdropKey? backdropKey;
  final _filterLayer = LayerHandle<_GeometryBackdropLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final layer = _filterLayer.layer ??= _GeometryBackdropLayer(() {
      final transform = getTransformTo(null);
      configure(
        shader,
        MatrixUtils.transformRect(transform, Offset.zero & size),
      );
      configureGeometry?.call(transform, size);
      return filterBuilder?.call() ?? ui.ImageFilter.shader(shader);
    });
    layer.backdropKey = backdropKey;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _filterLayer.layer = null;
    super.dispose();
  }
}

/// Configure when the scene is assembled, including retained child layers
/// under a moving TransformLayer. Does not schedule frames while idle.
class _GeometryBackdropLayer extends BackdropFilterLayer {
  _GeometryBackdropLayer(this.configureFilter);
  final ui.ImageFilter Function() configureFilter;
  @override
  bool get alwaysNeedsAddToScene => true;
  @override
  void addToScene(ui.SceneBuilder builder) {
    final next = configureFilter();
    if (!identical(filter, next)) filter = next;
    super.addToScene(builder);
  }
}
