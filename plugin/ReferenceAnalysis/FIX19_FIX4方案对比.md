# FIX19：FIX4 为什么延迟低，以及如何保留它

依据：用户上传的 WeChatLiquidGlass_0_4_4_TEST4_FIX4_flat.zip 中 `WXGBackdrop.m`、`WXGGlassView.m`、`WXGHost.m`。

## FIX4 的实际做法

- `WXGCaptureRegion` 新建区域时总是 `requiresModel=YES`，所以始终走 `WXGPrune` + `[source.layer renderInContext:]`：隐藏 `WXG*` 视图、排除项和不在 ROI 内的子树（模型层 `hidden`），对页面视图的**模型树**做一次 CPU 光栅，然后在同一个关闭动画的 `CATransaction` 中恢复。
- 在 `CADisplayLink` 回调里执行，早于本次 runloop 的 Core Animation 提交；顶部和底部两个区域轮流读取；读取后立即 GPU 绘制并 `presentDrawable`（尽快上屏）。
- 每块玻璃再把共享图片用 CPU 画进自己的缓冲区。

## 为什么感觉延迟低

模型树是这一帧即将提交的状态：滚动偏移、布局都已是本帧的值。FIX15–18 读的是呈现层/渲染服务，即已提交的上一帧；FIX16 起又挪到提交之后才读和绘制，玻璃通常比内容晚一次合成。

## 为什么会“冻结”

UIKit 动画把模型值直接设成终点，中间过程只存在于呈现层和渲染服务。读模型树时，转场、键盘、插入行等都会画成终点，看起来像图层定住或提前到位。

## FIX19 的组合

- 默认模型树一次读取（FIX4），放在提交前、UIKit 布局之后，并先 `layoutIfNeeded`。
- 玻璃范围内或玻璃祖先上有动画、或有系统合成内容时，改用呈现层分支读取（FIX18）并预测；新出现的动画保留上一张背景最多两帧（新加入、未提交的动画在呈现层里仍是终点）。
- `presentsWithTransaction`：drawable 与本帧的提交一起交给渲染服务；所有玻璃共用一个命令队列，等待最后一个命令缓冲区排上队后统一 present。
- 每块玻璃同时计算模型映射和呈现映射；发布的样本来自哪棵树，就用哪套映射，覆盖区包含两者。
- 有同帧提交时，滚动类运动不再需要“模型补偿”（置 0）；显示时刻预测只作用于动画期间的呈现层读取。

## 未验证

真机上：提交前观察者与 UIKit 内部顺序、`presentsWithTransaction` 对整帧耗时的影响、呈现层在提交前是否包含本帧的非动画改动（模型映射正是为此准备）、FIX19 与 FIX4 的主观跟手度对比。
