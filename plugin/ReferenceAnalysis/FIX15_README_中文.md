# WeChat Liquid Glass · TEST4 FIX15

版本 `0.4.15-test4fix15`，基于 FIX14。本次修改背景取样路径和设置半屏期间的刷新；折射、模糊、色散、透镜动画、按钮／输入栏布局、底栏返回策略及已有参数保留。

## 新诊断确认的问题

这次上传的是 FIX14、iOS 15.7、最高 60Hz 的设备日志。去除重复的最后快照后有 15 个场景样本。聊天样本中，每次取背景约 26–79ms，中位数约 56ms；常见的一轮分别截图整屏 MMTableView、壁纸 UIImageView、额外背景层，合计读取面积为屏幕的三倍。大部分主线程时间用在这些读取里，调成 120 的请求值无法消除阻塞，也不能让 60Hz 屏幕变成 120Hz。

FIX14 遇到表格的 CALayer 顺序与 UIView 顺序不同，就放弃继续拆分，回到整张表格截图。这不是视频等特殊内容的需要。另一方面，FIX14 打开自身设置或其他模态页面时明确暂停 display link，因此设置半屏缩放／拖动中的冻结有直接的代码原因。日志没有显示取样失败或缓冲耗尽是这些样本的主要原因。

## TEST9 原本怎样做

本次重新核对了上传的 TEST9 工程：它也重复取得背景图像，使用 drawViewHierarchyInRect:afterScreenUpdates:NO 把背景画进可复用的 shared Metal buffer，再由 GPU 做高斯模糊和折射。默认及可设置上限为 60Hz，display link 也是 60Hz。它不是直接拿到系统合成器的实时纹理，更不是存一张旧图一直显示。

Demo 通常只有一个底栏、一个背景源、一次读取；完整插件需要多处玻璃，还必须排除玻璃自身，不能把 Demo 的根视图截图原封不动套上去，否则会采到玻璃自己。相关函数与证据在 ReferenceAnalysis/TEST9_FIX15_sampling_review.md 和 Validation/fix15_diagnostic_evidence.json。

## FIX15 的修改

- 普通二维图层每个采样周期从当前 presentation layer／尚未上屏时的 model layer 重新绘制到原有 Metal 共享缓冲区，减少普通消息、文字、图片反复经过 UIKit 同步截图的开销。没有缓存某个页面的图像来替代后续取样，也没有暂停滚动或转场取样。
- 容器按实际 CALayer.sublayers 顺序及当前 zPosition 处理；相同 z 保留原顺序。表格可继续拆到与玻璃取样区域相交的消息／列表分支。
- 每次读取都检查当前子图层。视频、Metal、远程图层、未知图层、合成滤镜、阴影、非二维变换、特殊 contents 等继续走原生读取；不把它们当作普通空图层。这里仍然是 CPU 取背景、GPU 算光学，不声称实现了系统内部的零拷贝材质管线。
- 设置半屏打开、缩放和拖动时保持已有玻璃持续取样。布局修复和点击仍暂停，避免改动前台设置的视图；应用失活、控制中心和进入后台时仍保留原暂停保护。
- 保留原来的三缓冲租约、GPU 复制、完整取样覆盖检查和显示频率策略。没有为凑帧率改掉模糊半径、折射强度、输出画布，也没有偷偷恢复早期修改原生层级再截图的路径。

## 安装与反馈

替换旧主插件，完全退出再打开微信，确认标题为 FIX15。dylib 用于已有注入方式；越狱环境按 rootful／rootless 选择对应 deb，同一时间只加载一个主插件版本。保留既有参数即可；本版不需要升级 WGP4.3 探针。

先看三个短场景：连续滚动首页／聊天；一边看玻璃一边收放键盘；拖动自身设置半屏，观察后面的玻璃是否同步。异常时直接导出 FIX15 诊断，不用重跑整个探针流程。

诊断新增 liveSamplingAtExport，与打开设置前的场景证据分开。backdrop.regions 的 currentLayerMS、nativeHierarchyMS、layerReads、nativeReads 显示取样成本；slowBranches.backend/rasterGuard 显示剩余原生读取的原因；glassFrames 的 presentIntervalMS、presentedBackdropAgeMS、gpuMS 显示上屏间隔、背景年龄与 GPU 时间。coveredRenderFrames 用来检查半屏期间是否仍在刷新。上述是实际运行后记录的值，samplingCap 只是上限。

本环境不能运行微信／UIKit／Metal 真机。本包完成交叉编译和回归检查；实际帧率、特殊媒体是否完整以及半屏取样坐标仍需真机验证，未声称 FIX15 已满帧。完整检查见 VALIDATION.md，旧版报告只供历史追溯。

自行编译：配置 THEOS 后运行 ./build.sh rootless 或 ./build.sh rootful。
