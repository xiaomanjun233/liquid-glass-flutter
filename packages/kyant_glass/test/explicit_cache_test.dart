import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyant_glass/kyant_glass.dart';

class _Source extends ChangeNotifier implements KyantBackdrop {
  _Source(this.image);
  @override
  final ui.Image image;
  @override
  Rect get rect => const Rect.fromLTWH(0, 0, 160, 160);
  @override
  Matrix4 get imageToGlobal => Matrix4.identity();
  @override
  int revision = 0;
  void update() {
    revision++;
    notifyListeners();
  }
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 160, 160), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final result = await picture.toImage(160, 160);
  picture.dispose();
  return result;
}

void main() {
  testWidgets('terminal lens and contiguous filters need only two snapshots', (
    tester,
  ) async {
    await tester.runAsync(KyantGlass.precache);
    final image = (await tester.runAsync(_image))!;
    final source = _Source(image);
    final live = KyantDiagnostics.liveImages;
    Widget scene({double blur = 2, String label = 'a', KyantBackdrop? input}) =>
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.square(
              dimension: 80,
              child: KyantGlass(
                backdrop: input ?? source,
                pipeline: KyantPipeline.explicit,
                highlight: 0,
                effects: [
                  const KyantColorControls.vibrancy(),
                  KyantBlur(blur),
                  const KyantLens(),
                ],
                child: Text(label),
              ),
            ),
          ),
        );
    final before = KyantDiagnostics.snapshots;
    await tester.pumpWidget(scene());
    await tester.pumpAndSettle();
    expect(
      KyantDiagnostics.snapshots - before,
      2,
      reason: 'One crop and one composed filter input; final lens is direct.',
    );
    final cached = KyantDiagnostics.snapshots;
    await tester.pumpWidget(scene(label: 'b'));
    await tester.pumpAndSettle();
    expect(
      KyantDiagnostics.snapshots,
      cached,
      reason: 'Equivalent effect values and child rebuild reuse the input.',
    );
    await tester.pumpWidget(scene(blur: 3));
    await tester.pumpAndSettle();
    expect(KyantDiagnostics.snapshots - cached, 2);
    final changed = KyantDiagnostics.snapshots;
    final replacement = _Source(image);
    await tester.pumpWidget(scene(blur: 3, input: replacement));
    await tester.pumpAndSettle();
    expect(
      KyantDiagnostics.snapshots - changed,
      2,
      reason: 'Different source with the same revision must invalidate.',
    );
    final replaced = KyantDiagnostics.snapshots;
    replacement.update();
    await tester.pumpAndSettle();
    expect(KyantDiagnostics.snapshots - replaced, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(KyantDiagnostics.liveImages, live);
    source.dispose();
    replacement.dispose();
    image.dispose();
  });

  testWidgets('a lens before another effect still materializes in list order', (
    tester,
  ) async {
    await tester.runAsync(KyantGlass.precache);
    final image = (await tester.runAsync(_image))!;
    final source = _Source(image);
    final before = KyantDiagnostics.snapshots;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 80,
          child: KyantGlass(
            backdrop: source,
            pipeline: KyantPipeline.explicit,
            effects: const [
              KyantLens(),
              KyantColorControls(),
              KyantOpacity(.5),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      KyantDiagnostics.snapshots - before,
      3,
      reason: 'Crop, nonterminal lens, and the ordered composed filter run.',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    source.dispose();
    image.dispose();
  });
}
