# TEST9 与 FIX14／FIX15 的取样路径

依据本次上传的 WGLiquidDockDemo_0.9_TEST9_flat.zip，没有根据早期说明猜测 Demo 行为。附件 SHA-256 记录在 Validation/fix15_diagnostic_evidence.json。

- Sources/WGLGlassView.m 的 newFrame（约 281 行）创建共享 MTLBuffer、使用同一块内存的 CGContext 和 Metal texture，备用上传路径只在 linear texture 不可用时使用。
- drawSource:inContext:（约 300 行）把玻璃区域换算到 source 坐标，调用一次 drawViewHierarchyInRect:afterScreenUpdates:NO；失败时使用 renderInContext。
- capture（约 310 行）使用最多三个可复用缓冲，直接画背景；不存在每帧 UIImage → MTKTextureLoader 的中间拷贝。校准图开启时还有一个可选来源。
- tick:（约 345 行）根据 captureFPS 重取背景，再调用 GPU 绘制；WGLDemoBar.m 的 display link 指定 60Hz，WGLConfig.m 的 captureFPS 默认及上限也为 60。
- WGLHost.m 的 Demo 挂在 window，背景来自独立内容 view，避免捕获自身；设置显示时该 Demo 隐藏／暂停，不能把它视为已经验证过半屏背景取样的实现。

FIX14 已经使用共享 Metal buffer，但使用多个原生 UIView 子树截图来重建干净背景。在这次日志里，三个完整屏幕分支分别耗时，造成主线程阻塞。FIX15 对普通当前图层使用 CA 二维绘制，保留实际 layer 顺序、presentation 坐标、原生特殊图层读取和同一个共享 Metal/GPU 光学链路。

没有把 TEST9 源代码新增导入主插件：本版主要改的是现有 WXGBackdrop.m 和 WXGHost.m。所有原光学、运动与完整分辨率 Gaussian 源码均与 FIX14 保持一致；检查也再次使用本次上传的 Demo，而非只对照旧存档。

限制：renderInContext 不是系统渲染服务的零拷贝输出。它是否在该微信／主题组合里保留全部普通图层的画面与正确时序，需要真机确认。特殊层的 guard 每帧检查，不使用旧的分类结果或旧纹理绕过更新。原生读取失败或三缓冲都被 GPU 占用时才保留上一个有效画面，并记录失败／busy 指标。
