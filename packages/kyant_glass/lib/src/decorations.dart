// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'material.dart';
import 'programs.dart';

final highlightProgram = loadKyantProgram('kyant_highlight.frag');

class KyantDecorationPainter extends CustomPainter {
  KyantDecorationPainter({
    required this.corners,
    this.highlight,
    this.shader,
    this.innerShadow,
    this.shadow,
    this.density = 1,
  });
  final BorderRadius corners;
  final KyantHighlight? highlight;
  final ui.FragmentShader? shader;
  final KyantShadow? innerShadow, shadow;
  final double density;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = corners.toRRect(rect).scaleRadii();
    final outside = shadow;
    if (outside != null && outside.alpha > 0) {
      canvas.save();
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(
            rect.inflate(outside.radius * 4 + outside.offset.distance),
          ),
          Path()..addRRect(shape),
        ),
      );
      canvas.drawRRect(
        shape.shift(outside.offset),
        Paint()
          ..color = outside.color.withValues(
            alpha: outside.color.a * outside.alpha,
          )
          ..blendMode = outside.blendMode
          ..maskFilter = outside.radius > 0
              ? MaskFilter.blur(BlurStyle.normal, outside.radius)
              : null,
      );
      canvas.restore();
    }
    final h = highlight;
    if (h != null && h.width > 0 && h.alpha > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (h.width * density).ceil() / density * 2
        ..blendMode = h.blendMode
        ..color = h.color.withValues(alpha: h.color.a * h.alpha)
        ..maskFilter = h.blur > 0
            ? MaskFilter.blur(BlurStyle.normal, h.blur)
            : null;
      final s = shader;
      if (s != null && h.style != KyantHighlightStyle.plain) {
        final a = h.color.a * h.alpha;
        final values = [
          size.width,
          size.height,
          shape.tlRadiusX,
          shape.trRadiusX,
          shape.brRadiusX,
          shape.blRadiusX,
          h.color.r * a,
          h.color.g * a,
          h.color.b * a,
          a,
          h.angle,
          h.falloff,
          h.style.index.toDouble(),
          h.floor,
        ];
        for (var i = 0; i < values.length; i++) {
          s.setFloat(i, values[i]);
        }
        paint.shader = s;
      }
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRRect(shape, paint);
      canvas.restore();
    }
    final inner = innerShadow;
    if (inner != null && inner.alpha > 0) {
      // Isolated S - translate(S), blurred and clipped back to S. Clear must
      // never touch the backdrop or the child content.
      canvas.save();
      canvas.clipRRect(shape);
      canvas.saveLayer(
        rect.inflate(inner.radius * 3),
        Paint()
          ..blendMode = inner.blendMode
          ..color = Color.fromRGBO(255, 255, 255, inner.alpha)
          ..imageFilter = inner.radius > 0
              ? ui.ImageFilter.blur(
                  sigmaX: inner.radius,
                  sigmaY: inner.radius,
                  tileMode: TileMode.decal,
                )
              : null,
      );
      canvas.drawRRect(shape, Paint()..color = inner.color);
      canvas.drawRRect(
        shape.shift(inner.offset),
        Paint()..blendMode = BlendMode.clear,
      );
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(KyantDecorationPainter old) =>
      corners != old.corners ||
      highlight != old.highlight ||
      shader != old.shader ||
      shadow != old.shadow ||
      innerShadow != old.innerShadow ||
      density != old.density;
}
