# 使用指南

## 初始化

启动时调用 `await KyantGlass.precache()`；使用渐变模糊时还可调用 `await KyantProgressiveBlur.precache()`。README 提供原生背景滤镜的最小示例。

## 显式背景

Web、显式路径和需要明确变换域的页面使用 Controller。以下片段沿用 README 的 Flutter 与 `kyant_glass` import，放在 `MaterialApp` / `Scaffold` 页面中：

```dart
class ExplicitGlassDemo extends StatefulWidget {
  const ExplicitGlassDemo({super.key});
  @override
  State<ExplicitGlassDemo> createState() => _ExplicitGlassDemoState();
}

class _ExplicitGlassDemoState extends State<ExplicitGlassDemo> {
  final _background = KyantBackdropController(captureOnNative: true);

  @override
  void dispose() {
    _background.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      KyantBackdropSource(
        controller: _background,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3557CE), Color(0xFFFFA66E)],
            ),
          ),
        ),
      ),
      Center(
        child: KyantGlass(
          backdrop: _background,
          pipeline: KyantPipeline.explicit,
          tint: const Color(0x40FFFFFF),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Explicit background'),
          ),
        ),
      ),
    ],
  );
}
```

Source 先绘制，消费者作为兄弟分支叠在其后。Controller 由创建它的页面释放。`captureOnNative: true` 开启原生显式捕获；Web 自动捕获。

通过 `captureHeight` / `captureBottomHeight` 约束区域时，保留透镜位移与模糊的采样边距。`maxCaptureWidth` 用于显式调整采样分辨率。保留子层动画通过 Source 的 `repaint` 接收驱动 `Listenable`，无需重新创建 Controller。

## 有序效果链

`effects` 替代快捷参数生成的默认链，按列表顺序处理：

```dart
KyantGlass(
  borderRadius: const BorderRadius.only(
    topLeft: Radius.circular(28),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(16),
    bottomRight: Radius.circular(28),
  ),
  effects: const [
    KyantColorControls.vibrancy(),
    KyantBlur(2),
    KyantLens(height: 16, amount: 10, dispersion: .35, depth: true),
  ],
  highlightStyle: const KyantHighlight.ambient(),
  shadow: const KyantShadow(),
  innerShadow: const KyantShadow.inner(),
  tint: const Color(0x40FFFFFF),
  child: const Padding(
    padding: EdgeInsets.all(24),
    child: Text('Ordered effects'),
  ),
)
```

颜色调整使用 `KyantColorControls` / `KyantColorFilter`，材质透明度使用 `KyantOpacity`。

## 控件

| 控件 | 参数与用途 |
|---|---|
| `LiquidButton` | `child`、`onPressed`，玻璃按钮 |
| `LiquidToggle` | `value`、`onChanged`，开关 |
| `LiquidSlider` | `value`、`onChanged`、`min`、`max`，可提供 `onChangeEnd` |
| `LiquidBottomTabs` | `tabs`、`selected`、`onChanged`、`tint`、`accent`、`foreground`，至少两个标签 |
| `KyantGlassControl` | `child`，为自定义内容添加按压和指针反馈 |

四个高层控件直接沿用原版 Catalog 名称。

控件通过 `backdrop` 或 `KyantBackdropScope` 接收背景。外部容器为按压和拖动形变留出空间，完整组合见 [画廊源码](../example/lib/main.dart)。

## 渐变模糊

```dart
const SizedBox(
  height: 120,
  child: KyantProgressiveBlur(
    sigma: 12,
    mode: KyantProgressiveMode.layered,
    layers: 4,
  ),
)
```

各模式与采样差异见 [渲染说明](RENDERING.md)。

## 诊断

`KyantRenderSettings` 为子树选择渲染路径。帧记录器按一次操作收集结果：

```dart
final recorder = KyantFrameRecorder();
recorder.start('glass-drag');
// 操作完成后读取结果。
final result = recorder.stop();
recorder.dispose();
```

画廊通过 `--dart-define=KYANT_BENCHMARK=true` 开启诊断面板。
