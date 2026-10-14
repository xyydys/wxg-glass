# WeChat Liquid Glass · TEST4 FIX24

版本 `0.4.24-test4fix24`，基于 FIX23。只改了 `WXGGlassView.m`（同步模式网格）与版本号，其余 28 个源文件与 FIX23 逐字节相同（`tools/audit_fix24_scope.py`）。

## 圆心的亮点和一圈圈的纹路

截图放大后能看到：按钮圆心有一个小亮斑，周围有一圈圈的明暗带，而且边缘那圈强折射被“拖”进了本该不变形的中间区域。这是网格**细分平滑**造成的：Core Animation 可以把网格的相邻顶点做平均，让网格更圆滑。这会把边缘陡峭的折射映射拖进中间，并把所有环汇合的圆心挤成一个点。

FIX20–23 想关掉平滑，但只在网格对象有设置方法时才设置。网格工厂返回的是不可变类型，没有这个方法，于是一直用着系统默认的自动平滑。这也解释了 FIX20 那时折射发软的一部分原因。

FIX24：先取网格的可变副本，再明确把细分步数设为 0，并把实际值写进诊断（每块玻璃 `materialLayers` 的 `meshSubdivisionSteps`，应为 **0**）。另外修正了“网格是否被接受”的判断：之前按对象地址比较，图层保存副本时会误报为未接受。

## 安装

```bash
cd /var/mobile && unzip -o WeChatLiquidGlass_0_4_24_TEST4_FIX24_flat.zip -d WeChatLiquidGlass_FIX24 && cd WeChatLiquidGlass_FIX24 && chmod +x build.sh && ./build.sh rootless
```

## 请确认

1. 导航按钮、底栏在同步模式下，圆心的亮斑和一圈圈的纹路是否消失，中间是否是干净的模糊。
2. 如果还在，导出诊断看 `meshSubdivisionSteps`：如果不是 0，说明这台系统上平滑关不掉，下一步换一种网格构造方式。

## 说明

按钮这么小（直径约 40pt），用你的折射 8.97 / 宽度 7.7pt 时，边缘最多把背景推开约 23pt，已经超过按钮半径，所以边缘一圈本来就会出现镜像拉伸。回读模式同理，这不是网格的问题。

本环境无法编译 Objective-C，请以手机端 `./build.sh` 为准。38 个 C 测试通过，括号结构检查与范围审计通过。
