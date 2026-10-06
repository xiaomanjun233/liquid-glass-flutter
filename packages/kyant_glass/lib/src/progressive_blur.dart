import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'backdrop.dart';
import 'diagnostics.dart';
import 'programs.dart';
import 'material.dart';
import 'shader_backdrop.dart';

enum KyantProgressiveMode { separate, shared, interpolated, layered }

ui.FragmentProgram? _layeredProgram;
Future<ui.FragmentProgram>? _layeredLoading;
Future<ui.FragmentProgram> _loadLayeredProgram() =>
    _layeredLoading ??= loadKyantProgram('kyant_progressive_mask.frag')
        .then((program) {
          _layeredProgram = program;
          return program;
        });

/// Flutter progressive-blur extension, not part of Kyant 2.0.0.
/// [shared] keeps the original 64 disjoint Gaussian bands and sigma profile.
/// [interpolated] blends four Gaussian levels from an explicit source; it is
/// an experimental approximation requiring visual acceptance and latency tests.
/// [layered] uses [layers] live Gaussian increments with smooth alpha masks.
/// Fewer layers reduce filter groups, with a coarser intermediate distribution.
/// One layer is a fixed Gaussian faded over the sharp background, not a
/// continuously varying Gaussian radius. The independent default remains eight.
class KyantProgressiveBlur extends StatefulWidget {
  const KyantProgressiveBlur({
    super.key,
    required this.sigma,
    this.mode = KyantProgressiveMode.shared,
    this.backdrop,
    this.bands = 64,
    this.layers = 8,
  }) : assert(sigma >= 0),
       assert(bands > 0),
       assert(layers >= 1 && layers <= 32),
       assert(mode != KyantProgressiveMode.interpolated || backdrop != null);
  final double sigma;
  final int bands;

  /// Layered mode only. 4 is a lighter approximation, 8 the default;
  /// 1 is a single fixed-blur/alpha-mask variant. No background snapshots.
  final int layers;
  final KyantProgressiveMode mode;
  final KyantBackdrop? backdrop;
  static Future<void> precache() async {
    if (ui.ImageFilter.isShaderFilterSupported) await _loadLayeredProgram();
  }

  @override
  State<KyantProgressiveBlur> createState() => _ProgressiveState();
}

class _ProgressiveState extends State<KyantProgressiveBlur> {
  final _key = BackdropKey();
  final _cache = _BlurCache();
  ui.FragmentShader? _shader;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (_loading || widget.mode != KyantProgressiveMode.interpolated) return;
    _loading = true;
    loadKyantProgram('kyant_progressive.frag').then(
      (p) {
        if (mounted) setState(() => _shader = p.fragmentShader());
      },
      onError: (Object e, StackTrace s) => FlutterError.reportError(
        FlutterErrorDetails(exception: e, stack: s, library: 'kyant_glass'),
      ),
    );
  }

  @override
  void didUpdateWidget(KyantProgressiveBlur old) {
    super.didUpdateWidget(old);
    _load();
    if (old.sigma != widget.sigma || old.backdrop != widget.backdrop) {
      _cache.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cache.clear();
  }

  @override
  void dispose() {
    _cache.clear();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final override = KyantRenderSettings.settingsOf(context)
        ?.debugProgressiveBands;
    var bands = override ?? widget.bands;
    if (widget.sigma == 0 || bands == 0) return const SizedBox.expand();
    final layered = override == null
        ? widget.mode == KyantProgressiveMode.layered
        : override < 0;
    if (layered && ui.ImageFilter.isShaderFilterSupported) {
      return _LayeredProgressive(
        sigma: widget.sigma,
        levels: bands < 0 ? -bands : widget.layers,
      );
    }
    // The diagnostic layered override must not remove blur on Skia/Web.
    if (bands < 0) bands = widget.bands;
    if (widget.mode == KyantProgressiveMode.interpolated && _shader != null) {
      return ClipRect(
        child: CustomPaint(
          painter: _InterpolatedBlur(
            source: widget.backdrop!,
            shader: _shader!,
            sigma: widget.sigma,
            cache: _cache,
            density: MediaQuery.devicePixelRatioOf(context),
            transform: () =>
                (context.findRenderObject()! as RenderBox).getTransformTo(null),
          ),
          child: const SizedBox.expand(),
        ),
      );
    }
    return _gaussianBands(
      widget.sigma,
      bands,
      widget.mode == KyantProgressiveMode.separate ? null : _key,
    );
  }
}

Widget _gaussianBands(double sigma, int bands, BackdropKey? groupKey) =>
    LayoutBuilder(
      builder: (context, c) => ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < bands; i++)
              Positioned(
                left: 0,
                right: 0,
                top: c.maxHeight * i / bands,
                height: c.maxHeight / bands,
                child: ClipRect(
                  child: BackdropFilter(
                    backdropGroupKey: groupKey,
                    filter: ui.ImageFilter.blur(
                      sigmaX: sigma * (1 - (i + .5) / bands),
                      sigmaY: sigma * (1 - (i + .5) / bands),
                      tileMode: TileMode.clamp,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

/// Live incremental Gaussian variance, with one smooth alpha shader per level.
/// Endpoints remain sigma→0; intermediate distributions are Gaussian mixtures.
/// Experimental: fewer native passes, no post-frame image capture.
class _LayeredProgressive extends StatefulWidget {
  const _LayeredProgressive({required this.sigma, required this.levels});
  final double sigma;
  final int levels;
  @override
  State<_LayeredProgressive> createState() => _LayeredState();
}

class _LayeredState extends State<_LayeredProgressive> {
  ui.FragmentProgram? _program;
  final _passes = <_ProgressivePass>[];
  final _fallbackKey = BackdropKey();
  Matrix4? _lastWorld;
  double? _lastDensity;
  (double, double, double)? _localY;
  @override
  void initState() {
    super.initState();
    if (_layeredProgram != null) {
      _program = _layeredProgram;
      _sync();
      return;
    }
    _loadLayeredProgram().then(
      (p) {
        if (!mounted) return;
        setState(() {
          _program = p;
          _sync();
        });
      },
      onError: (Object e, StackTrace s) =>
          FlutterError.reportError(FlutterErrorDetails(exception: e, stack: s)),
    );
  }

  void _sync() {
    if (_program == null) return;
    while (_passes.length < widget.levels) {
      _passes.add(_ProgressivePass(_program!.fragmentShader()));
    }
    while (_passes.length > widget.levels) {
      _passes.removeLast().dispose();
    }
    for (var i = 0; i < widget.levels; i++) {
      final lower = widget.sigma * (1 - (i + 1) / widget.levels);
      final upper = widget.sigma * (1 - i / widget.levels);
      _passes[i].updateSigma(math.sqrt(upper * upper - lower * lower));
    }
  }

  // Every layer is top-aligned in the same domain. Share the inverse when its
  // complete transform and DPR match, including compositing-only movement.
  // This caches geometry, never pixels: scrolling still samples live content.
  (double, double, double)? _textureToLocalY(Matrix4 world, double density) {
    if (_lastDensity == density &&
        listEquals(_lastWorld?.storage, world.storage)) {
      return _localY;
    }
    _lastWorld = world.clone();
    _lastDensity = density;
    final matrix = Matrix4.identity()
      ..scaleByDouble(density, density, 1, 1)
      ..multiply(world);
    if (matrix.determinant().abs() < 1e-10) return _localY = null;
    final inverse = Matrix4.inverted(matrix);
    return _localY = (
      inverse.entry(1, 0),
      inverse.entry(1, 1),
      inverse.entry(1, 3),
    );
  }

  @override
  void didUpdateWidget(_LayeredProgressive old) {
    super.didUpdateWidget(old);
    if (old.sigma != widget.sigma || old.levels != widget.levels) _sync();
  }

  @override
  void dispose() {
    for (final pass in _passes) {
      pass.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_passes.length != widget.levels) {
      return _gaussianBands(widget.sigma, 64, _fallbackKey);
    }
    final density = MediaQuery.devicePixelRatioOf(context);
    final n = widget.levels;
    return LayoutBuilder(
      builder: (context, c) => ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = n - 1; i >= 0; i--)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: c.maxHeight * (i + 1) / n,
                child: ClipRect(
                  child: KyantShaderBackdrop(
                    shader: _passes[i].shader,
                    configure: (_, _) {},
                    configureGeometry: (world, _) {
                      _passes[i].configure(
                        _textureToLocalY(world, density),
                        c.maxHeight * i / n,
                        c.maxHeight * (i + 1) / n,
                      );
                    },
                    filterBuilder: () => _passes[i].filter,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One consumer owns one shader and immutable filter chain. Rebuild the native
/// shader filter after changing uniforms: dart:ui snapshots those values when
/// creating its native filter, so reusing it after a move would freeze geometry.
class _ProgressivePass {
  _ProgressivePass(this.shader);
  final ui.FragmentShader shader;
  static final _identity = ui.ImageFilter.matrix(Matrix4.identity().storage);
  double? _sigma;
  late ui.ImageFilter _gaussian;
  ui.ImageFilter? _filter;
  (double, double, double)? _localY;
  double? _start, _end;
  bool _valid = false;

  void updateSigma(double sigma) {
    if (_sigma == sigma) return;
    _sigma = sigma;
    _gaussian = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.clamp,
    );
    _filter = null;
  }

  void configure((double, double, double)? localY, double start, double end) {
    _valid = localY != null;
    if (localY == null) return;
    if (_localY == localY && _start == start && _end == end) return;
    _localY = localY;
    _start = start;
    _end = end;
    shader
      ..setFloat(2, localY.$1)
      ..setFloat(3, localY.$2)
      ..setFloat(4, localY.$3)
      ..setFloat(5, start)
      ..setFloat(6, end);
    _filter = null;
  }

  ui.ImageFilter get filter {
    if (!_valid) return _identity;
    return _filter ??= ui.ImageFilter.compose(
      inner: _gaussian,
      outer: ui.ImageFilter.shader(shader),
    );
  }

  void dispose() {
    _filter = null;
    shader.dispose();
  }
}

void _disposeImage(ui.Image image) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    image.dispose();
    KyantDiagnostics.imageDisposed();
  });
}

class _BlurCache {
  final images = <ui.Image>[];
  int revision = -1;
  Size size = Size.zero;
  List<double>? matrix;
  void clear() {
    for (final image in images) {
      _disposeImage(image);
    }
    images.clear();
    revision = -1;
  }
}

class _InterpolatedBlur extends CustomPainter {
  _InterpolatedBlur({
    required this.source,
    required this.shader,
    required this.sigma,
    required this.cache,
    required this.density,
    required this.transform,
  }) : super(repaint: source);
  final KyantBackdrop source;
  final ui.FragmentShader shader;
  final double sigma, density;
  final _BlurCache cache;
  final Matrix4 Function() transform;
  @override
  void paint(Canvas canvas, Size size) {
    final image = source.image;
    final target = transform();
    if (image == null || size.isEmpty || target.determinant().abs() < 1e-10) {
      return;
    }
    final matrix = Matrix4.inverted(target)..multiply(source.imageToGlobal);
    final pad = (3 * sigma * density).ceil() / density;
    final w = math.max(1, ((size.width + 2 * pad) * density).ceil());
    final h = math.max(1, ((size.height + 2 * pad) * density).ceil());
    if (cache.images.isEmpty ||
        cache.revision != source.revision ||
        cache.size != size ||
        !listEquals(cache.matrix, matrix.storage)) {
      cache.clear();
      ui.Image record(void Function(Canvas) draw) {
        final r = ui.PictureRecorder();
        draw(Canvas(r));
        final p = r.endRecording();
        final result = p.toImageSync(w, h);
        p.dispose();
        KyantDiagnostics.imageCreated(w, h);
        return result;
      }

      final base = record((c) {
        c.scale(density);
        c.translate(pad, pad);
        c.transform(matrix.storage);
        c.drawImage(
          image,
          Offset.zero,
          Paint()..filterQuality = FilterQuality.low,
        );
      });
      cache.images.add(base);
      for (var i = 1; i < 4; i++) {
        final s = sigma * density * i / 3;
        cache.images.add(
          record(
            (c) => c.drawImage(
              base,
              Offset.zero,
              Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: s,
                  sigmaY: s,
                  tileMode: TileMode.clamp,
                ),
            ),
          ),
        );
      }
      cache.revision = source.revision;
      cache.size = size;
      cache.matrix = List.of(matrix.storage);
    }
    final floats = [
      size.width,
      size.height,
      w.toDouble(),
      h.toDouble(),
      pad * density,
      density,
    ];
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    for (var i = 0; i < 4; i++) {
      shader.setImageSampler(i, cache.images[i]);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_InterpolatedBlur old) =>
      old.sigma != sigma || old.source != source || old.density != density;
}
