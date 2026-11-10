#import "WXGCommon.h"
#include "WXGDockScript.h"
#include <stdarg.h>

NSString * const WXGSettingsChanged = @"com.runyu.WGLiquidDockDemo.settings";
static NSMutableArray<NSString *> *WXGMessages;

void WXGLog(NSString *format, ...) {
#if !defined(WXG_RELEASE) || !WXG_RELEASE
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    @synchronized(WXGConfig.class) {
        if (!WXGMessages) WXGMessages = [NSMutableArray array];
        [WXGMessages addObject:[NSString stringWithFormat:@"%.3f %@", CACurrentMediaTime(), message]];
        if (WXGMessages.count > 160) [WXGMessages removeObjectAtIndex:0];
    }
    NSLog(@"[WeChatLiquidGlass] %@", message);
#else
    (void)format;   // FIX113: 对外发布包(-DWXG_RELEASE)不打 syslog / 不留内存日志
#endif
}
NSString *WXGLogText(void) {
    @synchronized(WXGConfig.class) { return [WXGMessages componentsJoinedByString:@"\n"] ?: @""; }
}

NSString *WXGNormalizeHex(NSString *hex) {
    if(![hex isKindOfClass:NSString.class]) return nil;
    NSString *s=[[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if([s hasPrefix:@"#"]) s=[s substringFromIndex:1];
    if(s.length!=6 && s.length!=8) return nil;
    if([s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet]].location!=NSNotFound) return nil;
    return [@"#" stringByAppendingString:s.length==6?[s stringByAppendingString:@"FF"]:s];
}
UIColor *WXGColor(NSString *hex) {
    NSString *s=WXGNormalizeHex(hex); if(!s) return UIColor.clearColor;
    unsigned int v=0; [[NSScanner scannerWithString:[s substringFromIndex:1]] scanHexInt:&v];
    return [UIColor colorWithRed:((v>>24)&255)/255.0 green:((v>>16)&255)/255.0 blue:((v>>8)&255)/255.0 alpha:(v&255)/255.0];
}

NSInteger WXGScreenCaptureFPS(UIScreen *screen) {
    return WXGEffectiveFPS((int)WXGConfig.shared.captureFPS,(int)(screen?:UIScreen.mainScreen).maximumFramesPerSecond);
}
void WXGConfigureDisplayLink(CADisplayLink *link,UIScreen *screen) {
    NSInteger maximum=WXGEffectiveFPS(120,(int)(screen?:UIScreen.mainScreen).maximumFramesPerSecond);
    // Test the exact selector instead of depending on a compiler-rt availability
    // helper. This also builds with Linux/Theos cross-compilers on the iOS 13 target.
    if([link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        CAFrameRateRange target=CAFrameRateRangeMake(MIN(30,maximum),maximum,maximum);
        CAFrameRateRange current=link.preferredFrameRateRange;
        if(current.minimum!=target.minimum || current.maximum!=target.maximum || current.preferred!=target.preferred)link.preferredFrameRateRange=target;
#pragma clang diagnostic pop
    }else if(link.preferredFramesPerSecond!=maximum)link.preferredFramesPerSecond=maximum;
}

/* Keys kept in a table instead of properties (FIX85): every range's glass
   (FIX130: refraction, blur, material, shadow), the two borders (iOS 26's,
   iOS 27's), the dock, the segment bar, the pages' features. Each is a number
   ('n', clamped to lo..hi), a switch ('b') or a colour ('h'). A key with
   `inherit` starts, when it has never been stored, from that key's current
   value (so nothing looks different until it is changed). They are ordinary
   keys to everything else (KVC, the settings rows, export / import, the
   build defaults). */
typedef struct {const char *key; char kind; double def,lo,hi; const char *inherit,*hex;} WXGExtraSpec;
static const WXGExtraSpec WXGExtraSpecs[]={
    {"bubbleFullGlass",'b',0,0,1,NULL,NULL},
    {"bubbleSharedBackdrop",'b',1,0,1,NULL,NULL},   // FIX119 B
    {"rimStyle",'n',3,2,3,NULL,NULL},
    {"dockRimStyle",'n',3,2,3,"rimStyle",NULL},
    {"bubbleRimStyle",'n',3,2,3,"rimStyle",NULL},
    {"rim27Hex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"rim27Opacity",'n',0.6,0,1,NULL,NULL},
    {"rim27Width",'n',2.0,0.3,8,NULL,NULL},
    {"rim27Falloff",'n',1.6,0.5,4,NULL,NULL},
    {"rim27EndLevel",'n',0.15,0,1,NULL,NULL},
    {"rim27Angle",'n',90,0,180,NULL,NULL},
    {"darkRim27Hex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"darkRim27Opacity",'n',0.35,0,1,NULL,NULL},
    {"darkRim27Width",'n',2.0,0.3,8,NULL,NULL},
    {"darkRim27Falloff",'n',1.6,0.5,4,NULL,NULL},
    {"darkRim27EndLevel",'n',0.15,0,1,NULL,NULL},
    {"darkRim27Angle",'n',0,0,180,NULL,NULL},
    {"rim27Sharpness",'n',2,0.5,6,NULL,NULL},
    {"darkRim27Sharpness",'n',2,0.5,6,"rim27Sharpness",NULL},   // FIX89: the second highlight's own
    {"dockRim27Hex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"dockRim27Opacity",'n',0.6,0,1,NULL,NULL},
    {"dockRim27Width",'n',2.0,0.3,8,NULL,NULL},
    {"dockRim27Falloff",'n',1.6,0.5,4,NULL,NULL},
    {"dockRim27EndLevel",'n',0.15,0,1,NULL,NULL},
    {"dockRim27Angle",'n',90,0,180,NULL,NULL},
    {"dockDarkRim27Hex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"dockDarkRim27Opacity",'n',0.35,0,1,NULL,NULL},
    {"dockDarkRim27Width",'n',2.0,0.3,8,NULL,NULL},
    {"dockDarkRim27Falloff",'n',1.6,0.5,4,NULL,NULL},
    {"dockDarkRim27EndLevel",'n',0.15,0,1,NULL,NULL},
    {"dockDarkRim27Angle",'n',0,0,180,NULL,NULL},
    {"dockRim27Sharpness",'n',2,0.5,6,NULL,NULL},
    {"dockDarkRim27Sharpness",'n',2,0.5,6,"dockRim27Sharpness",NULL},   // FIX89: the second highlight's own
    {"bubbleRim27Hex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"bubbleRim27Opacity",'n',0.6,0,1,NULL,NULL},
    {"bubbleRim27Width",'n',2.0,0.3,8,NULL,NULL},
    {"bubbleRim27Falloff",'n',1.6,0.5,4,NULL,NULL},
    {"bubbleRim27EndLevel",'n',0.15,0,1,NULL,NULL},
    {"bubbleRim27Angle",'n',90,0,180,NULL,NULL},
    {"bubbleDarkRim27Hex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"bubbleDarkRim27Opacity",'n',0.35,0,1,NULL,NULL},
    {"bubbleDarkRim27Width",'n',2.0,0.3,8,NULL,NULL},
    {"bubbleDarkRim27Falloff",'n',1.6,0.5,4,NULL,NULL},
    {"bubbleDarkRim27EndLevel",'n',0.15,0,1,NULL,NULL},
    {"bubbleDarkRim27Angle",'n',0,0,180,NULL,NULL},
    {"bubbleRim27Sharpness",'n',2,0.5,6,NULL,NULL},
    {"bubbleDarkRim27Sharpness",'n',2,0.5,6,"bubbleRim27Sharpness",NULL},   // FIX89: the second highlight's own
    // FIX88: the lens's colour split has its own band and top / bottom ratio
    // (first: the refraction band's).
    {"dockIconTitleGap",'n',5,0,16,NULL,NULL},    // FIX89: the dock's icons: icon to title (pt)
    {"dockIconOffset",'n',0,-12,12,NULL,NULL},    // FIX89: icon and title together, + down (pt)
    {"dockTitleSize",'n',10,8,13,NULL,NULL},      // FIX91: the titles' size (pt; 10.5 before)
    {"dockTitleWeight",'n',1,0,4,NULL,NULL},      // FIX91: 0 light .. 4 bold (2 medium); FIX114 B: regular, as WeChat's own tab titles
    {"dockTitleWeightNative",'b',0,0,1,NULL,NULL},   // FIX114 B: the one-time move from the old default (medium) to regular is done
    {"dockTitleBolderSelected",'b',0,0,1,NULL,NULL},   // FIX91: the selected title one step bolder (always before)
    // FIX112: FIX94's bar following the lens' rim is gone (setting and effect).
    // FIX112 E: the lens shows what is under it (the shrunk bar with its own
    // veil, the page around it) unless its filter colour is switched on: then
    // that colour over the whole lens (icons included), as it lifts.
    {"lensTintOn",'b',0,0,1,NULL,NULL},
    // FIX113 H: the lens' refraction outward (its rim gathers what lies just
    // outside it, iOS 26) instead of inward (needs the server's new shader).
    // FIX113 I (user: an offset that cancels the refraction width): the share
    // of the lens' rim offset taken away (0 as before; 1 the rim shows what is
    // under it and the band only bends it). Needs the server's new shader.
    {"lensOffsetCancel",'n',0,0,1,NULL,NULL},
    // FIX113 N: the chat list's segment bar in place of its search field (a
    // demo grouping); the groove's darkness over the background, per appearance.
    {"chatSegments",'b',1,0,1,NULL,NULL},
    // FIX113 L (user: the lens' border forks at its top / bottom; the lens'
    // border has nothing to do with the bar): the bar's own outline is not
    // drawn inside the lens unless switched back on (it branched off the
    // lens' rim where the page above / below the bar shows through the lens).
    // FIX113 K's bar following the rim is gone again (the user did not want it).
    // FIX113 M (user: take away the slanted line joining the inner and outer
    // outline, cut it off from the magnified outside, small and flat inside):
    // the bar seen through the lens unbent and inset in full (WXG_LENS_FLAT).
    // FIX113: the two-ended input bar's icons: the plugin's set (SF Symbols,
    // the emoji key as Face ID) or WeChat's own artwork.
    {"inputSystemIcons",'b',1,0,1,NULL,NULL},
    // FIX115 J (user: the two-ended bar's text capsule "大一点短一点", the plus
    // as big): pt at the reference width (scaled like the rest): the capsule's
    // single-line height (TEST9: 40), the plus' size (0 = the capsule's
    // height), the distance from the screen's sides (TEST9: 28) and from the
    // plus to the capsule (TEST9: 12).
    {"inputPillHeight",'n',44,34,54,NULL,NULL},
    {"inputPlusSize",'n',0,0,54,NULL,NULL},
    {"inputSideMargin",'n',34,8,60,NULL,NULL},
    {"inputPlusGap",'n',12,4,24,NULL,NULL},
    // FIX115 J: WeChat's coloured buttons (完成) as tinted glass capsules (WXGLocalGlass.m).
    {"localColorButtons",'b',1,0,1,NULL,NULL},
    // FIX115 Q: 朋友圈's "N条新消息" banner (glass capsule, the avatar round) and its ·· button (WXGLocalGlass.m).
    {"localMoments",'b',1,0,1,NULL,NULL},
    // FIX115 L (user: the press stretch "不要被那么轻易的拉动": "屏幕上拖3的距离按钮
    // 变形1的距离甚至比例更大点"): the finger's travel per point of pull (1 = as
    // before: the pull is the finger's distance, rubber-banded).
    // FIX115 N (user, 21:34: "默认值改为8"): 8; range to 12. FIX115 O (user,
    // 21:58: "别从8开始万一有人喜欢更灵敏"): the default 3 again (L's, the user's
    // first 3:1), range 1-12, nothing moved: a value a phone has stays.
    {"pressStretchRatio",'n',3,1,12,NULL,NULL},
    {"pressStretchRatioBack",'b',1,0,1,NULL,NULL},   // FIX115 O: N's 8 moved back to 3 (once)
    // FIX116 A (user, 10-29: the home "+" menu as in his reference video: a
    // glass capsule with the title on the left, a round glass icon on the
    // right in line with the "+"; each row fading in, "but not the flip",
    // the entrance designed again; WXGMenuCascade.h, WXGDecorations.m):
    // the switch (off: the one glass plate behind WeChat's own rows, as
    // before), the icon's size (pt at the "+"'s own size; the capsule is 0.78
    // of it), the gap between two rows' starts (ms) and the speed of it all.
    {"homeMenuCapsules",'b',1,0,1,NULL,NULL},
    {"homeMenuIconSize",'n',44,34,56,NULL,NULL},
    {"homeMenuStagger",'n',34,0,80,NULL,NULL},
    {"homeMenuSpeed",'n',1,.5,2,NULL,NULL},
    // FIX118 A (user, 11-04: the 我 page as Telegram's profile, the avatar
    // melting into the Dynamic Island; "给这次要做的功能加一个开关，关掉开关的话就只做
    // 头像上收，打开开关的话就完全替换掉状态"; WXGMeHeader.m): the header itself, the
    // banner pull (in place of WeChat's status pull), the avatar's size, on a
    // notched phone melting into the notch (off: shrinking and fading, as
    // Telegram), and nudges of the cut-out's place / width (pt).
    {"meHeader",'b',1,0,1,NULL,NULL},
    {"meBanner",'b',0,0,1,NULL,NULL},
    {"meBannerEdgeStyle",'n',0,0,2,NULL,NULL},   // FIX118 F (user: keep the drips, and a natural fade into WeChat's page): 0 drips, 1 fade, 2 plain
    {"meAvatarSize",'n',100,70,130,NULL,NULL},
    {"meNotchMerge",'b',1,0,1,NULL,NULL},
    {"meCutoutY",'n',0,-8,8,NULL,NULL},
    {"meCutoutW",'n',0,-30,30,NULL,NULL},
    // FIX113: the dock's icons Telegram's (Chats, Contacts, Calls, Settings),
    // each with its own animation when its tab is chosen.
    {"dockTelegramIcons",'b',0,0,1,NULL,NULL},
    // FIX115 D: 底栏主题优先: the dock takes WeChat's / a theme's icons and
    // title colours as shown (at their shown size); Telegram's and the accent off.
    {"dockThemeFirst",'b',0,0,1,NULL,NULL},
    // FIX113 C: the selected tab's colour (icon and title) for the plugin's
    // own icons (system symbols, Telegram's); WeChat's own keep theirs.
    {"dockAccentHex",'h',0,0,0,NULL,"#08B861FF"},
    {"lensTintHex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"lensTintOpacity",'n',.12,0,1,NULL,NULL},
    {"darkLensTintHex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"darkLensTintOpacity",'n',.08,0,1,NULL,NULL},
    // FIX95: the tap animation is the real lens; this brings back the
    // render-server one (smooth through WeChat's switch, but only a shape).
    {"dockTapSimpleTravel",'b',0,0,1,NULL,NULL},
    // FIX98: the tap's real lens: its move x this (FIX43's 0.28 s x (0.85 +
    // 0.05 x tabs) is 1), its drop (s; FIX95 0.09), and when WeChat switches
    // (0 at the release, 1 when the lens has nearly arrived, 2 once it is down).
    // FIX99: new keys with faster defaults (FIX98's 1.5 / 0.26 s were stored
    // for everyone; a FIX98 value the tester changed is carried over on load),
    // and the share of the move the pill takes to turn into the lens.
    {"dockTapMoveScale",'n',1.4,.6,3,NULL,NULL},
    {"dockTapDropTime",'n',.16,.08,.8,NULL,NULL},
    {"dockTapLensShare",'n',.40,.15,.9,NULL,NULL},
    // FIX100: when WeChat switches: 0 at the touch (as its own tab bar), 1 at
    // the release, 2 when the lens has nearly arrived, 3 once it is down (a
    // new key: FIX98/99's 0..2 = 1..3; one the tester changed comes along).
    {"dockTapSwitchWhen",'n',0,0,3,NULL,NULL},
    {"dockTapSmartHold",'b',0,0,1,NULL,NULL},
    {"dockTapSmartHoldOff",'b',0,0,1,NULL,NULL},   // FIX119 F: the one-time move to off is done (E saved every key, its 1 with them)   // FIX119 E; FIX119 F: off by default (the page came late: the user felt WeChat had not taken the tap)
    // FIX101: after the switch the lens waits for WeChat's busy frames to pass.
    // FIX102: off (user: slower; every tap waited 65-210 ms): a new key.
    {"dockTapCalmWaitOn",'b',0,0,1,NULL,NULL},
    // FIX102: after a pause (WeChat's switch) the rest of the tap catches up.
    {"dockTapCatchUp",'b',1,0,1,NULL,NULL},
    // 离散底栏: the selected tab a wide capsule, the others balls (on by
    // default in this build); balls joined; the original pill on the
    // selected tab; gap (pt); the selection's width (cells); balls x the
    // dock's height; spring damping ratio and response (s, React's damping
    // 20 / stiffness 230 / mass 1.2 is about 0.6 / 0.45); lighter glass.
    {"dockDiscrete",'b',1,0,1,NULL,NULL},
    {"dockDiscreteConnected",'b',0,0,1,NULL,NULL},
    {"dockDiscretePill",'b',0,0,1,NULL,NULL},
    {"dockDiscreteGap",'n',8,0,24,NULL,NULL},
    {"dockDiscreteWide",'n',2,1,3,NULL,NULL},
    {"dockDiscreteBall",'n',.9,.6,1.3,NULL,NULL},
    {"dockDiscreteDamping",'n',.6,.45,1,NULL,NULL},
    {"dockDiscreteResponse",'n',.45,.2,1,NULL,NULL},
    {"dockDiscreteLight",'b',0,0,1,NULL,NULL},
    // FIX106 B (user: icons and titles a little small): the icon's size (pt;
    // A used the atlas's 26), the 中文 and English titles' sizes (A: 13 / 9.5).
    {"dockDiscreteIconSize",'n',30,20,40,NULL,NULL},
    {"dockDiscreteTitleSize",'n',15,10,20,NULL,NULL},
    {"dockDiscreteSubtitleSize",'n',11,8,16,NULL,NULL},
    // FIX106 C (user: connected, the end icons sat too far out): how far the
    // joined balls' icons gather toward their run's middle (share of a cell).
    {"dockDiscreteGather",'n',.22,0,.45,NULL,NULL},
    // FIX106 H (user: the wide capsule's centred icon + titles look off, they
    // need an offset): the block moved this far left when wide (pt; 0 = centred).
    {"dockDiscreteContentShift",'n',10,0,30,NULL,NULL},
    // FIX107 B (user: an adjustable continuous radius for the plus panel's
    // tiles and the emoji group selection): pt; 0 = WeChat's own.
    {"localTileRadius",'n',0,0,32,NULL,NULL},
    {"localTabRadius",'n',0,0,22,NULL,NULL},
    // FIX95: the chat title's avatar (头像模式): its size and height (pt,
    // scaled with 截图比例微调), the ring's width and colour per appearance.
    {"avatarSize",'n',60,32,88,NULL,NULL},
    {"avatarOffsetY",'n',0,-24,24,NULL,NULL},
    {"avatarBorderWidth",'n',1.5,0,4,NULL,NULL},
    {"avatarBorderHex",'h',0,0,0,NULL,"#80808052"},
    {"avatarDarkBorderHex",'h',0,0,0,NULL,"#9E9E9E6B"},
    // FIX109 (user: the chat page's top-right button as the chat's avatar, an
    // adjustable inner padding): pt between the photo and the glass's edge.
    {"chatAvatarInset",'n',4,0,12,NULL,NULL},
    // FIX109 (user: the capsule under the avatar in 头像模式 may need another
    // size): its height (pt; its top stays 5 pt into the avatar's lower edge).
    {"avatarCapsuleHeight",'n',30,22,48,NULL,NULL},
    // FIX114 M (user: a taller capsule is for more room around the text, not
    // larger text): its text's size (pt), whatever the height; and iOS 26's
    // grey chevron after the name (opens the chat's settings; not while typing).
    {"avatarCapsuleTextSize",'n',15,11,20,NULL,NULL},
    {"avatarCapsuleChevron",'b',1,0,1,NULL,NULL},
    {"avatarCapsuleChevronSize",'n',14.5,8,24,NULL,NULL},   // FIX114 N (08:35: a touch larger)
    // FIX109 B (user: the default gap between the pinned module and the
    // avatar mode's capsule looks wide): pt added to it (negative: closer).
    {"pinnedGapAdjust",'n',0,-16,16,NULL,NULL},
    // FIX88: 平稳背景时加强材质 again (FIX85, removed in FIX86).
    // FIX113 O: the chat list's segment bar's own lens and pill (user: not the
    // dock's parameters; its pill's inset, colour and border its own), first
    // from the dock's; its text; the floating search (segment bar, the home
    // page's and 通讯录's search bars stay below the title row).
    {"segmentLensRefraction",'n',1.15,0,20,"lensRefraction",NULL},
    {"segmentLensDispersion",'n',.95,0,8,"lensDispersion",NULL},
    {"segmentLensEdgeWidth",'n',10,1,60,"lensEdgeWidth",NULL},
    {"segmentLensTopEdgeRatio",'n',1,.1,1,"lensTopEdgeRatio",NULL},
    {"segmentLensEdgeSharpness",'n',3,1,6,"lensEdgeSharpness",NULL},
    {"segmentLensZoom",'n',1.2,1,1.5,"lensZoom",NULL},
    {"segmentLensGrowth",'n',1.28,1.08,1.5,"lensGrowth",NULL},
    {"segmentBarGrowth",'n',1,1,1.08,"barGrowth",NULL},
    {"segmentEndWrap",'n',6,2,10,"endWrap",NULL},
    {"segmentBodyPinch",'n',.18,0,.3,"bodyPinch",NULL},
    {"segmentLensBlur",'n',0,0,12,"lensBlur",NULL},
    {"segmentPillRimAtRest",'n',0,0,1,NULL,NULL},
    {"segmentLensTintOn",'b',0,0,1,"lensTintOn",NULL},
    {"segmentLensTintHex",'h',0,0,0,"lensTintHex","#FFFFFFFF"},
    {"segmentDarkLensTintHex",'h',0,0,0,"darkLensTintHex","#FFFFFFFF"},
    {"segmentLensTintOpacity",'n',.12,0,1,"lensTintOpacity",NULL},
    {"segmentDarkLensTintOpacity",'n',.08,0,1,"darkLensTintOpacity",NULL},
    {"segmentSelectionInset",'n',4,2,14,"selectionInset",NULL},
    {"segmentPillAuto",'b',0,0,1,NULL,NULL},
    {"segmentPillHex",'h',0,0,0,"selectionHex","#71879EFF"},
    {"segmentDarkPillHex",'h',0,0,0,"darkSelectionHex","#71879EFF"},
    {"segmentPillOpacity",'n',.3,0,1,"selectionOpacity",NULL},
    {"segmentDarkPillOpacity",'n',.3,0,1,"selectionOpacity",NULL},
    {"segmentTitleSize",'n',14,10,18,NULL,NULL},
    {"segmentTitleWeight",'n',2,0,4,NULL,NULL},
    {"segmentInkHex",'h',0,0,0,NULL,"#1A1A1AEB"},
    {"segmentDarkInkHex",'h',0,0,0,NULL,"#F7F7F7F7"},
    {"searchFloat",'b',0,0,1,NULL,NULL},
    {"settingsBackgroundHex",'h',0,0,0,NULL,"#F2F2F7FF"},
    {"settingsDarkBackgroundHex",'h',0,0,0,NULL,"#1C1C1EFF"},
    // FIX113 O: two more glass ranges with every glass setting of their own
    // (as the bubbles'): 分组 (the segment bar) and 设置页 (this plugin's
    // settings pages: their cards and title-bar buttons).
    {"segmentRimStyle",'n',3,2,3,"dockRimStyle",NULL},
    {"cardRimStyle",'n',3,2,3,"rimStyle",NULL},
    {"segmentRim27Hex",'h',0,0,0,"dockRim27Hex","#FFFFFFFF"},
    {"cardRim27Hex",'h',0,0,0,"rim27Hex","#FFFFFFFF"},
    {"segmentRim27Opacity",'n',0.6,0,1,"dockRim27Opacity",NULL},
    {"cardRim27Opacity",'n',0.6,0,1,"rim27Opacity",NULL},
    {"segmentRim27Width",'n',2.0,0.3,8,"dockRim27Width",NULL},
    {"cardRim27Width",'n',2.0,0.3,8,"rim27Width",NULL},
    {"segmentRim27Falloff",'n',1.6,0.5,4,"dockRim27Falloff",NULL},
    {"cardRim27Falloff",'n',1.6,0.5,4,"rim27Falloff",NULL},
    {"segmentRim27EndLevel",'n',0.15,0,1,"dockRim27EndLevel",NULL},
    {"cardRim27EndLevel",'n',0.15,0,1,"rim27EndLevel",NULL},
    {"segmentRim27Angle",'n',90,0,180,"dockRim27Angle",NULL},
    {"cardRim27Angle",'n',90,0,180,"rim27Angle",NULL},
    {"segmentDarkRim27Hex",'h',0,0,0,"dockDarkRim27Hex","#FFFFFFFF"},
    {"cardDarkRim27Hex",'h',0,0,0,"darkRim27Hex","#FFFFFFFF"},
    {"segmentDarkRim27Opacity",'n',0.35,0,1,"dockDarkRim27Opacity",NULL},
    {"cardDarkRim27Opacity",'n',0.35,0,1,"darkRim27Opacity",NULL},
    {"segmentDarkRim27Width",'n',2.0,0.3,8,"dockDarkRim27Width",NULL},
    {"cardDarkRim27Width",'n',2.0,0.3,8,"darkRim27Width",NULL},
    {"segmentDarkRim27Falloff",'n',1.6,0.5,4,"dockDarkRim27Falloff",NULL},
    {"cardDarkRim27Falloff",'n',1.6,0.5,4,"darkRim27Falloff",NULL},
    {"segmentDarkRim27EndLevel",'n',0.15,0,1,"dockDarkRim27EndLevel",NULL},
    {"cardDarkRim27EndLevel",'n',0.15,0,1,"darkRim27EndLevel",NULL},
    {"segmentDarkRim27Angle",'n',0,0,180,"dockDarkRim27Angle",NULL},
    {"cardDarkRim27Angle",'n',0,0,180,"darkRim27Angle",NULL},
    {"segmentRim27Sharpness",'n',2,0.5,6,"dockRim27Sharpness",NULL},
    {"cardRim27Sharpness",'n',2,0.5,6,"rim27Sharpness",NULL},
    {"segmentDarkRim27Sharpness",'n',2,0.5,6,"dockDarkRim27Sharpness",NULL},
    {"cardDarkRim27Sharpness",'n',2,0.5,6,"darkRim27Sharpness",NULL},
    // FIX113 P (user: the segment bar as the dock, tuned from there, not the
    // system's segmented control): its glass, pill and titles start from the
    // dock's (the keys above now inherit the dock's); the pill fades while
    // pressed as the dock's; the selected title in the dock's accent colour.
    {"segmentPillPressedOpacity",'n',.05,0,1,"pressedOpacity",NULL},
    {"segmentAccentOn",'b',1,0,1,NULL,NULL},
    {"segmentAccentHex",'h',0,0,0,"dockAccentHex","#08B861FF"},
    // FIX113 X (user: the lens' border set like every other glass's, on its
    // own): the 透镜 range of 边框与渐隐 (the dock's lens and the segment bar's):
    // all three rim styles with their values. Starts as the lens' plain line
    // was (colour, opacity, width per appearance; no side fade, no glow); the
    // other styles start from the dock's values.
    {"lensGlassRimStyle",'n',3,2,3,NULL,NULL},
    {"lensGlassRim27Hex",'h',0,0,0,"dockRim27Hex","#FFFFFFFF"},
    {"lensGlassRim27Opacity",'n',0.6,0,1,"dockRim27Opacity",NULL},
    {"lensGlassRim27Width",'n',2.0,0.3,8,"dockRim27Width",NULL},
    {"lensGlassRim27Falloff",'n',1.6,0.5,4,"dockRim27Falloff",NULL},
    {"lensGlassRim27EndLevel",'n',0.15,0,1,"dockRim27EndLevel",NULL},
    {"lensGlassRim27Angle",'n',90,0,180,"dockRim27Angle",NULL},
    {"lensGlassDarkRim27Hex",'h',0,0,0,"dockDarkRim27Hex","#FFFFFFFF"},
    {"lensGlassDarkRim27Opacity",'n',0.35,0,1,"dockDarkRim27Opacity",NULL},
    {"lensGlassDarkRim27Width",'n',2.0,0.3,8,"dockDarkRim27Width",NULL},
    {"lensGlassDarkRim27Falloff",'n',1.6,0.5,4,"dockDarkRim27Falloff",NULL},
    {"lensGlassDarkRim27EndLevel",'n',0.15,0,1,"dockDarkRim27EndLevel",NULL},
    {"lensGlassDarkRim27Angle",'n',0,0,180,"dockDarkRim27Angle",NULL},
    {"lensGlassRim27Sharpness",'n',2,0.5,6,"dockRim27Sharpness",NULL},
    {"lensGlassDarkRim27Sharpness",'n',2,0.5,6,"dockDarkRim27Sharpness",NULL},
    // FIX113 X (user: the icons and titles in the lens refracted by a width
    // and strength of their own, the rest by the lens' current ones): start
    // as the lens'.
    {"lensIconRefraction",'n',1.15,0,20,"lensRefraction",NULL},
    {"lensIconEdgeWidth",'n',10,1,60,"lensEdgeWidth",NULL},
    {"segmentLensIconRefraction",'n',1.15,0,20,"segmentLensRefraction",NULL},
    {"segmentLensIconEdgeWidth",'n',10,1,60,"segmentLensEdgeWidth",NULL},
    // FIX113 Y (user: the icons and titles also need their own top / bottom
    // band ratio and narrowing; the drag-speed deformation switchable, its
    // height change limited).
    {"lensIconTopEdgeRatio",'n',1,.1,1,"lensTopEdgeRatio",NULL},
    {"lensIconEdgeSharpness",'n',3,1,6,"lensEdgeSharpness",NULL},
    {"segmentLensIconTopEdgeRatio",'n',1,.1,1,"segmentLensTopEdgeRatio",NULL},
    {"segmentLensIconEdgeSharpness",'n',3,1,6,"segmentLensEdgeSharpness",NULL},
    {"lensElasticOn",'b',1,0,1,NULL,NULL},
    {"segmentLensElasticOn",'b',1,0,1,"lensElasticOn",NULL},
    // FIX113 Y: as the lens squashes / swells, the smaller bar in it insets by
    // that much more / less, so the strip between it and the lens' rim keeps
    // its width (1 fully, 0 as before).
    // FIX114 B: a chat without the avatar title keeps WeChat's own title-bar
    // buttons and title (local glass capsules behind them).
    {"chatNativeBar",'b',1,0,1,NULL,NULL},
    {"navNativeButtons",'b',0,0,1,NULL,NULL},   // FIX114 B: every page but the home page: WeChat's own title-bar buttons, capsules behind
    // FIX114 R (user: diagnostics could only be exported from the plugin's
    // settings, never from the chat where the title bar jumps): a small
    // button on every page that exports at once, and while it is on, what the
    // title bars show recorded frame by frame (WXGHost.m).
    {"diagnosticsFloat",'b',0,0,1,NULL,NULL},
    {"settingsFloat",'b',0,0,1,NULL,NULL},   // FIX115 G: a button on every page that opens / closes these settings
    // FIX114 V (user, 23:46: "只把原生的这些抓进自建的"): WeChat's own title-bar
    // buttons shown in the plugin's own glass buttons (its row, its transitions),
    // a copy of WeChat's icon / text / count inside, the real ones hidden.
    {"navNativeLook",'b',1,0,1,NULL,NULL},
    // FIX114 C (user: the top buttons' distance to the screen's edges set by hand):
    // the title row's margin to the sides (pt at the reference width: m.edge
    // was 20) and how far the whole row is moved down (pt).
    {"navEdge",'n',20,8,36,NULL,NULL},
    // FIX115 S (user: "对视频号整个这一项都固定一个边距可调值"): every 视频号 page's
    // title-row margin (the feed's capsules, the other pages' buttons) instead of navEdge.
    {"finderEdge",'n',14,0,30,NULL,NULL},
    {"navOffsetY",'n',0,0,16,NULL,NULL},
    {"lensElasticKeepStrip",'n',1,0,1,NULL,NULL},
    {"segmentLensElasticKeepStrip",'n',1,0,1,"lensElasticKeepStrip",NULL},
    // FIX126: the system's own deformation (WXGLensFlex.h, fitted on the tab bar lens recorded on
    // iOS 26.6), for the dock's and the segment bar's lens.
    {"lensFlexStrength",'n',1,0,3,NULL,NULL},      // both gains x this
    {"lensFlexSlow",'n',8,3,20,NULL,NULL},         // the slow follower's frequency (rad/s): lower, a longer and softer swing back
    {"lensFlexDamping",'n',.5,.15,1.2,NULL,NULL},  // its damping ratio: lower, more of the opposite shape on stopping
    {"lensFlexSymmetric",'b',0,0,1,NULL,NULL},
    {"lensFlexSqueeze",'n',1,0,1.5,NULL,NULL},     // FIX133: the narrow-and-tall half alone x this (1: the system's)
    // FIX127 (user: "wire the table's system values into the dock, the whole thing replaced"): what
    // the dock could not express of iOS 26's tab bar (WXGDockSystem.h; probe 2). All 0 / off: the dock as it was.
    {"dockCellExtra",'n',0,0,20,NULL,NULL},        // each tab's cell this much wider than a quarter (they overlap; iOS 26: 10)
    {"dockLensLiftWidth",'n',0,0,40,NULL,NULL},    // > 0: the lifted lens is its cell + this (iOS 26: 16); 0: at least 1.2 cells, as before
    {"dockLensHang",'n',0,0,.5,NULL,NULL},         // the lens stays lifted this long after the finger leaves (iOS 26: 0.18 s)
    // FIX131: iOS 26's light under a finger on the bar (WXGDockSystem.h): on / off, the spot's and the bar's strength (white).
    {"dockTouchGlow",'b',0,0,1,NULL,NULL},
    {"dockTouchGlowSpot",'n',.15,0,.5,NULL,NULL},
    {"dockTouchGlowBar",'n',.04,0,.2,NULL,NULL},
    {"dockMoveSpring",'b',0,0,1,NULL,NULL},        // the lens goes to a tab on the system's position spring
    {"dockMoveResponse",'n',.40,.2,.8,NULL,NULL},
    {"dockMoveDamping",'n',.86,.5,1.2,NULL,NULL},
    // FIX130 (user: "everything now uses what we took from iOS 26; the old refraction, material, borders and lens can
    // go"): one glass for every range, the system's as measured on iOS 26.6 (FIX124): each range its own values, the
    // other ranges starting from 其余玻璃's.
    //   refraction: within `band` of the outline (a share of the short side, at most bandMax pt) a point shows what
    //     lies depth x (1 - sqrt(1 - x^2)) further in, x = 1 - its depth / band (depth a share of the short side too);
    //     the outermost ring squeezes the picture at most `squeeze` times (0: unlimited, the curve as it is);
    //   blur: by the glass' short side (small: up to 48 pt; large: 90 pt; a straight line between and beyond);
    //   material: the backdrop's saturation and brightness, then white (light) / black (dark) over it at `veil`;
    //   shadow: opacity per appearance, softness (a Gaussian's sigma, pt) and how far down.
    {"glassBand",'n',.25,.02,.5,NULL,NULL},
    {"glassDepth",'n',.8,0,1,NULL,NULL},
    {"glassBandMax",'n',20,4,80,NULL,NULL},
    {"glassSqueeze",'n',3,0,20,NULL,NULL},
    {"glassDispersion",'n',0,0,3,NULL,NULL},
    {"glassBlurSmall",'n',1.8,0,10,NULL,NULL},
    {"glassBlurLarge",'n',5.5,0,20,NULL,NULL},
    {"glassVeil",'n',.65,0,1,NULL,NULL},
    {"darkGlassVeil",'n',.605,0,1,NULL,NULL},
    {"glassSaturation",'n',1.34,0,3,NULL,NULL},
    {"darkGlassSaturation",'n',1.67,0,3,NULL,NULL},
    {"glassBrightness",'n',-.03,-.3,.3,NULL,NULL},
    {"darkGlassBrightness",'n',.18,-.3,.3,NULL,NULL},
    {"glassShadow",'n',.25,0,.6,NULL,NULL},
    {"darkGlassShadow",'n',.05,0,.6,NULL,NULL},
    {"glassShadowBlur",'n',18,.5,40,NULL,NULL},
    {"glassShadowOffset",'n',8,-10,30,NULL,NULL},
    {"dockGlassBand",'n',.25,.02,.5,"glassBand",NULL},
    {"dockGlassDepth",'n',.8,0,1,"glassDepth",NULL},
    {"dockGlassBandMax",'n',20,4,80,"glassBandMax",NULL},
    {"dockGlassSqueeze",'n',3,0,20,"glassSqueeze",NULL},
    {"dockGlassDispersion",'n',0,0,3,"glassDispersion",NULL},
    {"dockGlassBlurSmall",'n',1.8,0,10,"glassBlurSmall",NULL},
    {"dockGlassBlurLarge",'n',5.5,0,20,"glassBlurLarge",NULL},
    {"dockGlassVeil",'n',.585,0,1,NULL,NULL},              // FIX131: the bar's own (WXGDockSystem.h), a little clearer than a button
    {"dockDarkGlassVeil",'n',.605,0,1,"darkGlassVeil",NULL},
    {"dockGlassSaturation",'n',1.34,0,3,"glassSaturation",NULL},
    {"dockDarkGlassSaturation",'n',1.67,0,3,"darkGlassSaturation",NULL},
    {"dockGlassBrightness",'n',0,-.3,.3,NULL,NULL},
    {"dockDarkGlassBrightness",'n',.18,-.3,.3,"darkGlassBrightness",NULL},
    {"dockGlassShadow",'n',.065,0,.6,NULL,NULL},           // FIX131: the bar's shadow, much fainter than a button's
    {"dockDarkGlassShadow",'n',.05,0,.6,"darkGlassShadow",NULL},
    {"dockGlassShadowBlur",'n',15,.5,40,NULL,NULL},
    {"dockGlassShadowOffset",'n',8,-10,30,"glassShadowOffset",NULL},
    {"bubbleGlassBand",'n',.25,.02,.5,"glassBand",NULL},
    {"bubbleGlassDepth",'n',.8,0,1,"glassDepth",NULL},
    {"bubbleGlassBandMax",'n',20,4,80,"glassBandMax",NULL},
    {"bubbleGlassSqueeze",'n',3,0,20,"glassSqueeze",NULL},
    {"bubbleGlassDispersion",'n',0,0,3,"glassDispersion",NULL},
    {"bubbleGlassBlurSmall",'n',1.8,0,10,"glassBlurSmall",NULL},
    {"bubbleGlassBlurLarge",'n',5.5,0,20,"glassBlurLarge",NULL},
    {"bubbleGlassVeil",'n',.65,0,1,"glassVeil",NULL},
    {"bubbleDarkGlassVeil",'n',.605,0,1,"darkGlassVeil",NULL},
    {"bubbleGlassSaturation",'n',1.34,0,3,"glassSaturation",NULL},
    {"bubbleDarkGlassSaturation",'n',1.67,0,3,"darkGlassSaturation",NULL},
    {"bubbleGlassBrightness",'n',-.03,-.3,.3,"glassBrightness",NULL},
    {"bubbleDarkGlassBrightness",'n',.18,-.3,.3,"darkGlassBrightness",NULL},
    {"bubbleGlassShadow",'n',0,0,.6,NULL,NULL},
    {"bubbleDarkGlassShadow",'n',0,0,.6,NULL,NULL},
    {"bubbleGlassShadowBlur",'n',18,.5,40,"glassShadowBlur",NULL},
    {"bubbleGlassShadowOffset",'n',8,-10,30,"glassShadowOffset",NULL},
    {"segmentGlassBand",'n',.25,.02,.5,"glassBand",NULL},
    {"segmentGlassDepth",'n',.8,0,1,"glassDepth",NULL},
    {"segmentGlassBandMax",'n',20,4,80,"glassBandMax",NULL},
    {"segmentGlassSqueeze",'n',3,0,20,"glassSqueeze",NULL},
    {"segmentGlassDispersion",'n',0,0,3,"glassDispersion",NULL},
    {"segmentGlassBlurSmall",'n',1.8,0,10,"glassBlurSmall",NULL},
    {"segmentGlassBlurLarge",'n',5.5,0,20,"glassBlurLarge",NULL},
    {"segmentGlassVeil",'n',.65,0,1,"glassVeil",NULL},
    {"segmentDarkGlassVeil",'n',.605,0,1,"darkGlassVeil",NULL},
    {"segmentGlassSaturation",'n',1.34,0,3,"glassSaturation",NULL},
    {"segmentDarkGlassSaturation",'n',1.67,0,3,"darkGlassSaturation",NULL},
    {"segmentGlassBrightness",'n',-.03,-.3,.3,"glassBrightness",NULL},
    {"segmentDarkGlassBrightness",'n',.18,-.3,.3,"darkGlassBrightness",NULL},
    {"segmentGlassShadow",'n',.25,0,.6,"glassShadow",NULL},
    {"segmentDarkGlassShadow",'n',.05,0,.6,"darkGlassShadow",NULL},
    {"segmentGlassShadowBlur",'n',18,.5,40,"glassShadowBlur",NULL},
    {"segmentGlassShadowOffset",'n',8,-10,30,"glassShadowOffset",NULL},
    {"cardGlassBand",'n',.25,.02,.5,"glassBand",NULL},
    {"cardGlassDepth",'n',.8,0,1,"glassDepth",NULL},
    {"cardGlassBandMax",'n',20,4,80,"glassBandMax",NULL},
    {"cardGlassSqueeze",'n',3,0,20,"glassSqueeze",NULL},
    {"cardGlassDispersion",'n',0,0,3,"glassDispersion",NULL},
    {"cardGlassBlurSmall",'n',1.8,0,10,"glassBlurSmall",NULL},
    {"cardGlassBlurLarge",'n',5.5,0,20,"glassBlurLarge",NULL},
    {"cardGlassVeil",'n',.65,0,1,"glassVeil",NULL},
    {"cardDarkGlassVeil",'n',.605,0,1,"darkGlassVeil",NULL},
    {"cardGlassSaturation",'n',1.34,0,3,"glassSaturation",NULL},
    {"cardDarkGlassSaturation",'n',1.67,0,3,"darkGlassSaturation",NULL},
    {"cardGlassBrightness",'n',-.03,-.3,.3,"glassBrightness",NULL},
    {"cardDarkGlassBrightness",'n',.18,-.3,.3,"darkGlassBrightness",NULL},
    {"cardGlassShadow",'n',0,0,.6,NULL,NULL},
    {"cardDarkGlassShadow",'n',0,0,.6,NULL,NULL},
    {"cardGlassShadowBlur",'n',18,.5,40,"glassShadowBlur",NULL},
    {"cardGlassShadowOffset",'n',8,-10,30,"glassShadowOffset",NULL},
    // The lens of the dock and of the segment bar (while held): the same curve, its band and depth shares of the
    // lens' height (the system tab bar's lens: 0.10 and, by the recording, 0.30), the colour split toward its corners.
    {"lensCurveBand",'n',.10,.02,.5,NULL,NULL},
    {"lensCurveDepth",'n',.30,0,.8,NULL,NULL},
    {"lensCurveDispersion",'n',1,0,3,NULL,NULL},
    {"lensCurveSqueeze",'n',0,0,20,NULL,NULL},
    {"segmentLensCurveBand",'n',.10,.02,.5,"lensCurveBand",NULL},
    {"segmentLensCurveDepth",'n',.30,0,.8,"lensCurveDepth",NULL},
    {"segmentLensCurveDispersion",'n',1,0,3,"lensCurveDispersion",NULL},
    {"segmentLensCurveSqueeze",'n',0,0,20,"lensCurveSqueeze",NULL},
    // FIX113 Z: iOS 27 rims per appearance: dark mode's own two highlights
    // (…Rim27DarkMode…), first taken from the light mode's (the ones above).
    {"rim27DarkModeHex",'h',0,0,0,"rim27Hex","#FFFFFFFF"},
    {"rim27DarkModeOpacity",'n',0.6,0,1,"rim27Opacity",NULL},
    {"rim27DarkModeWidth",'n',2.0,0.3,8,"rim27Width",NULL},
    {"rim27DarkModeFalloff",'n',1.6,0.5,4,"rim27Falloff",NULL},
    {"rim27DarkModeEndLevel",'n',0.15,0,1,"rim27EndLevel",NULL},
    {"rim27DarkModeAngle",'n',90,0,180,"rim27Angle",NULL},
    {"darkRim27DarkModeHex",'h',0,0,0,"darkRim27Hex","#FFFFFFFF"},
    {"darkRim27DarkModeOpacity",'n',0.35,0,1,"darkRim27Opacity",NULL},
    {"darkRim27DarkModeWidth",'n',2.0,0.3,8,"darkRim27Width",NULL},
    {"darkRim27DarkModeFalloff",'n',1.6,0.5,4,"darkRim27Falloff",NULL},
    {"darkRim27DarkModeEndLevel",'n',0.15,0,1,"darkRim27EndLevel",NULL},
    {"darkRim27DarkModeAngle",'n',0,0,180,"darkRim27Angle",NULL},
    {"rim27DarkModeSharpness",'n',2,0.5,6,"rim27Sharpness",NULL},
    {"darkRim27DarkModeSharpness",'n',2,0.5,6,"darkRim27Sharpness",NULL},
    {"dockRim27DarkModeHex",'h',0,0,0,"dockRim27Hex","#FFFFFFFF"},
    {"dockRim27DarkModeOpacity",'n',0.6,0,1,"dockRim27Opacity",NULL},
    {"dockRim27DarkModeWidth",'n',2.0,0.3,8,"dockRim27Width",NULL},
    {"dockRim27DarkModeFalloff",'n',1.6,0.5,4,"dockRim27Falloff",NULL},
    {"dockRim27DarkModeEndLevel",'n',0.15,0,1,"dockRim27EndLevel",NULL},
    {"dockRim27DarkModeAngle",'n',90,0,180,"dockRim27Angle",NULL},
    {"dockDarkRim27DarkModeHex",'h',0,0,0,"dockDarkRim27Hex","#FFFFFFFF"},
    {"dockDarkRim27DarkModeOpacity",'n',0.35,0,1,"dockDarkRim27Opacity",NULL},
    {"dockDarkRim27DarkModeWidth",'n',2.0,0.3,8,"dockDarkRim27Width",NULL},
    {"dockDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"dockDarkRim27Falloff",NULL},
    {"dockDarkRim27DarkModeEndLevel",'n',0.15,0,1,"dockDarkRim27EndLevel",NULL},
    {"dockDarkRim27DarkModeAngle",'n',0,0,180,"dockDarkRim27Angle",NULL},
    {"dockRim27DarkModeSharpness",'n',2,0.5,6,"dockRim27Sharpness",NULL},
    {"dockDarkRim27DarkModeSharpness",'n',2,0.5,6,"dockDarkRim27Sharpness",NULL},
    {"bubbleRim27DarkModeHex",'h',0,0,0,"bubbleRim27Hex","#FFFFFFFF"},
    {"bubbleRim27DarkModeOpacity",'n',0.6,0,1,"bubbleRim27Opacity",NULL},
    {"bubbleRim27DarkModeWidth",'n',2.0,0.3,8,"bubbleRim27Width",NULL},
    {"bubbleRim27DarkModeFalloff",'n',1.6,0.5,4,"bubbleRim27Falloff",NULL},
    {"bubbleRim27DarkModeEndLevel",'n',0.15,0,1,"bubbleRim27EndLevel",NULL},
    {"bubbleRim27DarkModeAngle",'n',90,0,180,"bubbleRim27Angle",NULL},
    {"bubbleDarkRim27DarkModeHex",'h',0,0,0,"bubbleDarkRim27Hex","#FFFFFFFF"},
    {"bubbleDarkRim27DarkModeOpacity",'n',0.35,0,1,"bubbleDarkRim27Opacity",NULL},
    {"bubbleDarkRim27DarkModeWidth",'n',2.0,0.3,8,"bubbleDarkRim27Width",NULL},
    {"bubbleDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"bubbleDarkRim27Falloff",NULL},
    {"bubbleDarkRim27DarkModeEndLevel",'n',0.15,0,1,"bubbleDarkRim27EndLevel",NULL},
    {"bubbleDarkRim27DarkModeAngle",'n',0,0,180,"bubbleDarkRim27Angle",NULL},
    {"bubbleRim27DarkModeSharpness",'n',2,0.5,6,"bubbleRim27Sharpness",NULL},
    {"bubbleDarkRim27DarkModeSharpness",'n',2,0.5,6,"bubbleDarkRim27Sharpness",NULL},
    {"segmentRim27DarkModeHex",'h',0,0,0,"segmentRim27Hex","#FFFFFFFF"},
    {"cardRim27DarkModeHex",'h',0,0,0,"cardRim27Hex","#FFFFFFFF"},
    {"segmentRim27DarkModeOpacity",'n',0.6,0,1,"segmentRim27Opacity",NULL},
    {"cardRim27DarkModeOpacity",'n',0.6,0,1,"cardRim27Opacity",NULL},
    {"segmentRim27DarkModeWidth",'n',2.0,0.3,8,"segmentRim27Width",NULL},
    {"cardRim27DarkModeWidth",'n',2.0,0.3,8,"cardRim27Width",NULL},
    {"segmentRim27DarkModeFalloff",'n',1.6,0.5,4,"segmentRim27Falloff",NULL},
    {"cardRim27DarkModeFalloff",'n',1.6,0.5,4,"cardRim27Falloff",NULL},
    {"segmentRim27DarkModeEndLevel",'n',0.15,0,1,"segmentRim27EndLevel",NULL},
    {"cardRim27DarkModeEndLevel",'n',0.15,0,1,"cardRim27EndLevel",NULL},
    {"segmentRim27DarkModeAngle",'n',90,0,180,"segmentRim27Angle",NULL},
    {"cardRim27DarkModeAngle",'n',90,0,180,"cardRim27Angle",NULL},
    {"segmentDarkRim27DarkModeHex",'h',0,0,0,"segmentDarkRim27Hex","#FFFFFFFF"},
    {"cardDarkRim27DarkModeHex",'h',0,0,0,"cardDarkRim27Hex","#FFFFFFFF"},
    {"segmentDarkRim27DarkModeOpacity",'n',0.35,0,1,"segmentDarkRim27Opacity",NULL},
    {"cardDarkRim27DarkModeOpacity",'n',0.35,0,1,"cardDarkRim27Opacity",NULL},
    {"segmentDarkRim27DarkModeWidth",'n',2.0,0.3,8,"segmentDarkRim27Width",NULL},
    {"cardDarkRim27DarkModeWidth",'n',2.0,0.3,8,"cardDarkRim27Width",NULL},
    {"segmentDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"segmentDarkRim27Falloff",NULL},
    {"cardDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"cardDarkRim27Falloff",NULL},
    {"segmentDarkRim27DarkModeEndLevel",'n',0.15,0,1,"segmentDarkRim27EndLevel",NULL},
    {"cardDarkRim27DarkModeEndLevel",'n',0.15,0,1,"cardDarkRim27EndLevel",NULL},
    {"segmentDarkRim27DarkModeAngle",'n',0,0,180,"segmentDarkRim27Angle",NULL},
    {"cardDarkRim27DarkModeAngle",'n',0,0,180,"cardDarkRim27Angle",NULL},
    {"segmentRim27DarkModeSharpness",'n',2,0.5,6,"segmentRim27Sharpness",NULL},
    {"cardRim27DarkModeSharpness",'n',2,0.5,6,"cardRim27Sharpness",NULL},
    {"segmentDarkRim27DarkModeSharpness",'n',2,0.5,6,"segmentDarkRim27Sharpness",NULL},
    {"cardDarkRim27DarkModeSharpness",'n',2,0.5,6,"cardDarkRim27Sharpness",NULL},
    {"lensGlassRim27DarkModeHex",'h',0,0,0,"lensGlassRim27Hex","#FFFFFFFF"},
    {"lensGlassRim27DarkModeOpacity",'n',0.6,0,1,"lensGlassRim27Opacity",NULL},
    {"lensGlassRim27DarkModeWidth",'n',2.0,0.3,8,"lensGlassRim27Width",NULL},
    {"lensGlassRim27DarkModeFalloff",'n',1.6,0.5,4,"lensGlassRim27Falloff",NULL},
    {"lensGlassRim27DarkModeEndLevel",'n',0.15,0,1,"lensGlassRim27EndLevel",NULL},
    {"lensGlassRim27DarkModeAngle",'n',90,0,180,"lensGlassRim27Angle",NULL},
    {"lensGlassDarkRim27DarkModeHex",'h',0,0,0,"lensGlassDarkRim27Hex","#FFFFFFFF"},
    {"lensGlassDarkRim27DarkModeOpacity",'n',0.35,0,1,"lensGlassDarkRim27Opacity",NULL},
    {"lensGlassDarkRim27DarkModeWidth",'n',2.0,0.3,8,"lensGlassDarkRim27Width",NULL},
    {"lensGlassDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"lensGlassDarkRim27Falloff",NULL},
    {"lensGlassDarkRim27DarkModeEndLevel",'n',0.15,0,1,"lensGlassDarkRim27EndLevel",NULL},
    {"lensGlassDarkRim27DarkModeAngle",'n',0,0,180,"lensGlassDarkRim27Angle",NULL},
    {"lensGlassRim27DarkModeSharpness",'n',2,0.5,6,"lensGlassRim27Sharpness",NULL},
    {"lensGlassDarkRim27DarkModeSharpness",'n',2,0.5,6,"lensGlassDarkRim27Sharpness",NULL},
    // FIX114 C (user: the segment bar's lens border set apart from the dock's):
    // 分组透镜, every key of the 透镜 range again, starting as it is set now.
    {"segmentLensGlassRimStyle",'n',3,2,3,"lensGlassRimStyle",NULL},
    {"segmentLensGlassRim27Hex",'h',0,0,0,"lensGlassRim27Hex","#FFFFFFFF"},
    {"segmentLensGlassRim27Opacity",'n',0.6,0,1,"lensGlassRim27Opacity",NULL},
    {"segmentLensGlassRim27Width",'n',2.0,0.3,8,"lensGlassRim27Width",NULL},
    {"segmentLensGlassRim27Falloff",'n',1.6,0.5,4,"lensGlassRim27Falloff",NULL},
    {"segmentLensGlassRim27EndLevel",'n',0.15,0,1,"lensGlassRim27EndLevel",NULL},
    {"segmentLensGlassRim27Angle",'n',90,0,180,"lensGlassRim27Angle",NULL},
    {"segmentLensGlassDarkRim27Hex",'h',0,0,0,"lensGlassDarkRim27Hex","#FFFFFFFF"},
    {"segmentLensGlassDarkRim27Opacity",'n',0.35,0,1,"lensGlassDarkRim27Opacity",NULL},
    {"segmentLensGlassDarkRim27Width",'n',2.0,0.3,8,"lensGlassDarkRim27Width",NULL},
    {"segmentLensGlassDarkRim27Falloff",'n',1.6,0.5,4,"lensGlassDarkRim27Falloff",NULL},
    {"segmentLensGlassDarkRim27EndLevel",'n',0.15,0,1,"lensGlassDarkRim27EndLevel",NULL},
    {"segmentLensGlassDarkRim27Angle",'n',0,0,180,"lensGlassDarkRim27Angle",NULL},
    {"segmentLensGlassRim27Sharpness",'n',2,0.5,6,"lensGlassRim27Sharpness",NULL},
    {"segmentLensGlassDarkRim27Sharpness",'n',2,0.5,6,"lensGlassDarkRim27Sharpness",NULL},
    {"segmentLensGlassRim27DarkModeHex",'h',0,0,0,"lensGlassRim27DarkModeHex","#FFFFFFFF"},
    {"segmentLensGlassRim27DarkModeOpacity",'n',0.6,0,1,"lensGlassRim27DarkModeOpacity",NULL},
    {"segmentLensGlassRim27DarkModeWidth",'n',2.0,0.3,8,"lensGlassRim27DarkModeWidth",NULL},
    {"segmentLensGlassRim27DarkModeFalloff",'n',1.6,0.5,4,"lensGlassRim27DarkModeFalloff",NULL},
    {"segmentLensGlassRim27DarkModeEndLevel",'n',0.15,0,1,"lensGlassRim27DarkModeEndLevel",NULL},
    {"segmentLensGlassRim27DarkModeAngle",'n',90,0,180,"lensGlassRim27DarkModeAngle",NULL},
    {"segmentLensGlassDarkRim27DarkModeHex",'h',0,0,0,"lensGlassDarkRim27DarkModeHex","#FFFFFFFF"},
    {"segmentLensGlassDarkRim27DarkModeOpacity",'n',0.35,0,1,"lensGlassDarkRim27DarkModeOpacity",NULL},
    {"segmentLensGlassDarkRim27DarkModeWidth",'n',2.0,0.3,8,"lensGlassDarkRim27DarkModeWidth",NULL},
    {"segmentLensGlassDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"lensGlassDarkRim27DarkModeFalloff",NULL},
    {"segmentLensGlassDarkRim27DarkModeEndLevel",'n',0.15,0,1,"lensGlassDarkRim27DarkModeEndLevel",NULL},
    {"segmentLensGlassDarkRim27DarkModeAngle",'n',0,0,180,"lensGlassDarkRim27DarkModeAngle",NULL},
    {"segmentLensGlassRim27DarkModeSharpness",'n',2,0.5,6,"lensGlassRim27DarkModeSharpness",NULL},
    {"segmentLensGlassDarkRim27DarkModeSharpness",'n',2,0.5,6,"lensGlassDarkRim27DarkModeSharpness",NULL},
    // FIX114 J (user: Telegram's glass takes its colour from what is behind
    // it, blur and saturation, no solid layer over it): each range's backdrop
    // saturation (TEST9's 1.05 by default, as before) and brightness (added
    // to every colour, 0 by default), before refraction.
    {"backdropSaturation",'n',1.05,0,3,NULL,NULL},
    {"backdropBrightness",'n',0,-.3,.3,NULL,NULL},
    // FIX115 S (user, 10-27 02:05: "边框自定义"): 视频号's range of 边框与渐隐 (the
    // video feed's capsules), as 分组透镜's keys; light and dark both start
    // from the other glass's dark-appearance values (the look those capsules
    // had: their rim always the dark one's), the style from the other glass's.
    {"finderGlassRimStyle",'n',3,2,3,"rimStyle",NULL},
    {"finderGlassRim27Hex",'h',0,0,0,"rim27DarkModeHex","#FFFFFFFF"},
    {"finderGlassRim27Opacity",'n',0.6,0,1,"rim27DarkModeOpacity",NULL},
    {"finderGlassRim27Width",'n',2.0,0.3,8,"rim27DarkModeWidth",NULL},
    {"finderGlassRim27Falloff",'n',1.6,0.5,4,"rim27DarkModeFalloff",NULL},
    {"finderGlassRim27EndLevel",'n',0.15,0,1,"rim27DarkModeEndLevel",NULL},
    {"finderGlassRim27Angle",'n',90,0,180,"rim27DarkModeAngle",NULL},
    {"finderGlassDarkRim27Hex",'h',0,0,0,"darkRim27DarkModeHex","#FFFFFFFF"},
    {"finderGlassDarkRim27Opacity",'n',0.35,0,1,"darkRim27DarkModeOpacity",NULL},
    {"finderGlassDarkRim27Width",'n',2.0,0.3,8,"darkRim27DarkModeWidth",NULL},
    {"finderGlassDarkRim27Falloff",'n',1.6,0.5,4,"darkRim27DarkModeFalloff",NULL},
    {"finderGlassDarkRim27EndLevel",'n',0.15,0,1,"darkRim27DarkModeEndLevel",NULL},
    {"finderGlassDarkRim27Angle",'n',0,0,180,"darkRim27DarkModeAngle",NULL},
    {"finderGlassRim27Sharpness",'n',2,0.5,6,"rim27DarkModeSharpness",NULL},
    {"finderGlassDarkRim27Sharpness",'n',2,0.5,6,"darkRim27DarkModeSharpness",NULL},
    {"finderGlassRim27DarkModeHex",'h',0,0,0,"rim27DarkModeHex","#FFFFFFFF"},
    {"finderGlassRim27DarkModeOpacity",'n',0.6,0,1,"rim27DarkModeOpacity",NULL},
    {"finderGlassRim27DarkModeWidth",'n',2.0,0.3,8,"rim27DarkModeWidth",NULL},
    {"finderGlassRim27DarkModeFalloff",'n',1.6,0.5,4,"rim27DarkModeFalloff",NULL},
    {"finderGlassRim27DarkModeEndLevel",'n',0.15,0,1,"rim27DarkModeEndLevel",NULL},
    {"finderGlassRim27DarkModeAngle",'n',90,0,180,"rim27DarkModeAngle",NULL},
    {"finderGlassDarkRim27DarkModeHex",'h',0,0,0,"darkRim27DarkModeHex","#FFFFFFFF"},
    {"finderGlassDarkRim27DarkModeOpacity",'n',0.35,0,1,"darkRim27DarkModeOpacity",NULL},
    {"finderGlassDarkRim27DarkModeWidth",'n',2.0,0.3,8,"darkRim27DarkModeWidth",NULL},
    {"finderGlassDarkRim27DarkModeFalloff",'n',1.6,0.5,4,"darkRim27DarkModeFalloff",NULL},
    {"finderGlassDarkRim27DarkModeEndLevel",'n',0.15,0,1,"darkRim27DarkModeEndLevel",NULL},
    {"finderGlassDarkRim27DarkModeAngle",'n',0,0,180,"darkRim27DarkModeAngle",NULL},
    {"finderGlassRim27DarkModeSharpness",'n',2,0.5,6,"rim27DarkModeSharpness",NULL},
    {"finderGlassDarkRim27DarkModeSharpness",'n',2,0.5,6,"darkRim27DarkModeSharpness",NULL},
    // FIX123 iOS 26 边框, the system's own recipe (WXGRim26.h, generated): per range (other /
    // dock / bubble / segment / card / lens / segment lens / 视频号) the rim's shape (as the
    // system's CASDFKeyFillHighlightEffect: height 1 pt, curvature 0.7, key and fill lights)
    // and, per appearance, its colour matrix (as the system's vibrantColorMatrix: dark dumped,
    // light fitted on the captures) and the faint line all round. Ranges inherit as the other
    // border keys (dark keys their parent range's dark ones). New key names: FIX122 F / G's
    // rim26... keys meant other things and are no longer read.
    {"edge26CaptureScale",'n',.5,.1,1,NULL,NULL},   // the copy of what lies under the rim: its resolution (of the screen's points)
    {"edge26Height",'n',1,0.3,4,NULL,NULL},
    {"edge26Curve",'n',0.7,0,1,NULL,NULL},
    {"edge26Angle",'n',45,0,180,NULL,NULL},
    {"edge26Key",'n',1.05,0,1.5,NULL,NULL},
    {"edge26Fill",'n',1,0,1.5,NULL,NULL},
    {"edge26Spread",'n',1,0.3,6,NULL,NULL},
    {"edge26Floor",'n',.30,0,1,NULL,NULL},   // FIX132: the lights stay on all round at this share (0: the system's)
    {"edge26Opacity",'n',1,0,1,NULL,NULL},
    {"darkEdge26Opacity",'n',1,0,1,NULL,NULL},
    {"edge26Gain",'n',0.174,0,4,NULL,NULL},
    {"darkEdge26Gain",'n',1.35,0,4,NULL,NULL},
    {"edge26Chroma",'n',1.51,0,8,NULL,NULL},
    {"darkEdge26Chroma",'n',3,0,8,NULL,NULL},
    {"edge26Lift",'n',0.847,0,1,NULL,NULL},
    {"darkEdge26Lift",'n',0.15,0,1,NULL,NULL},
    {"edge26Ring",'n',0.13,0,1,NULL,NULL},
    {"darkEdge26Ring",'n',0.04,0,1,NULL,NULL},
    {"dockEdge26Height",'n',1,0.3,4,"edge26Height",NULL},
    {"dockEdge26Curve",'n',0.7,0,1,"edge26Curve",NULL},
    {"dockEdge26Angle",'n',45,0,180,"edge26Angle",NULL},
    {"dockEdge26Key",'n',1.05,0,1.5,"edge26Key",NULL},
    {"dockEdge26Fill",'n',1,0,1.5,"edge26Fill",NULL},
    {"dockEdge26Spread",'n',1,0.3,6,"edge26Spread",NULL},
    {"dockEdge26Floor",'n',.30,0,1,"edge26Floor",NULL},
    {"dockEdge26Opacity",'n',1,0,1,"edge26Opacity",NULL},
    {"dockDarkEdge26Opacity",'n',1,0,1,"darkEdge26Opacity",NULL},
    {"dockEdge26Gain",'n',0.174,0,4,"edge26Gain",NULL},
    {"dockDarkEdge26Gain",'n',1.35,0,4,"darkEdge26Gain",NULL},
    {"dockEdge26Chroma",'n',1.51,0,8,"edge26Chroma",NULL},
    {"dockDarkEdge26Chroma",'n',3,0,8,"darkEdge26Chroma",NULL},
    {"dockEdge26Lift",'n',0.847,0,1,"edge26Lift",NULL},
    {"dockDarkEdge26Lift",'n',0.15,0,1,"darkEdge26Lift",NULL},
    {"dockEdge26Ring",'n',0.13,0,1,"edge26Ring",NULL},
    {"dockDarkEdge26Ring",'n',0.04,0,1,"darkEdge26Ring",NULL},
    {"bubbleEdge26Height",'n',1,0.3,4,"edge26Height",NULL},
    {"bubbleEdge26Curve",'n',0.7,0,1,"edge26Curve",NULL},
    {"bubbleEdge26Angle",'n',45,0,180,"edge26Angle",NULL},
    {"bubbleEdge26Key",'n',1.05,0,1.5,"edge26Key",NULL},
    {"bubbleEdge26Fill",'n',1,0,1.5,"edge26Fill",NULL},
    {"bubbleEdge26Spread",'n',1,0.3,6,"edge26Spread",NULL},
    {"bubbleEdge26Floor",'n',.30,0,1,"edge26Floor",NULL},
    {"bubbleEdge26Opacity",'n',1,0,1,"edge26Opacity",NULL},
    {"bubbleDarkEdge26Opacity",'n',1,0,1,"darkEdge26Opacity",NULL},
    {"bubbleEdge26Gain",'n',0.174,0,4,"edge26Gain",NULL},
    {"bubbleDarkEdge26Gain",'n',1.35,0,4,"darkEdge26Gain",NULL},
    {"bubbleEdge26Chroma",'n',1.51,0,8,"edge26Chroma",NULL},
    {"bubbleDarkEdge26Chroma",'n',3,0,8,"darkEdge26Chroma",NULL},
    {"bubbleEdge26Lift",'n',0.847,0,1,"edge26Lift",NULL},
    {"bubbleDarkEdge26Lift",'n',0.15,0,1,"darkEdge26Lift",NULL},
    {"bubbleEdge26Ring",'n',0.13,0,1,"edge26Ring",NULL},
    {"bubbleDarkEdge26Ring",'n',0.04,0,1,"darkEdge26Ring",NULL},
    {"segmentEdge26Height",'n',1,0.3,4,"dockEdge26Height",NULL},
    {"segmentEdge26Curve",'n',0.7,0,1,"dockEdge26Curve",NULL},
    {"segmentEdge26Angle",'n',45,0,180,"dockEdge26Angle",NULL},
    {"segmentEdge26Key",'n',1.05,0,1.5,"dockEdge26Key",NULL},
    {"segmentEdge26Fill",'n',1,0,1.5,"dockEdge26Fill",NULL},
    {"segmentEdge26Spread",'n',1,0.3,6,"dockEdge26Spread",NULL},
    {"segmentEdge26Floor",'n',.30,0,1,"dockEdge26Floor",NULL},
    {"segmentEdge26Opacity",'n',1,0,1,"dockEdge26Opacity",NULL},
    {"segmentDarkEdge26Opacity",'n',1,0,1,"dockDarkEdge26Opacity",NULL},
    {"segmentEdge26Gain",'n',0.174,0,4,"dockEdge26Gain",NULL},
    {"segmentDarkEdge26Gain",'n',1.35,0,4,"dockDarkEdge26Gain",NULL},
    {"segmentEdge26Chroma",'n',1.51,0,8,"dockEdge26Chroma",NULL},
    {"segmentDarkEdge26Chroma",'n',3,0,8,"dockDarkEdge26Chroma",NULL},
    {"segmentEdge26Lift",'n',0.847,0,1,"dockEdge26Lift",NULL},
    {"segmentDarkEdge26Lift",'n',0.15,0,1,"dockDarkEdge26Lift",NULL},
    {"segmentEdge26Ring",'n',0.13,0,1,"dockEdge26Ring",NULL},
    {"segmentDarkEdge26Ring",'n',0.04,0,1,"dockDarkEdge26Ring",NULL},
    {"cardEdge26Height",'n',1,0.3,4,"edge26Height",NULL},
    {"cardEdge26Curve",'n',0.7,0,1,"edge26Curve",NULL},
    {"cardEdge26Angle",'n',45,0,180,"edge26Angle",NULL},
    {"cardEdge26Key",'n',1.05,0,1.5,"edge26Key",NULL},
    {"cardEdge26Fill",'n',1,0,1.5,"edge26Fill",NULL},
    {"cardEdge26Spread",'n',1,0.3,6,"edge26Spread",NULL},
    {"cardEdge26Floor",'n',.30,0,1,"edge26Floor",NULL},
    {"cardEdge26Opacity",'n',1,0,1,"edge26Opacity",NULL},
    {"cardDarkEdge26Opacity",'n',1,0,1,"darkEdge26Opacity",NULL},
    {"cardEdge26Gain",'n',0.174,0,4,"edge26Gain",NULL},
    {"cardDarkEdge26Gain",'n',1.35,0,4,"darkEdge26Gain",NULL},
    {"cardEdge26Chroma",'n',1.51,0,8,"edge26Chroma",NULL},
    {"cardDarkEdge26Chroma",'n',3,0,8,"darkEdge26Chroma",NULL},
    {"cardEdge26Lift",'n',0.847,0,1,"edge26Lift",NULL},
    {"cardDarkEdge26Lift",'n',0.15,0,1,"darkEdge26Lift",NULL},
    {"cardEdge26Ring",'n',0.13,0,1,"edge26Ring",NULL},
    {"cardDarkEdge26Ring",'n',0.04,0,1,"darkEdge26Ring",NULL},
    {"lensGlassEdge26Height",'n',1,0.3,4,"dockEdge26Height",NULL},
    {"lensGlassEdge26Curve",'n',0.7,0,1,"dockEdge26Curve",NULL},
    {"lensGlassEdge26Angle",'n',45,0,180,"dockEdge26Angle",NULL},
    {"lensGlassEdge26Key",'n',1.05,0,1.5,"dockEdge26Key",NULL},
    {"lensGlassEdge26Fill",'n',1,0,1.5,"dockEdge26Fill",NULL},
    {"lensGlassEdge26Spread",'n',1,0.3,6,"dockEdge26Spread",NULL},
    {"lensGlassEdge26Floor",'n',.30,0,1,"dockEdge26Floor",NULL},
    {"lensGlassEdge26Opacity",'n',1,0,1,"dockEdge26Opacity",NULL},
    {"lensGlassDarkEdge26Opacity",'n',1,0,1,"dockDarkEdge26Opacity",NULL},
    {"lensGlassEdge26Gain",'n',0.174,0,4,"dockEdge26Gain",NULL},
    {"lensGlassDarkEdge26Gain",'n',1.35,0,4,"dockDarkEdge26Gain",NULL},
    {"lensGlassEdge26Chroma",'n',1.51,0,8,"dockEdge26Chroma",NULL},
    {"lensGlassDarkEdge26Chroma",'n',3,0,8,"dockDarkEdge26Chroma",NULL},
    {"lensGlassEdge26Lift",'n',0.847,0,1,"dockEdge26Lift",NULL},
    {"lensGlassDarkEdge26Lift",'n',0.15,0,1,"dockDarkEdge26Lift",NULL},
    {"lensGlassEdge26Ring",'n',0.13,0,1,"dockEdge26Ring",NULL},
    {"lensGlassDarkEdge26Ring",'n',0.04,0,1,"dockDarkEdge26Ring",NULL},
    {"segmentLensGlassEdge26Height",'n',1,0.3,4,"lensGlassEdge26Height",NULL},
    {"segmentLensGlassEdge26Curve",'n',0.7,0,1,"lensGlassEdge26Curve",NULL},
    {"segmentLensGlassEdge26Angle",'n',45,0,180,"lensGlassEdge26Angle",NULL},
    {"segmentLensGlassEdge26Key",'n',1.05,0,1.5,"lensGlassEdge26Key",NULL},
    {"segmentLensGlassEdge26Fill",'n',1,0,1.5,"lensGlassEdge26Fill",NULL},
    {"segmentLensGlassEdge26Spread",'n',1,0.3,6,"lensGlassEdge26Spread",NULL},
    {"segmentLensGlassEdge26Floor",'n',.30,0,1,"lensGlassEdge26Floor",NULL},
    {"segmentLensGlassEdge26Opacity",'n',1,0,1,"lensGlassEdge26Opacity",NULL},
    {"segmentLensGlassDarkEdge26Opacity",'n',1,0,1,"lensGlassDarkEdge26Opacity",NULL},
    {"segmentLensGlassEdge26Gain",'n',0.174,0,4,"lensGlassEdge26Gain",NULL},
    {"segmentLensGlassDarkEdge26Gain",'n',1.35,0,4,"lensGlassDarkEdge26Gain",NULL},
    {"segmentLensGlassEdge26Chroma",'n',1.51,0,8,"lensGlassEdge26Chroma",NULL},
    {"segmentLensGlassDarkEdge26Chroma",'n',3,0,8,"lensGlassDarkEdge26Chroma",NULL},
    {"segmentLensGlassEdge26Lift",'n',0.847,0,1,"lensGlassEdge26Lift",NULL},
    {"segmentLensGlassDarkEdge26Lift",'n',0.15,0,1,"lensGlassDarkEdge26Lift",NULL},
    {"segmentLensGlassEdge26Ring",'n',0.13,0,1,"lensGlassEdge26Ring",NULL},
    {"segmentLensGlassDarkEdge26Ring",'n',0.04,0,1,"lensGlassDarkEdge26Ring",NULL},
    {"finderGlassEdge26Height",'n',1,0.3,4,"edge26Height",NULL},
    {"finderGlassEdge26Curve",'n',0.7,0,1,"edge26Curve",NULL},
    {"finderGlassEdge26Angle",'n',45,0,180,"edge26Angle",NULL},
    {"finderGlassEdge26Key",'n',1.05,0,1.5,"edge26Key",NULL},
    {"finderGlassEdge26Fill",'n',1,0,1.5,"edge26Fill",NULL},
    {"finderGlassEdge26Spread",'n',1,0.3,6,"edge26Spread",NULL},
    {"finderGlassEdge26Floor",'n',.30,0,1,"edge26Floor",NULL},
    {"finderGlassEdge26Opacity",'n',1,0,1,"darkEdge26Opacity",NULL},   // 视频号: over video, both appearances start as the other glass's dark one (as its other border keys)
    {"finderGlassDarkEdge26Opacity",'n',1,0,1,"darkEdge26Opacity",NULL},
    {"finderGlassEdge26Gain",'n',1.35,0,4,"darkEdge26Gain",NULL},
    {"finderGlassDarkEdge26Gain",'n',1.35,0,4,"darkEdge26Gain",NULL},
    {"finderGlassEdge26Chroma",'n',3,0,8,"darkEdge26Chroma",NULL},
    {"finderGlassDarkEdge26Chroma",'n',3,0,8,"darkEdge26Chroma",NULL},
    {"finderGlassEdge26Lift",'n',0.15,0,1,"darkEdge26Lift",NULL},
    {"finderGlassDarkEdge26Lift",'n',0.15,0,1,"darkEdge26Lift",NULL},
    {"finderGlassEdge26Ring",'n',0.04,0,1,"darkEdge26Ring",NULL},
    {"finderGlassDarkEdge26Ring",'n',0.04,0,1,"darkEdge26Ring",NULL},
};
static const size_t WXGExtraCount=sizeof WXGExtraSpecs/sizeof *WXGExtraSpecs;
static NSDictionary<NSString *,NSNumber *> *WXGExtraIndex(void) {
    static NSDictionary *index;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableDictionary *d=[NSMutableDictionary dictionaryWithCapacity:WXGExtraCount];
        for(size_t i=0;i<WXGExtraCount;i++)d[@(WXGExtraSpecs[i].key)]=@(i);
        index=d;
    });
    return index;
}
static NSArray<NSString *> *WXGExtraKeys(void) {
    static NSArray *keys;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableArray *a=[NSMutableArray arrayWithCapacity:WXGExtraCount];
        for(size_t i=0;i<WXGExtraCount;i++)[a addObject:@(WXGExtraSpecs[i].key)];
        keys=a;
    });
    return keys;
}
/* The name of a scoped key: stem "RimSampleOpacity" -> rimSampleOpacity,
   darkRimSampleOpacity, dockRimSampleOpacity, dockDarkRimSampleOpacity,
   bubbleRimSampleOpacity, bubbleDarkRimSampleOpacity. */
static NSString *WXGScopedKey(WXGGlassScope scope,BOOL dark,NSString *stem) {
    if(scope==WXGGlassScopeDock)return [(dark?@"dockDark":@"dock") stringByAppendingString:stem];
    if(scope==WXGGlassScopeBubble)return [(dark?@"bubbleDark":@"bubble") stringByAppendingString:stem];
    if(scope==WXGGlassScopeSegment)return [(dark?@"segmentDark":@"segment") stringByAppendingString:stem];   // FIX113 O
    if(scope==WXGGlassScopeCard)return [(dark?@"cardDark":@"card") stringByAppendingString:stem];
    if(scope==WXGGlassScopeLens)return [(dark?@"lensGlassDark":@"lensGlass") stringByAppendingString:stem];   // FIX113 X
    if(scope==WXGGlassScopeSegmentLens)return [(dark?@"segmentLensGlassDark":@"segmentLensGlass") stringByAppendingString:stem];   // FIX114 C
    if(scope==WXGGlassScopeFinder)return [(dark?@"finderGlassDark":@"finderGlass") stringByAppendingString:stem];   // FIX115 S
    if(dark)return [@"dark" stringByAppendingString:stem];
    return [[stem substringToIndex:1].lowercaseString stringByAppendingString:[stem substringFromIndex:1]];
}
@interface WXGConfig () {
    NSMutableDictionary<NSString *,id> *_extra;
    NSDictionary *_defaultsOverride;   // FIX114 G: a build's defaults other than this build's (initWithBuildDefaults:)
}
@end

/* FIX130: the settings of the builds before, read once more under their new names. Only what was the system's
   already carries over: 其余玻璃's refraction, blur, material and shadow where their iOS 26 switches were on, and the
   lens' band, depth and colour split where its curve was on (FIX122 - FIX129). Everything else of the old glass (its
   band refraction, veil colours, the two old border styles ...) is not read any more: those ranges start from the
   system's values. */
NSDictionary *WXGRenamedSettings(NSDictionary *stored) {
    if(!stored.count || stored[@"glassBand"])return stored;   // nothing stored, or already this build's
    NSMutableDictionary *d=[stored mutableCopy];
    BOOL (^on)(NSString *)=^BOOL(NSString *key){id v=stored[key];return [v isKindOfClass:NSNumber.class] && [v doubleValue]>.5;};
    void (^move)(NSString *,NSString *)=^(NSString *to,NSString *from){id v=stored[from];if([v isKindOfClass:NSNumber.class] && !d[to])d[to]=v;};
    if(on(@"kyantOtherOn")) {
        move(@"glassBand",@"kyantOtherHeight");move(@"glassDepth",@"kyantOtherAmount");move(@"glassBandMax",@"kyantOtherMaxHeight");move(@"glassDispersion",@"kyantOtherDispersion");
        if(on(@"kyantOtherRimFine"))d[@"glassSqueeze"]=@0;else move(@"glassSqueeze",@"kyantOtherRimMax");
    }
    if(on(@"ios26BlurOn")){move(@"glassBlurSmall",@"ios26BlurSmall");move(@"glassBlurLarge",@"ios26BlurLarge");}
    if(on(@"ios26MaterialOn")) {
        move(@"glassVeil",@"ios26VeilOpacity");move(@"darkGlassVeil",@"darkIos26VeilOpacity");move(@"glassSaturation",@"ios26Saturation");
        move(@"darkGlassSaturation",@"darkIos26Saturation");move(@"glassBrightness",@"ios26Brightness");move(@"darkGlassBrightness",@"darkIos26Brightness");
    }
    if(on(@"ios26ShadowOn")) {
        move(@"glassShadow",@"ios26ShadowOpacity");move(@"darkGlassShadow",@"darkIos26ShadowOpacity");move(@"glassShadowBlur",@"ios26ShadowBlur");move(@"glassShadowOffset",@"ios26ShadowOffset");
    }
    if(on(@"lensKyantOn")) {
        move(@"lensCurveBand",@"lensKyantHeight");move(@"lensCurveDepth",@"lensKyantAmount");move(@"lensCurveDispersion",@"lensKyantDispersion");
        if(stored[@"lensKyantRimFine"] && !on(@"lensKyantRimFine"))move(@"lensCurveSqueeze",@"lensKyantRimMax");
    }
    if(on(@"segmentLensKyantOn")) {
        move(@"segmentLensCurveBand",@"segmentLensKyantHeight");move(@"segmentLensCurveDepth",@"segmentLensKyantAmount");move(@"segmentLensCurveDispersion",@"segmentLensKyantDispersion");
        if(stored[@"segmentLensKyantRimFine"] && !on(@"segmentLensKyantRimFine"))move(@"segmentLensCurveSqueeze",@"segmentLensKyantRimMax");
    }
    return d;
}
@implementation WXGConfig
+ (instancetype)shared { static WXGConfig *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [self new]; [value adoptBuildDefaults]; }); return value; }
// FIX114 G: a fresh install's values had `defaults` been the build's (not
// read from or written to the phone's settings).
- (instancetype)initWithBuildDefaults:(NSDictionary *)defaults {
    if((self=[super init])){_defaultsOverride=defaults?:@{};[self loadDefaults];[self normalize];_defaultsOverride=nil;}
    return self;
}
// FIX114 G (user, 10-23: “settings nobody changed take these values; ones
// already customised are not overwritten”): once per new set of defaults
// (WXGBuildDefaultsStamp), each setting on this phone still equal to the
// previous build's default (WXG_PREVIOUS_DEFAULT_OPTICS_JSON over the
// built-in ones) moves to this build's; any other value is the person's and
// stays. Written straight to the settings (no change notification: this
// runs while the shared configuration is being made).
// FIX114 G (review): a range's rim style stays when any of that range's
// rim settings is the person's (a glow tuned under the old style would be
// hidden by switching the style alone). The range: the style key's prefix
// (none: rim… / darkRim…), keys after it naming a rim; the segment bar's
// lens has its own range.
static BOOL WXGRimGroupTouched(NSString *style,NSSet<NSString *> *custom) {
    NSString *prefix=[style isEqualToString:@"rimStyle"]?@"":[style substringToIndex:style.length-@"RimStyle".length];
    for(NSString *key in custom) {
        if([key isEqualToString:style])continue;
        if(!prefix.length){if([key hasPrefix:@"rim"] || [key hasPrefix:@"darkRim"] || [key hasPrefix:@"edge26"] || [key hasPrefix:@"darkEdge26"])return YES;continue;}   // FIX123: the iOS 26 rim's keys too
        if(![key hasPrefix:prefix] || ([prefix isEqualToString:@"segment"] && [key hasPrefix:@"segmentLensGlass"]))continue;
        NSString *rest=[key substringFromIndex:prefix.length];
        if([rest rangeOfString:@"Rim"].location!=NSNotFound || [rest rangeOfString:@"Edge26"].location!=NSNotFound)return YES;
    }
    return NO;
}
- (void)adoptBuildDefaults {
    NSUserDefaults *suite=[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"];
    NSString *stamp=WXGBuildDefaultsStamp();
    if(!stamp.length || [[suite stringForKey:@"defaultsStamp.config"] isEqualToString:stamp])return;
    NSDictionary *stored=nil,*previous=WXGPreviousBuildDefaultSection(@"config");
    NSUInteger moved=0,kept=0;NSString *failure=nil;
    // FIX114 G (review): at WeChat's launch, inside +shared: nothing here may
    // throw out (the stamp is written whatever happens, so never twice).
    @try {
        stored=[suite dictionaryForKey:@"optics.test4"];
        if(stored.count && previous.count) {
            NSArray *keys=self.keys;
            NSDictionary *mine=[self dictionaryWithValuesForKeys:keys];
            NSDictionary *old=[[[WXGConfig alloc] initWithBuildDefaults:previous] dictionaryWithValuesForKeys:keys];
            NSDictionary *now=[[[WXGConfig alloc] initWithBuildDefaults:WXGBuildDefaultOptics()] dictionaryWithValuesForKeys:keys];
            // Markers of one-time moves (not settings): never adopted.
            NSSet *skip=[NSSet setWithArray:@[@"enabled",@"dockTitleWeightNative",@"segmentDockLook",@"dockTapSmartHoldOff"]];
            NSMutableSet<NSString *> *custom=[NSMutableSet set];
            for(NSString *key in keys)if(!WXGSameSettingValue(mine[key],old[key]))[custom addObject:key];
            NSMutableDictionary *adopt=[NSMutableDictionary dictionary];
            for(NSString *key in keys) {
                id value=now[key];
                if([skip containsObject:key] || !value || value==NSNull.null || WXGSameSettingValue(old[key],value))continue;
                BOOL style=[key hasSuffix:@"RimStyle"] || [key isEqualToString:@"rimStyle"];
                if([custom containsObject:key] || (style && WXGRimGroupTouched(key,custom)))++kept;
                else adopt[key]=value;
            }
            for(NSString *key in adopt)[self setValue:adopt[key] forKey:key];
            moved=adopt.count;
            if(moved){[self normalize];[suite setObject:[self dictionaryWithValuesForKeys:keys] forKey:@"optics.test4"];}
        }
    }@catch(NSException *error) {
        failure=error.reason?:error.name?:@"exception";
    }@finally {
        [suite setObject:stamp forKey:@"defaultsStamp.config"];
    }
    WXGNoteDefaultsAdoption(@"config",@{@"stored":@(stored.count>0),@"moved":@(moved),@"kept":@(kept),@"error":failure?:@""});
}
- (void)loadDefaults {
    _enabled=YES; _haptics=YES;
    _widthFraction=0.92; _height=68; _lift=12;
    _captureFPS=120; _captureBudget=35; _motionPrediction=YES; _renderMode=2; _syncBlurScale=1; _samplerSource=0; _syncPresent=YES;
    _syncMeshRefraction=YES; _syncDispersion=YES; _syncCaptureScale=0; _performanceMode=NO;
    // The dock's lens: its own blur, zoom and growth, the bar under it; the icons and titles drawn in it (the
    // overlay's own band: lensRefraction, lensEdgeWidth, lensTopEdgeRatio and lensEdgeSharpness are what the
    // table's lensIcon… keys start from, lensDispersion their colour split).
    _lensBlur=0; _lensZoom=1.20; _lensGrowth=1.28; _bodyPinch=.18; _barGrowth=1.025; _endWrap=4;
    _lensRefraction=1.15; _lensDispersion=.95; _lensEdgeWidth=10; _lensTopEdgeRatio=1; _lensEdgeSharpness=3;
    _selectionInset=6; _selectionOpacity=.30; _pressedOpacity=.05; _selectionHex=@"#71879EFF"; _darkSelectionHex=@"#71879EFF";
    _useWeChatIcons=YES; _messageMenuCornerRadius=18; _dockSwitchTiming=0;
    _dockSearchGap=12; _dockSearchHeightRatio=.82; _dockSearchWidthFraction=.94;
    _pressStretch=YES; _pressStretchDistance=16; _pressStretchAmount=.6; _dockEndStretch=YES; _dockEndStretchDistance=18;   // FIX68
    _pressStretchCapsule=.5; _pressStretchMax=8; _pressStretchFollow=.3; _pressStretchNative=YES;   // FIX80
    // FIX82: liquid bubbles, WeChat's (and MixBubble's) bubble colours.
    _bubbleOutgoingHex=@"#95EC69CC"; _bubbleIncomingHex=@"#FFFFFFCC"; _darkBubbleOutgoingHex=@"#95EC69CC"; _darkBubbleIncomingHex=@"#2C2C2CCC";
    // FIX64: WeChatFade's own defaults (96 / 112 pt), the blur over the same bands.
    _edgeChatFadeTop=96; _edgeChatFadeBottom=112; _edgeChatBlurTop=96; _edgeChatBlurBottom=112; _edgeChatBlurTopRadius=3; _edgeChatBlurBottomRadius=3;
    _edgeOtherFadeTop=96; _edgeOtherFadeBottom=112; _edgeOtherBlurTop=96; _edgeOtherBlurBottom=112; _edgeOtherBlurTopRadius=3; _edgeOtherBlurBottomRadius=3;
    [self loadExtraDefaults];
    [self applyBuildDefaults];
}
// FIX85: the table's keys from their defaults; an inheriting key from its
// source's value now (table order: a source may itself be a table key).
- (void)loadExtraDefaults {
    _extra=[NSMutableDictionary dictionaryWithCapacity:WXGExtraCount];
    for(size_t i=0;i<WXGExtraCount;i++)[self inheritExtra:i];
}
- (void)inheritExtra:(size_t)i {
    const WXGExtraSpec *spec=&WXGExtraSpecs[i];NSString *key=@(spec->key);
    id value=nil;
    if(spec->inherit) {
        @try {value=[self valueForKey:@(spec->inherit)];} @catch(__unused NSException *error) {value=nil;}
    }
    if(spec->kind=='h'){if(![value isKindOfClass:NSString.class])value=@(spec->hex?:"#FFFFFFFF");}
    else if(![value isKindOfClass:NSNumber.class])value=@(spec->def);
    _extra[key]=value;
}
// FIX85: after values from outside (an import, a build's defaults): an
// inheriting table key that was not among them starts again from its source.
// FIX86: only when its source came with them (or was itself re-derived
// here); the rim style only from an imported colour switch. A partial import
// leaves every other key as it is (FIX85 re-derived them all: an import
// without the rim styles reset the three ranges' styles to 普通 / 取自背景).
- (void)reinheritExtrasMissingFrom:(NSDictionary *)values {
    NSMutableSet<NSString *> *changed=[NSMutableSet setWithArray:values.allKeys];
    for(size_t i=0;i<WXGExtraCount;i++) {
        const WXGExtraSpec *spec=&WXGExtraSpecs[i];NSString *key=@(spec->key);
        if(values[key])continue;
        BOOL rederive=spec->inherit && [changed containsObject:@(spec->inherit)];
        if(rederive){[self inheritExtra:i];[changed addObject:key];}
    }
}
- (id)valueForUndefinedKey:(NSString *)key {
    if(WXGExtraIndex()[key])return _extra[key];
    return [super valueForUndefinedKey:key];
}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    NSNumber *index=WXGExtraIndex()[key];
    if(!index){[super setValue:value forUndefinedKey:key];return;}
    char kind=WXGExtraSpecs[index.unsignedIntegerValue].kind;
    if(kind=='h'?[value isKindOfClass:NSString.class]:[value isKindOfClass:NSNumber.class])_extra[key]=value;
}
- (double)extraNumber:(NSString *)key {id v=_extra[key];return [v isKindOfClass:NSNumber.class]?[v doubleValue]:0;}
- (NSString *)extraHex:(NSString *)key {id v=_extra[key];return [v isKindOfClass:NSString.class]?v:@"#FFFFFFFF";}
// FIX59: this build's own defaults (WXGBuildProfile.h, e.g. the author's tuned
// values), over the built-in ones. Empty: none.
- (void)applyBuildDefaults {
    NSDictionary *defaults=_defaultsOverride?:WXGBuildDefaultOptics();
    for(NSString *key in self.keys) {
        id value=defaults[key];BOOL color=[key hasSuffix:@"Hex"];
        if([key isEqual:@"enabled"])continue;
        if(color?[value isKindOfClass:NSString.class]:([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])))[self setValue:value forKey:key];
    }
    if(defaults.count)[self reinheritExtrasMissingFrom:defaults];   // FIX85
    [self nativeDockTitleWeight];   // FIX114 B (review): a build's defaults made with the old default (medium) too
}
// FIX114 B: the dock's titles regular (WeChat's own), from the old default
// medium, once (the marker set).
- (void)nativeDockTitleWeight {
    if([_extra[@"dockTitleWeightNative"] doubleValue]>.5)return;
    if(lround([_extra[@"dockTitleWeight"] doubleValue])==2)_extra[@"dockTitleWeight"]=@1;
    _extra[@"dockTitleWeightNative"]=@1;
}
- (NSArray *)baseKeys { return @[@"lensBlur",@"lensRefraction",@"lensDispersion",@"lensEdgeWidth",@"enabled",@"haptics",@"widthFraction",@"height",@"lift",@"captureFPS",@"captureBudget",@"motionPrediction",@"renderMode",@"syncBlurScale",@"samplerSource",@"syncPresent",@"syncMeshRefraction",@"syncDispersion",@"syncCaptureScale",@"lensTopEdgeRatio",@"lensEdgeSharpness",@"lensZoom",@"lensGrowth",@"bodyPinch",@"selectionInset",@"selectionOpacity",@"pressedOpacity",@"selectionHex",@"darkSelectionHex",@"useWeChatIcons",@"barGrowth",@"endWrap",@"messageMenuCornerRadius",@"dockSwitchTiming",@"performanceMode",
    @"dockSearchGap",@"dockSearchHeightRatio",@"dockSearchWidthFraction",
    @"edgeChatFadeTop",@"edgeChatFadeBottom",@"edgeChatBlurTop",@"edgeChatBlurBottom",@"edgeChatBlurTopRadius",@"edgeChatBlurBottomRadius",
    @"edgeOtherFadeTop",@"edgeOtherFadeBottom",@"edgeOtherBlurTop",@"edgeOtherBlurBottom",@"edgeOtherBlurTopRadius",@"edgeOtherBlurBottomRadius",
    @"pressStretch",@"pressStretchDistance",@"pressStretchAmount",@"pressStretchCapsule",@"pressStretchMax",@"pressStretchFollow",@"bubbleOutgoingHex",@"bubbleIncomingHex",@"darkBubbleOutgoingHex",@"darkBubbleIncomingHex",@"dockEndStretch",@"dockEndStretchDistance",
    @"pressStretchNative"]; }
- (NSArray *)keys {
    static NSArray *all;static dispatch_once_t once;
    dispatch_once(&once,^{all=[self.baseKeys arrayByAddingObjectsFromArray:WXGExtraKeys()];});
    return all;
}
- (instancetype)init {
    if((self=[super init])) {
        [self loadDefaults];
        // What the settings pages stored (a build before FIX130: under this build's names, WXGRenamedSettings).
        NSDictionary *local=WXGRenamedSettings([[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] dictionaryForKey:@"optics.test4"]);
        for(NSString *key in self.keys) {
            id value=local[key];BOOL color=[key hasSuffix:@"Hex"];
            if(color?[value isKindOfClass:NSString.class]:[value isKindOfClass:NSNumber.class])[self setValue:value forKey:key];
        }
        // FIX85: a table key never stored starts from its source's value as loaded above (the user's own).
        for(size_t i=0;i<WXGExtraCount;i++) {
            id stored=local[@(WXGExtraSpecs[i].key)];
            BOOL valid=WXGExtraSpecs[i].kind=='h'?[stored isKindOfClass:NSString.class]:[stored isKindOfClass:NSNumber.class];
            if(!valid)[self inheritExtra:i];
        }
        // FIX114 B (user: the dock's titles do not look like WeChat's): WeChat's
        // own tab titles are regular (diagnostics: .SFUI-Regular 10 pt, weight
        // 0); a configuration still at the old default (medium) moves once.
        if(local && [local[@"dockTitleWeightNative"] doubleValue]<.5){_extra[@"dockTitleWeightNative"]=@0;[self nativeDockTitleWeight];}   // (the defaults loaded above had set the marker)
        // FIX119 F: E's 会卡的标签等透镜落下再切 (on) goes off once; set again by hand it stays (the marker is stored then).
        if(local && ![local[@"dockTapSmartHoldOff"] isKindOfClass:NSNumber.class]){_extra[@"dockTapSmartHold"]=@0;_extra[@"dockTapSmartHoldOff"]=@1;}
        // FIX115 O (user, 21:58: "别从8开始万一有人喜欢更灵敏"; review: N saved
        // every key, so a phone that ran N has 8 stored whether N moved it there,
        // it was N's default or it was set by hand; N's marker tells those): 8
        // under N's marker goes back to 3, once.
        if(local && ![local[@"pressStretchRatioBack"] isKindOfClass:NSNumber.class]) {
            NSNumber *ratio=local[@"pressStretchRatio"];
            if([local[@"pressStretchRatioMoved"] isKindOfClass:NSNumber.class] && [ratio isKindOfClass:NSNumber.class] && fabs(ratio.doubleValue-8)<.001)
                _extra[@"pressStretchRatio"]=@3;
            _extra[@"pressStretchRatioBack"]=@1;
        }
        if(!local)[self loadDefaults];   // FIX81: a fresh install is exactly 恢复默认 (this build's defaults as they are)
        [self normalize];
    } return self;
}
- (void)normalize {
    // FIX115 I (user, 10-26 09:54: with Telegram's icons the accent colour at
    // 100 %): with them on, the stored accent is made opaque (the default's
    // was transparent: the selected tab would have been invisible).
    if([_extra[@"dockTelegramIcons"] doubleValue]>.5) {
        NSString *accent=WXGNormalizeHex(_extra[@"dockAccentHex"]);
        if(accent.length==9 && ![[accent substringFromIndex:7] isEqualToString:@"FF"])_extra[@"dockAccentHex"]=[[accent substringToIndex:7] stringByAppendingString:@"FF"];
    }
    if (!isfinite(_widthFraction)) _widthFraction=.92;
    if (!isfinite(_height)) _height=68;
    if (!isfinite(_lift)) _lift=12;
    _widthFraction=WXGClamp(_widthFraction,.65,.98); _height=WXGClamp(_height,54,90);
    _lift=WXGClamp(_lift,-80,160);
    if(!isfinite(_dockSearchGap))_dockSearchGap=12;
    if(!isfinite(_dockSearchHeightRatio))_dockSearchHeightRatio=.82;
    if(!isfinite(_dockSearchWidthFraction))_dockSearchWidthFraction=.94;
    _dockSearchGap=WXGClamp(_dockSearchGap,2,40);_dockSearchHeightRatio=WXGClamp(_dockSearchHeightRatio,.55,1);
    _dockSearchWidthFraction=WXGClamp(_dockSearchWidthFraction,.65,.98);
    // FIX68: hold-and-drag stretch.
    if(!isfinite(_pressStretchDistance))_pressStretchDistance=16;
    if(!isfinite(_pressStretchAmount))_pressStretchAmount=.6;
    if(!isfinite(_dockEndStretchDistance))_dockEndStretchDistance=18;
    _pressStretchDistance=WXGClamp(_pressStretchDistance,0,32);_pressStretchAmount=WXGClamp(_pressStretchAmount,0,1.5);
    _dockEndStretchDistance=WXGClamp(_dockEndStretchDistance,0,40);
    // FIX80
    if(!isfinite(_pressStretchCapsule))_pressStretchCapsule=.5;
    if(!isfinite(_pressStretchMax))_pressStretchMax=8;
    if(!isfinite(_pressStretchFollow))_pressStretchFollow=.3;
    _bubbleOutgoingHex=WXGNormalizeHex(_bubbleOutgoingHex)?:@"#95EC69CC";_bubbleIncomingHex=WXGNormalizeHex(_bubbleIncomingHex)?:@"#FFFFFFCC";
    _darkBubbleOutgoingHex=WXGNormalizeHex(_darkBubbleOutgoingHex)?:@"#95EC69CC";_darkBubbleIncomingHex=WXGNormalizeHex(_darkBubbleIncomingHex)?:@"#2C2C2CCC";
    _pressStretchCapsule=WXGClamp(_pressStretchCapsule,0,1);_pressStretchMax=WXGClamp(_pressStretchMax,1,20);_pressStretchFollow=WXGClamp(_pressStretchFollow,0,1);
    
    
    
    
    
    
    // FIX64: the edge fade's ranges (WeChatFade: top 0-320, bottom 0-360).
    if(!isfinite(_edgeChatFadeTop))_edgeChatFadeTop=96;
    if(!isfinite(_edgeChatFadeBottom))_edgeChatFadeBottom=112;
    if(!isfinite(_edgeChatBlurTop))_edgeChatBlurTop=96;
    if(!isfinite(_edgeChatBlurBottom))_edgeChatBlurBottom=112;
    if(!isfinite(_edgeChatBlurTopRadius))_edgeChatBlurTopRadius=3;
    if(!isfinite(_edgeChatBlurBottomRadius))_edgeChatBlurBottomRadius=3;
    if(!isfinite(_edgeOtherFadeTop))_edgeOtherFadeTop=96;
    if(!isfinite(_edgeOtherFadeBottom))_edgeOtherFadeBottom=112;
    if(!isfinite(_edgeOtherBlurTop))_edgeOtherBlurTop=96;
    if(!isfinite(_edgeOtherBlurBottom))_edgeOtherBlurBottom=112;
    if(!isfinite(_edgeOtherBlurTopRadius))_edgeOtherBlurTopRadius=3;
    if(!isfinite(_edgeOtherBlurBottomRadius))_edgeOtherBlurBottomRadius=3;
    _edgeChatFadeTop=WXGClamp(_edgeChatFadeTop,0,320);_edgeChatFadeBottom=WXGClamp(_edgeChatFadeBottom,0,360);
    _edgeChatBlurTop=WXGClamp(_edgeChatBlurTop,0,320);_edgeChatBlurBottom=WXGClamp(_edgeChatBlurBottom,0,360);
    _edgeChatBlurTopRadius=WXGClamp(_edgeChatBlurTopRadius,0,8);_edgeChatBlurBottomRadius=WXGClamp(_edgeChatBlurBottomRadius,0,8);
    _edgeOtherFadeTop=WXGClamp(_edgeOtherFadeTop,0,320);_edgeOtherFadeBottom=WXGClamp(_edgeOtherFadeBottom,0,360);
    _edgeOtherBlurTop=WXGClamp(_edgeOtherBlurTop,0,320);_edgeOtherBlurBottom=WXGClamp(_edgeOtherBlurBottom,0,360);
    _edgeOtherBlurTopRadius=WXGClamp(_edgeOtherBlurTopRadius,0,8);_edgeOtherBlurBottomRadius=WXGClamp(_edgeOtherBlurBottomRadius,0,8);
    _captureFPS=(NSInteger)WXGClamp(_captureFPS,15,120);
    if(!isfinite(_captureBudget))_captureBudget=35;
    _captureBudget=round(WXGClamp(_captureBudget,20,80));
    // FIX27: render-server (同步) is the only mode; its mesh refraction always on.
    _renderMode=2;_syncMeshRefraction=YES;
    _samplerSource=(NSInteger)WXGClamp(_samplerSource,0,1);
    if(!isfinite(_syncCaptureScale))_syncCaptureScale=0;
    _syncCaptureScale=WXGClamp(_syncCaptureScale,0,3);
    if(!isfinite(_syncBlurScale))_syncBlurScale=1;
    _syncBlurScale=WXGClamp(_syncBlurScale,.5,3);
    if(!isfinite(_lensBlur))_lensBlur=0;
    _lensBlur=WXGClamp(_lensBlur,0,12);
    if(!isfinite(_lensRefraction))_lensRefraction=1.15;
    if(!isfinite(_lensDispersion))_lensDispersion=.95;
    if(!isfinite(_lensEdgeWidth))_lensEdgeWidth=10;
    _lensRefraction=WXGClamp(_lensRefraction,0,20);_lensDispersion=WXGClamp(_lensDispersion,0,8);_lensEdgeWidth=WXGClamp(_lensEdgeWidth,1,60);
    if(!isfinite(_lensTopEdgeRatio))_lensTopEdgeRatio=1;
    if(!isfinite(_lensEdgeSharpness))_lensEdgeSharpness=3;
    _lensTopEdgeRatio=WXGClamp(_lensTopEdgeRatio,.1,1);_lensEdgeSharpness=WXGClamp(_lensEdgeSharpness,1,6);
    if (!isfinite(_lensZoom)) _lensZoom=1.20;
    if (!isfinite(_lensGrowth)) _lensGrowth=1.28;
    if (!isfinite(_bodyPinch)) _bodyPinch=.18;
    _lensZoom=WXGClamp(_lensZoom,1,1.5); _lensGrowth=WXGClamp(_lensGrowth,1.08,1.5);
    _bodyPinch=WXGClamp(_bodyPinch,0,.30);
    if(!isfinite(_selectionInset)) _selectionInset=6;
    if(!isfinite(_selectionOpacity)) _selectionOpacity=.30;
    if(!isfinite(_pressedOpacity)) _pressedOpacity=.05;
    _selectionInset=WXGClamp(_selectionInset,2,14);
    _selectionOpacity=WXGClamp(_selectionOpacity,0,.75); _pressedOpacity=WXGClamp(_pressedOpacity,0,.4);
    _selectionHex=WXGNormalizeHex(_selectionHex)?:@"#71879EFF";
    _darkSelectionHex=WXGNormalizeHex(_darkSelectionHex)?:_selectionHex;
    if(!isfinite(_barGrowth)) _barGrowth=1.025;
    if(!isfinite(_endWrap)) _endWrap=4;
    
    _barGrowth=WXGClamp(_barGrowth,1,1.08); _endWrap=WXGClamp(_endWrap,2,10);
    
    if(!isfinite(_messageMenuCornerRadius))_messageMenuCornerRadius=18;
    _messageMenuCornerRadius=WXGClamp(_messageMenuCornerRadius,0,40);
    
    _dockSwitchTiming=0;   // FIX37: the switch is always forwarded at once
    // FIX85: the table's keys.
    for(size_t i=0;i<WXGExtraCount;i++) {
        const WXGExtraSpec *spec=&WXGExtraSpecs[i];NSString *key=@(spec->key);id value=_extra[key];
        if(spec->kind=='h'){_extra[key]=WXGNormalizeHex(value)?:@(spec->hex?:"#FFFFFFFF");continue;}
        double v=[value isKindOfClass:NSNumber.class]?[value doubleValue]:spec->def;
        if(!isfinite(v))v=spec->def;
        if(spec->kind=='b'){_extra[key]=@(v>.5);continue;}
        v=WXGClamp(v,spec->lo,spec->hi);
        if(strlen(spec->key)>=8 && !strcmp(spec->key+strlen(spec->key)-8,"RimStyle"))v=lround(v)==WXGRimStyleGlow?WXGRimStyleGlow:WXGRimStyle26;   // FIX130 ("rimStyle" too: compared from its R)
        if(!strcmp(spec->key,"rimStyle"))v=lround(v)==WXGRimStyleGlow?WXGRimStyleGlow:WXGRimStyle26;
        if(strstr(spec->key,"Share"))v=round(v);   // FIX114 L: a choice
        _extra[key]=@(v);
    }
}
static NSUInteger WXGConfigRevisionCounter=1;
NSUInteger WXGConfigRevision(void) {return WXGConfigRevisionCounter;}
- (void)save {
    [self normalize];++WXGConfigRevisionCounter;
    [[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] setObject:[self dictionaryWithValuesForKeys:self.keys] forKey:@"optics.test4"];
    [[NSNotificationCenter defaultCenter] postNotificationName:WXGSettingsChanged object:nil];
}
- (BOOL)reloadSharedParameters {
    WXGConfig *fresh=[WXGConfig new];
    NSDictionary *before=[self dictionaryWithValuesForKeys:[self keys]],*after=[fresh dictionaryWithValuesForKeys:[self keys]];
    if([before isEqual:after]) return NO;
    for(NSString *key in [self keys]) [self setValue:after[key] forKey:key];
    ++WXGConfigRevisionCounter;
    return YES;
}
- (void)reset { [self loadDefaults]; [self save]; }
// FIX115 H: every key back to this build's defaults (WXGBuildProfile.h), the
// keys named kept as they are (the main switch, the floating tool buttons).
- (void)resetAllKeeping:(NSArray<NSString *> *)kept {
    NSMutableDictionary *held=[NSMutableDictionary dictionary];
    for(NSString *key in kept)if([self knowsKey:key]){id v=[self valueForKey:key];if(v)held[key]=v;}
    [self loadDefaults];
    for(NSString *key in held)[self setValue:held[key] forKey:key];
    [self save];
}
// FIX81: only these keys back to the defaults (one settings page).
- (void)resetKeys:(NSArray<NSString *> *)keys {
    NSArray *all=[self keys];
    NSDictionary *current=[self dictionaryWithValuesForKeys:all];
    NSSet *reset=[NSSet setWithArray:keys];
    [self loadDefaults];
    for(NSString *key in all) {
        id value=current[key];
        if(![reset containsObject:key] && value!=NSNull.null)[self setValue:value forKey:key];
    }
    [self save];
}
// FIX58: the dock reads its own body optics and rim; every other glass the shared ones.
- (WXGScopeOptics)opticsForDock:(BOOL)dock {return [self opticsForScope:dock?WXGGlassScopeDock:WXGGlassScopeOther];}   // FIX114 L: with 共用
- (NSDictionary *)parameterValues {return [self dictionaryWithValuesForKeys:[self keys]];}
#pragma mark FIX85 scopes and rim styles
// FIX86: the dock, the other glass and the bubbles each choose their style.
- (WXGRimStyle)rimStyleForScope:(WXGGlassScope)scope {
    return lround([self extraNumber:WXGScopedKey(scope,NO,@"RimStyle")])==WXGRimStyleGlow?WXGRimStyleGlow:WXGRimStyle26;   // FIX130: iOS 27 or iOS 26 (the two older styles are gone)
}
// FIX123: an iOS 26 rim range's values (the border page's sharing applies).
- (WXGRim26Settings)rim26ForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    #define K(stem) [self extraNumber:WXGScopedKey(scope,NO,stem)]
    #define KD(stem) [self extraNumber:WXGScopedKey(scope,dark,stem)]
    WXGRim26Settings r;memset(&r,0,sizeof r);
    r.height=WXGClamp(K(@"Edge26Height"),.3,4);r.curve=WXGClamp(K(@"Edge26Curve"),0,1);
    r.angle=WXGClamp(K(@"Edge26Angle"),0,180);r.key=WXGClamp(K(@"Edge26Key"),0,1.5);r.fill=WXGClamp(K(@"Edge26Fill"),0,1.5);r.spread=WXGClamp(K(@"Edge26Spread"),.3,6);r.floor=WXGClamp(K(@"Edge26Floor"),0,1);
    r.opacity=WXGClamp(KD(@"Edge26Opacity"),0,1);r.gain=WXGClamp(KD(@"Edge26Gain"),0,4);r.chroma=WXGClamp(KD(@"Edge26Chroma"),0,8);
    r.lift=WXGClamp(KD(@"Edge26Lift"),0,1);r.ring=WXGClamp(KD(@"Edge26Ring"),0,1);
    r.captureScale=WXGClamp([self extraNumber:@"edge26CaptureScale"],.1,1);
    #undef K
    #undef KD
    return r;
}
- (BOOL)bubbleFullGlass {return [self extraNumber:@"bubbleFullGlass"]>.5;}
#pragma mark FIX130 one glass for every range
// The row of a range's glass values: 其余玻璃, the dock (and its lens' border range), the bubbles, the segment bar
// (and its lens'), the settings page; 视频号 (its border only) is 其余玻璃's glass.
static NSInteger WXGGlassRow(WXGGlassScope scope) {
    return scope==WXGGlassScopeDock || scope==WXGGlassScopeLens?1:scope==WXGGlassScopeBubble?2:
           scope==WXGGlassScopeSegment || scope==WXGGlassScopeSegmentLens?3:scope==WXGGlassScopeCard?4:0;
}
enum {WXGGlassBand,WXGGlassDepth,WXGGlassBandMax,WXGGlassSqueeze,WXGGlassDispersion,WXGGlassBlurSmall,WXGGlassBlurLarge,
      WXGGlassVeil,WXGGlassDarkVeil,WXGGlassSaturation,WXGGlassDarkSaturation,WXGGlassBrightness,WXGGlassDarkBrightness,
      WXGGlassShadow,WXGGlassDarkShadow,WXGGlassShadowBlur,WXGGlassShadowOffset,WXGGlassValueCount};
// Literal keys: these run every frame for every glass.
#define WXG_GLASS_KEYS(p,d) {@p "lassBand",@p "lassDepth",@p "lassBandMax",@p "lassSqueeze",@p "lassDispersion",@p "lassBlurSmall",@p "lassBlurLarge",\
    @p "lassVeil",@d "lassVeil",@p "lassSaturation",@d "lassSaturation",@p "lassBrightness",@d "lassBrightness",\
    @p "lassShadow",@d "lassShadow",@p "lassShadowBlur",@p "lassShadowOffset"}
static NSString *const WXGGlassKeys[5][WXGGlassValueCount]={WXG_GLASS_KEYS("g","darkG"),WXG_GLASS_KEYS("dockG","dockDarkG"),WXG_GLASS_KEYS("bubbleG","bubbleDarkG"),
                                                            WXG_GLASS_KEYS("segmentG","segmentDarkG"),WXG_GLASS_KEYS("cardG","cardDarkG")};
- (double)glass:(NSInteger)value scope:(WXGGlassScope)scope {return [self extraNumber:WXGGlassKeys[WXGGlassRow(scope)][value]];}
// 共用 (a range using another's settings of a page) is gone: every range its own.
// The body's refraction is the curve's (glassCurveForScope:) and its blur goes by its size (glassBlurForScope:side:).
// What is left of these feeds the dock's fixed overlay shader, which draws the icons in the lens: no refraction at
// rest, its old 10 pt band, and no clear ring (the blur covers the whole glass).
- (WXGScopeOptics)opticsForScope:(WXGGlassScope)scope {
    return (WXGScopeOptics){0,0,10,[self glassBlurForScope:scope side:scope==WXGGlassScopeDock?_height:44],100};
}
// The system's blur for a glass whose short side is `side` points.
- (CGFloat)glassBlurForScope:(WXGGlassScope)scope side:(CGFloat)side {
    CGFloat small=WXGClamp([self glass:WXGGlassBlurSmall scope:scope],0,10),large=WXGClamp([self glass:WXGGlassBlurLarge scope:scope],0,20);
    if(!(side>48))return small;
    return WXGClamp(small+(large-small)*(side-48)/42.,MIN(small,large),MAX(MAX(small,large)*1.5,small));
}
// The system's face is (1 - a) x (levels of the backdrop's luma + its colour kept) + a x fill; here: the backdrop's
// saturation and brightness, then the veil (white in light mode, black in dark) at `a`.
- (WXGBackdropTone)backdropToneForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    return (WXGBackdropTone){WXGClamp([self glass:dark?WXGGlassDarkSaturation:WXGGlassSaturation scope:scope],0,3),
                             WXGClamp([self glass:dark?WXGGlassDarkBrightness:WXGGlassBrightness scope:scope],-.3,.3)};
}
- (NSString *)materialHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {(void)scope;return dark?@"#000000FF":@"#FFFFFFFF";}
- (CGFloat)materialOpacityForScope:(WXGGlassScope)scope dark:(BOOL)dark {return WXGClamp([self glass:dark?WXGGlassDarkVeil:WXGGlassVeil scope:scope],0,1);}
// The system's shadow: a Gaussian of `blur` points, `offset` down (the lens borders' ranges are their glass's).
- (WXGDropShadowSettings)dropShadowForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    return (WXGDropShadowSettings){WXGClamp([self glass:dark?WXGGlassDarkShadow:WXGGlassShadow scope:scope],0,.6),
                                   WXGClamp([self glass:WXGGlassShadowBlur scope:scope],.5,40),WXGClamp([self glass:WXGGlassShadowOffset scope:scope],-10,30),0};
}
// The refraction of a glass' body (WXGLensCurve.h): the band and the depth at the outline as shares of its short
// side, the band at most `maxHeight` points (the depth with it in proportion), the colour split toward its corners.
- (WXGGlassCurve)glassCurveForScope:(WXGGlassScope)scope {
    WXGGlassCurve k;
    k.height=WXGClamp([self glass:WXGGlassBand scope:scope],.02,.5);k.amount=WXGClamp([self glass:WXGGlassDepth scope:scope],0,1);
    k.maxHeight=WXGClamp([self glass:WXGGlassBandMax scope:scope],4,80);k.squeeze=WXGClamp([self glass:WXGGlassSqueeze scope:scope],0,20);
    k.dispersion=WXGClamp([self glass:WXGGlassDispersion scope:scope],0,3);
    return k;
}
// FIX127: iOS 26's tab bar in the dock's own settings.
- (CGFloat)dockCellExtra {return WXGClamp([self extraNumber:@"dockCellExtra"],0,20);}
- (CGFloat)dockLensLiftWidth {return WXGClamp([self extraNumber:@"dockLensLiftWidth"],0,40);}
- (CGFloat)dockLensHang {return WXGClamp([self extraNumber:@"dockLensHang"],0,.5);}
- (BOOL)dockMoveSpring {return [self extraNumber:@"dockMoveSpring"]>.5;}
- (CGFloat)dockMoveResponse {return WXGClamp([self extraNumber:@"dockMoveResponse"],.2,.8);}
- (CGFloat)dockMoveDamping {return WXGClamp([self extraNumber:@"dockMoveDamping"],.5,1.2);}
/* Every value probe 2 measured on the system's bar, as the dock's settings
   (WXGDockSystem.h), for a screen `width` points wide: the bar the screen
   less 21 pt a side and 62 pt high, the selection 4 pt inside it, the cells
   overlapping by 10 pt, the lens lifted 16 pt wider and taller (70 pt: 70 / 62
   of the bar) and 8.4 pt past the bar's ends, the bar 3.55% larger while
   held, the lens' content 1.16x; the lens' glass the curve with the
   system's band (0.10 of its height) and the depth that puts the mirrored
   bar where the recording has it (0.30; the filter's own number is 0.25),
   no blur and no tint; the system's deformation, position spring and hang;
   its own highlight border (iOS 26's). */
- (NSDictionary<NSString *,NSNumber *> *)dockSystem26ValuesForScreenWidth:(CGFloat)width {
    CGFloat fraction=width>100?WXGClamp((width-2*WXG_DOCK26_SIDE_MARGIN)/width,.65,.98):.9045;
    return @{@"widthFraction":@(fraction),@"height":@(WXG_DOCK26_HEIGHT),@"selectionInset":@(WXG_DOCK26_INSET),
             @"lensGrowth":@((WXG_DOCK26_HEIGHT-2*WXG_DOCK26_INSET+WXG_DOCK26_LIFT)/WXG_DOCK26_HEIGHT),
             @"barGrowth":@(WXG_DOCK26_BAR_GROWTH),@"endWrap":@(WXG_DOCK26_END_WRAP),@"lensZoom":@(WXG_DOCK26_ZOOM),
             @"dockCellExtra":@(WXG_DOCK26_CELL_EXTRA),@"dockLensLiftWidth":@(WXG_DOCK26_LIFT),@"dockLensHang":@(WXG_DOCK26_HANG),
             @"dockMoveSpring":@YES,@"dockMoveResponse":@(WXG_DOCK26_RESPONSE),@"dockMoveDamping":@(WXG_DOCK26_DAMPING),
             @"lensCurveBand":@(WXG_DOCK26_LENS_BAND),@"lensCurveDepth":@(WXG_DOCK26_LENS_AMOUNT),
             @"lensBlur":@0,@"lensTintOn":@NO,
             // FIX128 / FIX129: how far in the bar's edge shows through the lens; the lens' own border as the system's
             // (its highlight rim, curvature 0.8).
             @"bodyPinch":@(WXG_DOCK26_PINCH),
             @"lensGlassRimStyle":@(WXGRimStyle26),@"lensGlassEdge26Curve":@(WXG_DOCK26_LENS_RIM_CURVE),
             @"lensGlassEdge26Height":@1,@"lensGlassEdge26Opacity":@1,@"lensGlassDarkEdge26Opacity":@1,
             @"lensElasticOn":@YES,@"lensFlexStrength":@1,@"lensFlexSlow":@8,@"lensFlexDamping":@.5,@"lensFlexSymmetric":@NO,@"lensFlexSqueeze":@1,
             // FIX131: the bar's own glass (the buttons' law but for its light face and its shadow), its iOS 26 border,
             // the resting selection (its colours are dockSystem26Colours), a tap's lift and drop, the light under a finger.
             @"dockGlassBand":@.25,@"dockGlassDepth":@.8,@"dockGlassBandMax":@20,@"dockGlassBlurSmall":@1.8,@"dockGlassBlurLarge":@5.5,
             @"dockGlassVeil":@(WXG_DOCK26_BODY_VEIL),@"dockDarkGlassVeil":@.605,@"dockGlassSaturation":@1.34,@"dockDarkGlassSaturation":@1.67,
             @"dockGlassBrightness":@(WXG_DOCK26_BODY_BRIGHTNESS),@"dockDarkGlassBrightness":@.18,
             @"dockGlassShadow":@(WXG_DOCK26_SHADOW),@"dockDarkGlassShadow":@.05,@"dockGlassShadowBlur":@(WXG_DOCK26_SHADOW_BLUR),@"dockGlassShadowOffset":@8,
             @"dockRimStyle":@(WXGRimStyle26),
             @"selectionOpacity":@.75,@"pressedOpacity":@0,
             @"dockTapDropTime":@(WXG_SCRIPT26_DROP_TIME),@"dockTapLensShare":@(WXG_SCRIPT26_LIFT_TIME/WXGDockSpringDuration(WXG_DOCK26_RESPONSE,WXG_DOCK26_DAMPING)),
             @"dockTouchGlow":@YES,@"dockTouchGlowSpot":@(WXG_DOCK26_GLOW_SPOT),@"dockTouchGlowBar":@(WXG_DOCK26_GLOW_BAR)};
}
// FIX131: the colours that go with them: the resting selection, black at 0.07 in light and white at 0.14 in dark
// (the alpha here x the 0.75 above).
- (NSDictionary<NSString *,NSString *> *)dockSystem26Colours {
    return @{@"selectionHex":[NSString stringWithFormat:@"#000000%02lX",lround(WXG_DOCK26_PILL_LIGHT/.75*255)],
             @"darkSelectionHex":[NSString stringWithFormat:@"#FFFFFF%02lX",lround(WXG_DOCK26_PILL_DARK/.75*255)]};
}
static NSString *const WXGDockSystem26BackupKey=@"dockSystem26.before";
- (BOOL)hasDockSystem26Backup {
    return [[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] dictionaryForKey:WXGDockSystem26BackupKey].count>0;
}
// Those values into the settings (saved). What was there is kept (from before
// the first time, if applied again) for restoreDockBeforeSystem26.
- (void)applyDockSystem26ForScreenWidth:(CGFloat)width {
    NSDictionary<NSString *,NSNumber *> *values=[self dockSystem26ValuesForScreenWidth:width];
    NSUserDefaults *suite=[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"];
    // FIX128: a key this build's 套用 sets and an earlier build's did not is kept from now.
    NSDictionary *kept=[suite dictionaryForKey:WXGDockSystem26BackupKey];
    NSMutableDictionary *before=kept.count?[kept mutableCopy]:[NSMutableDictionary dictionary];
    for(NSString *key in values) {
        if(before[key])continue;
        id value=nil;
        @try {value=[self valueForKey:key];} @catch(__unused NSException *error) {value=nil;}
        if([value isKindOfClass:NSNumber.class])before[key]=value;
    }
    NSDictionary<NSString *,NSString *> *colours=[self dockSystem26Colours];   // FIX131
    for(NSString *key in colours) {
        if(before[key])continue;
        id value=nil;
        @try {value=[self valueForKey:key];} @catch(__unused NSException *error) {value=nil;}
        if([value isKindOfClass:NSString.class])before[key]=value;
    }
    if(![before isEqualToDictionary:kept?:@{}])[suite setObject:before forKey:WXGDockSystem26BackupKey];
    for(NSString *key in values)[self setValue:values[key] forKey:key];
    for(NSString *key in colours)[self setValue:colours[key] forKey:key];
    [self save];
}
// The values from before 套用 back (only the keys it changed); NO: nothing kept.
- (BOOL)restoreDockBeforeSystem26 {
    NSUserDefaults *suite=[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"];
    NSDictionary *before=[suite dictionaryForKey:WXGDockSystem26BackupKey];
    if(!before.count)return NO;
    NSSet *known=[NSSet setWithArray:[self dockSystem26ValuesForScreenWidth:0].allKeys];
    for(NSString *key in before)if([known containsObject:key] && [before[key] isKindOfClass:NSNumber.class])[self setValue:before[key] forKey:key];
    NSDictionary *colours=[self dockSystem26Colours];   // FIX131
    for(NSString *key in before)if(colours[key] && [before[key] isKindOfClass:NSString.class])[self setValue:before[key] forKey:key];
    [suite removeObjectForKey:WXGDockSystem26BackupKey];
    [self save];
    return YES;
}
// The lens' deformation as it moves: the system's (WXGLensFlex.h, fitted on the tab bar lens recorded on iOS 26.6).
- (WXGLensFlexParams)lensFlexParams {
    WXGLensFlexParams p=WXGLensFlexDefaults();
    p.on=1;
    double k=WXGClamp([self extraNumber:@"lensFlexStrength"],0,3);p.gainX*=k;p.gainY*=k;
    p.slow=WXGClamp([self extraNumber:@"lensFlexSlow"],3,20);p.slowDamping=WXGClamp([self extraNumber:@"lensFlexDamping"],.15,1.2);
    p.symmetric=[self extraNumber:@"lensFlexSymmetric"]>.5;p.squeeze=WXGClamp([self extraNumber:@"lensFlexSqueeze"],0,1.5);
    return p;
}
- (WXGLensSettings)lensSettingsForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    // Literal keys: this runs a few times a frame while the bar draws.
    WXGLensSettings l;memset(&l,0,sizeof l);
    if(scope==WXGGlassScopeSegment) {
        l.band=[self extraNumber:@"segmentLensCurveBand"];l.depth=[self extraNumber:@"segmentLensCurveDepth"];
        l.split=[self extraNumber:@"segmentLensCurveDispersion"];l.squeeze=[self extraNumber:@"segmentLensCurveSqueeze"];
        l.zoom=[self extraNumber:@"segmentLensZoom"];l.growth=[self extraNumber:@"segmentLensGrowth"];l.barGrowth=[self extraNumber:@"segmentBarGrowth"];
        l.endWrap=[self extraNumber:@"segmentEndWrap"];l.pinch=[self extraNumber:@"segmentBodyPinch"];l.blur=[self extraNumber:@"segmentLensBlur"];
        l.rimAtRest=WXGClamp([self extraNumber:@"segmentPillRimAtRest"],0,1);
        l.tintOn=[self extraNumber:@"segmentLensTintOn"]>.5;l.tintOpacity=[self extraNumber:dark?@"segmentDarkLensTintOpacity":@"segmentLensTintOpacity"];
        l.selectionInset=[self extraNumber:@"segmentSelectionInset"];
        l.iconRefraction=[self extraNumber:@"segmentLensIconRefraction"];l.iconEdgeWidth=[self extraNumber:@"segmentLensIconEdgeWidth"];
        l.iconTopRatio=[self extraNumber:@"segmentLensIconTopEdgeRatio"];l.iconSharpness=[self extraNumber:@"segmentLensIconEdgeSharpness"];
        l.iconDispersion=[self extraNumber:@"segmentLensDispersion"];
        l.elasticOn=[self extraNumber:@"segmentLensElasticOn"]>.5;l.elasticKeepStrip=[self extraNumber:@"segmentLensElasticKeepStrip"];
    }else {
        l.band=[self extraNumber:@"lensCurveBand"];l.depth=[self extraNumber:@"lensCurveDepth"];
        l.split=[self extraNumber:@"lensCurveDispersion"];l.squeeze=[self extraNumber:@"lensCurveSqueeze"];
        l.zoom=_lensZoom;l.growth=_lensGrowth;l.barGrowth=_barGrowth;l.endWrap=_endWrap;l.pinch=_bodyPinch;l.blur=_lensBlur;
        l.tintOn=[self extraNumber:@"lensTintOn"]>.5;l.tintOpacity=[self extraNumber:dark?@"darkLensTintOpacity":@"lensTintOpacity"];
        l.selectionInset=_selectionInset;
        l.iconRefraction=[self extraNumber:@"lensIconRefraction"];l.iconEdgeWidth=[self extraNumber:@"lensIconEdgeWidth"];
        l.iconTopRatio=[self extraNumber:@"lensIconTopEdgeRatio"];l.iconSharpness=[self extraNumber:@"lensIconEdgeSharpness"];
        l.iconDispersion=_lensDispersion;
        l.elasticOn=[self extraNumber:@"lensElasticOn"]>.5;l.elasticKeepStrip=[self extraNumber:@"lensElasticKeepStrip"];
    }
    l.band=WXGClamp(l.band,.02,.5);l.depth=WXGClamp(l.depth,0,.8);l.split=WXGClamp(l.split,0,3);l.squeeze=WXGClamp(l.squeeze,0,20);
    return l;
}
- (UIColor *)lensRimLineColorDark:(BOOL)dark width:(CGFloat *)width {
    if([self rimStyleForScope:WXGGlassScopeLens]==WXGRimStyleGlow) {
        WXGRimGlowShape g=[self rimGlowForScope:WXGGlassScopeLens index:0 dark:dark];
        if(width)*width=WXGClamp(g.width*.5,.3,1.5);
        return [UIColor colorWithRed:g.red green:g.green blue:g.blue alpha:WXGClamp(g.alpha,0,1)];
    }
    if(width)*width=0;   // the iOS 26 border is its own layers: no plain line
    return UIColor.clearColor;
}
- (NSString *)lensTintHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    if(scope==WXGGlassScopeSegment)return [self extraHex:dark?@"segmentDarkLensTintHex":@"segmentLensTintHex"];
    return [self extraHex:dark?@"darkLensTintHex":@"lensTintHex"];
}
// FIX113 O: a key this configuration holds (a property of the list or a table key).
- (BOOL)knowsKey:(NSString *)key {return key && (WXGExtraIndex()[key]!=nil || [self.keys containsObject:key]);}
- (CGFloat)dockIconTitleGap {return [self extraNumber:@"dockIconTitleGap"];}
- (CGFloat)dockIconOffset {return [self extraNumber:@"dockIconOffset"];}
- (CGFloat)dockTitleSize {return [self extraNumber:@"dockTitleSize"];}
- (NSInteger)dockTitleWeight {return (NSInteger)lround([self extraNumber:@"dockTitleWeight"]);}
- (BOOL)dockTitleBolderSelected {return [self extraNumber:@"dockTitleBolderSelected"]>.5;}
- (BOOL)dockTapSimpleTravel {return [self extraNumber:@"dockTapSimpleTravel"]>.5;}
- (CGFloat)dockTapDurationScale {return [self extraNumber:@"dockTapMoveScale"];}   // FIX99 key
- (CGFloat)dockTapDropDuration {return [self extraNumber:@"dockTapDropTime"];}       // FIX99 key
- (CGFloat)dockTapLensShare {return [self extraNumber:@"dockTapLensShare"];}
- (NSInteger)dockTapSwitchWhen {return (NSInteger)lround([self extraNumber:@"dockTapSwitchWhen"]);}
// The moment for a switch made at the release (WXGScriptHoldsSwitch: 0 at
// once, 1 nearly arrived, 2 down); 按下时 is 0 for what is left to the release.
- (NSInteger)dockTapSwitchMoment {return MAX(0,self.dockTapSwitchWhen-1);}
- (BOOL)dockTapSwitchAtTouchDown {return self.dockTapSwitchWhen==0;}
- (BOOL)dockTapWaitForCalm {return [self extraNumber:@"dockTapCalmWaitOn"]>.5;}
- (BOOL)dockTapCatchUp {return [self extraNumber:@"dockTapCatchUp"]>.5;}
- (BOOL)dockDiscrete {return [self extraNumber:@"dockDiscrete"]>.5;}
- (BOOL)dockDiscreteConnected {return [self extraNumber:@"dockDiscreteConnected"]>.5;}
- (BOOL)dockDiscretePill {return [self extraNumber:@"dockDiscretePill"]>.5;}
- (CGFloat)dockDiscreteGap {return WXGClamp([self extraNumber:@"dockDiscreteGap"],0,24);}
- (CGFloat)dockDiscreteWide {return WXGClamp([self extraNumber:@"dockDiscreteWide"],1,3);}
- (CGFloat)dockDiscreteBall {return WXGClamp([self extraNumber:@"dockDiscreteBall"],.6,1.3);}
- (CGFloat)dockDiscreteDamping {return WXGClamp([self extraNumber:@"dockDiscreteDamping"],.45,1);}
- (CGFloat)dockDiscreteResponse {return WXGClamp([self extraNumber:@"dockDiscreteResponse"],.2,1);}
- (BOOL)dockDiscreteLight {return [self extraNumber:@"dockDiscreteLight"]>.5;}
- (CGFloat)dockDiscreteIconSize {return WXGClamp([self extraNumber:@"dockDiscreteIconSize"],20,40);}
- (CGFloat)dockDiscreteTitleSize {return WXGClamp([self extraNumber:@"dockDiscreteTitleSize"],10,20);}
- (CGFloat)dockDiscreteSubtitleSize {return WXGClamp([self extraNumber:@"dockDiscreteSubtitleSize"],8,16);}
- (CGFloat)dockDiscreteGather {return WXGClamp([self extraNumber:@"dockDiscreteGather"],0,.45);}
- (CGFloat)dockDiscreteContentShift {return WXGClamp([self extraNumber:@"dockDiscreteContentShift"],0,30);}
- (CGFloat)avatarSize {return [self extraNumber:@"avatarSize"];}
- (CGFloat)avatarOffsetY {return [self extraNumber:@"avatarOffsetY"];}
- (CGFloat)avatarBorderWidth {return [self extraNumber:@"avatarBorderWidth"];}
- (NSString *)avatarBorderHexDark:(BOOL)dark {return [self extraHex:dark?@"avatarDarkBorderHex":@"avatarBorderHex"];}
// FIX89: the iOS 27-like rim's two highlights, drawn together whatever the
// appearance: 0 from the keys that were light mode's, 1 from dark mode's (so
// an upgrade keeps both as they were set, now on screen at once).
// FIX113 Z: and per appearance: dark mode's two from the …Rim27DarkMode… keys.
- (WXGRimGlowShape)rimGlowForScope:(WXGGlassScope)scope index:(NSInteger)index dark:(BOOL)dark {
    BOOL second=index==1;NSString *stem=dark?@"Rim27DarkMode":@"Rim27";
    NSString *(^key)(NSString *)=^NSString *(NSString *attr){return WXGScopedKey(scope,second,[stem stringByAppendingString:attr]);};
    CGFloat r=1,g=1,b=1,a=1;
    if(![WXGColor([self extraHex:key(@"Hex")]) getRed:&r green:&g blue:&b alpha:&a]){r=g=b=1;a=1;}
    CGFloat opacity=WXGClamp([self extraNumber:key(@"Opacity")],0,1);
    return (WXGRimGlowShape){[self extraNumber:key(@"Width")],[self extraNumber:key(@"Falloff")],
                             [self extraNumber:key(@"EndLevel")],[self extraNumber:key(@"Sharpness")],
                             [self extraNumber:key(@"Angle")],WXGClamp(r,0,1),WXGClamp(g,0,1),WXGClamp(b,0,1),WXGClamp(a*opacity,0,1)};
}
@end
// FIX114 C: the title row's margin to the screen's sides and its move down,
// in points for a metrics scale (the margin at 20 is m.edge as before).
CGFloat WXGTitleRowEdge(double scale) {return WXGClamp([WXGConfig.shared extraNumber:@"navEdge"],8,36)*scale;}
CGFloat WXGTitleRowOffset(double scale) {return WXGClamp([WXGConfig.shared extraNumber:@"navOffsetY"],0,16)*scale;}
CGFloat WXGFinderRowEdge(double scale) {return WXGClamp([WXGConfig.shared extraNumber:@"finderEdge"],0,30)*scale;}   // FIX115 S
