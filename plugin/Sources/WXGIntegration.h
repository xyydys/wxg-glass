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

/* FIX115 A (user: another plugin's theme icons, more than a hundred all over
   WeChat, are gone while this one is installed): an override this plugin puts
   on a class for a method the class only inherits (most of WeChat's views:
   layoutSubviews / didMoveToWindow; UIImageView: setFrame: / setBounds: /
   setCenter:) used to call the superclass's implementation as it was when the
   override went in, at launch. A plugin that hooks the superclass after that
   (UIView's layoutSubviews, setFrame: ...) was then skipped for every view of
   that class, and for UIImageView that is every icon. Now:
   WXGOwnImplementation is the class's own implementation (replaced in place,
   called as before) or NULL (inherited), and the override calls
   WXGThrough(own,superclass,selector): for an inherited method the
   superclass's implementation as it is at that call, whoever hooked it.
   FIX115 B (user, 02:54: A did not bring the other plugin's icons back, and
   a white band showed behind the home title row): the overrides call what
   was there when they went in again (WXGCapturedImplementation: the class's
   own or the inherited one, as before A); A's list in the diagnostics stays. */
FOUNDATION_EXPORT IMP WXGOwnImplementation(Class cls,SEL selector);
static inline IMP WXGCapturedImplementation(Class cls,SEL selector) {
    Method m=cls && selector?class_getInstanceMethod(cls,selector):NULL;return m?method_getImplementation(m):NULL;
}
static inline IMP WXGThrough(IMP own,Class superclass,SEL selector) {return own?:class_getMethodImplementation(superclass,selector);}
// Adds the override (the class only inherits the method) or replaces the class's own.
FOUNDATION_EXPORT void WXGInstallOverride(Class cls,SEL selector,IMP replacement,const char *types);
FOUNDATION_EXPORT NSArray<NSDictionary *> *WXGOverrideEvidence(void);   // FIX115 A: what was installed, how; still ours on top?
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
FOUNDATION_EXPORT CGRect WXGSearchFieldBox(UITextField *field);   // FIX114 E: the box a UISearchBar's field draws (null: its bounds)
// FIX114 C: a title bar's content drawn lower by the title row's offset (顶部按钮往下移), and back.
FOUNDATION_EXPORT NSUInteger WXGMoveBarContent(UINavigationBar *bar);   // the content views moved
FOUNDATION_EXPORT void WXGRestoreBarContent(void);
FOUNDATION_EXPORT NSArray<NSString *> *WXGActionNames(UIControl *control);
FOUNDATION_EXPORT BOOL WXGCanForward(UIControl *control);
FOUNDATION_EXPORT CGRect WXGCGRect(WXGRect r);
/* One coordinator owns all source captures. Consumers never start a capture. */
void WXGRegisterBackdropView(WXGGlassView *view);
UIView *WXGContentSourceForView(UIView *view);
FOUNDATION_EXPORT void WXGBeginBackdropFrame(NSArray<WXGGlassView *> *views,BOOL moving,CFTimeInterval frameTime);
FOUNDATION_EXPORT NSDictionary *WXGBackdropEvidence(void);
FOUNDATION_EXPORT NSDictionary *WXGDropShadowEvidence(void);   // FIX114 M
// FIX114 M (review): a view a drop shadow holds open, about to be opened by a
// WXGStateBag: YES and its own clipsToBounds in *clipsWithout (the shadow
// leaves it to that bag from then on); NO when no shadow holds it.
FOUNDATION_EXPORT BOOL WXGShadowAdoptOverflow(UIView *view,BOOL *clipsWithout);
// FIX115 K: a view held open (not clipping) for `holder` (weakly), with the shadows' count.
FOUNDATION_EXPORT void WXGHoldClipOpen(UIView *view,id holder);
FOUNDATION_EXPORT void WXGReleaseClipHolds(id holder);
/* FIX114 R: the title-bar trace (WXGHost.m), recorded while the diagnostics
   export button is on: on (callers build their text only then), a line for an
   event, a line for `key` only when its text changed, a page's short tag. */
FOUNDATION_EXPORT BOOL WXGNavTraceOn(void);
FOUNDATION_EXPORT void WXGNavTraceEvent(NSString *text);
FOUNDATION_EXPORT void WXGNavTraceEventOnce(NSString *key,NSString *text);
FOUNDATION_EXPORT NSString *WXGNavTracePage(UIViewController *page);
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
// FIX107: more of WeChat in glass (WXGLocalGlass.m): search fields, the plus
// panel's tiles, the emoji board's keys and group selection, the share sheet.
@property(nonatomic) BOOL localSearch,localPanel,localEmoji,localSheet;
// FIX108: title capsules; glass for the title-bar buttons the host leaves native.
@property(nonatomic) BOOL localTitle,localNavButtons;
// FIX109: a theme's search field kept as the theme draws it (default: the glass
// wins); the chat page's top-right button shows the chat's avatar.
@property(nonatomic) BOOL localSearchThemeFirst,chatAvatarButton;
- (NSArray *)keys;
- (void)save;
// FIX115 H: every switch (and 整体大小) to this build's defaults, else the
// built-in ones; not the main switch, 首页搜索 or the frame-rate logs.
- (void)resetToBuildDefaults;
@end

/* FIX84: frame-rate log (WXGPerfMonitor.m). */
FOUNDATION_EXPORT void WXGPerfApplyPreferences(void);              // start / stop with the switches
FOUNDATION_EXPORT void WXGPerfNotePluginWork(double milliseconds);  // the plugin's main-thread time
FOUNDATION_EXPORT BOOL WXGPerfActive(void);
// Runs `work`, adding its time to the plugin's (unless inside the host's timed tick / refresh).
FOUNDATION_EXPORT void WXGPerfTimePluginWork(void (NS_NOESCAPE ^work)(void));
// FIX113 Z: the same, its time also kept under `label` for the page-switch log.
FOUNDATION_EXPORT void WXGPerfTimePluginWorkAs(const char *label,void (NS_NOESCAPE ^work)(void));
/* FIX113 Z: page-switch performance (WXGPerfMonitor.m): every push, pop,
   presentation, dismissal and tab switch while the plugin is on (or the
   frame-rate log is), from the call that started it to 0.3 s after its
   animation ended: the first frame, frames missed, the worst frame and where
   the main thread's time went (the plugin's parts, Core Animation's commit,
   WeChat's own). Its own display link runs only during a switch. */
FOUNDATION_EXPORT BOOL WXGTransitionPerfOn;   // a switch is being recorded (fast check for the notes below)
FOUNDATION_EXPORT void WXGTransitionPerfNavigationCall(NSString *kind,BOOL began);   // outermost push / pop call starts / ends
FOUNDATION_EXPORT void WXGTransitionPerfBegin(NSString *kind,UIViewController *from,UIViewController *to,id<UIViewControllerTransitionCoordinator> coordinator);
FOUNDATION_EXPORT void WXGTransitionPerfAppearance(UIViewController *controller,BOOL appearing);   // from viewWillAppear: / viewWillDisappear:
FOUNDATION_EXPORT void WXGTransitionPerfNoteSlot(NSInteger slot,double milliseconds,BOOL plugin);
FOUNDATION_EXPORT void WXGTransitionPerfNoteIdle(double milliseconds);
FOUNDATION_EXPORT void WXGTransitionPerfNoteMesh(void);
FOUNDATION_EXPORT void WXGTransitionPerfCommitPhase(BOOL inside);   // Core Animation's commit starts / ends
FOUNDATION_EXPORT void WXGTransitionPerfLabel(NSString *label,double milliseconds);   // the plugin's time by part
FOUNDATION_EXPORT NSDictionary *WXGTransitionPerfEvidence(void);
// FIX119 A: every scroll recorded in full (WXGPerfMonitor.m); the glass' GPU time and submissions
FOUNDATION_EXPORT void WXGScrollPerfInstall(void);
FOUNDATION_EXPORT void WXGStallSamplerArm(double seconds,NSString *label);   // FIX119 D: sample the main thread's stalls for a while
FOUNDATION_EXPORT void WXGStallSamplerPause(BOOL paused);                     // FIX119 E
FOUNDATION_EXPORT void WXGPerfNoteGPU(double milliseconds);
FOUNDATION_EXPORT void WXGPerfNoteGlassSubmit(void);
FOUNDATION_EXPORT void WXGTransitionPerfShowReport(UIViewController *from);
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
- (void)unconceal:(UIView *)view;   // FIX114 S: shown again (its mask as it was), the rest of its state kept
- (void)adaptMonochromeImage:(UIImageView *)view;
- (void)adaptLabelColor:(UILabel *)view;
- (void)clear:(UIView *)view;
- (void)paint:(UIView *)view color:(UIColor *)color;   // FIX47
- (void)allowOverflow:(UIView *)view;
// FIX115 J: the fill WeChat last gave a view this bag cleared; a view rounded
// by a mask layer of its own (WeChat's coloured 完成): the mask off, restorably
// (one WeChat sets again goes again on reapply).
- (UIColor *)nativeColorOf:(UIView *)view;
- (void)unmask:(UIView *)view;
- (void)round:(UIView *)view radius:(CGFloat)radius;   // FIX115 Q: drawn round, restorably
- (void)titleColor:(UIButton *)button color:(UIColor *)color;   // FIX115 Q: a button's title colour, restorably
// FIX115 L: cleared, and its layer kept without a fill against WeChat painting it again (restorably).
- (void)guardFill:(UIView *)view;
// FIX115 M: a layer of no view hidden (restorably).
- (void)hideDecorationLayer:(CALayer *)layer;
- (void)clearImagePaint:(UIImageView *)view;
- (BOOL)centerNativeImage:(UIImageView *)image inHost:(UIView *)host maximumInk:(CGFloat)maximum;
// FIX113 E: everything inside a native view drawn `dx` points to the right
// (its layer's sublayerTransform: no frame of WeChat's changes, so its own
// layout never undoes it); 0 puts it back. Restored with the rest.
- (void)shiftContents:(UIView *)view x:(CGFloat)dx;
- (void)shiftContents:(UIView *)view x:(CGFloat)dx y:(CGFloat)dy;   // FIX114 C
- (void)shiftView:(UIView *)view x:(CGFloat)dx y:(CGFloat)dy;       // R22: transform shift for leaf UIImageView/UILabel or container sublayerTransform
- (CGFloat)contentShiftOf:(UIView *)view;
- (CGPoint)contentOffsetOf:(UIView *)view;   // FIX114 C: across and down
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
// FIX114 S: through a push / pop it stays where it is laid out (fading with
// the native view as before, never moving with it). FIX114 T: and it does not
// blink when WeChat swaps that view (out of the window for a moment, or at 0
// opacity for one frame): it keeps showing, its opacity changing as a fade.
@property(nonatomic) BOOL holdsPlace;
// FIX114 V: a copy of a native control's content (WeChat's icon / text /
// count as WeChat draws them) shown in this glass instead of its own icon and
// text, at `nativeContentOrigin` in the glass (the control's place relative to
// it); the signature and source it was copied from (copied again on a change).
@property(nonatomic,strong) UIView *nativeContent;
@property(nonatomic) CGPoint nativeContentOrigin;
@property(nonatomic) NSUInteger nativeContentSignature;
@property(nonatomic,weak) UIView *nativeContentSource;
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
// FIX113: the icon at its own size (WeChat's artwork as WeChat draws it: the
// glyph's points, not fitted to the plugin's icon box); smaller only to fit.
@property(nonatomic) BOOL naturalIconSize;
// FIX87: the icon's colour instead of the label colour (nil = as before).
@property(nonatomic,strong) UIColor *iconTint;
@property(nonatomic,copy) NSString *role;
@property(nonatomic,readonly) CGRect materialRect;
// FIX114 M: a small grey symbol right after the title (the avatar mode's
// capsule: iOS 26's chevron), the text and it centred together; nil: none.
// Its height (pt) and the gap to the text.
@property(nonatomic,strong) UIImage *trailingSymbol;
@property(nonatomic) CGFloat trailingSymbolHeight,trailingGap;
@property(nonatomic) CGFloat trailingBias;   // FIX114 O: the text and symbol moved right (less room after the symbol)
// Ink-drop home "+" trigger button: 270 deg solid arc + dynamic N bottom dots + two-stage +/x swap.
@property(nonatomic) BOOL homePlusTrigger;
- (void)setHomePlusProgress:(double)progress dotsHidden:(BOOL)hidden;
- (void)setHomePlusDotCount:(NSInteger)count;
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

/* FIX107: more of WeChat in glass (WXGLocalGlass.m): material-only glass
   in place of the paint of search fields (capsules), the plus panel's tiles,
   the emoji board's 发送 / 删除 and group selection, and the share sheet's
   background. Hosts are hooked by class (hostClassNames); it runs its own
   display link while one of them is on screen. */
@interface WXGLocalGlass : NSObject
+ (instancetype)shared;
+ (NSArray<NSString *> *)hostClassNames;
- (void)hostLaidOut:(UIView *)view;
- (void)controllerLaidOut:(UIViewController *)controller;
- (void)navigationRouteChanged;   // FIX108: the host's page changed: title-bar buttons looked at again
- (void)applyConfiguration;
- (void)releaseTransientResources;   // memory warning
- (void)restore;
- (NSDictionary *)evidence;
- (NSArray<UIView *> *)navButtonAnchors;   // FIX114 T: title-bar buttons with our glass on screen (the trace)
@end
// FIX114 V: a WeChat title-bar button's glass as the local glass sizes it (in
// the button; CGRectNull: nothing to put one behind), and whether it paints
// its own (a green 完成: left as WeChat has it).
FOUNDATION_EXPORT CGRect WXGNativeNavGlassRect(UIView *button);
FOUNDATION_EXPORT BOOL WXGNativeNavButtonFilled(UIView *button);
// FIX112: the page's title capsule (its title view's text, else the bar's own
// title, as the local glass draws it) in the window; CGRectNull: no title text.
FOUNDATION_EXPORT CGRect WXGLocalTitleCapsuleRect(UINavigationBar *bar,UIView *titleView,UIWindow *window);

/* FIX113 N: the chat list's segment bar in place of its search field
   (WXGChatSegments.m): over the list's search bar on the 微信 page, the
   dock's lens on four segments (a demo grouping), WeChat's bar faded out and
   given back while its own search uses it or when off. */
/* FIX118 A: the 我 page's header as Telegram's profile (WXGMeHeader.m, WXGMeMetaball.h). */
@interface WXGMeHeader : NSObject
+ (instancetype)shared;
- (NSDictionary *)evidence;
// FIX118 B: the banner's video (picked from the photo library, kept in the app's Library)
- (void)pickBannerVideoFrom:(UIViewController *)controller;
- (void)clearBannerVideo;
- (NSString *)bannerVideoName;
@end
FOUNDATION_EXPORT NSString *WXGSelfAvatarState(void);   // FIX118 B: where the 我 page's photo came from
FOUNDATION_EXPORT BOOL WXGMeHeaderOwnsView(UIView *view);   // FIX120 G: the 我 header's own views (the host's top-paint cleaning skips them)

@interface WXGChatSegments : NSObject
+ (instancetype)shared;
- (BOOL)wanted;   // the switch, the plugin on and authorised, render-server mode
- (BOOL)titleModeWanted;   // R20: expand home title capsule into compact All/Unread group bar
- (void)updateOnPage:(UIViewController *)page;   // the host's refresh on the chat list
- (void)updateTitleBarOnPage:(UIViewController *)page inOverlay:(UIView *)overlay rect:(CGRect)rect navTitle:(UIView *)navTitle pullTitle:(UIView *)pullTitle englishHint:(BOOL)englishHint;
- (void)hideTitleBar;      // visually hides the title group bar (keeps MFTitleView concealed while titleModeWanted is on)
- (void)releaseTitleBar;   // hides the title group bar and restores MFTitleView (when titleModeWanted is off or plugin disabled)
- (void)searchBarLaidOut:(UIView *)view;         // a search bar laid out (follows the field)
// FIX113 O: every host frame: the floating search (the segment bar, WeChat's
// home / 通讯录 search bars) and home title group bar in the navigation overlay.
- (void)hostTick:(CFTimeInterval)time page:(UIViewController *)leaf overlay:(UIView *)overlay transitioning:(BOOL)transitioning transitionInvolvesHome:(BOOL)transitionInvolvesHome homePanel:(CGFloat)homePanel rowOffset:(CGFloat)rowOffset;
- (void)suspendFloating;   // a page this host leaves native: nothing left floating, WeChat's bars back
- (void)restore;           // the segment bar (WeChat's search bar back)
- (void)restoreAll;        // the segment bar and the floating capsules (the plugin off)
- (NSDictionary *)evidence;
@end
/* FIX113 R: the user's chat groups (WXGChatSegments.m): 1-6, each
   {id, name, rule (0 全部 1 未读 2 单聊 3 群聊 4 自定义), members (user names)}. */
FOUNDATION_EXPORT NSString * const WXGChatGroupsChanged;
FOUNDATION_EXPORT NSArray<NSDictionary *> *WXGChatGroupList(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *WXGChatGroupDefaults(void);
FOUNDATION_EXPORT void WXGChatGroupSave(NSArray<NSDictionary *> *groups);
// The chats of WeChat's whole home list, for choosing members: id, title, kind
// (2 单聊 3 群聊 0 other); main thread.
FOUNDATION_EXPORT NSArray<NSDictionary *> *WXGChatSessionChoices(void);
FOUNDATION_EXPORT NSString *WXGChatNameSummary(void);   // FIX113 Z: where the names came from (counts only), after WXGChatSessionChoices

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
- (CGFloat)titleRowOffsetForPage:(UIViewController *)page;   // FIX114 C: 顶部按钮往下移 there (NAN when unknown)
- (void)openSettingsFrom:(UIViewController *)controller;
- (void)previewLens;
- (NSDictionary *)runtimeMetrics;
- (NSDictionary *)samplingMetrics;
- (NSDictionary *)evidence;
- (NSString *)diagnostics;
- (void)recordForward:(NSDictionary *)action;
- (void)exportDiagnosticsFrom:(UIViewController *)controller;
// FIX108: a title-bar button the host has no glass for and leaves native (web
// pages, pages presented over the tabs) while the title-bar setting is on.
- (BOOL)leavesNavigationControlNative:(UIView *)control;
// FIX114 V: a chat's title view while the plugin draws chat titles (the avatar
// mode): hidden wherever it is (a new one WeChat makes as a swipe back starts
// too); YES when it is (no capsule of the local glass behind it then).
- (BOOL)concealsChatTitleView:(UIView *)view;
// FIX114 M: WeChat's search page opened at once from `page` (its own search
// entry, as its search button does); NO when that page has none.
- (BOOL)openWeChatSearchOn:(UIViewController *)page;
// FIX116 A: the glass of the home page's "+" in `window` (CGRectNull: the
// plugin has none there); the plus menu's icons are put in line with it.
- (CGRect)homePlusRectInWindow:(UIWindow *)window;
- (WXGSurface *)homePlusSurfaceInWindow:(UIWindow *)window;
// FIX118 A: the user's own photo (HD, from the contact's address; kept on disk); nil while it downloads.
- (UIImage *)selfAvatarPhoto;
@end

FOUNDATION_EXPORT UIViewController *WXGIntegrationSettings(void);
// FIX106 I: the settings hide WeChat's navigation bar while they are shown and
// give it back after; whether they still hold it (and what WeChat had), and
// the safety net giving it back once no settings page is in the stack.
FOUNDATION_EXPORT BOOL WXGSettingsHoldsNavigation(UINavigationController *nav,BOOL *barWasHidden);
FOUNDATION_EXPORT BOOL WXGSettingsReleaseStaleNavigation(UINavigationController *nav);
FOUNDATION_EXPORT BOOL WXGSettingsShowBarForPage(UIViewController *page);
