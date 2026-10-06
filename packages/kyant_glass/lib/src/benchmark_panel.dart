import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'diagnostics.dart';
import 'material.dart';

/// Opt-in benchmark controls. Recording itself never rebuilds this panel.
class KyantBenchmarkPanel extends StatefulWidget {
  const KyantBenchmarkPanel({
    super.key,
    required this.child,
    this.enabled = false,
    this.autoRun = false,
    this.scrollKey,
    this.onResults,
    this.onRunning,
    this.initialProgressiveBands = 64,
  });
  final Widget child;
  final bool enabled;
  final bool autoRun;
  final int initialProgressiveBands;
  final Key? scrollKey;
  final Future<void> Function(String json)? onResults;
  final Future<void> Function(bool running)? onRunning;
  @override
  State<KyantBenchmarkPanel> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<KyantBenchmarkPanel> {
  final _recorder = KyantFrameRecorder();
  String _scenario = 'home_scroll', _phase = 'warm', _result = '';
  bool _recording = false, _stopping = false;
  bool _disableGlass = false;
  late int _bands = widget.initialProgressiveBands;
  KyantPipeline _pipeline = KyantPipeline.composed;
  bool _automatic = false, _cancel = false;
  String _progress = '';
  @override
  void initState() {
    super.initState();
    if (widget.enabled && widget.autoRun) {
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) _runAutomatic();
      });
    }
  }

  ScrollPosition? _scrollPosition() {
    ScrollPosition? result;
    void visit(Element element, bool selected) {
      if (element.widget case Offstage(offstage: true)) return;
      selected = selected || element.widget.key == widget.scrollKey;
      if (selected &&
          element is StatefulElement &&
          element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final position = state.position;
        if (axisDirectionToAxis(position.axisDirection) == Axis.vertical &&
            position.hasContentDimensions &&
            position.maxScrollExtent > 0) {
          result ??= position;
        }
      }
      element.visitChildren((child) => visit(child, selected));
    }

    (context as Element).visitChildren(
      (child) => visit(child, widget.scrollKey == null),
    );
    return result;
  }

  Future<void> _runAutomatic() async {
    if (_recording || _automatic) return;
    final original = (_bands, _disableGlass, _pipeline);
    final results = <Map<String, Object>>[];
    setState(() {
      _automatic = true;
      _cancel = false;
      _progress = '准备滚动对照';
    });
    try {
      await widget.onRunning?.call(true);
      final position = _scrollPosition();
      if (position == null) throw StateError('未找到可滚动的测试首页');
      final distance = position.maxScrollExtent.clamp(0.0, 1200.0);
      Future<void> sweep(int cycles) async {
        for (var i = 0; i < cycles && mounted && !_cancel; i++) {
          await position.animateTo(
            distance,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          );
          if (!mounted || _cancel) return;
          await position.animateTo(
            0,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          );
        }
      }

      const cases = [
        (64, false),
        (0, false),
        (64, true),
        (0, true),
        (-8, false),
        (-16, false),
        (64, false),
      ];
      for (var i = 0; i < cases.length && mounted && !_cancel; i++) {
        final config = cases[i];
        setState(() {
          _bands = config.$1;
          _disableGlass = config.$2;
          _pipeline = KyantPipeline.composed;
          _progress =
              '对照 ${i + 1}/${cases.length} · ${_bands < 0 ? '融合${-_bands}' : '顶栏$_bands'} · 玻璃${_disableGlass ? '关' : '开'}';
        });
        await WidgetsBinding.instance.endOfFrame;
        position.jumpTo(0);
        await sweep(1);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted || _cancel) break;
        _recorder.start(
          'automatic_scroll/warm/composed/bands=$_bands/glass=${!_disableGlass}/run=$i',
        );
        await sweep(2);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        final result = _recorder.stop();
        result['scrollDistanceLogical'] = distance;
        result['cancelled'] = _cancel;
        results.add(result);
        debugPrint('KYANT_BENCHMARK ${jsonEncode(result)}', wrapWidth: 2000);
        await widget.onResults?.call(jsonEncode(results));
      }
      if (mounted) {
        setState(() {
          _result = const JsonEncoder.withIndent('  ').convert(results);
          _progress = _cancel ? '已取消，已保存完成的采样' : '对照完成，已保存 ${results.length} 组';
        });
      }
    } catch (error, stack) {
      debugPrint('KYANT_BENCHMARK_ERROR $error\n$stack');
      if (mounted) setState(() => _progress = '采样失败：$error');
    } finally {
      _recorder.stop();
      await widget.onRunning?.call(false);
      if (mounted) {
        setState(() {
          _automatic = false;
          _bands = original.$1;
          _disableGlass = original.$2;
          _pipeline = original.$3;
        });
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      setState(() => _stopping = true);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final result = _recorder.stopJson();
      debugPrint('KYANT_BENCHMARK $result', wrapWidth: 1000);
      setState(() {
        _result = result;
        _recording = false;
        _stopping = false;
      });
    } else {
      setState(() => _recording = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _recording) {
          _recorder.start(
            '$_scenario/$_phase/${_pipeline.name}/bands=$_bands/glass=${!_disableGlass}',
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      children: [
        KyantRenderSettings(
          pipeline: _pipeline,
          debugDisableGlass: _disableGlass,
          debugProgressiveBands: _bands,
          child: widget.child,
        ),
        Positioned(
          right: 8,
          top: MediaQuery.paddingOf(context).top + 4,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_recording && !_automatic) ...[
                    _CycleChoice<String>(
                      value: _scenario,
                      items: [
                        for (final value in const [
                          'home_scroll',
                          'dock_drag',
                          'post_reverse',
                          'search',
                          'comments',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _scenario = v!),
                    ),
                    _CycleChoice<String>(
                      value: _phase,
                      items: [
                        for (final v in const ['cold', 'warm'])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) => setState(() => _phase = v!),
                    ),
                  ],
                  TextButton(
                    onPressed: _automatic
                        ? () => setState(() => _cancel = true)
                        : _stopping
                        ? null
                        : _toggle,
                    child: Text(
                      _automatic
                          ? '取消对照'
                          : _stopping
                          ? '等待帧报告'
                          : _recording
                          ? '停止采样'
                          : '开始采样',
                    ),
                  ),
                  if (_result.isNotEmpty && !_recording && !_automatic)
                    IconButton(
                      tooltip: '复制 JSON',
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _result)),
                      icon: const Icon(Icons.copy, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!_recording && !_automatic)
          Positioned(
            right: 8,
            top: MediaQuery.paddingOf(context).top + 54,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CycleChoice<int>(
                    value: _bands,
                    items: [
                      for (final n in [64, 16, 4, 0, -1, -4, -8, -16])
                        DropdownMenuItem(
                          value: n,
                          child: Text(n < 0 ? '融合 ${-n}' : '顶栏 $n'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _bands = v!),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _disableGlass = !_disableGlass),
                    child: Text(_disableGlass ? '玻璃关' : '玻璃开'),
                  ),
                  _CycleChoice<KyantPipeline>(
                    value: _pipeline,
                    items: [
                      for (final p in KyantPipeline.values)
                        DropdownMenuItem(value: p, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _pipeline = v!),
                  ),
                ],
              ),
            ),
          ),
        if (!_recording)
          Positioned(
            right: 8,
            top: MediaQuery.paddingOf(context).top + 106,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              child: _automatic
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(_progress),
                    )
                  : TextButton(
                      onPressed: _runAutomatic,
                      child: Text(_progress.isEmpty ? '自动滚动对照' : _progress),
                    ),
            ),
          ),
      ],
    );
  }
}

/// MaterialApp.builder sits above Navigator/Overlay. A diagnostic selector must
/// not try to push a popup route from that context.
class _CycleChoice<T> extends StatelessWidget {
  const _CycleChoice({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((item) => item.value == value);
    return TextButton(
      onPressed: () => onChanged(items[(index + 1) % items.length].value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [items[index].child, const Icon(Icons.arrow_right, size: 18)],
      ),
    );
  }
}
