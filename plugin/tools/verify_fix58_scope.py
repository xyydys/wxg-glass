#!/usr/bin/env python3
"""FIX58 scope check against FIX57.
FIX58 = FIX57 + new settings pages + the dock / other-glass split of four
glass settings. Version strings aside:
  engine split   WXGCommon.h, WXGConfig.m, WXGGlassView.m, WXGDemoBar.m: undoing
                 the FIX58 edits below gives FIX57's file exactly (the dock's own
                 body optics and rim: dockRefraction ... dockDarkRimFade, read through
                 opticsForDock: / rimForDock:dark: / rimHexForDock:dark:; and the
                 clear-ring mask filled by WXGFillRingMask, new WXGEdgeMaskBand.h,
                 byte-identical, Tests/EdgeMaskBandTests.c)
  settings UI    WXGSettings.m, WXGOpticalSettings.m rewritten, WXGSettingsKit.h new
  version        WXGHost.m only version strings
  everything else (lens files, shader, the other 30+ sources, tests, build files):
                 FIX57's byte for byte; Makefile only adds PhotosUI (image picker)
Usage: verify_fix58_scope.py <FIX57 dir> [--json out]"""
import json, os, re, sys
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fix57 = sys.argv[1]
VERSION = [r"0\.4\.\d+", r"test4fix\d+", r"TEST4 FIX\d+", r"TEST4_FIX\d+", r'"revision":@"FIX\d+"']
def norm(text):
    for pattern in VERSION: text = re.sub(pattern, "<v>", text)
    return text
def read(*parts): return open(os.path.join(*parts), encoding="utf-8").read()
# The FIX58 edits, (FIX58 text, FIX57 text), applied in order.
UNDO = {
"WXGCommon.h": [
    (r"""
// FIX58: what the dock and the other glass set separately.
typedef struct { CGFloat refraction,dispersion,edgeWidth,blur,blurCoverage; } WXGScopeOptics;
typedef struct { CGFloat opacity,width,brightness,fade; } WXGScopeRim;
""",
     r"""
"""),
    (r"""@property(nonatomic) CGFloat lensTopEdgeRatio,lensEdgeSharpness;
// FIX58: the dock's own body optics and body rim (the shared values above are
// now "other glass"). First run copies the shared values, so nothing changes.
@property(nonatomic) CGFloat dockRefraction,dockDispersion,dockEdgeWidth,dockBlur,dockBlurCoverage;
@property(nonatomic,copy) NSString *dockRimHex,*dockDarkRimHex;
@property(nonatomic) CGFloat dockRimOpacity,dockDarkRimOpacity,dockBorderWidth,dockDarkBorderWidth;
@property(nonatomic) CGFloat dockRimBrightness,dockDarkRimBrightness,dockRimFade,dockDarkRimFade;
- (WXGScopeOptics)opticsForDock:(BOOL)dock;
- (WXGScopeRim)rimForDock:(BOOL)dock dark:(BOOL)dark;
- (NSString *)rimHexForDock:(BOOL)dock dark:(BOOL)dark;
""",
     r"""@property(nonatomic) CGFloat lensTopEdgeRatio,lensEdgeSharpness;
"""),
],
"WXGConfig.m": [
    (r"""    _dockSwitchTiming=0; _dockTapTravel=YES;
    // FIX58: the dock starts from the same values as the other glass.
    _dockRefraction=_refraction; _dockDispersion=_dispersion; _dockEdgeWidth=_edgeWidth; _dockBlur=_blur; _dockBlurCoverage=_blurCoverage;
    _dockRimHex=_rimHex; _dockDarkRimHex=_darkRimHex; _dockRimOpacity=_rimOpacity; _dockDarkRimOpacity=_darkRimOpacity;
    _dockBorderWidth=_barBorderWidth; _dockDarkBorderWidth=_darkBarBorderWidth;
    _dockRimBrightness=_rimBrightness; _dockDarkRimBrightness=_darkRimBrightness; _dockRimFade=_rimFade; _dockDarkRimFade=_darkRimFade;
""",
     r"""    _dockSwitchTiming=0; _dockTapTravel=YES;
"""),
    (r"""- (NSArray *)keys { return @[@"lensBlur",@"lensBlurCoverage",@"lensRefraction",@"lensDispersion",@"lensEdgeWidth",@"enabled",@"calibration",@"clearMaterial",@"haptics",@"widthFraction",@"height",@"lift",@"refraction",@"dispersion",@"blur",@"captureFPS",@"captureBudget",@"motionPrediction",@"renderMode",@"syncBlurScale",@"samplerSource",@"syncPresent",@"syncMeshRefraction",@"syncDispersion",@"syncCaptureScale",@"lensTopEdgeRatio",@"lensEdgeSharpness",@"alwaysShow",@"lensZoom",@"lensGrowth",@"bodyPinch",@"edgeWidth",@"selectionInset",@"selectionOpacity",@"pressedOpacity",@"barBorderWidth",@"lensBorderWidth",@"borderOpacity",@"selectionHex",@"darkSelectionHex",@"blurCoverage",@"useWeChatIcons",@"borderHex",@"barGrowth",@"endWrap",@"fadeMaterialAtEdge",@"materialOpacity",@"darkMaterialOpacity",@"rimFade",@"darkRimGain",@"materialHex",@"darkMaterialHex",@"rimHex",@"darkRimHex",@"lensRimHex",@"darkLensRimHex",@"rimOpacity",@"darkRimOpacity",@"lensRimOpacity",@"darkLensRimOpacity",@"rimBrightness",@"darkRimBrightness",@"rimFadeTopLeft",@"rimFadeBottomRight",@"darkRimFadeTopLeft",@"darkRimFadeBottomRight",@"darkRimFade",@"darkBarBorderWidth",@"darkLensBorderWidth",@"dockMaterialHex",@"dockDarkMaterialHex",@"dockMaterialOpacity",@"dockDarkMaterialOpacity",@"materialFadeWidth",@"dockMaterialFadeWidth",@"messageMenuCornerRadius",@"materialEdgeFade",@"materialEdgeFadeEnabled",@"dockMaterialEdgeFadeEnabled",@"dockMaterialEdgeFade",@"dockSwitchTiming",@"dockTapTravel",
    @"dockRefraction",@"dockDispersion",@"dockEdgeWidth",@"dockBlur",@"dockBlurCoverage",@"dockRimHex",@"dockDarkRimHex",@"dockRimOpacity",@"dockDarkRimOpacity",
    @"dockBorderWidth",@"dockDarkBorderWidth",@"dockRimBrightness",@"dockDarkRimBrightness",@"dockRimFade",@"dockDarkRimFade"]; }
""",
     r"""- (NSArray *)keys { return @[@"lensBlur",@"lensBlurCoverage",@"lensRefraction",@"lensDispersion",@"lensEdgeWidth",@"enabled",@"calibration",@"clearMaterial",@"haptics",@"widthFraction",@"height",@"lift",@"refraction",@"dispersion",@"blur",@"captureFPS",@"captureBudget",@"motionPrediction",@"renderMode",@"syncBlurScale",@"samplerSource",@"syncPresent",@"syncMeshRefraction",@"syncDispersion",@"syncCaptureScale",@"lensTopEdgeRatio",@"lensEdgeSharpness",@"alwaysShow",@"lensZoom",@"lensGrowth",@"bodyPinch",@"edgeWidth",@"selectionInset",@"selectionOpacity",@"pressedOpacity",@"barBorderWidth",@"lensBorderWidth",@"borderOpacity",@"selectionHex",@"darkSelectionHex",@"blurCoverage",@"useWeChatIcons",@"borderHex",@"barGrowth",@"endWrap",@"fadeMaterialAtEdge",@"materialOpacity",@"darkMaterialOpacity",@"rimFade",@"darkRimGain",@"materialHex",@"darkMaterialHex",@"rimHex",@"darkRimHex",@"lensRimHex",@"darkLensRimHex",@"rimOpacity",@"darkRimOpacity",@"lensRimOpacity",@"darkLensRimOpacity",@"rimBrightness",@"darkRimBrightness",@"rimFadeTopLeft",@"rimFadeBottomRight",@"darkRimFadeTopLeft",@"darkRimFadeBottomRight",@"darkRimFade",@"darkBarBorderWidth",@"darkLensBorderWidth",@"dockMaterialHex",@"dockDarkMaterialHex",@"dockMaterialOpacity",@"dockDarkMaterialOpacity",@"materialFadeWidth",@"dockMaterialFadeWidth",@"messageMenuCornerRadius",@"materialEdgeFade",@"materialEdgeFadeEnabled",@"dockMaterialEdgeFadeEnabled",@"dockMaterialEdgeFade",@"dockSwitchTiming",@"dockTapTravel"]; }
"""),
    (r"""        if(!local[@"dockMaterialEdgeFade"])_dockMaterialEdgeFade=_materialEdgeFade;
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
""",
     r"""        if(!local[@"dockMaterialEdgeFade"])_dockMaterialEdgeFade=_materialEdgeFade;
"""),
    (r"""    _dockMaterialEdgeFade=WXGClamp(_dockMaterialEdgeFade,0,60);
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
""",
     r"""    _dockMaterialEdgeFade=WXGClamp(_dockMaterialEdgeFade,0,60);
"""),
    (r"""- (void)reset { [self loadDefaults]; [self save]; }
// FIX58: the dock reads its own body optics and rim; every other glass the shared ones.
- (WXGScopeOptics)opticsForDock:(BOOL)dock {
    return dock?(WXGScopeOptics){_dockRefraction,_dockDispersion,_dockEdgeWidth,_dockBlur,_dockBlurCoverage}
               :(WXGScopeOptics){_refraction,_dispersion,_edgeWidth,_blur,_blurCoverage};
}
- (WXGScopeRim)rimForDock:(BOOL)dock dark:(BOOL)dark {
    if(dock)return dark?(WXGScopeRim){_dockDarkRimOpacity,_dockDarkBorderWidth,_dockDarkRimBrightness,_dockDarkRimFade}
                       :(WXGScopeRim){_dockRimOpacity,_dockBorderWidth,_dockRimBrightness,_dockRimFade};
    return dark?(WXGScopeRim){_darkRimOpacity,_darkBarBorderWidth,_darkRimBrightness,_darkRimFade}
               :(WXGScopeRim){_rimOpacity,_barBorderWidth,_rimBrightness,_rimFade};
}
- (NSString *)rimHexForDock:(BOOL)dock dark:(BOOL)dark {return dock?(dark?_dockDarkRimHex:_dockRimHex):(dark?_darkRimHex:_rimHex);}
""",
     r"""- (void)reset { [self loadDefaults]; [self save]; }
"""),
],
"WXGGlassView.m": [
    (r"""#include "WXGMeshRefraction.h"
#include "WXGEdgeMaskBand.h"
""",
     r"""#include "WXGMeshRefraction.h"
"""),
    (r"""    WXGScopeOptics dock=[c opticsForDock:YES];   // FIX58: the tap lens belongs to the dock
    WXGOpticalValues resting={(float)dock.refraction,(float)dock.dispersion,(float)dock.edgeWidth};
""",
     r"""    WXGOpticalValues resting={(float)c.refraction,(float)c.dispersion,(float)c.edgeWidth};
"""),
    (r"""        [v configureGroup:@"wxg.travel" radius:(dock.blur+(c.lensBlur-dock.blur)*press)*c.syncBlurScale channel:split?i+1:0];
""",
     r"""        [v configureGroup:@"wxg.travel" radius:(c.blur+(c.lensBlur-c.blur)*press)*c.syncBlurScale channel:split?i+1:0];
"""),
    (r"""    // FIX58: the dock's body rim (and the brightness / fade its lens rim shares)
    // is set apart from the rim of every other glass.
    WXGScopeRim rim=[c rimForDock:_dockSurface dark:dark];
    CGFloat brightness=rim.brightness;
    UIColor *barColor=WXGBrightened(WXGColor([c rimHexForDock:_dockSurface dark:dark]),brightness);
""",
     r"""    CGFloat brightness=dark?c.darkRimBrightness:c.rimBrightness;
    UIColor *barColor=WXGBrightened(WXGColor(dark?c.darkRimHex:c.rimHex),brightness);
"""),
    (r"""    CGFloat barAlpha=CGColorGetAlpha(barColor.CGColor)*rim.opacity;
""",
     r"""    CGFloat barAlpha=CGColorGetAlpha(barColor.CGColor)*(dark?c.darkRimOpacity:c.rimOpacity);
"""),
    (r"""    CGFloat sideFade=rim.fade,topLeft=dark?c.darkRimFadeTopLeft:c.rimFadeTopLeft,bottomRight=dark?c.darkRimFadeBottomRight:c.rimFadeBottomRight;
""",
     r"""    CGFloat sideFade=dark?c.darkRimFade:c.rimFade,topLeft=dark?c.darkRimFadeTopLeft:c.rimFadeTopLeft,bottomRight=dark?c.darkRimFadeBottomRight:c.rimFadeBottomRight;
"""),
    (r"""    [_bodyRim configureWidth:rim.width color:[barColor colorWithAlphaComponent:barAlpha]
""",
     r"""    [_bodyRim configureWidth:dark?c.darkBarBorderWidth:c.barBorderWidth color:[barColor colorWithAlphaComponent:barAlpha]
"""),
    (r"""    WXGScopeOptics scoped=[c opticsForDock:_dockSurface];   // FIX58
    WXGMeshOptics bodyOptics={(float)_glassRect.size.width,(float)_glassRect.size.height,1.f,(float)_maximumCornerRadius,(float)scoped.edgeWidth,
        (float)(scoped.refraction*(_buttonPressEffect?1+.35*press:1)),1.f,_buttonPressEffect?1.f+.04f*press:1.f,1.f,
        (float)(scoped.dispersion*.85),0.f,0.f,0.f};
""",
     r"""    WXGMeshOptics bodyOptics={(float)_glassRect.size.width,(float)_glassRect.size.height,1.f,(float)_maximumCornerRadius,(float)c.edgeWidth,
        (float)(c.refraction*(_buttonPressEffect?1+.35*press:1)),1.f,_buttonPressEffect?1.f+.04f*press:1.f,1.f,
        (float)(c.dispersion*.85),0.f,0.f,0.f};
"""),
    (r"""    [self applyStack:_bodyStack visible:body split:split radius:scoped.blur*scale optics:bodyOptics quality:WXGMeshQualityBody mesh:bodyMesh];
    BOOL ring=bodyMesh && scoped.blurCoverage<99.5 && scoped.blur*scale>.01;
""",
     r"""    [self applyStack:_bodyStack visible:body split:split radius:c.blur*scale optics:bodyOptics quality:WXGMeshQualityBody mesh:bodyMesh];
    BOOL ring=bodyMesh && c.blurCoverage<99.5 && c.blur*scale>.01;
"""),
    (r"""        WXGOpticalValues resting={(float)scoped.refraction,(float)scoped.dispersion,(float)scoped.edgeWidth};
""",
     r"""        WXGOpticalValues resting={(float)c.refraction,(float)c.dispersion,(float)c.edgeWidth};
"""),
    (r"""        lensBlur=(scoped.blur+(c.lensBlur-scoped.blur)*press)*scale;
""",
     r"""        lensBlur=(c.blur+(c.lensBlur-c.blur)*press)*scale;
"""),
    (r"""    WXGScopeOptics scoped=[c opticsForDock:_dockSurface];   // FIX58
    float key[5]={(float)_glassRect.size.width,(float)_glassRect.size.height,(float)_maximumCornerRadius,(float)scoped.edgeWidth,(float)(scoped.blurCoverage*.01)};
""",
     r"""    float key[5]={(float)_glassRect.size.width,(float)_glassRect.size.height,(float)_maximumCornerRadius,(float)c.edgeWidth,(float)(c.blurCoverage*.01)};
"""),
    (r"""                // FIX58: same bytes, the field evaluated along the outline only.
                WXGFillRingMask(bytes,w,h,stride,(float)scale,key);
""",
     r"""                for(size_t j=0;j<h;j++)for(size_t i=0;i<w;i++) {
                    float alpha=WXGSharpRingAlpha(((float)i+.5f)/(float)scale,((float)j+.5f)/(float)scale,key[0],key[1],key[2],key[3],key[4]);
                    bytes[j*stride+i]=(uint8_t)lroundf(255.f*alpha);
                }
"""),
    (r"""    WXGConfig *c=WXGConfig.shared; WXGScopeOptics scoped=[c opticsForDock:_dockSurface];   // FIX58
    WXGScopeRim rim=[c rimForDock:_dockSurface dark:[self darkAppearance]];
    CGFloat sigma=scoped.blur*[self screenScale];
""",
     r"""    WXGConfig *c=WXGConfig.shared; CGFloat sigma=c.blur*[self screenScale];
"""),
    (r"""    u.material=(WXGFloat4){(float)_pressAmount,(float)scoped.refraction,(float)scoped.dispersion,(float)scoped.blur};
""",
     r"""    u.material=(WXGFloat4){(float)_pressAmount,(float)c.refraction,(float)c.dispersion,(float)c.blur};
"""),
    (r"""    u.optics=(WXGFloat4){(float)c.lensZoom,(float)rim.width,(float)c.bodyPinch,(float)scoped.edgeWidth};
""",
     r"""    u.optics=(WXGFloat4){(float)c.lensZoom,(float)(darkStyle?c.darkBarBorderWidth:c.barBorderWidth),(float)c.bodyPinch,(float)c.edgeWidth};
"""),
    (r"""    [WXGBrightened(WXGColor([c rimHexForDock:_dockSurface dark:darkStyle]),rim.brightness) getRed:&r green:&g blue:&b alpha:&a];
    u.borderColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*rim.opacity)};
""",
     r"""    [WXGBrightened(WXGColor(darkStyle?c.darkRimHex:c.rimHex),darkStyle?c.darkRimBrightness:c.rimBrightness) getRed:&r green:&g blue:&b alpha:&a];
    u.borderColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*(darkStyle?c.darkRimOpacity:c.rimOpacity))};
"""),
    (r"""    u.motion=(WXGFloat4){(float)_barScale,edgeFade && edgeFadeRange>.01?1.f:0.f,(float)(scoped.blurCoverage*.01),(float)_lensAnchorX};
""",
     r"""    u.motion=(WXGFloat4){(float)_barScale,edgeFade && edgeFadeRange>.01?1.f:0.f,(float)(c.blurCoverage*.01),(float)_lensAnchorX};
"""),
    (r"""    u.rim=(WXGFloat4){(float)rim.fade,1.f,(float)(darkStyle?c.darkLensBorderWidth:c.lensBorderWidth),(float)_maximumCornerRadius};
""",
     r"""    u.rim=(WXGFloat4){(float)(darkStyle?c.darkRimFade:c.rimFade),1.f,(float)(darkStyle?c.darkLensBorderWidth:c.lensBorderWidth),(float)_maximumCornerRadius};
"""),
],
"WXGDemoBar.m": [
    (r"""    WXGConfig *c=WXGConfig.shared;WXGScopeOptics dock=[c opticsForDock:YES];   // FIX58: the dock's own resting optics
    return [NSString stringWithFormat:@"%.1fx%.1f/%d/%.3f/%.3f/%.2f/%.3f/%.2f/%.2f/%.2f/%.3f/%.3f/%.2f",size.width,size.height,c.syncDispersion,
        c.lensRefraction,c.lensDispersion,c.lensEdgeWidth,c.lensZoom,c.lensBlur,dock.blur,c.syncBlurScale,dock.refraction,dock.dispersion,dock.edgeWidth];
""",
     r"""    WXGConfig *c=WXGConfig.shared;
    return [NSString stringWithFormat:@"%.1fx%.1f/%d/%.3f/%.3f/%.2f/%.3f/%.2f/%.2f/%.2f",size.width,size.height,c.syncDispersion,
        c.lensRefraction,c.lensDispersion,c.lensEdgeWidth,c.lensZoom,c.lensBlur,c.blur,c.syncBlurScale];
"""),
    (r"""    _fallback.layer.borderWidth=c.dockBorderWidth;
""",
     r"""    _fallback.layer.borderWidth=c.barBorderWidth;
"""),
    (r"""    WXGScopeOptics dock=[c opticsForDock:YES];
    return [NSString stringWithFormat:@"TEST9 呼出/收回；运动形变 %@；按压 %.3f；速度 %.1f pt/s；形变 %.3f\n底栏：折射 %.2f / 色散 %.2f / 宽度 %.1f pt\n透镜：折射 %.2f / 色散 %.2f / 宽度 %.1f pt\n底栏模糊 %.2f pt / 覆盖 %.0f%%\n%@",
""",
     r"""    return [NSString stringWithFormat:@"TEST9 呼出/收回；运动形变 %@；按压 %.3f；速度 %.1f pt/s；形变 %.3f\n普通：折射 %.2f / 色散 %.2f / 宽度 %.1f pt\n透镜：折射 %.2f / 色散 %.2f / 宽度 %.1f pt\nTEST9 模糊 %.2f pt / 覆盖 %.0f%%\n%@",
"""),
    (r"""        dock.refraction,dock.dispersion,dock.edgeWidth,c.lensRefraction,c.lensDispersion,c.lensEdgeWidth,dock.blur,dock.blurCoverage,_glass.diagnostics];
""",
     r"""        c.refraction,c.dispersion,c.edgeWidth,c.lensRefraction,c.lensDispersion,c.lensEdgeWidth,c.blur,c.blurCoverage,_glass.diagnostics];
"""),
],
}
REWRITTEN = {"WXGSettings.m", "WXGOpticalSettings.m"}
NEW = {"WXGSettingsKit.h", "WXGEdgeMaskBand.h"}
VERSION_ONLY = {"WXGHost.m"}
problems, sources = [], {}
names = sorted(set(os.listdir(os.path.join(here, "Sources"))) | set(os.listdir(os.path.join(fix57, "Sources"))))
for name in names:
    mine, old = os.path.join(here, "Sources", name), os.path.join(fix57, "Sources", name)
    if name in NEW:
        sources[name] = ("new (settings pages)" if name == "WXGSettingsKit.h" else "new (edge mask along the outline)") if os.path.exists(mine) and not os.path.exists(old) else "unexpected"
        if sources[name] == "unexpected": problems.append(f"Sources/{name}: expected new"); 
        continue
    if not os.path.exists(mine) or not os.path.exists(old):
        problems.append(f"Sources/{name}: added or removed"); continue
    new, base = read(mine), read(old)
    if name in REWRITTEN:
        sources[name] = "rewritten (settings pages)"; continue
    if name in UNDO:
        undone = new
        for after, before in UNDO[name]:
            if undone.count(after) != 1: problems.append(f"Sources/{name}: FIX58 edit not found once: {after[:60]!r}"); continue
            undone = undone.replace(after, before)
        ok = undone == base
        sources[name] = f"FIX57 + {len(UNDO[name])} FIX58 edits" if ok else "changed"
        if not ok: problems.append(f"Sources/{name}: differs from FIX57 beyond the FIX58 edits")
        continue
    if new == base: sources[name] = "FIX57"
    elif name in VERSION_ONLY and norm(new) == norm(base): sources[name] = "FIX57 (version strings)"
    else: sources[name] = "changed"; problems.append(f"Sources/{name}: differs from FIX57")
# The embedded shader is still WXGGlass.metal.
src = read(here, "Sources", "WXGGlass.metal")
src = src.replace('#include "WXGLensOptics.h"', read(here, "Sources", "WXGLensOptics.h")).replace('#include "WXGOptics.h"', read(here, "Sources", "WXGOptics.h"))
embedded = ('// Generated from WXGGlass.metal; rebuild with tools/embed_shader.py.\n'
            'static const char WXGMetalSource[] =\n' + '\n'.join(json.dumps(line + '\n') for line in src.splitlines()) + ';\n')
if embedded != read(here, "Sources", "WXGShaderSource.h"): problems.append("WXGShaderSource.h is not the embedded WXGGlass.metal")
# Every dock* key the split added is saved, migrated, clamped and read.
config, common = read(here, "Sources", "WXGConfig.m"), read(here, "Sources", "WXGCommon.h")
DOCK = ["dockRefraction", "dockDispersion", "dockEdgeWidth", "dockBlur", "dockBlurCoverage", "dockRimHex", "dockDarkRimHex",
        "dockRimOpacity", "dockDarkRimOpacity", "dockBorderWidth", "dockDarkBorderWidth", "dockRimBrightness", "dockDarkRimBrightness",
        "dockRimFade", "dockDarkRimFade"]
keys = re.search(r"- \(NSArray \*\)keys \{ return @\[(.*?)\]; \}", config, re.S).group(1)
for key in DOCK:
    if f'@"{key}"' not in keys: problems.append(f"{key}: not in the saved keys")
    if f'if(!local[@"{key}"])_{key}=' not in config: problems.append(f"{key}: no first-run copy of the shared value")
    if config.count(f"_{key}") < 4: problems.append(f"{key}: not defaulted / clamped / read")
    if key not in common: problems.append(f"{key}: not declared")
# The glass reads the scoped values everywhere the shared ones were read.
glass = read(here, "Sources", "WXGGlassView.m")
for shared in ["refraction", "dispersion", "edgeWidth", "blur", "blurCoverage", "barBorderWidth", "darkBarBorderWidth",
               "rimOpacity", "darkRimOpacity", "rimBrightness", "darkRimBrightness", "rimFade", "darkRimFade", "rimHex", "darkRimHex"]:
    if re.search(r"\b[cv]\." + shared + r"(?![A-Za-z])", glass): problems.append(f"WXGGlassView.m still reads {shared} directly")
tests = {}
for name in sorted(set(os.listdir(os.path.join(here, "Tests"))) | set(os.listdir(os.path.join(fix57, "Tests")))):
    mine, ref = os.path.join(here, "Tests", name), os.path.join(fix57, "Tests", name)
    if os.path.isdir(mine): continue
    if name == "EdgeMaskBandTests.c":
        tests[name] = "new" if os.path.exists(mine) and not os.path.exists(ref) else "unexpected"
        if tests[name] == "unexpected": problems.append(f"Tests/{name}: expected new")
        continue
    if not os.path.exists(mine) or not os.path.exists(ref): tests[name] = "added or removed"; problems.append(f"Tests/{name}: added or removed"); continue
    tests[name] = "FIX57" if read(mine) == read(ref) else "changed"
    if tests[name] == "changed": problems.append(f"Tests/{name}: differs from FIX57")
others = {}
for name in ["build.sh", "WeChatLiquidGlass.plist"]:
    others[name] = "FIX57" if read(here, name) == read(fix57, name) else "changed"
    if others[name] == "changed": problems.append(f"{name}: changed")
make, make57 = read(here, "Makefile"), read(fix57, "Makefile")
others["Makefile"] = "FIX57 + PhotosUI" if make == make57.replace("Metal MetalKit\n", "Metal MetalKit PhotosUI\n") else "changed"
if others["Makefile"] == "changed": problems.append("Makefile: changed beyond adding PhotosUI")
strip = lambda t: "\n".join(l for l in norm(t).splitlines() if not l.startswith("Description:"))
others["control"] = "FIX57 (name / version / description)" if strip(read(fix57, "control")) == strip(read(here, "control")) else "changed"
if others["control"] == "changed": problems.append("control: changed beyond name / version / description")
result = {"sources": sources, "tests": tests, "other": others, "problems": problems}
if len(sys.argv) > 3 and sys.argv[2] == "--json":
    json.dump(result, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(json.dumps(result, ensure_ascii=False, indent=1))
sys.exit(1 if problems else 0)
