import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'material.dart';

/// Full affine mapping. Perspective must use a projected explicit source.
void bindKyantLens(
  ui.FragmentShader shader, {
  required Size size,
  required BorderRadius corners,
  required KyantLens lens,
  required Matrix4 localToTexture,
  required Size sourceSize,
  required bool filterInput,
}) {
  final inverse = Matrix4.inverted(localToTexture);
  final m = localToTexture.storage, n = inverse.storage;
  final r = corners.toRRect(Offset.zero & size).scaleRadii();
  if (!filterInput) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
  }
  final values = [
    size.width,
    size.height,
    r.tlRadiusX,
    r.trRadiusX,
    r.brRadiusX,
    r.blRadiusX,
    m[0],
    m[4],
    m[12],
    m[1],
    m[5],
    m[13],
    n[0],
    n[4],
    n[12],
    n[1],
    n[5],
    n[13],
    sourceSize.width,
    sourceSize.height,
    lens.height,
    lens.amount,
    lens.dispersion,
    lens.depth ? 1.0 : 0.0,
    filterInput ? 1.0 : 0.0,
  ];
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i + 2, values[i]);
  }
}
