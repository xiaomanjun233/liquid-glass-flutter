import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kyant_glass/kyant_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([KyantGlass.precache(), KyantProgressiveBlur.precache()]);
  runApp(const GlassGallery());
}

class GlassGallery extends StatefulWidget {
  const GlassGallery({super.key});
  @override
  State<GlassGallery> createState() => _GalleryState();
}

class _GalleryState extends State<GlassGallery> {
  bool _dark = false, _rtl = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Kyant Glass · Flutter',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3557CE),
        brightness: _dark ? Brightness.dark : Brightness.light,
      ),
    ),
    home: Directionality(
      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      child: GalleryScene(
        dark: _dark,
        onTheme: () => setState(() => _dark = !_dark),
        onDirection: () => setState(() => _rtl = !_rtl),
      ),
    ),
  );
}

class GalleryScene extends StatefulWidget {
  const GalleryScene({
    super.key,
    required this.dark,
    required this.onTheme,
    required this.onDirection,
  });
  final bool dark;
  final VoidCallback onTheme, onDirection;
  @override
  State<GalleryScene> createState() => _GallerySceneState();
}

class _GallerySceneState extends State<GalleryScene>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  final _source = KyantBackdropController(captureOnNative: true);
  KyantCombinedBackdrop? _combined;
  late final _shifted = KyantTransformedBackdrop(
    _source,
    Matrix4.identity()..translateByDouble(8, 0, 0, 1),
  );
  final _empty = KyantEmptyBackdrop();
  KyantPipeline _pipeline = kIsWeb
      ? KyantPipeline.explicit
      : KyantPipeline.composed;
  KyantProgressiveMode _blurMode = KyantProgressiveMode.shared;
  bool _moving = false,
      _toggle = true,
      _transform = false,
      _opacity = false,
      _depth = false;
  double _slider = .45, _dispersion = 1;
  int _tab = 0, _sourceMode = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = View.of(context).devicePixelRatio;
    if (_combined == null || _combined!.pixelRatio != ratio) {
      _combined?.dispose();
      _combined = KyantCombinedBackdrop([_source], pixelRatio: ratio);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _combined?.dispose();
    _shifted.dispose();
    _empty.dispose();
    _source.dispose();
    super.dispose();
  }

  KyantBackdrop get _input => switch (_sourceMode) {
    1 => _combined!,
    2 => _shifted,
    3 => _empty,
    _ => _source,
  };
  Widget _chip(String label, bool value, ValueChanged<bool> change) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(label: Text(label), selected: value, onSelected: change),
  );
  @override
  Widget build(BuildContext context) {
    _source.captureOnNative =
        _pipeline == KyantPipeline.explicit ||
        _blurMode == KyantProgressiveMode.interpolated;
    return KyantRenderSettings(
      pipeline: _pipeline,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kyant Glass / Flutter'),
          actions: [
            IconButton(
              onPressed: widget.onTheme,
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              onPressed: widget.onDirection,
              icon: const Icon(Icons.format_textdirection_r_to_l),
            ),
          ],
        ),
        body: KyantBenchmarkPanel(
          enabled: const bool.fromEnvironment('KYANT_BENCHMARK'),
          child: Column(
            children: [
              Material(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      DropdownButton<KyantPipeline>(
                        value: _pipeline,
                        items: [
                          for (final p in KyantPipeline.values)
                            DropdownMenuItem(value: p, child: Text(p.name)),
                        ],
                        onChanged: (p) => setState(() => _pipeline = p!),
                      ),
                      const SizedBox(width: 16),
                      _chip(
                        '动态背景',
                        _moving,
                        (v) => setState(() {
                          _moving = v;
                          if (v) {
                            _clock.repeat();
                          } else {
                            _clock.stop();
                          }
                        }),
                      ),
                      _chip(
                        '缩放 / 旋转',
                        _transform,
                        (v) => setState(() => _transform = v),
                      ),
                      _chip(
                        '离屏透明度',
                        _opacity,
                        (v) => setState(() => _opacity = v),
                      ),
                      _chip('深度', _depth, (v) => setState(() => _depth = v)),
                      _chip(
                        _dispersion == 0 ? '单采样' : '七组色散',
                        _dispersion > 0,
                        (v) => setState(() => _dispersion = v ? 1 : 0),
                      ),
                      DropdownButton<int>(
                        value: _sourceMode,
                        items: [
                          for (final (i, label) in [
                            'Layer / Canvas',
                            'Combined',
                            'Transformed',
                            'Empty',
                          ].indexed)
                            DropdownMenuItem(value: i, child: Text(label)),
                        ],
                        onChanged: (v) => setState(() => _sourceMode = v!),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<KyantProgressiveMode>(
                        value: _blurMode,
                        items: [
                          for (final m in KyantProgressiveMode.values)
                            DropdownMenuItem(
                              value: m,
                              child: Text('顶栏 ${m.name}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _blurMode = v!),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    KyantBackdropSource(
                      controller: _source,
                      repaint: _clock,
                      child: AnimatedBuilder(
                        animation: _clock,
                        child: Image.asset(
                          'assets/landscape.webp',
                          fit: BoxFit.cover,
                        ),
                        builder: (context, child) => Stack(
                          fit: StackFit.expand,
                          children: [
                            Transform.scale(
                              scale: 1 + .03 * math.sin(_clock.value * math.pi),
                              child: child,
                            ),
                            ColoredBox(
                              color: widget.dark
                                  ? const Color(0x800A1220)
                                  : const Color(0x18FFFFFF),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 120,
                      child: IgnorePointer(
                        child: KyantProgressiveBlur(
                          sigma: 12,
                          mode: _blurMode,
                          backdrop: _source,
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      key: const ValueKey('gallery-scroll'),
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 130),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '光学与交互对照',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${KyantCapabilities.renderer} · Kyant 2.0.0\n'
                                'composed 原生同帧背景 / explicit 显式快照实验。旋转、离屏和动态延迟需分别验收。',
                              ),
                              const SizedBox(height: 24),
                              for (final style in KyantHighlightStyle.values)
                                _card(style),
                              LiquidButton(
                                backdrop: _input,
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (context) => const AlertDialog(
                                    title: Text('按钮'),
                                    content: Text('检查按下、释放和再次按下的连续性。'),
                                  ),
                                ),
                                child: const Text('Liquid Button'),
                              ),
                              const SizedBox(height: 16),
                              const Text('插值顶栏是近似实验，不作为默认保真结论。测试时请观察背景是否落后一帧。'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: LiquidBottomTabs(
                            tabs: const [
                              KyantTab(label: '光学', icon: Icons.blur_on),
                              KyantTab(label: '交互', icon: Icons.touch_app),
                              KyantTab(label: '稳定', icon: Icons.layers),
                            ],
                            selected: _tab,
                            onChanged: (v) => setState(() => _tab = v),
                            backdrop: _source,
                            width: 300,
                            tint: Colors.white.withValues(
                              alpha: widget.dark ? .12 : .5,
                            ),
                            accent: Theme.of(context).colorScheme.primary,
                            foreground: widget.dark
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(KyantHighlightStyle style) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: AnimatedBuilder(
      animation: _clock,
      builder: (context, child) => Opacity(
        opacity: _opacity ? .72 : 1,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..rotateZ(
              _transform ? .12 * math.sin(_clock.value * math.pi * 2) : 0,
            )
            ..scaleByDouble(_transform ? .93 : 1, _transform ? .93 : 1, 1, 1),
          child: child,
        ),
      ),
      child: RepaintBoundary(
        child: KyantGlass(
          backdrop: _input,
          radius: 28,
          effects: [
            const KyantColorControls.vibrancy(),
            const KyantBlur(4),
            KyantLens(
              height: 24,
              amount: 22,
              dispersion: _dispersion,
              depth: _depth,
            ),
          ],
          highlightStyle: KyantHighlight(style: style, width: 1, blur: .5),
          shadow: const KyantShadow(),
          innerShadow: const KyantShadow.inner(),
          tint: (widget.dark ? Colors.black : Colors.white).withValues(
            alpha: .15,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('柔和背景下的折射、高光与触摸反馈。'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    LiquidToggle(
                      value: _toggle,
                      backdrop: _input,
                      onChanged: (v) => setState(() => _toggle = v),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: LiquidSlider(
                        value: _slider,
                        backdrop: _input,
                        onChanged: (v) => setState(() => _slider = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
