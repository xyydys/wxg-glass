# WeChat Liquid Glass · TEST4 FIX53

版本 `0.4.53-test4fix53`，基于 FIX52。只改点按 / 按住时的透镜；着色器、网格、透镜光学与 FIX52 逐字节相同（`tools/audit_fix53_scope.py`）。

## 为什么之前透镜内外一样高

点按另一个标签、或按住时，你看到的透镜不是 Metal 画的那个，而是 FIX44 移到系统渲染服务里的透镜（为了滑动不掉帧）。它自己取一份画面，里面包含整条全高的底栏，然后整体折射，所以透镜内外的底栏一样高。FIX46–FIX52 的内缩、45° 过渡、两端分离都只改了 Metal 透镜，只在手指拖动时看得到，点按时一个都没生效。

## 现在

点按 / 按住的透镜仍然完全在渲染服务里运行（流畅度不变），只做了两处改动：

1. **取样换成和玻璃共用**：透镜里看到的是底栏下面的页面，不再是全高的底栏（与拖动时的透镜相同）。
2. **内部缩小的底栏由这个透镜自己画**：材质（与底栏同色同不透明度）、边框（与底栏边框同色、同宽、同样按方向渐隐）、选中色，形状与拖动透镜的公式一致：
   - 中段：上下各内缩一段，内缩深度随按压变化（你的设置下浮起时约 3.8pt）；
   - 透镜轮廓与底栏边框相交处：外侧边框沿约 45° 的短斜线接到内部缩小的边框；
   - 到了底栏两端（交点进入圆弧）：这一侧不再过渡，内部底栏显示自己的圆头，和透镜边之间是一道缝，与 iOS 26 录屏一致；
   - 落回静止时内缩归零，与原来一样交还给逐帧的底栏。

`ReferenceAnalysis/FIX53_travel_inner_simulation.png` 是按你的参数算出的样子，三行依次是：底栏中段、末端标签、交点刚越过直线段末端的一瞬间。每行三张：几何示意、点按透镜（新）、拖动透镜（着色器公式）。点按透镜的内部底栏与拖动透镜逐像素一致（中段、末端 0.00% 不同，过渡瞬间 0.06%）。

**和拖动时仍有的区别**：拖动时内部底栏的边缘靠近透镜边会被折射弯曲一下；点按透镜的边缘是直的。渲染服务里的图层没法逐帧算这种弯曲。

## 安装

```bash
cd /var/mobile && unzip -o WeChatLiquidGlass_0_4_53_TEST4_FIX53_flat.zip -d WeChatLiquidGlass_FIX53 && cd WeChatLiquidGlass_FIX53 && chmod +x build.sh && ./build.sh rootless
```

## 验证边界

本环境无法编译 Objective-C，请以手机端为准。已完成：
- 41 个 C 测试（`-Wall -Wextra -Werror`），新增 `TravelInnerTests`：
  - 内缩与拖动透镜相同；
  - 过渡与 FIX51 的公式逐点相等，平均斜率 45°；
  - 边框正好在内侧半个线宽；
  - 静止时是一条直线；
- 按你的参数做的形状对比（上面那张图）；
- `tools/check_unused_statics.py`（0）、括号结构检查、范围审计、源码中没有 `@available`。

诊断的 `dockInteraction` 里新增 `travelCaptureGroup`（应为 `wxg.glass.…`）、`travelInnerInsetAtLift`、`travelInnerVeilAlpha`、`travelInnerRimWidth`，如果点按透镜看起来不对，导出一份就能看出它用的取样和内缩值。
