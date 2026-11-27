#import "WXGSettingsKit.h"
#import "WXGBannerLibraryController.h"
#import "WXGInputSymbols.h"

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
static NSDictionary *WXGSwitch3(NSString *title,NSString *key,NSString *dock,NSString *bubble) {
    return WXGBubbleKey(WXGSwitch(title,key,dock),bubble);
}
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
/* FIX113 O / R20: a row's key in a range. 分组、设置页、视频号 rows are derived from
   the bubbles' (or dock's) key: bubbleGlassVeil -> finderGlassVeil, bubbleRimStyle -> finderGlassRimStyle. */
static NSString *WXGRowKeyForScope(NSDictionary *spec,NSString *scope) {
    if([scope isEqual:@"dock"])return spec[@"dock"]?:spec[@"key"];
    if([scope isEqual:@"bubble"])return spec[@"bubble"]?:spec[@"key"];
    if([scope isEqual:@"segment"] || [scope isEqual:@"card"] || [scope isEqual:@"lens"] || [scope isEqual:@"segmentLens"] || [scope isEqual:@"finder"]) {
        if(spec[scope])return spec[scope];
        NSString *from=spec[@"bubble"],*prefix=@"bubble";
        if(!from){from=spec[@"dock"];prefix=@"dock";}
        if([from hasPrefix:prefix]) {
            NSString *suffix=[from substringFromIndex:prefix.length];
            NSString *stem=scope;
            if([scope isEqual:@"lens"])stem=@"lensGlass";
            else if([scope isEqual:@"segmentLens"])stem=@"segmentLensGlass";
            else if([scope isEqual:@"finder"])stem=([suffix hasPrefix:@"Glass"] || [suffix hasPrefix:@"DarkGlass"])?@"finder":@"finderGlass";
            NSString *derived=[stem stringByAppendingString:suffix];
            return [WXGConfig.shared knowsKey:derived]?derived:@"";
        }
    }
    return spec[@"key"];
}
#define WXG_COPY_NOTE @"复制到：把这个范围现在的设置一次性复制给另一个范围——那个范围自己的值直接被替换成这里的（不能撤销），之后两边各调各的。只复制两边都有的项（例如透镜边框范围只复制边框）。"
static NSDictionary *WXGCopyGroup(void) {
    NSMutableDictionary *c=[WXGGroup(@"复制到",nil,@[],WXG_COPY_NOTE) mutableCopy];
    c[@"copySlot"]=@YES;
    return c;
}
static NSDictionary *WXGChoiceValues(NSDictionary *row,NSArray<NSNumber *> *values) {NSMutableDictionary *m=[row mutableCopy];m[@"values"]=values;return m;}
static NSDictionary *WXGHomeMenuGroup(NSString *title,WXGHomeMenuStyle style,NSArray *controls,NSString *footer) {
    NSArray *rows=[controls arrayByAddingObjectsFromArray:@[
        WXGSlider(@"动画速度",@"homeMenuSpeed",nil,.5,2,@"%.2f 倍"),
        WXGSlider(@"展开后自动收回（0 = 关闭）",@"homeMenuAutoClose",nil,0,30,@"%.0f s")]];
    NSMutableDictionary *group=[WXGGroup(title,nil,rows,footer) mutableCopy];
    group[@"homeMenuStyle"]=@(style);
    return group;
}
static NSDictionary *WXGHomeFormGroup(BOOL categories,NSString *title,NSArray *rows,NSString *footer) {
    NSMutableDictionary *spec=[WXGGroup(title,nil,rows,footer) mutableCopy];
    spec[@"homeGroupForm"]=@(categories);
    return spec;
}
static BOOL WXGShowsHomeMenuGroup(NSDictionary *group) {
    NSNumber *form=group[@"homeGroupForm"];
    if(form && form.boolValue!=([WXGConfig.shared extraNumber:@"homeGroupForm"]>.5))return NO;
    NSNumber *required=group[@"homeMenuStyle"];
    return !required || required.integerValue==WXGConfig.shared.homeMenuStyle;
}
static NSDictionary *WXGModuleSpec(NSString *module) {
    if([module hasPrefix:@"split"]) {
        NSMutableArray *links=[NSMutableArray array];
        for(WXGInputSymbolRole role=0;role<WXGInputSymbolCount;role++) {
            WXGInputSymbolInfo info=WXGInputRoleInfo(role);
            NSString *stem=@(info.stem),*label=@(info.label);
            if([module isEqual:stem]) {
                NSMutableDictionary *name=[WXGRow(@"symbol",@"符号名称",[stem stringByAppendingString:@"SymbolName"],nil) mutableCopy];
                name[@"role"]=@(role);
                return @{@"title":label,@"groups":@[
                    WXGGroup(nil,nil,@[name,
                        WXGChoice3(@"粗细",[stem stringByAppendingString:@"Weight"],nil,nil,@[@"纤细",@"细",@"常规",@"半粗",@"粗"],NO),
                        WXGSlider(@"大小",[stem stringByAppendingString:@"Size"],nil,10,32,@"%.1f pt"),
                        WXGColorRow(@"浅色模式",[stem stringByAppendingString:@"LightHex"],nil),
                        WXGColorRow(@"深色模式",[stem stringByAppendingString:@"DarkHex"],nil)],nil),
                    WXGGroup(nil,nil,@[WXGAction(@"恢复这个图标的默认设置",@"resetPage",YES)],nil)]};
            }
            [links addObject:WXGAction(label,[@"open:" stringByAppendingString:stem],NO)];
        }
        if([module isEqual:@"splitSymbols"])return @{@"title":@"双端输入栏图标",@"groups":@[WXGGroup(nil,nil,links,nil)]};
    }
    if([module isEqual:@"pureDock"])return @{@"title":@"底栏透镜与形变",@"scoped":@NO,@"groups":@[
        WXGGroup(@"R8 极光透镜引擎",nil,@[WXGSwitch(@"启用 R8 极光透镜与形变",@"dockPureGlassMode",nil)],
                 @"底栏与首页分组栏（含标题分组栏）统一使用本页的 R8 连续极光透镜与自适应形变，并直接兼容离散底栏、Telegram 图标、底栏搜索与 iOS 27 边框。"),
        WXGGroup(@"透镜折射与色散 · R8 极光连续模型",nil,@[
            WXGSlider(@"透镜折射带宽",@"dockPureR8Band",nil,0,40,@"%.1f pt"),
            WXGSlider(@"透镜折射深度",@"dockPureR8Depth",nil,0,50,@"%.1f pt"),
            WXGSlider(@"透镜连续极光色散",@"dockPureR8Dispersion",nil,0,5,@"%.2f")],
            @"默认：带宽 18.0 pt、深度 26.0 pt、色散 2.40。首页分组栏与标题分组栏会自动按自身高度相对底栏等比缩放。"),
        WXGGroup(@"透镜内缩窄底栏与图标放大",nil,@[
            WXGSlider(@"透镜内底栏收缩比例",@"dockPureInnerBarShrink",nil,0,.55,@"%.2f"),
            WXGSwitch(@"内底栏纯平无颈部斜坡（对比开关）",@"dockPureInnerFlat",nil),
            WXGSlider(@"透镜内图标与标题放大",@"dockPureIconZoom",nil,1,1.4,@"%.2f 倍")],
            @"按当前底栏实际高度（包含按压时底栏放大倍数）的比例向内收缩并保持不变（默认 0.18，即保留 82% 高度）；底栏、分组栏与标题分组栏完全同步。"),
        WXGGroup(@"按压尺寸与底栏本体",nil,@[
            WXGSlider(@"按压时底栏放大",@"dockPureBarGrowth",nil,1,1.08,@"%.3f 倍"),
            WXGSlider(@"按压时透镜高度放大",@"dockPureLensGrowth",nil,1,1.4,@"%.2f 倍"),
            WXGSlider(@"抬起时透镜加宽",@"dockPureLensLiftWidth",nil,0,40,@"%.1f pt"),
            WXGSlider(@"透镜超出底栏两端",@"dockPureEndWrap",nil,0,14,@"%.1f pt"),
            WXGSwitch(@"按压时底栏发光（可选）",@"dockPureTouchGlow",nil)],
            @"底栏、分组栏、视频号及各类玻璃的自定义色彩材质、阴影与 iOS 27 边框均可在「效果调整」里独立微调。"),
        WXGGroup(@"iOS 26 胶囊切换透镜时机",nil,@[
            WXGSlider(@"切换弹簧响应时间",@"dockPureMoveResponse",nil,.2,.8,@"%.2f s"),
            WXGSlider(@"切换弹簧阻尼比",@"dockPureMoveDamping",nil,.5,1.2,@"%.2f"),
            WXGSlider(@"胶囊变透镜时机（滑动比例）",@"dockPureTapLiftRatio",nil,.15,.9,@"%.2f"),
            WXGSlider(@"透镜回落为胶囊耗时",@"dockPureTapDropTime",nil,.08,.6,@"%.2f s"),
            WXGSlider(@"松手后保持透镜停留",@"dockPureLensHang",nil,0,.5,@"%.2f s")],
            @"保留实测的胶囊→透镜切换时机与停留节奏。透镜尚未落下时连续点切其他标签会自动维持玻璃透镜状态。"),
        WXGGroup(@"运动时透镜形变（幅度自适应时长）",nil,@[
            WXGSwitch(@"开启运动形变",@"dockPureFlexOn",nil),
            WXGSlider(@"落下后最扁高度（改大自动提速）",@"dockPureFlexRestFloor",nil,.5,1,@"%.2f"),
            WXGSlider(@"落定压扁幅度",@"dockPureFlexFlatten",nil,0,1.5,@"%.2f"),
            WXGSlider(@"形变整体幅度",@"dockPureFlexStrength",nil,0,2,@"%.2f"),
            WXGSlider(@"加速挤高幅度",@"dockPureFlexSqueeze",nil,0,1.5,@"%.2f"),
            WXGSlider(@"基础回弹频率",@"dockPureFlexSlow",nil,3,20,@"%.1f rad/s"),
            WXGSlider(@"回弹阻尼比",@"dockPureFlexDamping",nil,.15,1.2,@"%.2f"),
            WXGSwitch(@"压扁与拉高对称",@"dockPureFlexSymmetric",nil)],
            @"修改最扁高度时按有效形变路程自动缩短回弹耗时，并用平滑软膝替代硬截断。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 @"仅恢复本页透镜与形变参数为默认值，不影响其他页面。")
    ]};
    if([module isEqual:@"effect"])return @{@"title":@"效果调整",@"scoped":@YES,@"scopes":@[@"other",@"dock",@"lens",@"segment",@"segmentLens",@"bubble",@"card",@"finder"],@"groups":@[
        WXGNotIn(WXGGroup(@"折射",nil,@[
                 WXGSlider3(@"折射带宽（短边的比例）",@"glassBand",@"dockGlassBand",@"bubbleGlassBand",.02,.5,@"%.3f"),
                 WXGSlider3(@"边缘取样深度（短边的比例）",@"glassDepth",@"dockGlassDepth",@"bubbleGlassDepth",0,1,@"%.3f"),
                 WXGSlider3(@"带宽上限",@"glassBandMax",@"dockGlassBandMax",@"bubbleGlassBandMax",4,80,@"%.0f pt"),
                 WXGSlider3(@"最外圈最大压缩（0 = 不限制）",@"glassSqueeze",@"dockGlassSqueeze",@"bubbleGlassSqueeze",0,20,@"%.1f 倍"),
                 WXGSlider3(@"色散",@"glassDispersion",@"dockGlassDispersion",@"bubbleGlassDispersion",0,3,@"%.2f")],
                 @"沿用 iOS 26.6 实测的折射曲线。默认带宽为玻璃短边的 25%，边缘取样深度为短边的 80%。带宽达到 20 pt 上限后，取样深度也按比例缩小。"),@[@"lens",@"segmentLens"]),
        WXGNotIn(WXGGroup(@"模糊",nil,@[
                 WXGSlider3(@"小玻璃（短边 ≤ 48 pt）",@"glassBlurSmall",@"dockGlassBlurSmall",@"bubbleGlassBlurSmall",0,10,@"%.2f"),
                 WXGSlider3(@"大玻璃（短边 90 pt）",@"glassBlurLarge",@"dockGlassBlurLarge",@"bubbleGlassBlurLarge",0,20,@"%.2f")],
                 @"两个滑块分别设置小玻璃和大玻璃的背景模糊半径。当前范围内的玻璃按实际短边长度在两者之间过渡。"),@[@"lens",@"segmentLens"]),
        WXGNotIn(WXGGroup(@"自定义色彩材质 · 浅色模式",nil,@[
                 WXGSwitch3(@"启用自定义色彩材质",@"glassTintOn",@"dockGlassTintOn",@"bubbleGlassTintOn"),
                 WXGColor3(@"材质颜色",@"glassTintHex",@"dockGlassTintHex",@"bubbleGlassTintHex"),
                 WXGSlider3(@"色彩材质覆盖比例",@"glassVeil",@"dockGlassVeil",@"bubbleGlassVeil",0,1,@"%.3f"),
                 WXGSlider3(@"背景饱和度",@"glassSaturation",@"dockGlassSaturation",@"bubbleGlassSaturation",0,3,@"%.2f"),
                 WXGSlider3(@"背景亮度",@"glassBrightness",@"dockGlassBrightness",@"bubbleGlassBrightness",-.3,.3,@"%+.2f")],
                 @"所有玻璃（含底栏、分组栏、视频号、气泡、设置页等）均已统一使用已验证的液态折射与模糊。这里可为每个范围单独启用自定义色彩材质并调节覆盖比例；未启用自定义颜色时，按系统默认白/黑面纱覆盖。"),@[@"lens",@"segmentLens"]),
        WXGNotIn(WXGGroup(@"自定义色彩材质 · 深色模式",nil,@[
                 WXGColor3(@"材质颜色",@"darkGlassTintHex",@"dockDarkGlassTintHex",@"bubbleDarkGlassTintHex"),
                 WXGSlider3(@"色彩材质覆盖比例",@"darkGlassVeil",@"dockDarkGlassVeil",@"bubbleDarkGlassVeil",0,1,@"%.3f"),
                 WXGSlider3(@"背景饱和度",@"darkGlassSaturation",@"dockDarkGlassSaturation",@"bubbleDarkGlassSaturation",0,3,@"%.2f"),
                 WXGSlider3(@"背景亮度",@"darkGlassBrightness",@"dockDarkGlassBrightness",@"bubbleDarkGlassBrightness",-.3,.3,@"%+.2f")],
                 @"深色模式下的自定义色彩材质颜色与覆盖比例。视频号范围默认覆盖比例为 0（透明视频背景），可按需调高或着色。"),@[@"lens",@"segmentLens"]),
        WXGNotIn(WXGGroup(@"阴影",nil,@[
                 WXGSlider3(@"浓度（浅色模式）",@"glassShadow",@"dockGlassShadow",@"bubbleGlassShadow",0,.6,@"%.2f"),
                 WXGSlider3(@"浓度（深色模式）",@"darkGlassShadow",@"dockDarkGlassShadow",@"bubbleDarkGlassShadow",0,.6,@"%.2f"),
                 WXGSlider3(@"柔和度",@"glassShadowBlur",@"dockGlassShadowBlur",@"bubbleGlassShadowBlur",.5,40,@"%.1f pt"),
                 WXGSlider3(@"向下偏移",@"glassShadowOffset",@"dockGlassShadowOffset",@"bubbleGlassShadowOffset",-10,30,@"%.1f pt")],
                 @"这些参数控制当前范围的玻璃外阴影。"),@[@"lens",@"segmentLens"]),
        WXGGroup(@"边框样式",nil,@[WXGBare(WXGChoiceValues(WXGChoice3(@"样式",@"rimStyle",@"dockRimStyle",@"bubbleRimStyle",@[@"iOS 26",@"iOS 27"],YES),@[@3,@2]))],
                 @"每个范围（包含底栏透镜、分组透镜与视频号）可独立选择 iOS 26 或 iOS 27 边框样式。"),
        WXGStyled(WXGGroup(@"iOS 26 · 形状",nil,@[WXGSlider3(@"高度（往里多宽）",@"edge26Height",@"dockEdge26Height",@"bubbleEdge26Height",.3,4,@"%.2f pt"),
                                 WXGSlider3(@"往里变暗",@"edge26Curve",@"dockEdge26Curve",@"bubbleEdge26Curve",0,1,@"%.2f"),
                                 WXGSlider3(@"主光方向",@"edge26Angle",@"dockEdge26Angle",@"bubbleEdge26Angle",0,180,@"%.0f°"),
                                 WXGSlider3(@"主光（右下）",@"edge26Key",@"dockEdge26Key",@"bubbleEdge26Key",0,1.5,@"%.2f"),
                                 WXGSlider3(@"补光（左上）",@"edge26Fill",@"dockEdge26Fill",@"bubbleEdge26Fill",0,1.5,@"%.2f"),
                                 WXGSlider3(@"收拢",@"edge26Spread",@"dockEdge26Spread",@"bubbleEdge26Spread",.3,6,@"%.2f"),
                                 WXGSlider3(@"最暗处保留",@"edge26Floor",@"dockEdge26Floor",@"bubbleEdge26Floor",0,1,@"%.2f")],
                 @"iOS 26 系统高光边框：右下一盏主光、左上一盏补光，颜色取自玻璃底下的内容。"),@[@3]),
        WXGStyled(WXGGroup(@"iOS 26 · 浅色模式",nil,@[WXGSlider3(@"强度",@"edge26Opacity",@"dockEdge26Opacity",@"bubbleEdge26Opacity",0,1,nil),
                                 WXGSlider3(@"亮度增益",@"edge26Gain",@"dockEdge26Gain",@"bubbleEdge26Gain",0,4,@"%.3f"),
                                 WXGSlider3(@"色彩增益",@"edge26Chroma",@"dockEdge26Chroma",@"bubbleEdge26Chroma",0,8,@"%.3f"),
                                 WXGSlider3(@"提亮",@"edge26Lift",@"dockEdge26Lift",@"bubbleEdge26Lift",0,1,@"%.3f"),
                                 WXGSlider3(@"环绕微光",@"edge26Ring",@"dockEdge26Ring",@"bubbleEdge26Ring",0,1,@"%.2f")],
                 nil),@[@3]),
        WXGStyled(WXGGroup(@"iOS 26 · 深色模式",nil,@[WXGSlider3(@"强度",@"darkEdge26Opacity",@"dockDarkEdge26Opacity",@"bubbleDarkEdge26Opacity",0,1,nil),
                                 WXGSlider3(@"亮度增益",@"darkEdge26Gain",@"dockDarkEdge26Gain",@"bubbleDarkEdge26Gain",0,4,@"%.3f"),
                                 WXGSlider3(@"色彩增益",@"darkEdge26Chroma",@"dockDarkEdge26Chroma",@"bubbleDarkEdge26Chroma",0,8,@"%.3f"),
                                 WXGSlider3(@"提亮",@"darkEdge26Lift",@"dockDarkEdge26Lift",@"bubbleDarkEdge26Lift",0,1,@"%.3f"),
                                 WXGSlider3(@"环绕微光",@"darkEdge26Ring",@"dockDarkEdge26Ring",@"bubbleDarkEdge26Ring",0,1,@"%.2f")],
                 nil),@[@3]),
        WXGStyled(WXGGroup(@"iOS 27 · 浅色模式 · 高光一",nil,@[WXGColor3(@"颜色",@"rim27Hex",@"dockRim27Hex",@"bubbleRim27Hex"),
                                 WXGSlider3(@"不透明度",@"rim27Opacity",@"dockRim27Opacity",@"bubbleRim27Opacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"rim27Width",@"dockRim27Width",@"bubbleRim27Width",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"rim27Falloff",@"dockRim27Falloff",@"bubbleRim27Falloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"rim27Angle",@"dockRim27Angle",@"bubbleRim27Angle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"rim27EndLevel",@"dockRim27EndLevel",@"bubbleRim27EndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"rim27Sharpness",@"dockRim27Sharpness",@"bubbleRim27Sharpness",0.5,6,nil)],
                 @"iOS 27 双高光渐隐边框，浅色模式与深色模式各两道，支持在底栏、分组栏、视频号与透镜上独立调节。"),@[@2]),
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
                 nil),@[@2]),
        WXGStyled(WXGGroup(@"iOS 27 · 深色模式 · 高光二",nil,@[WXGColor3(@"颜色",@"darkRim27DarkModeHex",@"dockDarkRim27DarkModeHex",@"bubbleDarkRim27DarkModeHex"),
                                 WXGSlider3(@"不透明度",@"darkRim27DarkModeOpacity",@"dockDarkRim27DarkModeOpacity",@"bubbleDarkRim27DarkModeOpacity",0,1,nil),
                                 WXGSlider3(@"渐隐宽度",@"darkRim27DarkModeWidth",@"dockDarkRim27DarkModeWidth",@"bubbleDarkRim27DarkModeWidth",.3,8,@"%.1f pt"),
                                 WXGSlider3(@"向内渐隐曲线",@"darkRim27DarkModeFalloff",@"dockDarkRim27DarkModeFalloff",@"bubbleDarkRim27DarkModeFalloff",.5,4,nil),
                                 WXGSlider3(@"高光方向",@"darkRim27DarkModeAngle",@"dockDarkRim27DarkModeAngle",@"bubbleDarkRim27DarkModeAngle",0,180,@"%.0f°"),
                                 WXGSlider3(@"最暗处亮度",@"darkRim27DarkModeEndLevel",@"dockDarkRim27DarkModeEndLevel",@"bubbleDarkRim27DarkModeEndLevel",0,1,nil),
                                 WXGSlider3(@"过渡速度",@"darkRim27DarkModeSharpness",@"dockDarkRim27DarkModeSharpness",@"bubbleDarkRim27DarkModeSharpness",0.5,6,nil)],
                 nil),@[@2]),
        WXGCopyGroup(),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 @"这一页的全部设置（每个范围、浅色和深色）回到默认值；其它页不变。")]};
    if([module isEqual:@"chat"])return @{@"title":@"聊天页",@"groups":@[
        WXGGroup(@"输入栏",nil,@[WXGSwitch(@"聊天悬浮输入栏",@"pref.input",nil),
                 WXGSwitch(@"原生宽度三端输入（测试）",@"pref.nativeInputTest",nil),
                 WXGSwitch(@"双端输入栏用系统图标",@"splitInputSystemSymbols",nil),
                 WXGAction(@"自定义双端输入栏图标",@"open:splitSymbols",NO),
                 WXGSlider(@"输入框高度",@"inputPillHeight",nil,34,54,@"%.1f pt"),
                 WXGSlider(@"左侧加号大小（0 = 和输入框一样高）",@"inputPlusSize",nil,0,54,@"%.1f pt"),
                 WXGSlider(@"离屏幕两边",@"inputSideMargin",nil,8,60,@"%.1f pt"),
                 WXGSlider(@"加号和输入框的间距",@"inputPlusGap",nil,4,24,@"%.1f pt")],
                 @"聊天悬浮输入栏：默认是双端输入栏；“原生宽度三端输入（测试）”开启后保留原生输入宽度和动作，单行三段等高，多行只增高中间。双端输入栏用系统图标可逐项设置 SF Symbols，关闭后使用微信原图。尺寸四项只管双端输入栏：输入框高度；左侧加号大小（0 = 和输入框一样高）；离屏幕两边的距离；加号和输入框的间距。"),
        WXGGroup(@"标题与头像",nil,@[WXGSwitch(@"聊天标题使用头像 + 小胶囊",@"pref.avatarTitle",nil),
                 WXGSwitch(@"不用头像标题时，聊天页顶部保持微信原生",@"chatNativeBar",nil),
                 WXGSwitch(@"聊天右上角按钮显示头像",@"pref.chatAvatarButton",nil),
                 WXGSlider(@"头像按钮内边距",@"chatAvatarInset",nil,0,12,@"%.1f pt")],
                 @"聊天标题使用头像 + 小胶囊：仿 iOS 26 信息 App，头像在上、名字胶囊在下。不用头像标题时，聊天页顶部可以保持微信原生的返回按钮、右上角按钮和标题（后面各垫一块玻璃胶囊）。聊天右上角按钮显示头像：还是原来那个按钮，玻璃里画对方的头像；内边距是头像离玻璃边缘的距离。"),
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
        WXGGroup(@"液态气泡",nil,@[WXGSwitch(@"液态气泡",@"pref.bubbles",nil),
                 WXGSwitch(@"气泡用完整玻璃",@"bubbleFullGlass",nil),
                 WXGSwitch(@"气泡共用一次背景采样（省 GPU）",@"bubbleSharedBackdrop",nil)],
                 @"文字、语音和支持的消息卡片使用玻璃背景。气泡用完整玻璃：关着时气泡只有颜色和边框（省电）；打开后每个气泡都有折射和模糊，折射、模糊、材质、边框在“效果调整”的“气泡”范围里调。气泡共用一次背景采样：一屏的气泡共用同一份背景，省 GPU。"),
        WXGGroup(@"引用消息",nil,@[WXGSwitch(@"隐藏引用原生背景",@"bubbleQuoteHideNativeBackground",nil),
                 WXGSwitch(@"显示引用分割线",@"bubbleQuoteDivider",nil)],
                 @"开启液态气泡后生效。分割线显示在正文和引用内容之间。"),
        WXGGroup(@"气泡颜色",nil,@[WXGColorRow(@"自己的气泡",@"bubbleOutgoingHex",nil),
                 WXGColorRow(@"对方的气泡",@"bubbleIncomingHex",nil),
                 WXGColorRow(@"自己的气泡",@"darkBubbleOutgoingHex",nil),
                 WXGColorRow(@"对方的气泡",@"darkBubbleIncomingHex",nil)],
                 @"自己的和对方的气泡颜色，浅色、深色各一组，可以带透明度。"),
        WXGGroup(@"消息长按菜单",nil,@[WXGSlider(@"菜单圆角",@"messageMenuCornerRadius",nil,0,40,@"%.0f pt")],
                 @"长按消息弹出菜单的玻璃圆角。若微信的菜单容器本身裁剪了更小的圆角，以较小者为准。"),
        WXGGroup(@"面板与弹层",nil,@[WXGSwitch(@"加号面板的方块",@"pref.localPanel",nil),
                 WXGSwitch(@"表情面板的发送、删除和分组选中",@"pref.localEmoji",nil),
                 WXGSwitch(@"转发 / 分享弹层的背景",@"pref.localSheet",nil),
                 WXGSlider(@"加号方块圆角",@"localTileRadius",nil,0,32,@"%.1f pt"),
                 WXGSlider(@"表情分组选中圆角",@"localTabRadius",nil,0,22,@"%.1f pt")],
                 @"加号面板的方块、表情面板的发送 / 删除和分组选中、转发 / 分享弹层的背景换成玻璃；两个圆角是加号方块和表情分组选中的。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 nil)]};
    if([module isEqual:@"home"])return @{@"title":@"首页",@"groups":@[
        WXGGroup(@"首页标题分组栏",nil,@[
                 WXGSwitch(@"首页标题拓展为分组栏（全部 / 未读）",@"homeTitleSegments",nil),
                 WXGSwitch(@"标题分组显示英文（All / Unread）",@"homeTitleSegmentsEnglish",nil)],
                 @"直接按现有首页标题大小拓展为分组栏（默认 全部 / 未读，支持英文 All / Unread），复用与底栏等比同步的选中胶囊与按压透镜，点击即可筛选聊天列表。"),
        WXGGroup(@"分组栏与搜索框尺寸",nil,@[
                 WXGSwitch(@"显示列表分组栏",@"chatSegments",nil),
                 WXGChoice3(@"分组形式",@"homeGroupForm",nil,nil,@[@"自定义分组",@"分类分页"],YES),
                 WXGChoice3(@"显示方式",@"homeGroupCoexists",nil,nil,@[@"替换搜索框",@"搜索与分组共存"],YES),
                 WXGSwitch(@"仅在首页悬浮",@"searchFloat",nil),
                 WXGSlider(@"搜索框宽度（0 = 原生）",@"homeSearchWidthPct",nil,0,98,@"%.0f%%"),
                 WXGSlider(@"搜索框高度（0 = 原生）",@"homeSearchHeight",nil,0,64,@"%.1f pt"),
                 WXGSlider(@"与顶部标题的距离（-1 = 原生）",@"homeSearchTopGap",nil,-1,32,@"%.1f pt"),
                 WXGSlider(@"分组栏宽度（0 = 原生）",@"homeGroupWidthPct",nil,0,98,@"%.0f%%"),
                 WXGSlider(@"分组栏高度（0 = 原生）",@"homeGroupHeight",nil,0,64,@"%.1f pt"),
                 WXGSlider(@"搜索框与分组栏间距",@"homeSearchGroupGap",nil,0,32,@"%.1f pt")],
                 @"两行共存时，搜索在上，分组在下。替换搜索框时，分组单独占一行。两种方式都保留列表原有的底部留白。"),
        WXGGroup(@"首页滚动诊断",nil,@[WXGSwitch(@"记录首页逐帧轨迹",@"homeMotionTrace",nil)],
                 @"记录列表偏移、顶部各行位置和分组透镜进度。导出诊断会包含最近 14400 帧，可用于排查回弹和返回位置。"),
        WXGHomeFormGroup(YES,@"分类分页",@[WXGChoice3(@"滑动模式",@"homeGroupPaging",nil,nil,@[@"淡入",@"分页"],NO)],
                 @"置顶、私聊、群聊、服务、企业按会话类型筛选。点标签或在消息列表中左右滑动切组，屏幕右边缘保留给会话操作。"),
        WXGHomeFormGroup(NO,@"分组列表",@[WXGAction(@"管理分组（新建 / 改名 / 选聊天 / 排序）",@"manageGroups",NO)],
                 @"分组是你自己的：最多 6 个，每个可以是 全部 / 未读 / 单聊 / 群聊，或者“自定义”——自己选里面有哪些聊天。分组栏上从左到右就是这里的顺序。"),
        WXGGroup(@"选中胶囊",nil,@[WXGSlider(@"内边距",@"segmentSelectionInset",nil,2,14,@"%.1f pt"),WXGSwitch(@"用页面的背景色",@"segmentPillAuto",nil),
                                 WXGColorRow(@"浅色模式颜色",@"segmentPillHex",nil),WXGSlider(@"浅色模式不透明度",@"segmentPillOpacity",nil,0,1,nil),
                                 WXGColorRow(@"深色模式颜色",@"segmentDarkPillHex",nil),WXGSlider(@"深色模式不透明度",@"segmentDarkPillOpacity",nil,0,1,nil),
                                 WXGSlider(@"按住时不透明度",@"segmentPillPressedOpacity",nil,0,1,nil)],
                 @"开启 R8 透镜引擎时直接同步底栏的选中胶囊；关闭后可在这里单独调整传统选中胶囊颜色。"),
        WXGGroup(@"选中胶囊边框",nil,@[WXGSlider(@"静止时也显示",@"segmentPillRimAtRest",nil,0,1,nil)],
                 @"选中胶囊（按住时就是透镜）自己的一圈边框，可在「效果调整 → 分组透镜的边框」里单独调节。"),
        WXGGroup(@"文字",nil,@[WXGSlider(@"字号",@"segmentTitleSize",nil,10,18,@"%.1f pt"),WXGSlider(@"字重（细 → 粗）",@"segmentTitleWeight",nil,0,4,@"%.0f"),
                             WXGColorRow(@"浅色模式颜色",@"segmentInkHex",nil),WXGColorRow(@"深色模式颜色",@"segmentDarkInkHex",nil),
                             WXGSwitch(@"选中的用强调色",@"segmentAccentOn",nil),WXGColorRow(@"强调色",@"segmentAccentHex",nil)],
                 @"和底栏一样：没选中的是深灰（深色模式浅灰），选中的那一段用强调色，字重自动加一级。"),
        WXGGroup(@"首页加号菜单",nil,@[WXGBare(WXGChoiceValues(
                 WXGChoice3(@"样式",@"homeMenuCapsules",nil,nil,@[@"融展玻璃",@"胶囊展开"],YES),
                 @[@(WXGHomeMenuStyleMorph),@(WXGHomeMenuStyleCapsules)]))],nil),
        WXGHomeMenuGroup(@"融展玻璃",WXGHomeMenuStyleMorph,@[
                 WXGSlider(@"融展菜单宽度",@"homeMenuMorphWidth",nil,160,320,@"%.0f pt"),
                 WXGSlider(@"融展菜单外圆角增量",@"homeMenuMorphCornerExtra",nil,0,12,@"%.1f pt")],
                 @"外圆角增量为 0 时，菜单与选中胶囊的圆角等距。"),
        WXGHomeMenuGroup(@"胶囊展开",WXGHomeMenuStyleCapsules,@[
                 WXGSlider(@"胶囊图标大小",@"homeMenuIconSize",nil,34,56,@"%.0f pt"),
                 WXGSlider(@"胶囊展开间隔",@"homeMenuStagger",nil,0,80,@"%.0f ms")],
                 @"展开时，圆点从加号飞向菜单图标。"),
        WXGGroup(@"搜索框",nil,@[WXGSwitch(@"搜索框换成玻璃胶囊",@"pref.localSearch",nil),
                 WXGSwitch(@"搜索框让主题优先",@"pref.localSearchThemeFirst",nil),
                 WXGSwitch(@"隐藏聊天列表顶部搜索栏",@"pref.hideTopSearch",nil)],
                 @"搜索框换成玻璃胶囊；“搜索框让主题优先”打开后图标和文字交给微信或主题。隐藏聊天列表顶部搜索栏只在开启底栏搜索按钮时生效。"),
        WXGGroup(@"朋友圈",nil,@[WXGSwitch(@"朋友圈新消息横幅和 ·· 按钮",@"localMoments",nil)],
                 nil),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 @"分组栏的色彩材质、阴影与边框在「效果调整 → 分组栏」里，按压透镜与形变在「底栏透镜与形变」里。")]};
    if([module isEqual:@"me"])return @{@"title":@"个人页",@"groups":@[
        WXGGroup(@"“我”页头部",nil,@[WXGSwitch(@"Telegram 式头部（头像收进灵动岛）",@"meHeader",nil),
                                 WXGSwitch(@"下拉展开横幅（替换微信的下拉状态）",@"meBanner",nil),
                                 WXGAction(@"横幅媒体库",@"meBannerLibrary",NO),
                                 WXGSlider(@"头像大小",@"meAvatarSize",nil,70,130,@"%.0f pt"),
                                 WXGSwitch(@"刘海屏：头像融进刘海",@"meNotchMerge",nil),
                                 WXGSlider(@"灵动岛 / 刘海位置微调（上下）",@"meCutoutY",nil,-8,8,@"%.1f pt"),
                                 WXGSlider(@"灵动岛 / 刘海宽度微调",@"meCutoutW",nil,-30,30,@"%.0f pt")],
                 @"轻点头像可打开个人资料。向上滑动时，头像收向灵动岛或刘海，昵称移到导航栏。启用横幅后，下拉约 100 pt 松手即可展开，上推收回。横幅下缘渐隐，背景可在媒体库选择头像、图片或静音循环视频。状态入口在头像下方。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 nil)]};
    if([module isEqual:@"dock"])return @{@"title":@"底栏",@"groups":@[
        WXGGroup(@"开关",nil,@[WXGSwitch(@"真实悬浮标签栏",@"pref.dock",nil)],
                 @"用插件的悬浮底栏替换微信的标签栏。"),
        WXGGroup(@"尺寸",nil,@[WXGSlider(@"底栏宽度比例",@"widthFraction",nil,.65,.98,nil),WXGSlider(@"底栏高度",@"height",nil,54,90,@"%.1f pt"),
                             WXGSlider(@"底边相对安全区",@"lift",nil,-80,160,@"%.1f pt")],@"lift"),
        WXGGroup(@"iOS 26 系统底栏",nil,@[WXGAction(@"套用 iOS 26 实测数值",@"dockSystem26",NO),WXGAction(@"还原套用前的数值",@"dockSystem26Restore",NO),
                             WXGSlider(@"每格加宽（相邻两格重叠）",@"dockCellExtra",nil,0,20,@"%.1f pt"),
                             WXGSlider(@"按压时透镜加宽",@"dockLensLiftWidth",nil,0,40,@"%.1f pt"),
                             WXGSlider(@"松手后透镜停留",@"dockLensHang",nil,0,.5,@"%.2f s"),
                             WXGSwitch(@"切换时用系统的位置弹簧",@"dockMoveSpring",nil),
                             WXGSlider(@"位置弹簧：响应",@"dockMoveResponse",nil,.2,.8,@"%.2f s"),WXGSlider(@"位置弹簧：阻尼比",@"dockMoveDamping",nil,.5,1.2,@"%.2f")],
                 @"把 iOS 26.6 真机底栏上量出来的尺寸与节奏套用到当前底栏；透镜折射与色散统一在「底栏透镜与形变」中调节。"),
        WXGGroup(@"离散样式",nil,@[WXGSwitch(@"离散底栏",@"dockDiscrete",nil),
                                 WXGSwitch(@"未选中的小球连成一体",@"dockDiscreteConnected",nil),
                                 WXGSlider(@"相连时图标向中间收拢",@"dockDiscreteGather",nil,0,.45,@"%.2f"),
                                 WXGSwitch(@"选中项加原选中胶囊",@"dockDiscretePill",nil),
                                 WXGSlider(@"间距",@"dockDiscreteGap",nil,0,24,@"%.1f pt"),
                                 WXGSlider(@"选中项占位",@"dockDiscreteWide",nil,1,3,@"%.2f 格"),
                                 WXGSlider(@"小球直径（相对底栏高度）",@"dockDiscreteBall",nil,.6,1.3,@"%.2f"),
                                 WXGSlider(@"宽位内容左移",@"dockDiscreteContentShift",nil,0,30,@"%.1f pt"),
                                 WXGSlider(@"弹簧阻尼",@"dockDiscreteDamping",nil,.45,1,@"%.2f"),
                                 WXGSlider(@"弹簧响应",@"dockDiscreteResponse",nil,.2,1,@"%.2f s"),
                                 WXGSwitch(@"各块用轻量玻璃",@"dockDiscreteLight",nil)],
                 @"离散底栏：选中的标签是一块宽胶囊（左边图标，右边上中文、下英文），其余标签各是一个只有图标的小球，每块都是独立的底栏玻璃（材质、折射和边框都用“底栏”范围的设置）。切换时所有标签的宽度一起走同一个阻尼弹簧：旧的收成小球、新的展开，整行总宽不变、不会左右漂；回弹时新的会略微超宽、旧的略微被挤窄。未选中的小球连成一体：相邻两个小球之间的间距被玻璃填上，连成一整块（位置不变，只是间隙连上）；切换一开始，旧选中项就一边收窄一边并入两旁，新选中项一边展开一边分出来，约在弹簧响应的 0.35 倍时连成一块（默认约 0.16 s），不等动画结束。相连时图标向中间收拢：连成一块的小球，图标按这个比例往这一块的中间靠（0 = 停在各自小球的中心；默认 0.22，图标间距缩到 0.78 格，两连和三连间距一样），两端圆头处留出更多空间，跟着弹簧滑过去，角标跟着图标走。离散样式的图标和中英文标题也跟随“图标与标题整体缩放”，粗细跟随那里的“文字粗细”；文字放不下时自动缩小。宽位内容左移：宽胶囊里图标和标题整体居中后再往左挪这么多（0 = 正中，默认 10 pt），最多挪到图标落在左端圆头正中为止，小球时不偏。未读角标在每块胶囊的右上角，跟着胶囊宽窄移动。选中项加原选中胶囊：在宽胶囊里加上原来底栏的选中胶囊（透镜、底色和边框，颜色和内边距用下面“选中胶囊”的设置），切换时它从中心长出来、在旧的那块里缩没。间距：块与块之间。选中项占位：选中项占几格（2 格 = 两个小球加中间的间距那么宽；1 格时只放大图标不显示文字）。小球直径：相对底栏高度。整行放不下时（FIX113 E）先把选中项收窄（最少 1.6 格），再把间距缩小（最少一半），最后才缩小小球；有搜索按钮时，整行先加宽到能放下这个高度的小球（最宽到搜索框展开时那一行的宽度）。弹簧阻尼越小回弹越明显（0.6 约等于参考效果，1 不回弹）；弹簧响应越小越快。有搜索按钮时整行靠向搜索按钮那一边。打开搜索时变回连续底栏完成变形（两者交叉淡化）；关闭时，底栏快变回原样时就交叉淡回离散样式（FIX113 D），不会先停在完整的连续底栏上。各块用轻量玻璃：每块只用一层背景、不分色散通道，省电但少了色散和边缘环。"),
        WXGGroup(@"搜索",nil,@[WXGSwitch(@"底栏搜索按钮",@"pref.dockSearch",nil),
                 WXGSwitch(@"搜索按钮放在左边",@"pref.dockSearchLeading",nil),
                 WXGSlider(@"两块玻璃的间距",@"dockSearchGap",nil,2,40,@"%.1f pt")],
                 @"平时底栏宽度比例是整行：标签栏、间距和圆形搜索按钮。点搜索按钮直接打开微信自己的搜索页。需要系统渲染（同步）模式。"),
        WXGGroup(@"选中胶囊",nil,@[WXGColorRow(@"浅色模式底色",@"selectionHex",nil),WXGColorRow(@"深色模式底色",@"darkSelectionHex",nil),
                                 WXGSlider(@"静置底色不透明度",@"selectionOpacity",nil,0,.75,nil),WXGSlider(@"静置内边距",@"selectionInset",nil,2,14,@"%.1f pt")],nil),
        WXGGroup(@"图标与文字",nil,@[WXGSlider(@"图标与标题整体缩放",@"dockIconScalePercent",nil,60,140,@"%.0f%%"),
                                   WXGSwitch(@"隐藏底栏标题",@"dockHideTitles",nil),
                                   WXGChoice3(@"文字粗细",@"dockTitleWeight",nil,nil,@[@"细",@"常规",@"中等",@"半粗",@"粗"],NO),
                                   WXGSwitch(@"选中的文字加粗一档",@"dockTitleBolderSelected",nil)],
                 @"显示标题时，连续底栏采用 iOS 26 实测的图标与文字位置。100% 为实测尺寸，图标、标题和两者的间距一起围绕中线缩放，选中态和透镜采用相同布局。隐藏标题后图标在底栏内垂直居中，离散底栏也会隐藏中英文标题。"),
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
                 @"底栏主题优先（FIX115 D，默认关）：底栏的图标和标题颜色完全交给微信或别的插件的主题——用微信底栏里正在显示的那张图（主题的 PNG 也一样），按它在微信底栏里显示的大小画（不再按图片自己的尺寸、也不再限制在 30 pt 以内；同一个主题的 PNG 用不同倍数加载时尺寸不一样，以前就会忽大忽小），未选中 / 选中的文字颜色用微信 / 主题自己的；Telegram 图标和“选中强调色”不再用于底栏。图标缩放、隐藏标题和文字样式仍在“图标与文字”里设置。诊断的底栏图标那一行会写每个标签的图片尺寸、倍数和显示大小。Telegram 图标（FIX113）：微信、通讯录、发现、我依次换成 Telegram 的聊天、联系人、通话、设置图标（Telegram for iOS 开源仓库里的原动画，GPLv2），平时是静止的样子，切到哪个标签就播放它自己的那段动画（约 0.6–0.75 秒，按 Telegram 的 60 帧），透镜里外、离散底栏都一样；拖动经过别的标签不播，松手落定才播；系统“减弱动态效果”打开时不播。开着时优先于“使用微信原生图标”。选中强调色（FIX113 C）：选中标签的图标和文字颜色，系统图标和 Telegram 图标都用它（默认是原来的绿色），Telegram 图标播放动画时也是这个颜色；使用微信原生图标时仍是微信自己的颜色。FIX115 I：强调色在底栏里总是按 100% 不透明画（颜色的不透明度不用）；开着 Telegram 图标时存着的强调色也自动改成 100%。点按切换（FIX95 / FIX98 / FIX99）：点别的标签时，呼出的就是拖动时那块完整的透镜（折射、色散、透镜里的底栏和图标都一样），自己滑过去再落成胶囊；按住不放，到位后就跟着手指，可以继续左右拖。胶囊变透镜：滑动开始后，在滑动时长的这个比例内升起成透镜、颜色褪成透明（默认 0.40，FIX98 是颜色 0.65、升起 0.55）。落下时长：从透镜落回胶囊、颜色回来用的时间，默认 0.16 s（FIX98 0.26 s），在到位前 70% 就开始落，到位后约 0.05 s 落完，所以颜色的变化都在滑动里完成，不会到位以后还慢慢变。点按滑动时长：1 倍是 FIX43 的 0.28 s ×（0.85 + 0.05 × 标签数），默认 1.4 倍（一个标签约 0.35 s，点一下一共约 0.4 s）。FIX98 时调过这两项的，值会带过来；没调过的用新的默认值。切换页面的时机适用于冷启动首次打开和后续访问。选“按下时”（默认）会在按下标签时切到新页；选“松手时”会在松手时切换；选“快到位时”会在透镜滑完约 80% 时切换；选“落下后”会等透镜落定。开启“按下时：会卡的标签等透镜落下再切”后，如果该标签上次切换后 0.7 秒内累计卡顿达到 50 ms，点它时会等透镜落下再切。按下就已切换时，滑到另一个标签松手会切到最后那个标签，滑出底栏则停留在按下时选中的页。切换后等页面忙完再滑（FIX101，FIX102 起默认关闭）：打开后透镜在微信切完页面后原地等到连续三帧准时（最多 0.6 s）再滑，滑动更不容易被打断，但每次都会晚 0.07–0.2 s 开始。停顿后加速追上（FIX102，默认打开）：透镜因为微信切页面停住多久，剩下的动画就快那么久的六成（最多快四分之一），落下的时间尽量和没停时一样。拖动时胶囊颜色也按升起的程度渐变（按压 0.05–0.45）。打开“点按时用简化透镜”恢复 FIX33–FIX94 的做法：动画交给系统渲染服务，页面立刻切换，但滑动的只是一个形状，没有透镜的效果（上面几项不影响它）。"),
        WXGGroup(@"拖过两端",nil,@[WXGSwitch(@"拖过两端时拉长底栏",@"dockEndStretch",nil),
                 WXGSlider(@"两端拉长距离",@"dockEndStretchDistance",nil,0,40,@"%.0f pt")],
                 @"透镜到了第一个或最后一个标签还继续往外拉，那一端的底栏跟着手指被拉出去，松手弹回。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复本页默认",@"resetPage",YES)],
                 @"底栏的折射、模糊、材质、边框和透镜在“效果调整”的“底栏”范围里。")]};
    if([module isEqual:@"fade"])return @{@"title":@"渐进式模糊",@"groups":@[
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
    if([module isEqual:@"general"])return @{@"title":@"通用",@"groups":@[
        WXGGroup(@"玻璃外观",nil,@[WXGSwitch(@"全局玻璃阴影",@"glassShadowOn",nil)],
                 @"控制所有范围的玻璃外阴影。重新开启后，各范围沿用原有的阴影参数。"),
        WXGGroup(@"顶部按钮",nil,@[WXGSwitch(@"顶部按钮与背景适配",@"pref.nav",nil),
                 WXGSwitch(@"标题换成玻璃胶囊",@"pref.localTitle",nil),
                 WXGSwitch(@"通讯录标题覆盖胶囊",@"contactsTitleCapsule",nil),
                 WXGSwitch(@"发现标题覆盖胶囊",@"discoverTitleCapsule",nil),
                 WXGSwitch(@"网页、弹出页面的顶部按钮",@"pref.localNavButtons",nil),
                 WXGSwitch(@"带颜色的按钮（如绿色“完成”）",@"localColorButtons",nil),
                 WXGSwitch(@"其它页面顶部按钮也保持微信原生",@"navNativeButtons",nil),
                 WXGSwitch(@"原生按钮放进插件自己的玻璃按钮（稳定）",@"navNativeLook",nil),
                 WXGSlider(@"截图比例微调",@"pref.sizeScale",nil,.85,1.20,@"%.2f"),
                 WXGSlider(@"顶部按钮离屏幕两边",@"navEdge",nil,8,36,@"%.1f pt"),
                 WXGSlider(@"视频号顶部按钮离屏幕两边",@"finderEdge",nil,0,30,@"%.1f pt"),
                 WXGSlider(@"顶部按钮往下移",@"navOffsetY",nil,0,16,@"%.1f pt")],
                 @"顶部按钮与背景适配：各页面顶部的按钮换成玻璃按钮。标题换成玻璃胶囊、网页和弹出页面的顶部按钮、带颜色的按钮（如绿色“完成”）各有开关。其它页面顶部按钮也保持微信原生：按钮是微信自己的图标、文字和位置，后面垫胶囊；“原生按钮放进插件自己的玻璃按钮”更稳定。截图比例微调同时作用于顶部按钮的大小；离屏幕两边、往下移是整排的位置，视频号单独一项。"),
        WXGGroup(@"交互",nil,@[WXGSwitch(@"触感反馈",@"haptics",nil),WXGSwitch(@"按住拖动拉伸玻璃按钮",@"pressStretch",nil),WXGSwitch(@"首页左上角和三段输入两侧也拉伸",@"pressStretchNative",nil),
                             WXGSlider(@"最大拉动距离",@"pressStretchDistance",nil,0,32,@"%.0f pt"),WXGSlider(@"拉伸强度",@"pressStretchAmount",nil,0,1.5,@"%.2f"),
                             WXGSlider(@"最大拉伸幅度",@"pressStretchMax",nil,1,20,@"%.1f pt"),WXGSlider(@"胶囊拉伸程度",@"pressStretchCapsule",nil,0,1,@"%.2f"),
                             WXGSlider(@"跟手移动",@"pressStretchFollow",nil,0,1,@"%.2f"),
                             WXGSlider(@"拖动与变形的比例（拖几 pt 算 1 pt）",@"pressStretchRatio",nil,1,12,@"%.1f")],
                 @"按住导航按钮、标题、输入栏两侧的按钮、首页左上角按钮或底栏搜索按钮再拖动：玻璃朝手指方向拉长、另一个方向变窄（远离手指的一侧几乎不动，靠近手指的一侧伸出去），整体再跟着手指移动一点。拉动距离越拉越难，最多按“最大拉动距离”算（按 44 pt 的按钮算，小一点和大一点的按钮按比例）；拉伸强度是每拉 1 pt 拉长多少 pt（变窄是一半）；最大拉伸幅度是最多拉长多少 pt，越接近越拉不动；跟手移动是玻璃跟着手指移动拉动距离的多少（0 就是原地不动，1 是完全跟手），移动和拉伸来自同一个拉动距离，拉得越远两者都越大。胶囊、圆角矩形这类不是圆的玻璃只沿上下、左右拉伸，不会斜着变形，程度是圆形按钮的“胶囊拉伸程度”倍。手指按住期间一直拉着，松手才用弹簧弹回（会过冲一下）；在按钮 40 pt 以内松手是点击，更远就是放弃点击。首页左上角按钮和三段输入两侧的触摸仍由微信处理，上面微信自己的图标也跟着玻璃一起变形（只是画面跟着变，点击位置不受影响）。输入文字的那块胶囊（两种输入栏都是）固定不动：点按、拖动都不放大、不拉伸，点它里面的按钮只有按钮图标自己有按下效果。系统“减弱动态效果”打开时不拉伸。拖动与变形的比例（FIX115 L；默认 3，1–12）：手指在屏幕上拖多少 pt 才算拉动 1 pt，上面的拉动距离、拉伸、跟手移动都按折算后的拉动来算——3 就是拖 3 pt 玻璃才“被拉”1 pt；往左更灵敏，1 就是以前的样子；往右越来越难拉动，8 就很不容易被拉变形。N 版存下的 8（不管是 N 的默认、自动改的还是手调的）装上 O 后回到 3 一次，之后再调的值不会被改。关掉“按住拖动拉伸玻璃按钮”就完全没有拉伸，回到原来按下微微放大的效果；只关“首页左上角和三段输入两侧也拉伸”时，这几处只保留按下效果，其余按钮照常拉伸。"),
        WXGGroup(@"性能与清晰度",nil,@[WXGSwitch(@"流畅模式",@"performanceMode",nil),
                 WXGSwitch(@"RGB 色散",@"syncDispersion",nil),
                 WXGSlider(@"模糊倍率",@"syncBlurScale",nil,.5,3,nil),
                 WXGSlider(@"采样倍率",@"syncCaptureScale",nil,0,3,nil),
                 WXGSlider(@"取色分辨率（各范围共用）",@"edge26CaptureScale",nil,.1,1,@"%.2f 倍")],
                 @"流畅模式：每块玻璃只用一层背景（没有红绿蓝三层），采样最多 2 倍。RGB 色散：用红绿蓝三层背景实现色散，若玻璃整体偏色可关闭。模糊倍率：所有模糊半径再乘这个数。采样倍率：0 = 屏幕倍数。iOS 26 边框的取色分辨率：边框颜色取自玻璃底下内容的一份低分辨率拷贝，越低越省。")]};
    if([module isEqual:@"settingsPage"])return @{@"title":@"设置页调整",@"groups":@[
        WXGGroup(@"设置页壁纸",nil,@[WXGWallpaperRow(@"浅色模式",NO),WXGWallpaperRow(@"深色模式",YES)],
                 @"只用于这几页设置，给玻璃卡片做背景；没有导入时用下面的纯色。"),
        WXGGroup(@"无壁纸时的背景色",nil,@[WXGColorRow(@"浅色模式",@"settingsBackgroundHex",nil),WXGColorRow(@"深色模式",@"settingsDarkBackgroundHex",nil)],
                 @"FIX113 O：没有导入壁纸时，这几页设置的背景是纯色（默认浅色模式浅灰、深色模式深灰），不再是原来的彩色渐变。卡片和按钮的玻璃参数在折射、模糊、材质、边框几页的“设置页”范围里。"),
        WXGGroup(@"卡片",nil,@[WXGSlider(@"卡片圆角",@"ui.cardRadius",nil,0,40,@"%.0f pt")],@"所有卡片都是连续圆角，不超过卡片高度的一半。"),
        WXGGroup(@"强调色",nil,@[WXGColorRow(@"字体与图标",@"ui.accentHex",nil),WXGAction(@"恢复跟随系统",@"accentReset",NO)],
                 @"也可以点设置首页右上角的调色板按钮修改。"),
        WXGGroup(@"参数共享",nil,@[WXGAction(@"复制当前参数",@"shareCopy",NO),WXGAction(@"导出参数文件",@"shareExport",NO),
                                 WXGAction(@"从剪贴板导入参数",@"shareImportClipboard",NO),WXGAction(@"从文件导入参数",@"shareImportFile",NO)],
                 @"包括全部玻璃参数（折射、模糊、材质、边框、底栏、渐隐与模糊、拉伸等）、基本设置和底栏里的开关、设置页的卡片圆角和强调色；总开关、授权、壁纸和头像不在里面。复制得到一段文字，可以直接用微信发给别人，对方复制后点“从剪贴板导入参数”。导入也认诊断 JSON（新版里的完整参数；旧版只有玻璃参数）。想把一套参数做成安装后的默认值，导出参数文件发给作者。"),
        WXGGroup(@"帧率检测",nil,@[WXGSwitch(@"记录帧率",@"pref.perfMonitor",nil),WXGSwitch(@"显示帧率浮标",@"pref.perfHUD",nil)],
                 @"打开后每一帧都记下来：每秒的帧率、掉帧、最长一帧、当时的页面、是否在滑动、本插件占用的主线程时间、温度状态和内存。按页面分“滑动 / 静止”统计，一帧超过 50 ms 的卡顿单独列出。插件总开关关闭时也照样记录，可以开关插件各测一段对比。浮标可以拖动，绿色是满帧、橙色掉一些、红色明显掉帧。记录本身每帧只做几次加法；在高刷屏上开着时屏幕会保持最高刷新率。最近 20 分钟的逐秒记录会每 15 秒存一次，微信被杀掉后下次导出里还有上一次的记录。"),
        WXGGroup(@"帧率日志",nil,@[WXGAction(@"查看帧率报告",@"perfReport",NO),WXGAction(@"查看页面切换报告",@"perfSwitches",NO),WXGAction(@"导出帧率日志 JSON",@"perfExport",NO),WXGAction(@"清空本次记录",@"perfClear",YES)],
                 @"报告里有总体和各页面的平均帧率、掉帧比例、卡顿（每秒多等的毫秒数）、p95 帧时间、最长一帧和插件耗时，以及最近的卡顿。导出的 JSON 里还有逐秒记录和上一次运行的记录，发给作者即可。页面切换报告（FIX113 Z）：每次进出页面（push / pop、弹出 / 收起、切标签）从发起到动画结束后 0.3 s：首帧要多久、掉了几帧、最长一帧，以及这段时间主线程花在哪里——插件（分刷新、每帧玻璃、各个挂钩、渐隐、气泡等）、Core Animation 提交、微信自己。插件开着就一直记（只在切换那一会儿跑自己的计时器），插件关着时打开“记录帧率”也记，可以对比；最近 40 次也在导出的帧率 JSON 和诊断里。"),
        WXGGroup(@"诊断",nil,@[WXGAction(@"材质、位置与性能诊断",@"diagnostics",NO),WXGAction(@"导出各页诊断 JSON",@"export",NO),
                             WXGSwitch(@"任意页面导出诊断（浮动按钮）",@"diagnosticsFloat",nil),
                             WXGSwitch(@"悬浮按钮打开 / 收起设置（调参对比）",@"settingsFloat",nil)],
                 @"FIX114 R：打开后每个页面左边都有一个小的“导出诊断”按钮（可以拖到别处），在哪一页点它，导出的就是那一页当时的诊断（比如聊天页），不用再进设置。FIX115 G：“悬浮按钮打开 / 收起设置”打开后每个页面右边有一个小的“设置”按钮（也能拖），点一下设置页直接盖在当前页面上淡入，再点（按钮变成“收起”）就淡出，回到刚才的页面——页面在底下一直保持原样，玻璃不用重画；再打开还是上次停的那一页、滚到的位置，方便一边调参数一边和 iOS 26 原生对比。从设置首页左上角返回也能关。开着的时候插件还会一帧一帧记下顶部按钮、标题和它们后面玻璃的位置和透明度（只记有变化的帧，最近几千条），所以跳动、缺失发生后马上点它导出，就能看到是哪一帧、哪个按钮出了问题，不用录屏。平时用不到时关掉（记录有一点点耗电）。"),
        WXGGroup(@"恢复",nil,@[WXGAction(@"恢复全部默认参数",@"reset",YES)],
                 @"FIX115 H：所有玻璃参数（每个范围的折射、模糊、材质、边框，底栏、分组、透镜、气泡、渐隐、菜单圆角……）、各项功能开关、整体比例和卡片圆角回到本版的标准参数（和设置首页的“恢复默认参数”一样）。总开关、两个悬浮按钮、壁纸、头像、强调色和自己建的分组不变；不覆写旧 demo 的 config.v9。")]};
    return nil;
}

/* FIX115 E: 复制到. A page's settings of one range paired with another's:
   rows of the groups every range shows, by their key in each range (WXGRowKeyForScope;
   a row with one key for all ranges is shared already: skipped); rows of a
   range's own groups (折射 / 模糊: 底栏本体, 其余玻璃, 液态气泡 ...) by their
   title (折射强度 with 折射强度); a title twice in a range: not paired. Only
   the configuration's own keys (sliders, switches, colours, choices). */
static BOOL WXGCopyableKey(NSString *key) {return key.length && ![key hasPrefix:@"pref."] && ![key hasPrefix:@"ui."] && [WXGConfig.shared knowsKey:key];}
static NSArray<NSArray<NSString *> *> *WXGCopyPairs(NSDictionary *spec,NSString *from,NSString *to) {
    NSMutableArray *pairs=[NSMutableArray array];NSMutableSet *taken=[NSMutableSet set];
    NSMutableDictionary *fromTitled=[NSMutableDictionary dictionary],*toTitled=[NSMutableDictionary dictionary];
    NSMutableSet *twice=[NSMutableSet set];
    NSSet *types=[NSSet setWithArray:@[@"slider",@"switch",@"color",@"choice"]];
    for(NSDictionary *group in spec[@"groups"]) {
        if([group[@"copySlot"] boolValue] || [group[@"title"] isEqual:@"恢复"])continue;
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
// The page's settings of `to` become `from`'s. Not saved here (the caller
// saves once). The settings changed, counted.
static NSUInteger WXGCopyRange(NSString *module,NSString *from,NSString *to) {
    NSDictionary *spec=WXGModuleSpec(module);NSArray *scopes=spec[@"scopes"];
    if(![scopes containsObject:from] || ![scopes containsObject:to] || [from isEqual:to])return 0;
    WXGConfig *c=WXGConfig.shared;NSUInteger changed=0;
    for(NSArray<NSString *> *pair in WXGCopyPairs(spec,from,to)) {
        id value=[c valueForKey:pair[0]];if(!value || value==NSNull.null)continue;
        if(![[c valueForKey:pair[1]] isEqual:value]){[c setValue:value forKey:pair[1]];++changed;}
    }
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
    if([name isEqual:@"dockTelegramIcons"] && [value boolValue])[target setValue:@NO forKey:@"dockThemeFirst"];
    if([name isEqual:@"dockThemeFirst"] && [value boolValue])[target setValue:@NO forKey:@"dockTelegramIcons"];
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

@interface WXGInputSymbolRow : WXGSettingsRow
@end
@implementation WXGInputSymbolRow {
    UILabel *_name;
    UIImageView *_preview;
    __weak UIAlertAction *_saveAction;
}
- (instancetype)initWithSpec:(NSDictionary *)spec key:(NSString *)key page:(WXGSettingsPage *)page {
    if((self=[super initWithSpec:spec key:key page:page])) {
        _name=[UILabel new];_name.font=[UIFont systemFontOfSize:13];
        _name.textColor=UIColor.secondaryLabelColor;[self addSubview:_name];
        _preview=[UIImageView new];_preview.contentMode=UIViewContentModeScaleAspectFit;[self addSubview:_preview];
        self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editName)]];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(configChanged:) name:WXGSettingsChanged object:nil];
        [self refresh];
    }
    return self;
}
- (void)configChanged:(NSNotification *)note {(void)note;[self refresh];}
- (CGFloat)rowHeight {return 64;}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=self.bounds.size.width;
    self.titleLabel.frame=CGRectMake(16,9,MAX(0,width-84),23);
    _name.frame=CGRectMake(16,33,MAX(0,width-84),19);
    CGSize size=_preview.image.size;
    CGFloat fit=MIN(1.,MIN(48./MAX(1.,size.width),40./MAX(1.,size.height)));
    _preview.bounds=CGRectMake(0,0,size.width*fit,size.height*fit);
    _preview.center=CGPointMake(width-38,self.bounds.size.height*.5);
}
- (void)refresh {
    WXGInputSymbolRole role=[self.spec[@"role"] unsignedIntegerValue];
    _preview.image=WXGInputSymbolImage(role);_preview.tintColor=WXGInputSymbolColor(role);
    _name.text=WXGRowGet(self.key);self.accessibilityValue=_name.text;[self setNeedsLayout];
}
- (void)validateName:(UITextField *)field {
    NSString *name=[field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _saveAction.enabled=!name.length || (name.length<=128 && [UIImage systemImageNamed:name]!=nil);
}
- (void)editName {
    WXGInputSymbolInfo info=WXGInputRoleInfo([self.spec[@"role"] unsignedIntegerValue]);
    NSString *fallback=@(info.fallback);
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"SF Symbols 名称" message:@"输入本机支持的符号名称，留空可恢复默认。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text=WXGRowGet(self.key);field.placeholder=fallback;
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.keyboardType=UIKeyboardTypeASCIICapable;
        [field addTarget:self action:@selector(validateName:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UITextField *field=alert.textFields.firstObject;
    UIAlertAction *save=[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name=[field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        WXGRowSet(self.key,name.length?name:fallback);
    }];
    [alert addAction:save];_saveAction=save;[self validateName:field];
    [self.page presentViewController:alert animated:YES completion:nil];
}
- (BOOL)accessibilityActivate {[self editName];return YES;}
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
- (void)refresh {_switch.on=[WXGRowGet(self.key) boolValue] && (![self.key isEqual:@"dockTelegramIcons"] || !WXGDockThemeFirst());}
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
// The choice of a stored value and back (spec "values"; none: the index itself).
- (NSInteger)choiceOfValue:(NSInteger)value {
    NSArray<NSNumber *> *values=self.spec[@"values"];if(!values.count)return value;
    NSUInteger i=[values indexOfObject:@(value)];return i==NSNotFound?-1:(NSInteger)i;
}
- (NSInteger)valueOfChoice:(NSInteger)choice {
    NSArray<NSNumber *> *values=self.spec[@"values"];
    return choice>=0 && choice<(NSInteger)values.count?values[(NSUInteger)choice].integerValue:choice;
}
- (void)refresh {
    [self showChoice:[self choiceOfValue:[WXGRowGet(self.key) integerValue]]];
    _pill.frame=[self pillFrameFor:_shown];_pill.hidden=_shown<0;
}
- (void)choose:(UIButton *)sender {
    if(sender.tag==_shown)return;
    WXGRowSet(self.key,@([self valueOfChoice:sender.tag]));
    if(WXGConfig.shared.haptics)[[[UISelectionFeedbackGenerator alloc]init] selectionChanged];
    BOOL wasHidden=_pill.hidden;
    [self showChoice:[self choiceOfValue:[WXGRowGet(self.key) integerValue]]];
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
    WXGHomeMenuStyle _builtHomeMenuStyle;
    BOOL _builtHomeCoexists,_builtHomeForm;
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
    if([_module isEqual:@"home"]) {
        _builtHomeMenuStyle=WXGConfig.shared.homeMenuStyle;
        _builtHomeForm=[WXGConfig.shared extraNumber:@"homeGroupForm"]>.5;
        _builtHomeCoexists=[WXGConfig.shared extraNumber:@"homeGroupCoexists"]>.5;
    }
    NSArray *specGroups=_spec[@"groups"];
    for(NSUInteger groupIndex=0;groupIndex<specGroups.count;groupIndex++) {
        NSDictionary *group=specGroups[groupIndex];
        if(!WXGShowsHomeMenuGroup(group))continue;
        if([group[@"copySlot"] boolValue]){group=[self copyGroupFrom:group];if(!group)continue;}    // FIX115 E
        NSString *scope=group[@"scope"];
        if(self.scoped && scope && ![scope isEqual:_scope])continue;
        NSArray *styles=group[@"styles"];   // FIX85: only for these rim styles
        if(styles && ![styles containsObject:style])continue;
        if(self.scoped && [group[@"notIn"] containsObject:_scope])continue;   // FIX113 O
        NSMutableDictionary *built=[NSMutableDictionary dictionary];
        if(group[@"title"])built[@"label"]=[self sectionLabel:group[@"title"]];
        WXGSettingsCard *card=[self addCard:NO];built[@"card"]=card;
        NSMutableArray *rows=[NSMutableArray array],*separators=[NSMutableArray array],*rowIndexes=[NSMutableArray array];
        NSArray *specRows=group[@"rows"];
        for(NSUInteger rowIndex=0;rowIndex<specRows.count;rowIndex++) {
            NSDictionary *spec=specRows[rowIndex];
            NSString *key=self.scoped?WXGRowKeyForScope(spec,_scope):spec[@"key"];
            if(!_builtHomeCoexists && [key isEqual:@"homeSearchGroupGap"])continue;
            if(key && !key.length)continue;   // FIX113 O: not in this range
            NSString *type=spec[@"type"];WXGSettingsRow *row=nil;
            if([type isEqual:@"symbol"])row=[[WXGInputSymbolRow alloc]initWithSpec:spec key:key page:self];
            else if([type isEqual:@"slider"])row=[[WXGSliderRow alloc]initWithSpec:spec key:key page:self];
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
            [card.contentView addSubview:row];[rows addObject:row];[rowIndexes addObject:@(rowIndex)];
        }
        if(!rows.count && specRows.count) {   // FIX130: none of its rows in this range (a lens' border range has only the border)
            [(UIView *)built[@"label"] removeFromSuperview];[card removeFromSuperview];continue;
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
    if([_module isEqual:@"dock"])for(NSDictionary *group in _groups)
        for(WXGSettingsRow *row in group[@"rows"])
            if([row.key isEqual:@"dockTelegramIcons"] || [row.key isEqual:@"dockThemeFirst"])[row refresh];
    for(NSDictionary *group in _groups)if([group[@"footerText"] isEqual:@"lift"]) {
        UILabel *footer=group[@"footer"];NSString *text=[self liftFooter];
        if(![footer.text isEqual:text]){footer.text=text;[self.view setNeedsLayout];}
    }
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self refreshRows];}
- (BOOL)homeChoicesChanged {
    return [_module isEqual:@"home"] && (_builtHomeMenuStyle!=WXGConfig.shared.homeMenuStyle ||
        _builtHomeForm!=([WXGConfig.shared extraNumber:@"homeGroupForm"]>.5) ||
        _builtHomeCoexists!=([WXGConfig.shared extraNumber:@"homeGroupCoexists"]>.5));
}
- (void)refreshRows {
    // FIX85: the style changed elsewhere (恢复本页默认, an import): other groups.
    BOOL styled=NO;for(NSDictionary *group in _spec[@"groups"])if(group[@"styles"]){styled=YES;break;}
    if((styled && _builtStyle!=[self scopeRimStyle]) ||
       [self homeChoicesChanged]){[self choiceChanged:@{}];return;}
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
    NSString *module=_module;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"把「%@」的设置复制到%@？",[self titleOfScope:from],names]
        message:[NSString stringWithFormat:@"%@原来的值会被替换成「%@」现在的值，不能撤销；之后各调各的。",names,[self titleOfScope:from]] preferredStyle:UIAlertControllerStyleAlert];
    __weak WXGSettingsModule *weakSelf=self;
    void (^copy)(void)=^{
        NSUInteger changed=0;
        for(NSString *t in targets)changed+=WXGCopyRange(module,from,t);
        [WXGConfig.shared save];
        if(WXGConfig.shared.haptics)[[[UINotificationFeedbackGenerator alloc]init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        WXGSettingsModule *me=weakSelf;[me refreshRows];
        UIAlertController *done=[UIAlertController alertControllerWithTitle:changed?[NSString stringWithFormat:@"已复制（改了 %lu 项）",(unsigned long)changed]:@"已经一样了，没有要改的"
            message:nil preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [me presentViewController:done animated:YES completion:nil];
    };
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){copy();}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)choiceChanged:(NSDictionary *)spec {
    if(spec.count && _builtStyle==[self scopeRimStyle] &&
       ![self homeChoicesChanged])return;
    [UIView performWithoutAnimation:^{[self buildGroups];[self.view setNeedsLayout];[self.view layoutIfNeeded];}];
    UIScrollView *scroll=self.scrollView;
    CGFloat maximum=MAX(0,scroll.contentSize.height-scroll.bounds.size.height);
    if(scroll.contentOffset.y>maximum)[scroll setContentOffset:CGPointMake(0,maximum) animated:YES];
}
- (NSString *)titleOfScope:(NSString *)scope {
    NSDictionary *titles=@{@"dock":@"底栏",@"other":@"其余玻璃",@"bubble":@"气泡",@"segment":@"分组栏",@"card":@"设置页",@"lens":@"底栏透镜的边框",@"segmentLens":@"分组透镜的边框",@"finder":@"视频号"};
    return titles[scope]?:scope;
}
// What the range chosen covers (only that one: the list of all was long).
- (NSString *)descriptionOfScope:(NSString *)scope {
    NSDictionary *texts=@{@"dock":@"悬浮标签栏本体。按压透镜在「底栏透镜与形变」中调节。",
                          @"other":@"导航按钮、标题胶囊、输入栏、搜索框、菜单、面板等。",
                          @"bubble":@"聊天里的液态气泡（“气泡用完整玻璃”开着时生效）。",
                          @"segment":@"聊天列表顶部的分组栏和首页标题分组栏。",
                          @"card":@"这几页设置的卡片和按钮，调节时可直接看到。",
                          @"lens":@"底栏按住时浮起的透镜自己的边框，支持 iOS 26 / iOS 27。",
                          @"segmentLens":@"分组栏与标题分组栏按住时的透镜和选中胶囊边框，支持 iOS 26 / iOS 27。",
                          @"finder":@"视频号视频页和作品页顶部的按钮胶囊。"};
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
    if([action isEqual:@"meBannerLibrary"]){[self.navigationController pushViewController:WXGBannerLibraryPage() animated:YES];return;}
    if([action isEqual:@"manageGroups"]){[self.navigationController pushViewController:WXGChatGroupsPage() animated:YES];return;}   // FIX113 R
    if([action hasPrefix:@"copyTo:"]){[self copyScopeTo:[action substringFromIndex:7]];return;}   // FIX115 E
    // FIX114 O (user: the capsule's proportions are not the screenshot's): the
    // iOS 26 Messages capsule as measured (3x screenshot): about 29 pt high,
    // 17 pt text, a 12 pt chevron (its paddings 14 / 11 pt are fixed).
    if([action isEqual:@"avatarCapsuleIOS"]){WXGRowSet(@"avatarCapsuleHeight",@29.0);WXGRowSet(@"avatarCapsuleTextSize",@17.0);WXGRowSet(@"avatarCapsuleChevronSize",@12.0);[self refreshRows];return;}
    // FIX127: iOS 26's tab bar values into the dock's settings, and back.
    if([action isEqual:@"dockSystem26"]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"套用 iOS 26 实测数值？"
            message:@"底栏的宽高、内边距、透镜大小和放大、透镜的折射和边框、形变、松手停留和位置弹簧，以及底栏这块玻璃自己的材质 / 阴影 / 边框、选中胶囊的颜色、轻点的起落、手指下的光、图标和文字的大小位置，换成 iOS 26 系统底栏上量出来的值。原来的值会存一份，点“还原套用前的数值”可以全部放回去。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak WXGSettingsModule *weakSelf=self;
        [alert addAction:[UIAlertAction actionWithTitle:@"套用" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            CGSize screen=UIScreen.mainScreen.bounds.size;
            [WXGConfig.shared applyDockSystem26ForScreenWidth:MIN(screen.width,screen.height)];[weakSelf refreshRows];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if([action isEqual:@"dockSystem26Restore"]) {
        BOOL kept=[WXGConfig.shared hasDockSystem26Backup];
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:kept?@"还原套用前的数值？":@"没有可还原的数值"
            message:kept?@"“套用 iOS 26 实测数值”改过的那些项回到第一次套用之前的值，其它设置不变。":@"还没有套用过 iOS 26 实测数值（或者已经还原过了）。" preferredStyle:UIAlertControllerStyleAlert];
        __weak WXGSettingsModule *weakSelf=self;
        if(kept) {
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"还原" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
                [WXGConfig.shared restoreDockBeforeSystem26];[weakSelf refreshRows];
            }]];
        }else [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
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
    NSDictionary *scopeTitles=@{@"dock":@"底栏",@"other":@"其余玻璃",@"bubble":@"气泡",@"segment":@"分组栏",@"card":@"设置页",@"lens":@"底栏透镜的边框",@"segmentLens":@"分组透镜的边框",@"finder":@"视频号"};
    for(NSArray *card in cards) {
        if(card.count<3 || ![card[0] isKindOfClass:NSString.class])continue;
        NSString *module=card[0];NSDictionary *spec=WXGModuleSpec(module);if(!spec)continue;
        NSString *pageTitle=[spec[@"title"] isKindOfClass:NSString.class]?spec[@"title"]:card[1];
        if(WXGSearchAll([NSString stringWithFormat:@"%@ %@ %@",pageTitle,card[1],card[2]],words))
            [first addObject:@{@"module":module,@"group":@(-1),@"row":@(-1),@"title":card[1],@"path":card[2]}];
        NSArray *groups=spec[@"groups"];
        for(NSUInteger g=0;g<groups.count;g++) {
            NSDictionary *group=groups[g];
            if(!WXGShowsHomeMenuGroup(group))continue;
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
