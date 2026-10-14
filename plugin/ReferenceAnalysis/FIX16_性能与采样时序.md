# FIX16：卡顿与“动画终点”背景的原因

依据：本次上传的 WGLiquidDockDemo_0_9_TEST9_flat.zip、WeChatLiquidGlass_0_4_15_TEST4_FIX15_flat.zip，以及其中 Validation/fix15_diagnostic_evidence.json（FIX14 实机日志摘要）、fix13_log_evidence.json。

## Demo 0.9 与 FIX15 的差别

| | 0.9 TEST9 Demo | FIX15 |
| --- | --- | --- |
| 每次取样的原生读取 | 1 次（整个源视图） | 每个未拆分分支 1 次；聊天页常见 3 次全屏，或多个 cell 各 1 次 |
| display link / 取样上限 | 60 Hz / 60 Hz | 设备最高（120） / 默认 120，且不插冷却 |
| 取样时刻 | display link 回调内 | display link 回调内（CA 提交前） |
| 玻璃数量 | 1 个底栏 | 导航按钮、标题、输入栏、底栏、装饰等多处 |

## 日志中的开销特征（FIX14，A12，iOS 15.7，60 Hz，atlas 1x）

- 聊天取样 26–79 ms，中位 56 ms；`tickCPUms` 与取样耗时几乎相等，即主线程时间几乎全部用于读取。
- 全屏 `MMTableView` 15–32 ms，全屏壁纸 `UIImageView` 8–28 ms，全屏空背景 `MagicEmojiImplicitBackgroundView` 5–29 ms，130×40 的 `MMEdgeTipsView` 3.9 ms。
- atlas 已降到 1x，全屏读取仍约 17 ms：`drawViewHierarchy` 的开销来自原生合成器按视图面积渲染，与 CGContext 的缩放和裁剪基本无关。
- FIX12 日志：首页玻璃实际呈现 12–40 Hz，`presented_backdrop_age_ms` 中位 33–48 ms。

## 终点画面的机制

CADisplayLink 回调和触摸、键盘通知等处理处在同一个 run loop 周期里，Core Animation 在本周期的 BeforeWaiting 才提交。回调运行时，本周期里刚添加的动画还没有开始时间，presentation layer 返回模型值（动画终点）；而原生读取得到的是渲染服务已提交的旧状态。同一张取样里可能混入两种时间点的内容。读取一次 30–70 ms，这张画面会停留数帧。

另外，`renderInContext` 从分支根的 presentation 副本绘制。根以下的子图层若有正在运行的动画，扁平化结果可能与屏幕不一致；FIX16 对这种分支继续拆分或改走原生读取。

## FIX16 对应修改

1. 背景读取与玻璃 GPU 工作移到 CA 提交之后的 run loop 观察者（顺序 2001500）。
2. 主线程预算：读取间隔 ≥ 平均开销 ÷ 占用上限（默认 35%）。
3. `CABackingStore` 与普通 CALayer 子类走 CPU；只有渲染服务专属内容走原生读取；分类只读模型层并按类缓存。
4. 子图层动画保护（`animatingSublayer`）。

## 未验证

没有在真机上测量 FIX16。`CABackingStore` 的类型名按 iOS 现有行为判断：若某系统版本名称不同，结果只是回到 FIX15 的原生读取，不会画错。预算策略的数值行为见 Tests/BackdropBudgetTests.c。
