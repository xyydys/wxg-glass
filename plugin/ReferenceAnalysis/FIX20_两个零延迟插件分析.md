# FIX20：两个零延迟液态玻璃插件的做法

依据：用户上传的 `微信液态玻璃58.dylib`、`Liquidify.dylib`（arm64/arm64e）。只看字符串表中的类名、属性、选择子和日志，没有解除其授权或混淆。

## 微信液态玻璃58（wcliquidglass）

- 设置键：`WCLiquidGlassRefractionStrength`、`WCLiquidGlassBlurRadius`、`WCLiquidGlassColorOpacity`、`WCLiquidGlassUseClearMode`，以及导航按钮、输入栏、长按菜单、气泡、列表等开关。
- 视图：`CCLiquidGlassView`，属性有 `blurView`（UIVisualEffectView）、`manualBackdropView`、`backdropLayer`、`blurMaskView/Layer`、`tintView`、`tintGradientLayer`、`cachedBackdropBlurRadius`、`cachedBackdropFilterStyle`、`cachedMeshTransform`、`cachedMeshRefractionStrength`、`cachedMeshCornerRadius`、`cachedMeshUsesManualBackdrop`、`cachedSecureGlassStrings`（运行时解码私有名称）。
- 没有 Metal、CADisplayLink、drawViewHierarchy。结论：渲染服务背景层 + 滤镜 + 网格折射 + 色调/描边，无回读，无延迟；折射由网格整体位移实现，没有色散。

## Liquidify

- 包名 `com.charlieleung.liquidify`，进程 SpringBoard；作用于控制中心、主屏小组件、文件夹、灵动岛、音量 HUD、锁屏时钟等 SpringBoard 类。
- `CABackdropLayer`、`CAFilter filterWithName:`；滤镜 `gaussianBlur`（`inputRadius`、`inputNormalizeEdges`）、`colorBrightness`、`colorContrast`、`colorSaturate`（`inputAmount`）、`colorInvert`、`colorMatrix`（`inputColorMatrix`、`inputBackdropAware`）；键路径 `filters.gaussianBlur.inputRadius`。
- 网格：`meshTransform`、`subdivisionSteps`、深度归一化 `none`；日志 “meshTransform exists but the liquid glass label backdrop rejected it”“Private mesh transform unavailable; label edge refraction is not supported”。网格类名不以明文出现。
- 含设备标识与授权检查字符串。不适合也无法搬进微信：它挂的是 SpringBoard 的类；可借鉴的是方法。

## 对本项目的意义

渲染服务方案的延迟为零，但只能运行系统滤镜和网格变形。FIX20 用 TEST9 的形状场和折射曲线生成网格（偏差 0.27–0.56pt），并用第二层不模糊背景加 TEST9 清晰边权重遮罩还原清晰折射边；缺少的只有 RGB 色散。
