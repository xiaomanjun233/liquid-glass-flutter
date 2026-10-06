import 'dart:convert';

import 'package:flutter/scheduler.dart';

/// No ChangeNotifier and no setState: collecting timings never requests a frame.
class KyantFrameRecorder {
  KyantFrameRecorder({this.capacity = 12000});
  final int capacity;
  final List<FrameTiming> _frames = [];
  bool _recording = false;
  String _scenario = '';
  int _dropped = 0;
  void start(String scenario) {
    stop();
    _scenario = scenario;
    _frames.clear();
    _dropped = 0;
    _recording = true;
    SchedulerBinding.instance.addTimingsCallback(_receive);
  }

  void _receive(List<FrameTiming> timings) {
    for (final frame in timings) {
      if (_frames.length < capacity) {
        _frames.add(frame);
      } else {
        _dropped++;
      }
    }
  }

  Map<String, Object> stop() {
    if (_recording) SchedulerBinding.instance.removeTimingsCallback(_receive);
    _recording = false;
    return {
      'scenario': _scenario,
      'frames': _frames.length,
      'discardedSamples': _dropped,
      'buildMs': summarize(
        _frames.map((f) => f.buildDuration.inMicroseconds / 1000),
      ),
      'rasterMs': summarize(
        _frames.map((f) => f.rasterDuration.inMicroseconds / 1000),
      ),
      'totalSpanMs': summarize(
        _frames.map((f) => f.totalSpan.inMicroseconds / 1000),
      ),
      'note': 'totalSpan includes pipeline latency; it is not a dropped-frame count.',
      'resources': KyantDiagnostics.snapshot(),
    };
  }

  String stopJson() => const JsonEncoder.withIndent('  ').convert(stop());
  void dispose() {
    stop();
  }

  static Map<String, num> summarize(Iterable<double> samples) {
    final sorted = samples.toList()..sort();
    if (sorted.isEmpty) return {'p50': 0, 'p95': 0, 'p99': 0, 'max': 0};
    double at(double p) => sorted[((sorted.length - 1) * p).round()];
    return {'p50': at(.5), 'p95': at(.95), 'p99': at(.99), 'max': sorted.last};
  }
}

/// Application-visible resources only; engine GPU allocations require a trace.
abstract final class KyantDiagnostics {
  static int snapshots = 0, snapshotPixels = 0, liveImages = 0;
  static int filterPaints = 0, explicitPaints = 0;
  static void imageCreated(int width, int height) {
    snapshots++;
    snapshotPixels += width * height;
    liveImages++;
  }

  static void imageDisposed() {
    liveImages--;
  }

  static Map<String, int> snapshot() => {
    'snapshots': snapshots,
    'snapshotPixels': snapshotPixels,
    'liveImages': liveImages,
    'filterPaints': filterPaints,
    'explicitPaints': explicitPaints,
  };
}
