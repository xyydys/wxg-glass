#import "WXGIntegration.h"
#import "WXGInputRepairPolicy.h"
#import "WXGDockInteraction.h"
#import "WXGDockPresentation.h"
#import "WXGDockSearchLayout.h"
// FIX30: WeChat Settings entry state (defined with the hooks at the end of the file).
static BOOL WXGSettingsEntryReady;
static NSUInteger WXGSettingsEntryInsertions;
// FIX31: main-thread attribution during dock taps. Each slot accumulates the
// milliseconds our code spent since the last display tick; the run-loop idle
// clock measures how long the main thread actually slept. A slow frame's
// "other" time is busy time that was not ours: WeChat's own work.
// FIX36: what happened during the first 30 s after load, one line per change
// (page, navigation glass, dock glass readiness, icon reads).
static CFTimeInterval WXGLoadTime;
static NSMutableArray<NSString *> *WXGColdStartLog;
static NSString *WXGLastColdSummary;
static NSString *WXGLastColdMessage;
static NSUInteger WXGColdRepeats;
static void WXGColdLog(NSString *message) {
    CFTimeInterval t=CACurrentMediaTime()-WXGLoadTime;
    if(!message || t>30)return;
    if(!WXGColdStartLog)WXGColdStartLog=[NSMutableArray array];
    // Identical consecutive lines collapse into one with a repeat count.
    if([message isEqual:WXGLastColdMessage] && WXGColdStartLog.count) {
        ++WXGColdRepeats;
        WXGColdStartLog[WXGColdStartLog.count-1]=[NSString stringWithFormat:@"%@ ×%lu（至 +%.2fs）",
            [WXGColdStartLog.lastObject componentsSeparatedByString:@" ×"].firstObject,(unsigned long)WXGColdRepeats+1,t];
        return;
    }
    if(WXGColdStartLog.count>=150)return;
    WXGLastColdMessage=message;WXGColdRepeats=0;
    [WXGColdStartLog addObject:[NSString stringWithFormat:@"+%.2fs %@",t,message]];
}
static double WXGProfileTotals[WXGProfileSlotCount];
static NSUInteger WXGProfileMeshBuilds;
static CFTimeInterval WXGIdleSince,WXGIdleTotal;
// FIX84: how many of the host's timed passes (its display-link tick, its
// refresh) are running; the frame-rate log takes the outermost one's time.
static NSInteger WXGHostTimedDepth;
BOOL WXGHostTimingPlugin(void) {return WXGHostTimedDepth>0;}
void WXGProfileAdd(WXGProfileSlot slot,double milliseconds) {
    if(slot>=0 && slot<WXGProfileSlotCount)WXGProfileTotals[slot]+=milliseconds;
    // The whole tick; a refresh (reported after it ended) or a tab switch
    // only outside a tick, which already holds them.
    if(slot==WXGProfileTick || (WXGHostTimedDepth==0 && (slot==WXGProfileRefresh || slot==WXGProfileSwitch)))WXGPerfNotePluginWork(milliseconds);
}
void WXGProfileMeshBuilt(void) {++WXGProfileMeshBuilds;}
double WXGProfileOursTotal(void) {
    return WXGProfileTotals[WXGProfileTick]+WXGProfileTotals[WXGProfileRefresh]+WXGProfileTotals[WXGProfileSwitch]+WXGProfileTotals[WXGProfileHooks];
}
CFTimeInterval WXGSecondsSinceLoad(void) {return WXGLoadTime>0?CACurrentMediaTime()-WXGLoadTime:0;}
static BOOL WXGHostQuietForLicense(void);   // FIX102 (below the host)
static void WXGInstallIdleClock(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        CFRunLoopObserverRef sleep=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting,YES,LONG_MAX,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){WXGIdleSince=CACurrentMediaTime();});
        CFRunLoopObserverRef wake=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopAfterWaiting,YES,LONG_MIN,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){
                if(WXGIdleSince>0){WXGIdleTotal+=CACurrentMediaTime()-WXGIdleSince;WXGIdleSince=0;}
            });
        if(sleep){CFRunLoopAddObserver(CFRunLoopGetMain(),sleep,kCFRunLoopCommonModes);CFRelease(sleep);}
        if(wake){CFRunLoopAddObserver(CFRunLoopGetMain(),wake,kCFRunLoopCommonModes);CFRelease(wake);}
    });
}

// Do not rebuild/reparent native chrome inside UIKit's push/pop setup stack.
static NSUInteger WXGNavigationCallDepth;
static NSUInteger WXGPageTopLogs,WXGPageTopRepairs;   // FIX106 I (WXGCheckPageTop)

@interface WXGRoute : NSObject
@property(nonatomic,strong) UIViewController *leaf;
@property(nonatomic,strong) UINavigationController *nav;
@property(nonatomic,strong) UITabBarController *tabs;
@property(nonatomic,copy) NSString *path;
@property(nonatomic) BOOL primary,unsupported,chat,presented;
// FIX67: a chat inside a full-screen presented navigation stack (a chat
// opened from WeChat's search): adapted like a pushed chat, never primary.
@property(nonatomic) BOOL presentedStack;
@end
@implementation WXGRoute
@end
static BOOL WXGPresentedChatStack(WXGRoute *r,UIViewController *root,UIWindow *w) {
    static Class chat;static dispatch_once_t once;
    dispatch_once(&once,^{chat=NSClassFromString(@"BaseMsgContentViewController");});
    if(!chat || ![r.leaf isKindOfClass:chat] || r.unsupported || !root.isViewLoaded || root.view.window!=w)return NO;
    // The chat's own navigation is inside the presentation (not the tabs' one).
    if(!r.nav || !r.nav.presentingViewController)return NO;
    // Full screen and settled: sheets and a presentation still sliding stay covers.
    CGRect f=WXGWindowRect(root.view,w);
    return fabs(f.origin.x)<1 && fabs(f.origin.y)<1 && fabs(f.size.width-w.bounds.size.width)<1 && fabs(f.size.height-w.bounds.size.height)<1;
}
static WXGRoute *WXGRouteForWindow(UIWindow *w) {
    WXGRoute *r=[WXGRoute new];UIViewController *vc=w.rootViewController;
    NSMutableArray *seen=[NSMutableArray array],*names=[NSMutableArray array];BOOL presented=NO;UIViewController *presentedRoot=nil;
    while(vc && seen.count<24 && ![seen containsObject:vc]) {
        [seen addObject:vc];NSString *name=NSStringFromClass(vc.class);[names addObject:name];
        if([name containsString:@"Flutter"] || [name containsString:@"WebView"] || [name hasPrefix:@"WAUINavigation"] || [name hasPrefix:@"WXG"])r.unsupported=YES;
        UIViewController *next=nil;
        if([vc isKindOfClass:UITabBarController.class])r.tabs=(id)vc;
        if([vc isKindOfClass:UINavigationController.class])r.nav=(id)vc;
        if(vc.presentedViewController){next=vc.presentedViewController;if(!presented)presentedRoot=next;presented=YES;}
        else if([vc isKindOfClass:UITabBarController.class])next=((UITabBarController *)vc).selectedViewController;
        else if([vc isKindOfClass:UINavigationController.class])next=((UINavigationController *)vc).visibleViewController;
        else if(!r.nav || ![r.nav.viewControllers containsObject:vc])for(UIViewController *child in vc.childViewControllers.reverseObjectEnumerator)
            if(child.isViewLoaded && WXGVisible(child.view,w) && child.view.bounds.size.width>w.bounds.size.width*.7){next=child;break;}
        r.leaf=vc;vc=next;
    }
    r.path=[names componentsJoinedByString:@" / "];
    r.presentedStack=presented && WXGPresentedChatStack(r,presentedRoot,w);
    r.presented=presented && !r.presentedStack;if(r.presented)r.unsupported=YES;
    r.primary=r.tabs && !presented && (!r.nav || r.nav.visibleViewController==r.nav.viewControllers.firstObject);
    r.chat=[NSStringFromClass(r.leaf.class) isEqual:@"BaseMsgContentViewController"];
    return r;
}
@interface WXGOverlay : UIView
@end
@implementation WXGOverlay
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    if(self.hidden || self.alpha<.01)return nil;
    UIView *v=[super hitTest:p withEvent:event];return v==self?nil:v;
}
@end
static void WXGResetOwnedTransform(UIView *view) {
    // These are plugin-owned model resets inside a native UIView animation
    // transaction. Suppress only our setter; never touch the native animations.
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        view.transform=CGAffineTransformIdentity;[CATransaction commit];
    }];
}
// A page owns its views; it does not reuse a different page's sized canvases.
static char WXGPageStateKey;
@interface WXGPageState : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSString *,WXGSurface *> *pool;
@property(nonatomic,strong) WXGInputAdapter *input;
@end
@implementation WXGPageState
- (void)dealloc {
    for(WXGSurface *surface in _pool.allValues)[surface removeFromSuperview];
    for(WXGSurface *surface in _input.surfaces)[surface removeFromSuperview];
}
@end
// FIX88: a chat page's avatar lookup (the title's avatar mode).
@interface WXGAvatarState : NSObject
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,copy) NSString *source;
@property(nonatomic) BOOL fromService;
@property(nonatomic) NSUInteger attempts,refreshes;
@property(nonatomic) CFTimeInterval lookupAt;
@property(nonatomic) BOOL probed;                    // FIX95: the diagnostics probe ran for this page
@property(nonatomic) CFTimeInterval downloadWaitUntil;   // FIX95: the HD photo is on its way: prefer it
@property(nonatomic,copy) NSString *user;           // FIX100: whose downloaded photo it is
@end
@implementation WXGAvatarState
@end
@interface WXGHostTickProxy : NSObject
@property(nonatomic,weak) WXGIntegrationHost *owner;
- (void)tick:(CADisplayLink *)link;
@end
@interface WXGIntegrationHost () <UIAdaptivePresentationControllerDelegate,UIGestureRecognizerDelegate>
@property(nonatomic,strong) WXGOverlay *overlay,*navigationOverlay;
@property(nonatomic,strong) NSArray<WXGSurface *> *departingButtons;
@property(nonatomic,strong) WXGInputAdapter *departingInput;
@property(nonatomic,strong) id<UIViewControllerTransitionCoordinator> nativeTransition;
@property(nonatomic,weak) id<UIViewControllerTransitionCoordinator> completedTransition;
@property(nonatomic,weak) UIViewController *transitionFrom,*transitionTo;
@property(nonatomic) CFTimeInterval lastMetrics,lastTickTime;
@property(nonatomic) double tickCost,backdropCost,drawCost,refreshCost,maxTickCost;
// FIX16 post-commit frame: the display callback queues; the observer flushes.
@property(nonatomic,strong) NSArray<WXGGlassView *> *pendingBackdropViews;
@property(nonatomic) BOOL backdropFramePending,pendingBackdropMoving;
@property(nonatomic) CFTimeInterval pendingBackdropTime,pendingTargetTime;
@property(nonatomic) BOOL pendingInteractive,pendingTransition;
@property(nonatomic) CFRunLoopObserverRef commitObserver;
@property(nonatomic) NSUInteger postCommitFrames,postCommitFallbacks,droppedPendingFrames;
@property(nonatomic) double postCommitDelayMS,postCommitCost,maxPostCommitCost;
@property(nonatomic) NSUInteger navigationPaintRescans;
// FIX22 tab-switch trace: native switch time, our refresh phases, and the
// display intervals during the following 1.5 s; the last 6 switches.
@property(nonatomic,strong) NSMutableDictionary *tabTrace;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *tabTraces;
@property(nonatomic,strong) NSDictionary *lastSlowRefreshPhases;
// FIX22 cold-start census of everything painting the top of the window.
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *topPaintCensus;
@property(nonatomic) BOOL censusScheduled;
@property(nonatomic,strong) WXGStateBag *snapshotStates,*coldStartStates;
@property(nonatomic) NSUInteger snapshotScanFrames,snapshotsConcealed,coldStartLayersCleared;
// FIX28: a pop toward a tab root starts the snapshot watch even before (or
// without) UIKit's coordinator; concealments last until the next transition.
@property(nonatomic,weak) UIViewController *rootReturnTarget;
@property(nonatomic) CFTimeInterval rootReturnUntil;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *snapshotLog;
@property(nonatomic,copy) NSString *snapshotSource;
@property(nonatomic,strong) NSHashTable<UIView *> *snapshotViews;
@property(nonatomic,weak) UIViewController *rootReturnOther;
@property(nonatomic) NSUInteger pageTopPaintCleared;
@property(nonatomic) CFTimeInterval lastTopPaintScan;
// FIX30: tab root pages loaded ahead of the first switch, and the finer
// timing of the route/tree phase of a refresh.
@property(nonatomic) BOOL prewarmScheduled;
@property(nonatomic) CFTimeInterval lastColdNavAttempt;
@property(nonatomic) NSUInteger appearances,stalePendingClears,appearanceMatches;
@property(nonatomic,copy) NSString *lastDockProbe;
// FIX50: the wallet (Kinda) list chain whose clipping was lifted.
@property(nonatomic,copy) NSArray<NSString *> *kindaProbe;
@property(nonatomic,copy) NSString *lastNavLog;
@property(nonatomic,strong) NSMutableArray<NSString *> *prewarmed;
@property(nonatomic,strong) NSMutableDictionary *routePhases;
// FIX31: deferred tab switch and the dock tap profile.
@property(nonatomic) NSInteger pendingTabIndex;
@property(nonatomic) BOOL pendingUntilLanded;   // FIX95: waiting for the tap's real lens to be down
@property(nonatomic) NSInteger pendingRetaps;   // FIX95: the same tab tapped again meanwhile
// FIX99: tabs shown since launch; a first visit (WeChat loads the page then,
// 0.3-1.3 s of main thread on the tester's phone) waits for the lens to be
// down whatever the moment chosen, so the lens never freezes mid-way.
@property(nonatomic,strong) NSMutableIndexSet *visitedTabs;
@property(nonatomic) NSInteger pendingMoment;
@property(nonatomic) NSUInteger firstVisitLogs;
@property(nonatomic) NSUInteger touchDownSwitches;   // FIX100: switches made at a touch-down (按下时)
@property(nonatomic) NSUInteger landedSwitches;
@property(nonatomic) CFTimeInterval pendingTabSince,lastSwitchAt,profileUntil,profileStart;
@property(nonatomic) BOOL profileActive;
@property(nonatomic) NSUInteger profileWindows,profileFrames,profileSlowFrames;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *profileWorst;
@property(nonatomic,strong) NSHashTable *pullCensusScrolls;
@property(nonatomic) NSUInteger transitionSerial,transitionCancellations,transitionCompletions;
@property(nonatomic) CFTimeInterval transitionBegan;
@property(nonatomic) NSUInteger transitionSamplingSkips,navigationSetupDeferrals;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *transitionLog;
@property(nonatomic) BOOL navigationDirty;
@property(nonatomic) BOOL navigationBindingPending,hasBeenActive;
@property(nonatomic,copy) NSString *navigationBindingKey;
@property(nonatomic) CFTimeInterval lastBindingRepair;
@property(nonatomic) NSUInteger bindingRecoveries,samplingLayoutSkips;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *navigationRequests;
@property(nonatomic,strong) NSHashTable<UIView *> *homeGestureHosts,*navigationChromeHosts;
@property(nonatomic) NSUInteger navigationRepairs,homeReattachments;
@property(nonatomic,weak) UIViewController *dockPrimaryOwner;
@property(nonatomic,weak) UITabBar *suppressedTabBar;
@property(nonatomic) WXGDockPresentation dockPresentation;
@property(nonatomic) BOOL dockTransitionFromRoot,dockTransitionToRoot;
@property(nonatomic) BOOL clearingNavigationChrome;
@property(nonatomic) NSUInteger scopedChromeRepairs,ignoredHomeHosts;
@property(nonatomic,strong) WXGPageState *activePage;
@property(nonatomic,strong) NSHashTable<WXGPageState *> *pages;
@property(nonatomic,weak) UIViewController *pendingController;
@property(nonatomic) BOOL needsEarlyLayout;
@property(nonatomic) NSUInteger pageRestores;
@property(nonatomic) CFTimeInterval lastPrime;
@property(nonatomic,strong) NSMutableArray<WXGSurface *> *buttons;
@property(nonatomic,strong) NSMutableDictionary<NSString *,WXGSurface *> *surfacePool;
@property(nonatomic,strong) NSHashTable<UIScrollView *> *scrollViews;
@property(nonatomic,strong) NSMapTable<UIScrollView *,NSValue *> *scrollOffsets;
@property(nonatomic) CFTimeInterval lastRefresh,lastFrame,frameStart;
@property(nonatomic) NSUInteger frames,slowFrames,refreshes;
@property(nonatomic) NSUInteger coveredRenderFrames;
@property(nonatomic) WXGInputRepairGate inputRepairGate;
@property(nonatomic) BOOL inputRepairsSuspended;
@property(nonatomic) NSUInteger inputRepairRequests,inputRepairPasses,inputRepairDeferrals,inputInactiveSkips;
@property(nonatomic) CFTimeInterval inputRepairMS,maxInputRepairMS;
@property(nonatomic,strong) NSArray<UIView *> *pageViews;
@property(nonatomic) CFTimeInterval lastTreeScan,lastPaintScan;
@property(nonatomic,copy) NSString *dockStyleKey;
@property(nonatomic,strong) WXGDemoBar *dockView;
// FIX60: the dock's search button. The dock and the button live in one row
// (lifted above the keyboard while searching); one spring drives the morph.
@property(nonatomic,strong) WXGOverlay *dockRow;
@property(nonatomic,strong) WXGDockSearch *searchView;
@property(nonatomic) BOOL searchOpen,searchLeading,searchEntryTriggered,searchSwitchRequested,nativeSearchEditing;
@property(nonatomic) double searchT,searchV;
@property(nonatomic) CFTimeInterval searchLastTick,pendingSearchSince;
@property(nonatomic) CGRect dockRowRect,dockOpenRect;
@property(nonatomic) CGFloat searchGap,keyboardTop,keyboardLift;
@property(nonatomic) CGFloat homePanel;   // FIX67: mini-program panel progress, 0 .. 1
@property(nonatomic,weak) UIControl *homeSearchControl;
@property(nonatomic,weak) UISearchBar *homeSearchBarRef;
@property(nonatomic,weak) UITextField *handoffField;
@property(nonatomic,weak) UIResponder *handoffResponder;
@property(nonatomic) CFTimeInterval handoffResponderSince;
@property(nonatomic) NSUInteger deliveryAttempts;
@property(nonatomic,weak) UIView *homeSearchBarScanPage;
@property(nonatomic,copy) NSString *pendingSearchText,*searchEntry,*lastSearchHandoff,*topSearchStatus;
@property(nonatomic) NSUInteger searchOpens,searchHandoffs,searchHandoffMisses,topSearchHides;
@property(nonatomic,weak) UIView *topSearchHeader;
@property(nonatomic,weak) UITableView *topSearchTable;
@property(nonatomic) CGFloat topSearchHeight;
@property(nonatomic) BOOL topSearchClipped,topSearchHidden;
@property(nonatomic,strong) WXGInputAdapter *inputAdapter;
@property(nonatomic,strong) WXGStateBag *navStates,*dockStates;
@property(nonatomic,strong) WXGRoute *route;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,weak) UINavigationController *settings;
@property(nonatomic,strong) UIButton *launcher;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,strong) WXGHostTickProxy *proxy;
@property(nonatomic) BOOL started,queued,refreshing,preserveDockDuringReset,suspendedByCover;
@property(nonatomic) UIUserInterfaceStyle appearanceStyle;
@property(nonatomic,weak) id<UIViewControllerTransitionCoordinator> waitingTransition;
@property(nonatomic) CFTimeInterval lastParameters;
@property(nonatomic,copy) NSString *routeToken,*status,*avatarStatus;
// FIX88: the chat's avatar for the title's avatar mode (per page state in
// WXGAvatarState, associated with the page).
@property(nonatomic,weak) UIViewController *avatarLookupPage;
@property(nonatomic) NSUInteger avatarLookups;
@property(nonatomic,copy) NSString *avatarSource;
// FIX95: what the avatar lookup saw (diagnostics) and the photo downloads.
@property(nonatomic,copy) NSDictionary *avatarProbe;
@property(nonatomic,copy) NSString *avatarDownloadStatus;
@property(nonatomic) NSUInteger avatarDownloads,avatarDiskHits;   // FIX100: photos shown from the disk cache
@property(nonatomic) BOOL avatarRetryPending;
@property(nonatomic,strong) UILongPressGestureRecognizer *dockLongPress;   // FIX89: the settings fallback
// FIX92: the title bar's glass kept above the page (keepNavigationOnTop).
@property(nonatomic) NSUInteger navigationRaises,navigationCovers;
@property(nonatomic,copy) NSString *lastNavigationCover;
@property(nonatomic,strong) NSHashTable *navigationCoverSeen;   // FIX93: each cover logged once
// FIX93: the home list pulled down past its top (pt), and a trace of the title
// bar while it is (diagnostics: what WeChat does to its own title bar).
@property(nonatomic) CGFloat homePull;
@property(nonatomic) CFTimeInterval homePullTraceAt,homePullTraceStart;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *homePullTrace;
@property(nonatomic,copy) NSArray *homePullHosts;
@property(nonatomic) NSUInteger homePullFades;
@property(nonatomic) BOOL homeTopBarInList;   // FIX94: last seen (the edge fade is told when it changes)
@property(nonatomic) NSUInteger homeTopBarMoves;
@property(nonatomic,weak) UIView *homeTopBarList;
@property(nonatomic,weak) UIViewController *homeTopBarPage;
@property(nonatomic) CFTimeInterval homeTopBarPulledAt;
@property(nonatomic) BOOL homeTopBarAtRest;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *paintEvidence;
@property(nonatomic,strong) NSDictionary *lastSceneEvidence;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *sceneHistory;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *actionHistory;
@property(nonatomic) CFTimeInterval lastEvidence;
@property(nonatomic) CFTimeInterval lastChromeEvidence;
@property(nonatomic,strong) NSArray *chromeEvidence;
- (void)refresh;
- (void)tick:(CADisplayLink *)link;
- (void)flushPendingFrame:(BOOL)fallback;
- (void)dropPendingFrame;
- (void)finishTabTrace;
- (void)scheduleTopPaintCensus;
- (void)captureTopPaintCensus:(NSString *)label;
- (void)concealTransitionSnapshots;
- (void)clearPageTopPaint:(UIView *)page;
- (void)prewarmTabPagesFrom:(NSUInteger)index;
- (void)matchPageAppearance:(WXGRoute *)r;
- (void)probeDockRenderState:(NSUInteger)step;
- (void)forwardTabIndex:(NSInteger)index;
- (void)firePendingTabIfReady;
- (BOOL)dockRequestedTabAtTouchDown:(NSInteger)index;   // FIX100
- (void)profileFrame:(CADisplayLink *)link now:(CFTimeInterval)now;
- (void)beginRootReturnTo:(UIViewController *)root source:(NSString *)source;
- (void)capturePaintCensus:(NSString *)label bottom:(BOOL)bottom;
- (void)capturePullDownCensus;
- (void)flushInputRepair;
- (NSDictionary *)inputRepairMetrics;
- (NSArray *)navigationChromeMetrics;
- (BOOL)isDockRoot:(UIViewController *)controller;
- (void)applyDockPresentation:(WXGDockPresentation)presentation;
@end
// FIX62: whatever is first responder (a text field, or a web page's input:
// WeChat's search page focuses neither a UITextField nor a UITextView).
// An action sent to nil goes to the first responder.
static __weak UIResponder *WXGCapturedResponder;
@interface UIResponder (WXGFirstResponder)
- (void)wxg_captureFirstResponder:(id)sender;
@end
@implementation UIResponder (WXGFirstResponder)
- (void)wxg_captureFirstResponder:(id)sender {(void)sender;WXGCapturedResponder=self;}
@end
static UIResponder *WXGFirstResponder(void) {
    WXGCapturedResponder=nil;
    [UIApplication.sharedApplication sendAction:@selector(wxg_captureFirstResponder:) to:nil from:nil forEvent:nil];
    UIResponder *responder=WXGCapturedResponder;WXGCapturedResponder=nil;
    return responder;
}
@implementation WXGHostTickProxy
- (void)tick:(CADisplayLink *)link {[self.owner tick:link];}
@end
@implementation WXGIntegrationHost
+ (instancetype)shared {static WXGIntegrationHost *h;static dispatch_once_t once;dispatch_once(&once,^{h=[self new];});return h;}
- (void)start {
    if(_started)return;_started=YES;_pendingTabIndex=-1;WXGInstallIdleClock();
    WXGLicenseSetQuietCheck(WXGHostQuietForLicense);   // FIX102
    __weak WXGIntegrationHost *probeSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[probeSelf probeDockRenderState:0];});_buttons=[NSMutableArray array];_inputAdapter=[WXGInputAdapter new];_surfacePool=[NSMutableDictionary dictionary];_pages=[NSHashTable weakObjectsHashTable];_scrollViews=[NSHashTable weakObjectsHashTable];_scrollOffsets=[NSMapTable weakToStrongObjectsMapTable];_paintEvidence=[NSMutableArray array];_sceneHistory=[NSMutableArray array];_actionHistory=[NSMutableArray array];_transitionLog=[NSMutableArray array];_navigationDirty=YES;
    _hasBeenActive=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    _navigationRequests=[NSMutableArray array];
    // Warm the usual slots once; no page or controller is retained by a slot.
    for(NSString *slot in @[@"left0",@"left1",@"right0",@"right1",@"chatTitle",@"avatar"])
        _surfacePool[slot]=[WXGSurface new];
    NSNotificationCenter *n=NSNotificationCenter.defaultCenter;
    for(NSString *name in @[UIApplicationDidBecomeActiveNotification,UIApplicationWillResignActiveNotification,
                            UIWindowDidBecomeKeyNotification,UIWindowDidBecomeVisibleNotification,
                            UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification,
                            UIKeyboardDidHideNotification,UITextViewTextDidChangeNotification,UIApplicationDidReceiveMemoryWarningNotification,WXGSettingsChanged,@"WXGIntegrationChanged"])
        [n addObserver:self selector:@selector(changed:) name:name object:nil];
    // FIX60: the dock search follows the keyboard and hands its text to
    // WeChat's own search field when that field starts editing.
    [n addObserver:self selector:@selector(dockSearchKeyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [n addObserver:self selector:@selector(textFieldBegan:) name:UITextFieldTextDidBeginEditingNotification object:nil];
    [n addObserver:self selector:@selector(textFieldEnded:) name:UITextFieldTextDidEndEditingNotification object:nil];
    _homeGestureHosts=[NSHashTable weakObjectsHashTable];_navigationChromeHosts=[NSHashTable weakObjectsHashTable];
    _timer=[NSTimer timerWithTimeInterval:.75 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    _proxy=[WXGHostTickProxy new];_proxy.owner=self;
    _displayLink=[CADisplayLink displayLinkWithTarget:_proxy selector:@selector(tick:)];WXGConfigureDisplayLink(_displayLink,UIScreen.mainScreen);_displayLink.paused=YES;
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    // FIX19: run just BEFORE Core Animation commits (order 2000000) and after
    // UIKit's before-commit handler (1999000). The model tree then holds this
    // display frame's final state, and the glass drawables are presented in
    // the same transaction, so WeChat's frame and the glass reach the screen
    // together. (FIX16-18 ran after the commit: a frame later.) Animations
    // added in this pass are not committed yet; the sampler detects and holds
    // those frames instead of reading their end state.
    __weak WXGIntegrationHost *weakHost=self;
    _commitObserver=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,true,1999500,
        ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){[weakHost flushPendingFrame:NO];});
    if(_commitObserver)CFRunLoopAddObserver(CFRunLoopGetMain(),_commitObserver,kCFRunLoopCommonModes);
    // FIX101: how long Core Animation's own commit (order 2000000) takes: the
    // layout and drawing of everything on screen, WeChat's pages included.
    static CFTimeInterval commitStart;
    CFRunLoopObserverRef beforeCommit=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,true,1999999,
        ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){commitStart=CACurrentMediaTime();});
    CFRunLoopObserverRef afterCommit=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,true,2000001,
        ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){
            if(commitStart>0){WXGProfileTotals[WXGProfileCommit]+=(CACurrentMediaTime()-commitStart)*1000;commitStart=0;}
        });
    if(beforeCommit){CFRunLoopAddObserver(CFRunLoopGetMain(),beforeCommit,kCFRunLoopCommonModes);CFRelease(beforeCommit);}
    if(afterCommit){CFRunLoopAddObserver(CFRunLoopGetMain(),afterCommit,kCFRunLoopCommonModes);CFRelease(afterCommit);}
    WXGLog(@"WeChat Liquid Glass 0.4.105 TEST4 FIX105 启动；%@；iOS %@",NSBundle.mainBundle.bundleIdentifier,UIDevice.currentDevice.systemVersion);
    [self schedule];
}
- (void)changed:(NSNotification *)n {
    if([n.name isEqual:UIApplicationDidReceiveMemoryWarningNotification]) {
        for(WXGPageState *page in _pages) {
            for(WXGSurface *surface in page.pool.allValues)[surface.glass releaseTransientResources];
            for(WXGSurface *surface in page.input.surfaces)[surface.glass releaseTransientResources];
        }
        for(WXGGlassView *glass in _dockView.allGlasses)[glass releaseTransientResources];   // 离散底栏: the pieces too
        WXGInvalidateSharedBackdrop();return;
    }
    if([n.name isEqual:UITextViewTextDidChangeNotification])[self layoutInput];
    if([n.name isEqual:WXGSettingsChanged])[WXGConfig.shared reloadSharedParameters];
    if([n.name isEqual:WXGSettingsChanged] || [n.name isEqual:@"WXGIntegrationChanged"]) {
        _dockStyleKey=nil;_navigationDirty=YES;
        [WXGDecorations.shared applyConfiguration];
        [WXGBubbles.shared applyConfiguration];   // FIX82
        for(WXGPageState *page in _pages) {
            if(!WXGPluginEnabled() || !WXGPreferences.shared.input)[page.input restore];
            for(WXGSurface *surface in page.pool.allValues)[surface applyConfig];
            for(WXGSurface *surface in page.input.surfaces)[surface applyConfig];
        }
    }
    if([n.name isEqual:UIApplicationWillResignActiveNotification]) {
        // Keep TEST4's mount, native suppression and last drawable during system interruptions.
        _inputRepairsSuspended=YES;_displayLink.paused=YES;_lastFrame=0;return;
    }
    if([n.name isEqual:UIApplicationDidBecomeActiveNotification]){_inputRepairsSuspended=NO;_hasBeenActive=YES;_lastFrame=0;[self refresh];return;}
    if(!_hasBeenActive && ([n.name isEqual:UIWindowDidBecomeVisibleNotification] || [n.name isEqual:UIWindowDidBecomeKeyNotification])) {
        [self refresh];return;
    }
    [self schedule];
}
- (void)poll:(NSTimer *)timer {(void)timer;[self schedule];}
- (void)schedule {
    if(!_started || _queued || _refreshing)return;_queued=YES;
    // Coalesce in this run-loop turn, without a fixed 80 ms presentation delay.
    dispatch_async(dispatch_get_main_queue(),^{self.queued=NO;[self refresh];});
}
- (UIWindow *)contentWindow {
    NSMutableOrderedSet *windows=[NSMutableOrderedSet orderedSet];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive)
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
    UIWindow *best=nil;NSInteger score=-1;
    for(UIWindow *w in windows) {
        NSString *name=NSStringFromClass(w.class);
        if(w.hidden || w.alpha<.01 || !w.rootViewController || w.bounds.size.width<250 || w.windowLevel!=UIWindowLevelNormal ||
           [name containsString:@"Keyboard"] || [name containsString:@"TextEffects"])continue;
        WXGRoute *r=WXGRouteForWindow(w);
NSInteger s=(r.tabs?100:0)+(w.isKeyWindow?10:0)+(w==_window?5:0);
        if(s>score){best=w;score=s;}
    }return best;
}
// FIX41: the glass follows the appearance of the page it is drawn over. The
// overlay hangs under WeChat's root view, which at launch still reports the
// system style (dark at night) while WeChat already shows its pages light;
// with a dark material at 0 opacity the dock was fully transparent until
// WeChat applied its setting further up. Surfaces with their own override
// (video pages) keep it.
// FIX42: what the dock actually is on screen during cold start, every 0.2 s
// from 1 s to 12 s after load (logged only when it changes).
- (void)probeDockRenderState:(NSUInteger)step {
    if(CACurrentMediaTime()-WXGLoadTime>12 || step>80)return;
    UITabBar *native=_route.tabs.tabBar;
    NSString *line=[NSString stringWithFormat:@"渲染状态 呈现%ld | 原生底栏 隐%d 透%.2f | %@",(long)_dockPresentation,native?native.hidden:-1,native?native.alpha:-1,
        _dockView?_dockView.renderState:@"尚无底栏"];
    if(![line isEqual:_lastDockProbe]){_lastDockProbe=line;WXGColdLog(line);}
    __weak WXGIntegrationHost *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf probeDockRenderState:step+1];});
}
- (void)matchPageAppearance:(WXGRoute *)r {
    if(!_overlay)return;
    UIUserInterfaceStyle style=r.leaf.isViewLoaded?r.leaf.view.traitCollection.userInterfaceStyle:UIUserInterfaceStyleUnspecified;
    if(style==UIUserInterfaceStyleUnspecified && r.nav.isViewLoaded)style=r.nav.view.traitCollection.userInterfaceStyle;
    if(style==UIUserInterfaceStyleUnspecified || _overlay.overrideUserInterfaceStyle==style)return;
    WXGColdLog([NSString stringWithFormat:@"外观跟随页面：%@ → %@（窗口 %@）",
        _overlay.overrideUserInterfaceStyle==UIUserInterfaceStyleDark?@"深色":_overlay.overrideUserInterfaceStyle==UIUserInterfaceStyleLight?@"浅色":@"未指定",
        style==UIUserInterfaceStyleDark?@"深色":@"浅色",_window.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?@"深色":@"浅色"]);
    _overlay.overrideUserInterfaceStyle=style;++_appearanceMatches;
}
- (void)ensureOverlay:(UIWindow *)w {
    if(!_overlay){_overlay=[WXGOverlay new];_overlay.backgroundColor=UIColor.clearColor;_overlay.opaque=NO;}
    UIView *owner=w.rootViewController.view;
    if(_overlay.superview!=owner){[_overlay removeFromSuperview];[owner addSubview:_overlay];}
    CGRect frame=[w convertRect:w.bounds toView:owner];
    if(!CGRectEqualToRect(_overlay.frame,frame))_overlay.frame=frame;
    _overlay.hidden=NO;if(owner.subviews.lastObject!=_overlay)[owner bringSubviewToFront:_overlay];
    UIView *navOwner=_route.nav.view;
    if(!_navigationOverlay) {
        _navigationOverlay=[WXGOverlay new];_navigationOverlay.backgroundColor=UIColor.clearColor;
        // FIX92: drawn above every sibling, whatever their order (WeChat's
        // mini-program panel puts views above it for a moment).
        _navigationOverlay.layer.zPosition=10000;
    }
    if(navOwner && _navigationOverlay.superview!=navOwner){[_navigationOverlay removeFromSuperview];[navOwner addSubview:_navigationOverlay];}
    if(navOwner){_navigationOverlay.frame=[w convertRect:w.bounds toView:navOwner];[navOwner bringSubviewToFront:_navigationOverlay];}
    _navigationOverlay.userInteractionEnabled=_nativeTransition==nil;
    if(!_launcher) {
        _launcher=[UIButton buttonWithType:UIButtonTypeSystem];[_launcher setTitle:@"WG" forState:UIControlStateNormal];
        _launcher.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightBold];
        _launcher.backgroundColor=[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.9];
        _launcher.layer.cornerRadius=13;_launcher.accessibilityLabel=@"微信玻璃测试版设置";
        [_launcher addTarget:self action:@selector(presentSettings) forControlEvents:UIControlEventTouchUpInside];
        [_overlay addSubview:_launcher];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(moveEntry:)];[_launcher addGestureRecognizer:pan];
    }
    if(CGRectIsEmpty(_launcher.frame))_launcher.frame=CGRectMake(w.bounds.size.width-34,w.safeAreaInsets.top+86,26,26);
    // FIX30: the entry is a row in WeChat's Settings; the floating button
    // remains only if that API is missing (long-press on the dock also opens).
    // FIX105: and only for a licensed account — an unlicensed one must leave no
    // trace, so the floating entry never shows there even if the Settings-row
    // hook failed (it reappears once authorized; settings is still reachable by
    // a long press on the dock, which only exists when licensed anyway).
    _launcher.hidden=WXGSettingsEntryReady || WXGLicenseCurrentState(NO)!=WXGLicenseAuthorized;[_overlay bringSubviewToFront:_launcher];
}
// FIX105: take every plugin layer out of WeChat's view tree (not just hide its
// effects) for an unlicensed account, so nothing of the plugin is present.
// ensureOverlay puts them back when the account becomes authorized.
- (void)detachOverlays {
    if(_overlay.superview)[_overlay removeFromSuperview];
    if(_navigationOverlay.superview)[_navigationOverlay removeFromSuperview];
    _launcher.hidden=YES;
}
- (void)moveEntry:(UIPanGestureRecognizer *)pan {
    CGPoint p=[pan locationInView:_overlay];
    _launcher.center=CGPointMake(WXGClamp(p.x,14,_overlay.bounds.size.width-14),WXGClamp(p.y,_window.safeAreaInsets.top+14,_overlay.bounds.size.height-_window.safeAreaInsets.bottom-14));
}
- (void)resetRoute {
    if(!_routeToken && !_buttons.count && !_inputAdapter.installed && !_dockView.active && !_navStates && !_dockStates)return;
    for(WXGSurface *b in _buttons){b.active=NO;b.original=nil;b.motionHost=nil;b.followsNative=NO;WXGResetOwnedTransform(b);b.alpha=1;b.perform=nil;b.glass.backdropExclusions=@[];b.hidden=YES;}[_buttons removeAllObjects];
    if(!_preserveDockDuringReset)[self applyDockPresentation:WXGDockHidden];
    // Do not expose native tab artwork to UIKit's transition snapshot between
    // pushes/pops. Its native alpha is restored only when replacement is off.
    if(!WXGPluginEnabled() || !WXGPreferences.shared.dock){WXGRestoreDockTouchDelegates(_suppressedTabBar);[_dockStates restore];_dockStates=nil;_suppressedTabBar=nil;
        [_snapshotStates restore];_snapshotStates=nil;}
    [_inputAdapter setSuspended:YES];[_navStates restore];_navStates=nil;_routeToken=nil;
    [_paintEvidence removeAllObjects];_pageViews=nil;_lastTreeScan=_lastPaintScan=0;WXGInvalidateSharedBackdrop();
}
- (void)selectPage:(UIViewController *)controller {
    WXGPageState *page=objc_getAssociatedObject(controller,&WXGPageStateKey);
    if(!page) {
        page=[WXGPageState new];
        page.pool=_activePage?[NSMutableDictionary dictionary]:_surfacePool;
        page.input=_activePage?[WXGInputAdapter new]:_inputAdapter;
        objc_setAssociatedObject(controller,&WXGPageStateKey,page,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[_pages addObject:page];
    }else if(_activePage!=page)++_pageRestores;
    _activePage=page;_surfacePool=page.pool;_inputAdapter=page.input;
}
- (void)prepareController:(UIViewController *)controller {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if([NSStringFromClass(controller.class) hasPrefix:@"WXG"] || !controller.navigationController ||
       ![controller.navigationController.viewControllers containsObject:controller])return;
    // FIX38: only an appearance with a transition is "pending". A tab switch or
    // the first appearance at launch has none, and nothing ever cleared it:
    // every later navigation layout was deferred to the asynchronous refresh,
    // one frame or more after WeChat's own top buttons were on screen.
    if(controller.transitionCoordinator){_pendingController=controller;_needsEarlyLayout=YES;}
    _navigationDirty=YES;++_appearances;
    // UIKit owns the from/to route, including cancellation. Never override it
    // using a child controller that happened to receive viewWillAppear.
    [self observeTransition:controller.transitionCoordinator];
    if(controller.isViewLoaded && controller.view.window)[self schedule];
}
- (void)controllerLaidOut:(UIViewController *)controller {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(_needsEarlyLayout && controller==_pendingController && controller.view.window && !_refreshing){
        _needsEarlyLayout=NO;[self schedule];
    }
}
- (void)nativeNavigationLaidOut {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    _navigationDirty=YES;[_dockStates reapply];[_navStates reapply];
    if(_refreshing)return;
    if(WXGNavigationCallDepth || _pendingController || _nativeTransition || _route.nav.transitionCoordinator.isAnimated) {
        ++_navigationSetupDeferrals;
        if(CACurrentMediaTime()-WXGLoadTime<30)WXGColdLog([NSString stringWithFormat:@"导航布局推迟：%@",
            WXGNavigationCallDepth?@"导航调用中":_pendingController?@"页面待出现":_nativeTransition?@"转场中":@"转场动画"]);
        [self schedule];return;
    }
    // Apply after the native layout, before this transaction is presented.
    // Queuing every repair left one original back/count frame on iOS 15.
    if(_window && _route.leaf && !_pendingController && !_nativeTransition &&
       WXGPluginEnabled() && WXGPreferences.shared.nav && !_route.unsupported && !_suspendedByCover) {
        _refreshing=YES;
        @try {[self buildNavigation];_navigationDirty=NO;}
        @catch(NSException *error){WXGLog(@"导航同步修复：%@",error.reason);_navigationDirty=YES;}
        @finally {_refreshing=NO;}
    }else [self schedule];
}
- (void)navigationChromeLaidOut:(UIView *)view {
    if(view)[_navigationChromeHosts addObject:view];
    if(WXGBackdropCaptureInProgress() || _clearingNavigationChrome || !view.window ||
       !WXGPluginEnabled() || !WXGPreferences.shared.nav || _suspendedByCover)return;
    NSString *name=NSStringFromClass(view.class);
    // _UIBarBackground contains paint only; suppress the host itself so later
    // effect/image descendants cannot repaint it after their layout callbacks.
    // This cheap early path also works before the first route is prepared.
    UIView *earlyBar=view.superview;
    while(earlyBar && ![earlyBar isKindOfClass:UINavigationBar.class])earlyBar=earlyBar.superview;
    BOOL nativeEarly=[name isEqual:@"_UIBarBackground"] && [NSStringFromClass(earlyBar.class) isEqual:@"MMUINavigationBar"];
    if(nativeEarly && (!_window || view.window==_window) && (!_route.nav || earlyBar==_route.nav.navigationBar) && !_route.unsupported) {
        if(!_navStates)_navStates=[WXGStateBag new];
        [_navStates conceal:view];++_scopedChromeRepairs;
        if(!_window)[self schedule];return;
    }
    if(!_window){[self schedule];return;}
    if(view.window!=_window || _route.unsupported)return;
    if(WXGNavigationCallDepth || _pendingController || _nativeTransition) {
        _navigationDirty=YES;++_navigationSetupDeferrals;[self schedule];return;
    }
    BOOL system=[name isEqual:@"_UIBarBackground"] && [view isDescendantOfView:_route.nav.navigationBar];
    BOOL fake=[name isEqual:@"FakeNavigationBar"] && [view isDescendantOfView:_route.nav.view];
    CGRect r=WXGWindowRect(view,_window);
    if(!system && !(fake && r.size.width>_window.bounds.size.width*.65 &&
        r.origin.y<_window.safeAreaInsets.top+60 && r.size.height<220))return;
    if(!_navStates)_navStates=[WXGStateBag new];
    _clearingNavigationChrome=YES;
    @try {
        if(system){[_navStates conceal:view];++_scopedChromeRepairs;return;}
        // Only the just-laid-out native chrome subtree is reconsidered. The
        // existing StateBag keeps controls/labels/gesture content intact.
        [UIView performWithoutAnimation:^{
            [CATransaction begin];[CATransaction setDisableActions:YES];
            [self.navStates stripChrome:view preserving:@[]];
            [CATransaction commit];
        }];
        ++_scopedChromeRepairs;
    }@finally {_clearingNavigationChrome=NO;}
}
- (void)navigationControlLaidOut:(UIView *)view {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(WXGNavigationCallDepth){[_navStates reapply];_navigationBindingPending=YES;return;}
    if(!WXGPluginEnabled() || !WXGPreferences.shared.nav)return;
    if(!_window && view.window){[self refresh];}
    if(view.window!=_window || !_window)return;
    for(WXGSurface *surface in _buttons)if(surface.original==view){[_navStates reapply];return;}
    BOOL navigation=[view isDescendantOfView:_route.nav.navigationBar];
    for(UIView *parent=view.superview;!navigation && parent;parent=parent.superview)
        navigation=[NSStringFromClass(parent.class) isEqual:@"MMNewMsgContentNavBar"];
    if(!navigation)return;
    // didMoveToWindow can arrive in the middle of buildNavigation. Keep this
    // request after that pass instead of silently dropping the replacement.
    _navigationBindingPending=YES;
    if(_refreshing)return;
    _navigationBindingPending=NO;[self nativeNavigationLaidOut];
}
- (void)repairDetachedNavigationBindings {
    if(_refreshing || _nativeTransition || !_route.leaf || _suspendedByCover ||
       !WXGPluginEnabled() || !WXGPreferences.shared.nav)return;
    BOOL missing=_navigationBindingPending || ![_navigationBindingKey isEqual:[self currentNavigationBindingKey]];
    for(WXGSurface *surface in _buttons) {
        if(surface.motionOwner!=_route.leaf || [surface.role isEqual:@"nativeGesture"])continue;
        if(surface.followsNative && surface.motionHost.window!=_window){missing=YES;break;}
    }
    if(!missing || CACurrentMediaTime()-_lastBindingRepair<1./30)return;
    _lastBindingRepair=CACurrentMediaTime();_navigationBindingPending=NO;++_bindingRecoveries;
    WXGColdLog([NSString stringWithFormat:@"导航绑定修复 #%lu（%@）",(unsigned long)_bindingRecoveries,
        ![_navigationBindingKey isEqual:[self currentNavigationBindingKey]]?@"按钮被替换":@"按钮离开窗口"]);
    [self nativeNavigationLaidOut];
}
- (NSString *)currentNavigationBindingKey {
    UINavigationItem *item=_route.leaf.navigationItem;
    NSMutableString *key=[NSMutableString stringWithFormat:@"%p/%p/%p",_route.leaf,item,_route.nav.navigationBar.topItem];
    for(UIBarButtonItem *button in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]]) {
        id value=WXGRead(button,@"view");UIView *host=button.customView?:([value isKindOfClass:UIView.class]?value:nil);
        [key appendFormat:@"/%p:%p:%p:%p:%p",button,host,host.superview,host.window,host.subviews.firstObject];
    }
    return key;
}
- (void)alignHomeGestureIcon:(UIView *)host diameter:(CGFloat)diameter {
    // The supplied probe identifies a MainFrameLeftBarView with a gesture and
    // a 24pt UIImageView whose visible glyph is 8pt left of the host center.
    // Keep its real gesture recognizer; correct only its native image geometry.
    if(![NSStringFromClass(host.class) isEqual:@"MainFrameLeftBarView"] || !_navStates)return;
    for(UIView *child in WXGViews(host,32)) {
        if(![child isKindOfClass:UIImageView.class] || !WXGVisible(child,_window))continue;
        UIImageView *image=(id)child;
        if(image.image && image.bounds.size.width>4 && image.bounds.size.width<80) {
            [_navStates adaptMonochromeImage:image];
            [_navStates centerNativeImage:image inHost:host maximumInk:MIN(26,diameter*.50)];break;
        }
    }
}
- (void)homeGestureLaidOut:(UIView *)host {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(host.window)[_homeGestureHosts addObject:host];
    if(!_window && host.window && !_refreshing)[self refresh];
    if(_refreshing || ![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] ||
       !WXGPluginEnabled() || !WXGPreferences.shared.nav)return;
    WXGSurface *bound=_surfacePool[@"nativeLeft0"];
    if(host.window!=_window || !WXGVisible(host,_window) ||
       ![host isDescendantOfView:_route.nav.view]) {
        // Hidden/off-window duplicate hosts must not steal the single glass
        // slot. A detached active host gets one native-layout repair request.
        ++_ignoredHomeHosts;
        if(bound.motionHost==host){_navigationBindingPending=YES;[self schedule];}
        return;
    }
    _refreshing=YES;
    @try {
        if(!_navStates)_navStates=[WXGStateBag new];
        WXGMetrics m=WXGMeasure(_window.bounds.size.width-_window.safeAreaInsets.left-_window.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
        CGFloat h=_route.nav.navigationBar.bounds.size.height;
        if(m.button>MAX(36,h))m=WXGMeasure(440*MAX(36,h)/44,1);
        [self bindHomeGesture:host diameter:m.button slot:@"nativeLeft0"];
    } @catch(NSException *error){WXGLog(@"首页手势挂载：%@",error.reason);_navigationDirty=YES;}
    @finally {_refreshing=NO;}
}
- (WXGSurface *)bindHomeGesture:(UIView *)host diameter:(CGFloat)diameter slot:(NSString *)slot {
    if(!host.superview || host.window!=_window)return nil;
    WXGSurface *surface=[self pooledSurface:slot];
    if(surface.superview!=host || surface.motionHost!=host)++_homeReattachments;
    surface.role=@"nativeGesture";surface.motionHost=host;
    surface.motionOwner=_route.leaf;surface.followsNative=NO;surface.materialOnly=YES;[surface setImage:nil title:nil count:nil];
    surface.glass.sourceView=_route.leaf.view;
    surface.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,host,_route.nav.navigationBar]:@[host,_route.nav.navigationBar];
    CGRect material=CGRectMake(CGRectGetMidX(host.bounds)-diameter*.5,CGRectGetMidY(host.bounds)-diameter*.5,diameter,diameter);
    [_navStates allowOverflow:host];[self alignHomeGestureIcon:host diameter:diameter];
    [surface placeMaterial:material inParent:host];
    if(host.subviews.firstObject!=surface)[host insertSubview:surface atIndex:0];
    [surface observeTouchesInView:host];   // FIX70: the button's own view takes the touches
    surface.hidden=NO;surface.alpha=1;return surface;
}
- (void)followHomeSurfaces {
    if(![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"])return;
    for(WXGSurface *surface in _buttons) {
        UIView *native=[surface.role isEqual:@"nativeGesture"]?surface.motionHost:surface.original;
        if(!native || native.window!=_window)continue;
        if([surface.role isEqual:@"nativeGesture"]) {
            // Geometry and alpha now inherit from the actual native host. Only
            // a genuine rehome requires reattachment, not every display frame.
            if(surface.superview!=native)[self bindHomeGesture:native diameter:surface.materialRect.size.height slot:@"nativeLeft0"];
        }else if(surface.original && surface.superview.window==_window) {
            // Preserve TEST4's corrected x grid and raster-centered icon, follow native y.
            CGRect r=WXGWindowRect(native,_window);
            CGPoint center=[_window convertPoint:CGPointMake(0,CGRectGetMidY(r)) toView:surface.superview];
            CGRect frame=surface.followsNative?surface.restingFrame:surface.frame;
            frame.origin.y=center.y-frame.size.height*.5;
            [CATransaction begin];[CATransaction setDisableActions:YES];
            if(surface.followsNative)WXGResetOwnedTransform(surface);
            if(!CGRectEqualToRect(frame,surface.frame))surface.frame=frame;
            if(surface.followsNative)surface.restingFrame=frame;
            [CATransaction commit];
        }
    }
}
- (void)primeNewSurfaces {
    CFTimeInterval now=CACurrentMediaTime();if(now-_lastPrime<1./WXGScreenCaptureFPS(_window.screen))return;
    NSMutableArray *all=[NSMutableArray array];
    for(WXGSurface *surface in _buttons)if(surface.active && !surface.plain)[all addObject:surface.glass];
    for(WXGSurface *surface in _inputAdapter.surfaces)if(surface.active && !surface.plain)[all addObject:surface.glass];
    for(WXGSurface *surface in [WXGDecorations.shared visibleSurfaces])[all addObject:surface.glass];
    if(_dockView.active)[all addObjectsFromArray:_dockView.renderGlasses];   // 离散底栏: the pieces' glass
    BOOL cold=NO;for(WXGGlassView *glass in all){[glass layoutIfNeeded];if(glass.ready && !glass.hasPresentedFrame)cold=YES;}
    // Prewarm geometry/Metal only. Native layout and tab target/action callbacks
    // must not synchronously rasterize a newly constructed page's entire tree.
    // The display-link owns the single shared capture after the native commit.
    if(cold){_lastPrime=now;for(WXGGlassView *glass in all)if(!glass.hasPresentedFrame)[glass preparePresentation];}
}
- (void)recordPaint:(UIView *)v bag:(WXGStateBag *)bag hidden:(BOOL)hidden {
    if(!v)return;WXGViewState *before=[bag remember:v];
    if(hidden)[bag hide:v];else[bag clear:v];
    /* Evidence records classes, geometry and original/suppressed paint state;
       no chat strings, titles or identifiers are written. */
    BOOL known=NO;for(NSDictionary *p in _paintEvidence)if([p[@"pointer"] isEqual:[NSString stringWithFormat:@"%p",v]]){known=YES;break;}
    if(!known && _paintEvidence.count<100) {
        CGRect r=WXGWindowRect(v,_window);
        [_paintEvidence addObject:@{@"class":NSStringFromClass(v.class),@"pointer":[NSString stringWithFormat:@"%p",v],
            @"rect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],@"operation":hidden?@"alpha_zero":@"clear_color",
            @"originalAlpha":@(before.originalAlpha),@"originalHidden":@(before.originallyHidden)}];
    }
}
- (void)clearNavigationPaint {
    UINavigationBar *bar=_route.nav.navigationBar;if(!bar || !_navStates)return;
    _lastPaintScan=CACurrentMediaTime();NSMutableArray *paintHosts=[NSMutableArray array];
    // A background may have finished its first layout before our lifecycle
    // hook was installed. Discover the current bar's exact paint hosts too.
    for(UIView *view in WXGViews(bar,80))if([NSStringFromClass(view.class) isEqual:@"_UIBarBackground"]) {
        [paintHosts addObject:view];[_navigationChromeHosts addObject:view];[_navStates conceal:view];
    }
    // Keep native effect trees intact below their paint-only host mask. There
    // is no need to repeatedly set their effects to nil during a push.
    [_navStates stripChrome:bar preserving:paintHosts];
    // FakeNavigationBar may be under MMUIHookView beside the page, not inside
    // leaf.view. Its own lifecycle registers it even before our first route.
    for(UIView *chrome in _navigationChromeHosts)if(chrome.window==_window) {
        NSString *name=NSStringFromClass(chrome.class);
        if([name isEqual:@"_UIBarBackground"] && [chrome isDescendantOfView:bar])[_navStates conceal:chrome];
        else if([chrome isDescendantOfView:_route.nav.view] && [name isEqual:@"FakeNavigationBar"])
            [_navStates stripChrome:chrome preserving:@[]];
    }
    // Scope cleanup to real navigation chrome. Chat tips and Moments covers
    // remain content, even when they overlap the status/navigation area.
    // FIX60: geometry first; only views in the top band are asked for their
    // class name (a Swift class's first name request demangles it).
    static Class chatBarClass;static dispatch_once_t chatBarOnce;
    dispatch_once(&chatBarOnce,^{chatBarClass=NSClassFromString(@"MMNewMsgContentNavBar");});
    for(UIView *v in _pageViews?:@[]) {
        BOOL chatBar=chatBarClass && v.class==chatBarClass;
        CGRect rect=WXGWindowRect(v,_window);
        if(!chatBar && !(rect.origin.y<_window.safeAreaInsets.top+50 && rect.size.height<220))continue;
        NSString *name=chatBar?@"MMNewMsgContentNavBar":NSStringFromClass(v.class);
        BOOL customBar=[name containsString:@"NavigationBar"] || [name hasSuffix:@"NavBar"] || [name hasSuffix:@"NavBarView"];
        if(!chatBar && !customBar)continue;
        NSMutableArray *protected=[NSMutableArray array];
        for(UIView *child in WXGViews(v,100)) {
            NSString *n=NSStringFromClass(child.class);
            if([n containsString:@"Tips"] || [n containsString:@"Banner"] || [n containsString:@"Cover"])[protected addObject:child];
        }
        for(NSString *key in @[@"blurBgView",@"backgroundView",@"_backgroundView",@"shadowView",@"separatorView"]) {
            id bg=WXGRead(v,key);
            if([bg isKindOfClass:UIView.class] && bg!=v && [bg isDescendantOfView:v])[_navStates stripChrome:bg preserving:protected];
        }
        [_navStates stripChrome:v preserving:protected];
    }
    // FIX27: during cold start (收取中…) WeChat lays a plain, opaque, full-size
    // UIView inside MainFrameTableView (white, or dark in dark mode). It shows
    // above the search bar until WeChat removes it about 10 s later or on a
    // scroll; the page behind it is the normal grey. Clear its paint only.
    for(UIView *v in _pageViews?:@[]) {
        static Class listClass;static dispatch_once_t listOnce;
        dispatch_once(&listOnce,^{listClass=NSClassFromString(@"MainFrameTableView");});
        if(!listClass || v.class!=listClass)continue;   // FIX60: by class, not by name
        for(UIView *child in v.subviews) {
            if(child.class!=UIView.class || child.subviews.count>2)continue;
            CGFloat alpha=child.backgroundColor?CGColorGetAlpha(child.backgroundColor.CGColor):0;
            if(alpha<.99 || child.bounds.size.width<v.bounds.size.width-1 || child.bounds.size.height<v.bounds.size.height*.9)continue;
            // Own bag, never restored on route changes: WeChat removes the
            // layer itself, so bringing it back during a pop would only flash.
            if(!_coldStartStates)_coldStartStates=[WXGStateBag new];
            [_coldStartStates clear:child];++_coldStartLayersCleared;
        }
    }
    [self clearPageTopPaint:_route.leaf.isViewLoaded?_route.leaf.view:nil];
    [_navStates reapply];
}
// FIX29: WeChat paints the nav-area background with views inside the PAGE,
// not the navigation bar: an opaque white (chat settings) or grey (services)
// UIView, or a blur view (Moments), exactly 0..navBottom at the top and full
// width, plus a hairline at navBottom. Captured in the FIX27/28 settled-page
// census; the nav-bar cleanup never saw them.
// FIX30: breadth-first walk that only enters branches reaching the given
// horizontal band of the window (top nav area, bottom bar area) and never
// descends into cells. The page content far from the band is never visited.
static NSArray<UIView *> *WXGViewsInBand(UIView *root,UIWindow *w,CGFloat minY,CGFloat maxY,NSUInteger limit) {
    if(!root || !w)return @[];
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root],*out=[NSMutableArray array];
    for(NSUInteger i=0;i<queue.count && out.count<limit;i++) {
        UIView *v=queue[i];
        if(v.hidden || WXGIsPluginView(v))continue;
        CGRect r=WXGWindowRect(v,w);
        if(CGRectGetMaxY(r)<minY || CGRectGetMinY(r)>maxY)continue;
        [out addObject:v];
        if([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class])continue;
        [queue addObjectsFromArray:v.subviews];
    }
    return out;
}
// FIX47/48: two backgrounds differ visibly (resolved for the view's traits).
static BOOL WXGColorsDiffer(UIColor *a,UIColor *b,UITraitCollection *traits) {
    CGFloat r1=0,g1=0,b1=0,a1=0,r2=0,g2=0,b2=0,a2=0;
    if(![[a resolvedColorWithTraitCollection:traits] getRed:&r1 green:&g1 blue:&b1 alpha:&a1] ||
       ![[b resolvedColorWithTraitCollection:traits] getRed:&r2 green:&g2 blue:&b2 alpha:&a2])return NO;
    return fabs(r1-r2)+fabs(g1-g2)+fabs(b1-b2)>=.01;
}
- (void)clearPageTopPaint:(UIView *)page {
    UIWindow *w=_window;if(!page || !w || !_navStates || !page.window)return;
    UINavigationBar *bar=_route.nav.navigationBar;
    CGFloat navBottom=bar.window?CGRectGetMaxY(WXGWindowRect(bar,w)):w.safeAreaInsets.top+44;
    CGFloat width=w.bounds.size.width;
    for(UIView *v in WXGViewsInBand(page,w,-1,navBottom+48,500)) {
        if(v==page || v.hidden || WXGIsPluginView(v) || [v isKindOfClass:UIControl.class] ||
           [v isKindOfClass:UILabel.class] || [v isKindOfClass:UIScrollView.class])continue;
        CGRect r=WXGWindowRect(v,w);
        if(r.size.width<width-1)continue;
        BOOL hairline=r.size.height<=1.5 && fabs(CGRectGetMinY(r)-navBottom)<=2 && !v.subviews.count;
        BOOL plate=fabs(CGRectGetMinY(r))<=1 && fabs(r.size.height-navBottom)<=6;
        BOOL shade=[v isKindOfClass:UIImageView.class] && fabs(CGRectGetMinY(r))<=1 && r.size.height>navBottom+6 &&
            r.size.height<=navBottom+40 && !v.subviews.count;
        if(!hairline && !plate && !shade)continue;
        // Never anything that carries content: buttons, titles, text.
        BOOL content=NO;
        for(UIView *child in WXGViews(v,30))if(child!=v && ([child isKindOfClass:UIControl.class] || [child isKindOfClass:UILabel.class] ||
            [child isKindOfClass:UITextView.class] || WXGIsPluginView(child))){content=YES;break;}
        if(content)continue;
        if(hairline)[_navStates hide:v];
        else if([v isKindOfClass:UIVisualEffectView.class])[_navStates conceal:v];
        else if([v isKindOfClass:UIImageView.class])[_navStates clearImagePaint:(id)v];
        else if(v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor)>.01)[_navStates clear:v];
        else continue;
        ++_pageTopPaintCleared;
    }
    // FIX47: a full-screen opaque background (the page itself or one of its
    // top full-screen views) whose opaque content starts at the bar's bottom and
    // covers everything below: only its strip behind the bar is ever visible,
    // a plate in effect (Kinda wallet pages: 0.10 grey above 0.07 content).
    // Painted the content's own colour (never cleared: behind the page could be
    // black, a dark strip in light mode), only where the two differ.
    CGFloat height=w.bounds.size.height;
    NSMutableArray<UIView *> *backs=[NSMutableArray arrayWithObject:page];
    for(UIView *v in WXGViews(page,60))if(v!=page)[backs addObject:v];
    for(UIView *v in backs) {
        if(v.hidden || WXGIsPluginView(v) || [v isKindOfClass:UIScrollView.class] || [v isKindOfClass:UIControl.class])continue;
        if(!v.backgroundColor || CGColorGetAlpha(v.backgroundColor.CGColor)<.99)continue;
        CGRect r=WXGWindowRect(v,w);
        if(fabs(CGRectGetMinY(r))>1 || r.size.width<width-1 || CGRectGetMaxY(r)<height-1)continue;
        UIColor *content=nil;
        for(UIView *c in WXGViews(v,200)) {
            if(c==v || c.hidden || !c.backgroundColor || CGColorGetAlpha(c.backgroundColor.CGColor)<.99)continue;
            CGRect cr=WXGWindowRect(c,w);
            if(cr.size.width>=width-1 && fabs(CGRectGetMinY(cr)-navBottom)<=3 && CGRectGetMaxY(cr)>=height-1){content=c.backgroundColor;break;}
        }
        if(!content)continue;
        if(WXGColorsDiffer(v.backgroundColor,content,v.traitCollection)){[_navStates paint:v color:content];++_pageTopPaintCleared;}
        break;
    }
    // FIX50: WeChat Pay's Kinda pages (wallet) lay their list out below the bar
    // and clip it there, so rows vanish at the bar's edge instead of passing
    // under the glass: the top reads as an opaque bar. Let the list and the
    // containers that start at the bar's bottom draw past their top edge
    // (clipping only: frames and touches unchanged; restored on leaving).
    if([NSStringFromClass(_route.leaf.class) hasPrefix:@"Kinda"]) {
        NSMutableArray *probe=[NSMutableArray array];
        for(UIView *v in WXGViews(page,400)) {
            if(![v isKindOfClass:UIScrollView.class] || v.hidden)continue;
            CGRect r=WXGWindowRect(v,w);
            if(r.size.width<width-1 || fabs(CGRectGetMinY(r)-navBottom)>3 || CGRectGetMaxY(r)<height-1)continue;
            for(UIView *a=v;a && a!=page;a=a.superview) {
                CGRect ar=WXGWindowRect(a,w);
                if(CGRectGetMinY(ar)<navBottom-3)break;          // already reaches under the bar
                if(probe.count<10)[probe addObject:[NSString stringWithFormat:@"%@ y%.0f h%.0f clip%d%@",NSStringFromClass(a.class),CGRectGetMinY(ar),ar.size.height,a.clipsToBounds,
                    a==v?[NSString stringWithFormat:@" offset%.0f content%.0f rows%lu",((UIScrollView *)v).contentOffset.y,((UIScrollView *)v).contentSize.height,(unsigned long)v.subviews.count]:@""]];
                if(a.clipsToBounds){[_navStates allowOverflow:a];++_pageTopPaintCleared;}
            }
            break;
        }
        _kindaProbe=probe.count?probe:@[@"没有找到从导航栏底边开始的整宽列表"];
    }
}
// FIX27: during a push/pop involving a tab root, WeChat slides its own
// snapshot of the native tab bar (rendered without our mask, so with the old
// items and white background) along with the page. Conceal snapshot-like,
// full-width bottom views in that root page and in the transition containers
// for the duration; restored on the next route reset.
static BOOL WXGLooksLikeTabBarSnapshot(UIView *v,UIWindow *w,CGFloat barHeight) {
    if(v.hidden || v.alpha<.01 || WXGIsPluginView(v))return NO;
    CGRect r=WXGWindowRect(v,w);CGFloat width=w.bounds.size.width,height=w.bounds.size.height;
    if(r.size.width<width*.9 || r.size.height<30 || r.size.height>150 || CGRectGetMinY(r)<height-160 || CGRectGetMaxY(r)>height+40)return NO;
    // Anchored to the screen's bottom edge, with the native bar's height.
    if(CGRectGetMaxY(r)<height-6)return NO;
    if(barHeight>1 && fabs(r.size.height-barHeight)>MAX(8,barHeight*.15))return NO;
    NSString *name=NSStringFromClass(v.class);
    BOOL named=[name containsString:@"TabBar"] || [name containsString:@"Snapshot"] || [name containsString:@"Replicant"] || [name containsString:@"BottomBar"];
    BOOL image=[v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image!=nil;
    // FIX29: chat -> home showed an unmasked, bar-sized UIVisualEffectView in
    // a plain container (the bar's own background lives in the masked bar).
    BOOL blur=[v isKindOfClass:UIVisualEffectView.class];
    return named || image || blur || (v.layer.contents!=nil && v.subviews.count==0);
}
static BOOL WXGLooksLikeTabBarHairline(UIView *v,UIWindow *w,CGFloat barHeight) {
    if(v.hidden || v.subviews.count || barHeight<=1 || WXGIsPluginView(v))return NO;
    CGRect r=WXGWindowRect(v,w);
    return r.size.height<=1.5 && r.size.width>=w.bounds.size.width*.9 && fabs(CGRectGetMinY(r)-(w.bounds.size.height-barHeight))<=3;
}
- (void)concealTransitionSnapshots {
    UIViewController *root=nil;
    if(_nativeTransition && (_dockTransitionToRoot || _dockTransitionFromRoot))root=_dockTransitionToRoot?_transitionTo:_transitionFrom;
    if(!root && _rootReturnTarget && CACurrentMediaTime()<_rootReturnUntil)root=_rootReturnTarget;
    if(!root || !root.isViewLoaded || !_dockView)return;
    // FIX29: every frame; the chat-return bar background is created by UIKit
    // after the pop starts, and must be gone by the next frame. FIX30: once
    // something was concealed in this transition, every third frame suffices.
    ++_snapshotScanFrames;
    if(_snapshotViews.count && _snapshotScanFrames%3)return;
    UIWindow *w=_window;if(!w)return;
    CGFloat bandTop=w.bounds.size.height-MAX(_suppressedTabBar.bounds.size.height,60)-12,bandBottom=w.bounds.size.height+40;
    NSMutableArray<UIView *> *candidates=[NSMutableArray arrayWithArray:WXGViewsInBand(root.view,w,bandTop,bandBottom,300)];
    // FIX28/29: every ancestor up to the window, and a few levels into each
    // sibling branch: the chat-return bar background sits in a plain container.
    UIViewController *other=_nativeTransition?(_dockTransitionToRoot?_transitionFrom:_transitionTo):_rootReturnOther;
    UIView *otherView=other.isViewLoaded?other.view:nil;
    UIView *path=root.view;
    for(UIView *container=root.view.superview;container;path=container,container=container.superview)
        for(UIView *child in container.subviews) {
            if(child==path || (otherView && (child==otherView || [otherView isDescendantOfView:child])))continue;
            [candidates addObjectsFromArray:WXGViewsInBand(child,w,bandTop,bandBottom,40)];
        }
    if(!_snapshotStates)_snapshotStates=[WXGStateBag new];
    NSMutableArray<NSString *> *found=[NSMutableArray array];
    for(UIView *v in candidates) {
        if(v==_dockView || [v isDescendantOfView:_dockView] || ![v isDescendantOfView:w])continue;
        if(_suppressedTabBar && (v==_suppressedTabBar || [v isDescendantOfView:_suppressedTabBar]))continue;
        if(otherView && [v isDescendantOfView:otherView])continue;
        CGFloat barHeight=_suppressedTabBar.bounds.size.height;
        BOOL hairline=WXGLooksLikeTabBarHairline(v,w,barHeight);
        if(!hairline && !WXGLooksLikeTabBarSnapshot(v,w,barHeight))continue;
        if(!_snapshotViews)_snapshotViews=[NSHashTable weakObjectsHashTable];
        if([_snapshotViews containsObject:v])continue;
        [_snapshotViews addObject:v];[_snapshotStates conceal:v];++_snapshotsConcealed;
        if(found.count<4)[found addObject:NSStringFromClass(v.class)];
    }
    if(found.count) {
        if(!_snapshotLog)_snapshotLog=[NSMutableArray array];
        [_snapshotLog addObject:@{@"t":@(CACurrentMediaTime()),@"source":_snapshotSource?:@"transition",
            @"root":NSStringFromClass(root.class),@"classes":found}];
        if(_snapshotLog.count>10)[_snapshotLog removeObjectAtIndex:0];
    }
}
// FIX28: called from the pop hook before UIKit pops toward a tab root, and at
// every transition begin. The previous transition's concealments are lifted
// here (the views are normally gone by now), not at the route reset: on the
// chat page WeChat removed its tab bar snapshot after our reset, so it showed.
- (void)beginRootReturnTo:(UIViewController *)root source:(NSString *)source {
    [_snapshotStates restore];_snapshotStates=nil;[_snapshotViews removeAllObjects];
    _rootReturnTarget=root;_rootReturnUntil=root?CACurrentMediaTime()+.9:0;_snapshotSource=source;
    _rootReturnOther=root.navigationController.topViewController!=root?root.navigationController.topViewController:nil;
    _snapshotScanFrames=1;[self concealTransitionSnapshots];
}
- (BOOL)isBack:(UIControl *)button {
    for(NSString *s in WXGActionNames(button)) {
        NSString *lower=s.lowercaseString;if([lower containsString:@"backbutton"] || [lower containsString:@"return"] || [lower isEqual:@"goback"])return YES;
    }return NO;
}
- (NSString *)titleForControl:(UIControl *)button {
    if([button isKindOfClass:UIButton.class]) {
        UIButton *b=(id)button;if(b.titleLabel.hidden || b.titleLabel.alpha<.01)return nil;
        return b.currentTitle?:b.currentAttributedTitle.string?:b.titleLabel.text;
    }
    for(UIView *v in WXGViews(button,24))if([v isKindOfClass:UILabel.class] && !v.hidden) {
        NSString *text=((UILabel *)v).text?:((UILabel *)v).attributedText.string;if(text.length)return text;
    }
    return nil;
}
- (NSString *)backCount:(UIControl *)button {
    NSString *s=[[self titleForControl:button] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    static NSRegularExpression *pattern;static dispatch_once_t once;
    dispatch_once(&once,^{pattern=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]{1,7}\\+?$" options:0 error:nil];});
    if(s.length && s.length<=8 && s.integerValue>0 && [pattern numberOfMatchesInString:s options:0 range:NSMakeRange(0,s.length)]==1)return s;
    return nil;
}
- (BOOL)controlOnLeft:(UIControl *)control {
    if([self isBack:control])return YES;
    UINavigationItem *item=_route.leaf.navigationItem;
    for(NSUInteger side=0;side<2;side++)for(UIBarButtonItem *button in side?item.rightBarButtonItems:item.leftBarButtonItems) {
        id raw=WXGRead(button,@"view");UIView *host=button.customView?:([raw isKindOfClass:UIView.class]?raw:nil);
        if(host && (control==host || [control isDescendantOfView:host] || [host isDescendantOfView:control]))return side==0;
    }
    // An interactive pop can move a left control past the middle of the screen.
    // Keep the bound role until the native item actually changes.
    for(NSString *key in _surfacePool)if(_surfacePool[key].original==control) {
        if([key hasPrefix:@"left"])return YES;if([key hasPrefix:@"right"])return NO;
    }
    return CGRectGetMidX(WXGWindowRect(control,_window))<CGRectGetMidX(_window.bounds);
}
- (NSInteger)navigationOrder:(UIControl *)control {
    UINavigationItem *item=_route.leaf.navigationItem;
    for(NSUInteger side=0;side<2;side++) {
        NSArray *items=side?item.rightBarButtonItems:item.leftBarButtonItems;
        for(NSUInteger i=0;i<items.count;i++) {
            UIBarButtonItem *button=items[i];id raw=WXGRead(button,@"view");
            UIView *host=button.customView?:([raw isKindOfClass:UIView.class]?raw:nil);
            if(host && (control==host || [control isDescendantOfView:host] || [host isDescendantOfView:control]))
                return side?1000-(NSInteger)i:(NSInteger)i;
        }
    }
    return NSNotFound;
}
- (NSArray<UIControl *> *)navigationControls {
    UINavigationBar *bar=_route.nav.navigationBar;NSMutableArray *out=[NSMutableArray array];
    NSMutableOrderedSet *candidates=[NSMutableOrderedSet orderedSetWithArray:WXGViews(bar,320)];
    // Custom/plugin actions can be siblings of UINavigationBar, especially the
    // home left icon. Never walk table/collection cells looking for actions.
    if(_route.primary || _route.chat)[candidates addObjectsFromArray:_pageViews?:@[]];
    UINavigationItem *item=_route.leaf.navigationItem;
    for(UIBarButtonItem *b in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]])
        if(b.customView)[candidates addObjectsFromArray:WXGViews(b.customView,40)];
    for(UIView *v in candidates) {
        if(![v isKindOfClass:UIControl.class] || !WXGCanForward((id)v))continue;
        if(_nativeTransition && _departingButtons.count) {
            BOOL outgoing=NO;for(WXGSurface *surface in _departingButtons)if(surface.original==v){outgoing=YES;break;}
            BOOL incoming=NO;
            for(UIBarButtonItem *barItem in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]]) {
                id raw=WXGRead(barItem,@"view");UIView *host=barItem.customView?:([raw isKindOfClass:UIView.class]?raw:nil);
                if(host && (v==host || [v isDescendantOfView:host] || [host isDescendantOfView:v]))incoming=YES;
            }
            if(outgoing && !incoming) {
                BOOL rebound=NO;for(id target in ((UIControl *)v).allTargets)if(target==_route.leaf)rebound=YES;
                if(!rebound)continue;
            }
        }
        if(v.hidden)continue;
        if(!WXGVisible(v.superview,_window))continue;
        BOOL existing=NO;for(WXGSurface *s in _buttons)if(s.original==v){existing=YES;break;}
        BOOL home=[NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
        if(home && [WXGActionNames((id)v) containsObject:@"onSearchButtonTapped"]){[_navStates hide:v];_homeSearchControl=(UIControl *)v;continue;}
        if(home && ![WXGActionNames((id)v) containsObject:@"showRightTopMenuBtn"])continue;
        if(!existing && !WXGVisible(v,_window))continue;
        CGRect r=WXGWindowRect(v,_window),nr=WXGWindowRect(bar,_window);
        if(r.size.height<16 || r.size.height>80 || r.size.width<4 || r.size.width>180 || (!home && fabs(CGRectGetMidY(r)-CGRectGetMidY(nr))>24))continue;
        // Only extra corner actions qualify outside the actual navigation bar.
        if(![v isDescendantOfView:bar] && CGRectGetMidX(r)>_window.bounds.size.width*.32 && CGRectGetMidX(r)<_window.bounds.size.width*.68)continue;
        if(![out containsObject:v])[out addObject:v];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){NSInteger ai=[self navigationOrder:(id)a],bi=[self navigationOrder:(id)b];
        CGFloat width=self.window.bounds.size.width;
        CGFloat x=ai==NSNotFound?CGRectGetMidX(WXGWindowRect(a,self.window)):(ai>=900?width-1-(1000-ai)*44:1+ai*44);
        CGFloat y=bi==NSNotFound?CGRectGetMidX(WXGWindowRect(b,self.window)):(bi>=900?width-1-(1000-bi)*44:1+bi*44);
        return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;}];
    return out;
}
- (WXGSurface *)pooledSurface:(NSString *)slot {
    WXGSurface *surface=_surfacePool[slot];
    if(!surface){surface=[WXGSurface new];_surfacePool[slot]=surface;}
    if(![_buttons containsObject:surface])[_buttons addObject:surface];
    if(!surface.active){surface.active=YES;[surface applyConfig];}
    surface.hidden=NO;surface.materialOnly=NO;surface.perform=nil;surface.original=nil;
    return surface;
}
- (BOOL)canForwardItem:(UIBarButtonItem *)item {
    if(!item.enabled || !item.action)return NO;
    if(!item.target)return YES; // UIKit resolves a nil target via the responder chain.
    NSMethodSignature *sig=[item.target methodSignatureForSelector:item.action];
    return sig && sig.methodReturnType[0]=='v' && (sig.numberOfArguments==2 ||
        (sig.numberOfArguments==3 && [sig getArgumentTypeAtIndex:2][0]=='@'));
}
// FIX88: the avatar of the chat on screen (the title's avatar mode). The
// chat page has no avatar view of its own, so FIX87 always fell back to the
// placeholder. In order:
//  1. an avatar view on the page or its title view (as before);
//  2. the chat's contact (GetContact / m_contact ...) and WeChat's head-image
//     service (MMHeadImageMgr through MMServiceCenter / MMContext), each
//     method's type encoding checked before it is called;
//  3. in a one-to-one chat, the avatar on a visible incoming message (the
//     other side's).
// A found image is kept for that chat page (a service image is asked for
// again a few times: it may be the default while the real one loads); until
// then it is looked up again every half second, 12 s at most. Only the source
// goes to the diagnostics.
static id WXGAvatarCall(id target,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if(!target || ![target respondsToSelector:selector])return nil;
    Method m=object_isClass(target)?class_getClassMethod((Class)target,selector):class_getInstanceMethod(object_getClass(target),selector);
    if(!m || method_getNumberOfArguments(m)!=2)return nil;
    char type[8]={0};method_getReturnType(m,type,sizeof type);
    if(type[0]!='@')return nil;
    @try {return ((id (*)(id,SEL))objc_msgSend)(target,selector);} @catch(__unused NSException *error) {return nil;}
}
static id WXGAvatarService(id container,NSString *className) {
    Class cls=NSClassFromString(className);SEL selector=NSSelectorFromString(@"getService:");
    if(!container || !cls || ![container respondsToSelector:selector])return nil;
    Method m=class_getInstanceMethod(object_getClass(container),selector);
    if(!m || method_getNumberOfArguments(m)!=3)return nil;
    char r[8]={0},a[8]={0};method_getReturnType(m,r,sizeof r);method_getArgumentType(m,2,a,sizeof a);
    if(r[0]!='@' || (a[0]!='#' && a[0]!='@'))return nil;   // an object back, a class (or object) in
    @try {return ((id (*)(id,SEL,Class))objc_msgSend)(container,selector,cls);} @catch(__unused NSException *error) {return nil;}
}
// An integer argument's encoding: 0 not an integer, 8 for a 64-bit one (q Q,
// and l L on arm64), 4 otherwise (i I s S c C B).
static int WXGAvatarIntegerWidth(const char *type) {
    if(!type || !type[0])return 0;
    char t=type[0];
    if(t=='r' || t=='n' || t=='N' || t=='o' || t=='O' || t=='R' || t=='V')t=type[1];   // qualifiers
    if(t=='q' || t=='Q' || t=='l' || t=='L')return 8;
    if(t=='i' || t=='I' || t=='s' || t=='S' || t=='c' || t=='C' || t=='B')return 4;
    return 0;
}
static NSString *WXGAvatarUserName(id contact) {
    if(!contact)return nil;
    id name=WXGRead(contact,@"m_nsUsrName");
    return [name isKindOfClass:NSString.class] && [name length]>1 && [name length]<96?name:nil;
}
// MMHeadImageMgr: getHeadImage:withCategory: (an object and an integer) or a
// one-object variant, checked by their type encodings.
static UIImage *WXGAvatarFromService(NSString *userName,NSString **via,NSMutableDictionary *probe) {
    id center=WXGAvatarCall(NSClassFromString(@"MMServiceCenter"),@"defaultCenter");
    id context=WXGAvatarCall(NSClassFromString(@"MMContext"),@"currentContext");
    if(probe){probe[@"serviceCenter"]=@(center!=nil);probe[@"context"]=@(context!=nil);probe[@"headImageMgrClass"]=@(NSClassFromString(@"MMHeadImageMgr")!=nil);}
    for(id container in @[context?:NSNull.null,center?:NSNull.null]) {
        if(container==NSNull.null)continue;
        id manager=WXGAvatarService(container,@"MMHeadImageMgr");
        if(!manager)continue;
        if(probe && !probe[@"headImageMgr"]) {
            probe[@"headImageMgr"]=NSStringFromClass([manager class]);
            // Its head-image methods by name only (what to call next time).
            NSMutableArray *names=[NSMutableArray array];unsigned int count=0;
            Method *methods=class_copyMethodList(object_getClass(manager),&count);
            for(unsigned int i=0;i<count && names.count<40;i++) {
                NSString *name=NSStringFromSelector(method_getName(methods[i]));
                if([name rangeOfString:@"head" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
                   [name rangeOfString:@"avatar" options:NSCaseInsensitiveSearch].location!=NSNotFound)[names addObject:name];
            }
            free(methods);probe[@"headImageMgrMethods"]=names;
        }
        SEL two=NSSelectorFromString(@"getHeadImage:withCategory:");
        Method m=[manager respondsToSelector:two]?class_getInstanceMethod(object_getClass(manager),two):NULL;
        if(m && method_getNumberOfArguments(m)==4) {
            char r[8]={0},a[8]={0},b[8]={0};method_getReturnType(m,r,sizeof r);method_getArgumentType(m,2,a,sizeof a);method_getArgumentType(m,3,b,sizeof b);
            int width=WXGAvatarIntegerWidth(b);
            if(r[0]=='@' && a[0]=='@' && width) {
                for(unsigned int category=0;category<=1;category++) {
                    id image=nil;
                    @try {
                        image=width==8?((id (*)(id,SEL,id,unsigned long long))objc_msgSend)(manager,two,userName,(unsigned long long)category):
                                       ((id (*)(id,SEL,id,unsigned int))objc_msgSend)(manager,two,userName,category);
                    } @catch(__unused NSException *error) {image=nil;}
                    if([image isKindOfClass:UIImage.class]){*via=[NSString stringWithFormat:@"MMHeadImageMgr getHeadImage:withCategory:%u",category];return image;}
                }
            }
        }
        for(NSString *name in @[@"getHeadImageWithUserName:",@"getHeadImage:",@"getHeadImageForUserName:"]) {
            SEL one=NSSelectorFromString(name);
            Method k=[manager respondsToSelector:one]?class_getInstanceMethod(object_getClass(manager),one):NULL;
            if(!k || method_getNumberOfArguments(k)!=3)continue;
            char r[8]={0},a[8]={0};method_getReturnType(k,r,sizeof r);method_getArgumentType(k,2,a,sizeof a);
            if(r[0]!='@' || a[0]!='@')continue;
            id image=nil;
            @try {image=((id (*)(id,SEL,id))objc_msgSend)(manager,one,userName);} @catch(__unused NSException *error) {image=nil;}
            if([image isKindOfClass:UIImage.class]){*via=[@"MMHeadImageMgr " stringByAppendingString:name];return image;}
        }
    }
    return nil;
}
static UIImage *WXGAvatarImageOfLayer(CALayer *layer,int depth) {
    id contents=layer.contents;
    if(contents && CFGetTypeID((__bridge CFTypeRef)contents)==CGImageGetTypeID() && layer.bounds.size.width>16)
        return [UIImage imageWithCGImage:(__bridge CGImageRef)contents scale:layer.contentsScale?:2 orientation:UIImageOrientationUp];
    if(depth<=0)return nil;
    for(CALayer *sub in layer.sublayers){UIImage *image=WXGAvatarImageOfLayer(sub,depth-1);if(image)return image;}
    return nil;
}
static UIImage *WXGAvatarImageOfView(UIView *view) {
    if([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image)return ((UIImageView *)view).image;
    for(UIView *v in WXGViews(view,12))if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && v.bounds.size.width>16)return ((UIImageView *)v).image;
    return WXGAvatarImageOfLayer(view.layer,3);   // FIX95: also a sublayer's picture
}
// FIX95: WeChat's head-image views go by several names.
static BOOL WXGAvatarViewName(NSString *name) {
    for(NSString *part in @[@"HeadImage",@"HeadImg",@"HeadView",@"Avatar",@"avatar",@"headImage"])if([name containsString:part])return YES;
    return NO;
}
// FIX95: the contact's own photo address (the HD one first).
static NSURL *WXGAvatarURL(id contact,NSString **key) {
    for(NSString *name in @[@"m_nsHeadHDImgUrl",@"m_nsHeadImgUrl"]) {
        id value=WXGRead(contact,name);
        if(![value isKindOfClass:NSString.class] || [value length]<10)continue;
        NSURL *url=[NSURL URLWithString:value];
        if(url.host.length && ([url.scheme isEqual:@"https"] || [url.scheme isEqual:@"http"])){if(key)*key=name;return url;}
    }
    return nil;
}
static NSCache<NSString *,UIImage *> *WXGAvatarPhotos(void) {
    static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=48;});
    return cache;
}
/* FIX100 (user: every launch the avatar is read again, though it was read
   last time): a downloaded photo is kept on disk too (WeChat's Caches,
   WeChatLiquidGlass/Avatars), one binary plist per contact (a hash of the
   user name): the name, the address it came from and the image's bytes. The
   next launch shows it at once; if the contact's address has changed since,
   it is downloaded again in the background and replaces it. At most 300 kept
   (the oldest 60 go). */
static NSString *WXGAvatarDiskDirectory(void) {
    static NSString *directory;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSString *caches=NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
        directory=caches?[caches stringByAppendingPathComponent:@"WeChatLiquidGlass/Avatars"]:nil;
        if(directory)[NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    return directory;
}
static NSString *WXGAvatarDiskPath(NSString *userName) {
    NSString *directory=WXGAvatarDiskDirectory();NSData *bytes=[userName dataUsingEncoding:NSUTF8StringEncoding];
    if(!directory || !bytes.length)return nil;
    uint64_t hash=1469598103934665603ULL;const uint8_t *b=bytes.bytes;   // FNV-1a
    for(NSUInteger i=0;i<bytes.length;i++){hash^=b[i];hash*=1099511628211ULL;}
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%016llx.plist",(unsigned long long)hash]];
}
static UIImage *WXGAvatarDiskRead(NSString *userName,NSString **address) {
    NSString *path=WXGAvatarDiskPath(userName);NSData *file=path?[NSData dataWithContentsOfFile:path]:nil;
    if(!file)return nil;
    NSDictionary *entry=[NSPropertyListSerialization propertyListWithData:file options:NSPropertyListImmutable format:NULL error:NULL];
    if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"user"] isEqual:userName] || ![entry[@"image"] isKindOfClass:NSData.class])return nil;
    UIImage *image=[UIImage imageWithData:entry[@"image"] scale:UIScreen.mainScreen.scale];
    if(image.size.width<8)return nil;
    if(address)*address=[entry[@"url"] isKindOfClass:NSString.class]?entry[@"url"]:nil;
    return image;
}
static void WXGAvatarDiskWrite(NSString *userName,NSString *address,NSData *image) {
    NSString *path=WXGAvatarDiskPath(userName);if(!path || !image.length)return;
    NSDictionary *entry=@{@"user":userName,@"url":address?:@"",@"image":image,@"saved":@([NSDate date].timeIntervalSince1970)};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSData *file=[NSPropertyListSerialization dataWithPropertyList:entry format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        if(!file)return;
        [file writeToFile:path atomically:YES];
        NSFileManager *files=NSFileManager.defaultManager;NSString *directory=WXGAvatarDiskDirectory();
        NSArray<NSString *> *names=[files contentsOfDirectoryAtPath:directory error:NULL];
        if(names.count<=300)return;
        NSMutableArray<NSDictionary *> *dated=[NSMutableArray array];
        for(NSString *name in names) {
            NSString *full=[directory stringByAppendingPathComponent:name];
            NSDate *date=[files attributesOfItemAtPath:full error:NULL].fileModificationDate?:NSDate.distantPast;
            [dated addObject:@{@"path":full,@"date":date}];
        }
        [dated sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"date"] compare:b[@"date"]];}];
        for(NSUInteger i=0;i<60 && i<dated.count;i++)[files removeItemAtPath:dated[i][@"path"] error:NULL];
    });
}
// The other side's avatar on a visible incoming message: a head-image view
// near the left edge (one-to-one chats only).
- (UIImage *)visibleIncomingAvatarIn:(UIViewController *)page probe:(NSMutableDictionary *)probe {
    UIWindow *w=page.view.window;if(!w)return nil;
    // Only the message list's visible cells (class names cost on first use).
    // FIX95: a collection view too.
    UIScrollView *list=nil;
    for(UIView *v in WXGViews(page.view,300))if(([v isKindOfClass:UITableView.class] || [v isKindOfClass:UICollectionView.class]) && v.bounds.size.height>w.bounds.size.height*.4){list=(id)v;break;}
    NSArray<UIView *> *cells=[list isKindOfClass:UITableView.class]?((UITableView *)list).visibleCells:[list isKindOfClass:UICollectionView.class]?((UICollectionView *)list).visibleCells:@[];
    NSMutableArray<UIView *> *views=[NSMutableArray array];
    for(UIView *cell in cells)[views addObjectsFromArray:WXGViews(cell,120)];
    NSMutableArray *seen=probe?[NSMutableArray array]:nil;
    if(probe){probe[@"messageList"]=list?NSStringFromClass(list.class):@"none";probe[@"visibleCells"]=@(cells.count);}
    for(UIView *v in views) {
        if(WXGIsPluginView(v) || v.hidden || v.alpha<.01)continue;
        CGRect r=WXGWindowRect(v,w);
        BOOL square=r.size.width>=24 && r.size.width<=72 && fabs(r.size.width-r.size.height)<=4 && CGRectGetMidX(r)<=w.bounds.size.width*.3;
        if(!square)continue;
        NSString *name=NSStringFromClass(v.class);
        BOOL named=WXGAvatarViewName(name);
        UIImage *image=named?WXGAvatarImageOfView(v):nil;
        if(seen.count<12)[seen addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f@%.0f,%.0f%@%@",name,r.size.width,r.size.height,r.origin.x,r.origin.y,named?@" 名称匹配":@"",image?@" 有图":@""]];
        if(image){if(probe)probe[@"leftSquareViews"]=seen;return image;}
    }
    if(probe)probe[@"leftSquareViews"]=seen?:@[];
    return nil;
}
static char WXGAvatarStateKey;   // per chat page: its WXGAvatarState
// FIX95: the contact's photo from its address (WeChat's CDN), once per contact
// (a failed try is retried once; an http address is tried as https first).
// FIX100: a photo already downloaded, this launch or an earlier one (disk);
// one from an earlier launch whose contact now has another address is
// downloaded again in the background (once per launch), shown meanwhile.
- (UIImage *)keptAvatarFor:(NSString *)userName contact:(id)contact {
    if(!userName)return nil;
    UIImage *photo=[WXGAvatarPhotos() objectForKey:userName];
    if(photo)return photo;
    NSString *address=nil;photo=WXGAvatarDiskRead(userName,&address);
    if(!photo)return nil;
    [WXGAvatarPhotos() setObject:photo forKey:userName];++_avatarDiskHits;
    _avatarDownloadStatus=@"头像来自本地缓存";
    static NSMutableSet<NSString *> *checked;static dispatch_once_t once;dispatch_once(&once,^{checked=[NSMutableSet set];});
    NSURL *current=WXGAvatarURL(contact,NULL);
    if(current && ![checked containsObject:userName] && ![current.absoluteString isEqual:address]) {
        [checked addObject:userName];
        BOOL started=NO;[self downloadAvatarFor:userName contact:contact started:&started refresh:YES];
        if(started)_avatarDownloadStatus=@"头像来自本地缓存，地址变了，后台重新下载";
    }
    return photo;
}
- (UIImage *)downloadedAvatarFor:(NSString *)userName contact:(id)contact started:(BOOL *)started {
    userName=[userName copy];
    UIImage *photo=[self keptAvatarFor:userName contact:contact];
    if(photo || !userName)return photo;
    [self downloadAvatarFor:userName contact:contact started:started refresh:NO];
    return nil;
}
- (void)downloadAvatarFor:(NSString *)userName contact:(id)contact started:(BOOL *)started refresh:(BOOL)refresh {
    static NSMutableSet<NSString *> *loading;static NSMutableDictionary<NSString *,NSNumber *> *failed;static dispatch_once_t once;
    dispatch_once(&once,^{loading=[NSMutableSet set];failed=[NSMutableDictionary dictionary];});
    if([loading containsObject:userName]){if(started)*started=YES;return;}
    NSInteger tries=failed[userName].integerValue;if(tries>=2)return;
    NSURL *url=WXGAvatarURL(contact,NULL);if(!url)return;
    NSString *address=url.absoluteString;   // FIX100: kept with the photo (before the https try)
    if(tries==0 && [url.scheme isEqual:@"http"]) {
        NSURLComponents *parts=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];parts.scheme=@"https";url=parts.URL?:url;
    }
    [loading addObject:userName];++_avatarDownloads;if(started)*started=YES;
    if(!refresh)_avatarDownloadStatus=[NSString stringWithFormat:@"下载头像中（%@）",url.host];
    __weak WXGIntegrationHost *weakSelf=self;CGFloat scale=UIScreen.mainScreen.scale;
    NSURLSessionDataTask *task=[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSInteger code=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        UIImage *image=data.length && (code==0 || code<400)?[UIImage imageWithData:data scale:scale]:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            [loading removeObject:userName];
            WXGIntegrationHost *host=weakSelf;
            if(image.size.width>=8) {
                [WXGAvatarPhotos() setObject:image forKey:userName];
                WXGAvatarDiskWrite(userName,address,data);   // FIX100
                // A message-list picture on screen gives way to it (refreshed again).
                UIViewController *page=host.route.leaf;
                WXGAvatarState *shown=page?objc_getAssociatedObject(page,&WXGAvatarStateKey):nil;
                if(shown.image && ![shown.source containsString:@"已下载"]){shown.refreshes=0;shown.downloadWaitUntil=CACurrentMediaTime()+1;shown.lookupAt=0;}
                // FIX100: a kept photo on screen whose address changed: the new one.
                if(refresh && shown.image && [shown.source containsString:@"已下载"] && [shown.user isEqual:userName])shown.image=image;
                host.avatarDownloadStatus=[NSString stringWithFormat:@"头像下载完成（%.0f×%.0f）",image.size.width*image.scale,image.size.height*image.scale];
                host.navigationDirty=YES;[host schedule];
            }else {
                failed[userName]=@(failed[userName].integerValue+1);
                host.avatarDownloadStatus=[NSString stringWithFormat:@"头像下载失败（HTTP %ld%@%@）",(long)code,error?@"，":@"",error.localizedDescription?:@""];
            }
        });
    }];
    task.priority=refresh?NSURLSessionTaskPriorityLow:NSURLSessionTaskPriorityHigh;[task resume];
}
// A group chat's title ends with its member count, "名字(23)" (or full-width
// "名字（23）").
static BOOL WXGTitleLooksLikeGroup(NSString *title) {
    title=[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(title.length<3)return NO;
    BOOL ascii=[title hasSuffix:@")"],wide=[title hasSuffix:@"）"];
    if(!ascii && !wide)return NO;
    NSRange open=[title rangeOfString:ascii?@"(":@"（" options:NSBackwardsSearch];
    if(open.location==NSNotFound || open.location+2>=title.length)return NO;
    NSString *inner=[title substringWithRange:NSMakeRange(open.location+1,title.length-open.location-2)];
    return inner.length && [inner rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location==NSNotFound;
}
// WeChat's group ids: "…@chatroom" (and WeCom's "…@im.chatroom").
static BOOL WXGUserNameIsGroup(NSString *userName) {return [userName hasSuffix:@"chatroom"];}
// The title bar is only rebuilt when something changes, so a lookup that has
// not found the image yet (or is still refreshing one) asks for another pass.
- (void)retryAvatarAfter:(CFTimeInterval)delay {
    if(_avatarRetryPending)return;
    _avatarRetryPending=YES;__weak WXGIntegrationHost *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(MAX(.05,delay)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGIntegrationHost *host=weakSelf;if(!host)return;
        host.avatarRetryPending=NO;
        if(!WXGPreferences.shared.avatarTitle || !host.route.chat || host.route.leaf!=host.avatarLookupPage)return;
        host.navigationDirty=YES;[host schedule];
    });
}
// Per chat page (an associated object, gone with the page): the image found,
// where from, and how often it was looked up / refreshed.
- (WXGAvatarState *)avatarStateFor:(UIViewController *)page {
    WXGAvatarState *state=objc_getAssociatedObject(page,&WXGAvatarStateKey);
    if(!state){state=[WXGAvatarState new];objc_setAssociatedObject(page,&WXGAvatarStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return state;
}
- (UIImage *)avatarImageForTitle:(NSString *)title {
    UIViewController *page=_route.leaf;
    if(!page)return nil;
    WXGAvatarState *state=[self avatarStateFor:page];
    // Back on a page whose lookup gave up: another 12 s.
    if(page!=_avatarLookupPage){_avatarLookupPage=page;if(!state.image)state.attempts=0;}
    UIImage *cached=state.image;
    // A found image is kept, except one from the head-image service: that can
    // be WeChat's default while the real one downloads, so the service is asked
    // again (every 0.75 s, 8 times) and the image replaced if it changes.
    // Nothing found: again every 0.5 s, at most 24 times (12 s).
    // FIX95: a picture from the message list is replaced by the contact's
    // downloaded photo when that arrives.
    BOOL photoPending=cached && ![state.source containsString:@"已下载"] && !state.fromService && state.refreshes<8 && state.downloadWaitUntil>0;
    BOOL refreshing=cached && (state.fromService || photoPending) && state.refreshes<8;
    if(cached && !refreshing){_avatarSource=state.source;return cached;}
    if(!cached && state.attempts>=24)return nil;
    CFTimeInterval now=CACurrentMediaTime(),interval=cached?.75:.5;
    if(now-state.lookupAt<interval){[self retryAvatarAfter:interval-(now-state.lookupAt)];return cached;}
    state.lookupAt=now;++_avatarLookups;
    if(cached)++state.refreshes;else ++state.attempts;
    UIImage *found=nil;NSString *source=nil;BOOL fromService=NO;
    for(id object in @[page,page.navigationItem.titleView?:[NSNull null]]) {
        if(object==NSNull.null)continue;
        for(NSString *key in @[@"headImageView",@"m_headImageView",@"avatarImageView",@"m_avatarImageView"]) {
            id v=WXGRead(object,key);
            if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image){found=((UIImageView *)v).image;source=[@"页面上的头像视图 " stringByAppendingString:key];break;}
        }
        if(found)break;
    }
    NSString *userName=nil;
    // FIX95: the first lookup on a page records what it saw (diagnostics).
    NSMutableDictionary *probe=state.probed?nil:[NSMutableDictionary dictionary];state.probed=YES;
    BOOL downloading=NO;
    if(!found) {
        id contact=nil;
        for(NSString *name in @[@"GetContact",@"getContact",@"getChatContact",@"contact"]){contact=WXGAvatarCall(page,name);if(WXGAvatarUserName(contact))break;contact=nil;}
        for(NSString *key in @[@"m_contact",@"m_oContact",@"_contact",@"m_chatContact"]){if(contact)break;id c=WXGRead(page,key);if(WXGAvatarUserName(c))contact=c;}
        userName=WXGAvatarUserName(contact);
        if(probe) {
            probe[@"page"]=NSStringFromClass(page.class);probe[@"contact"]=contact?NSStringFromClass([contact class]):@"none";
            probe[@"chat"]=userName?(WXGUserNameIsGroup(userName)?@"群聊":@"单聊"):@"未知";
            for(NSString *key in @[@"m_nsHeadImgUrl",@"m_nsHeadHDImgUrl",@"m_nsHeadHDMd5"]) {
                id value=contact?WXGRead(contact,key):nil;
                NSURL *url=[value isKindOfClass:NSString.class]?[NSURL URLWithString:value]:nil;
                probe[key]=!value?@"无":[value isKindOfClass:NSString.class]?([value length]?(url.host.length?[@"有，" stringByAppendingString:url.host]:[NSString stringWithFormat:@"有（%lu 字）",(unsigned long)[value length]]):@"空"):NSStringFromClass([value class]);
            }
        }
        NSString *via=nil;
        // FIX100: a photo already downloaded (this launch or an earlier one,
        // kept on disk) first: no placeholder, no service round.
        if(userName) {
            found=[self keptAvatarFor:userName contact:contact];
            if(found){source=@"聊天联系人 → 头像地址（已下载，本地缓存）";state.user=userName;state.downloadWaitUntil=0;}
        }
        if(!found && userName) {
            found=WXGAvatarFromService(userName,&via,probe);
            if(found){source=[@"聊天联系人 → " stringByAppendingString:via];fromService=YES;}
        }
        // FIX95: else the contact's own photo, downloaded once (HD first).
        if(!found && userName) {
            found=[self downloadedAvatarFor:userName contact:contact started:&downloading];
            if(found){source=@"聊天联系人 → 头像地址（已下载）";fromService=NO;state.downloadWaitUntil=0;state.user=userName;}
            else if(downloading && state.downloadWaitUntil<=0)state.downloadWaitUntil=now+3;
        }
    }
    // The message list only in a chat known to be one-to-one: a contact that
    // is not a group, or (no contact found) a known title (the one the bar
    // shows) without a member count. A group's messages show other people.
    BOOL group=WXGUserNameIsGroup(userName) || (!userName && WXGTitleLooksLikeGroup(title));
    BOOL oneToOne=userName?!group:(title.length && !group);
    // FIX95: while the HD photo downloads (3 s at most), not the message list's.
    BOOL waitForPhoto=downloading && now<state.downloadWaitUntil;
    if(!found && !cached && oneToOne && (!waitForPhoto || probe)) {
        UIImage *message=[self visibleIncomingAvatarIn:page probe:probe];   // (the first time also for the probe)
        if(message && !waitForPhoto){found=message;source=userName?@"聊天里对方消息的头像":@"聊天里对方消息的头像（未找到联系人，按标题判断为单聊）";}
    }
    if(probe)_avatarProbe=probe;
    if(found) {
        if(!cached || found.CGImage!=cached.CGImage) {
            state.image=found;state.source=source;
            _avatarStatus=[NSString stringWithFormat:@"读到头像：%@%@",source,cached?@"（已更新）":@""];
        }
        state.fromService=fromService;_avatarSource=state.source;
        if(fromService && state.refreshes<8)[self retryAvatarAfter:.75];
        return found;
    }
    if(cached){if(state.refreshes<8)[self retryAvatarAfter:.75];_avatarSource=state.source;return cached;}   // nothing this time: keep it
    _avatarSource=nil;
    _avatarStatus=downloading?@"找到了聊天联系人，正在下载对方的头像，暂用占位图":
                  userName?(group?@"群聊：头像服务没有返回图片，暂用占位图":@"找到了聊天联系人，但头像服务、头像地址和消息里都没读到图片，暂用占位图"):
                           (group?@"没有找到聊天联系人，标题像群聊，不从消息里取头像，暂用占位图":
                            (title.length?@"没有找到聊天联系人，消息里也没有对方头像，暂用占位图":@"没有找到聊天联系人，也没有标题，不从消息里取头像，暂用占位图"));
    if(state.attempts<24)[self retryAvatarAfter:.5];
    return nil;
}
- (UIView *)motionInkForControl:(UIControl *)control {
    for(UIView *view in WXGViews(control,24))if([view isKindOfClass:UIImageView.class] &&
        !view.hidden && view.alpha>.01 && ((UIImageView *)view).image && view.bounds.size.width>4 && view.bounds.size.width<80)return view;
    return control;
}
- (NSString *)fullTitleFromView:(UIView *)view fallback:(NSString *)fallback {
    NSMutableArray<UILabel *> *labels=[NSMutableArray array];UILabel *main=nil;
    for(UIView *v in WXGViews(view,80))if([v isKindOfClass:UILabel.class] && !v.hidden && v.alpha>.01) {
        UILabel *label=(id)v;NSString *text=label.text?:label.attributedText.string;
        if(!text.length)continue;[labels addObject:label];
        if(!main || label.font.pointSize*label.bounds.size.width>main.font.pointSize*main.bounds.size.width)main=label;
    }
    if(!main)return fallback;
    CGFloat y=CGRectGetMidY([main convertRect:main.bounds toView:view]);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a,UILabel *b){
        CGFloat x=[a convertRect:a.bounds toView:view].origin.x,z=[b convertRect:b.bounds toView:view].origin.x;
        return x<z?NSOrderedAscending:x>z?NSOrderedDescending:NSOrderedSame;
    }];
    NSMutableString *title=[NSMutableString string];
    for(UILabel *label in labels)if(fabs(CGRectGetMidY([label convertRect:label.bounds toView:view])-y)<MAX(12,main.bounds.size.height*.65)) {
        NSString *text=label.text?:label.attributedText.string;
        if(![title hasSuffix:text])[title appendString:text];
    }
    if(fallback.length>title.length && [fallback hasPrefix:title])return fallback;
    return title.length?title:fallback;
}
- (void)logTransition:(NSString *)phase cancelled:(BOOL)cancelled {
    NSDictionary *row=@{@"t":@(CACurrentMediaTime()),@"serial":@(_transitionSerial),@"phase":phase,@"cancelled":@(cancelled),
        @"fromID":[NSString stringWithFormat:@"%p",_transitionFrom],@"toID":[NSString stringWithFormat:@"%p",_transitionTo],
        @"from":_transitionFrom?NSStringFromClass(_transitionFrom.class):@"none",@"to":_transitionTo?NSStringFromClass(_transitionTo.class):@"none",
        @"duration":@(_nativeTransition.transitionDuration),@"elapsed":@(MAX(0,CACurrentMediaTime()-_transitionBegan)),
        @"interactive":@(_nativeTransition.isInteractive),@"percent":@(_nativeTransition.percentComplete),
        @"navigationCallDepth":@(WXGNavigationCallDepth),@"animationsEnabled":@(UIView.areAnimationsEnabled)};
    [_transitionLog addObject:row];if(_transitionLog.count>48)[_transitionLog removeObjectAtIndex:0];
}
- (void)observeTransition:(id<UIViewControllerTransitionCoordinator>)coordinator {
    if(!coordinator || !coordinator.isAnimated || _nativeTransition==coordinator || _completedTransition==coordinator)return;
    UIViewController *from=[coordinator viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *to=[coordinator viewControllerForKey:UITransitionContextToViewControllerKey];
    // Only navigation transitions are owned here. UIKit presents sheets/images itself.
    // After a pop UIKit may already have detached `from` from the stack.
    // `to` must still belong to a navigation controller: presentations are not ours.
    if(!from || !to || !to.navigationController ||
       (from.navigationController && from.navigationController!=to.navigationController))return;
    if(_nativeTransition){
        for(WXGSurface *surface in _departingButtons){surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);}
        _departingButtons=nil;_departingInput=nil;
    }
    _nativeTransition=coordinator;_transitionFrom=from;_transitionTo=to;++_transitionSerial;
    // FIX21: the destination's bar background is shown at the start of a
    // pop/push (e.g. back from 视频号); clear it now, not after completion.
    if(WXGPluginEnabled() && WXGPreferences.shared.nav && _route.nav){
        @try {[self clearNavigationPaint];++_navigationPaintRescans;if(to.isViewLoaded)[self clearPageTopPaint:to.view];}
        @catch(NSException *error){WXGLog(@"转场导航背景清理：%@",error.reason);}
    }
    _dockTransitionFromRoot=[self isDockRoot:from];_dockTransitionToRoot=[self isDockRoot:to];
    if(_dockTransitionToRoot)[self captureTopPaintCensus:@"transitionToTabRoot"];
    if(_dockTransitionToRoot || _dockTransitionFromRoot)
        [self beginRootReturnTo:_dockTransitionToRoot?to:from source:_dockTransitionToRoot?@"transitionToRoot":@"transitionFromRoot"];
    if(_dockTransitionToRoot) {
        __weak WXGIntegrationHost *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            [weakSelf capturePaintCensus:@"transitionToTabRoot+0.12s" bottom:YES];
        });
    }
    BOOL dockAvailable=WXGPluginEnabled() && WXGPreferences.shared.dock && !_suspendedByCover && !_settings.presentingViewController;
    [self applyDockPresentation:WXGDockPresentationForState(dockAvailable,NO,YES,_dockTransitionToRoot)];
    _transitionBegan=CACurrentMediaTime();
    for(WXGSurface *surface in _buttons)[surface beginNativeDeparture];
    // Retain the stable home reference. UIKit may already have written the
    // offscreen endpoint here; reading it creates the observed reverse drift.
    [self logTransition:@"begin" cancelled:NO];
    __weak WXGIntegrationHost *weak=self;
    [coordinator notifyWhenInteractionChangesUsingBlock:^(id<UIViewControllerTransitionCoordinatorContext> context){
        [weak logTransition:@"interaction_end" cancelled:context.isCancelled];
    }];
    __weak id<UIViewControllerTransitionCoordinator> weakCoordinator=coordinator;
    BOOL registered=[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){
        [weak logTransition:@"coordinator_completion" cancelled:context.isCancelled];
        [weak finishNativeTransition:weakCoordinator cancelled:context.isCancelled];
    }];
    // UIKit documents that completion can still run when this return value is NO.
    if(!registered)[self logTransition:@"alongside_not_queued" cancelled:coordinator.isCancelled];
}
- (void)dropDepartingButtons {
    for(WXGSurface *surface in _departingButtons){surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);}
    _departingButtons=nil;
}
- (void)finishNativeTransition:(id<UIViewControllerTransitionCoordinator>)coordinator cancelled:(BOOL)cancelled {
    if(!coordinator || _nativeTransition!=coordinator)return;
    if(cancelled)++_transitionCancellations;else ++_transitionCompletions;
    [self logTransition:@"complete" cancelled:cancelled];
    for(WXGSurface *surface in _departingButtons){surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);}
    for(WXGSurface *surface in _departingInput.surfaces)surface.active=NO;
    _departingButtons=nil;_departingInput=nil;_completedTransition=coordinator;_nativeTransition=nil;
    WXGResetOwnedTransform(_dockView);_dockView.layer.mask=nil;_pendingController=nil;_needsEarlyLayout=NO;_navigationDirty=YES;
    // A completed push is already bound to its incoming page. Restoring all
    // masks here briefly exposed native artwork and discarded those bindings.
    if(cancelled || _route.leaf!=_transitionTo)[self resetRoute];
    BOOL dockAvailable=WXGPluginEnabled() && WXGPreferences.shared.dock && !_suspendedByCover && !_settings.presentingViewController;
    [self applyDockPresentation:WXGDockPresentationAfterTransition(dockAvailable,_dockTransitionFromRoot,_dockTransitionToRoot,cancelled)];
    [_navStates reapply];[self schedule];
}
- (void)buildNavigation {
    ++_navigationRepairs;
    UINavigationBar *bar=_route.nav.navigationBar;UIWindow *w=_window;
    BOOL home=[NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
    if(!bar || !_route.leaf.isViewLoaded){[_navStates reapply];return;}
    // Pull-down rehomes the home gesture while temporarily hiding UINavigationBar.
    // Visibility is not destruction; existing surfaces follow their real hosts.
    if(!home && (bar.hidden || bar.alpha<.01)){[_navStates reapply];return;}
    if(!_navStates)_navStates=[WXGStateBag new];
    NSArray<UIControl *> *controls=[self navigationControls];
    if(CACurrentMediaTime()-WXGLoadTime<30) {
        NSMutableArray *names=[NSMutableArray array];for(UIControl *c in controls)[names addObject:NSStringFromClass(c.class)];
        NSString *line=[NSString stringWithFormat:@"导航构建 %@：原生按钮 %lu [%@]",NSStringFromClass(_route.leaf.class),(unsigned long)controls.count,[names componentsJoinedByString:@","]];
        if(![line isEqual:_lastNavLog]){_lastNavLog=line;WXGColdLog(line);}
    }
    NSMutableSet *alive=[NSMutableSet set];
    CGRect nr=WXGWindowRect(bar,w);CGFloat midX=CGRectGetMidX(w.bounds),centerY=CGRectGetMidY(nr);
    WXGMetrics m=WXGMeasure(w.bounds.size.width-w.safeAreaInsets.left-w.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
    if(m.button>MAX(36,nr.size.height))m=WXGMeasure(440*MAX(36,nr.size.height)/44,1);
    centerY=MAX(centerY,w.safeAreaInsets.top+m.button*.5);
    CGFloat left=w.safeAreaInsets.left+m.edge,right=w.bounds.size.width-w.safeAreaInsets.right-m.edge;
    NSMutableArray *leftButtons=[NSMutableArray array],*rightButtons=[NSMutableArray array];
    NSUInteger leftSlot=0,rightSlot=0;
    for(UIControl *b in controls) {
        BOOL onLeft=[self controlOnLeft:b];
        NSString *slot=[NSString stringWithFormat:@"%@%lu",onLeft?@"left":@"right",(unsigned long)(onLeft?leftSlot++:rightSlot++)];
        WXGSurface *s=[self pooledSurface:slot];s.original=b;s.motionHost=[self motionInkForControl:b];WXGResetOwnedTransform(s);[alive addObject:s];
        BOOL back=[self isBack:b];NSString *count=back?[self backCount:b]:nil;
        UIImage *image=WXGButtonImage(b);NSString *title=image?nil:[self titleForControl:b];
        if(back && !image)image=[UIImage systemImageNamed:@"chevron.left"];
        s.role=back?@"back":title.length?@"textAction":@"navigationAction";
        // Video artwork can keep its native contrast while material selection
        // follows the same WeChat window appearance and shared TEST9 settings.
        s.overrideUserInterfaceStyle=[NSStringFromClass(_route.leaf.class) hasPrefix:@"WCFinder"]?w.traitCollection.userInterfaceStyle:UIUserInterfaceStyleUnspecified;
        [s setNativeIconSource:s.motionHost preservingColors:[NSStringFromClass(_route.leaf.class) hasPrefix:@"WCFinder"]];
        s.label.font=[UIFont systemFontOfSize:17*m.scale weight:UIFontWeightSemibold];
        s.countLabel.font=[UIFont monospacedDigitSystemFontOfSize:12*m.scale weight:UIFontWeightSemibold];
        [s setImage:image title:title count:count];
        s.accessibilityLabel=b.accessibilityLabel.length?b.accessibilityLabel:back?@"返回":title.length?title:WXGActionNames(b).firstObject;
        s.enabled=b.enabled;s.glass.sourceView=_route.leaf.view;s.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
        CGFloat width=m.button;
        if(count.length)width=WXGCapsuleWidth([count sizeWithAttributes:@{NSFontAttributeName:s.countLabel.font}].width,36*m.scale,m.button,14*m.scale,w.bounds.size.width*.36);
        else if(title.length)width=WXGCapsuleWidth([title sizeWithAttributes:@{NSFontAttributeName:s.label.font}].width,0,m.button,14*m.scale,w.bounds.size.width*.38);
        /* Store desired visual size; place after grouping to preserve left /
           right edge equality even when the rightmost control was only 24 pt. */
        CGRect desired=CGRectMake(0,0,width+2*WXGCanvasPaddingX,m.button+2*WXGCanvasPaddingY);
        if(!CGRectEqualToRect(s.bounds,desired))s.bounds=desired;
        if(onLeft)[leftButtons addObject:s];else[rightButtons addObject:s];
    }
    // UIBarButtonItem target/action is valid even without a discoverable
    // MMBarButton. Preserve the real item as sender rather than invent actions.
    NSArray *groups=@[_route.leaf.navigationItem.leftBarButtonItems?:@[],(_route.leaf.navigationItem.rightBarButtonItems.reverseObjectEnumerator.allObjects?:@[])];
    for(NSUInteger side=0;side<2;side++)for(UIBarButtonItem *item in groups[side]) {
        if([NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] && ![(item.action?NSStringFromSelector(item.action):@"") isEqual:@"showRightTopMenuBtn"])continue;
        id raw=WXGRead(item,@"view");UIView *native=item.customView?:([raw isKindOfClass:UIView.class]?raw:nil);
        BOOL bound=NO;for(UIControl *control in controls)if(control==native || [control isDescendantOfView:native] || [native isDescendantOfView:control]){bound=YES;break;}
        if(bound || ![self canForwardItem:item])continue;
        NSString *slot=[NSString stringWithFormat:@"%@%lu",side?@"right":@"left",(unsigned long)(side?rightSlot++:leftSlot++)];
        WXGSurface *surface=[self pooledSurface:slot];surface.role=@"barItemAction";WXGResetOwnedTransform(surface);
        surface.overrideUserInterfaceStyle=[NSStringFromClass(_route.leaf.class) hasPrefix:@"WCFinder"]?w.traitCollection.userInterfaceStyle:UIUserInterfaceStyleUnspecified;
        __weak UIBarButtonItem *weakItem=item;
        surface.perform=^{UIBarButtonItem *original=weakItem;if(!original || !original.enabled)return;
            [UIApplication.sharedApplication sendAction:original.action to:original.target from:original forEvent:nil];
            [WXGIntegrationHost.shared schedule];};
        UIImage *icon=item.image;
        if(!icon && [native isKindOfClass:UIControl.class])icon=WXGButtonImage((id)native);
        [surface setNativeIconSource:native preservingColors:[NSStringFromClass(_route.leaf.class) hasPrefix:@"WCFinder"]];
        [surface setImage:icon title:icon?nil:item.title count:nil];
        CGFloat width=icon?m.button:WXGCapsuleWidth([item.title sizeWithAttributes:@{NSFontAttributeName:surface.label.font}].width,0,m.button,14*m.scale,w.bounds.size.width*.32);
        CGRect bounds=CGRectMake(0,0,width+2*WXGCanvasPaddingX,m.button+2*WXGCanvasPaddingY);
        if(!CGRectEqualToRect(surface.bounds,bounds))surface.bounds=bounds;
        surface.glass.sourceView=_route.leaf.view;surface.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
        [(side?rightButtons:leftButtons) addObject:surface];[alive addObject:surface];if(native)[_navStates conceal:native];surface.motionHost=native;
    }
    for(WXGSurface *s in leftButtons) {
        CGFloat width=s.bounds.size.width-2*WXGCanvasPaddingX;
        [s placeMaterial:CGRectMake(left,centerY-m.button*.5,width,m.button) inParent:_navigationOverlay];left+=width+m.gap;
        [_navStates conceal:s.original];
    }
    for(WXGSurface *s in rightButtons.reverseObjectEnumerator) {
        CGFloat width=s.bounds.size.width-2*WXGCanvasPaddingX;right-=width;
        CGFloat y=centerY;
        if([NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] && s.original)
            y=CGRectGetMidY(WXGWindowRect(s.original,w));
        [s placeMaterial:CGRectMake(right,y-m.button*.5,width,m.button) inParent:_navigationOverlay];right-=m.gap;
        [_navStates conceal:s.original];
    }
    if(_route.chat) {
        UILabel *nativeLabel=nil;UIView *titleView=_route.leaf.navigationItem.titleView;
        for(UIView *v in WXGViews(titleView,80))if([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length && !v.hidden) {
            if(!nativeLabel || v.bounds.size.width*((UILabel *)v).font.pointSize>nativeLabel.bounds.size.width*nativeLabel.font.pointSize)nativeLabel=(id)v;
        }
        NSString *title=[self fullTitleFromView:titleView fallback:_route.leaf.navigationItem.title?:_route.leaf.title];
        if(title.length) {
            WXGSurface *t=nil,*a=nil;
            for(WXGSurface *s in _buttons){if([s.role isEqual:@"chatTitle"])t=s;if([s.role isEqual:@"avatar"])a=s;}
            if(!t){t=[self pooledSurface:@"chatTitle"];t.role=@"chatTitle";}
            [alive addObject:t];t.label.font=[UIFont systemFontOfSize:17*m.scale weight:UIFontWeightSemibold];
            [t setImage:nil title:title count:nil];
            UIControl *detail=rightButtons.count?((WXGSurface *)rightButtons.lastObject).original:nil;
            t.motionHost=nativeLabel?:titleView;WXGResetOwnedTransform(t);t.original=detail;t.enabled=detail!=nil;t.glass.sourceView=_route.leaf.view;
            t.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
            if(WXGPreferences.shared.avatarTitle) {
                if(!a){a=[self pooledSurface:@"avatar"];a.role=@"avatar";}
                // FIX88: looked up until found (kept per chat page); the title tells groups apart.
                UIImage *avatar=[self avatarImageForTitle:title];
                // FIX94: a grey disc with a white figure (fills the circle like a photo).
                static UIImage *placeholder;static dispatch_once_t placeholderOnce;
                dispatch_once(&placeholderOnce,^{
                    CGFloat d=120;
                    placeholder=[[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(d,d)] imageWithActions:^(UIGraphicsImageRendererContext *context){
                        (void)context;[[UIColor colorWithWhite:.78 alpha:1] setFill];UIRectFill(CGRectMake(0,0,d,d));
                        UIImageSymbolConfiguration *size=[UIImageSymbolConfiguration configurationWithPointSize:d*.46 weight:UIImageSymbolWeightRegular];
                        UIImage *figure=[[UIImage systemImageNamed:@"person.fill" withConfiguration:size] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
                        CGSize s=figure.size;[figure drawInRect:CGRectMake((d-s.width)*.5,(d-s.height)*.5+d*.04,s.width,s.height)];
                    }];
                });
                // FIX94: no glass: the photo itself, the glass's former size.
                if(!a.plain)a.plain=YES;
                [a setImage:avatar?:placeholder title:nil count:nil];   // the same image: no work
                [alive addObject:a];a.motionHost=nativeLabel?:titleView;WXGResetOwnedTransform(a);a.original=detail;a.enabled=detail!=nil;a.glass.sourceView=_route.leaf.view;
                a.glass.backdropExclusions=t.glass.backdropExclusions;
                // FIX95: size and height are settings; the title capsule stays
                // where the default 60 pt avatar puts it (its top 5 pt under the
                // avatar's lower edge), the avatar about its own centre.
                CGFloat nominal=60*m.scale,y=centerY-m.button*.5;
                CGFloat diameter=WXGClamp(WXGConfig.shared.avatarSize,32,88)*m.scale;
                CGFloat avatarMid=y+nominal*.5+WXGClamp(WXGConfig.shared.avatarOffsetY,-24,24)*m.scale;
                [a placeMaterial:CGRectMake(midX-diameter*.5,avatarMid-diameter*.5,diameter,diameter) inParent:_navigationOverlay];
                CGFloat th=30*m.scale,tw=WXGCapsuleWidth([title sizeWithAttributes:@{NSFontAttributeName:t.label.font}].width,0,th,14*m.scale,w.bounds.size.width*.70);
                [t placeMaterial:CGRectMake(midX-tw*.5,y+nominal-5*m.scale,tw,th) inParent:_navigationOverlay];
                // FIX94: the avatar one layer above the title capsule (its lower
                // edge overlaps the capsule; the capsule must never cut into it).
                if(a.superview==_navigationOverlay && t.superview==_navigationOverlay &&
                   [_navigationOverlay.subviews indexOfObjectIdenticalTo:a]<[_navigationOverlay.subviews indexOfObjectIdenticalTo:t])
                    [_navigationOverlay insertSubview:a aboveSubview:t];
            } else {
                CGFloat limit=2*MAX(0,MIN(midX-left,right-midX));
                if(!leftButtons.count)limit=2*MAX(0,MIN(midX-(w.safeAreaInsets.left+m.edge),right-midX));
                limit=MAX(0,limit);
                if(limit>=m.button) {
                    CGFloat tw=WXGCapsuleWidth([title sizeWithAttributes:@{NSFontAttributeName:t.label.font}].width,0,m.button,14*m.scale,limit);
                    [t placeMaterial:CGRectMake(midX-tw*.5,centerY-m.button*.5,tw,m.button) inParent:_navigationOverlay];
                }else{[alive removeObject:t];}
            }
            if([alive containsObject:t] && titleView)[_navStates conceal:titleView];
            else if(titleView)[_navStates restoreView:titleView];
        }
    }
    if(_route.primary) {
        NSUInteger slot=0;
        NSMutableArray *candidates=[WXGViews(bar,200) mutableCopy];[candidates addObjectsFromArray:_pageViews?:@[]];
        if(home)for(UIView *v in _homeGestureHosts)if(![candidates containsObject:v] && [v isDescendantOfView:_route.nav.view])[candidates addObject:v];
        NSMutableSet *visited=[NSMutableSet set];
        // FIX60: compared by class (no class name per candidate view).
        static Class leftBarClass;static dispatch_once_t leftBarOnce;
        dispatch_once(&leftBarOnce,^{leftBarClass=NSClassFromString(@"MainFrameLeftBarView");});
        BOOL homePage=[NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
        for(UIView *v in candidates) {
            BOOL home=homePage;
            if(home && (!leftBarClass || v.class!=leftBarClass))continue;
            if([visited containsObject:v])continue;[visited addObject:v];
            // MainFrameLeftBarView is an observed native host. During pull-down
            // WeChat can move its recognizer to a child without replacing the icon.
            if((!home && !v.gestureRecognizers.count) || !WXGVisible(v,w) || ([v isKindOfClass:UIControl.class] && WXGCanForward((id)v)))continue;
            CGRect r=WXGWindowRect(v,w);
            if(r.size.width<12 || r.size.width>65 || r.size.height<12 || r.size.height>65 || CGRectGetMidX(r)>w.bounds.size.width*.28 || (!home && fabs(CGRectGetMidY(r)-centerY)>24))continue;
            WXGSurface *surface=[self bindHomeGesture:v diameter:m.button slot:[NSString stringWithFormat:@"nativeLeft%lu",(unsigned long)slot++]];
            if(surface)[alive addObject:surface];if(home)break;
        }
    }
    for(WXGSurface *s in _buttons.copy)if(![alive containsObject:s]) {
        BOOL temporary=s.motionHost.window==w && s.motionOwner==_route.leaf &&
            (_nativeTransition || !WXGVisible(s.motionHost,w));
        if(temporary)continue;
        s.active=NO;s.hidden=YES;if(s.original && ![s.role isEqual:@"chatTitle"] && ![s.role isEqual:@"avatar"])[_navStates restoreView:s.original];[_buttons removeObject:s];
    }
    [self styleFinderButtons];
    for(WXGSurface *surface in _buttons) {
        surface.nativeTransitionActive=_nativeTransition!=nil;
        if(![surface.role isEqual:@"nativeGesture"]){[surface bindMotionHost:surface.motionHost owner:_route.leaf];[surface followNativePresentation];}
    }
    // A reused native control has exactly one glass representation. Different
    // from/to controls still follow their own native presentation animations.
    if(_departingButtons.count) {
        NSMutableArray *outgoing=[_departingButtons mutableCopy];
        for(WXGSurface *old in _departingButtons)for(WXGSurface *current in _buttons) {
            BOOL sameControl=old.original && old.original==current.original;
            BOOL sameHost=old.motionHost && old.motionHost==current.motionHost;
            if(old!=current && (sameControl || sameHost)) {
                old.active=NO;old.hidden=YES;[outgoing removeObject:old];break;
            }
        }
        _departingButtons=outgoing;
    }
    [self clearNavigationPaint];[_overlay bringSubviewToFront:_launcher];
    _navigationBindingKey=[self currentNavigationBindingKey];
}
// FIX85/86: 视频号 (WCFinder pages, over video): each button keeps its own
// glass (FIX86: no shared capsule any more), with no material tint (blur and
// refraction only) and the rim always in its dark-appearance settings (the
// page is video whatever the system appearance). Every other page: both
// reset. Each value is assigned only when it differs (no glass relaid out on
// every navigation-bar layout).
- (void)styleFinderButtons {
    BOOL finder=[NSStringFromClass(_route.leaf.class) hasPrefix:@"WCFinder"];
    UIColor *veil=finder?UIColor.clearColor:nil;
    for(WXGSurface *s in _buttons) {
        if(s.glass.veilOverride!=veil)s.glass.veilOverride=veil;
        if(s.glass.rimAlwaysDark!=finder)s.glass.rimAlwaysDark=finder;
    }
}
- (NSArray<UIControl *> *)nativeTabButtons {
    NSMutableArray *a=[NSMutableArray array];
    for(UIView *v in WXGViews(_route.tabs.tabBar,100))if([NSStringFromClass(v.class) isEqual:@"UITabBarButton"] && [v isKindOfClass:UIControl.class])[a addObject:v];
    [a sortUsingComparator:^NSComparisonResult(UIView *x,UIView *y){return x.frame.origin.x<y.frame.origin.x?NSOrderedAscending:NSOrderedDescending;}];return a;
}
- (NSArray<NSString *> *)tabBadges {
    NSMutableArray *out=[NSMutableArray array];UITabBar *bar=_route.tabs.tabBar;
    for(NSInteger i=0;i<4;i++) {
        NSString *badge=i<(NSInteger)bar.items.count?bar.items[i].badgeValue:nil;
        if(!badge.length) {
            CGFloat x=(i+.5)*bar.bounds.size.width/4;
            for(UIView *v in WXGViews(bar,140)) {
                NSString *n=NSStringFromClass(v.class).lowercaseString;
                if(![n containsString:@"badge"] && ![n containsString:@"reddot"])continue;
                if(v.hidden || v.alpha<.01 || v.bounds.size.width<3 || v.bounds.size.height<3)continue;
                CGFloat cx=CGRectGetMidX([v convertRect:v.bounds toView:bar]);
                if(fabs(cx-x)>bar.bounds.size.width/8)continue;
                for(UIView *child in WXGViews(v,12))if([child isKindOfClass:UILabel.class] && ((UILabel *)child).text.length){badge=((UILabel *)child).text;break;}
                if(!badge.length)badge=@"•";break;
            }
        }[out addObject:badge?:@""];
    }return out;
}
- (BOOL)isDockRoot:(UIViewController *)controller {
    UINavigationController *nav=controller.navigationController;
    UITabBarController *tabs=nav.tabBarController;
    BOOL selected=NO;
    for(UIViewController *parent=nav;parent;parent=parent.parentViewController)if(parent==tabs.selectedViewController){selected=YES;break;}
    return controller && nav && tabs.viewControllers.count==4 && nav.viewControllers.firstObject==controller && selected;
}
- (void)applyDockPresentation:(WXGDockPresentation)presentation {
    if(presentation!=WXGDockSettled)[_dockView cancelInteraction];
    _dockPresentation=presentation;
    // FIX60: searching only on a settled tab root.
    if(presentation!=WXGDockSettled)[self closeDockSearchAnimated:NO];
    if(!_dockView)return;
    // Keep one stable owner. Native MMTabBar may be hidden or below the page
    // during a return; its replacement no longer inherits those transient states.
    // FIX60: the owner is the dock row inside the overlay (same coordinates).
    [self ensureDockRow];
    UIView *owner=_dockRow?:_overlay;
    if(owner && _dockView.superview!=owner){[_dockView removeFromSuperview];[owner addSubview:_dockView];}
    BOOL visible=presentation!=WXGDockHidden;
    _dockView.active=visible;_dockView.hidden=!visible;
    _dockView.userInteractionEnabled=presentation==WXGDockSettled;
    WXGResetOwnedTransform(_dockView);_dockView.layer.mask=nil;
    _dockView.glass.sourceView=_window.rootViewController.view;[_dockView propagateGlassSources];
    [self applySearchPresentation:visible interactive:presentation==WXGDockSettled];
    if(visible && _overlay){[_overlay.superview bringSubviewToFront:_overlay];[_overlay bringSubviewToFront:_dockRow?:_dockView];[_overlay bringSubviewToFront:_launcher];}
}
- (void)buildDock {
    if(!_route.primary || _route.tabs.viewControllers.count!=4)return;
    if(_suppressedTabBar && _suppressedTabBar!=_route.tabs.tabBar){WXGRestoreDockTouchDelegates(_suppressedTabBar);[_dockStates restore];_dockStates=nil;}
    _suppressedTabBar=_route.tabs.tabBar;_dockPrimaryOwner=_route.leaf;
    if(!_dockView) {
        _dockView=[WXGDemoBar new];_dockView.externallyDriven=YES;_dockView.hidden=YES;
        [_dockView addTarget:self action:@selector(dockChanged:) forControlEvents:UIControlEventValueChanged];
        __weak WXGIntegrationHost *weakHost=self;   // FIX100: 按下时
        _dockView.tabSwitchRequest=^BOOL(NSInteger index){return [weakHost dockRequestedTabAtTouchDown:index];};
        [_dockView addTarget:self action:@selector(closeDockSearchTapped) forControlEvents:UIControlEventPrimaryActionTriggered];   // FIX60
        // FIX89: the settings fallback's long press never takes the dock's
        // touch: it only begins without WeChat's settings entry, on the tab
        // already selected, and cancels nothing (FIX35-88 it recognised every
        // 0.9 s hold, entry or not, and UIKit cancelled the dock's tracking:
        // a hold on another tab snapped back and never switched).
        UILongPressGestureRecognizer *g=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(dockLongPress:)];
        g.minimumPressDuration=.9;g.cancelsTouchesInView=NO;g.delaysTouchesEnded=NO;g.delegate=self;
        [_dockView addGestureRecognizer:g];_dockLongPress=g;
    }
    UITabBar *nativeBar=_route.tabs.tabBar;
    if(!_dockStates)_dockStates=[WXGStateBag new];
    // User-approved stable return policy: one foreground dock, no partial
    // exposure mask, reconstructed native transform, or ownership swapping.
    WXGRestoreDockTouchDelegates(nativeBar);
    [self ensureDockRow];
    UIView *owner=_dockRow?:_overlay;
    if(_dockView.superview!=owner){[_dockView removeFromSuperview];[owner addSubview:_dockView];}
    CGRect bounds=[_window convertRect:_window.bounds toView:_overlay];
    WXGConfig *c=WXGConfig.shared;CGFloat rowWidth=(bounds.size.width-_window.safeAreaInsets.left-_window.safeAreaInsets.right)*c.widthFraction;
    CGFloat rowX=bounds.origin.x+_window.safeAreaInsets.left+(bounds.size.width-_window.safeAreaInsets.left-_window.safeAreaInsets.right-rowWidth)*.5;
    CGFloat y=CGRectGetMaxY(bounds)-MAX(0,_window.safeAreaInsets.bottom+c.lift)-c.height;
    // FIX60: with the search button the dock's width setting is the whole
    // row: the capsule, a gap and the round button (left or right).
    BOOL search=[self dockSearchAvailable],leading=WXGPreferences.shared.dockSearchLeading;
    // FIX61: the gap is a setting; searching, the row has its own width and
    // height (centred on the dock's row). The close button stays inside the
    // dock's canvas, so the search row is at most 72 pt wider than the dock.
    CGFloat usable=bounds.size.width-_window.safeAreaInsets.left-_window.safeAreaInsets.right;
    CGFloat gap=search?c.dockSearchGap:0,openH=round(c.height*c.dockSearchHeightRatio*2)/2;
    // FIX68: on the search button's side the bar's end stretch stays in the gap.
    CGFloat room=search?MAX(2,gap*.75):0;
    _dockView.endStretchRoomLeft=search && leading?room:0;_dockView.endStretchRoomRight=search && !leading?room:0;
    // FIX63: both glasses stay inside their 40 pt canvas padding, spring and
    // swell included: button on the left, the close button reaches out by half
    // the extra width; on the right, the field also widens by the height
    // difference.
    CGFloat extra=leading?64:MIN(64,MAX(0,2*(30+openH-c.height)));
    CGFloat openW=MIN(MAX(usable*c.dockSearchWidthFraction,2*openH+gap),rowWidth+extra);
    CGFloat openX=bounds.origin.x+_window.safeAreaInsets.left+(usable-openW)*.5;
    CGRect row=CGRectMake(rowX,y,rowWidth,c.height),openRow=CGRectMake(openX,y+(c.height-openH)*.5,openW,openH);
    if(search && (!CGRectEqualToRect(row,_dockRowRect) || !CGRectEqualToRect(openRow,_dockOpenRect) || leading!=_searchLeading || fabs(gap-_searchGap)>.01))
        [self closeDockSearchAnimated:NO];
    _dockRowRect=search?row:CGRectZero;_dockOpenRect=search?openRow:CGRectZero;_searchLeading=leading;_searchGap=gap;
    WXGDockSearchRow restRow={(float)rowX,(float)rowWidth,(float)c.height},searchRow={(float)openX,(float)openW,(float)openH};
    WXGDockSearchSpans rest=search?WXGDockSearchLayoutRows(0,restRow,searchRow,(float)gap,leading):(WXGDockSearchSpans){(float)rowX,(float)rowWidth,0,0,(float)c.height};
    WXGDockSearchSpans open=search?WXGDockSearchLayoutRows(1,restRow,searchRow,(float)gap,leading):rest;
    CGFloat x=rest.capsuleX,width=rest.capsuleW;
    // The button's canvas holds both its outlines (round at rest, the field).
    CGFloat searchMin=MIN(rest.searchX,open.searchX),searchMax=MAX(rest.searchX+rest.searchW,open.searchX+open.searchW);
    CGRect searchFrame=CGRectMake(searchMin-WXGCanvasPaddingX,y-WXGCanvasPaddingY,searchMax-searchMin+2*WXGCanvasPaddingX,c.height+2*WXGCanvasPaddingY);
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.dockView.transform=CGAffineTransformIdentity;
        self.dockView.frame=CGRectMake(x-WXGCanvasPaddingX,y-WXGCanvasPaddingY,width+2*WXGCanvasPaddingX,c.height+2*WXGCanvasPaddingY);
        if(search && self.searchView)self.searchView.frame=searchFrame;
        [CATransaction commit];
    }];
    _dockView.glass.sourceView=_window.rootViewController.view;_dockView.glass.backdropExclusions=@[_route.tabs.tabBar];
    [_dockView propagateGlassSources];   // 离散底栏: the pieces see the same page
    [_dockView updateNativeIconsFromTabController:_route.tabs];
    // FIX31: while a deferred switch is pending the dock is ahead of WeChat on
    // purpose; syncing back would snap the lens to the old tab and cancel it.
    if(_pendingTabIndex<0)[_dockView syncSelectedIndex:_route.tabs.selectedIndex];
    [_dockView updateBadges:[self tabBadges]];
    NSString *style=[NSString stringWithFormat:@"%@/%ld",NSStringFromCGSize(_dockView.bounds.size),(long)_window.traitCollection.userInterfaceStyle];
    if(![_dockStyleKey isEqual:style]){_dockStyleKey=style;[_dockView applyConfig];[_searchView applyConfig];}
    [self applyDockPresentation:WXGDockPresentationForState(YES,YES,_nativeTransition!=nil,_dockTransitionToRoot)];
    // applyDockPresentation may have just made the button: give it its frame.
    if(search && _searchView && !CGRectEqualToRect(_searchView.frame,searchFrame))
        [UIView performWithoutAnimation:^{self.searchView.frame=searchFrame;}];
    [self applySearchMorph];
    [self suppressNativeDockPaint];
    [_overlay bringSubviewToFront:_launcher];
}
#pragma mark - FIX60 dock search
// A round search button beside the dock (left or right). Tapped, it widens
// into a search field and the dock narrows into a round close button (one
// spring, WXGDockSearchLayout.h); the field takes the keyboard and the row
// rides above it. The search key hands the text to WeChat's own search:
// its search entry is triggered and the text typed into WeChat's field as
// soon as that field starts editing (on another tab, 微信 is opened first).
- (BOOL)dockSearchAvailable {
    WXGPreferences *p=WXGPreferences.shared;
    return p.dockSearch && p.dock && WXGEffectiveRenderMode()>=2 && WXGPluginEnabled();
}
// The dock and the button share this pass-through row inside the overlay,
// with the overlay's coordinates; its transform is the keyboard lift.
- (void)ensureDockRow {
    if(!_overlay)return;
    if(!_dockRow){_dockRow=[WXGOverlay new];_dockRow.backgroundColor=UIColor.clearColor;_dockRow.opaque=NO;}
    if(_dockRow.superview!=_overlay){[_dockRow removeFromSuperview];[_overlay addSubview:_dockRow];}
    CGRect bounds=_overlay.bounds;CGPoint centre=CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds));
    if(CGRectEqualToRect(_dockRow.bounds,bounds) && CGPointEqualToPoint(_dockRow.center,centre))return;
    [UIView performWithoutAnimation:^{self.dockRow.bounds=bounds;self.dockRow.center=centre;}];
}
- (void)applySearchPresentation:(BOOL)visible interactive:(BOOL)interactive {
    BOOL want=visible && _dockRow && !CGRectIsEmpty(_dockRowRect) && [self dockSearchAvailable];
    if(!want) {
        if(_searchView && (!_searchView.hidden || _searchView.active)){[self closeDockSearchAnimated:NO];_searchView.active=NO;_searchView.hidden=YES;}
        if(_dockView.morphing){_dockView.searchMode=NO;[_dockView setSearchShape:_dockView.materialRect progress:0];}
        return;
    }
    if(!_searchView) {
        _searchView=[WXGDockSearch new];_searchView.hidden=YES;
        [_searchView addTarget:self action:@selector(openDockSearch) forControlEvents:UIControlEventPrimaryActionTriggered];
        __weak WXGIntegrationHost *weakSelf=self;
        _searchView.onSubmit=^(NSString *text){[weakSelf submitDockSearch:text];};
        _searchView.onClose=^{[weakSelf closeDockSearchAnimated:YES];};
    }
    if(_searchView.superview!=_dockRow) {
        [_searchView removeFromSuperview];
        if(_dockView.superview==_dockRow)[_dockRow insertSubview:_searchView belowSubview:_dockView];else [_dockRow addSubview:_searchView];
    }
    // FIX63: the field sits above both glasses.
    UIView *fieldView=_searchView.fieldView;
    if(fieldView.superview!=_dockRow || _dockRow.subviews.lastObject!=fieldView)[_dockRow addSubview:fieldView];
    _searchView.closesWhenOpen=!_searchLeading;_dockView.showsClose=_searchLeading;
    _searchView.hidden=NO;_searchView.active=YES;_searchView.userInteractionEnabled=interactive;
    _searchView.glass.sourceView=_window.rootViewController.view;
}
// Both outlines from the spring value (own coordinates of each view).
- (void)applySearchMorph {
    if(!_dockView)return;
    BOOL live=_searchView && !_searchView.hidden && !CGRectIsEmpty(_dockRowRect);
    if(!live) {
        _searchT=_searchV=0;
        if(_dockView.morphing)[_dockView setSearchShape:_dockView.materialRect progress:0];
        return;
    }
    CGRect row=_dockRowRect,openRow=_dockOpenRect,dockFrame=_dockView.frame,searchFrame=_searchView.frame;
    WXGDockSearchRow rest={(float)row.origin.x,(float)row.size.width,(float)row.size.height},open={(float)openRow.origin.x,(float)openRow.size.width,(float)openRow.size.height};
    WXGDockSearchSpans s=WXGDockSearchLayoutRows((float)_searchT,rest,open,(float)_searchGap,_searchLeading);
    // FIX62: the whole row swells a little with the spring (speed, overshoot).
    s=WXGDockSearchSwell(s,WXGDockSearchSwellAmount((float)_searchT,(float)_searchV,(float)row.size.width),_searchLeading);
    CGFloat progress=WXGClamp(_searchT,0,1),top=CGRectGetMidY(row)-s.height*.5;
    // FIX63: the field ends on the left, the close button on the right. Button
    // on the left: its glass widens into the field (magnifier rides along),
    // the capsule becomes the close button. Button on the right: the capsule
    // becomes the field (it fades in over it), the button the close button.
    BOOL leading=_searchLeading;
    float tabs=WXGDockSearchTabsFade((float)progress),close=WXGDockSearchCloseReveal((float)progress);
    [_dockView setSearchShape:CGRectMake(s.capsuleX-dockFrame.origin.x,top-dockFrame.origin.y,s.capsuleW,s.height) progress:progress];
    [_searchView setShape:CGRectMake(s.searchX-searchFrame.origin.x,top-searchFrame.origin.y,s.searchW,s.height)
                magnifier:leading?0:1-tabs close:leading?0:close];
    CGRect fieldRow=leading?CGRectMake(s.searchX,top,s.searchW,s.height):CGRectMake(s.capsuleX,top,s.capsuleW,s.height);
    [_searchView setFieldFrame:fieldRow reveal:progress iconRides:leading];
}
- (void)stepDockSearch:(CFTimeInterval)time {
    if(!_searchView || _searchView.hidden || !_searchView.active){_searchLastTick=0;return;}
    double target=_searchOpen?1:0;
    if(_searchT!=target || _searchV!=0) {
        double dt=_searchLastTick>0?time-_searchLastTick:1./60;
        if(UIAccessibilityIsReduceMotionEnabled()){_searchT=target;_searchV=0;}
        else WXGSpring(&_searchT,&_searchV,target,WXG_DOCK_SEARCH_STIFFNESS,WXG_DOCK_SEARCH_DAMPING,dt);
        [self applySearchMorph];
    }
    _searchLastTick=time;
    [_searchView tick:time];
}
- (void)openDockSearch {
    if(_searchOpen || !_searchView || _searchView.hidden || _dockPresentation!=WXGDockSettled || _nativeTransition ||
       _suspendedByCover || !_route.primary || _pendingSearchText)return;
    _searchOpen=YES;++_searchOpens;_pendingTabIndex=-1;
    _dockView.searchMode=YES;_searchView.expanded=YES;
    // FIX61: only the animation; the keyboard comes when the field is tapped.
}
- (void)closeDockSearchTapped {[self closeDockSearchAnimated:YES];}
- (void)closeDockSearchAnimated:(BOOL)animated {
    if(_searchOpen) {
        _searchOpen=NO;_dockView.searchMode=NO;
        UITextField *field=_searchView.field;
        // Handing over, WeChat's field takes the keyboard from ours (no dip).
        if(field.isFirstResponder && !_searchEntryTriggered)[field resignFirstResponder];
        _searchView.expanded=NO;
    }
    if(!animated) {
        if(_searchT!=0 || _searchV!=0){_searchT=0;_searchV=0;[self applySearchMorph];}
        [self setKeyboardLift:0 duration:0 curve:0];
    }
}
- (void)dockSearchKeyboard:(NSNotification *)note {
    UIWindow *w=_window;if(!w)return;
    CGRect end=[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local=[w convertRect:end fromCoordinateSpace:w.screen.coordinateSpace];
    CGFloat bottom=CGRectGetMaxY(w.bounds);
    _keyboardTop=(CGRectIsEmpty(local) || CGRectGetMinY(local)>=bottom-1)?bottom:CGRectGetMinY(local);
    [self updateKeyboardLift:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]
                       curve:[note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue]];
}
- (void)updateKeyboardLift:(double)duration curve:(NSInteger)curve {
    CGFloat lift=0;
    if(_searchOpen && _keyboardTop>0 && !CGRectIsEmpty(_dockOpenRect) && _overlay && _window) {
        CGRect row=[_overlay convertRect:_dockOpenRect toView:_window];
        lift=MAX(0,CGRectGetMaxY(row)+10-_keyboardTop);
    }
    [self setKeyboardLift:lift duration:duration curve:curve];
}
- (void)setKeyboardLift:(CGFloat)lift duration:(double)duration curve:(NSInteger)curve {
    if(!_dockRow){_keyboardLift=0;return;}
    // FIX67: plus the slide-away while the mini-program panel opens.
    CGAffineTransform target=CGAffineTransformMakeTranslation(0,-lift+[self homePanelDrop]);
    if(fabs(lift-_keyboardLift)<.5 && CGAffineTransformEqualToTransform(_dockRow.transform,target))return;
    _keyboardLift=lift;
    if(duration<=0){[self.dockRow.layer removeAllAnimations];[UIView performWithoutAnimation:^{self.dockRow.transform=target;}];return;}
    // The keyboard's own duration and curve: the row moves with it.
    [UIView animateWithDuration:duration delay:0 options:((UIViewAnimationOptions)curve<<16)|UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                     animations:^{self.dockRow.transform=target;} completion:nil];
}

#pragma mark - FIX60 handing the search to WeChat

- (void)submitDockSearch:(NSString *)text {
    if(!_searchOpen || !text.length || _pendingSearchText)return;
    _pendingSearchText=[text copy];_pendingSearchSince=CACurrentMediaTime();++_searchHandoffs;
    _searchEntryTriggered=NO;_searchSwitchRequested=NO;_searchEntry=nil;_deliveryAttempts=0;_handoffField=nil;_handoffResponder=nil;
    [self continueSearchHandoff];
}
// WeChat's search entry on the chat list: the top-right search button (kept
// hidden there since FIX10) or, failing that, the list's own search bar.
- (UIControl *)homeSearchEntry {
    UIControl *entry=_homeSearchControl;
    if(entry.window && WXGCanForward(entry))return entry;
    NSMutableArray *candidates=[NSMutableArray arrayWithArray:WXGViews(_route.nav.navigationBar,320)];
    [candidates addObjectsFromArray:_pageViews?:@[]];
    for(UIView *v in candidates)if([v isKindOfClass:UIControl.class] && WXGCanForward((id)v) && [WXGActionNames((id)v) containsObject:@"onSearchButtonTapped"])
        {_homeSearchControl=(id)v;return (id)v;}
    return nil;
}
- (UISearchBar *)homeSearchBar {
    if(![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] || !_route.leaf.isViewLoaded)return nil;
    UIView *page=_route.leaf.view;UISearchBar *bar=_homeSearchBarRef;
    if(bar.window && [bar isDescendantOfView:page])return bar;
    // Once per list (cached): the page scan, then a deeper walk.
    for(UIView *v in _pageViews?:@[])if([v isKindOfClass:UISearchBar.class] && v.window){_homeSearchBarRef=(id)v;return (id)v;}
    if(_homeSearchBarScanPage==page)return nil;
    _homeSearchBarScanPage=page;
    for(UIView *v in WXGViews(page,1500))if([v isKindOfClass:UISearchBar.class] && v.window){_homeSearchBarRef=(id)v;return (id)v;}
    return nil;
}
- (void)continueSearchHandoff {
    if(!_pendingSearchText)return;
    if(CACurrentMediaTime()-_pendingSearchSince>4.6) {
        [self finishSearchHandoff:_searchEntryTriggered?@"已打开微信搜索，但没有可以输入的焦点":@"4 秒内没有回到微信页的搜索入口" success:NO];
        return;
    }
    if(_searchEntryTriggered)return;
    BOOL home=_route.primary && [NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
    if(!home) {
        // Search lives on the 微信 tab: switch there. FIX62: WeChat's search
        // opens as soon as that page is on screen, not at our next refresh.
        if(_route.primary && _route.tabs.viewControllers.count==4 && !_searchSwitchRequested && !_nativeTransition) {
            _searchSwitchRequested=YES;[self forwardTabIndex:0];[_dockView syncSelectedIndex:0];[self schedule];
            [self pollHomeSearchEntry:0];
        }
        return;
    }
    [self triggerHomeSearchEntry];
}
- (void)pollHomeSearchEntry:(NSUInteger)attempt {
    if(!_pendingSearchText || _searchEntryTriggered)return;
    UIControl *entry=_homeSearchControl;
    if(entry.window && WXGCanForward(entry)){[self triggerHomeSearchEntry];return;}
    if(attempt>=30)return;   // the refresh path takes over
    __weak WXGIntegrationHost *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.03*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf pollHomeSearchEntry:attempt+1];});
}
- (void)triggerHomeSearchEntry {
    if(!_pendingSearchText || _searchEntryTriggered)return;
    UIControl *entry=[self homeSearchEntry];
    if(entry) {
        _searchEntryTriggered=YES;_searchEntry=@"右上角搜索按钮";
        [entry sendActionsForControlEvents:UIControlEventTouchDown];
        [entry sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        UISearchBar *bar=[self homeSearchBar];
        if(!bar) {
            if(_route.primary && [NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"])
                [self finishSearchHandoff:@"聊天列表上没有找到微信的搜索入口" success:NO];
            return;
        }
        _searchEntryTriggered=YES;_searchEntry=@"聊天列表搜索栏";
        [self restoreTopSearch];   // WeChat's own bar is about to be used
        [bar.searchTextField becomeFirstResponder];
    }
    [self recordForward:@{@"role":@"dockSearch",@"entry":_searchEntry?:@"",@"textLength":@(_pendingSearchText.length)}];
    [self scheduleSearchDelivery:.15];
}
// FIX61: WeChat's search page can focus more than one field while it opens
// (FIX60 diagnostics: the field that began editing was no longer focused
// 60 ms later and the text was lost). The text now stays pending until it is
// typed into the text field (not ours) that is focused, tried every 0.1 s;
// at the deadline it is written into the field that began editing.
- (UITextField *)focusedTextField:(UITextField **)candidateOut {
    UITextField *focused=nil,*candidate=nil;
    NSMutableArray<UIWindow *> *windows=[NSMutableArray array];
    if(_window)[windows addObject:_window];
    UIWindow *key=UIApplication.sharedApplication.keyWindow;NSString *keyName=key?NSStringFromClass(key.class):@"";
    if(key && key!=_window && ![keyName containsString:@"Keyboard"] && ![keyName containsString:@"TextEffects"])[windows addObject:key];
    for(UIWindow *w in windows) {
        if(w.hidden)continue;
        NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:w];
        for(NSUInteger i=0;i<queue.count && i<4000;i++) {
            UIView *v=queue[i];
            if([v isKindOfClass:UITextField.class] && v!=_searchView.field) {
                UITextField *field=(id)v;
                if(field.isFirstResponder){focused=field;break;}
                if(!candidate && WXGVisible(field,w) && ([field.superview isKindOfClass:UISearchBar.class] || [field isKindOfClass:NSClassFromString(@"UISearchBarTextField")] ||
                   [field.placeholder containsString:@"搜索"]))candidate=field;
            }
            if(WXGIsPluginView(v) || [v isKindOfClass:UITableViewCell.class])continue;
            [queue addObjectsFromArray:v.subviews];
        }
        if(focused)break;
    }
    if(candidateOut)*candidateOut=candidate;
    return focused;
}
- (void)scheduleSearchDelivery:(NSTimeInterval)delay {
    __weak WXGIntegrationHost *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf attemptSearchDelivery];});
}
// As typed by the keyboard: replaces what the field holds, WeChat searches.
- (BOOL)typeSearchText:(NSString *)text into:(UITextField *)field {
    @try {
        UITextRange *all=[field textRangeFromPosition:field.beginningOfDocument toPosition:field.endOfDocument];
        if(all && !all.isEmpty)field.selectedTextRange=all;
        [field insertText:text];
    } @catch(NSException *error){WXGLog(@"底栏搜索填入失败：%@",error.reason);return NO;}
    return [field.text containsString:text];
}
// Not focused: set the text and send what typing sends (editing changed,
// the change notification, the search bar delegate's textDidChange).
- (BOOL)writeSearchText:(NSString *)text into:(UITextField *)field {
    @try {
        field.text=text;
        [field sendActionsForControlEvents:UIControlEventEditingChanged];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextFieldTextDidChangeNotification object:field];
        UISearchBar *bar=nil;for(UIView *v=field.superview;v;v=v.superview)if([v isKindOfClass:UISearchBar.class]){bar=(id)v;break;}
        id<UISearchBarDelegate> delegate=bar.delegate;
        if(bar && [delegate respondsToSelector:@selector(searchBar:textDidChange:)])[delegate searchBar:bar textDidChange:text];
    } @catch(NSException *error){WXGLog(@"底栏搜索写入失败：%@",error.reason);return NO;}
    return [field.text isEqualToString:text];
}
// FIX62: WeChat's search page focuses its own input (not a UITextField: the
// FIX61 diagnostics found no focused text field while its keyboard was up).
// Whatever responder takes the keyboard from ours gets the text as typed
// (insertText:), once it has held the focus for 0.2 s; then the search key.
- (BOOL)typeSearchText:(NSString *)text intoResponder:(UIResponder *)responder {
    if([responder isKindOfClass:UITextField.class])return [self typeSearchText:text into:(UITextField *)responder];
    @try {[(id<UIKeyInput>)responder insertText:text];}
    @catch(NSException *error){WXGLog(@"底栏搜索填入失败：%@",error.reason);return NO;}
    return YES;
}
- (void)attemptSearchDelivery {
    NSString *text=_pendingSearchText;
    if(!text || !_searchEntryTriggered)return;
    ++_deliveryAttempts;
    CFTimeInterval now=CACurrentMediaTime();
    NSString *entry=_searchEntry?:@"";
    UIResponder *responder=WXGFirstResponder();
    BOOL usable=responder && responder!=_searchView.field && [responder conformsToProtocol:@protocol(UIKeyInput)];
    if(usable) {
        // A newly focused input settles first (a page attaches its handlers).
        if(responder!=_handoffResponder){_handoffResponder=responder;_handoffResponderSince=now;[self scheduleSearchDelivery:.2];return;}
        if(now-_handoffResponderSince<.18){[self scheduleSearchDelivery:.08];return;}
        if([self typeSearchText:text intoResponder:responder]) {
            // FIX63: no search key afterwards: WeChat searches as the text
            // arrives, and the newline FIX62 sent stayed in its field (the
            // field looked empty until one backspace).
            [self finishSearchHandoff:[NSString stringWithFormat:@"%@ → %@：已填入（第 %lu 次）",entry,NSStringFromClass(responder.class),(unsigned long)_deliveryAttempts] success:YES];
            return;
        }
    }
    if(now-_pendingSearchSince<4.2) {
        // Every half second, focus a visible search field if nothing took the keyboard.
        if(!usable && _deliveryAttempts%5==0) {
            UITextField *candidate=nil;[self focusedTextField:&candidate];
            if(candidate)[candidate becomeFirstResponder];
        }
        [self scheduleSearchDelivery:.1];
        return;
    }
    UITextField *target=_handoffField;
    if(target && [self writeSearchText:text into:target]) {
        [self finishSearchHandoff:[NSString stringWithFormat:@"%@ → %@：没有聚焦的输入框，已直接写入",entry,NSStringFromClass(target.class)] success:YES];
        return;
    }
    [self finishSearchHandoff:[NSString stringWithFormat:@"%@：没有接收输入的焦点（最后的焦点 %@）",entry,responder?NSStringFromClass(responder.class):@"无"] success:NO];
}
- (void)textFieldBegan:(NSNotification *)note {
    UITextField *field=note.object;
    if(![field isKindOfClass:UITextField.class] || field==_searchView.field)return;
    // WeChat's search bar inside the hidden list header: let it draw while it
    // is used (FIX61: no header reassignment here, it took the focus away).
    UIView *header=_topSearchHeader;
    if(_topSearchHidden && header && [field isDescendantOfView:header]){_nativeSearchEditing=YES;header.clipsToBounds=NO;}
    if(_pendingSearchText && _searchEntryTriggered){_handoffField=field;[self scheduleSearchDelivery:.08];}
}
- (void)textFieldEnded:(NSNotification *)note {
    UITextField *field=note.object;
    if(![field isKindOfClass:UITextField.class] || field==_searchView.field)return;
    // Searching is over once WeChat cleared its field; the next refresh hides the bar again.
    if(_nativeSearchEditing && !field.text.length){_nativeSearchEditing=NO;[self schedule];}
}
- (void)finishSearchHandoff:(NSString *)message success:(BOOL)success {
    _lastSearchHandoff=message;if(!success)++_searchHandoffMisses;
    WXGLog(@"底栏搜索：%@",message);
    BOOL triggered=_searchEntryTriggered;
    _pendingSearchText=nil;_searchEntryTriggered=NO;_searchSwitchRequested=NO;
    // Nothing opened: the text stays in our field. Otherwise WeChat's search
    // has it (or failed to take it): ours closes.
    if(success || triggered)[self closeDockSearchAnimated:NO];
}

#pragma mark - FIX60 the chat list's own search bar

// Collapsed, not removed: the list's header (holding only the search bar)
// gets height 0 and clips, so the list starts under the navigation bar.
// WeChat's bar stays in place for its own search; while WeChat edits in it,
// the header is given back. Restored when the switch, the dock search or the
// plugin is off.
- (void)updateTopSearchHiding {
    if(!(WXGPreferences.shared.hideTopSearch && [self dockSearchAvailable])){[self restoreTopSearch];return;}
    if(_pendingSearchText)return;
    if(!_route.primary || ![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"])return;
    UISearchBar *bar=[self homeSearchBar];
    // WeChat's own search still using its bar (focused or holding text): wait.
    if(_nativeSearchEditing) {
        if(bar.searchTextField.isFirstResponder || bar.searchTextField.text.length)return;
        _nativeSearchEditing=NO;
    }
    if(!bar){_topSearchStatus=@"没有找到聊天列表的搜索栏";return;}
    UITableView *table=nil;UIView *header=nil;
    for(UIView *v=bar;v.superview;v=v.superview)if([v.superview isKindOfClass:UITableView.class]){table=(id)v.superview;header=v;break;}
    if(!table || table.tableHeaderView!=header){_topSearchStatus=@"搜索栏不在列表表头里，未隐藏";return;}
    if(_topSearchHidden && _topSearchHeader!=header)[self restoreTopSearch];
    CGFloat height=header.frame.size.height;
    if(_topSearchHidden && height<.5){if(!header.clipsToBounds)header.clipsToBounds=YES;return;}
    if(height<.5){_topSearchStatus=@"表头高度为 0";return;}
    if(height>bar.frame.size.height+8){_topSearchStatus=[NSString stringWithFormat:@"表头 %.0f pt 里还有别的内容，未隐藏",height];return;}
    if(!_topSearchHidden){_topSearchHeight=height;_topSearchClipped=header.clipsToBounds;}
    _topSearchHeader=header;_topSearchTable=table;_topSearchHidden=YES;++_topSearchHides;
    [UIView performWithoutAnimation:^{
        header.clipsToBounds=YES;
        CGRect frame=header.frame;frame.size.height=0;header.frame=frame;
        table.tableHeaderView=header;   // the table reads the new height
    }];
    _topSearchStatus=@"已隐藏";
}
- (void)restoreTopSearch {
    if(!_topSearchHidden)return;
    _topSearchHidden=NO;
    UIView *header=_topSearchHeader;UITableView *table=_topSearchTable;
    if(header) {
        CGFloat height=_topSearchHeight;BOOL clipped=_topSearchClipped;
        [UIView performWithoutAnimation:^{
            CGRect frame=header.frame;frame.size.height=height;header.frame=frame;
            header.clipsToBounds=clipped;
            if(table.tableHeaderView==header)table.tableHeaderView=header;
        }];
    }
    _topSearchStatus=@"已恢复";
}
- (NSDictionary *)dockSearchEvidence {
    return @{@"available":@([self dockSearchAvailable]),@"open":@(_searchOpen),@"progress":@(round(_searchT*1000)/1000),
             @"leading":@(_searchLeading),@"row":NSStringFromCGRect(_dockRowRect),@"gap":@(_searchGap),@"keyboardLift":@(_keyboardLift),
             @"opens":@(_searchOpens),@"handoffs":@(_searchHandoffs),@"handoffMisses":@(_searchHandoffMisses),
             @"lastHandoff":_lastSearchHandoff?:@"",@"entryControl":@(_homeSearchControl!=nil),
             @"button":_searchView?@{@"hidden":@(_searchView.hidden),@"active":@(_searchView.active),@"frame":NSStringFromCGRect(_searchView.frame),
                                     @"shape":NSStringFromCGRect(_searchView.shape),@"renderer":_searchView.glass.diagnostics?:@""}:@"none",
             @"topSearchBar":@{@"switch":@(WXGPreferences.shared.hideTopSearch),@"hidden":@(_topSearchHidden),@"status":_topSearchStatus?:@"",
                               @"hides":@(_topSearchHides),@"savedHeight":@(_topSearchHeight),@"nativeEditing":@(_nativeSearchEditing)}};
}
- (void)suppressNativeDockPaint {
    UITabBar *bar=_suppressedTabBar;if(!bar || !_dockStates)return;
    // The replacement is outside the native bar. Mask its paint once, including
    // future native children/snapshots, without altering UIKit geometry or alpha.
    [_dockStates conceal:bar];
    [_dockStates reapply];
}
// FIX100 (按下时): WeChat's own tab bar switches as the finger goes down, so
// its page work (the stall) comes before anything moves; the dock asks for the
// same on a touch going to another tab, and the lens glides over the new page.
- (BOOL)dockRequestedTabAtTouchDown:(NSInteger)index {
    if(_dockPresentation!=WXGDockSettled || _nativeTransition || _suspendedByCover || !_route.primary ||
       !WXGPluginEnabled() || !WXGPreferences.shared.dock || !_dockView.userInteractionEnabled)return NO;
    UITabBarController *tabs=_route.tabs;
    if(!tabs || index<0 || index>=(NSInteger)tabs.viewControllers.count || index==(NSInteger)tabs.selectedIndex)return NO;
    // A switch still held for an earlier tap (its lens landing) is not
    // thrown away by a press that may yet be cancelled: that press waits.
    if(_pendingTabIndex>=0)return NO;
    CFTimeInterval now=CACurrentMediaTime();
    _profileUntil=MAX(_profileUntil,now+1.5);
    [self noteVisitedTab:tabs];
    ++_touchDownSwitches;
    [self forwardTabIndex:index];
    if(_touchDownSwitches<=6)WXGLog(@"底栏：按下即切换到第 %ld 个标签（启动后 %.1f s，微信切换 %.0f ms）",(long)index+1,WXGSecondsSinceLoad(),(CACurrentMediaTime()-now)*1000);
    return (NSInteger)tabs.selectedIndex==index;
}
// FIX99/100: the tab WeChat shows now has been shown since launch.
- (void)noteVisitedTab:(UITabBarController *)tabs {
    if(!_visitedTabs)_visitedTabs=[NSMutableIndexSet indexSet];
    if(tabs.selectedIndex<tabs.viewControllers.count)[_visitedTabs addIndex:tabs.selectedIndex];
}
- (void)dockChanged:(WXGDemoBar *)sender {
    if(_dockPresentation!=WXGDockSettled || _nativeTransition || _suspendedByCover || !_route.primary ||
       !WXGPluginEnabled() || !WXGPreferences.shared.dock || !sender.userInteractionEnabled)return;
    UITabBarController *tabs=_route.tabs;NSInteger index=sender.selectedIndex;
    if(!tabs || index<0 || index>=(NSInteger)tabs.viewControllers.count)return;
    CFTimeInterval now=CACurrentMediaTime();
    _profileUntil=MAX(_profileUntil,now+1.5);
    [self noteVisitedTab:tabs];
    // FIX100: the switch WeChat already made at this touch (按下时, the bar
    // says so for this release): nothing more to forward (forwarding again
    // would be a tap on the current tab: to the top, or to the unread).
    if(sender.switchedAtTouchDown && index==(NSInteger)tabs.selectedIndex){_pendingTabIndex=-1;_pendingUntilLanded=NO;_pendingRetaps=0;return;}
    // FIX31: optionally let the lens finish first; WeChat's own switch work
    // then cannot stall the lens animation (tick fires it, see firePending).
    // FIX34: with the render-server animation nothing on the main thread can
    // stall the lens, so the switch is forwarded at once whatever the timing.
    // FIX95: the tap animation is the real lens, frame by frame: WeChat
    // switches once it is down (WeChat's switch and the frames after it block
    // the main thread for 0.1-0.3 s, which would freeze it half way).
    // A tap back on WeChat's own tab before the held switch went: cancelled
    // (nothing to forward: WeChat never left it, so no re-tap either).
    if(_pendingTabIndex>=0 && _pendingUntilLanded && index==(NSInteger)tabs.selectedIndex) {
        _pendingTabIndex=-1;_pendingUntilLanded=NO;_pendingRetaps=0;return;
    }
    BOOL firstVisit=index>=0 && ![_visitedTabs containsIndex:(NSUInteger)index];
    NSInteger moment=firstVisit?2:WXGConfig.shared.dockTapSwitchMoment;   // FIX99
    if([sender holdsTabSwitchAtMoment:moment] && index!=(NSInteger)tabs.selectedIndex) {
        // The same tab tapped again while held: WeChat gets the switch and
        // then that second tap (as without the hold: e.g. 微信 to the unread).
        _pendingRetaps=(_pendingTabIndex==index && _pendingUntilLanded)?1:0;
        _pendingTabIndex=index;_pendingTabSince=now;_pendingUntilLanded=YES;_pendingMoment=moment;return;
    }
    if(WXGConfig.shared.dockSwitchTiming>0 && !sender.travelling && index!=(NSInteger)tabs.selectedIndex) {
        _pendingTabIndex=index;_pendingTabSince=now;_pendingUntilLanded=NO;return;
    }
    // FIX98: the same tab tapped again while its switch was held, and this
    // landing holds nothing (moment 1 with nothing left to move): the switch,
    // then that second tap, as firePendingTabIfReady would.
    BOOL retap=_pendingTabIndex==index && _pendingUntilLanded && index!=(NSInteger)tabs.selectedIndex;
    _pendingTabIndex=-1;_pendingUntilLanded=NO;_pendingRetaps=0;
    [self forwardTabIndex:index];
    if(retap)[self sendSecondTapToIndex:index];
}
- (void)sendSecondTapToIndex:(NSInteger)index {
    __weak WXGIntegrationHost *weakSelf=self;
    dispatch_async(dispatch_get_main_queue(),^{
        WXGIntegrationHost *host=weakSelf;UITabBarController *tabs=host.route.tabs;
        if(!host || !tabs || host.pendingTabIndex>=0 || (NSInteger)tabs.selectedIndex!=index || host.dockView.selectedIndex!=index)return;
        [host forwardTabIndex:index];   // the second tap
    });
}
- (void)firePendingTabIfReady {
    if(_pendingTabIndex<0)return;
    NSInteger timing=WXGConfig.shared.dockSwitchTiming;
    CFTimeInterval waited=CACurrentMediaTime()-_pendingTabSince;
    if(_pendingUntilLanded) {
        // FIX95: once the lens is down (a new touch's glide keeps it waiting;
        // never while a finger is on the dock; 1 s at most otherwise).
        // FIX98: held at most 1.5 s (the lens' clock can run slow under stalls).
        if(([_dockView holdsTabSwitchAtMoment:_pendingMoment] && waited<1.5) || _dockView.tracking)return;
        if(timing>0 && !(timing==1?_dockView.lensArrived:_dockView.lensAtRest) && waited<1.5)return;
    }else {
        BOOL ready=timing==1?_dockView.lensArrived:_dockView.lensAtRest;
        if(!ready && waited<.6)return;
    }
    if(_pendingUntilLanded && ++_landedSwitches<=6)WXGLog(@"底栏：透镜落下后切换到第 %ld 个标签（松手后等了 %.0f ms）",(long)_pendingTabIndex+1,waited*1000);
    NSInteger index=_pendingTabIndex,retaps=_pendingUntilLanded?_pendingRetaps:0;_pendingTabIndex=-1;_pendingUntilLanded=NO;_pendingRetaps=0;
    // Re-check: the route or dock state may have changed while waiting.
    if(_dockPresentation!=WXGDockSettled || _nativeTransition || _suspendedByCover || !_route.primary || !_route.tabs ||
       index>=(NSInteger)_route.tabs.viewControllers.count || _dockView.selectedIndex!=index)return;
    [self forwardTabIndex:index];
    if(retaps>0)[self sendSecondTapToIndex:index];
}
- (void)forwardTabIndex:(NSInteger)index {
    UITabBarController *tabs=_route.tabs;if(!tabs || index<0 || index>=(NSInteger)tabs.viewControllers.count)return;
    NSArray *native=[self nativeTabButtons];
    // FIX99: the dock's lens pauses through the stall that follows; a tab
    // never shown since launch is noted (WeChat loads it now).
    [_dockView noteTabSwitchForwarding];
    if(!_visitedTabs)_visitedTabs=[NSMutableIndexSet indexSet];
    BOOL firstVisit=![_visitedTabs containsIndex:(NSUInteger)index];
    [_visitedTabs addIndex:(NSUInteger)index];
    CFTimeInterval forwardStart=CACurrentMediaTime();
    [self recordForward:@{@"role":@"tab",@"index":@(index),@"nativeBindingAvailable":@(index<(NSInteger)native.count && WXGCanForward(native[index]))}];
    if(index<(NSInteger)native.count && WXGCanForward(native[index])) {
        UIControl *button=native[index];[button sendActionsForControlEvents:UIControlEventTouchDown];
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    }else {
        UIViewController *vc=tabs.viewControllers[index];id<UITabBarControllerDelegate> delegate=tabs.delegate;
        if([delegate respondsToSelector:@selector(tabBarController:shouldSelectViewController:)] && ![delegate tabBarController:tabs shouldSelectViewController:vc])return;
        tabs.selectedViewController=vc;
        if([delegate respondsToSelector:@selector(tabBarController:didSelectViewController:)])[delegate tabBarController:tabs didSelectViewController:vc];
    }
    double switchMS=(CACurrentMediaTime()-forwardStart)*1000;WXGProfileAdd(WXGProfileSwitch,switchMS);
    _lastSwitchAt=CACurrentMediaTime();_profileUntil=MAX(_profileUntil,_lastSwitchAt+1.5);
    [self finishTabTrace];
    if(firstVisit && ++_firstVisitLogs<=4)WXGLog(@"底栏：第 %ld 个标签启动后第一次打开（启动后 %.1f s），微信切换用了 %.0f ms",(long)index+1,WXGSecondsSinceLoad(),switchMS);
    _tabTrace=[@{@"index":@(index),@"t":@(forwardStart),@"wechatSwitchMS":@(switchMS),@"firstVisit":@(firstVisit),@"timing":@(WXGConfig.shared.dockSwitchTiming),
                 @"maxIntervalMS":@0,@"slowFrames":@0,@"frames":@0} mutableCopy];
    // FIX37: build the new page's glass now, in the commit that first shows
    // the page. Scheduled, it ran one run-loop later and the page's own top
    // buttons were visible for a frame or more on every switch.
    if(!_refreshing){_queued=NO;[self refresh];}else [self schedule];
    // FIX100: WeChat's switch and this refresh held the main thread since
    // forwardStart: the dock's running tap animation carries on from there.
    [_dockView tabSwitchForwardedFrom:forwardStart];
}
// FIX22: record every view painting the top of the window (status bar and
// navigation area) at +2 s and +6 s after a cold start, and when a transition
// back to a tab root begins (视频号 return). Classes, frames and colours only.
- (void)scheduleTopPaintCensus {
    _censusScheduled=YES;__weak WXGIntegrationHost *weakSelf=self;
    for(NSNumber *delay in @[@2,@6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            [weakSelf captureTopPaintCensus:[NSString stringWithFormat:@"coldStart+%@s",delay]];
        });
    }
}
- (void)captureTopPaintCensus:(NSString *)label {[self capturePaintCensus:label bottom:NO];}
// FIX27: the same census for the bottom band (what lies under the dock).
- (void)capturePaintCensus:(NSString *)label bottom:(BOOL)bottom {
    UIWindow *w=_window;if(!w)return;
    // Event snapshots are capped; the cold-start ones always land.
    if(![label hasPrefix:@"coldStart"] && _topPaintCensus.count>=20)[_topPaintCensus removeObjectAtIndex:0];
    @try {
        CGFloat limit=MAX(100,w.safeAreaInsets.top+56),bottomEdge=w.bounds.size.height-MAX(120,w.safeAreaInsets.bottom+90);
        NSMutableArray *rows=[NSMutableArray array];
        for(UIView *v in WXGViews(w,2500)) {
            if(v.hidden || v.alpha<.01 || v.layer.opacity<.01 || WXGIsPluginView(v))continue;
            CGRect r=WXGWindowRect(v,w);
            if(bottom?(CGRectGetMaxY(r)<bottomEdge || CGRectGetMinY(r)>=w.bounds.size.height):(CGRectGetMinY(r)>limit || CGRectGetMaxY(r)<=0))continue;
            if(r.size.width<w.bounds.size.width*.5)continue;
            UIColor *bg=[v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection];
            CGFloat red=0,green=0,blue=0,alpha=0;if(bg)[bg getRed:&red green:&green blue:&blue alpha:&alpha];
            BOOL contents=v.layer.contents!=nil,effect=[v isKindOfClass:UIVisualEffectView.class];
            if(alpha<.05 && !contents && !effect)continue;
            BOOL masked=NO;for(UIView *a=v;a && a!=w;a=a.superview)if(a.layer.mask){masked=YES;break;}
            [rows addObject:@{@"class":NSStringFromClass(v.class),@"parent":v.superview?NSStringFromClass(v.superview.class):@"none",
                @"rect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],@"rgba":@[@(red),@(green),@(blue),@(alpha)],
                @"alpha":@(v.alpha),@"contents":@(contents),@"effect":@(effect),@"maskedOrUnderMask":@(masked),
                @"inNavigationBar":@(_route.nav.navigationBar && [v isDescendantOfView:_route.nav.navigationBar]),
                @"inPage":@(_route.leaf.isViewLoaded && [v isDescendantOfView:_route.leaf.view]),
                @"inTabRoot":@(_route.tabs.isViewLoaded && [v isDescendantOfView:_route.tabs.view])}];
            if(rows.count>=40)break;
        }
        if(!_topPaintCensus)_topPaintCensus=[NSMutableArray array];
        [_topPaintCensus addObject:@{@"label":label,@"region":bottom?@"bottom":@"top",@"t":@(CACurrentMediaTime()),
            @"page":_route.leaf?NSStringFromClass(_route.leaf.class):@"none",@"style":@(w.traitCollection.userInterfaceStyle),@"views":rows}];
        if(_topPaintCensus.count>22)[_topPaintCensus removeObjectAtIndex:0];
    } @catch(NSException *error){WXGLog(@"顶部绘制统计异常：%@",error.reason);}
}
// FIX67: WeChat's mini-program panel (pull the chat list down) covers the
// screen and WeChat's own tab bar leaves: the dock row slides down off the
// screen as the panel opens (WXGHomePanelProgressForController, 0 .. 1) and
// takes no touches while it is away. Anywhere else the slide is 0.
- (CGFloat)homePanelDrop {
    if(_homePanel<=0 || !_overlay || !_dockView)return 0;
    CGFloat top=CGRectGetMinY(_dockView.frame)+WXGCanvasPaddingY;
    return _homePanel*MAX(0,CGRectGetHeight(_overlay.bounds)-top+16);
}
- (void)updateHomePanel {
    static Class home;static dispatch_once_t once;
    dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");});
    CGFloat k=0;
    if(_route.primary && home && [_route.leaf isKindOfClass:home] && _dockPresentation==WXGDockSettled && !_nativeTransition && !_suspendedByCover)
        k=WXGHomePanelProgressForController(_route.leaf);
    if(fabs(k-_homePanel)<.002 && (k==0)==(_homePanel==0))return;
    _homePanel=k;
    [self setKeyboardLift:_keyboardLift duration:0 curve:0];
    _dockRow.userInteractionEnabled=k<.01;
    if(k>0)[_dockView cancelInteraction];
}
// FIX92: the title bar's glass stays above the page. Pulling the home list
// down into the mini-program panel, the title and the buttons went under the
// list's fade and blur for a moment, until the next refresh brought the bar
// back to the front. Every frame: the overlay back to the front of its
// container (its layer is drawn above its siblings anyway, zPosition), and
// anything outside the container painted above it over the title bar (that
// the overlay cannot be raised above) is logged, the first few times.
- (void)keepNavigationOnTop {
    UIView *overlay=_navigationOverlay,*owner=overlay.superview;
    if(!owner || overlay.hidden || !_buttons.count || !overlay.window)return;
    UIView *top=owner.subviews.lastObject;
    if(top!=overlay) {
        ++_navigationRaises;
        if(_navigationRaises<=12)WXGLog(@"顶栏：%@ 盖到了顶栏上面，已移回最上层",NSStringFromClass(top.class));
        [owner bringSubviewToFront:overlay];
    }
    if(_suspendedByCover || _nativeTransition)return;   // a sheet or a push is meant to be above
    const CGFloat band=120;   // the title bar's height on screen, about
    if(!_navigationCoverSeen)_navigationCoverSeen=[NSHashTable weakObjectsHashTable];
    UIView *child=owner;
    for(UIView *parent=owner.superview;parent && child!=overlay.window;child=parent,parent=parent.superview) {
        NSArray<UIView *> *siblings=parent.subviews;NSUInteger at=[siblings indexOfObjectIdenticalTo:child];
        if(at==NSNotFound)break;
        for(NSUInteger i=at+1;i<siblings.count;i++) {
            UIView *v=siblings[i];
            if(v.hidden || v.alpha<.01 || WXGIsPluginView(v) || v.layer.zPosition<child.layer.zPosition || [_navigationCoverSeen containsObject:v])continue;
            CGRect r=[v convertRect:v.bounds toView:nil];
            if(CGRectGetMinY(r)>band || CGRectGetMaxY(r)<1 || r.size.width<overlay.bounds.size.width*.5)continue;
            [_navigationCoverSeen addObject:v];[self noteNavigationCover:NSStringFromClass(v.class) in:parent over:child rect:r];
        }
        // FIX93: layers of their own (no view), above the bar's branch too.
        NSArray<CALayer *> *layers=parent.layer.sublayers;NSUInteger layerAt=[layers indexOfObjectIdenticalTo:child.layer];
        for(NSUInteger i=layerAt==NSNotFound?layers.count:layerAt+1;i<layers.count;i++) {
            CALayer *layer=layers[i];
            if([layer.delegate isKindOfClass:UIView.class] || layer.hidden || layer.opacity<.01 || layer.zPosition<child.layer.zPosition || [_navigationCoverSeen containsObject:layer])continue;
            CGRect r=[parent.layer convertRect:layer.frame toLayer:overlay.window.layer];
            if(CGRectGetMinY(r)>band || CGRectGetMaxY(r)<1 || r.size.width<overlay.bounds.size.width*.5)continue;
            [_navigationCoverSeen addObject:layer];[self noteNavigationCover:[@"图层 " stringByAppendingString:NSStringFromClass(layer.class)] in:parent over:child rect:r];
        }
    }
}
- (void)noteNavigationCover:(NSString *)what in:(UIView *)parent over:(UIView *)child rect:(CGRect)r {
    ++_navigationCovers;
    _lastNavigationCover=[NSString stringWithFormat:@"%@ 在 %@ 里，盖在顶栏所在的 %@ 上面（%@）",what,NSStringFromClass(parent.class),NSStringFromClass(child.class),NSStringFromCGRect(r)];
    if(_navigationCovers<=10)WXGLog(@"顶栏：%@",_lastNavigationCover);
}
// FIX94: WeChat's own title bar buttons (the left one hosts the glass) inside
// the home list: pulled down, WeChat moves them into the list's header
// (WAMainFrameTaskBarView, seen in FIX93's trace), where the list's fade
// mask and the blur band over the list covered them.
// Shown there (a hidden or transparent copy left in the header does not count).
static BOOL WXGShownInside(UIView *v,UIView *list) {
    if(!v.window || ![v isDescendantOfView:list])return NO;
    for(UIView *x=v;x && x!=list;x=x.superview)if(x.hidden || x.alpha<.01)return NO;
    return YES;
}
- (BOOL)topBarViewsInList:(UIView *)list {
    for(UIView *v in _homeGestureHosts.allObjects)if(WXGShownInside(v,list))return YES;
    for(WXGSurface *s in _buttons)if(WXGShownInside(s.motionHost?:s.original,list))return YES;
    return NO;
}
// What the edge fade asks: the top fade and blur of this list step aside.
BOOL WXGHomeTopBarInList(UIView *list) {
    WXGIntegrationHost *h=WXGIntegrationHost.shared;
    return list && h.homeTopBarInList && h.homeTopBarList==list;
}
- (void)followHomeTopBar {
    static Class home,table;static dispatch_once_t once;
    dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");table=NSClassFromString(@"MainFrameTableView");});
    UIScrollView *found=nil;
    if(_route.primary && home && [_route.leaf isKindOfClass:home]) {
        for(UIScrollView *scroll in _scrollViews)
            if(scroll.window==_window && (table?[scroll isKindOfClass:table]:scroll.bounds.size.height>_window.bounds.size.height*.5) && [self topBarViewsInList:scroll]){found=scroll;break;}
    }
    // Only while the list is pulled down (or the panel shows) and for a
    // second after it settles (WeChat moves them back with a delay): if a
    // WeChat version kept them in the list at rest, the fade comes back.
    CFTimeInterval now=CACurrentMediaTime();
    if(_homePull>.5 || _homePanel>0)_homeTopBarPulledAt=now;
    BOOL inList=found && now-_homeTopBarPulledAt<1;
    _homeTopBarAtRest=found && !inList;   // diagnostics: WeChat keeps them in the list at rest
    if(inList==_homeTopBarInList && (!inList || found==_homeTopBarList))return;
    UIViewController *page=_homeTopBarPage;
    _homeTopBarInList=inList;_homeTopBarList=inList?found:nil;_homeTopBarPage=inList?_route.leaf:nil;
    if(++_homeTopBarMoves<=6)WXGLog(@"顶栏：微信的顶部按钮%@首页列表（下拉 %.0f pt）%@",found?@"在":@"不在",_homePull,inList?@"，列表顶部的渐隐和模糊让开":@"，恢复渐隐和模糊");
    // The list's top fade and blur step aside / come back now (on the home
    // page they were taken from, also when the change is leaving it).
    WXGEdgeFadeSyncController(_route.leaf);
    if(page && page!=_route.leaf)WXGEdgeFadeSyncController(page);
}
// FIX93: the home list pulled down past its top (the largest list on the page).
- (CGFloat)currentHomePull {
    static Class home;static dispatch_once_t once;
    dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");});
    if(!_route.primary || !home || ![_route.leaf isKindOfClass:home] || !_window)return 0;
    CGFloat pull=0,h=_window.bounds.size.height,w=_window.bounds.size.width;
    for(UIScrollView *scroll in _scrollViews)
        if(scroll.window==_window && scroll.bounds.size.height>h*.5 && scroll.bounds.size.width>w*.8)
            pull=MAX(pull,-(scroll.contentOffset.y+scroll.adjustedContentInset.top));
    return pull;
}
// FIX93: pulling the home list down (toward the mini-program panel), WeChat
// fades its own title bar; the glass followed that opacity (FIX92 kept it on
// top, but faded it showed the page's fade and blur through it). While the
// list is pulled, the title and right buttons stay at full opacity until the
// panel actually opens (then they follow WeChat out).
- (void)updateHomePullFloor {
    _homePull=[self currentHomePull];
    CGFloat floor=_homePull>1?WXGClamp(1-_homePanel,0,1):0;
    for(WXGSurface *surface in _buttons)if(![surface.role isEqual:@"nativeGesture"])surface.alphaFloor=floor;
    for(WXGSurface *surface in _departingButtons)surface.alphaFloor=0;
}
// FIX93: what the title bar does while the home list is pulled (every 0.1 s,
// the last 60 samples): WeChat's opacity of each button's own view, the
// glass's, positions, the navigation bar's; where the native views live.
- (void)followHomePull:(CFTimeInterval)now {
    if(_homePull<=1 && _homePanel<=0)return;
    if(now-_homePullTraceAt<.1)return;
    if(now-_homePullTraceAt>1)_homePullTraceStart=now;   // a new pull
    _homePullTraceAt=now;
    if(!_homePullTrace)_homePullTrace=[NSMutableArray array];
    NSMutableArray *items=[NSMutableArray array];NSMutableArray *hosts=[NSMutableArray array];
    for(WXGSurface *s in _buttons) {
        UIView *host=s.motionHost;
        CGFloat chain=1;BOOL hidden=NO;
        for(UIView *v=host;v && v!=_window;v=v.superview){CALayer *l=v.layer.presentationLayer?:v.layer;chain*=l.opacity;if(l.hidden){hidden=YES;break;}}
        CGRect r=[s convertRect:s.bounds toView:nil];
        [items addObject:@{@"role":s.role?:@"?",@"alpha":@(round(s.alpha*100)/100),@"native":@(round(chain*100)/100),@"nativeHidden":@(hidden),
                           @"y":@(round(CGRectGetMidY(r))),@"hostY":@(round(CGRectGetMidY([host convertRect:host.bounds toView:nil])))}];
        if(chain<.95 && ![s.role isEqual:@"nativeGesture"] && ++_homePullFades<=6)
            WXGLog(@"顶栏：首页下拉 %.0f pt 时微信把 %@ 淡到 %.2f%@（面板 %.2f），玻璃保持 %.2f",_homePull,s.role?:@"?",chain,hidden?@"（隐藏）":@"",_homePanel,s.alpha);
        NSMutableArray *chainNames=[NSMutableArray array];
        for(UIView *v=host;v && chainNames.count<8;v=v.superview)[chainNames addObject:NSStringFromClass(v.class)];
        [hosts addObject:@{@"role":s.role?:@"?",@"chain":chainNames}];
    }
    UINavigationBar *bar=_route.nav.navigationBar;
    [_homePullTrace addObject:@{@"t":@(round((now-_homePullTraceStart)*100)/100),@"pull":@(round(_homePull)),@"panel":@(round(_homePanel*100)/100),
        @"bar":@{@"alpha":@(round(bar.alpha*100)/100),@"hidden":@(bar.hidden),@"y":@(round(CGRectGetMinY([bar convertRect:bar.bounds toView:nil])))},@"buttons":items}];
    if(_homePullTrace.count>60)[_homePullTrace removeObjectAtIndex:0];
    _homePullHosts=hosts;
}
// FIX27: once per scroll view, when a page is pulled down past its top by
// 40 pt (Moments, home), record what paints the top at that moment.
- (void)capturePullDownCensus {
    if(!_pullCensusScrolls)_pullCensusScrolls=[NSHashTable weakObjectsHashTable];
    for(UIScrollView *scroll in _scrollViews) {
        if(!scroll.window || [_pullCensusScrolls containsObject:scroll])continue;
        if(scroll.contentOffset.y+scroll.adjustedContentInset.top<-40) {
            [_pullCensusScrolls addObject:scroll];
            [self capturePaintCensus:[@"pullDown:" stringByAppendingString:_route.leaf?NSStringFromClass(_route.leaf.class):@"none"] bottom:NO];
        }
    }
}
// FIX30: the first switch to a tab paid for WeChat creating that page (one
// first switch measured 218 ms of native work). After launch, when nothing is
// animating, load and lay out each not-yet-loaded tab root off-screen, one per
// 0.4 s. viewWillAppear and friends still run at the real switch.
- (void)prewarmTabPagesFrom:(NSUInteger)index {
    if(index==0)[_dockView prewarmTravel];
    UITabBarController *tabs=_route.tabs;if(!tabs || index>=tabs.viewControllers.count)return;
    __weak WXGIntegrationHost *weakSelf=self;
    BOOL busy=_nativeTransition!=nil || _dockView.tracking || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    if(busy) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.6*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf prewarmTabPagesFrom:index];});
        return;
    }
    UIViewController *tab=tabs.viewControllers[index];
    UIViewController *root=[tab isKindOfClass:UINavigationController.class]?((UINavigationController *)tab).viewControllers.firstObject:tab;
    if(tab!=tabs.selectedViewController && root && !root.isViewLoaded) {
        CFTimeInterval start=CACurrentMediaTime();
        @try {
            [tab loadViewIfNeeded];[root loadViewIfNeeded];
            root.view.frame=tabs.view.bounds;[root.view setNeedsLayout];[root.view layoutIfNeeded];
            if(!_prewarmed)_prewarmed=[NSMutableArray array];
            [_prewarmed addObject:[NSString stringWithFormat:@"%@ %.1fms",NSStringFromClass(root.class),(CACurrentMediaTime()-start)*1000]];
        } @catch(NSException *error){WXGLog(@"标签页预载：%@",error.reason);}
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf prewarmTabPagesFrom:index+1];});
}
// FIX31: one record per display interval while a dock tap is in progress
// (touch-down to 1.5 s after the last switch). Slow frames keep a breakdown:
// how long the main thread slept, our tick (with the dock, overlay draws,
// backdrop setup, mesh builds and cleanups inside it), our refresh, WeChat's
// switch call, and the rest of the busy time, which is not our code.
- (void)profileFrame:(CADisplayLink *)link now:(CFTimeInterval)now {
    if(_dockView.tracking || _pendingTabIndex>=0)_profileUntil=MAX(_profileUntil,now+1.5);
    BOOL inWindow=now<_profileUntil;
    if(inWindow && !_profileActive){_profileActive=YES;_profileStart=now;++_profileWindows;}
    if(_profileActive && _lastTickTime>0) {
        double interval=_lastTickTime*1000,idle=WXGIdleTotal*1000,frame=(link.targetTimestamp-link.timestamp)*1000;
        if(frame<=1)frame=1000./60;
        ++_profileFrames;
        if(interval>frame*1.5) {
            ++_profileSlowFrames;
            double ours=WXGProfileTotals[WXGProfileTick]+WXGProfileTotals[WXGProfileRefresh]+WXGProfileTotals[WXGProfileSwitch]+WXGProfileTotals[WXGProfileHooks];
            double commit=WXGProfileTotals[WXGProfileCommit];   // FIX101
            double busy=MAX(0,interval-idle);
            NSString *phase=_dockView.tracking?@"touching":_pendingTabIndex>=0?@"waitingToSwitch":
                (now-_lastSwitchAt<1.5?@"afterSwitch":@"settling");
            NSDictionary *record=@{@"atMS":@(round((now-_profileStart)*1000)),@"phase":phase,@"intervalMS":@(round(interval*10)/10),
                @"idleMS":@(round(idle*10)/10),@"busyMS":@(round(busy*10)/10),@"otherMS":@(round(MAX(0,busy-ours-commit)*10)/10),
                @"commitMS":@(round(commit*10)/10),@"hooksMS":@(round(WXGProfileTotals[WXGProfileHooks]*10)/10),
                @"tickMS":@(round(WXGProfileTotals[WXGProfileTick]*10)/10),@"dockMS":@(round(WXGProfileTotals[WXGProfileDock]*10)/10),
                @"drawMS":@(round(WXGProfileTotals[WXGProfileDraw]*10)/10),@"syncMS":@(round(WXGProfileTotals[WXGProfileSync]*10)/10),
                @"meshMS":@(round(WXGProfileTotals[WXGProfileMesh]*10)/10),@"meshBuilds":@(WXGProfileMeshBuilds),
                @"cleanupMS":@(round(WXGProfileTotals[WXGProfileCleanup]*10)/10),@"refreshMS":@(round(WXGProfileTotals[WXGProfileRefresh]*10)/10),
                @"switchMS":@(round(WXGProfileTotals[WXGProfileSwitch]*10)/10)};
            if(!_profileWorst)_profileWorst=[NSMutableArray array];
            [_profileWorst addObject:record];
            [_profileWorst sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"intervalMS"] compare:a[@"intervalMS"]];}];
            if(_profileWorst.count>16)[_profileWorst removeLastObject];
        }
    }
    if(_profileActive && !inWindow)_profileActive=NO;
    for(NSInteger i=0;i<WXGProfileSlotCount;i++)WXGProfileTotals[i]=0;
    WXGProfileMeshBuilds=0;WXGIdleTotal=0;
}
- (void)finishTabTrace {
    if(!_tabTrace)return;
    if(!_tabTraces)_tabTraces=[NSMutableArray array];
    [_tabTraces addObject:_tabTrace.copy];if(_tabTraces.count>6)[_tabTraces removeObjectAtIndex:0];
    _tabTrace=nil;
}
// FIX35: only a fallback when WeChat's Settings has no entry row; holding the
// lens to slide must never open settings.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if(recognizer==_dockLongPress)return !WXGSettingsEntryReady && _dockView.restingOnSelectedTab;
    return YES;
}
- (void)dockLongPress:(UILongPressGestureRecognizer *)g {
    if(WXGSettingsEntryReady || g.state!=UIGestureRecognizerStateBegan)return;
    [_dockView cancelInteraction];[self presentSettings];
}
- (void)refresh {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(WXGNavigationCallDepth){++_navigationSetupDeferrals;[self schedule];return;}
    if(_refreshing)return;_refreshing=YES;_lastRefresh=CACurrentMediaTime();++_refreshes;++WXGHostTimedDepth;
    @try {
        UIApplicationState appState=UIApplication.sharedApplication.applicationState;
        if(_inputRepairsSuspended || appState==UIApplicationStateBackground || (appState!=UIApplicationStateActive && _hasBeenActive)){_displayLink.paused=YES;return;}
        if(CACurrentMediaTime()-_lastParameters>1.2){_lastParameters=CACurrentMediaTime();if([WXGConfig.shared reloadSharedParameters]){_dockStyleKey=nil;_navigationDirty=YES;}}
        CFTimeInterval stepMark=CACurrentMediaTime();NSMutableDictionary *steps=[NSMutableDictionary dictionary];
        UIWindow *w=[self contentWindow];if(!w)return;
        WXGRoute *r=WXGRouteForWindow(w);
        // FIX106 I: WeChat's bar and edge swipe back as they were once no
        // plugin settings page is left in this navigation (a safety net; the
        // pages themselves give them back as they leave).
        if(r.nav && WXGSettingsReleaseStaleNavigation(r.nav))_navigationDirty=YES;
        steps[@"routeMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        // FIX67: back from a presented chat to the page that presented it
        // (WeChat's search): that chat's glass goes, the page stays native.
        if(r.presented && WXGPluginEnabled() && _route && !_route.presentedStack) {
            if(!_suspendedByCover){_dockView.userInteractionEnabled=NO;_searchView.userInteractionEnabled=NO;[_dockView cancelInteraction];}
            _suspendedByCover=YES;
            // Keep the retained scene's optical pixels live while a sheet
            // scales/moves it. Only native adaptation and touches are suspended.
            WXGConfigureDisplayLink(_displayLink,w.screen);
            _displayLink.paused=appState!=UIApplicationStateActive;return;
        }
        if(_suspendedByCover){_suspendedByCover=NO;_lastFrame=0;_navigationDirty=YES;}

        [self observeTransition:r.nav.transitionCoordinator];
        if(_nativeTransition && _transitionTo.isViewLoaded && _transitionTo.view.window==w) {
            r.leaf=_transitionTo;r.chat=[NSStringFromClass(r.leaf.class) isEqual:@"BaseMsgContentViewController"];
            r.primary=r.tabs && r.leaf==r.nav.viewControllers.firstObject;
        }
        BOOL switching=_window!=w || _route.leaf!=r.leaf;
        _preserveDockDuringReset=_window==w && (_route.primary || r.primary || _nativeTransition) && _route.tabs==r.tabs && WXGPluginEnabled() && WXGPreferences.shared.dock;
        if(switching && _nativeTransition && _route.leaf==_transitionFrom && r.leaf==_transitionTo) {
            _departingButtons=_buttons.copy;_departingInput=_inputAdapter;[_departingInput setSuspended:YES];
            for(WXGSurface *surface in _departingInput.surfaces)surface.active=!surface.hidden && surface.window!=nil;
            [_buttons removeAllObjects];_routeToken=nil;_pageViews=nil;_lastTreeScan=0;_navigationDirty=YES;
            WXGInvalidateSharedBackdrop();
        }else if(switching){[self resetRoute];_navigationDirty=YES;}
        steps[@"transitionAndResetMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        WXGConfigureDisplayLink(_displayLink,w.screen);_window=w;_route=r;[self selectPage:r.leaf];[self ensureOverlay:w];
        [self matchPageAppearance:r];
        steps[@"selectPageMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        WXGDecorations.shared.source=r.leaf.view;
        WXGPreferences *p=WXGPreferences.shared;
        // FIX59: only for the accounts this build is made for (WXGLicense.m).
        if(r.tabs)WXGLicenseNoteMainInterface();
        BOOL licensed=WXGLicenseCurrentState(NO)==WXGLicenseAuthorized;
        BOOL available=p.enabled && licensed && !r.unsupported && !_settings.presentingViewController;
        // FIX60: the chat list's search bar comes back only when the plugin is off here.
        if(!p.enabled || !licensed){[self restoreTopSearch];[WXGBubbles.shared restore];}
        // FIX73: an unsupported destination (this plugin's own settings, a
        // Flutter / web page) pauses the display link below, so the buttons of
        // the page being left froze where they were, on top of the new page's
        // own buttons, until UIKit finished the transition. They go at once;
        // the page being left shows its native buttons while it slides out.
        if(!available)[self dropDepartingButtons];
        if(!available){[self resetRoute];[_inputAdapter restore];[WXGDecorations.shared restore];
            // FIX105: 未授权（含验证中、未读到账号）时整块撤出插件的图层，而不只是隐藏
            // 效果——overlay 从视图树移走、悬浮入口藏起，微信任何地方都看不出装过插件。
            // 只针对本来就没授权的账号；被踢的账号手机里还有有效票据，冷启动会先凭票据
            // 显示玻璃、等服务器回 403 再撤掉，那一下是踢人生效，不在这里处理。
            if(!licensed)[self detachOverlays];
            _status=!p.enabled?@"已关闭，原生界面已恢复":!licensed?@"当前账号未授权、尚未读到或正在联网验证，保留原生界面":r.unsupported?@"Flutter/Web/模态页面保留原生界面":@"等待导航转场完成";_displayLink.paused=YES;return;}
        // FIX101: the parts of this step timed apart (a tab switch after a
        // chat spent 94 ms in it on the tester's phone, cause unknown).
        steps[@"gateMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        if(_appearanceStyle!=w.traitCollection.userInterfaceStyle) {
            _appearanceStyle=w.traitCollection.userInterfaceStyle;_dockStyleKey=nil;_navigationDirty=YES;
            for(WXGSurface *surface in _buttons)[surface applyConfig];
            for(WXGSurface *surface in _inputAdapter.surfaces)[surface applyConfig];
        }
        if(_displayLink.paused){_lastFrame=0;_frameStart=CACurrentMediaTime();_frames=_slowFrames=0;}_displayLink.paused=appState!=UIApplicationStateActive;
        steps[@"appearanceMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        NSString *token=[NSString stringWithFormat:@"%p:%ld:%.0fx%.0f:%d%d%d%d%d%d%d%d",r.leaf,(long)r.tabs.selectedIndex,w.bounds.size.width,w.bounds.size.height,p.nav,p.dock,p.input,p.avatarTitle,p.homeSearch,
            p.dockSearch,p.dockSearchLeading,p.hideTopSearch];
        if(![_routeToken isEqual:token]){if(!_nativeTransition)[self resetRoute];_routeToken=token;_navigationDirty=YES;}
        steps[@"routeTokenMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        if(!_pageViews || CACurrentMediaTime()-_lastTreeScan>.75) {
            _lastTreeScan=CACurrentMediaTime();_pageViews=WXGViews(r.leaf.view,900);[_scrollViews removeAllObjects];
            steps[@"treeScanMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
            // FIX30: only the four decoration host classes need the call; the
            // hosts are also hooked directly, this pass is only a fallback.
            // FIX60: the classes themselves (exact class, as the names were).
            static NSSet *hosts;static dispatch_once_t once;
            dispatch_once(&once,^{
                NSMutableSet *classes=[NSMutableSet set];
                for(NSString *name in @[@"MMMsgCommonTipsView",@"MMMsgTipsMixedListExpandView",@"MainFrameActionFloatView",@"MMMenuContentView"]) {
                    Class cls=NSClassFromString(name);if(cls)[classes addObject:cls];
                }
                hosts=classes;
            });
            for(UIView *v in _pageViews) {
                if([v isKindOfClass:UIScrollView.class])[_scrollViews addObject:(id)v];
                if([hosts containsObject:v.class])[WXGDecorations.shared nativeHostLaidOut:v];
            }
            steps[@"hostsMS"]=@((CACurrentMediaTime()-stepMark)*1000);
        }
        CFTimeInterval phaseMark=CACurrentMediaTime();NSMutableDictionary *phases=[NSMutableDictionary dictionary];
        phases[@"routeAndTreeMS"]=@((phaseMark-_lastRefresh)*1000);phases[@"routeSteps"]=steps;
        if(r.chat && p.input){[_inputAdapter installInController:r.leaf window:w];[self layoutInput];}
        phases[@"inputMS"]=@((CACurrentMediaTime()-phaseMark)*1000);phaseMark=CACurrentMediaTime();
        if(r.chat && !_navigationDirty) {
            NSString *current=[self fullTitleFromView:r.leaf.navigationItem.titleView fallback:r.leaf.navigationItem.title?:r.leaf.title];
            for(WXGSurface *surface in _buttons)if([surface.role isEqual:@"chatTitle"] && ![surface.label.text?:@"" isEqual:current?:@""]){_navigationDirty=YES;break;}
        }
        if(p.nav && (_navigationDirty || switching)){[self buildNavigation];_navigationDirty=NO;phases[@"buildNavigation"]=@YES;}
        // FIX21: WeChat can repaint or add bar-background views after our
        // build (finishing cold start, re-showing a bar hidden by 视频号). Re-run
        // the bar-only paint cleanup about once a second, not only on route changes.
        else if(p.nav && _route.nav && CACurrentMediaTime()-_lastPaintScan>.9){[self clearNavigationPaint];++_navigationPaintRescans;}
        phases[@"navigationMS"]=@((CACurrentMediaTime()-phaseMark)*1000);phaseMark=CACurrentMediaTime();
        if(p.dock && r.primary)[self buildDock];
        else {
            [self applyDockPresentation:WXGDockPresentationForState(p.dock,NO,_nativeTransition!=nil,_dockTransitionToRoot)];
            if(!WXGPluginEnabled() || !p.dock){WXGRestoreDockTouchDelegates(_suppressedTabBar);[_dockStates restore];_dockStates=nil;_suppressedTabBar=nil;
                [_snapshotStates restore];_snapshotStates=nil;[_snapshotViews removeAllObjects];}
        }
        // FIX60: the chat list's own search bar, and a search handed to WeChat.
        [self updateTopSearchHiding];
        [self continueSearchHandoff];
        phases[@"dockMS"]=@((CACurrentMediaTime()-phaseMark)*1000);phaseMark=CACurrentMediaTime();
        [WXGDecorations.shared refresh];
        phases[@"decorationsMS"]=@((CACurrentMediaTime()-phaseMark)*1000);phaseMark=CACurrentMediaTime();
        [self primeNewSurfaces];
        phases[@"primeMS"]=@((CACurrentMediaTime()-phaseMark)*1000);
        double total=(CACurrentMediaTime()-_lastRefresh)*1000;phases[@"totalMS"]=@(total);phases[@"switching"]=@(switching);
        if(total>8)_lastSlowRefreshPhases=phases;
        if(_tabTrace && !_tabTrace[@"refresh"])_tabTrace[@"refresh"]=phases;
        if(r.primary && !_censusScheduled)[self scheduleTopPaintCensus];
        // FIX38: a pending controller outlives no transition.
        if(_pendingController && !_nativeTransition && !_route.nav.transitionCoordinator){_pendingController=nil;_needsEarlyLayout=NO;++_stalePendingClears;}
        if(CACurrentMediaTime()-WXGLoadTime<30) {
            NSString *icons=[_dockView.nativeIconSummary componentsSeparatedByString:@"\n"].firstObject?:@"-";
            NSMutableArray<NSString *> *roles=[NSMutableArray array];
            for(WXGSurface *surface in _buttons)[roles addObject:[NSString stringWithFormat:@"%@%@",surface.role?:@"?",surface.glass.ready?@"":@"(未就绪)"]];
            NSString *summary=[NSString stringWithFormat:@"页面 %@ | 导航玻璃 %lu [%@] 修复 %lu | 底栏玻璃 就绪 %d 首帧 %d 外观 %@ | %@",
                r.leaf?NSStringFromClass(r.leaf.class):@"none",(unsigned long)_buttons.count,[roles componentsJoinedByString:@","],
                (unsigned long)_bindingRecoveries,_dockView.glass.ready,_dockView.glass.hasPresentedFrame,
                _dockView.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?@"深色":@"浅色",icons];
            if(![summary isEqual:WXGLastColdSummary]){WXGLastColdSummary=summary;WXGColdLog(summary);}
        }
        if(r.primary && r.tabs && !_prewarmScheduled) {
            _prewarmScheduled=YES;__weak WXGIntegrationHost *weakSelf=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf prewarmTabPagesFrom:0];});
        }
        // FIX27: a page that is not a tab root (chat settings, Moments...) gets
        // one top census 0.4 s after it becomes the route.
        if(switching && !r.primary && r.leaf) {
            __weak WXGIntegrationHost *weakSelf=self;NSString *page=NSStringFromClass(r.leaf.class);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                [weakSelf capturePaintCensus:[@"settled:" stringByAppendingString:page] bottom:NO];
            });
        }
        _status=r.chat?@"聊天：浮动导航与原生编辑器适配":r.primary?@"主页：图标居中与真实浮动标签栏":@"原生页面：导航按钮按内容适配";
        // Detailed pixel diagnostics are collected only on explicit export.
        // No periodic renderInContext/text bitmap evidence on the UI hot path.
    }@catch(NSException *e){WXGLog(@"适配异常，恢复原控件：%@",e.reason);[self resetRoute];_status=e.reason;}
    @finally {--WXGHostTimedDepth;_refreshCost=(CACurrentMediaTime()-_lastRefresh)*1000;WXGProfileAdd(WXGProfileRefresh,_refreshCost);_refreshing=NO;_preserveDockDuringReset=NO;}
}
- (void)dropPendingFrame {
    if(_backdropFramePending)++_droppedPendingFrames;
    _backdropFramePending=NO;_pendingBackdropViews=nil;WXGDropDeferredGlassTicks();
}
// Runs the queued backdrop read and every queued glass draw for one display
// callback. `fallback` is the next callback finding the previous frame still
// queued (no BeforeWaiting in between); it then runs inline, as FIX15 did.
- (void)flushPendingFrame:(BOOL)fallback {
    if(!_backdropFramePending && !WXGDeferredGlassTickCount())return;
    if(WXGBackdropCaptureInProgress())return;
    BOOL hadFrame=_backdropFramePending;
    NSArray<WXGGlassView *> *views=_pendingBackdropViews?:@[];
    _backdropFramePending=NO;_pendingBackdropViews=nil;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || _inputRepairsSuspended){WXGDropDeferredGlassTicks();return;}
    CFTimeInterval begin=CACurrentMediaTime();
    if(hadFrame) {
        if(fallback)++_postCommitFallbacks;else ++_postCommitFrames;
        _postCommitDelayMS=MAX(0,begin-_pendingBackdropTime)*1000;
        // Complete this frame's UIKit layout now (the commit would do the same
        // a moment later), so the model tree read below is final.
        if(!fallback) {
            NSMutableSet<UIWindow *> *windows=[NSMutableSet set];
            for(WXGGlassView *glass in views)if(glass.window)[windows addObject:glass.window];
            @try {for(UIWindow *window in windows)[window layoutIfNeeded];}
            @catch(NSException *e){WXGLog(@"提交前布局异常：%@",e.reason);}
        }
        WXGBackdropSetFrameTiming(_pendingTargetTime,_pendingInteractive,_pendingTransition);
        @try {WXGBeginBackdropFrame(views,_pendingBackdropMoving,_pendingBackdropTime);}
        @catch(NSException *e){WXGLog(@"背景读取异常：%@",e.reason);}
    }
    _backdropCost=(CACurrentMediaTime()-begin)*1000;
    CFTimeInterval drawStart=CACurrentMediaTime();
    @try {WXGFlushDeferredGlassTicks();}
    @catch(NSException *e){WXGLog(@"玻璃绘制异常：%@",e.reason);WXGDropDeferredGlassTicks();}
    _drawCost=(CACurrentMediaTime()-drawStart)*1000;
    _postCommitCost=(CACurrentMediaTime()-begin)*1000;_maxPostCommitCost=MAX(_maxPostCommitCost,_postCommitCost);
    if(_tabTrace && _postCommitCost>[_tabTrace[@"maxFlushMS"] doubleValue])_tabTrace[@"maxFlushMS"]=@(_postCommitCost);
}
- (void)tick:(CADisplayLink *)link {
    if(_backdropFramePending || WXGDeferredGlassTickCount())[self flushPendingFrame:YES];
    if(_inputRepairsSuspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self dropPendingFrame];return;}
    // Overflow from native layout hooks is one pending repair. Reset only at
    // an actual display callback, not a wall-time timeout inside a CA loop.
    WXGInputRepairNextFrame(&_inputRepairGate);
    CFTimeInterval begin=CACurrentMediaTime();_lastTickTime=_lastFrame?link.timestamp-_lastFrame:0;
    ++WXGHostTimedDepth;
    @try {[self tickBody:link begin:begin];}
    @finally {--WXGHostTimedDepth;}
}
- (void)tickBody:(CADisplayLink *)link begin:(CFTimeInterval)begin {
    if(_tabTrace) {
        if(begin-[_tabTrace[@"t"] doubleValue]>1.5)[self finishTabTrace];
        else if(_lastTickTime>0) {
            double ms=_lastTickTime*1000;
            _tabTrace[@"frames"]=@([_tabTrace[@"frames"] integerValue]+1);
            if(ms>25)_tabTrace[@"slowFrames"]=@([_tabTrace[@"slowFrames"] integerValue]+1);
            if(ms>[_tabTrace[@"maxIntervalMS"] doubleValue])_tabTrace[@"maxIntervalMS"]=@(ms);
        }
    }
    if(_lastFrame && link.timestamp-_lastFrame>1./40)++_slowFrames;
    [self profileFrame:link now:begin];
    _lastFrame=link.timestamp;++_frames;
    if(_suspendedByCover)++_coveredRenderFrames;
    BOOL moving=NO;
    for(UIScrollView *scroll in _scrollViews) {
        NSValue *previous=[_scrollOffsets objectForKey:scroll];
        if(scroll.dragging || scroll.decelerating || (previous && !CGPointEqualToPoint(previous.CGPointValue,scroll.contentOffset)))moving=YES;
        [_scrollOffsets setObject:[NSValue valueWithCGPoint:scroll.contentOffset] forKey:scroll];
    }
    if(!_suspendedByCover) {
        [self repairDetachedNavigationBindings];
        [self flushInputRepair];
        [self followHomeSurfaces];[_dockStates reapply];[_navStates reapply];
        if(_nativeTransition && WXGPluginEnabled() && WXGPreferences.shared.input)
            [_departingInput reapplyPaint];
    }
    for(WXGSurface *surface in _departingButtons){surface.nativeTransitionActive=_nativeTransition!=nil;[surface followNativePresentation];}
    [self updateHomePullFloor];   // FIX93: before the glass follows WeChat's title bar
    [self followHomeTopBar];      // FIX94
    for(WXGSurface *surface in _buttons){surface.nativeTransitionActive=_nativeTransition!=nil;[surface followNativePresentation];}
    if(_nativeTransition || _suspendedByCover)moving=YES;
    NSMutableArray *glass=[NSMutableArray array];
    [self followHomePull:begin];   // FIX93: after followNativePresentation read the native state
    NSArray<WXGSurface *> *decorations=[WXGDecorations.shared visibleSurfaces];
    NSArray *navigation=[_buttons arrayByAddingObjectsFromArray:_departingButtons?:@[]];
    for(WXGSurface *surface in [navigation arrayByAddingObjectsFromArray:decorations])if(surface.active && !surface.plain && !surface.hidden && surface.alpha>.001){[surface layoutIfNeeded];[surface.glass layoutIfNeeded];[glass addObject:surface.glass];}
    NSArray *inputs=[_inputAdapter.surfaces arrayByAddingObjectsFromArray:_departingInput.surfaces?:@[]];
    for(WXGSurface *surface in inputs)if(surface.active && !surface.plain){[surface layoutIfNeeded];[surface.glass layoutIfNeeded];[glass addObject:surface.glass];}
    if(_dockView.active && !_dockView.hidden) {
        [_dockView layoutIfNeeded];
        for(WXGGlassView *view in _dockView.renderGlasses){[view layoutIfNeeded];[glass addObject:view];}   // 离散底栏: the pieces' glass
    }
    for(WXGGlassView *view in glass)if(view.pressAmount>.001)moving=YES;
    for(WXGGlassView *view in glass)view.backgroundMoving=moving;
    // FIX16: geometry (springs, frames, content transforms) is applied now so
    // it is part of this pass's commit. The scene read and all glass GPU work
    // are queued and run by the post-commit observer, against committed
    // presentation state. If no observer runs, the next callback flushes.
    // FIX27: render-server (同步) glass reads nothing from this process. No
    // queued frame, no deferred ticks, no pre-commit layout: surfaces tick
    // here and present with this pass's transaction.
    BOOL readback=WXGEffectiveRenderMode()<2;
    if(!readback) {
        @try {
            for(WXGSurface *surface in _buttons)[surface tick:link.timestamp];
            for(WXGSurface *surface in _departingButtons)[surface tick:link.timestamp];
            for(WXGSurface *surface in inputs)[surface tick:link.timestamp];
            for(WXGSurface *surface in decorations)[surface tick:link.timestamp];
            [WXGBubbles.shared tick:link.timestamp];   // FIX82
            CFTimeInterval dockStart=CACurrentMediaTime();
            [self stepDockSearch:link.timestamp];   // FIX60: before the dock, same frame
            if(_dockView.active)[_dockView tick:link];
            WXGProfileAdd(WXGProfileDock,(CACurrentMediaTime()-dockStart)*1000);
            [self firePendingTabIfReady];
        }@finally {}
        CFTimeInterval cleanupStart=CACurrentMediaTime();
        [self concealTransitionSnapshots];
        [self capturePullDownCensus];
        [self updateHomePanel];
        [self keepNavigationOnTop];   // FIX92
        // FIX37: right after launch WeChat lays its top buttons out late; until
        // a tab root has its navigation glass, retry every 0.1 s.
        if(!_buttons.count && _route.primary && _route.leaf && !_nativeTransition && WXGPreferences.shared.nav &&
           begin-WXGLoadTime<15 && begin-_lastColdNavAttempt>.1) {
            _lastColdNavAttempt=begin;[self nativeNavigationLaidOut];
        }
        if(moving && _navStates && begin-_lastTopPaintScan>.25 && WXGPreferences.shared.nav) {
            _lastTopPaintScan=begin;
            @try {[self clearPageTopPaint:_route.leaf.isViewLoaded?_route.leaf.view:nil];[_navStates reapply];}
            @catch(NSException *error){WXGLog(@"顶部背景清理：%@",error.reason);}
        }
        WXGProfileAdd(WXGProfileCleanup,(CACurrentMediaTime()-cleanupStart)*1000);
        _tickCost=(CACurrentMediaTime()-begin)*1000;_maxTickCost=MAX(_maxTickCost,_tickCost);
        WXGProfileAdd(WXGProfileTick,_tickCost);
        return;
    }
    _pendingBackdropViews=glass;_pendingBackdropMoving=moving;_pendingBackdropTime=link.timestamp;_backdropFramePending=YES;
    _pendingTargetTime=link.targetTimestamp;_pendingTransition=_nativeTransition!=nil;
    _pendingInteractive=_nativeTransition!=nil && _nativeTransition.isInteractive;
    if(!_commitObserver) {
        _backdropFramePending=NO;_pendingBackdropViews=nil;
        WXGBackdropSetFrameTiming(_pendingTargetTime,_pendingInteractive,_pendingTransition);
        WXGBeginBackdropFrame(glass,moving,link.timestamp);
    }
    else WXGBeginDeferredGlassTicks();
    @try {
        for(WXGSurface *surface in _buttons)[surface tick:link.timestamp];
        for(WXGSurface *surface in _departingButtons)[surface tick:link.timestamp];
        for(WXGSurface *surface in inputs)[surface tick:link.timestamp];
        for(WXGSurface *surface in decorations)[surface tick:link.timestamp];
        [self stepDockSearch:link.timestamp];
        if(_dockView.active)[_dockView tick:link];
        [self firePendingTabIfReady];   // FIX95: the tap's held switch, in this mode too
    }@finally {if(_commitObserver)WXGEndDeferredGlassTicks();}
    _tickCost=(CACurrentMediaTime()-begin)*1000;_maxTickCost=MAX(_maxTickCost,_tickCost);
    WXGPerfNotePluginWork(_tickCost);   // FIX84: readback mode (no CABackdropLayer)
}
- (void)layoutInput {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self layoutInput];});return;}
    if(_inputRepairsSuspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || _suspendedByCover){++_inputInactiveSkips;return;}
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(!WXGPluginEnabled() || !WXGPreferences.shared.input || (!_route.chat && !_departingInput))return;
    ++_inputRepairRequests;WXGInputRepairRequest(&_inputRepairGate);
    [self flushInputRepair];
}
- (void)flushInputRepair {
    if(!_inputRepairGate.pending)return;
    if(_inputRepairsSuspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || _suspendedByCover)return;
    BOOL eligible=!_refreshing && !WXGNativeInputLayoutInProgress() && !WXGNavigationCallDepth && !WXGBackdropCaptureInProgress();
    if(!WXGInputRepairTryBegin(&_inputRepairGate,eligible)){++_inputRepairDeferrals;return;}
    CFTimeInterval begin=CACurrentMediaTime();++_inputRepairPasses;
    @try {
        if(WXGPluginEnabled() && WXGPreferences.shared.input) {
            // Guard departing paint too: it can cause native layout callbacks.
            if(_nativeTransition)[_departingInput reapplyPaint];
            if(_route.chat){if(_inputAdapter.installed)[_inputAdapter layout];else [self schedule];}
        }
    } @finally {
        _inputRepairMS=(CACurrentMediaTime()-begin)*1000;_maxInputRepairMS=MAX(_maxInputRepairMS,_inputRepairMS);
        WXGInputRepairEnd(&_inputRepairGate);
    }
}
- (void)presentSettings {
    if(_settings.presentingViewController)return;
    UIViewController *presenter=_route.leaf?:_window.rootViewController;
    while(presenter.presentedViewController)presenter=presenter.presentedViewController;
    if(!presenter)return;
    _lastSceneEvidence=self.evidence;[_sceneHistory addObject:_lastSceneEvidence];if(_sceneHistory.count>120)[_sceneHistory removeObjectAtIndex:0];
    [self closeDockSearchAnimated:NO];   // FIX60: no keyboard over the settings
    _suspendedByCover=YES;_dockView.userInteractionEnabled=NO;_searchView.userInteractionEnabled=NO;[_dockView cancelInteraction];
    _displayLink.paused=_inputRepairsSuspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:WXGIntegrationSettings()];
    _settings=nav;[presenter presentViewController:nav animated:YES completion:^{nav.presentationController.delegate=self;}];
}
- (NSString *)versionString {return @"0.4.105 · TEST4 FIX105";}
- (void)openSettingsFrom:(UIViewController *)controller {
    UINavigationController *nav=controller.navigationController;
    if(nav){[nav pushViewController:WXGIntegrationSettings() animated:YES];return;}
    [self presentSettings];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)p {(void)p;_settings=nil;[self schedule];}
- (NSDictionary *)runtimeMetrics {
    NSMutableArray *bindings=[NSMutableArray array];
    for(WXGSurface *surface in [_buttons arrayByAddingObjectsFromArray:_departingButtons?:@[]])if(bindings.count<16) {
        UIView *host=surface.motionHost;
        [bindings addObject:@{@"role":surface.role?:@"",@"surface":[NSString stringWithFormat:@"%p",surface],
          @"hostClass":host?NSStringFromClass(host.class):@"none",@"host":[NSString stringWithFormat:@"%p",host],
          @"ownerID":[NSString stringWithFormat:@"%p",surface.motionOwner],@"glassBounds":NSStringFromCGRect(surface.glass.bounds),@"presentedFrame":@(surface.glass.hasPresentedFrame),
          @"owner":surface.motionOwner?NSStringFromClass(surface.motionOwner.class):@"none",@"frame":NSStringFromCGRect(surface.frame),
          @"material":NSStringFromCGRect(surface.materialRect),@"alpha":@(surface.alpha),@"hidden":@(surface.hidden),@"active":@(surface.active),
          @"hostFrame":NSStringFromCGRect(WXGWindowRect(host,_window)),@"hostParent":host.superview?NSStringFromClass(host.superview.class):@"none",
          @"style":@(surface.traitCollection.userInterfaceStyle),@"template":@(surface.iconView.image.renderingMode==UIImageRenderingModeAlwaysTemplate),
          @"titleLength":@(surface.label.text.length),@"digitSuffixPresent":@(surface.label.text.length && [surface.label.text rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location!=NSNotFound)}];
    }
    return @{@"version":@"0.4.105-test4fix105",@"pageID":[NSString stringWithFormat:@"%p",_route.leaf],@"page":_route.leaf?NSStringFromClass(_route.leaf.class):@"none",@"primary":@(_route.primary),
      @"tickCPUms":@(_tickCost),@"sharedCaptureCPUms":@(_backdropCost),@"drawAndDockCaptureCPUms":@(_drawCost),@"refreshCPUms":@(_refreshCost),@"maxTickCPUms":@(_maxTickCost),
      @"navigationPaintRescans":@(_navigationPaintRescans),@"tabBarSnapshotsConcealed":@(_snapshotsConcealed),
      @"coldStartLayersCleared":@(_coldStartLayersCleared),@"tabBarSnapshotLog":_snapshotLog?:@[],@"pageTopPaintCleared":@(_pageTopPaintCleared),@"pageTopRepairs":@(WXGPageTopRepairs),@"settingsEntryReady":@(WXGSettingsEntryReady),@"navigationRaises":@(_navigationRaises),@"navigationCovers":@(_navigationCovers),@"lastNavigationCover":_lastNavigationCover?:@"none",@"homePullTrace":_homePullTrace?:@[],@"homeTopBarInList":@(_homeTopBarInList),@"homeTopBarMoves":@(_homeTopBarMoves),@"landedSwitches":@(_landedSwitches),@"homeTopBarInListAtRest":@(_homeTopBarAtRest),@"homePullHosts":_homePullHosts?:@[],@"coldStartLog":WXGColdStartLog?:@[],
      @"appearances":@(_appearances),@"stalePendingClears":@(_stalePendingClears),@"appearanceMatches":@(_appearanceMatches),
      @"dockProfile":@{@"windows":@(_profileWindows),@"frames":@(_profileFrames),@"slowFrames":@(_profileSlowFrames),@"worst":_profileWorst?:@[]},@"settingsEntryInsertions":@(WXGSettingsEntryInsertions),@"prewarmedTabPages":_prewarmed?:@[],
      @"tabSwitches":_tabTraces?:@[],@"currentTabTrace":_tabTrace?:@{},@"lastSlowRefresh":_lastSlowRefreshPhases?:@{},
      @"coldStartTopPaint":_topPaintCensus?:@[],
      @"postCommit":@{@"observer":@(_commitObserver!=NULL),@"order":@1999500,@"phase":@"beforeCoreAnimationCommit",@"frames":@(_postCommitFrames),@"inlineFallbacks":@(_postCommitFallbacks),@"dropped":@(_droppedPendingFrames),
        @"delayFromCallbackMS":@(_postCommitDelayMS),@"presentScheduleWaitMS":@(WXGGlassScheduleWaitMS()),@"costMS":@(_postCommitCost),@"maxCostMS":@(_maxPostCommitCost)},
      @"callbackIntervalms":@(_lastTickTime*1000),@"callbackCount":@(_frames),@"refreshCount":@(_refreshes),@"covered":@(_suspendedByCover),
      @"navigationRepairs":@(_navigationRepairs),@"homeReattachments":@(_homeReattachments),@"decorations":WXGDecorations.shared.evidence,@"bubbles":WXGBubbles.shared.evidence,
      @"bindingRecoveries":@(_bindingRecoveries),@"samplingLayoutSkips":@(_samplingLayoutSkips),@"navigationSetupDeferrals":@(_navigationSetupDeferrals),@"transitionSamplingSkips":@(_transitionSamplingSkips),@"navigationRequests":_navigationRequests?:@[],
      @"transition":@{ @"active":@(_nativeTransition!=nil),@"interactive":@(_nativeTransition.isInteractive),@"percent":@(_nativeTransition.percentComplete),
        @"serial":@(_transitionSerial),@"cancelled":@(_transitionCancellations),@"completed":@(_transitionCompletions),@"events":_transitionLog?:@[]},
      @"inputBinding":@{@"installed":@(_inputAdapter.installed),@"tool":[NSString stringWithFormat:@"%p",_inputAdapter.tool],@"frame":NSStringFromCGRect(WXGWindowRect(_inputAdapter.tool,_window))},
      @"inputRepair":self.inputRepairMetrics,
      @"bindings":bindings,@"backdrop":WXGBackdropEvidence(),@"dock":_dockView.glass.diagnostics?:@"none"};
}
- (NSDictionary *)inputRepairMetrics {
    return @{@"requests":@(_inputRepairRequests),@"passes":@(_inputRepairPasses),@"deferred":@(_inputRepairDeferrals),
        @"inactiveSkips":@(_inputInactiveSkips),@"pending":@(_inputRepairGate.pending!=0),@"usedThisFrame":@(_inputRepairGate.used),
        @"budget":@(WXGInputRepairBudget),@"lastMS":@(_inputRepairMS),@"maxMS":@(_maxInputRepairMS)};
}
- (NSArray *)navigationChromeMetrics {
    CFTimeInterval now=CACurrentMediaTime();if(_chromeEvidence && now-_lastChromeEvidence<.5)return _chromeEvidence;
    _lastChromeEvidence=now;NSMutableArray *out=[NSMutableArray array];
    NSMutableOrderedSet *views=[NSMutableOrderedSet orderedSetWithArray:_navigationChromeHosts.allObjects?:@[]];
    [views addObjectsFromArray:WXGViews(_route.nav.navigationBar,48)];
    for(UIView *view in views) {
        if(view.window!=_window || WXGIsPluginView(view))continue;
        NSString *name=NSStringFromClass(view.class),*lower=name.lowercaseString;
        BOOL paint=[lower containsString:@"background"] || [lower containsString:@"backdrop"] ||
            [view isKindOfClass:UIVisualEffectView.class] || [name isEqual:@"FakeNavigationBar"];
        if(!paint)continue;
        CALayer *layer=view.layer;
        [out addObject:@{@"class":name,@"id":[NSString stringWithFormat:@"%p",view],
            @"parentClass":view.superview?NSStringFromClass(view.superview.class):@"none",
            @"rect":NSStringFromCGRect(WXGWindowRect(view,_window)),@"alpha":@(view.alpha),@"hidden":@(view.hidden),
            @"backgroundAlpha":@(layer.backgroundColor?CGColorGetAlpha(layer.backgroundColor):0),
            @"hasContents":@(layer.contents!=nil),@"hasMask":@(layer.mask!=nil),
            @"effect":[view isKindOfClass:UIVisualEffectView.class]?NSStringFromClass(((UIVisualEffectView *)view).effect.class)?:@"nil":@"none"}];
        if(out.count>=16)break;
    }
    _chromeEvidence=out;return out;
}
- (NSDictionary *)samplingMetrics {
    NSMutableArray *frames=[NSMutableArray array];
    NSArray *surfaces=[[_buttons arrayByAddingObjectsFromArray:_departingButtons?:@[]] arrayByAddingObjectsFromArray:_inputAdapter.surfaces?:@[]];
    for(WXGSurface *s in surfaces)if(s.active && !s.plain && frames.count<16)[frames addObject:s.glass.frameMetrics];
    if(_dockView.active)[frames addObject:_dockView.glass.frameMetrics];
    NSDictionary *dock=@{@"owner":_dockPrimaryOwner?NSStringFromClass(_dockPrimaryOwner.class):@"none",
        @"ownerID":[NSString stringWithFormat:@"%p",_dockPrimaryOwner],
        @"parent":_dockView.superview?NSStringFromClass(_dockView.superview.class):@"none",
        @"attached":@(_dockView.window!=nil),@"active":@(_dockView.active),
        @"nativeSuppressionRetained":@(_dockStates!=nil),@"nativeExposureMask":@NO,@"nativeBarChild":@(_dockView.superview==_suppressedTabBar),
        @"foregroundChild":@(_dockView.superview==_overlay || (_dockRow && _dockView.superview==_dockRow && _dockRow.superview==_overlay)),@"presentation":@(_dockPresentation),
        @"search":[self dockSearchEvidence],
        @"nativeBarHasPaintMask":@(_suppressedTabBar.layer.mask!=nil),
        @"transitionToRoot":@(_dockTransitionToRoot),@"acceptsTouches":@(_dockView.userInteractionEnabled),
        @"returnPolicy":@"foreground_readonly_until_complete",
        @"screenBottomGap":@(MAX(0,_window.safeAreaInsets.bottom+WXGConfig.shared.lift))};
    return @{@"revision":@"FIX103",@"edgeFade":WXGEdgeFadeEvidence(),@"rims":WXGRimSummary(),@"calm":WXGCalmEvidence(),@"keyboard":WXGKeyboardTraceEvidence(),@"settingsStorage":WXGSettingsStorageEvidence(),@"inputRepair":self.inputRepairMetrics,@"glassFrames":frames,@"backdrop":WXGBackdropEvidence(),@"dockOwnership":dock,
        @"covered":@(_suspendedByCover),@"displayLinkPaused":@(_displayLink.paused),@"coveredRenderFrames":@(_coveredRenderFrames),
        @"dockInteraction":_dockView.dockInteractionMetrics?:@{},@"dockGestureProtection":WXGDockTouchProtectionMetrics(_suppressedTabBar),
        @"navigationChrome":self.navigationChromeMetrics,
        @"scopedChromeRepairs":@(_scopedChromeRepairs),@"ignoredHomeHosts":@(_ignoredHomeHosts),@"transitionSamplingSkips":@(_transitionSamplingSkips),@"navigationSetupDeferrals":@(_navigationSetupDeferrals),@"textureCopyBackend":@"GPU_all_due_consumers"};
}
- (void)previewLens {[_dockView previewLens];}
- (NSArray *)navigationInventory {
    NSMutableArray *out=[NSMutableArray array];
    NSMutableOrderedSet *views=[NSMutableOrderedSet orderedSetWithArray:WXGViews(_route.nav.navigationBar,250)];
    [views addObjectsFromArray:_pageViews?:@[]];
    for(UIView *view in views) {
        CGRect rect=WXGWindowRect(view,_window);
        if(rect.origin.y>_window.safeAreaInsets.top+160 || rect.size.height>220 || CGRectIsEmpty(rect))continue;
        if([view isKindOfClass:UILabel.class] || WXGIsPluginView(view))continue;
        [out addObject:@{@"class":NSStringFromClass(view.class),@"rect":@[@(rect.origin.x),@(rect.origin.y),@(rect.size.width),@(rect.size.height)],
            @"alpha":@(view.alpha),@"hidden":@(view.hidden),@"gestures":@(view.gestureRecognizers.count),
            @"actions":[view isKindOfClass:UIControl.class]?WXGActionNames((id)view):@[]}];
        if(out.count>=100)break;
    }return out;
}
- (NSDictionary *)evidence {
    NSMutableArray *buttons=[NSMutableArray array];for(WXGSurface *s in _buttons)[buttons addObject:s.evidence];
    return @{@"schema":@"wxg-test4-fix11",@"version":@"0.4.105-test4fix105",@"runtime":self.runtimeMetrics,
        @"backdrop":WXGBackdropEvidence(),@"nativeNavigationCandidates":[self navigationInventory],
        @"performance":@{@"screenMaximumFPS":@(_window.screen.maximumFramesPerSecond),@"requestedCaptureFPS":@(WXGConfig.shared.captureFPS),@"effectiveCaptureFPS":@(WXGScreenCaptureFPS(_window.screen)),@"hostHighRefreshOptIn":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CADisableMinimumFrameDurationOnPhone"]?:@NO,@"displayCallbacks":@(_frames),@"callbacksOver25ms":@(_slowFrames),@"refreshes":@(_refreshes),
            @"displayCallbackRate":@(_frames/MAX(.001,CACurrentMediaTime()-_frameStart)),@"pageRestores":@(_pageRestores),@"cachedPages":@(_pages.count),@"pooledNavigationSurfaces":@(_surfacePool.count),@"pooledInputSurfaces":@(_inputAdapter.surfaces.count)},@"page":_route.path?:@"",@"presentedChat":@(_route.presentedStack),@"status":_status?:@"",
        @"unix":@(NSDate.date.timeIntervalSince1970),@"uptime":@(CACurrentMediaTime()),@"contentSizeCategory":_window.traitCollection.preferredContentSizeCategory?:@"",
        @"system":UIDevice.currentDevice.systemVersion,@"wechat":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",
        @"window":@[@(_window.bounds.size.width),@(_window.bounds.size.height)],@"scale":@(_window.screen.scale),
        @"safeArea":@[@(_window.safeAreaInsets.top),@(_window.safeAreaInsets.left),@(_window.safeAreaInsets.bottom),@(_window.safeAreaInsets.right)],
        @"buttons":buttons,@"input":_inputAdapter.evidence,@"clearedPaint":_paintEvidence.copy,
        @"navigationPaint":_navStates.evidence?:@[],@"tabBarPaint":_dockStates.evidence?:@[],
        @"materialParameters":WXGConfig.shared.parameterValues,@"license":WXGLicenseEvidence(),@"dockLayers":_dockView.hidden?@{}:_dockView.glass.layerEvidence?:@{},
        @"dock":_dockView.hidden?@"当前页不显示":_dockView.diagnostics?:@"尚未创建",
        @"avatarStatus":_avatarStatus?:@"标题胶囊模式",@"avatarLookups":@(_avatarLookups),@"avatarProbe":_avatarProbe?:@{},@"avatarDownload":_avatarDownloadStatus?:@"none",@"avatarDownloads":@(_avatarDownloads),@"avatarDiskHits":@(_avatarDiskHits),@"kindaProbe":_kindaProbe?:@[],@"sharedParametersDomain":@"com.runyu.WeChatLiquidGlass/optics.test4",@"log":WXGLogText()};
}
- (NSString *)diagnostics {
    NSDictionary *payload=@{@"currentOrLastScene":_settings.presentingViewController?(_lastSceneEvidence?:@{}):self.evidence,@"history":_sceneHistory.copy?:@[],@"actionDispatches":_actionHistory.copy?:@[],@"log":WXGLogText(),
        @"liveSamplingAtExport":self.samplingMetrics,
        // FIX84: every setting (importable as is) and the frame-rate log's summary.
        @"settingsShare":WXGSharePayload(),@"frameRate":WXGPerfEvidence()};
    NSData *d=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];return [[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"诊断暂不可用";
}
- (void)recordForward:(NSDictionary *)action {
    NSMutableDictionary *e=[action mutableCopy];e[@"time"]=@(CACurrentMediaTime());e[@"page"]=_route.path?:@"";
    [_actionHistory addObject:e];if(_actionHistory.count>500)[_actionHistory removeObjectAtIndex:0];
}
- (void)exportDiagnosticsFrom:(UIViewController *)controller {
#if defined(WXG_RELEASE) && WXG_RELEASE
    (void)controller;   // FIX113: 对外发布包不导出诊断
#else
    /* Preserve pre-cover scene evidence AND separate live sampling counters.
       Exporting from settings must not disguise a paused/stale source. */
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"WeChatLiquidGlass_TEST4_FIX103_diagnostics.json"];
    [self.diagnostics writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    a.popoverPresentationController.sourceView=controller.view;a.popoverPresentationController.sourceRect=CGRectMake(controller.view.bounds.size.width*.5,60,1,1);
    [controller presentViewController:a animated:YES completion:nil];
#endif
}
@end
// FIX102: nothing moving that a 50-95 ms read would freeze: no finger or
// lens animation on the dock, no tab switch in the last 2 s, no push / pop.
static BOOL WXGHostQuietForLicense(void) {
    WXGIntegrationHost *host=WXGIntegrationHost.shared;
    if(!host)return YES;
    WXGDemoBar *dock=host.dockView;
    if(dock && (dock.tracking || !dock.lensAtRest))return NO;
    return host.nativeTransition==nil && CACurrentMediaTime()-host.lastSwitchAt>2;
}


/* Local method replacement works with MobileSubstrate or libhooker injection,
   without shipping a substrate header or touching UIView's global setter. */
// FIX30: the settings entry lives in WeChat's own Settings page, as a native
// row built with WeChat's table manager (NewSettingViewController's
// m_tableViewMgr, WCTableViewSectionManager, WCTableViewNormalCellManager), the
// way other WeChat tweaks add theirs. reloadTableData rebuilds the table, so the
// section is added again after every rebuild.
static void WXGInsertSettingsEntry(UIViewController *settings) {
    // FIX105: no settings row for an unauthorized account (including while
    // verifying or before the account is read) — same as the overlay and the
    // floating entry, the plugin leaves no trace in WeChat's own Settings until
    // the account is confirmed authorized. This runs on every reloadTableData,
    // so the row appears the next time WeChat rebuilds that table after the
    // account becomes authorized (reopening Settings; authorization normally
    // finishes well before the user is on this page).
    // FIX106: 授权行入口也给“曾授权但现在连不上 / 需更新”的正当用户（Unreachable/Outdated），
    // 让他们进设置点“重新检测”；从没授权过的人永远是 Denied/Unknown，仍然零入口、零痕迹。
    // Authorized 仍照旧插入（下面的条件包含它），首次授权用户的入口不受影响。
    WXGLicenseState entryState=WXGLicenseCurrentState(NO);
    if(entryState!=WXGLicenseAuthorized && entryState!=WXGLicenseUnreachable && entryState!=WXGLicenseOutdated)return;
    @try {
        Ivar ivar=class_getInstanceVariable(object_getClass(settings),"m_tableViewMgr");
        id manager=ivar?object_getIvar(settings,ivar):nil;
        Class sectionClass=NSClassFromString(@"WCTableViewSectionManager"),cellClass=NSClassFromString(@"WCTableViewNormalCellManager");
        SEL sectionSelector=NSSelectorFromString(@"sectionInfoDefaut"),cellSelector=NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:");
        SEL addCell=NSSelectorFromString(@"addCell:"),insert=NSSelectorFromString(@"insertSection:At:"),getTable=NSSelectorFromString(@"getTableView");
        if(!manager || ![sectionClass respondsToSelector:sectionSelector] || ![cellClass respondsToSelector:cellSelector] ||
           ![manager respondsToSelector:insert] || ![manager respondsToSelector:getTable])return;
        UITableView *table=((id(*)(id,SEL))objc_msgSend)(manager,getTable);
        if(![table isKindOfClass:UITableView.class])return;
        id section=((id(*)(id,SEL))objc_msgSend)(sectionClass,sectionSelector);
        id cell=((id(*)(id,SEL,SEL,id,NSString *,NSInteger))objc_msgSend)(cellClass,cellSelector,
            NSSelectorFromString(@"wxg_openGlassSettings"),settings,@"微信 Liquid Glass",1);
        if(!section || !cell || ![section respondsToSelector:addCell])return;
        ((void(*)(id,SEL,id))objc_msgSend)(section,addCell,cell);
        NSInteger sections=table.numberOfSections;
        NSUInteger index=sections>1?1:(NSUInteger)MAX(sections,0);
        ((void(*)(id,SEL,id,NSUInteger))objc_msgSend)(manager,insert,section,index);
        [table reloadData];++WXGSettingsEntryInsertions;
    } @catch(NSException *error){WXGLog(@"设置入口：%@",error.reason);}
}
static void WXGInstallSettingsEntry(void (^hook)(Class,SEL,void (^)(id))) {
    Class settings=NSClassFromString(@"NewSettingViewController");SEL reload=NSSelectorFromString(@"reloadTableData");
    WXGSettingsEntryReady=settings && class_getInstanceMethod(settings,reload) && class_getInstanceVariable(settings,"m_tableViewMgr") &&
        [NSClassFromString(@"WCTableViewSectionManager") respondsToSelector:NSSelectorFromString(@"sectionInfoDefaut")] &&
        [NSClassFromString(@"WCTableViewNormalCellManager") respondsToSelector:NSSelectorFromString(@"normalCellForSel:target:title:accessoryType:")];
    if(!WXGSettingsEntryReady)return;
    class_addMethod(settings,NSSelectorFromString(@"wxg_openGlassSettings"),
        imp_implementationWithBlock(^(UIViewController *controller){[WXGIntegrationHost.shared openSettingsFrom:controller];}),"v@:");
    hook(settings,reload,^(id controller){if([controller isKindOfClass:UIViewController.class])WXGInsertSettingsEntry(controller);});
}
static void WXGHookVoid(Class c,SEL selector,void (^after)(id)) {
    if(!c)return;Method m=class_getInstanceMethod(c,selector);if(!m)return;
    IMP original=method_getImplementation(m);
    IMP replacement=imp_implementationWithBlock(^(id object){
        ((void (*)(id,SEL))original)(object,selector);
        if(WXGBackdropCaptureInProgress()) {++WXGIntegrationHost.shared.samplingLayoutSkips;return;}
        // FIX102: timed for the dock profile (hooksMS), without the refreshes,
        // ticks and nested hooks it runs (those are counted on their own).
        CFTimeInterval begin=CACurrentMediaTime();double inner=WXGProfileOursTotal();
        [WXGIntegrationHost.shared start];after(object);
        double spent=(CACurrentMediaTime()-begin)*1000-(WXGProfileOursTotal()-inner);
        if(spent>0)WXGProfileTotals[WXGProfileHooks]+=spent;
    });
    if(!class_addMethod(c,selector,replacement,method_getTypeEncoding(m)))class_replaceMethod(c,selector,replacement,method_getTypeEncoding(m));
}
static void WXGHookInputLayout(Class c) {
    SEL selector=@selector(layoutSubviews);Method method=class_getInstanceMethod(c,selector);if(!method)return;
    IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^(id object){
        WXGBeginNativeInputLayout();
        @try {((void(*)(id,SEL))original)(object,selector);}
        @finally {WXGEndNativeInputLayout();}
        // The outer tool/panel pass has finished all its children. Applying at
        // a nested MMGrowTextView callback fights the remaining parent layout.
        if(!WXGNativeInputLayoutInProgress())[WXGIntegrationHost.shared layoutInput];
    });
    if(!class_addMethod(c,selector,replacement,method_getTypeEncoding(method)))
        class_replaceMethod(c,selector,replacement,method_getTypeEncoding(method));
}
static void WXGRecordNativePop(UINavigationController *nav,SEL selector,BOOL animated) {
        WXGIntegrationHost *host=WXGIntegrationHost.shared;
        if(nav==host.route.nav && !WXGBackdropCaptureInProgress()) {
            // Bounded metadata only; never change the animated argument,
            // navigation delegate, gesture recognizers or interactive driver.
            [host.navigationRequests addObject:@{@"t":@(CACurrentMediaTime()),@"method":NSStringFromSelector(selector),@"animated":@(animated),
                @"animationsEnabled":@(UIView.areAnimationsEnabled),@"disableActions":@(CATransaction.disableActions),
                @"from":NSStringFromClass(nav.topViewController.class)?:@"none",
                @"depth":@(nav.viewControllers.count),@"popGesture":@(nav.interactivePopGestureRecognizer.state)}];
            if(host.navigationRequests.count>32)[host.navigationRequests removeObjectAtIndex:0];
            // FIX28: popping to the stack root (chat -> home) starts the tab
            // bar snapshot watch now, independent of the coordinator.
            BOOL toRoot=[NSStringFromSelector(selector) hasPrefix:@"popToRoot"] || nav.viewControllers.count==2;
            UIViewController *root=nav.viewControllers.firstObject;
            if(toRoot && root && [host isDockRoot:root])[host beginRootReturnTo:root source:@"popRequest"];
        }
}
static void WXGObserveNavigationPop(void) {
    for(NSString *name in @[@"popViewControllerAnimated:",@"popToRootViewControllerAnimated:"]) {
        SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(UINavigationController.class,selector);
        IMP original=method_getImplementation(method);
        IMP replacement=imp_implementationWithBlock(^id(UINavigationController *nav,BOOL animated){
            WXGRecordNativePop(nav,selector,animated);
            ++WXGNavigationCallDepth;
            @try {return ((id(*)(id,SEL,BOOL))original)(nav,selector,animated);}
            @finally {--WXGNavigationCallDepth;if(!WXGNavigationCallDepth)[WXGIntegrationHost.shared schedule];}
        });
        class_replaceMethod(UINavigationController.class,selector,replacement,method_getTypeEncoding(method));
    }
    SEL selector=@selector(popToViewController:animated:);Method method=class_getInstanceMethod(UINavigationController.class,selector);
    IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^id(UINavigationController *nav,UIViewController *destination,BOOL animated){
        WXGRecordNativePop(nav,selector,animated);
        ++WXGNavigationCallDepth;
        @try {return ((id(*)(id,SEL,id,BOOL))original)(nav,selector,destination,animated);}
        @finally {--WXGNavigationCallDepth;if(!WXGNavigationCallDepth)[WXGIntegrationHost.shared schedule];}
    });
    class_replaceMethod(UINavigationController.class,selector,replacement,method_getTypeEncoding(method));
    selector=@selector(pushViewController:animated:);method=class_getInstanceMethod(UINavigationController.class,selector);
    IMP pushOriginal=method_getImplementation(method);SEL pushSelector=selector;
    replacement=imp_implementationWithBlock(^(UINavigationController *nav,UIViewController *destination,BOOL animated){
        WXGRecordNativePop(nav,pushSelector,animated);++WXGNavigationCallDepth;
        @try {((void(*)(id,SEL,id,BOOL))pushOriginal)(nav,pushSelector,destination,animated);}
        @finally {--WXGNavigationCallDepth;if(!WXGNavigationCallDepth)[WXGIntegrationHost.shared schedule];}
    });
    class_replaceMethod(UINavigationController.class,selector,replacement,method_getTypeEncoding(method));
}
static void WXGInstallDockHitTesting(void) {
    Class cls=NSClassFromString(@"MMTabBar");if(!cls)return;
    SEL selector=@selector(hitTest:withEvent:);Method method=class_getInstanceMethod(cls,selector);if(!method)return;
    IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^UIView *(UIView *bar,CGPoint point,UIEvent *event){
        WXGIntegrationHost *host=WXGIntegrationHost.shared;
        WXGDemoBar *dock=host.dockView;
        if(host.suppressedTabBar==bar && host.dockStates && dock.superview==host.overlay &&
           WXGPluginEnabled() && WXGPreferences.shared.dock)return nil;
        if(dock.superview==bar && dock.active && !dock.hidden && !bar.hidden && bar.alpha>.01 && WXGPluginEnabled() && WXGPreferences.shared.dock) {
            // The raised part extends above native bounds; preserve its actual
            // interactive capsule while suppressing old invisible tab hit areas.
            return [dock hitTest:[bar convertPoint:point toView:dock] withEvent:event];
        }
        return ((id(*)(id,SEL,CGPoint,id))original)(bar,selector,point,event);
    });
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(method));
}
/* FIX106 I (user: 聊天设置 - single and group 聊天信息 - always opened with its
   first rows under the title bar, as if the list had no top inset; 微信设置
   and a plugin's page opened from it sometimes lost the bar itself). WeChat's
   settings-like pages rest at their list's top when pushed. Right after the
   push (four checks over about a second, untouched by the finger): a list
   whose own top - its adjusted inset - would put the first row below the
   title bar, but which rests scrolled up into the bar by no more than the
   bar's area, is put at its top. Each check is logged (the list's frame,
   insets, offset and place in its parent, the bar, whether the plugin's
   settings still hold this navigation) so a case this does not cover can be
   told apart in the diagnostics. */
static UIScrollView *WXGPageMainList(UIViewController *controller) {
    UIView *root=controller.view;if(!root.window)return nil;
    CGFloat width=root.bounds.size.width,height=root.bounds.size.height,bestArea=0;
    UIScrollView *best=nil;
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root];
    for(NSUInteger i=0;i<queue.count && i<400;i++) {
        UIView *v=queue[i];
        if(v.hidden || v.alpha<.01 || WXGIsPluginView(v))continue;
        if([v isKindOfClass:UIScrollView.class] && ![v isKindOfClass:UITextView.class]) {
            CGRect r=[v convertRect:v.bounds toView:root];
            if(r.size.width>=width*.9 && r.size.height>=height*.5 && r.size.width*r.size.height>bestArea){best=(UIScrollView *)v;bestArea=r.size.width*r.size.height;}
            continue;   // a list's own views are its content
        }
        if([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class])continue;
        [queue addObjectsFromArray:v.subviews];
    }
    return best;
}
static void WXGCheckPageTop(UIViewController *controller,NSUInteger step) {
    if(!controller.isViewLoaded || !controller.view.window || !WXGPluginEnabled() || WXGBackdropCaptureInProgress())return;
    UINavigationController *nav=controller.navigationController;
    if(!nav || nav.topViewController!=controller || nav.transitionCoordinator)return;   // left, covered or moving
    UIWindow *w=controller.view.window;UINavigationBar *bar=nav.navigationBar;
    BOOL barShown=!nav.navigationBarHidden && !bar.hidden && bar.alpha>.01 && bar.window==w;
    CGFloat navBottom=barShown?CGRectGetMaxY([bar convertRect:bar.bounds toView:nil]):w.safeAreaInsets.top;
    BOOL barWasHidden=NO,held=WXGSettingsHoldsNavigation(nav,&barWasHidden);
    NSString *page=NSStringFromClass(controller.class);
    UIScrollView *list=WXGPageMainList(controller);
    if(!list) {
        if(step==0 && WXGPageTopLogs++<40)WXGLog(@"顶部：%@ 没找到整页列表（导航栏%@，底边 %.0f）",page,barShown?@"显示":@"隐藏",navBottom);
        return;
    }
    CGRect frame=[list convertRect:list.bounds toView:nil];
    CGFloat inset=list.adjustedContentInset.top,offset=list.contentOffset.y;
    CGFloat restingTop=CGRectGetMinY(frame)+inset,currentTop=CGRectGetMinY(frame)-offset,past=offset+inset;
    BOOL touched=list.tracking || list.dragging || list.decelerating;
    BOOL under=currentTop<navBottom-2,restOK=restingTop>=navBottom-2;
    BOOL repair=barShown && !touched && under && restOK && past>2 && past<=navBottom+8;
    // The list's own top under the bar: WeChat gave it no top inset at all
    // (UIKit never adjusts it, its inset 0) while it starts under the bar - the
    // FIX106 I log of 聊天信息 before the edge-fade plate stopped going in front
    // of the list. A fallback: the inset the bar needs is added (and the list
    // put at its new top if it rested at the old one).
    CGFloat missing=navBottom-restingTop;
    BOOL addInset=!repair && barShown && !touched && !restOK && list.contentInsetAdjustmentBehavior==UIScrollViewContentInsetAdjustmentNever &&
        list.contentInset.top<1 && CGRectGetMinY(frame)>=-1 && CGRectGetMinY(frame)<navBottom-2 && missing>2 && missing<=navBottom+2;
    if((step==0 || under || !barShown) && WXGPageTopLogs++<40) {
        UIView *parent=list.superview;NSUInteger index=[parent.subviews indexOfObjectIdenticalTo:list];
        Class plate=NSClassFromString(@"WXGEdgePlateView");BOOL plateBelow=NO,plateBehind=NO;
        for(NSUInteger i=0;i<parent.subviews.count;i++)if(plate && [parent.subviews[i] isKindOfClass:plate]) {
            if(i<index)plateBelow=YES;
            else if(parent.subviews[i].layer.zPosition<list.layer.zPosition)plateBehind=YES;
        }
        WXGLog(@"顶部 #%lu：%@ 列表 %@ y%.0f 高%.0f | 内边距 系统后 %.0f 自身 %.0f 行为 %ld | 偏移 %.0f 内容 %.0f | 内容顶 现在 %.0f 静止 %.0f | 导航栏%@ 底边 %.0f%@ | 列表是%@第 %lu 个子视图%@%@%@",
            (unsigned long)step,page,NSStringFromClass(list.class),CGRectGetMinY(frame),frame.size.height,
            inset,list.contentInset.top,(long)list.contentInsetAdjustmentBehavior,offset,list.contentSize.height,currentTop,restingTop,
            barShown?@"显示":@"隐藏",navBottom,held?(barWasHidden?@"，插件设置还拿着它（微信原本隐藏）":@"，插件设置还拿着它（微信原本显示）"):@"",
            parent==controller.view?@"页面视图的":@"子容器的",(unsigned long)index+1,plateBelow?@"（下面有渐隐底板）":plateBehind?@"（渐隐底板排在它后面、画在它下面）":@"",
            touched?@"，手指在动":@"",repair?@" → 回到列表顶部":addInset?[NSString stringWithFormat:@" → 补上顶部内边距 %.0f",missing]:under?@"，内容压在顶栏下面":@"");
    }
    if(repair) {
        ++WXGPageTopRepairs;
        [UIView performWithoutAnimation:^{[list setContentOffset:CGPointMake(list.contentOffset.x,-inset) animated:NO];}];
        return;
    }
    if(addInset) {
        ++WXGPageTopRepairs;
        BOOL atTop=offset<=-inset+.5;
        [UIView performWithoutAnimation:^{
            UIEdgeInsets content=list.contentInset;content.top+=missing;list.contentInset=content;
            UIEdgeInsets indicator=list.verticalScrollIndicatorInsets;indicator.top+=missing;list.verticalScrollIndicatorInsets=indicator;
            if(atTop)[list setContentOffset:CGPointMake(list.contentOffset.x,-list.adjustedContentInset.top) animated:NO];
        }];
        return;
    }
    if(touched || step>=3)return;
    static const double delays[]={.25,.6,1.2};
    __weak UIViewController *weakController=controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((delays[step]-(step?delays[step-1]:0))*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UIViewController *c=weakController;if(c)WXGCheckPageTop(c,step+1);
    });
}
static void WXGNotePageAppeared(UIViewController *controller) {
    static Class classes[3];static dispatch_once_t once;
    dispatch_once(&once,^{
        NSArray<NSString *> *names=@[@"ChatRoomInfoViewController",@"AddContactToChatRoomViewController",@"NewSettingViewController"];
        for(NSUInteger i=0;i<3;i++)classes[i]=NSClassFromString(names[i]);
    });
    BOOL match=NO;for(NSUInteger i=0;i<3 && !match;i++)match=classes[i] && [controller isKindOfClass:classes[i]];
    if(!match || !WXGPluginEnabled())return;
    // The bar always; the list's top when pushed now (not when shown again
    // after a page above it went: the scroll position is the user's then) or
    // when the bar has just come back (the list rested at the bar-less top).
    BOOL pushed=controller.isMovingToParentViewController;
    __weak UIViewController *weakController=controller;
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *c=weakController;if(!c)return;
        BOOL shown=WXGSettingsShowBarForPage(c);
        if(shown)[c.navigationController.view layoutIfNeeded];
        if(pushed || shown)WXGCheckPageTop(c,0);
    });
}
__attribute__((constructor)) static void WXGInitialize(void) {
    WXGLoadTime=CACurrentMediaTime();WXGColdLog(@"插件加载");
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.tencent.xin"])return;
    void (^install)(void)=^{
        // FIX104: the unlock ticket first of all, here rather than on the next
        // main turn (which waits for WeChat's launch): the cached tickets are
        // read off main and the shader compiles while WeChat starts, so the
        // first refresh already finds the account unlocked.
        WXGUnlockStart();
        WXGPrewarmGlassPipeline();WXGInstallNativeIconGuard();WXGInstallDockHitTesting();
        for(NSString *name in @[@"viewWillAppear:",@"viewDidAppear:"]) {
            SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(UIViewController.class,selector);
            IMP original=method_getImplementation(method);BOOL will=[name isEqual:@"viewWillAppear:"];
            IMP replacement=imp_implementationWithBlock(^(UIViewController *controller,BOOL animated){
                ((void (*)(id,SEL,BOOL))original)(controller,selector,animated);
                if(WXGBackdropCaptureInProgress()){++WXGIntegrationHost.shared.samplingLayoutSkips;return;}
                WXGEdgeFadeNoteController(controller,YES);   // FIX64 (FIX65: our own settings pages too)
                if(!will)WXGNotePageAppeared(controller);   // FIX106 I: 聊天信息 / 设置 rest at their top
                if([NSStringFromClass(controller.class) hasPrefix:@"WXG"])return;
                WXGIntegrationHost *host=WXGIntegrationHost.shared;[host start];
                if(will)[host prepareController:controller];
                else {
                    if(host.nativeTransition) {
                        if(controller==host.transitionFrom || controller==host.transitionTo)
                            [host logTransition:@"view_did_appear" cancelled:NO];
                        [host schedule];
                    }else {
                        if(controller==host.pendingController){host.pendingController=nil;host.needsEarlyLayout=NO;}
                        [host schedule];
                    }
                }
            });
            class_replaceMethod(UIViewController.class,selector,replacement,method_getTypeEncoding(method));
        }
        WXGHookVoid(UIViewController.class,@selector(viewDidLayoutSubviews),^(UIViewController *controller){
            [WXGIntegrationHost.shared controllerLaidOut:controller];
            WXGEdgeFadeNoteController(controller,NO);   // FIX64/65: only the chat page and the other pages (WXGEdgeFade.m)
        });
        WXGHookVoid(NSClassFromString(@"MMUINavigationBar"),@selector(layoutSubviews),^(__unused id object){[WXGIntegrationHost.shared nativeNavigationLaidOut];});
        for(NSString *name in @[@"_UIBarBackground",@"FakeNavigationBar"])
            for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
                WXGHookVoid(NSClassFromString(name),NSSelectorFromString(selectorName),^(UIView *view){
                    [WXGIntegrationHost.shared navigationChromeLaidOut:view];
                });
        WXGHookVoid(NSClassFromString(@"MMTabBar"),@selector(layoutSubviews),^(__unused id object){
            WXGIntegrationHost *host=WXGIntegrationHost.shared;[host suppressNativeDockPaint];if(!host.refreshing && host.route.primary && !WXGNavigationCallDepth){host.refreshing=YES;@try {[host buildDock];}@finally {host.refreshing=NO;}}else [host schedule];
        });
        WXGHookVoid(NSClassFromString(@"MMNewMsgContentNavBar"),@selector(layoutSubviews),^(__unused id object){
            WXGIntegrationHost *host=WXGIntegrationHost.shared;if(host.refreshing)return;
            [host.navStates reapply];[host schedule];
        });
        for(NSString *name in @[@"MMInputToolView",@"InputToolViewBar",@"MMGrowTextView"])
            WXGHookInputLayout(NSClassFromString(name));
        WXGHookVoid(NSClassFromString(@"MainFrameLeftBarView"),@selector(layoutSubviews),^(UIView *view){[WXGIntegrationHost.shared homeGestureLaidOut:view];});
        for(NSString *selectorName in @[@"didMoveToSuperview",@"didMoveToWindow"])
            WXGHookVoid(NSClassFromString(@"MainFrameLeftBarView"),NSSelectorFromString(selectorName),^(UIView *view){[WXGIntegrationHost.shared homeGestureLaidOut:view];});
        for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToSuperview",@"didMoveToWindow"])
            WXGHookVoid(NSClassFromString(@"MMBarButton"),NSSelectorFromString(selectorName),^(UIView *view){[WXGIntegrationHost.shared navigationControlLaidOut:view];});
        for(NSString *name in @[@"MMMsgCommonTipsView",@"MMMsgTipsMixedListExpandView",@"MainFrameActionFloatView",@"MMMenuContentView"])
            for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
                WXGHookVoid(NSClassFromString(name),NSSelectorFromString(selectorName),^(UIView *view){[WXGDecorations.shared nativeHostLaidOut:view];});
        // FIX82: liquid chat bubbles (WXGBubbles.m).
        for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
            WXGHookVoid(NSClassFromString(@"TextMessageCellView"),NSSelectorFromString(selectorName),^(UIView *view){
                WXGPerfTimePluginWork(^{[WXGBubbles.shared textCellLaidOut:view];});   // FIX84: counted in the frame-rate log
            });
        WXGObserveNavigationPop();
        WXGInstallSettingsEntry(^(Class c,SEL selector,void (^after)(id)){WXGHookVoid(c,selector,after);});
        dispatch_async(dispatch_get_main_queue(),^{[WXGIntegrationHost.shared start];WXGPerfApplyPreferences();WXGCalmApplyPreferences();WXGKeyboardTraceStart();});   // FIX84: the frame-rate log (FIX85: the keyboard trace; FIX88: the calm background again; FIX103: the unlock ticket first, so the shader compiles while WeChat starts; FIX104: that moved to the top of install)
    };
    // Register before the first native view pass, without constructing UIKit
    // surfaces inside the dyld initializer. Start runs on a native callback or
    // the next main-queue turn, whichever occurs first.
    if(NSThread.isMainThread)install();else dispatch_async(dispatch_get_main_queue(),install);
}
