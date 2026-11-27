#include "WXGBuildIdentity.h"
#import "WXGIntegration.h"
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import "WXGInputRepairPolicy.h"
#import "WXGBubbleContent.h"
#import "WXGDockInteraction.h"
#import "WXGDockPresentation.h"
#import "WXGDockSearchLayout.h"
#import "WXGDockDiscrete.h"
#import "WXGHomeSearchLayout.h"
// FIX30: WeChat Settings entry state (defined with the hooks at the end of the file).
static BOOL WXGSettingsEntryReady;
static BOOL WXGSurfaceInNativeView(WXGSurface *surface);   // FIX113 D
static NSArray<NSString *> *WXGLoadedTweaks(void);   // FIX114 Y (diagnostics)
static NSArray<NSDictionary *> *WXGForeignViews(UIWindow *w);
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
    // FIX113 Z: the page-switch log; the plugin's own time as above, and its
    // hooks outside a tick (inside one, the tick holds them).
    if(WXGTransitionPerfOn)
        WXGTransitionPerfNoteSlot(slot,milliseconds,slot==WXGProfileTick || (WXGHostTimedDepth==0 && (slot==WXGProfileRefresh || slot==WXGProfileHooks)));   // (a tab switch's forward is WeChat loading the tab)
}
void WXGProfileMeshBuilt(void) {++WXGProfileMeshBuilds;WXGTransitionPerfNoteMesh();}
double WXGProfileOursTotal(void) {
    return WXGProfileTotals[WXGProfileTick]+WXGProfileTotals[WXGProfileRefresh]+WXGProfileTotals[WXGProfileSwitch]+WXGProfileTotals[WXGProfileHooks];
}
CFTimeInterval WXGSecondsSinceLoad(void) {return WXGLoadTime>0?CACurrentMediaTime()-WXGLoadTime:0;}
/* FIX114 R (user: the export was only in the plugin's settings, never on the
   chat where WeChat's title-bar buttons and their glass jump or go missing):
   while the export button is on, what the title bars show is written down
   frame by frame, a line for a button only when it changed (on the main
   thread only: the display link and UIKit's layout). */
static BOOL WXGTraceRunning;
static NSMutableArray<NSString *> *WXGTraceLines;
static NSMutableDictionary<NSString *,NSString *> *WXGTraceLast,*WXGTraceOnce;
static NSUInteger WXGTraceDropped;
static void WXGTraceAppend(NSString *line) {
    if(!line.length)return;
    if(!WXGTraceLines)WXGTraceLines=[NSMutableArray array];
    [WXGTraceLines addObject:line];
    if(WXGTraceLines.count>6000){[WXGTraceLines removeObjectsInRange:NSMakeRange(0,1000)];WXGTraceDropped+=1000;}
}
BOOL WXGNavTraceOn(void) {return WXGTraceRunning;}
void WXGNavTraceEvent(NSString *text) {
    if(!WXGTraceRunning || !text.length)return;
    WXGTraceAppend([NSString stringWithFormat:@"%.3f ● %@",WXGSecondsSinceLoad(),text]);
}
void WXGNavTraceEventOnce(NSString *key,NSString *text) {
    if(!WXGTraceRunning || !key.length || !text.length)return;
    if(!WXGTraceOnce)WXGTraceOnce=[NSMutableDictionary dictionary];
    if([WXGTraceOnce[key] isEqualToString:text])return;
    if(WXGTraceOnce.count>64)[WXGTraceOnce removeAllObjects];
    WXGTraceOnce[key]=text;WXGNavTraceEvent(text);
}
NSString *WXGNavTracePage(UIViewController *page) {
    if(!page)return @"无";
    NSString *name=NSStringFromClass(page.class)?:@"?";
    if(name.length>14 && [name hasSuffix:@"ViewController"])name=[name substringToIndex:name.length-14];
    return [NSString stringWithFormat:@"%@#%03lx",name,(unsigned long)((((uintptr_t)(__bridge void *)page)>>4)&0xfff)];
}
// Where `r` (in the view's own coordinates) is on screen as drawn now (the
// presentation tree: mid-animation, with every transform and content shift
// above it), and how visible (its own and every superlayer's opacity; 0 when
// one of them is hidden).
static CGRect WXGTraceScreenRect(UIView *view,CGRect r,double *alpha) {
    CALayer *layer=view.layer.presentationLayer?:view.layer;double a=1;
    for(CALayer *l=layer;l;) {
        if(l.hidden)a=0;else a*=l.opacity;
        CALayer *up=l.superlayer;if(!up)break;
        r=[l convertRect:r toLayer:up];l=up;
    }
    if(alpha)*alpha=a;
    return r;
}
static BOOL WXGHostQuietForLicense(void);   // FIX102 (below the host)
static void WXGInstallIdleClock(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        CFRunLoopObserverRef sleep=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting,YES,LONG_MAX,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){WXGIdleSince=CACurrentMediaTime();});
        CFRunLoopObserverRef wake=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopAfterWaiting,YES,LONG_MIN,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){
                if(WXGIdleSince>0){double slept=CACurrentMediaTime()-WXGIdleSince;WXGIdleTotal+=slept;WXGIdleSince=0;
                    if(WXGTransitionPerfOn)WXGTransitionPerfNoteIdle(slept*1000);}   // FIX113 Z
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
    if(!(fabs(f.origin.x)<1 && fabs(f.origin.y)<1 && fabs(f.size.width-w.bounds.size.width)<1 && fabs(f.size.height-w.bounds.size.height)<1))return NO;
    // FIX114 E: the chat itself the whole window too (WeChat's half-screen chat
    // sits in a full-screen container: a sheet, the page under it stays the
    // host's, covered; its input bar is adapted on its own: WXGSideChatInput).
    if(!r.leaf.isViewLoaded)return NO;
    CGRect c=WXGWindowRect(r.leaf.view,w);
    return fabs(c.origin.y)<1 && fabs(c.size.height-w.bounds.size.height)<1;
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
// FIX108 C/E: WeChat's own "+" artwork cut off: one colour, a ring drawn
// edge to edge (ink on three or more edges, on the ring's diagonals, none in
// the corners). A theme's tile, disc or plain "+" is left alone. Cached by
// the artwork (the button gets a new image object for it every frame of a pull).
static BOOL WXGInkTouchesEdges(UIImage *image) {
    if(!image || image.size.width<4 || image.size.height<4 || fabs(image.size.width-image.size.height)>1)return NO;
    static NSMutableDictionary<NSString *,NSNumber *> *cache;if(!cache)cache=[NSMutableDictionary dictionary];
    NSString *key=[NSString stringWithFormat:@"%p/%.1f/%.1f/%ld",(__bridge void *)(image.imageAsset?:(id)image),image.size.width,image.scale,(long)image.renderingMode];
    NSNumber *known=cache[key];if(known)return known.boolValue;
    enum {N=24};uint8_t px[N*N*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(px,N,N,8,N*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);BOOL ring=NO;
    if(context) {
        UIGraphicsPushContext(context);[image drawInRect:CGRectMake(0,0,N,N)];UIGraphicsPopContext();CGContextRelease(context);
        #define A(x,y) px[((y)*N+(x))*4+3]
        BOOL top=NO,bottom=NO,left=NO,right=NO;
        for(int i=0;i<N;i++){if(A(i,0)>96)top=YES;if(A(i,N-1)>96)bottom=YES;if(A(0,i)>96)left=YES;if(A(N-1,i)>96)right=YES;}
        BOOL edges=(top?1:0)+(bottom?1:0)+(left?1:0)+(right?1:0)>=3;
        BOOL corners=A(0,0)<64 && A(N-1,0)<64 && A(0,N-1)<64 && A(N-1,N-1)<64;
        // the ring on its diagonals (about 0.16 of the size in from each corner)
        int d=4,hits=0;int pts[4][2]={{d,d},{N-1-d,d},{d,N-1-d},{N-1-d,N-1-d}};
        for(int k=0;k<4;k++){int m=0;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++)m=MAX(m,(int)A(pts[k][0]+dx,pts[k][1]+dy));if(m>64)hits++;}
        #undef A
        extern BOOL WXGImageIsMonochrome(UIImage *image);
        BOOL hole=px[((7)*N+7)*4+3]<64 && px[((7)*N+N-8)*4+3]<64 && px[((N-8)*N+7)*4+3]<64 && px[((N-8)*N+N-8)*4+3]<64;   // a ring, not a disc
        ring=edges && corners && hole && hits==4 && WXGImageIsMonochrome(image);
    }
    cache[key]=@(ring);if(cache.count>64)[cache removeAllObjects];
    return ring;
}
static UIImage *WXGHomePlusSymbol(void) {
    static UIImage *symbol;static dispatch_once_t once;
    dispatch_once(&once,^{
        UIImageSymbolConfiguration *c=[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightLight];
        symbol=[[UIImage systemImageNamed:@"plus.circle" withConfiguration:c] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return symbol;
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
// FIX115 O: a 视频号 capsule's group: WeChat's buttons over it, the view it
// is in (holds the page's title too, not UIKit's copied button container),
// the container FIX113 E shifted (and by how much), and the page's title.
@interface WXGFinderLink : NSObject
@property(nonatomic,strong) NSHashTable<UIView *> *views;
@property(nonatomic,weak) UIView *holder,*container,*title;
@property(nonatomic) CGFloat shift;   // the container's (0: none, or each button's own)
@property(nonatomic) CGFloat placedShift;   // the shift the capsule's place includes (either way; signed: FIX115 Q)
@property(nonatomic) BOOL left;             // FIX115 Q: the screen's left side's (its shift goes right; the right side's left)
@property(nonatomic) BOOL missingNoted;     // its buttons gone outside a transition: a rebuild asked once
@property(nonatomic) BOOL veiled;           // FIX115 O+: its page started leaving: not shown until it is back
// FIX115 T: where its buttons are in the holder at rest (unshifted: UIKit's
// copies of their container for a push / pop are there), the copies hidden,
// and WeChat's buttons hidden while it is veiled (a given-up swipe).
@property(nonatomic) CGRect rest;
@property(nonatomic) CFTimeInterval veiledAtRest;
@property(nonatomic) BOOL leaving;   // FIX115 U: veiled as its page left (not as it came in): only then are WeChat's buttons hidden   // when it was first seen veiled with no transition (0: not)
@property(nonatomic,strong) NSHashTable<UIView *> *copies,*concealed,*checked;   // checked: copies looked at once (review)
@end
@implementation WXGFinderLink
@end
static char WXGFinderLinkKey;
// How visible `view` is as drawn now (presentation opacities; 0 when one is
// hidden), counted up to `stop` (not included: what the capsule shares).
static double WXGOpacityBelow(UIView *view,UIView *stop) {
    double a=1;
    for(UIView *v=view;v && v!=stop;v=v.superview) {
        CALayer *model=v.layer,*shown=model.presentationLayer?:model;
        if(model.hidden || shown.hidden)return 0;
        a*=shown.opacity;
    }
    return a;
}
// The nearest view holding all of them (nil when they share none).
static UIView *WXGCommonParent(NSArray<UIView *> *views) {
    UIView *parent=views.firstObject.superview;
    for(;parent;parent=parent.superview){BOOL all=YES;for(UIView *v in views)if(![v isDescendantOfView:parent]){all=NO;break;}if(all)break;}
    return parent;
}
// FIX115 O: where a 视频号 capsule goes: above the buttons' container, in the
// view that holds the page's title as well (the bar's content view); with no
// title, the bar's child holding the container; the bar when that is the
// container itself.
static UIView *WXGFinderHolder(UIView *container,UIView *title,UIView *bar) {
    if(container==bar)return bar;
    if(title)for(UIView *p=container.superview;p;p=p.superview){if([title isDescendantOfView:p])return p;if(p==bar)break;}
    UIView *top=container;while(top.superview && top.superview!=bar)top=top.superview;
    return top.superview==bar && top!=container?top:bar;
}
// FIX115 O (review): a container the left side's shift may go on: like the
// one bound (in the capsule's holder, not the bar, not holding the page's
// title, on the screen's left half).
static BOOL WXGFinderContainerFits(WXGFinderLink *link,UIView *container) {
    UIView *holder=link.holder;UIWindow *w=holder.window;
    if(!container || !w || container==holder || ![container isDescendantOfView:holder] || [container isKindOfClass:UINavigationBar.class] ||
       (link.title && [link.title isDescendantOfView:container]))return NO;
    CGRect area=WXGWindowRect(container,w);   // FIX115 Q: on its own side's half
    return link.left?CGRectGetMaxX(area)<=CGRectGetMidX(w.bounds)+1:CGRectGetMinX(area)>=CGRectGetMidX(w.bounds)-1;
}
// FIX115 R (user, 10-27 01:47: "仅视频号第一页特殊……第二页包括后面的同步的都是
// 其余玻璃这一项……在里面的都按普通玻璃算"): only 视频号's first page (the
// video feed, WCFinderTimelineTabViewController) has the capsules under
// WeChat's own buttons; its other pages (个人页, 设置, 赞和收藏 …) are
// ordinary pages, the plugin's title row as everywhere else.
static BOOL WXGFinderFeedName(NSString *name) {
    return [name hasPrefix:@"WCFinderTimelineTab"] ||
           [name hasPrefix:@"WCFinderShareList"] ||
           [name hasPrefix:@"WCFinderFeed"] ||
           [name hasPrefix:@"WCFinderFullScreen"] ||
           [name hasPrefix:@"WCFinderStream"] ||
           [name hasPrefix:@"WCFinderProfile"] ||
           [name hasPrefix:@"WCFinderTopicList"] ||
           [name hasPrefix:@"WCFinderRelated"] ||
           [name hasPrefix:@"WCFinderCollection"];
}
static BOOL WXGFinderFeed(UIViewController *vc) {return vc && WXGFinderFeedName(NSStringFromClass(vc.class));}
// FIX115 S: any 视频号 page (its margin is 视频号's, its title view's tabs stay WeChat's).
static BOOL WXGFinderPage(UIViewController *vc) {return vc && [NSStringFromClass(vc.class) hasPrefix:@"WCFinder"];}
// FIX115 V: the separate WeChat Icon Swap tweak's report (its replaced
// names, the originals' looks, names not in its pack), when it is loaded.
static id WXGIconSwapEvidence(void) {
    Class swap=NSClassFromString(@"WISIconSwap");SEL snapshot=NSSelectorFromString(@"snapshot");
    if(!swap || ![swap respondsToSelector:snapshot])return NSNull.null;
    @try {id value=((id (*)(id,SEL))objc_msgSend)(swap,snapshot);return [value isKindOfClass:NSDictionary.class]?value:NSNull.null;}
    @catch(__unused NSException *e){return NSNull.null;}
}
// FIX115 T (user, 10-27 02:49, screen recording: in a swipe back from 视频号
// "返回时图标不消失缺失部分"; diagnostics_7: UIKit's copies of the two button
// containers, _UIReplicantView 16+56 and 360+64 in the capsules' holder, are
// cut at the containers' bounds, and the icons are drawn moved by S's margin
// (12 pt right on the left): the second one cut in half): one of UIKit's
// copies of the buttons at `rest` (a direct child of the holder whose frame
// covers at least half of both: the buttons and itself; review: not any large copy).
static BOOL WXGFinderCopyAt(UIView *v,CGRect rest) {
    static Class replicant;static dispatch_once_t once;dispatch_once(&once,^{replicant=NSClassFromString(@"_UIReplicantView");});
    if(!replicant || ![v isKindOfClass:replicant] || CGRectIsNull(rest) || CGRectIsEmpty(rest))return NO;
    CGRect f=v.frame,i=CGRectIntersection(f,rest);
    if(CGRectIsNull(i) || CGRectIsEmpty(f))return NO;
    return i.size.width*i.size.height>=.5*MAX(f.size.width*f.size.height,rest.size.width*rest.size.height);
}
// The group's buttons' common view now, when all of them are on screen.
static UIView *WXGFinderLiveContainer(WXGFinderLink *link) {
    NSArray<UIView *> *views=link.views.allObjects;if(!views.count)return nil;
    for(UIView *v in views)if(!v.window)return nil;
    return WXGCommonParent(views);
}
@interface WXGHostTickProxy : NSObject
@property(nonatomic,weak) WXGIntegrationHost *owner;
- (void)tick:(CADisplayLink *)link;
@end
@class WXGSideChatInput;
@interface WXGIntegrationHost () <UIAdaptivePresentationControllerDelegate,UIGestureRecognizerDelegate>
@property(nonatomic,strong) WXGOverlay *overlay,*navigationOverlay;
@property(nonatomic,weak) UIControl *chatAvatarControl;   // FIX114 B: the chat's top-right button the avatar is drawn in (host-owned)
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSDictionary *> *navSnapshots;   // FIX114 B: diagnostics
// FIX114 C: the title row's move down now (the home page's "+" follows it),
// the views opened for it (class names, diagnostics), the home page's title
// view when WeChat keeps it out of the bar, the home icon's alignment.
@property(nonatomic) CGFloat rowOffset;
@property(nonatomic,weak) UIView *homeTitleView;
@property(nonatomic) CFTimeInterval homeTitleSearchedAt;
@property(nonatomic,weak) UIView *homeIconHost;
@property(nonatomic,weak) WXGSurface *homeIconSurface;
@property(nonatomic) NSUInteger rowBarContents;   // the bar content views moved (0: none found, or not moved)
@property(nonatomic,strong) WXGSideChatInput *sideChat;   // FIX114 E
- (void)endSideChat:(NSString *)reason;
- (BOOL)adaptsChat:(UIViewController *)chat;   // FIX114 E (review): the host's own page, adapted by it
// FIX113 Q / FIX114 C: the page the title row was last laid out for (its offset is for it).
@property(nonatomic,weak) UIViewController *navCapsuleLeaf;
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
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *firstVisitTraces;
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
// Distinguish the first load of a page in the switching diagnostics.
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
@property(nonatomic,strong) NSHashTable<UIView *> *homeRightRows,*homePlusControls,*homeSearchControls;
@property(nonatomic,weak) WXGSurface *homePlusSurface,*homeSearchSurface;
@property(nonatomic) BOOL homeControlsChanged,homeShowingPullControls;
@property(nonatomic) NSInteger homeIconBranch;
@property(nonatomic) NSUInteger navigationRepairs,homeReattachments,otherBarLayoutsSkipped;
@property(nonatomic) NSUInteger homeNavigationLayoutsReused,homeNavigationRevision;
@property(nonatomic) BOOL homeNavigationNeedsFinalLayout,homeNavigationHidden;
@property(nonatomic,weak) UIView *homeNavigationTitle,*homeNavigationTitleParent;
@property(nonatomic,weak) UIScrollView *homeConversationList;
@property(nonatomic) CGRect homeNavigationRect,homeNavigationWindowBounds,homeNavigationTitleBounds;
@property(nonatomic) UIEdgeInsets homeNavigationSafeArea;
@property(nonatomic) UIUserInterfaceStyle homeNavigationStyle;
@property(nonatomic) NSUInteger homeMovesThisTurn,homeMoveLoopBreaks,homeHostConflicts;   // FIX114 M (crash)
@property(nonatomic) NSUInteger directSearchOpens;   // FIX114 M: the search box capsule straight to WeChat's search page
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
@property(nonatomic,weak) UIControl *homeSearchHidden;   // FIX107: hidden by us (the dock's search stands in)
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
// FIX114 R: the diagnostics export button shown on every page (on the window,
// above any page presented over the tabs), the title-bar trace's clock.
@property(nonatomic,strong) UIButton *exportFloat;
// FIX115 G: the button that opens / closes the settings over any page, and the
// settings it opens (kept: opened again where it was left).
@property(nonatomic,strong) UIButton *settingsFloat;
@property(nonatomic,strong) UINavigationController *floatSettings;
@property(nonatomic,weak) id homeMenuFloatOwner;
@property(nonatomic,weak) UIWindow *homeMenuFloatWindow;
@property(nonatomic) CGRect homeMenuFloatOcclusion;
@property(nonatomic,strong) CADisplayLink *traceLink;
@property(nonatomic) NSUInteger floatExports,traceFrames;
// FIX114 S: the transition (serial) and page the avatar title was last laid
// out for during a push / pop: laid out once then, held until it is over.
@property(nonatomic) NSUInteger middleSerial;
@property(nonatomic,weak) UIViewController *middleLeaf;
@property(nonatomic,copy) NSArray *nativeLookDump;   // FIX114 W: the last back button copied, as it is made
// FIX114 T: the chat page whose top-right button was found (its chevron kept
// while WeChat swaps that button).
@property(nonatomic,weak) UIViewController *chevronLeaf;
- (void)traceTick:(CADisplayLink *)link;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,strong) WXGHostTickProxy *proxy;
@property(nonatomic) BOOL started,queued,refreshing,preserveDockDuringReset,suspendedByCover;
@property(nonatomic) NSUInteger refreshRequest;
@property(nonatomic) UIUserInterfaceStyle appearanceStyle;
@property(nonatomic,weak) id<UIViewControllerTransitionCoordinator> waitingTransition;
@property(nonatomic) CFTimeInterval lastParameters;
@property(nonatomic,copy) NSString *routeToken,*status,*avatarStatus;
// FIX88: the chat's avatar for the title's avatar mode (per page state in
// WXGAvatarState, associated with the page).
@property(nonatomic,weak) UIViewController *avatarLookupPage;
@property(nonatomic) NSUInteger avatarLookups;
// FIX119 E: per tab, how long the main thread stalled in the 0.7 s after its last switch (frames past their time);
// with 按下时 and 会卡的标签等透镜落下再切 on, a tab whose switch stalled the lens is switched once the lens is down.
@property(nonatomic) NSUInteger smartHolds;
@property(nonatomic) NSInteger smartHeldIndex;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSNumber *> *tabStallMS;
@property(nonatomic,copy) NSString *avatarSource;
// FIX95: what the avatar lookup saw (diagnostics) and the photo downloads.
@property(nonatomic,copy) NSDictionary *avatarProbe;
@property(nonatomic,copy) NSString *avatarDownloadStatus;
@property(nonatomic) NSUInteger avatarDownloads,avatarDiskHits;   // FIX100: photos shown from the disk cache
@property(nonatomic) BOOL avatarRetryPending;
// FIX109 B: the chat's pinned module (置顶) moved down with the avatar title.
@property(nonatomic) CGFloat pinnedShift;
@property(nonatomic,weak) UIView *pinnedBar;
@property(nonatomic) BOOL pinnedApplied;
@property(nonatomic) NSUInteger pinnedMoves;
@property(nonatomic,strong) UILongPressGestureRecognizer *dockLongPress;   // FIX89: the settings fallback
// FIX92: the title bar's glass kept above the page (keepNavigationOnTop).
@property(nonatomic) NSUInteger navigationRaises,navigationCovers;
@property(nonatomic,copy) NSString *lastNavigationCover;
@property(nonatomic,strong) NSHashTable *navigationCoverSeen;   // FIX93: each cover logged once
// FIX93: the home list pulled down past its top (pt), and a trace of the title
// bar while it is (diagnostics: what WeChat does to its own title bar).
@property(nonatomic) CGFloat homePull;
@property(nonatomic,strong) NSMutableDictionary<NSNumber *,NSArray *> *badgeArtCache;   // FIX108 D
@property(nonatomic) CGFloat homeFloorHold;            // FIX108 C: the floor while pulled, held a moment after
@property(nonatomic) CGFloat homePullFloorValue,homeRowBottom;
@property(nonatomic) CFTimeInterval homePullSeenAt;
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
@property(nonatomic) BOOL titleAlignedButtons;   // FIX112: this page's buttons at its title's height
@property(nonatomic) CGFloat discreteRowGrowth;
// FIX113 E: 视频号: the native views whose contents are drawn shifted, and what the last pass did.
@property(nonatomic,strong) NSHashTable<UIView *> *finderShiftHosts;
// FIX115 O: 视频号's capsules follow their buttons' (else their page title's)
// opacity: how often the title stood in, nothing was on screen, a new
// container got the left side's shift again, and a cancelled swipe kept them.
@property(nonatomic) NSUInteger finderTitleFrames,finderAwayFrames,finderReshifts,finderKept,finderVeils,finderReveals;
@property(nonatomic) NSUInteger finderCopiesHidden,finderIconsConcealed,finderIconReveals;   // FIX115 T
@property(nonatomic) NSUInteger finderEntryVeils,finderResumeRebuilds,finderDriftRebuilds;   // FIX115 U / R20
@property(nonatomic) NSUInteger finderCopyLogs;   // FIX115 O: logs of what the bar holds as 视频号 leaves
@property(nonatomic,copy) NSDictionary *finderEvidence;   // FIX113 E: how much wider the row is for the discrete dock's balls (pt)
@property(nonatomic) CGFloat titleOffset,titleOffsetBar;   // the title's middle from the bar's, for a bar this tall
@property(nonatomic,weak) UIViewController *titleRetryLeaf;
@property(nonatomic) NSUInteger titleRetries;
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
- (void)alignPinnedModule;
- (BOOL)chatBar:(UIView *)bar extendsTo:(CGPoint)point;
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
// FIX114 R: the trace's display link holds this, not the host.
@interface WXGTraceTickProxy : NSObject
@property(nonatomic,weak) WXGIntegrationHost *owner;
@end
@implementation WXGTraceTickProxy
- (void)traceTick:(CADisplayLink *)link {[self.owner traceTick:link];}
@end
// FIX114 C: the views around the moved title row that would cut it off at
// their bounds (WeChat's bar content clips on some pages) let it show,
// restorably, in a bag of their own (closed again as soon as the row is not
// moved there); only bar-sized ones (never a list, a page or the window).
static NSMutableOrderedSet<NSString *> *WXGRowOpenedClips;
static WXGStateBag *WXGRowClipBag;
static void WXGOpenRowClips(UIView *view,UIView *stop,CGFloat diameter) {
    CGFloat limit=MAX(64,diameter*2);NSUInteger depth=0;
    for(UIView *p=view;p && p!=stop && depth<8;p=p.superview,depth++) {
        if([p isKindOfClass:UIScrollView.class] || [p isKindOfClass:UIWindow.class])break;
        if(!p.clipsToBounds || p.bounds.size.height>limit)continue;
        if(!WXGRowClipBag)WXGRowClipBag=[WXGStateBag new];
        [WXGRowClipBag allowOverflow:p];
        if(!WXGRowOpenedClips)WXGRowOpenedClips=[NSMutableOrderedSet orderedSet];
        if(WXGRowOpenedClips.count<12)[WXGRowOpenedClips addObject:NSStringFromClass(p.class)];
    }
}
static void WXGCloseRowClips(UIView *view,UIView *stop) {
    if(!WXGRowClipBag)return;NSUInteger depth=0;
    for(UIView *p=view;p && p!=stop && depth<8;p=p.superview,depth++) {
        if([p isKindOfClass:UIScrollView.class] || [p isKindOfClass:UIWindow.class])break;
        [WXGRowClipBag restoreView:p];
    }
}
// FIX114 C: a title bar's content (_UINavigationBarContentView: WeChat's
// title and buttons and the local glass behind them) drawn lower by the
// title row's offset. Only a bar the host lays out (its pages: WeChat's bar
// background is cleared there); a web page's or a sheet's bar, with WeChat's
// own background and line, stays as it is (review). One bag for every bar,
// used by the host and by the local glass (before each commit), so a bar is
// moved the same whoever looks at it; 0 (the setting at 0, the title-bar
// adaptation off, 视频号 on top, a page the host leaves) puts it back.
static WXGStateBag *WXGRowBag;
static NSHashTable<UINavigationBar *> *WXGRowHostBars;
static CGFloat WXGRowDownForBar(UINavigationBar *bar) {
    UIWindow *w=bar.window;
    if(!w || ![WXGRowHostBars containsObject:bar] || !WXGPluginEnabled() || !WXGPreferences.shared.nav)return 0;
    id owner=bar.delegate;
    if([owner isKindOfClass:UINavigationController.class] &&
       WXGFinderFeed(((UINavigationController *)owner).topViewController))return 0;
    WXGMetrics m=WXGMeasure(w.bounds.size.width-w.safeAreaInsets.left-w.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
    CGFloat h=bar.bounds.size.height;if(m.button>MAX(36,h))m=WXGMeasure(440*MAX(36,h)/44,1);
    CGFloat pixel=w.screen.scale?:3;return round(WXGTitleRowOffset(m.scale)*pixel)/pixel;
}
// The views of a bar that hold its content: _UINavigationBarContentView;
// (review) a bar without one (another system's layout): every subview but
// its background.
static NSArray<UIView *> *WXGBarContentViews(UINavigationBar *bar) {
    static Class content;static dispatch_once_t once;dispatch_once(&once,^{content=NSClassFromString(@"_UINavigationBarContentView");});
    NSMutableArray *found=[NSMutableArray array],*others=[NSMutableArray array];
    for(UIView *v in bar.subviews) {
        if(content && [v isKindOfClass:content])[found addObject:v];
        else if(!WXGIsPluginView(v) && ![NSStringFromClass(v.class) containsString:@"Background"])[others addObject:v];
    }
    return found.count?found:others;
}
NSUInteger WXGMoveBarContent(UINavigationBar *bar) {
    if(!bar)return 0;
    CGFloat dy=WXGRowDownForBar(bar);
    if(!WXGRowBag){if(dy<.01)return 0;WXGRowBag=[WXGStateBag new];}
    UIWindow *w=bar.window;NSUInteger moved=0;
    WXGMetrics m=WXGMeasure(w.bounds.size.width-w.safeAreaInsets.left-w.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
    for(UIView *v in WXGBarContentViews(bar)) {
        [WXGRowBag shiftContents:v x:0 y:dy];
        if(dy>.01){WXGOpenRowClips(v,bar.superview,m.button);++moved;}
        else WXGCloseRowClips(v,bar.superview);
    }
    return moved;
}
// The host lays this bar out (its title row moves) or leaves it (back to WeChat's).
static void WXGRowAdoptBar(UINavigationBar *bar,BOOL adopt) {
    if(!bar)return;
    if(adopt){if(!WXGRowHostBars)WXGRowHostBars=[NSHashTable weakObjectsHashTable];[WXGRowHostBars addObject:bar];return;}
    if(![WXGRowHostBars containsObject:bar])return;
    [WXGRowHostBars removeObject:bar];WXGMoveBarContent(bar);
}
void WXGRestoreBarContent(void) {[WXGRowBag restore];WXGRowBag=nil;[WXGRowClipBag restore];WXGRowClipBag=nil;[WXGRowHostBars removeAllObjects];}
// (review) A native view's place on screen without the row's own move (the
// bar's content drawn lower): by frames up to the bar.
static CGRect WXGUnmovedWindowRect(UIView *v,UINavigationBar *bar,UIWindow *w) {
    if(!v || !w)return CGRectZero;
    if(bar && [v isDescendantOfView:bar]) {
        CGRect r=v.bounds;UIView *p=v;NSUInteger depth=0;
        for(;p && p!=bar && depth<16;p=p.superview,depth++){r.origin.x+=p.frame.origin.x-p.bounds.origin.x;r.origin.y+=p.frame.origin.y-p.bounds.origin.y;}
        if(p==bar)return [bar convertRect:r toView:w];
    }
    return WXGWindowRect(v,w);
}
// (review) The bar's buttons drawn below its bounds still take their
// touches there: a touch in that band goes to the control drawn under it
// (when the layers' hit-testing follows the moved content; otherwise there
// is none and nothing changes).
static UIView *WXGRowExtendedHit(UINavigationBar *bar,CGPoint point,UIEvent *event) {
    if(!WXGRowBag || bar.hidden || bar.alpha<.01 || !bar.userInteractionEnabled)return nil;
    CGRect b=bar.bounds;
    if(point.x<CGRectGetMinX(b) || point.x>CGRectGetMaxX(b) || point.y<CGRectGetMaxY(b))return nil;
    for(UIView *v in bar.subviews.reverseObjectEnumerator) {
        CGFloat dy=[WXGRowBag contentOffsetOf:v].y;
        if(dy<.01 || point.y>CGRectGetMaxY(b)+dy || v.hidden || v.alpha<.01 || !v.userInteractionEnabled)continue;
        for(UIView *sub in v.subviews.reverseObjectEnumerator) {
            if(sub.hidden || sub.alpha<.01 || !sub.userInteractionEnabled)continue;
            UIView *hit=[sub hitTest:[sub convertPoint:point fromView:bar] withEvent:event];
            for(UIView *c=hit;c && c!=v;c=c.superview)if([c isKindOfClass:UIControl.class] || c.gestureRecognizers.count)return hit;
        }
    }
    return nil;
}
static void WXGHookBarHits(Class c) {
    if(!c)return;SEL selector=@selector(hitTest:withEvent:);Method m=class_getInstanceMethod(c,selector);if(!m)return;
    IMP own=WXGCapturedImplementation(c,selector);Class superclass=class_getSuperclass(c);   // FIX115 B: what was there when installed (as before A)
    IMP replacement=imp_implementationWithBlock(^UIView *(UINavigationBar *bar,CGPoint point,UIEvent *event){
        UIView *hit=((UIView *(*)(id,SEL,CGPoint,UIEvent *))WXGThrough(own,superclass,selector))(bar,selector,point,event);
        if(hit || !WXGRowBag)return hit;
        @try {return WXGRowExtendedHit(bar,point,event);} @catch(__unused NSException *error) {return nil;}
    });
    WXGInstallOverride(c,selector,replacement,method_getTypeEncoding(m));
}
// FIX114 E (user: the half-screen chat a message's notification opens over
// another page keeps WeChat's own input bar): a chat on screen that is not
// the host's page (WeChat's half-screen chat: a sheet over the page, or a
// chat in a window of its own) has its input bar adapted by an adapter of
// its own, ticked by its own display link; the page under it keeps what it
// shows (the host stays on it, covered). Render-server glass only (it reads
// nothing from this process); stopped as soon as the chat is gone, is the
// host's page, or the plugin / the input adaptation is off.
@class WXGSideChatInput;
@interface WXGSideChatTick : NSObject
@property(nonatomic,weak) WXGSideChatInput *owner;
@end
@interface WXGSideChatInput : NSObject
@property(nonatomic,weak) UIViewController *chat;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) WXGInputAdapter *adapter;
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic) BOOL pending;
@property(nonatomic) CGRect lastFrame;
@property(nonatomic) CFTimeInterval movedAt,triedAt,startedAt;
@property(nonatomic,copy) NSString *status;
@property(nonatomic) NSUInteger installs,ticks,layouts,attempts;
- (void)tick:(CADisplayLink *)link;
- (void)layoutNow;
- (void)stop:(NSString *)reason;
@end
@implementation WXGSideChatTick
- (void)tick:(CADisplayLink *)link {[self.owner tick:link];}
@end
static NSMutableArray<NSDictionary *> *WXGSideChatLog;   // diagnostics: what was seen and decided
static void WXGSideChatNote(NSDictionary *entry) {
    if(!WXGSideChatLog)WXGSideChatLog=[NSMutableArray array];
    [WXGSideChatLog addObject:entry];if(WXGSideChatLog.count>16)[WXGSideChatLog removeObjectAtIndex:0];
}
static BOOL WXGSideChatWanted(void) {
    return WXGPluginEnabled() && WXGPreferences.shared.input && WXGEffectiveRenderMode()>=2;
}
// (review) Full width, below the top, down to the window's bottom: a sheet the
// input bar's layout (window width, bottom-anchored) fits.
static BOOL WXGSideChatSheetFrame(CGRect f,UIWindow *w) {
    CGSize s=w.bounds.size;
    return fabs(f.origin.x)<1 && fabs(f.size.width-s.width)<1 && f.origin.y>=1 && CGRectGetMaxY(f)>=s.height-2 && f.size.height>=s.height*.3;
}
@implementation WXGSideChatInput
- (void)start {
    if(_link)return;
    WXGSideChatTick *proxy=[WXGSideChatTick new];proxy.owner=self;
    _link=[CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    WXGConfigureDisplayLink(_link,_window.screen?:UIScreen.mainScreen);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _startedAt=CACurrentMediaTime();
    NSNotificationCenter *n=NSNotificationCenter.defaultCenter;
    for(NSString *name in @[UIKeyboardWillChangeFrameNotification,UIKeyboardDidChangeFrameNotification,UIKeyboardDidHideNotification])
        [n addObserver:self selector:@selector(keyboardChanged:) name:name object:nil];
}
- (void)keyboardChanged:(NSNotification *)note {(void)note;_pending=YES;}
- (void)stop:(NSString *)reason {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_link invalidate];_link=nil;
    @try {[_adapter restore];} @catch(__unused NSException *error) {}
    _adapter=nil;_status=reason;
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[_link invalidate];}
- (void)tick:(CADisplayLink *)link {
    UIViewController *chat=_chat;UIWindow *w=chat.viewIfLoaded.window;
    NSString *why=!chat?@"聊天已关闭":!w?@"聊天不在窗口里":!WXGSideChatWanted()?@"插件或输入栏适配关闭":
        [WXGIntegrationHost.shared adaptsChat:chat]?@"已是宿主的页面":nil;
    if(why){[WXGIntegrationHost.shared endSideChat:why];return;}
    // (review) A system interruption (控制中心, a call banner): wait, as the host's own input bar does.
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    @try {
        _window=w;
        if(!WXGVisible(chat.view,w))return;   // covered or hidden: nothing to draw
        ++_ticks;
        BOOL eligible=!WXGNativeInputLayoutInProgress() && !WXGBackdropCaptureInProgress() && !WXGNavigationCallDepth;
        // (review) Installed when something laid out, backing off, at most 30 tries.
        if(!_adapter.installed && _pending && eligible && _attempts<30 && link.timestamp-_triedAt>MIN(2.,.25*pow(1.4,_attempts))) {
            _triedAt=link.timestamp;++_attempts;_pending=NO;if(!_adapter)_adapter=[WXGInputAdapter new];
            if([_adapter installInController:chat window:w]){++_installs;_attempts=0;_status=@"输入栏已适配";}
            else _status=[_adapter.evidence[@"status"] description]?:@"等待输入栏布局";
        }
        if(!_adapter.installed)return;
        CALayer *shown=chat.view.layer.presentationLayer;
        CGRect frame=shown?[w convertRect:shown.frame fromView:chat.view.superview]:[chat.view convertRect:chat.view.bounds toView:nil];
        if(!CGRectEqualToRect(frame,_lastFrame)){_lastFrame=frame;_movedAt=link.timestamp;}   // the glass moves with the sheet: no new layout
        if(_pending && eligible)[self layoutNow];
        BOOL moving=link.timestamp-_movedAt<.3;
        for(WXGSurface *surface in _adapter.surfaces) {
            if(!surface.active || surface.plain)continue;
            [surface layoutIfNeeded];[surface.glass layoutIfNeeded];
            surface.glass.backgroundMoving=moving || surface.glass.pressAmount>.001;
            [surface tick:link.timestamp];
        }
    } @catch(NSException *error) {
        [WXGIntegrationHost.shared endSideChat:[NSString stringWithFormat:@"异常：%@",error.reason]];
    }
}
- (void)layoutNow {
    if(!_adapter.installed)return;
    _pending=NO;++_layouts;[_adapter layout];
}
- (NSDictionary *)evidence {
    UIViewController *chat=_chat;UIWindow *w=chat.viewIfLoaded.window;
    return @{@"status":_status?:@"",@"chat":chat?NSStringFromClass(chat.class):@"none",@"window":w?NSStringFromClass(w.class):@"none",
             @"frame":NSStringFromCGRect(_lastFrame),@"installs":@(_installs),@"attempts":@(_attempts),@"layouts":@(_layouts),@"ticks":@(_ticks),
             @"adapter":_adapter.evidence?:@{}};
}
@end
@implementation WXGIntegrationHost
+ (instancetype)shared {static WXGIntegrationHost *h;static dispatch_once_t once;dispatch_once(&once,^{h=[self new];});return h;}
- (void)start {
    if(_started)return;_started=YES;_pendingTabIndex=-1;_smartHeldIndex=-1;WXGInstallIdleClock();
    (void)WXGMeHeader.shared;   // FIX118 A: the 我 page's header (it looks for the page itself)
    WXGScrollPerfInstall();   // FIX119 A: every scroll recorded in full (FIX117's 我 page probe is gone: its job is done)
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
    _homeRightRows=[NSHashTable weakObjectsHashTable];_homePlusControls=[NSHashTable weakObjectsHashTable];_homeSearchControls=[NSHashTable weakObjectsHashTable];
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
        ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){[weakHost followFinderCapsulesBeforeCommit];[weakHost flushPendingFrame:NO];});
    if(_commitObserver)CFRunLoopAddObserver(CFRunLoopGetMain(),_commitObserver,kCFRunLoopCommonModes);
    // FIX101: how long Core Animation's own commit (order 2000000) takes: the
    // layout and drawing of everything on screen, WeChat's pages included.
    static CFTimeInterval commitStart;
    CFRunLoopObserverRef beforeCommit=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,true,1999999,
        ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){
            [WXGChatSegments.shared finishHomeTitleRowBeforeCommit];
            commitStart=CACurrentMediaTime();if(WXGTransitionPerfOn)WXGTransitionPerfCommitPhase(YES);
        });
    CFRunLoopObserverRef afterCommit=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,true,2000001,
        ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){
            WXGTransitionPerfCommitPhase(NO);
            if(commitStart>0){double ms=(CACurrentMediaTime()-commitStart)*1000;WXGProfileTotals[WXGProfileCommit]+=ms;commitStart=0;
                if(WXGTransitionPerfOn)WXGTransitionPerfNoteSlot(WXGProfileCommit,ms,NO);}   // FIX113 Z
        });
    if(beforeCommit){CFRunLoopAddObserver(CFRunLoopGetMain(),beforeCommit,kCFRunLoopCommonModes);CFRelease(beforeCommit);}
    if(afterCommit){CFRunLoopAddObserver(CFRunLoopGetMain(),afterCommit,kCFRunLoopCommonModes);CFRelease(afterCommit);}
    WXGLog(@"WeChat Liquid Glass %@ 启动；%@；iOS %@",@WXG_BUILD_DISPLAY_VERSION,NSBundle.mainBundle.bundleIdentifier,UIDevice.currentDevice.systemVersion);
    [self schedule];
}
- (void)changed:(NSNotification *)n {
    if([n.name isEqual:UIApplicationDidReceiveMemoryWarningNotification]) {
        for(WXGPageState *page in _pages) {
            for(WXGSurface *surface in page.pool.allValues)[surface.glass releaseTransientResources];
            for(WXGSurface *surface in page.input.surfaces)[surface.glass releaseTransientResources];
        }
        for(WXGGlassView *glass in _dockView.allGlasses)[glass releaseTransientResources];   // 离散底栏: the pieces too
        [WXGLocalGlass.shared releaseTransientResources];   // FIX107
        WXGInvalidateSharedBackdrop();return;
    }
    if([n.name isEqual:UITextViewTextDidChangeNotification])[self layoutInput];
    if([n.name isEqual:WXGSettingsChanged])[WXGConfig.shared reloadSharedParameters];
    if([n.name isEqual:WXGSettingsChanged] || [n.name isEqual:@"WXGIntegrationChanged"]) {
        _dockStyleKey=nil;_navigationDirty=YES;
        [WXGDecorations.shared applyConfiguration];
        [WXGBubbles.shared applyConfiguration];   // FIX82
        [WXGLocalGlass.shared applyConfiguration];   // FIX107
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
    if([n.name isEqual:UIApplicationDidBecomeActiveNotification]) {
        _inputRepairsSuspended=NO;_hasBeenActive=YES;_lastFrame=0;_navigationDirty=YES;
        [self refresh];
        if(WXGFinderPage(_route.leaf)) {
            __weak WXGIntegrationHost *weakSelf=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.18*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                WXGIntegrationHost *me=weakSelf;
                if(!me || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
                if(WXGFinderPage(me.route.leaf)){me.navigationDirty=YES;++me.finderResumeRebuilds;[me refresh];}
            });
        }
        return;
    }
    if(!_hasBeenActive && ([n.name isEqual:UIWindowDidBecomeVisibleNotification] || [n.name isEqual:UIWindowDidBecomeKeyNotification])) {
        [self refresh];return;
    }
    [self schedule];
}
- (void)poll:(NSTimer *)timer {(void)timer;[self schedule];}
- (void)schedule {
    if(!_started || _queued || _refreshing)return;_queued=YES;
    NSUInteger request=++_refreshRequest;
    // Native appearance/layout hooks can enqueue this request during a tab
    // switch. A synchronous refresh after forwarding already serves it.
    dispatch_async(dispatch_get_main_queue(),^{
        if(!self.queued || self.refreshRequest!=request)return;
        self.queued=NO;
        [self refresh];
    });
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
    _launcher.hidden=WXGSettingsEntryReady || WXGLicenseCurrentState(NO)!=WXGLicenseAuthorized || [self homeMenuCoversFloat:_launcher inWindow:w];
    [_overlay bringSubviewToFront:_launcher];
    [self placeExportFloat:w shown:[WXGConfig.shared extraNumber:@"diagnosticsFloat"]>.5 && WXGLicenseCurrentState(NO)==WXGLicenseAuthorized];   // FIX114 R
    [self placeSettingsFloat:w shown:[WXGConfig.shared extraNumber:@"settingsFloat"]>.5 && WXGLicenseCurrentState(NO)==WXGLicenseAuthorized];   // FIX115 G
}
- (BOOL)homeMenuCoversFloat:(UIButton *)button inWindow:(UIWindow *)window {
    if(!window || !_homeMenuFloatOwner || window!=_homeMenuFloatWindow || button.window!=window)return NO;
    return CGRectIntersectsRect(_homeMenuFloatOcclusion,[button convertRect:button.bounds toView:window]);
}
- (void)applyHomeMenuFloatVisibilityInWindow:(UIWindow *)window {
    if(!window)return;
    BOOL licensed=WXGLicenseCurrentState(NO)==WXGLicenseAuthorized;
    if(_launcher.window==window)
        _launcher.hidden=!licensed || WXGSettingsEntryReady || [self homeMenuCoversFloat:_launcher inWindow:window];
    if(_exportFloat.window==window)
        _exportFloat.hidden=!licensed || [WXGConfig.shared extraNumber:@"diagnosticsFloat"]<=.5 || [self homeMenuCoversFloat:_exportFloat inWindow:window];
    if(_settingsFloat.window==window)
        _settingsFloat.hidden=!licensed || [WXGConfig.shared extraNumber:@"settingsFloat"]<=.5 || [self homeMenuCoversFloat:_settingsFloat inWindow:window];
}
- (void)updateHomeMenuFloatingToolsForOwner:(id)owner inWindow:(UIWindow *)window occupiedRect:(CGRect)rect {
    if(!owner)return;
    UIWindow *previousWindow=_homeMenuFloatWindow;
    if(CGRectIsEmpty(rect)) {
        if(_homeMenuFloatOwner!=owner)return;
        _homeMenuFloatOwner=nil;
        _homeMenuFloatWindow=nil;
        _homeMenuFloatOcclusion=CGRectNull;
        [self applyHomeMenuFloatVisibilityInWindow:previousWindow];
        return;
    }
    if(!window)return;
    if(_homeMenuFloatOwner==owner && previousWindow==window && CGRectEqualToRect(_homeMenuFloatOcclusion,rect))return;
    _homeMenuFloatOwner=owner;
    _homeMenuFloatWindow=window;
    _homeMenuFloatOcclusion=rect;
    if(previousWindow!=window)[self applyHomeMenuFloatVisibilityInWindow:previousWindow];
    [self applyHomeMenuFloatVisibilityInWindow:window];
}
/* FIX115 G (user, 10-26 08:05: a floating button that opens and closes the
   settings at once, to tune a near-perfect standard set against iOS 26): on the
   window like the export button (right side, draggable). Tap: the settings
   fade in over the page (over full screen: the page stays as it is under them,
   its glass still drawn, nothing laid out again on the way back); tap again
   ("收起"): they fade out. The same settings are opened each time (the page
   and scroll position left). Settings opened another way are closed too. */
- (void)placeSettingsFloat:(UIWindow *)w shown:(BOOL)shown {
    if(!shown || !w){_settingsFloat.hidden=YES;return;}
    if(!_settingsFloat) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
        b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        b.backgroundColor=[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.92];
        b.layer.cornerRadius=14;b.layer.borderWidth=.5;b.layer.borderColor=[UIColor.separatorColor resolvedColorWithTraitCollection:w.traitCollection].CGColor;
        b.layer.zPosition=10002;
        [b addTarget:self action:@selector(toggleSettingsFromFloat) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(moveSettingsFloat:)]];
        _settingsFloat=b;
    }
    if(_settingsFloat.superview!=w)[w addSubview:_settingsFloat];
    if(CGRectIsEmpty(_settingsFloat.frame))_settingsFloat.frame=CGRectMake(w.bounds.size.width-8-56,w.safeAreaInsets.top+150,56,28);
    _settingsFloat.hidden=[self homeMenuCoversFloat:_settingsFloat inWindow:w];
    [self titleSettingsFloat];
    if(w.subviews.lastObject!=_settingsFloat)[w bringSubviewToFront:_settingsFloat];
}
- (void)titleSettingsFloat {
    BOOL open=_settings.presentingViewController!=nil;
    NSString *title=open?@"收起":@"设置";
    if(![[_settingsFloat titleForState:UIControlStateNormal] isEqual:title]) {
        [UIView performWithoutAnimation:^{[self->_settingsFloat setTitle:title forState:UIControlStateNormal];[self->_settingsFloat layoutIfNeeded];}];
        _settingsFloat.accessibilityLabel=open?@"收起微信玻璃设置":@"打开微信玻璃设置";
    }
}
- (void)moveSettingsFloat:(UIPanGestureRecognizer *)pan {
    UIView *w=_settingsFloat.superview;if(!w)return;
    CGPoint p=[pan locationInView:w];CGSize size=_settingsFloat.bounds.size;UIEdgeInsets safe=w.safeAreaInsets;
    _settingsFloat.center=CGPointMake(WXGClamp(p.x,size.width*.5+4,w.bounds.size.width-size.width*.5-4),
                                      WXGClamp(p.y,safe.top+size.height*.5,w.bounds.size.height-safe.bottom-size.height*.5));
}
// The floating buttons above what was just presented / dismissed in their window.
- (void)raiseFloats {
    for(UIButton *b in @[_exportFloat?:(id)NSNull.null,_settingsFloat?:(id)NSNull.null]) {
        if(![b isKindOfClass:UIButton.class] || !b.superview || b.hidden)continue;
        if(b.superview.subviews.lastObject!=b)[b.superview bringSubviewToFront:b];
    }
    [self titleSettingsFloat];
}
- (void)toggleSettingsFromFloat {
    __weak WXGIntegrationHost *weakSelf=self;
    UINavigationController *open=_settings.presentingViewController?_settings:nil;
    if(open) {
        if(open.transitionCoordinator || open.isBeingPresented || open.isBeingDismissed)return;
        [open dismissViewControllerAnimated:YES completion:^{WXGIntegrationHost *me=weakSelf;[me raiseFloats];[me schedule];}];
        [_settingsFloat setTitle:@"设置" forState:UIControlStateNormal];
        if(WXGConfig.shared.haptics)[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        return;
    }
    UIViewController *presenter=_route.leaf.viewIfLoaded.window?_route.leaf:(_settingsFloat.window?:_window).rootViewController;
    while(presenter.presentedViewController)presenter=presenter.presentedViewController;
    if(!presenter || presenter.isBeingPresented || presenter.isBeingDismissed || [presenter isKindOfClass:UIAlertController.class] || [presenter isKindOfClass:UIActivityViewController.class])return;
    UINavigationController *nav=_floatSettings;
    if(!nav || nav.presentingViewController) {
        nav=[[UINavigationController alloc]initWithRootViewController:WXGIntegrationSettings()];
        nav.modalPresentationStyle=UIModalPresentationOverFullScreen;nav.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;nav.modalPresentationCapturesStatusBarAppearance=YES;
        _floatSettings=nav;
    }
    [self closeDockSearchAnimated:NO];   // no keyboard over the settings (as presentSettings)
    _lastSceneEvidence=nil;
    [WXGChatSegments.shared coverHomeSearchFor:_route.leaf];
    _suspendedByCover=YES;_dockView.userInteractionEnabled=NO;_searchView.userInteractionEnabled=NO;[_dockView cancelInteraction];
    _settings=nav;
    [_settingsFloat setTitle:@"收起" forState:UIControlStateNormal];
    if(WXGConfig.shared.haptics)[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [presenter presentViewController:nav animated:YES completion:^{
        WXGIntegrationHost *me=weakSelf;[me raiseFloats];
        // the page under the settings, for an export made while they are open
        // (after the fade: the tap itself stays light)
        if(me && me.settings.presentingViewController && !me.lastSceneEvidence)@try {me.lastSceneEvidence=me.evidence;} @catch(__unused NSException *error) {}
    }];
}
/* FIX114 R (user: "现在没有办法在别的地方导出"): the export on every page. A
   small button on the window itself (above the tabs and any chat presented
   over them, as the overlay is not), draggable; a tap exports that page's
   diagnostics at once. While it is shown the title bars are traced. */
- (void)placeExportFloat:(UIWindow *)w shown:(BOOL)shown {
    if(!shown || !w){_exportFloat.hidden=YES;[self setTraceRunning:NO];return;}
    if(!_exportFloat) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:@"导出诊断" forState:UIControlStateNormal];
        b.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        b.backgroundColor=[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.92];
        b.layer.cornerRadius=14;b.layer.borderWidth=.5;b.layer.borderColor=[UIColor.separatorColor resolvedColorWithTraitCollection:w.traitCollection].CGColor;
        b.layer.zPosition=10001;b.accessibilityLabel=@"导出微信玻璃诊断";
        [b addTarget:self action:@selector(exportFromFloat) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(moveExportFloat:)]];
        _exportFloat=b;
    }
    if(_exportFloat.superview!=w)[w addSubview:_exportFloat];
    if(CGRectIsEmpty(_exportFloat.frame))_exportFloat.frame=CGRectMake(8,w.safeAreaInsets.top+150,68,28);
    _exportFloat.hidden=[self homeMenuCoversFloat:_exportFloat inWindow:w];
    if(w.subviews.lastObject!=_exportFloat)[w bringSubviewToFront:_exportFloat];
    [self setTraceRunning:YES];
}
- (void)moveExportFloat:(UIPanGestureRecognizer *)pan {
    UIView *w=_exportFloat.superview;if(!w)return;
    CGPoint p=[pan locationInView:w];CGSize size=_exportFloat.bounds.size;UIEdgeInsets safe=w.safeAreaInsets;
    _exportFloat.center=CGPointMake(WXGClamp(p.x,size.width*.5+4,w.bounds.size.width-size.width*.5-4),
                                    WXGClamp(p.y,safe.top+size.height*.5,w.bounds.size.height-safe.bottom-size.height*.5));
}
- (void)exportFromFloat {
    UIViewController *presenter=_route.leaf.viewIfLoaded.window?_route.leaf:(_exportFloat.window?:_window).rootViewController;
    while(presenter.presentedViewController)presenter=presenter.presentedViewController;
    if(!presenter || [presenter isKindOfClass:UIActivityViewController.class])return;
    ++_floatExports;
    WXGNavTraceEvent([NSString stringWithFormat:@"点了导出诊断（%@）",_route.path?:@""]);
    [self exportDiagnosticsFrom:presenter];
}
- (void)setTraceRunning:(BOOL)on {
    if(on==WXGTraceRunning)return;
    if(on) {
        WXGTraceRunning=YES;
        if(!WXGTraceLast)WXGTraceLast=[NSMutableDictionary dictionary];
        WXGNavTraceEvent([NSString stringWithFormat:@"开始记录（%@）",self.versionString]);
        if(!_traceLink) {
            WXGTraceTickProxy *proxy=[WXGTraceTickProxy new];proxy.owner=self;
            _traceLink=[CADisplayLink displayLinkWithTarget:proxy selector:@selector(traceTick:)];
            WXGConfigureDisplayLink(_traceLink,_window.screen);
            [_traceLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        }
        _traceLink.paused=NO;
    }else {
        WXGNavTraceEvent(@"停止记录");
        WXGTraceRunning=NO;[_traceLink invalidate];_traceLink=nil;[WXGTraceLast removeAllObjects];[WXGTraceOnce removeAllObjects];
    }
}
- (void)traceTick:(CADisplayLink *)link {
    (void)link;
    if(!WXGTraceRunning || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    ++_traceFrames;
    CFTimeInterval start=CACurrentMediaTime();
    @try {[self traceFrame];} @catch(__unused NSException *error) {}
    WXGRecordHomeNavigationWork(_route.nav.navigationBar,0,(CACurrentMediaTime()-start)*1000.);
}
// One line for `key` when what it shows (`shape`: rounded to half points and
// 0.05 of opacity) is not what it showed last.
static BOOL WXGTraceShapeChanged(NSString *key,NSString *shape,NSMutableSet<NSString *> *seen) {
    [seen addObject:key];
    if([WXGTraceLast[key] isEqualToString:shape])return NO;
    WXGTraceLast[key]=shape;
    return YES;
}
static void WXGTraceShapeLine(NSString *key,NSString *line) {
    WXGTraceAppend([NSString stringWithFormat:@"%.3f %@ %@",WXGSecondsSinceLoad(),key,line]);
}
- (void)traceKey:(NSString *)key line:(NSString *)line shape:(NSString *)shape seen:(NSMutableSet<NSString *> *)seen {
    if(WXGTraceShapeChanged(key,shape,seen))WXGTraceShapeLine(key,line);
}
// A WeChat title-bar view: where it is (钮), how visible (透), its content
// shift (挪: the plugin's slot move), its first visible child (图: the icon or
// text as drawn) and the glass in it (玻), each on screen now.
- (void)traceView:(UIView *)v key:(NSString *)key seen:(NSMutableSet<NSString *> *)seen {
    if(!v)return;
    if(!v.window){[self traceKey:key line:@"不在窗口" shape:@"-" seen:seen];return;}
    double a=0;CGRect r=WXGTraceScreenRect(v,v.bounds,&a);
    CALayer *shown=v.layer.presentationLayer?:v.layer;double shift=shown.sublayerTransform.m41;
    WXGSurface *glass=nil;UIView *icon=nil;
    for(UIView *c in v.subviews) {
        if([c isKindOfClass:WXGSurface.class]){if(!glass)glass=(WXGSurface *)c;}
        else if(!icon && !c.hidden && c.alpha>.01 && c.bounds.size.width>1)icon=c;
    }
    if(!glass)for(UIView *c in v.subviews){for(UIView *d in c.subviews)if([d isKindOfClass:WXGSurface.class]){glass=(WXGSurface *)d;break;}if(glass)break;}
    if([v isKindOfClass:UIControl.class] && glass.superview==v)for(UIView *c in v.subviews)if(c!=glass && ![c isKindOfClass:WXGSurface.class] && !c.hidden && c.alpha>.01 && c.bounds.size.width>1){icon=c;break;}
    NSMutableString *shape=[NSMutableString stringWithFormat:@"%ld %ld %ld %ld %ld",lround(r.origin.x*2),lround(r.size.width*2),lround(r.origin.y*2),lround(a*20),lround(shift*2)];
    BOOL masked=NO,drawn=NO;
    CGRect ir=CGRectZero,gr=CGRectZero;double ga=0;
    // FIX114 T: hidden by an empty mask (the plugin's, or WeChat's) — not in the opacity.
    for(UIView *m=v;m && m!=v.window;m=m.superview)if(m.layer.mask && CGRectIsEmpty(m.layer.mask.bounds)){masked=YES;[shape appendString:@" m"];break;}
    if(icon) {
        ir=WXGTraceScreenRect(icon,icon.bounds,NULL);
        [shape appendFormat:@" %ld %ld",lround(ir.origin.x*2),lround(ir.size.width*2)];
    }
    if(glass) {
        CGRect m=glass.materialRect;if(CGRectIsNull(m) || CGRectIsEmpty(m))m=glass.bounds;
        gr=WXGTraceScreenRect(glass,m,&ga);
        if(glass.glass.superview)WXGTraceScreenRect(glass.glass,glass.glass.bounds,&ga);else ga=0;   // the glass itself (the surface may show without it)
        drawn=glass.glass.hasPresentedFrame;
        [shape appendFormat:@" %ld %ld %ld %d %d",lround(gr.origin.x*2),lround(gr.size.width*2),lround(ga*20),glass.active,drawn];
    }else [shape appendString:@" -"];
    if(!WXGTraceShapeChanged(key,shape,seen))return;
    NSMutableString *line=[NSMutableString stringWithFormat:@"钮 %.1f+%.1f y%.1f 透%.2f 挪%.1f",r.origin.x,r.size.width,r.origin.y,a,shift];
    if(masked)[line appendString:@" 遮住"];
    if(icon)[line appendFormat:@" 图 %.1f+%.1f",ir.origin.x,ir.size.width];
    if(glass) {
        [line appendFormat:@" 玻 %.1f+%.1f 透%.2f%@%@",gr.origin.x,gr.size.width,ga,glass.active?@"":@" 未激活",drawn?@"":@" 未出画"];
        if(a>.3 && (ga<.05 || !drawn))[line appendString:@" ✗玻璃看不见"];
    }else {
        [line appendString:@" 玻 无"];
        if(a>.3)[line appendString:@" ✗没有玻璃"];
    }
    WXGTraceShapeLine(key,line);
}
// One of the plugin's own title-row glasses (its title capsule, its buttons).
- (void)traceSurface:(WXGSurface *)s seen:(NSMutableSet<NSString *> *)seen {
    NSString *key=[NSString stringWithFormat:@"插件 %@#%03lx",s.role.length?s.role:@"按钮",(unsigned long)((((uintptr_t)(__bridge void *)s)>>4)&0xfff)];
    if(!s.window || s.hidden){NSString *t=s.window?@"隐藏":@"不在窗口";[self traceKey:key line:t shape:t seen:seen];return;}
    CGRect m=s.materialRect;if(CGRectIsNull(m) || CGRectIsEmpty(m))m=s.bounds;
    double a=0;CGRect r=WXGTraceScreenRect(s,m,&a);
    NSString *shape=[NSString stringWithFormat:@"%ld %ld %ld %ld %ld %d",lround(r.origin.x*2),lround(r.size.width*2),lround(r.origin.y*2),lround(r.size.height*2),lround(a*20),s.active];
    if(WXGTraceShapeChanged(key,shape,seen))
        WXGTraceShapeLine(key,[NSString stringWithFormat:@"%.1f+%.1f y%.1f 高%.1f 透%.2f%@",r.origin.x,r.size.width,r.origin.y,r.size.height,a,s.active?@"":@" 未激活"]);
}
- (void)traceFrame {
    NSMutableSet<NSString *> *seen=[NSMutableSet set];NSMutableArray<UIView *> *traced=[NSMutableArray array];
    UINavigationController *nav=_route.nav;
    if(nav.isViewLoaded && nav.view.window) {
        NSArray<UIViewController *> *stack=nav.viewControllers;
        NSMutableArray<UIViewController *> *pages=[NSMutableArray array];
        for(NSInteger i=(NSInteger)stack.count-1;i>=0 && i>=(NSInteger)stack.count-2;i--)[pages addObject:stack[(NSUInteger)i]];
        id<UIViewControllerTransitionCoordinator> c=nav.transitionCoordinator;
        UIViewController *from=[c viewControllerForKey:UITransitionContextFromViewControllerKey],*to=[c viewControllerForKey:UITransitionContextToViewControllerKey];
        if(from && ![pages containsObject:from])[pages addObject:from];
        if(to && ![pages containsObject:to])[pages addObject:to];
        if(c) {
            NSString *what=[NSString stringWithFormat:@"%@ → %@ %@%@",WXGNavTracePage(from),WXGNavTracePage(to),c.isInteractive?@"手势":@"动画",c.isCancelled?@" 已取消":@""];
            [self traceKey:@"转场" line:[what stringByAppendingFormat:@" 进度%.2f",c.percentComplete] shape:[what stringByAppendingFormat:@" %ld",lround(c.percentComplete*20)] seen:seen];
        }else [self traceKey:@"转场" line:@"无" shape:@"无" seen:seen];
        for(UIViewController *page in pages) {
            UINavigationItem *item=page.navigationItem;NSString *tag=WXGNavTracePage(page);
            NSArray<UIBarButtonItem *> *left=item.leftBarButtonItems?:@[],*right=item.rightBarButtonItems?:@[];
            for(NSUInteger i=0;i<left.count && i<4;i++)[self traceView:left[i].customView key:[NSString stringWithFormat:@"%@ 左%lu",tag,(unsigned long)i] seen:seen];
            for(NSUInteger i=0;i<right.count && i<4;i++)[self traceView:right[i].customView key:[NSString stringWithFormat:@"%@ 右%lu",tag,(unsigned long)i] seen:seen];
            if(item.titleView)[self traceView:item.titleView key:[tag stringByAppendingString:@" 标题"] seen:seen];
            for(UIBarButtonItem *b in [left arrayByAddingObjectsFromArray:right])if(b.customView)[traced addObject:b.customView];
        }
        // FIX114 T: the buttons with our glass that no item holds (WeChat replaced them; still on screen).
        for(UIView *anchor in WXGLocalGlass.shared.navButtonAnchors) {
            BOOL known=NO;for(UIView *t in traced)if(anchor==t || [anchor isDescendantOfView:t]){known=YES;break;}
            if(!known)[self traceView:anchor key:[NSString stringWithFormat:@"旧按钮 %@#%03lx",NSStringFromClass(anchor.class),(unsigned long)((((uintptr_t)(__bridge void *)anchor)>>4)&0xfff)] seen:seen];
        }
    }
    NSMutableOrderedSet<WXGSurface *> *own=[NSMutableOrderedSet orderedSetWithArray:_buttons?:@[]];
    if(_departingButtons)[own addObjectsFromArray:_departingButtons];
    for(WXGSurface *s in own)[self traceSurface:s seen:seen];
    // FIX115 O: as a 视频号 page leaves, what else its capsules' view holds
    // (UIKit's copies of its buttons; not the items' views, not the title's).
    if(_nativeTransition && WXGFinderFeed(_transitionFrom)) {
        UIView *holder=nil;
        for(WXGSurface *s in own)if([s.role isEqual:@"finderCapsule"]){holder=((WXGFinderLink *)objc_getAssociatedObject(s,&WXGFinderLinkKey)).holder;if(holder)break;}
        UIView *title=_transitionFrom.navigationItem.titleView;NSUInteger listed=0;
        for(UIView *v in holder.window?holder.subviews:@[]) {
            if(listed>=8)break;
            if([v isKindOfClass:WXGSurface.class] || (title && (v==title || [title isDescendantOfView:v])))continue;
            BOOL item=NO;for(UIView *t in traced)if(t==v || [t isDescendantOfView:v]){item=YES;break;}
            if(item)continue;
            ++listed;double a=0;CGRect r=WXGTraceScreenRect(v,v.bounds,&a);
            NSString *key=[NSString stringWithFormat:@"栏里 %@#%03lx",NSStringFromClass(v.class),(unsigned long)((((uintptr_t)(__bridge void *)v)>>4)&0xfff)];
            [self traceKey:key line:[NSString stringWithFormat:@"%.1f+%.1f y%.1f 透%.2f%@",r.origin.x,r.size.width,r.origin.y,a,v.hidden?@" 隐藏":@""]
                     shape:[NSString stringWithFormat:@"%ld %ld %ld %ld",lround(r.origin.x*2),lround(r.size.width*2),lround(a*20),(long)v.hidden] seen:seen];
        }
    }
    for(NSString *key in WXGTraceLast.allKeys)
        if(![seen containsObject:key]){[WXGTraceLast removeObjectForKey:key];WXGTraceAppend([NSString stringWithFormat:@"%.3f %@ 不见了",WXGSecondsSinceLoad(),key]);}
}
// FIX105: take every plugin layer out of WeChat's view tree (not just hide its
// effects) for an unlicensed account, so nothing of the plugin is present.
// ensureOverlay puts them back when the account becomes authorized.
- (void)detachOverlays {
    self.navCapsuleLeaf=nil;   // FIX113 Q
    [WXGChatSegments.shared hideTitleBar];
    if(_overlay.superview)[_overlay removeFromSuperview];
    if(_navigationOverlay.superview)[_navigationOverlay removeFromSuperview];
    _launcher.hidden=YES;
    [_exportFloat removeFromSuperview];[self setTraceRunning:NO];   // FIX114 R
    [_settingsFloat removeFromSuperview];   // FIX115 G
}
- (void)moveEntry:(UIPanGestureRecognizer *)pan {
    CGPoint p=[pan locationInView:_overlay];
    _launcher.center=CGPointMake(WXGClamp(p.x,14,_overlay.bounds.size.width-14),WXGClamp(p.y,_window.safeAreaInsets.top+14,_overlay.bounds.size.height-_window.safeAreaInsets.bottom-14));
}
- (void)resetRoute {
    self.navCapsuleLeaf=nil;   // FIX113 Q: no title row of ours now
    _homePlusSurface=nil;_homeSearchSurface=nil;_homeControlsChanged=YES;_homeShowingPullControls=NO;
    if(!_nativeTransition)[WXGChatSegments.shared hideTitleBar];
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
    // FIX114 E: a chat on screen that is not this host's page (the half-screen chat).
    static Class chatClass;static dispatch_once_t chatOnce;dispatch_once(&chatOnce,^{chatClass=NSClassFromString(@"BaseMsgContentViewController");});
    if(chatClass && [controller isKindOfClass:chatClass])[self noteSideChat:controller];
    if(_needsEarlyLayout && controller==_pendingController && controller.view.window && !_refreshing){
        _needsEarlyLayout=NO;[self schedule];
    }
}
- (BOOL)homeConversationListMoving {
    UIScrollView *list=_homeConversationList;
    return list && list.window==_window && (list.tracking || list.dragging || list.decelerating || WXGHomeListInNativePull(list));
}
- (void)navigationBarDidLayout:(UINavigationBar *)bar {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    UINavigationController *nav=_route.nav;
    static Class home;static dispatch_once_t once;dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");});
    if(_window && _route.primary && nav.topViewController==_route.leaf && [_route.leaf isKindOfClass:home] &&
       !_nativeTransition && !_pendingController && !nav.transitionCoordinator && nav.navigationBar.window==_window) {
        if(bar!=nav.navigationBar){++_otherBarLayoutsSkipped;return;}
        // The native controls move inside their real hosts on a vertical scroll.
        // Their presentation is already followed each frame. Rebind on a change
        // of host/geometry, and do one full validation once the scroll settles.
        UIView *title=_route.leaf.navigationItem.titleView;
        if(!_navigationDirty && !_navigationBindingPending && !_suspendedByCover && !WXGNavigationCallDepth &&
           _navCapsuleLeaf==_route.leaf && _buttons.count && [self homeConversationListMoving] &&
           _homeNavigationRevision==WXGConfigRevision() && _homeNavigationHidden==(bar.hidden || nav.navigationBarHidden) &&
           _homeNavigationStyle==bar.traitCollection.userInterfaceStyle &&
           title==_homeNavigationTitle && title.superview==_homeNavigationTitleParent &&
           CGRectEqualToRect(title.bounds,_homeNavigationTitleBounds) && CGRectEqualToRect(_window.bounds,_homeNavigationWindowBounds) &&
           UIEdgeInsetsEqualToEdgeInsets(_window.safeAreaInsets,_homeNavigationSafeArea) &&
           CGRectEqualToRect(WXGWindowRect(bar,_window),_homeNavigationRect) &&
           [_navigationBindingKey isEqual:[self currentNavigationBindingKey]]) {
            ++_homeNavigationLayoutsReused;_homeNavigationNeedsFinalLayout=YES;
            [_navStates reapply];
            return;
        }
    }
    [self nativeNavigationLaidOut];
}
- (void)nativeNavigationLaidOut {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){_navigationDirty=YES;return;}
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
// FIX108: WXGLocalGlass puts a glass behind the title-bar buttons this host
// leaves native: never one it has its own glass for, nothing while the
// title-bar setting is off. FIX108 B: decided from the button's own
// navigation (its top page, whether it is presented), by the same rules as
// WXGRouteForWindow, not from `_route`: a page presented over the tabs never
// becomes `_route` (the host suspends under covers), and `_route` follows a
// push or pop only after the buttons of the new page have laid out.
// FIX114 B (user: a chat without the avatar title: WeChat's own back button
// and icons, only a capsule of the right size behind them): its title-bar
// controls (all but the avatar button, when that is on) and its title stay
// WeChat's; the local glass puts capsules behind them.
- (BOOL)chatBarNativeFor:(UIViewController *)leaf {
    static Class chat;static dispatch_once_t once;dispatch_once(&once,^{chat=NSClassFromString(@"BaseMsgContentViewController");});
    return chat && [leaf isKindOfClass:chat] && !WXGPreferences.shared.avatarTitle && [WXGConfig.shared extraNumber:@"chatNativeBar"]>.5;
}
// FIX114 B: 顶部按钮保持微信原生 (every page but the home page and 视频号):
// the buttons stay WeChat's (icon, text, place), capsules behind them.
- (BOOL)navButtonsNativeFor:(UIViewController *)leaf {
    if([self chatBarNativeFor:leaf])return YES;
    if([WXGConfig.shared extraNumber:@"navNativeButtons"]<=.5 || !leaf)return NO;
    NSString *name=NSStringFromClass(leaf.class);
    return ![name isEqual:@"NewMainFrameViewController"] && !WXGFinderFeedName(name);   // FIX115 R: 视频号's other pages as any page
}
/* FIX114 V (user, 23:46, after FIX114 M-U: "就还是这个问题，能不能另想个办法，只把
   原生的这些抓进自建的"): the glass inside WeChat's own buttons could not be
   made steady: WeChat replaces those buttons when a push ends, when a swipe
   back starts and when it is cancelled, and the system's transition draws
   copies of them cut at the buttons' bounds (the user's screenshot: both
   capsules cut flat). The plugin's own buttons never had any of that. So the
   native look is now drawn by the plugin's own buttons: same row, pool,
   transitions and touches as 自己画的 buttons, with a copy of WeChat's
   button (its icon, text, unread count, as laid out) in the glass where the
   local glass had it, and WeChat's button hidden (原生按钮放进插件自己的玻璃按钮,
   default on; off: the glass inside WeChat's buttons as before). */
static UIViewController *WXGNavItemOwner(UINavigationController *nav,UIView *control);
- (BOOL)nativeLookFor:(UIViewController *)leaf {
    return [self navButtonsNativeFor:leaf] && [WXGConfig.shared extraNumber:@"navNativeLook"]>.5;
}
- (BOOL)drawsChatTitleForView:(UIView *)view {
    if(!view || !WXGPluginEnabled() || !WXGPreferences.shared.nav)return NO;
    UINavigationBar *bar=nil;NSUInteger depth=0;
    for(UIView *p=view.superview;p && depth<12;p=p.superview,depth++)if([p isKindOfClass:UINavigationBar.class]){bar=(UINavigationBar *)p;break;}
    id delegate=bar.delegate;if(![delegate isKindOfClass:UINavigationController.class])return NO;
    static Class chat;static dispatch_once_t once;dispatch_once(&once,^{chat=NSClassFromString(@"BaseMsgContentViewController");});
    UINavigationController *nav=delegate;
    UIViewController *owner=nav.topViewController;
    UIView *titleView=owner.navigationItem.titleView;
    if(!titleView || (view!=titleView && ![view isDescendantOfView:titleView])) {
        owner=WXGNavItemOwner(nav,view);
        titleView=owner.navigationItem.titleView;
        if(!titleView || (view!=titleView && ![view isDescendantOfView:titleView]))return NO;
    }
    if(![owner isKindOfClass:chat] || [self chatBarNativeFor:owner] || WXGLicenseCurrentState(NO)!=WXGLicenseAuthorized)return NO;
    if(!WXGPreferences.shared.avatarTitle) {
        // A plain chat capsule is also drawn by buildNavigation. Suppress the
        // local material during its first layout, before that method masks the
        // text. A separately presented chat can still own its native material.
        return nav==_route.nav && !_route.unsupported && !_suspendedByCover;
    }
    if(!_navStates)_navStates=[WXGStateBag new];
    [_navStates conceal:titleView];return YES;
}
// FIX114 B (review): the page whose bar items hold this control (in a push /
// pop both pages' items are in the bar; the top page alone made a chat's
// buttons lose their capsules as the chat slid out).
static UIViewController *WXGNavItemOwner(UINavigationController *nav,UIView *control) {
    // FIX114 O (user: in a half swipe back the native buttons' capsules went
    // missing): the page being popped leaves the stack as the pop starts (a
    // swipe back too), so its buttons were taken for the page below's (the
    // home page, not native): the local glass took their capsules down. The
    // transition's pages are looked at as well.
    NSMutableArray<UIViewController *> *pages=[nav.viewControllers.reverseObjectEnumerator.allObjects mutableCopy]?:[NSMutableArray array];
    id<UIViewControllerTransitionCoordinator> coordinator=nav.transitionCoordinator;
    if(coordinator)for(NSString *k in @[UITransitionContextFromViewControllerKey,UITransitionContextToViewControllerKey]) {
        UIViewController *vc=[coordinator viewControllerForKey:k];if(vc && ![pages containsObject:vc])[pages addObject:vc];
    }
    for(UIViewController *vc in pages) {
        UINavigationItem *item=vc.navigationItem;
        NSMutableArray<UIView *> *views=[NSMutableArray array];
        for(UIBarButtonItem *b in item.leftBarButtonItems?:@[])if(b.customView)[views addObject:b.customView];
        for(UIBarButtonItem *b in item.rightBarButtonItems?:@[])if(b.customView)[views addObject:b.customView];
        if(item.titleView)[views addObject:item.titleView];
        for(UIView *v in views)if(v==control || [control isDescendantOfView:v])return vc;
    }
    return nav.topViewController;
}
// FIX115 O: a control in one of the pages' own bar views (an item's custom
// view or the title view: WeChat's buttons), not in one of UIKit's own item buttons.
static BOOL WXGCustomItemHolds(UINavigationController *nav,UIView *control) {
    if(!nav || !control)return NO;
    NSMutableArray<UIViewController *> *pages=[nav.viewControllers mutableCopy]?:[NSMutableArray array];
    id<UIViewControllerTransitionCoordinator> coordinator=nav.transitionCoordinator;
    if(coordinator)for(NSString *k in @[UITransitionContextFromViewControllerKey,UITransitionContextToViewControllerKey]) {
        UIViewController *vc=[coordinator viewControllerForKey:k];if(vc && ![pages containsObject:vc])[pages addObject:vc];
    }
    for(UIViewController *vc in pages) {
        UINavigationItem *item=vc.navigationItem;
        if(item.titleView && (item.titleView==control || [control isDescendantOfView:item.titleView]))return YES;
        for(UIBarButtonItem *b in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]])
            if(b.customView && (b.customView==control || [control isDescendantOfView:b.customView]))return YES;
    }
    return NO;
}
// A side's items when none of them has a custom view (UIKit's own buttons
// only: LoadControl's top right); a side with one of WeChat's: none.
// FIX115 Q (review): `control` is in a page's title view (the stack's or the transition's pages).
static BOOL WXGInTitleView(UINavigationController *nav,UIView *control) {
    if(!nav || !control)return NO;
    NSMutableArray<UIViewController *> *pages=[nav.viewControllers mutableCopy]?:[NSMutableArray array];
    id<UIViewControllerTransitionCoordinator> coordinator=nav.transitionCoordinator;
    if(coordinator)for(NSString *k in @[UITransitionContextFromViewControllerKey,UITransitionContextToViewControllerKey]) {
        UIViewController *vc=[coordinator viewControllerForKey:k];if(vc && ![pages containsObject:vc])[pages addObject:vc];
    }
    for(UIViewController *vc in pages){UIView *t=vc.navigationItem.titleView;if(t && (t==control || [control isDescendantOfView:t]))return YES;}
    return NO;
}
// FIX115 S: one of 视频号's title tabs (赞和收藏 / 最近看过: WCFinderTabSwitchView,
// probe 10-27 00:53), in a title view or not.
static BOOL WXGFinderTab(UIView *control,UIView *bar) {
    for(UIView *v=control;v && v!=bar;v=v.superview)if([NSStringFromClass(v.class) hasPrefix:@"WCFinderTabSwitch"])return YES;
    return NO;
}
static NSArray<UIBarButtonItem *> *WXGSystemItems(NSArray<UIBarButtonItem *> *items) {
    for(UIBarButtonItem *item in items)if(item.customView)return @[];
    return items?:@[];
}
// `control` is (in) the view of one of the item's own UIKit buttons, on a side
// whose items are all UIKit's (WXGSystemItems).
static BOOL WXGSystemItemHolds(UINavigationItem *item,UIView *control) {
    if(!item || !control)return NO;
    for(NSArray<UIBarButtonItem *> *side in @[WXGSystemItems(item.leftBarButtonItems),WXGSystemItems(item.rightBarButtonItems)])
        for(UIBarButtonItem *b in side) {
            id raw=WXGRead(b,@"view");if(![raw isKindOfClass:UIView.class])continue;
            UIView *view=raw;if(view==control || [control isDescendantOfView:view] || [view isDescendantOfView:control])return YES;
        }
    return NO;
}
// FIX115 O: a 视频号 page's bar items hold this control (in the stack or in
// the transition; unlike WXGNavItemOwner, no top-page fallback).
static BOOL WXGFinderItemHolds(UINavigationController *nav,UIView *control) {
    if(!nav || !control)return NO;
    NSMutableArray<UIViewController *> *pages=[nav.viewControllers mutableCopy]?:[NSMutableArray array];
    id<UIViewControllerTransitionCoordinator> coordinator=nav.transitionCoordinator;
    if(coordinator)for(NSString *k in @[UITransitionContextFromViewControllerKey,UITransitionContextToViewControllerKey]) {
        UIViewController *vc=[coordinator viewControllerForKey:k];if(vc && ![pages containsObject:vc])[pages addObject:vc];
    }
    for(UIViewController *vc in pages) {
        if(!WXGFinderFeed(vc))continue;
        UINavigationItem *item=vc.navigationItem;
        for(UIBarButtonItem *b in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]])
            if(b.customView && (b.customView==control || [control isDescendantOfView:b.customView]))return YES;
    }
    return NO;
}
// FIX114 N: a glass that only opens its `original` (the chat title's capsule
// and avatar open 聊天信息) and does not stand in for that button.
static BOOL WXGSurfaceOnlyOpens(WXGSurface *surface) {
    return [surface.role isEqual:@"chatTitle"] || [surface.role isEqual:@"avatar"];
}
- (BOOL)leavesNavigationControlNative:(UIView *)control {
    if(!control || !WXGPluginEnabled() || !WXGPreferences.shared.nav)return NO;
    // FIX114 N (user, 08:35: in the native mode the chat's settings button lost its
    // glass): the title capsule and the avatar open that button (their
    // `original`) without drawing it; only a glass that draws it takes it over.
    for(WXGSurface *surface in _buttons)if(surface.original==control && !WXGSurfaceOnlyOpens(surface))return NO;
    UINavigationBar *bar=nil;NSUInteger depth=0;
    for(UIView *p=control.superview;p && depth<12;p=p.superview,depth++)if([p isKindOfClass:UINavigationBar.class]){bar=(UINavigationBar *)p;break;}
    id delegate=bar.delegate;if(![delegate isKindOfClass:UINavigationController.class])return NO;
    UINavigationController *nav=delegate;UIViewController *leaf=nav.topViewController;
    if(!leaf || !control.window)return NO;
    UIViewController *owner=WXGNavItemOwner(nav,control);
    if([self navButtonsNativeFor:owner] && !(WXGPreferences.shared.chatAvatarButton && control==_chatAvatarControl)) {   // FIX114 B
        // FIX114 V: the host's own glass with WeChat's look (unless switched off,
        // or a button painting its own: a green 完成); pages the host does not
        // take (web pages, sheets) as below.
        if(![self nativeLookFor:owner] || WXGNativeNavButtonFilled(control))return YES;
    }
    NSUInteger guard=0;
    for(UIViewController *c=leaf;c && guard<16;c=(c==nav?nav.parentViewController:c.parentViewController),guard++) {
        NSString *name=NSStringFromClass(c.class);
        if([name containsString:@"Flutter"] || [name containsString:@"WebView"] || [name hasPrefix:@"WAUINavigation"] || [name hasPrefix:@"WXG"])return YES;
    }
    UIViewController *root=nav;guard=0;
    while(root.parentViewController && guard<16){root=root.parentViewController;guard++;}
    if(!root.presentingViewController)return NO;
    // A chat presented full screen is the host's own (WXGPresentedChatStack).
    static Class chat;static dispatch_once_t once;
    dispatch_once(&once,^{chat=NSClassFromString(@"BaseMsgContentViewController");});
    UIWindow *w=control.window;
    if(chat && [leaf isKindOfClass:chat] && root.isViewLoaded && root.view.window==w) {
        CGRect f=WXGWindowRect(root.view,w),c=leaf.isViewLoaded?WXGWindowRect(leaf.view,w):CGRectNull;
        BOOL sheet=!CGRectIsNull(c) && !(fabs(c.origin.y)<1 && fabs(c.size.height-w.bounds.size.height)<1);   // FIX114 E: a half-screen chat: WeChat's buttons, capsules behind
        if(!sheet && fabs(f.origin.x)<1 && fabs(f.origin.y)<1 && fabs(f.size.width-w.bounds.size.width)<1 && fabs(f.size.height-w.bounds.size.height)<1)return NO;
    }
    return YES;
}
// The navigation item and the taskbar close area can both stay in the window.
// A mask hides replaced ink without changing WeChat's opacity or target/action.
- (NSInteger)homeBranchForHost:(UIView *)host {
    if(!host || !_window || host.window!=_window)return -1;
    if([host isDescendantOfView:_route.nav.navigationBar])return 0;
    static Class closeArea;static dispatch_once_t once;
    dispatch_once(&once,^{closeArea=NSClassFromString(@"WAMainFrameTaskBarCloseArea");});
    for(UIView *v=host.superview;v;v=v.superview) {
        if([v isKindOfClass:closeArea])return [v isDescendantOfView:_route.leaf.viewIfLoaded]?1:-1;
        if([v isKindOfClass:UIScrollView.class])break;
    }
    return -1;
}
- (UIView *)homeHostFrom:(NSHashTable<UIView *> *)hosts current:(UIView *)current pulling:(BOOL)pulling {
    UIView *bars[2]={nil,nil};
    CGFloat opacity[2]={-1.,-1.};
    for(UIView *candidate in hosts) {
        NSInteger branch=[self homeBranchForHost:candidate];
        if(branch<0 || CGRectIsEmpty(candidate.bounds))continue;
        if([candidate isKindOfClass:UIControl.class] && hosts!=_homeGestureHosts && !WXGCanForward((UIControl *)candidate))continue;
        // Search itself deliberately fades out while the list's search is visible.
        UIView *row=hosts==_homeSearchControls?candidate.superview:candidate;
        CGFloat alpha=1.;
        for(UIView *v=row;v && v!=_window;v=v.superview) {
            CALayer *layer=v.layer.presentationLayer?:v.layer;
            if(layer.hidden){alpha=0;break;}
            alpha*=layer.opacity;
        }
        if(alpha>opacity[branch] || (alpha==opacity[branch] && candidate==current)) {
            bars[branch]=candidate;opacity[branch]=alpha;
        }
    }
    return bars[WXGHomeUsesPullControls(opacity[0],opacity[1],pulling)?1:0];
}
- (NSHashTable<UIView *> *)rememberHomeAction:(UIControl *)control verify:(BOOL)verify {
    if(![control isKindOfClass:UIControl.class] || [self homeBranchForHost:control]<0)return nil;
    NSHashTable *known=[_homePlusControls containsObject:control]?_homePlusControls:
        [_homeSearchControls containsObject:control]?_homeSearchControls:nil;
    if(known && !verify)return known;
    NSArray *actions=WXGActionNames(control);
    NSHashTable *hosts=[actions containsObject:@"showRightTopMenuBtn"]?_homePlusControls:
        [actions containsObject:@"onSearchButtonTapped"]?_homeSearchControls:nil;
    if(hosts!=known) {
        if(known){[known removeObject:control];[_navStates unconceal:control];}
        if(hosts)[hosts addObject:control];
        _homeControlsChanged=YES;
    }
    return hosts;
}
- (void)concealHomeTwins:(NSHashTable<UIView *> *)hosts except:(UIView *)visible {
    for(UIView *v in hosts)if(v!=visible && [self homeBranchForHost:v]>=0)[_navStates conceal:v];
    if(visible)[_navStates unconceal:visible];
}
- (void)navigationControlLaidOut:(UIView *)view {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(WXGNavigationCallDepth){[_navStates reapply];_navigationBindingPending=YES;return;}
    if(!WXGPluginEnabled() || !WXGPreferences.shared.nav)return;
    if(!_window && view.window){[self refresh];}
    if(view.window!=_window || !_window)return;
    if(_route.primary && !_nativeTransition && !_suspendedByCover && !_pendingController &&
       [NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"]) {
        NSHashTable *hosts=[self rememberHomeAction:(UIControl *)view verify:NO];
        if(hosts==_homeSearchControls && _navStates && [self dockSearchAvailable]){[_navStates conceal:view];return;}
        WXGSurface *cover=hosts==_homePlusControls?_homePlusSurface:hosts==_homeSearchControls?_homeSearchSurface:nil;
        if(hosts && cover.active && cover.window==_window && cover.motionOwner==_route.leaf) {
            [_navStates conceal:view];
            if(cover.original!=view)_homeControlsChanged=YES;
            if(cover.original==view && cover.motionHost!=view && ![cover.motionHost isDescendantOfView:view])_navigationBindingPending=YES;
            return;
        }
        if(hosts && !_refreshing && ![view isDescendantOfView:_route.nav.navigationBar]) {
            _navigationBindingPending=YES;return;
        }
    }
    for(WXGSurface *surface in _buttons)if(surface.original==view && !WXGSurfaceOnlyOpens(surface)){[_navStates reapply];return;}   // FIX114 N
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
- (void)homeRightRowDidLayout:(UIView *)row {
    if(WXGBackdropCaptureInProgress())return;
    if(row.window && ![_homeRightRows containsObject:row])[_homeRightRows addObject:row];
    if(_suspendedByCover || _pendingController || _nativeTransition || !_route.primary || !_navStates ||
       !WXGPluginEnabled() || !WXGPreferences.shared.nav ||
       ![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] || [self homeBranchForHost:row]<0)return;
    for(UIView *v in WXGViews(row,20)) {
        if(![v isKindOfClass:UIControl.class] || !WXGCanForward((UIControl *)v) || CGRectIsEmpty(v.bounds))continue;
        NSHashTable *hosts=[self rememberHomeAction:(UIControl *)v verify:NO];
        if(!hosts)continue;
        WXGSurface *surface=hosts==_homePlusControls?_homePlusSurface:_homeSearchSurface;
        if(surface.active && surface.window==_window && surface.motionOwner==_route.leaf) {
            [_navStates conceal:v];
            if(surface.original!=v)_homeControlsChanged=YES;
        }else if(!_refreshing && (hosts==_homePlusControls || ![self dockSearchAvailable]))_navigationBindingPending=YES;
    }
}
- (void)repairDetachedNavigationBindings {
    if(_refreshing || _nativeTransition || !_route.leaf || _suspendedByCover ||
       !WXGPluginEnabled() || !WXGPreferences.shared.nav)return;
    if(_homeNavigationNeedsFinalLayout) {
        if(_navCapsuleLeaf!=_route.leaf)_homeNavigationNeedsFinalLayout=NO;
        else if(!_pendingController && !_route.nav.transitionCoordinator && ![self homeConversationListMoving]) {
            _homeNavigationNeedsFinalLayout=NO;[self nativeNavigationLaidOut];return;
        }
    }
    BOOL missing=_navigationBindingPending || ![_navigationBindingKey isEqual:[self currentNavigationBindingKey]];
    for(WXGSurface *surface in _buttons) {
        if(surface.motionOwner!=_route.leaf || WXGSurfaceInNativeView(surface))continue;
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
    UINavigationBar *bar=_route.nav.navigationBar;
    NSMutableString *key=[NSMutableString stringWithFormat:@"%p/%p/%p",_route.leaf,item,bar.topItem];
    if(WXGFinderFeed(_route.leaf) && bar)[key appendFormat:@"/fb:%lu",(unsigned long)bar.subviews.count];
    for(UIBarButtonItem *button in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]]) {
        UIView *host=button.customView;
        if(!host){id value=WXGRead(button,@"view");if([value isKindOfClass:UIView.class])host=value;}
        [key appendFormat:@"/%p:%p:%p:%p:%p:%lu",button,host,host.superview,host.window,host.subviews.firstObject,(unsigned long)host.subviews.count];
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
// FIX114 M (the user's crash, 07:14, iOS 26.6: killed after 10 s of one
// layout pass while WeChat went to the background): the home page's left
// glass was moved into WeChat's button view again and again inside one
// layout pass. Each move took it out of the window and back in, and each
// time its colours were resolved again (UIKit's appearance setters, slow).
// Decide between the two hosts before reparenting. A move keeps the glass
// in the window and the existing per-turn budget also covers reorders.
- (BOOL)homeMoveAllowed {
    if(_homeMovesThisTurn==0)dispatch_async(dispatch_get_main_queue(),^{WXGIntegrationHost.shared.homeMovesThisTurn=0;});
    if(++_homeMovesThisTurn>4){++_homeMoveLoopBreaks;_navigationBindingPending=YES;return NO;}
    return YES;
}
- (void)homeGestureLaidOut:(UIView *)host {
    if(WXGBackdropCaptureInProgress()){++_samplingLayoutSkips;return;}
    if(host.window && ![_homeGestureHosts containsObject:host]){[_homeGestureHosts addObject:host];_homeControlsChanged=YES;}
    if(!_window && host.window && !_refreshing)[self refresh];
    if(_refreshing || !_route.primary || _pendingController || _nativeTransition || _suspendedByCover ||
       ![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] ||
       !WXGPluginEnabled() || !WXGPreferences.shared.nav)return;
    WXGSurface *bound=_surfacePool[@"nativeLeft0"];
    if([self homeBranchForHost:host]<0){++_ignoredHomeHosts;if(bound.motionHost==host)_homeControlsChanged=YES;return;}
    UIView *wanted=[self homeHostFrom:_homeGestureHosts current:bound.motionHost pulling:[self currentHomePull]>.5];
    if(!wanted)return;
    if(bound.active && bound.superview==wanted && wanted!=host){++_homeHostConflicts;[_navStates conceal:host];return;}
    _refreshing=YES;
    @try {
        if(!_navStates)_navStates=[WXGStateBag new];
        WXGMetrics m=WXGMeasure(_window.bounds.size.width-_window.safeAreaInsets.left-_window.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
        CGFloat h=_route.nav.navigationBar.bounds.size.height;
        if(m.button>MAX(36,h))m=WXGMeasure(440*MAX(36,h)/44,1);
        WXGSurface *surface=[self bindHomeGesture:wanted diameter:m.button slot:@"nativeLeft0"];
        if(surface.superview)[self concealHomeTwins:_homeGestureHosts except:surface.superview];
    } @catch(NSException *error){WXGLog(@"首页手势挂载：%@",error.reason);_navigationDirty=YES;}
    @finally {_refreshing=NO;}
}
- (WXGSurface *)bindHomeGesture:(UIView *)host diameter:(CGFloat)diameter slot:(NSString *)slot {
    if(!host.superview || host.window!=_window)return nil;
    // FIX114 M (crash): moves and reorders are counted per turn of the run loop
    // (looked at before the pool resets the glass: a skipped turn leaves it as it is).
    WXGSurface *pooled=_surfacePool[slot];
    if(pooled.superview && (pooled.superview!=host || host.subviews.firstObject!=pooled) && ![self homeMoveAllowed]){[self schedule];return pooled;}
    WXGSurface *surface=[self pooledSurface:slot];
    if(surface.superview!=host || surface.motionHost!=host)++_homeReattachments;
    surface.role=@"nativeGesture";surface.motionHost=host;
    surface.motionOwner=_route.leaf;surface.followsNative=NO;surface.materialOnly=YES;[surface setImage:nil title:nil count:nil];
    surface.glass.sourceView=_route.leaf.view;
    surface.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,host,_route.nav.navigationBar]:@[host,_route.nav.navigationBar];
    CGRect material=CGRectMake(CGRectGetMidX(host.bounds)-diameter*.5,CGRectGetMidY(host.bounds)-diameter*.5,diameter,diameter);
    [_navStates allowOverflow:host];[self alignHomeGestureIcon:host diameter:diameter];
    [surface placeMaterial:material inParent:host];
    // FIX114 B (user: the home page's two top buttons sit at different
    // distances from the screen's edges): the right one is placed at the
    // title row's margin (safe area + m.edge), this one was centred on
    // WeChat's own view. Its contents (WeChat's icon and this glass, its
    // subview) are drawn shifted to the same margin; the view itself and its
    // gesture stay where WeChat put them.
    {
        UIWindow *w=_window;
        WXGMetrics m=WXGMeasure(w.bounds.size.width-w.safeAreaInsets.left-w.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
        CGFloat h=_route.nav.navigationBar.bounds.size.height;
        if(m.button>MAX(36,h))m=WXGMeasure(440*MAX(36,h)/44,1);
        CGFloat scale=w.screen.scale?:3,centre=[host convertPoint:CGPointMake(CGRectGetMidX(host.bounds),0) toView:w].x;
        // FIX114 C: the margin and the row's move down are settings.
        CGFloat dx=round((w.safeAreaInsets.left+WXGTitleRowEdge(m.scale)+diameter*.5-centre)*scale)/scale;
        // (In a title bar, the bar's content is moved down already.)
        CGFloat dy=[host isDescendantOfView:_route.nav.navigationBar]?[self navigationHomePullFor:host]:round(WXGTitleRowOffset(m.scale)*scale)/scale;
        [_navStates shiftContents:host x:fabs(dx)>=.5 && fabs(dx)<=32?dx:0 y:dy];
        if(dy>.01)[self openRowClipsFrom:host upTo:nil metrics:m];else WXGCloseRowClips(host,nil);
        _homeIconHost=host;_homeIconSurface=surface;_homeIconBranch=[self homeBranchForHost:host];
        if(_homeIconBranch==1) {
            Class titleClass=NSClassFromString(@"MFTitleView");
            for(UIView *title in host.superview.subviews)if([title isKindOfClass:titleClass]) {
                [_navStates shiftContents:title x:0 y:dy];
                if(dy>.01)[self openRowClipsFrom:title upTo:nil metrics:m];else WXGCloseRowClips(title,nil);
                break;
            }
        }
    }
    if(host.subviews.firstObject!=surface)[host insertSubview:surface atIndex:0];
    [surface observeTouchesInView:host];   // FIX70: the button's own view takes the touches
    surface.hidden=NO;surface.alpha=1;return surface;
}
// FIX114 C (user: the top buttons' distance to the screen's top set by
// hand): WeChat's own views of the title row drawn lower by the row's
// offset (their layers' sublayerTransform, restorable): the bar's content
// (WXGMoveBarContent: the title and native buttons with the glass behind
// them; the host's own glass is placed lower itself), and the home page's
// title when WeChat keeps it outside the bar. 0 puts them back.
- (void)moveNativeRow:(UINavigationBar *)bar by:(CGFloat)dy metrics:(WXGMetrics)m home:(BOOL)home {
    static Class homeTitle;static dispatch_once_t once;dispatch_once(&once,^{homeTitle=NSClassFromString(@"MFTitleView");});
    WXGRowAdoptBar(bar,YES);_rowBarContents=WXGMoveBarContent(bar);
    if(!home || !homeTitle)return;
    UIView *itemTitle=_route.leaf.navigationItem.titleView;
    if(itemTitle.window==_window && [itemTitle isKindOfClass:homeTitle])_homeTitleView=itemTitle;
    UIView *title=_homeTitleView;
    if((!title || title.window!=_window) && CACurrentMediaTime()-_homeTitleSearchedAt>1) {
        _homeTitleSearchedAt=CACurrentMediaTime();
        title=nil;
        for(UIView *host in _homeGestureHosts) {
            if(host.window!=_window)continue;
            UIView *row=host;for(NSUInteger i=0;i<4 && row.superview;i++)row=row.superview;
            for(UIView *v in WXGViews(row,160))if([v isKindOfClass:homeTitle]){title=v;break;}
            if(title)break;
        }
        _homeTitleView=title;
    }
    if(!title || title.window!=_window)return;
    // In the bar: moved with its content (review: a shift of its own from a
    // pull-down, when WeChat had it in the list, goes back to 0).
    BOOL inBar=[title isDescendantOfView:bar];
    if(inBar)[self followHomeNavigationContents:title];
    else {
        [_navStates shiftContents:title x:0 y:dy];
        if(dy>.01)[self openRowClipsFrom:title upTo:nil metrics:m];else WXGCloseRowClips(title,nil);
    }
}
- (void)openRowClipsFrom:(UIView *)view upTo:(UIView *)stop metrics:(WXGMetrics)m {
    WXGOpenRowClips(view,stop,m.button);
}
// FIX114 C: where the home page's left icon is drawn against its glass (the
// user saw the glass move to the margin and the star stay): their centres on
// screen, the shift, how deep the image is in the button's view.
- (NSDictionary *)homeIconEvidenceNow {
    UIView *host=_homeIconHost;WXGSurface *surface=_homeIconSurface;
    UIWindow *w=_window;if(!w || !surface || !host || host.window!=w)return @{};
    UIImageView *image=nil;
    for(UIView *v in WXGViews(host,32))if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && WXGVisible(v,w) && v.bounds.size.width>4 && v.bounds.size.width<80){image=(UIImageView *)v;break;}
    NSUInteger depth=0;for(UIView *p=image.superview;p && p!=host && depth<16;p=p.superview)++depth;
    CGRect glass=[surface convertRect:surface.materialRect toView:w],icon=CGRectNull;
    if(image) {   // the drawn glyph (its ink), as WeChat's image has it off-centre
        NSDictionary *ink=WXGRenderedInkEvidence(image);NSArray *r=ink[@"windowRect"];
        icon=[ink[@"available"] boolValue] && r.count==4?CGRectMake([r[0] doubleValue],[r[1] doubleValue],[r[2] doubleValue],[r[3] doubleValue]):[image convertRect:image.bounds toView:w];
    }
    CGPoint shift=[_navStates contentOffsetOf:host];
    return @{@"glassMidX":@(round(CGRectGetMidX(glass)*100)/100),@"glassMidY":@(round(CGRectGetMidY(glass)*100)/100),
        @"iconMidX":CGRectIsNull(icon)?@(-1):@(round(CGRectGetMidX(icon)*100)/100),@"iconMidY":CGRectIsNull(icon)?@(-1):@(round(CGRectGetMidY(icon)*100)/100),
        @"shiftX":@(shift.x),@"shiftY":@(shift.y),@"imageDepth":@(image?(NSInteger)depth:-1)};
}
// FIX114 E: a chat laid out that is on screen but not the page the host
// adapts: in a window of its own, or presented over the page without
// covering it whole (a sheet: the host stays on the page under it, covered).
- (BOOL)adaptsChat:(UIViewController *)chat {return chat && chat==_route.leaf && !_route.unsupported;}
- (void)noteSideChat:(UIViewController *)chat {
    UIWindow *w=chat.viewIfLoaded.window;
    if(_sideChat.chat==chat){_sideChat.pending=YES;return;}
    if(!w || [self adaptsChat:chat])return;
    if(!WXGSideChatWanted() || !WXGVisible(chat.view,w))return;
    // (review) Not a chat on its way in or out (a push, a swipe back), nor one
    // of the host's own stack: the host takes those.
    if(chat.navigationController.transitionCoordinator || [_route.nav.viewControllers containsObject:chat])return;
    CGRect f=[chat.view convertRect:chat.view.bounds toView:nil];
    UIViewController *root=chat;NSUInteger guard=0;
    while(root.parentViewController && guard<16){root=root.parentViewController;guard++;}
    BOOL otherWindow=_window && w!=_window,presented=root.presentingViewController!=nil;
    BOOL full=fabs(f.origin.y)<1 && fabs(f.size.height-w.bounds.size.height)<1;   // the route's own test (WXGPresentedChatStack)
    BOOL side=(otherWindow || (presented && !full)) && WXGSideChatSheetFrame(f,w);
    // (diagnostics) once per chat and decision every 2 s: layouts come many a second
    static NSString *lastKey;static CFTimeInterval lastAt;
    NSString *key=[NSString stringWithFormat:@"%p/%d/%d/%d/%.0f",chat,otherWindow,presented,full,f.origin.y];
    BOOL noted=[key isEqual:lastKey] && CACurrentMediaTime()-lastAt<2;
    if(!noted){lastKey=key;lastAt=CACurrentMediaTime();}
    if(!noted)WXGSideChatNote(@{@"time":@(round(WXGSecondsSinceLoad()*10)/10),@"window":NSStringFromClass(w.class),@"level":@(w.windowLevel),
                      @"hostWindow":@(w==_window),@"root":NSStringFromClass(root.class),@"presented":@(presented),@"frame":NSStringFromCGRect(f),
                      @"routeLeaf":_route.leaf?NSStringFromClass(_route.leaf.class):@"none",@"route":_route.path?:@"",@"side":@(side)});
    if(!side)return;
    __weak WXGIntegrationHost *weakSelf=self;__weak UIViewController *weakChat=chat;
    dispatch_async(dispatch_get_main_queue(),^{   // not inside WeChat's layout pass
        WXGIntegrationHost *host=weakSelf;UIViewController *c=weakChat;
        if(!host || !c || !c.viewIfLoaded.window || [host adaptsChat:c] || host.sideChat.chat==c || !WXGSideChatWanted())return;
        if(host.sideChat)[host endSideChat:@"换了一个聊天"];
        WXGSideChatInput *side=[WXGSideChatInput new];side.chat=c;side.window=c.view.window;side.pending=YES;side.status=@"开始";
        host.sideChat=side;[side start];
    });
}
- (void)endSideChat:(NSString *)reason {
    WXGSideChatInput *side=_sideChat;if(!side)return;
    _sideChat=nil;[side stop:reason];
    WXGSideChatNote(@{@"time":@(round(WXGSecondsSinceLoad()*10)/10),@"ended":reason?:@"",@"installs":@(side.installs),@"layouts":@(side.layouts)});
}
- (CGFloat)navigationHomePullFor:(UIView *)native {
    UIScrollView *list=_homeConversationList;
    if(_nativeTransition || _pendingController || !list || list.window!=_window ||
       ![native isDescendantOfView:_route.nav.navigationBar] ||
       ![list isDescendantOfView:_route.leaf.viewIfLoaded])return 0.;
    return WXGHomePullTranslation(list.contentOffset.y,WXGHomeConversationTop(list),_window.screen.scale);
}
- (CGFloat)homeCenterForSurface:(WXGSurface *)surface fallback:(CGFloat)rest {
    UIView *native=surface.original?:surface.motionHost;
    UINavigationBar *bar=_route.nav.navigationBar;
    BOOL attached=native && native.window==_window;
    CGFloat center=attached?CGRectGetMidY(WXGUnmovedWindowRect(native,bar,_window))+_rowOffset:rest;
    if(surface.homePlusAnchor && attached && !_nativeTransition && !_pendingController && _homePanel==0 &&
       bar.window==_window && !CGRectIsEmpty(bar.bounds) && [self homeBranchForHost:native]==1) {
        CGFloat navCenter=CGRectGetMidY(WXGWindowRect(bar,_window))+_rowOffset;
        for(UIView *button in _homePlusControls) {
            if(![button isDescendantOfView:bar] || CGRectIsEmpty(button.bounds))continue;
            navCenter=CGRectGetMidY(WXGUnmovedWindowRect(button,bar,_window))+_rowOffset;
            break;
        }
        return WXGHomePlusPullCenter(center,navCenter,[self navigationHomePullFor:bar]);
    }
    // The close-area twin already moves with the list. If only the stationary
    // item exists yet, follow the same rubber-banded displacement as the title.
    return center+[self navigationHomePullFor:attached?native:bar];
}
- (void)followHomeAction:(WXGSurface *)surface hosts:(NSHashTable<UIView *> *)hosts pulling:(BOOL)pulling {
    if(!surface.active || surface.motionOwner!=_route.leaf)return;
    UIControl *button=(UIControl *)[self homeHostFrom:hosts current:surface.original pulling:pulling];
    if(!button || button==surface.original)return;
    if(!surface.original && surface.perform){_navigationBindingPending=YES;return;}
    UIView *ink=[self motionInkForControl:button];
    surface.original=button;surface.enabled=button.enabled;
    [surface setNativeIconSource:ink preservingColors:NO];
    [surface bindMotionHost:ink owner:_route.leaf];
    [_navStates conceal:button];
}
- (void)followHomeNavigationContents:(UIView *)view {
    UINavigationBar *bar=_route.nav.navigationBar;
    if(!view || ![view isDescendantOfView:bar])return;
    CGPoint shift=[_navStates contentOffsetOf:view];
    CGFloat pull=[self navigationHomePullFor:view];
    if(view==_route.leaf.navigationItem.titleView && _homeIconBranch==1 && _homeIconSurface.active &&
       _homeIconSurface.motionOwner==_route.leaf && _homeIconSurface.window==_window &&
       (_homePanel>0. || WXGHomeHasPanelRange(_homeConversationList.adjustedContentInset.top,
                                             _homeConversationList.bounds.size.height,_window.screen.scale))) {
        CGRect row=[_homeIconSurface convertRect:_homeIconSurface.materialRect toView:_window];
        pull=MAX(0.,CGRectGetMidY(row)-CGRectGetMidY(WXGWindowRect(bar,_window))-_rowOffset);
    }
    if(shift.y==pull)return;
    if((shift.y==0.)!=(pull==0.)) {
        if(pull>0.)WXGOpenRowClips(view,bar.superview,_homeIconSurface.materialRect.size.height?:bar.bounds.size.height);
        else WXGCloseRowClips(view,bar.superview);
    }
    [_navStates shiftContents:view x:shift.x y:pull];
}
- (void)syncHomeControls {
    if(_refreshing || !_route.primary || _nativeTransition || _pendingController || WXGNavigationCallDepth ||
       _navCapsuleLeaf!=_route.leaf || !WXGPreferences.shared.nav)return;
    BOOL pulling=[self currentHomePull]>.5;
    if(!_homeControlsChanged && !pulling && !_homeShowingPullControls)return;
    _homeControlsChanged=NO;
    [self followHomeAction:_homePlusSurface hosts:_homePlusControls pulling:pulling];
    [self followHomeAction:_homeSearchSurface hosts:_homeSearchControls pulling:pulling];
    WXGSurface *left=_surfacePool[@"nativeLeft0"];
    UIView *wanted=[self homeHostFrom:_homeGestureHosts current:left.motionHost pulling:pulling];
    if(wanted && left.active && (left.superview!=wanted || left.motionHost!=wanted || _homeIconBranch!=[self homeBranchForHost:wanted])) {
        _refreshing=YES;
        @try {
            [self bindHomeGesture:wanted diameter:left.materialRect.size.height slot:@"nativeLeft0"];
            if(left.superview)[self concealHomeTwins:_homeGestureHosts except:left.superview];
        } @finally {_refreshing=NO;}
    }
    if(left.active)[self followHomeNavigationContents:left.superview];
    // With title groups disabled the real title and its local glass live
    // inside MFTitleView. The nav copy needs the same pull as the nav button;
    // its close-area twin already inherits the list's displacement.
    UIView *title=_route.leaf.navigationItem.titleView;
    if(title && !title.layer.mask && [title isKindOfClass:NSClassFromString(@"MFTitleView")])
        [self followHomeNavigationContents:title];
    _homeShowingPullControls=pulling || [self homeBranchForHost:left.motionHost]==1 ||
        [self homeBranchForHost:_homePlusSurface.original]==1 || [self homeBranchForHost:_homeSearchSurface.original]==1;
}
- (void)followHomeSurfaces {
    if(![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"])return;
    [self syncHomeControls];
    for(WXGSurface *surface in _buttons) {
        UIView *native=surface.original?:surface.motionHost;
        if((!native || native.window!=_window) && !surface.homePlusAnchor)continue;
        if([surface.role isEqual:@"nativeGesture"]) {
            // Geometry and alpha now inherit from the actual native host. Only
            // a genuine rehome requires reattachment, not every display frame.
            if(surface.superview!=native)[self bindHomeGesture:native diameter:surface.materialRect.size.height slot:@"nativeLeft0"];
        }else if((surface.original || surface.homePlusAnchor) && surface.superview.window==_window) {
            // Preserve TEST4's corrected x grid and raster-centered icon, follow native y.
            CGFloat y=[self homeCenterForSurface:surface fallback:_homeRowBottom-surface.materialRect.size.height*.5];
            CGPoint center=[_window convertPoint:CGPointMake(0,y) toView:surface.superview];
            CGRect frame=surface.followsNative?surface.restingFrame:surface.frame;
            frame.origin.y=center.y-frame.size.height*.5;
            [CATransaction begin];[CATransaction setDisableActions:YES];
            if(surface.followsNative)WXGResetOwnedTransform(surface);
            if(!CGRectEqualToRect(frame,surface.frame))surface.frame=frame;
            if(surface.followsNative)surface.restingFrame=frame;
            else if(surface.homePlusAnchor && !_nativeTransition) {
                surface.alpha=WXGClamp(1.-_homePanel,0.,1.);surface.hidden=surface.alpha<.001;
            }
            [CATransaction commit];
        }
    }
}
- (void)primeNewSurfaces {
    CFTimeInterval now=CACurrentMediaTime();if(now-_lastPrime<1./WXGScreenCaptureFPS(_window.screen))return;
    NSMutableArray *all=[NSMutableArray array];
    for(WXGSurface *surface in _buttons)if(surface.active && !surface.plain && surface.glass.active)[all addObject:surface.glass];
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
           [v isKindOfClass:UILabel.class] || [v isKindOfClass:UIScrollView.class] || WXGMeHeaderOwnsView(v))continue;   // FIX120 G: the 我 header's bar background is ours
        CGRect r=WXGWindowRect(v,w);
        if(r.size.width<width-1)continue;
        BOOL hairline=r.size.height<=1.5 && fabs(CGRectGetMinY(r)-navBottom)<=2 && !v.subviews.count;
        BOOL plate=fabs(CGRectGetMinY(r))<=1 && fabs(r.size.height-navBottom)<=6;
        BOOL shade=[v isKindOfClass:UIImageView.class] && fabs(CGRectGetMinY(r))<=1 && r.size.height>navBottom+6 &&
            r.size.height<=navBottom+40 && !v.subviews.count;
        if(!hairline && !plate && !shade)continue;
        if(WXGHomeTaskbarContains(v))continue;
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
        if(v.hidden || WXGIsPluginView(v) || [v isKindOfClass:UIScrollView.class] || [v isKindOfClass:UIControl.class] || WXGMeHeaderOwnsView(v))continue;
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
    // FIX109 E: WeChat's own tab bar pictures stay while the plugin is off or
    // was withdrawn (the dock view is kept, hidden, once made).
    if(!WXGPluginEnabled() || !WXGPreferences.shared.dock)return;
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
// FIX119 B: a control inside a list's content (it scrolls with the list).
static BOOL WXGInListContent(UIView *v,UIView *stop) {
    for(UIView *s=v.superview;s && s!=stop;s=s.superview)if([s isKindOfClass:UITableView.class] || [s isKindOfClass:UICollectionView.class])return YES;
    return NO;
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
    BOOL home=_route.primary && [NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
    UIView *plus=nil,*search=nil;
    if(home) {
        for(UIView *row in _homeRightRows)if([self homeBranchForHost:row]>=0)[candidates addObjectsFromArray:WXGViews(row,20)];
        for(UIView *v in candidates)if([v isKindOfClass:UIControl.class] && WXGCanForward((UIControl *)v))[self rememberHomeAction:(UIControl *)v verify:YES];
        BOOL pulling=[self currentHomePull]>.5;
        plus=[self homeHostFrom:_homePlusControls current:_homePlusSurface.original pulling:pulling];
        search=[self homeHostFrom:_homeSearchControls current:_homeSearchSurface.original pulling:pulling];
        if(plus)[candidates addObject:plus];
        if(search)[candidates addObject:search];
    }
    for(UIView *v in candidates) {
        if(![v isKindOfClass:UIControl.class] || !WXGCanForward((id)v))continue;
        if(home && v!=plus && v!=search)continue;
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
        if(v.hidden && (!home || v!=_homeSearchHidden))continue;
        if(!home && !WXGVisible(v.superview,_window))continue;
        BOOL existing=NO;for(WXGSurface *s in _buttons)if(s.original==v){existing=YES;break;}
        // FIX107: the search button WeChat (8.0.78) puts next to the title bar's
        // right button (通讯录, and the home page in a grey test): one bar item
        // holds both, the search one at alpha 0 while the list's search bar is
        // on screen and faded in once it scrolls away. It gets its glass even
        // at alpha 0, the glass following WeChat's alpha (no glass left empty,
        // none missing while it fades in). The home page keeps hiding it while
        // the dock's own search button stands in (since FIX10).
        BOOL fadingSearch=[WXGActionNames((id)v) containsObject:@"onSearchButtonTapped"];
        if(home && fadingSearch) {
            _homeSearchControl=(UIControl *)v;
            if([self dockSearchAvailable]){[_navStates hide:v];_homeSearchHidden=(UIControl *)v;continue;}
            if(_homeSearchHidden==v) {
                // Hidden while the dock search was on: WeChat's own rule for its
                // alpha (shown once the list's search bar is off screen), not
                // whatever it was when we hid it.
                [_navStates restoreView:v];_homeSearchHidden=nil;
                UISearchBar *listBar=[self homeSearchBar];
                CGFloat barBottom=CGRectGetMaxY(WXGWindowRect(_route.nav.navigationBar,_window));
                BOOL listBarShown=listBar && WXGVisible(listBar,_window) && CGRectGetMaxY(WXGWindowRect(listBar,_window))>barBottom+1;
                v.alpha=listBarShown?0:1;
            }
        }
        if(home && !fadingSearch && ![WXGActionNames((id)v) containsObject:@"showRightTopMenuBtn"])continue;
        if(!home && !existing && !fadingSearch && !WXGVisible(v,_window))continue;
        CGRect r=WXGWindowRect(v,_window),nr=WXGWindowRect(bar,_window);
        if(r.size.height<16 || r.size.height>80 || r.size.width<4 || r.size.width>180 || (!home && fabs(CGRectGetMidY(r)-CGRectGetMidY(nr))>24))continue;
        // Only extra corner actions qualify outside the actual navigation bar.
        if(![v isDescendantOfView:bar] && CGRectGetMidX(r)>_window.bounds.size.width*.32 && CGRectGetMidX(r)<_window.bounds.size.width*.68)continue;
        // FIX119 B (16 Pro Max, diagnostics_4: the 我 page's QR button, in WeChat's header in its list, scrolled up to the
        // bar's height, got a glass button of its own beside 设置): nothing in a list's content is one of the bar's buttons.
        // (Not on the home page: WeChat moves its top buttons into the home list while it is pulled down, FIX94.)
        if(!home && ![v isDescendantOfView:bar] && WXGInListContent(v,_window))continue;
        if(![out containsObject:v])[out addObject:v];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){
        if(home && a!=b)return a==search?NSOrderedAscending:NSOrderedDescending;
        NSInteger ai=[self navigationOrder:(id)a],bi=[self navigationOrder:(id)b];
        CGFloat width=self.window.bounds.size.width;
        CGFloat x=ai==NSNotFound?CGRectGetMidX(WXGWindowRect(a,self.window)):(ai>=900?width-1-(1000-ai)*44:1+ai*44);
        CGFloat y=bi==NSNotFound?CGRectGetMidX(WXGWindowRect(b,self.window)):(bi>=900?width-1-(1000-bi)*44:1+bi*44);
        // FIX107: two controls of one bar item (通讯录's add + search): by their own x.
        if(x==y){x=CGRectGetMidX(WXGWindowRect(a,self.window));y=CGRectGetMidX(WXGWindowRect(b,self.window));}
        return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;}];
    return out;
}
- (WXGSurface *)pooledSurface:(NSString *)slot {
    WXGSurface *surface=_surfacePool[slot];
    if(!surface){surface=[WXGSurface new];_surfacePool[slot]=surface;}
    if(![_buttons containsObject:surface])[_buttons addObject:surface];
    if(surface.glass.glassScopeOverride>=0)surface.glass.glassScopeOverride=-1;
    if(surface.glass.rimScopeOverride>=0)surface.glass.rimScopeOverride=-1;
    if(surface.glass.veilOverride)surface.glass.veilOverride=nil;
    if(!surface.active){surface.active=YES;[surface applyConfig];}
    surface.hidden=NO;surface.materialOnly=NO;surface.perform=nil;surface.original=nil;surface.homePlusAnchor=NO;
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
        // FIX115 C: only this plugin's own files (16 hex digits + .plist) are counted
        // and pruned; anything else in a directory of this name is left alone.
        NSMutableArray<NSString *> *names=[NSMutableArray array];
        NSCharacterSet *notHex=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
        for(NSString *name in [files contentsOfDirectoryAtPath:directory error:NULL])
            if(name.length==22 && [name hasSuffix:@".plist"] && [[name substringToIndex:16] rangeOfCharacterFromSet:notHex].location==NSNotFound)[names addObject:name];
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
// FIX118 A: the user's own photo for the 我 page's header (the contact's HD
// address first, kept on disk as the chats' avatars are; nil while it downloads).
// FIX118 B (diagnostics_17: no download ever started: the self contact has no
// address of its own): else WeChat's head-image manager: its original HD
// picture (asked to download it once), its original one; methods checked by
// their type encodings before they are called.
static NSString *WXGSelfAvatarStatus;
NSString *WXGSelfAvatarState(void) {return WXGSelfAvatarStatus?:@"";}
static UIImage *WXGSelfAvatarFromManager(id manager,NSString *user) {
    for(NSString *name in @[@"getOriginalHDHeadImg:withCategory:",@"getOriginalHeadImage:withCategory:"]) {
        SEL sel=NSSelectorFromString(name);
        Method m=[manager respondsToSelector:sel]?class_getInstanceMethod(object_getClass(manager),sel):NULL;
        if(!m || method_getNumberOfArguments(m)!=4)continue;
        char r[8]={0},a[8]={0},b[8]={0};method_getReturnType(m,r,sizeof r);method_getArgumentType(m,2,a,sizeof a);method_getArgumentType(m,3,b,sizeof b);
        int width=WXGAvatarIntegerWidth(b);
        if(r[0]!='@' || a[0]!='@' || !width)continue;
        for(unsigned int category=0;category<=1;category++) {
            id image=nil;
            @try {
                image=width==8?((id (*)(id,SEL,id,unsigned long long))objc_msgSend)(manager,sel,user,(unsigned long long)category):
                               ((id (*)(id,SEL,id,unsigned int))objc_msgSend)(manager,sel,user,category);
            } @catch(__unused NSException *error) {image=nil;}
            if([image isKindOfClass:UIImage.class] && [(UIImage *)image size].width>8){WXGSelfAvatarStatus=[NSString stringWithFormat:@"%@ %u",name,category];return image;}
        }
    }
    return nil;
}
// FIX118 C (diagnostics_18: "读不到自己的联系人": the encoding-checked calls of
// the chat avatars refused the self contact's path): read as the licence reads
// the account (plain calls, guarded), the account itself as a fallback name.
static id WXGSelfCall(id target,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if(!target || ![target respondsToSelector:selector])return nil;
    @try {return ((id (*)(id,SEL))objc_msgSend)(target,selector);} @catch(__unused NSException *error) {return nil;}
}
static id WXGSelfService(id container,NSString *className) {
    Class cls=NSClassFromString(className);SEL selector=NSSelectorFromString(@"getService:");
    if(!container || !cls || ![container respondsToSelector:selector])return nil;
    @try {return ((id (*)(id,SEL,Class))objc_msgSend)(container,selector,cls);} @catch(__unused NSException *error) {return nil;}
}
- (UIImage *)selfAvatarPhoto {
    static UIImage *best;static BOOL askedHD;
    id context=WXGSelfCall(NSClassFromString(@"MMContext"),@"currentContext")?:WXGSelfCall(NSClassFromString(@"MMContext"),@"activeUserContext");
    id contact=WXGSelfCall(WXGSelfService(context,@"CContactMgr"),@"getSelfContact");
    NSString *user=nil;
    if(contact){@try {id v=[contact valueForKey:@"m_nsUsrName"];if([v isKindOfClass:NSString.class] && [v length]>1)user=v;} @catch(__unused NSException *error) {}}
    if(!user)user=WXGAvatarUserName(contact);
    if(!user)user=WXGLicenseAccount();
    if(!user){WXGSelfAvatarStatus=[NSString stringWithFormat:@"读不到自己的账号（context %@，contact %@）",context?@"有":@"无",contact?@"有":@"无"];return best;}
    if(contact) {
        BOOL started=NO;UIImage *photo=[self downloadedAvatarFor:user contact:contact started:&started];
        if(photo){WXGSelfAvatarStatus=@"联系人头像地址（已下载）";return photo;}
        if(started){WXGSelfAvatarStatus=@"正在下载联系人头像";return best;}
    }
    id manager=WXGSelfService(context,@"MMHeadImageMgr");
    UIImage *image=manager?WXGSelfAvatarFromManager(manager,user):nil;
    if(image && (!best || image.size.width*image.scale>best.size.width*best.scale))best=image;
    // the HD one asked for once (WeChat downloads it; the next look finds it)
    SEL download=NSSelectorFromString(@"downloadHDHeadImg:forCategory:");
    Method d=manager && !askedHD && [manager respondsToSelector:download]?class_getInstanceMethod(object_getClass(manager),download):NULL;
    if(d && method_getNumberOfArguments(d)==4 && (!best || best.size.width*best.scale<300)) {
        char r[8]={0},a[8]={0},b[8]={0};method_getReturnType(d,r,sizeof r);method_getArgumentType(d,2,a,sizeof a);method_getArgumentType(d,3,b,sizeof b);
        int width=WXGAvatarIntegerWidth(b);
        if(r[0]=='v' && a[0]=='@' && width) {
            askedHD=YES;
            @try {
                if(width==8)((void (*)(id,SEL,id,unsigned long long))objc_msgSend)(manager,download,user,0ULL);
                else ((void (*)(id,SEL,id,unsigned int))objc_msgSend)(manager,download,user,0U);
            } @catch(__unused NSException *error) {}
        }
    }
    WXGSelfAvatarStatus=[NSString stringWithFormat:@"%@%@%@",best?[NSString stringWithFormat:@"头像管理器 %.0f px",best.size.width*best.scale]:@"头像管理器没给图",
        manager?@"":@"（没有头像管理器）",askedHD?@"；已请微信下载高清头像":@""];
    return best;
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
        if(!(WXGPreferences.shared.avatarTitle || WXGPreferences.shared.chatAvatarButton) || !host.route.chat || host.route.leaf!=host.avatarLookupPage)return;   // FIX109: also for the avatar button
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
        for(WXGSurface *surface in _departingButtons){surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);[self releaseFinderIconsOf:surface];}
        _departingButtons=nil;_departingInput=nil;
    }
    _nativeTransition=coordinator;_transitionFrom=from;_transitionTo=to;++_transitionSerial;
    // FIX115 O (user, 21:58 with diagnostics: "还是返回一半就切"; the 21:34
    // screenshot: both capsules cut flat at their buttons' ends): for a push /
    // pop UIKit takes the leaving page's button containers out of the window
    // and draws copies of them, cut at their bounds (navTrace: WeChat's 视频号
    // buttons and the capsules in them "不在窗口" the whole swipe; N's empty
    // mask came after the copy). The capsules are no longer in those
    // containers (bindFinderCapsules); what the bar holds then goes to the log.
    // FIX115 O (user, 10-27 00:02 with diagnostics_5: following the fade "会闪烁";
    // "触发返回玻璃就消失，所有行为交给微信自己"): the leaving page's capsules
    // go at once, as the transition starts; WeChat's buttons are left to UIKit.
    // They come back when the page is laid out again: a cancelled swipe fading
    // in once the transition is over, a page coming back in following its buttons.
    if(from!=to && WXGFinderFeed(from) && WXGPluginEnabled() && WXGPreferences.shared.nav) {
        [self veilFinderCapsulesOf:from];[self logFinderLeaving];
    }
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
// FIX115 O: the leaving 视频号 page's capsules not shown from now on (no
// animation left on them) until a layout of the page shows them again.
- (void)veilFinderCapsulesOf:(UIViewController *)page {
    NSMutableOrderedSet<WXGSurface *> *all=[NSMutableOrderedSet orderedSetWithArray:_buttons?:@[]];
    if(_departingButtons)[all addObjectsFromArray:_departingButtons];
    for(WXGSurface *s in all) {
        if(![s.role isEqual:@"finderCapsule"] || s.motionOwner!=page)continue;
        WXGFinderLink *link=objc_getAssociatedObject(s,&WXGFinderLinkKey);
        if(!link)continue;
        link.veiled=YES;link.leaving=YES;++_finderVeils;
        [UIView performWithoutAnimation:^{
            [CATransaction begin];[CATransaction setDisableActions:YES];
            [s.layer removeAnimationForKey:@"wxg.finderReveal"];s.alpha=0;
            [CATransaction commit];
        }];
        [link.checked removeAllObjects];[self hideFinderCopiesOf:link];
    }
}
// FIX115 T: WeChat's icons go with the glass as 视频号's first page starts
// leaving: UIKit's copies of its buttons (cut at their containers' bounds,
// the icons in them moved by the margin) hidden; they go with the transition.
- (void)hideFinderCopiesOf:(WXGFinderLink *)link {
    UIView *holder=link.holder;if(!holder.window)return;
    if(!link.checked)link.checked=[NSHashTable weakObjectsHashTable];
    // Each copy judged once, as first seen (where UIKit made it: the device
    // evidence has them as direct children of the holder).
    for(UIView *v in holder.subviews) {
        if(WXGIsPluginView(v) || [link.checked containsObject:v])continue;
        [link.checked addObject:v];
        if(v.hidden || !WXGFinderCopyAt(v,link.rest))continue;
        v.hidden=YES;
        if(!link.copies)link.copies=[NSHashTable weakObjectsHashTable];
        [link.copies addObject:v];++_finderCopiesHidden;
    }
}
// FIX115 O: what the bar holds 0.1 s after a 视频号 page starts leaving (its
// direct children and theirs: class, place, how visible), the first six
// times after launch: the copies UIKit draws are among them.
- (void)logFinderLeaving {
    if(_finderCopyLogs>=6)return;
    ++_finderCopyLogs;
    __weak UINavigationBar *weakBar=_route.nav.navigationBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UINavigationBar *bar=weakBar;if(!bar.window)return;
        NSMutableArray<NSString *> *parts=[NSMutableArray array];
        for(UIView *child in bar.subviews) {
            for(UIView *v in [@[child] arrayByAddingObjectsFromArray:child.subviews]) {
                if(parts.count>=18)break;
                double a=0;CGRect r=WXGTraceScreenRect(v,v.bounds,&a);
                [parts addObject:[NSString stringWithFormat:@"%@%@ %.0f+%.0f 透%.2f",v==child?@"":@"·",NSStringFromClass(v.class),r.origin.x,r.size.width,a]];
            }
        }
        WXGLog(@"视频号离开 0.1 s：导航栏 %@",[parts componentsJoinedByString:@"；"]);
    });
}
- (void)dropDepartingButtons {
    for(WXGSurface *surface in _departingButtons){surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);[self releaseFinderIconsOf:surface];}
    _departingButtons=nil;
}
// FIX115 T (review): a 视频号 capsule retired: WeChat's buttons it hid shown
// again (its page off screen by then, or staying: nothing to fade).
- (void)releaseFinderIconsOf:(WXGSurface *)surface {
    if(![surface.role isEqual:@"finderCapsule"])return;
    WXGFinderLink *link=objc_getAssociatedObject(surface,&WXGFinderLinkKey);
    if(link.concealed.count)[self showFinderIconsOf:link fade:NO];
}
- (void)finishNativeTransition:(id<UIViewControllerTransitionCoordinator>)coordinator cancelled:(BOOL)cancelled {
    if(!coordinator || _nativeTransition!=coordinator)return;
    if(cancelled)++_transitionCancellations;else ++_transitionCompletions;
    [self logTransition:@"complete" cancelled:cancelled];
    // FIX114 U (diagnostics_14: after every cancelled swipe back the chat's
    // avatar and capsule went for a frame and came back from 0): the page
    // stays, and its held title glasses (the same ones its layout takes again)
    // stay as they are; any not taken again within 0.4 s go then.
    // FIX115 O: 视频号's capsules too (the page they are on stays; diagnostics:
    // they went for a frame before its next layout put them back).
    NSMutableArray<WXGSurface *> *kept=[NSMutableArray array];
    // FIX115 O: a given-up swipe from 视频号: its capsules wherever they are
    // now (left for the page coming in, or still the route's: review).
    NSMutableArray<WXGSurface *> *finderStays=[NSMutableArray array];
    if(cancelled && WXGFinderFeed(_transitionFrom)) {
        for(WXGSurface *surface in [(_buttons?:@[]) arrayByAddingObjectsFromArray:_departingButtons?:@[]])
            if([surface.role isEqual:@"finderCapsule"] && surface.motionOwner==_transitionFrom && ![finderStays containsObject:surface])[finderStays addObject:surface];
    }
    for(WXGSurface *surface in _departingButtons) {
        BOOL finder=[surface.role isEqual:@"finderCapsule"];
        if(cancelled && (surface.holdsPlace || finder) && !surface.hidden){[kept addObject:surface];if(finder)++_finderKept;continue;}
        surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);[self releaseFinderIconsOf:surface];
    }
    // FIX115 T (review): a leave from 视频号 that went through: nothing of its
    // buttons stays hidden (a completed push keeps the state bag); UIKit's
    // copies, should one outlive the transition by 0.5 s, shown again.
    for(WXGSurface *surface in [(_buttons?:@[]) arrayByAddingObjectsFromArray:_departingButtons?:@[]]) {
        if(![surface.role isEqual:@"finderCapsule"] || surface.motionOwner!=_transitionFrom)continue;
        if(!cancelled)[self releaseFinderIconsOf:surface];
        WXGFinderLink *link=objc_getAssociatedObject(surface,&WXGFinderLinkKey);
        NSArray<UIView *> *copies=link.copies.allObjects;[link.copies removeAllObjects];
        if(!copies.count)continue;
        NSHashTable<UIView *> *left=[NSHashTable weakObjectsHashTable];for(UIView *copy in copies)[left addObject:copy];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            for(UIView *copy in left.allObjects)if(copy.window && copy.hidden)copy.hidden=NO;
        });
    }
    if(kept.count) {
        __weak WXGIntegrationHost *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            WXGIntegrationHost *host=weakSelf;if(!host)return;
            for(WXGSurface *surface in kept)if(![host.buttons containsObject:surface] && ![host.departingButtons containsObject:surface]){surface.active=NO;surface.hidden=YES;WXGResetOwnedTransform(surface);[host releaseFinderIconsOf:surface];}
        });
    }
    for(WXGSurface *surface in _departingInput.surfaces)surface.active=NO;
    _departingButtons=nil;_departingInput=nil;_completedTransition=coordinator;_nativeTransition=nil;
    // FIX113 E (a page whose bar may never be built); FIX115 O: not when 视频号 stays on top (a given-up swipe).
    if(!WXGFinderFeed(_route.leaf) && !WXGFinderFeed(_route.nav.topViewController))[self clearFinderShifts];
    WXGResetOwnedTransform(_dockView);_dockView.layer.mask=nil;_pendingController=nil;_needsEarlyLayout=NO;_navigationDirty=YES;
    // A completed push is already bound to its incoming page. Restoring all
    // masks here briefly exposed native artwork and discarded those bindings.
    if(cancelled || _route.leaf!=_transitionTo)[self resetRoute];
    // FIX115 O: a swipe back from 视频号 given up: the reset just took FIX113
    // E's shift off WeChat's buttons there; it goes back on at once (the next
    // layout measures and sets it again), so the icons do not jump. The
    // capsules (not shown since the swipe began) fade in at that layout.
    // (review) On the container the buttons are in now (UIKit may have made
    // a new one as the swipe was given up).
    for(WXGSurface *s in finderStays) {
        WXGFinderLink *link=objc_getAssociatedObject(s,&WXGFinderLinkKey);
        if(!link || fabs(link.placedShift)<.01)continue;
        if(!_navStates)_navStates=[WXGStateBag new];
        if(!_finderShiftHosts)_finderShiftHosts=[NSHashTable weakObjectsHashTable];
        if(fabs(link.shift)>.01) {
            UIView *live=WXGFinderLiveContainer(link),*container=WXGFinderContainerFits(link,live)?live:link.container;
            if(container.window){[_navStates allowOverflow:container];[_navStates shiftContents:container x:link.shift];[_finderShiftHosts addObject:container];link.container=container;}
        }else for(UIView *v in link.views.allObjects)if(v.window){[_navStates shiftContents:v x:link.placedShift];[_finderShiftHosts addObject:v];}
    }
    // FIX115 T: the reset showed WeChat's buttons hidden for the given-up
    // swipe: hidden again until the capsule fades in (the next layout).
    for(WXGSurface *s in finderStays) {
        WXGFinderLink *link=objc_getAssociatedObject(s,&WXGFinderLinkKey);
        if(!link.veiled || !link.concealed.count)continue;
        if(!_navStates)_navStates=[WXGStateBag new];
        for(UIView *v in link.concealed.allObjects)if(v.window)[_navStates conceal:v];
    }
    BOOL dockAvailable=WXGPluginEnabled() && WXGPreferences.shared.dock && !_suspendedByCover && !_settings.presentingViewController;
    [self applyDockPresentation:WXGDockPresentationAfterTransition(dockAvailable,_dockTransitionFromRoot,_dockTransitionToRoot,cancelled)];
    [_navStates reapply];[self schedule];
}
// FIX109 B: the chat's pinned module (置顶; the probe's TEST6 on the XS Max,
// WeChat 8.0.73): MMNewMsgContentNavBar, a child of the chat page's view, 155
// pt tall with the module (88 + 67), holds the bar's own background (from the
// top), the collapsed module's container (y 88: MMMsgCommonTipsView, a tap
// recogniser → onTapMixedList), the expanded list's container (y 88, hidden
// until expanded: MMMsgTipsMixedListExpandView, then the bar is full screen)
// and a dimming button; the message list's top inset is the bar's height.
// With the avatar title the containers move down by pinnedShift, the list's
// top inset grows by it while the module shows, and the bar takes touches in
// the moved containers below its own bounds. WeChat's own frames and inset
// are remembered (what it set last) and come back when the shift is 0.
static char WXGPinnedKey,WXGPinnedInsetKey;
static BOOL WXGShowsPinnedTips(UIView *container) {
    static Class tips;static dispatch_once_t once;dispatch_once(&once,^{tips=NSClassFromString(@"MMMsgCommonTipsView");});
    if(!tips || container.hidden || container.alpha<.01 || container.bounds.size.height<1)return NO;
    for(UIView *v in container.subviews)if([v isKindOfClass:tips] && !v.hidden && v.alpha>.01)return YES;
    return NO;
}
static BOOL WXGShiftListInset(UIScrollView *list,CGFloat shift) {
    NSArray *rec=objc_getAssociatedObject(list,&WXGPinnedInsetKey);
    UIEdgeInsets inset=list.contentInset,indicator=list.verticalScrollIndicatorInsets;
    CGFloat native=rec && fabs(inset.top-[rec[0] doubleValue])<.01?[rec[1] doubleValue]:inset.top;
    CGFloat nativeIndicator=rec && fabs(indicator.top-[rec[2] doubleValue])<.01?[rec[3] doubleValue]:indicator.top;
    CGFloat wanted=native+shift,wantedIndicator=nativeIndicator+shift;
    if(fabs(inset.top-wanted)>.01) {
        BOOL atTop=!list.dragging && !list.decelerating && list.contentOffset.y<=-list.adjustedContentInset.top+1;
        inset.top=wanted;list.contentInset=inset;
        if(atTop)list.contentOffset=CGPointMake(list.contentOffset.x,-list.adjustedContentInset.top);
    }
    if(fabs(indicator.top-wantedIndicator)>.01){indicator.top=wantedIndicator;list.verticalScrollIndicatorInsets=indicator;}
    objc_setAssociatedObject(list,&WXGPinnedInsetKey,shift>.01?@[@(wanted),@(native),@(wantedIndicator),@(nativeIndicator)]:nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return shift>.01;
}
- (void)alignPinnedModule {
    UIView *bar=_pinnedBar;
    if(!bar){_pinnedApplied=NO;_pinnedShift=0;return;}   // its page is gone
    if(!bar.window)return;   // its page is away: done when it is back (buildNavigation)
    CGFloat shift=_pinnedShift;BOOL applied=NO,tips=NO;
    for(UIView *v in bar.subviews) {
        if(WXGIsPluginView(v) || [v isKindOfClass:UIControl.class])continue;
        NSArray *rec=objc_getAssociatedObject(v,&WXGPinnedKey);CGRect f=v.frame;
        CGFloat native=rec && fabs(f.origin.y-[rec[0] doubleValue])<.01?[rec[1] doubleValue]:f.origin.y;
        if(native<20){if(rec)objc_setAssociatedObject(v,&WXGPinnedKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);continue;}   // the bar's background
        CGFloat wanted=native+shift;
        if(fabs(f.origin.y-wanted)>.01){f.origin.y=wanted;v.frame=f;++_pinnedMoves;}
        objc_setAssociatedObject(v,&WXGPinnedKey,shift>.01?@[@(wanted),@(native)]:nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(shift>.01)applied=YES;
        if(WXGShowsPinnedTips(v))tips=YES;
    }
    UIView *page=bar.superview;UIScrollView *list=nil;
    for(UIView *v in page.subviews)if([v isKindOfClass:UITableView.class] && v.bounds.size.height>=page.bounds.size.height*.6){list=(UIScrollView *)v;break;}
    if(list && WXGShiftListInset(list,tips?shift:0))applied=YES;
    _pinnedApplied=applied;
}
- (BOOL)chatBar:(UIView *)bar extendsTo:(CGPoint)point {
    if(_pinnedShift<=.01 || bar!=_pinnedBar)return NO;
    for(UIView *v in bar.subviews)
        if(objc_getAssociatedObject(v,&WXGPinnedKey) && !v.hidden && v.alpha>.01 && v.userInteractionEnabled && CGRectContainsPoint(v.frame,point))return YES;
    return NO;
}
// FIX114 M: iOS 26's chevron after the name in Messages' capsule (measured on
// the user's screenshot: 4.3 x 12 pt, heavy, #ADADAD): the compact chevron,
// heavy (the plain one before iOS 14), drawn in the capsule's grey.
static UIImage *WXGCapsuleChevron(void) {
    static UIImage *image;static dispatch_once_t once;
    dispatch_once(&once,^{
        UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightHeavy];
        UIImage *symbol=[UIImage systemImageNamed:@"chevron.compact.right" withConfiguration:config]?:[UIImage systemImageNamed:@"chevron.right" withConfiguration:config];
        image=[symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return image;
}
// FIX94: a grey disc with a white figure (fills the circle like a photo), while
// no photo of the chat has been found.
static UIImage *WXGAvatarPlaceholder(void) {
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
    return placeholder;
}
/* FIX114 V: a copy of what a WeChat control shows, to stand in the plugin's
   own glass for it: its image views (image, tint, symbol configuration), its
   labels (text or attributed text, font, colour) and plain views with a fill
   (an unread count's capsule), each where it is laid out now, no touches. A
   control drawing its content some other way: a picture of its layers. */
/* FIX114 W: a colour as the native view shows it (WeChat's colours can depend
   on its own views' traits: moved out to the plugin's layer, the unread
   count's capsule and number both came out black). */
static UIColor *WXGNativeResolved(UIColor *color,UIView *view) {
    return color?[color resolvedColorWithTraitCollection:view.traitCollection]:nil;
}
static NSAttributedString *WXGNativeResolvedText(NSAttributedString *text,UIView *view) {
    if(!text.length)return text;
    NSMutableAttributedString *out=[text mutableCopy];
    for(NSAttributedStringKey key in @[NSForegroundColorAttributeName,NSBackgroundColorAttributeName,NSStrokeColorAttributeName])
        [text enumerateAttribute:key inRange:NSMakeRange(0,text.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop){
            (void)stop;if([value isKindOfClass:UIColor.class])[out addAttribute:key value:WXGNativeResolved(value,view) range:range];
        }];
    return out;
}
static NSUInteger WXGNativeContentSignature(UIView *root,NSUInteger depth) {
    NSUInteger h=17;
    for(UIView *v in root.subviews) {
        if(WXGIsPluginView(v))continue;
        CGRect f=v.frame;
        h=h*131+(NSUInteger)(long)lround(f.origin.x*4)*3+(NSUInteger)(long)lround(f.origin.y*4)*5+(NSUInteger)(long)lround(f.size.width*4)*7+(NSUInteger)(long)lround(f.size.height*4)*11;
        h=h*131+(v.hidden?13:0)+(NSUInteger)(long)lround(v.alpha*20)*17+WXGNativeResolved(v.backgroundColor,v).hash;   // FIX114 W: as shown (light / dark)
        {CGColorRef fill=v.layer.backgroundColor;const CGFloat *k=fill?CGColorGetComponents(fill):NULL;size_t n=fill?CGColorGetNumberOfComponents(fill):0;
         for(size_t i=0;i<n && i<4;i++)h=h*31+(NSUInteger)(long)lround(k[i]*255);}
        if([v isKindOfClass:UIImageView.class]){UIImageView *iv=(UIImageView *)v;h=h*131+(NSUInteger)(uintptr_t)(__bridge void *)iv.image+WXGNativeResolved(iv.tintColor,iv).hash;}
        else if([v isKindOfClass:UILabel.class]){UILabel *l=(UILabel *)v;h=h*131+(l.attributedText.length?l.attributedText.hash:l.text.hash)+WXGNativeResolved(l.textColor,l).hash+l.font.hash;}
        if(depth<4)h=h*131+WXGNativeContentSignature(v,depth+1);
    }
    return h?:1;
}
/* FIX114 W (user, 00:48: "原生返回未读胶囊异常，变成了这种黑块": the copy of
   the back button's unread count was a black square with no number): what a
   view's layer adds beyond the view's own properties is copied too: a fill set
   on the layer, a blend with what is under it (compositing filter), filters,
   its mask (a copy), what it draws itself (contents) and layers of its own (a
   shape, text, gradient: copies; never WeChat's own layer objects moved). */
static CALayer *WXGNativeCopyLayer(CALayer *layer,NSUInteger depth);
static void WXGNativeCopyLayerLook(CALayer *from,CALayer *to,BOOL drawsItself) {
    // FIX114 Z (hardening): only a blend named by a string (a filter object is
    // never shared between two layers), and only a picture as contents (never
    // a view's own drawing store, which WeChat redraws and reuses).
    @try {
        id compositing=[from valueForKey:@"compositingFilter"];if([compositing isKindOfClass:NSString.class])[to setValue:compositing forKey:@"compositingFilter"];
    } @catch(__unused NSException *error) {}
    if(from.mask){CALayer *mask=WXGNativeCopyLayer(from.mask,0);if(mask)to.mask=mask;}
    id contents=from.contents;
    if(!drawsItself && contents && CFGetTypeID((__bridge CFTypeRef)contents)==CGImageGetTypeID()) {
        to.contents=from.contents;to.contentsGravity=from.contentsGravity;to.contentsRect=from.contentsRect;
        to.contentsCenter=from.contentsCenter;to.contentsScale=from.contentsScale;
    }
}
static void WXGNativeCopyOwnSublayers(CALayer *from,CALayer *to,NSUInteger depth) {
    if(depth>4)return;
    for(CALayer *sub in from.sublayers.copy) {
        if([sub.delegate isKindOfClass:UIView.class])continue;   // a view's: copied as a view
        CALayer *copy=WXGNativeCopyLayer(sub,depth+1);if(copy)[to addSublayer:copy];
    }
}
static CALayer *WXGNativeCopyLayer(CALayer *layer,NSUInteger depth) {
    if(!layer || layer.hidden || depth>4)return nil;
    CALayer *copy=nil;
    if([layer isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *s=(CAShapeLayer *)layer,*c=[CAShapeLayer layer];
        c.path=s.path;c.fillColor=s.fillColor;c.fillRule=s.fillRule;c.strokeColor=s.strokeColor;c.lineWidth=s.lineWidth;
        c.lineCap=s.lineCap;c.lineJoin=s.lineJoin;c.strokeStart=s.strokeStart;c.strokeEnd=s.strokeEnd;c.lineDashPattern=s.lineDashPattern;
        copy=c;
    }else if([layer isKindOfClass:CATextLayer.class]) {
        CATextLayer *t=(CATextLayer *)layer,*c=[CATextLayer layer];
        c.string=t.string;c.font=t.font;c.fontSize=t.fontSize;c.foregroundColor=t.foregroundColor;c.alignmentMode=t.alignmentMode;
        c.wrapped=t.wrapped;c.truncationMode=t.truncationMode;
        copy=c;
    }else if([layer isKindOfClass:CAGradientLayer.class]) {
        CAGradientLayer *g=(CAGradientLayer *)layer,*c=[CAGradientLayer layer];
        c.colors=g.colors;c.locations=g.locations;c.startPoint=g.startPoint;c.endPoint=g.endPoint;c.type=g.type;
        copy=c;
    }else if(layer.class==CALayer.class)copy=[CALayer layer];
    else return nil;   // a kind of layer this cannot copy faithfully: left out
    copy.bounds=layer.bounds;copy.position=layer.position;copy.anchorPoint=layer.anchorPoint;copy.transform=layer.transform;
    copy.opacity=layer.opacity;copy.backgroundColor=layer.backgroundColor;copy.cornerRadius=layer.cornerRadius;copy.masksToBounds=layer.masksToBounds;
    copy.borderWidth=layer.borderWidth;copy.borderColor=layer.borderColor;copy.contentsScale=layer.contentsScale;
    copy.cornerCurve=layer.cornerCurve;
    copy.maskedCorners=layer.maskedCorners;
    WXGNativeCopyLayerLook(layer,copy,NO);
    WXGNativeCopyOwnSublayers(layer,copy,depth);
    return copy;
}
static UIView *WXGNativeCloneView(UIView *v) {
    UIView *c=nil;
    if([v isKindOfClass:UIImageView.class]) {
        UIImageView *iv=(UIImageView *)v,*copy=[UIImageView new];
        copy.image=iv.image;copy.tintColor=WXGNativeResolved(iv.tintColor,iv);copy.contentMode=iv.contentMode;copy.preferredSymbolConfiguration=iv.preferredSymbolConfiguration;
        c=copy;
    }else if([v isKindOfClass:UILabel.class]) {
        UILabel *l=(UILabel *)v,*copy=[UILabel new];
        if(l.attributedText.length)copy.attributedText=WXGNativeResolvedText(l.attributedText,l);else {copy.text=l.text;copy.font=l.font;copy.textColor=WXGNativeResolved(l.textColor,l);}
        copy.textAlignment=l.textAlignment;copy.numberOfLines=l.numberOfLines;copy.lineBreakMode=l.lineBreakMode;
        copy.adjustsFontSizeToFitWidth=l.adjustsFontSizeToFitWidth;copy.minimumScaleFactor=l.minimumScaleFactor;copy.baselineAdjustment=l.baselineAdjustment;
        c=copy;
    }else c=[UIView new];
    // FIX114 W: the fill as the layer shows it (WeChat can paint the layer itself,
    // the view's own colour property then still holding an older one).
    // FIX114 X (user, 01:01, still a black block; measured on the screenshot:
    // exactly the copied "26" label's frame): a new label is opaque, so its
    // drawing has no transparency: the area around the digits came out black
    // (black digits on it). Every copy is drawn with transparency.
    c.opaque=NO;c.layer.opaque=NO;
    c.userInteractionEnabled=NO;c.backgroundColor=nil;c.layer.backgroundColor=v.layer.backgroundColor;c.alpha=v.alpha;c.clipsToBounds=v.clipsToBounds;
    c.layer.cornerRadius=v.layer.cornerRadius;c.layer.cornerCurve=v.layer.cornerCurve;c.layer.maskedCorners=v.layer.maskedCorners;
    c.layer.borderWidth=v.layer.borderWidth;c.layer.borderColor=v.layer.borderColor;
    c.bounds=v.bounds;c.center=v.center;c.transform=v.transform;
    // FIX114 W: the layer's own look (image views and labels draw themselves).
    BOOL drawsItself=[v isKindOfClass:UIImageView.class] || [v isKindOfClass:UILabel.class];
    WXGNativeCopyLayerLook(v.layer,c.layer,drawsItself);
    if(!drawsItself)WXGNativeCopyOwnSublayers(v.layer,c.layer,0);
    return c;
}
// FIX114 W: what a native control is made of (diagnostics: nativeLookDump).
static NSString *WXGNativeColorText(CGColorRef color) {
    if(!color)return @"";
    const CGFloat *k=CGColorGetComponents(color);size_t n=CGColorGetNumberOfComponents(color);
    NSMutableArray *parts=[NSMutableArray array];for(size_t i=0;i<n && i<4;i++)[parts addObject:[NSString stringWithFormat:@"%.2f",k[i]]];
    return [parts componentsJoinedByString:@","];
}
static void WXGNativeDump(UIView *view,NSUInteger depth,NSMutableArray *out) {
    for(UIView *v in view.subviews) {
        if(WXGIsPluginView(v) || out.count>=24)continue;
        CALayer *l=v.layer;NSMutableArray *own=[NSMutableArray array];
        for(CALayer *sub in l.sublayers)if(![sub.delegate isKindOfClass:UIView.class])[own addObject:[NSString stringWithFormat:@"%@ %@ bg(%@)",NSStringFromClass(sub.class),NSStringFromCGRect(sub.frame),WXGNativeColorText(sub.backgroundColor)]];
        id compositing=nil;NSArray *filters=nil;
        @try {compositing=[l valueForKey:@"compositingFilter"];filters=[l valueForKey:@"filters"];} @catch(__unused NSException *error) {}
        NSMutableDictionary *row=[@{@"depth":@(depth),@"class":NSStringFromClass(v.class)?:@"?",@"frame":NSStringFromCGRect(v.frame),@"hidden":@(v.hidden),@"alpha":@(v.alpha),@"opaque":@(v.opaque),
            @"bg":WXGNativeColorText([v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection].CGColor),@"layerBg":WXGNativeColorText(l.backgroundColor),
            @"radius":@(l.cornerRadius),@"clips":@(l.masksToBounds),@"mask":l.mask?NSStringFromClass(l.mask.class):@"",
            @"compositing":compositing?[compositing description]:@"",@"filters":@(filters.count),@"contents":l.contents?NSStringFromClass([l.contents class]):@"",@"ownLayers":own} mutableCopy];
        if([v isKindOfClass:UILabel.class]){UILabel *t=(UILabel *)v;row[@"text"]=t.text?:@"";row[@"textColor"]=WXGNativeColorText([t.textColor resolvedColorWithTraitCollection:t.traitCollection].CGColor);row[@"font"]=[NSString stringWithFormat:@"%@ %.1f",t.font.fontName,t.font.pointSize];}
        if([v isKindOfClass:UIImageView.class]){UIImageView *i=(UIImageView *)v;row[@"image"]=i.image?NSStringFromCGSize(i.image.size):@"";row[@"rendering"]=@(i.image.renderingMode);row[@"tint"]=WXGNativeColorText([i.tintColor resolvedColorWithTraitCollection:i.traitCollection].CGColor);}
        [out addObject:row];
        if(depth<4)WXGNativeDump(v,depth+1,out);
    }
}
static NSUInteger WXGNativeCloneInto(UIView *source,UIView *target,NSUInteger depth) {
    NSUInteger shown=0;
    for(UIView *v in source.subviews) {
        if(WXGIsPluginView(v) || v.hidden || v.alpha<.01)continue;
        UIView *c=WXGNativeCloneView(v);[target addSubview:c];
        CGColorRef fill=v.layer.backgroundColor;   // FIX114 W: as the layer shows it
        if(([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image) ||
           ([v isKindOfClass:UILabel.class] && (((UILabel *)v).text.length || ((UILabel *)v).attributedText.length)) ||
           (fill && CGColorGetAlpha(fill)>.01))++shown;
        if(depth<4)shown+=WXGNativeCloneInto(v,c,depth+1);
    }
    return shown;
}
static UIView *WXGNativeClone(UIView *control) {
    UIView *root=[UIView new];root.bounds=control.bounds;root.userInteractionEnabled=NO;root.opaque=NO;root.backgroundColor=nil;
    if(WXGNativeCloneInto(control,root,0))return root;
    // Drawn in its layers: a picture of them (its own layer's mask, the plugin's
    // hiding, left out), on the screen's pixels.
    for(UIView *v in root.subviews.copy)[v removeFromSuperview];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.opaque=NO;
    UIImage *picture=[[[UIGraphicsImageRenderer alloc]initWithBounds:control.bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
        for(CALayer *layer in control.layer.sublayers.copy) {
            id owner=layer.delegate;
            if(layer.hidden || layer.opacity<.01 || ([owner isKindOfClass:UIView.class] && WXGIsPluginView(owner)))continue;
            CGContextSaveGState(context.CGContext);
            CGContextTranslateCTM(context.CGContext,layer.frame.origin.x,layer.frame.origin.y);
            [layer renderInContext:context.CGContext];
            CGContextRestoreGState(context.CGContext);
        }
    }];
    UIImageView *image=[[UIImageView alloc]initWithImage:picture];image.frame=control.bounds;image.userInteractionEnabled=NO;image.opaque=NO;
    [root addSubview:image];
    return root;
}
- (void)buildNavigation {
    ++_navigationRepairs;
    _homeNavigationNeedsFinalLayout=NO;
    UINavigationBar *bar=_route.nav.navigationBar;UIWindow *w=_window;
    BOOL home=[NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
    WXGHomeMenuStyle homeMenuStyle=WXGConfig.shared.homeMenuStyle;
    CFTimeInterval buildStart=home?CACurrentMediaTime():0;
    if(!bar || !_route.leaf.isViewLoaded){if(!home && !_nativeTransition)[WXGChatSegments.shared hideTitleBar];[_navStates reapply];return;}
    // Pull-down rehomes the home gesture while temporarily hiding UINavigationBar.
    // Visibility is not destruction; existing surfaces follow their real hosts.
    if(!home && (bar.hidden || bar.alpha<.01)){if(!_nativeTransition)[WXGChatSegments.shared hideTitleBar];[_navStates reapply];return;}
    if(!_navStates)_navStates=[WXGStateBag new];
    NSArray<UIControl *> *controls=[self navigationControls];
    if(home){_homePlusSurface=nil;_homeSearchSurface=nil;}
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
    // FIX112: at the title's height. WeChat's title text sits above the bar's
    // middle (设置, 通讯录 ...) and its capsule follows the text, so the buttons
    // were lower than the title beside them. The page's own title when it can
    // be measured (a chat's too: the plugin's title capsule comes from here);
    // until then (its title not laid out yet, or none) the offset measured on
    // an earlier page with this bar, so pages never jump; the first page ever
    // looks again shortly. The home page keeps its own (WeChat's buttons).
    _titleAlignedButtons=NO;
    if(!home) {
        CGFloat barMid=CGRectGetMidY(nr),offset=NAN;
        // FIX114 O (user: entering a chat the title and the buttons jumped
        // together): during a push / pop the title is measured where UIKit has
        // it on its way in; the offset found on a settled page (this bar's
        // height) is used then, measured again only once the page has settled.
        BOOL known=_titleOffsetBar>0 && fabs(_titleOffsetBar-nr.size.height)<1;
        CGRect title=_nativeTransition && known?CGRectNull:WXGLocalTitleCapsuleRect(bar,_route.leaf.navigationItem.titleView,w);
        if(!CGRectIsNull(title) && fabs(CGRectGetMidY(title)-barMid)<m.button*.5){offset=CGRectGetMidY(title)-barMid;_titleOffset=offset;_titleOffsetBar=nr.size.height;}
        else if(_titleOffsetBar>0 && fabs(_titleOffsetBar-nr.size.height)<1)offset=_titleOffset;
        if(isfinite(offset)){centerY=barMid+offset;_titleAlignedButtons=YES;}
        else {
            if(_titleRetryLeaf!=_route.leaf){_titleRetryLeaf=_route.leaf;_titleRetries=0;}
            if(_titleRetries<3) {
                ++_titleRetries;__weak WXGIntegrationHost *weakSelf=self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.15*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                    WXGIntegrationHost *host=weakSelf;if(!host || host->_titleOffsetBar>0)return;
                    host->_navigationDirty=YES;[host schedule];
                });
            }
        }
    }
    // FIX114 C (user: the top buttons' distance to the screen's edges set by
    // hand): the whole row moved down by 顶部按钮往下移 (not on 视频号's pages:
    // WeChat's buttons over the video stay), its margin 顶部按钮离屏幕两边.
    CGFloat rowPixel=w.screen.scale?:3,centerY0=centerY;
    CGFloat rowDY=WXGFinderFeed(_route.leaf)?0:round(WXGTitleRowOffset(m.scale)*rowPixel)/rowPixel;
    CGFloat edge=WXGFinderPage(_route.leaf)?WXGFinderRowEdge(m.scale):WXGTitleRowEdge(m.scale);   // FIX115 S: 视频号's own margin
    centerY+=rowDY;_rowOffset=rowDY;
    _homeRowBottom=home?centerY+m.button*.5:NAN;
    self.navCapsuleLeaf=_route.leaf;   // FIX113 Q; FIX114 C: the page the title row's offset is for
    CGFloat left=w.safeAreaInsets.left+edge,right=w.bounds.size.width-w.safeAreaInsets.right-edge;
    NSMutableArray *leftButtons=[NSMutableArray array],*rightButtons=[NSMutableArray array];
    NSUInteger leftSlot=0,rightSlot=0;
    // FIX109: the chat page's top-right button (聊天信息, the outermost on the
    // right) shows the chat's avatar in its glass: the same button, the same
    // action; the photo inset by a setting (头像按钮内边距).
    UIControl *avatarControl=nil;UIImage *chatAvatar=nil;
    if(_route.chat && WXGPreferences.shared.chatAvatarButton) {
        for(UIControl *c in controls)if(![self controlOnLeft:c] && ![self isBack:c])avatarControl=c;
        if(avatarControl) {
            UIView *titleView=_route.leaf.navigationItem.titleView;
            NSString *title=[self fullTitleFromView:titleView fallback:_route.leaf.navigationItem.title?:_route.leaf.title];
            chatAvatar=[self avatarImageForTitle:title]?:WXGAvatarPlaceholder();
        }
    }
    // FIX113 D: 视频号 (WCFinder pages): WeChat's own buttons as they are (not
    // moved, not hidden, no glass button of the plugin's), a capsule of glass
    // under them (bindFinderCapsules); none of the buttons below.
    BOOL finderPage=WXGFinderFeed(_route.leaf);
    if(finderPage)[self bindFinderCapsules:controls metrics:m alive:alive];
    // FIX113 E: the bar's views may be reused for this page. FIX115 O (review):
    // not while 视频号 is still on top (a build for the page a given-up swipe
    // was bringing in, before the route is looked at again).
    else if(!_nativeTransition && !WXGFinderFeed(_route.nav.topViewController))[self clearFinderShifts];
    // FIX114 B: a chat without the avatar title keeps WeChat's buttons (but the avatar one).
    BOOL chatNative=_route.chat && [self chatBarNativeFor:_route.leaf],nativeButtons=[self navButtonsNativeFor:_route.leaf];
    _chatAvatarControl=avatarControl && chatAvatar?avatarControl:nil;
    BOOL nativeLook=nativeButtons && [self nativeLookFor:_route.leaf];   // FIX114 V
    for(UIControl *b in finderPage?@[]:controls) {
        // FIX115 O (navTrace: at the end of every cancelled swipe back from 视频号
        // the plugin's own four buttons showed for about 70 ms, bound to 视频号's
        // buttons while the page coming in was the route): a 视频号 page's
        // buttons never get the plugin's buttons (its capsules stand under them).
        if(WXGFinderItemHolds(_route.nav,b))continue;
        // FIX115 S (user, 02:05: "那个最近看过和赞和收藏还是不管为好"): a 视频号
        // page's title-view tabs are no buttons of the title row (R made them
        // the plugin's glass buttons at its slots).
        // (review) The tabs by class on any page (the leaving page's title view
        // stays live in a push / pop to or from a page that is not 视频号's).
        if(WXGFinderTab(b,bar) || (WXGFinderPage(_route.leaf) && WXGInTitleView(_route.nav,b)))continue;
        BOOL avatarSlot=b==avatarControl && chatAvatar;
        BOOL look=nativeLook && !avatarSlot && !WXGNativeNavButtonFilled(b);
        CGRect lookGlass=look?WXGNativeNavGlassRect(b):CGRectNull;
        if(look && (CGRectIsNull(lookGlass) || lookGlass.size.width<1 || lookGlass.size.height<1))look=NO;   // nothing to stand in for yet
        // FIX115 O (user: LoadControl's two top-right buttons lost their glass;
        // diagnostics_5: 顶部按钮保持微信原生 and its look are on, and those are
        // UIKit's own item buttons, no custom view): one of those (not a
        // UIButton: no WeChat look to copy, the local glass does not take it
        // either) gets the plugin's own glass button with its icon, as before
        // the native modes, instead of none.
        // (review) Only the view of one of this page's items without a custom
        // view, in the bar, on a side with no WeChat (custom view) button (the
        // plugin's row would sit over it otherwise).
        BOOL systemItem=nativeButtons && !look && !avatarSlot && ![b isKindOfClass:UIButton.class] && [b isDescendantOfView:bar] &&
            !WXGCustomItemHolds(_route.nav,b) && WXGSystemItemHolds(_route.leaf.navigationItem,b);
        if(nativeButtons && !look && !avatarSlot && !systemItem)continue;
        BOOL onLeft=[self controlOnLeft:b];
        NSString *slot=[NSString stringWithFormat:@"%@%lu",onLeft?@"left":@"right",(unsigned long)(onLeft?leftSlot++:rightSlot++)];
        if(home)slot=[_homePlusControls containsObject:b]?@"right1":@"right0";
        WXGSurface *s=[self pooledSurface:slot];s.original=b;s.motionHost=[self motionInkForControl:b];WXGResetOwnedTransform(s);[alive addObject:s];
        BOOL back=[self isBack:b];NSString *count=back?[self backCount:b]:nil;
        UIImage *image=WXGButtonImage(b);NSString *title=image?nil:[self titleForControl:b];
        // FIX108 C: the home "+": the artwork WeChat hands the button there (a
        // 20 pt ring drawn edge to edge) is cut off on its sides; drawn in the
        // glass, the ring showed flat sides. The same shape as a symbol then.
        BOOL homePlusBtn=home && [WXGActionNames(b) containsObject:@"showRightTopMenuBtn"];
        if(homePlusBtn && ((image && WXGInkTouchesEdges(image)) ||
           (!image && !title.length && homeMenuStyle==WXGHomeMenuStyleMorph)))image=WXGHomePlusSymbol();
        if(back && !image)image=[UIImage systemImageNamed:@"chevron.left"];
        BOOL avatarButton=b==avatarControl && chatAvatar;
        if(avatarButton){image=chatAvatar;title=nil;}
        s.role=avatarButton?@"chatAvatarButton":back?@"back":title.length?@"textAction":[WXGActionNames(b) containsObject:@"onSearchButtonTapped"]?@"navigationSearch":@"navigationAction";
        // Video artwork can keep its native contrast while material selection
        // follows the same WeChat window appearance and shared TEST9 settings.
        s.overrideUserInterfaceStyle=WXGFinderFeed(_route.leaf)?w.traitCollection.userInterfaceStyle:UIUserInterfaceStyleUnspecified;
        [s setNativeIconSource:s.motionHost preservingColors:WXGFinderFeed(_route.leaf)];
        s.label.font=[UIFont systemFontOfSize:17*m.scale weight:UIFontWeightSemibold];
        s.countLabel.font=[UIFont monospacedDigitSystemFontOfSize:12*m.scale weight:UIFontWeightSemibold];
        [s setImage:look?nil:image title:look?nil:title count:look?nil:count];
        // FIX114 V: WeChat's own content in the glass (copied again when it changes).
        if(look) {
            NSUInteger signature=WXGNativeContentSignature(b,0);
            if(!s.nativeContent || s.nativeContentSource!=b || s.nativeContentSignature!=signature) {
                UIView *clone=nil;@try {clone=WXGNativeClone(b);} @catch(NSException *error) {WXGLog(@"原生按钮拷贝失败：%@",error.reason);clone=nil;}   // FIX114 Z
                s.nativeContent=clone;s.nativeContentSource=b;s.nativeContentSignature=signature;
                if(back){NSMutableArray *dump=[NSMutableArray array];WXGNativeDump(b,0,dump);_nativeLookDump=dump;}   // FIX114 W (diagnostics)
            }
            s.nativeContentOrigin=CGPointMake(-lookGlass.origin.x,-lookGlass.origin.y);
        }else if(s.nativeContent){s.nativeContent=nil;s.nativeContentSource=nil;s.nativeContentSignature=0;}
        s.homePlusAnchor=homePlusBtn;
        s.homePlusTrigger=homePlusBtn && homeMenuStyle==WXGHomeMenuStyleCapsules;
        if(homePlusBtn)_homePlusSurface=s;
        else if(home && [s.role isEqual:@"navigationSearch"])_homeSearchSurface=s;
        s.accessibilityLabel=b.accessibilityLabel.length?b.accessibilityLabel:back?@"返回":title.length?title:WXGActionNames(b).firstObject;
        s.enabled=b.enabled;s.glass.sourceView=_route.leaf.view;s.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
        CGFloat width=m.button,height=m.button;
        if(look){width=lookGlass.size.width;height=lookGlass.size.height;}   // FIX114 V: the size the local glass gave it
        else if(count.length)width=WXGCapsuleWidth([count sizeWithAttributes:@{NSFontAttributeName:s.countLabel.font}].width,36*m.scale,m.button,14*m.scale,w.bounds.size.width*.36);
        else if(title.length)width=WXGCapsuleWidth([title sizeWithAttributes:@{NSFontAttributeName:s.label.font}].width,0,m.button,14*m.scale,w.bounds.size.width*.38);
        /* Store desired visual size; place after grouping to preserve left /
           right edge equality even when the rightmost control was only 24 pt. */
        CGRect desired=CGRectMake(0,0,width+2*WXGCanvasPaddingX,height+2*WXGCanvasPaddingY);
        if(!CGRectEqualToRect(s.bounds,desired))s.bounds=desired;
        if(onLeft)[leftButtons addObject:s];else[rightButtons addObject:s];
    }
    // UIBarButtonItem target/action is valid even without a discoverable
    // MMBarButton. Preserve the real item as sender rather than invent actions.
    NSArray *groups=finderPage?@[@[],@[]]:@[_route.leaf.navigationItem.leftBarButtonItems?:@[],(_route.leaf.navigationItem.rightBarButtonItems.reverseObjectEnumerator.allObjects?:@[])];
    // FIX115 O: with WeChat's buttons kept native, only UIKit's own items (no custom view) here.
    if(nativeButtons && !finderPage)groups=@[WXGSystemItems(groups[0]),WXGSystemItems(groups[1])];   // (review) a side with a WeChat button: none
    for(NSUInteger side=0;side<2;side++)for(UIBarButtonItem *item in groups[side]) {
        if([NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"] && ![(item.action?NSStringFromSelector(item.action):@"") isEqual:@"showRightTopMenuBtn"])continue;
        id raw=WXGRead(item,@"view");UIView *native=item.customView?:([raw isKindOfClass:UIView.class]?raw:nil);
        BOOL bound=NO;for(UIControl *control in controls)if(control==native || [control isDescendantOfView:native] || [native isDescendantOfView:control]){bound=YES;break;}
        if(bound || (home && _homePlusSurface) || ![self canForwardItem:item])continue;
        NSString *slot=[NSString stringWithFormat:@"%@%lu",side?@"right":@"left",(unsigned long)(side?rightSlot++:leftSlot++)];
        BOOL homePlusItem=home && item.action==@selector(showRightTopMenuBtn);
        if(homePlusItem)slot=@"right1";
        WXGSurface *surface=[self pooledSurface:slot];surface.role=@"barItemAction";WXGResetOwnedTransform(surface);
        if(surface.nativeContent){surface.nativeContent=nil;surface.nativeContentSource=nil;surface.nativeContentSignature=0;}   // FIX114 V
        surface.overrideUserInterfaceStyle=WXGFinderFeed(_route.leaf)?w.traitCollection.userInterfaceStyle:UIUserInterfaceStyleUnspecified;
        __weak UIBarButtonItem *weakItem=item;
        surface.perform=^{UIBarButtonItem *original=weakItem;if(!original || !original.enabled)return;
            [UIApplication.sharedApplication sendAction:original.action to:original.target from:original forEvent:nil];
            [WXGIntegrationHost.shared schedule];};
        UIImage *icon=item.image;
        if(!icon && [native isKindOfClass:UIControl.class])icon=WXGButtonImage((id)native);
        if(!icon && !item.title.length && homePlusItem && homeMenuStyle==WXGHomeMenuStyleMorph)icon=WXGHomePlusSymbol();
        [surface setNativeIconSource:native preservingColors:WXGFinderFeed(_route.leaf)];
        [surface setImage:icon title:icon?nil:item.title count:nil];
        surface.homePlusAnchor=homePlusItem;
        if(homePlusItem)_homePlusSurface=surface;
        surface.homePlusTrigger=homePlusItem && homeMenuStyle==WXGHomeMenuStyleCapsules;
        CGFloat width=icon?m.button:WXGCapsuleWidth([item.title sizeWithAttributes:@{NSFontAttributeName:surface.label.font}].width,0,m.button,14*m.scale,w.bounds.size.width*.32);
        CGRect bounds=CGRectMake(0,0,width+2*WXGCanvasPaddingX,m.button+2*WXGCanvasPaddingY);
        if(!CGRectEqualToRect(surface.bounds,bounds))surface.bounds=bounds;
        surface.glass.sourceView=_route.leaf.view;surface.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
        [(side?rightButtons:leftButtons) addObject:surface];[alive addObject:surface];if(native)[_navStates conceal:native];surface.motionHost=native;
    }
    for(WXGSurface *s in leftButtons) {
        CGFloat width=s.bounds.size.width-2*WXGCanvasPaddingX,height=s.bounds.size.height-2*WXGCanvasPaddingY;   // FIX114 V: its own height
        [s placeMaterial:CGRectMake(left,centerY-height*.5,width,height) inParent:_navigationOverlay];left+=width+m.gap;
        [_navStates conceal:s.original];
    }
    for(WXGSurface *s in rightButtons.reverseObjectEnumerator) {
        CGFloat width=s.bounds.size.width-2*WXGCanvasPaddingX,height=s.bounds.size.height-2*WXGCanvasPaddingY;right-=width;   // FIX114 V: its own height
        CGFloat y=home?[self homeCenterForSurface:s fallback:centerY]:centerY;
        if(home && s.homePlusAnchor)y=[w convertPoint:CGPointMake(0,y) toView:_navigationOverlay].y;
        [s placeMaterial:CGRectMake(right,y-height*.5,width,height) inParent:_navigationOverlay];right-=m.gap;
        [_navStates conceal:s.original];
    }
    CGFloat pinnedShift=_route.chat?rowDY:0;   // FIX109 B; FIX114 C: the module moves down with the row
    if(_route.chat) {
        UILabel *nativeLabel=nil;UIView *titleView=_route.leaf.navigationItem.titleView;
        for(UIView *v in WXGViews(titleView,80))if([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length && !v.hidden) {
            if(!nativeLabel || v.bounds.size.width*((UILabel *)v).font.pointSize>nativeLabel.bounds.size.width*nativeLabel.font.pointSize)nativeLabel=(id)v;
        }
        NSString *title=[self fullTitleFromView:titleView fallback:_route.leaf.navigationItem.title?:_route.leaf.title];
        if(chatNative && titleView){[_navStates restoreView:titleView];title=nil;}   // FIX114 B: WeChat's own title (the local glass's capsule behind it)
        if(title.length) {
            WXGSurface *t=nil,*a=nil;
            for(WXGSurface *s in _buttons){if([s.role isEqual:@"chatTitle"])t=s;if([s.role isEqual:@"avatar"])a=s;}
            if(!t){t=[self pooledSurface:@"chatTitle"];t.role=@"chatTitle";}
            // FIX109: the capsule under the avatar has its own height (头像下小胶囊高度).
            CGFloat avatarCapsule=WXGClamp([WXGConfig.shared extraNumber:@"avatarCapsuleHeight"],22,48);
            // FIX114 M (user: a taller capsule is for more empty room around
            // the text, not for larger text): the text has its own size
            // (头像下胶囊文字大小), whatever the height; only a capsule too low
            // for it shrinks it to fit (at most 0.62 of the height).
            CGFloat titleSize=17;
            if(WXGPreferences.shared.avatarTitle) {
                titleSize=WXGAvatarCapsuleTextSize([WXGConfig.shared extraNumber:@"avatarCapsuleTextSize"],avatarCapsule);
            }
            UIFont *titleFont=[UIFont systemFontOfSize:titleSize*m.scale weight:UIFontWeightSemibold];
            // FIX114 S (user, 13:12: the middle locked where it is, like the
            // plugin's own top buttons): with WeChat's own top buttons kept, the
            // chat's avatar and its capsule are laid out once in a push / pop and
            // then held there (no new size, text or place until it is over, and
            // not moved with WeChat's title on its way); they fade with it.
            // FIX114 Y (user, 01:25: the chat's title capsules still flicker in a
            // swipe back; diagnostics_18: without the avatar the capsule went at
            // every swipe's start for ~70 ms and for a frame at a cancel's end):
            // every chat title capsule (and avatar) is held, not only the avatar
            // mode's with WeChat's own buttons.
            BOOL holdMiddle=YES;
            BOOL frozen=holdMiddle && _nativeTransition && _middleSerial==_transitionSerial && _middleLeaf==_route.leaf && [_buttons containsObject:t] && (!a || [_buttons containsObject:a]);
            if(holdMiddle && _nativeTransition && !frozen){_middleSerial=_transitionSerial;_middleLeaf=_route.leaf;}
            t.holdsPlace=holdMiddle;
            [alive addObject:t];if(!frozen && ![t.label.font isEqual:titleFont])t.label.font=titleFont;
            UIControl *detail=rightButtons.count?((WXGSurface *)rightButtons.lastObject).original:nil;
            // FIX114 M (user: the avatar opens the chat's settings too): with
            // WeChat's own top buttons kept (no glass buttons of the plugin's),
            // its outermost right button (聊天信息) itself, as WXGLocalGlass leaves it.
            if(!detail)for(UIControl *c in controls)if(![self controlOnLeft:c] && ![self isBack:c] && WXGNavItemOwner(_route.nav,c)==_route.leaf)detail=c;
            // FIX114 M (user: iOS 26's capsule has a narrow grey chevron after
            // the name, as the top-right button opens the chat's settings; not
            // while the title says the other side is typing): in the avatar
            // mode, when the capsule opens the settings (头像下胶囊显示箭头).
            BOOL typing=[title containsString:@"正在输入"] || [title containsString:@"正在讲话"] || [title.lowercaseString containsString:@"typing"];
            // FIX114 T (diagnostics_13: after every cancelled swipe back the capsule
            // went 161 -> 149 -> 161 pt wide in two frames): WeChat puts its
            // top-right button in a moment after the title, and without it the
            // chevron went and came back. Kept for the page once it had it.
            if(detail)_chevronLeaf=_route.leaf;
            BOOL hasDetail=detail || (_chevronLeaf && _chevronLeaf==_route.leaf);
            BOOL chevron=WXGPreferences.shared.avatarTitle && hasDetail && !typing && [WXGConfig.shared extraNumber:@"avatarCapsuleChevron"]>.5;
            if(!frozen)t.trailingSymbol=chevron?WXGCapsuleChevron():nil;
            // FIX114 N (user, 08:35: the chevron a touch small): its height a setting
            // (头像下胶囊箭头大小, pt, default 14.5; it was 12 x text / 16).
            CGFloat chevronHeight=WXGClamp([WXGConfig.shared extraNumber:@"avatarCapsuleChevronSize"],8,24);
            if(!frozen){t.trailingSymbolHeight=round(chevronHeight*m.scale*3)/3;t.trailingGap=round(MAX(5,6*titleSize/16)*m.scale*3)/3;[t setImage:nil title:title count:nil];}
            t.motionHost=nativeLabel?:titleView;WXGResetOwnedTransform(t);t.original=detail;t.enabled=detail!=nil;t.glass.sourceView=_route.leaf.view;
            t.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
            if(WXGPreferences.shared.avatarTitle) {
                if(!a){a=[self pooledSurface:@"avatar"];a.role=@"avatar";}
                a.holdsPlace=holdMiddle;   // FIX114 S
                // FIX88: looked up until found (kept per chat page); the title tells groups apart.
                UIImage *avatar=[self avatarImageForTitle:title];
                // FIX94: no glass: the photo itself, the glass's former size.
                if(!a.plain)a.plain=YES;
                if(!frozen)[a setImage:avatar?:WXGAvatarPlaceholder() title:nil count:nil];   // the same image: no work
                [alive addObject:a];a.motionHost=nativeLabel?:titleView;WXGResetOwnedTransform(a);a.original=detail;a.enabled=detail!=nil;a.glass.sourceView=_route.leaf.view;
                a.glass.backdropExclusions=t.glass.backdropExclusions;
                // FIX95: size and height are settings; the title capsule stays
                // where the default 60 pt avatar puts it (its top 5 pt under the
                // avatar's lower edge), the avatar about its own centre.
                CGFloat nominal=60*m.scale,y=centerY-m.button*.5;
                CGFloat diameter=WXGClamp(WXGConfig.shared.avatarSize,32,88)*m.scale;
                CGFloat avatarMid=y+nominal*.5+WXGClamp(WXGConfig.shared.avatarOffsetY,-24,24)*m.scale;
                if(!frozen)[a placeMaterial:CGRectMake(midX-diameter*.5,avatarMid-diameter*.5,diameter,diameter) inParent:_navigationOverlay];
                // FIX114 M: room for the chevron (its gap and width) beside the text.
                CGFloat extra=t.trailingSymbol?t.trailingGap+t.trailingSymbolHeight*t.trailingSymbol.size.width/MAX(.01,t.trailingSymbol.size.height):0;
                // FIX114 O (user: the two sides out of balance next to iOS 26's):
                // with the chevron, 14 pt before the text and 11 pt after the
                // chevron, as measured on the user's screenshot (13.7 / 11).
                CGFloat padBefore=14*m.scale,padAfter=t.trailingSymbol?11*m.scale:padBefore;
                if(!frozen)t.trailingBias=(padBefore-padAfter)*.5;
                CGFloat th=avatarCapsule*m.scale,tw=WXGCapsuleWidth([title sizeWithAttributes:@{NSFontAttributeName:t.label.font}].width+(padBefore+padAfter)-28*m.scale,extra,th,14*m.scale,w.bounds.size.width*.70);
                if(!frozen)[t placeMaterial:CGRectMake(midX-tw*.5,y+nominal-5*m.scale,tw,th) inParent:_navigationOverlay];
                // FIX109 B: the pinned module keeps the gap it has under the
                // default title capsule (bottom centerY + m.button / 2) below
                // the avatar mode's lowest part (the small capsule, or the
                // avatar when it is set lower / larger).
                CGFloat lowest=MAX(y+nominal-5*m.scale+th,avatarMid+diameter*.5),scale=w.screen.scale?:3;
                // FIX109 B: the gap itself adjustable (置顶与小胶囊间距, pt; negative closer).
                CGFloat gapAdjust=WXGClamp([WXGConfig.shared extraNumber:@"pinnedGapAdjust"],-16,16)*m.scale;
                pinnedShift=MAX(0,round((lowest-(centerY0+m.button*.5)+gapAdjust)*scale)/scale);   // FIX114 C: from where WeChat has it
                // FIX94: the avatar one layer above the title capsule (its lower
                // edge overlaps the capsule; the capsule must never cut into it).
                if(a.superview==_navigationOverlay && t.superview==_navigationOverlay &&
                   [_navigationOverlay.subviews indexOfObjectIdenticalTo:a]<[_navigationOverlay.subviews indexOfObjectIdenticalTo:t])
                    [_navigationOverlay insertSubview:a aboveSubview:t];
            } else {
                CGFloat limit=2*MAX(0,MIN(midX-left,right-midX));
                if(!leftButtons.count)limit=2*MAX(0,MIN(midX-(w.safeAreaInsets.left+edge),right-midX));
                limit=MAX(0,limit);
                if(limit>=m.button) {
                    CGFloat tw=WXGCapsuleWidth([title sizeWithAttributes:@{NSFontAttributeName:t.label.font}].width,0,m.button,14*m.scale,limit);
                    if(!frozen)[t placeMaterial:CGRectMake(midX-tw*.5,centerY-m.button*.5,tw,m.button) inParent:_navigationOverlay];   // FIX114 Y
                }else{[alive removeObject:t];}
            }
            if([alive containsObject:t] && titleView)[_navStates conceal:titleView];
            else if(titleView)[_navStates restoreView:titleView];
        }
        static Class chatBarClass;static dispatch_once_t chatBarOnce;
        dispatch_once(&chatBarOnce,^{chatBarClass=NSClassFromString(@"MMNewMsgContentNavBar");});
        if(chatBarClass && _route.leaf.isViewLoaded)for(UIView *v in _route.leaf.view.subviews)if([v isKindOfClass:chatBarClass]){_pinnedBar=v;break;}
    }
    // FIX109 C: only a chat page sets it: leaving (back to the list, the
    // module's page sliding away) keeps the module where it is (B put it back
    // at once and it overlapped the title again while the page left).
    if(_route.chat){_pinnedShift=pinnedShift;[self alignPinnedModule];}
    if(home && _route.primary) {
        Class cls=NSClassFromString(@"MainFrameLeftBarView");
        for(UIView *v in WXGViews(bar,200))if([v isKindOfClass:cls])[_homeGestureHosts addObject:v];
        for(UIView *v in _pageViews)if([v isKindOfClass:cls])[_homeGestureHosts addObject:v];
        UIView *leftHost=[self homeHostFrom:_homeGestureHosts current:_surfacePool[@"nativeLeft0"].motionHost pulling:[self currentHomePull]>.5];
        if(leftHost) {
            WXGSurface *surface=[self bindHomeGesture:leftHost diameter:m.button slot:@"nativeLeft0"];
            if(surface){[alive addObject:surface];[self concealHomeTwins:_homeGestureHosts except:surface.superview];}
        }
    }else if(_route.primary) {
        NSUInteger slot=0;
        NSMutableArray *candidates=[WXGViews(bar,200) mutableCopy];[candidates addObjectsFromArray:_pageViews?:@[]];
        NSMutableSet *visited=[NSMutableSet set];
        for(UIView *v in candidates) {
            if([visited containsObject:v])continue;[visited addObject:v];
            if(!v.gestureRecognizers.count || !WXGVisible(v,w) || ([v isKindOfClass:UIControl.class] && WXGCanForward((id)v)))continue;
            CGRect r=WXGWindowRect(v,w);
            if(r.size.width<12 || r.size.width>65 || r.size.height<12 || r.size.height>65 || CGRectGetMidX(r)>w.bounds.size.width*.28 || fabs(CGRectGetMidY(r)-centerY)>24)continue;
            WXGSurface *surface=[self bindHomeGesture:v diameter:m.button slot:[NSString stringWithFormat:@"nativeLeft%lu",(unsigned long)slot++]];
            if(surface)[alive addObject:surface];
        }
    }
    // Measure the home group in the navigation row while native buttons set its width.
    BOOL strictHome=home && _route.primary && !_route.unsupported && !_suspendedByCover;
    if(strictHome && [WXGChatSegments.shared titleModeWanted]) {
        UIView *navTitle=_route.leaf.navigationItem.titleView;
        UIView *pullTitle=nil;
        static Class mfTitleCls;static dispatch_once_t mfOnce;
        dispatch_once(&mfOnce,^{mfTitleCls=NSClassFromString(@"MFTitleView");});
        if(mfTitleCls) {
            for(UIView *gh in _homeGestureHosts) {
                UIView *parent=gh.superview;
                if(!parent || parent.window!=w || [parent isDescendantOfView:bar])continue;
                for(UIView *sib in parent.subviews) {
                    if(sib!=navTitle && [sib isKindOfClass:mfTitleCls]){pullTitle=sib;break;}
                }
                if(pullTitle)break;
            }
        }
        UIView *sampleTitle=navTitle?:pullTitle?:_homeTitleView;
        NSString *titleTxt=[self fullTitleFromView:sampleTitle fallback:_route.leaf.navigationItem.title?:_route.leaf.title];
        BOOL enHint=titleTxt && [titleTxt.lowercaseString containsString:@"wechat"];
        CGFloat leftBound=w.safeAreaInsets.left+edge,rightBound=w.bounds.size.width-w.safeAreaInsets.right-edge;
        for(WXGSurface *s in alive) {
            if(!s.window || s.hidden || [s.role isEqual:@"chatTitle"] || [s.role isEqual:@"avatar"])continue;
            CGRect sr=[s convertRect:s.materialRect toView:w];
            if(CGRectIsEmpty(sr))continue;
            if(CGRectGetMidX(sr)<midX)leftBound=MAX(leftBound,CGRectGetMaxX(sr)+m.gap);
            else rightBound=MIN(rightBound,CGRectGetMinX(sr)-m.gap);
        }
        CGFloat avail=floor(2.*MAX(0,MIN(midX-leftBound,rightBound-midX)));
        if(avail>=m.button*1.8) {
            // The segment bar fits the actual title glyphs within these nav-button limits.
            CGFloat titleHeight=round(m.button);
            CGFloat titleCenter=CGRectGetMidY(nr)+rowDY;
            CGRect tr=[w convertRect:CGRectMake(midX-avail*.5,titleCenter-titleHeight*.5,avail,titleHeight) toView:_navigationOverlay];
            [WXGChatSegments.shared updateTitleBarOnPage:_route.leaf inOverlay:_navigationOverlay rect:tr navTitle:navTitle pullTitle:pullTitle englishHint:enHint];
        }else [WXGChatSegments.shared hideTitleBar];
    }else if(![WXGChatSegments.shared titleModeWanted]) {
        [WXGChatSegments.shared releaseTitleBar];
    }else if(!_nativeTransition) {
        [WXGChatSegments.shared hideTitleBar];
    }
    for(WXGSurface *s in _buttons.copy)if(![alive containsObject:s]) {
        BOOL temporary=s.motionHost.window==w && s.motionOwner==_route.leaf &&
            (_nativeTransition || !WXGVisible(s.motionHost,w));
        if(temporary)continue;
        s.active=NO;s.hidden=YES;if(s.original && ![s.role isEqual:@"chatTitle"] && ![s.role isEqual:@"avatar"])[_navStates restoreView:s.original];[_buttons removeObject:s];
        // FIX115 T: a capsule gone: WeChat's buttons it hid shown again.
        if([s.role isEqual:@"finderCapsule"]){WXGFinderLink *link=objc_getAssociatedObject(s,&WXGFinderLinkKey);if(link.concealed.count)[self showFinderIconsOf:link fade:NO];}
    }
    [self styleFinderButtons];
    [self moveNativeRow:bar by:rowDY metrics:m home:home];   // FIX114 C
    // FIX114 B: what each page's title row looked like last (exported from the
    // settings page the scene there is the settings'): every glass's place on
    // screen, its button's, and the outer margins.
    @try {
        NSMutableArray *rows=[NSMutableArray array];CGFloat minX=CGFLOAT_MAX,maxX=-CGFLOAT_MAX;
        for(WXGSurface *s in _buttons) {
            if(!s.window || s.hidden)continue;
            CGRect glass=[s convertRect:s.materialRect toView:w];
            CGRect native=s.original?WXGWindowRect(s.original,w):(s.motionHost?WXGWindowRect(s.motionHost,w):CGRectNull);
            [rows addObject:@{@"role":s.role?:@"",@"glass":NSStringFromCGRect(glass),@"native":CGRectIsNull(native)?@"-":NSStringFromCGRect(native),
                              @"shift":@([_navStates contentShiftOf:s.motionHost])}];
            if(![s.role isEqual:@"chatTitle"] && ![s.role isEqual:@"avatar"]){minX=MIN(minX,CGRectGetMinX(glass));maxX=MAX(maxX,CGRectGetMaxX(glass));}
        }
        if(!_navSnapshots)_navSnapshots=[NSMutableDictionary dictionary];
        NSString *page=NSStringFromClass(_route.leaf.class)?:@"?";
        if(_navSnapshots.count>=12 && !_navSnapshots[page])[_navSnapshots removeObjectForKey:_navSnapshots.allKeys.firstObject];
        _navSnapshots[page]=@{@"glasses":rows,@"leftMargin":@(minX<CGFLOAT_MAX?round((minX-w.safeAreaInsets.left)*10)/10:-1),
                              @"rightMargin":@(maxX>-CGFLOAT_MAX?round((w.bounds.size.width-w.safeAreaInsets.right-maxX)*10)/10:-1),
                              @"nativeButtons":@(nativeButtons),@"edge":@(round(edge*10)/10),@"rowOffset":@(rowDY),@"rowBarContents":@(_rowBarContents),@"homeTitleOutsideBar":@(home && _homeTitleView && ![_homeTitleView isDescendantOfView:bar]),
                              @"openedClips":WXGRowOpenedClips.array?:@[]};
    } @catch(__unused NSException *error) {}
    for(WXGSurface *surface in _buttons) {
        surface.nativeTransitionActive=_nativeTransition!=nil;
        if(!WXGSurfaceInNativeView(surface)){[surface bindMotionHost:surface.motionHost owner:_route.leaf];[surface followNativePresentation];}
    }
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
    if(home)_homeControlsChanged=YES;
    if(home && _homePlusSurface)[self concealHomeTwins:_homePlusControls except:nil];
    if(home && (_homeSearchSurface || [self dockSearchAvailable]))[self concealHomeTwins:_homeSearchControls except:nil];
    _navigationBindingKey=[self currentNavigationBindingKey];
    if(home) {
        UIView *title=_route.leaf.navigationItem.titleView;
        _homeNavigationRevision=WXGConfigRevision();_homeNavigationHidden=bar.hidden || _route.nav.navigationBarHidden;
        _homeNavigationStyle=bar.traitCollection.userInterfaceStyle;
        _homeNavigationTitle=title;_homeNavigationTitleParent=title.superview;_homeNavigationTitleBounds=title.bounds;
        _homeNavigationWindowBounds=w.bounds;_homeNavigationSafeArea=w.safeAreaInsets;_homeNavigationRect=WXGWindowRect(bar,w);
        WXGRecordHomeNavigationWork(bar,(CACurrentMediaTime()-buildStart)*1000.,0);
    }
}
// Glass the plugin put inside WeChat's own views (the home page's left icon,
// 视频号's capsules): it moves with them, nothing to follow.
static BOOL WXGSurfaceInNativeView(WXGSurface *surface) {
    return [surface.role isEqual:@"nativeGesture"] || [surface.role isEqual:@"finderCapsule"];
}
static BOOL WXGFinderBadgeView(UIView *v) {
    if(!v)return YES;
    NSString *cls=NSStringFromClass(v.class);
    return [cls containsString:@"RedDot"] || [cls containsString:@"Badge"];
}
- (void)bindFinderCapsules:(NSArray<UIControl *> *)controls metrics:(WXGMetrics)m alive:(NSMutableSet *)alive {
    UIWindow *w=_window;UINavigationBar *bar=_route.nav.navigationBar;
    if(!w || !bar)return;
    if(!_finderShiftHosts)_finderShiftHosts=[NSHashTable weakObjectsHashTable];
    for(UIView *host in _finderShiftHosts.allObjects)[_navStates shiftContents:host x:0];
    [_finderShiftHosts removeAllObjects];
    NSMutableArray<UIView *> *natives=[NSMutableArray array];
    UINavigationItem *item=_route.leaf.navigationItem;
    for(UIControl *c in controls)if(WXGVisible(c,w) && !WXGFinderBadgeView(c) && !WXGInTitleView(_route.nav,c) && !WXGFinderTab(c,bar))[natives addObject:c];
    // R20: walk shared customViews so sibling Back + floating PiP buttons are
    // BOTH discovered instead of skipping the whole customView when Back is found.
    for(UIBarButtonItem *button in [item.leftBarButtonItems?:@[] arrayByAddingObjectsFromArray:item.rightBarButtonItems?:@[]]) {
        id raw=WXGRead(button,@"view");UIView *native=button.customView?:([raw isKindOfClass:UIView.class]?raw:nil);
        if(!native || !WXGVisible(native,w) || WXGFinderBadgeView(native))continue;
        BOOL foundSub=NO;
        for(UIView *sub in WXGViews(native,64)) {
            if(sub==native || WXGIsPluginView(sub) || !WXGVisible(sub,w) || WXGFinderBadgeView(sub))continue;
            if(WXGInTitleView(_route.nav,sub) || WXGFinderTab(sub,bar))continue;
            BOOL tappable=[sub isKindOfClass:UIControl.class] || sub.gestureRecognizers.count>0;
            if(!tappable)continue;
            CGRect sr=WXGWindowRect(sub,w);
            if(sr.size.width<16 || sr.size.height<16 || sr.size.width>w.bounds.size.width*.4 || sr.size.height>m.button*1.5)continue;
            BOOL dup=NO;for(UIView *v in natives)if(v==sub || [v isDescendantOfView:sub] || [sub isDescendantOfView:v]){dup=YES;break;}
            if(!dup){[natives addObject:sub];foundSub=YES;}
        }
        if(!foundSub) {
            BOOL bound=NO;for(UIView *v in natives)if(v==native || [v isDescendantOfView:native] || [native isDescendantOfView:v]){bound=YES;break;}
            if(!bound)[natives addObject:native];
        }
    }
    // Also discover any bar-hosted UIControls (e.g. Finder floating PiP button)
    // that navigationControls did not forward, excluding red-dot badges.
    for(UIView *sub in WXGViews(bar,160)) {
        if(sub==bar || WXGIsPluginView(sub) || !WXGVisible(sub,w) || ![sub isKindOfClass:UIControl.class] || WXGFinderBadgeView(sub))continue;
        if(WXGInTitleView(_route.nav,sub) || WXGFinderTab(sub,bar))continue;
        CGRect sr=WXGWindowRect(sub,w);
        if(sr.size.width<16 || sr.size.height<16 || sr.size.width>w.bounds.size.width*.35 || sr.size.height>m.button*1.5)continue;
        BOOL dup=NO;for(UIView *v in natives)if(v==sub || [v isDescendantOfView:sub] || [sub isDescendantOfView:v]){dup=YES;break;}
        if(!dup)[natives addObject:sub];
    }
    // Each one's ink (the icon, else the view), in the window.
    NSMutableArray<NSDictionary *> *marks=[NSMutableArray array];
    NSMutableArray<NSString *> *discovered=[NSMutableArray array];
    for(UIView *native in natives) {
        UIView *ink=[native isKindOfClass:UIControl.class]?[self motionInkForControl:(UIControl *)native]:native;
        CGRect r=WXGWindowRect(ink,w);
        if(CGRectIsEmpty(r) || r.size.width<4 || r.size.height<4 || r.size.width>w.bounds.size.width*.4 || r.size.height>m.button*1.5)continue;
        BOOL text=[ink isKindOfClass:UILabel.class];
        if(!text && ![ink isKindOfClass:UIImageView.class] && [native isKindOfClass:UIButton.class]) {
            UIButton *button=(UIButton *)native;UILabel *label=button.currentTitle.length && !button.currentImage?button.titleLabel:nil;
            CGRect t=label.window==w && !label.hidden && label.text.length?WXGWindowRect(label,w):CGRectNull;
            if(!CGRectIsNull(t) && t.size.width>=4 && t.size.height>=4){text=YES;r=t;}
        }
        [marks addObject:@{@"view":native,@"rect":[NSValue valueWithCGRect:r],@"text":@(text)}];
        if(discovered.count<16)[discovered addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f",NSStringFromClass(native.class),r.origin.x,r.origin.y,r.size.width,r.size.height]];
    }
    [marks sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        CGFloat x=CGRectGetMidX([a[@"rect"] CGRectValue]),y=CGRectGetMidX([b[@"rect"] CGRectValue]);
        return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;}];
    // Groups: same side, next to each other (widened to 2.15 buttons so Back + PiP always merge).
    NSMutableArray<NSMutableArray<NSDictionary *> *> *groups=[NSMutableArray array];
    CGFloat mid=CGRectGetMidX(w.bounds);
    for(NSDictionary *mark in marks) {
        CGRect r=[mark[@"rect"] CGRectValue];NSDictionary *last=groups.lastObject.lastObject;
        CGRect p=last?[last[@"rect"] CGRectValue]:CGRectNull;
        BOOL join=last && (CGRectGetMidX(p)<mid)==(CGRectGetMidX(r)<mid) && CGRectGetMidX(r)-CGRectGetMidX(p)<=m.button*2.15 &&
            fabs(CGRectGetMidY(r)-CGRectGetMidY(p))<m.button*.55;
        if(join)[groups.lastObject addObject:mark];else [groups addObject:[NSMutableArray arrayWithObject:mark]];
    }
    UIView *title=item.titleView.window==w && [item.titleView isDescendantOfView:bar]?item.titleView:nil;
    NSMutableArray<NSDictionary *> *capsules=[NSMutableArray array];
    CGFloat rightMargin=NAN,leftEdge=CGFLOAT_MAX,rightNow=NAN;
    CGFloat pad=14*m.scale;
    for(NSArray<NSDictionary *> *group in groups) {
        NSMutableArray<UIView *> *views=[NSMutableArray array];
        CGFloat x0=CGFLOAT_MAX,x1=-CGFLOAT_MAX,n1=-CGFLOAT_MAX,y=0;
        for(NSDictionary *mark in group) {
            CGRect r=[mark[@"rect"] CGRectValue];[views addObject:mark[@"view"]];
            CGFloat natural=MAX(m.button*.5,r.size.width*.5+(m.button-MIN(r.size.height,m.button))*.5);
            CGFloat half=[mark[@"text"] boolValue]?MAX(m.button*.5,r.size.width*.5+pad):natural;
            x0=MIN(x0,CGRectGetMidX(r)-half);x1=MAX(x1,CGRectGetMidX(r)+half);n1=MAX(n1,CGRectGetMidX(r)+natural);y+=CGRectGetMidY(r)/group.count;
        }
        UIView *parent=WXGCommonParent(views);
        if(!parent || parent.window!=w || !(parent==bar || [parent isDescendantOfView:bar]))continue;
        UIView *holder=WXGFinderHolder(parent,title,bar);
        UIView *below=nil;
        for(UIView *child in holder.subviews) {
            if(WXGIsPluginView(child))continue;
            BOOL holds=NO;for(UIView *v in views)if(v==child || [v isDescendantOfView:child]){holds=YES;break;}
            if(holds){below=child;break;}
        }
        if(!below)continue;
        BOOL left=(x0+x1)*.5<mid;
        if(left)leftEdge=MIN(leftEdge,x0);
        else {
            rightMargin=isnan(rightMargin)?CGRectGetMaxX(w.bounds)-n1:MIN(rightMargin,CGRectGetMaxX(w.bounds)-n1);
            rightNow=isnan(rightNow)?CGRectGetMaxX(w.bounds)-x1:MIN(rightNow,CGRectGetMaxX(w.bounds)-x1);
        }
        [capsules addObject:@{@"views":views,@"parent":parent,@"holder":holder,@"below":below,@"left":@(left),
                              @"rect":[NSValue valueWithCGRect:CGRectMake(x0,y-m.button*.5,x1-x0,m.button)]}];
    }
    CGFloat E=WXGFinderRowEdge(m.scale),shift=0;
    if(leftEdge<CGFLOAT_MAX)shift=WXGClamp(CGRectGetMinX(w.bounds)+w.safeAreaInsets.left+E-leftEdge,-m.button,m.button);
    if(fabs(shift)<.5)shift=0;
    CGFloat rshift=isfinite(rightNow)?WXGClamp(E+w.safeAreaInsets.right-rightNow,-m.button,m.button):0;
    if(fabs(rshift)<.5)rshift=0;
    {CGFloat px=w.screen.scale?:3;shift=round(shift*px)/px;rshift=round(rshift*px)/px;}
    NSMutableArray *evidence=[NSMutableArray array];
    NSUInteger slot=0;
    for(NSDictionary *capsule in capsules) {
        UIView *parent=capsule[@"parent"],*holder=capsule[@"holder"],*below=capsule[@"below"];NSArray<UIView *> *views=capsule[@"views"];
        CGRect rect=[capsule[@"rect"] CGRectValue];BOOL left=[capsule[@"left"] boolValue];
        CGRect rest=CGRectNull;
        for(UIView *v in views)rest=CGRectIsNull(rest)?[holder convertRect:v.bounds fromView:v]:CGRectUnion(rest,[holder convertRect:v.bounds fromView:v]);
        {CATransform3D row=holder.layer.sublayerTransform;if(!CGRectIsNull(rest) && row.m11==1 && row.m12==0 && row.m21==0 && row.m22==1)rest=CGRectOffset(rest,-row.m41,-row.m42);}
        NSString *how=@"none";
        if(left && shift!=0) {
            CGRect area=WXGWindowRect(parent,w);
            if(parent!=bar && parent!=holder && CGRectGetMaxX(area)<=mid+1){[_navStates shiftContents:parent x:shift];[_finderShiftHosts addObject:parent];how=@"container";}
            else {for(UIView *v in views){[_navStates shiftContents:v x:shift];[_finderShiftHosts addObject:v];}how=@"buttons";}
            rect=CGRectOffset(rect,shift,0);
        }else if(!left && rshift!=0) {
            CGRect area=WXGWindowRect(parent,w);
            if(parent!=bar && parent!=holder && CGRectGetMinX(area)>=mid-1){[_navStates shiftContents:parent x:-rshift];[_finderShiftHosts addObject:parent];how=@"container";}
            else {for(UIView *v in views){[_navStates shiftContents:v x:-rshift];[_finderShiftHosts addObject:v];}how=@"buttons";}
            rect=CGRectOffset(rect,-rshift,0);
        }
        WXGSurface *s=[self pooledSurface:[NSString stringWithFormat:@"finderCapsule%lu",(unsigned long)slot++]];
        s.role=@"finderCapsule";s.motionHost=nil;s.motionOwner=_route.leaf;s.followsNative=NO;s.materialOnly=YES;
        WXGResetOwnedTransform(s);[s setNativeIconSource:nil preservingColors:NO];[s setImage:nil title:nil count:nil];
        s.overrideUserInterfaceStyle=w.traitCollection.userInterfaceStyle;
        s.glass.glassScopeOverride=WXGGlassScopeFinder;
        s.glass.rimScopeOverride=WXGGlassScopeFinder;
        s.glass.veilOverride=nil;
        [s applyConfig];
        s.glass.sourceView=_route.leaf.view;
        s.glass.backdropExclusions=_inputAdapter.tool?@[_inputAdapter.tool,bar]:@[bar];
        [_navStates allowOverflow:parent];[_navStates allowOverflow:holder];
        CGRect local=[holder convertRect:rect fromView:nil];
        CATransform3D row=holder.layer.sublayerTransform;
        if(row.m11==1 && row.m12==0 && row.m21==0 && row.m22==1)local=CGRectOffset(local,-row.m41,-row.m42);
        [s placeMaterial:local inParent:holder];
        NSUInteger at=[holder.subviews indexOfObjectIdenticalTo:s],under=[holder.subviews indexOfObjectIdenticalTo:below];
        if(at==NSNotFound || under==NSNotFound || at>under)[holder insertSubview:s belowSubview:below];
        WXGFinderLink *link=objc_getAssociatedObject(s,&WXGFinderLinkKey);
        if(!link){link=[WXGFinderLink new];objc_setAssociatedObject(s,&WXGFinderLinkKey,link,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        link.views=[NSHashTable weakObjectsHashTable];for(UIView *v in views)[link.views addObject:v];
        link.holder=holder;link.container=parent;link.title=[title isDescendantOfView:holder]?title:nil;
        CGFloat moved=left?shift:-rshift;
        link.left=left;link.shift=[how isEqual:@"container"]?moved:0;link.placedShift=[how isEqual:@"none"]?0:moved;link.missingNoted=NO;
        if(!CGRectIsNull(rest))link.rest=rest;
        if(_nativeTransition && _transitionTo==_route.leaf){if(!link.veiled)++_finderEntryVeils;link.veiled=YES;link.leaving=NO;}
        BOOL reveal=NO,unveiled=NO;
        if(link.veiled && !_nativeTransition){link.veiled=NO;link.leaving=NO;unveiled=YES;reveal=YES;}
        s.hidden=NO;[alive addObject:s];[self followFinderCapsule:s];
        if(reveal && s.alpha>.01) {
            CABasicAnimation *in=[CABasicAnimation animationWithKeyPath:@"opacity"];
            in.fromValue=@0;in.toValue=@(s.layer.opacity);in.duration=.2;
            in.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [s.layer addAnimation:in forKey:@"wxg.finderReveal"];++_finderReveals;
        }
        if(unveiled)[self showFinderIconsOf:link fade:reveal];
        [evidence addObject:@{@"side":left?@"left":@"right",@"buttons":@(views.count),@"parent":NSStringFromClass(parent.class),
                              @"holder":NSStringFromClass(holder.class),@"below":NSStringFromClass(below.class),@"title":@(link.title!=nil),
                              @"alpha":@(round(s.alpha*100)/100),
                              @"x":@(round(CGRectGetMinX(rect)*10)/10),@"w":@(round(rect.size.width*10)/10),@"shift":@(round(moved*10)/10),@"shiftedBy":how}];
    }
    _finderEvidence=@{@"page":NSStringFromClass(_route.leaf.class)?:@"",@"discovered":discovered,@"capsules":evidence,
                      @"rightMargin":isfinite(rightMargin)?@(round(rightMargin*10)/10):NSNull.null,
                      @"rightNow":isfinite(rightNow)?@(round(rightNow*10)/10):NSNull.null,@"textPadding":@(round(pad*10)/10),
                      @"leftEdge":leftEdge<CGFLOAT_MAX?@(round(leftEdge*10)/10):NSNull.null,
                      @"finderEdge":@(round(E*10)/10),@"leftShift":@(round(shift*10)/10),@"rightShift":@(round(-rshift*10)/10)};
}
- (void)followFinderCapsule:(WXGSurface *)s {
    WXGFinderLink *link=objc_getAssociatedObject(s,&WXGFinderLinkKey);
    UIView *holder=link.holder;
    if(!link || !holder || s.superview!=holder || !holder.window)return;
    NSArray<UIView *> *views=link.views.allObjects;
    NSMutableArray<UIView *> *live=[NSMutableArray array];
    for(UIView *v in views)if(v.window==holder.window && [v isDescendantOfView:holder])[live addObject:v];
    if(link.veiled && _nativeTransition && _transitionFrom==s.motionOwner)[self hideFinderCopiesOf:link];
    BOOL settled=!_nativeTransition || !_route.nav.transitionCoordinator;
    if(link.veiled && settled && live.count) {
        CFTimeInterval now=CACurrentMediaTime();
        if(link.veiledAtRest<=0){link.veiledAtRest=now;_navigationDirty=YES;[self schedule];}
        else if(now-link.veiledAtRest>.6) {
            link.veiled=NO;link.leaving=NO;link.veiledAtRest=0;[self showFinderIconsOf:link fade:YES];
            CABasicAnimation *in=[CABasicAnimation animationWithKeyPath:@"opacity"];
            in.fromValue=@0;in.toValue=@1;in.duration=.2;in.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [s.layer addAnimation:in forKey:@"wxg.finderReveal"];
        }
    }else link.veiledAtRest=0;
    BOOL givenUp=_nativeTransition && _transitionFrom==s.motionOwner && (_nativeTransition.isCancelled || !_route.nav.transitionCoordinator);
    if(link.veiled && link.leaving && live.count && (!_nativeTransition || givenUp)) {
        if(!_navStates)_navStates=[WXGStateBag new];
        if(!link.concealed)link.concealed=[NSHashTable weakObjectsHashTable];
        for(UIView *v in live)if(![link.concealed containsObject:v] || ![v.layer.mask.name isEqual:@"wxg.conceal"]){[_navStates conceal:v];[link.concealed addObject:v];++_finderIconsConcealed;}
    }
    double alpha=0;
    if(live.count) {
        link.missingNoted=NO;
        for(UIView *v in live)alpha=MAX(alpha,WXGOpacityBelow(v,holder));
        UIView *container=live.count==views.count?WXGCommonParent(live):nil;
        // R20: re-apply shift both when UIKit swaps container AND when UIKit
        // resets sublayerTransform on the same container (e.g. after background).
        BOOL shiftLost=container && fabs(link.shift)>.01 && fabs(container.layer.sublayerTransform.m41-link.shift)>.5;
        if(fabs(link.shift)>.01 && _navStates && (container!=link.container || shiftLost) && WXGFinderContainerFits(link,container)) {
            [_navStates allowOverflow:container];[_navStates shiftContents:container x:link.shift];
            if(!_finderShiftHosts)_finderShiftHosts=[NSHashTable weakObjectsHashTable];
            [_finderShiftHosts addObject:container];link.container=container;++_finderReshifts;
        }
        // R20: self-heal if native buttons drifted relative to holder at rest
        // (e.g. after returning from background or PiP appearing/disappearing).
        if(!_nativeTransition && !_route.nav.transitionCoordinator && !link.veiled &&
           live.count==views.count && !CGRectIsNull(link.rest) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive) {
            CGRect nowRest=CGRectNull;
            for(UIView *v in live)nowRest=CGRectIsNull(nowRest)?[holder convertRect:v.bounds fromView:v]:CGRectUnion(nowRest,[holder convertRect:v.bounds fromView:v]);
            CATransform3D row=holder.layer.sublayerTransform;
            if(!CGRectIsNull(nowRest) && row.m11==1 && row.m12==0 && row.m21==0 && row.m22==1)nowRest=CGRectOffset(nowRest,-row.m41,-row.m42);
            if(!CGRectIsNull(nowRest) && fabs(link.placedShift)>.01)nowRest=CGRectOffset(nowRest,-link.placedShift,0);
            if(!CGRectIsNull(nowRest) &&
               (fabs(nowRest.origin.x-link.rest.origin.x)>1.5 || fabs(nowRest.origin.y-link.rest.origin.y)>1.5 || fabs(nowRest.size.width-link.rest.size.width)>2.)) {
                link.rest=nowRest;_navigationDirty=YES;++_finderDriftRebuilds;[self schedule];
            }
        }
        UIView *branch=nil;
        for(UIView *child in holder.subviews) {
            if(WXGIsPluginView(child))continue;
            BOOL holds=NO;for(UIView *v in live)if(v==child || [v isDescendantOfView:child]){holds=YES;break;}
            if(holds){branch=child;break;}
        }
        NSUInteger at=[holder.subviews indexOfObjectIdenticalTo:s],under=branch?[holder.subviews indexOfObjectIdenticalTo:branch]:NSNotFound;
        if(at!=NSNotFound && under!=NSNotFound && at>under)[holder insertSubview:s belowSubview:branch];
    }else if(link.veiled) {
    }else if(_nativeTransition || _route.nav.transitionCoordinator) {
        UIView *title=link.title;
        if(title.window==holder.window && [title isDescendantOfView:holder]){alpha=WXGOpacityBelow(title,holder);++_finderTitleFrames;}
        else ++_finderAwayFrames;
    }else {
        ++_finderAwayFrames;
        if(!link.missingNoted){link.missingNoted=YES;_navigationDirty=YES;[self schedule];}
    }
    if(link.veiled)alpha=0;
    alpha=WXGClamp(alpha,0,1);
    if(alpha<.01)[s.layer removeAnimationForKey:@"wxg.finderReveal"];
    if(fabs(s.alpha-alpha)<.002)return;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        s.alpha=alpha;
        [CATransaction commit];
    }];
}
- (void)followFinderCapsules {
    for(WXGSurface *s in _buttons)if(!s.hidden && [s.role isEqual:@"finderCapsule"])[self followFinderCapsule:s];
    for(WXGSurface *s in _departingButtons)if(!s.hidden && [s.role isEqual:@"finderCapsule"])[self followFinderCapsule:s];
}
- (void)followFinderCapsulesBeforeCommit {
    if(!WXGPluginEnabled() || _suspendedByCover || WXGBackdropCaptureInProgress() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    BOOL any=NO;
    for(WXGSurface *s in _buttons)if([s.role isEqual:@"finderCapsule"] && !s.hidden){any=YES;break;}
    if(!any)for(WXGSurface *s in _departingButtons)if([s.role isEqual:@"finderCapsule"] && !s.hidden){any=YES;break;}
    if(!any)return;
    @try {[self followFinderCapsules];}
    @catch(NSException *e){WXGLog(@"视频号胶囊提交前跟随：%@",e.reason);}
}
- (void)showFinderIconsOf:(WXGFinderLink *)link fade:(BOOL)fade {
    NSArray<UIView *> *views=link.concealed.allObjects;[link.concealed removeAllObjects];
    for(UIView *v in views) {
        [_navStates unconceal:v];
        if(!fade || !v.window)continue;
        CABasicAnimation *in=[CABasicAnimation animationWithKeyPath:@"opacity"];
        in.fromValue=@0;in.toValue=@(v.layer.opacity);in.duration=.2;
        in.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [v.layer addAnimation:in forKey:@"wxg.finderReveal"];++_finderIconReveals;
    }
}
- (void)clearFinderShifts {
    if(!_finderShiftHosts.count)return;
    for(UIView *host in _finderShiftHosts.allObjects)[_navStates shiftContents:host x:0];
    [_finderShiftHosts removeAllObjects];_finderEvidence=nil;
}
// R20: Finder capsules use WXGGlassScopeFinder for full glass settings (color
// overlay, veil coverage, shadow, iOS 27 border) without forcing clear veil.
- (void)styleFinderButtons {
    for(WXGSurface *s in _buttons) {
        BOOL finderCapsule=[s.role isEqual:@"finderCapsule"];
        NSInteger scope=finderCapsule?WXGGlassScopeFinder:-1;
        if(s.glass.veilOverride)s.glass.veilOverride=nil;
        if(s.glass.rimAlwaysDark)s.glass.rimAlwaysDark=NO;
        if(s.glass.glassScopeOverride!=scope)s.glass.glassScopeOverride=scope;
        if(s.glass.rimScopeOverride!=scope)s.glass.rimScopeOverride=scope;
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
// FIX108 D (probe TEST4b: the native MMTabBar with ThemeBox off / on): each
// tab's badge as WeChat draws it there (MMBadgeView: its red image and the
// count label; a theme empties that image and puts its own image view in
// it, at its own size and place), pictured, with where its centre sits from
// the tab icon's: the dock shows that instead of its own red label, so a
// theme's badge comes through and WeChat's own looks like WeChat's.
- (NSArray *)tabBadgeArt {
    NSMutableArray *out=[NSMutableArray arrayWithObjects:NSNull.null,NSNull.null,NSNull.null,NSNull.null,nil];
    UITabBar *bar=_route.tabs.tabBar;if(!bar || bar.bounds.size.width<1 || !bar.window)return out;
    NSMutableArray<UIView *> *items=[NSMutableArray array];
    for(UIView *v in bar.subviews)if([NSStringFromClass(v.class) containsString:@"TabBarItemView"])[items addObject:v];
    if(items.count!=4) {   // FIX108 E: nested one level deeper on another build
        [items removeAllObjects];
        for(UIView *v in WXGViews(bar,80))if(v!=bar && [NSStringFromClass(v.class) containsString:@"TabBarItemView"] && ![NSStringFromClass(v.superview.class) containsString:@"TabBarItemView"])[items addObject:v];
    }
    if(items.count!=4)return out;
    // Left to right, as tabBadges orders the badges (FIX108 E: not reversed for
    // right-to-left: each picture goes with the label its visibility comes from).
    [items sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){
        CGFloat x=CGRectGetMidX([a convertRect:a.bounds toView:bar]),y=CGRectGetMidX([b convertRect:b.bounds toView:bar]);
        return x<y?NSOrderedAscending:NSOrderedDescending;}];
    if(!_badgeArtCache)_badgeArtCache=[NSMutableDictionary dictionary];
    CGFloat scale=bar.window.screen.scale?:UIScreen.mainScreen.scale;
    for(NSUInteger i=0;i<4;i++) {
        UIView *item=items[i],*badge=nil;
        // FIX108 E: called from the tab bar's own layout, before its items'
        // (a count going from 9 to 10 was pictured in the old frame).
        [item layoutIfNeeded];
        for(UIView *v in WXGViews(item,40)) {
            NSString *n=NSStringFromClass(v.class).lowercaseString;
            if(([n containsString:@"badge"] || [n containsString:@"reddot"]) && !v.hidden && v.alpha>.01){badge=v;break;}
        }
        if(!badge)continue;
        UIImageView *icon=nil;CGFloat best=0;
        for(UIView *v in WXGViews(item,40)) {
            if(![v isKindOfClass:UIImageView.class] || [v isDescendantOfView:badge] || v.hidden || !((UIImageView *)v).image)continue;
            CGSize size=v.bounds.size;if(size.width<14 || size.height<14 || size.width>72 || size.height>72)continue;
            if(size.width*size.height>best){best=size.width*size.height;icon=(UIImageView *)v;}
        }
        if(!icon)continue;
        // What the badge draws: itself (an image, a fill) and its shown children
        // (a theme's image view, the count), nothing of its empty frame.
        CGRect ink=CGRectNull;
        NSMutableString *key=[NSMutableString stringWithFormat:@"%p/%ld/%.0f",(__bridge void *)badge,(long)bar.traitCollection.userInterfaceStyle,scale];
        for(UIView *v in WXGViews(badge,12)) {
            BOOL shown=YES;for(UIView *p=v;p && p!=badge.superview;p=p.superview)if(p.hidden || p.alpha<.01){shown=NO;break;}
            if(!shown)continue;
            BOOL draws=NO;
            if([v isKindOfClass:UIImageView.class])draws=((UIImageView *)v).image.size.width>0;
            else if([v isKindOfClass:UILabel.class])draws=((UILabel *)v).text.length>0;
            if(!draws && v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor)>.05)draws=YES;
            if(!draws && ![v isKindOfClass:UILabel.class] && v.layer.contents)draws=YES;
            if(!draws)continue;
            CGRect r=[v convertRect:v.bounds toView:badge];
            ink=CGRectIsNull(ink)?r:CGRectUnion(ink,r);
            [key appendFormat:@"|%p:%.1f,%.1f,%.1f,%.1f:%p:%@:%.2f:%@:%@:%@:%@",(__bridge void *)v,r.origin.x,r.origin.y,r.size.width,r.size.height,
                [v isKindOfClass:UIImageView.class]?(__bridge void *)((UIImageView *)v).image:NULL,[v isKindOfClass:UILabel.class]?((UILabel *)v).text:@"",v.alpha,
                [v isKindOfClass:UILabel.class]?((UILabel *)v).textColor:@"",[v isKindOfClass:UILabel.class]?((UILabel *)v).font.fontName:@"",v.backgroundColor?:@"",v.tintColor?:@""];
        }
        if(CGRectIsNull(ink) || ink.size.width<3 || ink.size.height<3 || ink.size.width>80 || ink.size.height>60)continue;
        CGRect inItem=[badge convertRect:ink toView:item],iconRect=[icon convertRect:icon.bounds toView:item];
        // FIX108 E: pictured at the dock's size (its icon box is 26 pt), pixel
        // sharp, not scaled afterwards; the offset in the dock's points.
        CGFloat k=WXGClamp(26/MAX(iconRect.size.height,1),.6,1.4);
        CGPoint offset=CGPointMake((CGRectGetMidX(inItem)-CGRectGetMidX(iconRect))*k,(CGRectGetMidY(inItem)-CGRectGetMidY(iconRect))*k);
        CGSize size=CGSizeMake(round(ink.size.width*k*scale)/scale,round(ink.size.height*k*scale)/scale);
        [key appendFormat:@"|k%.3f",k];
        NSArray *cached=_badgeArtCache[@(i)];UIImage *image=nil;
        if([cached.firstObject isEqual:key])image=cached[1];
        else {
            UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=scale;format.opaque=NO;
            image=[[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context){
                CGContextScaleCTM(context.CGContext,size.width/ink.size.width,size.height/ink.size.height);
                CGContextTranslateCTM(context.CGContext,-ink.origin.x,-ink.origin.y);[badge.layer renderInContext:context.CGContext];
            }];
            if(image)_badgeArtCache[@(i)]=@[key.copy,image];
        }
        if(image)out[i]=@{@"image":image,@"offset":[NSValue valueWithCGPoint:offset],@"icon":@26};
    }
    return out;
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
    // FIX109 E: the tab bar's own layout calls this before any refresh has
    // looked at the switch and the licence: nothing is made, nothing masked.
    if(!WXGPluginEnabled() || !WXGPreferences.shared.dock || !_overlay.superview)return;
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
    // FIX113 E: 离散底栏 beside the search button: the round button and its gap
    // leave too little of the row for balls as tall as asked (with the default
    // width, about 0.7 of the bar at most: the size setting did nothing past
    // that). The row grows as far as they need (selected tab at its floor),
    // never wider than the search field's own row; past that they shrink.
    _discreteRowGrowth=0;
    if(search && c.dockDiscrete) {
        CGFloat need=WXGDiscreteNeededWidth((float)c.height,(float)c.dockDiscreteBall,(float)c.dockDiscreteGap,(float)c.dockDiscreteWide)+c.height+gap;
        CGFloat grown=ceil(MIN(MAX(rowWidth,need),MAX(rowWidth,usable*c.dockSearchWidthFraction)));
        if(grown>rowWidth+.5) {
            _discreteRowGrowth=grown-rowWidth;rowWidth=grown;
            rowX=bounds.origin.x+_window.safeAreaInsets.left+(usable-rowWidth)*.5;
        }
    }
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
    [_dockView updateBadgeArt:[self tabBadgeArt]];   // FIX108 D
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
// FIX114 M (user: no in-between form any more: the dock's search button and
// the search boxes go straight to WeChat's search page): the button no
// longer widens into a field of ours (the dock no longer turns into a close
// button); tapped, WeChat's own search entry is triggered as its search
// button does (on another tab, 微信 is opened first), with nothing to type
// over (an empty hand-over: done as soon as the entry is triggered).
- (void)openDockSearch {
    if(!_searchView || _searchView.hidden || _dockPresentation!=WXGDockSettled || _nativeTransition ||
       _suspendedByCover || !_route.primary || _pendingSearchText)return;
    ++_searchOpens;_pendingTabIndex=-1;
    if(_searchOpen)[self closeDockSearchAnimated:NO];   // (a field of ours left open by an older build's state)
    _pendingSearchText=@"";_pendingSearchSince=CACurrentMediaTime();++_searchHandoffs;
    _searchEntryTriggered=NO;_searchSwitchRequested=NO;_searchEntry=nil;_deliveryAttempts=0;_handoffField=nil;_handoffResponder=nil;
    [self continueSearchHandoff];
    // (review) Ended in time even if nothing refreshes meanwhile (the deadline
    // is looked at in continueSearchHandoff, called from refresh).
    __weak WXGIntegrationHost *weakSelf=self;CFTimeInterval since=_pendingSearchSince;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGIntegrationHost *host=weakSelf;
        if(host && host.pendingSearchText && host.pendingSearchSince==since)[host continueSearchHandoff];
    });
}
- (BOOL)openWeChatSearchOn:(UIViewController *)page {
    if(!page || page!=_route.leaf || ![NSStringFromClass(page.class) isEqual:@"NewMainFrameViewController"] || _pendingSearchText)return NO;
    UIControl *entry=[self homeSearchEntry];if(!entry)return NO;
    [entry sendActionsForControlEvents:UIControlEventTouchDown];
    [entry sendActionsForControlEvents:UIControlEventTouchUpInside];
    ++_directSearchOpens;_lastSearchHandoff=@"搜索框胶囊 → 微信搜索按钮：直接打开搜索页";
    [self recordForward:@{@"role":@"floatingSearch",@"entry":@"右上角搜索按钮"}];
    return YES;
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
    if(bar.window && [bar isDescendantOfView:page] && !WXGHomeTaskbarContains(bar))return bar;
    // Once per list (cached): the page scan, then a deeper walk.
    for(UIView *v in _pageViews?:@[])if([v isKindOfClass:UISearchBar.class] && v.window && !WXGHomeTaskbarContains(v)){_homeSearchBarRef=(id)v;return (id)v;}
    if(_homeSearchBarScanPage==page)return nil;
    _homeSearchBarScanPage=page;
    for(UIView *v in WXGViews(page,1500))if([v isKindOfClass:UISearchBar.class] && v.window && !WXGHomeTaskbarContains(v)){_homeSearchBarRef=(id)v;return (id)v;}
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
    // FIX114 M: only opening WeChat's search (the button, no text of ours): done.
    if(!_pendingSearchText.length){[self finishSearchHandoff:[NSString stringWithFormat:@"%@：已直接打开微信搜索",_searchEntry?:@""] success:YES];return;}
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
    // FIX113 N: the search and group rows share the header.
    if([WXGChatSegments.shared wanted]){[self restoreTopSearch];_topSearchStatus=@"搜索框和分组栏共用表头";return;}
    if(_pendingSearchText)return;
    if(!_route.primary || ![NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"])return;
    UISearchBar *bar=[self homeSearchBar];
    // WeChat's own search still using its bar (focused or holding text): wait.
    if(_nativeSearchEditing) {
        UITextField *installed=WXGInstalledSearchField(bar);
        if(installed.isFirstResponder || installed.text.length)return;
        _nativeSearchEditing=NO;
    }
    if(!bar){_topSearchStatus=@"没有找到聊天列表的搜索栏";return;}
    UITableView *table=nil;UIView *header=nil;
    for(UIView *v=bar;v.superview;v=v.superview)if([v.superview isKindOfClass:UITableView.class]){table=(id)v.superview;header=v;break;}
    if(!table || table.tableHeaderView!=header){_topSearchStatus=@"搜索栏不在列表表头里，未隐藏";return;}
    if(WXGHomeListInNativePull(table))return;
    if(_topSearchHidden && _topSearchHeader!=header){[self restoreTopSearch];if(_topSearchHidden)return;}
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
    UIView *header=_topSearchHeader;UITableView *table=_topSearchTable;
    if(header && table.tableHeaderView==header && WXGHomeListInNativePull(table) && WXGPluginEnabled())return;
    _topSearchHidden=NO;
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
             @"opens":@(_searchOpens),@"handoffs":@(_searchHandoffs),@"handoffMisses":@(_searchHandoffMisses),@"directOpens":@(_directSearchOpens),@"mode":@"直接打开微信搜索（FIX114 M）",
             @"lastHandoff":_lastSearchHandoff?:@"",@"entryControl":@(_homeSearchControl!=nil),
             @"button":_searchView?@{@"hidden":@(_searchView.hidden),@"active":@(_searchView.active),@"frame":NSStringFromCGRect(_searchView.frame),
                                     @"shape":NSStringFromCGRect(_searchView.shape),@"renderer":_searchView.glass.diagnostics?:@""}:@"none",
             @"topSearchBar":@{@"switch":@(WXGPreferences.shared.hideTopSearch),@"hidden":@(_topSearchHidden),@"status":_topSearchStatus?:@"",
                               @"hides":@(_topSearchHides),@"savedHeight":@(_topSearchHeight),@"nativeEditing":@(_nativeSearchEditing)}};
}
- (void)suppressNativeDockPaint {
    UITabBar *bar=_suppressedTabBar;if(!bar || !_dockStates)return;
    // FIX109 E: never while the plugin is off / not authorised (a cold start
    // of an account that is not, or no longer, authorised hid WeChat's tab bar
    // on every tab bar layout until the next refresh gave it back).
    if(!WXGPluginEnabled() || !WXGPreferences.shared.dock){WXGRestoreDockTouchDelegates(bar);[_dockStates restore];_dockStates=nil;_suppressedTabBar=nil;return;}
    // The replacement is outside the native bar. Mask its paint once, including
    // future native children/snapshots, without altering UIKit geometry or alpha.
    [_dockStates conceal:bar];
    [_dockStates reapply];
}
- (BOOL)dockRequestedTabAtTouchDown:(NSInteger)index {
    WXGStallSamplerArm(1.5,[NSString stringWithFormat:@"底栏按下第 %ld 个",(long)index+1]);   // FIX119 D
    if(_dockPresentation!=WXGDockSettled || _nativeTransition || _suspendedByCover || !_route.primary ||
       !WXGPluginEnabled() || !WXGPreferences.shared.dock || !_dockView.userInteractionEnabled)return NO;
    UITabBarController *tabs=_route.tabs;
    if(!tabs || index<0 || index>=(NSInteger)tabs.viewControllers.count || index==(NSInteger)tabs.selectedIndex)return NO;
    // A switch still held for an earlier tap (its lens landing) is not
    // thrown away by a press that may yet be cancelled: that press waits.
    if(_pendingTabIndex>=0)return NO;
    // Only an observed stall on this tab can activate the optional smart hold.
    // Cold and warm taps otherwise use the same configured dispatch time.
    NSNumber *stall=_tabStallMS[@(index)];
    if(stall && stall.doubleValue>=50 && [WXGConfig.shared extraNumber:@"dockTapSmartHold"]>.5){++_smartHolds;_smartHeldIndex=index;return NO;}
    CFTimeInterval now=CACurrentMediaTime();
    _profileUntil=MAX(_profileUntil,now+1.5);
    ++_touchDownSwitches;
    [self forwardTabIndex:index];
    if(_touchDownSwitches<=6)WXGLog(@"底栏：按下即切换到第 %ld 个标签（启动后 %.1f s，转发及同步刷新合计 %.0f ms）",(long)index+1,WXGSecondsSinceLoad(),(CACurrentMediaTime()-now)*1000);
    return (NSInteger)tabs.selectedIndex==index;
}
- (NSDictionary *)tabStallEvidence {   // FIX119 E
    NSMutableDictionary *d=[NSMutableDictionary dictionary];
    for(NSNumber *k in _tabStallMS)d[[NSString stringWithFormat:@"%ld",(long)k.integerValue+1]]=@(round(_tabStallMS[k].doubleValue));
    return d;
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
    BOOL smartHeld=index==_smartHeldIndex;_smartHeldIndex=-1;
    NSInteger moment=smartHeld?2:WXGConfig.shared.dockTapSwitchMoment;
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
    [self noteVisitedTab:tabs];
    BOOL firstVisit=![_visitedTabs containsIndex:(NSUInteger)index];
    [_visitedTabs addIndex:(NSUInteger)index];
    CFTimeInterval forwardStart=CACurrentMediaTime();
    [self recordForward:@{@"role":@"tab",@"index":@(index),@"nativeBindingAvailable":@(index<(NSInteger)native.count && WXGCanForward(native[index]))}];
    // FIX113 Z: one timed pass (the hooks it runs inside are part of it, not
    // counted a second time by WXGPerfTimePluginWork).
    ++WXGHostTimedDepth;
    @try {
        if(index<(NSInteger)native.count && WXGCanForward(native[index])) {
            UIControl *button=native[index];[button sendActionsForControlEvents:UIControlEventTouchDown];
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        }else {
            UIViewController *vc=tabs.viewControllers[index];id<UITabBarControllerDelegate> delegate=tabs.delegate;
            if([delegate respondsToSelector:@selector(tabBarController:shouldSelectViewController:)] && ![delegate tabBarController:tabs shouldSelectViewController:vc])return;
            tabs.selectedViewController=vc;
            if([delegate respondsToSelector:@selector(tabBarController:didSelectViewController:)])[delegate tabBarController:tabs didSelectViewController:vc];
        }
    } @finally {--WXGHostTimedDepth;}
    double switchMS=(CACurrentMediaTime()-forwardStart)*1000;WXGProfileAdd(WXGProfileSwitch,switchMS);
    _lastSwitchAt=CACurrentMediaTime();_profileUntil=MAX(_profileUntil,_lastSwitchAt+1.5);
    [self finishTabTrace];
    if(firstVisit && ++_firstVisitLogs<=4)WXGLog(@"底栏：第 %ld 个标签启动后第一次打开（启动后 %.1f s），微信切换用了 %.0f ms",(long)index+1,WXGSecondsSinceLoad(),switchMS);
    _tabTrace=[@{@"index":@(index),@"t":@(forwardStart),@"wechatSwitchMS":@(switchMS),@"firstVisit":@(firstVisit),@"timing":@(WXGConfig.shared.dockSwitchTiming),
                 @"maxIntervalMS":@0,@"slowFrames":@0,@"frames":@0} mutableCopy];
    // FIX37: build the new page's glass now, in the commit that first shows
    // the page. Scheduled, it ran one run-loop later and the page's own top
    // buttons were visible for a frame or more on every switch.
    if(!_refreshing)[self refresh];else [self schedule];
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
// Record when WeChat actually reparents the native title controls.
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
    if(++_homeTopBarMoves<=6)WXGLog(@"顶栏：微信的顶部按钮%@首页列表（下拉 %.0f pt）",inList?@"进入":@"离开",_homePull);
    WXGEdgeFadeSyncController(_route.leaf);
    if(page && page!=_route.leaf)WXGEdgeFadeSyncController(page);
}
// FIX93: the home list pulled down past its top (the largest list on the page).
- (CGFloat)currentHomePull {
    static Class home;static dispatch_once_t once;
    dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");});
    if(!_route.primary || !home || ![_route.leaf isKindOfClass:home] || !_window)return 0;
    UIScrollView *list=_homeConversationList;
    if(list && list.window==_window)return MAX(0.,-(list.contentOffset.y+WXGHomeConversationTop(list)));
    CGFloat pull=0,h=_window.bounds.size.height,w=_window.bounds.size.width;
    for(UIScrollView *scroll in _scrollViews)
        if(scroll.window==_window && scroll.bounds.size.height>h*.5 && scroll.bounds.size.width>w*.8)
            pull=MAX(pull,-(scroll.contentOffset.y+WXGHomeConversationTop(scroll)));
    return pull;
}
// FIX93: pulling the home list down (toward the mini-program panel), WeChat
// fades its own title bar; the glass followed that opacity (FIX92 kept it on
// top, but faded it showed the page's fade and blur through it). While the
// list is pulled, the title and right buttons stay at full opacity until the
// panel actually opens (then they follow WeChat out).
- (void)updateHomePullFloor {
    _homePull=[self currentHomePull];
    // FIX108 C (probe TEST5, 盯选中 on the "+": the frame the list came back to
    // rest its glass had a shown opacity of 0, every pull): the floor dropped
    // to 0 the moment the pull did, while WeChat's title bar was still at 0 on
    // its way back. The last floor is held for 0.45 s after the pull ends.
    CFTimeInterval now=CACurrentMediaTime();CGFloat floor;
    // FIX108 E: only on the home page itself, not during a push / pop (the
    // next page's glass is not lifted), never above what the panel allows.
    BOOL homePage=[NSStringFromClass(_route.leaf.class) isEqual:@"NewMainFrameViewController"];
    if(_homePull>.2){floor=WXGClamp(1-_homePanel,0,1);_homeFloorHold=floor;_homePullSeenAt=now;}
    else floor=homePage && !_nativeTransition && now-_homePullSeenAt<.65?MIN(_homeFloorHold,WXGClamp(1-_homePanel,0,1)):0;
    _homePullFloorValue=floor;
    // FIX107: the search button WeChat fades in and out keeps its own alpha (the
    // list pulled down shows the search bar: WeChat's button is at 0 then).
    for(WXGSurface *surface in _buttons)if(!WXGSurfaceInNativeView(surface))surface.alphaFloor=[surface.role isEqual:@"navigationSearch"]?0:floor;
    for(WXGSurface *surface in _departingButtons)surface.alphaFloor=0;
}
- (WXGSurface *)homeTitleRowAnchorForPage:(UIViewController *)page {
    if(!page || _navCapsuleLeaf!=page || _route.leaf!=page || !_route.primary ||
       _nativeTransition || _pendingController || _suspendedByCover || !_window)return nil;
    // The embedded left button rides the taskbar's actual close area, including
    // its compressed travel at full height. Plus supplies the same row on pages
    // where WeChat omits the left button.
    WXGSurface *left=_homeIconSurface;
    if(left.motionOwner==page && left.active && !left.hidden && left.window==_window)return left;
    WXGSurface *plus=_homePlusSurface;
    return plus.motionOwner==page && plus.active && plus.window==_window?plus:nil;
}
- (CGFloat)homePullAlphaFloor {return _homePullFloorValue;}
- (CGFloat)homeRowBottomForPage:(UIViewController *)page window:(UIWindow *)window {
    return page && _navCapsuleLeaf==page && _window==window?_homeRowBottom:NAN;
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
                           @"branch":@([self homeBranchForHost:host]),@"nativeInkMasked":@([s.original.layer.mask.name isEqual:@"wxg.conceal"]),
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
    UITabBarController *tabs=_route.tabs;if(!tabs || index>=tabs.viewControllers.count)return;
    __weak WXGIntegrationHost *weakSelf=self;
    // Building a different native page can take several display intervals.
    // A released tap continues to animate after UIControl stops tracking.
    BOOL dockMoving=_dockView.tracking || _dockView.travelling || (_dockView.active && !_dockView.lensAtRest);
    BOOL busy=_nativeTransition!=nil || dockMoving || _pendingTabIndex>=0 || CACurrentMediaTime()<_profileUntil ||
        UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    if(busy) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.6*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf prewarmTabPagesFrom:index];});
        return;
    }
    if(index==0)[_dockView prewarmTravel];
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
    // FIX119 E: the tab's stall, half the last one and half this one (less WeChat's switch call itself: the lens is
    // moved on by that long, FIX100, so only what comes after it shows)
    {NSNumber *index=_tabTrace[@"index"];double stall=MAX(0,[_tabTrace[@"stallMS"] doubleValue]-[_tabTrace[@"wechatSwitchMS"] doubleValue]);
     _tabTrace[@"lensStallMS"]=@(round(stall));
     if(index && [_tabTrace[@"frames"] integerValue]>=3) {
         if(!_tabStallMS)_tabStallMS=[NSMutableDictionary dictionary];
         NSNumber *old=_tabStallMS[index];_tabStallMS[index]=@(old?(old.doubleValue+stall)*.5:stall);
     }}
    if(!_tabTraces)_tabTraces=[NSMutableArray array];
    NSDictionary *record=_tabTrace.copy;
    [_tabTraces addObject:record];if(_tabTraces.count>6)[_tabTraces removeObjectAtIndex:0];
    if([record[@"firstVisit"] boolValue] && _firstVisitTraces.count<4) {
        if(!_firstVisitTraces)_firstVisitTraces=[NSMutableArray array];
        [_firstVisitTraces addObject:record];
    }
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
    if(_refreshing)return;
    _queued=NO;_refreshing=YES;_lastRefresh=CACurrentMediaTime();++_refreshes;++WXGHostTimedDepth;
    @try {
        UIApplicationState appState=UIApplication.sharedApplication.applicationState;
        if(_inputRepairsSuspended || appState==UIApplicationStateBackground || (appState!=UIApplicationStateActive && _hasBeenActive)){_displayLink.paused=YES;return;}
        // FIX119 E (diagnostics_22's stall samples: -[WXGConfig init] inside the refresh a tab switch runs, a whole
        // configuration read again in the switch): not while a tab switch or a dock touch is going on (the next quiet
        // refresh does it; a change made in the settings is applied at once by WXGSettingsChanged anyway).
        BOOL tabBusy=_tabTrace!=nil || _dockView.tracking || _nativeTransition || _pendingTabIndex>=0 || CACurrentMediaTime()<_profileUntil;
        if(!tabBusy && CACurrentMediaTime()-_lastParameters>1.2){_lastParameters=CACurrentMediaTime();if([WXGConfig.shared reloadSharedParameters]){_dockStyleKey=nil;_navigationDirty=YES;}}
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
        // FIX114 E (review): also a sheet over a chat presented full screen (that
        // chat still on screen under it): it stays the host's, covered.
        BOOL overStack=_route.presentedStack && r.leaf!=_route.leaf && _route.leaf.viewIfLoaded.window==w;
        if(r.presented && WXGPluginEnabled() && _route && (!_route.presentedStack || overStack)) {
            if(!_suspendedByCover){[WXGChatSegments.shared coverHomeSearchFor:_route.leaf];_dockView.userInteractionEnabled=NO;_searchView.userInteractionEnabled=NO;[_dockView cancelInteraction];}
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
        BOOL nativeBarChanged=switching || _route.unsupported!=r.unsupported;   // FIX108
        if(switching)_homePullSeenAt=0;   // FIX108 E: no held floor on another page
        WXGConfigureDisplayLink(_displayLink,w.screen);_window=w;_route=r;[self selectPage:r.leaf];
        // FIX59: only for the accounts this build is made for (WXGLicense.m).
        // FIX109 E: read before the overlays go in (the main interface noted
        // first, or the first pass reads the launch's "unknown"): an account
        // that is not authorised (or not yet / no longer) never gets them.
        if(r.tabs)WXGLicenseNoteMainInterface();
        BOOL licensed=WXGLicenseCurrentState(NO)==WXGLicenseAuthorized;
        if(licensed)[self ensureOverlay:w];else [self detachOverlays];
        // FIX108: the title-bar buttons of a page this host leaves native get
        // the local glass (their layout may have come before this route).
        if(nativeBarChanged)[WXGLocalGlass.shared navigationRouteChanged];
        [self matchPageAppearance:r];
        steps[@"selectPageMS"]=@((CACurrentMediaTime()-stepMark)*1000);stepMark=CACurrentMediaTime();
        WXGDecorations.shared.source=r.leaf.view;
        WXGPreferences *p=WXGPreferences.shared;
        BOOL available=p.enabled && licensed && !r.unsupported && !_settings.presentingViewController;
        // FIX60: the chat list's search bar comes back only when the plugin is off here.
        if(!p.enabled || !licensed){[self restoreTopSearch];[WXGBubbles.shared restore];[WXGLocalGlass.shared restore];[WXGChatSegments.shared restoreAll];}   // FIX107: the local glass too; FIX113 N: the segment bar (O: and the floating search)
        // FIX114 C: the title bars' content back where WeChat draws it (review:
        // the plugin's own switch-and-licence state, and the chat's pinned
        // module, which the row moved too).
        if(!WXGPluginEnabled() || !licensed || !p.input)[self endSideChat:@"插件或输入栏适配关闭"];   // FIX114 E
        if(!WXGPluginEnabled() || !licensed || !p.nav) {
            WXGRestoreBarContent();
            if(!p.nav && (_pinnedShift>0 || _pinnedApplied)){_pinnedShift=0;[self alignPinnedModule];}
        }
        // A page the host leaves (a web page pushed in this bar): the bar back to WeChat's.
        if(r.unsupported)WXGRowAdoptBar(r.nav.navigationBar,NO);
        // FIX73: an unsupported destination (this plugin's own settings, a
        // Flutter / web page) pauses the display link below, so the buttons of
        // the page being left froze where they were, on top of the new page's
        // own buttons, until UIKit finished the transition. They go at once;
        // the page being left shows its native buttons while it slides out.
        if(!available)[self dropDepartingButtons];
        if(!available){[self resetRoute];[_inputAdapter restore];[WXGDecorations.shared restore];
            [WXGChatSegments.shared suspendFloating];   // FIX113 O: nothing floats over a web / Flutter page (the display link stops below)
            // FIX109 E: the dock and the masked tab bar back to WeChat's at once
            // whatever resetRoute's shortcut decided.
            if(!p.enabled || !licensed){[self applyDockPresentation:WXGDockHidden];WXGRestoreDockTouchDelegates(_suppressedTabBar);[_dockStates restore];_dockStates=nil;_suppressedTabBar=nil;[_snapshotStates restore];_snapshotStates=nil;[_snapshotViews removeAllObjects];
                if(_pinnedShift>0 || _pinnedApplied){_pinnedShift=0;[self alignPinnedModule];}}   // the pinned module back where WeChat put it
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
        NSString *token=[NSString stringWithFormat:@"%p:%ld:%.0fx%.0f:%d%d%d%d%d%d%d%d%d",r.leaf,(long)r.tabs.selectedIndex,w.bounds.size.width,w.bounds.size.height,p.nav,p.dock,p.input,p.avatarTitle,p.homeSearch,
            p.dockSearch,p.dockSearchLeading,p.hideTopSearch,p.chatAvatarButton];
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
                for(NSString *name in @[@"MMMsgCommonTipsView",@"MMMsgTipsMixedListExpandView",@"MainFrameActionFloatView",@"MMMenuContentView",@"WCOperateFloatView"]) {
                    Class cls=NSClassFromString(name);if(cls)[classes addObject:cls];
                }
                hosts=classes;
            });
            _homeConversationList=nil;
            Class homeList=NSClassFromString(@"MainFrameTableView");
            for(UIView *v in _pageViews) {
                if([v isKindOfClass:UIScrollView.class]) {
                    [_scrollViews addObject:(id)v];
                    if([v isKindOfClass:homeList] && v.window==w)_homeConversationList=(UIScrollView *)v;
                }
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
        // FIX113 N: the segment bar in its place (or WeChat's bar back when off).
        if(r.primary && [NSStringFromClass(r.leaf.class) isEqual:@"NewMainFrameViewController"])[WXGChatSegments.shared updateOnPage:r.leaf];
        else if(![WXGChatSegments.shared wanted])[WXGChatSegments.shared restore];
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
            if(begin-[_tabTrace[@"t"] doubleValue]<=.7) {   // FIX119 E: the time frames ran past their refresh just after the switch
                double nominal=(link.targetTimestamp-link.timestamp)*1000;if(nominal<4 || nominal>40)nominal=1000.0/60;
                if(ms>nominal*1.5)_tabTrace[@"stallMS"]=@([_tabTrace[@"stallMS"] doubleValue]+ms-nominal);
            }
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
    if(!_suspendedByCover) {
        static Class homeCls;static dispatch_once_t homeClsOnce;
        dispatch_once(&homeClsOnce,^{homeCls=NSClassFromString(@"NewMainFrameViewController");});
        BOOL involvesHome=homeCls && ([_route.leaf isKindOfClass:homeCls] || [_transitionFrom isKindOfClass:homeCls] || [_transitionTo isKindOfClass:homeCls]);
        [WXGChatSegments.shared hostTick:link.timestamp page:_route.leaf overlay:_navigationOverlay transitioning:_nativeTransition!=nil transitionInvolvesHome:involvesHome homePanel:_homePanel rowOffset:_rowOffset];   // FIX113 O / R23
    }else [WXGChatSegments.shared hideTitleBar];
    for(WXGSurface *surface in _buttons){surface.nativeTransitionActive=_nativeTransition!=nil;[surface followNativePresentation];}
    [self followFinderCapsules];   // FIX115 O
    if(_nativeTransition || _suspendedByCover)moving=YES;
    NSMutableArray *glass=[NSMutableArray array];
    [self followHomePull:begin];   // FIX93: after followNativePresentation read the native state
    NSArray<WXGSurface *> *decorations=[WXGDecorations.shared visibleSurfaces];
    NSArray *navigation=[_buttons arrayByAddingObjectsFromArray:_departingButtons?:@[]];
    for(WXGSurface *surface in [navigation arrayByAddingObjectsFromArray:decorations])if(surface.active && !surface.plain && !surface.hidden && surface.alpha>.001){[surface layoutIfNeeded];if(surface.glass.active){[surface.glass layoutIfNeeded];[glass addObject:surface.glass];}}
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
    // FIX114 E (review): the half-screen chat's bar in this same pass when it
    // can be (its own link's next tick otherwise).
    if(_sideChat) {
        _sideChat.pending=YES;
        if(!_refreshing && !WXGNativeInputLayoutInProgress() && !WXGBackdropCaptureInProgress() && !WXGNavigationCallDepth &&
           UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[_sideChat layoutNow];
    }
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
    [WXGChatSegments.shared coverHomeSearchFor:_route.leaf];
    _suspendedByCover=YES;_dockView.userInteractionEnabled=NO;_searchView.userInteractionEnabled=NO;[_dockView cancelInteraction];
    _displayLink.paused=_inputRepairsSuspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:WXGIntegrationSettings()];
    _settings=nav;[presenter presentViewController:nav animated:YES completion:^{nav.presentationController.delegate=self;}];
}
// FIX114 C: how far the title row is moved down on `page` (NAN: not laid out for it).
- (CGFloat)titleRowOffsetForPage:(UIViewController *)page {
    return page && page==self.navCapsuleLeaf?_rowOffset:NAN;
}
- (NSString *)versionString {return @WXG_BUILD_DISPLAY_VERSION;}
// FIX116 A: the glass the plugin draws for the home page's "+" (the button whose
// action is showRightTopMenuBtn), in window points; null when there is none.
- (WXGSurface *)homePlusSurfaceInWindow:(UIWindow *)window {
    if(!window)return nil;
    for(WXGSurface *s in _buttons) {
        if(s.window!=window || s.hidden)continue;
        if(s.homePlusAnchor)return s;
    }
    return nil;
}
- (CGRect)homePlusRectInWindow:(UIWindow *)window {
    WXGSurface *s=[self homePlusSurfaceInWindow:window];
    if(!s)return CGRectNull;
    CGRect r=[s convertRect:s.materialRect toView:window];
    return (!CGRectIsNull(r) && !CGRectIsEmpty(r))?r:CGRectNull;
}
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
    return @{@"version":@WXG_BUILD_PACKAGE_VERSION,@"pageID":[NSString stringWithFormat:@"%p",_route.leaf],@"page":_route.leaf?NSStringFromClass(_route.leaf.class):@"none",@"primary":@(_route.primary),
      @"tickCPUms":@(_tickCost),@"sharedCaptureCPUms":@(_backdropCost),@"drawAndDockCaptureCPUms":@(_drawCost),@"refreshCPUms":@(_refreshCost),@"maxTickCPUms":@(_maxTickCost),
      @"navigationPaintRescans":@(_navigationPaintRescans),@"tabBarSnapshotsConcealed":@(_snapshotsConcealed),
      @"coldStartLayersCleared":@(_coldStartLayersCleared),@"tabBarSnapshotLog":_snapshotLog?:@[],@"pageTopPaintCleared":@(_pageTopPaintCleared),@"pageTopRepairs":@(WXGPageTopRepairs),@"settingsEntryReady":@(WXGSettingsEntryReady),@"navigationRaises":@(_navigationRaises),@"navigationCovers":@(_navigationCovers),@"lastNavigationCover":_lastNavigationCover?:@"none",@"homePullTrace":_homePullTrace?:@[],@"navSnapshots":_navSnapshots?:@{},@"homeIcon":[self homeIconEvidenceNow],
      @"sideChat":@{@"now":_sideChat?[_sideChat evidence]:@{},@"log":WXGSideChatLog?:@[]},@"homeTopBarInList":@(_homeTopBarInList),@"homeTopBarMoves":@(_homeTopBarMoves),@"nativeTabArtwork":_dockView.nativeIconSummary?:@"",@"landedSwitches":@(_landedSwitches),@"smartHolds":@(_smartHolds),@"tabStallMS":[self tabStallEvidence],@"homeTopBarInListAtRest":@(_homeTopBarAtRest),@"homePullHosts":_homePullHosts?:@[],@"coldStartLog":WXGColdStartLog?:@[],
      @"appearances":@(_appearances),@"stalePendingClears":@(_stalePendingClears),@"appearanceMatches":@(_appearanceMatches),
      @"dockProfile":@{@"windows":@(_profileWindows),@"frames":@(_profileFrames),@"slowFrames":@(_profileSlowFrames),@"worst":_profileWorst?:@[]},@"settingsEntryInsertions":@(WXGSettingsEntryInsertions),@"prewarmedTabPages":_prewarmed?:@[],
      @"tabSwitches":_tabTraces?:@[],@"firstVisitTabSwitches":_firstVisitTraces?:@[],@"currentTabTrace":_tabTrace?:@{},@"lastSlowRefresh":_lastSlowRefreshPhases?:@{},
      @"coldStartTopPaint":_topPaintCensus?:@[],
      @"postCommit":@{@"observer":@(_commitObserver!=NULL),@"order":@1999500,@"phase":@"beforeCoreAnimationCommit",@"frames":@(_postCommitFrames),@"inlineFallbacks":@(_postCommitFallbacks),@"dropped":@(_droppedPendingFrames),
        @"delayFromCallbackMS":@(_postCommitDelayMS),@"presentScheduleWaitMS":@(WXGGlassScheduleWaitMS()),@"costMS":@(_postCommitCost),@"maxCostMS":@(_maxPostCommitCost)},
      @"callbackIntervalms":@(_lastTickTime*1000),@"callbackCount":@(_frames),@"refreshCount":@(_refreshes),@"covered":@(_suspendedByCover),
      @"navigationRepairs":@(_navigationRepairs),@"otherBarLayoutsSkipped":@(_otherBarLayoutsSkipped),@"homeNavigationLayoutsReused":@(_homeNavigationLayoutsReused),@"homeReattachments":@(_homeReattachments),@"homeMoveLoopBreaks":@(_homeMoveLoopBreaks),@"homeHostConflicts":@(_homeHostConflicts),@"decorations":WXGDecorations.shared.evidence,@"meHeader":WXGMeHeader.shared.evidence,@"bubbles":WXGBubbles.shared.evidence,@"localGlass":WXGLocalGlass.shared.evidence,@"chatSegments":WXGChatSegments.shared.evidence,
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
    return @{@"revision":@WXG_BUILD_DIAGNOSTIC_REVISION,@"diagnosticSchema":@"FIX103",@"edgeFade":WXGEdgeFadeEvidence(),@"rims":WXGRimSummary(),@"keyboard":WXGKeyboardTraceEvidence(),@"settingsStorage":WXGSettingsStorageEvidence(),@"inputRepair":self.inputRepairMetrics,@"glassFrames":frames,@"backdrop":WXGBackdropEvidence(),@"dockOwnership":dock,
        @"covered":@(_suspendedByCover),@"displayLinkPaused":@(_displayLink.paused),@"coveredRenderFrames":@(_coveredRenderFrames),
        @"dockInteraction":_dockView.dockInteractionMetrics?:@{},@"dockGestureProtection":WXGDockTouchProtectionMetrics(_suppressedTabBar),
        @"navigationChrome":self.navigationChromeMetrics,
        @"dropShadow":WXGDropShadowEvidence(),@"homeMoveLoopBreaks":@(_homeMoveLoopBreaks),@"homeHostConflicts":@(_homeHostConflicts),   // FIX114 M
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
    return @{@"schema":@"wxg-test4-fix11",@"version":@WXG_BUILD_PACKAGE_VERSION,@"runtime":self.runtimeMetrics,
        @"backdrop":WXGBackdropEvidence(),@"nativeNavigationCandidates":[self navigationInventory],
        @"performance":@{@"screenMaximumFPS":@(_window.screen.maximumFramesPerSecond),@"requestedCaptureFPS":@(WXGConfig.shared.captureFPS),@"effectiveCaptureFPS":@(WXGScreenCaptureFPS(_window.screen)),@"hostHighRefreshOptIn":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CADisableMinimumFrameDurationOnPhone"]?:@NO,@"displayCallbacks":@(_frames),@"callbacksOver25ms":@(_slowFrames),@"refreshes":@(_refreshes),
            @"displayCallbackRate":@(_frames/MAX(.001,CACurrentMediaTime()-_frameStart)),@"pageRestores":@(_pageRestores),@"cachedPages":@(_pages.count),@"pooledNavigationSurfaces":@(_surfacePool.count),@"pooledInputSurfaces":@(_inputAdapter.surfaces.count)},@"page":_route.path?:@"",@"presentedChat":@(_route.presentedStack),@"status":_status?:@"",
        @"unix":@(NSDate.date.timeIntervalSince1970),@"uptime":@(CACurrentMediaTime()),@"contentSizeCategory":_window.traitCollection.preferredContentSizeCategory?:@"",
        @"system":UIDevice.currentDevice.systemVersion,@"wechat":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"",
        @"window":@[@(_window.bounds.size.width),@(_window.bounds.size.height)],@"scale":@(_window.screen.scale),
        @"safeArea":@[@(_window.safeAreaInsets.top),@(_window.safeAreaInsets.left),@(_window.safeAreaInsets.bottom),@(_window.safeAreaInsets.right)],
        @"buttons":buttons,@"titleAlignedButtons":@(_titleAlignedButtons),@"discreteRowGrowth":@(round(_discreteRowGrowth*10)/10),@"finderCapsules":_finderEvidence?:@{},@"finderFollow":@{@"titleFrames":@(_finderTitleFrames),@"awayFrames":@(_finderAwayFrames),@"reshifts":@(_finderReshifts),@"keptOnCancel":@(_finderKept),@"leaveLogs":@(_finderCopyLogs),@"veils":@(_finderVeils),@"reveals":@(_finderReveals),@"copiesHidden":@(_finderCopiesHidden),@"iconsConcealed":@(_finderIconsConcealed),@"iconReveals":@(_finderIconReveals),@"entryVeils":@(_finderEntryVeils),@"resumeRebuilds":@(_finderResumeRebuilds),@"driftRebuilds":@(_finderDriftRebuilds)},@"titleOffset":@(_titleOffset),@"input":_inputAdapter.evidence,@"clearedPaint":_paintEvidence.copy,
        @"navigationPaint":_navStates.evidence?:@[],@"tabBarPaint":_dockStates.evidence?:@[],
        @"materialParameters":WXGConfig.shared.parameterValues,@"license":WXGLicenseEvidence(),@"dockLayers":_dockView.hidden?@{}:_dockView.glass.layerEvidence?:@{},
        @"dock":_dockView.hidden?@"当前页不显示":_dockView.diagnostics?:@"尚未创建",
        @"avatarStatus":_avatarStatus?:@"标题胶囊模式",@"nativeLookDump":_nativeLookDump?:@[],@"pinnedModule":@{@"shift":@(_pinnedShift),@"applied":@(_pinnedApplied),@"moves":@(_pinnedMoves),@"bar":_pinnedBar?@YES:@NO},@"avatarLookups":@(_avatarLookups),@"avatarProbe":_avatarProbe?:@{},@"avatarDownload":_avatarDownloadStatus?:@"none",@"avatarDownloads":@(_avatarDownloads),@"avatarDiskHits":@(_avatarDiskHits),@"kindaProbe":_kindaProbe?:@[],@"sharedParametersDomain":@"com.runyu.WeChatLiquidGlass/optics.test4",@"defaultsAdoption":WXGDefaultsAdoption(),@"log":WXGLogText()};   // FIX114 G
}
- (NSString *)diagnostics {
    NSDictionary *payload=@{@"currentOrLastScene":_settings.presentingViewController?(_lastSceneEvidence?:@{}):self.evidence,@"history":_sceneHistory.copy?:@[],@"actionDispatches":_actionHistory.copy?:@[],@"log":WXGLogText(),
        @"homeMotion":WXGChatSegments.shared.homeMotionEvidence,@"liveSamplingAtExport":self.samplingMetrics,
        // FIX84: every setting (importable as is) and the frame-rate log's summary.
        @"settingsShare":WXGSharePayload(),@"frameRate":WXGPerfEvidence(),
        @"pageSwitches":WXGTransitionPerfEvidence(),   // FIX113 Z
        // FIX114 R: the title bars frame by frame (only while the export button is on).
        @"otherTweaks":@{@"loaded":WXGLoadedTweaks(),@"views":WXGForeignViews(_window),@"ourOverrides":WXGOverrideEvidence(),@"iconSwap":WXGIconSwapEvidence()},   // FIX114 Y (FIX115 A: our overrides, how each calls through; V: the icon swap tweak's own report)
        @"navTrace":@{@"on":@(WXGTraceRunning),@"frames":@(_traceFrames),@"dropped":@(WXGTraceDropped),@"floatExports":@(_floatExports),
                      @"exportedFrom":_settings.presentingViewController?@"设置":@"页面",@"lines":WXGTraceLines.copy?:@[]}};
    NSData *d=nil;   // FIX114 D (review): a value JSON cannot hold throws
    @try {d=[NSJSONSerialization isValidJSONObject:payload]?[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil]:nil;} @catch(__unused NSException *error) {d=nil;}
    return d?[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@"诊断暂不可用":@"诊断暂不可用（有写不成 JSON 的值）";
}
/* FIX114 Y (user, 01:25: another plugin's theme disappears with this one on):
   which other tweaks are loaded into WeChat (their file names), and the views
   on screen made by one of them (the class's own image: neither the system,
   WeChat's app nor this plugin), so an export shows whose theme it is and
   where it lives. */
static NSString *WXGOwnImagePath(void) {
    static NSString *path;static dispatch_once_t once;
    dispatch_once(&once,^{Dl_info info;if(dladdr((const void *)&WXGOwnImagePath,&info) && info.dli_fname)path=@(info.dli_fname);});
    return path;
}
static BOOL WXGForeignImage(NSString *path) {
    if(!path.length || [path hasPrefix:@"/System/"] || [path hasPrefix:@"/usr/lib/"] || [path hasPrefix:@"/Developer/"])return NO;
    if([path isEqualToString:WXGOwnImagePath()])return NO;
    if([path containsString:@".app/"] && ![path.pathExtension isEqualToString:@"dylib"])return NO;   // WeChat's own binary and frameworks
    return YES;
}
static NSArray<NSString *> *WXGLoadedTweaks(void) {
    NSMutableArray<NSString *> *out=[NSMutableArray array];
    uint32_t n=_dyld_image_count();
    for(uint32_t i=0;i<n && out.count<40;i++) {
        const char *c=_dyld_get_image_name(i);if(!c)continue;
        NSString *path=@(c);if(WXGForeignImage(path))[out addObject:path.lastPathComponent];
    }
    return out;
}
static NSArray<NSDictionary *> *WXGForeignViews(UIWindow *w) {
    NSMutableArray *out=[NSMutableArray array];if(!w)return out;
    NSMutableDictionary<NSString *,NSNumber *> *seen=[NSMutableDictionary dictionary];
    for(UIView *v in WXGViews(w,1200)) {
        if(out.count>=30)break;
        const char *image=class_getImageName(object_getClass(v));if(!image)continue;
        NSString *path=@(image);if(!WXGForeignImage(path))continue;
        NSString *name=NSStringFromClass(v.class)?:@"?";
        if(seen[name].integerValue>=3)continue;seen[name]=@(seen[name].integerValue+1);
        CGRect r=WXGWindowRect(v,w);
        [out addObject:@{@"class":name,@"image":path.lastPathComponent,@"rect":@[@(round(r.origin.x)),@(round(r.origin.y)),@(round(r.size.width)),@(round(r.size.height))],
                         @"hidden":@(v.hidden),@"alpha":@(v.alpha),@"superview":NSStringFromClass(v.superview.class)?:@""}];
    }
    return out;
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
    WXGStallSamplerPause(YES);   // FIX119 E (diagnostics_22: the export itself was the longest stall)
    [self.diagnostics writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    WXGStallSamplerPause(NO);
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
    IMP own=WXGCapturedImplementation(c,selector);Class superclass=class_getSuperclass(c);   // FIX115 B: what was there when installed (as before A)
    NSString *label=[NSString stringWithFormat:@"%@.%@",NSStringFromClass(c),NSStringFromSelector(selector)];   // FIX113 Z
    IMP replacement=imp_implementationWithBlock(^(id object){
        ((void (*)(id,SEL))WXGThrough(own,superclass,selector))(object,selector);
        if(WXGBackdropCaptureInProgress()) {++WXGIntegrationHost.shared.samplingLayoutSkips;return;}
        // FIX102: timed for the dock profile (hooksMS), without the refreshes,
        // ticks and nested hooks it runs (those are counted on their own).
        CFTimeInterval begin=CACurrentMediaTime();double inner=WXGProfileOursTotal();
        [WXGIntegrationHost.shared start];after(object);
        double spent=(CACurrentMediaTime()-begin)*1000-(WXGProfileOursTotal()-inner);
        if(spent>0) {
            WXGProfileAdd(WXGProfileHooks,spent);   // FIX113 Z: through WXGProfileAdd (the page-switch log too)
            // FIX114 A: inside a timed pass (a tab switch's forward, a refresh) too, marked.
            if(WXGTransitionPerfOn)WXGTransitionPerfLabel(WXGHostTimingPlugin()?[label stringByAppendingString:@" ⊂"]:label,spent);
        }
    });
    WXGInstallOverride(c,selector,replacement,method_getTypeEncoding(m));
}
// Some WeChat releases subclass the payment or mini-program root. Native
// overrides can call each other via super; deliver layout once, after the
// outermost registered class has finished placing the message content.
static BOOL WXGBubbleHookOwnsCell(Class owner,UIView *cell,NSSet<Class> *roots) {
    static char key;
    Class actual=object_getClass(cell);
    id cached=objc_getAssociatedObject(actual,&key);
    if(!cached) {
        Class closest=actual;
        while(closest && ![roots containsObject:closest])closest=class_getSuperclass(closest);
        if(closest && WXGBubbleKindForHost(cell)==WXGBubbleUnsupported)closest=Nil;
        cached=(id)closest?:NSNull.null;
        objc_setAssociatedObject(actual,&key,cached,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cached==owner;
}

static void WXGHookBubbleContent(NSString *className, NSArray<NSString *> *selectors, void (^after)(UIView *)) {
    Class cls=NSClassFromString(className);
    if(![cls isSubclassOfClass:UIView.class])return;
    for(NSString *name in selectors) {
        SEL selector=NSSelectorFromString(name);
        Method method=class_getInstanceMethod(cls,selector);
        if(!method)continue;
        IMP prior=WXGCapturedImplementation(cls,selector);
        Class superclass=class_getSuperclass(cls);
        IMP replacement=imp_implementationWithBlock(^(UIView *view) {
            ((void(*)(id,SEL))WXGThrough(prior,superclass,selector))(view,selector);
            if(NSThread.isMainThread && !WXGBackdropCaptureInProgress())after(view);
        });
        WXGInstallOverride(cls,selector,replacement,method_getTypeEncoding(method));
    }
}

static void WXGInstallBubbleHooks(void) {
    NSMutableSet<Class> *available=[NSMutableSet set];
    NSArray<NSString *> *names=[WXGBubbleCardClassNames() arrayByAddingObjectsFromArray:
        @[@"TextMessageCellView",@"BaseMessageCellView",@"CommonMessageCellView"]];
    for(NSString *name in names) {
        Class cls=NSClassFromString(name);
        if(cls && [cls isSubclassOfClass:UIView.class])[available addObject:cls];
    }
    NSSet<Class> *roots=available.copy;
    for(Class cls in roots) {
        for(NSString *name in @[@"layoutSubviews",@"didMoveToWindow",@"prepareForReuse"]) {
            SEL selector=NSSelectorFromString(name);
            Method method=class_getInstanceMethod(cls,selector);
            if(!method)continue;
            BOOL reuse=[name isEqualToString:@"prepareForReuse"];
            IMP prior=method_getImplementation(method);
            IMP replacement=imp_implementationWithBlock(^(UIView *cell) {
                BOOL owns=NSThread.isMainThread && WXGBubbleHookOwnsCell(cls,cell,roots);
                if(owns && reuse)[WXGBubbles.shared messageCellWillReuse:cell];
                ((void(*)(id,SEL))prior)(cell,selector);
                if(owns && !reuse && !WXGBackdropCaptureInProgress())
                    WXGPerfTimePluginWorkAs("bubbles",^{[WXGBubbles.shared messageCellLaidOut:cell];});
            });
            WXGInstallOverride(cls,selector,replacement,method_getTypeEncoding(method));
        }
    }
    // A native quote can arrive or change size after its message cell has
    // finished layout, including under the table cell as a sibling.
    WXGHookBubbleContent(@"MMInputMsgReferView",@[@"layoutSubviews",@"didMoveToWindow"],^(UIView *preview){
        if(preview.window)[WXGBubbles.shared nativeQuoteLaidOut:preview];
    });
    // WeChat attaches and sizes the transcript's renderer independently of
    // VoiceMessageCellView. Its old owner also needs a refresh on detachment.
    WXGHookBubbleContent(@"CTRichTextView",@[@"didMoveToSuperview",@"didMoveToWindow",@"layoutSubviews"],^(UIView *textView){
        [WXGBubbles.shared nativeBubbleChildDidChange:textView];
    });
    // MixBubble also resynchronizes on attachment of the actual async skin.
    WXGHookBubbleContent(@"YYAsyncImageView",@[@"didMoveToSuperview"],^(UIView *image){
        [WXGBubbles.shared nativeBubbleChildDidChange:image];
    });
}

// FIX109 B: the chat bar also takes a touch in a container it moved below its bounds.
static void WXGHookChatBarTouches(Class c) {
    if(!c)return;SEL selector=@selector(pointInside:withEvent:);Method m=class_getInstanceMethod(c,selector);if(!m)return;
    IMP own=WXGCapturedImplementation(c,selector);Class superclass=class_getSuperclass(c);   // FIX115 B: what was there when installed (as before A)
    IMP replacement=imp_implementationWithBlock(^BOOL(UIView *view,CGPoint point,UIEvent *event){
        if(((BOOL (*)(id,SEL,CGPoint,UIEvent *))WXGThrough(own,superclass,selector))(view,selector,point,event))return YES;
        return [WXGIntegrationHost.shared chatBar:view extendsTo:point];
    });
    WXGInstallOverride(c,selector,replacement,method_getTypeEncoding(m));
}
static void WXGHookInputLayout(Class c) {
    if(!c)return;SEL selector=@selector(layoutSubviews);Method method=class_getInstanceMethod(c,selector);if(!method)return;
    IMP own=WXGCapturedImplementation(c,selector);Class superclass=class_getSuperclass(c);   // FIX115 B: what was there when installed (as before A)
    IMP replacement=imp_implementationWithBlock(^(id object){
        WXGBeginNativeInputLayout();
        @try {((void(*)(id,SEL))WXGThrough(own,superclass,selector))(object,selector);}
        @finally {WXGEndNativeInputLayout();}
        // The outer tool/panel pass has finished all its children. Applying at
        // a nested MMGrowTextView callback fights the remaining parent layout.
        if(!WXGNativeInputLayoutInProgress())[WXGIntegrationHost.shared layoutInput];
    });
    WXGInstallOverride(c,selector,replacement,method_getTypeEncoding(method));
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
            if(!WXGNavigationCallDepth)WXGTransitionPerfNavigationCall(@"pop",YES);   // FIX113 Z
            ++WXGNavigationCallDepth;
            @try {return ((id(*)(id,SEL,BOOL))original)(nav,selector,animated);}
            @finally {--WXGNavigationCallDepth;if(!WXGNavigationCallDepth){WXGTransitionPerfNavigationCall(@"pop",NO);[WXGIntegrationHost.shared schedule];}}
        });
        WXGInstallOverride(UINavigationController.class,selector,replacement,method_getTypeEncoding(method));
    }
    SEL selector=@selector(popToViewController:animated:);Method method=class_getInstanceMethod(UINavigationController.class,selector);
    IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^id(UINavigationController *nav,UIViewController *destination,BOOL animated){
        WXGRecordNativePop(nav,selector,animated);
        if(!WXGNavigationCallDepth)WXGTransitionPerfNavigationCall(@"pop",YES);   // FIX113 Z
        ++WXGNavigationCallDepth;
        @try {return ((id(*)(id,SEL,id,BOOL))original)(nav,selector,destination,animated);}
        @finally {--WXGNavigationCallDepth;if(!WXGNavigationCallDepth){WXGTransitionPerfNavigationCall(@"pop",NO);[WXGIntegrationHost.shared schedule];}}
    });
    WXGInstallOverride(UINavigationController.class,selector,replacement,method_getTypeEncoding(method));
    selector=@selector(pushViewController:animated:);method=class_getInstanceMethod(UINavigationController.class,selector);
    IMP pushOriginal=method_getImplementation(method);SEL pushSelector=selector;
    replacement=imp_implementationWithBlock(^(UINavigationController *nav,UIViewController *destination,BOOL animated){
        [WXGChatSegments.shared willPushFrom:nav.topViewController to:destination];
        [WXGChatSegments.shared coverHomeSearchFor:nav.topViewController];
        WXGRecordNativePop(nav,pushSelector,animated);
        if(!WXGNavigationCallDepth)WXGTransitionPerfNavigationCall(@"push",YES);   // FIX113 Z
        ++WXGNavigationCallDepth;
        @try {((void(*)(id,SEL,id,BOOL))pushOriginal)(nav,pushSelector,destination,animated);}
        @finally {--WXGNavigationCallDepth;if(!WXGNavigationCallDepth){WXGTransitionPerfNavigationCall(@"push",NO);[WXGIntegrationHost.shared schedule];}}
    });
    WXGInstallOverride(UINavigationController.class,selector,replacement,method_getTypeEncoding(method));
}
static void WXGInstallDockHitTesting(void) {
    Class cls=NSClassFromString(@"MMTabBar");if(!cls)return;
    SEL selector=@selector(hitTest:withEvent:);Method method=class_getInstanceMethod(cls,selector);if(!method)return;
    IMP own=WXGCapturedImplementation(cls,selector);Class superclass=class_getSuperclass(cls);   // FIX115 B: what was there when installed (as before A)
    IMP replacement=imp_implementationWithBlock(^UIView *(UIView *bar,CGPoint point,UIEvent *event){
        IMP original=WXGThrough(own,superclass,selector);
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
    WXGInstallOverride(cls,selector,replacement,method_getTypeEncoding(method));
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
/* FIX111: FIX110 (the iOS 26 system-glass attempts, all taken out again) may
   have left values in WeChat's own preferences. Exactly what it changed, by
   its own records in the plugin's suite, is put back once; its records go.
   Nothing else is read or written (keys of other tweaks stay as they are). */
static void WXGRemoveFix110Leftovers(void) {
    @try {
        NSUserDefaults *suite=[[NSUserDefaults alloc]initWithSuiteName:@"com.runyu.WeChatLiquidGlass"],*app=NSUserDefaults.standardUserDefaults;
        NSArray<NSString *> *records=@[@"design.addedIgnore",@"design.removedCompat",@"design.overrideInfo",@"nativeGlass.wroteDefaults",
            @"nativeGlass.design",@"nativeGlass.strategy",@"nativeGlass.testing",@"nativeGlass.banned",@"nativeGlass.armed",@"nativeGlass.os"];
        BOOL any=NO;for(NSString *key in records)if([suite objectForKey:key]){any=YES;break;}
        if(!any)return;
        if([suite boolForKey:@"nativeGlass.wroteDefaults"])   // FIX110 B's three keys
            for(NSString *key in @[@"UIDesignRequiresCompatibility",@"com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck",@"com.apple.SwiftUI.EnableLiquidGlass"])[app removeObjectForKey:key];
        if([suite boolForKey:@"design.addedIgnore"])[app removeObjectForKey:@"com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"];   // F added it
        if([suite boolForKey:@"design.removedCompat"])[app setBool:YES forKey:@"UIDesignRequiresCompatibility"];                // F removed it
        for(NSString *key in records)[suite removeObjectForKey:key];
        WXGColdLog(@"FIX111：FIX110 留在微信偏好里的设计设置已按原样还原");
    } @catch(__unused NSException *error) {}
}
__attribute__((constructor)) static void WXGInitialize(void) {
    WXGLoadTime=CACurrentMediaTime();WXGColdLog(@"插件加载");
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.tencent.xin"])return;
    WXGRemoveFix110Leftovers();
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
                if(will)WXGTransitionPerfAppearance(controller,YES);   // FIX113 Z: a page switch starts being recorded
                if(WXGBackdropCaptureInProgress()){++WXGIntegrationHost.shared.samplingLayoutSkips;return;}
                // FIX113 Z: timed (the page-switch log's "appear"; also the hooks' total).
                WXGPerfTimePluginWorkAs(will?"appear":"didAppear",^{
                    WXGEdgeFadeNoteController(controller,YES);   // FIX64 (FIX65: our own settings pages too)
                    if(will)[WXGChatSegments.shared willShowHome:controller];
                    else {[WXGChatSegments.shared didShowHome:controller];WXGNotePageAppeared(controller);}   // FIX106 I: 聊天信息 / 设置 rest at their top
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
            });
            WXGInstallOverride(UIViewController.class,selector,replacement,method_getTypeEncoding(method));
        }
        // A page sheet can capture the presenter without a disappearance callback.
        // Release the home capsule before UIKit takes that snapshot.
        {
            SEL selector=@selector(presentViewController:animated:completion:);
            Method method=class_getInstanceMethod(UIViewController.class,selector);
            IMP original=method_getImplementation(method);
            IMP replacement=imp_implementationWithBlock(^(UIViewController *controller,UIViewController *target,BOOL animated,void (^completion)(void)){
                [WXGChatSegments.shared coverHomeSearchFor:controller];
                ((void(*)(id,SEL,id,BOOL,id))original)(controller,selector,target,animated,completion);
            });
            WXGInstallOverride(UIViewController.class,selector,replacement,method_getTypeEncoding(method));
        }
        {
            SEL selector=@selector(viewWillDisappear:);Method method=class_getInstanceMethod(UIViewController.class,selector);
            IMP original=method?method_getImplementation(method):NULL;
            if(original) {
                IMP replacement=imp_implementationWithBlock(^(UIViewController *controller,BOOL animated){
                    [WXGChatSegments.shared moveTitleWithHomePage:controller];
                    [WXGChatSegments.shared coverHomeSearchFor:controller];
                    ((void (*)(id,SEL,BOOL))original)(controller,selector,animated);
                    WXGTransitionPerfAppearance(controller,NO);
                });
                WXGInstallOverride(UIViewController.class,selector,replacement,method_getTypeEncoding(method));
            }
        }
        WXGHookVoid(UIViewController.class,@selector(viewDidLayoutSubviews),^(UIViewController *controller){
            [WXGIntegrationHost.shared controllerLaidOut:controller];
            // FIX114 A: each part under its own name in the page-switch log.
            WXGPerfTimePluginWorkAs("localGlass.controller",^{[WXGLocalGlass.shared controllerLaidOut:controller];});   // FIX107: the emoji search sheet's field (fallback)
            WXGPerfTimePluginWorkAs("edgeFade.layout",^{WXGEdgeFadeNoteController(controller,NO);});   // FIX64/65: only the chat page and the other pages (WXGEdgeFade.m)
        });
        WXGHookVoid(NSClassFromString(@"MMUINavigationBar"),@selector(layoutSubviews),^(id object){[WXGIntegrationHost.shared navigationBarDidLayout:object];});
        WXGHookBarHits(UINavigationBar.class);WXGHookBarHits(NSClassFromString(@"MMUINavigationBar"));   // FIX114 C (review)
        for(NSString *name in @[@"_UIBarBackground",@"FakeNavigationBar"])
            for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
                WXGHookVoid(NSClassFromString(name),NSSelectorFromString(selectorName),^(UIView *view){
                    [WXGIntegrationHost.shared navigationChromeLaidOut:view];
                });
        WXGHookVoid(NSClassFromString(@"MMTabBar"),@selector(layoutSubviews),^(__unused id object){
            WXGIntegrationHost *host=WXGIntegrationHost.shared;[host suppressNativeDockPaint];if(!host.refreshing && host.route.primary && !WXGNavigationCallDepth){host.refreshing=YES;@try {[host buildDock];}@finally {host.refreshing=NO;}}else [host schedule];
        });
        WXGHookVoid(NSClassFromString(@"MMNewMsgContentNavBar"),@selector(layoutSubviews),^(id object){
            WXGIntegrationHost *host=WXGIntegrationHost.shared;
            if(object==host.pinnedBar && (host.pinnedShift>0 || host.pinnedApplied))[host alignPinnedModule];   // FIX109 B: after WeChat placed them
            if(host.refreshing)return;
            [host.navStates reapply];[host schedule];
        });
        // FIX109 B: touches in the pinned module moved below the bar's bounds;
        // and before every commit the module put back where it belongs (WeChat
        // can place its containers outside the bar's layout).
        WXGHookChatBarTouches(NSClassFromString(@"MMNewMsgContentNavBar"));
        CFRunLoopObserverRef pinnedObserver=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999700,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity activity){
                WXGIntegrationHost *host=WXGIntegrationHost.shared;
                if(host.pinnedShift>0 || host.pinnedApplied)[host alignPinnedModule];
            });
        if(pinnedObserver){CFRunLoopAddObserver(CFRunLoopGetMain(),pinnedObserver,kCFRunLoopCommonModes);CFRelease(pinnedObserver);}
        for(NSString *name in @[@"MMInputToolView",@"InputToolViewBar",@"MMGrowTextView",@"MMGrowDictationIconView"])   // FIX113: the dictation icon too
            WXGHookInputLayout(NSClassFromString(name));
        WXGHookVoid(NSClassFromString(@"MainFrameLeftBarView"),@selector(layoutSubviews),^(UIView *view){[WXGIntegrationHost.shared homeGestureLaidOut:view];});
        for(NSString *selectorName in @[@"didMoveToSuperview",@"didMoveToWindow"])
            WXGHookVoid(NSClassFromString(@"MainFrameLeftBarView"),NSSelectorFromString(selectorName),^(UIView *view){[WXGIntegrationHost.shared homeGestureLaidOut:view];});
        for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToSuperview",@"didMoveToWindow"])
            WXGHookVoid(NSClassFromString(@"MMBarButton"),NSSelectorFromString(selectorName),^(UIView *view){WXGPerfTimePluginWorkAs("navButtons",^{[WXGIntegrationHost.shared navigationControlLaidOut:view];});});
        for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
            WXGHookVoid(NSClassFromString(@"NewMainFrameRightTopMenuBtn"),NSSelectorFromString(selectorName),^(UIView *row){[WXGIntegrationHost.shared homeRightRowDidLayout:row];});
        for(NSString *name in @[@"MMMsgCommonTipsView",@"MMMsgTipsMixedListExpandView",@"MainFrameActionFloatView",@"MMMenuContentView",@"WCOperateFloatView"])
            for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
                WXGHookVoid(NSClassFromString(name),NSSelectorFromString(selectorName),^(UIView *view){WXGPerfTimePluginWorkAs("decorations.host",^{[WXGDecorations.shared nativeHostLaidOut:view];});});
        // FIX107: more of WeChat in glass (WXGLocalGlass.m).
        for(NSString *name in WXGLocalGlass.hostClassNames)
            for(NSString *selectorName in @[@"layoutSubviews",@"didMoveToWindow"])
                WXGHookVoid(NSClassFromString(name),NSSelectorFromString(selectorName),^(UIView *view){
                    WXGPerfTimePluginWorkAs("localGlass+segments",^{[WXGLocalGlass.shared hostLaidOut:view];[WXGChatSegments.shared searchBarLaidOut:view];});   // FIX113 N: the segment bar follows its search bar
                });
        WXGInstallBubbleHooks();
        WXGObserveNavigationPop();
        WXGInstallSettingsEntry(^(Class c,SEL selector,void (^after)(id)){WXGHookVoid(c,selector,after);});
        dispatch_async(dispatch_get_main_queue(),^{[WXGIntegrationHost.shared start];WXGPerfApplyPreferences();WXGKeyboardTraceStart();});   // FIX84: the frame-rate log (FIX85: the keyboard trace; FIX88: the calm background again; FIX103: the unlock ticket first, so the shader compiles while WeChat starts; FIX104: that moved to the top of install)
    };
    // Register before the first native view pass, without constructing UIKit
    // surfaces inside the dyld initializer. Start runs on a native callback or
    // the next main-queue turn, whichever occurs first.
    if(NSThread.isMainThread)install();else dispatch_async(dispatch_get_main_queue(),install);
}
