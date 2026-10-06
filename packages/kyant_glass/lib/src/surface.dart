import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'backdrop.dart';
import 'combined_backdrop.dart';
import 'decorations.dart';
import 'diagnostics.dart';
import 'material.dart';
import 'shader_backdrop.dart';
import 'shader_uniforms.dart';
import 'programs.dart';

final _lensProgram = loadKyantProgram('kyant_lens.frag');

class KyantGlass extends StatefulWidget {
  const KyantGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.borderRadius,
    this.blur = 2,
    this.refractionHeight = 16,
    this.refractionAmount = 10,
    this.dispersion = .35,
    this.depth = false,
    this.tint = const Color(0xBFFFFFFF),
    this.highlight = .45,
    this.highlightStyle,
    this.shadow,
    this.innerShadow,
    this.backdrop,
    this.effects,
    this.pipeline,
    this.backdropGroupKey,
    this.textureOrigin = Offset.zero,
  });
  final Widget child;
  final double radius,
      blur,
      refractionHeight,
      refractionAmount,
      dispersion,
      highlight;
  final BorderRadiusGeometry? borderRadius;
  final bool depth;
  final Color tint;
  final KyantHighlight? highlightStyle;
  final KyantShadow? shadow, innerShadow;
  final KyantBackdrop? backdrop;
  final List<KyantEffect>? effects;
  final KyantPipeline? pipeline;
  final BackdropKey? backdropGroupKey;

  /// Origin of a known native render target, in global physical pixels.
  /// Arbitrary ancestor saveLayers need an explicit source; do not guess it.
  final Offset textureOrigin;
  static bool get supportsLiveRefraction =>
      ui.ImageFilter.isShaderFilterSupported;
  static Future<void> precache() async {
    await _lensProgram;
    await highlightProgram;
  }

  @override
  State<KyantGlass> createState() => _KyantGlassState();
}

class _KyantGlassState extends State<KyantGlass> {
  final _shaders = <ui.FragmentShader>[];
  ui.FragmentProgram? _program;
  ui.FragmentShader? _highlightShader;
  final _cache = _ExplicitCache();
  List<KyantEffect> get _effects =>
      widget.effects ??
      [
        KyantBlur(widget.blur),
        KyantLens(
          height: widget.refractionHeight,
          amount: widget.refractionAmount,
          dispersion: widget.dispersion,
          depth: widget.depth,
        ),
      ];
  @override
  void initState() {
    super.initState();
    _program = cachedKyantProgram('kyant_lens.frag');
    if (_program != null) {
      _syncShaders();
    } else {
      _lensProgram.then((program) {
        if (!mounted) return;
        setState(() {
          _program = program;
          _syncShaders();
          _cache.clear();
        });
      }, onError: _shaderError);
    }
    final highlight = cachedKyantProgram('kyant_highlight.frag');
    if (highlight != null) {
      _highlightShader = highlight.fragmentShader();
    } else {
      highlightProgram.then((program) {
        if (mounted) {
          setState(() => _highlightShader = program.fragmentShader());
        }
      }, onError: _shaderError);
    }
  }

  void _shaderError(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'kyant_glass'),
  );
  void _syncShaders() {
    final count = _effects.whereType<KyantLens>().length;
    if (_program == null) return;
    while (_shaders.length < count) {
      _shaders.add(_program!.fragmentShader());
    }
    while (_shaders.length > count) {
      _shaders.removeLast().dispose();
    }
  }

  @override
  void didUpdateWidget(KyantGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncShaders();
    _cache.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cache.clear();
  }

  @override
  void dispose() {
    _cache.clear();
    for (final shader in _shaders) {
      shader.dispose();
    }
    _highlightShader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (KyantRenderSettings.settingsOf(context)?.debugDisableGlass ?? false) {
      return ClipRRect(
        borderRadius:
            widget.borderRadius ?? BorderRadius.circular(widget.radius),
        child: ColoredBox(color: widget.tint, child: widget.child),
      );
    }
    final source = widget.backdrop ?? KyantBackdropScope.maybeOf(context);
    if (source != null &&
        KyantBackdropSource.producersOf(context)
            .any((producer) => containsKyantSource(source, producer))) {
      throw FlutterError(
        'A KyantGlass consumer cannot be inside its own backdrop source. '
        'Place source and consumer in sibling branches.',
      );
    }
    final mode = widget.pipeline ?? KyantRenderSettings.of(context);
    final corners =
        (widget.borderRadius ?? BorderRadius.circular(widget.radius)).resolve(
          Directionality.of(context),
        );
    final effects = _effects;
    final density = MediaQuery.devicePixelRatioOf(context);
    final highlight =
        widget.highlightStyle ??
        KyantHighlight(
          color: const Color(0xFFFFFFFF).withValues(alpha: widget.highlight),
          width: .575,
          blur: 0,
          blendMode: BlendMode.srcOver,
          floor: .2,
        );
    Widget material;
    if (source is KyantEmptyBackdrop) {
      material = ColoredBox(color: widget.tint, child: widget.child);
    } else if (source != null &&
        (mode == KyantPipeline.explicit ||
            source is! KyantBackdropController ||
            !KyantGlass.supportsLiveRefraction)) {
      material = CustomPaint(
        painter: _ExplicitPainter(
          source: source,
          cache: _cache,
          effects: effects,
          shaders: _shaders,
          corners: corners,
          density: density,
          transform: () =>
              (context.findRenderObject()! as RenderBox).getTransformTo(null),
        ),
        child: ColoredBox(color: widget.tint, child: widget.child),
      );
    } else {
      ui.ImageFilter? compose() {
        ui.ImageFilter? result;
        var index = 0;
        for (final effect in effects) {
          final filter = effect is KyantLens
              ? (index < _shaders.length && KyantGlass.supportsLiveRefraction
                    ? ui.ImageFilter.shader(_shaders[index++])
                    : null)
              : kyantBasicFilter(effect);
          result = kyantCompose(result, filter);
        }
        return result;
      }

      final filters = <Widget>[];
      if (_shaders.isNotEmpty && KyantGlass.supportsLiveRefraction) {
        void bind(Matrix4 transform, Size size) {
          KyantDiagnostics.filterPaints++;
          final matrix = Matrix4.identity()
            ..translateByDouble(
              -widget.textureOrigin.dx,
              -widget.textureOrigin.dy,
              0,
              1,
            )
            ..scaleByDouble(density, density, 1, 1)
            ..multiply(transform);
          if (matrix.determinant().abs() < 1e-10) return;
          var i = 0;
          for (final lens in effects.whereType<KyantLens>()) {
            bindKyantLens(
              _shaders[i++],
              size: size,
              corners: corners,
              lens: lens,
              localToTexture: matrix,
              sourceSize: Size.zero,
              filterInput: true,
            );
          }
        }

        if (mode == KyantPipeline.legacy) {
          var i = 0;
          for (final effect in effects) {
            if (effect is KyantLens) {
              final shader = _shaders[i++];
              filters.add(
                Positioned.fill(
                  child: KyantShaderBackdrop(
                    shader: shader,
                    configure: (_, _) {},
                    configureGeometry: bind,
                  ),
                ),
              );
            } else {
              final filter = kyantBasicFilter(effect);
              if (filter != null) {
                filters.add(
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: filter,
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              }
            }
          }
        } else {
          filters.add(
            Positioned.fill(
              child: KyantShaderBackdrop(
                shader: _shaders.first,
                configure: (_, _) {},
                configureGeometry: bind,
                filterBuilder: () => compose()!,
                backdropKey: widget.backdropGroupKey,
              ),
            ),
          );
        }
      } else {
        final filter = compose();
        if (filter != null) {
          filters.add(
            Positioned.fill(
              child: BackdropFilter(
                filter: filter,
                backdropGroupKey: widget.backdropGroupKey,
                child: const SizedBox.expand(),
              ),
            ),
          );
        }
      }
      material = Stack(
        fit: StackFit.passthrough,
        children: [
          ...filters,
          ColoredBox(color: widget.tint, child: widget.child),
        ],
      );
    }
    return CustomPaint(
      painter: KyantDecorationPainter(corners: corners, shadow: widget.shadow),
      child: ClipRRect(
        borderRadius: corners,
        child: CustomPaint(
          foregroundPainter: KyantDecorationPainter(
            corners: corners,
            highlight: highlight,
            shader: _highlightShader,
            innerShadow: widget.innerShadow,
            density: density,
          ),
          child: material,
        ),
      ),
    );
  }
}

void _release(ui.Image image) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    image.dispose();
    KyantDiagnostics.imageDisposed();
  });
}

class _ExplicitCache {
  ui.Image? image;
  int revision = -1;
  List<double>? transform;
  Size size = Size.zero;
  double padding = 0;
  void clear() {
    if (image != null) _release(image!);
    image = null;
    revision = -1;
  }
}

class _ExplicitPainter extends CustomPainter {
  _ExplicitPainter({
    required this.source,
    required this.cache,
    required this.effects,
    required this.shaders,
    required this.corners,
    required this.density,
    required this.transform,
  }) : super(repaint: source);
  final KyantBackdrop source;
  final _ExplicitCache cache;
  final List<KyantEffect> effects;
  final List<ui.FragmentShader> shaders;
  final BorderRadius corners;
  final double density;
  final Matrix4 Function() transform;
  @override
  void paint(Canvas canvas, Size size) {
    final input = source.image;
    if (input == null || size.isEmpty) return;
    final target = transform();
    if (target.determinant().abs() < 1e-10) return;
    final mapping = Matrix4.inverted(target)..multiply(source.imageToGlobal);
    if (cache.image == null ||
        cache.revision != source.revision ||
        cache.size != size ||
        !listEquals(cache.transform, mapping.storage)) {
      cache.clear();
      var padding = 0.0;
      for (final effect in effects) {
        if (effect is KyantBlur) padding += 3 * effect.sigma;
        if (effect is KyantLens) {
          padding += effect.amount * (1 + effect.dispersion);
        }
      }
      padding = (padding * density).ceil() / density;
      final width = math.max(1, ((size.width + 2 * padding) * density).ceil());
      final height = math.max(
        1,
        ((size.height + 2 * padding) * density).ceil(),
      );
      ui.Image record(void Function(Canvas) paint) {
        final recorder = ui.PictureRecorder();
        paint(Canvas(recorder));
        final picture = recorder.endRecording();
        final result = picture.toImageSync(width, height);
        picture.dispose();
        KyantDiagnostics.imageCreated(width, height);
        return result;
      }

      var image = record((c) {
        c.scale(density);
        c.translate(padding, padding);
        c.transform(mapping.storage);
        c.drawImage(
          input,
          Offset.zero,
          Paint()..filterQuality = FilterQuality.low,
        );
      });
      var lensIndex = 0;
      for (final effect in effects) {
        final previous = image;
        if (effect is KyantLens) {
          if (lensIndex >= shaders.length) continue;
          final shader = shaders[lensIndex++];
          final sample = Matrix4.identity()
            ..translateByDouble(padding * density, padding * density, 0, 1)
            ..scaleByDouble(density, density, 1, 1);
          bindKyantLens(
            shader,
            size: size,
            corners: corners,
            lens: effect,
            localToTexture: sample,
            sourceSize: Size(width.toDouble(), height.toDouble()),
            filterInput: false,
          );
          shader.setImageSampler(0, previous);
          image = record((c) {
            c.scale(density);
            c.translate(padding, padding);
            c.drawRect(
              Rect.fromLTWH(
                -padding,
                -padding,
                width / density,
                height / density,
              ),
              Paint()..shader = shader,
            );
          });
        } else {
          final filter = kyantBasicFilter(effect, scale: density);
          if (filter == null) continue;
          image = record(
            (c) => c.drawImage(
              previous,
              Offset.zero,
              Paint()..imageFilter = filter,
            ),
          );
        }
        _release(previous);
      }
      cache.image = image;
      cache.padding = padding;
      cache.size = size;
      cache.revision = source.revision;
      cache.transform = List.of(mapping.storage);
    }
    KyantDiagnostics.explicitPaints++;
    final pad = cache.padding;
    canvas.drawImageRect(
      cache.image!,
      Rect.fromLTWH(
        pad * density,
        pad * density,
        size.width * density,
        size.height * density,
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_ExplicitPainter old) => true;
}

/// Caller owns [image]. Explicit image rendering also works on Web.
class KyantGlassImage extends StatefulWidget {
  const KyantGlassImage({
    super.key,
    required this.image,
    this.radius = 28,
    this.refractionHeight = 20,
    this.refractionAmount = 16,
    this.dispersion = .5,
    this.depth = false,
    this.highlight = .45,
    this.child = const SizedBox.expand(),
  });
  final ui.Image image;
  final double radius,
      refractionHeight,
      refractionAmount,
      dispersion,
      highlight;
  final bool depth;
  final Widget child;
  @override
  State<KyantGlassImage> createState() => _KyantGlassImageState();
}

class _KyantGlassImageState extends State<KyantGlassImage> {
  ui.FragmentShader? _shader;
  ui.FragmentShader? _highlightShader;
  @override
  void initState() {
    super.initState();
    _lensProgram.then((p) {
      if (mounted) setState(() => _shader = p.fragmentShader());
    }, onError: _onError);
    highlightProgram.then((p) {
      if (mounted) setState(() => _highlightShader = p.fragmentShader());
    }, onError: _onError);
  }

  void _onError(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'kyant_glass'),
  );

  @override
  void dispose() {
    _shader?.dispose();
    _highlightShader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    child: CustomPaint(
      painter: _ImagePainter(widget, _shader),
      foregroundPainter: KyantDecorationPainter(
        corners: BorderRadius.circular(widget.radius),
        shader: _highlightShader,
        density: MediaQuery.devicePixelRatioOf(context),
        highlight: KyantHighlight(
          color: const Color(0xFFFFFFFF).withValues(alpha: widget.highlight),
          width: .575,
          blur: 0,
          floor: .2,
          blendMode: BlendMode.srcOver,
        ),
      ),
      child: widget.child,
    ),
  );
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.widget, this.shader);
  final KyantGlassImage widget;
  final ui.FragmentShader? shader;
  @override
  void paint(Canvas canvas, Size size) {
    final s = shader;
    if (s == null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: widget.image,
        fit: BoxFit.cover,
      );
      return;
    }
    final scale = math.max(
      size.width / widget.image.width,
      size.height / widget.image.height,
    );
    final mapping = Matrix4.identity()
      ..translateByDouble(
        (widget.image.width - size.width / scale) / 2,
        (widget.image.height - size.height / scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(1 / scale, 1 / scale, 1, 1);
    bindKyantLens(
      s,
      size: size,
      corners: BorderRadius.circular(widget.radius),
      lens: KyantLens(
        height: widget.refractionHeight,
        amount: widget.refractionAmount,
        dispersion: widget.dispersion,
        depth: widget.depth,
      ),
      localToTexture: mapping,
      sourceSize: Size(
        widget.image.width.toDouble(),
        widget.image.height.toDouble(),
      ),
      filterInput: false,
    );
    s.setImageSampler(0, widget.image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_ImagePainter old) =>
      widget != old.widget || shader != old.shader;
}
