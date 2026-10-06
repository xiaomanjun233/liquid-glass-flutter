// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
// Adapted from Kyant Backdrop 2.0.0, Apache-2.0. See NOTICE.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum KyantPipeline { composed, legacy, explicit }

enum KyantHighlightStyle { plain, directional, ambient }

/// Diagnostic routing; identical optical parameters are used by all backends.
class KyantRenderSettings extends InheritedWidget {
  const KyantRenderSettings({
    super.key,
    required super.child,
    this.pipeline = KyantPipeline.composed,
    this.debugDisableGlass = false,
    this.debugProgressiveBands,
  });
  final KyantPipeline pipeline;
  final bool debugDisableGlass;

  /// Null respects the widget mode; positive selects reference bands, negative
  /// selects layered levels, and zero disables progressive blur for diagnosis.
  final int? debugProgressiveBands;
  static KyantRenderSettings? settingsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KyantRenderSettings>();
  static KyantPipeline of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<KyantRenderSettings>()
          ?.pipeline ??
      const String.fromEnvironment(
        'KYANT_PIPELINE',
        defaultValue: 'composed',
      ).toPipeline();
  @override
  bool updateShouldNotify(KyantRenderSettings oldWidget) =>
      pipeline != oldWidget.pipeline ||
      debugDisableGlass != oldWidget.debugDisableGlass ||
      debugProgressiveBands != oldWidget.debugProgressiveBands;
}

extension on String {
  KyantPipeline toPipeline() => switch (this) {
    'legacy' => KyantPipeline.legacy,
    'explicit' => KyantPipeline.explicit,
    _ => KyantPipeline.composed,
  };
}

@immutable
class KyantHighlight {
  const KyantHighlight({
    this.style = KyantHighlightStyle.directional,
    this.color = const Color(0x80FFFFFF),
    this.width = .5,
    this.blur = .25,
    this.alpha = 1,
    this.angle = math.pi / 4,
    this.falloff = 1,
    this.blendMode = BlendMode.plus,
    this.floor = 0,
  });
  const KyantHighlight.ambient({
    this.width = .5,
    this.blur = .25,
    this.alpha = 1,
    this.angle = math.pi / 4,
    this.falloff = 1,
  }) : style = KyantHighlightStyle.ambient,
       color = const Color(0x61FFFFFF),
       blendMode = BlendMode.srcOver,
       floor = 0;
  const KyantHighlight.plain({
    this.color = const Color(0x61FFFFFF),
    this.width = .5,
    this.blur = .25,
    this.alpha = 1,
    this.blendMode = BlendMode.plus,
  }) : style = KyantHighlightStyle.plain,
       angle = 0,
       falloff = 1,
       floor = 0;
  final KyantHighlightStyle style;
  final Color color;
  final double width, blur, alpha, angle, falloff, floor;
  final BlendMode blendMode;
}

@immutable
class KyantShadow {
  const KyantShadow({
    this.radius = 24,
    this.offset = const Offset(0, 4),
    this.color = const Color(0x1A000000),
    this.alpha = 1,
    this.blendMode = BlendMode.srcOver,
  });
  const KyantShadow.inner({
    this.radius = 24,
    this.offset = const Offset(0, 24),
    this.color = const Color(0x26000000),
    this.alpha = 1,
    this.blendMode = BlendMode.srcOver,
  });
  final double radius, alpha;
  final Offset offset;
  final Color color;
  final BlendMode blendMode;
}

/// Effects are applied in list order. Lens shaders are owned by each surface.
sealed class KyantEffect {
  const KyantEffect();
}

class KyantBlur extends KyantEffect {
  const KyantBlur(this.sigma) : assert(sigma >= 0);
  final double sigma;
}

class KyantColorFilter extends KyantEffect {
  const KyantColorFilter(this.filter);
  final ColorFilter filter;
}

class KyantColorControls extends KyantEffect {
  const KyantColorControls({
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
  });
  const KyantColorControls.vibrancy()
    : brightness = 0,
      contrast = 1,
      saturation = 1.5;
  final double brightness, contrast, saturation;
  List<double> get matrix {
    final r = contrast * .213 * (1 - saturation);
    final g = contrast * .715 * (1 - saturation);
    final b = contrast * .072 * (1 - saturation);
    final s = contrast * saturation;
    final t = (.5 - contrast * .5 + brightness) * 255;
    return [
      r + s,
      g,
      b,
      0,
      t,
      r,
      g + s,
      b,
      0,
      t,
      r,
      g,
      b + s,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  ColorFilter get filter => ColorFilter.matrix(matrix);
}

class KyantOpacity extends KyantEffect {
  const KyantOpacity(this.alpha) : assert(alpha >= 0 && alpha <= 1);
  final double alpha;
  ColorFilter get filter => ColorFilter.matrix([
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    alpha,
    0,
  ]);
}

class KyantLens extends KyantEffect {
  const KyantLens({
    this.height = 16,
    this.amount = 10,
    this.dispersion = .35,
    this.depth = false,
  }) : assert(height >= 0),
       assert(amount >= 0),
       assert(dispersion >= 0);
  final double height, amount, dispersion;
  final bool depth;
}

ui.ImageFilter? kyantBasicFilter(KyantEffect effect, {double scale = 1}) =>
    switch (effect) {
      KyantBlur(:final sigma) =>
        sigma > 0
            ? ui.ImageFilter.blur(
                sigmaX: sigma * scale,
                sigmaY: sigma * scale,
                tileMode: TileMode.clamp,
              )
            : null,
      KyantColorFilter(:final filter) => filter,
      KyantColorControls() => effect.filter,
      KyantOpacity() => effect.filter,
      KyantLens() => null,
    };

ui.ImageFilter? kyantCompose(ui.ImageFilter? first, ui.ImageFilter? next) =>
    first == null
    ? next
    : next == null
    ? first
    : ui.ImageFilter.compose(inner: first, outer: next);

class KyantCapabilities {
  const KyantCapabilities._();
  static bool get liveBackdrop => ui.ImageFilter.isShaderFilterSupported;
  static bool get explicitImages => true;

  /// Stock ImageFilter.shader supplies input size but no offscreen origin.
  static bool get nativeArbitraryOffscreenOrigin => false;

  /// Source snapshots are delivered after paint, then consumed next frame.
  static bool get explicitBackdropIsSameFrame => false;
  static String get renderer => liveBackdrop
      ? 'Impeller'
      : kIsWeb
      ? 'Web explicit texture'
      : 'Explicit texture / blur fallback';
}
