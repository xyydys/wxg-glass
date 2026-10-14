# WeChat Liquid Glass · TEST4 FIX11

版本 `0.4.11-test4fix11`。这是针对 FIX10 最新反馈重新修改的测试版，保留现有光学参数和两端／三端输入布局。旧 FIX4、FIX10 工程与产物单独保留，没有覆盖。

## 本次改动

- **连续采样**：删除 FIX10 的转场／待进入页面停采样、每帧仅两个玻璃复制名额、采样耗时乘三的等待。键盘移动、进入／返回、视频等场景按所设帧率上限持续申请背景更新；离场但仍可见的输入栏也参与更新。
- **背景像素路径**：删除丢失原生绘制内容的离线图层复制树。同一窗口的玻璃共用当前可见场景的背景，使用原 demo 的 `drawViewHierarchyInRect:afterScreenUpdates:NO` 读取不含插件玻璃的原生子树，按当前显示坐标合成，直接写入共享 Metal 缓冲区；根视图不整棵同步 `renderInContext`，也不临时隐藏原生层。顶栏、底栏、输入栏不再分别截图，更不再逐按钮复制 UIKit 位图。
- **GPU 取区域**：每块玻璃从共享背景通过 GPU 仿射映射取得所需区域，再进入原有 TEST9 高斯和折射流程。缓冲区最多三份；CPU 写入与在途 GPU 读取用租约隔开，不阻塞等待旧帧。
- **坐标与归属**：挂载与缓存仍属于各自的页面，像素按 presentation 层的当前坐标从可见场景取样，包括键盘移动的中间状态。返回时一个按钮下方可能同时经过两个页面，因此取样包含正在显示的两侧内容，不固定取某一页或终点快照。底栏成为原生 `MMTabBar` 的子视图，跟随原生底栏的位置、透明度和遮挡顺序。删除窗口覆盖层上的底栏位移补偿及露出裁剪，原生底栏只隐藏旧绘制子项。上抬超出原生边界的胶囊保留点击区域。
- **图标及冷启动背景**：星标玻璃直接放进真实 `MainFrameLeftBarView` 宿主。仅对已登记的该图标保留目标 frame／bounds／center，其余 UIImageView 原样执行。修正操作不参与原生位置动画；稳定页不把原生图标重排误作导航转场。补清理 `MMUIHookView` 旁支里的 `FakeNavigationBar`，并在原生 push/pop 设置完成后、同一轮提交前处理挂载。
- **材质及视频号**：取消脱离原生内容的图层克隆，视频页同样走原生合成截图；四个按钮继续读取同一份普通玻璃参数，保留其原生图片资源和 tint。材质深浅仍跟随界面外观，不随背景亮度自动切换。

19 个核心文件与 FIX10 完全一致，包括 TEST9 的 .metal、内嵌原光学 shader、折射／模糊函数、独立透镜设置、运动、整个 DemoBar 和输入几何函数。两个输入适配器只更换背景所属页面，未重写编辑器布局或语音动作。GPU 区域复制是单独附加 kernel，不修改光学 shader。

## 性能与验证边界

支持的屏幕可以请求最高 120 Hz；这是上限，**不是已实测到 120 帧的保证**。本版不再通过区域轮转／转场暂停来降低更新频率。采样吃紧时优先降低背景读取的空间分辨率，范围 1–2x；60 Hz 设备从 1x 开始，Metal 输出与光学高斯仍保持原屏幕分辨率。旧的“静止 15 Hz”开关本版停用并从界面移除，避免把视频或键盘运动误判为静止。

环境只有 Linux 上的 iOS 交叉编译工具，不能运行微信、UIKit 或 Metal。已完成数值检查、Objective-C 检查与实际 arm64 编译链接；不能据此宣布低设备卡死、原生转场或视频像素已真机修好。原生 compositor 截图对特定视频／受限渲染层的支持，以及本版端到端延迟，仍需要设备确认。Metal 在运行时编译；本版提前预热，不能承诺冷启动第一瞬间管线已经就绪。

与上一版不同，本版没有刻意等转场结束再取第一张背景。读取失败时保留旧 drawable，并在诊断记失败；不会把失败的空白图当作成功采样。

## 安装与最短核对

编译包包含 arm64 dylib、plist、rootful/rootless deb 及同一份完整源码。最低部署 iOS 13；arm64e 只做语义检查，没有另外生成该架构的 dylib。替换主插件后完全退出微信再打开，保留现有参数，确保运行的是 `0.4.11-test4fix11`。

先不录探针，确认以下三个短动作即可：

1. 冷启动停在首页，再下拉：星标与玻璃一起移动，顶栏白色背景不再回来。
2. 聊天内连续收起／抬起键盘，随后半返回并取消：看运动中玻璃内的背景是否持续变化；底栏是否随原生底栏移动。
3. 视频号播放时改变普通玻璃参数，再返回首页：看图标原色、参数响应和背景像素是否正确。

无需重跑此前整套抓取。若仍异常，现有 WGP4.3 能读取新增 `host.sampling`；只录该动作约 10 秒。手机已无法操作时不必勉强录制，可回到已保留的 FIX4。

## 诊断字段

- `host.sampling.backdrop.regions[].intervalMS / measuredCaptureFPS`：当前窗口场景背景成功更新的实际间隔及其倒数，不是 display-link 请求值。
- `host.sampling.backdrop.regions[].costMS / scale / branchDraws / busySkips`：原生读取耗时、实际分辨率、读取分支数与缓冲占用跳过数。
- `host.sampling.glassFrames[].presentedFrames / presentedBackdropUpdates`：Metal drawable 实际呈现次数／其中换了新背景的次数，来自 `addPresentedHandler`。
- `presentIntervalMS / presentedBackdropAgeMS`：真实呈现间隔、呈现时距背景采集开始的时间。
- `completedFrames / gpuMS / acquireMS`：GPU 完成次数、GPU 耗时、申请 drawable 的等待。完成不等于已经上屏。
- `dockOwnership.nativeBarChild` 应为 true；`nativeExposureMask` 应为 false。

没有开启探针时仅保留计数器，不持续写逐帧日志。原有探针的分卷上限保持不变。

## 自行编译

```sh
export THEOS=/opt/theos
./build.sh rootless
# 或 ./build.sh rootful
```

源码数值检查：`sh tools/test_geometry.sh`。原 demo 与上版存在时，可运行 `tools/audit_sources.py --demo <demo路径>` 和 `tools/audit_fix11_scope.py --baseline <FIX10路径>`。

`Validation/` 中旧版本命名的报告与旧审计脚本仅供追溯，不代表本版结果。当前验证清单见 `VALIDATION.md`。
