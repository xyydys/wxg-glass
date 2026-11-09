#import "WXGCommon.h"
#include "WXGShareChain.h"
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

/* FIX85: keys kept in a table instead of properties: the liquid bubbles'
   own optics and rim, the rim style, the colour-from-background style's own
   opacity / width / brightness / fade and the iOS 27-like rim (FIX86: the
   calm background material is gone again). Each is a number ('n', clamped to lo..hi), a switch
   ('b') or a colour ('h'). A key with `inherit` starts, when it has never
   been stored, from that key's current value (so nothing looks different
   until it is changed). They are ordinary keys to everything else (KVC,
   the settings rows, export / import, the build defaults). */
typedef struct {const char *key; char kind; double def,lo,hi; const char *inherit,*hex;} WXGExtraSpec;
static const WXGExtraSpec WXGExtraSpecs[]={
    {"bubbleRefraction",'n',1.15,0,20,"refraction",NULL},
    {"bubbleDispersion",'n',0.95,0,8,"dispersion",NULL},
    {"bubbleEdgeWidth",'n',10,1,60,"edgeWidth",NULL},
    {"bubbleBlur",'n',1.5,0,12,"blur",NULL},
    {"bubbleBlurCoverage",'n',0,0,100,"blurCoverage",NULL},
    {"bubbleFullGlass",'b',0,0,1,NULL,NULL},
    {"bubbleSharedBackdrop",'b',1,0,1,NULL,NULL},   // FIX119 B
    {"bubbleRimHex",'h',0,0,0,"rimHex","#FFFFFFFF"},
    {"bubbleDarkRimHex",'h',0,0,0,"darkRimHex","#FFFFFFFF"},
    {"bubbleRimOpacity",'n',0.5,0,1,"rimOpacity",NULL},
    {"bubbleDarkRimOpacity",'n',0.14,0,1,"darkRimOpacity",NULL},
    {"bubbleBorderWidth",'n',1,0,2,"barBorderWidth",NULL},
    {"bubbleDarkBorderWidth",'n',1,0,2,"darkBarBorderWidth",NULL},
    {"bubbleRimBrightness",'n',1,0,2,"rimBrightness",NULL},
    {"bubbleDarkRimBrightness",'n',1,0,2,"darkRimBrightness",NULL},
    {"bubbleRimFade",'n',0.7,0,1,"rimFade",NULL},
    {"bubbleDarkRimFade",'n',1,0,1,"darkRimFade",NULL},
    {"rimStyle",'n',1,0,2,NULL,NULL},
    {"dockRimStyle",'n',1,0,2,"rimStyle",NULL},
    {"bubbleRimStyle",'n',1,0,2,"rimStyle",NULL},
    {"rimSampleOpacity",'n',0.5,0,1,"rimOpacity",NULL},
    {"darkRimSampleOpacity",'n',0.5,0,1,"darkRimOpacity",NULL},
    {"dockRimSampleOpacity",'n',0.5,0,1,"dockRimOpacity",NULL},
    {"dockDarkRimSampleOpacity",'n',0.5,0,1,"dockDarkRimOpacity",NULL},
    {"bubbleRimSampleOpacity",'n',0.5,0,1,"bubbleRimOpacity",NULL},
    {"bubbleDarkRimSampleOpacity",'n',0.5,0,1,"bubbleDarkRimOpacity",NULL},
    {"rimSampleWidth",'n',1,0,2,"barBorderWidth",NULL},
    {"darkRimSampleWidth",'n',1,0,2,"darkBarBorderWidth",NULL},
    {"dockRimSampleWidth",'n',1,0,2,"dockBorderWidth",NULL},
    {"dockDarkRimSampleWidth",'n',1,0,2,"dockDarkBorderWidth",NULL},
    {"bubbleRimSampleWidth",'n',1,0,2,"bubbleBorderWidth",NULL},
    {"bubbleDarkRimSampleWidth",'n',1,0,2,"bubbleDarkBorderWidth",NULL},
    {"rimSampleBrightness",'n',1,0,2,"rimBrightness",NULL},
    {"darkRimSampleBrightness",'n',1,0,2,"darkRimBrightness",NULL},
    {"dockRimSampleBrightness",'n',1,0,2,"dockRimBrightness",NULL},
    {"dockDarkRimSampleBrightness",'n',1,0,2,"dockDarkRimBrightness",NULL},
    {"bubbleRimSampleBrightness",'n',1,0,2,"bubbleRimBrightness",NULL},
    {"bubbleDarkRimSampleBrightness",'n',1,0,2,"bubbleDarkRimBrightness",NULL},
    {"rimSampleFade",'n',0.7,0,1,"rimFade",NULL},
    {"darkRimSampleFade",'n',0.7,0,1,"darkRimFade",NULL},
    {"dockRimSampleFade",'n',0.7,0,1,"dockRimFade",NULL},
    {"dockDarkRimSampleFade",'n',0.7,0,1,"dockDarkRimFade",NULL},
    {"bubbleRimSampleFade",'n',0.7,0,1,"bubbleRimFade",NULL},
    {"bubbleDarkRimSampleFade",'n',0.7,0,1,"bubbleDarkRimFade",NULL},
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
    // FIX97: the bar seen through the lens splits its colours too: everywhere
    // (pt at the rim, from 0 at the centre) and near the ends (a share of the
    // lens' own split, where it refracts the bar most).
    {"lensBarDispersionOn",'b',1,0,1,NULL,NULL},
    {"lensBarDispersion",'n',.6,0,2,NULL,NULL},
    {"lensBarDispersionNearRim",'n',.35,0,1,NULL,NULL},
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
    // FIX109 (user: the 普通 rim softer, a short glow at its edge, not a
    // gradient across it): on per range (the switch kept from A); FIX109 B:
    // the glow inside the line, its width (pt) and the level it starts at
    // (of the line's), per range and appearance.
    {"rimInward",'b',1,0,1,NULL,NULL},
    {"dockRimInward",'b',1,0,1,"rimInward",NULL},
    {"bubbleRimInward",'b',1,0,1,"rimInward",NULL},
    {"rimSoftWidth",'n',.8,0,4,NULL,NULL},
    {"darkRimSoftWidth",'n',.8,0,4,"rimSoftWidth",NULL},
    {"dockRimSoftWidth",'n',.8,0,4,"rimSoftWidth",NULL},
    {"dockDarkRimSoftWidth",'n',.8,0,4,"darkRimSoftWidth",NULL},
    {"bubbleRimSoftWidth",'n',.8,0,4,"rimSoftWidth",NULL},
    {"bubbleDarkRimSoftWidth",'n',.8,0,4,"darkRimSoftWidth",NULL},
    {"rimSoftLevel",'n',.5,0,1,NULL,NULL},
    {"darkRimSoftLevel",'n',.5,0,1,"rimSoftLevel",NULL},
    {"dockRimSoftLevel",'n',.5,0,1,"rimSoftLevel",NULL},
    {"dockDarkRimSoftLevel",'n',.5,0,1,"darkRimSoftLevel",NULL},
    {"bubbleRimSoftLevel",'n',.5,0,1,"rimSoftLevel",NULL},
    {"bubbleDarkRimSoftLevel",'n',.5,0,1,"darkRimSoftLevel",NULL},
    // FIX109 C (user: 取自背景 the same way, its colour from the background):
    // the sampled line's own switch, glow width and level.
    {"rimSampleSoft",'b',1,0,1,"rimInward",NULL},
    {"dockRimSampleSoft",'b',1,0,1,"dockRimInward",NULL},
    {"bubbleRimSampleSoft",'b',1,0,1,"bubbleRimInward",NULL},
    {"rimSampleSoftWidth",'n',.8,0,4,"rimSoftWidth",NULL},
    {"darkRimSampleSoftWidth",'n',.8,0,4,"darkRimSoftWidth",NULL},
    {"dockRimSampleSoftWidth",'n',.8,0,4,"dockRimSoftWidth",NULL},
    {"dockDarkRimSampleSoftWidth",'n',.8,0,4,"dockDarkRimSoftWidth",NULL},
    {"bubbleRimSampleSoftWidth",'n',.8,0,4,"bubbleRimSoftWidth",NULL},
    {"bubbleDarkRimSampleSoftWidth",'n',.8,0,4,"bubbleDarkRimSoftWidth",NULL},
    {"rimSampleSoftLevel",'n',.5,0,1,"rimSoftLevel",NULL},
    {"darkRimSampleSoftLevel",'n',.5,0,1,"darkRimSoftLevel",NULL},
    {"dockRimSampleSoftLevel",'n',.5,0,1,"dockRimSoftLevel",NULL},
    {"dockDarkRimSampleSoftLevel",'n',.5,0,1,"dockDarkRimSoftLevel",NULL},
    {"bubbleRimSampleSoftLevel",'n',.5,0,1,"bubbleRimSoftLevel",NULL},
    {"bubbleDarkRimSampleSoftLevel",'n',.5,0,1,"bubbleDarkRimSoftLevel",NULL},
    {"lensDispersionWidth",'n',10,1,60,"lensEdgeWidth",NULL},
    {"lensDispersionTopRatio",'n',1,0.1,1,"lensTopEdgeRatio",NULL},
    // FIX122 Kyant 透镜模式 (WXGKyantLens.h): the dock's lens refracted and
    // split as Kyant's Backdrop lens(): on, the band and the shift at the
    // outline as shares of the lens' short side (the catalog's 10 / 56 and
    // 14 / 56), the colour split's strength (1 = his). Off = as before.
    {"lensKyantOn",'b',0,0,1,NULL,NULL},
    {"lensKyantHeight",'n',10./56.,.02,.5,NULL,NULL},
    {"lensKyantAmount",'n',14./56.,0,.8,NULL,NULL},
    {"lensKyantDispersion",'n',1,0,3,NULL,NULL},
    // FIX122 E: the outermost thin ring (his curve's infinitely steep
    // start): kept (his) or capped at this squeeze (WXGKyantOffsetCapped).
    {"lensKyantRimFine",'b',1,0,1,NULL,NULL},
    {"lensKyantRimMax",'n',3,1,20,NULL,NULL},
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
    {"segmentLensDispersionWidth",'n',10,1,60,"lensDispersionWidth",NULL},
    {"segmentLensDispersionTopRatio",'n',1,.1,1,"lensDispersionTopRatio",NULL},
    {"segmentLensZoom",'n',1.2,1,1.5,"lensZoom",NULL},
    {"segmentLensGrowth",'n',1.28,1.08,1.5,"lensGrowth",NULL},
    {"segmentBarGrowth",'n',1,1,1.08,"barGrowth",NULL},
    {"segmentEndWrap",'n',6,2,10,"endWrap",NULL},
    {"segmentBodyPinch",'n',.18,0,.3,"bodyPinch",NULL},
    {"segmentLensBlur",'n',0,0,12,"lensBlur",NULL},
    {"segmentLensBlurCoverage",'n',0,0,100,"lensBlurCoverage",NULL},
    {"segmentLensOffsetCancel",'n',0,0,1,"lensOffsetCancel",NULL},
    {"segmentLensKyantOn",'b',0,0,1,"lensKyantOn",NULL},   // FIX122
    {"segmentLensKyantHeight",'n',10./56.,.02,.5,"lensKyantHeight",NULL},
    {"segmentLensKyantAmount",'n',14./56.,0,.8,"lensKyantAmount",NULL},
    {"segmentLensKyantDispersion",'n',1,0,3,"lensKyantDispersion",NULL},
    {"segmentLensKyantRimFine",'b',1,0,1,"lensKyantRimFine",NULL},   // FIX122 E
    {"segmentLensKyantRimMax",'n',3,1,20,"lensKyantRimMax",NULL},
    {"segmentLensRimHex",'h',0,0,0,"lensRimHex","#FFFFFFFF"},
    {"segmentDarkLensRimHex",'h',0,0,0,"darkLensRimHex","#FFFFFFFF"},
    {"segmentLensRimOpacity",'n',.5,0,1,"lensRimOpacity",NULL},
    {"segmentDarkLensRimOpacity",'n',.3,0,1,"darkLensRimOpacity",NULL},
    {"segmentLensBorderWidth",'n',1,0,2,"lensBorderWidth",NULL},
    {"segmentDarkLensBorderWidth",'n',1,0,2,"darkLensBorderWidth",NULL},
    {"segmentPillRimAtRest",'n',0,0,1,NULL,NULL},
    {"segmentLensTintOn",'b',0,0,1,"lensTintOn",NULL},
    {"segmentLensTintHex",'h',0,0,0,"lensTintHex","#FFFFFFFF"},
    {"segmentDarkLensTintHex",'h',0,0,0,"darkLensTintHex","#FFFFFFFF"},
    {"segmentLensTintOpacity",'n',.12,0,1,"lensTintOpacity",NULL},
    {"segmentDarkLensTintOpacity",'n',.08,0,1,"darkLensTintOpacity",NULL},
    {"segmentLensBarDispersionOn",'b',1,0,1,"lensBarDispersionOn",NULL},
    {"segmentLensBarDispersion",'n',.6,0,2,"lensBarDispersion",NULL},
    {"segmentLensBarDispersionNearRim",'n',.35,0,1,"lensBarDispersionNearRim",NULL},
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
    {"segmentRefraction",'n',1.15,0,20,"dockRefraction",NULL},
    {"cardRefraction",'n',1.15,0,20,"refraction",NULL},
    {"segmentDispersion",'n',0.95,0,8,"dockDispersion",NULL},
    {"cardDispersion",'n',0.95,0,8,"dispersion",NULL},
    {"segmentEdgeWidth",'n',10,1,60,"dockEdgeWidth",NULL},
    {"cardEdgeWidth",'n',10,1,60,"edgeWidth",NULL},
    {"segmentBlur",'n',1.5,0,12,"dockBlur",NULL},
    {"cardBlur",'n',1.5,0,12,"blur",NULL},
    {"segmentBlurCoverage",'n',0,0,100,"dockBlurCoverage",NULL},
    {"cardBlurCoverage",'n',0,0,100,"blurCoverage",NULL},
    {"segmentRimHex",'h',0,0,0,"dockRimHex","#FFFFFFFF"},
    {"cardRimHex",'h',0,0,0,"rimHex","#FFFFFFFF"},
    {"segmentDarkRimHex",'h',0,0,0,"dockDarkRimHex","#FFFFFFFF"},
    {"cardDarkRimHex",'h',0,0,0,"darkRimHex","#FFFFFFFF"},
    {"segmentRimOpacity",'n',0.5,0,1,"dockRimOpacity",NULL},
    {"cardRimOpacity",'n',0.5,0,1,"rimOpacity",NULL},
    {"segmentDarkRimOpacity",'n',0.23,0,1,"dockDarkRimOpacity",NULL},
    {"cardDarkRimOpacity",'n',0.14,0,1,"darkRimOpacity",NULL},
    {"segmentBorderWidth",'n',1,0,2,"dockBorderWidth",NULL},
    {"cardBorderWidth",'n',1,0,2,"barBorderWidth",NULL},
    {"segmentDarkBorderWidth",'n',1,0,2,"dockDarkBorderWidth",NULL},
    {"cardDarkBorderWidth",'n',1,0,2,"darkBarBorderWidth",NULL},
    {"segmentRimBrightness",'n',1,0,2,"dockRimBrightness",NULL},
    {"cardRimBrightness",'n',1,0,2,"rimBrightness",NULL},
    {"segmentDarkRimBrightness",'n',1,0,2,"dockDarkRimBrightness",NULL},
    {"cardDarkRimBrightness",'n',1,0,2,"darkRimBrightness",NULL},
    {"segmentRimFade",'n',0.7,0,1,"dockRimFade",NULL},
    {"cardRimFade",'n',0.7,0,1,"rimFade",NULL},
    {"segmentDarkRimFade",'n',1,0,1,"dockDarkRimFade",NULL},
    {"cardDarkRimFade",'n',1,0,1,"darkRimFade",NULL},
    {"segmentRimStyle",'n',1,0,2,"dockRimStyle",NULL},
    {"cardRimStyle",'n',1,0,2,"rimStyle",NULL},
    {"segmentRimSampleOpacity",'n',0.5,0,1,"dockRimSampleOpacity",NULL},
    {"cardRimSampleOpacity",'n',0.5,0,1,"rimSampleOpacity",NULL},
    {"segmentDarkRimSampleOpacity",'n',0.5,0,1,"dockDarkRimSampleOpacity",NULL},
    {"cardDarkRimSampleOpacity",'n',0.5,0,1,"darkRimSampleOpacity",NULL},
    {"segmentRimSampleWidth",'n',1,0,2,"dockRimSampleWidth",NULL},
    {"cardRimSampleWidth",'n',1,0,2,"rimSampleWidth",NULL},
    {"segmentDarkRimSampleWidth",'n',1,0,2,"dockDarkRimSampleWidth",NULL},
    {"cardDarkRimSampleWidth",'n',1,0,2,"darkRimSampleWidth",NULL},
    {"segmentRimSampleBrightness",'n',1,0,2,"dockRimSampleBrightness",NULL},
    {"cardRimSampleBrightness",'n',1,0,2,"rimSampleBrightness",NULL},
    {"segmentDarkRimSampleBrightness",'n',1,0,2,"dockDarkRimSampleBrightness",NULL},
    {"cardDarkRimSampleBrightness",'n',1,0,2,"darkRimSampleBrightness",NULL},
    {"segmentRimSampleFade",'n',0.7,0,1,"dockRimSampleFade",NULL},
    {"cardRimSampleFade",'n',0.7,0,1,"rimSampleFade",NULL},
    {"segmentDarkRimSampleFade",'n',0.7,0,1,"dockDarkRimSampleFade",NULL},
    {"cardDarkRimSampleFade",'n',0.7,0,1,"darkRimSampleFade",NULL},
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
    {"segmentRimInward",'b',1,0,1,"dockRimInward",NULL},
    {"cardRimInward",'b',1,0,1,"rimInward",NULL},
    {"segmentRimSoftWidth",'n',.8,0,4,"dockRimSoftWidth",NULL},
    {"cardRimSoftWidth",'n',.8,0,4,"rimSoftWidth",NULL},
    {"segmentDarkRimSoftWidth",'n',.8,0,4,"dockDarkRimSoftWidth",NULL},
    {"cardDarkRimSoftWidth",'n',.8,0,4,"darkRimSoftWidth",NULL},
    {"segmentRimSoftLevel",'n',.5,0,1,"dockRimSoftLevel",NULL},
    {"cardRimSoftLevel",'n',.5,0,1,"rimSoftLevel",NULL},
    {"segmentDarkRimSoftLevel",'n',.5,0,1,"dockDarkRimSoftLevel",NULL},
    {"cardDarkRimSoftLevel",'n',.5,0,1,"darkRimSoftLevel",NULL},
    {"segmentRimSampleSoft",'b',1,0,1,"dockRimSampleSoft",NULL},
    {"cardRimSampleSoft",'b',1,0,1,"rimSampleSoft",NULL},
    {"segmentRimSampleSoftWidth",'n',.8,0,4,"dockRimSampleSoftWidth",NULL},
    {"cardRimSampleSoftWidth",'n',.8,0,4,"rimSampleSoftWidth",NULL},
    {"segmentDarkRimSampleSoftWidth",'n',.8,0,4,"dockDarkRimSampleSoftWidth",NULL},
    {"cardDarkRimSampleSoftWidth",'n',.8,0,4,"darkRimSampleSoftWidth",NULL},
    {"segmentRimSampleSoftLevel",'n',.5,0,1,"dockRimSampleSoftLevel",NULL},
    {"cardRimSampleSoftLevel",'n',.5,0,1,"rimSampleSoftLevel",NULL},
    {"segmentDarkRimSampleSoftLevel",'n',.5,0,1,"dockDarkRimSampleSoftLevel",NULL},
    {"cardDarkRimSampleSoftLevel",'n',.5,0,1,"darkRimSampleSoftLevel",NULL},
    {"segmentMaterialHex",'h',0,0,0,"dockMaterialHex","#FFFFFFFF"},
    {"segmentDarkMaterialHex",'h',0,0,0,"dockDarkMaterialHex","#29292BFF"},
    {"segmentMaterialOpacity",'n',.48,0,1,"dockMaterialOpacity",NULL},
    {"segmentDarkMaterialOpacity",'n',.58,0,1,"dockDarkMaterialOpacity",NULL},
    {"segmentMaterialEdgeFadeEnabled",'b',1,0,1,"dockMaterialEdgeFadeEnabled",NULL},
    {"segmentMaterialEdgeFade",'n',10,0,60,"dockMaterialEdgeFade",NULL},
    {"cardMaterialHex",'h',0,0,0,NULL,"#FFFFFFFF"},
    {"cardDarkMaterialHex",'h',0,0,0,NULL,"#2C2C2EFF"},
    {"cardMaterialOpacity",'n',.82,0,1,NULL,NULL},
    {"cardDarkMaterialOpacity",'n',.86,0,1,NULL,NULL},
    {"cardMaterialEdgeFadeEnabled",'b',0,0,1,NULL,NULL},
    {"cardMaterialEdgeFade",'n',0,0,60,NULL,NULL},
    // FIX113 P (user: the segment bar as the dock, tuned from there, not the
    // system's segmented control): its glass, pill and titles start from the
    // dock's (the keys above now inherit the dock's); the pill fades while
    // pressed as the dock's; the selected title in the dock's accent colour.
    {"segmentPillPressedOpacity",'n',.05,0,1,"pressedOpacity",NULL},
    {"segmentAccentOn",'b',1,0,1,NULL,NULL},
    {"segmentAccentHex",'h',0,0,0,"dockAccentHex","#08B861FF"},
    {"segmentDockLook",'b',1,0,1,NULL,NULL},   // marker: the look keys were moved to the dock's once (FIX113 O stored the flat ones)
    // FIX113 T: what the dock's (and the segment bar's) lens draws of the bar
    // seen through it: its outline (off since FIX113 L/N) and its background.
    {"lensBarOutlineOn",'b',0,0,1,NULL,NULL},
    {"lensBarVeilOn",'b',1,0,1,NULL,NULL},
    // FIX113 U (user: the lens should simply refract what lies under it; the
    // bar has one border, refracted it cannot fork): the lens' backdrop
    // captures the bar itself (veil, rim, icons) and refracts it with the
    // page; the shader draws none of the bar again (T's two switches, the
    // inner inset and the bar's split then do nothing). Off: as FIX113 T.
    {"lensRefractsBar",'b',1,0,1,NULL,NULL},
    // FIX113 X (user: the lens' border set like every other glass's, on its
    // own): the 透镜 range of 边框与渐隐 (the dock's lens and the segment bar's):
    // all three rim styles with their values. Starts as the lens' plain line
    // was (colour, opacity, width per appearance; no side fade, no glow); the
    // other styles start from the dock's values.
    {"lensGlassRimHex",'h',0,0,0,"lensRimHex","#FFFFFFFF"},
    {"lensGlassDarkRimHex",'h',0,0,0,"darkLensRimHex","#FFFFFFFF"},
    {"lensGlassRimOpacity",'n',0.5,0,1,"lensRimOpacity",NULL},
    {"lensGlassDarkRimOpacity",'n',0.14,0,1,"darkLensRimOpacity",NULL},
    {"lensGlassBorderWidth",'n',1,0,2,"lensBorderWidth",NULL},
    {"lensGlassDarkBorderWidth",'n',1,0,2,"darkLensBorderWidth",NULL},
    {"lensGlassRimBrightness",'n',1,0,2,"dockRimBrightness",NULL},
    {"lensGlassDarkRimBrightness",'n',1,0,2,"dockDarkRimBrightness",NULL},
    {"lensGlassRimFade",'n',0,0,1,NULL,NULL},
    {"lensGlassDarkRimFade",'n',0,0,1,NULL,NULL},
    {"lensGlassRimStyle",'n',0,0,2,NULL,NULL},
    {"lensGlassRimSampleOpacity",'n',0.5,0,1,"dockRimSampleOpacity",NULL},
    {"lensGlassDarkRimSampleOpacity",'n',0.5,0,1,"dockDarkRimSampleOpacity",NULL},
    {"lensGlassRimSampleWidth",'n',1,0,2,"dockRimSampleWidth",NULL},
    {"lensGlassDarkRimSampleWidth",'n',1,0,2,"dockDarkRimSampleWidth",NULL},
    {"lensGlassRimSampleBrightness",'n',1,0,2,"dockRimSampleBrightness",NULL},
    {"lensGlassDarkRimSampleBrightness",'n',1,0,2,"dockDarkRimSampleBrightness",NULL},
    {"lensGlassRimSampleFade",'n',0.7,0,1,"dockRimSampleFade",NULL},
    {"lensGlassDarkRimSampleFade",'n',0.7,0,1,"dockDarkRimSampleFade",NULL},
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
    {"lensGlassRimInward",'b',0,0,1,NULL,NULL},
    {"lensGlassRimSoftWidth",'n',.8,0,4,"dockRimSoftWidth",NULL},
    {"lensGlassDarkRimSoftWidth",'n',.8,0,4,"dockDarkRimSoftWidth",NULL},
    {"lensGlassRimSoftLevel",'n',.5,0,1,"dockRimSoftLevel",NULL},
    {"lensGlassDarkRimSoftLevel",'n',.5,0,1,"dockDarkRimSoftLevel",NULL},
    {"lensGlassRimSampleSoft",'b',1,0,1,"dockRimSampleSoft",NULL},
    {"lensGlassRimSampleSoftWidth",'n',.8,0,4,"dockRimSampleSoftWidth",NULL},
    {"lensGlassDarkRimSampleSoftWidth",'n',.8,0,4,"dockDarkRimSampleSoftWidth",NULL},
    {"lensGlassRimSampleSoftLevel",'n',.5,0,1,"dockRimSampleSoftLevel",NULL},
    {"lensGlassDarkRimSampleSoftLevel",'n',.5,0,1,"dockDarkRimSampleSoftLevel",NULL},
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
    {"lensElasticHeight",'n',1,0,1,NULL,NULL},
    {"segmentLensElasticOn",'b',1,0,1,"lensElasticOn",NULL},
    {"segmentLensElasticHeight",'n',1,0,1,"lensElasticHeight",NULL},
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
    // FIX122 C (user: only Kyant's 跟随滑动速度形变, in place of the dock's
    // own, adjustable): WXGKyantElastic.h, his values by default, shared by
    // the dock and the segment bar (each keeps its own on / off switch).
    {"lensElasticKyWidth",'n',.75,0,2,NULL,NULL},
    {"lensElasticKyHeight",'n',.25,0,2,NULL,NULL},
    {"lensElasticKyLimit",'n',.2,0,.5,NULL,NULL},
    {"lensElasticKySensitivity",'n',1,0,3,NULL,NULL},
    {"lensElasticKyDamping",'n',.5,.05,1.5,NULL,NULL},
    {"lensElasticKyStiffness",'n',300,20,1500,NULL,NULL},
    {"lensElasticKySymmetric",'b',0,0,1,NULL,NULL},
    // FIX122 D (user: Kyant's refraction for 其余玻璃 next): the other glass'
    // body refracted by his lens() (WXGKyantLens.h) instead of its band:
    // the band and the shift at the outline as shares of the glass' short
    // side (his LiquidButton: lens(12, 24) on 48 dp), depthEffect (his large
    // panels), his colour split's strength (his buttons have none). Ranges
    // sharing 其余玻璃's refraction page (共用) follow it.
    {"kyantOtherOn",'b',0,0,1,NULL,NULL},
    {"kyantOtherHeight",'n',.25,.02,.5,NULL,NULL},
    {"kyantOtherAmount",'n',.5,0,1,NULL,NULL},
    {"kyantOtherDepth",'b',0,0,1,NULL,NULL},
    {"kyantOtherDispersion",'n',0,0,3,NULL,NULL},
    {"kyantOtherMaxHeight",'n',24,4,80,NULL,NULL},
    {"kyantOtherRimFine",'b',0,0,1,NULL,NULL},   // FIX122 E: the thin outermost ring off (capped) by default here
    {"kyantOtherRimMax",'n',3,1,20,NULL,NULL},   // the band at most this (pt), the shift with it in proportion (his panels: 16-24 dp)
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
    {"segmentLensGlassRimHex",'h',0,0,0,"lensGlassRimHex","#FFFFFFFF"},
    {"segmentLensGlassDarkRimHex",'h',0,0,0,"lensGlassDarkRimHex","#FFFFFFFF"},
    {"segmentLensGlassRimOpacity",'n',0.5,0,1,"lensGlassRimOpacity",NULL},
    {"segmentLensGlassDarkRimOpacity",'n',0.14,0,1,"lensGlassDarkRimOpacity",NULL},
    {"segmentLensGlassBorderWidth",'n',1,0,2,"lensGlassBorderWidth",NULL},
    {"segmentLensGlassDarkBorderWidth",'n',1,0,2,"lensGlassDarkBorderWidth",NULL},
    {"segmentLensGlassRimBrightness",'n',1,0,2,"lensGlassRimBrightness",NULL},
    {"segmentLensGlassDarkRimBrightness",'n',1,0,2,"lensGlassDarkRimBrightness",NULL},
    {"segmentLensGlassRimFade",'n',0,0,1,"lensGlassRimFade",NULL},
    {"segmentLensGlassDarkRimFade",'n',0,0,1,"lensGlassDarkRimFade",NULL},
    {"segmentLensGlassRimStyle",'n',0,0,2,"lensGlassRimStyle",NULL},
    {"segmentLensGlassRimSampleOpacity",'n',0.5,0,1,"lensGlassRimSampleOpacity",NULL},
    {"segmentLensGlassDarkRimSampleOpacity",'n',0.5,0,1,"lensGlassDarkRimSampleOpacity",NULL},
    {"segmentLensGlassRimSampleWidth",'n',1,0,2,"lensGlassRimSampleWidth",NULL},
    {"segmentLensGlassDarkRimSampleWidth",'n',1,0,2,"lensGlassDarkRimSampleWidth",NULL},
    {"segmentLensGlassRimSampleBrightness",'n',1,0,2,"lensGlassRimSampleBrightness",NULL},
    {"segmentLensGlassDarkRimSampleBrightness",'n',1,0,2,"lensGlassDarkRimSampleBrightness",NULL},
    {"segmentLensGlassRimSampleFade",'n',0.7,0,1,"lensGlassRimSampleFade",NULL},
    {"segmentLensGlassDarkRimSampleFade",'n',0.7,0,1,"lensGlassDarkRimSampleFade",NULL},
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
    {"segmentLensGlassRimInward",'b',0,0,1,"lensGlassRimInward",NULL},
    {"segmentLensGlassRimSoftWidth",'n',.8,0,4,"lensGlassRimSoftWidth",NULL},
    {"segmentLensGlassDarkRimSoftWidth",'n',.8,0,4,"lensGlassDarkRimSoftWidth",NULL},
    {"segmentLensGlassRimSoftLevel",'n',.5,0,1,"lensGlassRimSoftLevel",NULL},
    {"segmentLensGlassDarkRimSoftLevel",'n',.5,0,1,"lensGlassDarkRimSoftLevel",NULL},
    {"segmentLensGlassRimSampleSoft",'b',1,0,1,"lensGlassRimSampleSoft",NULL},
    {"segmentLensGlassRimSampleSoftWidth",'n',.8,0,4,"lensGlassRimSampleSoftWidth",NULL},
    {"segmentLensGlassDarkRimSampleSoftWidth",'n',.8,0,4,"lensGlassDarkRimSampleSoftWidth",NULL},
    {"segmentLensGlassRimSampleSoftLevel",'n',.5,0,1,"lensGlassRimSampleSoftLevel",NULL},
    {"segmentLensGlassDarkRimSampleSoftLevel",'n',.5,0,1,"lensGlassDarkRimSampleSoftLevel",NULL},
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
    // FIX114 I (user: the original refraction is fine, only where it stops is
    // too obvious; on iOS 26 it fades in): each range's 边界过渡, TEST9's
    // shift mixed toward a soft one that eases out to nothing and never turns
    // back (WXGSoftEdge.h). 0 = exactly as before (the default everywhere).
    // The dock, bubbles and settings pages start as the other glass, the
    // segment bar as the dock (and 套用底栏 copies it).
    {"refractionTransition",'n',0,0,1,NULL,NULL},
    {"dockRefractionTransition",'n',0,0,1,"refractionTransition",NULL},
    {"bubbleRefractionTransition",'n',0,0,1,"refractionTransition",NULL},
    {"cardRefractionTransition",'n',0,0,1,"refractionTransition",NULL},
    {"segmentRefractionTransition",'n',0,0,1,"dockRefractionTransition",NULL},
    // FIX114 J (user: more to adjust in 边界过渡): its soft shift's shape:
    // the band (pt, 0 = automatic), the most the outline is magnified (2.5x),
    // the curve's power (2). The defaults are FIX114 I's.
    {"refractionTransitionWidth",'n',0,0,60,NULL,NULL},
    {"refractionTransitionStretch",'n',2.5,1.2,6,NULL,NULL},
    {"refractionTransitionCurve",'n',2,1.5,4,NULL,NULL},
    {"dockRefractionTransitionWidth",'n',0,0,60,"refractionTransitionWidth",NULL},
    {"dockRefractionTransitionStretch",'n',2.5,1.2,6,"refractionTransitionStretch",NULL},
    {"dockRefractionTransitionCurve",'n',2,1.5,4,"refractionTransitionCurve",NULL},
    {"bubbleRefractionTransitionWidth",'n',0,0,60,"refractionTransitionWidth",NULL},
    {"bubbleRefractionTransitionStretch",'n',2.5,1.2,6,"refractionTransitionStretch",NULL},
    {"bubbleRefractionTransitionCurve",'n',2,1.5,4,"refractionTransitionCurve",NULL},
    {"cardRefractionTransitionWidth",'n',0,0,60,"refractionTransitionWidth",NULL},
    {"cardRefractionTransitionStretch",'n',2.5,1.2,6,"refractionTransitionStretch",NULL},
    {"cardRefractionTransitionCurve",'n',2,1.5,4,"refractionTransitionCurve",NULL},
    {"segmentRefractionTransitionWidth",'n',0,0,60,"dockRefractionTransitionWidth",NULL},
    {"segmentRefractionTransitionStretch",'n',2.5,1.2,6,"dockRefractionTransitionStretch",NULL},
    {"segmentRefractionTransitionCurve",'n',2,1.5,4,"dockRefractionTransitionCurve",NULL},
    // FIX114 J (user: Telegram's glass takes its colour from what is behind
    // it, blur and saturation, no solid layer over it): each range's backdrop
    // saturation (TEST9's 1.05 by default, as before) and brightness (added
    // to every colour, 0 by default), before refraction.
    {"backdropSaturation",'n',1.05,0,3,NULL,NULL},
    {"backdropBrightness",'n',0,-.3,.3,NULL,NULL},
    {"dockBackdropSaturation",'n',1.05,0,3,"backdropSaturation",NULL},
    {"dockBackdropBrightness",'n',0,-.3,.3,"backdropBrightness",NULL},
    {"bubbleBackdropSaturation",'n',1.05,0,3,"backdropSaturation",NULL},
    {"bubbleBackdropBrightness",'n',0,-.3,.3,"backdropBrightness",NULL},
    {"cardBackdropSaturation",'n',1.05,0,3,"backdropSaturation",NULL},
    {"cardBackdropBrightness",'n',0,-.3,.3,"backdropBrightness",NULL},
    {"segmentBackdropSaturation",'n',1.05,0,3,"dockBackdropSaturation",NULL},
    {"segmentBackdropBrightness",'n',0,-.3,.3,"dockBackdropBrightness",NULL},
    // FIX114 J (user: the 取自背景 border wants a colour laid over it as the
    // bubbles have, light and dark): a colour mixed into the colour taken
    // from the background by its alpha, before the 取自背景 processing
    // (alpha 0, the default: as before). Every range of 边框与渐隐.
    {"rimSampleOverlayHex",'h',0,0,0,NULL,"#FFFFFF00"},
    {"darkRimSampleOverlayHex",'h',0,0,0,NULL,"#FFFFFF00"},
    {"dockRimSampleOverlayHex",'h',0,0,0,"rimSampleOverlayHex","#FFFFFF00"},
    {"dockDarkRimSampleOverlayHex",'h',0,0,0,"darkRimSampleOverlayHex","#FFFFFF00"},
    {"bubbleRimSampleOverlayHex",'h',0,0,0,"rimSampleOverlayHex","#FFFFFF00"},
    {"bubbleDarkRimSampleOverlayHex",'h',0,0,0,"darkRimSampleOverlayHex","#FFFFFF00"},
    {"cardRimSampleOverlayHex",'h',0,0,0,"rimSampleOverlayHex","#FFFFFF00"},
    {"cardDarkRimSampleOverlayHex",'h',0,0,0,"darkRimSampleOverlayHex","#FFFFFF00"},
    {"segmentRimSampleOverlayHex",'h',0,0,0,"dockRimSampleOverlayHex","#FFFFFF00"},
    {"segmentDarkRimSampleOverlayHex",'h',0,0,0,"dockDarkRimSampleOverlayHex","#FFFFFF00"},
    {"lensGlassRimSampleOverlayHex",'h',0,0,0,"dockRimSampleOverlayHex","#FFFFFF00"},
    {"lensGlassDarkRimSampleOverlayHex",'h',0,0,0,"dockDarkRimSampleOverlayHex","#FFFFFF00"},
    {"segmentLensGlassRimSampleOverlayHex",'h',0,0,0,"lensGlassRimSampleOverlayHex","#FFFFFF00"},
    {"segmentLensGlassDarkRimSampleOverlayHex",'h',0,0,0,"lensGlassDarkRimSampleOverlayHex","#FFFFFF00"},
    // FIX114 K (user: the shadow iOS 26 puts around its glass): each range's
    // drop shadow (WXGDropShadow.h). Defaults measured on the user's iOS 26
    // screenshot: 0.20 of the shape blurred with sigma 17 pt, 8 pt down. On
    // for the dock, the other glass and the segment bar; off (0) for the
    // bubbles and the settings cards. Light and dark strengths apart.
    {"dropShadowOpacity",'n',.2,0,.6,NULL,NULL},
    {"darkDropShadowOpacity",'n',.2,0,.6,NULL,NULL},
    {"dropShadowBlur",'n',17,.5,40,NULL,NULL},
    {"dropShadowOffset",'n',8,-10,30,NULL,NULL},
    {"dropShadowSpread",'n',0,-10,20,NULL,NULL},
    {"dockDropShadowOpacity",'n',.2,0,.6,"dropShadowOpacity",NULL},
    {"dockDarkDropShadowOpacity",'n',.2,0,.6,"darkDropShadowOpacity",NULL},
    {"dockDropShadowBlur",'n',17,.5,40,"dropShadowBlur",NULL},
    {"dockDropShadowOffset",'n',8,-10,30,"dropShadowOffset",NULL},
    {"dockDropShadowSpread",'n',0,-10,20,"dropShadowSpread",NULL},
    {"bubbleDropShadowOpacity",'n',0,0,.6,NULL,NULL},
    {"bubbleDarkDropShadowOpacity",'n',0,0,.6,NULL,NULL},
    {"bubbleDropShadowBlur",'n',17,.5,40,"dropShadowBlur",NULL},
    {"bubbleDropShadowOffset",'n',8,-10,30,"dropShadowOffset",NULL},
    {"bubbleDropShadowSpread",'n',0,-10,20,"dropShadowSpread",NULL},
    {"cardDropShadowOpacity",'n',0,0,.6,NULL,NULL},
    {"cardDarkDropShadowOpacity",'n',0,0,.6,NULL,NULL},
    {"cardDropShadowBlur",'n',17,.5,40,"dropShadowBlur",NULL},
    {"cardDropShadowOffset",'n',8,-10,30,"dropShadowOffset",NULL},
    {"cardDropShadowSpread",'n',0,-10,20,"dropShadowSpread",NULL},
    {"segmentDropShadowOpacity",'n',.2,0,.6,"dockDropShadowOpacity",NULL},
    {"segmentDarkDropShadowOpacity",'n',.2,0,.6,"dockDarkDropShadowOpacity",NULL},
    {"segmentDropShadowBlur",'n',17,.5,40,"dockDropShadowBlur",NULL},
    {"segmentDropShadowOffset",'n',8,-10,30,"dockDropShadowOffset",NULL},
    {"segmentDropShadowSpread",'n',0,-10,20,"dockDropShadowSpread",NULL},
    // FIX114 L (user: too many settings; a switch at the bottom of a page to
    // use another range's): per page with a range picker and range, which
    // range's settings of that page it uses: 0 its own (the default), else
    // that range + 1 (1 the other glass's, 2 the dock's, as L; FIX114 N: any
    // range of the page: 3 bubble, 4 segment, 5 card, 6 lens, 7 segment lens,
    // and the other glass itself can use another's). Its own values stay (back with 0).
    // FIX114 N (user, 08:35: from a range's page, its settings shared out to
    // the ranges chosen there, like choosing where they apply): the page sets
    // these keys of the ranges chosen (共用到).
    {"otherShareRefraction",'n',0,0,7,NULL,NULL},
    {"dockShareRefraction",'n',0,0,7,NULL,NULL},
    {"bubbleShareRefraction",'n',0,0,7,NULL,NULL},
    {"segmentShareRefraction",'n',0,0,7,NULL,NULL},
    {"cardShareRefraction",'n',0,0,7,NULL,NULL},
    {"otherShareBlur",'n',0,0,7,NULL,NULL},
    {"dockShareBlur",'n',0,0,7,NULL,NULL},
    {"bubbleShareBlur",'n',0,0,7,NULL,NULL},
    {"segmentShareBlur",'n',0,0,7,NULL,NULL},
    {"cardShareBlur",'n',0,0,7,NULL,NULL},
    {"otherShareMaterial",'n',0,0,7,NULL,NULL},
    {"dockShareMaterial",'n',0,0,7,NULL,NULL},
    {"segmentShareMaterial",'n',0,0,7,NULL,NULL},
    {"cardShareMaterial",'n',0,0,7,NULL,NULL},
    {"otherShareBorder",'n',0,0,8,NULL,NULL},
    {"dockShareBorder",'n',0,0,8,NULL,NULL},
    {"bubbleShareBorder",'n',0,0,8,NULL,NULL},
    {"segmentShareBorder",'n',0,0,8,NULL,NULL},
    {"cardShareBorder",'n',0,0,8,NULL,NULL},
    {"lensGlassShareBorder",'n',0,0,8,NULL,NULL},
    {"segmentLensGlassShareBorder",'n',0,0,8,NULL,NULL},
    // FIX115 S (user, 10-27 02:05: "边框自定义"): 视频号's range of 边框与渐隐 (the
    // video feed's capsules), as 分组透镜's keys; light and dark both start
    // from the other glass's dark-appearance values (the look those capsules
    // had: their rim always the dark one's), the style from the other glass's.
    {"finderGlassRimHex",'h',0,0,0,"darkRimHex","#FFFFFFFF"},
    {"finderGlassDarkRimHex",'h',0,0,0,"darkRimHex","#FFFFFFFF"},
    {"finderGlassRimOpacity",'n',0.5,0,1,"darkRimOpacity",NULL},
    {"finderGlassDarkRimOpacity",'n',0.14,0,1,"darkRimOpacity",NULL},
    {"finderGlassBorderWidth",'n',1,0,2,"darkBarBorderWidth",NULL},
    {"finderGlassDarkBorderWidth",'n',1,0,2,"darkBarBorderWidth",NULL},
    {"finderGlassRimBrightness",'n',1,0,2,"darkRimBrightness",NULL},
    {"finderGlassDarkRimBrightness",'n',1,0,2,"darkRimBrightness",NULL},
    {"finderGlassRimFade",'n',0,0,1,"darkRimFade",NULL},
    {"finderGlassDarkRimFade",'n',0,0,1,"darkRimFade",NULL},
    {"finderGlassRimStyle",'n',0,0,2,"rimStyle",NULL},
    {"finderGlassRimSampleOpacity",'n',0.5,0,1,"darkRimSampleOpacity",NULL},
    {"finderGlassDarkRimSampleOpacity",'n',0.5,0,1,"darkRimSampleOpacity",NULL},
    {"finderGlassRimSampleWidth",'n',1,0,2,"darkRimSampleWidth",NULL},
    {"finderGlassDarkRimSampleWidth",'n',1,0,2,"darkRimSampleWidth",NULL},
    {"finderGlassRimSampleBrightness",'n',1,0,2,"darkRimSampleBrightness",NULL},
    {"finderGlassDarkRimSampleBrightness",'n',1,0,2,"darkRimSampleBrightness",NULL},
    {"finderGlassRimSampleFade",'n',0.7,0,1,"darkRimSampleFade",NULL},
    {"finderGlassDarkRimSampleFade",'n',0.7,0,1,"darkRimSampleFade",NULL},
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
    {"finderGlassRimInward",'b',0,0,1,"rimInward",NULL},
    {"finderGlassRimSoftWidth",'n',.8,0,4,"darkRimSoftWidth",NULL},
    {"finderGlassDarkRimSoftWidth",'n',.8,0,4,"darkRimSoftWidth",NULL},
    {"finderGlassRimSoftLevel",'n',.5,0,1,"darkRimSoftLevel",NULL},
    {"finderGlassDarkRimSoftLevel",'n',.5,0,1,"darkRimSoftLevel",NULL},
    {"finderGlassRimSampleSoft",'b',1,0,1,"rimSampleSoft",NULL},
    {"finderGlassRimSampleSoftWidth",'n',.8,0,4,"darkRimSampleSoftWidth",NULL},
    {"finderGlassDarkRimSampleSoftWidth",'n',.8,0,4,"darkRimSampleSoftWidth",NULL},
    {"finderGlassRimSampleSoftLevel",'n',.5,0,1,"darkRimSampleSoftLevel",NULL},
    {"finderGlassDarkRimSampleSoftLevel",'n',.5,0,1,"darkRimSampleSoftLevel",NULL},
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
    {"finderGlassRimSampleOverlayHex",'h',0,0,0,"darkRimSampleOverlayHex","#FFFFFF00"},
    {"finderGlassDarkRimSampleOverlayHex",'h',0,0,0,"darkRimSampleOverlayHex","#FFFFFF00"},
    {"finderGlassShareBorder",'n',0,0,8,NULL,NULL},
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
        if(!prefix.length){if([key hasPrefix:@"rim"] || [key hasPrefix:@"darkRim"])return YES;continue;}
        if(![key hasPrefix:prefix] || ([prefix isEqualToString:@"segment"] && [key hasPrefix:@"segmentLensGlass"]))continue;
        if([[key substringFromIndex:prefix.length] rangeOfString:@"Rim"].location!=NSNotFound)return YES;
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
- (NSUserDefaults *)defaults { return [[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WGLiquidDockDemo"]; }
- (void)loadDefaults {
    _enabled=YES; _calibration=NO; _clearMaterial=YES; _haptics=YES;
    _widthFraction=0.92; _height=68; _lift=12; _refraction=1.15;
    _dispersion=.95; _blur=1.5; _captureFPS=120; _captureBudget=35; _motionPrediction=YES; _renderMode=0; _syncBlurScale=1; _samplerSource=0; _syncPresent=YES; _syncMeshRefraction=YES; _syncDispersion=YES; _syncCaptureScale=0; _lensTopEdgeRatio=1; _lensEdgeSharpness=3;
    _lensBlur=0;_lensBlurCoverage=0;
    _lensRefraction=1.15;_lensDispersion=.95;_lensEdgeWidth=10;
    _alwaysShow=NO; _lensZoom=1.20; _lensGrowth=1.28; _bodyPinch=.18; _edgeWidth=10;
    _selectionInset=6; _selectionOpacity=.30; _pressedOpacity=.05;
    _barBorderWidth=.65; _lensBorderWidth=.65; _borderOpacity=.65;
    _selectionHex=@"#71879EFF"; _borderHex=@"#FFFFFFFF";
    _blurCoverage=0; _useWeChatIcons=YES; _darkSelectionHex=@"#71879EFF";
    _barGrowth=1.025; _endWrap=4; _fadeMaterialAtEdge=YES;
    _materialOpacity=.48; _darkMaterialOpacity=.58; _rimFade=1; _darkRimGain=.22;
    _materialHex=@"#FFFFFFFF"; _darkMaterialHex=@"#29292BFF";
    _renderMode=2;
    _rimHex=@"#FFFFFFFF"; _darkRimHex=@"#FFFFFFFF"; _lensRimHex=@"#FFFFFFFF"; _darkLensRimHex=@"#FFFFFFFF";
    _rimOpacity=.65; _darkRimOpacity=.143; _lensRimOpacity=.65; _darkLensRimOpacity=.143;
    _rimBrightness=1; _darkRimBrightness=1;
    _rimFadeTopLeft=0; _rimFadeBottomRight=0; _darkRimFadeTopLeft=0; _darkRimFadeBottomRight=0; _darkRimFade=1;
    _darkBarBorderWidth=.65; _darkLensBorderWidth=.65;
    _dockMaterialHex=@"#FFFFFFFF"; _dockDarkMaterialHex=@"#29292BFF"; _dockMaterialOpacity=.48; _dockDarkMaterialOpacity=.58;
    _materialFadeWidth=0; _dockMaterialFadeWidth=0; _messageMenuCornerRadius=18; _materialEdgeFade=10;
    _materialEdgeFadeEnabled=YES; _dockMaterialEdgeFadeEnabled=YES; _dockMaterialEdgeFade=10;
    _dockSwitchTiming=0; _dockTapTravel=YES; _performanceMode=NO;
    _dockSearchGap=12; _dockSearchHeightRatio=.82; _dockSearchWidthFraction=.94;
    _pressStretch=YES; _pressStretchDistance=16; _pressStretchAmount=.6; _dockEndStretch=YES; _dockEndStretchDistance=18;   // FIX68
    _pressStretchCapsule=.5; _pressStretchMax=8; _pressStretchFollow=.3;   // FIX80
    // FIX82: liquid bubbles, WeChat's (and MixBubble's) bubble colours.
    _bubbleOutgoingHex=@"#95EC69CC"; _bubbleIncomingHex=@"#FFFFFFCC"; _darkBubbleOutgoingHex=@"#95EC69CC"; _darkBubbleIncomingHex=@"#2C2C2CCC";
    _bubbleEdgeFadeEnabled=YES; _bubbleEdgeFade=8;   // FIX83
    // FIX75 / FIX79: rim details (WXGRimDetail.h), per appearance.
    _rimDetails=YES; _rimOuterFade=.2; _darkRimOuterFade=.2; _rimInnerFade=.3; _darkRimInnerFade=.3; _rimSideLevel=.3; _darkRimSideLevel=.3;
    _rimSideDarken=NO; _darkRimSideDarken=NO;
    _rimInnerShadowOpacity=.10; _darkRimInnerShadowOpacity=.22; _rimInnerShadowRadius=2; _darkRimInnerShadowRadius=2;
    _rimInnerShadowHex=@"#000000FF"; _darkRimInnerShadowHex=@"#000000FF"; _pressStretchNative=YES;
    // FIX76: rim colour from the background.
    _rimSampleColor=YES; _rimSamplePlusLighter=NO; _rimSampleSaturation=1.8; _rimSampleContrast=1; _rimSampleGain=1.35; _rimSampleLift=.08; _rimSampleBlur=3;
    _darkRimSampleSaturation=1.8; _darkRimSampleContrast=1; _darkRimSampleGain=1.35; _darkRimSampleLift=.08; _darkRimSampleBlur=3;
    // FIX64: WeChatFade's own defaults (96 / 112 pt), the blur over the same bands.
    _edgeChatFadeTop=96; _edgeChatFadeBottom=112; _edgeChatBlurTop=96; _edgeChatBlurBottom=112; _edgeChatBlurTopRadius=3; _edgeChatBlurBottomRadius=3;
    _edgeOtherFadeTop=96; _edgeOtherFadeBottom=112; _edgeOtherBlurTop=96; _edgeOtherBlurBottom=112; _edgeOtherBlurTopRadius=3; _edgeOtherBlurBottomRadius=3;
    // FIX58: the dock starts from the same values as the other glass.
    _dockRefraction=_refraction; _dockDispersion=_dispersion; _dockEdgeWidth=_edgeWidth; _dockBlur=_blur; _dockBlurCoverage=_blurCoverage;
    _dockRimHex=_rimHex; _dockDarkRimHex=_darkRimHex; _dockRimOpacity=_rimOpacity; _dockDarkRimOpacity=_darkRimOpacity;
    _dockBorderWidth=_barBorderWidth; _dockDarkBorderWidth=_darkBarBorderWidth;
    _dockRimBrightness=_rimBrightness; _dockDarkRimBrightness=_darkRimBrightness; _dockRimFade=_rimFade; _dockDarkRimFade=_darkRimFade;
    // FIX81: the 边框与渐隐 page (dock and other glass, light and dark, rim
    // details, colour sampling) as the user tuned it on FIX80.
    _rimDetails=YES; _rimOuterFade=.1; _rimInnerFade=.8; _rimSideLevel=.1298; _rimSideDarken=NO; _rimInnerShadowHex=@"#000000FF";
    _rimInnerShadowOpacity=.0145; _rimInnerShadowRadius=1.461; _darkRimOuterFade=.3; _darkRimInnerFade=1.5; _darkRimSideLevel=.5595;
    _darkRimSideDarken=NO; _darkRimInnerShadowHex=@"#000000FF"; _darkRimInnerShadowOpacity=.22; _darkRimInnerShadowRadius=.8711; _rimSampleColor=YES;
    _rimSamplePlusLighter=YES; _rimSampleSaturation=3; _rimSampleGain=.8799; _rimSampleLift=.4852; _rimSampleContrast=1.2569; _rimSampleBlur=10;
    _darkRimSampleSaturation=1.5931; _darkRimSampleGain=2.5; _darkRimSampleLift=.6; _darkRimSampleContrast=.5; _darkRimSampleBlur=10;
    _rimHex=@"#FFFFFFFF"; _dockRimHex=@"#FFFFFFFF"; _rimOpacity=.5057; _dockRimOpacity=.4318; _barBorderWidth=1.2352; _dockBorderWidth=.9871;
    _rimBrightness=1.0008; _dockRimBrightness=1; _rimFade=.7095; _dockRimFade=0; _lensRimHex=@"#FFFFFFFF"; _lensRimOpacity=.5859;
    _lensBorderWidth=1.1029; _darkRimHex=@"#C2C2C2FF"; _dockDarkRimHex=@"#FFFFFFFF"; _darkRimOpacity=.1361; _dockDarkRimOpacity=.228;
    _darkBarBorderWidth=.9691; _dockDarkBorderWidth=1.0093; _darkRimBrightness=.8572; _dockDarkRimBrightness=.5456; _darkRimFade=1;
    _dockDarkRimFade=0; _darkLensRimHex=@"#D6D6D6FF"; _darkLensRimOpacity=.2696; _darkLensBorderWidth=.6892;
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
    if(!strcmp(spec->key,"rimStyle"))value=@(_rimSampleColor?WXGRimStyleSampled:WXGRimStyleClassic);
    // FIX113 X: the lens' line was drawn at the dock rim's brightness of the
    // dock's style (iOS 27: 1; 取自背景: that style's own).
    if(!strcmp(spec->key,"lensGlassRimBrightness") || !strcmp(spec->key,"lensGlassDarkRimBrightness")) {
        BOOL dark=!strcmp(spec->key,"lensGlassDarkRimBrightness");
        long style=lround([_extra[@"dockRimStyle"] doubleValue]);
        if(style==WXGRimStyleGlow)value=@1;
        else if(style==WXGRimStyleSampled)value=_extra[dark?@"dockDarkRimSampleBrightness":@"dockRimSampleBrightness"]?:@1;
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
        BOOL rederive=!strcmp(spec->key,"rimStyle")?[changed containsObject:@"rimSampleColor"]:
                      spec->inherit && [changed containsObject:@(spec->inherit)];
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
    // FIX85: an export from before the rim styles: its colour switch is the style.
    if(!defaults[@"rimStyle"] && [defaults[@"rimSampleColor"] isKindOfClass:NSNumber.class]) {
        NSMutableDictionary *d=[defaults mutableCopy];d[@"rimStyle"]=@([defaults[@"rimSampleColor"] boolValue]?WXGRimStyleSampled:WXGRimStyleClassic);defaults=d;
    }
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
- (NSArray *)baseKeys { return @[@"lensBlur",@"lensBlurCoverage",@"lensRefraction",@"lensDispersion",@"lensEdgeWidth",@"enabled",@"calibration",@"clearMaterial",@"haptics",@"widthFraction",@"height",@"lift",@"refraction",@"dispersion",@"blur",@"captureFPS",@"captureBudget",@"motionPrediction",@"renderMode",@"syncBlurScale",@"samplerSource",@"syncPresent",@"syncMeshRefraction",@"syncDispersion",@"syncCaptureScale",@"lensTopEdgeRatio",@"lensEdgeSharpness",@"alwaysShow",@"lensZoom",@"lensGrowth",@"bodyPinch",@"edgeWidth",@"selectionInset",@"selectionOpacity",@"pressedOpacity",@"barBorderWidth",@"lensBorderWidth",@"borderOpacity",@"selectionHex",@"darkSelectionHex",@"blurCoverage",@"useWeChatIcons",@"borderHex",@"barGrowth",@"endWrap",@"fadeMaterialAtEdge",@"materialOpacity",@"darkMaterialOpacity",@"rimFade",@"darkRimGain",@"materialHex",@"darkMaterialHex",@"rimHex",@"darkRimHex",@"lensRimHex",@"darkLensRimHex",@"rimOpacity",@"darkRimOpacity",@"lensRimOpacity",@"darkLensRimOpacity",@"rimBrightness",@"darkRimBrightness",@"rimFadeTopLeft",@"rimFadeBottomRight",@"darkRimFadeTopLeft",@"darkRimFadeBottomRight",@"darkRimFade",@"darkBarBorderWidth",@"darkLensBorderWidth",@"dockMaterialHex",@"dockDarkMaterialHex",@"dockMaterialOpacity",@"dockDarkMaterialOpacity",@"materialFadeWidth",@"dockMaterialFadeWidth",@"messageMenuCornerRadius",@"materialEdgeFade",@"materialEdgeFadeEnabled",@"dockMaterialEdgeFadeEnabled",@"dockMaterialEdgeFade",@"dockSwitchTiming",@"dockTapTravel",
    @"dockRefraction",@"dockDispersion",@"dockEdgeWidth",@"dockBlur",@"dockBlurCoverage",@"dockRimHex",@"dockDarkRimHex",@"dockRimOpacity",@"dockDarkRimOpacity",
    @"dockBorderWidth",@"dockDarkBorderWidth",@"dockRimBrightness",@"dockDarkRimBrightness",@"dockRimFade",@"dockDarkRimFade",@"performanceMode",
    @"dockSearchGap",@"dockSearchHeightRatio",@"dockSearchWidthFraction",
    @"edgeChatFadeTop",@"edgeChatFadeBottom",@"edgeChatBlurTop",@"edgeChatBlurBottom",@"edgeChatBlurTopRadius",@"edgeChatBlurBottomRadius",
    @"edgeOtherFadeTop",@"edgeOtherFadeBottom",@"edgeOtherBlurTop",@"edgeOtherBlurBottom",@"edgeOtherBlurTopRadius",@"edgeOtherBlurBottomRadius",
    @"pressStretch",@"pressStretchDistance",@"pressStretchAmount",@"pressStretchCapsule",@"pressStretchMax",@"pressStretchFollow",@"bubbleOutgoingHex",@"bubbleIncomingHex",@"darkBubbleOutgoingHex",@"darkBubbleIncomingHex",@"bubbleEdgeFadeEnabled",@"bubbleEdgeFade",@"dockEndStretch",@"dockEndStretchDistance",
    @"rimDetails",@"rimSideLevel",@"darkRimSideLevel",@"rimOuterFade",@"darkRimOuterFade",@"rimInnerFade",@"darkRimInnerFade",
    @"rimSideDarken",@"darkRimSideDarken",@"rimInnerShadowOpacity",@"darkRimInnerShadowOpacity",@"rimInnerShadowRadius",@"darkRimInnerShadowRadius",
    @"rimInnerShadowHex",@"darkRimInnerShadowHex",@"pressStretchNative",
    @"rimSampleColor",@"rimSamplePlusLighter",@"rimSampleSaturation",@"rimSampleContrast",@"rimSampleGain",@"rimSampleLift",@"rimSampleBlur",
    @"darkRimSampleSaturation",@"darkRimSampleContrast",@"darkRimSampleGain",@"darkRimSampleLift",@"darkRimSampleBlur"]; }
- (NSArray *)keys {
    static NSArray *all;static dispatch_once_t once;
    dispatch_once(&once,^{all=[self.baseKeys arrayByAddingObjectsFromArray:WXGExtraKeys()];});
    return all;
}
- (instancetype)init {
    if((self=[super init])) {
        [self loadDefaults];
        NSDictionary *d=[[self defaults] dictionaryForKey:@"config.v9"];
        BOOL migrating=!d;
        if(!d) d=[[self defaults] dictionaryForKey:@"config.v8"];
        BOOL hasModern=d!=nil;
        if(!d) d=[[self defaults] dictionaryForKey:@"config.v6"];
        if(!d) d=[[self defaults] dictionaryForKey:@"config.v5"];
        if(!d) d=[[self defaults] dictionaryForKey:@"config.v4"];
        for(NSString *key in [self keys]) {
            id value=d[key]; BOOL color=[key hasSuffix:@"Hex"];
            if(color?[value isKindOfClass:NSString.class]:[value isKindOfClass:NSNumber.class]) [self setValue:value forKey:key];
        }
        // Restore TEST6 visual tuning, retaining only current visibility toggles.
        // TEST7 optical/material experiments must not leak into this rollback.
        if(migrating && !hasModern) {
            NSDictionary *visible=[[self defaults] dictionaryForKey:@"config.v7"];
            for(NSString *key in @[@"enabled",@"alwaysShow"]) {
                id value=visible[key];
                if([value isKindOfClass:NSNumber.class]) [self setValue:value forKey:key];
            }
        }
        if(migrating && !d[@"darkSelectionHex"]) _darkSelectionHex=_selectionHex;
        // Adopt the new white rim only when the previous default is untouched.
        // Preserve a custom white (or any other user-chosen) border and all sizes.
        if(migrating && !hasModern && [WXGNormalizeHex(_borderHex) isEqual:@"#72869AFF"]) _borderHex=@"#FFFFFFFF";
        // Roll back to the user's TEST9 optical values. Do not import TEST3R's
        // experimental gradients, lens material or scale/reveal settings.
        _lensRefraction=_refraction;_lensDispersion=_dispersion;_lensEdgeWidth=_edgeWidth;
        if(_captureFPS==60)_captureFPS=120;
        NSDictionary *local=[[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] dictionaryForKey:@"optics.test4"];
        for(NSString *key in self.keys) {
            id value=local[key];BOOL color=[key hasSuffix:@"Hex"];
            if(color?[value isKindOfClass:NSString.class]:[value isKindOfClass:NSNumber.class])[self setValue:value forKey:key];
        }
        // FIX27: first run after the split takes every new per-appearance and
        // dock value from what the user had tuned in the shared settings.
        if(!local[@"rimHex"])_rimHex=_borderHex;
        if(!local[@"darkRimHex"])_darkRimHex=_borderHex;
        if(!local[@"lensRimHex"])_lensRimHex=_rimHex;
        if(!local[@"darkLensRimHex"])_darkLensRimHex=_darkRimHex;
        if(!local[@"rimOpacity"])_rimOpacity=_borderOpacity;
        if(!local[@"darkRimOpacity"])_darkRimOpacity=_borderOpacity*_darkRimGain;
        if(!local[@"lensRimOpacity"])_lensRimOpacity=_rimOpacity;
        if(!local[@"darkLensRimOpacity"])_darkLensRimOpacity=_darkRimOpacity;
        if(!local[@"darkRimFade"])_darkRimFade=_rimFade;
        if(!local[@"darkBarBorderWidth"])_darkBarBorderWidth=_barBorderWidth;
        if(!local[@"darkLensBorderWidth"])_darkLensBorderWidth=_lensBorderWidth;
        if(!local[@"dockMaterialHex"])_dockMaterialHex=_materialHex;
        if(!local[@"dockDarkMaterialHex"])_dockDarkMaterialHex=_darkMaterialHex;
        if(!local[@"dockMaterialOpacity"])_dockMaterialOpacity=_materialOpacity;
        if(!local[@"dockDarkMaterialOpacity"])_dockDarkMaterialOpacity=_darkMaterialOpacity;
        // FIX28: the edge weakening becomes one range (0 = none). Keep the
        // current look: off stays 0; on uses the FIX27 range or, if that was 0,
        // the refraction width it stood for.
        if(!local[@"materialEdgeFade"])
            _materialEdgeFade=!_fadeMaterialAtEdge?0:(_materialFadeWidth>0?_materialFadeWidth:_edgeWidth);
        // FIX29: split into dock / other glass, each with a switch and a range.
        // Same look as before for both; a range of 0 meant "off".
        if(!local[@"materialEdgeFadeEnabled"]) {
            _materialEdgeFadeEnabled=_materialEdgeFade>.01;
            if(_materialEdgeFade<=.01)_materialEdgeFade=_edgeWidth;
        }
        if(!local[@"dockMaterialEdgeFadeEnabled"])_dockMaterialEdgeFadeEnabled=_materialEdgeFadeEnabled;
        if(!local[@"dockMaterialEdgeFade"])_dockMaterialEdgeFade=_materialEdgeFade;
        // FIX58: the dock gets its own body optics and rim; the first run takes
        // the values the user had tuned for all glass, so the dock looks the same.
        if(!local[@"dockRefraction"])_dockRefraction=_refraction;
        if(!local[@"dockDispersion"])_dockDispersion=_dispersion;
        if(!local[@"dockEdgeWidth"])_dockEdgeWidth=_edgeWidth;
        if(!local[@"dockBlur"])_dockBlur=_blur;
        if(!local[@"dockBlurCoverage"])_dockBlurCoverage=_blurCoverage;
        if(!local[@"dockRimHex"])_dockRimHex=_rimHex;
        if(!local[@"dockDarkRimHex"])_dockDarkRimHex=_darkRimHex;
        if(!local[@"dockRimOpacity"])_dockRimOpacity=_rimOpacity;
        if(!local[@"dockDarkRimOpacity"])_dockDarkRimOpacity=_darkRimOpacity;
        if(!local[@"dockBorderWidth"])_dockBorderWidth=_barBorderWidth;
        if(!local[@"dockDarkBorderWidth"])_dockDarkBorderWidth=_darkBarBorderWidth;
        if(!local[@"dockRimBrightness"])_dockRimBrightness=_rimBrightness;
        if(!local[@"dockDarkRimBrightness"])_dockDarkRimBrightness=_darkRimBrightness;
        if(!local[@"dockRimFade"])_dockRimFade=_rimFade;
        if(!local[@"dockDarkRimFade"])_dockDarkRimFade=_darkRimFade;
        // FIX79: the rim details and the colour sampling were shared by both
        // appearances; the first run gives dark mode the values tuned so far.
        if(!local[@"darkRimSideLevel"])_darkRimSideLevel=_rimSideLevel;
        if(!local[@"darkRimInnerShadowRadius"])_darkRimInnerShadowRadius=_rimInnerShadowRadius;
        if(!local[@"darkRimSampleSaturation"])_darkRimSampleSaturation=_rimSampleSaturation;
        if(!local[@"darkRimSampleContrast"])_darkRimSampleContrast=_rimSampleContrast;
        if(!local[@"darkRimSampleGain"])_darkRimSampleGain=_rimSampleGain;
        if(!local[@"darkRimSampleLift"])_darkRimSampleLift=_rimSampleLift;
        if(!local[@"darkRimSampleBlur"])_darkRimSampleBlur=_rimSampleBlur;
        // FIX59: a fresh install takes this build's defaults as they are (the
        // migrations above derive values for old configurations only).
        // FIX81: a fresh install is exactly 恢复默认 (the migrations above
        // derive values from older configurations; with none, they would
        // overwrite the defaults with the old shared ones).
        // FIX85: a table key never stored starts from its source's value as
        // loaded above (the user's own), the rim style from the colour switch.
        for(size_t i=0;i<WXGExtraCount;i++) {
            id stored=local[@(WXGExtraSpecs[i].key)];
            BOOL valid=WXGExtraSpecs[i].kind=='h'?[stored isKindOfClass:NSString.class]:[stored isKindOfClass:NSNumber.class];
            if(!valid)[self inheritExtra:i];
        }
        // FIX113 P: FIX113 O stored the segment bar's flat look (no refraction,
        // blur or rim, a dark material, the page-coloured pill); once, those
        // keys start again from the dock's (its lens keys were the dock's already).
        if(local && ![local[@"segmentDockLook"] isKindOfClass:NSNumber.class])[self segmentLikeDock:NO];
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
        // FIX99: the tap's move and drop moved to new keys (faster defaults);
        // a FIX98 value the tester had changed from its default comes along.
        if(local) {
            NSNumber *move=local[@"dockTapDurationScale"],*drop=local[@"dockTapDropDuration"];
            if(!local[@"dockTapMoveScale"] && [move isKindOfClass:NSNumber.class] && fabs(move.doubleValue-1.5)>.001)_extra[@"dockTapMoveScale"]=move;
            if(!local[@"dockTapDropTime"] && [drop isKindOfClass:NSNumber.class] && fabs(drop.doubleValue-.26)>.001)_extra[@"dockTapDropTime"]=drop;
            NSNumber *moment=local[@"dockTapSwitchMoment"];   // FIX100
            if(!local[@"dockTapSwitchWhen"] && [moment isKindOfClass:NSNumber.class] && lround(moment.doubleValue)!=1)
                _extra[@"dockTapSwitchWhen"]=@(MIN(3,MAX(1,lround(moment.doubleValue)+1)));
        }
        if(!local && !d)[self loadDefaults];
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
    if (!isfinite(_refraction)) _refraction=1.15;
    if (!isfinite(_dispersion)) _dispersion=.95;
    if (!isfinite(_blur)) _blur=1.5;
    _widthFraction=WXGClamp(_widthFraction,.65,.98); _height=WXGClamp(_height,54,90);
    _lift=WXGClamp(_lift,-80,160); _refraction=WXGClamp(_refraction,0,20);
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
    if(!isfinite(_bubbleEdgeFade))_bubbleEdgeFade=8;
    _bubbleEdgeFade=WXGClamp(_bubbleEdgeFade,0,30);
    _pressStretchCapsule=WXGClamp(_pressStretchCapsule,0,1);_pressStretchMax=WXGClamp(_pressStretchMax,1,20);_pressStretchFollow=WXGClamp(_pressStretchFollow,0,1);
    // FIX75: rim details.
    // FIX79: side fades in 0.1 pt steps.
    CGFloat *fades[]={&_rimOuterFade,&_darkRimOuterFade,&_rimInnerFade,&_darkRimInnerFade};
    for(size_t i=0;i<sizeof fades/sizeof *fades;i++)*fades[i]=isfinite(*fades[i])?round(WXGClamp(*fades[i],0,1.5)*10)/10:.2;
    if(!isfinite(_rimSideLevel))_rimSideLevel=.3;
    if(!isfinite(_darkRimSideLevel))_darkRimSideLevel=_rimSideLevel;
    if(!isfinite(_rimInnerShadowOpacity))_rimInnerShadowOpacity=.10;
    if(!isfinite(_darkRimInnerShadowOpacity))_darkRimInnerShadowOpacity=.22;
    if(!isfinite(_rimInnerShadowRadius))_rimInnerShadowRadius=2;
    if(!isfinite(_darkRimInnerShadowRadius))_darkRimInnerShadowRadius=_rimInnerShadowRadius;
    _rimSideLevel=WXGClamp(_rimSideLevel,0,1);_darkRimSideLevel=WXGClamp(_darkRimSideLevel,0,1);
    _rimInnerShadowOpacity=WXGClamp(_rimInnerShadowOpacity,0,.6);_darkRimInnerShadowOpacity=WXGClamp(_darkRimInnerShadowOpacity,0,.6);
    _rimInnerShadowRadius=WXGClamp(_rimInnerShadowRadius,.3,6);_darkRimInnerShadowRadius=WXGClamp(_darkRimInnerShadowRadius,.3,6);
    if(!isfinite(_rimSampleSaturation))_rimSampleSaturation=1.8;
    if(!isfinite(_rimSampleContrast))_rimSampleContrast=1;
    if(!isfinite(_rimSampleGain))_rimSampleGain=1.35;
    if(!isfinite(_rimSampleLift))_rimSampleLift=.08;
    if(!isfinite(_rimSampleBlur))_rimSampleBlur=3;
    if(!isfinite(_darkRimSampleSaturation))_darkRimSampleSaturation=_rimSampleSaturation;
    if(!isfinite(_darkRimSampleContrast))_darkRimSampleContrast=_rimSampleContrast;
    if(!isfinite(_darkRimSampleGain))_darkRimSampleGain=_rimSampleGain;
    if(!isfinite(_darkRimSampleLift))_darkRimSampleLift=_rimSampleLift;
    if(!isfinite(_darkRimSampleBlur))_darkRimSampleBlur=_rimSampleBlur;
    _rimSampleSaturation=WXGClamp(_rimSampleSaturation,0,3);_rimSampleContrast=WXGClamp(_rimSampleContrast,.5,2);
    _rimSampleGain=WXGClamp(_rimSampleGain,.5,2.5);_rimSampleLift=WXGClamp(_rimSampleLift,0,.6);_rimSampleBlur=WXGClamp(_rimSampleBlur,0,10);
    _darkRimSampleSaturation=WXGClamp(_darkRimSampleSaturation,0,3);_darkRimSampleContrast=WXGClamp(_darkRimSampleContrast,.5,2);
    _darkRimSampleGain=WXGClamp(_darkRimSampleGain,.5,2.5);_darkRimSampleLift=WXGClamp(_darkRimSampleLift,0,.6);_darkRimSampleBlur=WXGClamp(_darkRimSampleBlur,0,10);
    _rimInnerShadowHex=WXGNormalizeHex(_rimInnerShadowHex)?:@"#000000FF";_darkRimInnerShadowHex=WXGNormalizeHex(_darkRimInnerShadowHex)?:@"#000000FF";
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
    _dispersion=WXGClamp(_dispersion,0,8); _blur=WXGClamp(_blur,0,12);
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
    if(!isfinite(_lensBlurCoverage))_lensBlurCoverage=0;
    _lensBlur=WXGClamp(_lensBlur,0,12);_lensBlurCoverage=WXGClamp(_lensBlurCoverage,0,100);
    if(!isfinite(_lensRefraction))_lensRefraction=_refraction;
    if(!isfinite(_lensDispersion))_lensDispersion=_dispersion;
    if(!isfinite(_lensEdgeWidth))_lensEdgeWidth=10;
    _lensRefraction=WXGClamp(_lensRefraction,0,20);_lensDispersion=WXGClamp(_lensDispersion,0,8);_lensEdgeWidth=WXGClamp(_lensEdgeWidth,1,60);
    if(!isfinite(_lensTopEdgeRatio))_lensTopEdgeRatio=1;
    if(!isfinite(_lensEdgeSharpness))_lensEdgeSharpness=3;
    _lensTopEdgeRatio=WXGClamp(_lensTopEdgeRatio,.1,1);_lensEdgeSharpness=WXGClamp(_lensEdgeSharpness,1,6);
    if (!isfinite(_lensZoom)) _lensZoom=1.20;
    if (!isfinite(_lensGrowth)) _lensGrowth=1.28;
    if (!isfinite(_bodyPinch)) _bodyPinch=.18;
    if (!isfinite(_edgeWidth)) _edgeWidth=10;
    _lensZoom=WXGClamp(_lensZoom,1,1.5); _lensGrowth=WXGClamp(_lensGrowth,1.08,1.5);
    _bodyPinch=WXGClamp(_bodyPinch,0,.30); _edgeWidth=WXGClamp(_edgeWidth,1,60);
    if(!isfinite(_selectionInset)) _selectionInset=6;
    if(!isfinite(_selectionOpacity)) _selectionOpacity=.30;
    if(!isfinite(_pressedOpacity)) _pressedOpacity=.05;
    if(!isfinite(_barBorderWidth)) _barBorderWidth=.65;
    if(!isfinite(_lensBorderWidth)) _lensBorderWidth=.65;
    if(!isfinite(_borderOpacity)) _borderOpacity=.65;
    _selectionInset=WXGClamp(_selectionInset,2,14);
    _selectionOpacity=WXGClamp(_selectionOpacity,0,.75); _pressedOpacity=WXGClamp(_pressedOpacity,0,.4);
    _barBorderWidth=WXGClamp(_barBorderWidth,0,2); _lensBorderWidth=WXGClamp(_lensBorderWidth,0,2);
    _borderOpacity=WXGClamp(_borderOpacity,0,1);
    _selectionHex=WXGNormalizeHex(_selectionHex)?:@"#71879EFF";
    _darkSelectionHex=WXGNormalizeHex(_darkSelectionHex)?:_selectionHex;
    if(!isfinite(_blurCoverage)) _blurCoverage=0;
    _blurCoverage=WXGClamp(_blurCoverage,0,100);
    _borderHex=WXGNormalizeHex(_borderHex)?:@"#FFFFFFFF";
    if(!isfinite(_barGrowth)) _barGrowth=1.025;
    if(!isfinite(_endWrap)) _endWrap=4;
    if(!isfinite(_materialOpacity)) _materialOpacity=.48;
    if(!isfinite(_darkMaterialOpacity)) _darkMaterialOpacity=.58;
    if(!isfinite(_rimFade)) _rimFade=1;
    if(!isfinite(_darkRimGain)) _darkRimGain=.22;
    _barGrowth=WXGClamp(_barGrowth,1,1.08); _endWrap=WXGClamp(_endWrap,2,10);
    _materialOpacity=WXGClamp(_materialOpacity,0,.95); _darkMaterialOpacity=WXGClamp(_darkMaterialOpacity,0,.95);
    _rimFade=WXGClamp(_rimFade,0,1); _darkRimGain=WXGClamp(_darkRimGain,0,1);
    _materialHex=WXGNormalizeHex(_materialHex)?:@"#FFFFFFFF";
    _darkMaterialHex=WXGNormalizeHex(_darkMaterialHex)?:@"#29292BFF";
    _rimHex=WXGNormalizeHex(_rimHex)?:@"#FFFFFFFF";_darkRimHex=WXGNormalizeHex(_darkRimHex)?:@"#FFFFFFFF";
    _lensRimHex=WXGNormalizeHex(_lensRimHex)?:_rimHex;_darkLensRimHex=WXGNormalizeHex(_darkLensRimHex)?:_darkRimHex;
    _dockMaterialHex=WXGNormalizeHex(_dockMaterialHex)?:_materialHex;_dockDarkMaterialHex=WXGNormalizeHex(_dockDarkMaterialHex)?:_darkMaterialHex;
    CGFloat *unit[]={&_rimOpacity,&_darkRimOpacity,&_lensRimOpacity,&_darkLensRimOpacity,&_rimFadeTopLeft,&_rimFadeBottomRight,
                     &_darkRimFadeTopLeft,&_darkRimFadeBottomRight,&_darkRimFade};
    for(size_t i=0;i<sizeof unit/sizeof *unit;i++)*unit[i]=isfinite(*unit[i])?WXGClamp(*unit[i],0,1):0;
    if(!isfinite(_rimBrightness))_rimBrightness=1;
    if(!isfinite(_darkRimBrightness))_darkRimBrightness=1;
    _rimBrightness=WXGClamp(_rimBrightness,0,2);_darkRimBrightness=WXGClamp(_darkRimBrightness,0,2);
    if(!isfinite(_darkBarBorderWidth))_darkBarBorderWidth=_barBorderWidth;
    if(!isfinite(_darkLensBorderWidth))_darkLensBorderWidth=_lensBorderWidth;
    _darkBarBorderWidth=WXGClamp(_darkBarBorderWidth,0,2);_darkLensBorderWidth=WXGClamp(_darkLensBorderWidth,0,2);
    if(!isfinite(_dockMaterialOpacity))_dockMaterialOpacity=_materialOpacity;
    if(!isfinite(_dockDarkMaterialOpacity))_dockDarkMaterialOpacity=_darkMaterialOpacity;
    _dockMaterialOpacity=WXGClamp(_dockMaterialOpacity,0,.95);_dockDarkMaterialOpacity=WXGClamp(_dockDarkMaterialOpacity,0,.95);
    if(!isfinite(_materialFadeWidth))_materialFadeWidth=0;
    if(!isfinite(_dockMaterialFadeWidth))_dockMaterialFadeWidth=0;
    _materialFadeWidth=WXGClamp(_materialFadeWidth,0,40);_dockMaterialFadeWidth=WXGClamp(_dockMaterialFadeWidth,0,40);
    if(!isfinite(_messageMenuCornerRadius))_messageMenuCornerRadius=18;
    _messageMenuCornerRadius=WXGClamp(_messageMenuCornerRadius,0,40);
    if(!isfinite(_materialEdgeFade))_materialEdgeFade=0;
    _materialEdgeFade=WXGClamp(_materialEdgeFade,0,60);
    if(!isfinite(_dockMaterialEdgeFade))_dockMaterialEdgeFade=10;
    _dockMaterialEdgeFade=WXGClamp(_dockMaterialEdgeFade,0,60);
    // FIX58: the dock's own body optics and rim, same ranges as the shared ones.
    if(!isfinite(_dockRefraction))_dockRefraction=_refraction;
    if(!isfinite(_dockDispersion))_dockDispersion=_dispersion;
    if(!isfinite(_dockEdgeWidth))_dockEdgeWidth=_edgeWidth;
    if(!isfinite(_dockBlur))_dockBlur=_blur;
    if(!isfinite(_dockBlurCoverage))_dockBlurCoverage=_blurCoverage;
    _dockRefraction=WXGClamp(_dockRefraction,0,20);_dockDispersion=WXGClamp(_dockDispersion,0,8);_dockEdgeWidth=WXGClamp(_dockEdgeWidth,1,60);
    _dockBlur=WXGClamp(_dockBlur,0,12);_dockBlurCoverage=WXGClamp(_dockBlurCoverage,0,100);
    _dockRimHex=WXGNormalizeHex(_dockRimHex)?:_rimHex;_dockDarkRimHex=WXGNormalizeHex(_dockDarkRimHex)?:_darkRimHex;
    CGFloat *dockUnit[]={&_dockRimOpacity,&_dockDarkRimOpacity,&_dockRimFade,&_dockDarkRimFade};
    for(size_t i=0;i<sizeof dockUnit/sizeof *dockUnit;i++)*dockUnit[i]=isfinite(*dockUnit[i])?WXGClamp(*dockUnit[i],0,1):0;
    if(!isfinite(_dockBorderWidth))_dockBorderWidth=_barBorderWidth;
    if(!isfinite(_dockDarkBorderWidth))_dockDarkBorderWidth=_darkBarBorderWidth;
    _dockBorderWidth=WXGClamp(_dockBorderWidth,0,2);_dockDarkBorderWidth=WXGClamp(_dockDarkBorderWidth,0,2);
    if(!isfinite(_dockRimBrightness))_dockRimBrightness=1;
    if(!isfinite(_dockDarkRimBrightness))_dockDarkRimBrightness=1;
    _dockRimBrightness=WXGClamp(_dockRimBrightness,0,2);_dockDarkRimBrightness=WXGClamp(_dockDarkRimBrightness,0,2);
    // FIX37: removed settings (user): the switch is always forwarded at once,
    // and iOS 26 rims only fade on the bottom-left / top-right diagonals.
    _dockSwitchTiming=0;
    _rimFadeTopLeft=_rimFadeBottomRight=_darkRimFadeTopLeft=_darkRimFadeBottomRight=0;
    // FIX85: the table's keys.
    if(!_extra)[self loadExtraDefaults];
    for(size_t i=0;i<WXGExtraCount;i++) {
        const WXGExtraSpec *spec=&WXGExtraSpecs[i];NSString *key=@(spec->key);id value=_extra[key];
        if(spec->kind=='h'){_extra[key]=WXGNormalizeHex(value)?:@(spec->hex?:"#FFFFFFFF");continue;}
        double v=[value isKindOfClass:NSNumber.class]?[value doubleValue]:spec->def;
        if(!isfinite(v))v=spec->def;
        if(spec->kind=='b'){_extra[key]=@(v>.5);continue;}
        v=WXGClamp(v,spec->lo,spec->hi);
        if(!strcmp(spec->key,"rimStyle") || !strcmp(spec->key,"dockRimStyle") || !strcmp(spec->key,"bubbleRimStyle"))v=round(v);
        if(strstr(spec->key,"Share"))v=round(v);   // FIX114 L: a choice
        _extra[key]=@(v);
    }
    _rimSampleColor=[self rimStyleValue]==WXGRimStyleSampled;
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
// FIX113 P: the segment bar's glass, pill and titles (all: its lens too)
// from the dock's values now.
- (void)segmentLikeDock:(BOOL)all {
    static NSSet<NSString *> *look;static dispatch_once_t once;
    dispatch_once(&once,^{look=[NSSet setWithArray:@[@"segmentRefraction",@"segmentDispersion",@"segmentBlur",@"segmentBlurCoverage",@"segmentEdgeWidth",@"segmentRefractionTransition",
        @"segmentRefractionTransitionWidth",@"segmentRefractionTransitionStretch",@"segmentRefractionTransitionCurve",@"segmentBackdropSaturation",@"segmentBackdropBrightness",
        @"segmentRimSampleOverlayHex",@"segmentDarkRimSampleOverlayHex",@"segmentDropShadowOpacity",@"segmentDarkDropShadowOpacity",
        @"segmentDropShadowBlur",@"segmentDropShadowOffset",@"segmentDropShadowSpread",
        @"segmentRimOpacity",@"segmentDarkRimOpacity",@"segmentRimStyle",@"segmentRimSampleOpacity",@"segmentDarkRimSampleOpacity",
        @"segmentRim27Opacity",@"segmentDarkRim27Opacity",@"segmentMaterialHex",@"segmentDarkMaterialHex",@"segmentMaterialOpacity",
        @"segmentDarkMaterialOpacity",@"segmentMaterialEdgeFadeEnabled",@"segmentMaterialEdgeFade",@"segmentPillAuto",@"segmentPillHex",
        @"segmentDarkPillHex",@"segmentPillOpacity",@"segmentDarkPillOpacity",@"segmentPillPressedOpacity",@"segmentInkHex",@"segmentDarkInkHex"]];});
    for(size_t i=0;i<WXGExtraCount;i++) {
        NSString *key=@(WXGExtraSpecs[i].key);
        if(![key hasPrefix:@"segment"] || [key isEqual:@"segmentDockLook"])continue;
        if(!(all?WXGExtraSpecs[i].inherit!=NULL:[look containsObject:key]))continue;
        [self inheritExtra:i];
    }
    // FIX113 Z: the segment bar's iOS 27 dark-mode highlights as the dock's
    // dark mode (they inherit from the segment bar's own light mode).
    for(size_t i=0;i<WXGExtraCount;i++) {
        NSString *key=@(WXGExtraSpecs[i].key);
        if(![key hasPrefix:@"segment"] || [key rangeOfString:@"Rim27DarkMode"].location==NSNotFound)continue;
        NSString *light=[key stringByReplacingOccurrencesOfString:@"Rim27DarkMode" withString:@"Rim27"];
        if(!all && ![look containsObject:light])continue;
        id value=_extra[[@"dock" stringByAppendingString:[key substringFromIndex:7]]];
        if(value)_extra[key]=value;
    }
    _extra[@"segmentDockLook"]=@1;
}
- (void)segmentFromDock {
    [self segmentLikeDock:YES];
    // the titles and the pill's "page colour" as the dock has them
    _extra[@"segmentPillAuto"]=@0;_extra[@"segmentAccentOn"]=@1;
    _extra[@"segmentInkHex"]=@"#1A1A1AEB";_extra[@"segmentDarkInkHex"]=@"#F7F7F7F7";
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
- (WXGScopeOptics)rawOpticsForDock:(BOOL)dock {
    return dock?(WXGScopeOptics){_dockRefraction,_dockDispersion,_dockEdgeWidth,_dockBlur,_dockBlurCoverage}
               :(WXGScopeOptics){_refraction,_dispersion,_edgeWidth,_blur,_blurCoverage};
}
- (WXGRimSampleTuning)rimSampleTuningDark:(BOOL)dark {
    if(dark)return (WXGRimSampleTuning){_darkRimSampleSaturation,_darkRimSampleContrast,_darkRimSampleGain,_darkRimSampleLift,_darkRimSampleBlur};
    return (WXGRimSampleTuning){_rimSampleSaturation,_rimSampleContrast,_rimSampleGain,_rimSampleLift,_rimSampleBlur};
}
- (WXGScopeRim)rimForDock:(BOOL)dock dark:(BOOL)dark {return [self rimForScope:dock?WXGGlassScopeDock:WXGGlassScopeOther dark:dark];}
- (NSString *)rimHexForDock:(BOOL)dock dark:(BOOL)dark {return dock?(dark?_dockDarkRimHex:_dockRimHex):(dark?_darkRimHex:_rimHex);}
- (NSDictionary *)parameterValues {return [self dictionaryWithValuesForKeys:[self keys]];}
#pragma mark FIX85 scopes and rim styles
- (WXGRimStyle)rimStyleValue {return [self rimStyleForScope:WXGGlassScopeOther];}
// FIX86: the dock, the other glass and the bubbles each choose their style.
- (WXGRimStyle)rimStyleForScope:(WXGGlassScope)scope {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    return (WXGRimStyle)lround(WXGClamp([self extraNumber:WXGScopedKey(scope,NO,@"RimStyle")],0,2));
}
- (BOOL)bubbleFullGlass {return [self extraNumber:@"bubbleFullGlass"]>.5;}
// FIX113 O: the ranges kept in the table (bubbles, 分组, 设置页).
static BOOL WXGTableScope(WXGGlassScope scope) {return scope==WXGGlassScopeBubble || scope==WXGGlassScopeSegment || scope==WXGGlassScopeCard || scope==WXGGlassScopeLens || scope==WXGGlassScopeSegmentLens || scope==WXGGlassScopeFinder;}
- (WXGScopeOptics)ownOpticsForScope:(WXGGlassScope)scope {
    if(WXGTableScope(scope))
        return (WXGScopeOptics){[self extraNumber:WXGScopedKey(scope,NO,@"Refraction")],[self extraNumber:WXGScopedKey(scope,NO,@"Dispersion")],
                                [self extraNumber:WXGScopedKey(scope,NO,@"EdgeWidth")],[self extraNumber:WXGScopedKey(scope,NO,@"Blur")],
                                [self extraNumber:WXGScopedKey(scope,NO,@"BlurCoverage")]};
    return [self rawOpticsForDock:scope==WXGGlassScopeDock];
}
// FIX114 L: refraction from the range 折射 shares with, blur from 模糊's.
- (WXGScopeOptics)opticsForScope:(WXGGlassScope)scope {
    WXGGlassScope r=[self sharedScope:scope page:WXGSharePageRefraction],b=[self sharedScope:scope page:WXGSharePageBlur];
    WXGScopeOptics o=[self ownOpticsForScope:r];
    if(b!=r){WXGScopeOptics ob=[self ownOpticsForScope:b];o.blur=ob.blur;o.blurCoverage=ob.blurCoverage;}
    return o;
}
// FIX114 L: the range whose settings of a page this one uses (a chain: the
// segment bar as the dock, the dock as the other glass). Literal keys.
static NSString *const WXGShareKeys[WXG_SHARE_RANGES][WXG_SHARE_PAGES]={
    {@"otherShareRefraction",@"otherShareBlur",@"otherShareMaterial",@"otherShareBorder"},
    {@"dockShareRefraction",@"dockShareBlur",@"dockShareMaterial",@"dockShareBorder"},
    {@"bubbleShareRefraction",@"bubbleShareBlur",nil,@"bubbleShareBorder"},
    {@"segmentShareRefraction",@"segmentShareBlur",@"segmentShareMaterial",@"segmentShareBorder"},
    {@"cardShareRefraction",@"cardShareBlur",@"cardShareMaterial",@"cardShareBorder"},
    {nil,nil,nil,@"lensGlassShareBorder"},
    {nil,nil,nil,@"segmentLensGlassShareBorder"},
    {nil,nil,nil,@"finderGlassShareBorder"}};   // FIX115 S
static long WXGShareValue(void *context,int range,int page) {
    NSString *key=WXGShareKeys[range][page];
    return key?lround([(__bridge WXGConfig *)context extraNumber:key]):0;
}
// FIX114 N: the chain in WXGShareChain.h (Tests/ShareChainTests.c).
- (WXGGlassScope)sharedScope:(WXGGlassScope)scope page:(WXGSharePage)page {
    static unsigned char present[WXG_SHARE_RANGES][WXG_SHARE_PAGES];static dispatch_once_t once;
    dispatch_once(&once,^{for(int r=0;r<WXG_SHARE_RANGES;r++)for(int p=0;p<WXG_SHARE_PAGES;p++)present[r][p]=WXGShareKeys[r][p]!=nil;});
    return (WXGGlassScope)WXGShareResolve((int)scope,(int)page,present,WXGShareValue,(__bridge void *)self);
}
// FIX114 I / J: a range's 边界过渡 and its shape (the lens borders' ranges
// are their glass's). Literal keys: this runs every frame for every glass.
static NSInteger WXGGlassRow(WXGGlassScope scope) {
    return scope==WXGGlassScopeDock || scope==WXGGlassScopeLens?1:scope==WXGGlassScopeBubble?2:
           scope==WXGGlassScopeSegment || scope==WXGGlassScopeSegmentLens?3:scope==WXGGlassScopeCard?4:0;
}
- (WXGTransitionSettings)refractionTransitionForScope:(WXGGlassScope)scope {
    static NSString *const keys[5][4]={
        {@"refractionTransition",@"refractionTransitionWidth",@"refractionTransitionStretch",@"refractionTransitionCurve"},
        {@"dockRefractionTransition",@"dockRefractionTransitionWidth",@"dockRefractionTransitionStretch",@"dockRefractionTransitionCurve"},
        {@"bubbleRefractionTransition",@"bubbleRefractionTransitionWidth",@"bubbleRefractionTransitionStretch",@"bubbleRefractionTransitionCurve"},
        {@"segmentRefractionTransition",@"segmentRefractionTransitionWidth",@"segmentRefractionTransitionStretch",@"segmentRefractionTransitionCurve"},
        {@"cardRefractionTransition",@"cardRefractionTransitionWidth",@"cardRefractionTransitionStretch",@"cardRefractionTransitionCurve"}};
    NSString *const *k=keys[WXGGlassRow([self sharedScope:scope page:WXGSharePageRefraction])];   // FIX114 L
    return (WXGTransitionSettings){WXGClamp([self extraNumber:k[0]],0,1),WXGClamp([self extraNumber:k[1]],0,60),
                                   WXGClamp([self extraNumber:k[2]],1.2,6),WXGClamp([self extraNumber:k[3]],1.5,4)};
}
// FIX114 J: a range's backdrop saturation and brightness.
- (WXGBackdropTone)backdropToneForScope:(WXGGlassScope)scope {
    static NSString *const keys[5][2]={{@"backdropSaturation",@"backdropBrightness"},{@"dockBackdropSaturation",@"dockBackdropBrightness"},
        {@"bubbleBackdropSaturation",@"bubbleBackdropBrightness"},{@"segmentBackdropSaturation",@"segmentBackdropBrightness"},
        {@"cardBackdropSaturation",@"cardBackdropBrightness"}};
    NSString *const *k=keys[WXGGlassRow([self sharedScope:scope page:WXGSharePageBlur])];   // FIX114 L
    return (WXGBackdropTone){WXGClamp([self extraNumber:k[0]],0,3),WXGClamp([self extraNumber:k[1]],-.3,.3)};
}
// FIX114 K: a range's drop shadow (the lens borders' ranges are their glass's).
- (WXGDropShadowSettings)dropShadowForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    static NSString *const keys[5][5]={
        {@"dropShadowOpacity",@"darkDropShadowOpacity",@"dropShadowBlur",@"dropShadowOffset",@"dropShadowSpread"},
        {@"dockDropShadowOpacity",@"dockDarkDropShadowOpacity",@"dockDropShadowBlur",@"dockDropShadowOffset",@"dockDropShadowSpread"},
        {@"bubbleDropShadowOpacity",@"bubbleDarkDropShadowOpacity",@"bubbleDropShadowBlur",@"bubbleDropShadowOffset",@"bubbleDropShadowSpread"},
        {@"segmentDropShadowOpacity",@"segmentDarkDropShadowOpacity",@"segmentDropShadowBlur",@"segmentDropShadowOffset",@"segmentDropShadowSpread"},
        {@"cardDropShadowOpacity",@"cardDarkDropShadowOpacity",@"cardDropShadowBlur",@"cardDropShadowOffset",@"cardDropShadowSpread"}};
    NSString *const *k=keys[WXGGlassRow([self sharedScope:scope page:WXGSharePageBorder])];   // FIX114 L
    return (WXGDropShadowSettings){WXGClamp([self extraNumber:k[dark?1:0]],0,.6),WXGClamp([self extraNumber:k[2]],.5,40),
                                   WXGClamp([self extraNumber:k[3]],-10,30),WXGClamp([self extraNumber:k[4]],-10,20)};
}
// FIX114 J: the 取自背景 colour overlay of a range of 边框与渐隐 (its own, the lenses' too).
- (NSString *)rimSampleOverlayHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    return [self extraHex:WXGScopedKey(scope,dark,@"RimSampleOverlayHex")];
}
// FIX113 O: a range's material (the bubbles tint themselves: the other glass's).
- (NSString *)materialHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageMaterial];   // FIX114 L
    if(scope==WXGGlassScopeSegment || scope==WXGGlassScopeCard)return [self extraHex:WXGScopedKey(scope,dark,@"MaterialHex")];
    if(scope==WXGGlassScopeDock)return dark?_dockDarkMaterialHex:_dockMaterialHex;
    return dark?_darkMaterialHex:_materialHex;
}
- (CGFloat)materialOpacityForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageMaterial];   // FIX114 L
    if(scope==WXGGlassScopeSegment || scope==WXGGlassScopeCard)return WXGClamp([self extraNumber:WXGScopedKey(scope,dark,@"MaterialOpacity")],0,1);
    if(scope==WXGGlassScopeDock)return dark?_dockDarkMaterialOpacity:_dockMaterialOpacity;
    return dark?_darkMaterialOpacity:_materialOpacity;
}
- (BOOL)materialEdgeFadeOnForScope:(WXGGlassScope)scope {
    scope=[self sharedScope:scope page:WXGSharePageMaterial];   // FIX114 L
    if(scope==WXGGlassScopeSegment || scope==WXGGlassScopeCard)return [self extraNumber:WXGScopedKey(scope,NO,@"MaterialEdgeFadeEnabled")]>.5;
    return scope==WXGGlassScopeDock?_dockMaterialEdgeFadeEnabled:_materialEdgeFadeEnabled;
}
- (CGFloat)materialEdgeFadeForScope:(WXGGlassScope)scope {
    scope=[self sharedScope:scope page:WXGSharePageMaterial];   // FIX114 L
    if(scope==WXGGlassScopeSegment || scope==WXGGlassScopeCard)return [self extraNumber:WXGScopedKey(scope,NO,@"MaterialEdgeFade")];
    return scope==WXGGlassScopeDock?_dockMaterialEdgeFade:_materialEdgeFade;
}
// FIX113 O: the lens of a range: the segment bar's own, every other the dock's.
// FIX122 D: Kyant's lens() on a glass' body: 其余玻璃's, and any range
// sharing its refraction page.
- (WXGKyantBody)kyantBodyForScope:(WXGGlassScope)scope {
    WXGKyantBody k={NO,0,0,0,0,0,0};
    if([self sharedScope:scope page:WXGSharePageRefraction]!=WXGGlassScopeOther || [self extraNumber:@"kyantOtherOn"]<=.5)return k;
    k.on=YES;k.height=WXGClamp([self extraNumber:@"kyantOtherHeight"],.02,.5);k.amount=WXGClamp([self extraNumber:@"kyantOtherAmount"],0,1);
    k.depth=[self extraNumber:@"kyantOtherDepth"]>.5?1:0;k.dispersion=WXGClamp([self extraNumber:@"kyantOtherDispersion"],0,3);
    k.maxHeight=WXGClamp([self extraNumber:@"kyantOtherMaxHeight"],4,80);
    k.rimMax=[self extraNumber:@"kyantOtherRimFine"]>.5?0:WXGClamp([self extraNumber:@"kyantOtherRimMax"],1,20);   // FIX122 E
    return k;
}
// FIX122 C: Kyant's drag-speed deformation, as set (WXGKyantElastic.h).
- (WXGKyantElasticParams)kyantElasticParams {
    WXGKyantElasticParams p;
    p.width=WXGClamp([self extraNumber:@"lensElasticKyWidth"],0,2);p.height=WXGClamp([self extraNumber:@"lensElasticKyHeight"],0,2);
    p.limit=WXGClamp([self extraNumber:@"lensElasticKyLimit"],0,.5);p.sensitivity=WXGClamp([self extraNumber:@"lensElasticKySensitivity"],0,3);
    p.damping=WXGClamp([self extraNumber:@"lensElasticKyDamping"],.05,1.5);p.stiffness=WXGClamp([self extraNumber:@"lensElasticKyStiffness"],20,1500);
    p.symmetric=[self extraNumber:@"lensElasticKySymmetric"]>.5;
    return p;
}
- (WXGLensSettings)lensSettingsForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    WXGLensSettings l;
    if(scope==WXGGlassScopeSegment) {
        // Literal keys: this runs a few times a frame while the bar draws.
        l.refraction=[self extraNumber:@"segmentLensRefraction"];l.dispersion=[self extraNumber:@"segmentLensDispersion"];l.edgeWidth=[self extraNumber:@"segmentLensEdgeWidth"];
        l.topRatio=[self extraNumber:@"segmentLensTopEdgeRatio"];l.sharpness=[self extraNumber:@"segmentLensEdgeSharpness"];
        l.dispersionWidth=[self extraNumber:@"segmentLensDispersionWidth"];l.dispersionTopRatio=[self extraNumber:@"segmentLensDispersionTopRatio"];
        l.zoom=[self extraNumber:@"segmentLensZoom"];l.growth=[self extraNumber:@"segmentLensGrowth"];l.barGrowth=[self extraNumber:@"segmentBarGrowth"];
        l.endWrap=[self extraNumber:@"segmentEndWrap"];l.pinch=[self extraNumber:@"segmentBodyPinch"];
        l.blur=[self extraNumber:@"segmentLensBlur"];l.blurCoverage=[self extraNumber:@"segmentLensBlurCoverage"];l.cancelSetting=[self extraNumber:@"segmentLensOffsetCancel"];
        l.rimOpacity=[self extraNumber:dark?@"segmentDarkLensRimOpacity":@"segmentLensRimOpacity"];l.borderWidth=[self extraNumber:dark?@"segmentDarkLensBorderWidth":@"segmentLensBorderWidth"];l.rimAtRest=WXGClamp([self extraNumber:@"segmentPillRimAtRest"],0,1);
        l.tintOn=[self extraNumber:@"segmentLensTintOn"]>.5;l.tintOpacity=[self extraNumber:dark?@"segmentDarkLensTintOpacity":@"segmentLensTintOpacity"];
        l.barDispersionOn=[self extraNumber:@"segmentLensBarDispersionOn"]>.5;l.barDispersion=[self extraNumber:@"segmentLensBarDispersion"];
        l.barDispersionNearRim=[self extraNumber:@"segmentLensBarDispersionNearRim"];l.selectionInset=[self extraNumber:@"segmentSelectionInset"];
        l.iconRefraction=[self extraNumber:@"segmentLensIconRefraction"];l.iconEdgeWidth=[self extraNumber:@"segmentLensIconEdgeWidth"];
        l.iconTopRatio=[self extraNumber:@"segmentLensIconTopEdgeRatio"];l.iconSharpness=[self extraNumber:@"segmentLensIconEdgeSharpness"];
        l.elasticOn=[self extraNumber:@"segmentLensElasticOn"]>.5;l.elasticHeight=[self extraNumber:@"segmentLensElasticHeight"];
        l.elasticKeepStrip=[self extraNumber:@"segmentLensElasticKeepStrip"];
        l.kyantOn=[self extraNumber:@"segmentLensKyantOn"]>.5;l.kyantHeight=[self extraNumber:@"segmentLensKyantHeight"];   // FIX122
        l.kyantAmount=[self extraNumber:@"segmentLensKyantAmount"];l.kyantDispersion=[self extraNumber:@"segmentLensKyantDispersion"];
        l.kyantRimMax=[self extraNumber:@"segmentLensKyantRimFine"]>.5?0:WXGClamp([self extraNumber:@"segmentLensKyantRimMax"],1,20);   // FIX122 E
    }else {
        l.refraction=_lensRefraction;l.dispersion=_lensDispersion;l.edgeWidth=_lensEdgeWidth;l.topRatio=_lensTopEdgeRatio;l.sharpness=_lensEdgeSharpness;
        l.dispersionWidth=[self extraNumber:@"lensDispersionWidth"];l.dispersionTopRatio=[self extraNumber:@"lensDispersionTopRatio"];
        l.zoom=_lensZoom;l.growth=_lensGrowth;l.barGrowth=_barGrowth;l.endWrap=_endWrap;l.pinch=_bodyPinch;
        l.blur=_lensBlur;l.blurCoverage=_lensBlurCoverage;l.cancelSetting=[self extraNumber:@"lensOffsetCancel"];
        l.rimOpacity=dark?_darkLensRimOpacity:_lensRimOpacity;l.borderWidth=dark?_darkLensBorderWidth:_lensBorderWidth;l.rimAtRest=0;
        l.tintOn=[self extraNumber:@"lensTintOn"]>.5;l.tintOpacity=[self extraNumber:dark?@"darkLensTintOpacity":@"lensTintOpacity"];
        l.barDispersionOn=[self extraNumber:@"lensBarDispersionOn"]>.5;l.barDispersion=[self extraNumber:@"lensBarDispersion"];
        l.barDispersionNearRim=[self extraNumber:@"lensBarDispersionNearRim"];l.selectionInset=_selectionInset;
        l.iconRefraction=[self extraNumber:@"lensIconRefraction"];l.iconEdgeWidth=[self extraNumber:@"lensIconEdgeWidth"];
        l.iconTopRatio=[self extraNumber:@"lensIconTopEdgeRatio"];l.iconSharpness=[self extraNumber:@"lensIconEdgeSharpness"];
        l.elasticOn=[self extraNumber:@"lensElasticOn"]>.5;l.elasticHeight=[self extraNumber:@"lensElasticHeight"];
        l.elasticKeepStrip=[self extraNumber:@"lensElasticKeepStrip"];
        l.kyantOn=[self extraNumber:@"lensKyantOn"]>.5;l.kyantHeight=[self extraNumber:@"lensKyantHeight"];   // FIX122
        l.kyantAmount=[self extraNumber:@"lensKyantAmount"];l.kyantDispersion=[self extraNumber:@"lensKyantDispersion"];
        l.kyantRimMax=[self extraNumber:@"lensKyantRimFine"]>.5?0:WXGClamp([self extraNumber:@"lensKyantRimMax"],1,20);   // FIX122 E
    }
    return l;
}
- (UIColor *)lensRimLineColorDark:(BOOL)dark width:(CGFloat *)width {
    if([self rimStyleForScope:WXGGlassScopeLens]==WXGRimStyleGlow) {
        WXGRimGlowShape g=[self rimGlowForScope:WXGGlassScopeLens index:0 dark:dark];
        if(width)*width=WXGClamp(g.width*.5,.3,1.5);
        return [UIColor colorWithRed:g.red green:g.green blue:g.blue alpha:WXGClamp(g.alpha,0,1)];
    }
    WXGScopeRim rim=[self rimForScope:WXGGlassScopeLens dark:dark];
    if(width)*width=rim.width;
    UIColor *color=WXGColor([self rimHexForScope:WXGGlassScopeLens dark:dark])?:UIColor.whiteColor;
    return [color colorWithAlphaComponent:WXGClamp(CGColorGetAlpha(color.CGColor)*rim.opacity,0,1)];
}
- (NSString *)lensRimHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    if(scope==WXGGlassScopeSegment)return [self extraHex:dark?@"segmentDarkLensRimHex":@"segmentLensRimHex"];
    return dark?_darkLensRimHex:_lensRimHex;
}
- (NSString *)lensTintHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    if(scope==WXGGlassScopeSegment)return [self extraHex:dark?@"segmentDarkLensTintHex":@"segmentLensTintHex"];
    return [self extraHex:dark?@"darkLensTintHex":@"lensTintHex"];
}
// FIX113 O: a key this configuration holds (a property of the list or a table key).
- (BOOL)knowsKey:(NSString *)key {return key && (WXGExtraIndex()[key]!=nil || [self.keys containsObject:key]);}
- (WXGScopeRim)classicRimForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    if(WXGTableScope(scope))
        return (WXGScopeRim){[self extraNumber:WXGScopedKey(scope,dark,@"RimOpacity")],[self extraNumber:WXGScopedKey(scope,dark,@"BorderWidth")],
                             [self extraNumber:WXGScopedKey(scope,dark,@"RimBrightness")],[self extraNumber:WXGScopedKey(scope,dark,@"RimFade")]};
    BOOL dock=scope==WXGGlassScopeDock;
    if(dock)return dark?(WXGScopeRim){_dockDarkRimOpacity,_dockDarkBorderWidth,_dockDarkRimBrightness,_dockDarkRimFade}
                       :(WXGScopeRim){_dockRimOpacity,_dockBorderWidth,_dockRimBrightness,_dockRimFade};
    return dark?(WXGScopeRim){_darkRimOpacity,_darkBarBorderWidth,_darkRimBrightness,_darkRimFade}
               :(WXGScopeRim){_rimOpacity,_barBorderWidth,_rimBrightness,_rimFade};
}
- (WXGScopeRim)rimForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    switch([self rimStyleForScope:scope]) {
        case WXGRimStyleSampled:
            return (WXGScopeRim){[self extraNumber:WXGScopedKey(scope,dark,@"RimSampleOpacity")],[self extraNumber:WXGScopedKey(scope,dark,@"RimSampleWidth")],
                                 [self extraNumber:WXGScopedKey(scope,dark,@"RimSampleBrightness")],[self extraNumber:WXGScopedKey(scope,dark,@"RimSampleFade")]};
        case WXGRimStyleGlow: {
            // FIX89: the two highlights carry their own colours and opacities
            // (rimGlowForScope:index:); no fade along the outline (nor on the
            // lens's rim, which shares it).
            WXGRimGlowShape shape=[self rimGlowForScope:scope index:0 dark:dark];
            return (WXGScopeRim){1,MIN(1.,shape.width*.5),1,0};
        }
        default:return [self classicRimForScope:scope dark:dark];
    }
}
// FIX109 B: the line's soft glow: its width (0 = off: the plain line) and
// level, of the range's style (FIX109 C: 普通 and 取自背景 each their own;
// iOS 27 none).
- (CGFloat)rimSoftWidthForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    WXGRimStyle style=[self rimStyleForScope:scope];if(style==WXGRimStyleGlow)return 0;
    BOOL sampled=style==WXGRimStyleSampled;
    if([self extraNumber:WXGScopedKey(scope,NO,sampled?@"RimSampleSoft":@"RimInward")]<=.5)return 0;
    return WXGClamp([self extraNumber:WXGScopedKey(scope,dark,sampled?@"RimSampleSoftWidth":@"RimSoftWidth")],0,4);
}
- (CGFloat)rimSoftLevelForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    BOOL sampled=[self rimStyleForScope:scope]==WXGRimStyleSampled;
    return WXGClamp([self extraNumber:WXGScopedKey(scope,dark,sampled?@"RimSampleSoftLevel":@"RimSoftLevel")],0,1);
}
- (NSString *)rimHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
    if([self rimStyleForScope:scope]==WXGRimStyleGlow)return [self extraHex:WXGScopedKey(scope,NO,dark?@"Rim27DarkModeHex":@"Rim27Hex")];   // FIX89: the first highlight's (FIX113 Z: this appearance's)
    if(WXGTableScope(scope))return [self extraHex:WXGScopedKey(scope,dark,@"RimHex")];
    return [self rimHexForDock:scope==WXGGlassScopeDock dark:dark];
}
- (CGFloat)dockIconTitleGap {return [self extraNumber:@"dockIconTitleGap"];}
- (CGFloat)dockIconOffset {return [self extraNumber:@"dockIconOffset"];}
- (CGFloat)dockTitleSize {return [self extraNumber:@"dockTitleSize"];}
- (NSInteger)dockTitleWeight {return (NSInteger)lround([self extraNumber:@"dockTitleWeight"]);}
- (BOOL)dockTitleBolderSelected {return [self extraNumber:@"dockTitleBolderSelected"]>.5;}
- (BOOL)lensBarDispersionOn {return [self extraNumber:@"lensBarDispersionOn"]>.5;}
- (CGFloat)lensBarDispersion {return [self extraNumber:@"lensBarDispersion"];}
- (CGFloat)lensBarDispersionNearRim {return [self extraNumber:@"lensBarDispersionNearRim"];}
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
- (CGFloat)lensDispersionWidth {return [self extraNumber:@"lensDispersionWidth"];}
- (CGFloat)lensDispersionTopRatio {return [self extraNumber:@"lensDispersionTopRatio"];}
// FIX89: the iOS 27-like rim's two highlights, drawn together whatever the
// appearance: 0 from the keys that were light mode's, 1 from dark mode's (so
// an upgrade keeps both as they were set, now on screen at once).
// FIX113 Z: and per appearance: dark mode's two from the …Rim27DarkMode… keys.
- (WXGRimGlowShape)rimGlowForScope:(WXGGlassScope)scope index:(NSInteger)index dark:(BOOL)dark {
    scope=[self sharedScope:scope page:WXGSharePageBorder];   // FIX114 L
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
