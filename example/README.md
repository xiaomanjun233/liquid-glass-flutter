# 独立效果画廊

`kyant_glass` 的独立 Android / Web 示例。使用 Flutter 3.47.5 / Dart 3.13.4，Android 使用 JDK 17。示例通过仓库内相对路径依赖库，使用随仓库提供的 AI 山湖风景背景。

```sh
flutter pub get
flutter run
flutter run -d chrome
```

画廊提供明暗主题、RTL、背景动画、渲染路径、背景组合 / 变换、色散 / 深度、渐变模糊模式与液态玻璃控件。

按需诊断：`flutter run --profile --dart-define=KYANT_BENCHMARK=true`，记录 Flutter 帧处理耗时。

```sh
flutter analyze
flutter test
flutter build web --release
flutter build apk --release --target-platform android-arm64
```

Android 预览使用开发签名。详见 [README](../README.md)、[使用指南](../docs/USAGE.md) 和 [渲染说明](../docs/RENDERING.md)。
