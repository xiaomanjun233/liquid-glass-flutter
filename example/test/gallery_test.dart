import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyant_glass_example/main.dart';

void main() {
  testWidgets('gallery fits a narrow screen and stops after background pause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GlassGallery());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilterChip, '动态背景'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilterChip, '动态背景'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
