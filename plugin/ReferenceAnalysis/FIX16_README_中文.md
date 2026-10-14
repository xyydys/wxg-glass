# WeChat Liquid Glass · TEST4 FIX16

版本 `0.4.16-test4fix16`，基于 FIX15。本版只改背景取样的**时机、频率和路径**；折射、模糊、色散、透镜动画、按钮／输入栏布局、底栏返回策略和已有参数全部保留（`tools/audit_fix16_scope.py` 逐字节核对了 20 个光学／布局源文件与 FIX15 相同）。

## 为什么 FIX15 会卡、会“提前”显示背景

1. **主线程被同步读取占满。** FIX14 日志（A12、iOS 15.7、60Hz）里每次聊天取背景 26–79ms，中位 56ms：表格、壁纸、魔法表情背景各一次 `drawViewHierarchy`。这个调用的开销是固定成本加视图面积——空的全屏视图也要约 17ms，130×40pt 的小视图也要 3.9ms，裁剪区域不减少开销。0.9 Demo 每帧只读一次、上限 60Hz；FIX15 默认请求 120Hz 且明确“不插入冷却”，120Hz 机型上每 8.3ms 就读一次，于是微信自己的滚动、布局、动画提交都被挤掉，整个界面掉帧，不只是玻璃。
2. **FIX15 的 CPU 快速路径几乎用不上。** UILabel／drawRect 视图的像素在 `CABackingStore` 里，不是 CGImage，FIX15 把它们判为“特殊内容”退回原生读取；微信自定义 CALayer 子类也一律退回。聊天页几乎每个 cell 仍然走原生读取。判断过程还对每个子图层取 `presentationLayer`（每次复制一份）。
3. **“动画终点”画面。** 取样在 display link 回调里进行，这时 Core Animation 还没提交本轮改动。同一轮里刚开始的动画（键盘、push、插入消息）尚未提交，读 presentation layer 得到的是模型值，也就是动画终点。取样间隔 30–70ms，又让这张错误画面停留更久。

## FIX16 的修改

- **提交后取样。** display link 回调只做弹簧、几何、内容变换（随本轮一起提交）。背景读取与所有玻璃的复制／模糊／光学改到 run loop 的 BeforeWaiting／Exit 观察者里执行，顺序 2001500，排在 Core Animation 提交（2000000）和 UIKit 提交后处理（2001000）之后。此时 presentation layer 描述的就是屏幕上的状态。某次观察者没有运行时，下一次 display link 回调会先把上一帧补做（诊断 `postCommit.inlineFallbacks`）。
- **主线程预算。** 新设置“采样主线程占用上限 · %”，默认 35，范围 20–80。读取开销按平均值估计，下次读取至少间隔“开销 ÷ 占用上限”。读取便宜时仍按目标帧率；读取昂贵时拉长间隔，玻璃的透镜、按压动画仍然每帧绘制。新页面立即读取；玻璃移动导致覆盖区失效时上限放宽 25 个百分点。
- **CPU 路径放宽。** `CABackingStore` 内容和普通 CALayer 子类改用 `renderInContext`。只有视频、Metal/GL、毛玻璃（Backdrop）、Portal、远程／LayerHost、Emitter、Replicator、Tiled、带 filter／Effect 的类名，以及 3D 变换、合成滤镜，仍走 `drawViewHierarchy`。阴影不再强制原生读取。分类只读模型层，并按类缓存结果。
- **子图层动画保护。** 分支内部（根以下）有正在运行的动画时，可安全拆分的容器继续拆分，让动画图层成为独立分支；不可拆分的走原生读取。这样插入行、淡入淡出、转圈等不会被画成终点状态。

## 安装

把 ZIP 放到 `/var/mobile`：

```bash
cd /var/mobile && unzip -o WeChatLiquidGlass_0_4_16_TEST4_FIX16_flat.zip -d WeChatLiquidGlass_FIX16 && cd WeChatLiquidGlass_FIX16 && chmod +x build.sh && ./build.sh rootless
```

rootful 环境把最后的参数换成 `rootful`。替换旧主插件，完全退出再打开微信，确认设置标题为 FIX16。同一时间只加载一个主插件版本。

## 这轮请对照

1. 连续滚动首页和聊天：微信本身是否跟 0.9 Demo 一样顺。
2. 一边看输入栏玻璃一边收放键盘；发一条消息看新气泡插入时玻璃是否还会“先跳到终点”。
3. 把“采样主线程占用上限”分别设为 20 / 35 / 60 对比：越高背景越跟手，但微信越容易掉帧。
4. 异常时导出 FIX16 诊断。重点字段：
   - `runtime.postCommit`：`frames` 应持续增长，`inlineFallbacks` 应远小于 `frames`；
   - `backdrop.regions[].costAverageMS`、`measuredMainThreadShare`、`budgetHolds`：实际读取开销、主线程占比、被预算推迟的次数；
   - `layerReads` 与 `nativeReads`：本版目标是 `nativeReads` 明显下降；`slowBranches[].rasterGuard` 说明剩余原生读取的原因；
   - `animationSplits`：因子图层动画而进一步拆分的次数。

## 已知风险

- `renderInContext` 由 Core Animation 在 CPU 上绘制。如果某种微信内容在玻璃下缺失或颜色不对，说明它不适合 CPU 绘制；请截图并导出诊断，把 `slowBranches` 里对应的类名发出来，可以把它加入原生读取名单。
- 预算是平均占比，单次很贵的读取（比如刚切页的第一张）仍会占用一整次读取时间。

## 验证边界

本包未在本环境编译 Objective-C（环境没有 clang 和 iOS SDK），请以手机端 `./build.sh` 结果为准。已完成：32 个 C 策略／几何测试（含新增主线程预算测试）、全部源文件括号结构检查、FIX15→FIX16 范围审计。实际帧率、键盘／插入动画是否完全同步、特殊媒体是否完整，需要真机确认。详见 `VALIDATION.md`。
