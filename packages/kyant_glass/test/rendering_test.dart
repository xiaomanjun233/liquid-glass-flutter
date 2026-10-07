import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyant_glass/kyant_glass.dart';

Future<ui.Image> quadrants() async {
  final r = ui.PictureRecorder();
  final c = Canvas(r);
  c.drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = Colors.red);
  c.drawRect(const Rect.fromLTWH(20, 0, 20, 20), Paint()..color = Colors.green);
  c.drawRect(const Rect.fromLTWH(0, 20, 20, 20), Paint()..color = Colors.blue);
  c.drawRect(
    const Rect.fromLTWH(20, 20, 20, 20),
    Paint()..color = Colors.yellow,
  );
  final p = r.endRecording();
  final image = await p.toImage(40, 40);
  p.dispose();
  return image;
}

Future<ByteData> pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
List<int> rgba(ByteData p, int x, int y) =>
    List.generate(4, (i) => p.getUint8((y * 80 + x) * 4 + i));

class _ImageSource extends ChangeNotifier implements KyantBackdrop {
  _ImageSource(this.image);
  @override
  final ui.Image image;
  @override
  Rect get rect => const Rect.fromLTWH(0, 0, 80, 80);
  @override
  Matrix4 get imageToGlobal => Matrix4.diagonal3Values(2, 2, 1);
  @override
  int get revision => 0;
}

void main() {
  testWidgets('prewarmed glass draws explicit content on its first frame', (
    tester,
  ) async {
    final image = (await tester.runAsync(quadrants))!;
    await tester.runAsync(KyantGlass.precache);
    final key = GlobalKey();
    final source = _ImageSource(image);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: 80,
              child: KyantGlass(
                backdrop: source,
                pipeline: KyantPipeline.explicit,
                radius: 0,
                highlight: 0,
                tint: Colors.transparent,
                effects: const [KyantBlur(0), KyantLens(height: 0, amount: 0)],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    final first = await pixels(tester, key);
    expect(rgba(first, 10, 10), [244, 67, 54, 255]);
    expect(rgba(first, 65, 65), [255, 235, 59, 255]);
    await tester.pumpAndSettle();
    final settled = await pixels(tester, key);
    expect(settled.buffer.asUint8List(), first.buffer.asUint8List());
    await tester.pumpWidget(const SizedBox());
    image.dispose();
  });
  testWidgets(
    'image shader preserves top-down quadrants when lens is disabled',
    (tester) async {
      final image = (await tester.runAsync(quadrants))!;
      await tester.runAsync(KyantGlass.precache);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: 80,
                child: KyantGlassImage(
                  image: image,
                  radius: 0,
                  refractionHeight: 0,
                  refractionAmount: 0,
                  highlight: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final p = await pixels(tester, key);
      expect(rgba(p, 10, 10), [244, 67, 54, 255]);
      expect(rgba(p, 65, 10), [76, 175, 80, 255]);
      expect(rgba(p, 10, 65), [33, 150, 243, 255]);
      expect(rgba(p, 65, 65), [255, 235, 59, 255]);
      await tester.pumpWidget(const SizedBox());
      image.dispose();
    },
  );
  testWidgets(
    'explicit effects preserve source placement and release owned images',
    (tester) async {
      final image = (await tester.runAsync(quadrants))!;
      await tester.runAsync(KyantGlass.precache);
      final source = _ImageSource(image), key = GlobalKey();
      final before = KyantDiagnostics.liveImages;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: 80,
                child: KyantGlass(
                  backdrop: source,
                  pipeline: KyantPipeline.explicit,
                  radius: 0,
                  highlight: 0,
                  tint: Colors.transparent,
                  effects: const [
                    KyantColorControls(),
                    KyantBlur(0),
                    KyantLens(height: 0, amount: 0),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final p = await pixels(tester, key);
      expect(rgba(p, 10, 10), [244, 67, 54, 255]);
      expect(rgba(p, 10, 65), [33, 150, 243, 255]);
      // Reading pixels crosses the test's async boundary; drain shader-ready
      // callbacks before testing reuse of the fully loaded material.
      await tester.pumpAndSettle();
      final allocations = KyantDiagnostics.snapshots;
      await tester.pump(const Duration(seconds: 1));
      expect(
        KyantDiagnostics.snapshots,
        allocations,
        reason: 'Static input should reuse intermediate images.',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(KyantDiagnostics.liveImages, before);
      source.dispose();
      image.dispose();
    },
  );
  testWidgets('retained moving glass resamples a static background', (
    tester,
  ) async {
    final image = (await tester.runAsync(quadrants))!;
    await tester.runAsync(KyantGlass.precache);
    final source = _ImageSource(image);
    final offset = ValueNotifier(Offset.zero);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<Offset>(
            valueListenable: offset,
            builder: (_, value, child) =>
                Transform.translate(offset: value, child: child),
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: 80,
                child: KyantGlass(
                  backdrop: source,
                  pipeline: KyantPipeline.explicit,
                  radius: 0,
                  highlight: 0,
                  tint: Colors.transparent,
                  effects: const [KyantLens(height: 0, amount: 0)],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(rgba(await pixels(tester, key), 10, 10), [244, 67, 54, 255]);
    offset.value = const Offset(40, 0);
    await tester.pumpAndSettle();
    expect(rgba(await pixels(tester, key), 10, 10), [76, 175, 80, 255]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    source.dispose();
    offset.dispose();
    image.dispose();
  });
  testWidgets('empty background never samples the scene', (tester) async {
    final empty = KyantEmptyBackdrop();
    await tester.pumpWidget(
      MaterialApp(
        home: KyantGlass(
          backdrop: empty,
          child: const SizedBox(width: 80, height: 80),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(KyantShaderBackdrop), findsNothing);
    await tester.pumpWidget(const SizedBox());
    empty.dispose();
  });
  test(
    'timing statistics keep percentiles separate from presentation counts',
    () {
      final summary = KyantFrameRecorder.summarize([1, 2, 3, 4, 100]);
      expect(summary['p50'], 3);
      expect(summary['p99'], 100);
      expect(KyantFrameRecorder.summarize([])['max'], 0);
    },
  );
}
