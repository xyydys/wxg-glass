#import "WXGCommon.h"
#import "WXGBackdropSample.h"

// Guard compositor readback against plugin layout re-entry. The sampler
// never changes native visibility, masks or frames.
BOOL WXGBackdropCaptureInProgress(void);
void WXGBeginNativeInputLayout(void);
void WXGEndNativeInputLayout(void);
BOOL WXGNativeInputLayoutInProgress(void);
#import "WXGGeometry.h"
#import <objc/runtime.h>
#import <objc/message.h>

FOUNDATION_EXPORT void WXGClaimInputTool(UIView *tool,id owner);
FOUNDATION_EXPORT void WXGReleaseInputTool(UIView *tool,id owner);
FOUNDATION_EXPORT id WXGRead(id object,NSString *key);
FOUNDATION_EXPORT NSArray<UIView *> *WXGViews(UIView *root,NSUInteger limit);
// FIX60: one of the plugin's own views, decided without a class name
// (asking a Swift class for its name demangles it, slow the first time).
FOUNDATION_EXPORT BOOL WXGIsPluginView(UIView *view);
FOUNDATION_EXPORT BOOL WXGVisible(UIView *view,UIWindow *window);
FOUNDATION_EXPORT CGRect WXGWindowRect(UIView *view,UIWindow *window);
FOUNDATION_EXPORT CGRect WXGRectInSource(UIView *view,UIView *source);
FOUNDATION_EXPORT BOOL WXGImageIsMonochrome(UIImage *image);
FOUNDATION_EXPORT UIImage *WXGCropInk(UIImage *image,UIColor *tint);
FOUNDATION_EXPORT UIImage *WXGButtonImage(UIControl *button);
FOUNDATION_EXPORT NSDictionary *WXGRenderedInkEvidence(UIView *view);
FOUNDATION_EXPORT NSArray<NSString *> *WXGActionNames(UIControl *control);
FOUNDATION_EXPORT BOOL WXGCanForward(UIControl *control);
FOUNDATION_EXPORT CGRect WXGCGRect(WXGRect r);
/* One coordinator owns all source captures. Consumers never start a capture. */
void WXGRegisterBackdropView(WXGGlassView *view);
UIView *WXGContentSourceForView(UIView *view);
FOUNDATION_EXPORT void WXGBeginBackdropFrame(NSArray<WXGGlassView *> *views,BOOL moving,CFTimeInterval frameTime);
FOUNDATION_EXPORT NSDictionary *WXGBackdropEvidence(void);
FOUNDATION_EXPORT void WXGInvalidateSharedBackdrop(void);
/* FIX16: glass ticks issued between Begin/End are queued and run by
   WXGFlushDeferredGlassTicks after the Core Animation commit. */
FOUNDATION_EXPORT void WXGBeginDeferredGlassTicks(void);
FOUNDATION_EXPORT void WXGEndDeferredGlassTicks(void);
FOUNDATION_EXPORT void WXGFlushDeferredGlassTicks(void);
FOUNDATION_EXPORT void WXGDropDeferredGlassTicks(void);
FOUNDATION_EXPORT NSUInteger WXGDeferredGlassTickCount(void);
/* FIX17: display timing for prediction. The host passes the display link's
   target time and transition state before each read; glass reports the
   measured capture-to-presentation latency of every fresh background. */
FOUNDATION_EXPORT void WXGBackdropSetFrameTiming(CFTimeInterval targetTimestamp,BOOL interactive,BOOL transition);
FOUNDATION_EXPORT void WXGBackdropRecordPresentationLatency(double seconds);
/* FIX18: 0 readback, 1 hybrid, 2 render server; 0 when CABackdropLayer is absent. */
// FIX31: attribution of main-thread time during dock taps (see dockProfile).
typedef NS_ENUM(NSInteger,WXGProfileSlot) {
    WXGProfileTick,WXGProfileDock,WXGProfileDraw,WXGProfileSync,WXGProfileMesh,
    WXGProfileRefresh,WXGProfileSwitch,WXGProfileCleanup,
    WXGProfileCommit,   // FIX101: Core Animation's commit (layout and drawing of every app layer)
    WXGProfileHooks,    // FIX102: the plugin's hooks in WeChat's own passes (layout hooks, observers)
    WXGProfileSlotCount
};
FOUNDATION_EXPORT void WXGProfileAdd(WXGProfileSlot slot,double milliseconds);
FOUNDATION_EXPORT void WXGProfileMeshBuilt(void);
FOUNDATION_EXPORT double WXGProfileOursTotal(void);   // FIX102: tick + refresh + switch + hooks so far (to time a hook without its nested parts)
FOUNDATION_EXPORT NSInteger WXGEffectiveRenderMode(void);
/* FIX19: main-thread wait for the batched transaction present, last frame. */
FOUNDATION_EXPORT double WXGGlassScheduleWaitMS(void);
/* FIX64: page edge fade + blur. The host reports every controller's
   appearance (YES) and layout (NO); the chat page and the other pages
   (home, contacts, Moments, chat settings) get the fade and blur bands. */
FOUNDATION_EXPORT void WXGEdgeFadeNoteController(UIViewController *controller,BOOL appearing);
FOUNDATION_EXPORT NSDictionary *WXGEdgeFadeEvidence(void);
/* FIX74: every glass rim (iOS 26 / classic), for the diagnostics export. */
FOUNDATION_EXPORT NSDictionary *WXGRimSummary(void);
/* FIX67: how far the home page's mini-program panel is open, 0 .. 1. */
FOUNDATION_EXPORT CGFloat WXGHomePanelProgressForController(UIViewController *home);
/* FIX94: pulling the home list down, WeChat moves its own title bar buttons
   into the list's header (WAMainFrameTaskBarView): YES while one of them is
   inside `list` (the edge fade then leaves the list's top alone). */
FOUNDATION_EXPORT BOOL WXGHomeTopBarInList(UIView *list);
/* FIX94: the page's fade and blur follow its list again now. */
FOUNDATION_EXPORT void WXGEdgeFadeSyncController(UIViewController *controller);

@interface WXGPreferences : NSObject
+ (instancetype)shared;
@property(nonatomic) BOOL enabled,nav,dock,input,avatarTitle,homeSearch,nativeInputTest,adaptiveIdle;
@property(nonatomic) CGFloat sizeScale;
// FIX60: the dock's search button, on the left instead of the right, and
// hiding the search bar at the top of the chat list.
@property(nonatomic) BOOL dockSearch,dockSearchLeading,hideTopSearch;
// FIX64: the page edge fade + blur (WXGEdgeFade.m).
@property(nonatomic) BOOL edgeFade;
// FIX82: liquid chat bubbles (WXGBubbles.m).
@property(nonatomic) BOOL bubbles;
// FIX84: the frame-rate log and its on-screen capsule (WXGPerfMonitor.m).
@property(nonatomic) BOOL perfMonitor,perfHUD;
- (NSArray *)keys;
- (void)save;
@end

/* FIX84: frame-rate log (WXGPerfMonitor.m). */
FOUNDATION_EXPORT void WXGPerfApplyPreferences(void);              // start / stop with the switches
FOUNDATION_EXPORT void WXGPerfNotePluginWork(double milliseconds);  // the plugin's main-thread time
FOUNDATION_EXPORT BOOL WXGPerfActive(void);
// Runs `work`, adding its time to the plugin's (unless inside the host's timed tick / refresh).
FOUNDATION_EXPORT void WXGPerfTimePluginWork(void (NS_NOESCAPE ^work)(void));
FOUNDATION_EXPORT BOOL WXGHostTimingPlugin(void);                 // inside the host's timed tick / refresh
FOUNDATION_EXPORT NSDictionary *WXGPerfEvidence(void);             // summary for the diagnostics
FOUNDATION_EXPORT void WXGPerfShowReport(UIViewController *from);
FOUNDATION_EXPORT void WXGPerfExportFrom(UIViewController *from);
FOUNDATION_EXPORT void WXGPerfClear(void);
/* FIX85: where the settings page's wallpapers and avatar are (WXGSettings.m). */
FOUNDATION_EXPORT NSDictionary *WXGSettingsStorageEvidence(void);
/* FIX85: keyboard trace for the diagnostics (WXGKeyboardTrace.m). */
FOUNDATION_EXPORT void WXGKeyboardTraceStart(void);
FOUNDATION_EXPORT NSDictionary *WXGKeyboardTraceEvidence(void);
/* FIX85/88: how calm the background behind each glass is (WXGCalmBackdrop.m). */
FOUNDATION_EXPORT void WXGCalmRegister(WXGGlassView *glass);
FOUNDATION_EXPORT void WXGCalmApplyPreferences(void);
FOUNDATION_EXPORT NSDictionary *WXGCalmEvidence(void);
FOUNDATION_EXPORT NSString *WXGCalmSummaryText(void);
/* FIX84: settings sharing (WXGSettingsShare.m). */
FOUNDATION_EXPORT NSDictionary *WXGSharePayload(void);
FOUNDATION_EXPORT void WXGShareCopy(UIViewController *from);
FOUNDATION_EXPORT void WXGShareExportFrom(UIViewController *from);
FOUNDATION_EXPORT void WXGShareImportClipboard(UIViewController *from,void (^done)(void));
FOUNDATION_EXPORT void WXGShareImportFile(UIViewController *from,void (^done)(void));

/* Only objects actually modified are recorded. Restoration runs on route,
   keyboard-mode, application-state and feature-switch changes. */
@interface WXGViewState : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,readonly) CGRect originalFrame;
@property(nonatomic,readonly) CGFloat originalAlpha;
@property(nonatomic,readonly) BOOL originallyHidden;
@property(nonatomic) BOOL restoreGeometry;
- (instancetype)initWithView:(UIView *)view;
- (void)restore;
- (void)updateNativeFrame:(CGRect)frame;
@end

void WXGSetInputHostFrame(UIView *view,CGRect frame,WXGViewState *state);
void WXGReleaseInputHost(UIView *view);
void WXGInstallNativeIconGuard(void);

@interface WXGStateBag : NSObject
- (WXGViewState *)remember:(UIView *)view;
- (void)hide:(UIView *)view;
- (void)conceal:(UIView *)view;
- (void)adaptMonochromeImage:(UIImageView *)view;
- (void)adaptLabelColor:(UILabel *)view;
- (void)clear:(UIView *)view;
- (void)paint:(UIView *)view color:(UIColor *)color;   // FIX47
- (void)allowOverflow:(UIView *)view;
- (void)clearImagePaint:(UIImageView *)view;
- (BOOL)centerNativeImage:(UIImageView *)image inHost:(UIView *)host maximumInk:(CGFloat)maximum;
- (void)stripChrome:(UIView *)root preserving:(NSArray<UIView *> *)content;
- (void)reapply;
- (void)restoreView:(UIView *)view;
- (void)restore;
- (NSArray<NSDictionary *> *)evidence;
@end

@interface WXGSurface : UIControl
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic,strong,readonly) UIImageView *iconView;
@property(nonatomic,strong,readonly) UILabel *label;
@property(nonatomic,strong,readonly) UILabel *countLabel;
@property(nonatomic,weak) UIControl *original;
@property(nonatomic,weak) UIView *motionHost;
@property(nonatomic,weak) UIViewController *motionOwner;
@property(nonatomic) CGRect restingFrame;
@property(nonatomic) BOOL followsNative,nativeTransitionActive;
// FIX93: following the native view's opacity, never below this (the home
// page pulled down: WeChat fades its own title bar, the glass stays); and the
// native opacity / hidden state last read (diagnostics).
@property(nonatomic) CGFloat alphaFloor;
@property(nonatomic,readonly) CGFloat nativeAlpha;
@property(nonatomic,readonly) BOOL nativeHidden;
- (void)bindMotionHost:(UIView *)host owner:(UIViewController *)owner;
- (void)beginNativeDeparture;
- (void)followNativePresentation;
@property(nonatomic,copy) void (^perform)(void);
@property(nonatomic) BOOL materialOnly,active;
@property(nonatomic) BOOL plain;
@property(nonatomic) CGFloat maximumCornerRadius;
@property(nonatomic,weak) WXGSurface *pressProxy;
/* FIX70: material-only glass (the chat input field, the home page's top-left
   button) where WeChat's own views take the touches: a passive recognizer on
   `view` drives this glass's press and stretch for touches that begin on it,
   never recognising, delaying or cancelling anything. */
- (void)observeTouchesInView:(UIView *)view;
/* FIX87: this glass never presses or stretches (the input fields' capsule:
   a tap that raised the keyboard grew it, and it shrank back only after the
   keyboard was up); taps on the plain buttons that proxy to it press only
   their own icons. */
@property(nonatomic) BOOL pressFixed;
// FIX87: the icon's colour instead of the label colour (nil = as before).
@property(nonatomic,strong) UIColor *iconTint;
@property(nonatomic,copy) NSString *role;
@property(nonatomic,readonly) CGRect materialRect;
- (void)placeMaterial:(CGRect)rect inParent:(UIView *)parent;
- (void)setImage:(UIImage *)image title:(NSString *)title count:(NSString *)count;
- (void)setNativeIconSource:(UIView *)source preservingColors:(BOOL)preserve;
- (void)applyConfig;
- (void)setExternalPressed:(BOOL)pressed;
- (void)tick:(CFTimeInterval)time;
- (NSDictionary *)evidence;
@end

/* Material-only attachments on the captured native pinned/menu hosts. */
@interface WXGDecorations : NSObject
+ (instancetype)shared;
@property(nonatomic,weak) UIView *source;
- (void)nativeHostLaidOut:(UIView *)view;
- (void)refresh;
- (void)applyConfiguration;
- (NSArray<WXGSurface *> *)visibleSurfaces;
- (void)restore;
- (NSDictionary *)evidence;
@end

/* FIX82: liquid chat bubbles (WXGBubbles.m, WXGBubbleRules.h): WeChat's
   text bubbles drawn as glass, the native bubble image hidden. */
@interface WXGBubbles : NSObject
+ (instancetype)shared;
- (void)textCellLaidOut:(UIView *)cell;
- (void)tick:(CFTimeInterval)time;
- (void)applyConfiguration;
- (void)restore;
- (NSDictionary *)evidence;
@end

@interface WXGInputAdapter : NSObject
@property(nonatomic,readonly) BOOL installed;
@property(nonatomic,strong,readonly) NSArray<WXGSurface *> *surfaces;
@property(nonatomic,weak,readonly) UIView *tool;
- (BOOL)installInController:(UIViewController *)vc window:(UIWindow *)window;
- (void)layout;
- (void)setSuspended:(BOOL)suspended;
- (void)reapplyPaint;
- (void)restore;
- (NSDictionary *)evidence;
@end

/* Opt-in native-width input experiment; the TEST4 adapter remains the default. */
@interface WXGNativeInputAdapter : NSObject
@property(nonatomic,readonly) BOOL installed;
@property(nonatomic,strong,readonly) NSArray<WXGSurface *> *surfaces;
@property(nonatomic,weak,readonly) UIView *tool;
- (BOOL)installInController:(UIViewController *)vc window:(UIWindow *)window;
- (void)layout;
- (void)setSuspended:(BOOL)suspended;
- (void)reapplyPaint;
- (void)restore;
- (NSDictionary *)evidence;
@end

@interface WXGIntegrationHost : NSObject
+ (instancetype)shared;
- (void)start;
- (void)schedule;
- (void)layoutInput;
- (void)presentSettings;
- (NSString *)versionString;
- (void)openSettingsFrom:(UIViewController *)controller;
- (void)previewLens;
- (NSDictionary *)runtimeMetrics;
- (NSDictionary *)samplingMetrics;
- (NSDictionary *)evidence;
- (NSString *)diagnostics;
- (void)recordForward:(NSDictionary *)action;
- (void)exportDiagnosticsFrom:(UIViewController *)controller;
@end

FOUNDATION_EXPORT UIViewController *WXGIntegrationSettings(void);
// FIX106 I: the settings hide WeChat's navigation bar while they are shown and
// give it back after; whether they still hold it (and what WeChat had), and
// the safety net giving it back once no settings page is in the stack.
FOUNDATION_EXPORT BOOL WXGSettingsHoldsNavigation(UINavigationController *nav,BOOL *barWasHidden);
FOUNDATION_EXPORT BOOL WXGSettingsReleaseStaleNavigation(UINavigationController *nav);
FOUNDATION_EXPORT BOOL WXGSettingsShowBarForPage(UIViewController *page);
