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
// FIX114 E (user: the style switch inside a card with its own "样式" title
// looked like a rounded box): the choice alone, the card itself a capsule
// with the choices in it (as the range row was), under the group's title.
static NSDictionary *WXGBare(NSDictionary *row) {NSMutableDictionary *m=[row mutableCopy];m[@"bare"]=@YES;return m;}
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
// FIX113 O: a group not shown in these ranges.
static NSDictionary *WXGNotIn(NSDictionary *group,NSArray<NSString *> *scopes) {NSMutableDictionary *m=[group mutableCopy];m[@"notIn"]=scopes;return m;}
/* FIX113 O: a row's key in a range. 分组 and 设置页 rows are derived from the
   bubbles' (or the dock's) key of the row: bubbleRimOpacity -> segmentRimOpacity,
   dockMaterialHex -> cardMaterialHex; @"" when that range has no such key
   (the row is not shown there); a row with one key is shared. */
static NSString *WXGRowKeyForScope(NSDictionary *spec,NSString *scope) {
    if([scope isEqual:@"dock"])return spec[@"dock"]?:spec[@"key"];
    if([scope isEqual:@"bubble"])return spec[@"bubble"]?:spec[@"key"];
    if([scope isEqual:@"segment"] || [scope isEqual:@"card"] || [scope isEqual:@"lens"] || [scope isEqual:@"segmentLens"] || [scope isEqual:@"finder"]) {
        if(spec[scope])return spec[scope];
        NSString *from=spec[@"bubble"],*prefix=@"bubble";
        if(!from){from=spec[@"dock"];prefix=@"dock";}
        if([from hasPrefix:prefix]) {
            // FIX113 X: the 透镜 range's keys are lensGlass… (lensRim… were the lens' plain line);
            // FIX114 C: 分组透镜's segmentLensGlass….
            // FIX115 S: 视频号's finderGlass… (its border only).
            NSString *stem=[scope isEqual:@"lens"]?@"lensGlass":[scope isEqual:@"segmentLens"]?@"segmentLensGlass":[scope isEqual:@"finder"]?@"finderGlass":scope;
            NSString *derived=[stem stringByAppendingString:[from substringFromIndex:prefix.length]];
            return [WXGConfig.shared knowsKey:derived]?derived:@"";
        }
    }
    return spec[@"key"];
}
// FIX114 L (user: too many settings; a switch at the bottom of a page to use
// another range's): a range's 共用 of a page, the page's last group (the
// range's other groups are hidden while it uses another's).
// FIX114 N (user, 08:35: not that: a range's settings of a page shared OUT to
// the ranges chosen, as one chooses where settings apply): the page's last
// group is 共用到, built for the range shown (buildGroups): a switch per other
// range of the page (on: that range uses this one's settings of the page) and
// 全部范围; a range that uses another's shows 共用 instead (a switch back to
// its own). The keys are L's (the range + 1, any range of the page).
#define WXG_SHARE_NOTE @"共用到（FIX114 N）：把这个范围在这一页的设置共用给打开的那些范围，就像选作用范围一样——打开的范围在这一页直接用这里的值，这里怎么调它们就跟着怎么变。只管这一页（折射、模糊、材质、边框四页各选各的）。被共用的范围自己原来调的值都还在，关掉就回来；“全部范围”一次全开或全关。一个范围在一页里只能跟一个来源：在别的范围这一页再打开它，就换成跟那边。"
#define WXG_FOLLOW_NOTE @"共用（FIX114 N）：这个范围在这一页现在用另一个范围的设置（在那个范围这一页的“共用到”里打开的），这里自己的项先藏起来，原来的值都还在。关掉上面的开关就用回自己的。"
static NSArray<NSString *> *WXGShareOrder(void) {return @[@"other",@"dock",@"bubble",@"segment",@"card",@"lens",@"segmentLens",@"finder"];}   // (WXGGlassScope order)
static NSString *WXGShareKeyFor(NSString *scope,NSInteger page) {
    NSDictionary *prefix=@{@"other":@"other",@"dock":@"dock",@"bubble":@"bubble",@"segment":@"segment",@"card":@"card",@"lens":@"lensGlass",@"segmentLens":@"segmentLensGlass",@"finder":@"finderGlass"};
    NSArray *pages=@[@"Refraction",@"Blur",@"Material",@"Border"];
    NSString *p=prefix[scope];if(!p || page<0 || page>3)return nil;
    NSString *key=[NSString stringWithFormat:@"%@Share%@",p,pages[(NSUInteger)page]];
    return [WXGConfig.shared knowsKey:key]?key:nil;
}
// The value a range holds to use `scope`'s settings (its WXGGlassScope + 1).
static NSInteger WXGShareCode(NSString *scope) {NSUInteger i=[WXGShareOrder() indexOfObject:scope];return i==NSNotFound?0:(NSInteger)i+1;}
static WXGGlassScope WXGShareScopeEnum(NSString *scope) {NSUInteger i=[WXGShareOrder() indexOfObject:scope];return i==NSNotFound?WXGGlassScopeOther:(WXGGlassScope)i;}
static NSString *WXGShareScopeName(WXGGlassScope scope) {NSArray *order=WXGShareOrder();return scope>=0 && (NSUInteger)scope<order.count?order[(NSUInteger)scope]:@"other";}
// The range whose settings of the page `scope` ends up using (itself: its own).
static NSString *WXGShareResolved(NSString *scope,NSInteger page) {
    return WXGShareScopeName([WXGConfig.shared sharedScope:WXGShareScopeEnum(scope) page:(WXGSharePage)page]);
}
// The page's groups with its 共用 groups just above its 恢复 (or last).
static NSArray *WXGWithShare(NSArray *groups,NSArray *share) {
    NSMutableArray *out=[groups mutableCopy];
    NSUInteger at=out.count;
    if(at && [[out.lastObject objectForKey:@"title"] isEqual:@"恢复"])at--;
    [out insertObjects:share atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at,share.count)]];
    return out;
}
// FIX115 E (user, 06:48: besides 共用, a way to hand one range's settings to
// another so that range's own values become these): 复制到, under 共用到.
#define WXG_COPY_NOTE @"复制到（FIX115 E）：把这个范围现在的设置一次性复制给另一个范围——那个范围自己的值直接被替换成这里的（不能撤销），之后两边各调各的、互不影响（和“共用到”不同：共用是一直跟着这里变，自己的值还留着）。点了会问只复制这一页，还是折射、模糊、材质、边框四页一起。这个范围正在共用别的范围时，复制的是它现在用的那一份；目标范围原来在共用别人的，复制后改回用自己的（也就是复制过去的这份）。两个范围各自独有的项（比如底栏的透镜、气泡的尾巴）不动。"
// A place for 共用到 / 共用 and 复制到, filled for the range shown when the page is built.
static NSArray *WXGShareGroups(NSInteger page) {
    NSMutableDictionary *g=[WXGGroup(@"共用到",nil,@[],WXG_SHARE_NOTE) mutableCopy];
    g[@"share"]=@YES;g[@"shareSlot"]=@YES;g[@"sharePage"]=@(page);
    NSMutableDictionary *c=[WXGGroup(@"复制到",nil,@[],WXG_COPY_NOTE) mutableCopy];
    c[@"share"]=@YES;c[@"copySlot"]=@YES;c[@"sharePage"]=@(page);   // shown while the range uses another's too
    return @[g,c];
}
// FIX114 J: a range's backdrop saturation / brightness (模糊 page).
#define WXG_TONE_NOTE @"背景饱和度 / 背景亮度（FIX114 J）：玻璃透出来的背景先做这两步再折射（像 Telegram 的玻璃：不靠一层颜色盖上去，而是让背景本身的颜色更鲜艳）。饱和度 1 = 原样，默认 1.05 和以前一样，调高颜色更艳；亮度 0 = 不变，正数变亮、负数变暗。想让玻璃更多“取自背景的颜色”，可以把“材质遮盖”调低、饱和度调高。只在同步渲染模式下有效。"
// FIX114 I: each range's 边界过渡, right below its 折射宽度.
#define WXG_TRANSITION_NOTE @"边界过渡（FIX114 I）：0 = 原来的样子。往右拉，折射的那一圈和中间不折射的地方之间的分界线会慢慢化开；拉到 1 时折射从边缘往里一点点变弱，看不出在哪结束，也不会出现拉丝。折射强度、折射宽度照样用。下面三项（FIX114 J）只在边界过渡大于 0 时有用，拉到 1 时最明显：过渡宽度 = 折射从边缘往里伸多远才完全消失，0 是自动（按折射强度和宽度算，最多到玻璃中线），手动设大了也不会超过中线；边缘最大拉伸 = 边缘处画面最多被拉长几倍，越大边缘弯得越厉害、能取到越深处的内容，太大会开始拉丝（默认 2.5）；过渡曲线 = 弯折怎么往里分布，小 = 铺得开、往里很远还在弯，大 = 集中在边上、里面很快就平了（默认 2）。只在同步渲染模式下有效。"
static NSDictionary *WXGModuleSpec(NSString *module) {
    if([module isEqual:@"basic"])return @{@"title":@"基本设置",@"groups":@[
        WXGGroup(@"适配",nil,@[WXGSwitch(@"顶部按钮与背景适配",@"pref.nav",nil),WXGSwitch(@"真实悬浮标签栏",@"pref.dock",nil),
                              WXGSwitch(@"聊天悬浮输入栏",@"pref.input",nil),WXGSwitch(@"原生宽度三端输入（测试）",@"pref.nativeInputTest",nil),
                              WXGSwitch(@"双端输入栏用系统图标",@"inputSystemIcons",nil)],
                 @"总开关在设置首页卡片的右侧，关闭后恢复微信原控件。默认是 TEST4 双端输入栏；三端输入测试默认关闭，开启后保留原生输入宽度和动作，单行三段等高，多行只增高中间。双端输入栏用系统图标（FIX113）：开着用插件这一套 SF Symbols 图标（表情键是 Face ID 图标，面板打开时是键盘）；关掉换回微信自己的图标（加号、表情 / 键盘、语音 / 键盘、发送都用微信当时显示的那张，微信没有图的地方仍用这一套）。"),
        WXGGroup(@"双端输入栏尺寸",nil,@[WXGSlider(@"输入框高度",@"inputPillHeight",nil,34,54,@"%.1f pt"),
                                   WXGSlider(@"左侧加号大小（0 = 和输入框一样高）",@"inputPlusSize",nil,0,54,@"%.1f pt"),
                                   WXGSlider(@"离屏幕两边",@"inputSideMargin",nil,8,60,@"%.1f pt"),
                                   WXGSlider(@"加号和输入框的间距",@"inputPlusGap",nil,4,24,@"%.1f pt")],
                 @"FIX115 J：默认的双端输入栏（不是三端测试）。输入框高度 = 一行字时那条胶囊有多高（以前 40 pt，现在默认 44 pt），右边的语音 / 发送按钮跟着变大；左侧加号默认和输入框一样高、一起变，想单独定就拉“左侧加号大小”（0 = 跟输入框）。离屏幕两边 = 左边加号到屏幕左边、右边输入框到屏幕右边的距离（以前 28 pt，现在默认 34 pt，所以输入框更短）；加号和输入框的间距默认 12 pt（以前也是 12）。都是按 440 pt 宽的屏幕说的，别的宽度按比例缩放（和“截图比例微调”一起）。胶囊不会比微信自己的输入框矮（高度调得很低、屏幕窄或打多行时，按输入框的高度来，光标和第一行、最后一行都在胶囊里）。输入：微信自己的输入框（光标、选字、多行变高、按住说话）照旧，只是它的宽度跟着胶囊变：输入框比 40 pt 高时，文字从左边往里多让出高出部分的一半，离胶囊的圆头保持原来的距离；打多行时胶囊照旧往上长，加号和右侧按钮留在最后一行。"),
        WXGGroup(@"更多玻璃",nil,@[WXGSwitch(@"搜索框换成玻璃胶囊",@"pref.localSearch",nil),WXGSwitch(@"加号面板的方块",@"pref.localPanel",nil),
                                WXGSwitch(@"表情面板的发送、删除和分组选中",@"pref.localEmoji",nil),WXGSwitch(@"转发 / 分享弹层的背景",@"pref.localSheet",nil),
                                WXGSwitch(@"标题换成玻璃胶囊",@"pref.localTitle",nil),WXGSwitch(@"网页、弹出页面的顶部按钮",@"pref.localNavButtons",nil),
                                WXGSwitch(@"带颜色的按钮（如绿色“完成”）",@"localColorButtons",nil),
                                WXGSwitch(@"朋友圈新消息横幅和 ·· 按钮",@"localMoments",nil),
                                WXGSlider(@"加号方块圆角",@"localTileRadius",nil,0,32,@"%.1f pt"),WXGSlider(@"表情分组选中圆角",@"localTabRadius",nil,0,22,@"%.1f pt"),
                                WXGSwitch(@"搜索框让主题优先",@"pref.localSearchThemeFirst",nil)],
                 @"FIX107：微信自己的控件保留（位置、点按、动作都不变），只把它们的底色换成玻璃（“其余玻璃”的折射、模糊、材质和边框）。搜索框：首页、通讯录、设置、收藏、新的朋友、表情搜索和点进去的搜索页都换成胶囊；搜一搜的结果页整页是网页，改不了。加号面板的 8 个方块是圆角方块，按下时玻璃跟着按压。两个圆角滑杆（FIX107 B）是连续圆角（和系统一样的平滑过渡），0 = 跟微信原来的一样（方块从微信自己的图上量，分组选中是 8 pt），最大到方块的一半就是圆形。表情面板右下角的发送、删除是胶囊，可以发送时发送键带微信原来的绿色；底部分组条里当前那一组的白色小方块换成玻璃。转发 / 分享弹层（图片和公众号文章右上角“…”是同一种）整块背景换成一块玻璃，着色比别处浓一些，文字才看得清。FIX108：顶栏标题（首页“微信(数量)”、通讯录、发现、聊天信息等）下面垫一个和两侧按钮等高的玻璃胶囊，文字还是微信自己的；网页那种很长或两行的标题不加，聊天页的标题本来就是胶囊。选照片时顶部“最近项目 ⌄”原来的灰色胶囊换成玻璃。网页、相册、收藏、卡包这类页面顶部的 ×、··· 原来没有玻璃（这些页面整页不走顶部按钮适配），现在在微信自己的图标后面垫一个同样大小的圆形玻璃；关掉“顶部按钮与背景适配”时一起关掉。只在同步渲染模式下生效。FIX109：表情分组选中块的玻璃改为放在微信那块白色方块旁边（白色本身遮掉），微信选中哪一格玻璃就立刻跟到哪一格，圆角滑杆改了马上生效（表情面板被微信留着反复用，以前要等它重新排版）。“插件”这类用系统标题的页面也加标题胶囊。选照片页左上角关闭按钮的玻璃和中间“最近项目 ⌄”胶囊一样高，其它按钮不变。搜索框让主题优先：默认关闭，玻璃优先——主题插件给搜索框换的图片会被藏到玻璃下面，主题清空了微信的白色底也照样找到搜索框；打开后，只要主题换了搜索框（图片或清空底色），就保持主题的样子、不加玻璃。FIX115 J：发起群聊 / 选择联系人页的搜索框也换成胶囊（选中的人的头像照旧在里面滚动）。带颜色的按钮：微信自己带底色的按钮（字体大小、聊天背景右上角的“完成”，选择联系人底部的“完成”等）换成玻璃胶囊，颜色跟着微信给它的底色走——能点时是微信的绿色，不能点时是普通玻璃；在顶栏里和顶栏其它玻璃一样高，别的地方和按钮本身一样大；文字和点按还是微信自己的。只在微信保留自己按钮的地方生效（弹出的页面、底部工具条等），插件自己接管顶栏按钮的页面照旧由插件的按钮来画。FIX115 Q：朋友圈新消息横幅和 ·· 按钮——“N条新消息”横幅原来的灰色圆角底换成玻璃胶囊（两头半圆），左边的头像变成圆形，和胶囊左端同心；文字跟着外观（深色白、浅色黑）。每条动态右下角呼出赞 / 评论的 ·· 按钮，灰色小底框换成同样大小的玻璃胶囊，两个点还是微信的。评论区不改。FIX115 S：视频号第一页（视频流）微信自己的按钮下面垫胶囊，没有材质覆盖，折射和其余玻璃一样，边框用“边框与渐隐”里单独的“视频号”范围（浅色、深色各一套）；视频号所有页面顶部按钮离屏幕两边的距离是“顶部按钮”里的“视频号顶部按钮离屏幕两边”（第一页微信的图标连同胶囊一起挪过去），不用“顶部按钮离屏幕两边”。顶部中间“赞和收藏”“最近看过”这类切换标签保持微信原生，不垫玻璃；个人页“设置”这类文字按钮是合适大小的胶囊。FIX115 T：离开视频号第一页（返回或进下一页）一开始，玻璃和微信那几个顶部图标一起消失（图标挪过位置，系统转场时拿的那份拷贝会被切掉一块，所以不显示）；滑一半松手回来时，图标先挪好再和玻璃一起淡入，不会先在原位置闪一下。FIX115 U：进入视频号第一页（从发现进来、从个人页返回）的转场过程中胶囊不显示，转场结束后再淡入（0.2 秒），不会在滑进来时边缘闪亮边。"),
        WXGGroup(@"标题与比例",nil,@[WXGSwitch(@"聊天标题使用头像 + 小胶囊",@"pref.avatarTitle",nil),
                                  WXGSwitch(@"不用头像标题时，聊天页顶部保持微信原生",@"chatNativeBar",nil),
                                  WXGSwitch(@"其它页面顶部按钮也保持微信原生",@"navNativeButtons",nil),
                                  WXGSwitch(@"原生按钮放进插件自己的玻璃按钮（稳定）",@"navNativeLook",nil),
                                  WXGSwitch(@"聊天右上角按钮显示头像",@"pref.chatAvatarButton",nil),
                                  WXGSlider(@"头像按钮内边距",@"chatAvatarInset",nil,0,12,@"%.1f pt"),
                                  WXGSlider(@"截图比例微调",@"pref.sizeScale",nil,.85,1.20,@"%.2f"),
                                  WXGSlider(@"顶部按钮离屏幕两边",@"navEdge",nil,8,36,@"%.1f pt"),
                                  WXGSlider(@"视频号顶部按钮离屏幕两边",@"finderEdge",nil,0,30,@"%.1f pt"),
                                  WXGSlider(@"顶部按钮往下移",@"navOffsetY",nil,0,16,@"%.1f pt")],
                 @"顶部按钮离屏幕两边 / 往下移（FIX114 C）：顶部一排（两侧按钮和中间的标题胶囊）离屏幕左右边的距离（左右一样，默认 20 pt，就是以前的位置），以及整排往下挪多少（默认 0，紧贴状态栏下面）；每个页面都一样：插件画的按钮、首页左上角和右上角、保持微信原生的按钮和标题（连同后面的胶囊），以及这几页设置自己的顶部。往下移时聊天页的置顶消息、首页的分组栏跟着往下；视频号第一页（视频流）在视频上，不动；视频号所有页面离屏幕两边的距离用下面单独的“视频号顶部按钮离屏幕两边”（FIX115 S，默认 14 pt）。两个值和按钮大小一样按屏幕宽度和截图比例缩放（440 pt 宽、比例 1.00 时就是填的 pt）。往上挪会压到状态栏，所以最少是 0。不用头像标题时，聊天页顶部保持微信原生（FIX114 B，默认开）：返回按钮（箭头和未读数）、右上角按钮和标题都是微信自己的图标、文字和位置，后面各垫一块自适应宽度的玻璃胶囊（由“更多玻璃”里的“标题换成玻璃胶囊”“网页、弹出页面的顶部按钮”画，关掉那两项就没有胶囊）；右上角显示头像开着时，那个按钮还是插件画的头像。关掉恢复以前插件自己画的返回胶囊和标题。其它页面顶部按钮也保持微信原生（默认关）：首页和视频号第一页以外的页面也这样——按钮是微信自己的图标、文字和位置，后面垫胶囊；最外面那个按钮的胶囊离屏幕边不是“顶部按钮离屏幕两边”的距离时，那一侧整组挪过去（FIX114 C 起两个方向都挪，最多 32 pt）。默认标题是与两侧等高的自适应胶囊。头像模式找不到现有真实头像时显示灰底白色人像的占位图。FIX114 V：原生按钮放进插件自己的玻璃按钮（默认开）——保持微信原生的那些顶部按钮不再在微信的按钮里垫玻璃，而是和插件自己画的按钮一样放在插件自己那一层（同样的位置、同样的推入 / 返回 / 半返回效果），玻璃里是微信原来按钮的图标、文字和未读数的一份拷贝（大小、颜色、位置都照微信的），真的微信按钮藏起来，点击照样转给它。微信在转场时换按钮、截图都不会再影响胶囊。关掉回到以前在微信按钮里垫玻璃的做法。原生未读数决定返回圆形或长胶囊。比例同时作用于这几页顶部的按钮。FIX109：聊天右上角按钮显示头像——还是原来那个按钮（点了照样进聊天信息），玻璃里画对方的头像（群聊是群头像，找不到时是占位图），描边用下面“头像模式”的描边设置；内边距是头像离玻璃边缘的距离，0 就是头像铺满整块玻璃。"),
        WXGGroup(@"头像模式",nil,@[WXGSlider(@"头像大小",@"avatarSize",nil,32,88,@"%.0f pt"),WXGSlider(@"头像上下位置",@"avatarOffsetY",nil,-24,24,@"%+.1f pt"),
                                WXGSlider(@"头像下小胶囊高度",@"avatarCapsuleHeight",nil,22,48,@"%.0f pt"),
                                WXGSlider(@"头像下胶囊文字大小",@"avatarCapsuleTextSize",nil,11,20,@"%.1f pt"),
                                WXGSwitch(@"头像下胶囊显示箭头",@"avatarCapsuleChevron",nil),
                                WXGSlider(@"头像下胶囊箭头大小",@"avatarCapsuleChevronSize",nil,8,24,@"%.1f pt"),
                                WXGAction(@"套用 iOS 26 截图的胶囊比例",@"avatarCapsuleIOS",NO),
                                WXGSlider(@"置顶与小胶囊间距",@"pinnedGapAdjust",nil,-16,16,@"%+.1f pt"),
                                WXGSlider(@"头像描边宽度",@"avatarBorderWidth",nil,0,4,@"%.2f pt"),
                                WXGColorRow(@"头像描边颜色（浅色模式）",@"avatarBorderHex",nil),WXGColorRow(@"头像描边颜色（深色模式）",@"avatarDarkBorderHex",nil)],
                 @"FIX95：打开上面的“聊天标题使用头像 + 小胶囊”后生效。头像没有玻璃，整圆铺满，在标题胶囊上面一层。大小按头像自己的中心缩放，标题胶囊位置不变；上下位置正数往下。描边画在头像圆形的内侧，颜色可以带透明度，浅色、深色各一个；宽度 0 为不描边。FIX109：头像下小胶囊高度——胶囊的上沿位置不变（压在头像下沿里 5 pt），往下变高或变矮。FIX114 M：文字大小单独调（头像下胶囊文字大小，默认 15 pt，以前固定 17 pt），和胶囊高度无关——胶囊加高只是让字周围更空，字不跟着变；只有胶囊矮到放不下这个字号时（字号超过高度的 0.62 倍）字才缩小。头像下胶囊显示箭头：仿 iOS 26 信息 App，名字右边一个灰色的窄粗箭头（系统图标 chevron.compact.right），点胶囊或头像都和点右上角一样进聊天信息；标题显示“对方正在输入…”时不显示箭头；箭头大小是它的高度（FIX114 N，默认 14.5 pt；M 是 12 pt 左右）。FIX114 O：有箭头时胶囊左边留 14 pt、箭头右边留 11 pt（和 iOS 26 截图量的 13.7 / 11 一样，不再两边相等）；“套用 iOS 26 截图的胶囊比例”把高度、文字、箭头设成截图里的约 29 / 17 / 12 pt。右上角按钮保持微信原生时，点头像和胶囊也进聊天信息。聊天里有置顶消息时，置顶条会整体下移，和小胶囊（或更低的头像）保持默认胶囊模式下同样的间距（约 8 pt）；“置顶与小胶囊间距”在这个基础上加减，负数更近，0 就是和默认模式一样。"),
        WXGGroup(@"交互",nil,@[WXGSwitch(@"触感反馈",@"haptics",nil),WXGSwitch(@"按住拖动拉伸玻璃按钮",@"pressStretch",nil),WXGSwitch(@"首页左上角和三段输入两侧也拉伸",@"pressStretchNative",nil),
                             WXGSlider(@"最大拉动距离",@"pressStretchDistance",nil,0,32,@"%.0f pt"),WXGSlider(@"拉伸强度",@"pressStretchAmount",nil,0,1.5,@"%.2f"),
                             WXGSlider(@"最大拉伸幅度",@"pressStretchMax",nil,1,20,@"%.1f pt"),WXGSlider(@"胶囊拉伸程度",@"pressStretchCapsule",nil,0,1,@"%.2f"),
                             WXGSlider(@"跟手移动",@"pressStretchFollow",nil,0,1,@"%.2f"),
                             WXGSlider(@"拖动与变形的比例（拖几 pt 算 1 pt）",@"pressStretchRatio",nil,1,12,@"%.1f")],
                 @"按住导航按钮、标题、输入栏两侧的按钮、首页左上角按钮或底栏搜索按钮再拖动：玻璃朝手指方向拉长、另一个方向变窄（远离手指的一侧几乎不动，靠近手指的一侧伸出去），整体再跟着手指移动一点。拉动距离越拉越难，最多按“最大拉动距离”算（按 44 pt 的按钮算，小一点和大一点的按钮按比例）；拉伸强度是每拉 1 pt 拉长多少 pt（变窄是一半）；最大拉伸幅度是最多拉长多少 pt，越接近越拉不动；跟手移动是玻璃跟着手指移动拉动距离的多少（0 就是原地不动，1 是完全跟手），移动和拉伸来自同一个拉动距离，拉得越远两者都越大。胶囊、圆角矩形这类不是圆的玻璃只沿上下、左右拉伸，不会斜着变形，程度是圆形按钮的“胶囊拉伸程度”倍。手指按住期间一直拉着，松手才用弹簧弹回（会过冲一下）；在按钮 40 pt 以内松手是点击，更远就是放弃点击。首页左上角按钮和三段输入两侧的触摸仍由微信处理，上面微信自己的图标也跟着玻璃一起变形（只是画面跟着变，点击位置不受影响）。输入文字的那块胶囊（两种输入栏都是）固定不动：点按、拖动都不放大、不拉伸，点它里面的按钮只有按钮图标自己有按下效果。系统“减弱动态效果”打开时不拉伸。拖动与变形的比例（FIX115 L；默认 3，1–12）：手指在屏幕上拖多少 pt 才算拉动 1 pt，上面的拉动距离、拉伸、跟手移动都按折算后的拉动来算——3 就是拖 3 pt 玻璃才“被拉”1 pt；往左更灵敏，1 就是以前的样子；往右越来越难拉动，8 就很不容易被拉变形。N 版存下的 8（不管是 N 的默认、自动改的还是手调的）装上 O 后回到 3 一次，之后再调的值不会被改。关掉“按住拖动拉伸玻璃按钮”就完全没有拉伸，回到原来按下微微放大的效果；只关“首页左上角和三段输入两侧也拉伸”时，这几处只保留按下效果，其余按钮照常拉伸。"),
        WXGGroup(@"消息长按菜单",nil,@[WXGSlider(@"菜单圆角",@"messageMenuCornerRadius",nil,0,40,@"%.0f pt")],
                 @"长按消息弹出菜单的玻璃圆角。若微信的菜单容器本身裁剪了更小的圆角，以较小者为准。"),
        WXGGroup(@"“我”页头部",nil,@[WXGSwitch(@"Telegram 式头部（头像收进灵动岛）",@"meHeader",nil),
                                 WXGSwitch(@"下拉展开头像横幅（替换微信的下拉状态）",@"meBanner",nil),
                                 WXGChoice3(@"横幅下边缘",@"meBannerEdgeStyle",nil,nil,@[@"液滴",@"渐隐",@"直边"],NO),
                                 WXGAction(@"选择横幅视频（相册）",@"meBannerVideo",NO),WXGAction(@"清除横幅视频",@"meBannerVideoClear",YES),
                                 WXGSlider(@"头像大小",@"meAvatarSize",nil,70,130,@"%.0f pt"),
                                 WXGSwitch(@"刘海屏：头像融进刘海",@"meNotchMerge",nil),
                                 WXGSlider(@"灵动岛 / 刘海位置微调（上下）",@"meCutoutY",nil,-8,8,@"%.1f pt"),
                                 WXGSlider(@"灵动岛 / 刘海宽度微调",@"meCutoutW",nil,-30,30,@"%.0f pt")],
                 @"FIX118 A：“我”页改成 Telegram 个人页的排法：头像居中变圆，下面居中是昵称、微信号和状态那两个按钮；二维码变成左上角的按钮，右上角“设置”直接打开本插件的设置；点头像进个人资料（FIX118 D 起不再单独放一条“个人资料”）。往上滑：头像变小、变模糊变暗，和灵动岛黏成一滴被吸进去，昵称滑到顶栏下面时顶栏中间出现小标题；松手停在一半时会自己回到“展开”或“收起”。灵动岛 / 刘海的位置按机型查表（Telegram 的各机型数据），对不准时用下面两个微调。刘海屏：开着“融进刘海”就和灵动岛一样黏进去，关掉就只缩小淡出（Telegram 在刘海屏上的做法）。“下拉展开头像横幅”打开后，往下拉“我”页不再拉出微信的状态页，而是头像撑开成整宽的横幅、下边缘像液体一样流动并滴落（状态仍可以从头像下面的状态按钮进）；关掉就是微信原来的下拉。FIX118 B：拉过约 100 pt 松手（或快速一甩）横幅停住展开，往上推收回；“选择横幅视频”从相册选一段视频，展开时淡入、静音循环播放，没选就是头像。FIX118 E/F：“横幅下边缘”可选液滴、渐隐（横幅下面约三分之一逐渐变透明，自然过渡到微信页面，不镜像）或直边；液滴：液滴的颜色是横幅在边缘处的镜像（越往下越模糊），横幅打开时下面的昵称和列表会再往下让一点，液滴只在这段空隙里垂下和滴落，不挡昵称。"),
        WXGGroup(@"首页加号菜单",nil,@[WXGSwitch(@"左侧玻璃胶囊 + 右侧圆形图标",@"homeMenuCapsules",nil),
                                  WXGSlider(@"图标大小",@"homeMenuIconSize",nil,34,56,@"%.0f pt"),
                                  WXGSlider(@"逐项出现的间隔",@"homeMenuStagger",nil,0,80,@"%.0f ms"),
                                  WXGSlider(@"动画速度",@"homeMenuSpeed",nil,.5,2,@"%.2f 倍")],
                 @"FIX116 A/B：点首页右上角的加号，菜单每一项变成左边一个玻璃胶囊（放标题）、右边一个圆形玻璃图标，图标和加号对齐；点按、动作、开合都还是微信自己的（只换看得见的部分）。入场：从上到下一项一项出现，图标先弹出来，胶囊从图标处向左展开，标题最后淡入，没有翻转；每一项比上一项晚出现的间隔越来越短。关掉这个开关就回到原来的一整块玻璃垫在微信菜单下面。图标大小就是圆形图标的直径（默认 44 pt，和加号差不多大），胶囊高是它的 0.78，微信自己一行放不下时图标会自动变小；间隔 = 第一项和第二项之间隔几毫秒；动画速度 2 倍 = 时间减半（弹簧的阻尼比不变，形状一样）。系统开了“减弱动态效果”时只淡入。FIX116 B：关闭（再点加号，或点别处）时有自己的退场动画，从打开时的位置倒着收：从最下面一项开始，标题先淡出，胶囊向图标收回，图标缩小并向加号靠，一共约 0.33 秒（动画速度也管它）；不再跟着微信的关闭动画走（以前会先往下掉一截再消失）。"),
        WXGGroup(@"性能",nil,@[WXGSwitch(@"流畅模式",@"performanceMode",nil)],
                 @"每块玻璃只用一层背景：不做 RGB 色散和边缘清晰环，背景最多按 2 倍采样（原来最多 6 层、按屏幕倍数）。滑动或转场卡顿、发热时打开对比；关闭时与之前完全一样。设置页的卡片始终是这种画法。"),
        WXGGroup(@"诊断",nil,@[WXGAction(@"材质、位置与性能诊断",@"diagnostics",NO),WXGAction(@"导出各页诊断 JSON",@"export",NO),
                             WXGSwitch(@"任意页面导出诊断（浮动按钮）",@"diagnosticsFloat",nil),
                             WXGSwitch(@"悬浮按钮打开 / 收起设置（调参对比）",@"settingsFloat",nil)],
                 @"FIX114 R：打开后每个页面左边都有一个小的“导出诊断”按钮（可以拖到别处），在哪一页点它，导出的就是那一页当时的诊断（比如聊天页），不用再进设置。FIX115 G：“悬浮按钮打开 / 收起设置”打开后每个页面右边有一个小的“设置”按钮（也能拖），点一下设置页直接盖在当前页面上淡入，再点（按钮变成“收起”）就淡出，回到刚才的页面——页面在底下一直保持原样，玻璃不用重画；再打开还是上次停的那一页、滚到的位置，方便一边调参数一边和 iOS 26 原生对比。从设置首页左上角返回也能关。开着的时候插件还会一帧一帧记下顶部按钮、标题和它们后面玻璃的位置和透明度（只记有变化的帧，最近几千条），所以跳动、缺失发生后马上点它导出，就能看到是哪一帧、哪个按钮出了问题，不用录屏。平时用不到时关掉（记录有一点点耗电）。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复全部默认参数",@"reset",YES)],
                 @"FIX115 H：所有玻璃参数（每个范围的折射、模糊、材质、边框，底栏、分组、透镜、气泡、渐隐、菜单圆角……）、各项功能开关、整体比例和卡片圆角回到本版的标准参数（和设置首页的“恢复默认参数”一样）。总开关、两个悬浮按钮、壁纸、头像、强调色和自己建的分组不变；不覆写旧 demo 的 config.v9。")]};
    if([module isEqual:@"refraction"])return @{@"title":@"折射强度和色散",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"bubble",@"segment",@"card"],@"groups":WXGWithShare(@[
        WXGGroup(@"底栏本体",@"dock",@[WXGSlider(@"折射强度",@"dockRefraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"dockDispersion",nil,0,8,nil),
                                      WXGSlider(@"折射宽度",@"dockEdgeWidth",nil,1,60,@"%.1f pt"),WXGSlider(@"边界过渡",@"dockRefractionTransition",nil,0,1,@"%.2f"),
                                       WXGSlider(@"过渡宽度（0 = 自动）",@"dockRefractionTransitionWidth",nil,0,60,@"%.1f pt"),WXGSlider(@"边缘最大拉伸",@"dockRefractionTransitionStretch",nil,1.2,6,@"%.1f 倍"),WXGSlider(@"过渡曲线",@"dockRefractionTransitionCurve",nil,1.5,4,@"%.2f")],
                 @"底栏静止时的玻璃。按下时透镜从这里平滑过渡到下面的透镜参数（透镜不受边界过渡影响）。\n" WXG_TRANSITION_NOTE),
        WXGGroup(@"透镜折射取景",@"dock",@[WXGSlider(@"边缘偏移抵消",@"lensOffsetCancel",nil,0,1,@"%.2f")],
                 @"边缘偏移抵消（FIX113 I）：折射带越宽、越强，透镜边缘一圈取的内容就越往里（强度 20、宽度 8 pt 时约 50 pt），边缘下面的图标被跳过、看不见。这一项把这个偏移抵消掉：0 = 原来的样子；1 = 边缘和折射带内侧都显示它们正下方的东西，折射带只在中间把内容弯折——靠边缘压缩（最多约 2.5 倍）、过了一半拉伸，所以加宽折射范围只会让畸变的一圈变宽，图标都还在原位附近（离原位最多约 0.3 个折射宽度），也不会翻折。强度到约 6 以上时抵消后的弯折已到最大，不再变强；色散不受影响。中间值是两者的混合。需要服务器换上 FIX113 I 的着色器（诊断 lensOffsetCancel.available 为 true）才生效。"),
        WXGGroup(@"透镜（按压时）",@"dock",@[WXGSlider(@"透镜折射强度",@"lensRefraction",nil,0,20,nil),WXGSlider(@"透镜 RGB 色散",@"lensDispersion",nil,0,8,nil),
                                         WXGSlider(@"透镜折射宽度（两端）",@"lensEdgeWidth",nil,1,60,@"%.1f pt"),
                                         WXGSlider(@"图标和文字的折射强度",@"lensIconRefraction",nil,0,20,nil),
                                         WXGSlider(@"图标和文字的折射宽度",@"lensIconEdgeWidth",nil,1,60,@"%.1f pt"),
                                         WXGSlider(@"图标和文字的上下宽度比例",@"lensIconTopEdgeRatio",nil,.1,1,nil),
                                         WXGSlider(@"图标和文字的上下收窄曲线",@"lensIconEdgeSharpness",nil,1,6,nil),
                                         WXGSlider(@"上下折射宽度比例",@"lensTopEdgeRatio",nil,.1,1,nil),
                                         WXGSlider(@"上下收窄曲线",@"lensEdgeSharpness",nil,1,6,nil),
                                         WXGSlider(@"透镜色散范围（两端）",@"lensDispersionWidth",nil,1,60,@"%.1f pt"),
                                         WXGSlider(@"上下色散范围比例",@"lensDispersionTopRatio",nil,.1,1,nil)],
                 @"图标和文字的折射强度 / 宽度（FIX113 X）：透镜里的图标和标题（以及静止时的选中色，它按压时就淡掉了）单独用这一组（第一次打开时和上面的透镜折射强度、宽度一样；FIX113 Y：上下宽度比例和收窄曲线也各用各的，第一次打开时和下面的一样），透镜里的其余部分——缩小的底栏、它的边框和背景、外面的页面——还用上面的“透镜折射强度”“透镜折射宽度”。只在“透镜直接折射底下的底栏”开着时分开（关着时透镜里的底栏是另画的，和图标一起用上面的）。色散、放大倍数两边共用。透镜的边框（FIX96）：透镜和选中胶囊用系统的连续圆角（iOS 的形状）；着色器算折射、透镜里的底栏和描边时，也按在你手机上量出的连续圆角曲线走（以前按圆形算，在顶边转进圆角处和系统外框差约 0.4 pt，看起来边框在圆角处最细、顶上又变宽），所以边框从两端到上下边一路变窄，上下最细。透镜的折射和色散独立于底栏本体。上下比例 1 为与两端相同；收窄曲线越大，离开两端越快收窄。到底栏两端时，弯曲底栏和页面的折射范围放松到上下边的宽度（FIX57）。色散有自己的范围（FIX88，像 iOS 26 的透镜）：从轮廓往里多宽内有颜色分离，可以比折射宽度更宽或更窄，上下同样按比例收窄（收窄曲线和折射共用）；第一次打开时和折射宽度、上下比例相同，看起来不变。"),
        WXGGroup(@"镜内底栏色散",@"dock",@[WXGSwitch(@"镜内底栏边缘色散",@"lensBarDispersionOn",nil),
                                       WXGSlider(@"整片透镜的色散（边缘处）",@"lensBarDispersion",nil,0,2,@"%.2f pt"),
                                       WXGSlider(@"两端加强（透镜色散的比例）",@"lensBarDispersionNearRim",nil,0,1,nil)],
                 @"只在关掉“透镜”里的“透镜直接折射底下的底栏”时有用（打开时透镜折射的是真实的底栏，色散就是透镜自己的 RGB 色散）。FIX97：透过透镜看到的底栏也有色散，不只透镜两端：上下深色槽的“括号”边、底栏的描边高光，都会按连续光谱散开成一圈柔和的彩边（外侧偏红、内侧偏蓝，不是三条分开的红绿蓝线）。“整片透镜的色散”像一块圆顶玻璃：透镜中心为 0，越往边缘越大，这里填的是到透镜边缘时的偏移；“两端加强”是在透镜折射底栏最厉害的地方（两端宽的折射带，上下随折射宽度比例变弱）再加上透镜自身色散的这个比例，所以靠近两端最明显。只在按下（透镜浮起）时出现，松开随按压程度消失；两个都调到 0 或关闭开关，和 FIX96 完全一样。只在同步渲染模式下生效。"),
        WXGGroup(@"其余玻璃",@"other",@[WXGSlider(@"折射强度",@"refraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"dispersion",nil,0,8,nil),
                                       WXGSlider(@"折射宽度",@"edgeWidth",nil,1,60,@"%.1f pt"),WXGSlider(@"边界过渡",@"refractionTransition",nil,0,1,@"%.2f"),
                                       WXGSlider(@"过渡宽度（0 = 自动）",@"refractionTransitionWidth",nil,0,60,@"%.1f pt"),WXGSlider(@"边缘最大拉伸",@"refractionTransitionStretch",nil,1.2,6,@"%.1f 倍"),WXGSlider(@"过渡曲线",@"refractionTransitionCurve",nil,1.5,4,@"%.2f")],
                 @"折射宽度是从轮廓向内的距离，范围外不位移。\n" WXG_TRANSITION_NOTE),
        WXGGroup(@"液态气泡",@"bubble",@[WXGSlider(@"折射强度",@"bubbleRefraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"bubbleDispersion",nil,0,8,nil),
                                       WXGSlider(@"折射宽度",@"bubbleEdgeWidth",nil,1,60,@"%.1f pt"),WXGSlider(@"边界过渡",@"bubbleRefractionTransition",nil,0,1,@"%.2f"),
                                       WXGSlider(@"过渡宽度（0 = 自动）",@"bubbleRefractionTransitionWidth",nil,0,60,@"%.1f pt"),WXGSlider(@"边缘最大拉伸",@"bubbleRefractionTransitionStretch",nil,1.2,6,@"%.1f 倍"),WXGSlider(@"过渡曲线",@"bubbleRefractionTransitionCurve",nil,1.5,4,@"%.2f"),WXGSwitch(@"气泡用完整玻璃",@"bubbleFullGlass",nil),
                                       WXGSwitch(@"气泡共用一次背景采样（省 GPU）",@"bubbleSharedBackdrop",nil)],
                 @"聊天里液态气泡自己的折射，第一次打开时和“其余玻璃”相同。气泡默认是轻量玻璃（一层背景，没有 RGB 色散和边缘清晰环，最多 2 倍采样），所以色散要打开“气泡用完整玻璃”才看得到；完整玻璃每个气泡最多 6 层背景，消息多时滑动更吃力，可以用帧率检测对比。\n" WXG_TRANSITION_NOTE),
        WXGGroup(@"分组栏",@"segment",@[WXGSlider(@"折射强度",@"segmentRefraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"segmentDispersion",nil,0,8,nil),
                                       WXGSlider(@"折射宽度",@"segmentEdgeWidth",nil,1,60,@"%.1f pt"),WXGSlider(@"边界过渡",@"segmentRefractionTransition",nil,0,1,@"%.2f"),
                                       WXGSlider(@"过渡宽度（0 = 自动）",@"segmentRefractionTransitionWidth",nil,0,60,@"%.1f pt"),WXGSlider(@"边缘最大拉伸",@"segmentRefractionTransitionStretch",nil,1.2,6,@"%.1f 倍"),WXGSlider(@"过渡曲线",@"segmentRefractionTransitionCurve",nil,1.5,4,@"%.2f")],
                 @"聊天列表分组栏静止时的玻璃（FIX113 O 起它自己一个范围，FIX113 P 起默认和底栏一样）。按住时透镜的参数在“分组”页。\n" WXG_TRANSITION_NOTE),
        WXGGroup(@"设置页",@"card",@[WXGSlider(@"折射强度",@"cardRefraction",nil,0,20,nil),WXGSlider(@"RGB 色散",@"cardDispersion",nil,0,8,nil),
                                    WXGSlider(@"折射宽度",@"cardEdgeWidth",nil,1,60,@"%.1f pt"),WXGSlider(@"边界过渡",@"cardRefractionTransition",nil,0,1,@"%.2f"),
                                       WXGSlider(@"过渡宽度（0 = 自动）",@"cardRefractionTransitionWidth",nil,0,60,@"%.1f pt"),WXGSlider(@"边缘最大拉伸",@"cardRefractionTransitionStretch",nil,1.2,6,@"%.1f 倍"),WXGSlider(@"过渡曲线",@"cardRefractionTransitionCurve",nil,1.5,4,@"%.2f")],
                 @"本插件这几页设置里的卡片和标题栏按钮（FIX113 O 起单独一个范围），第一次打开时和“其余玻璃”相同。\n" WXG_TRANSITION_NOTE),
        WXGGroup(@"色散方式",nil,@[WXGSwitch(@"RGB 色散",@"syncDispersion",nil)],
                 @"用红绿蓝三层背景实现色散，三种范围共用。若玻璃整体偏色可关闭。")],WXGShareGroups(0)),@"sharePage":@0};
    if([module isEqual:@"blur"])return @{@"title":@"模糊强度与范围",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"bubble",@"segment",@"card"],@"groups":WXGWithShare(@[
        WXGGroup(@"底栏本体",@"dock",@[WXGSlider(@"模糊半径",@"dockBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"dockBlurCoverage",nil,0,100,@"%.0f%%"),WXGSlider(@"背景饱和度",@"dockBackdropSaturation",nil,0,3,@"%.2f"),WXGSlider(@"背景亮度",@"dockBackdropBrightness",nil,-.3,.3,@"%+.2f")],
                 WXG_TONE_NOTE @"\n底栏的透镜（按下时）和点按时滑过去的那块也用底栏这两项。"),
        WXGGroup(@"透镜（按压时）",@"dock",@[WXGSlider(@"透镜模糊半径",@"lensBlur",nil,0,12,@"%.2f pt"),
                                         WXGSlider(@"透镜模糊覆盖扩展",@"lensBlurCoverage",nil,0,100,@"%.0f%%")],
                 @"透镜模糊默认 0（关闭）。按下时从底栏本体的模糊平滑过渡到这里。"),
        WXGGroup(@"其余玻璃",@"other",@[WXGSlider(@"模糊半径",@"blur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"blurCoverage",nil,0,100,@"%.0f%%"),WXGSlider(@"背景饱和度",@"backdropSaturation",nil,0,3,@"%.2f"),WXGSlider(@"背景亮度",@"backdropBrightness",nil,-.3,.3,@"%+.2f")],
                 @"仍是 TEST9 的半径与覆盖扩展。\n" WXG_TONE_NOTE),
        WXGGroup(@"液态气泡",@"bubble",@[WXGSlider(@"模糊半径",@"bubbleBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"bubbleBlurCoverage",nil,0,100,@"%.0f%%"),WXGSlider(@"背景饱和度",@"bubbleBackdropSaturation",nil,0,3,@"%.2f"),WXGSlider(@"背景亮度",@"bubbleBackdropBrightness",nil,-.3,.3,@"%+.2f")],
                 @"液态气泡自己的模糊，第一次打开时和“其余玻璃”相同。\n" WXG_TONE_NOTE),
        WXGGroup(@"分组栏",@"segment",@[WXGSlider(@"模糊半径",@"segmentBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"segmentBlurCoverage",nil,0,100,@"%.0f%%"),WXGSlider(@"背景饱和度",@"segmentBackdropSaturation",nil,0,3,@"%.2f"),WXGSlider(@"背景亮度",@"segmentBackdropBrightness",nil,-.3,.3,@"%+.2f")],
                 @"分组栏自己的模糊，默认和底栏一样。按住时透镜的模糊在“分组”页。\n" WXG_TONE_NOTE),
        WXGGroup(@"设置页",@"card",@[WXGSlider(@"模糊半径",@"cardBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"模糊覆盖扩展",@"cardBlurCoverage",nil,0,100,@"%.0f%%"),WXGSlider(@"背景饱和度",@"cardBackdropSaturation",nil,0,3,@"%.2f"),WXGSlider(@"背景亮度",@"cardBackdropBrightness",nil,-.3,.3,@"%+.2f")],
                 @"设置页卡片和按钮的模糊，第一次打开时和“其余玻璃”相同。\n" WXG_TONE_NOTE),
        WXGGroup(@"清晰度",nil,@[WXGSlider(@"模糊倍率",@"syncBlurScale",nil,.5,3,nil),WXGSlider(@"采样倍率",@"syncCaptureScale",nil,0,3,nil)],
                 [NSString stringWithFormat:@"三种范围共用。模糊倍率把 TEST9 模糊半径换算成系统高斯。采样倍率 0 = 跟随屏幕（本机 %.0f，设成 %.0f 与 0 相同）；调低能减轻 GPU 负担，但会变糊。",
                  UIScreen.mainScreen.scale,UIScreen.mainScreen.scale])],WXGShareGroups(1)),@"sharePage":@1};
    if([module isEqual:@"material"])return @{@"title":@"材质强度与范围",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"segment",@"card"],@"groups":WXGWithShare(@[
        WXGGroup(@"边缘减弱",nil,@[WXGSwitch(@"在边缘减弱",@"materialEdgeFadeEnabled",@"dockMaterialEdgeFadeEnabled"),
                                 WXGSlider(@"减弱范围",@"materialEdgeFade",@"dockMaterialEdgeFade",0,60,@"%.1f pt")],
                 @"开启后，材质遮盖从玻璃轮廓开始在“减弱范围”内由弱到强，范围以内完全覆盖；关闭或范围为 0 时整块完全覆盖。"),
        WXGGroup(@"浅色模式",nil,@[WXGColorRow(@"材质底色",@"materialHex",@"dockMaterialHex"),
                                 WXGSlider(@"材质遮盖",@"materialOpacity",@"dockMaterialOpacity",0,.95,nil)],nil),
        WXGGroup(@"深色模式",nil,@[WXGColorRow(@"材质底色",@"darkMaterialHex",@"dockDarkMaterialHex"),
                                 WXGSlider(@"材质遮盖",@"darkMaterialOpacity",@"dockDarkMaterialOpacity",0,.95,nil)],nil),
        WXGGroup(@"通用",nil,@[WXGSwitch(@"清透材质",@"clearMaterial",nil)],@"各范围共用。关闭时材质遮盖加强约 22%。分组栏的底色就是它“分组”范围的材质（浅色 / 深色模式各一），也可以在“分组”页里调。")],WXGShareGroups(2)),@"sharePage":@2};
    // FIX85: three rim styles, each with its own values (only the chosen
    // style's groups are shown), in three ranges: dock, other glass, bubbles.
    // FIX86: each range has its own style.
    if([module isEqual:@"border"])return @{@"title":@"边框与渐隐",@"scoped":@YES,@"scopes":@[@"dock",@"other",@"bubble",@"segment",@"card",@"lens",@"segmentLens",@"finder"],@"groups":WXGWithShare(@[
        WXGGroup(@"边框样式",nil,@[WXGBare(WXGChoice3(@"样式",@"rimStyle",@"dockRimStyle",@"bubbleRimStyle",@[@"普通",@"取自背景",@"iOS 27"],YES))],
                 @"底栏、其余玻璃、气泡三个范围各选各的样式（上面切换范围），互不影响：比如底栏用 iOS 27、其余玻璃取自背景、气泡用普通。三种样式各用各的参数，互不共享，下面只显示当前范围所选样式的设置（换样式时，其它样式的值保持不变）。普通：一条等宽的线，颜色自己定。取自背景：线的颜色来自玻璃后面的背景，不透明度、宽度、亮度、渐隐都是它自己的。iOS 27：不是一条线，而是两道沿轮廓往里渐渐消失的光，各有颜色和最亮的方向，同时画。三种样式都是浅色、深色各一套（iOS 27 从 FIX113 Z 起也分开）；视频号（FIX115 S）：第一页顶部按钮下面的胶囊用单独的“视频号”范围，浅色、深色各一套，第一次打开时两套都和其余玻璃的深色模式一样。透镜（FIX113 X）：底栏和分组栏按住时浮起的透镜自己的边框是单独的范围，也能选这三种样式；第一次打开是普通样式，颜色、不透明度、宽度和以前的透镜边框一样；取自背景时取的是透镜里显示的内容（缩小的底栏、页面）。FIX114 C 起两处分开：“底栏透镜”只管底栏，“分组透镜”只管分组栏（第一次打开时和底栏透镜当时的设置一样，之后各调各的）。"),
        WXGStyled(WXGGroup(@"普通 · 柔和泛光",nil,@[WXGBubbleKey(WXGSwitch(@"线的内侧加一点泛光",@"rimInward",@"dockRimInward"),@"bubbleRimInward")],
                 @"FIX109 B：普通边框还是原来那条线（下面的“宽度”，实打实不变淡），只在它里侧紧挨着加一小段柔和的泛光，让边缘不那么生硬：泛光从“泛光亮度”（相对线本身的亮度）开始，在“泛光宽度”这么短的距离内平滑消失（高斯曲线，起头圆润、没有长尾巴），按四分之一像素一级画，所以 0.5–1 pt 这么短也是一段平滑的过渡，而不是 A 版那种整段都在渐隐。泛光亮度调到 1 就等于把线的里侧边缘柔化；宽度 0 或关掉开关就是原来的线。颜色、不透明度、亮度、左下 / 右上渐隐都用普通样式自己的。三个范围各自开关，浅色、深色各一套宽度和亮度。"),@[@0]),
        WXGStyled(WXGGroup(@"普通 · 浅色模式",nil,@[WXGColor3(@"边框颜色",@"rimHex",@"dockRimHex",@"bubbleRimHex"),
                                 WXGSlider3(@"不透明度",@"rimOpacity",@"dockRimOpacity",@"bubbleRimOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"barBorderWidth",@"dockBorderWidth",@"bubbleBorderWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"泛光宽度",@"rimSoftWidth",@"dockRimSoftWidth",@"bubbleRimSoftWidth",0,4,@"%.2f pt"),
                                 WXGSlider3(@"泛光亮度",@"rimSoftLevel",@"dockRimSoftLevel",@"bubbleRimSoftLevel",0,1,nil),
                                 WXGSlider3(@"亮度",@"rimBrightness",@"dockRimBrightness",@"bubbleRimBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"rimFade",@"dockRimFade",@"bubbleRimFade",0,1,nil)],
                 @"亮度 1 为原色，低于 1 变暗，高于 1 向白色混合。渐隐只在左下和右上两条对角（iOS 26 的描边）。“宽度”是线本身的宽度（打开柔和泛光时也一样），泛光加在它里面。"),@[@0]),
        WXGStyled(WXGGroup(@"普通 · 深色模式",nil,@[WXGColor3(@"边框颜色",@"darkRimHex",@"dockDarkRimHex",@"bubbleDarkRimHex"),
                                 WXGSlider3(@"不透明度",@"darkRimOpacity",@"dockDarkRimOpacity",@"bubbleDarkRimOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"darkBarBorderWidth",@"dockDarkBorderWidth",@"bubbleDarkBorderWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"泛光宽度",@"darkRimSoftWidth",@"dockDarkRimSoftWidth",@"bubbleDarkRimSoftWidth",0,4,@"%.2f pt"),
                                 WXGSlider3(@"泛光亮度",@"darkRimSoftLevel",@"dockDarkRimSoftLevel",@"bubbleDarkRimSoftLevel",0,1,nil),
                                 WXGSlider3(@"亮度",@"darkRimBrightness",@"dockDarkRimBrightness",@"bubbleDarkRimBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"darkRimFade",@"dockDarkRimFade",@"bubbleDarkRimFade",0,1,nil)],nil),@[@0]),
        WXGStyled(WXGGroup(@"取自背景 · 柔和泛光",nil,@[WXGBubbleKey(WXGSwitch(@"线的内侧加一点泛光",@"rimSampleSoft",@"dockRimSampleSoft"),@"bubbleRimSampleSoft")],
                 @"FIX109 C：和普通样式的柔和泛光一样——线本身（下面的“宽度”）不变，里侧紧挨着一小段从“泛光亮度”平滑消失的泛光，颜色照样取自玻璃后面的背景（自动），饱和度、提亮这些处理也一样。打开后“描边细节”的分级线不用。三个范围各自开关，浅色、深色各一套宽度和亮度；第一次打开时和普通样式的值相同。"),@[@1]),
        WXGStyled(WXGGroup(@"取自背景 · 浅色模式",nil,@[WXGSlider3(@"不透明度",@"rimSampleOpacity",@"dockRimSampleOpacity",@"bubbleRimSampleOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"rimSampleWidth",@"dockRimSampleWidth",@"bubbleRimSampleWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"泛光宽度",@"rimSampleSoftWidth",@"dockRimSampleSoftWidth",@"bubbleRimSampleSoftWidth",0,4,@"%.2f pt"),
                                 WXGSlider3(@"泛光亮度",@"rimSampleSoftLevel",@"dockRimSampleSoftLevel",@"bubbleRimSampleSoftLevel",0,1,nil),
                                 WXGSlider3(@"亮度",@"rimSampleBrightness",@"dockRimSampleBrightness",@"bubbleRimSampleBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"rimSampleFade",@"dockRimSampleFade",@"bubbleRimSampleFade",0,1,nil),
                                 WXGSlider(@"饱和度",@"rimSampleSaturation",nil,0,3,nil),
                                 WXGSlider(@"亮度增益",@"rimSampleGain",nil,.5,2.5,nil),
                                 WXGSlider(@"提亮（变浅）",@"rimSampleLift",nil,0,.6,nil),
                                 WXGSlider(@"对比度",@"rimSampleContrast",nil,.5,2,nil),
                                 WXGSlider(@"取色模糊",@"rimSampleBlur",nil,0,10,@"%.1f pt")],
                 @"线的颜色取自这块玻璃后面的背景（先模糊，免得文字的细节透出来），再处理：饱和度让颜色更鲜艳，亮度增益按比例变亮，提亮往白色靠（变浅），对比度 1 为不变。不透明度、宽度、亮度、渐隐是这个样式自己的，底栏、其余玻璃、气泡各一套；饱和度到取色模糊几项三个范围共用。液态气泡和设置页的卡片没有自己的背景取色，用材质颜色按同样的参数处理（透镜范围取的是透镜里显示的内容）。"),@[@1]),
        WXGStyled(WXGGroup(@"取自背景 · 深色模式",nil,@[WXGSlider3(@"不透明度",@"darkRimSampleOpacity",@"dockDarkRimSampleOpacity",@"bubbleDarkRimSampleOpacity",0,1,nil),
                                 WXGSlider3(@"宽度",@"darkRimSampleWidth",@"dockDarkRimSampleWidth",@"bubbleDarkRimSampleWidth",0,2,@"%.2f pt"),
                                 WXGSlider3(@"泛光宽度",@"darkRimSampleSoftWidth",@"dockDarkRimSampleSoftWidth",@"bubbleDarkRimSampleSoftWidth",0,4,@"%.2f pt"),
                                 WXGSlider3(@"泛光亮度",@"darkRimSampleSoftLevel",@"dockDarkRimSampleSoftLevel",@"bubbleDarkRimSampleSoftLevel",0,1,nil),
                                 WXGSlider3(@"亮度",@"darkRimSampleBrightness",@"dockDarkRimSampleBrightness",@"bubbleDarkRimSampleBrightness",0,2,nil),
                                 WXGSlider3(@"左下 / 右上渐隐",@"darkRimSampleFade",@"dockDarkRimSampleFade",@"bubbleDarkRimSampleFade",0,1,nil),
                                 WXGSlider(@"饱和度",@"darkRimSampleSaturation",nil,0,3,nil),
                                 WXGSlider(@"亮度增益",@"darkRimSampleGain",nil,.5,2.5,nil),
                                 WXGSlider(@"提亮（变浅）",@"darkRimSampleLift",nil,0,.6,nil),
                                 WXGSlider(@"对比度",@"darkRimSampleContrast",nil,.5,2,nil),
                                 WXGSlider(@"取色模糊",@"darkRimSampleBlur",nil,0,10,@"%.1f pt")],nil),@[@1]),
        WXGStyled(WXGGroup(@"取自背景 · 颜色覆盖",nil,@[WXGColor3(@"浅色模式",@"rimSampleOverlayHex",@"dockRimSampleOverlayHex",@"bubbleRimSampleOverlayHex"),
                                 WXGColor3(@"深色模式",@"darkRimSampleOverlayHex",@"dockDarkRimSampleOverlayHex",@"bubbleDarkRimSampleOverlayHex")],
                 @"FIX114 J：和气泡一样给边框选一种颜色：从背景取到的颜色先按这个颜色的不透明度往它靠（不透明度 0 = 不覆盖，和以前一样；1 = 完全用这个颜色），再做上面的饱和度、提亮这些处理。每个范围各一套，浅色、深色模式分开。"),@[@1]),
        WXGStyled(WXGGroup(@"取自背景 · 叠加",nil,@[WXGSwitch(@"加亮叠加",@"rimSamplePlusLighter",nil)],@"打开后取到的颜色加在玻璃上（更亮），关闭时直接画成线。"),@[@1]),
        WXGNotIn(WXGStyled(WXGGroup(@"描边细节",nil,@[WXGSwitch(@"描边细节",@"rimDetails",nil)],
                 @"普通和取自背景两种样式可用（iOS 27 样式没有）。在原来的线上加细节，线和阴影都用边框自己的形状（系统的连续圆角）。外侧 / 内侧消散宽度：线从外轮廓往里、从内边往外各用多宽来过渡，每 0.1 pt 一级；两侧最外处强度：最外那一级剩多少（1 为不消散）。默认是透明度减弱；打开“两侧改为变暗”则改为颜色变暗。内侧阴影：线的里面一圈往内慢慢变淡的阴影。三个范围共用，浅色、深色各一套；底栏透镜保持原来的描边。"),@[@0,@1]),@[@"lens",@"segmentLens",@"finder"]),
        WXGNotIn(WXGStyled(WXGGroup(@"描边细节 · 浅色模式",nil,@[WXGSlider(@"外侧消散宽度",@"rimOuterFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"内侧消散宽度",@"rimInnerFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"两侧最外处强度",@"rimSideLevel",nil,0,1,nil),
                                 WXGSwitch(@"两侧改为变暗",@"rimSideDarken",nil),
                                 WXGColorRow(@"内侧阴影颜色",@"rimInnerShadowHex",nil),
                                 WXGSlider(@"内侧阴影浓度",@"rimInnerShadowOpacity",nil,0,.6,nil),
                                 WXGSlider(@"内侧阴影柔和度",@"rimInnerShadowRadius",nil,.3,6,@"%.1f pt")],nil),@[@0,@1]),@[@"lens",@"segmentLens",@"finder"]),
        WXGNotIn(WXGStyled(WXGGroup(@"描边细节 · 深色模式",nil,@[WXGSlider(@"外侧消散宽度",@"darkRimOuterFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"内侧消散宽度",@"darkRimInnerFade",nil,0,1.5,@"%.1f pt"),
                                 WXGSlider(@"两侧最外处强度",@"darkRimSideLevel",nil,0,1,nil),
                                 WXGSwitch(@"两侧改为变暗",@"darkRimSideDarken",nil),
                                 WXGColorRow(@"内侧阴影颜色",@"darkRimInnerShadowHex",nil),
                                 WXGSlider(@"内侧阴影浓度",@"darkRimInnerShadowOpacity",nil,0,.6,nil),
                                 WXGSlider(@"内侧阴影柔和度",@"darkRimInnerShadowRadius",nil,.3,6,@"%.1f pt")],nil),@[@0,@1]),@[@"lens",@"segmentLens",@"finder"]),
        WXGStyled(WXGGroup(@"iOS 27 · 浅色模式 · 高光一",nil,@[WXGColor3(@"颜色",@"rim27Hex",@"dockRim27Hex",@"bubbleRim27Hex"),
                                 WXGSlider3(@"不透明度",@"rim27Opacity",@"dockRim27Opacity",@"bubbleRim27Opacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"rim27Width",@"dockRim27Width",@"bubbleRim27Width",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"rim27Falloff",@"dockRim27Falloff",@"bubbleRim27Falloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"rim27Angle",@"dockRim27Angle",@"bubbleRim27Angle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"rim27EndLevel",@"dockRim27EndLevel",@"bubbleRim27EndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"rim27Sharpness",@"dockRim27Sharpness",@"bubbleRim27Sharpness",0.5,6,nil)],
                 @"iOS 27 的边框是两道同时存在的光，各有自己的颜色和方向（比如一道白的在上下边、一道深色的在两端），浅色模式、深色模式各一套（每套两道），系统是哪种外观就画哪套的两道（FIX113 Z；以前两种外观共用一套），深色模式那套第一次打开时和浅色模式这套一样。每一道都是从玻璃轮廓往里渐渐消失的光：最外圈最亮，往里在“渐隐宽度”内淡到没有；四周宽度处处一样（圆角处和上下一样宽），外边就是玻璃自己的轮廓（系统的连续圆角）。向内渐隐曲线：1 是均匀变淡，越大越快变淡（光贴着轮廓更细），小于 1 则亮的部分往里更宽。高光方向：这一道哪里最亮。0° 上下边最亮、往左右两端减弱；90° 左右两端最亮、往上下减弱；45° 左上和右下最亮，135° 右上和左下最亮。最暗处亮度：这一道最暗的地方减弱到这个比例（0 完全没有，1 一圈一样亮）。过渡速度：从最亮处往最暗处减弱的快慢，越大亮的部分越集中；1 随角度均匀减弱。只要一道时把另一道的不透明度调到 0。高光二画在高光一上面。升级后高光一是原来“浅色模式”那组的设置，高光二是原来“深色模式”那组的。底栏透镜里看到的底栏轮廓也按这两道画。"),@[@2]),
        WXGStyled(WXGGroup(@"iOS 27 · 浅色模式 · 高光二",nil,@[WXGColor3(@"颜色",@"darkRim27Hex",@"dockDarkRim27Hex",@"bubbleDarkRim27Hex"),
                                 WXGSlider3(@"不透明度",@"darkRim27Opacity",@"dockDarkRim27Opacity",@"bubbleDarkRim27Opacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"darkRim27Width",@"dockDarkRim27Width",@"bubbleDarkRim27Width",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"darkRim27Falloff",@"dockDarkRim27Falloff",@"bubbleDarkRim27Falloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"darkRim27Angle",@"dockDarkRim27Angle",@"bubbleDarkRim27Angle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"darkRim27EndLevel",@"dockDarkRim27EndLevel",@"bubbleDarkRim27EndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"darkRim27Sharpness",@"dockDarkRim27Sharpness",@"bubbleDarkRim27Sharpness",0.5,6,nil)],
                 nil),@[@2]),
        WXGStyled(WXGGroup(@"iOS 27 · 深色模式 · 高光一",nil,@[WXGColor3(@"颜色",@"rim27DarkModeHex",@"dockRim27DarkModeHex",@"bubbleRim27DarkModeHex"),
                                 WXGSlider3(@"不透明度",@"rim27DarkModeOpacity",@"dockRim27DarkModeOpacity",@"bubbleRim27DarkModeOpacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"rim27DarkModeWidth",@"dockRim27DarkModeWidth",@"bubbleRim27DarkModeWidth",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"rim27DarkModeFalloff",@"dockRim27DarkModeFalloff",@"bubbleRim27DarkModeFalloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"rim27DarkModeAngle",@"dockRim27DarkModeAngle",@"bubbleRim27DarkModeAngle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"rim27DarkModeEndLevel",@"dockRim27DarkModeEndLevel",@"bubbleRim27DarkModeEndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"rim27DarkModeSharpness",@"dockRim27DarkModeSharpness",@"bubbleRim27DarkModeSharpness",0.5,6,nil)],
                 @"FIX113 Z：深色模式自己的两道，参数的意思和浅色模式那两组一样。第一次打开时每一项都是浅色模式那组当时的值，之后各调各的。（视频号第一页的胶囊从 FIX115 S 起用自己的“视频号”范围。）"),@[@2]),
        WXGStyled(WXGGroup(@"iOS 27 · 深色模式 · 高光二",nil,@[WXGColor3(@"颜色",@"darkRim27DarkModeHex",@"dockDarkRim27DarkModeHex",@"bubbleDarkRim27DarkModeHex"),
                                 WXGSlider3(@"不透明度",@"darkRim27DarkModeOpacity",@"dockDarkRim27DarkModeOpacity",@"bubbleDarkRim27DarkModeOpacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"darkRim27DarkModeWidth",@"dockDarkRim27DarkModeWidth",@"bubbleDarkRim27DarkModeWidth",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"darkRim27DarkModeFalloff",@"dockDarkRim27DarkModeFalloff",@"bubbleDarkRim27DarkModeFalloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"darkRim27DarkModeAngle",@"dockDarkRim27DarkModeAngle",@"bubbleDarkRim27DarkModeAngle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"darkRim27DarkModeEndLevel",@"dockDarkRim27DarkModeEndLevel",@"bubbleDarkRim27DarkModeEndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"darkRim27DarkModeSharpness",@"dockDarkRim27DarkModeSharpness",@"bubbleDarkRim27DarkModeSharpness",0.5,6,nil)],
                 nil),@[@2]),
        WXGNotIn(WXGGroup(@"外阴影",nil,@[WXGSlider3(@"浓度（浅色模式）",@"dropShadowOpacity",@"dockDropShadowOpacity",@"bubbleDropShadowOpacity",0,.6,@"%.2f"),
                                 WXGSlider3(@"浓度（深色模式）",@"darkDropShadowOpacity",@"dockDarkDropShadowOpacity",@"bubbleDarkDropShadowOpacity",0,.6,@"%.2f"),
                                 WXGSlider3(@"柔和度",@"dropShadowBlur",@"dockDropShadowBlur",@"bubbleDropShadowBlur",.5,40,@"%.1f pt"),
                                 WXGSlider3(@"向下偏移",@"dropShadowOffset",@"dockDropShadowOffset",@"bubbleDropShadowOffset",-10,30,@"%.1f pt"),
                                 WXGSlider3(@"扩展",@"dropShadowSpread",@"dockDropShadowSpread",@"bubbleDropShadowSpread",-10,20,@"%.1f pt")],
                 @"FIX114 K：iOS 26 玻璃周围那圈很淡、很散的影子。默认值是从你发的 iOS 26 截图（返回按钮）量出来的：浓度 0.20、柔和度 17 pt、往下 8 pt——按钮旁边暗约 6%、下面约 9%、上面约 4%，往外大约 30 pt 才完全消失。浓度 = 影子多黑（0 = 没有）；柔和度 = 影子散开多远，越大越淡越宽；向下偏移 = 影子往下挪多少（负数往上）；扩展 = 影子比玻璃本身大多少。影子只画在玻璃外面，玻璃里面不会变灰。底栏、其余玻璃、分组栏默认打开，气泡和设置页默认关（0）。底栏原来那层固定的阴影去掉了，换成这里的。"),@[@"lens",@"segmentLens",@"finder"]),
        WXGGroup(@"透镜滤镜色",@"lens",@[WXGSwitch(@"透镜滤镜色",@"lensTintOn",nil),
                                     WXGColorRow(@"浅色模式颜色",@"lensTintHex",nil),WXGSlider(@"浅色模式浓度",@"lensTintOpacity",nil,0,1,nil),
                                     WXGColorRow(@"深色模式颜色",@"darkLensTintHex",nil),WXGSlider(@"深色模式浓度",@"darkLensTintOpacity",nil,0,1,nil)],
                 @"只管底栏的透镜（分组栏透镜的滤镜色在“分组”页）。FIX112 E：关闭（默认）时透镜里就是它下面的东西：缩小的底栏是底栏自己的颜色，底栏外面是背景本来的颜色，不加任何颜色。打开后抬起的透镜整片盖一层这里的颜色（图标也在下面），随透镜抬起出现；静止的选中胶囊不受影响。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 @"这一页的全部设置（三种样式、各个范围、浅色和深色、描边细节、透镜边框）回到默认值；其它页不变。")],WXGShareGroups(3)),@"sharePage":@3};
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
                 @"离散底栏：选中的标签是一块宽胶囊（左边图标，右边上中文、下英文），其余标签各是一个只有图标的小球，每块都是独立的底栏玻璃（材质、折射和边框都用“底栏”范围的设置）。切换时所有标签的宽度一起走同一个阻尼弹簧：旧的收成小球、新的展开，整行总宽不变、不会左右漂；回弹时新的会略微超宽、旧的略微被挤窄。未选中的小球连成一体：相邻两个小球之间的间距被玻璃填上，连成一整块（位置不变，只是间隙连上）；切换一开始，旧选中项就一边收窄一边并入两旁，新选中项一边展开一边分出来，约在弹簧响应的 0.35 倍时连成一块（默认约 0.16 s），不等动画结束。相连时图标向中间收拢：连成一块的小球，图标按这个比例往这一块的中间靠（0 = 停在各自小球的中心；默认 0.22，图标间距缩到 0.78 格，两连和三连间距一样），两端圆头处留出更多空间，跟着弹簧滑过去，角标跟着图标走。图标大小、中文 / 英文标题字号只管离散底栏（连续底栏的文字设置在“图标与文字”里），粗细跟随那里的“文字粗细”；文字放不下时自动缩小。宽位内容左移：宽胶囊里图标和标题整体居中后再往左挪这么多（0 = 正中，默认 10 pt），最多挪到图标落在左端圆头正中为止，小球时不偏。未读角标在每块胶囊的右上角，跟着胶囊宽窄移动。选中项加原选中胶囊：在宽胶囊里加上原来底栏的选中胶囊（透镜、底色和边框，颜色和内边距用下面“选中胶囊”的设置），切换时它从中心长出来、在旧的那块里缩没。间距：块与块之间。选中项占位：选中项占几格（2 格 = 两个小球加中间的间距那么宽；1 格时只放大图标不显示文字）。小球直径：相对底栏高度。整行放不下时（FIX113 E）先把选中项收窄（最少 1.6 格），再把间距缩小（最少一半），最后才缩小小球；有搜索按钮时，整行先加宽到能放下这个高度的小球（最宽到搜索框展开时那一行的宽度）。弹簧阻尼越小回弹越明显（0.6 约等于参考效果，1 不回弹）；弹簧响应越小越快。有搜索按钮时整行靠向搜索按钮那一边。打开搜索时变回连续底栏完成变形（两者交叉淡化）；关闭时，底栏快变回原样时就交叉淡回离散样式（FIX113 D），不会先停在完整的连续底栏上。各块用轻量玻璃：每块只用一层背景、不分色散通道，省电但少了色散和边缘环。"),
        WXGGroup(@"搜索",nil,@[WXGSwitch(@"底栏搜索按钮",@"pref.dockSearch",nil),WXGSwitch(@"搜索按钮放在左边",@"pref.dockSearchLeading",nil),
                             WXGSlider(@"两块玻璃的间距",@"dockSearchGap",nil,2,40,@"%.1f pt"),
                             WXGSwitch(@"隐藏聊天列表顶部搜索栏",@"pref.hideTopSearch",nil)],
                 @"平时底栏宽度比例是整行：标签栏、间距和圆形搜索按钮。点搜索按钮直接打开微信自己的搜索页（在其他标签页时先切到“微信”），不再先变成搜索框、标签栏也不再变成关闭按钮（FIX114 M）。聊天列表顶部的搜索框胶囊也一样：在搜索框原位时点它就是点微信自己的搜索框；列表往上滚、胶囊停在标题下面时点它，直接打开微信的搜索页。隐藏顶部搜索栏只在开启底栏搜索时生效。需要系统渲染（同步）模式。"),
        WXGGroup(@"透镜",nil,@[WXGSlider(@"透镜内容放大倍数",@"lensZoom",nil,1,1.5,nil),WXGSlider(@"按压透镜外扩倍数",@"lensGrowth",nil,1.08,1.5,nil),
                             WXGSlider(@"按压底栏整体放大",@"barGrowth",nil,1,1.08,@"%.3f"),WXGSlider(@"首尾透镜外包距离",@"endWrap",nil,2,10,@"%.1f pt"),
                             WXGSlider(@"镜内底栏统一内收",@"bodyPinch",nil,0,.30,@"%.3f"),
                             WXGSwitch(@"拖过两端时拉长底栏",@"dockEndStretch",nil),WXGSlider(@"两端拉长距离",@"dockEndStretchDistance",nil,0,40,@"%.0f pt"),
                             WXGSwitch(@"跟随滑动速度形变",@"lensElasticOn",nil),WXGSlider(@"形变时高度变化",@"lensElasticHeight",nil,0,1,@"%.2f"),
                             WXGSlider(@"形变时保持里面上下那条的宽度",@"lensElasticKeepStrip",nil,0,1,@"%.2f"),
                             WXGSwitch(@"透镜直接折射底下的底栏",@"lensRefractsBar",nil),
                             WXGSwitch(@"透镜里画底栏的描边",@"lensBarOutlineOn",nil),WXGSwitch(@"透镜里画底栏的背景",@"lensBarVeilOn",nil)],
                 @"透镜直接折射底下的底栏（FIX113 U，默认开）：按住时透镜里那条缩小的底栏，就是真实的底栏本身——它的模糊背景、底色、那一条边框都是底栏自己画出来的那份——按“镜内底栏统一内收”缩小，空出来的一圈是底栏外面的页面，然后整个用透镜的折射、放大和色散弯过去。透镜里不再另画任何底色和边框，所以缩小的底栏和外面的底栏是同一个东西、颜色完全一样（深色模式也是），边框也只有底栏自己那一条，被缩小、被折射。以前透镜取的是“不含底栏的页面”（底栏的几层和页面共用一次截取，透镜看不到它们），只能按几何形状在透镜里再画一遍底栏的底色和描边，这一份和真实的底栏是分开算的，所以会对不上、会分叉。打开这一项时，下面两个“透镜里画底栏的…”开关和“镜内底栏色散”不起作用（色散就是透镜自己的 RGB 色散），透镜模糊只加透镜自己的那一份；“镜内底栏统一内收”照样决定缩小多少。点按切换的动画透镜和分组栏的透镜也一样。关掉恢复 FIX113 T 的样子。透镜里画底栏的描边 / 背景（FIX113 T，只在关掉上一项时有用）：透镜里另画的那段底栏要不要画它的边框和背景色。跟随滑动速度形变（FIX113 Y，默认开）：透镜展开后拖得越快越扁长、急停时变圆（弹性形变），关掉后透镜只按按压大小变化、不跟速度变形。形变时高度变化：形变里高度那部分留多少，1 = 原来的样子（快拖时高度一直压到比底栏还矮，透镜里上下那条页面几乎没了；急停时又变胖），0 = 高度完全不变、只横向拉伸，中间值按比例。形变时保持里面上下那条的宽度（默认 1）：透镜被压扁 / 变胖时，里面缩小的底栏跟着多缩 / 少缩同样多，透镜边框和缩小底栏之间那条（页面）的宽度保持不变，透镜外形照样变形；0 = 以前那样跟着变；只在“透镜直接折射底下的底栏”开着时起作用（关掉时透镜里的底栏是着色器另画的那份，不跟这一项）。两项可以一起用；拖动使用 TEST9 弹簧。透镜的折射和模糊在对应模块的“底栏”范围里，透镜的边框在“边框与渐隐”的“底栏透镜”范围里（FIX113 X；分组栏的在“分组透镜”）。拖过两端时拉长底栏：透镜到了第一个或最后一个标签还继续往外拉，那一端的底栏跟着手指被拉出去（另一端不动，越拉越难，最多“两端拉长距离”），松手弹回；有搜索按钮的那一边最多拉到间距的 3/4。"),
        WXGGroup(@"选中胶囊",nil,@[WXGColorRow(@"浅色模式底色",@"selectionHex",nil),WXGColorRow(@"深色模式底色",@"darkSelectionHex",nil),
                                 WXGSlider(@"静置底色不透明度",@"selectionOpacity",nil,0,.75,nil),WXGSlider(@"静置内边距",@"selectionInset",nil,2,14,@"%.1f pt")],nil),
        WXGGroup(@"图标与文字",nil,@[WXGSlider(@"图标与文字间距",@"dockIconTitleGap",nil,0,16,@"%.1f pt"),WXGSlider(@"图标和文字整体上下",@"dockIconOffset",nil,-12,12,@"%+.1f pt"),
                                   WXGSlider(@"文字大小",@"dockTitleSize",nil,8,13,@"%.1f pt"),
                                   WXGChoice3(@"文字粗细",@"dockTitleWeight",nil,nil,@[@"细",@"常规",@"中等",@"半粗",@"粗"],NO),
                                   WXGSwitch(@"选中的文字加粗一档",@"dockTitleBolderSelected",nil)],
                 @"图标按微信自己的大小画（FIX114 B，以前统一缩放到 28 × 26 的框里，微信 28 pt 的图标被画小了；最大 30 pt）。图标与文字间距：图标框（按 26 pt 高算）下沿到文字上沿的距离，原来是 5 pt；调大调小时图标往上、文字往下各移一半，整组的中心不变。整体上下：图标和文字一起移，正数往下、负数往上，原来是 0。文字大小和粗细：FIX90 之前固定是 10.5 pt、未选中中等、选中半粗，FIX91 起默认 10 pt、中等，选中的不再更粗（打开“选中的文字加粗一档”恢复）；FIX114 B 起默认常规，和微信自己的标签一样（诊断里微信用的是 .SFUI-Regular 10 pt），还停在旧默认“中等”的会自动改成常规一次。微信自己用的字体写在诊断的底栏图标那一行（“微信标题字体”），可以对照。未读角标跟着图标走。透镜里的放大图标、点击动画用的都是同一套。"),
        WXGGroup(@"图标与动画",nil,@[WXGSwitch(@"使用微信原生图标",@"useWeChatIcons",nil),
                                  WXGSwitch(@"底栏主题优先（只接管玻璃和位置）",@"dockThemeFirst",nil),
                                  WXGSwitch(@"使用 Telegram 图标（切换时有动画）",@"dockTelegramIcons",nil),
                                  WXGColorRow(@"选中强调色",@"dockAccentHex",nil),
                                  WXGSlider(@"点按滑动时长（倍数）",@"dockTapMoveScale",nil,.6,3,@"%.2f ×"),
                                  WXGSlider(@"胶囊变透镜（滑动的比例）",@"dockTapLensShare",nil,.15,.9,@"%.2f"),
                                  WXGSlider(@"落下时长",@"dockTapDropTime",nil,.08,.8,@"%.2f s"),
                                  WXGChoice3(@"切换页面的时机",@"dockTapSwitchWhen",nil,nil,@[@"按下时",@"松手时",@"快到位时",@"落下后"],NO),
                                  WXGSwitch(@"按下时：会卡的标签等透镜落下再切",@"dockTapSmartHold",nil),
                                  WXGSwitch(@"切换后等页面忙完再滑",@"dockTapCalmWaitOn",nil),
                                  WXGSwitch(@"停顿后加速追上",@"dockTapCatchUp",nil),
                                  WXGSwitch(@"点按时用简化透镜（系统渲染）",@"dockTapSimpleTravel",nil)],
                 @"底栏主题优先（FIX115 D，默认关）：底栏的图标和标题颜色完全交给微信或别的插件的主题——用微信底栏里正在显示的那张图（主题的 PNG 也一样），按它在微信底栏里显示的大小画（不再按图片自己的尺寸、也不再限制在 30 pt 以内；同一个主题的 PNG 用不同倍数加载时尺寸不一样，以前就会忽大忽小），未选中 / 选中的文字颜色用微信 / 主题自己的；Telegram 图标和“选中强调色”不再用于底栏。插件只管玻璃、透镜、位置和间距（图标与文字的上下、间距、文字大小粗细照旧按上面的设置）。诊断的底栏图标那一行会写每个标签的图片尺寸、倍数和显示大小。Telegram 图标（FIX113）：微信、通讯录、发现、我依次换成 Telegram 的聊天、联系人、通话、设置图标（Telegram for iOS 开源仓库里的原动画，GPLv2），平时是静止的样子，切到哪个标签就播放它自己的那段动画（约 0.6–0.75 秒，按 Telegram 的 60 帧），透镜里外、离散底栏都一样；拖动经过别的标签不播，松手落定才播；系统“减弱动态效果”打开时不播。开着时优先于“使用微信原生图标”。选中强调色（FIX113 C）：选中标签的图标和文字颜色，系统图标和 Telegram 图标都用它（默认是原来的绿色），Telegram 图标播放动画时也是这个颜色；使用微信原生图标时仍是微信自己的颜色。FIX115 I：强调色在底栏里总是按 100% 不透明画（颜色的不透明度不用）；开着 Telegram 图标时存着的强调色也自动改成 100%。点按切换（FIX95 / FIX98 / FIX99）：点别的标签时，呼出的就是拖动时那块完整的透镜（折射、色散、透镜里的底栏和图标都一样），自己滑过去再落成胶囊；按住不放，到位后就跟着手指，可以继续左右拖。胶囊变透镜：滑动开始后，在滑动时长的这个比例内升起成透镜、颜色褪成透明（默认 0.40，FIX98 是颜色 0.65、升起 0.55）。落下时长：从透镜落回胶囊、颜色回来用的时间，默认 0.16 s（FIX98 0.26 s），在到位前 70% 就开始落，到位后约 0.05 s 落完，所以颜色的变化都在滑动里完成，不会到位以后还慢慢变。点按滑动时长：1 倍是 FIX43 的 0.28 s ×（0.85 + 0.05 × 标签数），默认 1.4 倍（一个标签约 0.35 s，点一下一共约 0.4 s）。FIX98 时调过这两项的，值会带过来；没调过的用新的默认值。切换页面的时机（FIX100）：按下时（默认）= 和微信自己的标签栏一样，手指一按下就让微信切页面：微信加载那一页的那一下卡顿发生在透镜动起来之前（透镜在原地等它，不跳），然后透镜在新页面上滑过去，页面和原生一样快出来；松手时 = 松手才切，动画接着走；快到位时 = 透镜滑完 80% 时切；落下后 = FIX95–FIX97 的做法。按下时以外的三种：微信切页面时主线程会卡 0.05–0.5 s，透镜在那一下停住、再从停住的地方接着走；启动后第一次打开某个标签总是等透镜落下再切。按下时：会卡的标签等透镜落下再切（FIX119 E；FIX119 F 起默认关闭）：插件记下每个标签上次切换后 0.7 秒内主线程卡了多久（帧超时的部分加起来），超过 50 ms 的标签下次也像第一次打开那样，等透镜落下再切，透镜一路不停；不卡的标签照旧按下就切。在 XS Max 上几乎每个标签都超过 50 ms（微信每次切标签都要检查数据库、刷新那一页），打开后页面差不多总在透镜落下后才出来，所以默认关着。按下后滑到别的标签松手，再切到那个标签；按下后滑出底栏松手，留在按下的那个标签（微信已经切过去了，和原生一样）。切换后等页面忙完再滑（FIX101，FIX102 起默认关闭）：打开后透镜在微信切完页面后原地等到连续三帧准时（最多 0.6 s）再滑，滑动更不容易被打断，但每次都会晚 0.07–0.2 s 开始。停顿后加速追上（FIX102，默认打开）：透镜因为微信切页面停住多久，剩下的动画就快那么久的六成（最多快四分之一），落下的时间尽量和没停时一样。拖动时胶囊颜色也按升起的程度渐变（按压 0.05–0.45）。打开“点按时用简化透镜”恢复 FIX33–FIX94 的做法：动画交给系统渲染服务，页面立刻切换，但滑动的只是一个形状，没有透镜的效果（上面几项不影响它）。")]};
    // FIX113 O: the chat list's segment bar has its own module (user: not the
    // dock's parameters; the pill's inset and border; its lens separate; the
    // floating switch); its glass (refraction, blur, material, border) is the
    // 分组 range of the glass pages.
    if([module isEqual:@"segments"])return @{@"title":@"分组",@"groups":@[
        WXGGroup(@"分组栏",nil,@[WXGSwitch(@"分组栏取代聊天列表搜索框",@"chatSegments",nil),WXGSwitch(@"悬浮，不随列表滚走",@"searchFloat",nil)],
                 @"聊天列表顶部的搜索框换成分组栏，默认 全部 / 未读（有未读或 @ 的）/ 单聊（个人聊天，不含公众号、服务通知这类）/ 群聊（含折叠的群聊），在上面的“管理分组”里可以新建、改名、排序，或做自己选聊天的分组。点哪个分组，聊天列表就只显示那一组（置顶的照样在前），“全部”就是微信原来的列表；每次重新打开微信从第一个“全部”开始。万一这台微信的会话列表结构对不上，会自动回到“全部”并在诊断里写明原因，不会动列表。FIX113 P 起它就是一条小底栏：玻璃、边框、选中胶囊、文字颜色、透镜都从底栏的参数开始，再在这里和各玻璃页的“分组”范围里微调。位置和大小（FIX114 E）：分组栏就在微信搜索框原来的位置、和它一样大（以前的宽度、加高、与标题胶囊的间距三项去掉了），下拉时也跟着微信的搜索框走；只有“顶部按钮往下移”大于 0 时跟着标题行往下挪同样多。悬浮：分组栏（以及首页、通讯录的搜索框）和标题胶囊在同一层，列表往上滚时停在标题栏下面，不跟着滚走；首页、通讯录的搜索框停住后点它，列表会回到顶部再打开微信自己的搜索。只在同步渲染模式下生效。"),
        WXGGroup(@"分组列表",nil,@[WXGAction(@"管理分组（新建 / 改名 / 选聊天 / 排序）",@"manageGroups",NO)],
                 @"分组是你自己的：最多 6 个，每个可以是 全部 / 未读 / 单聊 / 群聊，或者“自定义”——自己选里面有哪些聊天。分组栏上从左到右就是这里的顺序。"),
        WXGGroup(@"跟底栏一致",nil,@[WXGAction(@"套用底栏现在的样子",@"segmentFromDock",NO)],
                 @"把底栏现在的折射、模糊、材质、边框、选中胶囊颜色、透镜和文字颜色全部抄一份给分组栏（之后仍然各调各的）。调过底栏、想让分组栏跟上时用。"),
        WXGGroup(@"玻璃底色",nil,@[WXGColorRow(@"浅色模式",@"segmentMaterialHex",nil),WXGSlider(@"浅色模式不透明度",@"segmentMaterialOpacity",nil,0,1,nil),
                                WXGColorRow(@"深色模式",@"segmentDarkMaterialHex",nil),WXGSlider(@"深色模式不透明度",@"segmentDarkMaterialOpacity",nil,0,1,nil)],
                 @"分组栏玻璃的材质，默认和底栏的一样。也就是材质页“分组”范围的材质；折射、模糊、边框在折射、模糊、边框几页的“分组”范围里，默认也是底栏的值。"),
        WXGGroup(@"选中胶囊",nil,@[WXGSlider(@"内边距",@"segmentSelectionInset",nil,2,14,@"%.1f pt"),WXGSwitch(@"用页面的背景色",@"segmentPillAuto",nil),
                                 WXGColorRow(@"浅色模式颜色",@"segmentPillHex",nil),WXGSlider(@"浅色模式不透明度",@"segmentPillOpacity",nil,0,1,nil),
                                 WXGColorRow(@"深色模式颜色",@"segmentDarkPillHex",nil),WXGSlider(@"深色模式不透明度",@"segmentDarkPillOpacity",nil,0,1,nil),
                                 WXGSlider(@"按住时不透明度",@"segmentPillPressedOpacity",nil,0,1,nil)],
                 @"默认和底栏的选中胶囊一样（颜色、不透明度，按住变透镜时淡到“按住时不透明度”）。内边距是选中胶囊到分组栏边缘的距离（上下最多到分组栏高度的 30%）。打开“用页面的背景色”时颜色取自搜索框后面的页面，下面两个颜色不用；不透明度照样生效。"),
        WXGGroup(@"选中胶囊边框",nil,@[WXGSlider(@"静止时也显示",@"segmentPillRimAtRest",nil,0,1,nil)],
                 @"选中胶囊（按住时就是透镜）自己的一圈边框。按住时随按压出现；“静止时也显示”大于 0 时，松手停在那一段时也有这么多。边框的样式、颜色、宽度这些在“边框与渐隐”的“分组透镜”范围里（FIX114 C 起和底栏的透镜分开，三种样式都能用；第一次打开时和底栏透镜一样）。"),
        WXGGroup(@"文字",nil,@[WXGSlider(@"字号",@"segmentTitleSize",nil,10,18,@"%.1f pt"),WXGSlider(@"字重（细 → 粗）",@"segmentTitleWeight",nil,0,4,@"%.0f"),
                             WXGColorRow(@"浅色模式颜色",@"segmentInkHex",nil),WXGColorRow(@"深色模式颜色",@"segmentDarkInkHex",nil),
                             WXGSwitch(@"选中的用强调色",@"segmentAccentOn",nil),WXGColorRow(@"强调色",@"segmentAccentHex",nil)],
                 @"和底栏一样：没选中的是深灰（深色模式浅灰），选中的那一段用强调色（默认底栏的绿色），字重自动加一级。关掉强调色时选中的也用上面的颜色。"),
        WXGGroup(@"透镜（按住时）",nil,@[WXGSlider(@"透镜折射强度",@"segmentLensRefraction",nil,0,20,nil),WXGSlider(@"透镜 RGB 色散",@"segmentLensDispersion",nil,0,8,nil),
                                      WXGSlider(@"透镜折射宽度（两端）",@"segmentLensEdgeWidth",nil,1,60,@"%.1f pt"),
                                      WXGSlider(@"文字的折射强度",@"segmentLensIconRefraction",nil,0,20,nil),WXGSlider(@"文字的折射宽度",@"segmentLensIconEdgeWidth",nil,1,60,@"%.1f pt"),
                                      WXGSlider(@"文字的上下宽度比例",@"segmentLensIconTopEdgeRatio",nil,.1,1,nil),WXGSlider(@"文字的上下收窄曲线",@"segmentLensIconEdgeSharpness",nil,1,6,nil),
                                      WXGSwitch(@"跟随滑动速度形变",@"segmentLensElasticOn",nil),WXGSlider(@"形变时高度变化",@"segmentLensElasticHeight",nil,0,1,@"%.2f"),
                                      WXGSlider(@"形变时保持里面上下那条的宽度",@"segmentLensElasticKeepStrip",nil,0,1,@"%.2f"),
                                      WXGSlider(@"上下折射宽度比例",@"segmentLensTopEdgeRatio",nil,.1,1,nil),
                                      WXGSlider(@"上下收窄曲线",@"segmentLensEdgeSharpness",nil,1,6,nil),
                                      WXGSlider(@"透镜色散范围（两端）",@"segmentLensDispersionWidth",nil,1,60,@"%.1f pt"),WXGSlider(@"上下色散范围比例",@"segmentLensDispersionTopRatio",nil,.1,1,nil),
                                      WXGSlider(@"边缘偏移抵消",@"segmentLensOffsetCancel",nil,0,1,@"%.2f"),
                                      WXGSlider(@"透镜内容放大倍数",@"segmentLensZoom",nil,1,1.5,nil),WXGSlider(@"按住透镜外扩倍数",@"segmentLensGrowth",nil,1.08,1.5,nil),
                                      WXGSlider(@"按住分组栏整体放大",@"segmentBarGrowth",nil,1,1.08,@"%.3f"),WXGSlider(@"首尾透镜外包距离",@"segmentEndWrap",nil,2,10,@"%.1f pt"),
                                      WXGSlider(@"镜内分组栏统一内收",@"segmentBodyPinch",nil,0,.30,@"%.3f"),
                                      WXGSlider(@"透镜模糊半径",@"segmentLensBlur",nil,0,12,@"%.2f pt"),WXGSlider(@"透镜模糊覆盖扩展",@"segmentLensBlurCoverage",nil,0,100,@"%.0f%%")],
                 @"分组栏自己的透镜，第一次打开时和底栏的透镜相同，之后各调各的。文字的折射强度 / 宽度（FIX113 X）：透镜里的分组名单独用这一组，其余部分用上面的透镜折射强度、宽度；上下宽度比例、收窄曲线也各用各的（FIX113 Y）。跟随滑动速度形变、形变时高度变化、形变时保持里面上下那条的宽度（FIX113 Y）：和底栏“透镜”组里的一样，分组栏自己一套。透镜直接折射底下的分组栏（FIX113 U，跟着底栏“透镜”组里的“透镜直接折射底下的底栏”开关，默认开）：透镜里那条缩小的分组栏就是真实的分组栏（底色、边框）按“镜内分组栏统一内收”缩小后再被透镜折射，不再另画一份；开着时“镜内分组栏色散”不起作用。边缘偏移抵消需要服务器的 FIX113 I 着色器。点按切换的动画时长、胶囊变透镜的快慢和两端拉长仍用底栏的设置。"),
        WXGGroup(@"透镜滤镜色",nil,@[WXGSwitch(@"透镜滤镜色",@"segmentLensTintOn",nil),
                                  WXGColorRow(@"浅色模式颜色",@"segmentLensTintHex",nil),WXGSlider(@"浅色模式浓度",@"segmentLensTintOpacity",nil,0,1,nil),
                                  WXGColorRow(@"深色模式颜色",@"segmentDarkLensTintHex",nil),WXGSlider(@"深色模式浓度",@"segmentDarkLensTintOpacity",nil,0,1,nil)],nil),
        WXGGroup(@"镜内分组栏色散",nil,@[WXGSwitch(@"镜内边缘色散",@"segmentLensBarDispersionOn",nil),
                                     WXGSlider(@"整片透镜的色散（边缘处）",@"segmentLensBarDispersion",nil,0,2,@"%.2f pt"),
                                     WXGSlider(@"两端加强（透镜色散的比例）",@"segmentLensBarDispersionNearRim",nil,0,1,nil)],
                 @"只在关掉底栏的“透镜直接折射底下的底栏”时有用：那时透镜里另画的分组栏的色散。打开时透镜折射的是真实的分组栏，色散用上面“透镜 RGB 色散”。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],@"这一页的设置回到默认值；分组范围的折射、模糊、材质、边框在各自页面里恢复。")]};
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
        WXGGroup(@"帧率日志",nil,@[WXGAction(@"查看帧率报告",@"perfReport",NO),WXGAction(@"查看页面切换报告",@"perfSwitches",NO),WXGAction(@"导出帧率日志 JSON",@"perfExport",NO),WXGAction(@"清空本次记录",@"perfClear",YES)],
                 @"报告里有总体和各页面的平均帧率、掉帧比例、卡顿（每秒多等的毫秒数）、p95 帧时间、最长一帧和插件耗时，以及最近的卡顿。导出的 JSON 里还有逐秒记录和上一次运行的记录，发给作者即可。页面切换报告（FIX113 Z）：每次进出页面（push / pop、弹出 / 收起、切标签）从发起到动画结束后 0.3 s：首帧要多久、掉了几帧、最长一帧，以及这段时间主线程花在哪里——插件（分刷新、每帧玻璃、各个挂钩、渐隐、气泡等）、Core Animation 提交、微信自己。插件开着就一直记（只在切换那一会儿跑自己的计时器），插件关着时打开“记录帧率”也记，可以对比；最近 40 次也在导出的帧率 JSON 和诊断里。"),
        WXGGroup(@"参数共享",nil,@[WXGAction(@"复制当前参数",@"shareCopy",NO),WXGAction(@"导出参数文件",@"shareExport",NO),
                                 WXGAction(@"从剪贴板导入参数",@"shareImportClipboard",NO),WXGAction(@"从文件导入参数",@"shareImportFile",NO)],
                 @"包括全部玻璃参数（折射、模糊、材质、边框、底栏、渐隐与模糊、拉伸等）、基本设置和底栏里的开关、设置页的卡片圆角和强调色；总开关、授权、壁纸和头像不在里面。复制得到一段文字，可以直接用微信发给别人，对方复制后点“从剪贴板导入参数”。导入也认诊断 JSON（新版里的完整参数；旧版只有玻璃参数）。想把一套参数做成安装后的默认值，导出参数文件发给作者。")]};
    if([module isEqual:@"wallpaper"])return @{@"title":@"壁纸",@"groups":@[
        WXGGroup(@"设置页壁纸",nil,@[WXGWallpaperRow(@"浅色模式",NO),WXGWallpaperRow(@"深色模式",YES)],
                 @"只用于这几页设置，给玻璃卡片做背景；没有导入时用下面的纯色。"),
        WXGGroup(@"无壁纸时的背景色",nil,@[WXGColorRow(@"浅色模式",@"settingsBackgroundHex",nil),WXGColorRow(@"深色模式",@"settingsDarkBackgroundHex",nil)],
                 @"FIX113 O：没有导入壁纸时，这几页设置的背景是纯色（默认浅色模式浅灰、深色模式深灰），不再是原来的彩色渐变。卡片和按钮的玻璃参数在折射、模糊、材质、边框几页的“设置页”范围里。"),
        WXGGroup(@"卡片",nil,@[WXGSlider(@"卡片圆角",@"ui.cardRadius",nil,0,40,@"%.0f pt")],@"所有卡片都是连续圆角，不超过卡片高度的一半。"),
        WXGGroup(@"强调色",nil,@[WXGColorRow(@"字体与图标",@"ui.accentHex",nil),WXGAction(@"恢复跟随系统",@"accentReset",NO)],
                 @"也可以点设置首页右上角的调色板按钮修改。")]};
    return nil;
}

/* FIX115 E: 复制到. A page's settings of one range paired with another's:
   rows of the groups every range shows, by their key in each range (WXGRowKeyForScope;
   a row with one key for all ranges is shared already: skipped); rows of a
   range's own groups (折射 / 模糊: 底栏本体, 其余玻璃, 液态气泡 ...) by their
   title (折射强度 with 折射强度); a title twice in a range: not paired. Only
   the configuration's own keys (sliders, switches, colours, choices). */
static NSArray<NSString *> *WXGCopyModules(void) {return @[@"refraction",@"blur",@"material",@"border"];}   // pages 0 ... 3
static BOOL WXGCopyableKey(NSString *key) {return key.length && ![key hasPrefix:@"pref."] && ![key hasPrefix:@"ui."] && [WXGConfig.shared knowsKey:key];}
static NSArray<NSArray<NSString *> *> *WXGCopyPairs(NSDictionary *spec,NSString *from,NSString *to) {
    NSMutableArray *pairs=[NSMutableArray array];NSMutableSet *taken=[NSMutableSet set];
    NSMutableDictionary *fromTitled=[NSMutableDictionary dictionary],*toTitled=[NSMutableDictionary dictionary];
    NSMutableSet *twice=[NSMutableSet set];
    NSSet *types=[NSSet setWithArray:@[@"slider",@"switch",@"color",@"choice"]];
    for(NSDictionary *group in spec[@"groups"]) {
        if([group[@"shareSlot"] boolValue] || [group[@"copySlot"] boolValue] || [group[@"title"] isEqual:@"恢复"])continue;
        NSString *scope=group[@"scope"];NSArray *notIn=group[@"notIn"];
        for(NSDictionary *row in group[@"rows"]) {
            if(![types containsObject:row[@"type"]])continue;
            if(!scope) {
                if([notIn containsObject:from] || [notIn containsObject:to])continue;
                NSString *a=WXGRowKeyForScope(row,from),*b=WXGRowKeyForScope(row,to);
                if(!WXGCopyableKey(a) || !WXGCopyableKey(b) || [a isEqual:b] || [taken containsObject:b])continue;
                [taken addObject:b];[pairs addObject:@[a,b]];
            }else if([scope isEqual:from] || [scope isEqual:to]) {
                NSString *key=WXGRowKeyForScope(row,scope),*title=row[@"title"];
                if(!WXGCopyableKey(key) || !title.length)continue;
                NSMutableDictionary *titled=[scope isEqual:from]?fromTitled:toTitled;
                NSString *mark=[NSString stringWithFormat:@"%@|%@",scope,title];
                if(titled[title])[twice addObject:mark];else titled[title]=key;
            }
        }
    }
    for(NSString *title in fromTitled) {
        NSString *a=fromTitled[title],*b=toTitled[title];
        if(!b || [twice containsObject:[NSString stringWithFormat:@"%@|%@",from,title]] || [twice containsObject:[NSString stringWithFormat:@"%@|%@",to,title]])continue;
        if([a isEqual:b] || [taken containsObject:b])continue;
        [taken addObject:b];[pairs addObject:@[a,b]];
    }
    return pairs;
}
// One page (module): `to`'s settings become what `from` shows now (its own,
// or those of the range it uses); `to` stops using another range's. Not saved
// here (the caller saves once). The settings changed, counted.
static NSUInteger WXGCopyRange(NSString *module,NSInteger page,NSString *from,NSString *to) {
    NSDictionary *spec=WXGModuleSpec(module);NSArray *scopes=spec[@"scopes"];
    if(![scopes containsObject:from] || ![scopes containsObject:to] || [from isEqual:to])return 0;
    NSString *source=WXGShareResolved(from,page);   // `from` showing `to`'s own already: only the 共用 below
    WXGConfig *c=WXGConfig.shared;NSUInteger changed=0;
    if(![source isEqual:to])for(NSArray<NSString *> *pair in WXGCopyPairs(spec,source,to)) {
        id value=[c valueForKey:pair[0]];if(!value || value==NSNull.null)continue;
        if(![[c valueForKey:pair[1]] isEqual:value]){[c setValue:value forKey:pair[1]];++changed;}
    }
    NSString *shareKey=WXGShareKeyFor(to,page);
    if(shareKey && ![WXGShareResolved(to,page) isEqual:to]){[c setValue:@0 forKey:shareKey];++changed;}
    return changed;
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

// FIX114 N: 共用到 / 共用 rows (a switch each). "shareTo": the target range
// uses the source range's settings of the page; "shareAll": every target;
// "shareFollow": the range shown uses another's (off: its own again).
@protocol WXGShareHost <NSObject>
- (void)shareChanged;
@end
@interface WXGShareRow : WXGSettingsRow
@end
@implementation WXGShareRow {UISwitch *_switch;}
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
- (NSInteger)sharePage {return [self.spec[@"page"] integerValue];}
- (NSArray<NSString *> *)targets {return [self.spec[@"type"] isEqual:@"shareAll"]?self.spec[@"targets"]:@[self.spec[@"target"]?:@""];}
- (BOOL)follows:(NSString *)target {
    NSString *source=self.spec[@"source"];
    return target.length && ![target isEqual:source] && [WXGShareResolved(target,self.sharePage) isEqual:source];
}
- (void)refresh {
    if([self.spec[@"type"] isEqual:@"shareFollow"]){_switch.on=YES;return;}
    BOOL all=self.targets.count>0;for(NSString *t in self.targets)if(![self follows:t]){all=NO;break;}
    _switch.on=all;
}
- (void)toggle:(UISwitch *)sender {
    NSInteger page=self.sharePage;
    if([self.spec[@"type"] isEqual:@"shareFollow"]) {
        if(!sender.on){NSString *key=WXGShareKeyFor(self.spec[@"target"],page);if(key)WXGRowSet(key,@0);}
    }else {
        NSInteger code=WXGShareCode(self.spec[@"source"]);
        for(NSString *t in self.targets) {
            NSString *key=WXGShareKeyFor(t,page);if(!key)continue;
            if(sender.on)WXGRowSet(key,@(code));
            else if([self follows:t])WXGRowSet(key,@0);
        }
    }
    if(WXGConfig.shared.haptics)[[[UISelectionFeedbackGenerator alloc]init] selectionChanged];
    id host=self.page;
    if([host respondsToSelector:@selector(shareChanged)])[(id<WXGShareHost>)host shareChanged];else [self refresh];
}
- (void)applyLook {[super applyLook];_switch.onTintColor=WXGSettingsStore.shared.controlTint;}
@end

// FIX85: a segmented choice (an integer key); the page is told when it
// changes so it can show the groups that belong to the new choice.
@protocol WXGChoiceHost <NSObject>
- (void)choiceChanged:(NSDictionary *)spec;
@end
@interface WXGChoiceRow : WXGSettingsRow
@end
// FIX114 C (user: the system's segmented control looks out of place on the
// old system these pages are for): the plugin's own pill row, like the
// range selector: a faint track, the choice under a pill that slides.
@implementation WXGChoiceRow {UIView *_track,*_pill;NSArray<UIButton *> *_options;NSInteger _shown;}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _track=[UIView new];_track.userInteractionEnabled=NO;_track.layer.cornerCurve=kCACornerCurveContinuous;[self addSubview:_track];
        _pill=[UIView new];_pill.userInteractionEnabled=NO;_pill.layer.cornerCurve=kCACornerCurveContinuous;[self addSubview:_pill];
        NSMutableArray *options=[NSMutableArray array];NSArray *choices=spec[@"choices"];
        for(NSUInteger i=0;i<choices.count;i++) {
            UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=(NSInteger)i;
            [b setTitle:choices[i] forState:UIControlStateNormal];
            b.titleLabel.font=[UIFont systemFontOfSize:choices.count>4?14:15 weight:UIFontWeightSemibold];
            b.titleLabel.adjustsFontSizeToFitWidth=YES;b.titleLabel.minimumScaleFactor=.7;
            b.accessibilityLabel=[NSString stringWithFormat:@"%@：%@",spec[@"title"]?:@"",choices[i]];
            [b addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:b];[options addObject:b];
        }
        _options=options;_shown=-1;[self refresh];
    }return self;
}
- (BOOL)bare {return [self.spec[@"bare"] boolValue];}
- (CGFloat)rowHeight {return self.bare?48:94;}
- (CGRect)pillFrameFor:(NSInteger)index {
    if(index<0 || index>=(NSInteger)_options.count)return CGRectZero;
    CGRect cell=_options[(NSUInteger)index].frame;CGFloat inset=self.bare?5:4;
    return cell.size.width>2*inset && cell.size.height>2*inset?CGRectInset(cell,inset,inset):CGRectZero;   // (review) not before the first layout
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat w=self.bounds.size.width;
    // FIX114 E: capsules (round ends), not rounded boxes. Bare: the card is
    // the track (its glass a capsule), the choices fill it.
    BOOL bare=self.bare;
    self.titleLabel.hidden=bare;_track.hidden=bare;
    if(!bare)self.titleLabel.frame=CGRectMake(16,11,MAX(20,w-32),20);
    CGRect track=bare?self.bounds:CGRectMake(16,40,MAX(20,w-32),42);_track.frame=track;
    _track.layer.cornerRadius=track.size.height*.5;
    CGFloat cell=track.size.width/MAX(1,(CGFloat)_options.count);
    for(UIButton *b in _options)b.frame=CGRectMake(track.origin.x+b.tag*cell,track.origin.y,cell,track.size.height);
    _pill.frame=[self pillFrameFor:_shown];_pill.hidden=_shown<0;
    _pill.layer.cornerRadius=MAX(0,(track.size.height-(bare?10:8))*.5);
}
- (void)showChoice:(NSInteger)index {
    _shown=index>=0 && index<(NSInteger)_options.count?index:-1;
    WXGSettingsStore *store=WXGSettingsStore.shared;
    for(UIButton *b in _options) {
        BOOL on=b.tag==_shown;
        UIColor *color=on?store.accentColor:store.secondaryColor;
        [b setTitleColor:color forState:UIControlStateNormal];[b setTitleColor:[color colorWithAlphaComponent:.45] forState:UIControlStateHighlighted];
        b.accessibilityTraits=on?UIAccessibilityTraitButton|UIAccessibilityTraitSelected:UIAccessibilityTraitButton;
    }
}
- (void)refresh {
    [self showChoice:[WXGRowGet(self.key) integerValue]];
    _pill.frame=[self pillFrameFor:_shown];_pill.hidden=_shown<0;
}
- (void)choose:(UIButton *)sender {
    if(sender.tag==_shown)return;
    WXGRowSet(self.key,@(sender.tag));
    if(WXGConfig.shared.haptics)[[[UISelectionFeedbackGenerator alloc]init] selectionChanged];
    BOOL wasHidden=_pill.hidden;
    [self showChoice:[WXGRowGet(self.key) integerValue]];
    CGRect to=[self pillFrameFor:_shown];_pill.hidden=_shown<0;
    if(wasHidden)_pill.frame=to;
    else [UIView animateWithDuration:.3 delay:0 usingSpringWithDamping:.84 initialSpringVelocity:0
                             options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                          animations:^{self->_pill.frame=to;} completion:nil];
    WXGSettingsPage *page=self.page;NSDictionary *spec=self.spec;
    // The page's groups for the new choice once the pill has slid (they
    // replace this row too); (review) quick taps make one rebuild.
    if([spec[@"rebuild"] boolValue] && [page conformsToProtocol:@protocol(WXGChoiceHost)]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:page selector:@selector(choiceChanged:) object:spec];
        [page performSelector:@selector(choiceChanged:) withObject:spec afterDelay:.34];
    }
}
- (void)applyLook {
    [super applyLook];WXGSettingsStore *store=WXGSettingsStore.shared;
    _track.backgroundColor=[UIColor.labelColor colorWithAlphaComponent:.06];
    _pill.backgroundColor=store.controlTint?[store.controlTint colorWithAlphaComponent:.22]:[UIColor.labelColor colorWithAlphaComponent:.12];
    [self showChoice:_shown];[self setNeedsLayout];
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
    // FIX114 C (user: seven ranges in a row were too many and untidy): the
    // card shows the range chosen; its arrow opens the list of all of them.
    UIButton *_scopeHeader;
    UILabel *_scopeCurrent;
    UIImageView *_scopeChevron;
    NSArray<UIButton *> *_scopeButtons;   // the list, shown while open
    UIView *_scopePill,*_scopeLine;
    BOOL _scopeOpen;
    NSMutableArray<NSDictionary *> *_groups;   // label, card, rows, separators, footer (as present)
    WXGRimStyle _builtStyle;                   // FIX85: the rim style the groups were built for (FIX86: the range's)
    BOOL _builtSharing;                        // FIX114 L: built for a range using another's (共用)
    // FIX113 O: opened from the settings search: scroll to this group (spec
    // index) and flash the row (or the group's card).
    NSInteger _focusGroup,_focusRow;
    BOOL _focusPending;
    __weak WXGSettingsCard *_flashCard;
    CGRect _flashRect;
}
- (instancetype)initWithModule:(NSString *)module {
    if((self=[super initWithNibName:nil bundle:nil])) {
        _module=[module copy];_spec=WXGModuleSpec(module);_scope=WXGLastScope;_focusGroup=_focusRow=-1;
        if(![self.scopes containsObject:_scope])_scope=[_scope isEqual:@"bubble"]?@"other":self.scopes.firstObject;   // FIX85
        self.pageTitle=_spec[@"title"]?:@"设置";self.showsAccentButton=YES;
    }return self;
}
- (BOOL)scoped {return [_spec[@"scoped"] boolValue];}
// FIX113 O: the search result to show (before the page is built). On a page
// with ranges, the range is kept when it shows that group and row, else the
// first range that does.
- (void)focusGroup:(NSInteger)groupIndex row:(NSInteger)rowIndex {
    NSArray *groups=_spec[@"groups"];
    if(groupIndex<0 || groupIndex>=(NSInteger)groups.count)return;
    _focusGroup=groupIndex;_focusRow=rowIndex;_focusPending=YES;
    if(!self.scoped)return;
    NSDictionary *group=groups[(NSUInteger)groupIndex];NSArray *rows=group[@"rows"];
    NSDictionary *row=rowIndex>=0 && rowIndex<(NSInteger)rows.count?rows[(NSUInteger)rowIndex]:nil;
    __weak WXGSettingsModule *weakSelf=self;
    BOOL (^shows)(NSString *)=^BOOL(NSString *scope) {
        if(group[@"scope"] && ![group[@"scope"] isEqual:scope])return NO;
        if([group[@"notIn"] containsObject:scope])return NO;
        if(group[@"styles"] && ![group[@"styles"] containsObject:@([weakSelf rimStyleOfRange:scope])])return NO;   // the range's rim style shows it
        NSString *key=row?WXGRowKeyForScope(row,scope):nil;
        return !(key && !key.length);
    };
    if(shows(_scope))return;
    for(NSString *scope in self.scopes)if(shows(scope)){_scope=scope;WXGLastScope=scope;break;}
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(!_focusPending || self.view.bounds.size.width<1)return;
    _focusPending=NO;
    NSDictionary *built=nil;
    for(NSDictionary *group in _groups)if([group[@"specIndex"] integerValue]==_focusGroup){built=group;break;}
    if(!built)return;   // not shown with this rim style
    WXGSettingsCard *card=built[@"card"];UIView *top=built[@"label"]?:card;
    CGRect rect=card.bounds;CGFloat y=CGRectGetMinY(top.frame)-4;
    NSArray *rows=built[@"rows"],*indexes=built[@"rowIndexes"];
    NSUInteger at=_focusRow>=0?[indexes indexOfObject:@(_focusRow)]:NSNotFound;
    if(at!=NSNotFound && at<rows.count) {
        rect=((UIView *)rows[at]).frame;
        // A row far down a long card: the row itself near the top.
        if(CGRectGetMinY(rect)>self.scrollView.bounds.size.height*.45)y=CGRectGetMinY(card.frame)+CGRectGetMinY(rect)-60;
    }
    UIScrollView *scroll=self.scrollView;
    CGFloat maximum=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
    scroll.contentOffset=CGPointMake(0,MIN(MAX(0,y),maximum));
    _flashCard=card;_flashRect=rect;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    WXGSettingsCard *card=_flashCard;_flashCard=nil;
    if(!card.superview)return;
    // A plain tint over the row (not the glass: glass is never faded).
    UIView *flash=[[UIView alloc]initWithFrame:_flashRect];flash.userInteractionEnabled=NO;
    UIColor *tint=WXGSettingsStore.shared.controlTint?:UIColor.systemBlueColor;
    flash.backgroundColor=[tint colorWithAlphaComponent:.2];
    if(card.capsule){flash.layer.cornerRadius=_flashRect.size.height*.5;flash.layer.cornerCurve=kCACornerCurveContinuous;}   // FIX114 E (review)
    [card.contentView insertSubview:flash atIndex:0];
    [UIView animateWithDuration:.9 delay:.6 options:UIViewAnimationOptionAllowUserInteraction animations:^{flash.alpha=0;}
                     completion:^(__unused BOOL finished){[flash removeFromSuperview];}];
}
// FIX85: the ranges of this page (the bubbles have one in some pages).
- (NSArray<NSString *> *)scopes {return _spec[@"scopes"]?:@[@"dock",@"other"];}
- (NSUInteger)selectedScopeIndex {NSUInteger i=[self.scopes indexOfObject:_scope];return i==NSNotFound?0:i;}
// FIX86: the rim style of the range selected on this page.
- (WXGRimStyle)scopeRimStyle {return [self rimStyleOfRange:_scope];}
- (WXGRimStyle)rimStyleOfRange:(NSString *)range {
    WXGGlassScope scope=!self.scoped?WXGGlassScopeOther:[range isEqual:@"dock"]?WXGGlassScopeDock:[range isEqual:@"bubble"]?WXGGlassScopeBubble:
                        [range isEqual:@"segment"]?WXGGlassScopeSegment:[range isEqual:@"card"]?WXGGlassScopeCard:[range isEqual:@"lens"]?WXGGlassScopeLens:
                        [range isEqual:@"segmentLens"]?WXGGlassScopeSegmentLens:[range isEqual:@"finder"]?WXGGlassScopeFinder:WXGGlassScopeOther;
    return [WXGConfig.shared rimStyleForScope:scope];
}
- (void)buildContent {
    if(self.scoped) {
        _scopeOpen=NO;
        _scopeLabel=[self sectionLabel:@"作用范围"];
        _scopeCard=[self addCard:NO];
        UIView *content=_scopeCard.contentView;
        _scopePill=[UIView new];_scopePill.userInteractionEnabled=NO;_scopePill.layer.cornerCurve=kCACornerCurveContinuous;
        [content addSubview:_scopePill];
        _scopeLine=[UIView new];_scopeLine.userInteractionEnabled=NO;[content addSubview:_scopeLine];
        _scopePill.hidden=YES;_scopeLine.hidden=YES;   // shown with the list
        _scopeHeader=[UIButton buttonWithType:UIButtonTypeCustom];
        [_scopeHeader addTarget:self action:@selector(toggleScopes) forControlEvents:UIControlEventTouchUpInside];
        [_scopeHeader addTarget:self action:@selector(scopeHeaderDown) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
        [_scopeHeader addTarget:self action:@selector(scopeHeaderUp) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchDragExit|UIControlEventTouchCancel];
        [content addSubview:_scopeHeader];
        _scopeCurrent=[UILabel new];_scopeCurrent.font=[UIFont systemFontOfSize:16.5 weight:UIFontWeightSemibold];_scopeCurrent.userInteractionEnabled=NO;
        [_scopeHeader addSubview:_scopeCurrent];
        _scopeChevron=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]]];
        _scopeChevron.contentMode=UIViewContentModeCenter;_scopeChevron.userInteractionEnabled=NO;[_scopeHeader addSubview:_scopeChevron];
        NSMutableArray *buttons=[NSMutableArray array];
        for(NSString *scope in self.scopes) {
            UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];[b setTitle:[self titleOfScope:scope] forState:UIControlStateNormal];
            b.titleLabel.font=[UIFont systemFontOfSize:15.5 weight:UIFontWeightSemibold];b.tag=(NSInteger)buttons.count;
            b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;b.contentEdgeInsets=UIEdgeInsetsMake(0,12,0,12);
            [b addTarget:self action:@selector(selectScope:) forControlEvents:UIControlEventTouchUpInside];
            b.hidden=YES;[content addSubview:b];[buttons addObject:b];
        }
        _scopeButtons=buttons;
        _scopeFooter=[UILabel new];_scopeFooter.numberOfLines=0;_scopeFooter.font=[UIFont systemFontOfSize:12.5];
        [self.content addSubview:_scopeFooter];
        [self showScope];
    }
    [self buildGroups];
    // The dock's lift footer quotes the current distance to the screen edge.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(configChanged) name:WXGSettingsChanged object:nil];
}
- (void)buildGroups {
    for(NSDictionary *group in _groups)for(NSString *part in @[@"label",@"card",@"footer"])[group[part] removeFromSuperview];
    _groups=[NSMutableArray array];
    __weak WXGSettingsModule *weakSelf=self;
    _builtStyle=[self scopeRimStyle];NSNumber *style=@(_builtStyle);
    _builtSharing=[self scopeSharing];   // FIX114 L: this range uses another's: only its 共用 (and 恢复)
    NSArray *specGroups=_spec[@"groups"];
    for(NSUInteger groupIndex=0;groupIndex<specGroups.count;groupIndex++) {
        NSDictionary *group=specGroups[groupIndex];
        if([group[@"shareSlot"] boolValue]){group=[self shareGroupFrom:group];if(!group)continue;}   // FIX114 N
        if([group[@"copySlot"] boolValue]){group=[self copyGroupFrom:group];if(!group)continue;}    // FIX115 E
        NSString *scope=group[@"scope"];
        if(self.scoped && scope && ![scope isEqual:_scope])continue;
        NSArray *styles=group[@"styles"];   // FIX85: only for these rim styles
        if(styles && ![styles containsObject:style])continue;
        if(self.scoped && [group[@"notIn"] containsObject:_scope])continue;   // FIX113 O
        if(_builtSharing && ![group[@"share"] boolValue] && ![group[@"title"] isEqual:@"恢复"])continue;   // FIX114 L
        NSMutableDictionary *built=[NSMutableDictionary dictionary];
        if(group[@"title"])built[@"label"]=[self sectionLabel:group[@"title"]];
        WXGSettingsCard *card=[self addCard:NO];built[@"card"]=card;
        NSMutableArray *rows=[NSMutableArray array],*separators=[NSMutableArray array],*rowIndexes=[NSMutableArray array];
        NSArray *specRows=group[@"rows"];
        for(NSUInteger rowIndex=0;rowIndex<specRows.count;rowIndex++) {
            NSDictionary *spec=specRows[rowIndex];
            NSString *key=self.scoped?WXGRowKeyForScope(spec,_scope):spec[@"key"];
            if(key && !key.length)continue;   // FIX113 O: not in this range
            NSString *type=spec[@"type"];WXGSettingsRow *row=nil;
            if([type isEqual:@"slider"])row=[[WXGSliderRow alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"switch"])row=[[WXGSwitchRow alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"color"])row=[[WXGColorRowView alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"wallpaper"])row=[[WXGWallpaperRowView alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"choice"])row=[[WXGChoiceRow alloc]initWithSpec:spec key:key page:self];
            else if([type hasPrefix:@"share"])row=[[WXGShareRow alloc]initWithSpec:spec key:key page:self];   // FIX114 N
            else if([type isEqual:@"action"]) {
                WXGActionRow *action=[[WXGActionRow alloc]initWithSpec:spec key:key page:self];
                NSString *name=spec[@"action"];action.handler=^{[weakSelf runAction:name];};row=action;
            }
            if(!row)continue;
            if(rows.count){UIView *line=[UIView new];line.userInteractionEnabled=NO;[card.contentView addSubview:line];[separators addObject:line];}
            [card.contentView addSubview:row];[rows addObject:row];[rowIndexes addObject:@(rowIndex)];
        }
        built[@"rows"]=rows;built[@"separators"]=separators;built[@"rowIndexes"]=rowIndexes;built[@"specIndex"]=@(groupIndex);
        card.capsule=rows.count==1 && [((WXGSettingsRow *)rows.firstObject).spec[@"bare"] boolValue];   // FIX114 E
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
    if((styled && _builtStyle!=[self scopeRimStyle]) || _builtSharing!=[self scopeSharing]){[self choiceChanged:@{}];return;}   // FIX114 L: or 共用
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
    [self showScope];
    _scopePill.backgroundColor=store.controlTint?[store.controlTint colorWithAlphaComponent:.22]:[UIColor.labelColor colorWithAlphaComponent:.12];
    _scopeLine.backgroundColor=[UIColor.labelColor colorWithAlphaComponent:.12];
}
- (CGFloat)layoutContentForWidth:(CGFloat)width {
    CGFloat inner=MIN(MAX(100,width-2*self.sideMargin),620),side=(width-inner)*.5,y=0;
    if(_scopeCard) {
        _scopeLabel.frame=CGRectMake(side+6,y,inner-12,18);y+=18+8;
        // FIX114 C: the range chosen and an arrow; open, every range below it.
        CGFloat head=54,row=46,h=head+(_scopeOpen?_scopeButtons.count*row+8:0);
        _scopeCard.frame=CGRectMake(side,y,inner,h);
        _scopeHeader.frame=CGRectMake(0,0,inner,head);
        _scopeChevron.bounds=CGRectMake(0,0,24,24);_scopeChevron.center=CGPointMake(inner-16-12,head*.5);   // (review) it may be turned
        _scopeCurrent.frame=CGRectMake(18,0,MAX(20,inner-18-16-24-8),head);
        CGFloat hairline=1/MAX(1,UIScreen.mainScreen.scale);
        _scopeLine.frame=CGRectMake(16,head-hairline*.5,inner-32,hairline);
        for(UIButton *b in _scopeButtons)b.frame=CGRectMake(6,head+4+b.tag*row,inner-12,row);
        NSUInteger selected=self.selectedScopeIndex;
        if(selected<_scopeButtons.count)_scopePill.frame=CGRectInset(_scopeButtons[selected].frame,0,4);
        _scopePill.layer.cornerRadius=MAX(0,MIN(round(WXGSettingsStore.shared.cardRadius)-6,(row-8)*.5));
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
// FIX114 L: the range shown uses another range's settings of this page.
// FIX114 N: as resolved (a value naming no range of the page is its own).
- (BOOL)scopeSharing {
    NSNumber *page=_spec[@"sharePage"];if(!self.scoped || !page || !_scope)return NO;
    return WXGShareKeyFor(_scope,page.integerValue) && ![WXGShareResolved(_scope,page.integerValue) isEqual:_scope];
}
// FIX114 N: 共用到 for the range shown (a switch per other range of the page,
// 全部范围 first), or 共用 when it uses another's.
- (NSDictionary *)shareGroupFrom:(NSDictionary *)slot {
    NSNumber *pageNumber=slot[@"sharePage"]?:_spec[@"sharePage"];
    if(!self.scoped || !pageNumber || !_scope)return nil;
    NSInteger page=pageNumber.integerValue;
    if(!WXGShareKeyFor(_scope,page))return nil;
    NSMutableDictionary *group=[slot mutableCopy];[group removeObjectForKey:@"shareSlot"];
    NSString *followed=WXGShareResolved(_scope,page);
    if(![followed isEqual:_scope]) {
        group[@"title"]=@"共用";group[@"footer"]=WXG_FOLLOW_NOTE;
        group[@"rows"]=@[@{@"type":@"shareFollow",@"title":[NSString stringWithFormat:@"用「%@」的设置",[self titleOfScope:followed]],
                           @"target":_scope,@"source":followed,@"page":@(page)}];
        return group;
    }
    NSMutableArray *targets=[NSMutableArray array];
    for(NSString *t in self.scopes)if(![t isEqual:_scope] && WXGShareKeyFor(t,page))[targets addObject:t];
    if(!targets.count)return nil;
    NSMutableArray *rows=[NSMutableArray array];
    if(targets.count>1)[rows addObject:@{@"type":@"shareAll",@"title":@"全部范围",@"targets":targets,@"source":_scope,@"page":@(page)}];
    for(NSString *t in targets)[rows addObject:@{@"type":@"shareTo",@"title":[self titleOfScope:t],@"target":t,@"source":_scope,@"page":@(page)}];
    group[@"title"]=@"共用到";group[@"footer"]=WXG_SHARE_NOTE;group[@"rows"]=rows;
    return group;
}
- (void)shareChanged {[self refreshRows];}
// FIX115 E: 复制到 for the range shown: one row per other range of the page
// (复制到全部范围 first when there are several).
- (NSDictionary *)copyGroupFrom:(NSDictionary *)slot {
    if(!self.scoped || !_scope)return nil;
    NSMutableArray *targets=[NSMutableArray array];
    for(NSString *t in self.scopes)if(![t isEqual:_scope])[targets addObject:t];
    if(!targets.count)return nil;
    NSMutableDictionary *group=[slot mutableCopy];[group removeObjectForKey:@"copySlot"];
    NSMutableArray *rows=[NSMutableArray array];
    if(targets.count>1)[rows addObject:WXGAction(@"复制到全部范围",@"copyTo:*",NO)];
    for(NSString *t in targets)[rows addObject:WXGAction([NSString stringWithFormat:@"复制到「%@」",[self titleOfScope:t]],[@"copyTo:" stringByAppendingString:t],NO)];
    group[@"rows"]=rows;
    return group;
}
- (void)copyScopeTo:(NSString *)target {
    NSString *from=_scope;if(!from.length)return;
    NSArray<NSString *> *targets=[target isEqual:@"*"]?[self.scopes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *t,__unused NSDictionary *b){return ![t isEqual:from];}]]:@[target];
    if(!targets.count)return;
    NSString *names=[target isEqual:@"*"]?@"其它全部范围":[NSString stringWithFormat:@"「%@」",[self titleOfScope:target]];
    NSString *module=_module;NSInteger page=[_spec[@"sharePage"] integerValue];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"把「%@」的设置复制到%@？",[self titleOfScope:from],names]
        message:[NSString stringWithFormat:@"%@原来的值会被替换成「%@」现在的值，不能撤销；之后各调各的。",names,[self titleOfScope:from]] preferredStyle:UIAlertControllerStyleAlert];
    __weak WXGSettingsModule *weakSelf=self;
    void (^copy)(BOOL)=^(BOOL allPages){
        NSUInteger changed=0;NSArray<NSString *> *modules=WXGCopyModules();
        for(NSUInteger i=0;i<modules.count;i++) {
            NSString *m=allPages?modules[i]:module;NSInteger p=allPages?(NSInteger)i:page;
            // 全部范围: every other range of each page (the pages have different ranges).
            NSArray<NSString *> *these=[target isEqual:@"*"]?WXGModuleSpec(m)[@"scopes"]:targets;
            for(NSString *t in these)if(![t isEqual:from])changed+=WXGCopyRange(m,p,from,t);
            if(!allPages)break;
        }
        [WXGConfig.shared save];
        if(WXGConfig.shared.haptics)[[[UINotificationFeedbackGenerator alloc]init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        WXGSettingsModule *me=weakSelf;[me refreshRows];
        UIAlertController *done=[UIAlertController alertControllerWithTitle:changed?[NSString stringWithFormat:@"已复制（改了 %lu 项）",(unsigned long)changed]:@"已经一样了，没有要改的"
            message:nil preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [me presentViewController:done animated:YES completion:nil];
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"只复制这一页" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){copy(NO);}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"四页一起（折射、模糊、材质、边框）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){copy(YES);}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)choiceChanged:(NSDictionary *)spec {
    if(spec.count && _builtStyle==[self scopeRimStyle] && _builtSharing==[self scopeSharing])return;   // (review) back to the style shown: nothing to rebuild
    [UIView performWithoutAnimation:^{[self buildGroups];[self.view setNeedsLayout];[self.view layoutIfNeeded];}];
    UIScrollView *scroll=self.scrollView;
    CGFloat maximum=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
    if(scroll.contentOffset.y>maximum)[scroll setContentOffset:CGPointMake(0,maximum) animated:YES];
}
- (NSString *)titleOfScope:(NSString *)scope {
    NSDictionary *titles=@{@"dock":@"底栏",@"other":@"其余玻璃",@"bubble":@"气泡",@"segment":@"分组",@"card":@"设置页",@"lens":@"底栏透镜",@"segmentLens":@"分组透镜",@"finder":@"视频号"};
    return titles[scope]?:scope;
}
// What the range chosen covers (only that one: the list of all was long).
- (NSString *)descriptionOfScope:(NSString *)scope {
    NSDictionary *texts=@{@"dock":@"悬浮标签栏和按压时的透镜。",
                          @"other":@"导航按钮、标题胶囊、输入栏、菜单等。",
                          @"bubble":@"聊天里的液态气泡。",
                          @"segment":@"聊天列表顶部的分组栏（它的透镜和选中胶囊在“分组”页）。",
                          @"card":@"这几页设置的卡片和按钮，调节时可直接看到。",
                          @"lens":@"底栏按住时浮起的透镜（图标和文字的透镜）自己的边框，三种样式都能用，按住时随按压出现。",
                          @"segmentLens":@"分组栏按住时的透镜和选中胶囊自己的边框，和底栏透镜分开调；第一次打开时和底栏透镜当时的设置一样。",
                          @"finder":@"视频号第一页顶部按钮下面那几个胶囊自己的边框（只有边框，没有材质；折射、模糊跟其余玻璃）。浅色、深色各一套，跟系统外观切换，第一次打开时两套的颜色、不透明度、宽度这些都和其余玻璃的深色模式一样。描边细节和外阴影不在这个范围里调：胶囊用其余玻璃的（随系统浅色 / 深色）。"};
    return texts[scope]?:@"";
}
- (void)showScope {
    WXGSettingsStore *store=WXGSettingsStore.shared;NSUInteger selected=self.selectedScopeIndex;
    _scopeCurrent.text=[self titleOfScope:_scope];_scopeCurrent.textColor=store.accentColor;
    _scopeChevron.tintColor=store.secondaryColor;
    _scopeHeader.accessibilityLabel=@"作用范围";
    _scopeHeader.accessibilityValue=[NSString stringWithFormat:@"%@，%@",[self titleOfScope:_scope],_scopeOpen?@"已展开":@"已收起"];
    _scopeHeader.accessibilityHint=_scopeOpen?@"收起范围列表":@"展开选择别的范围";
    for(UIButton *b in _scopeButtons) {
        BOOL on=(NSUInteger)b.tag==selected;UIColor *color=on?store.accentColor:store.secondaryColor;
        [b setTitleColor:color forState:UIControlStateNormal];[b setTitleColor:[color colorWithAlphaComponent:.45] forState:UIControlStateHighlighted];
        b.accessibilityTraits=on?UIAccessibilityTraitButton|UIAccessibilityTraitSelected:UIAccessibilityTraitButton;
    }
    _scopeFooter.text=[self descriptionOfScope:_scope];
}
// Opened and closed in place (glass is never faded or flown in: the card and
// the groups below take their new places at once; the arrow turns and the
// list's titles fade in).
- (void)setScopesOpen:(BOOL)open {
    if(open==_scopeOpen)return;
    _scopeOpen=open;[self showScope];
    for(UIButton *b in _scopeButtons){b.hidden=!open;b.alpha=open?0:1;}
    _scopePill.hidden=!open;_scopeLine.hidden=!open;
    [UIView performWithoutAnimation:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];}];
    [UIView animateWithDuration:.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_scopeChevron.transform=open?CGAffineTransformMakeRotation((CGFloat)M_PI*.999):CGAffineTransformIdentity;
        for(UIButton *b in self->_scopeButtons)b.alpha=1;
    } completion:nil];
    UIScrollView *scroll=self.scrollView;
    CGFloat maximum=MAX(0,scroll.contentSize.height-scroll.bounds.size.height),target=MIN(scroll.contentOffset.y,maximum);
    // (review) closed after scrolling down the list: back to where the card is.
    if(!open && _scopeCard) {
        CGFloat top=[_scopeCard convertPoint:CGPointZero toView:scroll].y-scroll.adjustedContentInset.top-self.contentTop;
        if(target>top)target=MAX(-scroll.adjustedContentInset.top,top);
    }
    if(fabs(target-scroll.contentOffset.y)>.5)[scroll setContentOffset:CGPointMake(0,target) animated:YES];
    // (review) VoiceOver: to the chosen range in the list, back to the card when closed.
    NSUInteger selected=self.selectedScopeIndex;
    UIView *focus=open && selected<_scopeButtons.count?_scopeButtons[selected]:_scopeHeader;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,focus);
}
- (void)scopeHeaderDown {_scopeCurrent.alpha=.45;_scopeChevron.alpha=.45;}
- (void)scopeHeaderUp {_scopeCurrent.alpha=1;_scopeChevron.alpha=1;}
- (void)toggleScopes {
    if(WXGConfig.shared.haptics)[[[UISelectionFeedbackGenerator alloc]init] selectionChanged];
    [self setScopesOpen:!_scopeOpen];
}
- (void)selectScope:(UIButton *)sender {
    NSString *scope=sender.tag>=0 && sender.tag<(NSInteger)self.scopes.count?self.scopes[sender.tag]:@"other";
    if([scope isEqual:_scope]){[self setScopesOpen:NO];return;}
    _scope=scope;WXGLastScope=scope;
    if(WXGConfig.shared.haptics)[[[UISelectionFeedbackGenerator alloc]init] selectionChanged];
    // The groups replaced in place, the list closed (glass is never faded).
    [UIView performWithoutAnimation:^{[self buildGroups];}];
    [self setScopesOpen:NO];
    [UIView performWithoutAnimation:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];}];
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
    if([action isEqual:@"meBannerVideo"]){[WXGMeHeader.shared pickBannerVideoFrom:self];return;}   // FIX118 B
    if([action isEqual:@"meBannerVideoClear"]){[WXGMeHeader.shared clearBannerVideo];return;}
    if([action isEqual:@"manageGroups"]){[self.navigationController pushViewController:WXGChatGroupsPage() animated:YES];return;}   // FIX113 R
    if([action hasPrefix:@"copyTo:"]){[self copyScopeTo:[action substringFromIndex:7]];return;}   // FIX115 E
    // FIX114 O (user: the capsule's proportions are not the screenshot's): the
    // iOS 26 Messages capsule as measured (3x screenshot): about 29 pt high,
    // 17 pt text, a 12 pt chevron (its paddings 14 / 11 pt are fixed).
    if([action isEqual:@"avatarCapsuleIOS"]){WXGRowSet(@"avatarCapsuleHeight",@29.0);WXGRowSet(@"avatarCapsuleTextSize",@17.0);WXGRowSet(@"avatarCapsuleChevronSize",@12.0);[self refreshRows];return;}
    if([action isEqual:@"segmentFromDock"]) {   // FIX113 P
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"套用底栏现在的样子？"
            message:@"分组栏的折射、模糊、材质、边框、选中胶囊（颜色、内边距）、透镜和文字颜色换成底栏现在的值；分组栏开关、悬浮、字号字重不变。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak WXGSettingsModule *weakSelf=self;
        [alert addAction:[UIAlertAction actionWithTitle:@"套用" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            [WXGConfig.shared segmentFromDock];[weakSelf refreshRows];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    // FIX84: 帧率与参数.
    __weak WXGSettingsModule *weakModule=self;
    if([action isEqual:@"perfReport"]){WXGPerfShowReport(self);return;}
    if([action isEqual:@"perfSwitches"]){WXGTransitionPerfShowReport(self);return;}   // FIX113 Z
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
        NSArray *ranges=self.scoped?self.scopes:@[@"other"];
        for(NSDictionary *group in _spec[@"groups"])for(NSDictionary *row in group[@"rows"])for(NSString *scope in ranges) {
            NSString *key=self.scoped?WXGRowKeyForScope(row,scope):row[@"key"];   // FIX113 O: every range's own key
            if([key isKindOfClass:NSString.class] && key.length && ![key hasPrefix:@"pref."] && ![key hasPrefix:@"ui."] && ![keys containsObject:key])[keys addObject:key];
        }
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"恢复“%@”的默认值？",_spec[@"title"]?:@"本页"]
            message:@"这一页的设置（每个范围都算）回到默认值，其它页不变。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak WXGSettingsModule *weakSelf=self;
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
            [WXGConfig.shared resetKeys:keys];[weakSelf refreshRows];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if([action isEqual:@"reset"]) {   // FIX115 H: the global reset (as the home page's card)
        __weak WXGSettingsModule *weakSelf=self;
        WXGConfirmResetAll(self,^{[weakSelf refreshRows];});
    }
}
@end
UIViewController *WXGSettingsModulePage(NSString *module) {
    if([WXGHiddenSettingsModules() containsObject:module])return nil;   // FIX59: not in this build
    return WXGModuleSpec(module)?[[WXGSettingsModule alloc]initWithModule:module]:nil;
}
UIViewController *WXGSettingsModulePageFocused(NSString *module,NSInteger group,NSInteger row) {
    WXGSettingsModule *page=(WXGSettingsModule *)WXGSettingsModulePage(module);
    if(group>=0)[page focusGroup:group row:row];
    return page;
}

#pragma mark - Search

// FIX113 O: the settings search (the home page's search box). Every query
// word must appear in the result's title or where it is (page, group); a
// row or group whose own title holds a word comes first, a group found only
// by its explanation last.
static BOOL WXGSearchHas(NSString *text,NSString *word) {
    return text.length && [text rangeOfString:word options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch].location!=NSNotFound;
}
static BOOL WXGSearchAll(NSString *text,NSArray<NSString *> *words) {for(NSString *w in words)if(!WXGSearchHas(text,w))return NO;return YES;}
static BOOL WXGSearchAny(NSString *text,NSArray<NSString *> *words) {for(NSString *w in words)if(WXGSearchHas(text,w))return YES;return NO;}
NSArray<NSDictionary *> *WXGSettingsSearch(NSString *query,NSArray<NSArray *> *cards) {
    NSMutableArray<NSString *> *words=[NSMutableArray array];
    for(NSString *w in [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])if(w.length)[words addObject:w];
    if(!words.count)return @[];
    NSMutableArray *first=[NSMutableArray array],*second=[NSMutableArray array],*last=[NSMutableArray array];
    NSDictionary *scopeTitles=@{@"dock":@"底栏",@"other":@"其余玻璃",@"bubble":@"气泡",@"segment":@"分组",@"card":@"设置页",@"lens":@"底栏透镜",@"segmentLens":@"分组透镜",@"finder":@"视频号"};
    for(NSArray *card in cards) {
        if(card.count<3 || ![card[0] isKindOfClass:NSString.class])continue;
        NSString *module=card[0];NSDictionary *spec=WXGModuleSpec(module);if(!spec)continue;
        NSString *pageTitle=[spec[@"title"] isKindOfClass:NSString.class]?spec[@"title"]:card[1];
        if(WXGSearchAll([NSString stringWithFormat:@"%@ %@ %@",pageTitle,card[1],card[2]],words))
            [first addObject:@{@"module":module,@"group":@(-1),@"row":@(-1),@"title":card[1],@"path":card[2]}];
        NSArray *groups=spec[@"groups"];
        for(NSUInteger g=0;g<groups.count;g++) {
            NSDictionary *group=groups[g];
            NSString *groupTitle=[group[@"title"] isKindOfClass:NSString.class]?group[@"title"]:@"";
            NSString *range=scopeTitles[group[@"scope"]];
            NSString *place=range && groupTitle.length?[NSString stringWithFormat:@"%@（%@）",groupTitle,range]:groupTitle;
            NSString *context=[NSString stringWithFormat:@"%@ %@",pageTitle,place];
            NSString *footer=[group[@"footer"] isKindOfClass:NSString.class] && ![group[@"footer"] isEqual:@"lift"]?group[@"footer"]:@"";
            if(place.length && WXGSearchAny(place,words) && WXGSearchAll(context,words))
                [first addObject:@{@"module":module,@"group":@(g),@"row":@(-1),@"title":place,@"path":pageTitle}];
            else if(place.length && footer.length && WXGSearchAll([context stringByAppendingFormat:@" %@",footer],words))
                [last addObject:@{@"module":module,@"group":@(g),@"row":@(-1),@"title":place,@"path":pageTitle}];
            NSArray *rows=group[@"rows"];
            for(NSUInteger r=0;r<rows.count;r++) {
                NSString *title=rows[r][@"title"];
                if(![title isKindOfClass:NSString.class] || !title.length || !WXGSearchAny(title,words))continue;
                if(!WXGSearchAll([context stringByAppendingFormat:@" %@",title],words))continue;
                NSString *path=place.length?[NSString stringWithFormat:@"%@ › %@",pageTitle,place]:pageTitle;
                [(WXGSearchAll(title,words)?first:second) addObject:@{@"module":module,@"group":@(g),@"row":@(r),@"title":title,@"path":path}];
            }
        }
    }
    [first addObjectsFromArray:second];[first addObjectsFromArray:last];
    return first;
}
