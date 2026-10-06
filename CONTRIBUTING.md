# 贡献指南

欢迎提交可复现的问题、文档和渲染修复。请先阅读 [README](README.md) 与 [渲染说明](docs/RENDERING.md)。

使用 Flutter 3.47.5 / Dart 3.13.4，Android 使用 JDK 17。在 `packages/kyant_glass` 和 `example` 分别执行 `flutter pub get`、`flutter analyze`、`flutter test`。修改 Shader 后还需构建示例，验证真实 Shader 编译。

- 问题报告包含 Flutter 版本、平台、渲染器、最小复现、预期与实际行为。
- 光学改动使用棋盘格、细文字或条纹背景，说明圆角、像素密度、变换和明暗主题。
- 性能改动注明 Profile / Release 模式、设备、场景、预热情况与测量方法，分别报告 UI、raster 和实际呈现。
- 保持背景生产者与消费者关系清晰；不要引入自采样或静止时持续调度。
- 提交前检查差异，仅包含与改动有关的公开源码、测试或文档。

请勿提交凭证、个人或设备日志、签名文件、本机配置、APK、内部记录或未授权素材。

贡献按 Apache-2.0 提供。改编第三方代码时保留原版权、许可与来源，并说明修改。
