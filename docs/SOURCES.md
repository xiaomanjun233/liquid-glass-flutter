# 来源与改编

原作者：[Kyant / Kyant0](https://github.com/Kyant0)。上游：[AndroidLiquidGlass / Backdrop](https://github.com/Kyant0/AndroidLiquidGlass)。基线：`2.0.0`，提交 `bebb11a91bd97bf1dabde479f3b332ad9898731f`，Apache-2.0，Copyright 2025 Kyant。

## 对应关系

下列链接固定到基线提交。Flutter 文件对算法和交互进行改编，背景生命周期、渲染接口与控件树使用 Flutter 实现。

| 上游来源 | Flutter 对应内容 |
|---|---|
| [internal/Shaders.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt) | `kyant_lens.frag`、`kyant_highlight.frag` 的圆角距离场、折射、深度、色散与高光 |
| [effects](https://github.com/Kyant0/AndroidLiquidGlass/tree/bebb11a91bd97bf1dabde479f3b332ad9898731f/backdrop/src/commonMain/kotlin/com/kyant/backdrop/effects) | `material.dart` 的颜色、高斯、透镜与有序效果链 |
| [highlight](https://github.com/Kyant0/AndroidLiquidGlass/tree/bebb11a91bd97bf1dabde479f3b332ad9898731f/backdrop/src/commonMain/kotlin/com/kyant/backdrop/highlight) | `material.dart`、`decorations.dart` 与高光 Shader |
| [shadow](https://github.com/Kyant0/AndroidLiquidGlass/tree/bebb11a91bd97bf1dabde479f3b332ad9898731f/backdrop/src/commonMain/kotlin/com/kyant/backdrop/shadow) | `material.dart`、`decorations.dart` 的内外阴影 |
| [LiquidButton.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidButton.kt) | `controls.dart`、`interaction.dart` 的按钮与按压反馈 |
| [LiquidToggle.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidToggle.kt) | `controls.dart` 的开关 |
| [LiquidSlider.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidSlider.kt) | `controls.dart` 的滑块 |
| [LiquidBottomTabs.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/components/LiquidBottomTabs.kt) | `liquid_tabs.dart` 的外壳、移动透镜与标签交互 |
| [DampedDragAnimation.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/utils/DampedDragAnimation.kt) | `interaction.dart`、`liquid_tabs.dart`、`controls.dart` 的弹簧与阻尼拖动 |
| [InteractiveHighlight.kt](https://github.com/Kyant0/AndroidLiquidGlass/blob/bebb11a91bd97bf1dabde479f3b332ad9898731f/app/src/commonMain/kotlin/com/kyant/backdrop/catalog/utils/InteractiveHighlight.kt) | `interaction.dart` 的指针高光 |

## Flutter 改编

AGSL 改为 Flutter GLSL / sampler2D；加入 Flutter 坐标、GLES 方向适配、仿射采样、独立 Shader 实例、滤镜组合、背景捕获 / 合成与资源管理。交互接入 Flutter 指针、动画、键盘及语义接口。

渐变高斯实验、帧记录器、诊断、独立画廊和测试为本项目新增代码。`flutter_liquid_glasses`、`liquid_glass_renderer`、`just_liquid_glass` 是渲染组织的研究参考，本包未复制其代码或将其加入依赖。

## 许可文件

根目录及包目录的 `LICENSE` 保留上游许可证原文。`NOTICE` 记录作者与移植修改。改编文件头保留 Kyant 版权并标明 Flutter 修改；Flutter 模板的 BSD 许可见 `THIRD_PARTY_NOTICES`。

## 演示图片

示例背景 `example/assets/landscape.webp` 由 OpenAI imagegen 生成，画面为简洁的山湖风景。README 展示图来自使用该背景的真实 Flutter Web 画廊截图。

生成提示词：

> Generate one calm, simple panoramic landscape: a clear turquoise alpine lake, distant rounded mountain silhouettes, soft pale blue sky and a few airy clouds, gentle morning light. Large quiet color areas, low visual clutter, subtle natural details, modern clean travel photography. Wide horizontal composition, landscape only. Keep the center spacious and readable for translucent controls. No people, buildings, UI, typography, logos or watermark.
