# 液态玻璃 Flutter

一套可自定义的 Flutter 液态玻璃效果库，基于 **[Kyant](https://github.com/Kyant0)** 的 [AndroidLiquidGlass / Backdrop 2.0.0](https://github.com/Kyant0/AndroidLiquidGlass/tree/2.0.0) 移植。

通过背景折射、高斯模糊、色散、高光与阴影表现玻璃的厚度和光感，结合弹簧与阻尼拖动，让按钮、开关、滑块和底部标签随触摸产生柔性反馈。

当前包名 `kyant_glass`，版本 `0.2.0-dev.1`，使用 Flutter 3.47.5 / Dart 3.13.4。

## 文档

- [使用指南](docs/USAGE.md)：背景源、效果链、控件和诊断。
- [渲染说明](docs/RENDERING.md)：原生滤镜、显式采样、坐标与渐变模糊。
- [来源与改编](docs/SOURCES.md)：上游文件与 Flutter 实现的对应关系。
- [Kyant 原版文档](https://kyant.gitbook.io/backdrop)：原始液态玻璃库的设计与效果介绍。

## 组件

原版通过 Catalog 展示高层组件。本项目将这些交互示例改编成可直接使用的 Flutter 控件：

| 组件 | 用途 |
|---|---|
| [`KyantGlass`](packages/kyant_glass/lib/src/surface.dart) | 可配置效果链的玻璃表面 |
| [`KyantLiquidButton`](packages/kyant_glass/lib/src/controls.dart) | 带按压形变和指针高光的按钮 |
| [`KyantLiquidToggle`](packages/kyant_glass/lib/src/controls.dart) | 带弹簧反馈的开关 |
| [`KyantLiquidSlider`](packages/kyant_glass/lib/src/controls.dart) | 带阻尼拖动与形变的滑块 |
| [`KyantLiquidTabs`](packages/kyant_glass/lib/src/liquid_tabs.dart) | 外壳与内部移动透镜组成的底部标签 |
| [`KyantGlassControl`](packages/kyant_glass/lib/src/interaction.dart) | 为自定义内容添加柔性反馈 |

玻璃表面支持四角独立圆形半径、折射深度、七组色散、颜色 / vibrancy、三类高光与内外阴影。效果链按列表顺序组合。

## 演示

独立画廊提供明暗主题、RTL、动态背景、渲染路径切换、色散与深度调节，以及全部玻璃控件。背景由程序绘制。

```sh
git clone https://github.com/xiaomanjun233/liquid-glass-flutter.git
cd liquid-glass-flutter/example
flutter pub get
flutter run
# Web
flutter run -d chrome
```

Android 使用 JDK 17。示例源码见 [`example/lib/main.dart`](example/lib/main.dart)。

## 接入 Flutter

在 `pubspec.yaml` 中加入 Git 依赖；`ref` 也可以固定为具体提交 SHA：

```yaml
dependencies:
  kyant_glass:
    git:
      url: https://github.com/xiaomanjun233/liquid-glass-flutter.git
      ref: main
      path: packages/kyant_glass
```

启动时预热 Shader：

```dart
import 'package:flutter/material.dart';
import 'package:kyant_glass/kyant_glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await KyantGlass.precache();
  runApp(const MyApp());
}
```

在已经绘制的背景上放置玻璃表面：

```dart
KyantGlass(
  radius: 28,
  blur: 2,
  refractionHeight: 16,
  refractionAmount: 10,
  dispersion: .35,
  tint: const Color(0x40FFFFFF),
  child: const Padding(
    padding: EdgeInsets.all(24),
    child: Text('液态玻璃'),
  ),
)
```

Web 使用 `KyantBackdropSource` 提供背景图像；完整页面示例见 [使用指南](docs/USAGE.md)。

## Flutter 移植工作

- **光学 Shader**：将 Kyant 的 AGSL 圆角距离场、折射、深度、七组色散与高光改编为 Flutter GLSL / sampler2D；加入 GLES 纹理方向与坐标适配，零色散使用等效单采样。
- **滤镜链**：接入 Flutter 的颜色、高斯与 Shader ImageFilter，提供复合滤镜、分离滤镜对照和显式图像三条路径。
- **背景系统**：实现 Layer、Canvas、Combined、Empty、Transformed 输入，管理采样域、仿射变换、背景更新与图像释放。
- **交互控件**：将 Catalog 的按压、指针高光、弹簧形变和阻尼拖动接入 Flutter，加入键盘与语义支持，保留 BottomTabs 外壳和内部透镜的采样顺序。
- **绘制与缓存**：高光由 Shader 绘制；预热并缓存 FragmentProgram，每个表面持有独立 FragmentShader；保留稳定内容，减少动画重建。
- **渐变模糊扩展**：提供共享输入的分段高斯与较少层数的插值 / 遮罩模式，方便比较视觉效果与渲染成本。
- **独立工程**：整理库、画廊、渲染 / 几何 / 交互测试和 CI，应用通过依赖接入。

原生路径可直接消费已绘制背景，显式路径通过绘制后的背景图像采样。两者的时序和变换支持见 [渲染说明](docs/RENDERING.md)。

## 开发与验证

```sh
cd packages/kyant_glass
flutter pub get
flutter analyze
flutter test
cd ../../example
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --release --target-platform android-arm64
```

CI 执行分析、测试和示例构建。通过 `flutter run --profile --dart-define=KYANT_BENCHMARK=true` 开启画廊的帧耗时诊断。贡献方式见 [贡献指南](CONTRIBUTING.md)。

## 作者与许可

原始液态玻璃算法与 Catalog 交互由 **Kyant** 创作，Copyright 2025 Kyant。Flutter 移植与扩展由 [xiaomanjun233](https://github.com/xiaomanjun233) 及贡献者维护。

采用 **Apache License 2.0**。上游许可证原文保存在 [LICENSE](LICENSE)，作者与修改声明见 [NOTICE](NOTICE)，详细来源见 [SOURCES](docs/SOURCES.md)。Flutter 模板许可见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES)。
