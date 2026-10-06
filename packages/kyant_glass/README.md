# kyant_glass

将 [Kyant](https://github.com/Kyant0) 的 [AndroidLiquidGlass / Backdrop 2.0.0](https://github.com/Kyant0/AndroidLiquidGlass/tree/2.0.0) 适配到 Flutter，采用 Apache-2.0 许可证。

包含圆角折射、深度、七组色散、有序颜色 / 高斯效果、三类高光、阴影、显式背景与液态玻璃 Button / Toggle / Slider / BottomTabs。

```dart
import 'package:kyant_glass/kyant_glass.dart';

// WidgetsFlutterBinding.ensureInitialized() 后、runApp 前预热：
await KyantGlass.precache();
```

支持 Shader ImageFilter 的原生环境直接在已绘制内容上使用 `KyantGlass`。Web 或显式路径提供兄弟分支的 `KyantBackdropSource`，页面释放时销毁其 Controller。背景采样与变换细节见渲染说明。

完整内容见 [仓库 README](https://github.com/xiaomanjun233/liquid-glass-flutter)、[使用指南](https://github.com/xiaomanjun233/liquid-glass-flutter/blob/main/docs/USAGE.md)、[渲染说明](https://github.com/xiaomanjun233/liquid-glass-flutter/blob/main/docs/RENDERING.md) 和独立 `example/`。

原始算法与 Catalog 交互：Copyright 2025 Kyant。Flutter 改编：Copyright 2026 xiaomanjun233 and contributors。许可与修改声明见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。
