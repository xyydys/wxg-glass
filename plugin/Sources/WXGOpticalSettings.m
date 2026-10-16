#import "WXGSettingsKit.h"

// FIX58: the module pages behind the home cards. Every setting of the FIX57
// pages is here (tools/check_settings_coverage.py lists them). Four modules
// have two ranges: 底栏 (the dock and its lens) and 其余玻璃 (every other glass).

#pragma mark - Specs

static NSDictionary *WXGRow(NSString *type,NSString *title,NSString *key,NSString *dock) {
    NSMutableDictionary *row=[NSMutableDictionary dictionaryWithObjectsAndKeys:type,@"type",title,@"title",nil];
    if(key)row[@"key"]=key;
    if(dock)row[@"dock"]=dock;
    return row;
}
static NSDictionary *WXGSlider(NSString *title,NSString *key,NSString *dock,CGFloat lo,CGFloat hi,NSString *format) {
    NSMutableDictionary *row=[WXGRow(@"slider",title,key,dock) mutableCopy];
    row[@"min"]=@(lo);row[@"max"]=@(hi);row[@"format"]=format?:@"%.2f";return row;
}
static NSDictionary *WXGSwitch(NSString *title,NSString *key,NSString *dock) {return WXGRow(@"switch",title,key,dock);}
// FIX85: a row with a third key for the 气泡 range.
static NSDictionary *WXGBubbleKey(NSDictionary *row,NSString *bubble) {NSMutableDictionary *m=[row mutableCopy];m[@"bubble"]=bubble;return m;}
static NSDictionary *WXGSlider3(NSString *title,NSString *key,NSString *dock,NSString *bubble,CGFloat lo,CGFloat hi,NSString *format) {
    return WXGBubbleKey(WXGSlider(title,key,dock,lo,hi,format),bubble);
}
// FIX85: a segmented choice of an integer key; `rebuild` redraws the page
// (the groups shown depend on it). FIX86: with a key per range.
static NSDictionary *WXGChoice3(NSString *title,NSString *key,NSString *dock,NSString *bubble,NSArray<NSString *> *choices,BOOL rebuild) {
    NSMutableDictionary *row=[WXGBubbleKey(WXGRow(@"choice",title,key,dock),bubble) mutableCopy];row[@"choices"]=choices;row[@"rebuild"]=@(rebuild);return row;
}
static NSDictionary *WXGColorRow(NSString *title,NSString *key,NSString *dock) {return WXGRow(@"color",title,key,dock);}
static NSDictionary *WXGColor3(NSString *title,NSString *key,NSString *dock,NSString *bubble) {return WXGBubbleKey(WXGColorRow(title,key,dock),bubble);}
static NSDictionary *WXGAction(NSString *title,NSString *action,BOOL destructive) {
    NSMutableDictionary *row=[WXGRow(@"action",title,nil,nil) mutableCopy];row[@"action"]=action;row[@"destructive"]=@(destructive);return row;
}
static NSDictionary *WXGWallpaperRow(NSString *title,BOOL dark) {
    NSMutableDictionary *row=[WXGRow(@"wallpaper",title,nil,nil) mutableCopy];row[@"dark"]=@(dark);return row;
}
// scope nil: shown in both ranges; @"dock" / @"other": only there. A row's
// "dock" key replaces its key while the 底栏 range is selected.
static NSDictionary *WXGGroup(NSString *title,NSString *scope,NSArray *rows,NSString *footer) {
    NSMutableDictionary *group=[NSMutableDictionary dictionaryWithObject:rows forKey:@"rows"];
    if(title)group[@"title"]=title;
    if(scope)group[@"scope"]=scope;
    if(footer)group[@"footer"]=footer;
    return group;
}
// FIX85: a group shown only for these rim styles (边框与渐隐). FIX86: the
// style of the range selected on the page.
static NSDictionary *WXGStyled(NSDictionary *group,NSArray<NSNumber *> *styles) {NSMutableDictionary *m=[group mutableCopy];m[@"styles"]=styles;return m;}
static NSDictionary *WXGModuleSpec(NSString *module) {
    if([module isEqual:@"basic"])return @{@"title":@"基本设置",@"groups":@[
        WXGGroup(@"适配",nil,@[WXGSwitch(@"顶部按钮与背景适配",@"pref.nav",nil),WXGSwitch(@"真实悬浮标签栏",@"pref.dock",nil),
                              WXGSwitch(@"聊天悬浮输入栏",@"pref.input",nil),WXGSwitch(@"原生宽度三端输入（测试）",@"pref.nativeInputTest",nil)],
                 @"总开关在设置首页卡片的右侧，关闭后恢复微信原控件。默认是 TEST4 双端输入栏；三端输入测试默认关闭，开启后保留原生输入宽度和动作，单行三段等高，多行只增高中间。"),
        WXGGroup(@"标题与比例",nil,@[WXGSwitch(@"聊天标题使用头像 + 小胶囊",@"pref.avatarTitle",nil),
                                  WXGSlider(@"截图比例微调",@"pref.sizeScale",nil,.85,1.20,@"%.2f")],
                 @"默认标题是与两侧等高的自适应胶囊。头像模式找不到现有真实头像时显示灰底白色人像的占位图。原生未读数决定返回圆形或长胶囊。比例同时作用于这几页顶部的按钮。"),
        WXGGroup(@"头像模式",nil,@[WXGSlider(@"头像大小",@"avatarSize",nil,32,88,@"%.0f pt"),WXGSlider(@"头像上下位置",@"avatarOffsetY",nil,-24,24,@"%+.1f pt"),
                                WXGSlider(@"头像描边宽度",@"avatarBorderWidth",nil,0,4,@"%.2f pt"),
                                WXGColorRow(@"头像描边颜色（浅色模式）",@"avatarBorderHex",nil),WXGColorRow(@"头像描边颜色（深色模式）",@"avatarDarkBorderHex",nil)],
                 @"FIX95：打开上面的“聊天标题使用头像 + 小胶囊”后生效。头像没有玻璃，整圆铺满，在标题胶囊上面一层。大小按头像自己的中心缩放，标题胶囊位置不变；上下位置正数往下。描边画在头像圆形的内侧，颜色可以带透明度，浅色、深色各一个；宽度 0 为不描边。"),
        WXGGroup(@"交互",nil,@[WXGSwitch(@"触感反馈",@"haptics",nil),WXGSwitch(@"按住拖动拉伸玻璃按钮",@"pressStretch",nil),WXGSwitch(@"首页左上角和三段输入两侧也拉伸",@"pressStretchNative",nil),
                             WXGSlider(@"最大拉动距离",@"pressStretchDistance",nil,0,32,@"%.0f pt"),WXGSlider(@"拉伸强度",@"pressStretchAmount",nil,0,1.5,@"%.2f"),
                             WXGSlider(@"最大拉伸幅度",@"pressStretchMax",nil,1,20,@"%.1f pt"),WXGSlider(@"胶囊拉伸程度",@"pressStretchCapsule",nil,0,1,@"%.2f"),
                             WXGSlider(@"跟手移动",@"pressStretchFollow",nil,0,1,@"%.2f")],
                 @"按住导航按钮、标题、输入栏两侧的按钮、首页左上角按钮或底栏搜索按钮再拖动：玻璃朝手指方向拉长、另一个方向变窄（远离手指的一侧几乎不动，靠近手指的一侧伸出去），整体再跟着手指移动一点。拉动距离越拉越难，最多按“最大拉动距离”算（按 44 pt 的按钮算，小一点和大一点的按钮按比例）；拉伸强度是每拉 1 pt 拉长多少 pt（变窄是一半）；最大拉伸幅度是最多拉长多少 pt，越接近越拉不动；跟手移动是玻璃跟着手指移动拉动距离的多少（0 就是原地不动，1 是完全跟手），移动和拉伸来自同一个拉动距离，拉得越远两者都越大。胶囊、圆角矩形这类不是圆的玻璃只沿上下、左右拉伸，不会斜着变形，程度是圆形按钮的“胶囊拉伸程度”倍。手指按住期间一直拉着，松手才用弹簧弹回（会过冲一下）；在按钮 40 pt 以内松手是点击，更远就是放弃点击。首页左上角按钮和三段输入两侧的触摸仍由微信处理，上面微信自己的图标也跟着玻璃一起变形（只是画面跟着变，点击位置不受影响）。输入文字的那块胶囊（两种输入栏都是）固定不动：点按、拖动都不放大、不拉伸，点它里面的按钮只有按钮图标自己有按下效果。系统“减弱动态效果”打开时不拉伸。关掉“按住拖动拉伸玻璃按钮”就完全没有拉伸，回到原来按下微微放大的效果；只关“首页左上角和三段输入两侧也拉伸”时，这几处只保留按下效果，其余按钮照常拉伸。"),
        WXGGroup(@"消息长按菜单",nil,@[WXGSlider(@"菜单圆角",@"messageMenuCornerRadius",nil,0,40,@"%.0f pt")],
                 @"长按消息弹出菜单的玻璃圆角。若微信的菜单容器本身裁剪了更小的圆角，以较小者为准。"),
        WXGGroup(@"性能",nil,@[WXGSwitch(@"流畅模式",@"performanceMode",nil)],
                 @"每块玻璃只用一层背景：不做 RGB 色散和边缘清晰环，背景最多按 2 倍采样（原来最多 6 层、按屏幕倍数）。滑动或转场卡顿、发热时打开对比；关闭时与之前完全一样。设置页的卡片始终是这种画法。"),
        WXGGroup(@"诊断",nil,@[WXGAction(@"材质、位置与性能诊断",@"diagnostics",NO),WXGAction(@"导出各页诊断 JSON",@"export",NO)],nil),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本版默认参数",@"reset",YES)],
                 @"恢复折射、模糊、材质、边框、底栏、触感反馈和菜单圆角（底栏与其余玻璃都恢复）；上面的适配开关、截图比例、总开关，以及壁纸、圆角和强调色不变，也不覆写旧 demo 的 config.v9。")]};
    if([module isEqual:@"refraction"])return @{@"title":@"折射强度和色散",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"bubble"],@"groups":@[
        WXGGroup(@"底栏本体",@"dock",@[WXGSlider(@"折射强度",@"dockRefraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"dockDispersion",nil,0,8,nil),
                                      WXGSlider(@"折射宽度",@"dockEdgeWidth",nil,1,60,@"%.1f pt")],
                 @"底栏静止时的玻璃。按下时透镜从这里平滑过渡到下面的透镜参数。"),
        WXGGroup(@"透镜（按压时）",@"dock",@[WXGSlider(@"透镜折射强度",@"lensRefraction",nil,0,20,nil),WXGSlider(@"透镜 RGB 色散",@"lensDispersion",nil,0,8,nil),
                                         WXGSlider(@"透镜折射宽度（两端）",@"lensEdgeWidth",nil,1,60,@"%.1f pt"),
                                         WXGSlider(@"上下折射宽度比例",@"lensTopEdgeRatio",nil,.1,1,nil),
                                         WXGSlider(@"上下收窄曲线",@"lensEdgeSharpness",nil,1,6,nil),
                                         WXGSlider(@"透镜色散范围（两端）",@"lensDispersionWidth",nil,1,60,@"%.1f pt"),
                                         WXGSlider(@"上下色散范围比例",@"lensDispersionTopRatio",nil,.1,1,nil),
                                         WXGSwitch(@"镜内底栏贴着透镜边缘",@"lensBarFollowOn",nil),
                                         WXGSlider(@"镜内底栏离边缘（折射宽度的比例）",@"lensBarMargin",nil,.2,1,nil)],
                 @"透镜的边框（FIX96）：透镜和选中胶囊用系统的连续圆角（iOS 的形状）；着色器算折射、透镜里的底栏和描边时，也按在你手机上量出的连续圆角曲线走（以前按圆形算，在顶边转进圆角处和系统外框差约 0.4 pt，看起来边框在圆角处最细、顶上又变宽），所以边框从两端到上下边一路变窄，上下最细。镜内底栏贴着透镜边缘（FIX94，FIX95 起默认关闭）：透镜比底栏高，上下折射宽度收窄以后，透镜中间平的部分原样显示底栏，上下会露出一条深色的槽，中间最粗、圆角处没有。打开后透镜里的底栏按列上下放大，上下边停在离透镜边缘“折射宽度 × 这个比例”的地方：深色边框上下最细、往圆角处变粗，透镜里的底栏接近椭圆；和底栏的衔接仍是 45°，到底栏两端照常脱离。比例越小越贴边；透镜的一端压在底栏两端的圆头上时，圆头也不会越过透镜边缘。关闭恢复原来的折射做法。只在同步渲染模式下生效。透镜的折射和色散独立于底栏本体。上下比例 1 为与两端相同；收窄曲线越大，离开两端越快收窄。到底栏两端时，弯曲底栏和页面的折射范围放松到上下边的宽度（FIX57）。色散有自己的范围（FIX88，像 iOS 26 的透镜）：从轮廓往里多宽内有颜色分离，可以比折射宽度更宽或更窄，上下同样按比例收窄（收窄曲线和折射共用）；第一次打开时和折射宽度、上下比例相同，看起来不变。"),
        WXGGroup(@"镜内底栏色散",@"dock",@[WXGSwitch(@"镜内底栏边缘色散",@"lensBarDispersionOn",nil),
                                       WXGSlider(@"整片透镜的色散（边缘处）",@"lensBarDispersion",nil,0,2,@"%.2f pt"),
                                       WXGSlider(@"两端加强（透镜色散的比例）",@"lensBarDispersionNearRim",nil,0,1,nil)],
                 @"FIX97：透过透镜看到的底栏也有色散，不只透镜两端：上下深色槽的“括号”边、底栏的描边高光，都会按连续光谱散开成一圈柔和的彩边（外侧偏红、内侧偏蓝，不是三条分开的红绿蓝线）。“整片透镜的色散”像一块圆顶玻璃：透镜中心为 0，越往边缘越大，这里填的是到透镜边缘时的偏移；“两端加强”是在透镜折射底栏最厉害的地方（两端宽的折射带，上下随折射宽度比例变弱）再加上透镜自身色散的这个比例，所以靠近两端最明显。只在按下（透镜浮起）时出现，松开随按压程度消失；两个都调到 0 或关闭开关，和 FIX96 完全一样。只在同步渲染模式下生效。"),
        WXGGroup(@"其余玻璃",@"other",@[WXGSlider(@"折射强度",@"refraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"dispersion",nil,0,8,nil),
                                       WXGSlider(@"折射宽度",@"edgeWidth",nil,1,60,@"%.1f pt")],
                 @"折射宽度是从轮廓向内的距离，范围外不位移。"),
        WXGGroup(@"液态气泡",@"bubble",@[WXGSlider(@"折射强度",@"bubbleRefraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"bubbleDispersion",nil,0,8,nil),
                                       WXGSlider(@"折射宽度",@"bubbleEdgeWidth",nil,1,60,@"%.1f pt"),WXGSwitch(@"气泡用完整玻璃",@"bubbleFullGlass",nil)],
                 @"聊天里液态气泡自己的折射，第一次打开时和“其余玻璃”相同。气泡默认是轻量玻璃（一层背景，没有 RGB 色散和边缘清晰环，最多 2 倍采样），所以色散要打开“气泡用完整玻璃”才看得到；完整玻璃每个气泡最多 6 层背景，消息多时滑动更吃力，可以用帧率检测对比。"),
        WXGGroup(@"色散方式",nil,@[WXGSwitch(@"RGB 色散",@"syncDispersion",nil)],
                 @"用红绿蓝三层背景实现色散，三种范围共用。若玻璃整体偏色可关闭。")]};
    if([module isEqual:@"blur"])return @{@"title":@"模糊强度与范围",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"bubble"],@"groups":@[
        WXGGroup(@"底栏本体",@"dock",@[WXGSlider(@"模糊半径",@"dockBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"dockBlurCoverage",nil,0,100,@"%.0f%%")],nil),
        WXGGroup(@"透镜（按压时）",@"dock",@[WXGSlider(@"透镜模糊半径",@"lensBlur",nil,0,12,@"%.2f pt"),
                                         WXGSlider(@"透镜模糊覆盖扩展",@"lensBlurCoverage",nil,0,100,@"%.0f%%")],
                 @"透镜模糊默认 0（关闭）。按下时从底栏本体的模糊平滑过渡到这里。"),
        WXGGroup(@"其余玻璃",@"other",@[WXGSlider(@"模糊半径",@"blur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"blurCoverage",nil,0,100,@"%.0f%%")],
                 @"仍是 TEST9 的半径与覆盖扩展。"),
        WXGGroup(@"液态气泡",@"bubble",@[WXGSlider(@"模糊半径",@"bubbleBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"bubbleBlurCoverage",nil,0,100,@"%.0f%%")],
                 @"液态气泡自己的模糊，第一次打开时和“其余玻璃”相同。"),
        WXGGroup(@"清晰度",nil,@[WXGSlider(@"模糊倍率",@"syncBlurScale",nil,.5,3,nil),WXGSlider(@"采样倍率",@"syncCaptureScale",nil,0,3,nil)],
                 [NSString stringWithFormat:@"三种范围共用。模糊倍率把 TEST9 模糊半径换算成系统高斯。采样倍率 0 = 跟随屏幕（本机 %.0f，设成 %.0f 与 0 相同）；调低能减轻 GPU 负担，但会变糊。",
                  UIScreen.mainScreen.scale,UIScreen.mainScreen.scale])]};
    if([module isEqual:@"material"])return @{@"title":@"材质强度与范围",@"scoped":@YES,@"groups":@[
        WXGGroup(@"边缘减弱",nil,@[WXGSwitch(@"在边缘减弱",@"materialEdgeFadeEnabled",@"dockMaterialEdgeFadeEnabled"),
                                 WXGSlider(@"减弱范围",@"materialEdgeFade",@"dockMaterialEdgeFade",0,60,@"%.1f pt")],
                 @"开启后，材质遮盖从玻璃轮廓开始在“减弱范围”内由弱到强，范围以内完全覆盖；关闭或范围为 0 时整块完全覆盖。"),
        WXGGroup(@"浅色模式",nil,@[WXGColorRow(@"材质底色",@"materialHex",@"dockMaterialHex"),
                                 WXGSlider(@"材质遮盖",@"materialOpacity",@"dockMaterialOpacity",0,.95,nil)],nil),
        WXGGroup(@"深色模式",nil,@[WXGColorRow(@"材质底色",@"darkMaterialHex",@"dockDarkMaterialHex"),
                                 WXGSlider(@"材质遮盖",@"darkMaterialOpacity",@"dockDarkMaterialOpacity",0,.95,nil)],nil),
        WXGGroup(@"平稳背景",nil,@[WXGSwitch(@"平稳背景时加强材质",@"calmMaterial",nil),
                                 WXGSlider(@"平稳时材质遮盖 · 浅色",@"calmMaterialOpacity",@"dockCalmMaterialOpacity",0,.98,nil),
                                 WXGSlider(@"平稳时材质遮盖 · 深色",@"darkCalmMaterialOpacity",@"dockDarkCalmMaterialOpacity",0,.98,nil),
                                 WXGSlider(@"判定阈值",@"calmThreshold",nil,.005,.4,@"%.3f"),WXGSlider(@"过渡范围",@"calmRange",nil,.005,.4,@"%.3f"),
                                 WXGAction(@"查看当前背景变化程度",@"calmShow",NO)],
                 @"打开后，插件每隔零点几秒把每块玻璃后面那一小块背景缩小画一遍，量它的颜色变化程度（颜色的标准差：纯色是 0，文字页一般零点零几，照片、壁纸 0.1 以上）。低于“判定阈值”算平稳，材质遮盖用这里的“平稳时”值（底栏和其余玻璃各一套）；高于“阈值 + 过渡范围”还是上面原来的遮盖；中间平滑过渡，变化时用一秒多慢慢过去，不会一闪一闪。微信的大多数页面是纯色或文字，会接近不透明；聊天背景图、朋友圈封面这类图片后面保持原来的通透。液态气泡、视频号按钮和设置页的卡片不参与。关掉时完全不测量。每次测量的耗时在帧率日志和诊断里（calm）。"),
        WXGGroup(@"通用",nil,@[WXGSwitch(@"清透材质",@"clearMaterial",nil)],@"两种范围共用。关闭时材质遮盖加强约 22%。")]};
    // FIX85: three rim styles, each with its own values (only the chosen
    // style's groups are shown), in three ranges: dock, other glass, bubbles.
    // FIX86: each range has its own style.
    if([module isEqual:@"border"])return @{@"title":@"边框与渐隐",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"bubble"],@"groups":@[
        WXGGroup(@"边框样式",nil,@[WXGChoice3(@"样式",@"rimStyle",@"dockRimStyle",@"bubbleRimStyle",@[@"普通",@"取自背景",@"iOS 27"],YES)],
                 @"底栏、其余玻璃、气泡三个范围各选各的样式（上面切换范围），互不影响：比如底栏用 iOS 27、其余玻璃取自背景、气泡用普通。三种样式各用各的参数，互不共享，下面只显示当前范围所选样式的设置（换样式时，其它样式的值保持不变）。普通：一条等宽的线，颜色自己定。取自背景：线的颜色来自玻璃后面的背景，不透明度、宽度、亮度、渐隐都是它自己的。iOS 27：不是一条线，而是两道沿轮廓往里渐渐消失的光，各有颜色和最亮的方向，同时画（不分浅色、深色）。普通和取自背景浅色、深色各一套；视频号顶部的按钮在视频上，不管系统浅色还是深色，都用所选样式的深色模式那套（iOS 27 两种外观本来就一样）。底栏透镜（选中胶囊）的边框不随样式变，在“底栏”范围最下面。"),
        WXGStyled(WXGGroup(@"普通 · 浅色模式",nil,@[WXGColor3(@"边框颜色",@"rimHex",@"dockRimHex",@"bubbleRimHex"),
                                 WXGSlider3(@"不透明度",@"rimOpacity",@"dockRimOpacity",@"bubbleRimOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"barBorderWidth",@"dockBorderWidth",@"bubbleBorderWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"亮度",@"rimBrightness",@"dockRimBrightness",@"bubbleRimBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"rimFade",@"dockRimFade",@"bubbleRimFade",0,1,nil)],
                 @"亮度 1 为原色，低于 1 变暗，高于 1 向白色混合。渐隐只在左下和右上两条对角（iOS 26 的描边）。"),@[@0]),
        WXGStyled(WXGGroup(@"普通 · 深色模式",nil,@[WXGColor3(@"边框颜色",@"darkRimHex",@"dockDarkRimHex",@"bubbleDarkRimHex"),
                                 WXGSlider3(@"不透明度",@"darkRimOpacity",@"dockDarkRimOpacity",@"bubbleDarkRimOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"darkBarBorderWidth",@"dockDarkBorderWidth",@"bubbleDarkBorderWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"亮度",@"darkRimBrightness",@"dockDarkRimBrightness",@"bubbleDarkRimBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"darkRimFade",@"dockDarkRimFade",@"bubbleDarkRimFade",0,1,nil)],nil),@[@0]),
        WXGStyled(WXGGroup(@"取自背景 · 浅色模式",nil,@[WXGSlider3(@"不透明度",@"rimSampleOpacity",@"dockRimSampleOpacity",@"bubbleRimSampleOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"rimSampleWidth",@"dockRimSampleWidth",@"bubbleRimSampleWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"亮度",@"rimSampleBrightness",@"dockRimSampleBrightness",@"bubbleRimSampleBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"rimSampleFade",@"dockRimSampleFade",@"bubbleRimSampleFade",0,1,nil),
                                 WXGSlider(@"饱和度",@"rimSampleSaturation",nil,0,3,nil),
                                 WXGSlider(@"亮度增益",@"rimSampleGain",nil,.5,2.5,nil),
                                 WXGSlider(@"提亮（变浅）",@"rimSampleLift",nil,0,.6,nil),
                                 WXGSlider(@"对比度",@"rimSampleContrast",nil,.5,2,nil),
                                 WXGSlider(@"取色模糊",@"rimSampleBlur",nil,0,10,@"%.1f pt")],
                 @"线的颜色取自这块玻璃后面的背景（先模糊，免得文字的细节透出来），再处理：饱和度让颜色更鲜艳，亮度增益按比例变亮，提亮往白色靠（变浅），对比度 1 为不变。不透明度、宽度、亮度、渐隐是这个样式自己的，底栏、其余玻璃、气泡各一套；饱和度到取色模糊几项三个范围共用。液态气泡、底栏透镜和设置页的卡片没有自己的背景取色，用材质颜色按同样的参数处理。"),@[@1]),
        WXGStyled(WXGGroup(@"取自背景 · 深色模式",nil,@[WXGSlider3(@"不透明度",@"darkRimSampleOpacity",@"dockDarkRimSampleOpacity",@"bubbleDarkRimSampleOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"darkRimSampleWidth",@"dockDarkRimSampleWidth",@"bubbleDarkRimSampleWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"亮度",@"darkRimSampleBrightness",@"dockDarkRimSampleBrightness",@"bubbleDarkRimSampleBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"darkRimSampleFade",@"dockDarkRimSampleFade",@"bubbleDarkRimSampleFade",0,1,nil),
                                 WXGSlider(@"饱和度",@"darkRimSampleSaturation",nil,0,3,nil),
                                 WXGSlider(@"亮度增益",@"darkRimSampleGain",nil,.5,2.5,nil),
                                 WXGSlider(@"提亮（变浅）",@"darkRimSampleLift",nil,0,.6,nil),
                                 WXGSlider(@"对比度",@"darkRimSampleContrast",nil,.5,2,nil),
                                 WXGSlider(@"取色模糊",@"darkRimSampleBlur",nil,0,10,@"%.1f pt")],nil),@[@1]),
        WXGStyled(WXGGroup(@"取自背景 · 叠加",nil,@[WXGSwitch(@"加亮叠加",@"rimSamplePlusLighter",nil)],@"打开后取到的颜色加在玻璃上（更亮），关闭时直接画成线。"),@[@1]),
        WXGStyled(WXGGroup(@"描边细节",nil,@[WXGSwitch(@"描边细节",@"rimDetails",nil)],
                 @"普通和取自背景两种样式可用（iOS 27 样式没有）。在原来的线上加细节，线和阴影都用边框自己的形状（系统的连续圆角）。外侧 / 内侧消散宽度：线从外轮廓往里、从内边往外各用多宽来过渡，每 0.1 pt 一级；两侧最外处强度：最外那一级剩多少（1 为不消散）。默认是透明度减弱；打开“两侧改为变暗”则改为颜色变暗。内侧阴影：线的里面一圈往内慢慢变淡的阴影。三个范围共用，浅色、深色各一套；底栏透镜保持原来的描边。"),@[@0,@1]),
        WXGStyled(WXGGroup(@"描边细节 · 浅色模式",nil,@[WXGSlider(@"外侧消散宽度",@"rimOuterFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"内侧消散宽度",@"rimInnerFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"两侧最外处强度",@"rimSideLevel",nil,0,1,nil),
                                 WXGSwitch(@"两侧改为变暗",@"rimSideDarken",nil),
                                 WXGColorRow(@"内侧阴影颜色",@"rimInnerShadowHex",nil),
                                 WXGSlider(@"内侧阴影浓度",@"rimInnerShadowOpacity",nil,0,.6,nil),
                                 WXGSlider(@"内侧阴影柔和度",@"rimInnerShadowRadius",nil,.3,6,@"%.1f pt")],nil),@[@0,@1]),
        WXGStyled(WXGGroup(@"描边细节 · 深色模式",nil,@[WXGSlider(@"外侧消散宽度",@"darkRimOuterFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"内侧消散宽度",@"darkRimInnerFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"两侧最外处强度",@"darkRimSideLevel",nil,0,1,nil),
                                 WXGSwitch(@"两侧改为变暗",@"darkRimSideDarken",nil),
                                 WXGColorRow(@"内侧阴影颜色",@"darkRimInnerShadowHex",nil),
                                 WXGSlider(@"内侧阴影浓度",@"darkRimInnerShadowOpacity",nil,0,.6,nil),
                                 WXGSlider(@"内侧阴影柔和度",@"darkRimInnerShadowRadius",nil,.3,6,@"%.1f pt")],nil),@[@0,@1]),
        WXGStyled(WXGGroup(@"iOS 27 · 高光一",nil,@[WXGColor3(@"颜色",@"rim27Hex",@"dockRim27Hex",@"bubbleRim27Hex"),
                                 WXGSlider3(@"不透明度",@"rim27Opacity",@"dockRim27Opacity",@"bubbleRim27Opacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"rim27Width",@"dockRim27Width",@"bubbleRim27Width",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"rim27Falloff",@"dockRim27Falloff",@"bubbleRim27Falloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"rim27Angle",@"dockRim27Angle",@"bubbleRim27Angle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"rim27EndLevel",@"dockRim27EndLevel",@"bubbleRim27EndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"rim27Sharpness",@"dockRim27Sharpness",@"bubbleRim27Sharpness",0.5,6,nil)],
                 @"iOS 27 的边框是两道同时存在的光，各有自己的颜色和方向（比如一道白的在上下边、一道深色的在两端），不分浅色、深色模式，两种外观都同时画两道。每一道都是从玻璃轮廓往里渐渐消失的光：最外圈最亮，往里在“渐隐宽度”内淡到没有；四周宽度处处一样（圆角处和上下一样宽），外边就是玻璃自己的轮廓（系统的连续圆角）。向内渐隐曲线：1 是均匀变淡，越大越快变淡（光贴着轮廓更细），小于 1 则亮的部分往里更宽。高光方向：这一道哪里最亮。0° 上下边最亮、往左右两端减弱；90° 左右两端最亮、往上下减弱；45° 左上和右下最亮，135° 右上和左下最亮。最暗处亮度：这一道最暗的地方减弱到这个比例（0 完全没有，1 一圈一样亮）。过渡速度：从最亮处往最暗处减弱的快慢，越大亮的部分越集中；1 随角度均匀减弱。只要一道时把另一道的不透明度调到 0。高光二画在高光一上面。升级后高光一是原来“浅色模式”那组的设置，高光二是原来“深色模式”那组的。底栏透镜里看到的底栏轮廓也按这两道画。"),@[@2]),
        WXGStyled(WXGGroup(@"iOS 27 · 高光二",nil,@[WXGColor3(@"颜色",@"darkRim27Hex",@"dockDarkRim27Hex",@"bubbleDarkRim27Hex"),
                                 WXGSlider3(@"不透明度",@"darkRim27Opacity",@"dockDarkRim27Opacity",@"bubbleDarkRim27Opacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"darkRim27Width",@"dockDarkRim27Width",@"bubbleDarkRim27Width",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"darkRim27Falloff",@"dockDarkRim27Falloff",@"bubbleDarkRim27Falloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"darkRim27Angle",@"dockDarkRim27Angle",@"bubbleDarkRim27Angle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"darkRim27EndLevel",@"dockDarkRim27EndLevel",@"bubbleDarkRim27EndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"darkRim27Sharpness",@"dockDarkRim27Sharpness",@"bubbleDarkRim27Sharpness",0.5,6,nil)],
                 nil),@[@2]),
        WXGGroup(@"浅色模式 · 透镜",@"dock",@[WXGColorRow(@"边框颜色",@"lensRimHex",nil),WXGSlider(@"不透明度",@"lensRimOpacity",nil,0,1,nil),
                                         WXGSlider(@"宽度",@"lensBorderWidth",nil,0,2,@"%.2f pt")],@"透镜边框（选中胶囊）不随边框样式变；亮度和渐隐沿用当前样式底栏的设置。"),
        WXGGroup(@"深色模式 · 透镜",@"dock",@[WXGColorRow(@"边框颜色",@"darkLensRimHex",nil),WXGSlider(@"不透明度",@"darkLensRimOpacity",nil,0,1,nil),
                                         WXGSlider(@"宽度",@"darkLensBorderWidth",nil,0,2,@"%.2f pt")],nil),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 @"这一页的全部设置（三种样式、三个范围、浅色和深色、描边细节、透镜边框）回到默认值；其它页不变。")]};
    if([module isEqual:@"dock"])return @{@"title":@"底栏",@"groups":@[
        WXGGroup(@"尺寸",nil,@[WXGSlider(@"底栏宽度比例",@"widthFraction",nil,.65,.98,nil),WXGSlider(@"底栏高度",@"height",nil,54,90,@"%.1f pt"),
                             WXGSlider(@"底边相对安全区",@"lift",nil,-80,160,@"%.1f pt")],@"lift"),
        WXGGroup(@"离散样式",nil,@[WXGSwitch(@"离散底栏",@"dockDiscrete",nil),
                                 WXGSwitch(@"未选中的小球连成一体",@"dockDiscreteConnected",nil),
                                 WXGSlider(@"相连时图标向中间收拢",@"dockDiscreteGather",nil,0,.45,@"%.2f"),
                                 WXGSwitch(@"选中项加原选中胶囊",@"dockDiscretePill",nil),
                                 WXGSlider(@"间距",@"dockDiscreteGap",nil,0,24,@"%.1f pt"),
                                 WXGSlider(@"选中项占位",@"dockDiscreteWide",nil,1,3,@"%.2f 格"),
                                 WXGSlider(@"小球直径（相对底栏高度）",@"dockDiscreteBall",nil,.6,1.3,@"%.2f"),
                                 WXGSlider(@"图标大小",@"dockDiscreteIconSize",nil,20,40,@"%.1f pt"),
                                 WXGSlider(@"中文标题字号",@"dockDiscreteTitleSize",nil,10,20,@"%.1f pt"),
                                 WXGSlider(@"英文标题字号",@"dockDiscreteSubtitleSize",nil,8,16,@"%.1f pt"),
                                 WXGSlider(@"宽位内容左移",@"dockDiscreteContentShift",nil,0,30,@"%.1f pt"),
                                 WXGSlider(@"弹簧阻尼",@"dockDiscreteDamping",nil,.45,1,@"%.2f"),
                                 WXGSlider(@"弹簧响应",@"dockDiscreteResponse",nil,.2,1,@"%.2f s"),
                                 WXGSwitch(@"各块用轻量玻璃",@"dockDiscreteLight",nil)],
                 @"离散底栏：选中的标签是一块宽胶囊（左边图标，右边上中文、下英文），其余标签各是一个只有图标的小球，每块都是独立的底栏玻璃（材质、折射和边框都用“底栏”范围的设置）。切换时所有标签的宽度一起走同一个阻尼弹簧：旧的收成小球、新的展开，整行总宽不变、不会左右漂；回弹时新的会略微超宽、旧的略微被挤窄。未选中的小球连成一体：相邻两个小球之间的间距被玻璃填上，连成一整块（位置不变，只是间隙连上）；切换一开始，旧选中项就一边收窄一边并入两旁，新选中项一边展开一边分出来，约在弹簧响应的 0.35 倍时连成一块（默认约 0.16 s），不等动画结束。相连时图标向中间收拢：连成一块的小球，图标按这个比例往这一块的中间靠（0 = 停在各自小球的中心；默认 0.22，图标间距缩到 0.78 格，两连和三连间距一样），两端圆头处留出更多空间，跟着弹簧滑过去，角标跟着图标走。图标大小、中文 / 英文标题字号只管离散底栏（连续底栏的文字设置在“图标与文字”里），粗细跟随那里的“文字粗细”；文字放不下时自动缩小。宽位内容左移：宽胶囊里图标和标题整体居中后再往左挪这么多（0 = 正中，默认 10 pt），最多挪到图标落在左端圆头正中为止，小球时不偏。未读角标在每块胶囊的右上角，跟着胶囊宽窄移动。选中项加原选中胶囊：在宽胶囊里加上原来底栏的选中胶囊（透镜、底色和边框，颜色和内边距用下面“选中胶囊”的设置），切换时它从中心长出来、在旧的那块里缩没。间距：块与块之间。选中项占位：选中项占几格（2 格 = 两个小球加中间的间距那么宽；1 格时只放大图标不显示文字）。小球直径：相对底栏高度，整行放不下时自动缩小以塞进底栏宽度；调大可让整行铺满。弹簧阻尼越小回弹越明显（0.6 约等于参考效果，1 不回弹）；弹簧响应越小越快。有搜索按钮时整行靠向搜索按钮那一边。打开搜索时变回连续底栏完成变形（两者交叉淡化），关闭后再回到离散样式。各块用轻量玻璃：每块只用一层背景、不分色散通道，省电但少了色散和边缘环。"),
        WXGGroup(@"搜索",nil,@[WXGSwitch(@"底栏搜索按钮",@"pref.dockSearch",nil),WXGSwitch(@"搜索按钮放在左边",@"pref.dockSearchLeading",nil),
                             WXGSlider(@"两块玻璃的间距",@"dockSearchGap",nil,2,40,@"%.1f pt"),
                             WXGSlider(@"搜索时高度（相对底栏）",@"dockSearchHeightRatio",nil,.55,1,@"%.2f"),
                             WXGSlider(@"搜索时整行宽度比例",@"dockSearchWidthFraction",nil,.65,.98,nil),
                             WXGSwitch(@"隐藏聊天列表顶部搜索栏",@"pref.hideTopSearch",nil)],
                 @"平时底栏宽度比例是整行：标签栏、间距和圆形搜索按钮。点搜索按钮，搜索框总在左边、关闭按钮总在右边：按钮在左时它展开成搜索框、标签栏收成关闭按钮；按钮在右时标签栏变成搜索框、按钮变成关闭按钮。搜索时这一行用上面的高度和宽度（关闭按钮和搜索框一样高），最多比平时宽约 64 pt。点搜索框才弹出键盘；输入后按键盘上的“搜索”，文字交给微信自己的搜索（在其他标签页时先切到“微信”）。隐藏顶部搜索栏只在开启底栏搜索时生效。需要系统渲染（同步）模式。"),
        WXGGroup(@"透镜",nil,@[WXGSlider(@"透镜内容放大倍数",@"lensZoom",nil,1,1.5,nil),WXGSlider(@"按压透镜外扩倍数",@"lensGrowth",nil,1.08,1.5,nil),
                             WXGSlider(@"按压底栏整体放大",@"barGrowth",nil,1,1.08,@"%.3f"),WXGSlider(@"首尾透镜外包距离",@"endWrap",nil,2,10,@"%.1f pt"),
                             WXGSlider(@"镜内底栏统一内收",@"bodyPinch",nil,0,.30,@"%.3f"),
                             WXGSwitch(@"拖过两端时拉长底栏",@"dockEndStretch",nil),WXGSlider(@"两端拉长距离",@"dockEndStretchDistance",nil,0,40,@"%.0f pt")],
                 @"透镜展开后保留速度拉伸与急停压缩（弹性形变，始终开启）；拖动使用 TEST9 弹簧。透镜的折射、模糊和边框在对应模块的“底栏”范围里。拖过两端时拉长底栏：透镜到了第一个或最后一个标签还继续往外拉，那一端的底栏跟着手指被拉出去（另一端不动，越拉越难，最多“两端拉长距离”），松手弹回；有搜索按钮的那一边最多拉到间距的 3/4。"),
        WXGGroup(@"选中胶囊",nil,@[WXGColorRow(@"浅色模式底色",@"selectionHex",nil),WXGColorRow(@"深色模式底色",@"darkSelectionHex",nil),
                                 WXGSlider(@"静置底色不透明度",@"selectionOpacity",nil,0,.75,nil),WXGSlider(@"静置内边距",@"selectionInset",nil,2,14,@"%.1f pt")],nil),
        WXGGroup(@"图标与文字",nil,@[WXGSlider(@"图标与文字间距",@"dockIconTitleGap",nil,0,16,@"%.1f pt"),WXGSlider(@"图标和文字整体上下",@"dockIconOffset",nil,-12,12,@"%+.1f pt"),
                                   WXGSlider(@"文字大小",@"dockTitleSize",nil,8,13,@"%.1f pt"),
                                   WXGChoice3(@"文字粗细",@"dockTitleWeight",nil,nil,@[@"细",@"常规",@"中等",@"半粗",@"粗"],NO),
                                   WXGSwitch(@"选中的文字加粗一档",@"dockTitleBolderSelected",nil)],
                 @"图标与文字间距：图标（26 pt 高的框）下沿到文字上沿的距离，原来是 5 pt；调大调小时图标往上、文字往下各移一半，整组的中心不变。整体上下：图标和文字一起移，正数往下、负数往上，原来是 0。文字大小和粗细：FIX90 之前固定是 10.5 pt、未选中中等、选中半粗，现在默认 10 pt、中等，选中的不再更粗（打开“选中的文字加粗一档”恢复）。微信自己用的字体写在诊断的底栏图标那一行（“微信标题字体”），可以对照。未读角标跟着图标走。透镜里的放大图标、点击动画用的都是同一套。"),
        WXGGroup(@"图标与动画",nil,@[WXGSwitch(@"使用微信原生图标",@"useWeChatIcons",nil),
                                  WXGSlider(@"点按滑动时长（倍数）",@"dockTapMoveScale",nil,.6,3,@"%.2f ×"),
                                  WXGSlider(@"胶囊变透镜（滑动的比例）",@"dockTapLensShare",nil,.15,.9,@"%.2f"),
                                  WXGSlider(@"落下时长",@"dockTapDropTime",nil,.08,.8,@"%.2f s"),
                                  WXGChoice3(@"切换页面的时机",@"dockTapSwitchWhen",nil,nil,@[@"按下时",@"松手时",@"快到位时",@"落下后"],NO),
                                  WXGSwitch(@"切换后等页面忙完再滑",@"dockTapCalmWaitOn",nil),
                                  WXGSwitch(@"停顿后加速追上",@"dockTapCatchUp",nil),
                                  WXGSwitch(@"点按时用简化透镜（系统渲染）",@"dockTapSimpleTravel",nil)],
                 @"点按切换（FIX95 / FIX98 / FIX99）：点别的标签时，呼出的就是拖动时那块完整的透镜（折射、色散、透镜里的底栏和图标都一样），自己滑过去再落成胶囊；按住不放，到位后就跟着手指，可以继续左右拖。胶囊变透镜：滑动开始后，在滑动时长的这个比例内升起成透镜、颜色褪成透明（默认 0.40，FIX98 是颜色 0.65、升起 0.55）。落下时长：从透镜落回胶囊、颜色回来用的时间，默认 0.16 s（FIX98 0.26 s），在到位前 70% 就开始落，到位后约 0.05 s 落完，所以颜色的变化都在滑动里完成，不会到位以后还慢慢变。点按滑动时长：1 倍是 FIX43 的 0.28 s ×（0.85 + 0.05 × 标签数），默认 1.4 倍（一个标签约 0.35 s，点一下一共约 0.4 s）。FIX98 时调过这两项的，值会带过来；没调过的用新的默认值。切换页面的时机（FIX100）：按下时（默认）= 和微信自己的标签栏一样，手指一按下就让微信切页面：微信加载那一页的那一下卡顿发生在透镜动起来之前（透镜在原地等它，不跳），然后透镜在新页面上滑过去，页面和原生一样快出来；松手时 = 松手才切，动画接着走；快到位时 = 透镜滑完 80% 时切；落下后 = FIX95–FIX97 的做法。按下时以外的三种：微信切页面时主线程会卡 0.05–0.5 s，透镜在那一下停住、再从停住的地方接着走；启动后第一次打开某个标签总是等透镜落下再切。按下后滑到别的标签松手，再切到那个标签；按下后滑出底栏松手，留在按下的那个标签（微信已经切过去了，和原生一样）。切换后等页面忙完再滑（FIX101，FIX102 起默认关闭）：打开后透镜在微信切完页面后原地等到连续三帧准时（最多 0.6 s）再滑，滑动更不容易被打断，但每次都会晚 0.07–0.2 s 开始。停顿后加速追上（FIX102，默认打开）：透镜因为微信切页面停住多久，剩下的动画就快那么久的六成（最多快四分之一），落下的时间尽量和没停时一样。拖动时胶囊颜色也按升起的程度渐变（按压 0.05–0.45）。打开“点按时用简化透镜”恢复 FIX33–FIX94 的做法：动画交给系统渲染服务，页面立刻切换，但滑动的只是一个形状，没有透镜的效果（上面几项不影响它）。")]};
    if([module isEqual:@"bubble"])return @{@"title":@"液态气泡",@"groups":@[
        WXGGroup(@"开关",nil,@[WXGSwitch(@"液态气泡",@"pref.bubbles",nil)],
                 @"聊天里的文字消息换成玻璃气泡：微信原来的气泡和尾巴不画，玻璃就是气泡本体的大小，四个角都是单行气泡高度的一半（单行是胶囊，多行保持同样的圆角，字体调大时跟着变），按下面的颜色着色，颜色可以从轮廓往里渐强。折射、模糊和边框是气泡自己的（下面三项，或在对应页面的“气泡”范围里）。只在同步渲染模式下生效；图片、语音、文件等其它消息暂时保持原样。"),
        WXGGroup(@"气泡的玻璃",nil,@[WXGAction(@"折射与色散",@"open:refraction:bubble",NO),WXGAction(@"模糊",@"open:blur:bubble",NO),
                                    WXGAction(@"边框",@"open:border:bubble",NO)],
                 @"打开对应页面并切到“气泡”范围。第一次打开时这些值和“其余玻璃”相同，之后各调各的。"),
        WXGGroup(@"边缘减弱",nil,@[WXGSwitch(@"边缘减弱",@"bubbleEdgeFadeEnabled",nil),WXGSlider(@"减弱范围",@"bubbleEdgeFade",nil,0,30,@"%.1f pt")],
                 @"和“其余玻璃”的材质一样：开启后，气泡颜色从轮廓开始在“减弱范围”内由弱到强（轮廓处最淡），范围以内是下面设的浓度；关闭或范围为 0 时整块均匀着色。范围超过气泡高度的一半时，中间也到不了设的浓度。"),
        WXGGroup(@"浅色模式",nil,@[WXGColorRow(@"自己的气泡",@"bubbleOutgoingHex",nil),WXGColorRow(@"对方的气泡",@"bubbleIncomingHex",nil)],nil),
        WXGGroup(@"深色模式",nil,@[WXGColorRow(@"自己的气泡",@"darkBubbleOutgoingHex",nil),WXGColorRow(@"对方的气泡",@"darkBubbleIncomingHex",nil)],
                 @"颜色里的不透明度就是玻璃上着色的浓度，越低越透、折射越明显，文字也越难看清。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],nil)]};
    if([module isEqual:@"fade"])return @{@"title":@"渐隐与模糊",@"groups":@[
        WXGGroup(@"开关",nil,@[WXGSwitch(@"页面渐隐与模糊",@"pref.edgeFade",nil)],
                 @"页面的列表在上下边缘变透明（渐隐），同时越靠近边缘越模糊。距离都从列表的上边、下边往里算，设成 0 就关掉那一边。渐隐只改列表本身的透明度，不加颜色遮罩；模糊是贴着列表上下边的两条模糊带，在列表之上、输入栏、导航栏和底栏之下。"),
        WXGGroup(@"聊天页",nil,@[WXGSlider(@"顶部渐隐距离",@"edgeChatFadeTop",nil,0,320,@"%.0f pt"),WXGSlider(@"顶部模糊距离",@"edgeChatBlurTop",nil,0,320,@"%.0f pt"),
                               WXGSlider(@"顶部模糊强度",@"edgeChatBlurTopRadius",nil,0,8,@"%.1f pt"),
                               WXGSlider(@"底部渐隐距离",@"edgeChatFadeBottom",nil,0,360,@"%.0f pt"),WXGSlider(@"底部模糊距离",@"edgeChatBlurBottom",nil,0,360,@"%.0f pt"),
                               WXGSlider(@"底部模糊强度",@"edgeChatBlurBottomRadius",nil,0,8,@"%.1f pt")],
                 @"聊天的消息列表。模糊强度是最靠边处的模糊半径，往里逐渐减到 0；上下各自设置，设成 0 就不加那一边的模糊。"),
        WXGGroup(@"其余页面",nil,@[WXGSlider(@"顶部渐隐距离",@"edgeOtherFadeTop",nil,0,320,@"%.0f pt"),WXGSlider(@"顶部模糊距离",@"edgeOtherBlurTop",nil,0,320,@"%.0f pt"),
                               WXGSlider(@"顶部模糊强度",@"edgeOtherBlurTopRadius",nil,0,8,@"%.1f pt"),
                               WXGSlider(@"底部渐隐距离",@"edgeOtherFadeBottom",nil,0,360,@"%.0f pt"),WXGSlider(@"底部模糊距离",@"edgeOtherBlurBottom",nil,0,360,@"%.0f pt"),
                               WXGSlider(@"底部模糊强度",@"edgeOtherBlurBottomRadius",nil,0,8,@"%.1f pt")],
                 @"首页（聊天列表）、通讯录、朋友圈、聊天设置（单聊、群聊的聊天信息页）、微信的“设置”页，以及本插件的这几页设置。插件设置页里的卡片是玻璃，不能给列表加遮罩，所以渐隐是在列表上叠一层同样的壁纸、越靠边越不透明，看起来一样。")]};
    // FIX84: the frame-rate log and settings sharing.
    if([module isEqual:@"tools"])return @{@"title":@"帧率与参数",@"groups":@[
        WXGGroup(@"帧率检测",nil,@[WXGSwitch(@"记录帧率",@"pref.perfMonitor",nil),WXGSwitch(@"显示帧率浮标",@"pref.perfHUD",nil)],
                 @"打开后每一帧都记下来：每秒的帧率、掉帧、最长一帧、当时的页面、是否在滑动、本插件占用的主线程时间、温度状态和内存。按页面分“滑动 / 静止”统计，一帧超过 50 ms 的卡顿单独列出。插件总开关关闭时也照样记录，可以开关插件各测一段对比。浮标可以拖动，绿色是满帧、橙色掉一些、红色明显掉帧。记录本身每帧只做几次加法；在高刷屏上开着时屏幕会保持最高刷新率。最近 20 分钟的逐秒记录会每 15 秒存一次，微信被杀掉后下次导出里还有上一次的记录。"),
        WXGGroup(@"帧率日志",nil,@[WXGAction(@"查看帧率报告",@"perfReport",NO),WXGAction(@"导出帧率日志 JSON",@"perfExport",NO),WXGAction(@"清空本次记录",@"perfClear",YES)],
                 @"报告里有总体和各页面的平均帧率、掉帧比例、卡顿（每秒多等的毫秒数）、p95 帧时间、最长一帧和插件耗时，以及最近的卡顿。导出的 JSON 里还有逐秒记录和上一次运行的记录，发给作者即可。"),
        WXGGroup(@"参数共享",nil,@[WXGAction(@"复制当前参数",@"shareCopy",NO),WXGAction(@"导出参数文件",@"shareExport",NO),
                                 WXGAction(@"从剪贴板导入参数",@"shareImportClipboard",NO),WXGAction(@"从文件导入参数",@"shareImportFile",NO)],
                 @"包括全部玻璃参数（折射、模糊、材质、边框、底栏、渐隐与模糊、拉伸等）、基本设置和底栏里的开关、设置页的卡片圆角和强调色；总开关、授权、壁纸和头像不在里面。复制得到一段文字，可以直接用微信发给别人，对方复制后点“从剪贴板导入参数”。导入也认诊断 JSON（新版里的完整参数；旧版只有玻璃参数）。想把一套参数做成安装后的默认值，导出参数文件发给作者。")]};
    if([module isEqual:@"wallpaper"])return @{@"title":@"壁纸",@"groups":@[
        WXGGroup(@"设置页壁纸",nil,@[WXGWallpaperRow(@"浅色模式",NO),WXGWallpaperRow(@"深色模式",YES)],
                 @"只用于这几页设置，给玻璃卡片做背景；没有导入时用内置的渐变。"),
        WXGGroup(@"卡片",nil,@[WXGSlider(@"卡片圆角",@"ui.cardRadius",nil,0,40,@"%.0f pt")],@"所有卡片都是连续圆角，不超过卡片高度的一半。"),
        WXGGroup(@"强调色",nil,@[WXGColorRow(@"字体与图标",@"ui.accentHex",nil),WXGAction(@"恢复跟随系统",@"accentReset",NO)],
                 @"也可以点设置首页右上角的调色板按钮修改。")]};
    return nil;
}

#pragma mark - Values

static id WXGRowTarget(NSString *key,NSString **name) {
    if([key hasPrefix:@"pref."]){*name=[key substringFromIndex:5];return WXGPreferences.shared;}
    if([key hasPrefix:@"ui."]){*name=[key substringFromIndex:3];return WXGSettingsStore.shared;}
    *name=key;return WXGConfig.shared;
}
static id WXGRowGet(NSString *key) {NSString *name=nil;id target=key?WXGRowTarget(key,&name):nil;return name?[target valueForKey:name]:nil;}
static void WXGRowSet(NSString *key,id value) {
    NSString *name=nil;id target=key?WXGRowTarget(key,&name):nil;if(!name)return;
    [target setValue:value forKey:name];[target save];
}

#pragma mark - Rows

@interface WXGSettingsRow : UIView
@property(nonatomic,copy) NSDictionary *spec;
@property(nonatomic,copy) NSString *key;
@property(nonatomic,weak) WXGSettingsPage *page;
@property(nonatomic,strong) UILabel *titleLabel;
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page;
- (CGFloat)rowHeight;
- (void)refresh;
- (void)applyLook;
@end
@implementation WXGSettingsRow
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithFrame:CGRectZero])) {
        _spec=[spec copy];_key=[key copy];_page=page;
        _titleLabel=[UILabel new];_titleLabel.text=spec[@"title"];_titleLabel.font=[UIFont systemFontOfSize:15.5 weight:UIFontWeightMedium];
        _titleLabel.adjustsFontSizeToFitWidth=YES;_titleLabel.minimumScaleFactor=.75;[self addSubview:_titleLabel];
        self.accessibilityLabel=spec[@"title"];
    }return self;
}
- (CGFloat)rowHeight {return 52;}
- (void)refresh {}
- (void)applyLook {_titleLabel.textColor=WXGSettingsStore.shared.accentColor;}
@end

@interface WXGSliderRow : WXGSettingsRow
@end
@implementation WXGSliderRow {UILabel *_value;UISlider *_slider;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _value=[UILabel new];_value.textAlignment=NSTextAlignmentRight;_value.font=[UIFont monospacedDigitSystemFontOfSize:13.5 weight:UIFontWeightRegular];
        _slider=[UISlider new];_slider.minimumValue=[spec[@"min"] floatValue];_slider.maximumValue=[spec[@"max"] floatValue];
        _slider.accessibilityLabel=spec[@"title"];
        [_slider addTarget:self action:@selector(slide:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_value];[self addSubview:_slider];[self refresh];
    }return self;
}
- (CGFloat)rowHeight {return 70;}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width;
    self.titleLabel.frame=CGRectMake(16,11,MAX(20,w-32-86),20);_value.frame=CGRectMake(w-16-82,11,82,20);
    _slider.frame=CGRectMake(16,36,MAX(20,w-32),26);
}
- (void)showValue:(double)value {_value.text=[NSString stringWithFormat:self.spec[@"format"]?:@"%.2f",value];}
- (void)refresh {double value=[WXGRowGet(self.key) doubleValue];_slider.value=(float)value;[self showValue:value];}
- (void)slide:(UISlider *)slider {
    WXGRowSet(self.key,@((double)slider.value));
    double value=[WXGRowGet(self.key) doubleValue];   // as stored (clamped)
    if(fabs(value-slider.value)>1e-4)slider.value=(float)value;
    [self showValue:value];
}
- (void)applyLook {
    [super applyLook];WXGSettingsStore *store=WXGSettingsStore.shared;
    _value.textColor=store.secondaryColor;_slider.minimumTrackTintColor=store.controlTint;
}
@end

@interface WXGSwitchRow : WXGSettingsRow
@end
@implementation WXGSwitchRow {UISwitch *_switch;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _switch=[UISwitch new];_switch.accessibilityLabel=spec[@"title"];
        [_switch addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_switch];[self refresh];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGSize size=[_switch sizeThatFits:CGSizeZero];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    _switch.frame=CGRectMake(w-16-size.width,(h-size.height)*.5,size.width,size.height);
    self.titleLabel.frame=CGRectMake(16,0,MAX(20,CGRectGetMinX(_switch.frame)-28),h);
}
- (void)refresh {_switch.on=[WXGRowGet(self.key) boolValue];}
- (void)toggle:(UISwitch *)sender {WXGRowSet(self.key,@(sender.on));[self refresh];}
- (void)applyLook {[super applyLook];_switch.onTintColor=WXGSettingsStore.shared.controlTint;}
@end

// FIX85: a segmented choice (an integer key); the page is told when it
// changes so it can show the groups that belong to the new choice.
@protocol WXGChoiceHost <NSObject>
- (void)choiceChanged:(NSDictionary *)spec;
@end
@interface WXGChoiceRow : WXGSettingsRow
@end
@implementation WXGChoiceRow {UISegmentedControl *_control;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _control=[[UISegmentedControl alloc]initWithItems:spec[@"choices"]];_control.accessibilityLabel=spec[@"title"];
        [_control addTarget:self action:@selector(choose:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_control];[self refresh];
    }return self;
}
- (CGFloat)rowHeight {return 92;}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width;
    self.titleLabel.frame=CGRectMake(16,11,MAX(20,w-32),20);_control.frame=CGRectMake(16,42,MAX(20,w-32),36);
}
- (void)refresh {
    NSInteger value=[WXGRowGet(self.key) integerValue];
    _control.selectedSegmentIndex=value>=0 && value<(NSInteger)_control.numberOfSegments?value:UISegmentedControlNoSegment;
}
- (void)choose:(UISegmentedControl *)control {
    WXGRowSet(self.key,@(control.selectedSegmentIndex));[self refresh];
    WXGSettingsPage *page=self.page;
    if([self.spec[@"rebuild"] boolValue] && [page conformsToProtocol:@protocol(WXGChoiceHost)])
        dispatch_async(dispatch_get_main_queue(),^{[(id<WXGChoiceHost>)page choiceChanged:self.spec];});
}
- (void)applyLook {
    [super applyLook];WXGSettingsStore *store=WXGSettingsStore.shared;
    if(store.controlTint)_control.selectedSegmentTintColor=[store.controlTint colorWithAlphaComponent:.35];
}
@end

@interface WXGColorRowView : WXGSettingsRow
@end
@implementation WXGColorRowView {UIView *_swatch;UILabel *_hex;UIImageView *_chevron;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _swatch=[UIView new];_swatch.layer.cornerRadius=12;_swatch.layer.borderWidth=1;_swatch.userInteractionEnabled=NO;
        _hex=[UILabel new];_hex.textAlignment=NSTextAlignmentRight;_hex.font=[UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
        _chevron=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]]];
        _chevron.contentMode=UIViewContentModeCenter;
        for(UIView *v in @[_swatch,_hex,_chevron])[self addSubview:v];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(edit)]];
        self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;[self refresh];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    _chevron.frame=CGRectMake(w-16-10,(h-16)*.5,10,16);
    _swatch.frame=CGRectMake(CGRectGetMinX(_chevron.frame)-10-24,(h-24)*.5,24,24);
    _hex.frame=CGRectMake(CGRectGetMinX(_swatch.frame)-8-96,0,96,h);
    self.titleLabel.frame=CGRectMake(16,0,MAX(20,CGRectGetMinX(_hex.frame)-20),h);
}
- (NSString *)hexValue {id value=WXGRowGet(self.key);return [value isKindOfClass:NSString.class]?WXGNormalizeHex(value):nil;}
- (void)refresh {
    NSString *hex=[self hexValue];
    _swatch.backgroundColor=hex?WXGColor(hex):UIColor.labelColor;
    _hex.text=hex?:@"跟随系统";self.accessibilityValue=_hex.text;
}
- (BOOL)accessibilityActivate {[self edit];return YES;}
- (void)edit {
    WXGSettingsPage *page=self.page;NSString *hex=[self hexValue];BOOL accent=[self.key isEqual:@"ui.accentHex"];
    UIColor *current=hex?WXGColor(hex):[UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection];
    __weak WXGColorRowView *weakSelf=self;NSString *key=self.key;
    [page pickColorTitled:self.spec[@"title"] current:current alpha:!accent change:^(UIColor *color,BOOL finished){
        (void)finished;NSString *picked=WXGNormalizeHex(WXGHexFromColor(color));
        if(picked)WXGRowSet(key,picked);
        [weakSelf refresh];
    }];
}
- (void)applyLook {
    [super applyLook];WXGSettingsStore *store=WXGSettingsStore.shared;
    _hex.textColor=store.secondaryColor;_chevron.tintColor=store.secondaryColor;
    _swatch.layer.borderColor=[[UIColor.labelColor colorWithAlphaComponent:.25] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    [self refresh];
}
@end

@interface WXGActionRow : WXGSettingsRow
@property(nonatomic,copy) void (^handler)(void);
@end
@implementation WXGActionRow {UIImageView *_chevron;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _chevron=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]]];
        _chevron.contentMode=UIViewContentModeCenter;
        [self addSubview:_chevron];_chevron.hidden=[spec[@"destructive"] boolValue];
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(run)]];
        self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    }return self;
}
- (CGFloat)rowHeight {return 50;}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    _chevron.frame=CGRectMake(w-16-10,(h-16)*.5,10,16);self.titleLabel.frame=CGRectMake(16,0,MAX(20,w-52),h);
}
- (void)run {if(_handler)_handler();}
- (BOOL)accessibilityActivate {[self run];return YES;}
- (void)applyLook {
    [super applyLook];
    if([self.spec[@"destructive"] boolValue])self.titleLabel.textColor=UIColor.systemRedColor;
    _chevron.tintColor=WXGSettingsStore.shared.secondaryColor;
}
@end

@interface WXGWallpaperRowView : WXGSettingsRow
@end
@implementation WXGWallpaperRowView {UIImageView *_thumbnail;UIButton *_choose,*_clear;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _thumbnail=[UIImageView new];_thumbnail.contentMode=UIViewContentModeScaleAspectFill;_thumbnail.clipsToBounds=YES;
        _thumbnail.layer.cornerRadius=7;_thumbnail.layer.cornerCurve=kCACornerCurveContinuous;_thumbnail.layer.borderWidth=1;
        _choose=[UIButton buttonWithType:UIButtonTypeSystem];[_choose setTitle:@"导入" forState:UIControlStateNormal];
        _clear=[UIButton buttonWithType:UIButtonTypeSystem];[_clear setTitle:@"清除" forState:UIControlStateNormal];
        _choose.accessibilityLabel=[NSString stringWithFormat:@"导入%@壁纸",spec[@"title"]];
        _clear.accessibilityLabel=[NSString stringWithFormat:@"清除%@壁纸",spec[@"title"]];
        for(UIButton *b in @[_choose,_clear])b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [_choose addTarget:self action:@selector(choose) forControlEvents:UIControlEventTouchUpInside];
        [_clear addTarget:self action:@selector(clear) forControlEvents:UIControlEventTouchUpInside];
        for(UIView *v in @[_thumbnail,_choose,_clear])[self addSubview:v];
        self.accessibilityLabel=nil;   // the buttons speak for themselves
        [self refresh];
    }return self;
}
- (CGFloat)rowHeight {return 76;}
- (BOOL)dark {return [self.spec[@"dark"] boolValue];}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;
    _clear.frame=CGRectMake(w-16-44,(h-32)*.5,44,32);_choose.frame=CGRectMake(CGRectGetMinX(_clear.frame)-6-44,(h-32)*.5,44,32);
    _thumbnail.frame=CGRectMake(16,(h-58)*.5,40,58);
    self.titleLabel.frame=CGRectMake(CGRectGetMaxX(_thumbnail.frame)+14,0,MAX(20,CGRectGetMinX(_choose.frame)-CGRectGetMaxX(_thumbnail.frame)-20),h);
}
- (void)refresh {UIImage *image=[WXGSettingsStore.shared wallpaperForDark:self.dark];_thumbnail.image=image;_clear.enabled=image!=nil;}
- (void)choose {BOOL dark=self.dark;[self.page pickImage:^(UIImage *image){[WXGSettingsStore.shared setWallpaper:image dark:dark];}];}
- (void)clear {[WXGSettingsStore.shared setWallpaper:nil dark:self.dark];}
- (void)applyLook {
    [super applyLook];WXGSettingsStore *store=WXGSettingsStore.shared;
    UIColor *tint=store.controlTint?:UIColor.systemBlueColor;_choose.tintColor=tint;_clear.tintColor=tint;
    _thumbnail.backgroundColor=[UIColor.labelColor colorWithAlphaComponent:.08];
    _thumbnail.layer.borderColor=[[UIColor.labelColor colorWithAlphaComponent:.2] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    [self refresh];
}
@end

#pragma mark - Module page

// The range last chosen in any module (for this run of WeChat).
static NSString *WXGLastScope=@"dock";

@interface WXGSettingsModule : WXGSettingsPage <WXGChoiceHost>
- (instancetype)initWithModule:(NSString *)module;
@end
@implementation WXGSettingsModule {
    NSString *_module;
    NSDictionary *_spec;
    NSString *_scope;
    UILabel *_scopeLabel,*_scopeFooter;
    WXGSettingsCard *_scopeCard;
    NSArray<UIButton *> *_scopeButtons;
    UIView *_scopePill;
    NSMutableArray<NSDictionary *> *_groups;   // label, card, rows, separators, footer (as present)
    WXGRimStyle _builtStyle;                   // FIX85: the rim style the groups were built for (FIX86: the range's)
}
- (instancetype)initWithModule:(NSString *)module {
    if((self=[super initWithNibName:nil bundle:nil])) {
        _module=[module copy];_spec=WXGModuleSpec(module);_scope=WXGLastScope;
        if(![self.scopes containsObject:_scope])_scope=[_scope isEqual:@"bubble"]?@"other":self.scopes.firstObject;   // FIX85
        self.pageTitle=_spec[@"title"]?:@"设置";self.showsAccentButton=YES;
    }return self;
}
- (BOOL)scoped {return [_spec[@"scoped"] boolValue];}
// FIX85: the ranges of this page (the bubbles have one in some pages).
- (NSArray<NSString *> *)scopes {return _spec[@"scopes"]?:@[@"dock",@"other"];}
- (NSUInteger)selectedScopeIndex {NSUInteger i=[self.scopes indexOfObject:_scope];return i==NSNotFound?0:i;}
// FIX86: the rim style of the range selected on this page.
- (WXGRimStyle)scopeRimStyle {
    WXGGlassScope scope=!self.scoped?WXGGlassScopeOther:[_scope isEqual:@"dock"]?WXGGlassScopeDock:[_scope isEqual:@"bubble"]?WXGGlassScopeBubble:WXGGlassScopeOther;
    return [WXGConfig.shared rimStyleForScope:scope];
}
- (void)buildContent {
    if(self.scoped) {
        _scopeLabel=[self sectionLabel:@"作用范围"];
        _scopeCard=[self addCard:NO];
        _scopePill=[UIView new];_scopePill.userInteractionEnabled=NO;_scopePill.layer.cornerCurve=kCACornerCurveContinuous;
        [_scopeCard.contentView addSubview:_scopePill];
        NSMutableArray *buttons=[NSMutableArray array];
        NSDictionary *titles=@{@"dock":@"底栏",@"other":@"其余玻璃",@"bubble":@"气泡"};
        for(NSString *scope in self.scopes) {
            NSString *title=titles[scope]?:scope;
            UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];[b setTitle:title forState:UIControlStateNormal];
            b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];b.tag=(NSInteger)buttons.count;
            [b addTarget:self action:@selector(selectScope:) forControlEvents:UIControlEventTouchUpInside];
            [_scopeCard.contentView addSubview:b];[buttons addObject:b];
        }
        _scopeButtons=buttons;
        _scopeFooter=[UILabel new];_scopeFooter.numberOfLines=0;_scopeFooter.font=[UIFont systemFontOfSize:12.5];
        _scopeFooter.text=[self.scopes containsObject:@"bubble"]?
            @"底栏：悬浮标签栏和按压时的透镜。其余玻璃：导航按钮、标题胶囊、输入栏、菜单等，以及这几页的卡片，调节时可直接看到。气泡：聊天里的液态气泡。":
            @"底栏：悬浮标签栏和按压时的透镜。其余玻璃：导航按钮、标题胶囊、输入栏、菜单等，以及这几页的卡片，调节时可直接看到。";
        [self.content addSubview:_scopeFooter];
    }
    [self buildGroups];
    // The dock's lift footer quotes the current distance to the screen edge.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(configChanged) name:WXGSettingsChanged object:nil];
}
- (void)buildGroups {
    for(NSDictionary *group in _groups)for(NSString *part in @[@"label",@"card",@"footer"])[group[part] removeFromSuperview];
    _groups=[NSMutableArray array];
    __weak WXGSettingsModule *weakSelf=self;
    BOOL dock=self.scoped && [_scope isEqual:@"dock"],bubble=self.scoped && [_scope isEqual:@"bubble"];
    _builtStyle=[self scopeRimStyle];NSNumber *style=@(_builtStyle);
    for(NSDictionary *group in _spec[@"groups"]) {
        NSString *scope=group[@"scope"];
        if(self.scoped && scope && ![scope isEqual:_scope])continue;
        NSArray *styles=group[@"styles"];   // FIX85: only for these rim styles
        if(styles && ![styles containsObject:style])continue;
        NSMutableDictionary *built=[NSMutableDictionary dictionary];
        if(group[@"title"])built[@"label"]=[self sectionLabel:group[@"title"]];
        WXGSettingsCard *card=[self addCard:NO];built[@"card"]=card;
        NSMutableArray *rows=[NSMutableArray array],*separators=[NSMutableArray array];
        for(NSDictionary *spec in group[@"rows"]) {
            NSString *key=dock && spec[@"dock"]?spec[@"dock"]:bubble && spec[@"bubble"]?spec[@"bubble"]:spec[@"key"];
            NSString *type=spec[@"type"];WXGSettingsRow *row=nil;
            if([type isEqual:@"slider"])row=[[WXGSliderRow alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"switch"])row=[[WXGSwitchRow alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"color"])row=[[WXGColorRowView alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"wallpaper"])row=[[WXGWallpaperRowView alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"choice"])row=[[WXGChoiceRow alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"action"]) {
                WXGActionRow *action=[[WXGActionRow alloc]initWithSpec:spec key:key page:self];
                NSString *name=spec[@"action"];action.handler=^{[weakSelf runAction:name];};row=action;
            }
            if(!row)continue;
            if(rows.count){UIView *line=[UIView new];line.userInteractionEnabled=NO;[card.contentView addSubview:line];[separators addObject:line];}
            [card.contentView addSubview:row];[rows addObject:row];
        }
        built[@"rows"]=rows;built[@"separators"]=separators;
        NSString *footer=group[@"footer"];
        if(footer) {
            UILabel *label=[UILabel new];label.numberOfLines=0;label.font=[UIFont systemFontOfSize:12.5];
            label.text=[footer isEqual:@"lift"]?[self liftFooter]:footer;built[@"footerText"]=footer;
            [self.content addSubview:label];built[@"footer"]=label;
        }
        [_groups addObject:built];
    }
    [self applyLook];
}
- (NSString *)liftFooter {
    UIWindow *window=self.viewIfLoaded.window?:UIApplication.sharedApplication.keyWindow?:UIApplication.sharedApplication.windows.firstObject;
    return [NSString stringWithFormat:@"负值使底栏更靠近屏幕底边，到边缘自动停住。当前底边距屏幕约 %.1f pt。原有正值设置保持原位置。",
            MAX(0,window.safeAreaInsets.bottom+WXGConfig.shared.lift)];
}
- (void)configChanged {
    for(NSDictionary *group in _groups)if([group[@"footerText"] isEqual:@"lift"]) {
        UILabel *footer=group[@"footer"];NSString *text=[self liftFooter];
        if(![footer.text isEqual:text]){footer.text=text;[self.view setNeedsLayout];}
    }
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self refreshRows];}
- (void)refreshRows {
    // FIX85: the style changed elsewhere (恢复本页默认, an import): other groups.
    BOOL styled=NO;for(NSDictionary *group in _spec[@"groups"])if(group[@"styles"]){styled=YES;break;}
    if(styled && _builtStyle!=[self scopeRimStyle]){[self choiceChanged:@{}];return;}
    for(NSDictionary *group in _groups)for(WXGSettingsRow *row in group[@"rows"])[row refresh];
    [self configChanged];
}
- (void)applyLook {
    [super applyLook];
    WXGSettingsStore *store=WXGSettingsStore.shared;
    UIColor *line=[UIColor.labelColor colorWithAlphaComponent:.12];
    for(NSDictionary *group in _groups) {
        ((UILabel *)group[@"label"]).textColor=store.secondaryColor;
        ((UILabel *)group[@"footer"]).textColor=store.secondaryColor;
        for(WXGSettingsRow *row in group[@"rows"])[row applyLook];
        for(UIView *separator in group[@"separators"])separator.backgroundColor=line;
    }
    _scopeLabel.textColor=store.secondaryColor;_scopeFooter.textColor=store.secondaryColor;
    NSUInteger selected=self.selectedScopeIndex;
    for(UIButton *b in _scopeButtons) {
        [b setTitleColor:(NSUInteger)b.tag==selected?store.accentColor:store.secondaryColor forState:UIControlStateNormal];
        b.accessibilityTraits=(NSUInteger)b.tag==selected?UIAccessibilityTraitButton|UIAccessibilityTraitSelected:UIAccessibilityTraitButton;
    }
    _scopePill.backgroundColor=store.controlTint?[store.controlTint colorWithAlphaComponent:.22]:[UIColor.labelColor colorWithAlphaComponent:.12];
}
- (CGFloat)layoutContentForWidth:(CGFloat)width {
    CGFloat inner=MIN(MAX(100,width-2*self.sideMargin),620),side=(width-inner)*.5,y=0;
    if(_scopeCard) {
        _scopeLabel.frame=CGRectMake(side+6,y,inner-12,18);y+=18+8;
        CGFloat h=46;_scopeCard.frame=CGRectMake(side,y,inner,h);
        CGFloat half=inner/MAX(1,(CGFloat)_scopeButtons.count);   // FIX85: two or three ranges
        for(UIButton *b in _scopeButtons)b.frame=CGRectMake(b.tag*half,0,half,h);
        NSUInteger selected=self.selectedScopeIndex;
        _scopePill.frame=CGRectMake(selected*half+5,5,half-10,h-10);
        _scopePill.layer.cornerRadius=MAX(0,MIN(round(WXGSettingsStore.shared.cardRadius)-5,(h-10)*.5));
        y+=h;
        CGFloat fw=inner-12;CGSize size=[_scopeFooter sizeThatFits:CGSizeMake(fw,CGFLOAT_MAX)];
        _scopeFooter.frame=CGRectMake(side+6,y+7,fw,ceil(size.height));y+=7+ceil(size.height)+24;
    }
    for(NSDictionary *group in _groups) {
        UILabel *label=group[@"label"];
        if(label){label.frame=CGRectMake(side+6,y,inner-12,18);y+=18+8;}
        WXGSettingsCard *card=group[@"card"];NSArray<WXGSettingsRow *> *rows=group[@"rows"];NSArray<UIView *> *separators=group[@"separators"];
        CGFloat rowY=0,hairline=1/MAX(1,UIScreen.mainScreen.scale);
        for(NSUInteger i=0;i<rows.count;i++) {
            if(i && i-1<separators.count)separators[i-1].frame=CGRectMake(16,rowY-hairline*.5,inner-16,hairline);
            CGFloat h=rows[i].rowHeight;rows[i].frame=CGRectMake(0,rowY,inner,h);rowY+=h;
        }
        card.frame=CGRectMake(side,y,inner,MAX(rowY,1));y+=rowY;
        UILabel *footer=group[@"footer"];
        if(footer) {
            CGFloat fw=inner-12;CGSize size=[footer sizeThatFits:CGSizeMake(fw,CGFLOAT_MAX)];
            footer.frame=CGRectMake(side+6,y+7,fw,ceil(size.height));y+=7+ceil(size.height);
        }
        y+=24;
    }
    return y;
}
- (void)choiceChanged:(NSDictionary *)spec {
    (void)spec;
    [UIView performWithoutAnimation:^{[self buildGroups];[self.view setNeedsLayout];[self.view layoutIfNeeded];}];
    UIScrollView *scroll=self.scrollView;
    CGFloat maximum=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
    if(scroll.contentOffset.y>maximum)[scroll setContentOffset:CGPointMake(0,maximum) animated:YES];
}
- (void)selectScope:(UIButton *)sender {
    NSString *scope=sender.tag>=0 && sender.tag<(NSInteger)self.scopes.count?self.scopes[sender.tag]:@"other";
    if([scope isEqual:_scope])return;
    _scope=scope;WXGLastScope=scope;
    if(WXGConfig.shared.haptics)[[[UISelectionFeedbackGenerator alloc]init] selectionChanged];
    // Glass is never faded or flown in (a backdrop under opacity < 1 turns
    // into a flat fill): the groups are replaced in place, only the pill slides.
    CGRect from=_scopePill.frame;
    [UIView performWithoutAnimation:^{
        [self buildGroups];[self.view setNeedsLayout];[self.view layoutIfNeeded];
    }];
    CGRect to=_scopePill.frame;_scopePill.frame=from;
    [UIView animateWithDuration:.32 delay:0 usingSpringWithDamping:.84 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                     animations:^{self->_scopePill.frame=to;} completion:nil];
    // The other range may be shorter: do not leave the page scrolled past its end.
    UIScrollView *scroll=self.scrollView;
    CGFloat maximum=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
    if(scroll.contentOffset.y>maximum)[scroll setContentOffset:CGPointMake(0,maximum) animated:YES];
}
- (void)runAction:(NSString *)action {
    if([action isEqual:@"diagnostics"]){[self.navigationController pushViewController:WXGSettingsDiagnosticsPage() animated:YES];return;}
    if([action isEqual:@"export"]){[WXGIntegrationHost.shared exportDiagnosticsFrom:self];return;}
    if([action isEqual:@"accentReset"]){WXGSettingsStore.shared.accentHex=nil;[WXGSettingsStore.shared save];[self refreshRows];return;}
    // FIX85: open another page at a range (液态气泡 → its glass).
    if([action hasPrefix:@"open:"]) {
        NSArray<NSString *> *parts=[action componentsSeparatedByString:@":"];
        if(parts.count>=3)WXGLastScope=parts[2];
        UIViewController *page=parts.count>=2?WXGSettingsModulePage(parts[1]):nil;
        if(page)[self.navigationController pushViewController:page animated:YES];
        return;
    }
    if([action isEqual:@"calmShow"]){[self showMessage:@"背景变化程度" detail:WXGCalmSummaryText()];return;}   // FIX88
    // FIX84: 帧率与参数.
    __weak WXGSettingsModule *weakModule=self;
    if([action isEqual:@"perfReport"]){WXGPerfShowReport(self);return;}
    if([action isEqual:@"perfExport"]){WXGPerfExportFrom(self);return;}
    if([action isEqual:@"perfClear"]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清空本次帧率记录？" message:@"从现在重新开始统计；上一次运行微信时的记录保留。"
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){WXGPerfClear();}]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if([action isEqual:@"shareCopy"]){WXGShareCopy(self);return;}
    if([action isEqual:@"shareExport"]){WXGShareExportFrom(self);return;}
    if([action isEqual:@"shareImportClipboard"]){WXGShareImportClipboard(self,^{[weakModule refreshRows];});return;}
    if([action isEqual:@"shareImportFile"]){WXGShareImportFile(self,^{[weakModule refreshRows];});return;}
    if([action isEqual:@"resetPage"]) {
        // FIX81: every setting on this page (both ranges) back to the defaults.
        NSMutableArray *keys=[NSMutableArray array];
        for(NSDictionary *group in _spec[@"groups"])for(NSDictionary *row in group[@"rows"])for(NSString *field in @[@"key",@"dock",@"bubble"]) {
            NSString *key=row[field];
            if([key isKindOfClass:NSString.class] && ![key hasPrefix:@"pref."] && ![key hasPrefix:@"ui."])[keys addObject:key];
        }
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"恢复“%@”的默认值？",_spec[@"title"]?:@"本页"]
            message:@"这一页的设置（有两个范围的两个都算）回到默认值，其它页不变。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak WXGSettingsModule *weakSelf=self;
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
            [WXGConfig.shared resetKeys:keys];[weakSelf refreshRows];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if([action isEqual:@"reset"]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"恢复本版默认参数？"
            message:@"底栏和其余玻璃的折射、模糊、材质、边框，以及底栏、触感反馈和菜单圆角恢复默认；适配开关、截图比例、壁纸和强调色不变。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak WXGSettingsModule *weakSelf=self;
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
            [WXGConfig.shared reset];[weakSelf refreshRows];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
UIViewController *WXGSettingsModulePage(NSString *module) {
    if([WXGHiddenSettingsModules() containsObject:module])return nil;   // FIX59: not in this build
    return WXGModuleSpec(module)?[[WXGSettingsModule alloc]initWithModule:module]:nil;
}
