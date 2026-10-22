# 交接说明（给新对话）· WeChat Liquid Glass TEST4 · 当前 FIX114 G（用户 01:48 导出的参数作为这版默认；手机上没改过的设置换成新默认、改过的保留；基于 FIX114 F）


## FIX114（用户 17:16，附 diagnostics_11 和帧率 JSON：“分组可以了；首页顶部下拉时中间胶囊有概率在原位置留下空白胶囊；替换了搜索框的分组下拉时和胶囊设定的间距会变动而不是固定；右上角加号边缘显示不全，不知道是微信还是插件；感觉性能有一点问题，卡顿看能不能找到原因优化”）

- G（用户 10-23 01:50，附 WeChatLiquidGlass_settings_20261023_0148.json：“差不多了，参数也给你了，只针对没有改动过的设置项采用这套参数，已经被自定义过的不覆盖，实在做不到强制覆盖也行；编译 deb 的同时给最新的完整工程文件”）：
  - 默认值：`python3 tools/bake_defaults.py <导出的 json>` 写进 `WXGBuildProfile.h`：config 681/681（全部键，去掉总开关）、开关 20、设置页圆角 1（导出里没有强调色 = 不设）。和旧默认（FIX84 起那份，253 个键，其中 7 个是已删的平稳背景键）比，两边都有的 246 个键里 67 个值变了、新加 435 个（旧那份没有的键以前用代码里的默认）；开关变了 4 个（右上角头像标题开、底栏搜索关、原生输入栏测试关、整体大小 1.0143 → 1.0975）。
  - 怎么分辨“没改过”：手机上存的是每个键的值（`optics.test4` 等），不记哪个键被动过；所以按“和上一版的默认值一样 = 没改过”：
    - `bake_defaults.py` 写新默认时把被替换的那份留成 `WXG_PREVIOUS_DEFAULT_OPTICS_JSON`（同一个文件再烤一次不动它；以后再烤别的文件，就把当时的默认留成上一版）。
    - 新版第一次启动（每份新默认一次，`WXGBuildDefaultsStamp` = 默认 JSON 的 FNV-1a 哈希 + 长度，记在 `defaultsStamp.config` / `.integration` / `.ui`）：`WXGConfig`、`WXGPreferences`、`WXGSettingsStore` 的 shared 建好后各跑一次 `adoptBuildDefaults`：上一版默认（上一份 JSON 盖在代码默认上，`initWithBuildDefaults:` 算出全新安装时的全部值，含继承的键；开关：上一份里的值，没有就代码默认）和新默认不同的键，手机上的值等于上一版默认（数字相对误差 1e-5，颜色按规范化的十六进制）就换成新默认，否则保留。直接写回设置（这时在建 shared，不发改动通知）。总开关、首页搜索、帧率记录、壁纸、头像、分组列表不在里面。
    - 全新安装：本来就是新默认，只记下印记。用户自己那台（值就是导出的这份）基本不会动。
    - 限制：只认上一版的默认。跳过中间版本、手机上还是更早一版默认的值，会被当成改过的而保留；在“恢复本版默认参数”里可以手动换成新的。
    - 诊断 `runtime.defaultsAdoption`：印记、上一版默认的键数、每部分 `stored`（有没有存过）/ `moved`（换成新默认的个数）/ `kept`（保留的个数）。
  - 独立复查后改的：① 三处 adoptBuildDefaults 都包在 @try/@catch 里，印记在 @finally 里写（启动时在 +shared 里，出异常也不会每次启动都崩、也不会再跑），诊断里有 `error`；② 边框样式跟着它那一组走：某个范围（其它玻璃 rim… / darkRim…、dock、bubble、card、segment、lensGlass、segmentLensGlass）的边框设置里有任何一个是自己调过的，这个范围的 `…RimStyle` 也保留（这次 rimStyle 2→0、dockRimStyle 2→0、bubbleRimStyle 2→1，只换样式会把调好的 iOS 27 高光藏起来）；③ 一次性迁移的标记 `dockTitleWeightNative`、`segmentDockLook` 不参与；④ 开关：手机上没存过的开关按代码默认比；上一版默认里没有 integration / ui 部分时按代码默认算（只要上一版有默认）；⑤ `bake_defaults.py` 只在被替换的那份就是已提交（git HEAD）的那份时才把它留成上一版——提交前再烤一次（同一个或别的文件）不会把“上一版”变成手机上从没有过的那份；`--keep-previous` 不动上一版；⑥ control 的 Name / Description 更新。
  - 完整工程：`git archive` 打包当前提交（不含 dist 里的编译产物和 .git）。
  - 版本 0.4.114-test4fix114g。服务器不变。
- F（用户 10-23 00:57，附开 / 关插件的首页截图、探针 WGP_20261023_005433_797_baseline.zip、diagnostics_13：“这两个要是能是一个高度的，我直接跟你姓得了，而且它该跳还是跳啊”）：
  - 量错的东西：E 量的是 UISearchBar 自己的输入框（及其背景，8,11,398×32.67，在窗口 y=99），它被微信的 WCSearchBar 盖住、根本看不见。探针（不开插件的首页）：表头 UISearchBar(0,88,414,55) › UIView › WCSearchBar(0,88,414,55) › UIStackView › UIStackView › 一个类名正好是 UIView 的圆角块（r 6，#191919）= 看得见的搜索框，窗口 (8,92,398,36)，栏顶往下 4 pt；放大镜 UIImageView 24×24 在 (175.67,98)，“搜索” MMUILabel (203.67,100,34.67×20.33)，间距 4 pt。截图（XS Max 3x）：原生框 276–384 px = 92–128 pt；插件悬浮胶囊 297–393 px ≈ 99–131 pt——矮 3.3 pt、中线低 5.3 pt。diagnostics_13 的 `returnTrace` 只有一行 “y99.0 h32.7 float”、`fieldSource` “searchTextField background”，也是这个框。
  - `WXGVisibleSearchBox`（`WXGChatSegments.m`）：在 bar（或里面的 WCSearchBar）下找：类名正好是 UIView、圆角 ≥2、父视图是 UIStackView、高 24–60、宽 ≥ 栏宽 40% 的最宽那个（不看底色和 alpha：局部玻璃会清掉它的底色，插件会淡出整个栏）。`fieldRectIn:` 先用它（`fieldSource` = “WCSearchBar box”），找不到才走 E 的输入框背景 / 输入框。分组栏和悬浮搜索胶囊都用 `fieldRectIn:`，所以两个都是 398×36、y=92。
  - 跳的原因：返回首页的过程中，悬浮胶囊 / 分组栏和微信自己的栏（局部玻璃把看得见的 36 pt 框画成胶囊）会互相换着显示，一个 36 pt 在 y92、一个 32.7 pt 在 y99，换一次就上下跳 5 pt。现在两边同一个框，换的时候没有差。
  - 第一次量得太早（WeChat 还没排它的 stack view，框还是 0）会退回输入框的 32.7 pt：
    - 悬浮胶囊（`measureSlot:now:`）：找到这个搜索栏后，没量到画出来的框时第一秒每帧量、之后每 0.5 s、最多 80 次；量到过（`slot.exact`）就记下（`lastExact`），之后某次没找到也用记下的，不会退回输入框；固定着时每秒再量一次、没固定时 0.5 s，框的尺寸变了就重新抄图标和文字；每次从“没固定”变成“固定”（比如微信自己的搜索用完）都当场再量。第一次显示要等框和内容都是微信的（最多等 1 秒，等的时候显示的是微信自己的栏，局部玻璃画的是同一个框），所以不会出现先矮后高的一下。
    - 分组栏：`_fieldSource` 不是 “WCSearchBar box” 而现在能找到框时每 0.5 s 重新挂一次（`searchBarLaidOut:`），每次到首页 / 换了搜索栏最多 6 次，页面在滑动中不做。
  - 悬浮胶囊的内容（`WXGFloatingSearch copyLookOf:`）：在 WCSearchBar 里框内、自己和到 WCSearchBar 的父视图都没隐藏、alpha>0、不在输入框里的视图中，找“图标 + 紧挨着它右边的文字”这一对（图标 8–32 pt、同一行、间距 ≤16 pt；有几对取文字最大的）。抄图标的图片、tint、contentMode，文字的字体、颜色、对齐、attributedText（微信用富文本上色时颜色也对），位置就是它们在框里的位置（框居中放在胶囊里），所以胶囊的图标 / 文字和微信的完全重合；以前是 SF 的 magnifyingglass 15 pt + 16 pt 系统字、间距 5。没找到时第一秒每帧试、之后每 0.5 s，最多 90 次，找到前用旧的；深浅色（按搜索栏的 trait 比）变了马上抄一次、0.5 s 后再抄一次（微信可能按主题换固定颜色）。
  - 从聊天返回不再换：以前推进聊天后（转场结束）首页的悬浮胶囊就撤掉、微信的栏放回来，返回首页时滑回来的是微信的栏，转场结束才换成胶囊——这一换就是跳的那一下。现在别的页面是推在首页上面（同一个导航栈，`WXGPushedOver`）时胶囊不撤，跟着首页一起滑出去、滑回来，返回时根本不换。弹出的页面、换标签、网页 / Flutter（`suspendFloating`）、插件关 / 未授权照旧撤掉、还原微信的栏。
  - 诊断：`returnTrace` 现在只要最上面的页面变成首页（NewMainFrameViewController）就开始记（以前要等它是分组栏所在的页面）；没开分组栏时记 “capsule y.. h.. box y.. h..”（胶囊在窗口里的位置，hidden = 这时显示的是微信的栏；后面是微信画出来的框），转场中也记（带 T），只记变化，1.2 s 内。如果还跳，导出诊断看这一段。
  - 独立复查后改的：① 第一次显示前等框和内容（见上）、记下量到过的框；② 从没固定到固定当场再量、框尺寸变了重抄内容；③ 图标和文字按“一对”挑，排除输入框里的（占位文字），抄 attributedText 和对齐；④ 分组栏重量加了次数上限、转场中不做；⑤ 深浅色不用 traitCollectionDidChange（加进窗口前的 trait、退到后台时系统来回切都会触发多余的重抄），改为每帧比搜索栏的 trait；⑥ 诊断记在转场前、加上微信的框（约 30 ms 记一次）。
  - 第二次复查后改的：① 第一秒每帧量 / 抄的次数不算进上限（16 Pro Max 120 Hz 时第一秒就会把 80 / 90 次用完，之后再也不找）；② 被盖住 / 正在滑的页面上还固定着的胶囊，每帧（只在它在窗口里时）确认微信的栏还在同一个列表头里、胶囊还在同一个父视图、微信没在用自己的搜索，微信把栏的 alpha 改回来就再藏；不满足就撤掉、还原微信的栏；③ 微信的输入框开始编辑时，盖着它所在栏的胶囊马上撤（比如滑回首页过程中微信自己聚焦搜索）；④ 换了一个搜索栏（列表头重建）时先撤掉旧的，按“第一次显示”的规则重新等；⑤ 页面释放后它的胶囊从视图上拿掉。
  - 已知没做：首页 → 聊天 → 再推网页 / Flutter / 插件设置（`suspendFloating` 会撤所有胶囊）或弹出页面后再回到首页，转场结束时仍会从微信的栏换成胶囊（尺寸位置一样，只是玻璃画法可能略有差别）。
  - 版本 0.4.114-test4fix114f。服务器不变。
- E（用户 10-23 00:13：“三个样式的切换不是都要做成胶囊了吗怎么还是圆角矩形，直接删掉内部‘样式’两个字，外面的边框样式标题下换成之前范围的那种胶囊；首页搜索换成胶囊搜索框或者分组之后高度根本不对，不是原生搜索框的高度，从聊天返回还上下跳，直接按原本搜索框的大小和位置不是就很稳定吗；别的页面来通知之后的半屏聊天窗口输入框也丢失覆盖，还是原生的”）：
  - 边框样式（`WXGOpticalSettings.m`）：这一行去掉“样式”标题（`WXGBare`），整张卡片就是一条胶囊（`WXGSettingsCard.capsule`：圆角取高度的一半，不跟设置页圆角），三个选项铺满，选中的垫一块胶囊（内缩 5 pt，两端全圆）；其它多选一（底栏文字粗细、切换页面的时机）的轨道和选中块也改成两端全圆。
  - 首页分组栏（`WXGChatSegments.m`）：位置和大小就是微信的搜索框——去掉 FIX113 P / Q 的“宽度（占搜索框）”“加高”“与标题胶囊的间距”（设置页“位置与大小”组和 4 个键删除；用户诊断里设的是宽 96%、加高 5.2 pt、间距开 4 pt，所以比原生高、窄，而间距按标题行每次重算，回到首页时会重算一次——从聊天返回上下跳的来源之一），下拉时 FIX114 A 的“保持和标题行的距离”也去掉（跟着微信的搜索框走）；悬浮（列表往上滚时停在标题行下）保留；只有“顶部按钮往下移”大于 0 时跟着下移。微信搜索框的尺寸：UISearchBar 的输入框背景视图（类名含 Background、和输入框差不多大时，`WXGSearchFieldBox`）优先，否则输入框本身（诊断里是 8,11,398×32.67）。诊断 `chatSegments.fieldSource`（“searchTextField background”表示用了背景视图）和 `returnTrace`（回到首页后约 1 秒内每帧分组栏的 y、高、在列表 / 悬浮、转场中、微信搜索框的 y）。
  - 首页搜索胶囊（局部玻璃，`systemSearchBar:`）：同样用 `WXGSearchFieldBox`（背景视图的框，没有就输入框）。
  - 半屏聊天（通知打开的，`WXGHost.m WXGSideChatInput`）：诊断里见过的结构是 `MMPageSheetContainerViewController`（全屏容器）里一个从 y=100 开始、796 高的聊天。以前这种因为容器全屏被当成“全屏弹出的聊天”整页接管；现在聊天本身不是整个窗口时就当成页面上的一张纸：下面的页面保持原样（宿主照 FIX67 的“被盖住”处理），这张纸里的聊天的输入栏由一个单独的输入栏适配器适配（同一个 `WXGInputAdapter`），用它自己的显示链接驱动（只在同步渲染模式下），微信布局 / 键盘变化时重排；聊天在另一个窗口里也一样。聊天关了、变成宿主的页面（拉成全屏）、插件或输入栏适配关了就撤掉。顶部按钮在这种半屏聊天里不接管（`leavesNavigationControlNative` 返回 YES，有“网页、弹出页面的顶部按钮”时垫胶囊）。诊断 `runtime.sideChat`：`now`（状态、窗口、位置、安装次数、重排次数、适配器）和 `log`（看到的每个不是宿主页面的聊天：窗口、根控制器、是否弹出、位置、当时宿主的页面、是否当成半屏）。
  - 独立复查后改的：① 宿主“自己的页面”只算它真在适配的（`adaptsChat:`：路由的页面且不是不支持的页面），半屏聊天盖在全屏弹出的聊天（从搜索打开的）上时，下面那个聊天按“被盖住”保留，半屏的由单独的适配器管（以前两边都没有）；② 控制中心 / 来电横幅等让应用暂时不活跃时半屏聊天的适配器等着、不撤（以前撤了就不回来）；③ 微信输入栏布局时在同一轮就重排半屏聊天的输入栏（以前晚一帧，会闪一下原生的）；④ 当成半屏的条件和路由一致，并且要整宽、在顶部以下、一直到窗口底部（`WXGSideChatSheetFrame`），推入 / 侧滑返回中的聊天、宿主自己导航栈里的聊天不算；⑤ 分组栏跟随下移：别的页面在最上面时不动 `_gapDelta`（以前推出聊天时清零、回来再加上，往下移大于 0 时会跳）；⑥ 半屏适配器装不上时只在有布局时再试，越来越慢，最多 30 次；⑦ 半屏聊天被盖住 / 隐藏时不做每帧的事，跟着纸移动时不再每帧重排；⑧ UISearchBar 量到微信的框后就用它，不再被搜索栏里更宽的视图顶掉；⑨ 设置搜索跳到胶囊卡片时高亮也是胶囊；其它：“套用底栏”提示里去掉“加高”，删掉不再用的 `navigationCapsuleBottomForPage` / `navCapsuleBottom`，`returnTrace` 只记变化。
  - 版本 0.4.114-test4fix114e。服务器不变。
- D（用户 23:35，附“边框与渐隐”页截图：“别的有问题再说，最后改设置的一个地方：作用范围换成只显示当前设置、箭头展开选择别的的样式，不然太多了排列也不美观；样式换成当前作用范围的那种，系统的圆角反而不好看，本来就是给低系统的；本次编译后我会调好所有参数作为默认设置，确保捕捉到我的所有设置让我导出，别漏掉”）：
  - 作用范围（`WXGOpticalSettings.m`，所有分范围的页面）：一张卡片只显示当前范围（加粗、强调色）和右边的 chevron.down；点开在卡片里往下列出所有范围（每行 46 pt，当前的垫一块胶囊），选一个就换页面内容并收起，选当前的也收起；玻璃卡片和下面的组都是一下子换到新位置（玻璃不做淡入 / 飞入），只有箭头转 180° 和列表文字淡入。卡片下面的说明只写当前范围的那一句（以前七个范围的说明全写在一起）。
  - 多选一（`WXGChoiceRow`：边框样式、底栏文字粗细、切换页面的时机）：不再用系统的 UISegmentedControl，改成和作用范围一样的样子——一条很淡的轨道（label 6%），选中项下面一块胶囊（强调色 22% 或 label 12%），点别的胶囊弹簧滑过去；会换页面内容的（边框样式）等胶囊滑完（0.24 s）再重排。
  - 导出（`WXGSettingsShare.m`）：核对过，“复制当前参数 / 导出参数文件”带的是 WXGConfig 的全部键（基础 155 + 表里 531，去掉总开关 = 685）、开关 20 个（去掉总开关、首页搜索、两个帧率记录开关）、设置页圆角和强调色；`tools/bake_defaults.py` 用一份含全部键的导出试过，685/685、20、2 全部收下。导出时去掉 JSON 存不了的值（非有限数），不会整份导出失败；复制后的提示写出三类各几项。不在里面的：总开关、授权、帧率记录开关、壁纸和头像（图片）、分组栏的分组列表（里面有具体聊天，属于个人数据）、帧率胶囊的位置。
  - 独立复查后改的：边框样式连点只重排一次（`performSelector:afterDelay:.34` 先取消上一次，等胶囊滑完；样式没变就不重排）；读屏：范围卡片有“已展开 / 已收起”的值，展开时焦点到当前范围、收起时回到卡片；滚到列表下面再收起时页面回到卡片处；多选一的胶囊在第一次排版前不设无效尺寸；页面重建时列表是收起的；按下时文字变淡；参数和诊断导出写 JSON 前先检查（有写不成 JSON 的值时给出提示，不会让微信崩）。
  - 下一步：用户导出参数后，`python3 tools/bake_defaults.py <导出的 json>` 写进 `WXGBuildProfile.h` 作为这版的默认（全新安装和“恢复默认”用它，已有设置的手机不受影响）。
  - 版本 0.4.114-test4fix114d。服务器不变。
- C（用户 18:56，附首页和聊天页截图：“首页左上角星标的位置没有跟随按钮的移动；首页顶部的胶囊和聊天页顶部的胶囊不知道为什么都切掉了一部分；分组透镜的边框需要跟底栏图标和字体透镜的参数分开设置；能不能调节这些顶部按钮离屏幕边缘的距离，左右的以及上下的”）：
  - 截图量（XS Max 3x）：首页左上玻璃圆心 41.8 pt、星标墨迹中心约 36 pt（= MainFrameLeftBarView 中心，star_baseline：宿主 16,46,40,40）——玻璃按 B 的 dx≈6 平移了，星标没跟。标题胶囊（首页“微信(343)”、聊天“Mixbubble(238)”）比两侧圆低一行像素：两侧圆 132–263 px 上下各一行最亮的边（157），标题胶囊顶上那一行（131 px）没了，只剩 132–262，正好在导航栏上沿 44 pt 被切；标题文字中线比栏中线高 1/3 pt，胶囊（和栏一样高）跟着文字就伸出栏外。
  - 星标（`WXGNative.m centerNativeImage`）：图标对齐时用 `[host convertPoint:hostMid toView:image.superview]` 算中心；图片不是宿主的直接子视图时，这个换算把宿主的 sublayerTransform（B 的内容平移）算进去，于是每次对齐都把图标往回挪了平移量，渲染时再平移回原处——玻璃动了、星标没动。宿主有内容平移时改为按 frame 逐级相加算中心（和不平移时同一个点）。诊断 `navSnapshots.NewMainFrameViewController.homeIcon`：玻璃中心、星标墨迹中心（窗口坐标）、平移、图片在宿主里的层数，2 秒最多量一次。
  - 标题胶囊被切（`WXGLocalGlass.m WXGLocalInsideBar`）：标题胶囊和原生按钮的胶囊放进它所在的 UINavigationBar 的范围里（按 frame 换算到栏，不受内容平移影响）；不在导航栏里（首页那一排如果不在栏里）就放进会裁剪它的父视图范围里（只在没往下移时）。只做最多 2 pt 的修正（文字故意放高放低的、滚出裁剪范围的不管，胶囊不会和文字分开）。宿主拿标题位置对齐按钮（`WXGLocalTitleCapsuleRect`）也用修正后的、按 frame 换算的矩形。
  - 分组透镜边框（`WXGGlassScopeSegmentLens`，键 `segmentLensGlass…` / `segmentLensGlassDark…`，57 个，每个都从对应的 `lensGlass…` 继承——第一次打开和底栏透镜当时的设置一样，导入只带了 lensGlass 的旧配置时也跟着；“把底栏的参数抄给分组栏”会把底栏透镜的边框也抄过去）：GlassView 里分组栏的玻璃（glassScope 分组）画透镜边框时用这个范围（`lensRimScope`），其余（底栏）还是 `WXGGlassScopeLens`。边框与渐隐页范围多了“分组透镜”，原来的“透镜”改叫“底栏透镜”；七个范围分两行排；描边细节组在两个透镜范围都不显示；“透镜滤镜色”组只在底栏透镜（分组的滤镜色在分组页）。诊断 GlassView `lensRimScope`。
  - 顶部按钮离屏幕两边 / 往下移（基本设置 › 标题与比例；`navEdge` 8–36 pt 默认 20 = 以前的 m.edge，`navOffsetY` 0–16 pt 默认 0；都乘截图比例 m.scale，往下移按像素取整；`WXGTitleRowEdge` / `WXGTitleRowOffset`）：
    - 边距：插件自己的按钮（左右起点）、首页左按钮的平移、标题宽度上限、局部玻璃原生按钮的整组平移（`WXGLocalSideShift`，B 只往里 ±24，现在两个方向都挪、±32，最外面那个胶囊正好在边距上）、插件设置页自己的顶部。
    - 往下移：宿主算出的标题行中线 centerY 加上它（插件的按钮、标题胶囊、头像模式、`navCapsuleBottom`）；首页“+”跟着原生位置（不含栏内容的下移）再加（`followHomeSurfaces` 也加）；首页左按钮的内容平移加 y（宿主在导航栏里时不加：栏的内容已经整体下移）；导航栏内容视图（`_UINavigationBarContentView`：微信的标题、原生按钮和它们后面的局部玻璃）整个用 sublayerTransform 下移——宿主（`buildNavigation → moveNativeRow → WXGMoveBarContent`）和局部玻璃（提交前，对有标题 / 按钮玻璃的栏；覆盖宿主不接管的网页、弹出页）共用一个状态袋 `WXGRowBag`，同一个栏谁来都一样；首页标题视图 MFTitleView 不在栏里时由宿主单独下移（找一次，1 秒内不重找）。视频号页面不移（视频上的按钮，转场到视频号时栏内容回到 0）。插件关 / 未授权 / 顶部按钮适配关时 `WXGRestoreBarContent`。
    - 下移时会把挡住它的“栏那么大”的裁剪关掉（`WXGRowClipBag allowOverflow`，高 ≤ max(64, 2×按钮)，不碰滚动视图和窗口），诊断 `openedClips` 列出类名；`rowBarContents` 是这个页面下移的栏内容视图个数（0 = 没找到 `_UINavigationBarContentView`，iOS 26 上要看一下）；`homeTitleOutsideBar`。
    - 聊天页置顶模块：不用头像模式时按下移量下移（`pinnedShift`，FIX109 B 的那套：容器下移、显示置顶时列表 inset 加上）；头像模式的位移改成相对微信原位（centerY0）算，所以也包含下移。
    - 首页分组栏：开了“自定义与标题胶囊的间距”照旧按胶囊底边算（底边已含下移）；没开时按下移量下移（`titleRowOffsetForPage:`，同样夹在列表头部里），所以默认设置下往下移也不会盖住分组栏。
    - 插件设置页自己的顶部按钮和标题也按这两个值摆，调的时候直接能看到（`configLookChanged` 里值变了才重排）。
  - 独立复查后改的（12 条）：
    ① 首页“+”在静止时其实在导航栏里（下拉时微信才把它和左按钮搬进列表头部），`WXGWindowRect` 已含栏内容的下移，再加一次就是两倍：改用 `WXGUnmovedWindowRect`（在栏里时按 frame 换算到栏），buildNavigation 和 `followHomeSurfaces` 都是；`WXGRowDownForBar` 不再因为栏隐藏返回 0（下拉时会来回跳）。
    ② 顶部按钮适配关掉时聊天置顶模块的下移也还原（`_pinnedShift=0` + `alignPinnedModule`）。
    ③ `allowOverflow:` 记原值改为这个袋子第一次改它的时候（以前是第一次 `remember:` 时，两个袋子交错会把关着的裁剪当原值，关插件后栏一直不裁剪）。
    ④ 下移打开的裁剪单独一个袋子 `WXGRowClipBag`，下移回到 0（设置为 0、视频号、宿主放手的页面）就按视图关回去；还原条件改用 `WXGPluginEnabled()`。
    ⑤ 首页标题从列表搬回栏里时自己的下移清零（否则栏内容再移一次是两倍）。
    ⑥ 栏内容画到栏下面那一段的点按：`UINavigationBar` / `MMUINavigationBar` 的 `hitTest:withEvent:` 在原来返回 nil、点在栏下沿往下 dy 以内时，交给画在那里的控件（有控件 / 手势的才算，否则不拦）。如果系统的命中测试本来就不跟 sublayerTransform 走，这一段找不到控件，什么也不变。
    ⑦ 只移动宿主排版的栏（`WXGRowHostBars`，buildNavigation 收进来）：网页、弹出页这些栏的背景和分隔线还是微信自己的，内容移下去会挂在分隔线下面，所以不移；宿主遇到不支持的页面（同一个栏里推进来的网页）把栏放回 0。局部玻璃提交前仍会调 `WXGMoveBarContent`，对这些栏就是 0。
    ⑧ 系统标题（“插件”页）的标题矩形按 frame 量（以前 convertRect 会把内容视图自己的下移算进去，再画一次就多了）。
    ⑨ 找不到 `_UINavigationBarContentView` 时（别的系统版本）改为移动栏里除背景外的子视图。
    ⑩ 分组栏跟随下移在顶部按钮适配关掉时为 0。
    ⑪ 首页图标对齐的诊断改到导出诊断时才量（`runtime.homeIcon`），不在布局里每 2 秒渲染一次。
    ⑫ 不在栏里的标题的裁剪修正不越过列表（下拉时不会粘在列表边上再跳回）；插件设置页拖“往下移”时下面的卡片不动（标题行只往它和卡片之间的空里移）。
  - 没做：往上移（会压到状态栏，范围最小 0）。系统的命中测试是否跟着 sublayerTransform 走、iOS 26 上栏内容视图的类名，都要真机诊断（`rowBarContents`、首页 `homeIcon` 的 `imageDepth` / 中心差）确认。
  - 版本 0.4.114-test4fix114c。服务器不变。
- B（用户 17:54，附 diagnostics_12 和帧率 JSON：“取消掉平稳背景时增强材质，代码都删除；首页那两个问题还在，可能这台低系统设备太卡，它们俩移动速度不一致所以间距不一致，额外出现的胶囊还是有概率；首页顶部两个按钮间距边距不一致；有的页面按钮位置没有修正还是原本的，挤在旁边；聊天不用头像顶部时，返回胶囊和图标回归微信原生，只加合适大小的自适应宽度胶囊；底栏图标和字体感觉也不原生，是我们干预过吗”）：
  - 诊断说明：两份诊断都是在插件设置页导出的，当前场景是设置页，首页 / 聊天的按钮位置看不到。新加 `runtime.navSnapshots`：每个页面最后一次顶部按钮的玻璃位置、原按钮位置、内容平移、左右边距（`leftMargin` / `rightMargin`，相对安全区）和 `m.edge`，最多 12 个页面。
  - 平稳背景时加强材质整个删除：`WXGCalmBackdrop.m`、`WXGCalmMath.h`、`Tests/CalmMathTests.c`、Makefile 条目、配置的 7 个键（calmMaterial、calm/darkCalm/dockCalm/dockDarkCalmMaterialOpacity、calmThreshold、calmRange）和访问器、GlassView 的 `calmFactor` / `calmScope` / 两处遮盖调整、诊断 `calm`、设置页“平稳背景”组和“查看当前背景变化程度”、FIX114 A 只给它用的 `WXGHostPageSettling`。存过的旧键读到时直接忽略。`WXGBuildProfile.h` 里的旧值没删（不在键表里就不会读）。“切换后等页面忙完再滑”（dockTapCalmWait，FIX101）是另一回事，保留。
  - 分组栏下拉时和标题栏速度不一致：标题栏的玻璃是插在微信自己的按钮视图里的，跟着滚动同一次提交走；分组栏（悬浮时在页面里）是 hostTick（显示链接）里摆的，慢的手机上比滚动晚一帧，看起来速度不一样。现在 `WXGChatSegments` 加了一个提交前的 run loop 观察者（order 1999000，在 Core Animation 提交之前），每次提交前按列表此刻的位置再摆一次（`commitPlacements`），和滚动同一帧。
  - 额外的胶囊：微信下拉时会把它自己的搜索栏的 alpha 改回来（分组栏只在挂上时藏过一次），它（连同里面的局部玻璃搜索胶囊）就在原位置露出来。现在提交前和 hostTick 都看一眼，被改回来就再藏（`searchBarRehides`；微信自己在用搜索时不管）。另外 FIX114 A 的标题胶囊防抖仍在。
  - 首页左右按钮边距：右边“+”按标题栏边距（安全区 + m.edge）放，左边那个是按微信自己的 MainFrameLeftBarView 居中的。现在左边的内容（微信的图标和插件的玻璃，玻璃是它的子视图）用 sublayerTransform 平移到同样的边距（`shiftContents`，±24 pt 以内）；视图本身和手势不动。
  - 局部玻璃的原生顶部按钮（网页、弹出页等插件不接管的）：同一边的按钮整组按最外侧那个的胶囊平移，让它离屏幕边至少是标题栏边距（只往里，不往外，±24 pt 内）；每个导航栏两侧各算一次，0.25 s 缓存（`WXGLocalSideShift`）。
  - 聊天不用头像标题时顶部原生（`chatNativeBar`，默认开）：聊天页的标题栏按钮（右上角显示头像开着时，那个头像按钮除外）和标题都不接管——`leavesNavigationControlNative:` 对它们返回 YES，buildNavigation 跳过这些按钮、不建 chatTitle、把标题视图还原；局部玻璃给返回按钮（箭头 + 未读数，胶囊按内容自适应宽度）、右上角按钮和标题（MMTitleView）垫胶囊，并按上一条的边距整组内移。需要“更多玻璃”里的“标题换成玻璃胶囊”和“网页、弹出页面的顶部按钮”开着（默认开）。另加 `navNativeButtons`（默认关）：首页和视频号以外的页面都这样。
  - 底栏：微信自己的标签标题是 .SFUI-Regular 10 pt（诊断底栏图标那一行），插件默认是“中等”——默认改成常规，存着旧默认 2 的配置自动改一次（标记 `dockTitleWeightNative`）。图标以前统一缩放进 28 × 26（微信 28 pt 的图标被画小），现在按原尺寸画，只有大于 30 pt 的才缩。
  - 独立复查后改的：① 局部玻璃量按钮的图标 / 文字位置改用 frame 逐级相加（`WXGLocalFrameIn`），不用 convertRect——父视图的 sublayerTransform（内容平移）如果算进换算，玻璃会被平移两次、边距平移量也会自己抵消来回跳（FIX113 E 的视频号平移也是先撤掉再量）；② 最外侧按钮自己没有局部玻璃（自带底色，如绿色“完成”）时，那一侧不平移，免得别的按钮挪过去压到它；③ 判断按钮是否保持原生用“按钮所属的那一页”（`WXGNavItemOwner`：比对各页 navigationItem 的 customView / titleView），push / pop 时滑出去的聊天页按钮的胶囊不再一开始就消失；④ 标题粗细迁移：构建自带的默认值（WXGBuildProfile 里是 2）在全新安装 / 恢复默认时也改成常规（`nativeDockTitleWeight` 在 applyBuildDefaults 末尾），已有配置按标记迁移一次；⑤ Telegram 图标（动画帧是 26 pt）仍按原来的 28 × 26 框，原尺寸只用于微信自己的图标。已知：离散底栏（默认开）的图标仍按“离散底栏图标大小”（默认 30）画，没改；navSnapshots 只记插件自己画的按钮，局部玻璃的按钮不在里面。
  - 版本 0.4.114-test4fix114b。服务器不变。
- A：
  - 性能（XS Max iOS 15.7 60 Hz 的页面切换记录，40 次）：
    - 切标签每次插件约 100–250 ms（0.6 s 窗口里），其中每帧透镜网格 3 个（R/G/B，每个约 1 ms，网格一次切换 40–70 个）+ 同步 + Metal 绘制；微信自己转标签 45–130 ms（`switchMS`）。
    - “平稳背景时加强材质”（`WXGCalmBackdrop`）单帧 20–55 ms：每 0.3–1.2 s 把整页 renderInContext 一次——取的是所有玻璃矩形的并集，顶栏按钮 + 底栏 = 整页；切换时新页面没缓存最慢（首页→聊天那次 55 ms，看图返回 43–49 ms，切标签 17–38 ms）。
    - 首页→聊天：第一帧前插件 158 ms（UIViewController.viewDidLayoutSubviews 钩子 49、MMMsgCommonTipsView.didMoveToWindow 28〔置顶条玻璃第一次挂上〕、刷新 69），微信自己 653 ms（一帧 391 ms 是微信的）。
    - 改：① 平稳背景：按位置聚成几块（标题栏一块、底栏一块；并集面积不超过各自之和 1.6 倍才合并）分别渲染、各自裁剪；页面切换中、切换后 0.6–0.8 s、列表拖动 / 减速时不测（`WXGHostPageSettling()`：转场、切换记录中、导航调用中、切标签后 0.8 s、viewWillAppear 后 0.6 s、任一列表 dragging / decelerating / tracking），0.3 s 后再看；诊断 `settlingSkips`。② 透镜网格：透镜在动（尺寸 / 位置 / 按压在 0.08 s 内变过）时，和已有网格在尺寸、底栏边 1.5 pt、按压 0.04、额外内收 0.5 pt、放大 0.006 以内就继续用（`WXGMeshOpticsNear`），停下 0.12 s 后重新布局、换回精确的；诊断 `lensSeesBar.meshKeptWhileMoving`。③ 诊断细分：页面切换记录里插件各部分也记计时段里面的（标签加“ ⊂”），viewDidLayoutSubviews 钩子拆成 `localGlass.controller` / `edgeFade.layout`，置顶条等 `decorations.host`，MMBarButton `navButtons`。
    - 没动：微信自己的耗时；置顶条 / 渐隐第一次创建的开销（下一份记录里有拆开的数字再说）。
  - 首页下拉留下空白标题胶囊（`WXGLocalGlass.m`）：标题胶囊跟着标题文字显示；文字没了时要连续两轮“没有”才藏（防抖），这两轮靠下一次布局 / 提交。微信把文字拿走后如果主线程不再有提交，第二轮永远不来，胶囊就留在那里。现在第一轮“没有”时安排 0.15 s 后再看一次。另外标题缓存的键多看一层子视图（文字在第三层被隐藏时缓存不更新）。
  - 分组栏下拉时间距（`WXGChatSegments.m`，悬浮时）：首页下拉轨迹里微信的标题栏按钮正好跟着下拉移动（y = 66 + 下拉量），而搜索栏所在的头部自己另外排版，所以分组栏按列表位置走就和标题栏拉开 / 靠近。现在下拉时分组栏放在“静止位置 + 下拉量”，小程序面板打开时按面板进度过渡到列表给的位置；下拉中和之后 1 s、面板打开时不重新量间距（之前可能在面板动画中途量，量错到下一次静止）。诊断 `gap.lastPull`。不悬浮（在列表里）时没改。
  - 右上角加号边缘（`WXGNative.m WXGCropInk`）：插件把微信的图标按墨迹裁到边再画，阈值 alpha ≥ 16/255，抗锯齿的淡边被裁掉；改成 ≥ 3。所有用这个的导航 / 输入栏图标边缘都会完整一点（缩放显示的图标因此可能小 1 像素）。
  - 独立复查后改的：① 加号的阈值第一次改到了诊断用的 `WXGRenderedInkEvidence`（替换命中了第一个同样的循环），已还原那里，改在 `WXGCropInk`；② 分组栏下拉保持：`pinned` 是按当前头部算的，头部自己在拉伸时它也跟着变，“pinned + 下拉量”等于没改——现在静止（没下拉、面板没开）时记下 `_restTop`，下拉时用“记下的静止位置 + 下拉量”，并且先判断下拉再判断上滑停靠；③ 移动中的近似网格：按压过程中 offsetScale（= press）、折射、宽度、色散、圆角都在变，原来的容差只放宽了尺寸，等于没省：这几项也放宽（0.04 / 4% / 0.4 pt / 0.08 / 0.4 pt / 0.75 pt）；停下 0.12 s 后直接 `applySyncMode`（原来的 setNeedsLayout 在多数状态下到不了它）。已知：诊断里“⊂”的外层钩子标签包含里层标签的时间（只影响诊断）。
  - 版本 0.4.114-test4fix114a。服务器不变。

## FIX113（用户 10:36：FIX112 E 可以了；两段式表情换 Face ID、加图标开关；三段式听写图标自带背景偶尔延迟清除）

- Z（用户 16:32：“只需要再加一个所有 iOS 27 类型边框设置也区分深浅色模式就可以了，然后整体增加一个页面切换时的性能诊断；目前的大问题是分组还是读不到名字只能读到 id”）：
  - 名字（`WXGChatSegments.m`；没有新的诊断，最近的是 diagnostics_10）：
    - diagnostics_10：`service: none`、`how` m_contact 17 / none 280（会话只有在首页显示过才带 m_contact）。U 加了 MMContext，但取服务和查联系人都是“问类要方法”（`class_getInstanceMethod` + 编码检查）。授权代码用 `respondsToSelector:` 调 `[[MMContext currentContext] getService:CContactMgr]` 在同一台手机上是通的（诊断 license.source = “MMContext · CContactMgr”）。最可能的原因：服务是代理对象、或 getService: 靠转发应答，类上没有这个方法，于是一直拿不到服务。
    - 改法：`WXGObjectCallFits / WXGObjectCall0 / WXGObjectCall1`：`respondsToSelector:` + 对象自己的 `methodSignatureForSelector:`（返回对象、参数个数和种类对得上）再调，异常就当没有。容器依次：首页 MainSessionMgr 自己的 `m_context`（诊断 10 里 managerIvars 有 `m_context @"MMContext"`，就是这个账号的上下文）→ `MMContext currentContext` → `MMServiceCenter defaultCenter`。查联系人 `getContactByName: / getContactForSearchByName: / getContactWithUserName: / getContactByUserName:`，通讯录 `getContactList:contactType:` 也走同一套检查。
    - 诊断 `memberNames.serviceTried`：每个容器的类名和结果（返回的类名 / 返回空 / 不响应），`lookup`：答上来的查法。不含任何名字。
    - 选聊天页顶上一行灰字（`WXGChatNameSummary`）：读到几个 / 共几个、各来源个数、联系人服务从哪来；有没读到的就提示导出诊断。用户截图就能看出是哪一步。
  - iOS 27 边框分浅色 / 深色（`WXGConfig.m`、`WXGOpticalSettings.m`）：
    - 原来 `…Rim27…` 是高光一、`…DarkRim27…` 是高光二（FIX89 把旧的浅 / 深两组变成了两道），两种外观共用。新键 `…Rim27DarkMode…`（高光一）和 `…DarkRim27DarkMode…`（高光二），六个范围（其余 / 底栏 / 气泡 / 分组 / 设置页 / 透镜）× 两道 × 7 项 = 84 个，表尾生成，各自继承同范围浅色那一项（第一次打开看起来不变）。
    - `rimGlowForScope:index:dark:`，`rimHexForScope`、`rimForScope`、`lensRimLineColorDark:` 的 iOS 27 分支都按外观取；GlassView 三处用 `rimDark`（视频号顶部按钮总用深色那套，和别的样式一致）。
    - “分组栏跟底栏一样”（`segmentLikeDock:`）：分组的深色那套取底栏深色那套。
    - 设置：边框页 iOS 27 四组：浅色模式 · 高光一 / 二（原来两组改名），深色模式 · 高光一 / 二（新）。分组、设置页、透镜范围的行由气泡的键换前缀得到（`bubbleRim27DarkModeHex` → `lensGlassRim27DarkModeHex` 等）。keycheck：316 行，没有未知键。
  - 页面切换性能诊断（`WXGPerfMonitor.m` 新的一节，`WXGHost.m` 挂点）：
    - 每次 push / pop（从最外层那次调用开始，记 `callMS`）、present / dismiss（viewWillAppear 的 isBeingPresented、新加的 viewWillDisappear 钩子里 isBeingDismissed）、切标签（标签根页无动画出现）记一条。同一个 coordinator 只记一次；新的开始时旧的记为 interrupted。
    - 自己的 CADisplayLink 只在切换期间跑：到动画 completion 后 0.3 s（切标签 0.6 s，最多 5 s，进后台立即结束）。插件开着时记，插件关着时打开“记录帧率”也记（可对比）；未授权什么都不做。
    - 每条：kind、from / to（页面名 + 类名，容器取顶上的页）、手势 / 取消、UIKit 时长、firstFrameMS（发起到第一帧）、callMS、animationMS、帧数 / 掉帧 / 慢帧 / 最长 / 卡顿、主线程（busy、idle、插件、Core Animation 提交、微信 = 其余），setup（第一帧前）和全程按 WXGProfile 各槽（tick / dock / draw / sync / mesh 及次数 / cleanup / refresh / switch / hooks），`pluginByPart`（按标签：appear、edgeFade、bubbles、localGlass、decorations、calmBackdrop、各个 WXGHookVoid 的“类.方法”），最慢 3 帧的拆分。
    - 计时：`WXGProfileAdd` 多一个通知（插件时间 = tick + tick 外的 refresh / switch / hooks，和帧率日志同一口径）；提交观察者、空闲时钟、网格次数也通知；`WXGHookVoid` 的 hooks 改走 `WXGProfileAdd`；`WXGPerfTimePluginWorkAs(label, …)`（旧的 = "other"），各调用点加了标签；viewWillAppear / viewDidAppear 钩子本体现在也计时（"appear"/"didAppear"，也进 hooks 总数和帧率日志的插件时间）。
    - 输出：诊断根上 `pageSwitches`（最近 40 条 + 按路线汇总），帧率 JSON（`pageSwitches`，也随 perf_current.json 存），帧率报告末尾一节，“帧率与参数”里新入口“查看页面切换报告”，浮标切换后 4 s 第二行显示那次切换。
  - 独立复查后改的：① 进后台时 `finish:` 里 invalidate 显示链接 + 清全局会把记录对象释放，后面再用 self 就崩：`finish:` / `frame:` 开头用 `objc_precise_lifetime` 的局部强引用留住，链接和全局放到最后才清；② 弹出一个包着导航控制器的页面时，根页先收到 viewWillAppear、isBeingPresented 是 NO，被记成 pop：先看 `coordinator.presentationStyle != None` / to.isBeingPresented；③ 底栏切标签转给微信的那次调用（`WXGProfileSwitch`，主要是微信加载标签页）不再算插件时间，调用期间 `++WXGHostTimedDepth`，里面的挂钩不再被帧率日志重复计时；④ 提交阶段里跑的插件布局挂钩不再从“微信”里扣两次（`WXGTransitionPerfCommitPhase`，提交只算去掉插件那部分）；⑤ 找不到联系人服务时也缓存 5 秒（不再每个聊天重查一遍），respondsToSelector 也在 @try 里；⑥ 从 push / pop 调用起算只用于 push / pop。已知：记录器自己在 viewWillAppear 里的那点开销算在微信里（很小）。
  - 版本 0.4.113-test4fix113z。服务器不变。
- Y（用户 07:21：“透镜跟随滑动速度形变时，透镜里上下边框那个形成区变化太大，窄的时候几乎没有、宽的时候又很胖；加个限制或者给形变开关；图标和文字也要单独的上下折射范围渐变”）：
  - 原因：`WXGElasticLayout` 快拖时把透镜高度压向底栏高度的 90%（比底栏还矮，上下那条页面没了），急停时按 exp(−.78·strain) 变高（变胖）。
  - `WXGElasticLayoutLimited(...,heightShare)`：高度只保留形变的这一份（1 = 原样，0 = 高度不变、只横向拉伸）；`WXGElasticLayout` = share 1（测试里原来的断言都不变，另加 share 1 / 0 / 中间的断言）。分组栏 `WXGSegElastic` 同样加参数。
  - 配置：`lensElasticOn`（默认 1）/ `lensElasticHeight`（默认 1），分组栏 `segmentLensElastic*`（继承）。关掉形变时连按压初段的速度拉伸（demoStretch）也不加。设置在底栏页“透镜”组和分组栏透镜组。
  - 上下那条保持宽度（直接回应“形成区变化太大”）：透镜里缩小底栏的轮廓和透镜边框之间那条（看到的是底栏边缘外的页面、边框在里面形成）随透镜高度变：拖快时透镜从 86.6 压到 60.9 pt（400×66 的底栏，满按），每边少 12.85 pt；急停变胖到 114.4，每边多 13.9 pt。
    - 网格 `WXGMeshOptics.shrinkExtra`：加在完整内收上（显示 pt，可负），`WXGMeshShrinkFull` = 原内收 + extra，`WXGMeshShrinkAlong` 允许负值；环的 stop 只算正的。缓存键 `key[36]`、`WXGMeshOpticsClose`（0.125 pt）都带上。
    - 插件：`WXGGlassView.lensRestHeight`（不加速度形变时的透镜高度，底栏 `updateGeometry` 用 stretch 0 的 `WXGDockLayout`、分组栏用 stretch 0 的 `WXGSegLayout` 算），`applySyncMode` 缩小那段：`shrinkExtra = keep × (rest − 当前高度)/2`（0.25 pt 一档），上限让缩小的底栏至少剩 1/4 高（`barHalf × (.75 − pinch × press)`）。离散底栏的分片没设 rest（0），不加。
    - 背景边距：开着形变时预先按 `keep × 高度变化份额 × 0.2 × 底栏高` 留（实测最大 0.19 倍），边距在形变中不跳档；再和实际 extra 取大。
    - 配置 `lensElasticKeepStrip`（默认 1 = 完全保持；0 = 以前那样跟着变），分组栏 `segmentLensElasticKeepStrip`（继承）。设置在底栏页“透镜”组和分组栏透镜组：“形变时保持里面上下那条的宽度”。
    - 测试：`LensInsetAlongTests.c` 的位置初始化多一个 0；新增“extra 3 pt 时中间列的边缘再往里 3 pt”。诊断 `lensSeesBar` 加 `lensRestHeight`、`lensHeight`。
    - `shrinkExtra` 这个网格字段和 `WXGMeshShrinkFull / Along` 是 07:21 出现在工作区里的改动（不是这一轮对话写的），设计正好是这个，所以保留并接上了。
    - 独立复查后：① 原来 extra 和内收共用“沿底栏轮廓在透镜里多深”的渐变（`WXGLensDepthAlongBar`），透镜一压扁，中间那列的深度 = 边框到底栏边 / 0.3 跟着变浅，到透镜比底栏矮时为 0，extra 根本加不上（实测 64.7 pt 以下那条照样没了）。改成深度按静止的透镜量（`l.distance − shrinkExtra`，边框往外 / 往里挪 extra）；变胖（extra 为负）时缩小的底栏允许比真实底栏大（dz 下限 −0.25 × 底栏高，只在 extra < 0 时）。CPU 模拟（`scratchpad/exp/`，含折射 2.82 / 宽 12.35 / 放大 1.09）：pinch 0.131 时透镜从 0.8 到 1.28 倍静止高度，中间那条都是 9.8 pt（X：压扁到 65.8 以下就没了，胖到 1.28 倍是 13.4）；两端收进边框的位置随透镜挪 2–6 pt，形状和静止时一样（落在折射带里）。pinch 0 时静止就没有那条（被折射带吃掉），压扁 / 变胖也一样没有。新测试：压扁 13、压扁 20（比底栏矮）、变胖 13，那条都等于静止时。② 边距预算按透镜外扩算（`keep × 份额 × min((growth − .86) × 半高, 上限)`），Reduce Motion 时不留，上限 32 → 40。③ 设置说明写明只在“透镜直接折射底下的底栏”开着时起作用。DemoBar 里“形变一直开”的旧注释改了。网格压力测试（4 种底栏高、0.8–1.4 倍、宽 1 / 60、折射 20、色散）458 个全部建成、无 NaN。
    - 第二次复查：extra 0 时和 X 逐位相同（165 万点、400 个网格）；extra −0.5…+0.75 × 半高无 NaN / 折叠；pad 40 不影响网格容量。补了变胖 30 pt（extra −15，缩小的底栏比真实的大）的测试，撤掉 dz 负下限这条会失败。已知限制：① 中间那列的深度受 0.3 下限，外扩小时压到 0.9 倍底栏高那条会短一些（外扩 1.08 短 4.7 pt、1.15 短 2.6、1.28 短 0.4；用户的外扩约 1.18，短约 0.5–2 pt）；② 压扁时底栏边缘在透镜两端进边框的位置和外面的底栏对不上（例：103×70 透镜、68 pt 底栏、extra 8.5，约 15 pt 长的一段边框里外一边是底栏一边是页面），只靠边框的折射带遮住，上下比例小时那条带很窄——要是用户说两端有断口，就是这个，可以把 extra 只用在离两端远的地方（按 `|t·n|` 渐隐）或调小“保持”。
  - 图标和文字的上下宽度比例 / 收窄曲线：`lensIconTopEdgeRatio`、`lensIconEdgeSharpness`（分组栏 `segmentLensIcon*`），继承透镜原来的；同步模式透镜看得到底栏时，Metal 透镜那遍把 `u.sync.y / .z` 换成它们（每个 surface 前恢复）。设置在折射页“透镜（按压时）”和分组栏透镜组。
- X（用户 06:52：W“跟设成小于 2 没区别，没有自然收进去的那个东西……回退上一版；回退后做分离：图标和文字用另外的折射宽度和强度，其余用现在的；透镜边框也算成和其余玻璃一样的那一档设置，我单独调，不再用现在简单的边框”）：
  - W（上下边缘不往里取景 `lensTopCancel`）整个 `git revert`，回到 V。W 的调研结论留在这里备查：
    - LiquidGlassKit：SDF + smooth union 合并形状，Snell 剖面，边框 / 眩光是把底下内容在 LCH 里提亮（颜色随内容）；它的 LiquidLensView 仿 `_UILiquidLensView`。
    - iOS 26 系统标签栏透镜是私有 `_UILiquidLensView`（`initWithRestingBackground:`、`setLiftedContainerView:`、`setLiftedContentView:`、`setOverridePunchoutView:`、`setLiftedContentMode:1`、`setStyle:1`、`setWarpsContentBelow:YES`、`setLifted:animated:alongsideAnimations:completion:`），Telegram iOS 26 上就这么用（`TelegramUI/Components/LiquidLens`）。系统玻璃：CABackdropLayer + CAFilter `glassBackground`（CASDFLayer "@0" 定形状）+ `CASDFGlassHighlightEffect` 高光。Telegram 自绘用 iOS 26 才有的 CAFilter `displacementMap`（兄弟子层当位移图，R/G = x/y，0.5 不动，`inputAmount`、`inputOffset`）。
    - 用户录屏（`uploads/19dfbd2e-ScreenRecording_...mov`）量出：透镜里底栏缩小约 0.89（内收约 3.5 pt），图标放大约 1.15–1.2，上下暗弧贴着透镜边框、两头收进边框带色散，强折射只在两端。
  - 图标和文字单独的折射（只改插件，不用换服务器着色器）：同步模式下透镜看得到底栏（V）时，背景（底栏、页面）是 CA 网格折射的，Metal 透镜那遍只画选中色和选中图标 / 标题——所以那一遍的 `u.lensOptics.x / .z`（透镜折射强度 / 宽度）换成 `lensIconRefraction / lensIconEdgeWidth`（分组栏 `segmentLensIcon*`），网格还用 `lensRefraction / lensEdgeWidth`。新键第一次从透镜的值继承，看起来不变。色散、上下比例、收窄曲线、放大倍数、边缘偏移抵消两边共用。关掉“透镜直接折射底下的底栏”（T 的画法）时不分开。设置：折射页“透镜（按压时）”加两条，分组栏透镜组加“文字的折射强度 / 宽度”。
  - 透镜边框成为一个范围：`WXGGlassScopeLens = 5`，键前缀 `lensGlass` / `lensGlassDark`（`WXGScopedKey`；`lensRim…` 是原来的简单线，只作继承来源），表里 43 个键照“设置页”那套生成：普通（颜色 / 不透明度 / 宽度从原来的 `lensRimHex / lensRimOpacity / lensBorderWidth` 继承，左下右上渐隐 0、泛光关，样式默认普通 = 第一次打开和原来一样）、取自背景、iOS 27 两道高光、泛光，其余从底栏的继承。`WXGTableScope` 包含它。
    - 画法（`WXGGlassView layoutSubviews`）：`_lensRim` 按透镜范围的样式配置——普通线（+泛光）、iOS 27 两道高光（不透明度乘按压出现的系数）；取自背景用新的 `_lensRimTint`（WXGRimTintView，在透镜裁切层之上、`_lensRim` 之下，自己的捕获组 `wxg.glass.lensrim.%p`，取的是透镜里显示的内容），饱和度 / 增益等取色处理和别的范围共用。都乘 `max(WXGPressedBorderAlpha(press), rimAtRest)`。不加描边细节。
    - 以前底栏是“取自背景”时透镜线会被换成材质色，这个耦合去掉了（透镜有自己的样式）。
    - 分组栏的透镜也用这个范围；分组页“选中胶囊边框”只留“静止时也显示”。点按动画的透镜边框（一条 CA 边线）用 `lensRimLineColorDark:width:`（iOS 27 时取第一道高光的颜色）。
    - 设置：边框与渐隐加第六个范围“透镜”；行的键由气泡的键换前缀得到（`WXGRowKeyForScope`，透镜用 `lensGlass`）；“描边细节”三组在透镜范围不显示；“透镜滤镜色”从底栏范围挪到透镜范围；原来底栏范围里的“浅色 / 深色模式 · 透镜”两组删掉。
    - 诊断：glass 证据加 `lensRimTint`、`lensRimStyle`。
- V（用户 00:13，看了 U 的说明：“底栏缩小了呀，你让它折射缩小的底栏啊，包括背景也是，什么叫只折射下面的底栏？”——U 把镜内底栏的缩小去掉了，理解错）：
  - 要的是：按住时透镜底下那条底栏是缩小的（iOS 26，`bodyPinch` / `segmentBodyPinch` 的内收），这条缩小的底栏连同它的背景和它自己那一条边框，作为透镜底下的东西被透镜真实地折射；透镜里不另画任何边框和底色。
  - 做法（只改插件）：U 的“透镜自己的组截取真实底栏”保留；透镜网格（`WXGMeshSource`）在折射 + 放大之后再加一步 `WXGMeshShrinkBar`：
    - 在折射弯过、还没放大的显示点上，按着色器原来画镜内底栏的同一个内收（`WXGInnerInsetAlong(底栏高, press, pinch, WXGLensDepthAlongBar(...))`，到透镜两端为 0、和外面的底栏接上）算出 d；
    - 放大会把轮廓往外推，所以在放大前的源坐标里内收要用 dz = h − (h − d)/zoom（h = 放大中心到该处轮廓沿法线的距离），这样屏幕上缩小的轮廓正好在 d 处；
    - 沿底栏法线移动源点：缩小的底栏里面，从中线到它的轮廓对应真实底栏的中线到真实边缘（底色、边缘环、边框都跟着缩进来）；外面对应底栏边缘外的页面（整体外推 dz）。中线不动，轮廓两侧移动量相同，连续。
    - 网格新字段 `sbLeft/sbTop/sbRight/sbBottom/sbRadius/shrinkPress/shrinkPinch`（远端推到 ±10000，`sbRadius` 恒 0：底栏和分组栏都是胶囊），缓存键和相近判断都带上；缩小时网格用更细的 `WXGMeshQualityLensBar`。
    - 独立复查后：① 环一直铺到缩小轮廓以内（`stop` ≥ 轮廓深度 + 完整内收 + 2，带外 1 pt 一环），否则中间那段直线插值会把内收抹掉（折射宽度 10 时少 1.35 pt）；② 只要有按压就开（不看 pinch），pinch 趋近 0 时不会跳变，和 Metal 的选中胶囊一致；③ 透镜背景加边距 `_lensPad`（整个按压期间按满放大和满内收估 h(1−1/zoom)+内收/zoom+2，2 pt 一档，≤ 32），网格 `padX/padY`，bar*、sb* 都加边距，透镜边缘不再取到截取区被夹住的边；点按动画没有边距（只夹住，动画很短）；④ 底栏端点影响范围 0.75 × 高 + 2。
    - CPU 模拟（`scratchpad/lsim/sim.c`：逐像素 vs 真正光栅化的轮廓网格）两者几乎一样；深 / 浅色、中间 / 第一个标签、半按 / 全按的预览图 `scratchpad/lsim/preview_u2.png` 发给了用户。
  - Metal 透镜分支：仍不画底色、描边、第二道高光、底栏色散；`optics.z`（内收）不再置 0，静置选中色的形状跟网格里缩小的底栏一致。
  - 点按动画透镜：`WXGMakeTravelLensBackdrops(..., seesBar, barHeight)` 同样缩小（底栏居中、没有两端，`c.bodyPinch`），缓存键带上 pinch。
  - 设置说明改写：缩小多少照样由“镜内底栏统一内收”决定。
- U（用户 23:38：“为什么要在透镜内部专门去画边框？底栏有边框，让它自然地折射不就得了；底层只有底栏那一条边框，折射上去怎么可能分叉”；diagnostics_10 + 深浅色透镜截图）：
  - 透镜（`WXGGlassView.m`，只改插件，不用换服务器着色器）：
    - 原因：所有 backdrop（底栏本体 R/G/B、边缘环、透镜 R/G/B、边框取色）共用一个 groupName（`wxg.glass.%p`），同组只截一次、在最底下那个 backdrop 处截，所以透镜看到的是“不含底栏”的页面。底栏的底色（CA `_veilFallback`）、边框（`_bodyRim` / `_bodyTint`）、图标（Metal 本体）透镜都看不到，只能在着色器的透镜分支里按几何（`wxgLensBar`：弯折 + 内收 inset）再合成一份底色、描边、第二道高光、选中色。这份和真实底栏分开算，于是对不上、在透镜边缘分叉（FIX113 L/M/T 都是在补这个）。
    - 改法：配置 `lensRefractsBar`（默认 1）开着、同步模式 2 时，透镜那组 backdrop 换成自己的组 `wxg.glass.lens.%p`（`WXGSyncBackdropView configureGroup:radius:channel:plain:` 现在可以换组，记在 `group`），于是透镜截到的是它下面真实画出来的一切：页面、底栏的模糊背景和边缘环、CA 底色、CA 边框、Metal 图标（透镜下面的图标本体照旧挖掉，FIX37）。透镜自己的网格（折射、放大、RGB 三通道）把它们和页面一起弯过去，只有一条边框，不会分叉，颜色和外面完全一致。
    - 着色器透镜分支（surface 1）在这种模式下：`tintColor.w`、`borderColor.w`、`glowColor2.w` 置 0（不再另画底色、描边、第二道高光），`extra2.x/y` 置 0（不再另算底栏色散），`optics.z`（镜内统一内收）置 0；只剩静置选中色和选中图标。
    - 模糊：截到的底栏已经模糊过，透镜只加自己的模糊 `L.blur × press`（以前是本体模糊 → 透镜模糊插值）；也不再加 5% 饱和度（`plain`，截到的已经有了）。
    - 静置（press 四舍五入到 1/32 为 0）时透镜 backdrop 直接隐藏：没有折射、放大和模糊时它只是原样复制下面的东西，省掉第二次截取（滚动时首页底栏和分组栏都不多花一次）。Metal 上的选中色和选中图标照画。
    - 点按切换的动画透镜（`WXGDemoBar`）：`travelGroup` 在 `_glass.lensSeesBar` 时返回 nil，用自己的组（现在每个底栏一个：`wxg.travel.%p`，两个底栏的动画透镜不会共用一次截取），截到底栏和下面挖了洞的普通图标；不画 FIX88 的仿底色 / 仿描边；`WXGMakeTravelLensBackdrops(size,press,group,seesBar)` 同样只加透镜自己的模糊、不加饱和度；缓存键带上 seesBar。
    - 关掉 `lensRefractsBar` 回到 FIX113 T（共用截取 + 着色器另画，T 的两个开关、镜内统一内收、镜内底栏色散又起作用）。
    - 只在网格折射可用时（`syncMeshRefraction`、有 CAMeshTransform、不是 WXG_MESH_OFF 自测版）才这样做，否则透镜只会原样复制、也没人弯它，退回 T 的做法。状态由 `applySyncMode` 记在 `_lensSeesBarApplied`，Metal 透镜分支和点按动画都读它（不会在开关切换后错一帧）。R/G/B 通道的 colorMatrix 在 plain 时也不加 5% 饱和度（`WXGMakeChannelFilter(channel,plain)`）。
    - 设置：只在底栏“透镜”组加“透镜直接折射底下的底栏”（分组栏的透镜跟着它，分组栏页的说明里写了；没在两页各放一行，免得“恢复本页默认”动到另一页）；说明里写了原因，T 的两个开关、两处“镜内…色散”注明只在关掉时有用。
    - 诊断：glass 证据里 `lensSeesBar {on, lensGroupOwn, lensBlur, lensShown}`。
  - 名字（`WXGChatSegments.m`）：
    - diagnostics_10：`service: none`，`how`：session.m_contact 17 / none 280；CContact 的 `getContactDisplayName`、`m_nsNickName` 都有值。也就是取名字本身没问题，是拿不到 CContactMgr：只问了 `MMServiceCenter defaultCenter`，微信 8 要 `[[MMContext currentContext] getService:CContactMgr]`（授权代码读账号就是这么拿的）。
    - `WXGContactService` 先 MMContext、再 MMServiceCenter（都按签名检查后调用），来源记在 `serviceFrom`；缓存 5 秒（换账号后重新取）。`WXGContactTitle` 的取名方法列表按类缓存。
    - 通讯录：`WXGServiceContacts` 用 `getContactList:contactType:`（1, 0；只在签名正好是两个整数进、对象出时调用）拿好友和保存的群，并进名字表（`how` 里叫 addressBook），不在聊天列表里的也加进可选成员（照旧跳过公众号和微信自带项）；诊断 `serviceContacts` 是条数。
- T（用户 22:36：“读的是原始 ID，通讯录页跑了也没用；深色模式底栏透镜和下面的内容对不上，要么不显示底栏的边框和背景，要么是另一种颜色；开了悬浮为什么还会被模糊影响”）：
  - 悬浮：
    - 原因：分组栏和微信的搜索栏不悬停时都在列表里。WXGEdgeFade 的渐隐是列表 layer 的 mask，模糊带在列表的父视图里、就在列表上面，所以在顶部会被渐隐和模糊到。
    - 改法：悬浮开着时，分组栏和首页 / 通讯录的仿制胶囊一直放在列表的父视图（页面）里，插在列表和 WXGEdgeBlurView / WXGEdgeCoverView 之上（`WXGRaiseAboveList`）。位置是在列表里的位置，往上滚时停在标题栏下。
    - 好处：不在导航 overlay 里了，不会盖住 + 菜单。转场时跟着页面一起走（hostTick 转场中也放在页面里）。
    - 首页 / 通讯录的微信搜索栏在悬浮开着时一直淡出、由胶囊代替。微信自己的搜索在用时（输入框是第一响应者、有字、presented、searchController 激活），就把栏还给它（`nativeSearchActive:`）。
  - 名字：
    - `WXGSessionField` 现在也认运行时才解析的 getter（respondsToSelector + methodSignature，微信生成的模型类常这样），还会找 `_名字` 这种 ivar。
    - 联系人名字：固定键之外，再试这个类自己的、以 Remark / DisplayName / NickName / ShowName 结尾的无参 getter（去掉拼音）。等于用户名或 wxid_ 开头的值不算名字；去掉了 m_nsAliasName（微信号）。
    - 诊断 `memberNames.contactNameAnswers`：每个名字 getter 有没有返回内容（只记有 / 空）。
  - 透镜：新开关 `lensBarOutlineOn`（默认关，就是 L / N 的做法）、`lensBarVeilOn`（默认开），放在底栏页 › 透镜。只影响透镜那一遍（surface 1）的描边 / 第二道高光 / 材质色。深色模式的具体差异还在等截图。
  - 版本 0.4.113-test4fix113t。
- S（用户 22:13，附 diagnostics_8 和选聊天页截图：“分组第一次能点，从聊天返回后好像就不行；很多群和私聊获取不到名字，跑下通讯录可能有用”）：
  - diagnostics_8 没用上：导出时授权服务器连不上（请求超时 5 次），插件处于原生状态，分组一节是空的。
  - 返回后不能点：mountOver 以前按窗口设 `_bar.active`。聊天页开着时首页搜索栏布局一次（窗口为空）就会把它设成 NO，回来后 hitTest 一直返回 nil。现在挂上就是 active=YES（窗口由 tick / didMoveToWindow 自己管）。
  - 校验放宽：行数差对不上时，看 section：有一个 section 正好等于筛后的普通会话数、另一个不多于置顶数（置顶可能折叠），就算跟着变。失败只退回这一次，不再整次运行停用（后台线程 rebuild 例外）。
  - 名字：
    - 依次试 session.m_contact、通讯录页（ContactsViewController 自己的数组，以及类名带 Contact / Logic / Data 的数据对象往下一层）、CContactMgr 的 getContactByName: / getContactForSearchByName: / getContactWithUserName:、session 自己的显示名。
    - 联系人字段依次试 m_nsRemark、getContactDisplayName、m_nsNickName 等。
    - 都没有时显示“未命名（用户名末 6 位）”。
    - 通讯录页里有、但聊天列表里没有的好友和群也列出来，标注出来。
    - 诊断 `sessionFilter.memberNames`：各来源命中数、session / contact 类、和名字有关的方法名（不含任何名字）。
  - 版本 0.4.113-test4fix113s。
- R（用户 14:15，附 diagnostics_7 和表情搜索截图：“无法切换，也没办法设置某个分组，也没法添加新的分组；表情搜索框这里有个白色背景”）：
  - 无法切换：diagnostics_7 的 `sessionFilter` 写着“没有找到首页的 MainSessionMgr”，但钩子已经跑了 37 次 rebuild，全在主线程。
    - 原因是 8.0.73 里 manager 不在 NewMainFrameViewController 自己的 ivar，而在 `m_mainFrameLogicController`（MainFrameLogicController）里。
    - 另外首页列表 3 个 section：0 / 置顶 8 / 普通 292，和两个数组对得上。
  - `WXGFindManagerIn`：从首页（和 dataSource）往下两层找 ivar，用探针的安全读法，预算 900；找不到就用最近一次在主线程 rebuild 的 manager。诊断加了 managerPath、managerIvars / managerMethods、logicIvars / logicMethods（只有类型和数量），万一列表数据不是从这两个数组来的，下一轮能看出是谁。
  - 自定义分组：
    - `WXGChatGroupList / Save / Clean / Defaults`：默认偏好里的 `chatGroups.v1`，1–6 个，每个 {id, name, rule 0 全部 / 1 未读 / 2 单聊 / 3 群聊 / 4 自定义, members}；改动发 `WXGChatGroupsChanged`。
    - 规则 4 按用户名集合 `WXGFilterMembers` 匹配。钩子在主线程 rebuild 时存一份完整列表快照 `WXGFilterSnapshot`，给选成员用。
    - 分组栏改成 n 段：本地 `WXGSegLayout` / `WXGSegElastic` 是 WXGDockLayout / WXGElasticLayout 的 n 段版，着色器不受影响（透镜矩形由插件传）。名字太长就缩小字号放进那一段。
    - 当前分组按 id 记（只在这次运行里有效）。每次启动选第一个“全部”类型的分组；一个都没有就选第一个并自动套用。
  - 新文件 `WXGChatGroups.m`：
    - 分组页 ›“管理分组”（`manageGroups`）：每组点开可以改名、换类型、左移 / 右移、删除；另有新建（先起名再选类型）和恢复默认。
    - 自定义分组进“选择聊天”页（`WXGGroupMembersPage`）：搜索框 + 普通 UITableView。数据来自 `WXGChatSessionChoices`，名字取联系人备注 / 昵称（不进诊断）。离开页面时才保存。
  - 表情搜索白底：快捷跳转的结构里，整页宽的 #EDEDED 底带本来就是那一行的背景（页面的 view 是白的），Q 版把它清掉就露出了白色。现在 `clearSearchBandAround` 不清页面根这一层的视图了，玻璃只在胶囊上，底带保持微信画的灰色。
  - 版本 0.4.113-test4fix113r。服务器不变。
- Q（用户 12:57，附 WGP 圈选抓取 `WGP_20261021_125145_172_baseline_2.zip`（XS Max iOS 15.7 / 微信 8.0.73，插件未注入）和他之前给高版本写的 `WCLGSearchGroups_0.1.7_TEST8`）：
  - 表情搜索（输入框快捷跳转）专项：
    - 抓取结果：WCSearchTextField 直接在 NewEmoticonSearchViewController.view（白）里，frame 52,0 317x36。同一层有白色 UIView 16,0 382x36（圆角 4，输入框的胶囊），还有 #EDEDED 的 UIView 0,0 414x52（整条底带）；另有放大镜 UIImageView、MMUIButton、WKWebSearchView。
    - 对照 diagnostics_6：N 版同一个 host 挂了两块玻璃，一块在 414x52 的底带上，一块在胶囊上，就是“两层胶囊”。
    - `-[WXGLocalGlass emojiQuickJumpField:]`：只在“输入框的父视图就是该页的 view”时接管。只挂在高度和输入框一样、左右包住输入框的那块（最小的）上；整页宽的永远不挂（还是由 clearSearchBandAround 跟着玻璃清掉）。找不到胶囊就跳过，等下次布局再看。诊断 `localGlass.emojiQuickJump`。
  - 分组真的筛选（参考 WCLGEngine 的做法，自己重写，带保护）：
    - MainSessionMgr 的 `topSessions` / `normalSessions` / `totalTopSessionCount` 由 `-rebuildMainSessions` 重建。只有选了“全部”以外的分组时才挂钩，钩子在微信自己 rebuild 之后按分组筛这两个数组（对象和顺序不变）。
    - 首页的 manager 从首页控制器（和列表 dataSource）的 ivar 里找，用探针的安全读法。方法逐个检查签名。
    - 第一次筛选前记下“数据源行数 −（置顶 + 普通）”。筛选后数据源行数必须正好等于筛后的数组加这个差，才 reloadData；否则立刻回到全部，本次运行停用分组，诊断里写原因。
    - 分类只看用户名：群聊是 @chatroom 和 @placeholder_foldgroup；单聊是其余个人（去掉 gh_、@ 开头、@stranger、微信自己的入口名单）；未读看 m_uUnReadCount / m_uAtMeCount / m_uAtAllCount / m_uNewNotifyMsgCount。
    - 选择不保存，重启从全部开始。`restore`（分组栏关、插件关、未授权）都会先把完整列表还回去。
    - 诊断 `chatSegments.sessionFilter`：manager、api、各类计数、dataSourceRows、last、rebuilds。
    - 独立审查后加的保护（参考工程 validation.json 写着 device_tested: false，筛选从没在真机验证过）：
      - 只在主线程筛选。rebuild 钩子在分组栏挂上时就装（直通），记下微信在哪个线程 rebuild。见过后台线程 rebuild 就不启用；筛选中遇到就回到全部并停用。
      - 首页表格自己的类（MainFrameTableView，绝不碰 UITableView 本身）在筛选期间：insert / delete / reload / move 行和 section、begin/endUpdates、performBatchUpdates 都变成一次 reloadData（batch 先跑它的 block，completion 异步给 YES）；滚动或选中不存在的行直接丢掉。不筛选时原样转给 UIKit。诊断 `intercepts`、`tableGuards`。
      - totalTopSessionCount 记下微信自己的“置顶数 − 置顶数组长度”差值，筛选后按这个差设，回到全部时不对就补回。三个 setter 任何一个失败就三个一起还原；`applyFilter` 还要求钩子报告成功。
      - 被拒绝时透镜滑回“全部”（`returnToIndex:`）。
      - 第二轮审查：
        - 拦截开关 `WXGFilterGuarding` 和筛选开关 `WXGFilterIndex` 分开。回到全部时，先不筛地 rebuild、reloadData，然后才关拦截。
        - 置顶数：记下我们上次写的值（`WXGFilterWrittenCount`）。微信 rebuild 后仍是这个值，就沿用上次的差值，不会越漂越歪；回到全部时只有它还是我们写的才补回。
        - 写入顺序：先写置顶数再写数组，异常时三个都还原。
        - 后台线程 rebuild 一出现就原子置 `WXGFilterDisabled`，主线程立刻不再筛。
        - 任何拒绝都先把之前的筛选还原（`failFilter`）。
        - 空的 begin/end、空的 batch：行数一致就交给 UIKit（刷新行高），不一致才 reload。
        - `rectForRowAtIndexPath:` 越界返回 CGRectZero。
    - 间距只在列表静止在顶部、不在转场时测；限制在表头范围内（出了表头点不到，还会盖住第一行）。resetRoute / detachOverlays 清掉 navCapsuleLeaf。
    - 表情搜索：一时找不到胶囊时，已经挂在胶囊上的玻璃保留，不卸。
  - 分组栏位置与大小（分组页新组“位置与大小”）：
    - `segmentGapOn` / `segmentTopGap`：列表在最上面时分组栏上沿离标题栏那排玻璃的下沿多远，悬浮也停在这里。Host 在 buildNavigation 里记下 `navCapsuleBottom`（窗口坐标），`navigationCapsuleBottomForPage:inView:` 给出来；hostTick 里算 `_gapDelta`，`listFrame` = 自然位置 + delta。
    - `segmentWidthPercent`：50–106%，以输入框中线为中心。
  - 版本 0.4.113-test4fix113q。服务器不变。
- P（用户 11:42：“给分组换成底栏的形式吧，移植高系统的这种不怎么好看，不如直接用底栏的样子微调”）：
  - 分组栏不再是系统分段控件的样子（平的深色槽 + 页面色胶囊），默认就是一条小底栏：
    - 本体玻璃：`segmentRefraction/Dispersion/Blur/BlurCoverage`、`segment(Dark)RimOpacity`、`segmentRimStyle`、取自背景和 iOS 27 的不透明度、`segment(Dark)Material*`、材质边缘减弱，都改成继承底栏的键（O 里是 0 / 黑色叠加）。
    - 选中胶囊：`segmentPillAuto` 默认关；`segment(Dark)PillHex` 继承 `selectionHex/darkSelectionHex`；不透明度继承 `selectionOpacity`；新键 `segmentPillPressedOpacity` 继承 `pressedOpacity`。GlassView 新属性 `selectionOverridePressedAlpha`：覆盖色的 alpha 随按压从静止值淡到按住值，和底栏的选中色一样。
    - 文字：没选中的 #1A1A1A 0.92 / 深色 #F7F7F7 0.97（底栏的 WXGDockTabColor）；选中的用强调色（新键 `segmentAccentOn` 默认开、`segmentAccentHex` 继承 `dockAccentHex`），字重加一级。
    - 新键 `segmentHeightExtra`（加高 0–20 pt，上下各一半，不超出搜索栏那一行）。
  - 迁移：O 已经存下了平的那套值。新标记键 `segmentDockLook`：存档里没有它时，`segmentLikeDock:NO` 把这些“样子”键重新从底栏取一次（透镜键 O 起就是继承底栏的，不动）。
  - 分组页：“背景色”改名“玻璃底色”；选中胶囊加“按住时不透明度”；文字加“选中的用强调色”和强调色；分组栏组加“加高”；新组“跟底栏一致” ›“套用底栏现在的样子”（`-[WXGConfig segmentFromDock]`：所有继承底栏的 segment 键从底栏当前值重取，胶囊不用页面色、文字颜色回到底栏的，保存）。首页卡片副标题“小底栏 · 胶囊 · 透镜 · 悬浮”。
  - 版本 0.4.113-test4fix113p。服务器不变。
- O（用户 08:53，附 diagnostics_6）：
  - 分组不再借底栏的参数：
    - 新范围 `WXGGlassScopeSegment`（3）。`WXGGlassView.glassScopeOverride`（-1 = 按 surface）；分组栏设成 Segment，但仍保留 dockSurface（透镜那一套）。
    - 键都在 `WXGExtraSpecs` 末尾：`segment*` 本体光学 / 材质 / 边框（第一次加载时从底栏的值继承，但光学、边框不透明度、RimStyle 默认 0＝平的、没有边框），`segmentLens*` 透镜，`segmentSelectionInset` 胶囊内边距，`segmentPill*` 胶囊颜色 / 不透明度 / 用页面背景色，`segmentPillRimAtRest` 静止时边框，`segmentTitleSize/Weight`、`segment(Dark)InkHex` 文字。
    - `WXGLensSettings` + `-lensSettingsForScope:dark:`：GlassView 的透镜 uniforms 全部从 L 取（底栏范围取底栏的键，结果和以前一样）。
    - 删掉 N 的 `chatSegmentGroove*` 和 GlassView 的 `grooveBody`：“槽”就是分组范围的材质（背景色）。
  - 设置：
    - 新模块“分组”（`segments`，首页卡片在“通用”的底栏后面）：开关、悬浮、背景色、选中胶囊（内边距、颜色）、选中胶囊边框、文字、透镜（按住时）、透镜滤镜色、镜内色散、恢复。
    - 折射 / 模糊 / 边框三页的范围加“分组”“设置页”，材质页加这两个（材质页没有气泡）。
    - 行的键：`WXGRowKeyForScope`，由气泡键（没有就用底栏键）换前缀得到；`knowsKey:` 不认识就不显示该行。平稳背景组 `notIn` 这两个范围。
    - 底栏页里 N 的“聊天列表分组栏”组删了。
    - 点按切换的动画时长、胶囊变透镜的快慢、两端拉长仍跟底栏（设置页脚里写明了）。
  - 设置页玻璃：
    - 新范围 `WXGGlassScopeCard`（4）。卡片和标题栏按钮都设成 Card；`card*` 键第一次加载时继承“其余玻璃”的值。
    - 材质默认：浅色 #FFFFFF 0.82，深色 #2C2C2E 0.86，边缘减弱关。
  - 设置页背景：没导入壁纸时是纯色。`settingsBackgroundHex` #F2F2F7（浅灰）/ `settingsDarkBackgroundHex` #1C1C1E（深灰），在壁纸页“无壁纸时的背景色”里改；原来的彩色渐变不再用。
  - 悬浮 `searchFloat`（默认关；分组页 › 分组栏）：
    - 每帧由 `WXGHost tickBody` 调 `-[WXGChatSegments hostTick:page:overlay:transitioning:]`。
    - 分组栏：放进 `_navigationOverlay`。位置是自然位置，最高停在表格可见顶（overlay 坐标 + adjustedContentInset.top）加上输入框到表头顶的距离。转场、换页、overlay 隐藏、表头被换掉时回到列表里。
    - 首页（没分组栏时）和通讯录：微信的栏停不住，就在 overlay 里放一个仿制的玻璃胶囊（`WXGFloatingSearch`，放大镜 +“搜索”）。微信的栏用 StateBag 淡出，不搬动、不变形。点仿制胶囊：列表回到表头，再让微信的输入框 becomeFirstResponder（走微信自己的搜索）。
    - 诊断 `chatSegments.float`。
  - 表情搜索双胶囊（diagnostics_6）：`fieldSibling:` 选中了栏宽的 414×52 兄弟视图。现在取面积最小的普通底色；贴边的只在找不到时兜底。`field:host:skins:` 先卸掉同一 host、不同锚点的旧入口。
  - 设置搜索：首页头像卡下面一个搜索框。
    - `WXGSettingsSearch` 遍历首页卡片对应的模块 spec，每个词都要出现在标题或所在位置里。排序：标题命中、组名命中在前，只在说明里命中的组在最后；最多显示 80 条。
    - 点结果：`WXGSettingsModulePageFocused` 打开那一页；有范围的页面选能显示这一行的范围，滚到那一组，闪一下那一行。
  - 诊断：聊天列表探针不再要求表格在窗口里（在别的标签页打开设置也能读）。
  - 独立审查后改的：
    - `restore` 只管分组栏，`restoreAll` 连悬浮一起（插件关、未授权时）。以前分组栏关、悬浮开时每 0.75 秒的刷新会把悬浮拆掉重建、闪一下。
    - 插件不接管的页面（网页、Flutter、本设置）在 `!available` 里 `suspendFloating`：悬浮胶囊撤掉、微信的栏还原、分组栏回列表。hostTick 还要求 overlay 就在当前页的 nav.view 上。
    - 分组栏只在真正停住（自然位置高过停靠线）时才进 overlay，平时在列表里，不会盖住 + 菜单和下拉小程序面板。
    - 首页表头被“隐藏聊天列表顶部搜索栏”收起或栏被隐藏时，不出悬浮胶囊。
    - 分组栏开关打开时，若首页的栏正被悬浮淡出，先还原再取代。
    - 设置搜索：跳转时考虑该组的边框样式；结果行改成 `WXGSearchResultRow`；键盘弹出时底部留出键盘高度。
    - 分组透镜的键改成字面量（每帧会读几次）。
  - 版本 0.4.113-test4fix113o。服务器着色器不变（仍是 M）。
- N（用户 07:40，三件事）：
  - 删设置：折射页那一屏只留“边缘偏移抵消”（用户在选择题里选的）。镜内底栏小而平（M）、透镜里画底栏描边（L）、放大镜预设（J）、边缘向外取景（H）的设置和插件代码都删了。
    - L 的效果保留为固定行为：底栏透镜里永远不画底栏描边，点按动画的描边层也永远隐藏。
    - H 的透镜背景外扩（_lensPad、travelPad、WXGLensOutwardPad）全部去掉。
    - 服务器着色器不动：线上仍是 M 版，插件只是不再发 extra.w。
  - 分组栏（新文件 `WXGChatSegments.m`；设置在底栏页 ›“聊天列表分组栏”，`chatSegments` 默认开，两个槽深浅滑条）：
    - `WXGSegmentBar` 是底栏透镜的四段版。`WXGGlassView` 设 dockSurface，所以透镜、光学和点按脚本的参数都和底栏一样，复用 WXGDockLayout / WXGElasticLayout / WXGDockScript / 两端拉伸，触摸逻辑照 WXGDemoBar 抄、去掉微信切页相关部分。
    - GlassView 新增 `grooveBody`：本体平，没有折射、色散、模糊和边框；veilOverride 同时用在透镜里的 tintColor，按 1.22 换算、不渐隐。还新增 `selectionOverride` 做选中胶囊的颜色。显示链接空闲 10 帧后暂停。
    - `WXGChatSegments`：在首页 MainFrameTableView 的表头里找 UISearchBar 或 WCSearchBar，按输入框的矩形（searchTextField 或最宽的圆角视图）外扩 40pt 放进表头，表头本身就是搜索栏时放进 table；WeChat 的栏用 StateBag hide（alpha 0）。
    - 颜色：槽 = 黑色叠加（浅色 0.06、深色 0.45）；胶囊 = 往上找到的第一个不透明背景色；字为黑 0.86 或白 0.9。
    - 输入框开始编辑（微信自己的搜索、底栏搜索交接）就把栏还给微信；关掉、插件关闭、非同步渲染时 restore。开启时 hideTopSearch 不再收起表头。
    - 演示：切换不筛选，只记录。
    - 已知：和系统分段控件一样，从分组栏上开始的竖向拖动不会滚列表（UIControl 在 UIScrollView 里的默认行为）。
    - 诊断 `chatSegments.chatList`（只在诊断显示或导出、插件设置打开时读，5 秒节流，平时不读）：table 的 dataSource/delegate 类、各段行数、dataSource 和页面的 ivars、相关方法、visible cell 里通往用户名（只记类型 group/person/official/special，不记名字）和未读数的 ivar 路径、页面持有的数组、标签管理类和方法。
    - 读 ivar（审查后改）：weak 用 object_getIvar；strong 按 class_getIvarLayout 直接读；ARC 类的其它 ivar 不跟。没有 layout 的 MRC 类，只在 malloc_size>0 且 isa（不发消息）正好等于声明的类（字符串属于已知的字符串类）时才读。visited 集合用 opaque 指针；l、L 按 4 字节读。
    - 下一步：按 chatList 找到 cell → 会话 → 用户名、未读的路径，再用 heightForRow 返回 0 加隐藏 cell 的方式筛选（不改行数，避免和微信的增删冲突）。
  - 表情搜索异常捕获：`WXGLocalGlass controllerLaidOut` → `noteEmojiSearchPage:`。NewEmoticonSearchViewController 每次上屏，在 0.3、0.9、1.8 秒各记一次（每次启动只记前 6 个页面，类名用 class_getName，不 demangle Swift）：打开方式（输入框有字算快捷跳转）、输入框、祖先链、和输入框同一高度的视图（含我们的）、可能画出条带的视图（suspects）、本页的搜索玻璃和跳过原因。保留最近 9 条（`localGlass.emojiSearchCaptures`），第 1.5 秒的那次写一行日志。
- M（用户 06:47：“还是效果不够好，给个开关去掉连接内外框的斜线，直接和外面放大的断开，里面就是小的平的”）：
  - 那条斜线：镜内底栏的上下边在透镜两端被透镜边缘的折射往外弯（wxgLensBar 的 bend，两端折射带宽），一路弯到透镜边框；再加上 FIX47/FIX88 的 45° 内收斜坡。模拟器（user4 参数）里就是灰条两头向上翘、接到边框。
  - 开关 `lensBarFlat`（折射页 › 透镜边框 ›“镜内底栏小而平（与外框断开）”，默认关）。打开后镜内底栏不弯（bend = 原位）、整段按 `bodyPinch` 的完整内收（`WXGLensFullInset`），到透镜边框处直接断开；读回模式的镜内 inset 同样。点按动画的 veil（`WXGTravelVeilOutline`，`WXGLensFollow.flat`）在服务器着色器支持时也一样。
  - 传递：`extra.w` 的绝对值 = `WXG_LENS_FLAT`（1000），符号仍是 H 的方向。旧着色器把 +1000 当 FIX94 边距：边距那么大，`WXGLensBarZoom` 返回 1，镜内底栏就不弯了，只剩 45° 斜坡。向外取景时旧着色器会把 -1000 只当向外，所以那种情况不发。
  - 服务器：`plugin/ServerPatch_FIX113M/`。`worker.js.diff` 在 I 之上；`worker_without_HI.diff` 从 H 之前开始；也可以用整份 `worker.js`。`server/worker.js` 已导出，8 个水印位都在。诊断 `lensBarFlat.available/on`。
- L（用户 04:43：“我说的只是边框，不是底栏跟那个分离；边框是岔开的；透镜的边框跟底栏有什么关系”——K 理解错了）：
  - 截图放大看：透镜左上 / 右上拐角处，透镜自己的白色边框继续沿顶边走，同时从同一点分出一条白线，沿着透镜里那块页面色的条往里拐——“岔开”。那条是透镜那遍着色器画的底栏描边（`wxgLensBarLayers` 的 borderColor 描边和 FIX89 第二道高光 glowColor2）。用户 FIX112 起说的“上下边框两部分 / 外面一圈里面一圈”都是它。
  - 做法（只改插件）：透镜那遍（surface 1）把 `u.borderColor.w`、`u.glowColor2.w` 置 0，除非新开关 `lensBarOutline`（“透镜边框”组 › “透镜里画底栏描边”，默认关）打开；底栏本体那遍不变。点按动画（简化透镜）的 `_travelOutlines` 同样隐藏。
  - 撤回 K：`lensRimHug` 键、设置组、`extra.w` 的正值、点按动画的 follow 全部去掉（回到 FIX112 的“不跟随”）；放大镜式预设也不再填它。
  - 注意：K 之前的 FIX112 D 里用户说过要“缩小的底栏 + 上下描边”；这次他明确说边框不该和底栏有关，所以默认关掉描边、留开关。
- K（用户 04:04：自己调的一组比预设更像 iOS 26——透镜强度 3.05、色散 1.99、宽度 20、上下比例 0.56、收窄曲线 4.12、色散范围 8、上下 0.6；但透镜上下边缘一直“裂开 / 分开”，不能从边框那边比较完整地延伸过去）：
  - 模拟器用这组参数复现：透镜比底栏高，上下多出来的那条（透镜里看到的底栏外面）是一块单独的条，两头圆角、停在离边框一段的地方（拐角处折射带宽，往里取到了底栏里面），像两部分。录屏里 iOS 是一道贴着边框、两头收细并收进边框的暗弧。
  - FIX94 的“底栏跟着透镜边框”（`WXGLensBarZoom`：底栏在透镜里逐列竖直放大，使上下边离边框 = margin × 该处折射宽度，且不小于真实间隙 → 一道两头收进边框的弧）就是这个形状；FIX112 按用户要求删了设置（当时强度 20 盖住了效果）。所有服务器着色器里都还在（`extra.w > 0`）→ 不需要服务器更新。模拟（`scratchpad/lens_rim_hug.png`，浅色 / 深色，0 vs 0.3）：0.25–0.4 时就是贴边细弧。
  - 新键 `lensRimHug`（0..1，默认 0 关；新键，旧的 FIX94 / 112 值不带过来），底栏折射页新组“上下边缘贴合”。`u.extra.w`：向外取景开着（且同步渲染）时 −1，否则 `lensRimHug`（> 0 时）。点按动画（简化透镜）的轮廓同样跟随（`WXGLensFollow`，向外时 0）。放大镜式预设也填 0.3。
- J（用户 02:06，附 iOS 26 文件 App 标签栏拖动录屏：“这个透镜不是折射，几乎全是对下方内容的放大，折射只有一点点距离，越到透镜边缘越放大透镜范围内的内容”）：
  - 录屏逐帧看：透镜里图标在原位附近被放大，越靠边越被拉大、拉弯；上下只剩一道很细的暗弧（底栏外的部分被压到边缘）；边缘一圈窄窄的高光和色散。就是“整片透镜一个由内往外取景、越靠边放大越强的穹顶”，幅度不大。
  - 我们的公式（`WXGOpticalOffset`：带宽 × 幅度 × (1−smoothstep)²，向内）本来就能做到：把折射带设成透镜高度的一半（整片透镜都在带里），强度约 1（幅度 0.32），上下比例约 0.45。用户之前是宽度 8、强度 20（幅度 6.16，边缘往里约 50 pt，翻折、丢图标）——参数区间不对，不是模型不对。CPU 模拟（`scratchpad/lens_ios26_preset.png`：录屏一帧 vs 深色 / 浅色模拟）和录屏的放大、上下细弧一致。
  - 只加了一个按钮（不需要服务器）：底栏 › “iOS 26 式透镜” › “套用放大镜式透镜参数”：透镜折射宽度 = 底栏高度 × 透镜外扩倍数 / 2（夹在 1–60）、上下宽度比例 0.45、透镜折射强度 1.0、透镜色散 2.5（范围 8、上下 0.6）、边缘偏移抵消 0、向外取景关；弹窗确认，`save` 后刷新。H 的向外取景、I 的偏移抵消保留为可选项（服务器补丁用户已推 / 未推都不影响这个预设）。
- I（用户 22:00：H 的向外取景“还不如之前的”；觉得需要一个偏移值去消去实际的折射宽度）：
  - 新函数 `WXGLensRefractionOffset(distance,edgeWidth,strength,cancel)`（WXGOptics.h，着色器和网格共用）：cancel = 0 就是 `WXGOpticalOffset`（逐位相同，有测试）；cancel = 1 时边缘和折射带内侧都没有偏移，中间按 `edgeWidth × min(幅度, 1.55) × edge² × t` 推（边缘处压缩最多约 2.55 倍、带子一半以后拉伸；1.55 是不翻折的上限：映射斜率始终 ≥ 0.2；离原位最多 0.29 个折射宽度），所以加宽折射范围只让畸变的一圈变宽，下面的东西不丢；中间值线性混合（强度大时 0.5 一样会丢图标，模拟证实，建议 1）。标记 `WXG_LENS_CANCEL`，值放在 `u.style.w`（以前恒 0、旧着色器不读）。
  - 插件：`lensOffsetCancel`（0..1，默认 0），“透镜折射取景”组（和 H 的向外取景开关合成一组）。`WXGLensCancel()` 只有在着色器里有标记时才非 0；底栏透镜的背景网格（`WXGMeshOptics.cancel`，缓存键 / 相近判断都带上）和点按动画的背景同样抵消；向外边距按混合后的最远推开距离算。诊断 `lensOffsetCancel {available,value}`。模拟器 `tools/shader_sim` 加了参数 `cancel`。
  - 模拟（强度 20、宽度 8 / 20、向内，抵消 0 / 0.5 / 1）：1 时两种宽度下透镜边缘下的图标都在原位、被边缘弯折和色散；0.5 在宽度 20 时图标丢失。
  - 服务器：`server/worker.js` 已导出（H + I），`ServerPatch_FIX113I/`：`worker.js.diff`（已推 H 的情况）、`worker_without_H.diff`（没推 H）、整份 `worker.js`、中文说明；diff 路径是仓库根的 `worker.js`（H 那份写成了 `server/worker.js`，要在根目录用的话得改路径）。**未推送**，要用户推。
- H（用户 19:47，附诊断 5 + 两张截图（自己的透镜 / iOS 26 App Store）：① 表情搜索从输入框跳转还是有横条；② 想要 iOS 26 那样的边缘折射就得加大折射范围，但加大后透镜都快到图标上了图标还是不出现，缩小又几乎没有边缘畸变，要一个值能兼顾；③ 透镜边框“两部分”的现象还在）：
  - ① 诊断 `emojiSearchBand.around` 为空：搜索框底色视图的父视图就是 `NewEmoticonSearchViewController` 的根视图，F 的循环一上来就停了。现在一直看到根视图（含），根视图本身不清（它是整张面板的底色），只看它的其它子视图；诊断里每层还列出和输入框同一高度的兄弟视图（类名、位置、底色、是否隐藏、是否有图）。没有拿到横条视图本身，仍可能不是带底色的普通视图——下次诊断看 `around`。
  - ② 原因：透镜折射是“向内取景”：`refracted = p - n*offset`，边缘那一圈显示更靠里的内容，最大偏移 = 折射宽度 × 幅度（强度 > 2 后幅度 0.4 + 0.32 × (强度 − 2)，强度 20 时 6.16）。用户设置强度 20、宽度 8 pt → 边缘往里取约 50 pt：边缘下面 50 pt 内的东西都看不到（加宽范围更糟）。CPU 模拟（`tools/shader_sim`，用户参数，宽度 20、强度 3 / 5 / 8）证实：向内时强度 5 起透镜左缘下的图标消失；向外时都在，压在边缘上，而且透镜里的底栏一直铺到边缘，上下那两段灰色“边框”基本没了（③ 一并改善）。
  - 做法：着色器 `wxgLensDirection(u)`（`extra.w < 0` 为 −1）乘进透镜那遍的折射偏移和 `wxgLensBar` 的弯曲；标记字符串 `WXG_LENS_OUTWARD`。兼容：旧插件发 0（不变）；旧着色器只读 `extra.w > 0`（FIX94，已删），负值忽略；新插件只有在服务器下发的着色器里找到标记（`WXGPrepareMetal` 编译时检查，`WXGLensOutwardAvailable`）且设置 `lensOutward`（底栏 › 透镜折射方向 › “边缘向外取景（iOS 26）”，默认关）打开时才发 −1。`VER` 不变、uniform 布局不变。
  - 同步渲染模式下透镜下面的页面是 CA 网格折射的实时背景：`WXGMeshOptics` 加 `padX/padY`（图层 = 形状 + 四周边距，光学场按形状算，`WXGMeshShapeWidth/Height`），向外 = `offsetScale` 取负。底栏透镜的背景视图（`_lensStack`）在 `_lensClip`（按透镜裁切）里扩大 `_lensPad`（`WXGLensOutwardPad`：透镜边缘向外够到的距离 + 色散，最多 56 pt），网格的 bar* 坐标加边距；点按动画（简化透镜）的背景同样加边距，放在 (−pad, −pad)，键里带上边距。边距为 0 时与以前逐位相同。网格缓存键和“相近”判断带上边距。测试 `LensInsetAlongTests.c`：加边距只平移映射；向外在边缘与向内等距；带边距的轮廓网格覆盖形状、取样落在边距里。
  - 服务器：`server/worker.js` 已用 `tools/export_worker_shader.py` 写入新着色器（只改 3 处，8 个水印位置都在），`ServerPatch_FIX113H/`（diff + 整份 + 中文说明）。**还没推送**：用户推到 `xyydys/wxg-glass` main 后，手机要点“重新检测”并重开微信（插件一次运行只编译一次着色器），诊断 `lensOutward.available` 为 true 才算换上。
  - 建议参数（模拟）：打开向外后强度 3–8、宽度 15–25 pt 都能看到边缘畸变且图标不丢；强度 20 + 宽度 20 以上时边缘会把一百多 pt 外的内容压进来，像碎片。
  - 独立复查后：① 点按动画（简化透镜）的背景层原来跟透镜形状层一起被设成 / 动画到透镜大小，带边距时右、下各缺一条、网格也被压扁：现在带边距时背景层不在 `travelShapeLayers` 里，单独按“透镜大小 + 2 × 边距”设和做同一时钟的动画（`travelPad`）。② 非同步渲染模式取的是只比底栏宽 40 pt 的截图纹理，向外会取到边外（边缘拉丝）：`extra.w = −1` 只在 `_syncMode >= 2` 时发，设置说明写明只在同步渲染模式下生效。
- G（用户 18:15：未读角标、朋友圈红点这些要算在被透镜折射的那层，而不是浮在最上面不被折射）：
  - 经典底栏：角标不再是盖在底栏上的 UILabel，而是画进图标图集（普通、选中两张都画，`WXGIconJob.badges`：主线程准备好 {图, 位置}，图标队列只画）。位置和原来 `layoutBadges` 在缩放 1、无末端拉伸时一样（图集交给玻璃后，压下缩放和末端拉伸由玻璃统一处理）：微信 / 主题自己的角标图（FIX108 D）按它相对图标的位置；否则红色胶囊 + 数字（10 pt semibold，高 17）或 8 pt 红点（发现）。于是透镜里的选中图集、点按动画（渲染服务器版）的放大层、搜索变形层、备用图标都带着角标，透镜经过时角标跟图标一起被放大、折射。
  - 角标变了才重建图集：`badgeLayoutKey`（每格的值 + 角标图指针）并进 `iconLayoutKey`；`updateBadges` / `updateBadgeArt` 后 `rebuildIconsForBadges`（异步，新图集好之前保留旧的）。
  - UILabel 角标只在离散底栏显示（`applyBadgeVisibility`：没有值或不是离散底栏就隐藏；离散 / 经典切换时同步）。离散底栏没有透镜，角标仍在各胶囊右上角跟着宽窄走。
  - Telegram 动画补丁会擦掉图标框里的内容：补丁里画完这一帧后，把伸进这个框的角标（`atlasBadges`，随图集安装记录）再画一遍。
- F（用户 13:41，两张截图：表情搜索从表情面板点开正常，从输入框内容快捷跳转过去时搜索框所在那一行多出一条整宽的浅灰横条；Telegram 图标在离散底栏里和标题隔得太开）：
  - 表情搜索：没有这个页面的视图层级（探针抓取里只有搜索页 FTSHomeViewController）。推断：跳转打开时微信给搜索栏那一行刷了底色（整宽、比输入框高一些），从面板打开时是透明的；FIX109 E 的“只留输入框大小那块玻璃”让大的那块不加玻璃，底色就留着了。现在搜索框玻璃挂上后（`field:host:skins:`），在 `NewEmoticonSearchViewController` 页里，`clearSearchBandAround:` 把输入框往上 4 层祖先及其兄弟里“有底色、至少和输入框一样宽、把输入框中线包住、不高于 2.2 个输入框”的视图底色清掉（记在这块玻璃的状态里，玻璃撤掉时还原）。诊断：每块玻璃 `bandsCleared`，`localGlass.emojiSearchBand`（最近一次看到的输入框位置、清掉了什么、往上 4 层的类名 / 位置 / 底色）。如果横条还在，要在那个页面打开过后导出的诊断看 `emojiSearchBand.around`。
  - Telegram 间距：帧里给动画留了空（静止字形只占帧宽：聊天 0.86、联系人 0.74、通话 0.69、设置 0.81），离散底栏按整帧宽排图标和标题。`WXGTelegramRestInkWidth(tab)`（解码时从第 0 帧量）：离散底栏排版时图标宽度乘它（图像视图大小不变、不裁切，仍以字形为中心，动画越过间隙），标题离字形就是正常的间距，近了约 2–4.4 pt。经典底栏不变。
- E（用户 12:13 确认“可以了”，要了完整工程文件）（用户 11:54，附 XS Max / iOS 15.7 诊断：视频号左边两个按钮太靠边，照右边两个现在的样子做；有搜索按钮时离散小球高度设成和底栏一样会失效；C 那个包已经修好图标变白，D 里多余的改动可以撤回）：
  - 撤回：D 的 `WXGTelegramFillFrame`（source-in 上色）删掉，WXGTelegramIcons.m / WXGCommon.h 与 C 完全一致（C 的 `imageWithTintColor` 画进位图已经够了）。保留 D 里复查修的：动画自己的时钟、被打断标签的离散视图停掉、离散整套位图只在离散底栏显示时才做；经典底栏补丁每帧把这一帧 `imageWithTintColor` 后直接画进补丁（不建整套位图）。
  - 离散小球高度：诊断里底栏高 61.35、宽度比例 0.777（行宽 321.6），有搜索按钮时圆钮 61.35 + 间隔 8.2，离散底栏只剩约 252 pt，`WXGDiscreteFit` 直接把小球缩到约 44 pt（0.72 倍），所以 0.72 以上的“小球直径”都不起作用。现在：① `WXGDiscreteFit` 先保高度——选中项从设定的格数往下收（最少 `WXGDiscreteWideFloor` = 1.6 格），再收间距（最少一半、不小于 3 pt），最后才缩小球；② 宿主（`WXGHost` 底栏行布局）在离散底栏 + 搜索按钮时，把整行加宽到 `WXGDiscreteNeededWidth`（小球按设定高度、选中项 1.6 格、间距照设定）+ 圆钮 + 间隔，最多到搜索框展开那一行的宽度（`usable × dockSearchWidthFraction`）。诊断 `discreteRowGrowth`。用户这组设置在小球 1.0 时行宽约 381（≤ 389），小球满高、选中项约 1.6 格。设置说明同步改了。测试 `DockDiscreteTests.c` 加了三条。
  - 视频号左侧：诊断里有 `导航构建 WCFinderTimelineTabViewController：原生按钮 4 [MMBarButton,MMUIButton,MMBarButton,MMBarButton]`、`导航玻璃 2 [finderCapsule,finderCapsule]`（两侧各一组），没有几何。现在 `bindFinderCapsules:` 先量两侧胶囊：左边胶囊离左边缘比右边胶囊离右边缘近时，左边整组往里挪到同样的边距（只往里、最多一个按钮宽）。挪法不改微信任何视图的 frame（它自己排版会抵掉）：用 `WXGStateBag shiftContents:x:`（父视图 `layer.sublayerTransform` 平移，可还原、reapply 时补回）。左侧按钮的公共父视图只装左边的（整块在屏幕左半边）就平移它（胶囊在里面一起走），否则平移每个按钮自己的内容、胶囊按挪后的位置放。每次构建先撤掉上次的平移再量（同一次布局里，不会闪）；离开视频号（非视频号页构建且不在转场中、转场结束的新页不是视频号）撤掉平移（导航栏的视图可能给下一页复用）。诊断 `finderCapsules`（每块胶囊的边、按钮数、父视图类、位置、挪了多少、挪法 container / buttons）。不确定：sublayerTransform 是否参与 UIKit 的点击判定（不参与时点击区域留在原处，差几 pt）、玻璃取背景的位置是否算上它（不算时折射的背景偏几 pt）。
- D（用户 11:22：离散底栏点了以后标题已是强调色，图标到动画结束前都是白的；离散底栏开搜索再关，先变回完整底栏再变离散；视频号不再做图标位移、不用单独的玻璃按钮，只用胶囊垫在原来两个图标下面）+ C 的独立复查修正：
  - 帧的颜色：`WXGTelegramFillFrame(frame,rect,color)`（WXGTelegramIcons.m）在透明层里先画帧的白色覆盖，再 source-in 填颜色，不依赖 UIKit 画 tint 图时是否上色（`animationImages` 只播位图本身）。静止帧、离散底栏的帧位图、图集补丁都用它；补丁直接在纹理补丁的上下文里画（不再为经典底栏建整套位图）。离散底栏的整套位图只在离散底栏显示时才做（NSCache 8 套）。
  - 时钟（复查 1）：微信切页面会卡主线程 0.1–0.7 s，按墙钟算帧时一卡就直接播完回静止。现在动画有自己的时钟，每次 tick 最多走两帧（`telegramClock`）。
  - 被打断的标签（复查 3）：新标签开始时，上一个标签的离散底栏图像视图也停掉清空；`stopTelegramAnimation` 只停当前标签那两个视图（`stopDiscreteTelegramTab:`）。
  - 搜索关闭回离散底栏：原来 `discreteWanted` 要等变形完全结束（弹簧尾巴约 0.5 s 都是整条经典底栏）才交叉淡到离散。现在关闭时进度回到 0.15 以下就切回离散（`WXGDiscreteReturnProgress`），经典底栏和变形层的标签在离散底栏下面一起淡出（`fadeClassicOut`，0.2 s），之后收起并恢复不透明度；变形尾巴里阴影路径不再被变形外形覆盖；离散底栏回来后马上能点（beginTracking 先看离散）；弹簧过冲重新触发 `beginMorph` 时离散底栏保持、不取消触摸、不显示经典标签；尾巴里又打开搜索时变形层重新显示。
  - 视频号（WCFinder 页）：不再给每个按钮建插件的玻璃按钮、不再把图标挪到插件的位置、不再藏微信的按钮。`bindFinderCapsules:`：同一侧、相邻（中心距 ≤ 1.75 个按钮）、同一高度的原生按钮为一组，每组一块 materialOnly 胶囊（每个图标一个按钮高度的圆形槽，文字按钮按左右同样的边距加宽，连起来），插在它们最近的公共父视图里、它们那一支的下面（只在导航栏自己的视图里），跟首页左上角图标一样随原生视图移动和淡出、不接触摸；仍是透明材质 + 深色边框（`styleFinderButtons`）。`WXGSurfaceInNativeView`：nativeGesture / finderCapsule 不做原生运动跟随。没有用户的视频号诊断，按钮结构按导航栏通用方式找；如果胶囊没出现或位置不对，要视频号页面的诊断。
  - 未改：复查 4（GPU 读纹理时 CPU 改写可能撕裂一帧）仍接受。
- C（用户：能不能再加一个自定义强调色）+ B 的独立复查修正：
  - 强调色：新键 `dockAccentHex`（默认 `#08B861FF`，即原来的选中绿），底栏 › 图标与动画 › “选中强调色”。`WXGDockTabColor(selected,…)` 选中时用它（图标和标题都用；系统符号、Telegram 图标、离散底栏同一个函数）；微信原生图标保持它自己的颜色（那套是微信给的图）。`iconLayoutKey` 带上它，改色即重建图集。
  - 普通点按不播动画（B 的主要问题）：`telegramSettle` 在手指按着时返回，松手路径又没再调。现在两种底栏的 end tracking 在最终选中（含回到原标签 / 保留按下时的切换）之后、以及 `cancelTrackingWithEvent:` 里都调一次；回到原标签不播。
  - 帧画法：`replaceIconPatch` 换成 `-[WXGGlassView drawIconPatchAtPixels:scale:selected:drawing:]`：直接在纹理像素布局（BGRA / RGBA 预乘）的 CGBitmapContext 里按图集的点坐标画（UIKit 翻转 CTM），不经中间图片、不取整尺寸；外扩 1 px（原来 1 pt，标题间距很小时会擦到标题）。用安装图集时记下的几何（`atlasCenters` / `atlasIconY`，同步和异步两条路径都记），不再用底栏当前的几何（异步重建前两者可能不同）。
  - 动画中途图集被重建（异步）：装上新图集后 `_telegramLastFrame=-1` 并立刻 tick，当前帧画回去，不闪静止帧。离散底栏显示时也照样改经典图集（原来直接返回，图集停在中间帧）。
  - 帧图：Telegram 帧是白色模板，`imageWithTintColor` 的图放进 `animationImages` 会播成白色。现在每个标签 × 颜色一套预先着色的位图（`telegramBitmapsForTab:selected:`，NSCache 上限 8 套，每套约 60×96×96×4 ≈ 2 MB），补丁和离散底栏都用它；`WXGTelegramTabImage`（静止帧，给图集队列画）也改成缓存的位图。`stopTelegramAnimation` 同时停掉离散底栏图像视图的动画并清 `animationImages`。
  - 素材：Chats 的帧碰到裁切边，重新生成：四个都裁 512 画布里 87..425（`HALF=169`），边缘覆盖 ≤ 5/255。
  - 其它：Telegram 图标打开时不再做选中后的微信原生图标重扫；双端输入栏原生大小的图标原点取整到设备像素。
  - 已接受：GPU 读纹理时 CPU 改写，极少数帧可能撕裂（1 帧内的局部差异，看不出）。
- B（用户 10:46：换回微信原生图标后大小不是原生的；底栏要 Telegram 的四个带切换动画的图标，发现 = 通话、我 = 设置）：
  - 双端输入栏用微信自己的图时，`WXGSurface.naturalIconSize`：图标按它自己的大小画（裁掉透明边后的字形点数，和微信里一样大），只有放不下才缩；系统图标仍按插件的框。
  - Telegram 图标：素材是 Telegram for iOS 开源仓库（GPLv2）里的 `TabChats/TabContacts/TabCalls/TabSettings.json`（Lottie，60 fps，38/36/43/45 帧）。本机编 rlottie 逐帧渲染，四个裁同一个正方形（512 画布里 95..417），96×96 灰度覆盖，竖排成一张 PNG，嵌进 `Sources/WXGTelegramTabIcons.h`（约 270 KB；生成脚本 `tools/telegram_tab_icons.py`，文件头写了 render.c 的做法）。`WXGTelegramIcons.m` 第一次用时解成白色预乘的模板帧（每个图标约 1.5 MB）。开关 `dockTelegramIcons`（底栏 › 图标与动画，默认关，优先于微信原生图标）。微信 = 聊天、通讯录 = 联系人、发现 = 通话、我 = 设置；颜色用插件自己的选中绿 / 未选中墨色。
  - 静止：`WXGDockTabArtwork` 给第 0 帧（= 最后一帧）。切换：`selectIndex:` 结尾 `telegramSettle`（手指还在底栏上不播，松手落定才播；第一次只记下不播；减弱动态效果不播），自己的 CADisplayLink 按 60 fps 取帧，把那一帧画进图标图集里该标签的 26 pt 图标框（普通、选中两张图集都画），`WXGGlassView replaceIconPatch:` 直接改纹理（图集纹理改为 shared 存储，按纹理的 RGBA/BGRA 写），播完写回第 0 帧；被打断的那个先回到第 0 帧。离散底栏用两个 UIImageView 的 animationImages 播同样的帧。简化点按动画、搜索变形、回退图标用静止的图集。
  - 授权提醒：这些图标是 GPLv2 素材，对外分发插件要遵守 GPL（或者只自用）。
- 双端（两段式，`WXGInput.m`）输入栏：表情键的图标从 `face.smiling.fill` 换成 SF Symbol `faceid`（表情面板打开时仍是 `keyboard`）。新开关 `inputSystemIcons`（默认开，基本设置 › 适配“双端输入栏用系统图标”）：开 = 插件这一套 SF Symbols；关 = 微信自己那个按钮当时的图（只取 `UIButton.currentImage`，不从子视图里找，免得拿到发送键的绿色底板或听写的背景图），微信没有图的地方仍用这一套。加号、表情、右侧（发送 / 语音转文字 / 语音 / 键盘）都按这个来，每次布局都设（同一张图 `setImage` 直接返回；SF 图缓存）。
- 三端（三段式，`WXGNativeInput.m`）听写图标的背景：原来那个 52×40 的静态底板只在 0.35 s 一次的 `clearPaint` 里找、用透明度藏；微信在听写状态变化时会换一个新底板或把它重新显示，于是露一下才没。现在 `concealDictationBacking` 每次布局都看（只看听写视图的几个子视图），用空遮罩（微信改透明度也露不出来）；宿主还 hook 了 `MMGrowDictationIconView` 的 `layoutSubviews`，它一排版就触发输入栏布局。诊断 `dictationBackingsConcealed`。



## FIX112（用户 08:45：透镜上下边框两段、中间空；要整片透镜滤镜色；删两项设置；按钮比标题低）

- 透镜：截图里透镜只有上下两段边框，两端（左右）是空的。原因：透镜边框 `_lensRim`（CA 的 WXGRimView）沿用了底栏的“两侧淡出”（`rim.fade`），透镜两端正好是“侧”，淡没了。现在透镜边框 `fade:0`，整圈连续；左上 / 右下渐隐照旧。上下那条深色槽（透镜比底栏高，镜内看到的是页面）不改，靠滤镜色把整片透镜连成一体。
- 整片透镜滤镜色（新）：`_lensClip` 里一层 `_lensTint`（CALayer，跟透镜的连续圆角一起裁），颜色 `lensTintHex` / `darkLensTintHex`，浓度 `lensTintOpacity`（0.12）/ `darkLensTintOpacity`（0.08），乘透镜抬起量 `_pressAmount`（静止的选中胶囊不受影响），只在底栏（`_dockSurface`）。渲染服务器模式（renderMode ≥ 2）放在 `_lensMetal` 下面：盖住镜内的页面和底栏底色，图标在上面；其它模式镜内那层是不透明的，就放在它上面。设置在“边框”页的“浅色 / 深色模式 · 透镜”组。没动着色器、`WXGUniforms`、`VER`、服务器。
- 删除“镜内底栏贴着透镜边缘”和“镜内底栏离边缘”：设置行、`WXGConfig` 的两个键和方法都删了；`u.extra.w` 固定 0；底栏点按动画的轮廓（`WXGTravelVeilOutline`）不再传 follow。服务器上的着色器里 `extra.w>0` 那段分支还在（死代码，下次改着色器时一起删）；`WXGTravelVeil.h` / `WXGLensOptics.h` 的数学和测试保留没动。
- E（用户 10:20：没开滤镜色，透镜里的颜色却和下面的底栏、背景都不一样）：D 默认“跟随底栏材质”把镜内底栏的底色换成一层平铺的底栏材质（没有边缘渐弱、盖在没模糊的页面上），底栏外面那条也被铺成底栏色，所以和下面哪个都对不上。撤掉 D 的做法：透镜 pass 恢复原样（底色不再随抬起淡出），`lensTintFollowsMaterial` 删掉，新开关 `lensTintOn`（默认关）：关时透镜里就是它下面的东西（和 FIX111 及以前一样），开时滤镜色盖在整片抬起的透镜最上面（图标也在下面），乘 `clamp(press/0.9)`。点按动画（渲染服务器版）同样：底色带不再淡出，滤镜色层放到透镜最上面、只在开关打开时有颜色。到 E 为止透镜相对 FIX111 只剩两处改动：边框不两侧淡出、可选滤镜色。
- D（用户 10:09：C 改坏了，透镜里看不到原来那个缩小的底栏和它的上下边框）：用户要的是“缩小的底栏 + 上下描边”保留，只是透镜边框和缩小底栏描边之间那一条不要比别处透明。撤掉 C 的开关 `lensShowsBar`；透镜 pass 只把底栏底色 `tintColor.w` 乘 `1 − clamp(press/0.9)`，描边 / 高光（`borderColor`、`glowColor2`）不动；`_lensTint` 改成“透镜整片的底”：默认跟随底栏材质（`lensTintFollowsMaterial`，颜色和覆盖率直接取 `_veilFallback` 的），乘 `clamp(press/0.9)`，和底色的淡出正好交接，抬起后整片同一层材质、缩小底栏只靠描边看出；关掉跟随用自己的颜色 / 浓度。设置：边框页透镜组恢复原样，新组“透镜滤镜色”（跟随底栏材质 + 浅 / 深颜色和浓度），折射页 C 加的“镜内底栏”组删掉。点按动画（渲染服务器版）：只淡出底色带（`_travelVeilBands`），描边保留，滤镜色同样跟随材质。
- C（用户 09:07：透镜还是外面一圈、里面一圈、中间更透明）：里面那圈是着色器画的“镜内底栏”（内缩的底栏描边 + 底色），两圈之间是底栏外的页面（只有滤镜色）。新开关 `lensShowsBar`（默认关，折射页“镜内底栏”组）：关时透镜那一遍的 `tintColor.w`、`borderColor.w`、`glowColor2.w` 乘 `1 − clamp(press/0.9)`（只在 Metal 的透镜 pass、只在底栏），抬起后透镜里只有页面 + 滤镜色 + 图标 + 透镜自己一圈边框；静止的选中胶囊不变。渲染服务器版点按动画的 `_travelVeil` 同样按压力淡出（opacity 关键帧）。不改着色器和 uniform 布局。用户这次附的诊断是 0.4.105 的旧文件（当时 dockRimFade=0）。
- B（独立复查后）：① 按钮对齐改量页面自己的标题视图（微信多数页面用 MMTitleView，A 只看导航栏自带标题，设置 / 通讯录上其实没生效）：`WXGLocalTitleCapsuleRect(bar,titleView,window)` 先 `WXGLocalTitleFrame(titleView)`，再退到导航栏自带标题；聊天页也量（标题视图被宿主遮住也照量，插件的标题胶囊跟着走）；首页不变。量到就记下“标题中线 − 导航栏中线”（按导航栏高度），量不到（标题还没排好、或没有标题）用之前记下的，页面之间不跳；第一次一个都没量到时 0.15 s 后再看，最多 3 次。对齐时不再用安全区下限。② 点按动画（打开“简单点按动画”时的渲染服务器版透镜）也有滤镜色（`_travelLensTint`，随压力关键帧）。③ 设置说明改准：渲染服务器模式下滤镜色铺在页面上、镜内底栏底色 / 描边 / 图标在它上面；其它模式盖住整片透镜。
- 按钮高度：微信的标题文字在导航栏中线以上（设置、通讯录等），本地玻璃的标题胶囊跟着文字，插件的按钮却按导航栏中线（再被安全区下限往下压）放，于是比标题低约 5 pt。现在非聊天页、非首页时，按钮的中线取标题胶囊的中线（`WXGLocalTitleCapsuleRect`，同一套几何，标题胶囊没挂上也能算），差太多（超过半个按钮）才不跟。聊天页（插件自己的标题胶囊）和首页不变。诊断 `titleAlignedButtons`。



## FIX111（用户 03:44：撤掉所有高系统液态玻璃的尝试）

- 用户结论：FIX110 是在“插件自己的样子上套系统玻璃”——新旧样式位置不一样、底栏还是插件自己的、动画仍绑在插件上，重复且乱。要求清掉 FIX110 全部尝试，先拿工程文件。
- 做法：`git revert` FIX110 A…H2 全部提交，源码树与 FIX109 E（15c6c3a）完全一致；`tools/wxg_sdk26.py` 一并删除。只加了一件事：构造函数里 `WXGRemoveFix110Leftovers()`，按 FIX110 自己在套件 `com.runyu.WeChatLiquidGlass` 里的记录，把它改过的微信偏好原样还回去（B 写的三个键、F 加的 IgnoreSolarium、F 删掉的 UIDesignRequiresCompatibility=YES），然后删掉这些记录（design.* / nativeGlass.*）；没有记录就什么都不做，别的插件的键不碰。
- 以后若重做“高系统原生玻璃”，要点（已验证，FIX110 G 在 iOS 26.6 上让微信进了新设计）：
  - UIKit 每次启动只判断一次是否用 iOS 26 新设计；兼容设计里 UIGlassEffect 只是实色填充，单个视图怎么做都没用（FIX110 D 三种逐视图办法全失败）。
  - 判断条件：主程序链接的 SDK ≥ 26（LC_BUILD_VERSION 的 sdk 字段；VVebo 那种老 SDK 的要改这个数并去掉重复 LC_RPATH），且 Info.plist 的 `UIDesignRequiresCompatibility` 不是 YES。`+[_UIKitFeatures uncachedSolariumEnabledForCurrentDeviceIdiom]` 是 UIKit 自己的答案。
  - 微信 8.0.6x 已经用 iOS 26.1 SDK 编译，只是 Info.plist 写了 UIDesignRequiresCompatibility=YES。所以只需在插件构造函数里（UIApplicationMain 之前）hook `NSBundle objectForInfoDictionaryKey:` 和 `infoDictionary`，对主 bundle 的这一个键答 NO。
  - 代价：整个微信变成新设计——导航栏按钮项自带玻璃 platter（每项 `hidesSharedBackground` 可去掉，系统返回按钮不行；玻璃由 platter 容器 `_UIMultiLayer` 里的玻璃组层画）、tab bar 变成悬浮玻璃、列表有 UIScrollEdgeEffect。正确方向是用系统组件本身（UIBarButtonItem / UITabBar / UISearchBar / UIGlassEffect + UIGlassContainerEffect），而不是在插件自绘的栏上叠。


## FIX109（测试版 A · 基于 FIX108 F；用户 07:52 的七条）

- 表情分组选中块（`WXGLocalGlass.m tabCell:`）：用户报“改圆角无效、玻璃也会丢”。玻璃原来放在白色方块里面（清掉它的底色），微信选中哪格就显示哪格的方块（隐藏 / 显示，也可能是清空 / 填色），方块被换样子时玻璃跟着没了，而圆角只在格子布局时读（表情面板被微信留着复用，不重新布局就一直是旧值）。现在：玻璃放在方块旁边（同一父视图，紧贴方块上面），方块本身用空 mask 遮掉（`conceal:`），每次提交前按方块“会不会显示”（hidden、alpha、底色不透明度）立刻显示 / 隐藏玻璃（`entry.shown`）；圆角滑杆改动后在提交前按配置版本重读（`radiusFor`，加号方块同样）。认方块时不再要求有底色（选中前可能是空的），认过的方块记在关联对象上。隐藏的玻璃在 tick 里停用（像不在屏幕上）；激活 3 秒内没画出来的玻璃以前就一直空着，现在每约 1 秒再试一次（链接停下后 0.5 秒唤醒），直到画出来。
- 搜索框被主题压住：ThemeBox 在 `WCSearchBar` 最底层加一张和输入框一样大的 `UIImageView`（皮肤），并把微信的白色底（我们找的那个 plain UIView）清成透明，于是 FIX107 找不到底色、不加玻璃。现在默认玻璃优先：底色被清空的圆角 plain 视图也认（第二轮），和输入框重叠 ≥70%、面积不超过 2.5 倍的图片视图当作主题皮肤藏起来（可恢复）；宿主或它直接子视图的子视图数变了（主题后加皮肤）就在提交后重看。新开关“搜索框让主题优先”（`pref.localSearchThemeFirst`，默认关）：开着时有皮肤或底色被清空就不加玻璃；切换开关时先撤掉所有搜索玻璃再重看。皮肤只在微信自己的搜索栏里找（输入框自己的背景图不算）。
- 聊天右上角按钮显示头像（`pref.chatAvatarButton`，默认开；`chatAvatarInset` 0–12 pt，默认 4）：右边最外侧的按钮（聊天信息）还是原来那个按钮、原来的动作，玻璃里画对方 / 群的头像（和头像模式同一套查找、缓存和重试，找不到时是灰底占位图），圆形、按内边距缩进、头像描边用头像模式的描边设置；角色 `chatAvatarButton`（不当作标题头像，不裁切、不染色）。
- 头像模式下小胶囊高度（`avatarCapsuleHeight` 22–44 pt，默认 30）：上沿不变，字号按比例（30 → 17 pt，最多 20 pt）。
- 置顶模块跟着头像模式下移：需要先抓视图和触摸层，本版不动；探针升级到 TEST6（见下）。移动方案：默认胶囊底边 = `centerY + m.button/2`，头像模式小胶囊底边 = `y + 60×比例 − 5×比例 + 胶囊高`，置顶模块下移两者之差（胶囊高变了差值跟着变）；要确认置顶模块是谁、谁排它（约束 / frame）、移出父视图范围后触摸是否还能到、消息列表的 inset 要不要一起加。
- “插件”页标题：系统自己的标题标签（`_UINavigationBarContentView` 的直接子 `UILabel`，iOS 16 起在 `…TitleControl` 里）。新宿主类 `_UINavigationBarContentView`（`systemTitle:`），胶囊和别的标题一样高，限制在内容视图里（它在有些页面裁剪）；标题视图页（MMTitleView）没有这种标签，跳过。标题类的测量统一成 `titleMeasure` 块（MMTitleView / 系统标题）。
- 选照片左上角关闭按钮：同一导航栏里有 `MMDropableTitleView` 的灰胶囊（24–48 高）时，左侧只有图标的按钮的圆形玻璃改成胶囊的高度（32），其它按钮不变（`WXGLocalNavMatch`，0.25 秒缓存）。
- 普通边框向内渐隐（边框与渐隐 › 普通 · 向内渐隐，`rimInward` / `dockRimInward` / `bubbleRimInward` 默认开；宽度 `…RimInwardWidth` 0.3–24 pt 默认 4，曲线 `…RimInwardCurve` 0.5–16 默认 4，浅色深色各一套）：普通样式的线换成像 iOS 27 那样从轮廓往里渐隐的光，颜色 / 不透明度 / 亮度 / 左下右上渐隐都用普通样式自己的（渐隐 mask 仍盖在上面），整圈一样亮一样宽（没有沿轮廓的明暗）。台阶算法 `WXGRimInwardBands`（`WXGRimGlow.h`）：先每个设备像素一级（取曲线在这一级上的平均值），超过 20 级就把相邻亮度差最小的两级合并（尾巴和平缓处变宽，陡处保持一像素一级），嵌套的 Core Animation 边框叠出各级亮度（已在桌面上验证合成值等于每级平均值）。底栏透镜里看到的底栏轮廓（着色器）同样用这条曲线（glow 参数角度 0、端部亮度 1）。打开时“描边细节”的分级线不用（内阴影照旧）。
- 独立复查后（发布前已改）：没画出来的玻璃 3 秒后的重试不算“忙”（否则显示链接永远不停），每约 1 秒试一次、最多 30 秒；主题皮肤要四条边都在输入框几 pt / 15% 以内、不能包着输入框、里面没有微信的子视图（以前搜索栏整条背景图也可能被当成皮肤藏掉），皮肤只在搜索栏子视图变了时重找；分组方块先找已知 / 有底色 / 隐藏的，再找空的；导航栏内容视图被遮住时不加系统标题（否则加了又被撤）；向内渐隐把不透明度直接算进每层的 alpha（不用组不透明度，少一次离屏渲染），宽于圆角时左下 / 右上渐隐的角窗口跟着放大。
- FIX109 B（置顶模块跟着头像模式下移；依据探针 TEST6，XS Max，WeChat 8.0.73，装着 FIX109 A）：
  - 结构：聊天页 view 的子视图 `MMNewMsgContentNavBar`（按 frame 排，有置顶时 0,0,414,155 = 导航 88 + 置顶 67），里面四个子视图：从顶上开始的背景 UIView（0,0,414,155）、收起的置顶容器（y 88，高 67：`MMMsgCommonTipsView` 在它里面 y 8，自己不接触摸；容器上的点按手势 → `MMNewMsgContentNavBar onTapMixedList` 展开）、展开列表的容器（y 88，收起时隐藏、高 0；展开后高 154，里面 `MMMsgTipsMixedListExpandView` 的表格，每行一个 `MMMsgCommonTipsView`，右按钮 `firstTapRightButton`、整行 `performBgAction`）、黑色 0.8 的遮罩按钮（展开时全屏，`onMaskBgClick` 收起；展开时整条栏也变成全屏）。消息列表 `MMTableView` 的 contentInset 上 = 155（栏的高度），不自动调整。
  - 头像模式下默认胶囊底边 87.68、头像下小胶囊底边 128.08，差 40.4 pt，置顶顶边 96：两种模式下置顶和胶囊的间距都是 8.3 pt。
  - 做法（`WXGHost.m alignPinnedModule`）：头像模式的标题排好时算出位移 = max(小胶囊底边, 头像底边) − (centerY + m.button/2)，按像素取整（小胶囊高度、头像大小 / 位置变了位移跟着变）；栏里所有从顶部以下开始（y ≥ 20）的非按钮子视图（两个容器）y 加上位移；置顶显示时消息列表的 contentInset 上和滚动条 inset 也加上位移（在最顶上且没在拖动时偏移跟着改）。微信自己设的 frame / inset 记下来（我们设的值和它当时的原值），微信再改就以它的新值为准，位移为 0 时还原。栏自己的 `pointInside:` 加了一层：落在被移到栏外的容器里的点也算在栏里，否则下移的那部分点不到。微信的栏布局之后、以及每次提交前（观察者 1999700）都对一遍。诊断里 `pinnedModule`（shift / applied / moves）。
- FIX109 C（用户试 B 后）：
  - 普通边框 A / B 的“向内渐隐”不成功：用户要的是原来那条线基本不变、只在边缘有一点泛光的柔和感，而 (1 − 深度/宽度)^曲线 从轮廓起就开始变暗，宽了是整段渐变，窄了又看不出柔和。改为“线 + 泛光”（`WXGRimSoftBands`）：线本身（普通样式的“宽度”）实打实满亮、一层；紧挨着里面一段泛光，从“泛光亮度”（线亮度的比例）按高斯 level·e^(−4.6x²)（x 0→1，末端剩 1%）在“泛光宽度”内消失，四分之一像素一级（Core Animation 给边框的小数内沿抗锯齿，几级合成一段平滑过渡），超过 20 级合并亮度最接近的相邻两级；线和泛光的分界不会被合并（除非泛光亮度 = 1，那就是把线的内沿柔化）。新键 `…RimSoftWidth`（0–4，默认 0.8 pt）、`…RimSoftLevel`（0–1，默认 0.5），A 的 `…RimInwardWidth / Curve` 删除；开关仍是 `rimInward`（设置里叫“线的内侧加一点泛光”）。底栏透镜里看到的底栏轮廓恢复成普通的线（A 用 glow 参数近似，泛光在透镜里不画）。
  - 头像模式：小胶囊高度上限 48；新设置“置顶与小胶囊间距”（`pinnedGapAdjust`，−16…+16 pt，默认 0 = 和默认胶囊模式同样的约 8 pt，负数更近）。
- FIX109 D（用户试 C 后）：
  - 头像模式小胶囊加高时字不再跟着变大（用户加高就是因为字占玻璃太多）：字号 = min(17, 高度 × 17/30)，只在比默认 30 矮时缩小。
  - 置顶模块返回时弹回原位：B / C 在路由离开聊天页（返回列表、聊天页还在滑走）时把位移清零并立刻还原。现在位移只由聊天页的标题排版设置，离开时保持（随页面一起滑走 / 渐隐），页面释放后（栏没了）才清零。
  - 取自背景也用“线 + 泛光”：`WXGRimTintView` 的遮罩改用 `WXGRimSoftBands`（颜色仍是背景处理后的颜色），开关 `rimSampleSoft` 系列、宽度 `…RimSampleSoftWidth`、亮度 `…RimSampleSoftLevel`（第一次从普通样式的值继承）；没有自己背景的玻璃（气泡、设置卡片）由边框视图按取色颜色画同样的线 + 泛光；打开时深色两侧的黑底不用。`rimSoftWidthForScope / LevelForScope` 按该范围的样式取对应的值（iOS 27 为 0）。
- FIX109 E（用户 10-19 18:22 的两个 bug；用户下一步打算加“切换成系统原生玻璃”用来对比，本版没做）：
  - 插件没启用（总开关关、没授权、验证中、被踢）冷启动时闪一下玻璃 / 底栏：`MMTabBar layoutSubviews` 的钩子在任何刷新判断开关和授权之前就调 `suppressNativeDockPaint`（把微信底栏用空 mask 遮掉）和 `buildDock`（造底栏玻璃），刷新时才发现不该有再撤，于是闪一下。现在 `buildDock` 要 `WXGPluginEnabled() && pref.dock && overlay 已在窗口里` 才做；`suppressNativeDockPaint` 不满足时直接还原微信底栏；刷新时只有授权了才把 overlay 放进窗口（否则撤出）；总开关关 / 没授权时立刻隐藏底栏、还原底栏遮罩和返回时遮掉的底栏截图、置顶模块位移清零还原。刷新里先记“主界面已出现”再读授权（独立复查发现：否则冷启动第一次刷新读到的还是启动时的“未知”，overlay 不放、底栏和顶栏按钮要等下一次刷新）。返回首页时遮底栏截图（`concealTransitionSnapshots`）也要插件启用着（底栏玻璃造过一次就一直留着，以前撤掉后返回首页还会遮微信的底栏截图）。
  - 被踢 / 移出名单的账号：手机里还有没过期的票，离线优先，所以冷启动先当已授权，复查回 403 才删票撤掉，这一下是闪的来源之一。现在缓存一读完（构造函数里就开始读，远早于微信界面出来）、手机里只有一个账号的票时，就对这张票发复查（有几个账号的票时不发：最新那张不一定是登录着的账号，会把它自己的请求压后一轮；到期了才发，和第一次判断时本来就会发的是同一个请求，不等它、不延迟显示），403 多半在微信界面出来前就回来、票已删，界面出来时就是未授权，不再闪。网络很慢时仍可能闪一次，之后票已删就不会了。诊断 `launchRechecks`。
  - 表情搜索里两块搜索框玻璃叠在一起：一块是输入框大小的，另一块是更大、几乎整宽的胶囊。新规则：同一个页面（同一个视图控制器或其父子）里两块都显示着的搜索框玻璃，重叠超过较小那块的一半，就只留小的（输入框大小的）：后来的大的不加（跳过原因“和另一块搜索框玻璃重叠”），后来的小的把已有的大的撤掉。另外 FIX109 的“主题清空了底色”那一轮收紧：只认直接放在 `UIStackView` 里的（微信 `WCSearchBar` 的底色就在内层 stack 里，见 cap3 抓取），高 ≤ 44，且不能和搜索栏一样宽（至少窄 6 pt）。不同页面（推入时两页的搜索栏重叠）不算重叠。
- 探针 TEST6（`scratchpad/probe`，1.3.0-test6）：每个圈选元素多记触摸层（15 个点的真实命中、往上每层是否接触摸 / 是否包含它 / 谁改写命中 / 手势和目标）、布局（约束、自动尺寸、谁排版）、页面结构（顶层视图、列表 inset / 偏移、附近的 WXG 视图）；面板加“触摸记录”（真实触摸：命中链、收到触摸的手势、哪些手势响应、控件动作；窗口上的旁观手势在按下时就失败退出）。

## FIX108（测试版 A · 标题胶囊、选照片标题、网页 / 弹出页面的顶部按钮）

依据：探针 TEST5（圈选）在 XS Max（iOS 15.7，微信 8.0.73，未装 WXG）上点选的 18 个元素。
- 标题：首页 `MFTitleView`、其余 `MMTitleView`，都是导航栏中间 1×36 的视图，里面 17pt `MMUILabel`（`.SFUI-Medium`，黑 0.9），标签的 frame 以标题视图中心为原点；首页标题视图里还有隐藏的转圈（收取中）、两个隐藏标签、一个隐藏的 16pt 图标。“插件”页（第三方）是系统标题标签，不处理。
- 选照片：`MMDropableTitleView`（207×32）里 `MMUIButton` 114×32，底色 0.298 灰、圆角 16（这就是原生的灰胶囊，动作 `MMDropableTitleView onClick:`），旁边白字 `MMUILabel` 和 20pt 箭头。
- 关闭按钮：链接页 ×（`MMWebViewController OnClose`）、···（`onOperate:`）、相册 ×、收藏 / 卡包 ×，全是 `MMBarItemCustomView` 里的 `MMBarButton`（24×44，24pt 模板图）。它们没有玻璃的原因：`WXGRouteForWindow` 把类名含 `WebView` 的页面和弹出的页面整页标成 `unsupported`。
- 公众号消息页 `BrandTLFlutterViewController` 是 Flutter 画的，探针点不到任何视图，WXG 也盖不了。

改动（都在 `WXGLocalGlass.m`，FIX107 的“更多玻璃”框架）：
- 新种类 `title`：宿主 `MFTitleView` / `MMTitleView`（玻璃作为标题视图最底层的子视图，在微信标签下面；矩形 = 显示中的标签文字 + 图标 + 转圈的并集，横向各留 14pt×比例，高 = 顶部按钮高 `m.button`；宽于屏宽 60% 或高于 30pt（网页两行标题）不加；标题视图有 mask（聊天页被宿主接管）不加，已加的在提交前撤掉），以及 `MMDropableTitleView`（灰胶囊按钮清底色，玻璃进按钮最底层，跟按钮按压）。白字时玻璃强制深色。
- 新种类 `navButton`：宿主 `MMBarButton`（与宿主自己的钩子链在一起）。只在导航栏里、宿主 `leavesNavigationControlNative:` 为真（`顶部按钮与背景适配` 开、宿主没有给它玻璃、当前路由 `unsupported`）时，在按钮里最底层垫一个 `m.button` 的圆（文字按钮是胶囊），跟按钮按压；按钮自己有底图 / 底色（绿色完成）不加。路由切换（页面变化或 unsupported 变化）时 `navigationRouteChanged` 重看一遍按钮；每次提交前若宿主接管了就撤掉。
- 条目新增 `frame` 块（矩形不来自某个视图的 bounds 时），提交前重新量；提交前另外保证玻璃仍在微信内容下面（按钮可能重排子视图）。
- 设置“更多玻璃”加两个开关：标题换成玻璃胶囊、网页 / 弹出页面的顶部按钮（`pref.localTitle`、`pref.localNavButtons`，默认开）。版本 0.4.108 · TEST4 FIX108。
- FIX108 B（独立复查后）：
  - 网页 / 弹出页面的判断改为看按钮自己的导航（栈顶页面类名、是否被弹出、全屏弹出的聊天除外），不再看宿主的 `_route`：宿主在弹出页面下暂停（`_suspendedByCover`），`_route` 一直是下面那页，A 版相册、收藏、卡包的 × 实际拿不到玻璃；进出网页时 `_route` 晚于新页面按钮的布局，A 版会闪一下。
  - 本地显示链接只在有玻璃需要 tick（新的、变了、按着、刚出现）时运行，空闲 0.5 秒停；提交前只为屏幕上的玻璃唤醒（未激活、按下、还脏、外观或设置变了、发送键状态变了）。A 版每页都有标题胶囊，链接一直按屏幕刷新率跑。
  - 标题矩形按廉价键缓存（子视图身份 / 显示 / frame、文字和字体、转圈、窗口宽、比例、栏高），不用每次提交都排版文字。
  - 计算出来的矩形按像素取整（41.4pt 两个方向一样）；量视图得到的矩形不取整（A 版对 FIX107 的输入框等也取整，提交前又被改回小数，每次布局跳一下）。
  - 已有的玻璃在标题 / 按钮短暂没内容时保留；按钮隐藏不再撤玻璃（玻璃在按钮里跟着隐藏）。白字深色玻璃在外观变化时重判。短栏（横屏）按宿主同样的方式收小；圆形不超过到相邻按钮的距离；带数字的返回按钮用包住图标和数字的胶囊。取图标 / 文字不再用 UIButton 的懒加载 getter。子视图顺序每帧检查只用于两个新种类。宿主类列表里父类已在列表中的子类不再重复挂钩。
- FIX108 C（XS Max 实测 + 探针 TEST5 圈选 / 盯选中）：
  - 首页下拉后导航栏原位置留下一个空的标题胶囊：微信下拉时只把导航栏里的标题标签藏掉，标题视图还在。标题玻璃现在跟着标题文字显示（文字不显示就隐藏，透明度跟最显眼的那个标签）；网页按钮等计算出来的玻璃同理，矩形为空就隐藏（B 版会一直留着）。
  - 首页搜索框要切一次 tab 才变玻璃：重试改为 5 次、约 2.3 秒（原来 0.24 秒）；另外插件在启动后才变为可用（授权 / 渲染模式）时，提交前发现可用性变化就把所有已见宿主重看一遍。
  - 首页下拉时“+”闪一下：盯选中显示每次下拉回到原位的那一帧玻璃显示透明度为 0（下拉量回到 0 的瞬间下限变 0，微信导航栏还在 0）。下拉结束后 0.45 秒内保持下拉时的下限。
  - “+”图标显示不全：WXG 拿到的那张图（20pt）圆环贴边被切；墨迹碰到三条以上边的首页“+”改用同形的系统符号 plus.circle（20pt，细）。同一张资源换了图片对象（下拉时每帧一个）不再重新裁切着色。
  - 朋友圈赞 / 评论条（`WCOperateFloatView`，深灰九宫格底图 180×39，里面 `WCLikeButton` 赞、竖分隔线、`UIButton` 评论，白字白图标）：按首页“+”菜单的方式（WXGDecorations `momentsMenu`）换成胶囊玻璃，文字和图标改成标签色，竖分隔线隐藏。
  - 复查剩余项：邻近按钮的间距每次重算、只算显示中的按钮、文字胶囊也限宽；白字深色玻璃在墨色变化时也重判（只在玻璃风格真变了时唤醒）；标题缓存键加了文字颜色、行数和下一层子视图；唤醒要求玻璃还在锚点里且未隐藏；`mount` 只在新建 / 移动 / 变形 / 脏时唤醒显示链接。
- FIX108 D（底栏跟主题；依据探针 TEST4b 两组：XS Max，ThemeBox 关 / 开，均未装 WXG）：
  - 原生底栏：`MMTabBar` 里 4 个 `MMTabBarItemView`，各有 `MMWebImageView`（28pt 图标，原图模式，选中绿 / 未选中黑）、10pt 标题、`MMBadgeView`（UIImageView 子类：红色胶囊图 + “···”标签，或 8pt 红点）。ThemeBox 开：图标全换成彩色插画（26.67pt），选中色变 (0.65,0.75,0.49)，`MMBadgeView` 自己的图清空，里面另加一个 UIImageView（粉色圆 25pt / 小点 16pt，位置和原生不同）。
  - 图标：`WXGNativeIcons` 每次读取时把刚看到的图标（当前状态）和保存的同一 tab 同一状态的图按 8×8 外观指纹比；不同（主题开关、换了图标）就把以前保存的所有图（另一个状态、上次启动的缓存）都作废，缺的状态由看到的那个状态生成，直到真正切到那个 tab。由未选中图生成选中图时，彩色主题图保持原样（以前一律当模板染成绿色剪影），单色轮廓才染强调色；选中 tab 的未选中图没见过时用它的选中图。诊断里记“图标换过 n 次”。
  - 角标：`tabBadgeArt` 把原生（或主题的）角标按实际画出来的部分（自身图 / 底色、显示中的子图、数字）拍成图，记下它中心相对 tab 图标中心的偏移和原生图标高度；底栏不再用自己的红色标签，而是显示这张图（按 26pt 图标框缩放，同样的偏移）。离散底栏的位置规则不变，只换成这张图和它的尺寸。拍图按角标视图、子视图、图片、文字、外观缓存。
- FIX108 E（复查 C / D 后）：
  - 主题判断（D 版几乎每次切 tab 都误判、把记住的图全扔掉）：只比较当前既非选中、上次读取时也非选中的 tab 的未选中图（它们的视图已稳定），只和真正在视图里见过的（等级 ≥60）或上次启动缓存里的比，形状 64 格差超过 10 格或平均颜色差超过 0.25 才算不同，且参与比较的至少两个 tab 全部不同才算换了主题；换主题时标题颜色也一并作废。
  - 首页下拉后的保持只在首页、且不在推入 / 返回过程中，不超过小程序面板允许的值，切页时清零。
  - 首页“+”换系统图标只在：单色、方形、墨迹碰到三条以上边、四个角是空的、对角线上有圆环、环内是空的（WeChat 那张被切的圆圈加号）；按资源缓存判断结果。
  - 角标图：在 tab 项自己布局之后再拍（先 `layoutIfNeeded`）；直接按底栏 26pt 图标框的尺寸拍（不再拍完再缩放），位置取整到像素；缓存键加文字颜色、字体、底色、tint；tab 项找不到四个时往下一层找；不再为从右到左反转（和 tabBadges 一致）。
  - 朋友圈条在没找到内容层之前不再先剥掉底图（以前找不到就会一直没底、白字看不见），而是保持原样。
  - 每个玻璃每次提交前只量一次（矩形、墨色、可见度一起），相邻按钮间距每 0.25 秒算一次；没文字时不重判深浅色；标题连续两次提交没内容才隐藏（单次布局塌一下不再闪）。
- FIX108 F（复查 E 后）：标题文字被微信藏起来（下拉）时玻璃立刻隐藏，只有文字一时为空才延迟两次提交；新建玻璃时立刻按实际显示，已有的才延迟。朋友圈条同一个内容层短暂塌掉时玻璃保持（E 版可能被盖在原生深色底下），换了新的才恢复原样并在找到内容层时完整重清。相册标题的墨色每次提交都看。离散底栏的角标图也按像素取整。
- 还没做：朋友圈赞 / 评论条、底栏图标跟随主题与角标、首页下拉时“+”闪烁 / 显示不全（等开着 WXG 的 TEST5 圈选数据）。


## FIX107（测试版 A · 更多玻璃 + 顶栏动态搜索按钮；B · 圆角设置）

- B（0.4.107-test4fix107b）：用户要“可调节的连续圆角”改加号方块和表情分组选中块：`WXGConfig` 扩展项 `localTileRadius`（0–32 pt）、`localTabRadius`（0–22 pt），0 = 微信原样（方块从微信的图量出来存在 `nativeRadius`，分组选中用它图层的 8 pt），最大到边长一半；设置在 基本设置 › 更多玻璃。玻璃轮廓本来就是连续圆角。改了半径时玻璃重新 tick（`reshaped`）。另外把 A 加进 `currentNavigationBindingKey` 的“栏项子视图数和控件 hidden”撤回到 FIX106 的样子：用户报首页下拉时右上角加号闪一下、图标显示不全，下拉时微信会把顶栏按钮搬进列表表头，这两项只会多触发重新绑定（搜索按钮本来就在、只改 alpha，用不上它们）；闪烁的真正原因等探针 TEST4b 的每帧盯顶栏数据。
- 待抓（探针 TEST4b）：主题插件开 / 关时的底栏图标（`tabBar` 记录 + PNG）、角标位置；首页 / 通讯录 / 发现 / 聊天信息 / 选照片页的标题；朋友圈赞 / 评论弹出条；各处关闭按钮；首页下拉时加号的每帧数据。

- 分支 `feature/fix107-local-glass`（从 `feature/discrete-dock-clean` 开）。包版本 0.4.107-test4fix107a，`versionString` 改成 0.4.107。纯插件改动，没动着色器、`WXGUniforms`、`VER`、服务器。
- 依据：用户用探针 TEST2 / TEST3（`WeChatGlassProbe`，XS Max iOS 15.7 微信 8.0.73 和 16 Pro Max iOS 26.6 微信 8.0.78）抓的视图树。用户要求：“该做成按钮的做成按钮，该长条的做成长条胶囊”。
- **新文件 `Sources/WXGLocalGlass.m`**（接口在 `WXGIntegration.h`）：钩子挂在宿主类的 `layoutSubviews` / `didMoveToWindow`（`WXGLocalGlass.hostClassNames`，`WXGHost.m` 安装时用 `WXGHookVoid`）。每个元素保留微信自己的视图、动作和布局，只用 `WXGStateBag` 去掉它的底色（可还原，每次提交前 `reapply`），在原位放一块 `WXGSurface`（materialOnly，“其余玻璃”的参数）作为被涂色视图的最底层子视图（按钮则放在背景图视图正上方），所以跟着它移动、隐藏、淡入淡出：
  - 搜索框 → 胶囊：`WCSearchBar`（首页、通讯录、设置：栈里那块白色纯 UIView，r=6）、`WCWebSearchBar`（搜索页：灰色纯 UIView）、`FavSearchBar`（收藏：自己就是底色）、Swift 的 `WeChat.WCSearchTextField`（表情搜索：旁边那块白色纯 UIView；类找不到时由 `NewEmoticonSearchViewController` 的 `viewDidLayoutSubviews` 兜底）、系统 `UISearchBar`（新的朋友的 `MMUISearchBar`：输入框里名字带 Background 的背景视图隐藏），被 `WCSearchBar` 盖住的系统输入框不处理。搜一搜结果页整页是网页（`WCWebSearchViewControllerNewH5`，原生搜索栏隐藏），改不了。
  - 加号面板 8 个 `AttachmentButton` → 圆角方块：背景图视图 `clearImagePaint`，圆角从微信自己的方块图沿对角线量出来（`WXGLocalImageCorner`，量不到用边长 0.22），`observeTouchesInView:` 让按下时玻璃按压（拉伸跟随“首页左上角和三段输入两侧也拉伸”那个设置）。
  - 表情面板 发送 / 删除（按动作 `onTapSendButton` / `onTapDeleteButton` 找）→ 胶囊：去掉 4.8 pt 的裁剪（`allowOverflow`）和 1×1 背景图；发送键按当前状态的背景图取色，是彩色（绿）时玻璃用这个颜色 0.82 着色（`veilOverride`），灰白时不着色。
  - 表情分组条 `EmoticonBoardDynamicTabBarCollectionCell` 里每格的白色选中方块（未选中的是 hidden）→ 同圆角的玻璃，每格一块，跟着微信的 hidden 显示。
  - 转发 / 分享弹层 `MMScrollActionSheetContainerView`（图片查看器和公众号文章“…”是同一个原生类，文章版只多一个 `MMWebMenuHeaderView`）→ 毛玻璃视图 alpha 0，整块背景一块轻量玻璃（`lightweight`），圆角 26，着色浅色白 0.58 / 深色 (0.11,0.11,0.12) 0.58，保证文字可读。毛玻璃 contentView 里有内容就不处理。
  - 运行：只在同步渲染模式（`WXGEffectiveRenderMode()>=2`）。自己的 `CADisplayLink`（有可见的就跑，1.5 s 没有就停），每块玻璃只在新出现、换位置、换配置 / 外观、着色变化、按下前后 0.9 s、首帧没出来（最多 3 s）时 tick；不可见的 `active=NO`。不依赖宿主的显示刷新，所以宿主暂停的页面（文章页上的弹层等）也能用。
  - 每次提交前（`kCFRunLoopBeforeWaiting` 观察者，在布局之后）：重新去底色、按 `measure` 视图重新量玻璃的位置大小（宿主的 `layoutSubviews` 先于子视图布局，输入框自己布局后才定尺寸，比如新的朋友点进去出现“取消”时输入框变窄），显示刷新停着而有玻璃回到屏幕上（面板滑进来、表头滚回来，没有布局）就叫醒它（每 0.25 s 查一次）。找不到底色 / 还没尺寸的宿主 0.08 s 后再试，最多 3 次。
  - 不想要时什么都不做：插件关闭、未授权、不是同步模式或这一类开关关着，钩子里直接返回，不扫视图、不建玻璃（FIX105 的零痕迹）；见过的宿主记在弱引用表里，开关重新打开时 `applyConfiguration` 重新挂上。内存警告时释放这些玻璃的临时缓冲。
  - 已知取舍：弹层玻璃圆角 26，比微信自己的 12 圆，角上那一小块露出变暗的页面（就是更圆的角）。
  - 开关：`WXGPreferences` 新增 `localSearch` `localPanel` `localEmoji` `localSheet`（默认开），设置在 基本设置 › 更多玻璃。插件关闭 / 未授权时宿主调 `[WXGLocalGlass.shared restore]`。诊断 `runtime.localGlass`（每类挂了几块、屏幕上的、没挂上的原因 `skipped`、各类是否找到）。
- **顶栏动态搜索按钮**（`WXGHost.m`）：微信 8.0.78 通讯录右上角是一个自定义项 `ContactsRightTopMenuBtn`（76.7 宽）里并排两个 `MMBarButton`：添加朋友（右，`onAddContactButtonTapped`）和搜索（左，`onSearchButtonTapped`）；首页灰度是 `NewMainFrameRightTopMenuBtn`（搜索 + “+”）。搜索按钮一直在，只是列表的搜索栏在屏幕上时 alpha 0、滑走后淡入。原来 alpha 0 的不参与绑定，淡入后没有玻璃（丢目标），有了玻璃再淡出又空着；两个按钮同属一个栏项时排序不定，可能左右颠倒。现在：
  - `navigationControls`：`onSearchButtonTapped` 的控件 alpha 0 也绑定（玻璃按 `followNativePresentation` 跟微信的 alpha）；同一栏项的两个控件按实际 x 排序；首页仍然在底栏搜索可用时隐藏它（`_homeSearchHidden` 记着是我们藏的，底栏搜索关掉后还原）。
  - 角色 `navigationSearch`，`updateHomePullFloor` 不给它 alpha 下限（首页下拉时微信的搜索按钮是 0）。
  - `currentNavigationBindingKey` 加上栏项子视图数和其中控件的 hidden，按钮后加进来时会重新绑定。
- 待用户确认：各元素真机效果（尤其弹层的着色浓度、方块圆角、发送键绿色、搜索胶囊在深色模式）；通讯录 / 首页搜索按钮淡入淡出时玻璃是否跟着。


## FIX106（测试版 A–J · 离散底栏 + 顶栏修复）

- 分支：`feature/discrete-dock`（含试过又撤回的 E/F/G 及其 revert）和 `feature/discrete-dock-clean`（只有保留的 A/B/C/D/H/I/J，两者代码树完全相同）。`master` = 基线 FIX105（4a8e3f8）。干净补丁 `git format-patch master..feature/discrete-dock-clean`。包版本 0.4.106-test4fix106j；设置页里的 `versionString` 和诊断 `version` 还写着 0.4.105（没改，只差显示）。
- 编译（Linux，不用完整 Theos）：先跑一次 `plugin/tools/setup_linux_toolchain.sh`（clang-18 + ld64.lld、ldid procursus、theos/sdks 稀疏拉 iOS 16.5 SDK 到 `/home/claude/toolchain`），再 `cd plugin && sh tools/build_deb_linux.sh "$PWD" dist/out.deb`（解析 Makefile，`-Werror`，出 deb + dylib）。测试：`Tests/*.c` 57 个，x86 上用 `-O2 -ffp-contract=off`（不加的话 LensEndRimTests / RestingSelectionTests 在 FMA 下会 abort，基线就这样）；`DockScriptTests.c` 带 `-Werror` 有个基线就有的 unused 变量警告。`tools/check_msl.py`、`tools/check_unused_statics.py` 通过。纯插件改动，没动着色器、`WXGUniforms`、`VER`、服务器。

### 混淆包启动即闪退（`-irobf-icall`，已从默认 flag 去掉）

- 用户转来一份崩溃（iPhone 15 Pro · iOS 17.0 · 微信 8.0.79，侧载 IPA，Frameworks 里注入了 9 个插件）：启动 0.8 s 在 dyld 里断言 `large offset not support`（`PrebuiltLoader::BindTargetRef`，`makeLaunchSet`），插件代码还没运行。
- 用户给的 `..._0.4.106-test4fix106j_iphoneos-arm64_obf_3.deb` 的 UUID `4C4C4419-…-A1046A25ACF2` 与崩溃里的 WeChatLiquidGlass.dylib 一致；它有 331 个带 64 位随机附加偏移的绑定（全在 `__data`，即 `-irobf-icall` 的加密调用表：`CGContextRelease + 0xd559b8e69681b44d` 等），dyld 启动缓存存不下。普通包 0 个。原因和修法写在 `obfuscation/README_中文.md`。
- 改动：`build.yml` 的默认 `obf_flags` 去掉 `-irobf-icall`；两个作业出包后跑新的 `plugin/tools/check_dyld_binds.sh`（附加偏移超过 ±2^32 就失败，普通作业多装 `llvm-18` 拿 llvm-objdump，混淆作业没有就 `apt-get install llvm`，还没有则警告）。**之前用默认 flag 出的 `_obf` 包都带这个问题**，把它打进 IPA 的用户要换新包。

### A–H 离散底栏（`WXGDockDiscrete.h` 纯 C + `Tests/DockDiscreteTests.c`，`WXGDemoBar.m`）

- 用户要的样子（参考 React DiscreteTabs）：选中项是宽胶囊（左图标，右侧上中文下英文标题），其余是只有图标的玻璃小球（可选连成一个胶囊：小球占位 + 间距相连，不漏标题）；切换用阻尼弹簧（参考 damping 20 / stiffness 230 / mass 1.2）；可选给选中项加原来的选中胶囊。
- A：每个胶囊一块 dock 玻璃（`WXGGlassView`，dockSurface），图标标题是 UIKit 视图叠在上面；所有 tab 的宽度跟同一个半隐式弹簧（`WXGSpring`），展开量之和恒为 1，整行不漂移，过冲时新 tab 鼓、旧 tab 挤；原来的整条玻璃休眠，搜索变形时交叉淡回整条；按下即切（按下时）、提交、角标照旧；`lensAtRest` 等弹簧停。`WXGGlassView.deferShapeField`（轮廓在动时用胶囊距离场）。宿主：`renderGlasses` / `allGlasses` / `propagateGlassSources` 接入采样、预热、内存释放。
- B：未读角标放在每个胶囊右上 45° 处（不再压宽位的图标标题）；图标 / 标题加大到 30 / 15 / 11 pt（各一个设置）；相连小球和展开同时开始衔接（约 0.16 s 内连成一体，恒速 0.35×响应），不是等展开完再连。
- C：相连时一串的图标向这串的中间均匀收拢（默认 0.22 格，设置），随弹簧滑动，角标跟着。
- D：冷启动后快速切 tab（常是“我”）的闪退：底栏图标图集在后台队列读微信 tab 图标的 `-[UIImage imageAsset]`，主线程同时为离散底栏读同一批图，那个调用会创建并注册 asset、不是线程安全（`-[UIImageAsset _unsafe_registerImage:withConfiguration:]` EXC_BAD_ACCESS）。现在图标只在主线程解析（`WXGDockTabArtwork`），队列只画。
- E（撤回）：软化各块边缘带 / 边框——用户看不出变化。“圆角鼓鼓的”核实过：轮廓就是连续圆角，观感来自边缘带 + iOS 27 边框参数。
- F（撤回）：缩小宽位图标——用户要的是左右布局占位，不是大小。G（撤回）：图标贴左、标题右侧居中——用户要 A 的居中布局。
- H：A 的居中块整体左移一个偏移（默认 10 pt，`dockDiscreteContentShift` 0–30，“宽位内容左移”；不超过左端圆角中心处的图标位置；小球不移），`WXGDiscreteContentShifted`。
- 设置（底栏 › 离散样式，`WXGConfig.m` 的 `WXGExtraSpecs`）：`dockDiscrete`(开) `dockDiscreteConnected` `dockDiscreteGather`(.22) `dockDiscretePill` `dockDiscreteGap`(8) `dockDiscreteWide`(2 格) `dockDiscreteBall`(.9) `dockDiscreteIconSize`(30) `dockDiscreteTitleSize`(15) `dockDiscreteSubtitleSize`(11) `dockDiscreteContentShift`(10) `dockDiscreteDamping`(.6) `dockDiscreteResponse`(.45 s) `dockDiscreteLight`。

### I / J 顶栏被吃（`WXGSettings.m`、`WXGHost.m`、`WXGEdgeFade.m`）

- 用户：原生顶部被吃掉一部分——聊天设置（单聊 / 群聊的聊天信息）每次都是，微信设置和从它进的插件页偶尔（没有标题和返回）。截图逐像素对比（关插件的同页）：设置是导航栏被隐藏（列表上移“导航栏底 − 安全区顶”= 38 pt）；聊天信息是导航栏和玻璃都在，但列表内容整整压进顶栏 100 pt。
- I（设置）：插件设置页出现时隐藏微信导航栏、离开时还回去（`WXGSettingsNavigationState`）。交互式返回（边缘滑、iOS 26 全屏滑）可以中途取消，UIKit 把导航栏恢复成隐藏、页面再出现一次；原来在 will-disappear 就丢掉“微信原来的状态”，再出现时把隐藏记成微信的，真正离开时交给微信一个隐藏的导航栏。现在状态保留到 pop 真正完成（coordinator completion、未取消）。兜底：`WXGSettingsReleaseStaleNavigation`（宿主每次 refresh：导航里已没有设置页还被拿着 → 还回导航栏和返回手势）；`WXGSettingsShowBarForPage`（设置 / 聊天信息出现时导航栏是隐藏的、栈里没有设置页、上面没有弹出 → 显示）。用户反馈 I 之后设置没再出现（本来就是偶发，继续观察）。
- I 还加了 `WXGCheckPageTop`（`WXGHost.m`）：设置 / 聊天信息被 push 后约 1 秒内查 4 次，每次写一行日志“顶部 #n：页面 列表 y/高 | 内边距 系统后/自身/行为 | 偏移 | 内容顶 | 导航栏 | 列表是第几个子视图（底板）”；列表因偏移压进顶栏（内边距本身对）时回到顶部。计数 `runtime.pageTopRepairs`。
- J（聊天信息，原因由 I 的日志确定）：聊天信息的 `WCTableView` 是 `contentInsetAdjustmentBehavior = never`、自身内边距 0、在页面视图里排第 2——第 1 个是渐隐的背景底板（`WXGEdgePlateView`，FIX66 起插在列表下面防黑边）。微信只给页面的**第一个子视图**留顶部内边距（同 UIKit 旧的自动内边距规则）；设置页自己设 88，不受影响。现在（非聊天页、列表本来排第一时）底板放在列表**后面**、`zPosition` 比列表低 1（`place:behind:`），列表仍是第一个、画面不变；底板仍是视图，玻璃采样照旧跳过它、照旧拆分页面（页面子图层全是视图，不能直接塞 CALayer，否则采样走整页慢路径）。聊天页不变。兜底：从未调整、内边距 0、从顶栏下面开始的列表，push 后补上导航栏需要的内边距（日志“补上顶部内边距”）。诊断 `edgeFade.pages[].backgroundPlate.behindList`、`listIndex`。
- 待用户确认：J 装机后聊天信息是否正常；若不正常，日志里“顶部 #0”那行能看出列表排第几、内边距是谁给的。


## FIX105（测试版 ABC · 未授权整块撤出图层）

- 用户：没授权就彻底不碰微信；注入了但没授权成功，微信任何地方都不受插件影响、也别“底栏跳成玻璃又闪回”。
- 结论先说清楚：真正没授权过的账号本来就不显示玻璃（效果都 gate 在 `WXGPluginEnabled()`）；用户看到的“闪玻璃又回原生”基本是**被踢但本地还有有效票据**的情况——冷启动凭缓存票据显示玻璃，后台联网收到 403 再撤。这属于离线优先授权的固有现象，没在这版消除。
- 这版做的是“零痕迹”：`WXGHost.m` refresh 的 `!available` 分支里，`!licensed` 时调 `detachOverlays`——把 `_overlay`、`_navigationOverlay` 从视图树 `removeFromSuperview`、`_launcher` 隐藏。`ensureOverlay` 在重新授权后把它们装回来（幂等）。
- `ensureOverlay` 里悬浮入口的显隐改成 `WXGSettingsEntryReady || 未授权` 才隐藏（原来只看 `WXGSettingsEntryReady`）：设置入口钩子失败时，未授权账号也不再露出悬浮按钮。
- `WXGInsertSettingsEntry` 开头加 `WXGLicenseCurrentState(NO)!=WXGLicenseAuthorized` 时直接 return：未授权时微信「设置」里不插入插件入口行。它跟着 `reloadTableData` 跑，授权后下次微信重建该表格时才出现（不主动 reload 微信的设置页）。
- 风险/没做：每次刷新对未授权账号会 attach（ensureOverlay）又 detach，同一 runloop 无可见闪动，仅极小浪费；被踢账号的冷启动闪一下未处理（需求之外，且要联网优先才能免）。版本号 0.4.105。
- 验证：56 个 C 测试通过；arm64/arm64e、iOS 14、`-Werror` 0 诊断；deb 构建通过；dylib 无着色器文本。

## FIX104（测试版 ABC · 服务器决定复查间隔、冷启动不闪）

- 用户：从 FIX103 继续。①去掉 12 h 复查间隔，改由服务器在回答里下发；“重新检测”对已授权账号也要强制联网（`WXGUnlockStateFor` 的 Ready 分支没看 force）。目的是从名单删掉账号后很快生效。②冷启动先显示原生界面、过一下才跳成玻璃：本地票据要等后台读完再绕一圈主线程，着色器也等这之后才编译，第一次刷新时授权还是“正在验证”。
- 服务器（`xyydys/wxg-glass`，**改动还没推送**，见 `ServerPatch_FIX104/worker.js.diff`）：
  - `RECHECK_AFTER`（300）、`DENIED_RECHECK_AFTER`（300）；200 回答加 `recheckAfter`，403 加 `recheckAfter`。
  - 不进签名（签名内容不变，FIX103 插件照常验签）。node 跑过：200/403 都带字段，签名 OpenSSL 验证通过。
- `WXGUnlockPolicy.h`：
  - 去掉 `WXG_UNLOCK_REFRESH_AFTER`；`WXG_UNLOCK_RECHECK_DEFAULT` 600、`_MIN` 60、`_MAX` 7 天；
  - `WXGUnlockRecheckInterval(sent)`（无 / ≤0 / NaN → 默认，否则夹到 [60 s, 7 d]）、`WXGUnlockDeniedWait(sent)`（无 → 600，否则 [60 s, 1 d]）；
  - `WXGUnlockRefreshDue(now,expiresAt,fetchedAt,recheck)`：不可用、过了间隔、时钟比取票早了一个间隔以上、剩 < 3 天 → 到期。
- `WXGUnlock.m`：
  - 票据 `recheckAfter`（`WXGSecondsValue`：数字或数字字符串）；写进缓存 JSON；FIX103 的缓存没有 → 默认。
  - Ready 分支：`force || (!waiting && !waitOutdated && due)` 才请求（拿到票据后 60 s 冷却、退避照旧，force 无视）。
  - 403 的等待用 `deniedWait`。
  - `WXGChanged(host)`：拒绝、或者账号可用性和宿主上次看到的（`WXGEvalState`，在时间偏差更新之前取）不同、或者和回答前不同，才 `schedule` 宿主；通知总是发（设置页更新到期时间）。续期日志一小时最多一条。
  - 请求在 `WXGUnlockQueue` 上组装和发送（主线程只记 in-flight）。
  - 着色器：`WXGShaderText/Origin/Waiters` 改由 `os_unfair_lock` 保护，`WXGOfferShader` / `WXGUnlockWhenShaderReady` 任意线程可调（不再跳主线程）；已就绪时续期不再解码。
  - 冷启动：`WXGUnlockStart` 从宿主构造函数的 `install` 开头调用（原来在下一轮主队列里）。`WXGStartCacheLoad` 在 `WXGUnlockQueue` 上跑一个 `ENFORCE_QOS` USER_INITIATED 的块：算设备码（后台 identifierForVendor）→ 读缓存 → **在后台直接把最新票据的着色器交给 Metal** → 结果写进静态量 → 离开 `WXGCacheGroup` → 异步回主线程 `WXGAdoptCache(0)`（接手了就 `WXGChanged(YES)`）。
  - `WXGUnlockStateFor` 开头先 `WXGAdoptCache`：第一次最多等 0.3 s（`WXG_UNLOCK_LAUNCH_WAIT`），之后不等。没有设备码（重启后首次解锁前）时，等到主线程算出来再读一次，也等一次。
  - 诊断：`cacheReadAtMS`、`cacheReadMS`、`cacheWaitMS`、`ticket.recheckAfterSent`、`ticket.recheckEveryS`；`shaderReady/From` 加锁读。
  - 新导出 `WXGUnlockAsking(code)`。
- `WXGSettings.m`：首页“通用”第 4 张卡 `license`（“授权”，checkmark.seal），点按 → `recheckLicense`；副标题“有效至 M月d日 · 点按检测” / “正在联网检测…”。`_recheckPending`：回答到达（通知）时弹结果（授权有效 / 联网检测没有成功 / 插件需要更新）；页面不在屏幕上就记下来，`viewDidAppear` 再弹。状态变了照旧重建（被踢 → 未授权卡片）。
- `WXGHost.m`：`WXGUnlockStart()` 移到 `install` 开头；版本号 0.4.104。`WXGGlassView.m` 只改注释。
- 验证：56 个 C 测试；23 个 .m 用 iOS 16.5 SDK、arm64/arm64e、`-Werror` 通过；Linux 出 deb；dylib 无着色器文本。
- 独立审查（一轮）：修了“只纠正时间偏差的回答没通知宿主”“不在首页时结果提示丢失”“等待超时时 `cacheWaitMS` 没记”“版本不符的提示文字”，以及续期时重复解码、日志刷屏、设备码迟到时的一次跳变、连点。
- 没做 / 风险：
  - 服务器改动要推送才生效（之前插件用默认 10 分钟）；改小间隔后每台手机要等当前这轮间隔到了才拿到新值。
  - 后台线程调用 `identifierForVendor`（文档没写线程安全，业界常见）；构造函数里就开始读缓存，需要真机确认。
  - 关闭设置页的按钮不清 `_settings`（FIX103 之前就这样，没动）。
  - 每次复查都会重新下发 43 KB 着色器；如果嫌流量，可以让插件带上已有摘要、服务器摘要相同就不发着色器（签名本来就不含着色器字节）。


## FIX103（测试版 ABC · 联网解锁）

- 用户：服务器端已完成并测过（授权账号拿到着色器且签名对得上；不在名单的 403）。这一版做插件端：联网解锁、校验、本地缓存。
- 服务器：私有仓库 `xyydys/wxg-glass`（`worker.js` + `wrangler.jsonc`），推送 main 自动部署到 Cloudflare Worker `xyylwc`。
  - 地址 `https://xyylwc.kvgdth56kf.workers.dev`；`POST /v1/unlock`，body `{account, device, ts}`（插件另带 `ver:"1"`，服务器现在忽略）。
    - account：授权码，64 位小写十六进制；
    - device：≤128 字符；
    - ts：Unix 秒，和服务器相差 > 300 s 返回 400 `{"error":"stale"}`。
  - 200：`{ver, expiresAt, shader(base64), digest(sha256 hex), sig(base64 DER)}`。签名内容 `account|device|ver|expiresAt|digest`，有效期 7 天。
  - 403：`{"error":"not authorized"}`。GET 任意路径是自检（`pub` 是公钥）。
  - 私钥在 Worker 的 Secret `SIGN_PRIV`。
  - `ALLOWLIST` 是授权码列表；着色器在 `worker.js` 的 `SHADER`，和 FIX102 的 `WXGMetalSource` 逐字节相同（sha256 `93b80522…a88b6`，43429 字节）。
- 插件：
  - `WXGShaderSource.h` 不再被编进 dylib，只留给 `check_msl.py` 和模拟器用；
  - `WXGGlassView.m` 的 `WXGPrepareMetal` 改为在 `WXGUnlockWhenShaderReady` 回调里编译（全局队列）；在那之前所有玻璃视图都在等，和等编译一样。
- `WXGUnlock.m`（新）：
  - 状态只在主线程改；网络回答和磁盘在串行队列 `wxg.unlock` 上做，结果交回主线程（`WXGApplyAnswer`）。
  - 设备码：`SHA-256("WXGLiquidGlass.device.v1:" + identifierForVendor)`。
  - 校验（`WXGTicketProblem`，后台）：
    - 着色器 SHA-256 等于 digest；
    - `WXGUnlockSignedMessage`（`WXGUnlockPolicy.h`，纯 C）拼出签名内容；
    - `SecKeyCreateWithData`（原始 65 字节公钥）+ `SecKeyVerifySignature(kSecKeyAlgorithmECDSASignatureMessageX962SHA256)`；
    - `ver` 必须等于 `WXG_SHADER_VERSION`（"1"），否则是 Outdated。
  - 缓存：
    - 位置：`Library/Application Support/WeChatLiquidGlass/Unlock/<授权码>.wxgu`；
    - 格式：`WXGU1` + IV + AES-256-CBC(JSON)，密钥 `HMAC-SHA256(内置种子, "cache.v1|账号|设备")`；
    - 启动时 `WXGUnlockStart`（在宿主 start 之前）读入全部有效票据，用最新那张的着色器立刻编译；
    - 读不出 / 解不开的文件留着，解开后无效或过期的删掉。
  - 什么时候请求（`WXGUnlockPolicy.h` 有测试）：
    - 没有可用票据就请求；
    - 有票据时，拿到后 12 h 或剩 < 3 天续期；
    - 失败退避 5/15/60/300/900 s，有可用票据时至少 300 s；
    - 403 后 10 min、版本不符后 1 h 才再问；
    - 刚拿到票据 60 s 内不再问；
    - 退避和错误只属于最后一次回答的账号（`WXGAttemptAccount`），换账号不受影响；
    - stale：用响应的 `Date` 校正时间偏差，立即重试一次；
    - 只有正文是 `not authorized` 的 403 才算拒绝（删票据、删缓存、插件当场关闭），其他 403 当失败；
    - 时间回拨超过取票时间 1 天，票据不算数。
  - 设置页“重新检测”→ `WXGLicenseRecheckServer()`：无视退避立即请求；`buildContent` 里的 `WXGLicenseCurrentState(YES)` 不强制请求，避免“通知 → 重建 → 请求”循环。
  - 回答到达后发 `WXGLicenseChangedNotification` 并 `schedule` 宿主，设置首页自动重建。
- `WXGLicense.m`：本地名单 `WXG_LICENSED_ACCOUNT_HASHES` 删除。
  - 状态 = 账号（照旧，60 s / 安静时才读）+ `WXGUnlockStateFor(授权码)`（每秒最多算一次）。
  - 新状态 `WXGLicenseChecking` / `Unreachable` / `Outdated`（追加在枚举末尾）。
  - 诊断 `license.code`、`license.unlock`。
- `WXGBuildProfile.h`：`WXG_UNLOCK_ENDPOINTS`（按顺序试，失败换下一个）、`WXG_UNLOCK_PUBLIC_KEY`。Makefile 加 `Sources/WXGUnlock.m` 和 `Security`。
- 工具：
  - `tools/export_worker_shader.py <worker.js>`：从 `WXGShaderSource.h` 重写 `worker.js` 的 `SHADER`，对现有 `worker.js` 输出逐字节相同；
  - `tools/license_hash.py`：输出 `ALLOWLIST` 行；
  - `tools/build_deb_linux.sh`：Linux 出 deb，文件头里有工具链准备命令。
- 验证：
  - 56 个 C 测试；
  - 23 个 .m 用 iOS 16.5 SDK `-Werror` 检查通过；
  - 在 node 里运行 `worker.js` 原 handler（临时密钥）：200 / 403 / stale 都对，返回的票据用 OpenSSL 按插件同样步骤验证通过；
  - dylib 里没有着色器文本；
  - 独立审查一轮，修了 6 处：版本不符时请求不停、任何 403 都吊销、退避跨账号、过期提示文字、stale 退避、诊断里的版本号。又加固 3 处：拿到票据后 60 s 冷却、读不出的缓存不删、`Date` 头大小写。
- 没做 / 风险：
  - `workers.dev` 在国内可能连不上，建议绑自定义域名放到 `WXG_UNLOCK_ENDPOINTS` 最前；
  - 服务器不认请求里的 `ver`，换不兼容的着色器会让旧插件全部失效；
  - 没授权或还在验证时，设置页卡片也没有玻璃（没有着色器）；
  - 断网的被踢账号最多还能用 7 天。

## FIX102（测试版 ABC）

- 用户（附 FIX101 诊断）：“更慢了”。
- FIX101 诊断：
  - 7 次点按都等了空闲（`calmWaitMS` 65–210）；
  - `slowFrames` 显示长帧几乎只在按下后 11–29 ms 那一帧（切换帧，100–240 ms，已有暂停处理），之后 26–83 ms；
  - 第一次打开「通讯录」：refresh 67 ms，其中 `gateMS` 56.7。
- `gateMS` 来自 `WXGLicenseCurrentState(NO)`：每 3 s 调一次 `WXGReadAccount`（CContactMgr getSelfContact 等），50–95 ms。
  - 改为已知账号 60 s 一次，并且要宿主的 `WXGHostQuietForLicense`（底栏不跟手、透镜静止、切换后 > 2 s、无原生转场）同意，否则推迟。未知账号仍 0.5 s 一次；设置页 `recheck` 照旧。
  - 证据：`license` 里 `accountReads` / `accountReadLastMS` / `accountReadMaxMS` / `accountReadsPutOff`。
- 等空闲：新键 `dockTapCalmWaitOn`，默认 0（旧键 `dockTapWaitForCalm` 弃用）。
- 按下时请求改回 `dispatch_async`（去掉 0.03 s）。
- 追上：`WXGScriptScaleTime`（围绕 pivot 的时间仿射）、`WXGScriptCatchUp`（剩余部分缩短 pause × 0.6，最多 25%）。
  - 在 `tabSwitchForwardedFrom:` 的后移之后、`animationNow` 里丢失 > 10 ms 时调用；开关 `dockTapCatchUp`，默认 1。
  - `taps.catchUp` 是累计的 (1 − f)。
- 诊断：`WXGProfileHooks`。
  - `WXGHookVoid` 的 after 块和 `WXGPerfTimePluginWork`（气泡观察者、渐隐、平稳采样、装饰观察者）计时，扣掉其中嵌套的 tick / refresh / switch / hooks（`WXGProfileOursTotal`）；
  - 慢帧记录 `hooksMS`，`otherMS` 再减去它。
- 测试：`DockScriptTests` 加时间缩放逐点相等、追上的量与上限、微小停顿不变、pivot 处不跳。

## FIX101（测试版 ABC）

- 用户（附 FIX100 诊断）：底栏还是不稳定，明明有流畅的时候，但冷启动很卡、聊天返回后再切换也卡；一直维持最高标准就不难受。
- FIX100 诊断：12 次点按，计划约 470 ms，实际 539–1198 ms。
  - 切换本身已后移，卡的是之后 0.1–0.7 s 的慢帧，`afterSwitch` 的 `otherMS` 100–510。
  - 聊天返回后切到「微信」：`refresh` 99.8 ms，其中 `treeScanMS` 93.7（这一步含多段，原因未知，这次拆开计时）。
- 等空闲（`dockTapWaitForCalm`，默认 1）：
  - `tabSwitchForwardedFrom:` 之后在 tick 里每帧把脚本后移时钟走过的量（透镜原地不动，速度置 0），直到 `WXGScriptCalmWait`：连续 3 帧 ≤ max(1.6 × 帧长, 22 ms)；0.6 s 后只要求这一帧准时；1.2 s 封顶。
  - 结束时把时钟落后量也后移、时钟回到真实时间。
- 诊断：
  - `WXGProfileCommit`（1999999 / 2000001 两个观察者夹住 CA 的 commit），慢帧记录里 `commitMS`，`otherMS` 再减去它；
  - `taps` 加 `slowFrames`（[距按下 ms, 帧长 ms]，最多 10）和 `calmWaitMS`；
  - refresh 的 `routeSteps` 加 `gateMS`、`appearanceMS`、`routeTokenMS`，`treeScanMS` 只剩 WXGViews。
- 没做：透镜脱离主线程绘制（后台线程 Metal + CA 关键帧几何）。这是唯一能完全不受微信主线程影响的办法，但要大改 `WXGGlassView` 的布局路径，风险高。

## FIX100（测试版 ABC）

- 用户（附 FIX99 诊断）：
  - 不理解为什么原生微信是秒切，两者不应该这么冲突；
  - 头像每次启动进聊天都重新读取，明明上次读好了。
- FIX99 诊断：
  - 首次打开时微信切换：我 57 ms；发现 194 ms，`otherMS` 307；通讯录 15 ms，`refresh` 49 ms（`treeScanMS` 36），`otherMS` 111。
  - `taps`：点按 #3 实际 814 ms（计划 449），暂停 353 ms，因为落在上一次切换的 0.8 s 窗口里。
- 按下时（新键 `dockTapSwitchWhen` 0 按下时 / 1 松手时 / 2 快到位时 / 3 落下后，默认 0；旧 `dockTapSwitchMoment` ≠ 1 时 +1 搬过来）：
  - `WXGDemoBar`：跳到别的标签的按下（steps > 0.3）→ 0.03 s 后（手指还按着、`earlyIndex` 未变）调用 `tabSwitchRequest(index)`（返回 BOOL）→ 宿主 `dockRequestedTabAtTouchDown:`。
    - 宿主有挂起的切换时返回 NO，不吞前一个；否则 `forwardTabIndex`，返回是否已在该标签。`earlySent` 用这个返回值。
  - 松手：`switchedAtTouchDown`（`earlySent && earlyIndex==selectedIndex`，只在发 ValueChanged 时为真）→ `dockChanged:` 直接返回，不再转发（再转发等于点当前标签：回顶部 / 跳未读）。
    - 滑出底栏或系统取消：保留按下的标签（`keptEarly`、cancelTracking）。
  - `config.dockTapSwitchMoment` = max(0, when − 1)（松手后的时机）；`dockTapSwitchAtTouchDown`。
- 卡顿后接着走：
  - 宿主 `forwardTabIndex` 结束时（含 refresh）调用 `[_dockView tabSwitchForwardedFrom:forwardStart]`；
  - 运行中的脚本整体后移 `real − clock − since`（`WXGScriptShift`），时钟回到真实时间。卡多久都不跳。
  - 之后 0.8 s 的忙碌帧每步最多 1/30 s（`WXGScriptAfterSwitchCap`）；紧接的第一步 1/60。
- `noteVisitedTab:` 在 `dockChanged:` 和按下请求的开头记下当前标签（review：按下时的松手提前返回，启动时的标签就没记上）。
- 头像磁盘缓存：
  - `Caches/WeChatLiquidGlass/Avatars/<FNV-1a(userName)>.plist`（二进制 plist：user、url、image、saved）；
  - `keptAvatarFor:contact:` 先查内存再查磁盘，地址变了每次启动后台重下一次（`refresh:YES`，低优先级，下好后替换当前页 `state.image`，`state.user` 校验）；
  - `avatarImageForTitle:` 里它排在头像服务前面；写盘在后台队列，超过 300 个删最早的 60 个；诊断 `avatarDiskHits`。
- review 指出且已修：长卡顿 > 0.5 s 时跳（改成后移脚本）；按下记录靠 10 s 计时、取消后吞掉之后的点按（改成松手时由底栏标记）；宿主拒绝也算已发；启动标签没记访问（同上）。
- 没做：每次第一次进页面时插件自己的树扫描（通讯录 36 ms）还可以再省。

## FIX99（测试版 ABC）

- 用户：中间过程（变成透明透镜、再变回有色）反而比滑动占的时间多，不自然，要加快；冷启动后前几下为什么那么迟钝。
- 时序（`WXGDockScript.h`）：
  - `WXGScriptGlide` / `WXGScriptTravel` 加 `share`：升起和颜色共用一段（默认 0.40，原来升起 0.55、颜色 0.65）；
  - `WXGScriptDropLead` 0.40 → 0.70（到位前 70% 开始落）。
  - 默认：滑动 1.4 倍、落下 0.16 s。一个标签 0.35 s 到位、0.40 s 落下（到位后 0.048 s），颜色 0.14 s 褪完、0.24 s 开始回来。
- 配置：新键 `dockTapMoveScale`（1.4）、`dockTapDropTime`（0.16）、`dockTapLensShare`（0.40，0.15–0.9）。旧键 `dockTapDurationScale` / `dockTapDropDuration` 去掉了；载入时如果旧值不是 FIX98 默认值（1.5 / 0.26），就搬到新键。访问器名字没变。
- 冷启动：
  - FIX93/94 诊断里，第一次打开标签时 `afterSwitch` 主线程忙 0.3–1.3 s（`otherMS` 是微信自己的工作）。
  - 宿主 `visitedTabs`：启动后没显示过的标签按时机 2（等落下）挂起（`_pendingMoment`、`holdsTabSwitchAtMoment:`）。`forwardTabIndex` 标记已访问；`tabTrace.firstVisit`；前 4 次首次打开写日志（含微信切换 ms）。
  - 动画时钟：`WXGScriptClockAdvance(clock,lastReal,real,switchAt)`。只在宿主转发切换前后（`noteTabSwitchForwarding`，−0.02…+0.8 s）每步最多 1/60 s，最多落后 0.5 s；其它时候是真实时间（FIX98 对所有慢帧都压到 1/24 s，冷启动时慢动作）。
  - 图标重扫（0.45 / 0.9 s）在脚本运行时每 0.1 s 推迟，最多 2 s。
  - 诊断 `taps`：前 12 次（since、kind、to、landed、plannedMS、actualMS、longestFrameMS、switchAtMS、pausedMS），前 6 次写日志。`WXGSecondsSinceLoad()`。
- 没做：预先加载微信的标签页（可能有副作用；要看真机的 `taps` 和首次打开日志再决定）。透镜折射网格冷缓存：每个新尺寸 / 按压档位第一次要建，这里量约 0.4 ms 一个，真机估计 1 ms 左右，不是主要原因。

## FIX98（测试版 ABC）

- 用户：点按切换太快；选中胶囊色应该在移动中渐变成透明透镜、落下时再渐变回来，现在一按就透明、一落就有色，很不舒服、像卡顿；页面切换的瞬间动画未必要完成，动画慢一点自然一点不影响。
- 原因：`WXGRestingSelectionWeight` 在按压 0–0.12 内从 1 到 0；触摸时按压直接 0.10、落下最后约 30 ms 才低于 0.12。
- `WXGDockScript.h`：
  - 新 `select` 轨道：滑动 s0 → 0（65%）；落下段是 `dropStart..land` 的“尾巴”，压按从 dropStart 时的值降到 0（.45,0,.35,1），颜色从当时的值回到 1（.42,0,.58,1）。
  - `WXGScriptPressValue` / `WXGScriptSelectValue` 取代直接读轨道；滑动曲线一直保留到 dropStart。
  - `WXGScriptDrop(s,now,drop)`：dropStart = max(now, planEnd − 0.4·drop)，land = max(dropStart + drop, now + 0.1)。
  - `WXGScriptTravel(…,s0,…,scale,drop)`：时长 × scale；升起时颜色同样褪；dropStart 同上（且不早于升到顶 + 0.02 s）。
  - `WXGScriptHoldsSwitch(s,now,moment)`：0 不等，1 到移动的 80%，2 到 land（FIX95）。手指还按着滑动时总是等。
  - `WXGScriptClockStep`：动画时钟每步最多 1/24 s（`WXGScriptClockCap`，高于 30 fps 的一帧）。
- `WXGDemoBar.m`：
  - `animationNow`：有脚本时用上面的时钟，没有脚本时回到真实时间；记 `clockStalls` / `clockLostMS`。
  - 滑动从按下前的按压和颜色开始（不受按下时 0.10 的影响）；`_jumpPlanEnd` = 脚本的 planEnd，脚本结束时把时钟落后量加回去。
  - `_selectionShown`：有脚本时取脚本颜色，否则按压映射 + `_selectionCarry`（脚本结束时的差值，τ 0.08 s 衰减），所以任何打断都连续。
  - 传给 `WXGGlassView.selectionWeight`（-1 = 按压映射）→ uniform `extra2.w = 1 + weight` → 着色器 `wxgSelectionWeight`（镜内层叠和读回路径）。`_fallbackLens` 同样。
- `WXGLensOptics.h`：`WXGRestingSelectionWeight` 改成按压 0.05–0.45（拖动、按住、拖动松手）。
- `WXGHost.m`：等待最多 1.5 s；同一个标签在挂起时又点一次、而这次落下不等（时机 1、没有移动）：切换后补发第二次点按（`sendSecondTapToIndex:`，review 发现的）。
- 配置：`dockTapDurationScale`（0.6–3，默认 1.5）、`dockTapDropDuration`（0.08–0.8 s，默认 0.26）、`dockTapSwitchMoment`（0–2，默认 1）；设置在“底栏 → 图标与动画”。
- 测试：`DockScriptTests.c` 重写（颜色轨道、无跳变、时长、落下、旅行、三种时机、时钟、120 Hz 逐帧 + 0.18 s 卡顿）；`RestingSelectionTests.c` 改成 0.05–0.45。
- 没改：`dockTapSimpleTravel` 的系统渲染动画（颜色线性 1 − p/0.9），它交接给逐帧透镜时颜色仍可能差一截（FIX98 后最多约 0.5，以前约 0.87）。持续低于 24 fps 时动画会变慢（时钟上限）。

## FIX97（测试版 ABC）

- 用户（附 iOS 26“文件”App 底栏截图）：“基本没问题了”，但透镜内部别的地方也要有一定的色散，不只两端高折射范围（那里要较强），比如内部那个括号边界（上下深色槽的边）。
- 实现（只在同步渲染模式的透镜 pass，`WXGGlass.metal` 的 `u.sync.x>1.5` 分支）：
  - FIX46…FIX96 内联的“透镜里的底栏”（弯曲、FIX94 放大、inset、屏幕距离 dd）抽成 `wxgLensBar(p,…)`，可以在偏移点再问一次；层叠（veil、描边、第二道高光、静止选中）抽成 `wxgLensBarLayers(dd,…)`。`extra2` 为 0 时和 FIX96 逐像素一样（模拟器比对过）。
  - 分色向量 `split = dome × extra2.x × press + 透镜法线 × extra2.y × 透镜色散 × 1.55 × press × rim`：dome = (p − 透镜中心) / 半尺寸（圆顶：中心 0、边缘 1）；rim = 底栏折射带内的深度 × 折射带宽 / 两端宽（两端 1，上下按比例变小）。
  - `wxgLensBarSpectrum`：dd 在 p+split（红）、p、p−split（蓝）各算一次，按 t∈[−1,1] 二次插值，7 个波长逐个合成层叠，红绿蓝用峰在 t=1/0/−1 的三角权重（和为 2/3/2）。每个波长的柔化 `wide=max(soft,|a1|·.25+|a2|·.4)` 盖住步长，没有条纹。
  - 只取三个点的第一版：描边亮线裂成红、绿、蓝三条线，不要。
  - CA 只用一个 alpha 合成：取三通道最大的 alpha，再把 `extra2.z ×（alpha_max − alpha_c）` 补回 rgb（extra2.z = 假定的页面亮度：深色 0、浅色 1）。不补的话白底上色带低到 −0.8（review 发现的）。
  - 透镜画布是整个视图：只在 `lens.distance<1` 时算光谱（性能）。
- 配置：`lensBarDispersionOn`（b，默认 1）、`lensBarDispersion`（0–2 pt，默认 0.6）、`lensBarDispersionNearRim`（0–1，默认 0.35）；设置 → 折射强度和色散 → 底栏，“镜内底栏色散”一组。`WXGUniforms` 加 `extra2`（304 字节，`_Static_assert`）。
- 检查：`tools/shader_sim/check_bar_dispersion.py`（黑底 / 白底 × 4 个位置）：未按下与关闭相同、离边缘远不变、有彩边、每通道均值变化 < 0.004、每通道在关闭图 4 pt 邻域的范围内（±0.06）、亮度峰 / 谷数不多于关闭时。模拟器加了 `page`、`tint`、`pageGuess` 参数，默认值输出和以前一样。
- 没做：页面是图片或深色壁纸（浅色模式）时，补回的页面亮度是猜的，彩边那一两像素会略亮。

## FIX96（测试版 ABC）

- 用户：透镜和选中胶囊都是“安卓圆角”（FIX95 改成了 circular），很丑；他认为之前的问题也是圆形圆角造成的。
- 结论：之前的问题确实是 CA 的连续圆角和着色器的圆形胶囊对不上（见 FIX95 的测量）。这一版两边都用连续圆角。
- 测量：
  - FIX93 截图（`d0a2d038`）里透镜外框和底栏左端外框亮线的亚像素质心（列 / 行按法线方向选，窗口 ±2 / ±4 px）；
  - 以各自端头圆心为极点，φ 为离开直边法线的角度；
  - 透镜（长宽比 1.26）和底栏（5.3）的 ρ/R − 圆形胶囊在 −16°…28° 内吻合到 0.002 R，说明曲线与尺寸、长宽比无关（长宽比 ≥ 约 1.25）；
  - 数据和拟合脚本在 `ReferenceAnalysis/FIX96_continuous_corner/`。
- 实现：
  - `WXGOptics.h`：`WXGContinuousDeviation(phi)`（−24°…90° 的 5 项正弦级数，rms 0.0016 R）、`WXGContinuousCorrection(x,y,w,h)`；
  - `WXGCapsuleOpticalField` 的 distance 减去修正，法线仍用圆形的；
  - 长宽比 1.15→1.25 从圆形过渡到连续（圆形按钮不变）；端头圆心 0.15–0.40 R 内淡出；直边上 φ < −24° 提前返回。
  - 所有用胶囊场的地方（着色器 `wxgShape`、`WXGMeshRefraction.h`、`WXGTravelVeil.h`、`WXGSharpRingAlpha`）自动一致。
  - 轮廓网格：`WXGMeshContourPointC` 把环沿圆形法线外移修正量（环深度 = 场深度）；`WXGMeshContour` 在胶囊直边两端 0.40 R 内每 0.1 R 采样（连续曲线比圆形早离开直边）。底栏网格顶点 1656 → 1908，透镜 598 → 754，最大误差 0.20 → 0.24 pt。
  - 恢复 continuous：`_lensClip`、`_lensRim`、`_fallbackLens`、`_travelLens`。
- 测试：
  - 新 `ContinuousCornerTests.c`：与测量值的最大偏差 0.0011 R、圆形回退、交界处与 42° 的方向、边界、无跳变、对称、竖向胶囊；
  - `OpticsTests`、`RollbackOpticsTests` 的圆形轮廓断言改为连续轮廓。
- 没做：圆形按钮（CA continuous 下的圆是微方的圆）和圆角矩形不在这次的测量范围内。

## FIX95（测试版 ABC）

- 用户对 FIX94：
  - “底栏透镜改成啥了”，FIX94 的贴边放大不要；
  - 他说的透镜边框应该从圆角往上下最外侧一路变窄（图一 iOS 26），现在是圆角处最窄、上下又变宽（图二、图三，就是 FIX93 的截图）；
  - 下拉修好了；
  - 头像这次读到没有？头像大小、上下位置、描边宽度和颜色要能自定义；
  - 点按快速切换呼出的不是完整透镜，只是形状，透镜和里面都没效果。他原本的设计是：点按只是按设计好的速度和过程量自己走，不该改成别的东西。
- 透镜边框：
  - 量 FIX93 截图（`d0a2d038`）每列外框亮线和透镜内“底栏边缘亮线”的位置：正上方相距约 4 px，±11–19 pt 处 2–3 px，再往外变宽。
  - 外框按列下沉比圆形胶囊多约 1.5 px（±12–18 pt），说明系统 continuous 圆角在直边转圆弧处比圆形往里收约 0.5 pt。着色器按圆形胶囊算（`WXGCapsuleOpticalField`），亮线跟着圆形走，所以在那一段离 CA 外框最近。
  - 修改：`_lensClip` / `_lensRim` 的 `cornerCurve` 改为 circular（`WXGGlassView` init）。`_fallbackLens`、`_travelLens` 同样改。
  - 新工具 `tools/shader_sim/`：把嵌入的着色器当 C++ 在 CPU 上跑（`stub/metal_stdlib` 带像素纹理，`fwidth` 两遍模拟），按用户参数出图。`python3 tools/shader_sim/build.py <out> params.txt…`。圆形外框下，正上方相距 4 px，往外 5、6、7、8 px，单调。
  - 试过在着色器里加一圈“亮环”（style.w），模拟下和自然边界差不多，撤掉了。
  - FIX94 的贴边放大：键改为 `lensBarFollowOn`（默认 0）。旧键 `lensBarFollow` 不再读，所以 FIX94 自动打开的也关了。`WXGLensBarZoom` 和测试保留。
- 点按切换（推翻了“已经定下来的”里“点按在渲染服务里滑动”这一条，用户要求）：
  - `WXGDockScript.h`（纯 C，`Tests/DockScriptTests.c`）。按下别的标签：`WXGScriptGlide`（FIX43 时长、贝塞尔 .40/0/.30/1，前 55% 升到 max(.9,p0)，之后保持）。
  - 松手在该标签：`WXGScriptDrop`（land = max(now+.1, planEnd)，land−.09 起落下，land+.05 结束）。拖到别的标签松手：`WXGScriptTravel`（同 FIX43/FIX88 的 beginTravelToIndex 关键帧）。
  - `-tick:` 里 script 生效时直接设 `_lensX/_velocityX/_press/_pressVelocity`，弹簧不走，弹性形变照常用速度。按住过 planEnd+.02 → 结束 script、`_targetPress=1`（跟手）。拖动超过 10 pt → 结束 script（保留速度）。
  - 新触摸打断落下时记 `_resumeIndex`，在同一标签松手再落一次（`beginTravelToIndex`，无位移时只落下）。
  - 减弱动态效果、或打开 `dockTapSimpleTravel`（“点按时用简化透镜”）时不用 script：前者走 FIX42 主线程补间，后者走原渲染服务 travel，且都立即切换。
  - 宿主 `dockChanged`：`holdsTabSwitch`（script 第 1 段，或第 2 段且未到 land）时挂起，`pendingUntilLanded`。`firePendingTabIfReady`（两种渲染分支的 tick 里都调用）要等 `!holdsTabSwitch && !tracking`，再按 dockSwitchTiming 判断，最多等 1 s。
  - 挂起期间点回微信当前标签 → 取消挂起，什么都不转发。同一标签再点一次 → `pendingRetaps=1`，切换后下一轮 runloop 再转发一次点按。
  - 日志“底栏：透镜落下后切换到第 N 个标签（松手后等了 xx ms）”（前 6 次）。诊断里有 `landedSwitches`，dockInteraction 里有 `tapAnimation`、`scriptGlides/Drops/Travels/Drags`、`scripted`。
- 头像：
  - FIX94 诊断：`avatarStatus` 为“找到了聊天联系人，但头像服务和消息里都没读到图片”，`avatarLookups` 9 次。
  - 新路径 `downloadedAvatarFor:contact:started:`：读联系人的 `m_nsHeadHDImgUrl` / `m_nsHeadImgUrl`，http 先改 https，`NSURLSession.sharedSession` 下载，`NSCache` 按 userName 缓存，失败最多再试一次。下载中 3 s 内不取消息列表的图（`downloadWaitUntil`）。下完若屏幕上是消息列表的图，会刷新换掉。
  - 消息列表：表格或集合视图；类名含 HeadImage / HeadImg / HeadView / Avatar / avatar / headImage；`WXGAvatarImageOfLayer` 找子图层的 CGImage。
  - 探测（每个聊天页第一次，`avatarProbe`）：页面类、联系人类、单聊 / 群聊、三个头像字段（只记有无和域名）、MMServiceCenter / MMContext / MMHeadImageMgr 是否存在、管理器类名和带 head / avatar 的方法名（≤40）、消息列表类、可见 cell 数、左侧方形视图（类名、大小、是否名称匹配、有无图）。`avatarDownload` 为下载状态。
  - 设置（WXGExtraSpecs）：`avatarSize` 60（32–88）、`avatarOffsetY` 0（−24–24）、`avatarBorderWidth` 1.5（0–4）、`avatarBorderHex` #80808052、`avatarDarkBorderHex` #9E9E9E6B。在“基本设置 → 头像模式”。
  - 头像按自己的中心缩放（中心 = 原 60 pt 时的中心 + 偏移），标题胶囊位置按 60 pt 不变。描边 `borderWidth` 不超过头像宽的 1/4。

## FIX94（测试版 ABC）

- 用户：首页下拉仍被压；透镜黑边在圆角处最细（应在上下两端最细）；问是否读到对方头像；头像模式改成无玻璃的对方头像。
- 首页下拉：
  - FIX93 的 `homePullHosts`：下拉时 MainFrameLeftBarView 与 NewMainFrameRightTopMenuBtn 都在 `MainFrameTableView → WAMainFrameTopHeaderView → WAMainFrameTaskBarView(→ WAMainFrameTaskBarCloseArea)` 里。原生按钮进了列表，就落在 WXGEdgeFade 的列表遮罩和顶部模糊带下面。
  - `WXGIntegrationHost followHomeTopBar`（tick 里，紧跟 `updateHomePullFloor`）：首页时找 `_scrollViews` 里的 MainFrameTableView，`topBarViewsInList:` 查 `homeGestureHosts` 和 `_buttons` 的 motionHost/original 是否在它里面。
  - 视图本身及到列表之间的父视图 hidden 或 alpha < .01 的不算（`WXGShownInside`；conceal 只换遮罩，不改 alpha / hidden）。
  - 只在 `homePull > .5 || homePanel > 0` 时，以及之后 1 s 内生效（`homeTopBarPulledAt`），存 `homeTopBarInList` / `homeTopBarList` / `homeTopBarPage`（weak）。变化时调 `WXGEdgeFadeSyncController(_route.leaf)`，离开首页时也同步原来那个首页。
  - 静止时仍在列表里，则 `homeTopBarInListAtRest` = YES（诊断）。日志前 6 次。
  - `WXGHomeTopBarInList(list)`（WXGIntegration.h）= `homeTopBarInList && homeTopBarList == list`。
  - WXGEdgeFade：`maskTopSolid`（遮罩里覆盖顶部渐隐区 `_fadeTop+1` 的白层）在 `topBarInList` 时 opacity 1。顶部模糊带的 cover = `topBarInList ? 1 : panel`（半径 × (1 − cover)，> .99 隐藏）。底部不变。
- 透镜里的底栏贴边（`WXGLensBarZoom`，WXGLensOptics.h，Metal 与 C 共用）：
  - 镜内每一列，底栏竖直方向放大 z，让底栏边缘落在“透镜该列边缘 − margin × 该点折射带宽 `WXGLensEdgeWidth`”处。
  - x 先夹到底栏直段（端帽取直段末端的比例）。端帽列再取 `WXGLensBarColumnZoom` 在真实 x 处允许的比例（该列底栏高 hb、切线、inset 的竖直分量）中较小的一个，透镜一端压在端帽上时也不越过边缘（审查发现的问题，旧做法越过 4–8 pt）。z 用 softplus 下限 1（k = (z − 1)/.04）。
  - 着色器的 `dd` 除以 `length(float2(s.nx, s.ny/zf))`（只在竖直方向放大，端帽侧面的描边不再变细），zf = 1 时与原来完全相同。
  - 只有 render-server 分支有（readback / hybrid 没有），设置说明里写了“只在同步渲染模式下生效”。
  - Metal（render-server 透镜 pass）：`u.extra.w` > 0 时 `bend = wxgBasePoint(float2(p.x, barMid.y + (p.y − barMid.y)/zf))`，`dd` 也乘 zf。`u.extra.w` = `_dockSurface && lensBarFollow ? lensBarMargin : 0`。
  - CPU 点按动画轮廓：`WXGTravelVeilOutline(..., const WXGLensFollow *)`，WXGDemoBar `newTravelVeilPathForLens` 传 side（随 press 插值）/ ratio / sharpness / margin。
  - 配置：`lensBarFollow`（b，默认 1）、`lensBarMargin`（.5，.2–1）。已有存档没有这个键时 = `lensTopEdgeRatio < .99`。设置在“透镜（按压时）”。
  - 测试 `Tests/LensBarZoomTests.c`。
  - 早期模拟在 scratchpad `lens2/sim7.py`（x 夹住的版本）。
- 头像：
  - `a.plain = YES`（无玻璃 / fallback）。WXGSurface `layoutSubviews` 里 avatar && plain：iconView = 整个 materialRect，AspectFill，圆角 = h/2（circular）。
  - `styleAvatarRing`：borderWidth 1.5，浅色 white .5 α .32，深色 white .62 α .42。trait 变化时经 `resolveSourceImage` 重设。
  - buildNavigation 里放好标题胶囊后，若 a 在 t 下面就 `insertSubview:a aboveSubview:t`。
  - 占位图：渲染的 120 pt 灰底（white .78）+ 白色 person.fill（非模板）。
  - FIX93 诊断里 avatarTitle 关着（avatarLookups 0），读头像的路径没走到，尚未验证。

## FIX93（测试版 ABC）

- 用户：FIX92 没解决；发来 17:09 的参数导出，要作为默认值，但不强制覆盖别人已装旧版的设置。
- 默认值：`tools/bake_defaults.py` 写入 `WXGBuildProfile.h` 的 `WXG_DEFAULT_OPTICS_JSON`。参数 253/253 项、开关 12、ui 1，与导出逐项比对一致（sizeScale 四舍五入到 6 位）。
  - 加载顺序：`loadDefaults`（内置值 + 这份）→ 旧 suite → `optics.test4` 存档覆盖。存档是全量键，所以已有存档的手机不变。
  - 存档里没有的表键（新版本新加的），从它自己的来源键推出，不用这份。开关 / 卡片圆角只在没有存档时用这份。
- 顶栏：
  - FIX92 诊断：`navigationRaises` = 0；外层只记到常驻的 `MinimizeBaseView`（iConsoleWindow 里，全屏，第一次进首页时就有，与下拉无关）。层级没被盖。
  - 新判断：`followNativePresentation` 把原生宿主链的 opacity 乘到玻璃上，下拉时微信淡出自己的标题栏，玻璃跟着变淡，透出列表的渐隐 / 模糊。
  - 修改：`WXGSurface.alphaFloor`（以及记录用的 `nativeAlpha` / `nativeHidden`）。tick 里先 `updateHomePullFloor`：首页最大列表下拉量 `homePull` > 1 时，除 nativeGesture 以外的按钮 floor = 1 − homePanel；离开的按钮 floor 置 0。然后才 `followNativePresentation`，floor 也会顶掉 hidden。
  - 左按钮（nativeGesture，挂在 MainFrameLeftBarView 里）继承原生透明度，没处理。
  - 诊断：`followHomePull` 在下拉 / 面板打开时每 0.1 s 记一条，留最近 60 条（`homePullTrace`）。每条有 t、pull、panel、导航栏 alpha / hidden / y，以及每个按钮的 alpha、原生链 alpha、hidden、y、宿主 y。`homePullHosts` 是宿主的父链类名。原生链 alpha < 0.95 时记日志（前 6 次）。
  - 外层扫描改为每个视图 / 图层只记一次、继续往下扫，并加了不属于视图的 CALayer。

## FIX92（测试版 ABC）

- 用户：首页下拉想进顶部小程序时，标题和左右按钮的图层临时被压到模糊和渐隐下面，延迟后恢复；要顶部元素的优先级比模糊高。
- 判断：`_navigationOverlay` 在 `_route.nav.view` 里，只在 `ensureOverlay`（每次 refresh）时 `bringSubviewToFront`。下拉进小程序面板时，有视图（连同首页列表和它的渐隐遮罩、模糊带）排到了它上面，直到下一次 refresh。没有拿到当时的视图层级，是从“延迟后恢复”推断的。
- 修改：
  - overlay 的 `layer.zPosition = 10000`（同级里总在最上面画）；
  - tick 里 `keepNavigationOnTop`：每帧检查 overlay 是不是容器的最后一个子视图，不是就提回去（计数 `navigationRaises`，前 12 次记下盖上来的类）。
  - 再往外逐级检查：容器之外排在 overlay 所在分支上面、可见、非插件、宽度过半、在顶部 120 pt 内的视图，记日志和 `navigationCovers` / `lastNavigationCover`，同一个视图只记一次。这一层只记录，不改，封面 / 原生转场时不查。
- 若用户还看到，按 `lastNavigationCover` 记下的那一层再处理（可能要把 overlay 临时挪到更高的容器）。

## FIX91（测试版 ABC）

- 用户：底栏标题的字又粗又大（微信原本的太细太小，但现在的也太粗太大）。
- 原因：`WXGRenderDockIcons` 固定 `systemFontOfSize:10.5`，未选中 Medium、选中 Semibold；选中图集在透镜里再按 lensZoom 放大。
- 修改：表里 `dockTitleSize`（10，8–13）、`dockTitleWeight`（2，0–4：Light −.4 / Regular 0 / Medium .23 / Semibold .3 / Bold .4）、`dockTitleBolderSelected`（0）。`WXGIconJob.titleSize / titleWeight / bolderSelected`；`iconLayoutKey` 带上这三项，变了就重画图集。设置：底栏“图标与文字”分组加文字大小（滑块）、文字粗细（`WXGChoice3` 分段）、选中的文字加粗一档（开关）。
- 诊断：`WXGNativeIcons` 读到微信标题 UILabel 时记下字体名、字号和 `UIFontWeightTrait`，写在 `nativeIconSummary` 第一行（“微信标题字体 …”），以后可按它定默认值。

## FIX90（测试版 ABC）

- 用户：FIX89 可以了。问导出参数是不是全局的（是的话下次备份一份参数）；要能调底栏图标和标题之间的距离，以及整体上下位置（微信原来的不适合悬浮底栏）。
- 导出：`WXGSharePayload` 本来就是全部 `parameterValues`（整张表，含 FIX89 两道高光和本次的键）+ `WXGPreferences`（除 enabled / homeSearch / perfMonitor / perfHUD）+ 卡片圆角和强调色；没有改代码。用户说下次会备份一份发来，可以用 `tools/bake_defaults.py` 写成默认值。
- 图标位置：表里 `dockIconTitleGap`（5，0–16）、`dockIconOffset`（0，−12–12，+ 向下）。`WXGIconJob.iconShift / titleShift`：icon 中心 midY−8+iconShift，标题顶 midY+10+titleShift；iconShift = offset − (gap−5)/2，titleShift = offset + (gap−5)/2（gap 是 26 pt 图标框下沿到标题顶）。`applyConfig` 比较 `iconLayoutKey`，变了就 `rebuildIcons` + `layoutBadges`；角标 y 加 iconShift。设置：底栏页新分组“图标与文字”。

## FIX89（测试版 ABC）

- **用户对 FIX88 的反馈**（附 iOS 27 浅色 / 深色两组设置截图和 FIX88 诊断）：
  1. 两个方向的高光颜色本来就不一样，只加“另一方向高光”没意义。要的是两道各自颜色、各自角度的渐隐描边同时存在，比如截图里浅色那组（黑、90°）和深色那组（白、0°）一起画；不用分深浅色，也不要左下 / 右上渐隐。
  2. 在别的标签上长按能呼出透镜了，但按不久就弹回原标签，而不是一直跟着手指、松手切换。
- **iOS 27 两道高光**：
  - `WXGRimGlowLevel` 回到 FIX87 的单道形式（去掉 cross），`Tests/RimGlowTests.c` 也回到 FIX87。
  - `WXGRimGlowShape` 加颜色 red / green / blue / alpha（alpha = 颜色 alpha × 不透明度），去掉 cross；`WXGRimGlowCount` = 2。
  - `rimGlowForScope:index:`：0 用原浅色键（Rim27*），1 用原深色键（darkRim27* / dockDarkRim27* / bubbleDarkRim27*），与外观无关。新键 darkRim27Sharpness、dockDarkRim27Sharpness、bubbleDarkRim27Sharpness 继承原来共用的 Sharpness。删掉 Rim27Cross、Rim27Fade 各 6 个键；导入时未知键本来就忽略。
  - glow 样式的 `rimForScope` 返回 opacity 1、fade 0（透镜边框也不渐隐）；`rimHexForScope` 返回高光一的颜色。
  - CA：新类 `WXGRimGlowLayer`（嵌套光带 + `WXGRimLevelLayer` 遮罩 + 组不透明度 = alpha，按 key 缓存），`WXGRimView configureGlows:count:` 按顺序叠两个（高光二在上）；`WXGRimLevelLayer setEndLevel:sharpness:angle:`。诊断里每个边框的 `glow` 是两道的数组。
  - 着色器：`WXGUniforms` 加 `glow2`、`glowColor2`，18 个 float4 = 288 字节（静态断言已改）；`extra.x` 改为高光二的宽度。glow 时 `borderColor` = 高光一的颜色，透镜段和本体段在高光一之后再叠高光二。`wxgGlowStroke` 去掉 cross。
  - 点按动画：`_travelOutlines` 两条线；glass 的 `lensOutlineColors` / `lensOutlineWidths` 为数组（普通样式 1 条，glow 2 条，各取上下边处的亮度 `WXGRimGlowLevel(0,1,…)`，线宽 MAX(.75, MIN(宽·.5, 2))）。
  - 设置：“iOS 27 · 高光一 / 高光二”两组各 7 行（颜色、不透明度、渐隐宽度、向内渐隐曲线、高光方向、最暗处亮度、过渡速度），删掉“过渡”组；样式选择的说明文字改了。
- **长按弹回**：
  - 诊断：4 次取消都在按下整 0.90 s，`settingsEntryReady` = true。
  - 原因：`buildDock` 给底栏加的 `UILongPressGestureRecognizer`（0.9 s，FIX35 的设置备用入口）。入口已加入时处理函数直接返回，但识别器照样识别成功，`cancelsTouchesInView` 默认 YES，UIKit 取消了 WXGDemoBar 的 tracking（`cancelTrackingWithEvent:` → 回到原标签）。FIX87 的“长按松手不切换”也是它。
  - 修复：`cancelsTouchesInView=NO`、`delaysTouchesEnded=NO`；host 作 delegate，`gestureRecognizerShouldBegin:` 只在 `!WXGSettingsEntryReady && _dockView.restingOnSelectedTab` 时开始（新属性：手指按着、没有 travel、没拖动、按下和当前都是原选中的标签）。`continueTrackingWithTouch:` 在 `_fingerDown` 为 NO 时不再处理移动（识别器不再取消触摸后，打开设置时手指再滑也不会改底栏的标签）。
- 审查：独立只读审查一轮，1 处已改（上面最后一句）；结构体布局、键名（3 范围 × 2 道 × 7 项全部存在）、CA 图层和合成顺序检查无误。

## FIX88（测试版 ABC）

- **用户对 FIX87 的反馈**（附草图、微信底栏透镜截图、iOS 26 文件 App 透镜截图和录屏）：
  1. 表情换成实心笑脸，原来的比右侧大太多。
  2. iOS 27 边框其实两个方向都有高光，只是深浅色时另一个不明显，要加上。
  3. 平稳背景加强材质加回来再试。
  4. 顶栏头像模式一直读不到当前聊天的头像，要加读取。
  5. 底栏：
     - 在别的未选中标签上按压时透镜没被呼出；
     - 长按后松手不选中（和单点不同）；
     - 普通点按切换要和拖动呼出的透镜一样，底栏微微放大、透镜内底栏高度减小。
  6. 透镜：
     - 不开折射色散时，底栏与透镜边的连线是直角，折射后成了“平底的切圆”；要 45° 再折射，但到底栏末端仍要正常脱离（斜率不断变低甚至变负）。
     - 收窄折射范围后上下边框会比圆角转弯处“胖回去”。
     - iOS 26 的色散有自己的渐变范围，不限在折射范围里，上下同样收敛，要加。
- **表情**：`face.smiling.fill`（退回 `face.smiling`）。`WXGSurface` 的 emoji 角色 iconMax 由 MIN(26,h·.92) 改为 MIN(19,h·.67)：约 19 pt，对齐 dictation 角色约 17 pt 的麦克风。
- **另一方向高光**：
  - `WXGRimGlowLevel(nx,ny,angle,cross,endLevel,sharpness)`：a=|nx sin r+ny cos r|，b=|nx cos r−ny sin r|，返回 e+(1−e)·max(a^k, c·b^k)；cross 夹到 0..1，NaN 当 0。
  - 表里 `Rim27Cross` 每范围×浅深，默认 0.3，0..1，排在 Angle 行后面。`WXGRimGlowShape.cross`；`WXGRimLevelLayer setEndLevel:sharpness:angle:cross:`。
  - 着色器 `u.extra.x` = cross，`wxgGlowStroke(...,cross)`。`WXGUniforms` 加 `float4 extra`，256 字节（16 个 float4），静态断言已改。
  - 设置：两组 iOS 27 各加“另一方向高光”（`WXGSlider3`）。
- **平稳背景**：从 fix85 原样恢复：
  - 文件 `WXGCalmBackdrop.m`、`WXGCalmMath.h`、`Tests/CalmMathTests.c`；Makefile、`WXGIntegration.h` 的 `WXGCalm*` 声明；
  - 表里 calm 七个键、`calmFactor`、`WXGCalmRegister`、诊断 `calm`、启动时 `WXGCalmApplyPreferences()`、材质页的平稳背景组和 `calmShow`。
  - 新增：着色器的 `u.tintColor`（透镜内底栏的材质）也按 calmFactor 往平稳值移，和 `_veilFallback` 一致。
- **头像**：
  - `-avatarImageForTitle:`（buildNavigation 传入它算好的标题）。每页状态 `WXGAvatarState` 用关联对象挂在页面上：image、source、fromService、attempts、refreshes、lookupAt。
  - 顺序：页面 / titleView 的头像视图键 → 联系人（`GetContact` 等方法，或 `m_contact` 等实例变量，取 `m_nsUsrName`）→ `MMHeadImageMgr`（经 `MMServiceCenter defaultCenter` / `MMContext currentContext` 的 `getService:`）。
  - 类型检查：
    - `getService:` 返回 @、参数 # 或 @；
    - `getHeadImage:withCategory:` 返回 @、第一参 @、第二参整型：q/Q/l/L 按 64 位传，i/I/s/S/c/C/B 按 32 位，空编码拒绝；类别 0、1 各试一次；
    - 单参数的几个变体返回 @、参数 @。
  - 消息列表兜底（`-visibleIncomingAvatarIn:`，大 UITableView 的可见 cell 里类名含 HeadImage / Avatar、24–72 pt 方形、x 在左 30% 内）。只在确定单聊时用：
    - userName 已知且不以 “chatroom” 结尾（含 WeCom 的 @im.chatroom）；
    - 或者 userName 未知、标题非空，且标题不以 “(数字)” / “（数字）” 结尾。
  - 没找到：每 0.5 s 一次，每页最多 24 次（`retryAvatarAfter:` 用 dispatch_after 置 navigationDirty 再 schedule，同时只挂一个）。离开再回来，没图的页重新计数。
  - 头像服务的图：之后每 0.75 s 再问，共 8 次，CGImage 变了就替换（可能先给默认头像）。
  - 诊断 `avatarStatus`（来源或失败原因）、`avatarLookups`。
- **底栏点按动画**（render server 的 travel）：
  - `prepareTravelToIndex` 的 lift / mesh 用真实 `barGrowth`（之前是 1）；prewarm 同样，key 一致。
  - `animateTravelExtras` 改成密集线性关键帧（每 1/60 s，最多 121 帧）。`WXGKeyframeAt` 按关键时间和每段的 CAMediaTimingFunction 在 CPU 上算出 size / press，和 CA 对稀疏关键帧的求值一致；透镜中心用 `travelCentreAt:`（滑动曲线 .40,0,.30,1）。
  - 每帧加的动画：
    - 底栏放大 s=1+(barGrowth−1)·p，以 additive transform 加在 `_glass.layer` 和 `_travelNormalIcons` 上，绕底栏中心；
    - 洞（在图标层未缩放的空间）：位移 (L−bc)(1/s−1)，大小 lens·K/s；
    - 选中图标：缩放 z·s，`_travelIconImage` additive 位移 (L−bc)(1−1/s)，即先绕 bc 放大底栏、再绕 L 放大透镜；
    - 角标：以左上角绕 bc 位移（和 `layoutBadges` 一致）；
    - 透镜内底栏的各层 path。
  - zoom 和洞大小从稀疏动画挪到这里；`setTravelShapeModel` 的模型值同样带 s。
  - 透镜内底栏（`WXGTravelVeil.h`）：`WXGTravelVeilOutline` 用和着色器同一个 `WXGInnerInsetAlong` / `WXGLensDepthAlongBar`，偏移夹到 r−0.01（深层不交叉）；`WXGTravelVeilBands` 把材质边缘减弱拆成最多 8 层嵌套。轮廓线颜色 / 宽度取玻璃的 `lensOutlineColor` / `lensOutlineWidth`：
    - 普通边框：WXGRimStrengthTLBR 上下平均 × rim.opacity；
    - glow：再乘平均亮度，线宽 MAX(.75, MIN(光宽·.5, 2))。
  - 只在 travel backdrop 与玻璃共用捕获组（`backdropGroupName`，渲染模式 ≥2）时画。backdrop 的组改为每次 travel 用 `applyTravelGroup:` 设置，key 不再带组；prewarm 用自己的组 “wxg.travel”，避免在 opacity 0.001 下加入玻璃的组。
  - `loadTravelVeil` 持有 UIColor（之前 CGColorRef 可能悬空）。
- **按住别的标签**：
  - tick 里 phase 1 且手指按着、过了 `_travelPlanEnd+.02` → `handOverTravelToFinger`，计数 `holdHandovers`。
  - hand-over / cancelGlide：press 由当前尺寸反推；`_lensX` 由 `anchorForLensCentreX:press:` 反推（布局对锚点在首末标签间是线性的，可精确反解），所以真透镜接在动画透镜的同一个中心；`_elasticMotion` 清零。
  - 松手没切换（在外面，或按在别的标签、松手时回到原标签）记日志（前 20 次，含按下时长、按下 / 松手 / 原来的标签），系统取消也记；计数 `uncommittedEnds`。长按不切换的根因没找到。
- **透镜 45°**：
  - `WXGOptics.h`：`WXGInnerInsetAlong(barHeight,press,reduction,along)` = full·u·(2−u)，u=clamp(along/(2·full))，起点斜率 1（45°），到 2·full 处变平；`WXGLensDepthAlongBar(ld,tx,ty,lnx,lny)` = max(0,−ld)/max(|t·n|,.3)。
  - 着色器 `wxgLensInset`：底栏轮廓点 q（缩放后）在透镜场里的深度沿底栏切向换算；render-server 透镜段的 `dd` / `em` 用弯曲后的点。旧 `WXGInnerInset` 只留给测试。
  - 端头：法向转向时 |t·n| 变小，深度换算变大，收窄量一直到端头离开透镜，不会卡住。测试 `Tests/LensInsetAlongTests.c`（端头在透镜里收进去的情况在 `Tests/TravelVeilTests.c`）。
- **上下边框“胖回去”**：沿透镜轮廓数值检查了折射带宽度（各配置都单调，上下 ≤ 圆角处）。判断是直角台阶被折射放大的那一条，45° 后应消失；已请用户新版里再确认，有的话截图标位置。
- **色散范围**：
  - 表里 `lensDispersionWidth`（默认 10，1–60，继承 lensEdgeWidth）、`lensDispersionTopRatio`（默认 1，0.1–1，继承 lensTopEdgeRatio）。
  - `WXGMeshOptics` 末尾加 `dispersionWidth` / `dispersionTopRatio`（0 = 用折射带）。`WXGMeshDispersionSide` / `Ratio` / `BandWidth`；`WXGMeshSource` 的色散位移用 dwidth；环带和轮廓带取 max(折射, 色散)。
  - 底栏透镜（`applySyncMode`）和 `WXGMakeTravelLensBackdrops` 都是 edgeWidth→色散范围按 press 插值，**只在分色打开且 dispersion>0 时设置**。mesh 缓存 key 和 `WXGMeshOpticsClose` 含新字段。
  - 着色器：`u.extra.y/z`，`dispSide=mix(bodyEdge,extra.y,press)`，`WXGLensEdgeWidthAtBar` 用 extra.z。
- **审查**：
  - 第一轮独立只读审查 11 条，已改：
    - 悬空 CGColor；
    - 群聊兜底；
    - 头像不再重试；
    - 深层 path 交叉；
    - 关键帧间漂移；
    - hand-over 尺寸跳变（barGrowth、zoom×s、图标位移）；
    - 默认头像被缓存；
    - 类型编码检查；
    - glow 时轮廓为空、平稳背景和着色器材质不一致；
    - prewarm 把组成员放在 0.001 透明度下；
    - 色散关闭时也设置色散宽度。
  - 第二轮审查 7 条，已改：
    - @im.chatroom；
    - 群判断用实际显示的标题；
    - 头像状态和缓存改为每页关联对象（NSMapTable weak→strong 的值不及时释放，回到旧页还会停在默认头像）；
    - hand-over 清 elastic；
    - 轮廓亮度用 TLBR；
    - 角标按左上角。

## FIX87（测试版 ABC）

- 用户对 FIX86 的反馈：①iOS 27 边框在浅色模式应该反过来，两端最强、上下弱，或者更自由，深浅色各自决定渐隐方向；②两种输入栏里输入文字的胶囊在点击升起键盘时放大、键盘出来后又缩小，要固定不动；③两段式输入栏：表情换成苹果的笑脸，语音转文字要有状态提示（现在完全看不出是不是在听写）。键盘升起问题和默认参数用户说暂时不重要。
- 边框方向：`WXGRimGlowLevel(nx,ny,angle,endLevel,sharpness)` = e+(1−e)|n·d|^k，d=(sin a, cos a)，y 向下；0° 上下、90° 两端、45° 左上/右下、135° 右上/左下。表里 Rim27Angle 每范围×浅深（浅 90、深 0，0–180）。`WXGRimGlowShape.angle`；`WXGRimLevelLayer setEndLevel:sharpness:angle:`（上下直边、左右直边各自按方向取值，角场按方向，缓存 key 带角度）。着色器 `glow.x` = 1 + 角度（弧度），`wxgGlowStroke` 多了 nx。设置里“两端亮度”改名“最暗处亮度”（键名不变 Rim27EndLevel），加“高光方向”。
- 输入胶囊：`WXGSurface.pressFixed`（`observedTouchBegan:` 直接不接、`setExternalPressed:` 不按下、`stretches` 为 NO）。两段式 pill、三段式 center 设 YES。原因判断：按下时 _target=1，松手后弹簧回落要靠显示链接逐帧走，键盘调出时主线程被占住，所以放大一直留到键盘出来。plain 的 mic / emoji 仍有自己图标的按下效果（pressProxy 到 pill 后不再放大 pill）。`pressStretchNative` 的开关改名“首页左上角和三段输入两侧也拉伸”。
- 两段式表情：`face.smiling` / `keyboard`（静态缓存，`setImage` 不会每次重算）。面板状态：微信表情按钮图片 16×16 alpha 指纹（`WXGInputImagePrint`），输入栏静止在底部且不在编辑、并且按钮图片 0.4 s 没变时学为笑脸；当前指纹与笑脸平均差 > 0.06 视为面板开着（显示键盘）。没学到时一律笑脸。
- 听写：mic 在听写角色时 `perform` = `dictationTapped`，转发前记下微信听写图标（`MMGrowDictationIconView`，被插件隐藏）此刻的信号作为参照：子树 layer 的动画数、正在动画的 UIImageView、按钮 selected，以及**只属于微信二进制的类**（`class_getImageName` 含 “.app/”）里名字含 record/listen/dictat/recogn/work/start/run/activ/state/status/speak/voice/animat/play/busy/loading 的整型 / BOOL 实例变量。会话中 0.3 s 定时器（common modes）跑 `dictationTick`：先跑结束规则，再走宿主的 `layoutInput`（受键盘 / 遮挡 / 后台的门控）。与参照不同的信号持续 ≥1 s → “读得到”，记下这些信号的取值；之后只要其中任一仍是那个值（动画数仍高于参照、selected 仍为 YES）就算在听，停 1 s 结束。读得到且在听时右侧固定为听写按钮（会话开始时抓的那个控件），再点一次只先隐去提示（`stopAt`），微信停了才结束，1.5 s 后仍在听则恢复。读不到时：提示到出字（开始 1.5 s 后）为止，然后和 FIX86 一样变发送；另外收起键盘 0.5 s、图标离开窗口、12 s、90 s、离开聊天、再点一次都会结束。`endDictation` 立即去掉红色、脉动和“正在听写…”，再 `schedule`。提示标签放在 pill 里，位置取 `caretRectForPosition:beginningOfDocument`。dealloc 里停定时器。浮点实例变量只进诊断，NaN / 无穷记成字符串（JSON 不能存）。诊断 `input.dictation`（readable、onValues、changes、idle、last、lastEnd、icon 里有视图、动画 key、全部标量实例变量）和 `input.emoji`（distance、faceLearned）。
- 表情面板识别改用输入行 `_toolPanelView` 是否停在底部（容差 40 pt），按钮图片换了对象但形状差 ≤0.02 不算变化，学到的笑脸形状全局保存一次。
- 审查：独立只读审查一轮，按意见改了：诊断导出遇 NaN 会崩、听写状态与微信不同步时按钮会反着来（改为只在读得到时固定停止按钮，读不到时出字即结束）、UIKit 自己的实例变量混进比较、出字后听写按钮可能被微信移走（会话里用开始时抓的控件）、定时器绕过宿主门控 / 输入栏不布局时不会结束 / 适配器释放后定时器还在、提示位置没算滚动偏移、表情学习用了整个工具视图的位置。
- `WXGSurface.iconTint`（新）：覆盖图标颜色。

## FIX86（测试版 ABC）

- 用户对 FIX85 的反馈：①边框样式全局一个，选了就所有范围都变，要按范围分别生效；②部分玻璃圆角异常“没有拉伸而是两侧维持半圆”（多行气泡、设置卡片两端深色月牙）；③平稳背景加强材质调不出想要的效果，删掉；④iOS 27 边框胶囊圆角处比上下窄，要处处一样宽；⑤真正的 iOS 27 边框方向相反：高亮白边上下最亮、往两侧减弱，并且往内部渐隐，宽度可调（给了参考截图）；⑥视频号顶部按钮分开（不要胶囊），不覆盖材质，边框恒定用深色模式参数。
- 原因（②④）：FIX85 的 iOS 27 线的内边由 `UIBezierPath roundedRect` 展平后往里收，外边（裁剪）是 CA 的连续圆角，两条曲线不同：圆角矩形两端出现月牙、胶囊圆角处变窄。整个删掉（`WXGRimVariable.h`、`Tests/RimVariableTests.c`、`configureVariable:` / `layoutVariableRadius:`）。
- 新 iOS 27（`WXGRimGlow.h`，纯 C，`Tests/RimGlowTests.c`）：`WXGRimGlowBands(width,falloff,scale,max,…)` 每层约 1 px（最多 20 层），**嵌套**：第 j 层从轮廓开始、宽 (j+1)·宽/n（inset 都是 0），alpha b_j = 1−(1−A_j)/(1−A_{j+1})，叠起来第 j 段正好是 A_j = (1−(j+.5)/n)^falloff（取每段中点，总亮度几乎不随屏幕倍数变）；不用相接的层是因为相接处落在半像素上，两层的抗锯齿会留一圈暗线。`WXGRimGlowComposite` 给测试算叠加结果。`WXGRimGlowLevel(ny,endLevel,sharpness)` = e+(1−e)|ny|^k。`WXGRimView configureGlow:`（NULL 关）：`_glowHolder`（allowsGroupOpacity，opacity = 颜色 alpha）里用 `WXGRimPlaceBands` 放 CA 边框层（玻璃自己的连续圆角），holder.mask = `WXGRimLevelLayer`（上下直边 1、左右直边 endLevel、四角按方向的 256 px 场，和 `WXGRimFadeLayer` 同一套结构，角窗半径取 max(圆角, 光宽) —— 圆角比光宽小时侧边的光不会落进上下直边的全亮区）。两者都继承 `WXGRimFieldLayer`（四条直边 + 四个角窗 + 按 key 缓存的场图，`applyTop:bottom:left:right:fieldKey:level:`）。宽度不超过短边一半；glow 时自身 borderWidth 0、没有描边细节和背景取色；视图自己的对角渐隐照常。
- 着色器（底栏透镜里画的底栏轮廓）：`WXGUniforms` 加 `glow`（x 开、y 两端亮度、z 过渡速度、w 向内曲线；开时 `optics.y` = 光宽），`wxgGlowStroke` 按往里的深度和 ny 算，透镜段和本体段都用。结构 224 → 240 字节（静态断言已改）。改的是 `WXGGlass.metal`，`tools/embed_shader.py` 重新生成，`tools/check_msl.py` 通过。
- 配置：`rimStyle` + `dockRimStyle` / `bubbleRimStyle`（表里 inherit “rimStyle”，升级后等于原样式），`rimStyleForScope:`；`rimStyleValue` = 其余玻璃的，`rimSampleColor` 仍由它同步（旧导出兼容）。iOS 27 键：Rim27Hex / Opacity / Width（2，0.3–8）/ Falloff（1.6，0.5–4）/ EndLevel（0.15，0–1）/ Fade，每范围×浅深；Rim27Sharpness 每范围一个（2，0.5–6）。`rimGlowForScope:dark:` 返回 `WXGRimGlowShape`。FIX85 的 EndWidth / SideWidth 删除。
- 玻璃：样式按 `glassScope` 取；新属性 `rimAlwaysDark`（边框颜色、不透明度、宽度、渐隐、细节、取色参数、透镜边框、着色器里的 bar 轮廓颜色都按深色取；材质 / 选中色仍按实际外观）。着色器里“取自背景”判断改成本玻璃范围的样式。`WXGRimSummary` 输出 `styles`（dock / other / bubble）和每个边框的 `glow`。
- 设置：样式选择行有 dock / bubble 键（`WXGChoice3`），分组按当前范围的样式过滤（`scopeRimStyle`），换范围 / 恢复 / 导入后按该范围样式重建；iOS 27 三组按新参数重写。
- 平稳背景：`WXGCalmBackdrop.m`、`WXGCalmMath.h`、`Tests/CalmMathTests.c` 删除；`calmFactor`、表里的 calm 键、材质页分组、诊断 `calm` 都删了；启动只剩 `WXGPerfApplyPreferences(); WXGKeyboardTraceStart();`。
- 视频号：`groupFinderButtons:` 删除（按钮不再 plain / pressProxy，没有胶囊）。`styleFinderButtons`（导航按钮布局末尾，对 `_buttons` 全部）：WCFinder 页 veilOverride = 透明、`rimAlwaysDark` = YES，其它页 nil / NO，只在变化时赋值。
- 导入 / build 默认值后的 `reinheritExtrasMissingFrom:` 改为：只有来源键在这次的值里（或本身刚被重新推出）时才重新继承；`rimStyle` 只在导入了 `rimSampleColor` 时由它推出。FIX85 的做法会让一个不带样式的部分导入把三个范围的样式都改回普通 / 取自背景，也会把用户自己调过的继承键（如气泡宽度）盖掉。
- 审查：独立只读审查一轮，6 处问题已修（相接层的暗线、按外沿取值的亮度和单层全亮、小圆角时两端亮度失效、部分导入重置样式、透镜里的轮廓还是普通线、SHA256SUMS 和视频号说明的位置）。
- 键盘：无新数据，FIX85 的日志还在。默认参数：仍在等用户发参数文件，`tools/bake_defaults.py` 已认新键（试过 dock/bubble 样式和 Rim27 新键，旧 EndWidth / calm 键会被丢掉）。

## FIX85（测试版 ABC）

- 用户要求：①壁纸写进 Library/Preferences 和 Documents 两处，NSFileProtectionNone + 原子写 + 读时互相自愈，防微信清缓存；②排查键盘异常升起（截图：聊天里输入栏离键盘约 200 pt，中间透出聊天背景图），查不到就加日志；③液态气泡单独的玻璃和边框参数；④视频号左右各两个按钮各合成一个胶囊，不加深浅色材质覆盖，只有模糊和折射；⑤新边框样式仿 iOS 27：两端最粗上下最细，两端 / 上下宽度、过渡速度、颜色可调，独立于前两种；取自背景的样式要有自己的不透明度、宽度等，不和普通样式共享；⑥平稳背景（变化小）时材质接近不透明，能否量化，加开关，壁纸 / 图片背景时用更透明的。
- 配置：`WXGConfig.m` 新增表 `WXGExtraSpecs`（81 个键，KVC 经 `valueForUndefinedKey:` / `setValue:forUndefinedKey:` 存在 `_extra`），带 `inherit`（从未保存过时取来源键的当前值；导入 / build 默认值之后对缺的键再取一次 `reinheritExtrasMissingFrom:`），`normalize` 里夹范围。`keys` = `baseKeys` + 表。`rimStyle`（0 普通 / 1 取自背景 / 2 iOS 27）首次取自 `rimSampleColor`，之后 `rimSampleColor` 由样式同步。作用范围 `WXGGlassScope`（其余 / 底栏 / 气泡），`opticsForScope:`、`rimForScope:dark:`（返回当前样式自己的不透明度 / 宽度 / 亮度 / 渐隐）、`rimHexForScope:dark:`、`rimVariableForScope:dark:`。键名规则见 `WXGScopedKey`（rimSampleOpacity / darkRimSampleOpacity / dockRimSampleOpacity / dockDarkRimSampleOpacity / bubbleRimSampleOpacity / bubbleDarkRimSampleOpacity；iOS 27 是 Rim27Hex / Opacity / EndWidth / SideWidth / Fade，Rim27Sharpness 每个范围一个；气泡普通样式 bubbleRimHex / bubbleRimOpacity / bubbleBorderWidth / bubbleRimBrightness / bubbleRimFade 及 Dark；气泡光学 bubbleRefraction / Dispersion / EdgeWidth / Blur / BlurCoverage / FullGlass；平稳 calmMaterial、calmMaterialOpacity(+dark/dock)、calmThreshold、calmRange）。
- 玻璃：`WXGGlassView.bubbleSurface`（液态气泡设 YES，轻量与否看 `bubbleFullGlass`）、`glassScope`、`calmFactor`（遮盖往平稳值移动）。`WXGRimView configureVariable:`：连续圆角裁剪层里一个 even-odd 的 CAShapeLayer（外矩形 − 内边），内边由 `UIBezierPath roundedRect` 展平后按 `WXGRimVariable.h` 往里收；iOS 27 样式没有描边细节、没有背景取色。
- 平稳背景：`WXGCalmBackdrop.m`（`WXGCalmMath.h` + 测试）：NSTimer 0.3 s（按耗时放宽到 0.6 / 1.2 s），滑动时跳过；按 sourceView 分组，`renderInContext` 到约 0.25 px/pt 的位图（插件自己的祖先视图 layer.hidden 暂藏，同一事务里恢复），每块玻璃区域外扩 6 pt 算 RGB 标准差；视频 / Metal 图层区域算不平稳；换页 / 久未测的玻璃直接取新值，其余每次走 45%。不测：气泡、视频号胶囊（有 veilOverride）、lightweight。
- 设置：边框页顶部样式选择（新的 choice 行，切换后整页按样式重建）；refraction / blur / border 三页 `scopes` 含 bubble（三段切换）；行多了 `bubble` 备用键；材质页“平稳背景”组和“查看当前背景变化程度”；液态气泡页加三个 `open:模块:bubble` 入口；恢复本页默认会带上 bubble 键并按新样式重建页面。
- 视频号：`groupFinderButtons:`（`WCFinder*` 页）每侧 ≥2 个按钮时一个池化的 `finderLeftGroup` / `finderRightGroup`（materialOnly、跟随第一个按钮的原生运动、插在最下面），按钮 plain + pressProxy；这些页的玻璃 veilOverride = 透明。值只在变化时赋（不再每次布局开关玻璃）。
- 存储：`WXGSettings.m` 的 `WXGSettingsRead/Write/Remove`（同一个串行队列，读用 dispatch_sync），两处目录，失败的那份删除，旧 Application Support 文件迁移。帧率日志也在 Library/Preferences。
- 键盘：没找到原因（插件不改输入栏 y；只有底栏搜索 4 s 交接会聚焦）。`WXGKeyboardTrace.m` 记录通知和输入栏 / 键盘间距快照。下次要用户在出现时导出诊断。
- 审查：另一个只读审查找出 7 处问题，均已修（存储竞争 / 失败删旧图、导入后新键不跟随、视频 / Metal 背景被当成平稳、复用玻璃沿用旧平稳值、视频号每次布局开关玻璃、恢复默认后页面不按样式重建、透明背景色当黑色）。

## FIX84（测试版 ABC，A / B / C 三个账号）

- 来历：另一个对话里先在 FIX81 A 上做了这些（当时叫 FIX82，已发给用户，但不含液态气泡），用户随后发来 FIX83 A（液态气泡，FIX82/83 在他那条线上），要求合并。FIX84 = FIX83 A + 下面这些，三方合并（基准 FIX81 A），冲突只在版本号、`WXGPreferences` 键、`WXGIsPluginView` 名单、`Makefile`。
- 用户：FIX81 偶尔出现“渐隐直接跟随滑动，将整个页面消息都接近隐去”（首页截图：第一行正常，第二行渐隐，下面全是底色）；要一个帧率性能检测日志模块和一个配置参数共享模块（如果现有日志能完全读出参数也行）；他有一套效果好的参数，想做成安装后的默认设置（**这次没有发参数文件，等他用 FIX84 导出后发来**）。
- 渐隐：`WXGEdgeFade.m` 的列表登记表是 16 个指针的数组，页面释放时 `_scrollView`（weak）已是 nil，登记永不清除；满了以后新列表写进第 0 格，挤掉最早登记的首页列表，首页列表的 setBounds: 钩子找不到页面，遮罩（在列表滚动坐标里）不再跟随，随内容滑走。改为列表上的关联对象 `WXGEdgeListLink`（weak page），无上限；`refresh:` 时核对 `WXGEdgePageForList(list)==self`，否则重新关联并计数 `relinks`。诊断：`linked`、`maskLag`、`maskSyncs`、`relinks`。
- 帧率：`WXGFrameStats.h`（纯 C，`Tests/FrameStatsTests.c`）+ `WXGPerfMonitor.m`：自己的 CADisplayLink（`WXGConfigureDisplayLink`，屏幕最高刷新率），开关 `pref.perfMonitor` / `pref.perfHUD`（WXGPreferences，默认关）。每秒记录、按页面×滑动/静止汇总（1 ms 直方图求百分位）、>50 ms 或 3 次刷新的卡顿事件、插件主线程耗时（`WXGProfileAdd` 的 Tick，以及 tick 外的 Refresh / Switch；渐隐跟随滚动单独计时）。每 15 s 与退到后台时写 `Application Support/WeChatLiquidGlass/perf_current.json`，下次运行改名 `perf_previous.json`。浮标 `WXGPerfHUDView` 是微信主窗口的子视图（zPosition 100000，盖在弹出页面上；在 `WXGIsPluginView` 名单里），可拖动，位置存 `perf.hudCenter`。没有用独立窗口：独立窗口会成为 `UIApplication.windows.lastObject`，微信若把提示加到最后一个窗口就会被塞进 200×42 的小窗。同一次运行里关掉再打开记录，本次会话继续（只有“清空本次记录”重来）。插件耗时：宿主 tick / refresh 用嵌套计数 `WXGHostTimedDepth`，只记最外层；渐隐跟随在其中时不另计。报告页 `WXGPerfReportController`，导出 JSON（current + previous + 报告文字）。
- 参数共享：`WXGSettingsShare.m`。格式 `{"schema":"wxg-settings-v1","config":WXGConfig 全部键（除 enabled）,"integration":WXGPreferences（除 enabled/homeSearch/perfMonitor/perfHUD）,"ui":{cardRadius,accentHex}}`。复制（紧凑 JSON）/导出文件/剪贴板导入/文件导入（UIDocumentPicker，Import 模式）。导入认：本格式、诊断 JSON 的 `settingsShare`、旧诊断的 `materialParameters`（优先 currentOrLastScene 的）、裸的 WXGConfig 对象。诊断 JSON 顶层新加 `settingsShare` 和 `frameRate`。
- 默认值：`WXG_DEFAULT_OPTICS_JSON` 可以是旧的裸 config，也可以是上面的格式；`WXGBuildDefaultSection(@"config"/@"integration"/@"ui")`。WXGPreferences、WXGSettingsStore 在没有存储（新装）时用 build 的 integration / ui。`tools/bake_defaults.py <导出或诊断 JSON>` 写入（96 字符一段的 C 字符串拼接），已用样例验证往返和 ObjC 编译。
- 设置首页“通用”多了第三张卡片“帧率与参数”（module `tools`）。
- `WXGHost.m`：`tick:` 拆成 `tick:` + `tickBody:begin:`（只为在 tick 内置 `WXGHostTicking`，避免把 tick 内的 refresh / 切换重复计入插件耗时），版本号 0.4.82 / FIX84，诊断文件名改 FIX84。
- 合并后：液态气泡的 `textCellLaidOut`（TextMessageCellView 布局钩子）和每次提交前的 `reassert` 也计入插件耗时（`WXGPerfTimePluginWork`，在宿主 tick / refresh 里时不重复计），渐隐跟随同样。`bubbles` 开关和气泡颜色、边缘减弱在参数共享里（WXGPreferences / WXGConfig 的键自动包含）。设置首页“通用”和“个性化”各三张卡片。
- 待办：用户发来参数后 `python3 tools/bake_defaults.py <file>`，出带默认值的包（FIX85）。


## FIX81 ABC（另一个对话，未发布）

- 用户要求：在 FIX81 A 的基础上把测试 B 和 wxid_12cm2d89f8ya22 也绑定进去，折射和色散参数也开放。只改了 `WXGBuildProfile.h`（三个哈希：A wxid_mpuxjt2kgy2s22、B wxid_wb0yvnj7a1m522、C wxid_12cm2d89f8ya22；标签“测试版 ABC”；`WXG_HIDDEN_MODULES` 保持 `@[]`）。B 的 FIX60 预设没有加。FIX84 沿用这个授权。

## FIX83（只出测试版 A）

- 用户：气泡颜色要像“其余玻璃”那样可选范围的边缘减弱，不要整块填充。
- 做法：玻璃的着色覆盖可带自己的减弱范围；气泡页加开关和范围（默认开、8 pt）。

## FIX82（只出测试版 A）

- 用户：他的 MixBubble（自己的气泡插件，源码 `MixBubble_2_8_Release93_PROBE_PRIVATE_source.zip`）有接管微信原生气泡绘制的方法，其中“无尾巴单行圆角”（圆角始终是单行高度的一半）想搬进本插件，做液态气泡模块，集成气泡和玻璃的绘制，以后需要再自定义。
- 从 MixBubble 只取了找气泡本体的方法和圆角规则（`WBPFindTextBodyView`、`WBPEffectiveBubbleCornerRadius`、单行参考高度的取法），没有搬尾巴几何、合并、引用、翻译等。MixBubble 的覆盖层放在 TextMessageCellView 里本体下面；这里把玻璃放进本体最底层（随本体一起动）。
- 风险：每个可见气泡一层背景（滚动性能）；与 MixBubble 同时接管会叠加；长按换图靠提交前重隐藏。

## FIX81（只出测试版 A）

- 用户对 FIX80：描边“马马虎虎”，深色模式想让边框明显不容易（他认为是这种做法的局限，能理解）；发来 FIX80 诊断 JSON，要求把参数推为新版默认，并在边框页最底部加“恢复默认”，后续再调整。
- 做法：边框页 53 个键写进 `loadDefaults`；新装直接用默认值；边框页加“恢复本页默认”（`resetKeys:`）。拉伸参数没改默认（用户只说描边）。
- 深色模式观察：他的深色取色增益 2.5、提亮 0.6 都在滑块上限、对比度 0.5 在下限，深色背景经处理后接近白色；开了加亮叠加，线条最多把玻璃提亮“深色不透明度”（其余玻璃 0.14、底栏 0.23），这是深色下明显程度的直接上限。

## FIX80（只出测试版 A）

- 用户对 FIX79：描边已能调出接近目标的效果。按压拉伸要加参数：胶囊（非圆）只能上下 / 左右微微拉伸，不能斜向；加回一定的跟手移动（固定太死板）；加最大可拉伸幅度，与变形程度相关。另：希望把他这次调好的描边参数作为默认值（以后可能不再开放这些参数）。
- 做法：见 `WXGPressStretch.h` 的 `WXGStretchStyle`；三个新键与滑块。
- 默认值：需要用户导出的诊断 JSON（`materialParameters` 里是全部配置），拿到后把“边框与渐隐”页的键写进 `WXGConfig.m` 的 `loadDefaults`（恢复默认也会回到这套）。FIX80 发出时还没收到。

## FIX79（只出测试版 A）

- 用户对 FIX78：有渐隐了（嵌套遮罩可用）；线两侧的消散基本只有宽度变化，看不出中间亮两边暗的渐变；希望 0.1 pt 一级的消失感（透明度减弱或亮度降低），区分内外侧；深浅色配置要分开设置；“仅做尝试，渲染有风险或失败了再想办法”。
- 做法：两侧各 N 级（每级 ≤ 0.1 pt），每级是一圈 CA 边框（原连续圆角），透明度模式用嵌套带、变暗模式用全宽颜色 + 黑带，均精确到每级强度（`WXGRimDetail.h` 有推导，测试逐点验证）。取色线条：遮罩为透明度阶梯；变暗时描边视图在下垫黑（不透明度同线条），取色层 plusL 叠上，等于“颜色 × 级强度”。细节与取色参数全部分浅色 / 深色，开关共用。删除“中间亮线宽度”。
- 风险：backdrop 上的 plusL（只在变暗 + 未开加亮叠加时用到）；0.1 pt 的带靠 CA 边框抗锯齿，是否平滑需真机看。

## FIX78（只出测试版 A）

- 用户对 FIX77：两种边框颜色似乎并存，要确定只有一种生效；只让改原边框的颜色形式，不该做出“安卓圆角”的边框和阴影；选中胶囊的切换被弄坏（描述不出来）；不要乱加东西。
- 做法：所有自绘几何（环形图、圆弧路径阴影）删除。取色线条 = backdrop 视图，遮罩 = 容器 → 持有层（CA 边框 + 居中 CA 边框，mask = 与描边相同的 `WXGRimFadeLayer`）。内侧阴影 = CA 厚边框投影（裁剪到线内侧）。透镜回到 FIX72 描边（无细节、无取色层）；取色开启时透镜描边、透镜里的底栏轮廓、设置卡片都用材质颜色经同一矩阵处理的颜色。
- 风险：嵌套遮罩（backdrop 的 mask 子树里再有 mask）在 iOS 15 未实测；若不生效，取色线条可能没有渐隐或不显示。选中胶囊损坏的确切现象未知，按最可能原因（透镜取色层）处理。

## FIX77（只出测试版 A）

- 用户对 FIX76：找不到“描边取色”设置；取色线条只在四条边上各画了一段不完整的直线（颜色是对的）；宽度不能自定义。
- 原因：设置组被插到材质模块；`renderInContext` 画大半径连续圆角（圆 / 胶囊）时在每边中间画直线段而无圆弧（截图：按钮外接方框四边中段的亮线，胶囊两端的竖线），FIX74 的四个尖同源。
- 修：设置组移到边框模块；半径 > 0.3 短边时用 CG 圆弧环。宽度来自各模式“宽度”滑块，回复里说明。

## FIX76（只出测试版 A）

- 用户：背景取色不能丢（FIX74 调过后能做到类 iOS 26 的颜色），要饱和度、对比度，再加鲜明度；只需要“比背景亮、浅、鲜艳”；对比度可能不影响；不确定要不要和边框颜色二选一。
- 做法：取色打开时边框颜色不用（二选一），其余设置照用。线条 = `WXGRimTintView`（backdrop + 模糊 + 颜色矩阵，普通合成默认，plusL 可选），遮罩是用 renderInContext 画出的原 CA 边框（含 FIX75 两侧 / 中间）× 原对角渐隐场，所以形状与原边框一致（FIX73/74 的距离场轮廓不圆）。鲜明度没做（颜色矩阵是线性的，做不出“越灰加越多”），在 README 里说明了。
- 用户“其余玻璃”边框不透明度为 0，取色线条也用它，需调回。

## FIX75（只出测试版 A）

- 用户对 FIX74（新描边已生效）：画不出正圆（圆按钮在上下左右四处发尖）、宽度像固定的、和旧边框像冲突、透镜边框变两条、顶部和底部按钮同参数效果完全不同。要求：撤掉“渐隐时中间收窄”，只做线两侧变暗 + 内侧阴影（颜色可自定义），渐隐用旧方式——不是新画法，只给旧边框加细节；另外按钮拉伸加个开关（比原版差太多）。
- 诊断：`filterTypes` 里没有 screenBlendMode 也没有 plusL（混合模式不列在这里，不能据此判断）；用户开了加亮叠加、强度 1.5、饱和度 3、内侧阴影宽 0.5；“其余玻璃”的浅色 / 深色边框不透明度被调成 0。
- 做法：删掉图像式描边，`WXGRimView` 回到 CA 边框 + 原渐隐遮罩，细节都是子图层（受同一遮罩）：自身边框 alpha = a·side，居中内缩 `w(1−core)/2` 的边框 alpha = (a − a·side)/(1 − a·side)；内侧阴影 = 裁剪层（inset w，连续圆角）里的 shadowPath 环。颜色不再取背景。
- 拉伸：总开关 `pressStretch` 早就有（用户截图里就是它），另加 `pressStretchNative` 只管输入框 / 首页左上角。用户说的“按钮拉伸加开关”含义不完全确定，回复里说明了。

## FIX74（只出测试版 A）

- 用户：FIX73 打开自适应描边后完全没效果，仍是旧边框（诊断在插件设置页导出，没有玻璃条目）。
- 原因：`WXGBuildRimImages` 用 `CGImageCreate(…, NULL colorspace, kCGImageAlphaOnly, …)` 建线图，Core Graphics 拒绝（工程里其他 alpha-only 图都走位图上下文），每个形状都失败并进 `WXGRimFailed`，`layoutAdaptiveRadius:` 没有图就一直 `showClassic:YES`。
- 修：位图上下文建图；覆盖改 RGBA 上下文；解析圆角覆盖兜底；失败表随 `WXGConfigRevision()` 清空；`WXGRimSummary()` → 诊断 `liveSamplingAtExport.rims`（各状态数量、requests / builds / analyticBuilds / failures / lastFailure、blend、filterTypes 里是否有 screenBlendMode / plusL、最多 8 个在屏描边的 evidence）。
- 还没确认：图生成后，带蒙版、加入玻璃 backdrop group、合成为 `screenBlendMode` 的 CABackdropLayer 在 iOS 15 上的实际效果。

## FIX73（只出测试版 A）

- 用户：①进入插件设置页偶尔上一页按钮不隐去、叠在新页按钮上（黑色折射边，录屏 FIX69）；②输入框拉伸超出原输入框区域就被切掉，要限制；③改进描边，像 iOS 26：截面两侧暗中间亮、内侧一圈很淡的阴影、颜色随背景（亮度 / 对比度 / 饱和度都加了的感觉：浅色近白、深色更浅、彩色更亮的同色）、渐隐时两侧先没中间亮线变细；给了 6 张图让我自己分析。
- ①：推入 WXG 页时 refresh 先把 `_buttons` 转成 `_departingButtons`，然后因 unsupported 走 `!available` 分支暂停 display link，离开页的按钮不再 `followNativePresentation`，冻在原位直到 coordinator completion。现在 `!available` 时先 `dropDepartingButtons`（隐藏、失活、复位变换）。
- ②：`WXGStretchFit`：变换后圆角矩形的支撑函数求外接范围，二分拉动比例，使其不超出 `stretchClip`（祖先 clipsToBounds 的 bounds 与 layer.mask.frame 的交，转到 surface 坐标），框先并上不拉动（含按压）时的范围。拉伸目标（按压满时）和每帧姿态都限制。假设切割来自微信输入面板的 clipsToBounds；诊断 `stretchClip` 可确认。
- ③：测量与模型见 `ReferenceAnalysis/FIX73_rim.md`。实现见 VALIDATION。关键风险：`screenBlendMode` 作为 CABackdropLayer 的 compositingFilter 没在真机验证过（`plusL` 在 FIX23 的色散里用过）；若 `+[CAFilter filterTypes]` 列出 plusL 却没有 screen 会自动退到 plusL，另有用户开关“改用加亮叠加”。线层加入玻璃的 backdrop group（共用采集，后面没有玻璃内部），合成在玻璃之上。形状用 `renderInContext` 画连续圆角（与 refreshBodyMask 同法）。
- 用户的配置：流畅模式开着；描边宽度约 0.93–0.99 pt、渐隐约 0.64–0.69。新描边的强度等是新键，默认值由四组截图数据拟合（饱和度 1.8、对比度 1.15、提亮 0.16、强度 0.55）。

## FIX72（只出测试版 A）

- 用户：FIX71 完全不跟随。原因：`observedTouchBegan:` 收集 followers 后立刻 `updateContentTransform`，此时姿态仍是静止，`poseFollowers:` 在静止时清空名单。改为 `_followTouching` 期间不清空，触摸结束且静止后才清空；去掉按下时的立即刷新。诊断 `stretchFollowers`（类名，最多 8 个）。

## FIX71（只出测试版 A）

- 用户：输入框 / 首页左上角拉伸时，上面的图标和文字不动很奇怪。
- 做法：materialOnly 玻璃在被旁听的触摸开始时，从识别器所在视图（输入工具栏 / MainFrameLeftBarView）往下找完全落在玻璃区域（外扩 2 pt）里的最外层视图（不含玻璃自己和包含它的视图，最多看 400 个），存为弱引用 followers；每次姿态更新给它们的图层加 `transform` 的叠加动画（`additive`、`fillMode forwards`、超长时长），数值 = 同一姿态按图层 position 相对玻璃中心换算（`WXGStretchChildOffset`）；静止时移除并清空。只影响渲染，不改 frame / 命中 / 文字选择。
- 没确认：叠加的 transform 动画与微信自己在这些视图上的动画同时存在时的表现。

## FIX70（只出测试版 A）

- 用户对 FIX69：朋友圈仍黑；拉伸跟手正常（不再自己弹回）但玻璃离开原位太多，应几乎不动、只变形（胶囊更明显）；两个输入框和首页左上角按钮不会变形。
- 朋友圈：FIX69 诊断 `WCTimelineTableView` 背景 #111111（不透明），单元格白色，`backgroundPlate.source=list` 垫的就是 #111111。改为 `WXGEdgeCellPaint`（可见的整行单元格：backgroundColor / contentView / backgroundView 的不透明色），与列表色亮度差 > 0.35 时用单元格色（source=cells）。
- 拉伸姿态：平移 = 按压偏移 + 方向 × 拉长量 × 0.45（`WXG_STRETCH_SHIFT`），远端几乎不动。
- materialOnly 玻璃（`nativeGesture` 首页左上、`input` 输入框、`nativeInput*` 三端）：`observeTouchesInView:`（首页挂在 MainFrameLeftBarView，输入挂在 `_tool`）加 `WXGTouchObserver`（一直 possible、不能阻止 / 被阻止、不取消不延迟，触摸结束置 failed），从玻璃上开始的触摸驱动同一套按压与拉伸；只变形玻璃（文字 / 图标是微信的视图）。`setActive:NO` 时移除识别器。
- 没确认：用户说的“两个输入框”是否就是这两种输入栏（也可能指底栏搜索框，它展开后在底栏胶囊或搜索按钮玻璃上，这版没处理）。

## FIX69（只出测试版 A）

- 用户对 FIX68：拉伸会自己脱手弹回（应只在放弃点按 / 抬起手指时弹回）；朋友圈上下渐隐也变黑；融合不做了。
- 拉伸：FIX68 在手指离玻璃 40 pt 外时就释放（回弹 + 取消按下）。现在拉伸开启时整个触摸都按下并跟手，抬起时 40 pt 内才 `activateOriginal`。`gestureRecognizerShouldBegin:` 在跟踪中拒绝非 `UIScreenEdgePanGestureRecognizer` 的拖动手势（防止列表 / 全屏返回抢走触摸；不确定 UIKit 是否对祖先的手势也问被触摸的视图，问了就生效）。
- 渐隐底板：`WXGEdgeListPaint`（列表背景色 → table / collection 的 backgroundView 颜色），没有时 `WXGEdgeBackdropBehind`（从列表往上到页面：祖先不透明背景，或列表下方覆盖列表的不透明 / 有图片的兄弟视图）为否则用 `systemBackgroundColor`。诊断 `backgroundPlate.source`：list / backgroundView / systemBackground。
- 出包：从这版起直接给 deb。`/home/claude/build_deb.sh <工程> <输出.deb>`：按 Makefile 的文件和框架用 clang 18 编译、ld64.lld 链接（`-mlinker-version=711`，SDK 里补了 theos/sdks 的 .tbd）、`/home/claude/tools/ldid -S`、dpkg-deb（rootless：`/var/jb/...`、`iphoneos-arm64`）。用户偏好直接拿 deb。

## FIX68（只出测试版 A）

- 用户要 iOS 26 的按住拖动拉伸 + 回弹、相邻玻璃融合。商定分两步：这一版只做拉伸（导航按钮、标题胶囊、输入栏按钮、底栏搜索按钮）+ 底栏拖过两端拉长；下一步先只做“底栏 + 搜索按钮”的融合，再扩展。
- 拉伸（`WXGPressStretch.h`）：位移 = 橡皮筋 `L(1 − 1/(1 + 0.8d/L))`，L = 跟手距离 × clamp(短边/44, 0.75, 1.25)；拉伸矩阵 S = s·uuᵀ + p·vvᵀ，s = 1 + amount·|o|/沿向尺寸，p = max(0.6, 1 − 0.5·amount·|o|/横向尺寸)；姿态 = S × 按压缩放，平移 = 按压偏移 + o；子视图平移 = t + (M − I)·r。弹簧：跟手 600/41，松手 300/14（过冲约 23%）。开启拉伸时按住 / 点击范围为玻璃外 40 pt；`plain` 的 surface 不拉伸。全靠视图变换，玻璃内部（网格、边框、材质）不重建。
- 底栏两端：`trackPoint` 里手指越过首 / 末标签中心 8 pt 后，橡皮筋位移 o（上限为设置值，搜索按钮那侧再限到间距 × 0.75，由宿主设 `endStretchRoomLeft/Right`）；`WXGDockEndStretchPose`：sx = 1 + o/W，远端为锚点，sy = 1 − 0.2·o/h。变换加在 `_glass` 和 `_travelView` 上（它们改为 bounds + center 放置），角标按同一映射摆放。
- 没确认：斜向剪切变换下 CABackdropLayer 的表现（按压原来只有轴向缩放）；拉伸量和弹簧手感。

## FIX67（只出测试版 A）

- 用户对 FIX66：首页下拉出的小程序页上有不该有的渐隐和模糊，底栏也不该显示；从搜索进入的聊天所有效果都是原生的。
- 小程序页：它是 `MainFrameTableView` 里的 `WAMainFrameTopHeaderView`（FIX65 诊断：静止时窗口坐标 y −720、高 808，下边缘 88 = 导航栏下沿）。展开程度 = smoothstep((下边缘 / 窗口高 − 0.18) / 0.24)（`WXGHomePanelProgress`）。渐隐：遮罩里的白色子层不透明度 = 展开程度（遮罩合成 alpha = k + a(1−k)）；模糊带半径 × (1−k)，k>0.99 隐藏。底栏：`updateHomePanel`（每帧，只在首页、主路由、底栏静止、没有转场和遮盖时）→ `_dockRow` 下移 k ×（覆盖层高 − 底栏顶 + 16），和键盘上移合成（`setKeyboardLift` 的目标位移加上 `homePanelDrop`），k>0 时整行不接触摸。
- 搜索进入的聊天：`WXGRouteForWindow` 遇到弹出页时原来一律 `presented → unsupported`（刷新时挂起，保留下面的场景）。微信搜索是整屏弹出的导航，聊天推在里面。现在：叶子是 `BaseMsgContentViewController`、最后一个导航有 `presentingViewController`、弹出根视图正好铺满窗口 → `presentedStack`（不算 presented、不 unsupported、不 primary）。从这种聊天回到搜索页（presented）时不挂起，走 unsupported 复原。
- 没确认：小程序页类名在用户的版本上（FIX65 诊断里有 `WAMainFrameTopHeaderView` / `WAMainFrameTaskBarView`）；展开时这块的下边缘是否真在屏幕下方；搜索页确实是整屏模态（如果是 UISearchController 盖在首页上，路由本来就不是 presented，那原因另有，需要那时的诊断）。

## FIX66（只出测试版 A）

- 用户对 FIX65：没设壁纸的聊天页和微信“设置”页，上下渐隐处是黑的；其他页面不会。FIX65 诊断：聊天页 `MMTableView`、设置页 `WCTableView` 的背景色是不透明的 #EDEDED，页面视图本身没有不透明背景；首页的 `MMUIHookView`（页面视图）是不透明 #EDEDED。列表 mask 连列表背景色一起渐隐 → 露出后面的黑色窗口。
- 改动：列表 `backgroundColor` 不透明时，在列表正下方放 `WXGEdgePlateView`（同色，frame = 列表在父视图里的可见区域），在 `syncGeometry` 里跟随位置 / 大小 / 颜色（`isEqual` 比较）/ 隐藏；插件设置页（壁纸覆盖模式）不需要。

## FIX65（只出测试版 A）

- 用户对 FIX64：模糊强度默认太高；上下强度要分开（两边距离一般不同）；范围最大 8 就够；“其余页面”要加上我们自己的设置页和微信的设置页。
- 改动：
  - `WXGConfig`：`edge{Chat,Other}BlurRadius` 换成 `edge{Chat,Other}Blur{Top,Bottom}Radius`，0–8，默认 3（旧键不迁移，用户说旧值太高）。设置每组 6 行：顶部渐隐 / 模糊距离 / 模糊强度，底部同样。
  - 其余页面加 `NewSettingViewController` 和 `WXGSettingsPage`（`isKindOfClass`）。宿主的 `viewWillAppear:` / `viewDidAppear:` 钩子原来对 `WXG` 前缀的页面直接 return，`WXGEdgeFadeNoteController(c,YES)` 移到这个判断之前。
  - 插件设置页：列表是 `WXGSettingsScrollView`，里面是玻璃卡片（`CABackdropLayer`），列表加 mask 会破坏卡片的背景采样（和“背景层不能放在 alpha<1 下”同一类问题）。所以不加列表遮罩，改为在列表之上放 `WXGEdgeCoverView`（`UIImageView`，壁纸图、同 frame、同 contentMode，mask = 1 − 渐隐曲线，只在列表范围内），模糊带在它之上。`WXGSettingsPage.wallpaperView` 提供壁纸视图。深浅色切换时覆盖层在下一次滚动 / 布局时换图。
  - 设置变更通知改为 `refresh:NO`（不强制重新找列表，值变化照样重建遮罩 / 改强度），插件设置页里拖滑杆当前页即时生效。
  - 列表尺寸变化（键盘等）时 `syncGeometry` 直接整套重算（`appliedSize`），模糊带长度和遮罩一起更新。
- 没确认：强度 3 的观感；微信“设置”页找到的列表（诊断 `edgeFade.pages[]`）；“设置”的子页面（通用、隐私等）没有加，用户只说了设置页。

## FIX64（只出测试版 A）

- 用户给了两份工程：自己的 WeChatFade 1.1（页面渐隐，“我的渐隐可以”）和别人的渐隐 + 模糊（WCLG*，“渐隐 bug 多”）。要求：用自己的渐隐 + 别人的模糊做一个模块，聊天页和其余页面（首页、通讯录、朋友圈、聊天设置）分别设上下的渐隐和模糊距离。
- `WXGEdgeFade.m`：
  - 渐隐 = WeChatFade 原样：找列表（属性 `m_tableView` 等 +100，再整页打分：宽 ≥55%、高 ≥220、table +90、collection +75、类名 table/list/mmtableview/msg/main…），列表 `layer.mask` = 129 段 smoothstep 的 `CAGradientLayer`（`WXGEdgeFadeMath.h`），遮罩随 `layer.bounds.origin` 移动，原遮罩关闭时放回。不再用 60 fps 计时器：列表的类第一次被管理时挂 `setBounds:` / `setFrame:` / `setCenter:` / `layoutSubviews`（类自己没有实现的，加一个调用父类当前实现的版本），里面用 16 个指针的数组预筛再找页面；页面出现时强制重新找列表，布局时最多每秒一次，列表丢失时立即。
  - 模糊 = WCLG 的 `variableBlur`：`WXGEdgeBlurView` 的 layerClass 就是 `CABackdropLayer`（scale 0.5），滤镜 `variableBlur`（`inputRadius` = 设置的强度，`inputMaskImage` = 4×256 的表图，按 Telegram 表 k/255 @ n/287，边缘 1 → 内侧 0，`inputNormalizeEdges`）。没有 `variableBlur` 时退回 `gaussianBlur` + 同一张表的 `CAGradientLayer` 遮罩。两条带插在列表父视图里、紧贴列表之上，frame = 列表可见区域的上 / 下一段；列表就是页面根视图时不加模糊。没有用 WCLG 的同色色板。
  - 页面分组按类（`isKindOfClass`）：聊天 `BaseMsgContentViewController`（及 `MMMsgContentViewController`）；其余 `NewMainFrameViewController`、`ContactsViewController`、`WCTimeLineViewController`、`AddContactToChatRoomViewController`（单聊信息）、`ChatRoomInfoViewController`（群聊信息）。
  - 入口：宿主的 `viewWillAppear:` / `viewDidAppear:` 钩子末尾 `WXGEdgeFadeNoteController(c,YES)`，`viewDidLayoutSubviews` 钩子里 `(c,NO)`；设置变更（`WXGSettingsChanged` / `WXGIntegrationChanged`）刷新全部页面。
- 设置：`WXGPreferences.edgeFade`（默认开）；`WXGConfig` `edgeChat*` / `edgeOther*` 各 5 项（渐隐上 / 下 96 / 112、模糊上 / 下 96 / 112、强度 10；范围 0–320 / 0–360 / 0–30）。模块 id `fade`（检查脚本只认小写 id），首页卡片在“个性化”。
- 诊断：`edgeFade`（每页的列表类名、frame、遮罩是否挂上、模糊带 frame、模糊方式、找列表 / 换列表 / 重建遮罩次数）。
- 没确认：`variableBlur` 的遮罩图按图层拉伸（WCLG 用整幅图，开源 VariableBlur 用 100×100，都能用，所以按拉伸处理）；模糊强度 10 的观感；各页面列表是否就是要的那个（看诊断 `edgeFade.pages[].list`）。用户手机上如果还装着 WeChatFade 会和这里抢同一个遮罩。

## FIX63（只出测试版 A）

- 用户对 FIX62：搜索已经触发（结果是对的），但搜索框里不显示词，删一格才出现 → 是 FIX62 填入后补的 `insertText:@"\n"`（模拟搜索键）留在了微信的输入框里。去掉了，只填文字（微信边输入边出结果）。
- 回弹在终点处“顿一下”：FIX60 的硬限制（变宽的一块最多挤进间距 65%）到头后停住。`WXGDockSearchSwapRight` 改为越过终点时变小的一块按越过量 × 0.35 被压扁（tanh 软上限为高度的 1/4），另一块跟着，间距不变。
- 用户要求展开后总是左搜索框、右关闭：按钮在左 = 交换（`WXGDockSearchSwapRight` 镜像）；按钮在右 = 不交换（`WXGDockSearchStay`：胶囊→搜索框、圆按钮→关闭按钮，两行插值）。
  - `WXGDockSearch` 的输入区拆成独立的 `fieldView`（放大镜 + 输入框），由宿主放在底栏行的最上层，跟着左边那块玻璃：按钮在左时放大镜随前缘移动；按钮在右时整个输入区在胶囊上淡入。按钮自己有放大镜和 × 两个图标（按钮在右时用）。`closesWhenOpen` / `onClose`：按钮在右时展开后点它就是关闭。`WXGDemoBar.showsClose`：按钮在右时底栏不显示 ×、搜索时不接触摸。
  - 搜索行加宽上限：按钮在左 64 pt；在右 min(64, 2×(30+搜索高度−底栏高度))，保证弹簧和外鼓仍在 40 pt 画布内。

## FIX62（只出测试版 A）

- FIX61 诊断：`lastHandoff` = “右上角搜索按钮：没有找到微信的搜索输入框”。用户截图：触发后是微信新的搜索页（左上返回、“搜索本地或网络结果”，键盘已弹出），文字没进去。结论：那个页面的输入框不是 UITextField（扫描窗口找不到，也没有 TextDidBeginEditing 通知），多半是网页输入框。
- 改动：
  - 用 `sendAction:to:nil` 找当前第一响应者（`UIResponder (WXGFirstResponder)` 分类）；不是我们的输入框且实现 `UIKeyInput`，持续 0.2 秒后 `insertText:` 填入，0.3 秒后按搜索键（UITextField：搜索栏代理 `searchBarSearchButtonClicked:` 或 return；其他：`insertText:@"\n"`）。最多等 4.2 秒，之后回退写入开始编辑的 UITextField。
  - 不在“微信”页时，切过去后每 0.03 秒检查首页右上角搜索按钮是否已在窗口里，在了就立刻触发（`pollHomeSearchEntry:`），不等刷新。
  - `WXGDockSearch` 的 `textFieldShouldBeginEditing:` 只在展开时返回 YES：系统关闭微信搜索页时会把焦点还给我们的输入框，导致键盘不落下。
  - `WXGDockSearchSwell`：整行外侧两端随弹簧外鼓（速度项 1.4% 行宽 + 越过终点的量 × 9% 行宽），高度加外扩量的 1/3。
- 没确认：“\n”提交在微信的网页输入框里是否等同按搜索；如果填入后没有搜索，看 `lastHandoff` 里的响应者类名。

## FIX61（只出测试版 A）

- 用户对 FIX60 的反馈：要看清展开动画，不要自动弹键盘；搜索框“又高又短”；两块玻璃的间距要能调；切换动画时有灰色遮罩闪一下（有一帧是矩形）；输入的文字没有转进微信搜索，只打开了搜索页。
- 改动：
  - `openDockSearch` 不再让输入框成为焦点；点输入框才弹键盘。
  - `WXGConfig` 新增 `dockSearchGap`（默认 12）、`dockSearchHeightRatio`（0.82）、`dockSearchWidthFraction`（0.94），在“底栏 → 搜索”。`WXGDockSearchLayout.h` 改成两行（平时一行、搜索一行）插值：边缘、高度随 t 过渡，形状上下居中；搜索行最多比平时宽 72 pt。
  - 交给微信搜索：诊断里 `lastHandoff` 是“UISearchBarTextField：不是焦点，未填入”。现在文字一直挂着，每 0.1 秒找当前聚焦的输入框（不是我们的）用 `insertText:` 填入，最多 2.6 秒；之后写入开始编辑的那个输入框（`text` + EditingChanged + 通知 + `searchBar:textDidChange:`）。微信搜索框在被隐藏的表头里开始编辑时只取消裁剪，不再重设 `tableHeaderView`（怀疑它让输入框失去焦点）。
  - 去掉了标签栏淡出时的 CAFilter 高斯模糊（怀疑灰色闪烁）；搜索按钮初始阴影路径为空。灰色闪烁的原因没有确认，要等用户说明出现在动画还是键盘弹出时。
- FIX60 的诊断确认首次切页的 `treeScanMS` 已降到 0.03–0.08 ms。

## FIX60（底栏搜索）

- **用户要求**：参照一段录屏和 React 的 DiscoverButton，把首页顶部的搜索移到底栏。底栏 = 标签栏胶囊 + 圆形搜索按钮；点搜索按钮，它用弹簧（刚度 230、阻尼 20、质量 1.2）展开成搜索框，标签栏收成 × 圆钮，内容淡出 / 模糊；点 × 反过来。材质用自己的玻璃，选中仍是透镜 + 选中胶囊。用户选了“方案 B”：底部是真的输入框（不是点按钮就直接打开微信搜索页，那样少了展开这一段）；按钮左右可选；顶部搜索栏可以开关隐藏。
- **结构**：
  - `WXGDockSearchLayout.h`：整行布局（`WXGDockSearchLayout(t,…)`，t 是弹簧值，0 标签栏 / 1 搜索），间隔 `WXGDockSearchGap`，淡入淡出曲线。“底栏宽度比例”现在是整行宽度。
  - `WXGDockSearch.m`：搜索按钮，`dockSurface` 玻璃（底栏那套参数），同步模式下 Metal 覆盖层隐藏（它在这个模式下什么都不画）。圆形时点按发 `UIControlEventPrimaryActionTriggered`；展开后是 `UITextField`，按“搜索”调 `onSubmit`。
  - `WXGDemoBar`：`searchMode`（整个底栏只是 × 按钮，发 `PrimaryActionTriggered`）和 `setSearchShape:progress:`。形变期间玻璃轮廓跟着宿主给的形状，透镜收起、Metal 覆盖层隐藏，标签栏由普通图层画（和点按滑行动画同一套静止画法：未选中图标挖洞、选中胶囊底色、胶囊里的选中图标），这些图层可以淡出、加模糊（不含背景层，FIX37 的限制不适用）。回到原形时先 `drawNow` 再一起切回覆盖层。
  - `WXGHost.m`：底栏和按钮放在同一个 `dockRow`（穿透触摸的 `WXGOverlay`），键盘出现时按键盘的时长和曲线整体上移。弹簧在宿主每帧里推进（先于底栏的 tick）。只在稳定的标签页根页面可用，转场、遮盖、设置页都会直接复原。
- **交给微信搜索**：按“搜索”后先找首页右上角那个被隐藏的 `onSearchButtonTapped` 按钮触发（找不到就让列表表头的 `WCSearchBar` 成为焦点）；不在“微信”页时先切过去。之后监听 `UITextFieldTextDidBeginEditingNotification`，微信的输入框一开始编辑，就全选并 `insertText:` 填入（等同键盘输入，微信会出结果）。0.45 / 1.2 / 3.3 秒各补查一次（找焦点输入框，或让可见的搜索框成为焦点），3.2 秒没成功就记下原因。结果在诊断 `dockOwnership.search.lastHandoff`。**没有在真机上验证过**。
- **隐藏顶部搜索栏**（默认关，开了底栏搜索才生效）：把只装着搜索栏的表头高度收成 0、裁剪，再赋回 `tableHeaderView`；微信的输入框在表头里开始编辑时放回来，编辑结束且清空后再收。关掉开关 / 底栏搜索 / 插件时恢复。
- **卡顿修复**：FIX59 诊断里第一次切到“我”页 `treeScanMS` 52.9 ms，第一次回“微信”页 27.5 ms，之后约 1 ms。判断是逐个视图 `NSStringFromClass`（Swift 类第一次取名要 demangle）。改成 `WXGIsPluginView`（按类判断自己的视图）、几个固定微信类按类比较、自定义导航栏先按位置筛再取名。下一份诊断要看 `treeScanMS` 是否降下来。
- **待确认**：B 的预设里流畅模式是开的（来自用户的导出），用户还没说要不要关。

## FIX59（测试版，按账号授权）

- **账号授权**：`WXGLicense.m` + 每份工程自己的 `WXGBuildProfile.h`。
  - 宿主每次刷新时，看到登录后的主界面（`r.tabs`）就开始读当前 wxid。读取方式依次是：`MMContext` / `MMServiceCenter` → `CContactMgr getSelfContact.m_nsUsrName`，`SettingUtil getLocalUsrName:` / `getCurUsrName`，`AccountStorageMgr.m_oSetting.m_nsUsrName`。
  - 读到后算 `SHA-256("WXGLiquidGlass.license.v1:"+wxid)`，和列表比对；每 3 秒复查一次。
  - 原来所有 `WXGPreferences.shared.enabled` 的判断都换成了 `WXGPluginEnabled()`（总开关且已授权）。刷新里 `available` 也要求已授权，未授权时走和总开关关闭相同的恢复路径。
  - 设置首页在未授权或读不到账号时，只显示状态卡（当前账号、复制账号、重新检测）。诊断里有 `license` 一项（wxid 已打码，含读取方式）。
- **两份工程**：A 绑定 wxid_mpuxjt2kgy2s22，B 绑定 wxid_wb0yvnj7a1m522，B 的 `WXG_HIDDEN_MODULES` 是 `@[@"refraction"]`。`WXG_DEFAULT_OPTICS_JSON` 是这一版的预设参数（新装和恢复默认时用），现在为空。
- **性能**：
  - 设置页卡片设为 `WXGGlassView.lightweight`：1 层背景，不做 RGB 色散和清晰环，最多 2 倍采样；设置页显示刷新降到 60 Hz；
  - 新增配置项 `performanceMode`（流畅模式）：所有玻璃同样处理，关闭时和 FIX58 相同。
- 配置导入导出这一版没有做。
- `tools/verify_fix58_scope.py` 是 FIX58 对 FIX57 的校验，FIX59 改过这些文件，它不再适用。


把这个压缩包和这份说明一起发给新对话即可。要排查问题，再附一份最新诊断（插件设置 → 基本设置 → 导出各页诊断 JSON）。

## 这一版是什么

FIX58 = **FIX57 + 新的设置界面 + 四类玻璃参数拆成“底栏 / 其余玻璃”两套**。用户对 FIX57 的评价是“基本没问题了”，然后要求重做设置界面。

用 `tools/verify_fix58_scope.py <FIX57 目录>` 校验：
- 拆分只改了 4 个文件：`WXGCommon.h`、`WXGConfig.m`、`WXGGlassView.m`、`WXGDemoBar.m`。撤回脚本里列出的改动后，与 FIX57 逐字相同。
- `WXGGlassView.m` 另有 2 处：清晰环遮罩改用新的 `WXGEdgeMaskBand.h`。结果逐字节相同，只是更快，用新测试 `EdgeMaskBandTests.c` 核对。
- 设置界面：`WXGSettings.m`、`WXGOpticalSettings.m` 重写，`WXGSettingsKit.h` 是新文件。
- `WXGHost.m` 只改了版本号。
- 其余文件（含透镜和着色器）与 FIX57 逐字相同；测试是 FIX57 的 41 个，加上新的 `EdgeMaskBandTests.c`。
- `Makefile` 加了 `PhotosUI`。

`tools/check_settings_coverage.py <FIX57 目录>` 检查 FIX57 的 71 项设置在新页面里都还在。

### FIX58 设置界面（用户的要求）

- **布局**：参照用户给的 Liquid UI 截图，但每行两张卡片（黄金比矩形）。没有搜索。
- **首页**：
  - 头部卡片：圆头像（可从相册换）、插件名、版本号、总开关；
  - 模块卡片：基本设置、底栏、折射强度和色散、模糊强度与范围、材质强度与范围、边框与渐隐、壁纸。
- **顶部**：没有底板。
  - 左边是返回按钮，位置、形状和宿主的玻璃返回按钮完全一样（`WXGMeasure`、`centerY`，与 `buildNavigation` 一致）；
  - 中间是标题胶囊；
  - 右边是强调色按钮，改设置页的文字和图标颜色。
- **卡片**：用“其余玻璃”参数的实时玻璃做背景，连续圆角。圆角可调（0–40，默认 26）。
- **壁纸模块**：设置页的浅色、深色壁纸可以分别导入。
- **作用范围**：除底栏和基本设置外，四个玻璃模块都有“底栏 / 其余玻璃”切换。用户说以后还要把“其余玻璃”再细分。
- 用户原话：“不要漏掉现有设置，做好我再看”。

### FIX57 是什么（透镜部分仍是这样）

FIX57 = **FIX47 的透镜 + FIX54 的其余部分 + 末端放松**。当时用 `tools/verify_fix57_scope.py <FIX54 目录> <FIX47 目录>` 逐文件校验（版本号除外）：

- 透镜 5 个文件（`WXGGlass.metal`、`WXGGlassView.m`、`WXGLensOptics.h`、`WXGMeshRefraction.h`、`WXGOptics.h`）：FIX47 的，加上 FIX57 的改动（撤回后与 FIX47 逐字相同）；`WXGShaderSource.h` 是重新嵌入的着色器；
- 其余 40 个源文件：FIX54 的（头像、置顶回到 FIX44；钱包顶部 = FIX47 底色 + FIX50 列表）；
- 测试：FIX47 的 5 个透镜测试、FIX54 的其余测试，加上新的 `LensEndRelaxTests.c`。

为什么从 FIX47 出发：用户对比 FIX56 后说“改的是对的”，但 FIX54 / FIX56 的透镜“唤起胶囊”有缺陷，比不上 FIX47（FIX47 的内缩以约 45° 接上外侧边框，FIX46 是 1.25 pt 的台阶）；FIX56 的末端处理“太机械、太狠”。FIX47 只在停到首尾标签时有一点粘连（截图里内部底栏连到透镜边、上下各一个小钩），用户要求“微修 47”。

FIX45–FIX57 每一版的说明都在 `ReferenceAnalysis/FIXnn_README_中文.md`，对应的压缩包用户手里都有。

## 项目是什么

微信（iOS 15.7 / 8.0.73，测试机 iPhone XS Max A12，60Hz）的 iOS 26 液态玻璃插件：底栏（4 个标签 + 透镜）、导航按钮、输入栏、菜单等改成液态玻璃。Theos 在手机上编译：`./build.sh rootless`。编译参数是 `-Wall -Wextra`，Theos 再加 `-Werror`：未使用的函数、变量，格式串与参数不符，结构体按位置初始化缺字段，都会直接编译失败（`WXGGlassView.m` 和网格测试按 FIX47 用文件级 pragma 关掉了缺字段警告，`WXGMeshOptics` 末尾的字段可以省略为 0）。不能用 `@available`（手机工具链缺 `__isPlatformVersionAtLeast`）。

## 架构（只剩同步模式）

- **玻璃** `WXGGlassView.m`：
  - 系统渲染的毛玻璃层（`CABackdropLayer`），每个颜色通道一层，带折射网格（`WXGMeshRefraction.h` 里的轮廓网格，按光学参数缓存）；
  - 材质遮盖：一层系统渲染的图层（FIX40 起常驻）；
  - 其上是 Metal 叠加层（`WXGGlass.metal`，运行时从 `WXGShaderSource.h` 编译），只画图标、描边、选中胶囊和透镜内容；
  - 同一块玻璃的底栏和透镜共用一个取样组（`_syncGroup`），取的是底栏下面的页面；
  - 图层顺序：底栏裁剪（毛玻璃 + 遮盖 + 叠加层）< 底栏边框 < 透镜裁剪（毛玻璃 + 叠加层）< 透镜边框。透镜里看不到底栏本身，透镜内的“内部底栏”全由着色器画。
- **底栏** `WXGDemoBar.m`：
  - 按下另一个标签：在渲染服务里浮起并滑到目标（`beginGlideToIndex`）；松手：落成胶囊（`dropTravel`）；拖动：交回逐帧跟手的透镜（`handOverTravelToFinger`）；拖到另一个标签松手：渲染服务里的落下动画（`beginTravelToIndex`）；
  - 动画期间 Metal 叠加层隐藏并停止绘制，结束时先画好静止状态，再瞬间交接；
  - 拖动形变见 `WXGElasticMotion.h`（FIX39 的手感，用户满意）。透镜停在首尾标签时外包底栏末端 `endWrap`（设置“首尾透镜外包距离”，2–10 pt，默认 4）。
- **宿主** `WXGHost.m`：路由和刷新、导航玻璃绑定、冷启动日志、逐帧归因（`dockProfile`）、预热、外观跟随页面、页面顶部底板清理（含钱包）。
- **图标** `WXGNativeIcons.m`。
- **设置**（FIX58 重写）：入口在微信“我 → 设置 → 微信 Liquid Glass”（推入页面），长按底栏会以弹出页打开。
  - `WXGSettingsKit.h`：共用接口。
  - `WXGSettings.m`：
    - `WXGSettingsStore`：强调色、卡片圆角、壁纸、头像；
    - `WXGSettingsCard`：玻璃卡片，`WXGGlassView` 设 `overlayHidden`，不用 Metal 画布；
    - `WXGSettingsPage`：页面框架，含壁纸、顶部三块玻璃、滚动内容、自己的显示刷新、取色器和图片选择器；
    - `WXGSettingsHome`：首页；
    - 原来的诊断页。
  - `WXGOpticalSettings.m`：
    - 7 个模块的规格表 `WXGModuleSpec`（每行带 `key`，分范围的行再带一个 `dock` 键）；
    - 行控件：滑杆、开关、颜色、操作、壁纸；
    - 模块页 `WXGSettingsModule`。
  - 键的前缀：`pref.` 写 `WXGPreferences`，`ui.` 写 `WXGSettingsStore`，没有前缀写 `WXGConfig`。
  - 页面类名都以 WXG 开头，宿主会当成“不支持”的页面，暂停自己的逐帧刷新。所以设置页从 `viewWillAppear` 到 `viewDidDisappear` 用自己的 `CADisplayLink`（`WXGSettingsTicker` 弱引用页面）驱动顶部按钮和卡片。卡片只在屏幕上时刷新玻璃（`WXGPresentedVisible`）；配置版本变了、尺寸变了而不在屏幕上的卡片会保持待刷新，滚进来时再更新。
  - 显示时隐藏微信导航栏。导航栏隐藏后系统左滑返回会失效，所以把它的代理换成 `WXGSettingsNavigationState`，只实现 `gestureRecognizerShouldBegin:`，有上一页就允许。微信原来的代理被强引用保存。
  - 这个对象挂在导航控制器上，还记着进入时导航栏是否隐藏。最后一个设置页离开时（顶部换成了非设置页；只是被弹出页盖住不算），把导航栏和代理都还原成进入前的样子；整个弹出页关闭时不处理。
  - 卡片刷新的规则：
    - 新出现的卡片立即刷新（`_glassNew`）；
    - 配置或尺寸变化引起的刷新每秒最多约 12 次（拖动滑杆时）；
    - 圆角按整数 pt 生效。
  - 取色器什么都不改就关闭时，不写入任何颜色。
  - 导入的图片在串行后台队列里缩放、编码、写文件。
  - 存储：
    - `com.runyu.WeChatLiquidGlass` 的 `settings.ui`：强调色、圆角；
    - 沙盒 `Library/Application Support/WeChatLiquidGlass/`：`settings-wallpaper-light.jpg`、`settings-wallpaper-dark.jpg`、`settings-avatar.png`。
- **底栏 / 其余玻璃拆分**（FIX58）：
  - `WXGConfig` 新增 15 个底栏参数：`dockRefraction`、`dockDispersion`、`dockEdgeWidth`、`dockBlur`、`dockBlurCoverage`，以及浅色、深色各一套的 `dock(Dark)RimHex`、`RimOpacity`、`BorderWidth`、`RimBrightness`、`RimFade`。原来的共用参数现在只给“其余玻璃”用。材质遮盖从 FIX29 起就分开了。
  - 读取方式：`opticsForDock:`、`rimForDock:dark:`、`rimHexForDock:dark:`；玻璃按 `_dockSurface` 选择。
  - 第一次启动时，底栏这套直接复制当时的共用值，所以外观不变。`reset` 两套都恢复。
  - 透镜的静止端（按压过渡的起点）、点按时滑过去的透镜（`WXGMakeTravelLensBackdrops`）都用底栏这一套。
  - 以后细分“其余玻璃”：再加一套属性和读取方法，在 `WXGModuleSpec` 里给行加对应的键，在模块页的范围切换里加一项。
- **清晰环遮罩**（FIX58）：`WXGGlassView updateEdgeMask` 用 `WXGFillRingMask`（`WXGEdgeMaskBand.h`）只算轮廓附近，其余填 0。结果与逐像素计算逐字节相同（`Tests/EdgeMaskBandTests.c`）。

## 当前效果

- **拖动 / 按住已选中标签时的透镜**（Metal 着色器 + 透镜的折射网格），FIX47：
  - 透镜里的底栏比外侧小（内缩，用户设置约 4.4 pt），内缩在“与内缩深度相同的距离”内完成，外侧边框以约 45° 接到内部边框（`WXGInnerInset`）；只被折射带弯曲、不放大；不做颜色分离；
  - 折射带：FIX21（两端宽、上下按比例窄；用户 FIX49 时两端 20.26、上下比例 0.305、透镜折射 4.21），每个像素在底栏外时 4 pt 内收到上下宽度（`WXGLensEdgeWidthAtBar`，图标、内部底栏、页面都用它）；
  - **FIX57 末端**：透镜外沿离底栏末端 10 pt 起，到越过末端 2 pt 止（smoothstep），这一半透镜弯曲**内部底栏和页面**的折射带放松到上下边宽度（`WXGLensEndReach` / `WXGLensEndRelax`），图标仍用 FIX47 的。停在首尾标签时总是完成：内部底栏露出圆头，和透镜边之间一圈缝。其余位置与 FIX47 逐像素相同。着色器每个像素从统一变量里算（统一变量结构没变），`WXGGlassView.m` 给页面网格算同一个值（1/8 取整，`WXGMeshOptics.endLeft/endRight`）。
- **点按另一个标签时滑过去的透镜、拖到另一个标签松手后的落下**（渲染服务里的 `_travelLens`）：FIX47 原样，里面的底栏和外面一样高，末端不放松。
- **头像、置顶**：FIX44 原样（FIX45–FIX47 的头像读取、无玻璃描边、置顶下移都撤掉了）。**钱包顶部**：FIX47 整页底色 + FIX50 列表可画到导航栏下方，用户已确认有效。

## 新对话先看：点按和拖动是两个不同的透镜

- **拖动 / 按住已选中的标签**：Metal 着色器画的透镜。毛玻璃层和底栏共用取样组，取的是底栏下面的页面，着色器在上面画内缩的底栏。
- **按下另一个标签（滑过去、按住不动）/ 松手落下**：`WXGDemoBar.m` 里渲染服务的透镜（为了滑动不掉帧）。毛玻璃层用自己的取样组 `wxg.travel`（`WXGMakeTravelLensBackdrops`，网格固定、整段动画不变），取到的是**含全高底栏**的画面，自己也不画内部底栏。
- **只改着色器或拖动透镜网格的效果，点按时都看不到**。FIX53 试过让点按透镜共用取样组、自己画内部底栏，用户说乱套了。

## 用户对透镜两端的要求（原话整理）

- 末端时应早已把缩小的内部底栏完全包进透镜，不能还延续到透镜外圈（“透镜外的部分”指透镜的外圈，也就是折射带，不是透镜外面）。
- 两端的折射范围要像上下边那样收敛；已经在折射的图标、文字按原来的范围完成折射，只有底栏不再参与新的折射。直线段结束后不再和透镜边框有连线；要“脱离原底栏的效果，而不是有粘连”。
- FIX56 之后：“改的是对的”，但“太机械、太狠”；以 FIX47 为底“微修”，FIX47“比较丝滑”，只需优化停到最右端时的那点粘连，“收敛折射范围到一个值就行”。
- 上下边的折射以 FIX43 / FIX44 为准，不要改坏。
- 参考：`ReferenceAnalysis/FIX52_iOS26_right_end_frames.png`、`FIX52_iOS26_separation_frames64-80.png`（iOS 26 录屏逐帧：第 70→74 帧右端折射带收掉）。

## FIX45–FIX57 试过什么（结论）

- FIX45：透镜内底栏边缘轻微色散开关 → 问题严重、关不掉（实为 FIX44 的分通道取样）。
- FIX46：去掉放大使内缩恢复、修锯齿、去掉底栏颜色分离。
- FIX47：内缩约 45°（外侧边框接到内部边框）、透镜端伸出底栏时折射带变窄 → 用户后来认为最丝滑，是 FIX57 的透镜底子；当时的头像 / 置顶改动无效，已撤回。
- FIX48：两端“交点进入圆弧即骤降”到 0。
- FIX49：45° 改为从交点列水平算，但把上下边一起改了 → 上下边折射带被改坏。
- FIX50：透镜整体回退到 FIX43 → 用户：不该整体回退；钱包列表可画到导航栏下方（保留）。
- FIX51：透镜只在首尾图标之间折射 → 太早停掉折射。
- FIX52：每侧“粘连 / 分离” → 用户指出内外同高（看的是点按透镜）。
- FIX53：点按透镜共用取样 + 自己画内部底栏 → 乱套。
- FIX54：FIX46 透镜 + FIX44 头像 / 置顶 + 钱包修复。
- FIX55：交点处 45° 连接曲线 + 末端吸入 + 收窄 → “差这么多”，连接和吸入都算粘连。
- FIX56：FIX54 + 交点进入圆弧后 3 pt 内把这一侧折射带收到上下宽度 → 方向对，但太机械、太狠；FIX54 透镜唤起胶囊不如 FIX47。
- FIX57：FIX47 + 末端放松 → 用户真机确认“基本没问题了”。
- FIX58：新设置界面 + 底栏 / 其余玻璃拆分（本版），待用户真机确认。

教训：先确认用户看到的是哪个透镜；按用户的尺寸和设置模拟出图（`tools/lens_ends_sim/`，用户截图的样子能复现出来）；一次只改一处；用户说“只改 X”就只改 X。

## 头像、置顶（待做，当前为 FIX44 原样）

- 聊天标题的头像模式：可以去掉头像背后的玻璃（或加开关）；读取对方或群聊的真实头像，大小可自定义；名字在头像下方（参照 iMessage）；关掉玻璃时描边画在头像圆形图片的边缘上，可调颜色、透明度、渐隐；
- 置顶栏要整体下移，不被头像和标题挡住，触摸和展开都要跟着走。
- 已知：首页会话的标题不是普通文字标签（名字可能是数学粗斜体字符）；FIX46 读到的“对方消息头像”是语音按钮；置顶栏 `MMMsgCommonTipsView` 不在聊天页控制器的视图里，位移变换、改位置、改安全区都失败过；`WXGDecorations.m` 已经找得到它（kind = `pinnedRow`），可以从那里入手。FIX45–FIX47 的做法见各自的 README。

## 已经定下来的（不要再改回去）

- 拖动形变：FIX39 的速度映射（900 pt/s）、范围 0.70–1.60、最窄到底栏高度的 90%。
- 点按切换：FIX95 起是真实透镜按脚本逐帧走（FIX43 时长和曲线），微信等透镜落下再切换；渲染服务里的做法（FIX33–FIX94）只作为“点按时用简化透镜”选项。用户明确说点按只是按设计好的速度和过程量自己走，不能换成别的东西。
- 冷启动：图标缓存、备用材质底板保留到第一帧、材质层层级检查。
- 透镜：FIX47 的 45° 内缩和伸出底栏变窄的折射带；钱包顶部：FIX47 + FIX50 的做法。

## 工作方式（每次改动后）

```bash
sh tools/test_geometry.sh                      # C 测试（-Wall -Wextra -Werror）
python3 tools/check_unused_statics.py          # 未使用的文件级 static（-Werror 下会编译失败）
python3 tools/embed_shader.py                  # 改了 WXGGlass.metal 后重新嵌入着色器
python3 tools/check_msl.py                     # 着色器的语法 / 类型检查（模拟 Metal 头文件，当 C++ 编译）
python3 tools/verify_fix58_scope.py <FIX57目录>     # 本版的来源校验
python3 tools/check_settings_coverage.py <FIX57目录> # FIX57 的设置项在新页面里都还在
python3 tools/settings_preview/render_fix58_preview.py   # 设置页布局示意图（与代码同一套尺寸）
python3 tools/lens_ends_sim/make_figures57.py  # 重画 ReferenceAnalysis/FIX57_* 对照图（numpy、scipy、Pillow、Noto CJK，约 2 分钟）
```

Objective-C 可以用真实 SDK 头文件做语义检查：`GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --filter=blob:none --no-checkout https://github.com/theos/sdks`，稀疏检出 `iPhoneOS16.5.sdk` 的 `usr/include`、`Frameworks/**/Headers`、`Frameworks/**/Modules`（约 88 MB），然后对每个 `.m`：`clang -x objective-c -target arm64-apple-ios14.0 -isysroot <sdk> -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -fsyntax-only -ISources <file>`。

另外：新加的局部变量、格式串要逐一核对；`WXGMeshOptics` 现在 19 个字段（FIX47 的 4 个底栏字段 + FIX57 的 2 个末端字段，0 = 关闭）；静态函数若在定义之前使用，要加前置声明。
