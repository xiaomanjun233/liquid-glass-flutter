# 渲染说明

## 渲染路径

| 路径 | 输入与用途 |
|---|---|
| `KyantPipeline.composed` | 默认路径，将颜色、高斯和透镜组织为有序复合滤镜 |
| `KyantPipeline.legacy` | 分离背景滤镜，用于效果与成本对照 |
| `KyantPipeline.explicit` | 使用明确的背景图像及变换矩阵，适合 Web、组合背景和复杂采样域 |

`KyantGlass.supportsLiveRefraction` / `KyantCapabilities.liveBackdrop` 查询运行时是否支持 Shader ImageFilter。能力不足时，提供显式背景即可使用图像折射；没有背景图像的兼容路径显示模糊与装饰。

## 背景与坐标

`KyantBackdropSource` 捕获其子树，消费者在随后使用新图像，因此显式路径有捕获延迟。生产者与消费者放在兄弟分支，按顺序绘制。背景中的保留子层仅发生重绘或合成变换时，通过 `repaint` 提供驱动动画 / 滚动的 `Listenable`。这仍是显式约定：不会为了检测所有后代变化而在静止时轮询截图。

背景源自身与玻璃消费者的祖先只发生保留层位移时，会检测全局变换变化。源更新捕获坐标；消费者在合成结束后请求一次重绘来更新采样映射，因此该修正仍可能延迟一帧，不是同帧采样。嵌套源构建快照时不会反向触发源捕获；尺寸、DPR、源替换与释放会更新或取消对应的捕获任务。

Combined 背景按列表顺序叠加；Empty 背景提供空输入；Transformed 背景补偿 2D affine 变换。透视投影尚未实现。

原生 Shader ImageFilter 提供输入尺寸，但不自动提供任意祖先离屏纹理的原点。`textureOrigin` 用于已知原点；复杂 `Opacity`、缩放、旋转和 saveLayer 场景可以改用明确的显式背景域。

## 光学与形状

四角使用独立的圆形半径。折射、深度与七组色散改编自上游 2.0.0；关闭色散时走等效单采样。高光由 Shader 绘制，支持 Plain、Directional、Ambient，阴影使用高斯遮罩和独立混合参数。

当前形状为圆角矩形，椭圆圆角和自定义 SDF 尚未实现。Toggle / Slider 的原生轨道采样与显式变换轨道存在差异，BottomTabs 已提供完整控件，独立 BottomTab 公共组件尚未拆出。

## 渐变模糊

| 模式 | 实现 |
|---|---|
| `separate` | 不相交高斯分段，背景输入分离 |
| `shared` | 同样的分段轮廓，复用同源输入；默认 64 段 |
| `interpolated` | 从显式背景混合四级高斯 |
| `layered` | 1–32 层高斯与连续遮罩；默认 8 层 |

分层与插值通过近似换取较少滤镜组。较少层数会改变中段模糊分布；单层是固定模糊叠加透明度遮罩。可在画廊中使用细文字、条纹和动态背景比较。

## Web 图像链与采样成本

显式路径保留完整的效果顺序。连续的颜色、透明度和高斯效果由 `ImageFilter.compose` 合成一个输入阶段；链末尾的透镜直接绘制到消费者 Canvas，不再生成透镜输出快照。典型 `vibrancy → blur → lens` 每次缓存失效需要 **2 张局部中间图像**（裁剪输入、复合滤镜输出），原实现需要 4 张。背景源本身的共享快照另计。透镜后还有效果时仍保留中间图像，不能交换高斯与透镜的顺序。

缓存键包含背景对象与版本、坐标映射、尺寸、DPR、效果参数和圆角；只改变 child 或重建等值效果列表不会丢弃缓存。这里统计的是应用层 `ui.Image` 创建次数，不等于 GPU pass 数量，也不是帧率保证。

`toImageSync` 不代表零拷贝或纯 GPU。库没有调用 `toByteData`、PNG 编码或 Dart 逐像素处理，但 CanvasKit 的具体引擎版本可能在快照实现中进行 `readPixels` 与重新创建图像。应结合实际 Flutter 版本和浏览器测量，不能仅凭 Dart API 名称判断采样成本。参考 [Flutter CanvasKit picture 实现](https://github.com/flutter/flutter/blob/3.47.5/engine/src/flutter/lib/web_ui/lib/src/engine/canvaskit/picture.dart)。

任意 Widget 子树仍需要在绘制后生成共享背景图像，下一帧消费，`explicitBackdropIsSameFrame` 仍为 `false`。降低 `frameInterval` 无法消除这条管线的延迟；默认已经是 `Duration.zero`。`pixelRatio` / `maxCaptureWidth` 和区域裁剪是明确的质量选项，不会自动降低画质。只需显示图片或可直接绘制的背景时，可以用显式图像 / Canvas 背景避免每帧捕获整个 Widget 树。

`flutter build web --release --wasm` 可用于比较 skwasm 与 CanvasKit 的实际表现，但不会启用 Web 的 `ImageFilter.shader` 能力，也不保证快照零成本。真正的同帧任意背景纹理采样需要引擎支持或另一套渲染架构；本次修改没有引入引擎私有接口。

## 性能测量

程序预热缓存 FragmentProgram，每个表面分别持有 FragmentShader。固定内容保留，交互更新几何和材质。复合滤镜可能仍产生多个 GPU pass；整页缩放和组透明度可能扩大离屏输入。

`KyantFrameRecorder` 记录 build / raster / totalSpan 分位数，不主动请求动画帧。`totalSpan` 包含管线延迟；库资源计数覆盖应用可见图像，完整 GPU 分配和屏幕呈现由引擎 / 系统工具测量。

## 平台

仓库提供 Android 和 Web 示例宿主。Android 以运行时 Shader ImageFilter 能力选路，Web 使用显式图像路径。iOS 的构建与真机验证待补充。当前实现使用标准 Flutter 接口，Flutter GPU 后端与引擎补丁尚未加入。
