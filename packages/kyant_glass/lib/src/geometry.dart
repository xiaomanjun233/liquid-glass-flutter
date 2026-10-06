// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Kyant
// Copyright 2026 xiaomanjun233 and contributors
// 基于 Kyant Backdrop 2.0.0 改编；Flutter 修改与来源见 NOTICE、docs/SOURCES.md。
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Kyant's rounded rectangle SDF and gradient, in local logical coordinates.
/// The gradient uses a larger corner radius for the softer upstream lens.
abstract final class KyantLensGeometry {
  static double signedDistance(Offset point, Size size, double radius) {
    radius = radius.clamp(0, math.min(size.width, size.height) / 2);
    final corner = Offset(
      point.dx.abs() - size.width / 2 + radius,
      point.dy.abs() - size.height / 2 + radius,
    );
    final outside =
        Offset(math.max(corner.dx, 0), math.max(corner.dy, 0)).distance -
        radius;
    return outside + math.min(math.max(corner.dx, corner.dy), 0);
  }

  static Offset _unit(Offset v) =>
      v.distance > .0001 ? v / v.distance : Offset.zero;
  static Offset normal(Offset point, Size size, double radius) {
    radius = radius.clamp(0, math.min(size.width, size.height) / 2);
    final corner = Offset(
      point.dx.abs() - size.width / 2 + radius,
      point.dy.abs() - size.height / 2 + radius,
    );
    final gradient = corner.dx >= 0 || corner.dy >= 0
        ? _unit(Offset(math.max(corner.dx, 0), math.max(corner.dy, 0)))
        : corner.dx >= corner.dy
        ? const Offset(1, 0)
        : const Offset(0, 1);
    return Offset(point.dx.sign * gradient.dx, point.dy.sign * gradient.dy);
  }

  static Offset displacement(
    Offset point,
    Size size, {
    double radius = 24,
    double height = 16,
    double amount = 12,
    bool depth = false,
  }) {
    final sd = signedDistance(point, size, radius);
    if (height <= 0 || amount <= 0 || -sd >= height) return Offset.zero;
    final x = (1 + math.min(sd, 0) / height).clamp(0.0, 1.0);
    final d = -(1 - math.sqrt(1 - x * x)) * amount;
    final grad = normal(
      point,
      size,
      math.min(radius * 1.5, size.shortestSide / 2),
    );
    return _unit(grad + (depth ? _unit(point) : Offset.zero)) * d;
  }
}
