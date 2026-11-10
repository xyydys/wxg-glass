#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import "WXGMotion.h"
#import "WXGOptics.h"
#import "WXGLensOptics.h"
#import "WXGKyantElastic.h"
#import "WXGLensFlex.h"
#import "WXGDockSystem.h"
#import "WXGRenderPolicy.h"

FOUNDATION_EXPORT NSString * const WXGSettingsChanged;
FOUNDATION_EXPORT void WXGLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
FOUNDATION_EXPORT CFTimeInterval WXGSecondsSinceLoad(void);   // FIX99: since the plugin loaded
FOUNDATION_EXPORT NSString *WXGLogText(void);
FOUNDATION_EXPORT UIColor *WXGColor(NSString *hex);
FOUNDATION_EXPORT NSString *WXGNormalizeHex(NSString *hex);
FOUNDATION_EXPORT NSInteger WXGScreenCaptureFPS(UIScreen *screen);
FOUNDATION_EXPORT void WXGPrewarmGlassPipeline(void);
FOUNDATION_EXPORT void WXGConfigureDisplayLink(CADisplayLink *link,UIScreen *screen);

/* FIX59: this build (WXGBuildProfile.h, read by WXGLicense.m): its label,
   hidden settings modules, its defaults. FIX103: which WeChat accounts may
   use the plugin is decided by the unlock server (WXGUnlock.m). */
typedef NS_ENUM(NSInteger,WXGLicenseState) {WXGLicenseUnknown,WXGLicenseAuthorized,WXGLicenseDenied,
    WXGLicenseChecking,WXGLicenseUnreachable,WXGLicenseOutdated};   // FIX103: the last three: asking the server, no answer, a shader of another version
FOUNDATION_EXPORT BOOL WXGPluginEnabled(void);                 // the main switch AND an authorized account
FOUNDATION_EXPORT void WXGLicenseNoteMainInterface(void);       // WeChat's logged-in interface is up
FOUNDATION_EXPORT WXGLicenseState WXGLicenseCurrentState(BOOL recheck);
FOUNDATION_EXPORT WXGLicenseState WXGLicenseRecheckServer(void);   // FIX103: "重新检测": read the account and ask the server now
FOUNDATION_EXPORT void WXGLicenseSetQuietCheck(BOOL (*check)(void));   // FIX102: re-read the account only when this says YES
FOUNDATION_EXPORT NSString *WXGLicenseAccount(void);            // the current account (wxid), nil if not read
FOUNDATION_EXPORT NSString *WXGLicenseCode(void);               // FIX103: its licence code (what the server's list holds), nil if not read
FOUNDATION_EXPORT NSString *WXGLicenseAccountSource(void);
FOUNDATION_EXPORT NSDictionary *WXGLicenseEvidence(void);
/* FIX103: the unlock server (WXGUnlock.m). Main thread unless noted. */
typedef NS_ENUM(NSInteger,WXGUnlockState) {WXGUnlockNone,WXGUnlockReady,WXGUnlockDenied,WXGUnlockChecking,WXGUnlockUnreachable,WXGUnlockOutdated};
FOUNDATION_EXPORT NSString * const WXGLicenseChangedNotification;   // the server answered (posted on main)
FOUNDATION_EXPORT void WXGUnlockStart(void);                         // at launch (FIX104: the constructor): device id, cached tickets, shader
FOUNDATION_EXPORT WXGUnlockState WXGUnlockStateFor(NSString *licenseCode,BOOL force);
FOUNDATION_EXPORT void WXGUnlockWhenShaderReady(void (^block)(NSString *source));   // any thread; block runs once, off main
FOUNDATION_EXPORT NSString *WXGUnlockLastError(void);
FOUNDATION_EXPORT BOOL WXGUnlockAsking(NSString *licenseCode);   // FIX104: a request for this account is on its way
FOUNDATION_EXPORT BOOL WXGUnlockShaderReady(void);               // FIX109: 真实着色器是否已加载(防篡改用的真货信号)
FOUNDATION_EXPORT BOOL WXGUnlockHasUsableTicket(NSString *licenseCode);   // FIX109: 该账号是否真有一张没过期的票
FOUNDATION_EXPORT NSString *WXGUnlockServerShaderVersion(void);   // the server's shader version when it is not this plugin's, else nil
FOUNDATION_EXPORT NSDate *WXGUnlockExpiry(NSString *licenseCode);
FOUNDATION_EXPORT NSDictionary *WXGUnlockEvidence(void);
FOUNDATION_EXPORT NSString *WXGBuildLabel(void);
// FIX114 C: the title row's margin to the screen's sides (顶部按钮离屏幕两边)
// and its move down (顶部按钮往下移), in points for a metrics scale.
FOUNDATION_EXPORT CGFloat WXGTitleRowEdge(double scale);
FOUNDATION_EXPORT CGFloat WXGFinderRowEdge(double scale);   // FIX115 S: 视频号's pages' margin to the screen's sides
FOUNDATION_EXPORT CGFloat WXGTitleRowOffset(double scale);
FOUNDATION_EXPORT NSArray<NSString *> *WXGHiddenSettingsModules(void);
FOUNDATION_EXPORT NSDictionary *WXGBuildDefaultOptics(void);
// FIX84: a section of the build's defaults ("config", "integration", "ui"), {} if none.
FOUNDATION_EXPORT NSDictionary *WXGBuildDefaultSection(NSString *section);
// FIX114 G: the defaults the build replaced (same sections, {} if none), a
// stamp of this build's, the value test, and what moved on this phone.
FOUNDATION_EXPORT NSDictionary *WXGPreviousBuildDefaultSection(NSString *section);
FOUNDATION_EXPORT NSString *WXGBuildDefaultsStamp(void);
FOUNDATION_EXPORT BOOL WXGSameSettingValue(id a,id b);
FOUNDATION_EXPORT void WXGNoteDefaultsAdoption(NSString *section,NSDictionary *info);
FOUNDATION_EXPORT NSDictionary *WXGDefaultsAdoption(void);

// FIX58: what the dock and the other glass set separately.
typedef struct { CGFloat refraction,dispersion,edgeWidth,blur,blurCoverage; } WXGScopeOptics;
// FIX114 I / J: a range's 边界过渡 (0..1) and its soft shift's shape
// (WXGSoftEdge.h): the band (pt, 0 = automatic), the most the outline is
// magnified, the curve's power.
typedef struct { CGFloat amount,width,stretch,curve; } WXGTransitionSettings;
// FIX114 J: what a range's backdrop does to the page's colours before
// refraction (Telegram-like glass taking its colour from what is behind it):
// saturation (1 = as is; TEST9's 1.05 by default) and brightness (added).
typedef struct { CGFloat saturation,brightness; } WXGBackdropTone;
// FIX114 K: a range's drop shadow (WXGDropShadow.h): strength (this
// appearance's), sigma of its blur, how far down, how much larger (pt).
typedef struct { CGFloat opacity,blur,offset,spread; } WXGDropShadowSettings;
// FIX114 L: the four pages with a range picker; a range can use another
// range's settings of a page (共用).
typedef NS_ENUM(NSInteger,WXGSharePage) {WXGSharePageRefraction=0,WXGSharePageBlur=1,WXGSharePageMaterial=2,WXGSharePageBorder=3};
typedef struct { CGFloat opacity,width,brightness,fade; } WXGScopeRim;
// FIX122 D: Kyant's lens() on a glass' body (shares of its short side; depthEffect 0 / 1; split strength).
typedef struct { BOOL on; CGFloat height,amount,depth,dispersion,maxHeight,rimMax; } WXGKyantBody;   // maxHeight: the band's cap (pt); rimMax: FIX122 E (0 = his thin ring)
// FIX85: the three groups of glass with their own optics and rims (the
// liquid chat bubbles are the third), and the three rim styles.
typedef NS_ENUM(NSInteger,WXGGlassScope) {WXGGlassScopeOther=0,WXGGlassScopeDock=1,WXGGlassScopeBubble=2,
    WXGGlassScopeSegment=3,WXGGlassScopeCard=4,   // FIX113 O: 分组 (the chat list's segment bar), 设置页 (these settings)
    WXGGlassScopeLens=5,   // FIX113 X: 透镜 (the lens' border of the dock; 边框与渐隐 only)
    WXGGlassScopeSegmentLens=6,   // FIX114 C: 分组透镜 (the segment bar's lens border, its own since)
    WXGGlassScopeFinder=7};   // FIX115 S: 视频号 (the video feed's capsules' border; 边框与渐隐 only)
// FIX113 O: a lens's parameters (the dock's, or the segment bar's own); the
// rim and tint values of the appearance asked for.
typedef struct {
    CGFloat refraction,dispersion,edgeWidth,topRatio,sharpness,dispersionWidth,dispersionTopRatio;
    CGFloat zoom,growth,barGrowth,endWrap,pinch,blur,blurCoverage,cancelSetting;
    CGFloat rimOpacity,borderWidth,rimAtRest;
    BOOL tintOn;CGFloat tintOpacity;
    BOOL barDispersionOn;CGFloat barDispersion,barDispersionNearRim;
    CGFloat selectionInset;
    CGFloat iconRefraction,iconEdgeWidth;   // FIX113 X: the icons and titles in the lens (the rest: refraction, edgeWidth)
    CGFloat iconTopRatio,iconSharpness;     // FIX113 Y: and their top / bottom band ratio and narrowing curve
    BOOL elasticOn;CGFloat elasticHeight;   // FIX113 Y: the drag-speed deformation, the share of its height change kept
    CGFloat elasticKeepStrip;               // FIX113 Y: how much of the strip inside the lens is kept as it deforms
    BOOL kyantOn;CGFloat kyantHeight,kyantAmount,kyantDispersion,kyantRimMax;   // FIX122 E: kyantRimMax 0 = his thin outermost ring   // FIX122: Kyant 透镜模式 (shares of the lens' short side; split strength)
    // FIX128: iOS 26's colour split all round the outline, in place of Kyant's toward the corners (WXGMeshRefraction.h ring*):
    // red / blue each moved this many points at the outline, over this many points inward, the direction turned by this (radians).
    BOOL ringOn;CGFloat ringAmount,ringWidth,ringAngle;
} WXGLensSettings;
// FIX113: Telegram's tab icons for the dock (WXGTelegramIcons.m): on, the
// frames of a tab (0 Chats, 1 Contacts, 2 Calls, 3 Settings; template
// images, 60 fps), one frame tinted (0 = resting).
FOUNDATION_EXPORT BOOL WXGTelegramTabIconsOn(void);
// FIX115 D: 底栏主题优先 (the dock's glass and positions only; its icons and
// titles as WeChat / a theme shows them: their pictures at their shown size,
// their colours; the Telegram set and the accent colour not used).
FOUNDATION_EXPORT BOOL WXGDockThemeFirst(void);
FOUNDATION_EXPORT NSInteger WXGTelegramFrameCount(NSInteger tab);
FOUNDATION_EXPORT NSArray<UIImage *> *WXGTelegramFrames(NSInteger tab);
FOUNDATION_EXPORT UIImage *WXGTelegramTabImage(NSInteger tab,NSInteger frame,UIColor *color);
// FIX113 F: the resting glyph's ink width as a share of the frame's (main thread).
FOUNDATION_EXPORT CGFloat WXGTelegramRestInkWidth(NSInteger tab);
typedef NS_ENUM(NSInteger,WXGRimStyle) {WXGRimStyleClassic=0,WXGRimStyleSampled=1,WXGRimStyleGlow=2,
    WXGRimStyle26=3};   // FIX123: iOS 26 边框, the system's own recipe (FIX122 F / G's two styles are gone)
// FIX123: an iOS 26 rim range's values (WXGRim26.h; points).
typedef struct {
    CGFloat height,curve;                  // across the edge: how far in, how much it has fallen at its inner cut
    CGFloat angle,key,fill,spread;         // along the outline: the key light's direction, the two lights' levels, the lobes' exponent
    CGFloat opacity,gain,chroma,lift,ring; // this appearance's: strength; the colour matrix (luma gain, colour gain, lift); the faint line all round
    CGFloat captureScale;BOOL systemFilter;// the copy of what lies under the rim: its resolution; or the system's own blending filter instead
    BOOL shadowOn;CGFloat shadowOpacity,shadowLength;   // the optional inner shadow (not the system's)
} WXGRim26Settings;
// FIX86: the iOS 27-like rim (WXGRimGlow.h): a light that fades inward from
// the outline over `width` (its curve `falloff`), brightest along the top and
// bottom and down to `endLevel` at the two ends, the change by `sharpness`.
// FIX87: angle (degrees) of the highlight. FIX89: two of them drawn together
// (not per appearance), each with its colour: red, green, blue and alpha (the
// colour's alpha times the opacity).
typedef struct { CGFloat width,falloff,endLevel,sharpness,angle,red,green,blue,alpha; } WXGRimGlowShape;
enum { WXGRimGlowCount=2 };
// FIX79: the colour-sampling parameters of one appearance.
typedef struct { CGFloat saturation,contrast,gain,lift,blur; } WXGRimSampleTuning;
@interface WXGConfig : NSObject
+ (instancetype)shared;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL calibration;
@property(nonatomic) BOOL clearMaterial;
@property(nonatomic) BOOL haptics;
@property(nonatomic) BOOL alwaysShow;
@property(nonatomic) BOOL fadeMaterialAtEdge;
@property(nonatomic) BOOL useWeChatIcons;
@property(nonatomic) CGFloat lensRefraction,lensDispersion,lensEdgeWidth,lensBlur,lensBlurCoverage;
@property(nonatomic) CGFloat blurCoverage;
@property(nonatomic) CGFloat lensZoom, lensGrowth, bodyPinch, edgeWidth;
@property(nonatomic) CGFloat selectionInset, selectionOpacity, pressedOpacity;
@property(nonatomic) CGFloat barBorderWidth, lensBorderWidth, borderOpacity;
@property(nonatomic) CGFloat barGrowth, endWrap;
@property(nonatomic) CGFloat materialOpacity, darkMaterialOpacity, rimFade, darkRimGain;
@property(nonatomic,copy) NSString *selectionHex, *darkSelectionHex, *borderHex;
@property(nonatomic,copy) NSString *materialHex, *darkMaterialHex;
@property(nonatomic) CGFloat widthFraction;
@property(nonatomic) CGFloat height;
@property(nonatomic) CGFloat lift;
@property(nonatomic) CGFloat refraction;
@property(nonatomic) CGFloat dispersion;
@property(nonatomic) CGFloat blur;
@property(nonatomic) NSInteger captureFPS;
// FIX16: upper bound, in percent, of main-thread wall time spent reading the
// background. Glass still draws every frame; only background freshness yields.
@property(nonatomic) CGFloat captureBudget;
// FIX17: advance the background read to the time the glass is displayed.
@property(nonatomic) BOOL motionPrediction;
// FIX18 comparison: 0 readback optics, 1 hybrid (live body + readback edge
// band), 2 render server (live body and lens, no readback). syncBlurScale
// maps the TEST9 blur radius onto the render server's Gaussian radius.
@property(nonatomic) NSInteger renderMode;
@property(nonatomic) CGFloat syncBlurScale;
// FIX19: 0 automatic (FIX4 model tree; presentation path while animating),
// 1 presentation path only (FIX15-18). syncPresent presents the glass in the
// same Core Animation transaction as WeChat's frame.
@property(nonatomic) NSInteger samplerSource;
@property(nonatomic) BOOL syncPresent;
// FIX20: render-server (同步) mode bends the live backdrop with a mesh built
// from the TEST9 refraction field, plus TEST9's clear edge ring.
@property(nonatomic) BOOL syncMeshRefraction;
// FIX23: render-server RGB dispersion (three channel backdrops).
@property(nonatomic) BOOL syncDispersion;
// FIX26: render-server capture density in pixels per point; 0 = screen scale.
@property(nonatomic) CGFloat syncCaptureScale;
// FIX27: rims per appearance (bar rim and lens rim colour/opacity, widths,
// brightness, top-left / bottom-right fades and the side fade).
@property(nonatomic,copy) NSString *rimHex,*darkRimHex,*lensRimHex,*darkLensRimHex;
@property(nonatomic) CGFloat rimOpacity,darkRimOpacity,lensRimOpacity,darkLensRimOpacity;
@property(nonatomic) CGFloat rimBrightness,darkRimBrightness;
@property(nonatomic) CGFloat rimFadeTopLeft,rimFadeBottomRight,darkRimFadeTopLeft,darkRimFadeBottomRight,darkRimFade;
@property(nonatomic) CGFloat darkBarBorderWidth,darkLensBorderWidth;
// FIX27: material veil for the dock separately from all other glass, and the
// distance from the edge over which the veil weakens (0 = refraction width).
@property(nonatomic,copy) NSString *dockMaterialHex,*dockDarkMaterialHex;
@property(nonatomic) CGFloat dockMaterialOpacity,dockDarkMaterialOpacity,materialFadeWidth,dockMaterialFadeWidth;
// FIX28: one range for every glass: how far from the edge the material veil
// weakens. 0 = no weakening, the veil covers fully up to the outline.
@property(nonatomic) CGFloat materialEdgeFade;
// FIX29: the dock and all other glass each choose whether the veil weakens at
// the edge and over what range (materialEdgeFade is the other-glass range).
@property(nonatomic) BOOL materialEdgeFadeEnabled,dockMaterialEdgeFadeEnabled;
@property(nonatomic) CGFloat dockMaterialEdgeFade;
// FIX31: when a dock tap switches the WeChat page: 0 at touch-up (default),
// 1 once the lens has reached the tab, 2 once the lens animation has ended.
@property(nonatomic) NSInteger dockSwitchTiming;
// FIX33: a tap on another tab animates in the render server (iOS 26 style:
// touch lifts in place, release travels), immune to WeChat's main-thread work.
@property(nonatomic) BOOL dockTapTravel;
// FIX27: corner radius of the message long-press menu glass.
@property(nonatomic) CGFloat messageMenuCornerRadius;
// FIX21: lens rim width above/below the bar as a fraction of the end width
// (1 = previous isotropic lens), and how quickly it narrows leaving the ends.
@property(nonatomic) CGFloat lensTopEdgeRatio,lensEdgeSharpness;
// FIX59: 流畅模式: every glass one backdrop (no RGB channels, no clear ring),
// sampled at most 2x. Off = FIX58 rendering exactly.
@property(nonatomic) BOOL performanceMode;
// FIX61: the dock search: gap between the two glasses (pt); while searching,
// the row's height (fraction of the dock's) and width (fraction of the screen).
@property(nonatomic) CGFloat dockSearchGap,dockSearchHeightRatio,dockSearchWidthFraction;
// FIX64: page edge fade + blur, distances in pt from the list's top / bottom
// edge: the chat page, and the other pages (home, contacts, Moments, chat
// settings; FIX65: WeChat's settings and ours). FIX65: a blur strength for
// each edge (0-8).
@property(nonatomic) CGFloat edgeChatFadeTop,edgeChatFadeBottom,edgeChatBlurTop,edgeChatBlurBottom,edgeChatBlurTopRadius,edgeChatBlurBottomRadius;
// FIX68: hold-and-drag stretch of the glass buttons (follow distance in pt
// for a 44 pt button, stretch per point of offset) and the dock's ends.
@property(nonatomic) BOOL pressStretch,dockEndStretch;
@property(nonatomic) CGFloat pressStretchDistance,pressStretchAmount,dockEndStretchDistance;
// FIX80: non-round glass stretches this share of it, only along x / y; the
// lengthening eases into a maximum (pt); the glass moves with the finger by
// this share of the pull.
@property(nonatomic) CGFloat pressStretchCapsule,pressStretchMax,pressStretchFollow;
// FIX82: liquid chat bubbles: the tint of one's own and the other side's
// bubbles per appearance (colour and opacity).
@property(nonatomic,copy) NSString *bubbleOutgoingHex,*bubbleIncomingHex,*darkBubbleOutgoingHex,*darkBubbleIncomingHex;
// FIX83: the tint weakens toward the bubble's outline over this range (pt),
// as the other glass's material does.
@property(nonatomic) BOOL bubbleEdgeFadeEnabled;
@property(nonatomic) CGFloat bubbleEdgeFade;
// FIX75 / FIX79: details on the classic rim (WXGRimDetail.h), each
// appearance its own: the line's outer and inner sides fade over their own
// widths (pt, in 0.1 pt steps) down to `SideLevel` at the very sides, in
// opacity or (`SideDarken`) in brightness; and an inner shadow (colour,
// opacity, softness in pt).
@property(nonatomic) BOOL rimDetails,rimSideDarken,darkRimSideDarken;
@property(nonatomic) CGFloat rimOuterFade,darkRimOuterFade,rimInnerFade,darkRimInnerFade,rimSideLevel,darkRimSideLevel;
@property(nonatomic) CGFloat rimInnerShadowOpacity,darkRimInnerShadowOpacity,rimInnerShadowRadius,darkRimInnerShadowRadius;
@property(nonatomic,copy) NSString *rimInnerShadowHex,*darkRimInnerShadowHex;
// FIX75: the input field and the home page's top-left button stretch too
// (their own switch under the hold-and-drag one).
@property(nonatomic) BOOL pressStretchNative;
// FIX76: the rim line coloured from the background behind the glass
// (WXGRimSampleMatrix: saturation, contrast, gain, lift, then the rim's own
// brightness), blurred first; plus-lighter instead of normal compositing.
// FIX79: the parameters per appearance (the two switches are shared).
@property(nonatomic) BOOL rimSampleColor,rimSamplePlusLighter;
@property(nonatomic) CGFloat rimSampleSaturation,rimSampleContrast,rimSampleGain,rimSampleLift,rimSampleBlur;
@property(nonatomic) CGFloat darkRimSampleSaturation,darkRimSampleContrast,darkRimSampleGain,darkRimSampleLift,darkRimSampleBlur;
- (WXGRimSampleTuning)rimSampleTuningDark:(BOOL)dark;
@property(nonatomic) CGFloat edgeOtherFadeTop,edgeOtherFadeBottom,edgeOtherBlurTop,edgeOtherBlurBottom,edgeOtherBlurTopRadius,edgeOtherBlurBottomRadius;
// FIX58: the dock's own body optics and body rim (the shared values above are
// now "other glass"). First run copies the shared values, so nothing changes.
@property(nonatomic) CGFloat dockRefraction,dockDispersion,dockEdgeWidth,dockBlur,dockBlurCoverage;
@property(nonatomic,copy) NSString *dockRimHex,*dockDarkRimHex;
@property(nonatomic) CGFloat dockRimOpacity,dockDarkRimOpacity,dockBorderWidth,dockDarkBorderWidth;
@property(nonatomic) CGFloat dockRimBrightness,dockDarkRimBrightness,dockRimFade,dockDarkRimFade;
- (WXGScopeOptics)opticsForDock:(BOOL)dock;
- (WXGScopeRim)rimForDock:(BOOL)dock dark:(BOOL)dark;
// FIX85: by scope; the rim values are the current style's own (classic,
// colour from the background, or iOS 27), its colour the classic or iOS 27 one.
- (WXGScopeOptics)opticsForScope:(WXGGlassScope)scope;
- (WXGTransitionSettings)refractionTransitionForScope:(WXGGlassScope)scope;   // FIX114 I / J: 边界过渡 (amount 0 = TEST9 as before)
- (WXGBackdropTone)backdropToneForScope:(WXGGlassScope)scope;   // FIX114 J
- (WXGBackdropTone)backdropToneForScope:(WXGGlassScope)scope dark:(BOOL)dark;   // FIX124: the appearance's (本体照 iOS 26: its material's)
- (CGFloat)ios26BlurForScope:(WXGGlassScope)scope side:(CGFloat)side;   // FIX124: the system's blur for a glass of that short side; < 0: off
- (WXGDropShadowSettings)dropShadowForScope:(WXGGlassScope)scope dark:(BOOL)dark;   // FIX114 K
- (WXGGlassScope)sharedScope:(WXGGlassScope)scope page:(WXGSharePage)page;   // FIX114 L: the range whose settings of that page it uses
- (NSString *)rimSampleOverlayHexForScope:(WXGGlassScope)scope dark:(BOOL)dark;   // FIX114 J: 取自背景's colour overlay (alpha 0 = none)
- (WXGScopeRim)rimForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (NSString *)rimHexForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (WXGRimGlowShape)rimGlowForScope:(WXGGlassScope)scope index:(NSInteger)index dark:(BOOL)dark;   // FIX89: highlight 0 or 1 (FIX113 Z: of that appearance)
- (CGFloat)rimSoftWidthForScope:(WXGGlassScope)scope dark:(BOOL)dark;   // FIX109 B: the 普通 line's soft glow (0 = off)
- (CGFloat)rimSoftLevelForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (WXGRimStyle)rimStyleValue;                                // the other glass's
- (WXGRimStyle)rimStyleForScope:(WXGGlassScope)scope;        // FIX86: each range its own
- (WXGRim26Settings)rim26ForScope:(WXGGlassScope)scope dark:(BOOL)dark;   // FIX123
// FIX113 O: a range's material, its edge weakening, and a lens's parameters.
- (NSString *)materialHexForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (CGFloat)materialOpacityForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (BOOL)materialEdgeFadeOnForScope:(WXGGlassScope)scope;
- (CGFloat)materialEdgeFadeForScope:(WXGGlassScope)scope;
- (WXGLensSettings)lensSettingsForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (WXGKyantElasticParams)kyantElasticParams;
- (WXGLensFlexParams)lensFlexParams;   // FIX126: the system's deformation (iOS 26 recorded), `on` when it replaces Kyant's
// FIX127: iOS 26's tab bar (WXGDockSystem.h; probe 2). All 0 / off: the dock as it was.
- (CGFloat)dockCellExtra;       // each tab's cell this much wider than a quarter of the inside (they overlap)
- (CGFloat)dockLensLiftWidth;   // > 0: the lifted lens is its cell plus this
- (CGFloat)dockLensHang;        // s the lens stays lifted after the finger leaves
- (BOOL)dockMoveSpring;         // the lens goes to a tab on the system's position spring (response s, damping ratio)
- (CGFloat)dockMoveResponse;
- (CGFloat)dockMoveDamping;
- (NSDictionary<NSString *,NSNumber *> *)dockSystem26ValuesForScreenWidth:(CGFloat)width;   // every measured value, as settings
- (void)applyDockSystem26ForScreenWidth:(CGFloat)width;   // into the settings (saved); what was there kept
- (BOOL)hasDockSystem26Backup;
- (BOOL)restoreDockBeforeSystem26;                        // those back; NO: nothing kept
- (WXGKyantBody)kyantBodyForScope:(WXGGlassScope)scope;   // FIX122 D: Kyant's refraction on 其余玻璃 (and ranges sharing it)   // FIX122 C: Kyant's drag-speed deformation (dock and segment bar)
- (NSString *)lensRimHexForScope:(WXGGlassScope)scope dark:(BOOL)dark;
// FIX113 X: the 透镜 range's border as one line (the tap animation's lens,
// a plain layer border): its colour with opacity, and width.
- (UIColor *)lensRimLineColorDark:(BOOL)dark width:(CGFloat *)width;
- (NSString *)lensTintHexForScope:(WXGGlassScope)scope dark:(BOOL)dark;
- (BOOL)knowsKey:(NSString *)key;
- (BOOL)bubbleFullGlass;
// FIX88: the dock lens's colour split: its own band (pt) and top / bottom ratio.
// FIX89: the dock's icons and titles: the gap between them (pt, from the
// icon's box to the title's top; 5 as before) and both moved together (+ down).
- (CGFloat)dockIconTitleGap;
- (CGFloat)dockIconOffset;
// FIX91: the dock's titles: size (pt), weight (0 light, 1 regular, 2 medium,
// 3 semibold, 4 bold) and whether the selected one is a step bolder.
- (CGFloat)dockTitleSize;
- (NSInteger)dockTitleWeight;
- (BOOL)dockTitleBolderSelected;
// FIX97: the colour split of the bar seen through the dock's lens: on / off,
// everywhere in the lens (pt at its rim, growing from 0 at its centre), and
// near its ends (a share of the lens' own split, where it refracts the bar).
- (BOOL)lensBarDispersionOn;
- (CGFloat)lensBarDispersion;
- (CGFloat)lensBarDispersionNearRim;
- (BOOL)dockTapSimpleTravel;   // FIX95
// FIX98: the tap animation: its move's length x (FIX43 = 1), its drop (s),
// and when WeChat switches pages (0 release, 1 lens nearly there, 2 lens down).
- (CGFloat)dockTapDurationScale;
- (CGFloat)dockTapDropDuration;
- (CGFloat)dockTapLensShare;   // FIX99: the share of the move the pill takes to turn into the lens
- (NSInteger)dockTapSwitchMoment;     // FIX100: for a switch at the release (0..2)
- (NSInteger)dockTapSwitchWhen;       // FIX100: 0 touch-down, 1 release, 2 nearly arrived, 3 down
- (BOOL)dockTapSwitchAtTouchDown;
- (BOOL)dockTapWaitForCalm;           // FIX101: after a switch the lens waits for the main thread to be calm
- (BOOL)dockTapCatchUp;               // FIX102: after a pause the rest of the tap runs a little faster
// 离散底栏 (WXGDockDiscrete.h): the selected tab a wide capsule (icon, 中文 /
// English titles), the others balls; connected balls, the original pill on
// the selected tab, the gap, the selection's width in cells, the balls'
// size (x the dock's height), the spring (damping ratio, response s), and
// lighter glass for the pieces.
- (BOOL)dockDiscrete;
- (BOOL)dockDiscreteConnected;
- (BOOL)dockDiscretePill;
- (CGFloat)dockDiscreteGap;
- (CGFloat)dockDiscreteWide;
- (CGFloat)dockDiscreteBall;
- (CGFloat)dockDiscreteDamping;
- (CGFloat)dockDiscreteResponse;
- (BOOL)dockDiscreteLight;
- (CGFloat)dockDiscreteIconSize;       // FIX106 B: pt
- (CGFloat)dockDiscreteTitleSize;      // FIX106 B: 中文 title, pt
- (CGFloat)dockDiscreteSubtitleSize;   // FIX106 B: English title, pt
- (CGFloat)dockDiscreteGather;         // FIX106 C: connected, icons toward the run's middle (share of a cell)
- (CGFloat)dockDiscreteContentShift;   // FIX106 H: wide capsule's icon + titles moved left (pt; 0 = centred)
// FIX95: the chat title's avatar.
- (CGFloat)avatarSize;
- (CGFloat)avatarOffsetY;
- (CGFloat)avatarBorderWidth;
- (NSString *)avatarBorderHexDark:(BOOL)dark;
- (CGFloat)lensDispersionWidth;
- (CGFloat)lensDispersionTopRatio;
// FIX85: keys stored in a table (WXGConfig.m), read by name.
- (double)extraNumber:(NSString *)key;
- (NSString *)extraHex:(NSString *)key;
- (void)reinheritExtrasMissingFrom:(NSDictionary *)values;
- (NSString *)rimHexForDock:(BOOL)dock dark:(BOOL)dark;
- (void)save;
- (void)reset;
- (void)resetKeys:(NSArray<NSString *> *)keys;   // FIX81: one settings page
- (void)resetAllKeeping:(NSArray<NSString *> *)kept;   // FIX115 H: every key to this build's defaults but these
- (void)segmentFromDock;   // FIX113 P: the segment bar's glass, lens, pill and titles from the dock's values now (saved)
- (BOOL)reloadSharedParameters;
- (NSDictionary *)parameterValues;
- (NSArray *)keys;   // FIX84: every stored key (sharing, build defaults)
@end

// FIX33: a render-server backdrop (blur + light saturation) for the dock's
// tap animation lens; nil when the private class is unavailable.
FOUNDATION_EXPORT CALayer *WXGMakeTravelBackdropLayer(CGFloat blurRadius);
// FIX36: backdrop views for the tap-animation lens: the lens optics at full
// press (refraction, edge width and narrowing, zoom, per-channel dispersion)
// as a mesh for `size`. Their layers go into the animated lens.
// FIX88: in `group` (the dock glass's backdrop group: the page without the
// dock's veil, which the tap animation then draws itself); nil = its own capture.
FOUNDATION_EXPORT NSArray<UIView *> *WXGMakeTravelLensBackdrops(CGSize size,CGFloat press,NSString *group,BOOL seesBar,CGFloat barHeight);
// FIX113 I: the share of the lens' rim offset cancelled (0 unless the
// server's shader knows it).
FOUNDATION_EXPORT BOOL WXGLensCancelAvailable(void);
FOUNDATION_EXPORT CGFloat WXGLensCancel(void);
// FIX40: bumped whenever the configuration changes (save or reload).
FOUNDATION_EXPORT NSUInteger WXGConfigRevision(void);
@interface WXGGlassView : UIView
// FIX33: the dock's own lens steps aside while the render-server tap
// animation travels; the overlay then draws every icon unselected, no pill.
@property(nonatomic) BOOL lensSuppressed;
// FIX36: hide the Metal overlay (the render-server veil stands in) while the
// dock's tap animation draws icons and lens itself.
@property(nonatomic) BOOL overlayHidden;
- (BOOL)drawNow;   // YES when a frame was encoded (waits up to 12 ms for the GPU slot)
@property(nonatomic,readonly) NSString *renderState;   // FIX42: cold-start probe
@property(nonatomic) BOOL backgroundMoving;
@property(nonatomic,weak) UIView *sourceView;
@property(nonatomic,weak) UIView *calibrationView;
// Stored as weak membership; getter returns a temporary snapshot.
@property(nonatomic,copy) NSArray<UIView *> *backdropExclusions;
@property(nonatomic) CGRect glassRect;
@property(nonatomic) CGRect lensRect;
// FIX113 Y: the lens' height without the drag-speed deformation (0 unknown):
// the strip between the smaller bar and the lens' rim is kept against it.
@property(nonatomic) CGFloat lensRestHeight;
@property(nonatomic) CGFloat pressAmount;
// FIX98: how much of the resting selection colour the lens shows, 0..1 (a
// tap's scripted fade); < 0 (the default): by the press (WXGRestingSelectionWeight).
@property(nonatomic) CGFloat selectionWeight;
@property(nonatomic) CGFloat barScale, lensAnchorX;
@property(nonatomic) CGFloat maximumCornerRadius;

@property(nonatomic) BOOL active;
@property(nonatomic) BOOL dockSurface;
// FIX85: a liquid chat bubble: its own optics and rim (the "气泡" range).
@property(nonatomic) BOOL bubbleSurface;
@property(nonatomic,readonly) WXGGlassScope glassScope;
// FIX59: one backdrop at most 2x, no RGB channels or clear ring (the settings
// cards: many large glass on one page). The optics are otherwise the same.
@property(nonatomic) BOOL lightweight;
// FIX82: this glass's own tint (colour with its opacity) instead of the
// material colour and opacity of the settings; the rim's colour from the
// material follows it. nil = the settings (the liquid chat bubbles set it).
// FIX83: with it, the tint's own edge weakening (pt from the outline, the
// material's curve; 0 = uniform) instead of the settings'.
@property(nonatomic,strong) UIColor *veilOverride;
@property(nonatomic) CGFloat veilOverrideFade;
// FIX86: the rim always takes its dark-appearance settings (视频号's buttons,
// over video whatever the system appearance).
@property(nonatomic) BOOL rimAlwaysDark;
// FIX114 K: no drop shadow for this glass whatever its range sets (a host
// that draws its own or where a shadow cannot fit).
@property(nonatomic) BOOL dropShadowOff;
// FIX88: for the dock's tap animation: this glass's backdrop group (its layers
// share one capture of the page behind it, without this glass's own veil;
// nil outside render-server mode), the veil's colour as drawn, and the bar
// outline its lens last drew: one line, or (FIX89, the iOS 27-like rim) one
// per highlight, colour and width each.
@property(nonatomic,readonly,copy) NSString *backdropGroupName;
// FIX113 U: the lens' backdrop captures the bar beneath it (its own group)
// and refracts it; the tap animation's lens does the same.
@property(nonatomic,readonly) BOOL lensSeesBar;
@property(nonatomic,readonly) UIColor *veilColor;
@property(nonatomic,readonly) NSArray<UIColor *> *lensOutlineColors;
@property(nonatomic,readonly) NSArray<NSNumber *> *lensOutlineWidths;
// FIX60: the outline is being animated (dock search morph): the outline's
// distance field (Metal overlay only) is neither dropped nor rebuilt per frame.
@property(nonatomic) BOOL shapeAnimating;
// 离散底栏: the outline changes every frame of a switch while the overlay
// stays on. The native distance field is dropped and not requested (the
// shader's capsule distance stands in, exact for a capsule); NO again once
// the outline rests, and the field is made once for it.
@property(nonatomic) BOOL deferShapeField;
// Ordinary controls use optical deformation in their single body, never a second lens.
@property(nonatomic) BOOL buttonPressEffect;
// FIX113 O: this glass's range instead of its surface's (-1, the default:
// the dock / bubble / other glass by its surface): 分组 for the chat list's
// segment bar (a dock surface: the lens, but its own range and lens
// parameters), 设置页 for the settings pages' cards and buttons.
@property(nonatomic) NSInteger glassScopeOverride;
@property(nonatomic) NSInteger rimScopeOverride;   // FIX115 S: its border from this range (-1: its glass range's)
// FIX113 N: the resting selection (the segment bar's pill): this colour with
// its opacity instead of the selection colour of the settings.
@property(nonatomic,strong) UIColor *selectionOverride;
// FIX113 P: its alpha while pressed (as the dock's selection fades into the
// lens); < 0: the colour's own alpha throughout.
@property(nonatomic) CGFloat selectionOverridePressedAlpha;
@property(nonatomic,readonly) BOOL needsDraw;   // FIX113 N: a frame still to draw (the segment bar's idle pause waits for it)
@property(nonatomic,readonly) BOOL needsBackdropCapture,directDemoCapture;
@property(nonatomic,readonly) BOOL wantsBackdropCopy;
@property(nonatomic,readonly) CFTimeInterval lastBackdropCopyTime;
- (void)preparePresentation;
- (NSDictionary *)frameMetrics;
@property(nonatomic,copy) void (^onToneLevel)(CGFloat toneLevel);
@property(nonatomic,copy) void (^onReady)(BOOL ready);
@property(nonatomic,copy) void (^onFirstFrame)(void);
@property(nonatomic,readonly) BOOL hasPresentedFrame;
// FIX114 Y: its drop shadow never opens WeChat's clipping views above it (the
// menus: their own rounded containers clip square backgrounds and shadows,
// which showed as grey squares at the corners once opened).
@property(nonatomic) BOOL keepsAncestorClips;
/* FIX115 B (user, 02:54 screenshots, and the same at 01:25 on X: grey corners
   at the long-press and "+" menus; measured: a soft grey only inside the
   menu's own rectangle, around the glass's larger rounded corners, nothing
   outside it): this glass's own drop shadow, cut by the menu's container (the
   long-press menu's 8 pt rounded content view, the "+" menu's picture view),
   both clipping. L/M never opened them: the walk up stopped at the first view
   over 220 pt high, which was the plugin's own surface around the glass (made
   40 pt larger each side for the shadow: 226 / 292 pt); Y then opened nothing.
   With a root set: every clipping view from the glass up to and including the
   root that cuts the shadow is opened and held (any height; the plugin's own
   views never stop the walk), nothing above the root; a fade of the root
   (alpha) does not let them go, only hiding or leaving the window. Their
   paint was cleared (Z, the decorations' bag), so only the shadow shows. */
@property(nonatomic,weak) UIView *shadowClipRoot;
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) NSString *diagnostics;
@property(nonatomic,readonly) NSDictionary *layerEvidence;
- (void)setNormalIcons:(UIImage *)normal selectedIcons:(UIImage *)selected;
- (void)setNormalIconTexture:(id<MTLTexture>)normal selectedIconTexture:(id<MTLTexture>)selected;
// FIX113: a rectangle of an icon atlas texture redrawn in place: `pixels`
// (the texture's pixels, top-left origin) cleared and `draw` run in the
// atlas's own points (UIKit drawing, as the atlas was drawn at `scale`).
// NO when that texture cannot be written.
- (BOOL)drawIconPatchAtPixels:(CGRect)pixels scale:(CGFloat)scale selected:(BOOL)selected drawing:(void (^)(void))draw;
- (void)tick:(CFTimeInterval)time;
- (void)invalidateBackdrop;
- (void)applyStyle;
- (void)releaseTransientResources;
@end

@interface WXGDemoBar : UIControl
@property(nonatomic,readonly) WXGGlassView *glass;
@property(nonatomic,readonly) NSString *diagnostics;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL externallyDriven;
@property(nonatomic,readonly) CGRect materialRect;
@property(nonatomic,readonly) NSInteger selectedIndex;
// FIX31: the lens has reached its tab / the whole lens animation has ended.
@property(nonatomic,readonly) BOOL lensArrived,lensAtRest;
@property(nonatomic,readonly) BOOL holdsTabSwitch;   // FIX95: the real lens of a tap is still on its way
- (BOOL)holdsTabSwitchAtMoment:(NSInteger)moment;    // FIX99: the same for a given moment (a first visit waits for the landing)
- (void)noteTabSwitchForwarding;                     // FIX99: the host forwards a switch now (its stall pauses the lens)
// FIX100: a touch going to another tab asks WeChat to switch right away
// (切换页面的时机 按下时, as WeChat's own tab bar does); the host forwards it
// and answers whether it did.
@property(nonatomic,copy) BOOL (^tabSwitchRequest)(NSInteger index);
// FIX100: while the release's UIControlEventValueChanged goes out: WeChat is
// already on this tab since the touch-down (nothing to forward).
@property(nonatomic,readonly) BOOL switchedAtTouchDown;
// FIX100: WeChat's switch held the main thread since `before`: a running tap
// animation carries on from where it stopped (no jump, however long).
- (void)tabSwitchForwardedFrom:(CFTimeInterval)before;
@property(nonatomic,readonly) BOOL travelling;   // FIX34: render-server tap animation in progress
// FIX89: a finger resting on the tab already selected (no glide, no other tab):
// the only press the settings fallback's long press may take.
@property(nonatomic,readonly) BOOL restingOnSelectedTab;
@property(nonatomic,readonly) NSString *nativeIconSummary;   // FIX36: icon read state (cold-start log)
@property(nonatomic,readonly) NSString *renderState;   // FIX42: cold-start probe
- (void)syncSelectedIndex:(NSInteger)index;
- (void)prewarmTravel;   // FIX39: build the tap animation's layers and backdrop while idle
- (void)updateBadges:(NSArray<NSString *> *)badges;
- (void)updateBadgeArt:(NSArray *)art;   // FIX108 D: WeChat's / a theme's own badge pictures (NSNull = the dock's label)
- (void)applyConfig;
- (void)cancelInteraction;
- (void)previewLens;
- (void)updateNativeIconsFromTabController:(UITabBarController *)tabs;
- (void)tick:(CADisplayLink *)link;
// FIX60: the dock beside its search button. searchMode: the bar is a round
// close button (a tap sends UIControlEventPrimaryActionTriggered), no tabs.
// The search morph sets the glass outline (own coordinates) and how far the
// tabs have given way to the close glyph (0 tabs .. 1 close); the capsule
// (materialRect) with 0 is the ordinary dock again.
@property(nonatomic) BOOL searchMode;
@property(nonatomic) BOOL showsClose;   // FIX63: NO when the close button is the search button's (right side)
// FIX68: how far each end may be pushed out when the lens is dragged past the
// last tab (0 = only the setting's distance): the search button's side keeps
// clear of it.
@property(nonatomic) CGFloat endStretchRoomLeft,endStretchRoomRight;
@property(nonatomic,readonly) BOOL morphing;
- (void)setSearchShape:(CGRect)shape progress:(CGFloat)progress;
// 离散底栏 (WXGDockDiscrete.h): shown (not while searching or morphing). The
// glass that draws the dock now: the pieces' (one per capsule in use) or
// the bar's; every glass the dock owns (memory warnings); the bar glass's
// source view and exclusions copied to the pieces (after the host sets them).
@property(nonatomic,readonly) BOOL discreteShown;
@property(nonatomic,readonly) NSArray<WXGGlassView *> *renderGlasses;
@property(nonatomic,readonly) NSArray<WXGGlassView *> *allGlasses;
- (void)propagateGlassSources;
@end

// FIX60/63: the dock's search button: a round glass. The host animates its
// outline (`shape`, own coordinates) and its glyphs (magnifier, close), and
// places `fieldView` (magnifier + text field) over the glass that ends on the
// left: `setFieldFrame:` in fieldView's superview's coordinates. Tapped while
// round it sends UIControlEventPrimaryActionTriggered; open with
// closesWhenOpen (button on the right) a tap calls onClose; the field's
// search key calls onSubmit.
@interface WXGDockSearch : UIControl
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic,strong,readonly) UITextField *field;
@property(nonatomic,strong,readonly) UIView *fieldView;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL expanded;          // the field is (being) shown
@property(nonatomic) BOOL closesWhenOpen;
@property(nonatomic,readonly) CGRect shape;
@property(nonatomic,copy) void (^onSubmit)(NSString *text);
@property(nonatomic,copy) void (^onClose)(void);
- (void)setShape:(CGRect)shape magnifier:(CGFloat)magnifier close:(CGFloat)close;
- (void)setFieldFrame:(CGRect)frame reveal:(CGFloat)reveal iconRides:(BOOL)rides;
- (void)applyConfig;
- (void)tick:(CFTimeInterval)time;
@end
