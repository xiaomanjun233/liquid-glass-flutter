import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyant_glass/kyant_glass.dart';
import 'package:kyant_glass/src/transform_observer.dart';

Widget host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(devicePixelRatio: 1),
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

void main() {
  testWidgets('repaint signal captures retained descendant boundaries', (
    tester,
  ) async {
    final controller = KyantBackdropController(captureOnNative: true);
    final color = ValueNotifier(Colors.red);
    await tester.pumpWidget(
      host(
        KyantBackdropSource(
          controller: controller,
          repaint: color,
          child: RepaintBoundary(
            child: ValueListenableBuilder<Color>(
              valueListenable: color,
              builder: (_, value, _) => SizedBox.square(
                dimension: 40,
                child: ColoredBox(color: value),
              ),
            ),
          ),
        ),
      ),
    );
    final first = controller.revision;
    expect(first, greaterThan(0));
    color.value = Colors.blue;
    await tester.pump();
    expect(controller.revision, greaterThan(first));
    final changed = controller.revision;
    await tester.pump();
    await tester.pump();
    expect(controller.revision, changed);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    color.dispose();
    await tester.pump();
  });

  testWidgets('source follows retained ancestor transforms and then idles', (
    tester,
  ) async {
    final controller = KyantBackdropController(captureOnNative: true);
    final offset = ValueNotifier(Offset.zero);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<Offset>(
          valueListenable: offset,
          builder: (_, value, child) =>
              Transform.translate(offset: value, child: child),
          child: RepaintBoundary(
            child: KyantBackdropSource(
              controller: controller,
              child: const SizedBox.square(
                dimension: 40,
                child: ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
    expect(controller.rect.topLeft, Offset.zero);
    offset.value = const Offset(17, 23);
    await tester.pump();
    expect(controller.rect.topLeft, const Offset(17, 23));
    expect(controller.imageToGlobal.storage[12], 17);
    expect(controller.imageToGlobal.storage[13], 23);
    final revision = controller.revision;
    await tester.pump();
    expect(controller.revision, revision);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    offset.dispose();
    await tester.pump();
  });

  testWidgets('an initially offstage source waits until it has painted', (
    tester,
  ) async {
    final controller = KyantBackdropController(captureOnNative: true);
    final offstage = ValueNotifier(true);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<bool>(
          valueListenable: offstage,
          builder: (_, value, child) => Offstage(offstage: value, child: child),
          child: KyantBackdropSource(
            controller: controller,
            child: const SizedBox.square(
              dimension: 40,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    expect(controller.image, isNull);
    expect(tester.takeException(), isNull);
    offstage.value = false;
    await tester.pump();
    expect(controller.image, isNotNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    offstage.dispose();
    await tester.pump();
  });

  testWidgets('retained source reacts to DPR and size changes', (tester) async {
    final controller = KyantBackdropController(captureOnNative: true);
    final density = ValueNotifier(1.0);
    final size = ValueNotifier(40.0);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<double>(
          valueListenable: density,
          builder: (_, value, child) => MediaQuery(
            data: MediaQueryData(devicePixelRatio: value),
            child: child!,
          ),
          child: ValueListenableBuilder<double>(
            valueListenable: size,
            builder: (_, value, child) =>
                SizedBox.square(dimension: value, child: child),
            child: KyantBackdropSource(
              controller: controller,
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    expect(controller.image!.width, 40);
    density.value = 2;
    await tester.pump();
    expect(controller.image!.width, 80);
    expect(controller.imageToGlobal.storage[0], .5);
    size.value = 60;
    await tester.pump();
    expect(controller.image!.width, 120);
    expect(controller.rect.size, const Size.square(60));
    size.value = 0;
    await tester.pump();
    expect(controller.image, isNull);
    expect(controller.rect, Rect.zero);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    density.dispose();
    size.dispose();
    await tester.pump();
  });

  testWidgets('nested source snapshots settle and release owned images', (
    tester,
  ) async {
    final baseline = KyantDiagnostics.liveImages;
    final outer = KyantBackdropController(captureOnNative: true);
    final inner = KyantBackdropController(captureOnNative: true);
    await tester.pumpWidget(
      host(
        KyantBackdropSource(
          controller: outer,
          child: KyantBackdropSource(
            controller: inner,
            child: const SizedBox.square(
              dimension: 40,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final revisions = [outer.revision, inner.revision];
    expect(revisions.every((revision) => revision > 0), isTrue);
    await tester.pump();
    await tester.pump();
    expect([outer.revision, inner.revision], revisions);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    outer.dispose();
    inner.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(KyantDiagnostics.liveImages, baseline);
  });

  testWidgets('transform observer repaints a retained consumer once', (
    tester,
  ) async {
    final offset = ValueNotifier(Offset.zero);
    final painter = _CountingPainter();
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<Offset>(
          valueListenable: offset,
          builder: (_, value, child) =>
              Transform.translate(offset: value, child: child),
          child: RepaintBoundary(
            child: KyantTransformObserver(
              child: CustomPaint(size: const Size.square(40), painter: painter),
            ),
          ),
        ),
      ),
    );
    final first = painter.paints;
    offset.value = const Offset(17, 23);
    await tester.pump();
    expect(painter.paints, first, reason: 'The consumer was retained.');
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(painter.paints, first + 1);
    await tester.pump();
    expect(painter.paints, first + 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    offset.dispose();
  });

  testWidgets('follower source and a listening consumer settle', (
    tester,
  ) async {
    final baseline = KyantDiagnostics.liveImages;
    final controller = KyantBackdropController(captureOnNative: true);
    final link = LayerLink();
    await tester.pumpWidget(
      host(
        Stack(
          children: [
            KyantBackdropSource(
              controller: controller,
              child: SizedBox.square(
                dimension: 40,
                child: Stack(
                  children: [
                    CompositedTransformTarget(
                      link: link,
                      child: const SizedBox.square(dimension: 10),
                    ),
                    CompositedTransformFollower(
                      link: link,
                      child: const SizedBox.square(
                        dimension: 20,
                        child: ColoredBox(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            CustomPaint(
              size: const Size.square(40),
              painter: _SourcePainter(controller),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final revision = controller.revision;
    await tester.pump();
    await tester.pump();
    expect(controller.revision, revision);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(KyantDiagnostics.liveImages, baseline);
  });

  testWidgets('replacement cancels the old throttled source request', (
    tester,
  ) async {
    final baseline = KyantDiagnostics.liveImages;
    final old = KyantBackdropController(
      captureOnNative: true,
      frameInterval: const Duration(seconds: 1),
    );
    final replacement = KyantBackdropController(captureOnNative: true);
    final active = ValueNotifier(old);
    final repaint = ChangeNotifier();
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<KyantBackdropController>(
          valueListenable: active,
          builder: (_, controller, child) => KyantBackdropSource(
            controller: controller,
            repaint: repaint,
            child: child!,
          ),
          child: const SizedBox.square(
            dimension: 40,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(old.revision, greaterThan(0));
    final revision = old.revision;
    repaint.notifyListeners();
    active.value = replacement;
    await tester.pump();
    expect(replacement.revision, greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
    expect(old.revision, revision);
    old.dispose();
    repaint.notifyListeners();
    await tester.pumpWidget(const SizedBox());
    replacement.dispose();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(KyantDiagnostics.liveImages, baseline);
    active.dispose();
    repaint.dispose();
  });

  testWidgets('disabling native capture cancels work already throttled', (
    tester,
  ) async {
    final controller = KyantBackdropController(
      captureOnNative: true,
      frameInterval: const Duration(seconds: 1),
    );
    final repaint = ChangeNotifier();
    await tester.pumpWidget(
      host(
        KyantBackdropSource(
          controller: controller,
          repaint: repaint,
          child: const SizedBox.square(
            dimension: 40,
            child: ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final revision = controller.revision;
    expect(revision, greaterThan(0));
    repaint.notifyListeners();
    controller.captureOnNative = false;
    await tester.pump(const Duration(seconds: 2));
    expect(controller.revision, revision);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    repaint.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, skip: kIsWeb);
}

class _SourcePainter extends CustomPainter {
  _SourcePainter(this.source) : super(repaint: source);
  final KyantBackdrop source;

  @override
  void paint(Canvas canvas, Size size) {
    final image = source.image;
    if (image != null) canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(_SourcePainter oldDelegate) => false;
}

class _CountingPainter extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}
