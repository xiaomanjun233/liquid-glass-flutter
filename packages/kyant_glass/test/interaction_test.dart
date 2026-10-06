import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyant_glass/kyant_glass.dart';

void main() {
  testWidgets(
    'press expands, cancel settles, and a new press can interrupt release',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: KyantGlassControl(
              child: SizedBox.square(
                dimension: 44,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      );
      final control = find.byType(KyantGlassControl);
      double scale() => tester
          .widget<Transform>(
            find.byKey(const ValueKey('kyant-press-transform')),
          )
          .transform
          .storage[0];
      var pointer = await tester.startGesture(tester.getCenter(control));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(scale(), greaterThan(1.05));
      await pointer.moveBy(const Offset(15, 8));
      await pointer.cancel();
      await tester.pump(const Duration(milliseconds: 45));
      pointer = await tester.startGesture(tester.getCenter(control));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(scale(), greaterThan(1.05));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1, .001));
    },
  );
  testWidgets(
    'dock lens follows a drag and commits exactly one tab on release',
    (tester) async {
      final selected = ValueNotifier(0);
      final commits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (_, value, _) => LiquidBottomTabs(
                tabs: const [
                  KyantTab(label: '首页'),
                  KyantTab(label: '我的'),
                ],
                selected: value,
                onChanged: (value) {
                  commits.add(value);
                  selected.value = value;
                },
                tint: Colors.white54,
                foreground: Colors.black,
                accent: Colors.blue,
              ),
            ),
          ),
        ),
      );
      final lens = find.byKey(const ValueKey('kyant-dock-lens'));
      final start = tester.getCenter(lens).dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('首页')),
      );
      await tester.pump();
      // A real finger keeps sending moves. Restarting an AnimationController
      // on each move can leave every frame at simulation time zero.
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getCenter(lens).dx, greaterThan(start + 25));
      expect(commits, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, [1]);
      expect(tester.getCenter(lens).dx, greaterThan(start + 60));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selected.dispose();
    },
  );
}
