# WeChat Liquid Glass · TEST4 FIX26

版本 `0.4.26-test4fix26`，基于 FIX25。只改同步模式：网格内部填充方式和背景采样分辨率。回读路径、着色器、光学等 24 个源文件与 FIX25 逐字节相同（`tools/audit_fix26_scope.py`）。

## 开色散时内部的青色圈

FIX25 的内部填充比最后一圈环向外多铺了 1pt，在不变形区域重叠。我原以为重叠无害，但色散的绿、蓝两层是“相加”合成的：同一处被两个面覆盖时，绿和蓝各加了两次，红只画一次（红层是普通合成）。于是沿着那 1pt 的重叠带出现了一圈青色（青 = 绿 + 蓝）。测试显示 FIX25 每块玻璃约有 2–4% 的点被重复覆盖。

FIX26 改为“拉链”式收口：最里一圈环上半部分的每个顶点，与下半部分对称位置的顶点直接连成四边形，共用环自己的顶点。覆盖完整，没有任何重叠。为此，圆弧采样整体偏移半步，没有顶点恰好落在左右两端的尖点上，也就不会有退化面。

测试（底栏、导航按钮、输入胶囊、透镜、圆角矩形）：重复覆盖的点 0（FIX25 为 132–1119 个），退化三角形 0，每个位置 1 个顶点，内部误差 0，边缘精度不变。

## 关掉模糊后的像素感、锯齿

放大截图后，“好”字的斜笔画是约 3 个屏幕像素一级的台阶。在 3x 屏上，这说明背景是按每点 1 像素采的。我之前把背景层的 `scale` 设成了 1.0，以为 1 就是原生分辨率；实际看起来它是按“每点像素数”理解的，或者网格那一步是按图层默认的 1 倍栅格化的。开着模糊时看不出来，关掉模糊就成了像素画。

FIX26 把背景层的采样倍率、`contentsScale`、`rasterizationScale` 都设为屏幕倍率，3x 屏上就是 3。新增设置“同步模式采样倍率”：0 = 跟随屏幕（默认）。如果改完反而明显变卡，说明这台系统把它理解成相对倍率；这时把它调到 1 即可，并请把诊断发我。

诊断（每块玻璃 `materialLayers`）：
- `backdropDefaultScale`：背景层原本的默认值；
- `backdropRequestedScale` / `backdropAppliedScale`：我们设的值，以及系统实际接受的值；
- `meshBuilder` 应为 `contour_zipper_FIX26`，`meshSubdivisionSteps` 应为 0。

## 安装

```bash
cd /var/mobile && unzip -o WeChatLiquidGlass_0_4_26_TEST4_FIX26_flat.zip -d WeChatLiquidGlass_FIX26 && cd WeChatLiquidGlass_FIX26 && chmod +x build.sh && ./build.sh rootless
```

## 请确认

1. 开 RGB 色散：内部不再有青色圈。
2. 关掉模糊和材质覆层色：玻璃里的字和原图一样锐利，没有台阶。
3. 同步模式的流畅度和之前一样。

本环境无法编译 Objective-C，请以手机端 `./build.sh` 为准。38 个 C 测试通过（`Tests/ContourMeshTests.c` 新增“无重复覆盖”检查）；括号结构检查与范围审计通过。
