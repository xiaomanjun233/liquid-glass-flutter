import 'dart:ui' as ui;

final _loaded = <String, ui.FragmentProgram>{};
final _loading = <String, Future<ui.FragmentProgram>>{};

ui.FragmentProgram? cachedKyantProgram(String file) => _loaded[file];

/// Apps use package asset keys; tests run inside this package use local keys.
Future<ui.FragmentProgram> loadKyantProgram(String file) =>
    _loading.putIfAbsent(file, () => _load(file));

Future<ui.FragmentProgram> _load(String file) async {
  late final ui.FragmentProgram program;
  try {
    program = await ui.FragmentProgram.fromAsset(
      'packages/kyant_glass/shaders/$file',
    );
  } catch (_) {
    program = await ui.FragmentProgram.fromAsset('shaders/$file');
  }
  return _loaded[file] = program;
}
