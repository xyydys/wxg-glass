#import "WXGCommon.h"
#include <stdarg.h>

NSString * const WXGSettingsChanged = @"com.runyu.WGLiquidDockDemo.settings";
static NSMutableArray<NSString *> *WXGMessages;

void WXGLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    @synchronized(WXGConfig.class) {
        if (!WXGMessages) WXGMessages = [NSMutableArray array];
        [WXGMessages addObject:[NSString stringWithFormat:@"%.3f %@", CACurrentMediaTime(), message]];
        if (WXGMessages.count > 160) [WXGMessages removeObjectAtIndex:0];
    }
    NSLog(@"[WeChatLiquidGlass] %@", message);
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
    {"dockTitleWeight",'n',2,0,4,NULL,NULL},      // FIX91: 0 light .. 4 bold (2 medium)
    {"dockTitleBolderSelected",'b',0,0,1,NULL,NULL},   // FIX91: the selected title one step bolder (always before)
    // FIX94's bar following the rim; FIX95: off for everyone (a new key, so
    // FIX94's "on" is not carried over: the tester did not want it).
    {"lensBarFollowOn",'b',0,0,1,NULL,NULL},
    {"lensBarMargin",'n',.5,.2,1,NULL,NULL},      // FIX94: its distance from the rim, a share of the band
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
    // FIX95: the chat title's avatar (头像模式): its size and height (pt,
    // scaled with 截图比例微调), the ring's width and colour per appearance.
    {"avatarSize",'n',60,32,88,NULL,NULL},
    {"avatarOffsetY",'n',0,-24,24,NULL,NULL},
    {"avatarBorderWidth",'n',1.5,0,4,NULL,NULL},
    {"avatarBorderHex",'h',0,0,0,NULL,"#80808052"},
    {"avatarDarkBorderHex",'h',0,0,0,NULL,"#9E9E9E6B"},
    {"lensDispersionWidth",'n',10,1,60,"lensEdgeWidth",NULL},
    {"lensDispersionTopRatio",'n',1,0.1,1,"lensTopEdgeRatio",NULL},
    // FIX88: 平稳背景时加强材质 again (FIX85, removed in FIX86).
    {"calmMaterial",'b',0,0,1,NULL,NULL},
    {"calmMaterialOpacity",'n',0.82,0,0.98,NULL,NULL},
    {"darkCalmMaterialOpacity",'n',0.82,0,0.98,NULL,NULL},
    {"dockCalmMaterialOpacity",'n',0.82,0,0.98,NULL,NULL},
    {"dockDarkCalmMaterialOpacity",'n',0.82,0,0.98,NULL,NULL},
    {"calmThreshold",'n',0.06,0.005,0.4,NULL,NULL},
    {"calmRange",'n',0.05,0.005,0.4,NULL,NULL},
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
    if(dark)return [@"dark" stringByAppendingString:stem];
    return [[stem substringToIndex:1].lowercaseString stringByAppendingString:[stem substringFromIndex:1]];
}
@interface WXGConfig () {
    NSMutableDictionary<NSString *,id> *_extra;
}
@end

@implementation WXGConfig
+ (instancetype)shared { static WXGConfig *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [self new]; }); return value; }
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
    NSDictionary *defaults=WXGBuildDefaultOptics();
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
- (WXGScopeOptics)opticsForDock:(BOOL)dock {
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
    NSString *key=scope==WXGGlassScopeDock?@"dockRimStyle":scope==WXGGlassScopeBubble?@"bubbleRimStyle":@"rimStyle";
    return (WXGRimStyle)lround(WXGClamp([self extraNumber:key],0,2));
}
- (BOOL)bubbleFullGlass {return [self extraNumber:@"bubbleFullGlass"]>.5;}
- (WXGScopeOptics)opticsForScope:(WXGGlassScope)scope {
    if(scope==WXGGlassScopeBubble)
        return (WXGScopeOptics){[self extraNumber:@"bubbleRefraction"],[self extraNumber:@"bubbleDispersion"],[self extraNumber:@"bubbleEdgeWidth"],
                                [self extraNumber:@"bubbleBlur"],[self extraNumber:@"bubbleBlurCoverage"]};
    return [self opticsForDock:scope==WXGGlassScopeDock];
}
- (WXGScopeRim)classicRimForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    if(scope==WXGGlassScopeBubble)
        return (WXGScopeRim){[self extraNumber:WXGScopedKey(scope,dark,@"RimOpacity")],[self extraNumber:WXGScopedKey(scope,dark,@"BorderWidth")],
                             [self extraNumber:WXGScopedKey(scope,dark,@"RimBrightness")],[self extraNumber:WXGScopedKey(scope,dark,@"RimFade")]};
    BOOL dock=scope==WXGGlassScopeDock;
    if(dock)return dark?(WXGScopeRim){_dockDarkRimOpacity,_dockDarkBorderWidth,_dockDarkRimBrightness,_dockDarkRimFade}
                       :(WXGScopeRim){_dockRimOpacity,_dockBorderWidth,_dockRimBrightness,_dockRimFade};
    return dark?(WXGScopeRim){_darkRimOpacity,_darkBarBorderWidth,_darkRimBrightness,_darkRimFade}
               :(WXGScopeRim){_rimOpacity,_barBorderWidth,_rimBrightness,_rimFade};
}
- (WXGScopeRim)rimForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    switch([self rimStyleForScope:scope]) {
        case WXGRimStyleSampled:
            return (WXGScopeRim){[self extraNumber:WXGScopedKey(scope,dark,@"RimSampleOpacity")],[self extraNumber:WXGScopedKey(scope,dark,@"RimSampleWidth")],
                                 [self extraNumber:WXGScopedKey(scope,dark,@"RimSampleBrightness")],[self extraNumber:WXGScopedKey(scope,dark,@"RimSampleFade")]};
        case WXGRimStyleGlow: {
            // FIX89: the two highlights carry their own colours and opacities
            // (rimGlowForScope:index:); no fade along the outline (nor on the
            // lens's rim, which shares it).
            WXGRimGlowShape shape=[self rimGlowForScope:scope index:0];
            return (WXGScopeRim){1,MIN(1.,shape.width*.5),1,0};
        }
        default:return [self classicRimForScope:scope dark:dark];
    }
}
- (NSString *)rimHexForScope:(WXGGlassScope)scope dark:(BOOL)dark {
    if([self rimStyleForScope:scope]==WXGRimStyleGlow)return [self extraHex:WXGScopedKey(scope,NO,@"Rim27Hex")];   // FIX89: the first highlight's
    if(scope==WXGGlassScopeBubble)return [self extraHex:WXGScopedKey(scope,dark,@"RimHex")];
    return [self rimHexForDock:scope==WXGGlassScopeDock dark:dark];
}
- (CGFloat)dockIconTitleGap {return [self extraNumber:@"dockIconTitleGap"];}
- (CGFloat)dockIconOffset {return [self extraNumber:@"dockIconOffset"];}
- (CGFloat)dockTitleSize {return [self extraNumber:@"dockTitleSize"];}
- (NSInteger)dockTitleWeight {return (NSInteger)lround([self extraNumber:@"dockTitleWeight"]);}
- (BOOL)dockTitleBolderSelected {return [self extraNumber:@"dockTitleBolderSelected"]>.5;}
- (BOOL)lensBarFollow {return [self extraNumber:@"lensBarFollowOn"]>.5;}
- (CGFloat)lensBarMargin {return [self extraNumber:@"lensBarMargin"];}
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
- (BOOL)calmMaterialEnabled {return [self extraNumber:@"calmMaterial"]>.5;}
- (CGFloat)calmMaterialOpacityForDock:(BOOL)dock dark:(BOOL)dark {
    return [self extraNumber:WXGScopedKey(dock?WXGGlassScopeDock:WXGGlassScopeOther,dark,@"CalmMaterialOpacity")];
}
- (CGFloat)calmThreshold {return [self extraNumber:@"calmThreshold"];}
- (CGFloat)calmRange {return [self extraNumber:@"calmRange"];}
// FIX89: the iOS 27-like rim's two highlights, drawn together whatever the
// appearance: 0 from the keys that were light mode's, 1 from dark mode's (so
// an upgrade keeps both as they were set, now on screen at once).
- (WXGRimGlowShape)rimGlowForScope:(WXGGlassScope)scope index:(NSInteger)index {
    BOOL second=index==1;
    CGFloat r=1,g=1,b=1,a=1;
    if(![WXGColor([self extraHex:WXGScopedKey(scope,second,@"Rim27Hex")]) getRed:&r green:&g blue:&b alpha:&a]){r=g=b=1;a=1;}
    CGFloat opacity=WXGClamp([self extraNumber:WXGScopedKey(scope,second,@"Rim27Opacity")],0,1);
    return (WXGRimGlowShape){[self extraNumber:WXGScopedKey(scope,second,@"Rim27Width")],[self extraNumber:WXGScopedKey(scope,second,@"Rim27Falloff")],
                             [self extraNumber:WXGScopedKey(scope,second,@"Rim27EndLevel")],[self extraNumber:WXGScopedKey(scope,second,@"Rim27Sharpness")],
                             [self extraNumber:WXGScopedKey(scope,second,@"Rim27Angle")],WXGClamp(r,0,1),WXGClamp(g,0,1),WXGClamp(b,0,1),WXGClamp(a*opacity,0,1)};
}
@end
