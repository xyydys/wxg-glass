# FIX105 验证

- 和 FIX104 相比只改 `WXGHost.m`：refresh 的未授权分支调 `detachOverlays`（移走 overlay / 导航 overlay、隐藏悬浮入口），`ensureOverlay` 的悬浮入口显隐加上“已授权”条件；版本号 0.4.105。
- `tools/test_geometry.sh`：56 个 C 测试全部通过。
- iOS 16.5 SDK、arm64 / arm64e、iOS 14、`-Wall -Wextra -Werror`：0 诊断。
- `tools/check_unused_statics.py`：0。
- dylib 里仍无着色器文本（只有函数名 `wxgFragment`）。
- 没有真机运行。被踢但本地票据仍有效的账号冷启动会短暂显示玻璃再撤掉（踢人生效过程），未处理。

# FIX104 验证

- 和 FIX103 相比：`WXGUnlockPolicy.h`（服务器复查间隔）、`WXGUnlock.m`（recheckAfter、force、冷启动读缓存、着色器锁、后台发请求）、`WXGSettings.m`（“授权”卡片）、`WXGHost.m`（`WXGUnlockStart` 移到构造函数、版本号）、`WXGCommon.h`、`WXGGlassView.m`（注释）、`Tests/UnlockPolicyTests.c`。
- `tools/test_geometry.sh`：56 个 C 测试全部通过（`Validation/test_results.txt`）。
- `tools/build_deb_linux.sh`：iOS 16.5 SDK、clang 18、`-Wall -Wextra -Werror`，0 警告；另用 `-fsyntax-only` 对 23 个 .m 分别以 arm64 / arm64e、iOS 14.0 检查，0 诊断（iOS 13.0 目标下 `WXGSettings.m` 的 UIColorPickerViewController 可用性警告 FIX103 就有）。
- `tools/check_unused_statics.py`：0。
- 服务器补丁：`worker.js` 在 node 22 里用临时密钥跑原 handler：200 带 `recheckAfter: 300`，403 带 `{"error":"not authorized","recheckAfter":300}`，stale 不变；200 的签名按 FIX103 的签名内容用 OpenSSL 验证通过，摘要等于着色器 SHA-256（43429 字节）。
- dylib 里没有着色器文本（只有函数名 `wxgFragment`，和 FIX103 一样）。
- 没有真机运行。

# FIX102 验证

- 和 FIX101 相比：
  - `WXGLicense.m`：读账号 60 s 一次、空闲才读、计时；
  - `WXGHost.m`：`WXGHostQuietForLicense`、钩子计时、`WXGProfileOursTotal`、版本号；
  - `WXGPerfMonitor.m`：`WXGPerfTimePluginWork` 总是计时；
  - `WXGDecorations.m`：观察者计时；
  - `WXGIntegration.h`：`WXGProfileHooks`；
  - `WXGDockScript.h`：`WXGScriptScaleTime` / `WXGScriptCatchUp`；
  - `WXGDemoBar.m`：追上、按下时立即请求；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：`dockTapCalmWaitOn`（默认关）、`dockTapCatchUp`；
  - `Tests/DockScriptTests.c`；
  - `control`、`WXGBuildProfile.h` 第一行。
- `DockScriptTests`：
  - 缩放 0.8 倍后逐点相等；
  - 0.1 s 停顿缩短 0.06 s；2 s 停顿最多缩短四分之一；5 ms 不变；pivot 处位置不变。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py`、`tools/shader_sim/check_bar_dispersion.py` 通过。
- 没有在真机上运行过。

# FIX101 验证

- 和 FIX100 相比：
  - `WXGDockScript.h`：`WXGScriptCalmWait`；
  - `WXGDemoBar.m`：等空闲、点按记录的慢帧与等待时间；
  - `WXGHost.m`：CA commit 计时、刷新分步计时、版本号；
  - `WXGIntegration.h`：`WXGProfileCommit`；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：`dockTapWaitForCalm` 和设置行、说明；
  - `Tests/DockScriptTests.c`；
  - `control`、`WXGBuildProfile.h` 第一行。
- `DockScriptTests`：
  - 两帧准时还等、慢帧重新计数、三帧准时出发；
  - 0.6 s 后紧跟长帧还等、下一帧准时就走；1.2 s 封顶；
  - 120 Hz 下 20 ms 的帧也算准时（22 ms 下限）。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py`、`tools/shader_sim/check_bar_dispersion.py` 通过。
- 没有在真机上运行过。

# FIX100 验证

- 和 FIX99 相比：
  - `WXGDockScript.h`：`WXGScriptShift`、切换那一步 1/60、之后 1/30；
  - `WXGDemoBar.m`：按下时请求、`switchedAtTouchDown`、保留按下的标签、`tabSwitchForwardedFrom:`；
  - `WXGHost.m`：`dockRequestedTabAtTouchDown:`、松手不再重复转发、转发后通知底栏、`noteVisitedTab:`、头像磁盘缓存、版本号；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：`dockTapSwitchWhen`（迁移）、四档选择和说明；
  - `Tests/DockScriptTests.c`；
  - `control`、`WXGBuildProfile.h` 第一行。
- `DockScriptTests`：
  - 后移 0.7 s 的脚本与原曲线逐点相同（位置、按压、颜色）；
  - 切换那一步 ≤ 1/60 s，之后的忙碌帧 ≤ 1/30 s，落后 ≤ 0.5 s；
  - 按下时卡 0.2 s、再 3 个 90 ms 帧：照样落在标签上、按压 0、颜色 1。
- 独立 review（按下时的所有触摸路径、挂起逻辑、切换时宿主刷新是否打断触摸、头像缓存线程安全与串号、迁移）：指出 4 处，已修。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py`、`tools/shader_sim/check_bar_dispersion.py` 通过。
- 没有在真机上运行过。

# FIX99 验证

- 和 FIX98 相比：
  - `WXGDockScript.h`：`share` 参数、落下提前 0.70、`WXGScriptClockAdvance`；
  - `WXGDemoBar.m`：新参数、时钟只在转发切换前后、`holdsTabSwitchAtMoment:`、`noteTabSwitchForwarding`、点按记录、图标重扫推迟；
  - `WXGHost.m`：首次打开等落下、转发前通知、`WXGSecondsSinceLoad`、日志与诊断、版本号；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：新键（旧值迁移）和设置行、说明；
  - `Tests/DockScriptTests.c`；
  - `control`、`WXGBuildProfile.h` 第一行。
- `DockScriptTests`：
  - 一个标签 0.40 s 落下、到位后 0.048 s；透明保持不到 0.12 s；
  - 1/240 s 内最大变化 < 0.065；
  - 40 帧 60 ms（忙碌的冷启动）按真实时间走（2.4 s）；
  - 转发切换后的 0.18 s 卡顿只算 1/60 s，远离切换的卡顿不压，最多落后 0.5 s；
  - 120 Hz 下在 80% 处卡 0.18 s：按压、颜色最大一步 < 0.25（真实时间 0.74 / 0.85）。
- 60 Hz 模拟（切换卡 186 ms，之后 0.5 s 内每 3 帧一个 60 ms 帧）：0.72 s 落下（计划 0.40 s），按压、颜色最大一步约 0.21，不跳。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py`、`tools/shader_sim/check_bar_dispersion.py` 通过。
- 没有在真机上运行过。

# FIX98 验证

- 和 FIX97 相比：
  - `WXGDockScript.h`：颜色轨道、落下尾段、时长倍数、切换时机、动画时钟；
  - `WXGDemoBar.m`：动画时钟、颜色权重和交接、新参数；
  - `WXGGlassView.m` / `WXGCommon.h`：`selectionWeight` → `extra2.w`（uniform 大小不变，304 字节）；
  - `WXGGlass.metal`（重新嵌入）：`wxgSelectionWeight`；
  - `WXGLensOptics.h`：按压映射 0.05–0.45；
  - `WXGHost.m`：等待上限 1.5 s、补发第二次点按、版本号；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：三个新键和设置行、说明；
  - 测试：`DockScriptTests.c`、`RestingSelectionTests.c`；
  - `control`、`WXGBuildProfile.h` 第一行。
- `DockScriptTests`：
  - 一个标签的点按 0.53 s 落下、三个 0.58 s（FIX97 约 0.26 s）；
  - 颜色在按下那一帧 > 0.98，滑到 1/3 时约一半，65% 时为 0，落下一半时约一半，落下时为 1；
  - 1/240 s 内按压、颜色最大变化 < 0.045；
  - 120 Hz 逐帧、到 80% 时（0.31 s）卡 0.18 s：最大一帧 x 4.1 pt（正常帧的速度）、按压 0.16、颜色 0.14（卡顿那一步走 1/24 s；真实时间下按压一次跳 0.84、颜色 0.90），最后在标签上、按压 0、颜色 1；
- 独立 review：颜色在所有路径连续（按下、落下中再按、拖过 10 pt、按住交接、松手、取消、Reduce Motion）；指出的连点丢第二次点按、`_jumpPlanEnd` 混用时钟、等待无上限已修。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py`、`tools/shader_sim/check_bar_dispersion.py` 通过。
- 没有在真机上运行过。

# FIX97 验证

- 和 FIX96 相比：
  - `WXGGlass.metal`（重新嵌入 `WXGShaderSource.h`）：`wxgLensBar` / `wxgLensBarLayers` / `wxgLensBarSpectrum`，uniform 加 `extra2`；
  - `WXGGlassView.m`：`WXGUniforms.extra2`（304 字节）和它的取值；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：三个新键和“镜内底栏色散”一组；
  - `tools/shader_sim/sim.cpp`（`page`、`tint`、`pageGuess`、`barDisp`、`barDispRim`）、新 `tools/shader_sim/check_bar_dispersion.py`；
  - `WXGHost.m` 版本号、`control`、`WXGBuildProfile.h` 第一行。
- 模拟器：`barDisp 0 barDispRim 0` 的输出和 FIX96 的模拟器逐像素相同。
- `check_bar_dispersion.py` 通过（黑底、白底 × 第一个标签 / 两个之间 / 标签上 / 最后一个）：
  - 红蓝分离最大 0.45（黑底，1 px 硬边上的彩边）、离边缘远的地方变化 0；
  - 每通道均值变化 ≤ 0.0015；
  - 在关闭图 4 pt 邻域范围外最多 0.043（不补页面时白底 0.8）；
  - 亮度峰 / 谷数不多于关闭时（只取三点的版本会多出一条，能检查出来）。
- 独立 review：结构体顺序和大小、MSL（fwidth 在一致分支里、无命名冲突）、关闭时的合成顺序、配置行都没问题；指出的单 alpha 变暗和整幅画布的开销已修。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 没有在真机上运行过。

# FIX96 验证

- 和 FIX95 相比：
  - `WXGOptics.h`：连续圆角修正；
  - `WXGMeshRefraction.h`：网格环跟随连续轮廓、直边两端加密；
  - `WXGGlassView.m` / `WXGDemoBar.m`：透镜相关图层恢复 continuous；
  - `WXGOpticalSettings.m`：说明文字；
  - `WXGShaderSource.h`：重新嵌入；
  - 测试：新 `ContinuousCornerTests.c`，`OpticsTests.c` / `RollbackOpticsTests.c` 改为连续轮廓；
  - `ReferenceAnalysis/FIX96_continuous_corner/`、版本号。
- 测量：透镜与底栏两条曲线吻合到 0.002 R，拟合 rms 0.0016 R。
- `tools/shader_sim`：边框（外框到亮线的距离）从正上方 4 px 往两侧 4、5、6、7 px，单调。
- 轮廓网格测试：最大误差 0.24 pt（FIX95 为 0.20），没有超过 1 pt 的像素，无空洞、无重叠。
- C 测试 55 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 没有在真机上运行过。

# FIX95 验证

- 和 FIX94 相比：
  - `WXGGlassView.m`：透镜裁剪、外框改成圆形圆角；
  - `WXGDemoBar.m`、新 `WXGDockScript.h`：点按用真实透镜，按脚本逐帧驱动；
  - `WXGHost.m`：切换挂起到透镜落下、头像下载 / 探测 / 设置、版本号；
  - `WXGSurface.m`：头像描边读设置；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：新键和设置行；
  - `control`、`WXGBuildProfile.h` 第一行注释；
  - 着色器与 FIX94 相同（`WXGShaderSource.h` 逐字节一致）。
- 新测试 `DockScriptTests.c`：
  - 贝塞尔两端和单调；
  - 滑动时长、起止、55% 处升到 0.9 并保持；
  - 早松手落在计划时刻、晚松手 0.1 s 后落下，落下段只降不升；
  - 拖动松手的 0.27 ×（0.85 + 0.05 × 标签数）、计划下限 0.12 s、无位移只落下；
  - 值和速率都有限。
- `tools/shader_sim`：用用户 FIX94 的参数跑嵌入着色器，复现了 FIX93 截图的样子（黑槽、图标折射）。量出圆形外框下外框到亮线的距离：正上方 4 px，往两侧 5、6、7、8 px，单调。
- 独立审查：
  - 1 个中等问题：落下前再点同一个标签会绕过挂起，也少一次点按；
  - 若干小问题：script 结束跳到 `_targetX`、减弱动态效果 / 简化透镜回退时仍挂起、读回模式不触发挂起的切换、下载晚到不替换；
  - 以上都已修。
- C 测试 54 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 只能在真机上验证：
  - 透镜边框；
  - 点按时的透镜和切换延迟；
  - 头像下载（`avatarProbe`、`avatarDownload`）。
- 没有在真机上运行过。

# FIX94 验证

- 和 FIX93 相比：
  - `WXGHost.m`：首页下拉时顶栏按钮在列表里的检测、头像无玻璃 + 层级、版本号；
  - `WXGEdgeFade.m`：顶部渐隐 / 模糊让开；
  - `WXGLensOptics.h` / `WXGOptics.h` / `WXGGlass.metal` / `WXGShaderSource.h`：镜内底栏贴边；
  - `WXGGlassView.m` / `WXGTravelVeil.h` / `WXGDemoBar.m`；
  - `WXGConfig.m` / `WXGCommon.h` / `WXGOpticalSettings.m`：两个新参数；
  - `WXGSurface.m`：头像整圆 + 描边；
  - `WXGIntegration.h`、`control`、`WXGBuildProfile.h`（只改第一行注释，默认参数不变）。
- 新测试 `LensBarZoomTests.c`：
  - margin 0 时关闭（z = 1）；
  - 直段中间的底栏边缘 = 透镜边缘 − margin × 折射带宽；
  - 往衔接处单调降到 1；
  - 端帽取直段末端的比例；
  - 透镜一端压在端帽上（相对底栏端点 −14 到 +8 pt）：放大过的轮廓点都在透镜边缘以内，相邻 0.25 pt 的列比例变化 < 0.03。旧做法越过边缘 8.5 pt，这一项会失败；
  - 点按动画轮廓与着色器一致。
- 独立审查：找到 1 个中等问题（端帽在透镜一端下越过边缘）和 3 个小问题（同步渲染以外不生效、端帽侧面描边变细、隐藏的按钮副本也算在列表里），都已改掉或在设置说明里写明。
- C 测试 53 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/embed_shader.py` 重新生成，`tools/check_msl.py` 通过。
- 只能在真机上验证：
  - 首页下拉（日志“顶栏：微信的顶部按钮…”、`homeTopBarInList`）；
  - 透镜黑边的粗细；
  - 头像。
- 没有在真机上运行过。

# FIX93 验证

- 和 FIX92 相比：`WXGBuildProfile.h`（默认参数 JSON）、`WXGHost.m`（下拉时的透明度下限、下拉记录、外层扫描、版本号）、`WXGSurface.m` / `WXGIntegration.h`（`alphaFloor`、`nativeAlpha`、`nativeHidden`）、`control`。
- 默认参数：把 `WXG_DEFAULT_OPTICS_JSON` 编进一个 C 小程序打印出来，再用 Python 解析，与导出的文件逐项比对：253 项参数一致，开关只有 sizeScale 舍入到 6 位小数，卡片圆角 26。
- C 测试 52 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 下拉时的顶栏只能在真机上验证（`homePullTrace`、日志“顶栏：首页下拉 …”）。
- 没有在真机上运行过。

# FIX92 验证

- 和 FIX91 相比：`WXGHost.m`（顶栏 overlay 的 zPosition、每帧 `keepNavigationOnTop`、诊断字段、版本号）、`control`、`WXGBuildProfile.h` 注释。
- C 测试 52 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 下拉进小程序时的层级只能在真机上验证（诊断 `navigationRaises`、`navigationCovers`、`lastNavigationCover`，日志“顶栏：…”）。
- 没有在真机上运行过。

# FIX91 验证

- 和 FIX90 相比：`WXGConfig.m`（三个键和存取）、`WXGCommon.h`、`WXGDemoBar.m`（标题字体、重画条件）、`WXGNativeIcons.m`（记下微信标题字体）、`WXGOpticalSettings.m`（三行设置）、`WXGHost.m`（版本号）、`control`、`WXGBuildProfile.h` 注释。
- C 测试 52 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 没有在真机上运行过。

# FIX90 验证

- 和 FIX89 相比：`WXGConfig.m`（两个键和存取）、`WXGCommon.h`、`WXGDemoBar.m`（图标图集的图标 / 标题位移、角标、重建条件）、`WXGOpticalSettings.m`（底栏“图标与文字”分组）、`WXGHost.m`（版本号）、`control`、`WXGBuildProfile.h` 注释。
- C 测试 52 个全部通过；22 个 `.m` 以 `-Wall -Wextra -Werror -Wunguarded-availability-new` 编译链接 0 个诊断；未使用的 static 0；`tools/check_msl.py` 通过。
- 默认值（间距 5、上下 0）时图集与 FIX89 完全相同（位移都是 0）。
- 没有在真机上运行过。

# FIX89 验证

- **和 FIX88 相比改动的文件**：`WXGRimGlow.h`、`Tests/RimGlowTests.c`（都回到 FIX87 的单道形式）、`WXGCommon.h`、`WXGConfig.m`（删 12 个键、加 3 个 Sharpness 键、`rimGlowForScope:index:`）、`WXGGlassView.m`（`WXGRimGlowLayer`、两道高光、uniform、透镜轮廓数组）、`WXGGlass.metal` / `WXGShaderSource.h`（重新生成）、`WXGDemoBar.m`（两条轮廓线、`restingOnSelectedTab`）、`WXGHost.m`（长按识别器、版本号）、`WXGOpticalSettings.m`、`control`、`WXGBuildProfile.h` 注释。
- **C 测试 52 个全部通过**。
- **Objective-C**：
  - 22 个 `.m` 用 iOS 16.5 SDK 以 `-target arm64-apple-ios14.0 -Wall -Wextra -Werror -Wunguarded-availability-new` 编译并链接，0 个诊断；没有 `@available`。
  - 未使用的 static：0。
  - `WXGUniforms` 288 字节（18 个 float4）有静态断言，字段顺序与 `WXGGlass.metal` 一致。
  - `tools/check_msl.py` 通过（539 行），嵌入的着色器与 `WXGGlass.metal` 一致。
- **长按问题**：诊断里 4 次“触摸被系统取消”都在按下 0.90 s，等于设置备用入口长按的时长，设置入口为已加入，与代码里的原因一致。
- **只能在真机上验证的**：两道高光的观感（含底栏透镜里和点按动画里的线）；在别的标签上长按不再弹回（诊断 `dock.cancelled` 应不再随长按增加）。
- 独立只读审查一轮，1 处已改（见交接说明）。
- 没有在真机上运行过。

# FIX88 验证

- **和 FIX87 相比改动的文件**：
  - 新文件：`WXGTravelVeil.h`、`Tests/LensInsetAlongTests.c`、`Tests/TravelVeilTests.c`；
  - 从 FIX85 恢复：`WXGCalmBackdrop.m`、`WXGCalmMath.h`、`Tests/CalmMathTests.c`；
  - 修改：
    - `WXGRimGlow.h`（另一方向高光）、`Tests/RimGlowTests.c`；
    - `WXGOptics.h`（`WXGInnerInsetAlong`、`WXGLensDepthAlongBar`）、`WXGMeshRefraction.h`（色散范围）；
    - `WXGGlass.metal` / `WXGShaderSource.h`（重新生成）；
    - `WXGCommon.h`、`WXGConfig.m`（Rim27Cross 六个键、calm 七个键、两个色散范围键）、`WXGGlassView.m`、`WXGDemoBar.m`、`WXGHost.m`、`WXGInput.m`、`WXGSurface.m`、`WXGOpticalSettings.m`、`WXGIntegration.h`、`Makefile`、`control`、`WXGBuildProfile.h` 注释。
- **C 测试 52 个全部通过**。新加和改动的：
  - `LensInsetAlongTests`：
    - 衔接处为 0、起点斜率 1（45°），往里单调，到 2 倍收窄量处等于全部收窄；收窄上限；press 0 或收窄 0 时为 0；
    - 沿底栏的深度换算；整条轮廓透镜外就是底栏边、没有比 45° 更陡的台阶、中间是全部收窄；
    - 色散自己的范围：和折射带相同时映射不变，更宽时往里更远，只有折射带的地方没有分色。
  - `TravelVeilTests`：
    - 透镜外就是底栏轮廓，透镜中间上下是全部收窄量，端头在透镜里也收进去；
    - extra 沿法向往里；
    - 比底栏半高还深的层上下不交叉；
    - 材质边缘减弱的分层叠加后每层中点等于着色器的减弱曲线。
  - `RimGlowTests`：另一方向高光（0° 和 90° 时另一方向等于它的强度、主方向全亮；任何方向都不低于只有一道高光时；两道都全亮时斜角为一半；负数、NaN 和超过 1 的夹取）。
  - `CalmMathTests`：随平稳背景恢复。
- **Objective-C**：
  - 22 个 `.m` 用 iOS 16.5 SDK 以 `-target arm64-apple-ios14.0 -Wall -Wextra -Werror -Wunguarded-availability-new` 编译并链接，0 个诊断；没有 `@available`。
  - 未使用的 static：0。
  - `WXGUniforms` 256 字节（16 个 float4）有静态断言，与 `WXGGlass.metal` 的结构一致。
  - `tools/check_msl.py` 通过（532 行），嵌入的着色器与 `WXGGlass.metal` 一致。
- **离线模拟**（Python，按同一公式）：
  - 透镜内底栏的轮廓：原来在透镜边是直角台阶，折射后底部变平；现在 45° 进入、往里变平，折射后接近椭圆。
  - 透镜移到底栏两端时端头正常脱离。
  - 折射带宽度沿透镜轮廓在各组参数下单调，上下不比圆角处宽。
- **只能在真机上验证的**：
  - 头像的几条读取路径（诊断 `avatarStatus` / `avatarLookups`）；
  - 点按动画里底栏放大和透镜内底栏是否与真透镜对齐；
  - 按住别的标签后换成真透镜（`dock.holdHandovers`）；
  - 长按不切换的日志（`dock.uncommittedEnds` 和日志里的“底栏：松手没有切换”）。
- **独立只读审查两轮**：第一轮 11 条、第二轮 7 条，都已修改（见交接说明）。
- 没有在真机上运行过。

# FIX87 验证

- 和 FIX86 相比：`WXGRimGlow.h`（方向角）、`Tests/RimGlowTests.c`、`WXGCommon.h`、`WXGConfig.m`（Rim27Angle 六个键）、`WXGGlassView.m`（level 层方向、着色器 glow.x）、`WXGGlass.metal` / `WXGShaderSource.h`（重新生成）、`WXGOpticalSettings.m`（高光方向、最暗处亮度、拉伸开关文字）、`WXGIntegration.h` / `WXGSurface.m`（`pressFixed`、`iconTint`）、`WXGInput.m`（表情图标与面板状态、听写会话与提示）、`WXGNativeInput.m`（中间胶囊固定）、`WXGHost.m`（版本号）、`control`、`WXGBuildProfile.h` 注释。
- C 测试 49 个全部通过。`RimGlowTests` 加了方向：0° 上下全亮 / 两端为最暗处亮度，90° 反过来，45° 左上和右下全亮、右上为最暗处亮度，135° 右上全亮，180° 与 0° 相同，n 与 −n 相同，角度缺失按 0°。
- Objective-C：21 个 `.m` 用 iOS 16.5 SDK 以 `-target arm64-apple-ios14.0 -Wall -Wextra -Werror -Wunguarded-availability-new` 编译并链接，0 个诊断；没有 `@available`。未使用的 static：0。`tools/check_msl.py` 通过（490 行），嵌入的着色器与 `WXGGlass.metal` 一致。
- 离线按同样的分层、亮度场画了 90°（胶囊两端亮、上下直边暗）和 45°（左上 / 右下亮）。
- 输入栏的改动（胶囊固定、表情面板识别、听写状态）只能在真机上验证，诊断里有对应字段。
- 独立只读审查一轮，按意见改了 6 处（见交接说明）。
- 没有在真机上运行过。

# FIX86 验证

- 和 FIX85 相比：`WXGGlassView.m`（`WXGRimFieldLayer` / `WXGRimFadeLayer` / 新 `WXGRimLevelLayer`、`WXGRimView` 的 glow、按范围的样式、`rimAlwaysDark`、着色器 bar 轮廓颜色、`WXGRimSummary`）、新文件 `WXGRimGlow.h`、`Tests/RimGlowTests.c`；删除 `WXGRimVariable.h`、`WXGCalmMath.h`、`WXGCalmBackdrop.m`、`Tests/RimVariableTests.c`、`Tests/CalmMathTests.c`；`WXGConfig.m`（dock / bubble 样式键、iOS 27 新键、删 calm 键）、`WXGCommon.h`、`WXGIntegration.h`、`WXGOpticalSettings.m`（按范围的样式选择与分组、iOS 27 新分组、删平稳背景组）、`WXGHost.m`（删视频号胶囊、`styleFinderButtons`、启动、诊断、版本号）、`Makefile`、`control`、`WXGBuildProfile.h` 注释。
- C 测试 49 个全部通过。新 `RimGlowTests`：沿轮廓上下 1、两端为两端亮度、对 |ny| 单调、过渡速度越大越早变暗、45° 在速度 2 时为一半、参数夹取；往里约 1 px 一层、都从轮廓开始且每层宽一步、叠加后每段等于该段中点的曲线值且往里递减、超出宽度为 0、2x 与 3x 总亮度差 < 0.02、2 pt@3x 为 6 层、上限 20 层、细的为 1 层（中点亮度）、无宽度为 0。
- Objective-C：21 个 `.m` 用 iOS 16.5 SDK 以 `-target arm64-apple-ios14.0 -Wall -Wextra -Werror -Wunguarded-availability-new` 编译并链接，0 个诊断；没有 `@available`。未使用的 static：0。`WXG_RIM_GLOW_MAX_BANDS` ≤ `WXGRimBands` 容量有静态断言；`WXGUniforms` 240 字节（15 个 float4）有静态断言，与 `WXGGlass.metal` 的结构一致；`tools/check_msl.py` 通过（488 行）。
- 离线按同样的嵌套分层、亮度场和角窗半径画了胶囊、多行气泡、圆形按钮和圆角 0 的卡片（带抗锯齿）：四周宽度一致，上下最亮、往两端减弱，没有月牙，方角卡片的左右也按两端亮度。
- 独立只读审查一轮，6 处问题已修（见交接说明）。
- `tools/bake_defaults.py`：样例含三个范围的样式和 Rim27 新键时都保留，FIX85 的 EndWidth 和 calm 键被丢掉。
- 没有在真机上运行过。

# FIX85 验证

- 和 FIX84 相比：`WXGConfig.m`（表驱动的新键、作用范围与边框样式）、`WXGCommon.h`、`WXGIntegration.h`、`WXGGlassView.m`（气泡范围、平稳遮盖、iOS 27 边框）、新文件 `WXGRimVariable.h`、`WXGCalmMath.h`、`WXGCalmBackdrop.m`、`WXGKeyboardTrace.m`、`Tests/RimVariableTests.c`、`Tests/CalmMathTests.c`；`WXGOpticalSettings.m`（三段范围、样式选择、新分组和动作）、`WXGSettings.m`（双份存储）、`WXGHost.m`（视频号胶囊、启动、诊断、版本号）、`WXGBubbles.m`、`WXGSettingsShare.m`、`WXGPerfMonitor.m`（日志位置）、`tools/bake_defaults.py`（表里的键）、`Makefile`。
- C 测试 48 个全部通过。新 `RimVariableTests`：宽度规律（两端 / 上下 / 过渡速度、单调）、圆的内边误差 < 0.002 pt、160×44 胶囊两个方向上两端 1.6 pt / 上下 0.35 pt 且都在轮廓内、限制、退化轮廓。新 `CalmMathTests`：纯色 0、黑白 0.5、单通道、子区域、阈值两端与中点、单调、缓动步数。
- Objective-C：22 个 `.m` 用 iOS 16.5 SDK 以 `-target arm64-apple-ios14.0 -Wall -Wextra -Werror -Wunguarded-availability-new` 编译并链接，0 个诊断；没有 `@available`。未使用的 static：0。
- `tools/bake_defaults.py`：235 个配置键（154 + 表里 81）样例写入后往返一致。
- 独立只读审查一轮，7 处问题已修（见交接说明）。
- 没有在真机上运行过。

# FIX84 验证

- FIX83 A 与另一对话的 FIX81 ABC 改动三方合并（基准 FIX81 A）；相对 FIX81 A 的改动：`WXGEdgeFade.m`（列表登记改为关联对象、刷新时核对、诊断字段）、新文件 `WXGFrameStats.h`、`WXGPerfMonitor.m`、`WXGSettingsShare.m`、`Tests/FrameStatsTests.c`、`tools/bake_defaults.py`；`WXGHost.m`（插件耗时计入帧率日志、启动帧率检测、诊断加 `settingsShare` / `frameRate`、版本号）；`WXGNative.m`（两个新开关、新装用 build 的开关默认值）；`WXGLicense.m`（`WXGBuildDefaultSection`）；`WXGSettings.m`（新卡片、新装用 build 的界面默认值）；`WXGOpticalSettings.m`（“帧率与参数”模块和动作）；头文件声明；`Makefile` 加两个 .m；`control`、`WXGBuildProfile.h` 注释。
- 液态气泡布局钩子和提交前重隐藏计入插件耗时（`WXGPerfTimePluginWork`）。
- C 测试 46 个全部通过（含 FIX83 的 `BubbleRulesTests`；新增 `FrameStatsTests`：60/120 Hz 的掉帧与抖动界限、卡顿时间与 ms/s、掉帧率、1 ms 百分位含 200 ms 以上一档、5000 帧合并等于一次统计、无效间隔忽略）。
- Objective-C：20 个 `.m` 用 iOS 16.5 SDK 以 `-target arm64-apple-ios14.0 -Wall -Wextra -Werror -Wunguarded-availability-new` 编译并链接，0 个诊断；没有 `@available`。未使用的 static：0。
- `tools/bake_defaults.py`：用全部 154 个玻璃键（含液态气泡） + 开关 + 界面的样例写入 `WXGBuildProfile.h`，C 程序打印出的字符串能被 JSON 解析回原样，`WXGLicense.m` 以 ObjC 编译通过。
- deb：Linux 上用 clang 18 + ld64.lld（iOS 16.5 SDK 的 .tbd）链接，`ldid -S` 签名，rootless 布局。
- 另请一个独立的审查（只读）逐项检查了改动：渐隐关联、tick 拆分与原来逐字等价、JSON 安全、线程、浮标、导入。按它的意见改了：浮标颜色按当秒掉帧比例（不按屏幕最高帧率）、浮标改为主窗口子视图、同一次运行关再开不丢记录、插件耗时不重复计、导入时对方跟随系统色则清掉强调色、导入确认框找最上层页面弹出、文件大小读不到时也限制 16 MB。
- 没有在真机上运行过。

# FIX83 验证

- 和 FIX82 相比：`WXGGlassView` 加 `veilOverrideFade`（有 `veilOverride` 时，用它代替设置里的边缘减弱开关和范围，遮罩还是 `WXGVeilFadeMask`）；`WXGBubbleGlass` 按配置 `bubbleEdgeFadeEnabled`（YES）/ `bubbleEdgeFade`（8 pt，0–30）设置它；设置页“液态气泡”加“边缘减弱”组。
- C 测试全部通过；Objective-C：18 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX82 验证

- 和 FIX81 相比：
  - 新 `Sources/WXGBubbles.m`：`TextMessageCellView` 的 `layoutSubviews` / `didMoveToWindow` 之后（`WXGHookVoid`），在 5 层内找同时直接拥有 `RichTextView` 和 `YYAsyncImageView` 的最小视图作为气泡本体（MixBubble 的找法），本体里所有 `YYAsyncImageView` 用 `WXGStateBag` 以 alpha 隐藏、`RichTextView` 背景清掉；本体最底层插入 `WXGBubbleGlass`（一块 `WXGGlassView`：overlayHidden、lightweight，frame = 本体 bounds）。方向读 `m_viewModel` / `_viewModel` 的 `isSender`（返回类型为 BOOL 时），否则看气泡图片 x 是否 ≥ 0。每次提交前（run loop 观察者）对可见气泡重新隐藏，子视图集合变了才重扫。主机的显示链接里 tick（只有新建、尺寸 / 颜色 / 主题变化时才做事），配置变化时重新布局，关闭时恢复。诊断 `bubbles`。
  - 新 `Sources/WXGBubbleRules.h` + `Tests/BubbleRulesTests.c`：单行判定（34 ≤ h < 59）、参考高度（屏幕上最小的单行，至少 40）、圆角 = min(参考/2, 宽/2, 高/2)、无模型时按图片 x 判方向。
  - `WXGGlassView`：`veilOverride`（统一着色、不做边缘减弱；轻量玻璃的取色边框用它）。
  - 配置 4 个颜色键、偏好 `bubbles`；设置新模块“液态气泡”和首页卡片。
- C 测试全部通过；Objective-C：18 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过（微信 8.0.73 的气泡结构按 MixBubble 源码推断；滚动时每个可见气泡一层背景的开销未实测）。

# FIX81 验证

- 和 FIX80 相比：
  - `WXGConfig.m`：`loadDefaults` 末尾（`applyBuildDefaults` 之前）写入边框页 53 个键的值，取自用户 FIX80 诊断 JSON 的 `materialParameters`（数值保留 4 位小数）；脚本逐键比对源码与 JSON，0 处不一致。新装（无 `optics.test4`、无 `config.v4–v9`）改为 `loadDefaults`（原来只 `applyBuildDefaults`，前面的迁移会用旧共享值覆盖部分默认值）。新 `resetKeys:`：只把给定键恢复默认，其余键还原。
  - `WXGOpticalSettings.m`：边框模块末尾“恢复”组 + `resetPage` 动作（收集本页所有行的 key / dock 键，确认后 `resetKeys:`）。
- C 测试全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX80 验证

- 和 FIX79 相比：
  - `WXGPressStretch.h`：`WXGStretchStyle`（强度、胶囊比例、最大拉长、跟手比例），`WXGStretchPoseMake` / `WXGStretchFit` 改收这个结构。拉长量 e = M·tanh(x/M)（M ≤ 0 不限）；宽高比 > 1.1 的玻璃按两个轴分别拉伸（ex、ey 来自拉动的 x、y 分量 × 胶囊比例，另一轴变窄一半，矩阵无剪切）；平移 = 原来的 0.45 × 拉长 + 跟手比例 × 拉动。`Tests/PressStretchTests.c` 原用例用等价的旧参数（比例 1、不限、不跟手）不变，另加非圆无剪切 / 分量拉伸 / 过零连续、最大值逼近不超过、跟手平移与裁剪适配。
  - `WXGSurface.m`、`WXGDockSearch.m`：从配置取这四个值。
  - 配置：`pressStretchCapsule`（0.5，0–1）、`pressStretchMax`（8，1–20 pt）、`pressStretchFollow`（0.3，0–1）；设置页 基本设置 → 交互 加三个滑块。
- C 测试全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX79 验证

- 和 FIX78 相比：
  - `WXGRimDetail.h`：删除 `WXGRimDetailAlphas` / `WXGRimCoreInset` / `WXGRimRingExtent`；新增阶梯带：`WXGRimFitFades`（内外侧之和不超过线宽）、`WXGRimSteps`（每级 ≤ 0.1 pt，最多 10 级）、`WXGRimAlphaBands`（透明度：N+1 个嵌套带，第 j 带覆盖 [外侧·j/N, w − 内侧·j/N]，叠加后第 q 级为 e + (1−e)q/N）、`WXGRimDimBands`（变暗：每侧 N 个黑带，第 m 带覆盖该侧 m/N，叠加后第 q 级亮度为同一值）、`WXGRimStepped`。`Tests/RimDetailTests.c` 对 3 种线宽 × 4 组内外侧 × 3 个强度逐点检查两种叠加的结果和步长。
  - `WXGGlassView.m`：`WXGRimView` 不需要消散时仍是 FIX72 的自身边框；需要时自身边框为 0，改由 `_lineStack`（组不透明度 = 线条不透明度）里的池化 CA 边框画各级（透明度：颜色带；变暗：全宽颜色带 + 黑带）；取色且变暗（未开加亮叠加）时在线下画全宽黑带（不透明度 = 取色线条的不透明度）。`WXGRimTintView` 的遮罩改为同样的透明度阶梯带（白色），变暗时合成改为 plusL。内侧阴影不变。诊断 `rims` 增加内外侧、级数、带数、垫黑。
  - 配置：删除 `rimCoreWidth`；新增 `rimOuterFade` / `darkRimOuterFade`、`rimInnerFade` / `darkRimInnerFade`（0–1.5，取整到 0.1）、`darkRimSideLevel`、`rimSideDarken` / `darkRimSideDarken`、`darkRimInnerShadowRadius`、`darkRimSampleSaturation` / `Contrast` / `Gain` / `Lift` / `Blur`；首次运行深色沿用浅色已调的值。设置页分为“描边细节”“描边细节 · 浅色模式”“描边细节 · 深色模式”“描边取色”“描边取色 · 浅色模式”“描边取色 · 深色模式”。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过（取色线条在变暗模式下用 plusL 合成叠在黑带上，backdrop 图层上的 plusL 未实机确认；若不生效会退回普通合成，线条两侧比预期更暗一些）。

# FIX78 验证

- 和 FIX77 相比（`WXGGlassView.m`）：
  - 渐隐遮罩抽成 `WXGRimFadeLayer`（与 FIX72 的结构、贴图、布局逐行相同），描边和取色线条共用。
  - `WXGRimView`：FIX72 的边框 + 渐隐；两侧 / 中间仍是 CA 边框；内侧阴影改为“裁剪层（内缩线宽，连续圆角）里一个外扩 0.5 pt、厚边框的 CA 图层投出的阴影”（不再用圆弧路径的 shadowPath），阴影层 shouldRasterize。
  - `WXGRimTintView`：遮罩不再是图片，而是一个容器：里面一个持有层放 CA 边框（连续圆角、线宽、两侧亮度）和居中边框，持有层的 mask 是同一个渐隐层，持有层 opacity = 线条不透明度。删除 FIX76/77 的环形图生成、缓存、缩放和延迟补图。
  - 透镜：不加细节、不加取色层（`_lensTint` 删除），只换颜色来源；Metal 透镜里的底栏轮廓颜色在取色开启时同样用材质颜色处理后的颜色。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过（取色线条的遮罩里嵌套了一层遮罩，是否按预期生效需真机确认）。

# FIX77 验证

- 和 FIX76 相比：
  - `WXGOpticalSettings.m`：“描边取色”组从材质模块移到边框模块（FIX76 的插入锚点匹配到了材质模块的“浅色模式”组）。
  - `WXGGlassView.m`：`WXGMakeRimRing` 在半径 > 0.3 × 短边时不用 renderInContext，改用 CG 偶奇填充画圆弧圆角的环（两侧环 + 居中环）；小半径仍用 CA 边框离屏渲染。用户截图里 FIX76 在圆形 / 胶囊上只有每边中间的直线段，推断是离屏渲染器对大半径连续圆角的处理与屏幕不一致（FIX74 的四个尖与此相同）。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX76 验证

- 和 FIX75 相比：
  - `WXGRimDetail.h`：`WXGRimSampleMatrix`（饱和度、对比度、增益、提亮，再接原“亮度”语义的颜色矩阵，alpha 不变）、`WXGRimRingExtent`；`Tests/RimDetailTests.c` 加矩阵检查。
  - `WXGGlassView.m`：新 `WXGRimTintView`（自身图层是 CABackdropLayer，加入玻璃的背景组；滤镜：高斯模糊 + 颜色矩阵；默认普通合成，可选 plusL；遮罩 = 原边框本身的图：两层 CA 边框（全宽 × 两侧亮度、居中内缩全亮）用 renderInContext 画出，再乘原来的对角渐隐场；长边 1 pt 拉伸；胶囊高度变化先等比缩放、停 0.15 s 后补精确图；不透明度放在遮罩图层的 opacity 上）。`WXGRimView` 加 `lineHidden`（取色时只留内侧阴影）。主体 / 透镜各一个，放在对应描边之上。诊断 `rims` 加取色状态。
  - 配置 7 个键（`rimSampleColor`、`rimSamplePlusLighter`、`rimSampleSaturation`、`rimSampleContrast`、`rimSampleGain`、`rimSampleLift`、`rimSampleBlur`），设置“描边取色”组。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过（遮罩图层的 opacity 是否作用在 backdrop 的遮罩上、普通合成下颜色矩阵的结果，未实机确认）。

# FIX75 验证

- 和 FIX74 相比：
  - 删除 FIX73/74 的图像式描边（`WXGRimProfile.h`、`Tests/RimProfileTests.c`、距离场生成、背景取色的 CABackdropLayer、9 宫格图、相关 13 个配置键和设置组）。主体描边恢复 FIX72 的放置方式（`drawnBar` + 半径 × barScale）。
  - 新 `Sources/WXGRimDetail.h` + `Tests/RimDetailTests.c`：两侧 / 中间不透明度（中间合成后严格等于原不透明度）、中间带内缩。
  - `WXGGlassView.m`：`WXGRimView` 仍是原边框 + 原渐隐遮罩；细节开启时自身边框降到两侧不透明度，再加一个内缩的居中边框层；内侧阴影是裁剪到线内侧（连续圆角）的图层，用 shadowPath 画一个外矩形（顺时针）+ 略大于裁剪的圆角孔（逆时针）的环，只露出向内的模糊。都在原渐隐遮罩之下。诊断 `rims` 改为细节状态和样本。
  - 配置：`rimDetails`、`rimSideLevel`、`rimCoreWidth`、`rimInnerShadowHex` / `darkRimInnerShadowHex`、`rimInnerShadowOpacity` / `darkRimInnerShadowOpacity`、`rimInnerShadowRadius`、`pressStretchNative`；设置页“描边细节”组、交互组新开关。
  - `WXGSurface.m`：materialOnly 的玻璃（输入框、首页左上角）拉伸受 `pressStretchNative` 控制。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX74 验证

- 和 FIX73 相比：`WXGGlassView.m`：
  - 线图改用 `CGBitmapContextCreate(… NULL, kCGImageAlphaOnly)` + `CGBitmapContextCreateImage`，阴影图改用 RGBA 位图上下文（FIX73 用 `CGImageCreate` 加 NULL 颜色空间建 alpha-only 图，返回 NULL，所有形状都生成失败）。
  - 形状覆盖改用 RGBA 上下文画、取 alpha；没画出东西或距离场失败时，改用圆角公式的解析覆盖再算一次。
  - 失败记录在配置版本变化时清空（改设置即重试）。
  - 全局统计和所有描边视图的弱引用表；`WXGRimSummary()` 导出到诊断的 `liveSamplingAtExport.rims`；单个描边的 evidence 加尺寸和是否在屏。
- `WXGIntegration.h`（声明）、`WXGHost.m`（导出 `rims`、版本号）。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX73 验证

- 和 FIX72 相比：
  - 新文件 `Sources/WXGRimProfile.h`（描边截面、内侧阴影、9 宫格角区范围、取色矩阵，纯 C）、`Tests/RimProfileTests.c`、`ReferenceAnalysis/FIX73_rim.md`。
  - `WXGGlassView.m`：`WXGRimView` 加 iOS 26 模式——主线程用 Core Animation 画一次形状（连续圆角，2×2 超采样，四周留 3 px 空白），后台算距离场和截面 × 渐隐，生成线的 alpha 图和阴影图（长边 1 pt 拉伸，`contentsCenter`），按形状缓存、同形状共用；线是一层 CABackdropLayer（加入玻璃自己的背景组，滤镜：高斯模糊 + colorMatrix，合成：滤色，可改加亮），蒙版是线图；阴影是普通图层；新模式下视图自己不带蒙版、不画边框。胶囊高度变化用等比缩放，其他尺寸变化先拉伸旧图，停 0.12 s 后再生成。轻量玻璃（设置卡片）用普通图层 + 材质颜色。主体描边改为未缩放的 glassRect + 按压缩放变换。
  - `WXGHost.m`：目标路由不可用时先 `dropDepartingButtons`。
  - `WXGPressStretch.h`：`WXGStretchReach`（变换后圆角矩形的精确半宽高）、`WXGStretchFit`（二分出能留在裁剪框里的拉动比例）；`WXGSurface.m`：`stretchClip`（上层 clipsToBounds / 蒙版的范围），拉伸目标和每帧显示都按它限制；诊断 `stretchClip`。
  - 配置 14 个新键（`rimAdaptive`、`rimPlusLighter`、四个强度、饱和度 / 对比度 / 提亮 / 模糊、两个阴影浓度、阴影宽度），设置页“边框与渐隐”新组，版本号。
- C 测试 46 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 离线用同一套距离场 + 截面代码（圆角用解析近似代替 Core Animation）生成了胶囊和圆按钮的描边图，合成在三张参考截图的背景上看过：线条平滑无锯齿，肤色上偏金、浅色上近白、深色上浅灰，对角处变细变淡。
- 没有在真机上运行过。

# FIX72 验证

- 和 FIX71 相比：`WXGSurface.m`（跟随名单只在触摸结束且姿态回到静止后清空；按下时不再立即刷新；诊断 `stretchFollowers`）、版本号。
- C 测试 45 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX71 验证

- 和 FIX70 相比：`WXGSurface.m`（触摸开始时 `collectFollowersIn:` 找出完全落在玻璃上的最外层视图；`poseFollowers:` 给它们的图层加叠加的 transform 动画，变换按同一姿态绕玻璃中心换算；回到静止时移除；dealloc 时清理）、设置说明、版本号。
- C 测试 45 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX70 验证

- 和 FIX69 相比：`WXGPressStretch.h`（姿态平移改为拉长量 × 0.45 沿拉动方向，不再加整个拉动位移）、`Tests/PressStretchTests.c`（远端最多动拉长量的 10%、拉多远中心最多移 0.45 × 强度 × 上限）、`WXGSurface.m`（`WXGTouchObserver` 被动识别器与 `observeTouchesInView:`，仅 materialOnly 的玻璃使用）、`WXGHost.m`（首页左上角）、`WXGInput.m` / `WXGNativeInput.m`（输入框，挂在输入工具栏上）、`WXGEdgeFade.m`（单元格颜色与列表背景色明暗差 > 0.35 时用单元格颜色垫底）、设置说明、版本号。
- C 测试 45 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上运行过。

# FIX69 验证

- 和 FIX68 相比：`WXGSurface.m` / `WXGDockSearch.m`（拉伸时整个触摸期间保持按下和跟手，松手时 40 pt 内才算点击；按住时拒绝其他视图的非边缘拖动手势开始）、`WXGEdgeFade.m`（底板颜色：列表背景色 → 背景视图颜色 → 后面没有不透明内容时用系统背景色）、设置说明、版本号。
- C 测试 45 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- deb：Linux 上用 clang 18 + ld64.lld（iOS 16.5 SDK 的 .tbd）链接，`ldid -S` 签名，rootless 布局（`/var/jb/Library/MobileSubstrate/DynamicLibraries`，`iphoneos-arm64`）。
- 没有在真机上运行过。

# FIX68 验证

- 和 FIX67 相比：
  - 新文件 `Sources/WXGPressStretch.h`（橡皮筋、拉伸姿态、跟手 / 松手弹簧、底栏两端拉长，纯 C）和 `Tests/PressStretchTests.c`。
  - `WXGSurface.m`、`WXGDockSearch.m`：按下记录起点，拖动时按橡皮筋设目标位移，每帧弹簧推进；按压姿态之后再乘拉伸矩阵（斜向时是对称矩阵），玻璃、图标、文字、角标同一变换；按住 / 点击范围在开启拉伸时为玻璃外 40 pt。
  - `WXGDemoBar.m`：透镜拖过两端时 `followEndStretch`，玻璃视图和点击动画层同一变换（远端不动），角标跟着；玻璃和动画层改为用 bounds + center 放置（有变换时 frame 不可用）。`WXGHost.m`：搜索按钮那一侧的拉长上限（间距 × 0.75）；版本号。
  - `WXGConfig`：`pressStretch`、`pressStretchDistance`、`pressStretchAmount`、`dockEndStretch`、`dockEndStretchDistance`；设置页“基本设置 → 交互”和“底栏 → 透镜”。
- C 测试 45 个全部通过（新 `PressStretchTests`：橡皮筋单调且不超过上限、静止时等于按压姿态、横拉 / 竖拉 / 宽胶囊的点数、斜拉对称、子视图跟随、跟手弹簧几乎不过冲、松手过冲 1.2–3.5 pt（10 pt 起）且 0.8 秒内停稳、底栏远端不动近端外移 o、反向过冲时压短）。
- Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上编译、运行过。

# FIX67 验证

- 和 FIX66 相比：
  - `WXGEdgeFadeMath.h`：`WXGHomePanelProgress`（小程序页展开程度）；`Tests/EdgeFadeTests.c` 加了它的测试（静止、小幅下拉为 0，展开为 1，单调）。
  - `WXGEdgeFade.m`：`WXGHomePanelProgressForController`（找 `WAMainFrameTopHeaderView`，按它的下边缘算）；首页的遮罩里加一层不透明层（不透明度 = 展开程度），模糊带强度乘以 (1 − 展开程度)，完全展开时隐藏。
  - `WXGHost.m`：`WXGRoute.presentedStack`（整屏弹出的导航里的聊天按普通聊天处理）、从这种聊天返回弹出页时不再挂起而是复原；`updateHomePanel` / `homePanelDrop`（底栏行跟着展开程度下滑，和键盘上移合成一个位移）；诊断 `presentedChat`；版本号。
- C 测试 44 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上编译、运行过。

# FIX66 验证

- 和 FIX65 相比：`WXGEdgeFade.m`（列表背景色不透明时在列表下方加 `WXGEdgePlateView`，跟随列表位置、大小、颜色、隐藏）、`WXGNative.m`（底板的类加进 `WXGIsPluginView`）、版本号。
- C 测试 44 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上编译、运行过。

# FIX65 验证

- 和 FIX64 相比：`WXGEdgeFade.m`（上下各自的强度；“其余页面”加 `NewSettingViewController` 和 `WXGSettingsPage`；插件设置页用壁纸覆盖层代替列表遮罩）、`WXGConfig.m` / `WXGCommon.h`（强度拆成上下两项，0–8，默认 3）、`WXGOpticalSettings.m`（每组 6 个滑杆）、`WXGSettingsKit.h` / `WXGSettings.m`（`wallpaperView`）、`WXGNative.m`（覆盖层的类加进 `WXGIsPluginView`）、`WXGHost.m`（页面出现的通知移到插件自身页面的判断之前；版本号）。
- C 测试 44 个全部通过；Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；设置覆盖检查 0 个问题。
- 没有在真机上编译、运行过。

# FIX64 验证

- 和 FIX63 相比：
  - 新文件 `Sources/WXGEdgeFade.m`（渐隐与模糊模块，已加进 `Makefile`）、`Sources/WXGEdgeFadeMath.h`（渐隐曲线、模糊表，纯 C）、`Tests/EdgeFadeTests.c`。
  - `WXGHost.m`：页面出现 / 布局时通知模块；诊断 `edgeFade`；版本号。
  - `WXGConfig.m` / `WXGCommon.h`：10 个配置项（两组 × 5）。`WXGNative.m` / `WXGIntegration.h`：开关 `edgeFade`，模糊带的类加进 `WXGIsPluginView`。
  - `WXGOpticalSettings.m` / `WXGSettings.m`：“渐隐与模糊”模块和首页卡片。
  - 底栏搜索、玻璃、着色器和其余参数没有改。
- C 测试 44 个全部通过（原有 43 个 + `EdgeFadeTests`：两端透明、带外不透明、中点 0.5、单调、0.5 pt 以下关闭、超过列表高度按列表高度、上下重叠取较小；模糊表两端 1 和 0、单调不升、表里各点的原值）。
- Objective-C：17 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0；`tools/check_settings_coverage.py`（对 FIX57）0 个问题，新模块的 11 项都在。
- 没有在真机上编译、运行过。

# FIX63 验证

- 和 FIX62 相比：`WXGDockSearchLayout.h`（软回弹、按钮在右不交换）、`WXGDockSearch.m`（重写：独立输入区、按钮自带 ×、展开后可作关闭）、`WXGDemoBar.m`（`showsClose`）、`WXGHost.m`（形状与输入区分配、去掉换行、宽度上限）、设置说明、测试、版本号。
- C 测试 43 个全部通过；`DockSearchLayoutTests` 重写：两种行、左右两侧，静止 / 搜索端点（搜索框都在左、关闭都在右）、间距全程不变（含越过终点）、0–1 之间不出行且不窄于圆形、越过终点最多压扁 1/4、越过终点每一步都在动（没有平台）、外鼓、曲线、弹簧。
- Objective-C：16 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0。
- 没有在真机上编译、运行过。

# FIX62 验证

- 和 FIX61 相比：`WXGHost.m`（第一响应者查找、填入和搜索键、首页入口轮询、外鼓）、`WXGDockSearch.m`（只在展开时允许获得焦点）、`WXGDockSearchLayout.h`（`WXGDockSearchSwell` / `WXGDockSearchSwellAmount`）、测试、版本号。
- C 测试 43 个全部通过；`DockSearchLayoutTests` 加了外鼓：只移动外侧两端、间距不变、高度加三分之一、静止时为 0、速度和越过量的数值。
- Objective-C：16 个 `.m` 语义检查和 arm64 编译 0 个诊断；未使用的 static：0。
- 没有在真机上编译、运行过。

# FIX61 验证

- 和 FIX60 相比：`WXGDockSearchLayout.h`（两行插值）、`WXGHost.m`（布局、不自动弹键盘、交接重试与写入、表头处理）、`WXGDemoBar.m`（静止判断加上高度，去掉模糊）、`WXGDockSearch.m`（初始阴影）、`WXGGlassView.m` / `WXGCommon.h`（删掉模糊函数，加三个配置项声明）、`WXGConfig.m`（三个配置项）、`WXGOpticalSettings.m`（三个滑杆）、版本号。
- C 测试 43 个全部通过，原有 42 个输出与 FIX60 相同；`DockSearchLayoutTests` 加了独立搜索行的情况（端点、两侧镜像、始终在过渡中的行内、间距不变、不窄于圆形）。
- Objective-C：16 个 `.m` 用 iOS 16.5 SDK 做完整语义检查并编成 arm64 目标文件，0 个诊断。未使用的 static：0。
- 没有在真机上编译、运行过。

# FIX60 验证

## 和 FIX59 相比改了什么

- **新文件**
  - `Sources/WXGDockSearch.m`：搜索按钮（一块底栏材质的玻璃、放大镜、输入框、按压鼓起）。已加进 `Makefile`。
  - `Sources/WXGDockSearchLayout.h`：整行布局、弹簧参数、淡入淡出曲线（纯 C）。
  - `Tests/DockSearchLayoutTests.c`：上面这个头文件的测试。
- **`WXGDemoBar.m`**：搜索时的形变（玻璃轮廓、用普通图层画的静止标签栏、×）、× 的点按、无障碍；点按滑行动画结束时不会把形变中的覆盖层放出来。
- **`WXGHost.m`**：
  - 底栏和搜索按钮放进同一行（`dockRow`），按键盘位置整体上移；
  - 弹簧、打开 / 关闭、交给微信搜索、隐藏顶部搜索栏；
  - 诊断 `dockOwnership.search`；版本号；
  - 页面扫描不再逐个视图取类名（另见 `WXGNative.m`、`WXGBackdrop.m`、`WXGDecorations.m`、`WXGNativeInput.m`）。
- **`WXGGlassView.m`**：`shapeAnimating`（轮廓动画时不重建只给 Metal 覆盖层用的距离场）、覆盖层隐藏时也不建；`WXGSetLayerBlur`。
- **`WXGNative.m`**：三个新开关（`dockSearch`、`dockSearchLeading`、`hideTopSearch`）；`WXGIsPluginView`。
- **设置**：“底栏”模块加了“搜索”一组三个开关；首页卡片副标题。
- 其余文件、着色器、全部光学参数和默认值没有改。

## 检查

- **C 测试**：`sh tools/test_geometry.sh`（`-Wall -Wextra -Werror`）43 个全部通过，原有 42 个输出不变。新的 `DockSearchLayoutTests`：
  - 静止 / 搜索时两段的位置和宽度（搜索框和原来标签栏一样宽），左右两种；
  - t 从 -0.3 到 1.3：两块都不出整行、都不窄于圆形、间隔在 0–1 之间不变、回弹时至少留 35%、标签栏宽度单调、左右镜像；
  - 太窄的行保持圆形；
  - 淡入淡出曲线的端点；
  - 弹簧（230 / 20 / 1.2）：两个方向回弹 6%–12%，0.75 秒内稳定，最后正好停在目标。
- **Objective-C**：iOS 16.5 SDK 真实头文件，`-target arm64-apple-ios14.0 -fobjc-arc -Wall -Wextra -Werror`：
  - 16 个 `.m` 文件语义检查 0 个诊断；
  - 16 个都编成 arm64 目标文件，0 个诊断；
  - 没有用 `@available`。
- `python3 tools/check_unused_statics.py`：0。
- **网格耗时估算**：形变时每帧按新宽度重建折射网格。本机测得一块 68–340 pt 宽的底栏网格约 0.07–0.1 ms（C 部分），所以两块玻璃、每块最多 6 层（RGB 色散 + 清晰环）每帧约几毫秒；开了流畅模式是 2 层。

## 没有验证的

- **没有在真机上编译、运行过**。
- 交接给微信搜索：用的是诊断里看到的入口（首页右上角 `onSearchButtonTapped`，以及列表表头里的 `WCSearchBar`）。微信的搜索框什么时候、以什么方式开始编辑，只能在真机上看；诊断 `dockOwnership.search.lastHandoff` 会写下结果。
- 隐藏顶部搜索栏：按诊断里的结构（`WCSearchBar` 在 `MainFrameTableView` 的表头里）写的；微信自己改表头高度时会再收一次，次数在 `dockOwnership.search.topSearchBar.hides`。
