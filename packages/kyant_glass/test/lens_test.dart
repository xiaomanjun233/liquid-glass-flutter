import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyant_glass/kyant_glass.dart';

void main() {
  test('distance field describes straight edges and rounded corners', () {
    const size = Size(200, 100);
    expect(KyantLensGeometry.signedDistance(Offset.zero, size, 20), -50);
    expect(KyantLensGeometry.signedDistance(const Offset(100, 0), size, 20), 0);
    expect(
      KyantLensGeometry.signedDistance(const Offset(100, 50), size, 20),
      closeTo(math.sqrt(800) - 20, .0001),
    );
    expect(KyantLensGeometry.signedDistance(const Offset(0, 70), size, 20), 20);
  });
  test('lens vanishes in the interior and is symmetric near edges', () {
    const size = Size(200, 100);
    expect(KyantLensGeometry.displacement(Offset.zero, size), Offset.zero);
    final right = KyantLensGeometry.displacement(const Offset(99, 0), size);
    final left = KyantLensGeometry.displacement(const Offset(-99, 0), size);
    expect(right.dx, lessThan(0));
    expect(left.dx, closeTo(-right.dx, .0001));
    expect(right.dy, 0);
    expect(
      KyantLensGeometry.displacement(const Offset(99, 0), size, amount: 0),
      Offset.zero,
    );
    expect(
      KyantLensGeometry.normal(Offset.zero, size, 500).distance.isFinite,
      isTrue,
    );
  });
  testWidgets('unsupported renderer retains content with a clipped blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: KyantGlass(
              child: Padding(padding: EdgeInsets.all(20), child: Text('玻璃按钮')),
            ),
          ),
        ),
      ),
    );
    expect(find.text('玻璃按钮'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
