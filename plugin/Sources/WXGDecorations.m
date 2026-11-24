#import "WXGIntegration.h"
#import "WXGMenuCascade.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

/* FIX116 A (user, 10-29: the home "+" menu as in his reference video): each of
   WeChat's rows (RightTopMenuItemBtn) gets a glass capsule with its title on
   the left and a round glass icon on the right, the icons in line with the
   "+"; WeChat's own icon and title are hidden (not moved) and its row stays
   where it is, the only thing that takes touches, so every tap, action and
   the menu's own opening and closing are WeChat's. The glass of a row follows
   the touch on it through a recognizer that never recognizes (as the input
   field's glass does). The entrance is WXGMenuCascade.h's. */
@interface WXGMenuRowObserver : UIGestureRecognizer
@property(nonatomic,weak) WXGSurface *icon,*capsule;
@end
@implementation WXGMenuRowObserver {
    __weak UITouch *_followed;
}
- (instancetype)init {
    if((self=[super initWithTarget:nil action:NULL])){self.cancelsTouchesInView=NO;self.delaysTouchesBegan=NO;self.delaysTouchesEnded=NO;}
    return self;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {(void)other;return NO;}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {(void)other;return NO;}
- (void)press:(BOOL)on {[_icon setExternalPressed:on];[_capsule setExternalPressed:on];}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if(_followed){for(UITouch *touch in touches)[self ignoreTouch:touch forEvent:event];return;}
    _followed=touches.anyObject;[self press:YES];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if(!_followed || ![touches containsObject:_followed])return;
    // Like a control: pressed while the finger is on the row (and a little around it).
    [self press:CGRectContainsPoint(CGRectInset(self.view.bounds,-40,-40),[_followed locationInView:self.view])];
}
- (void)finish:(NSSet<UITouch *> *)touches {
    if(!_followed || ![touches containsObject:_followed])return;
    _followed=nil;[self press:NO];self.state=UIGestureRecognizerStateFailed;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {(void)event;[self finish:touches];}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {(void)event;[self finish:touches];}
- (void)reset {
    [super reset];
    if(_followed){_followed=nil;[self press:NO];}
}
@end

// One of WeChat's rows and the glass drawn for it.
@interface WXGMenuRow : NSObject
@property(nonatomic,weak) UIView *item;
@property(nonatomic,weak) UIImageView *nativeIcon;
@property(nonatomic,weak) UILabel *nativeLabel;
@property(nonatomic,strong) WXGSurface *icon,*capsule;
@property(nonatomic,strong) WXGMenuRowObserver *observer;
@property(nonatomic) CGRect itemFrame,iconRect,capsuleRect;   // the row and the glass' rectangles as last laid out, in the menu parent's coordinates
@property(nonatomic) double slotDistance;                     // how far below the "+" the row is
@property(nonatomic) BOOL drawn;                              // a row whose icon or title was found and is drawn in glass
@end
@implementation WXGMenuRow
@end

// FIX116 B: the home menu's glass is closed, open (laid out, entrance played, following the rows) or leaving (its exit running, deaf to WeChat's own close).
typedef NS_ENUM(NSInteger,WXGMenuPhase) {WXGMenuPhaseClosed,WXGMenuPhaseOpen,WXGMenuPhaseExiting};

// Track 3: 5 organic ink-drop particles bound 1:1 to the "+" ring's 5 bottom dots,
// rendered on the absolute topmost Z-order via CADisplayLink without triggering layout.
@interface WXGMenuInkOverlayView : UIView
- (void)playOpen:(BOOL)open speed:(double)speed plusRect:(CGRect)plusRect lastRowMidY:(CGFloat)lastRowMidY completion:(void (^)(void))completion;
- (void)stop;
- (void)inkTick:(CADisplayLink *)link;
@end

// Weak proxy so CADisplayLink never retains WXGMenuInkOverlayView.
@interface WXGInkLinkProxy : NSObject
@property(nonatomic,weak) WXGMenuInkOverlayView *target;
@end
@implementation WXGInkLinkProxy
- (void)tick:(CADisplayLink *)link {
    WXGMenuInkOverlayView *t=_target;
    if(!t){[link invalidate];return;}
    [t inkTick:link];
}
@end
@implementation WXGMenuInkOverlayView {
    CALayer *_dots[WXGMenuParticleCount];
    CADisplayLink *_link;
    BOOL _opening;
    CFTimeInterval _startTime;
    double _duration,_speed,_plusMidX,_plusMidY,_ringRadius,_lastRowMidY;
    void (^_onFinish)(void);
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.hidden=YES;
        self.layer.zPosition=20000;
        for(int i=0;i<WXGMenuParticleCount;i++) {
            CALayer *dot=[CALayer layer];dot.hidden=YES;
            _dots[i]=dot;[self.layer addSublayer:dot];
        }
        [self updateInkColor];
    }
    return self;
}
- (void)updateInkColor {
    UIColor *ink=[UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection];
    CGColorRef cg=ink.CGColor;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int i=0;i<WXGMenuParticleCount;i++)_dots[i].backgroundColor=cg;
    [CATransaction commit];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(!previous || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])[self updateInkColor];
}
- (void)stop {
    [_link invalidate];_link=nil;_onFinish=nil;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int i=0;i<WXGMenuParticleCount;i++)_dots[i].hidden=YES;
    self.hidden=YES;
    [CATransaction commit];
}
- (void)dealloc {
    [_link invalidate];_link=nil;
}
- (void)renderAt:(double)t {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int i=0;i<WXGMenuParticleCount;i++) {
        WXGMenuParticle p=WXGMenuParticlePoseAt(i,_opening?1:0,t,_speed,_plusMidX,_plusMidY,_ringRadius,_lastRowMidY);
        CALayer *dot=_dots[i];
        if(p.diameter<=.15 || p.alpha<=.005){dot.hidden=YES;continue;}
        dot.hidden=NO;
        dot.bounds=CGRectMake(0,0,(CGFloat)p.diameter,(CGFloat)p.diameter);
        dot.cornerRadius=(CGFloat)(p.diameter*.5);
        dot.position=CGPointMake((CGFloat)p.x,(CGFloat)p.y);
        dot.opacity=(float)p.alpha;
    }
    [CATransaction commit];
}
- (void)playOpen:(BOOL)open speed:(double)speed plusRect:(CGRect)plusRect lastRowMidY:(CGFloat)lastRowMidY completion:(void (^)(void))completion {
    [self stop];
    _opening=open;
    _speed=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    _duration=(open?.550:.350)/_speed;
    _plusMidX=CGRectGetMidX(plusRect);
    _plusMidY=CGRectGetMidY(plusRect);
    _ringRadius=WXGMenuRingRadius(MIN(plusRect.size.width,plusRect.size.height));
    _lastRowMidY=lastRowMidY;
    _onFinish=[completion copy];
    [self updateInkColor];
    self.hidden=NO;
    _startTime=CACurrentMediaTime();
    [self renderAt:0.];
    WXGInkLinkProxy *proxy=[WXGInkLinkProxy new];proxy.target=self;
    _link=[CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    WXGConfigureDisplayLink(_link,self.window.screen);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)inkTick:(CADisplayLink *)link {
    (void)link;
    if(!self.window){[self stop];return;}
    double elapsed=MAX(0.,CACurrentMediaTime()-_startTime);
    [self renderAt:elapsed];
    if(elapsed>=_duration) {
        void (^done)(void)=_onFinish;
        [self stop];
        if(done)done();
    }
}
@end

static char WXGDecorationKey;
@interface WXGDecoration : NSObject
@property(nonatomic,weak) UIView *host,*body;
@property(nonatomic,strong) WXGSurface *surface;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic,copy) NSString *kind;
@property(nonatomic) BOOL applying;
@property(nonatomic) BOOL validBody;
@property(nonatomic) CFTimeInterval lastPaint;
@property(nonatomic) NSUInteger bodyChildren,hostChildren;
@property(nonatomic) NSUInteger earlyRetries;
@property(nonatomic) UIUserInterfaceStyle appearance;
// FIX116 A: the home menu's capsule + icon rows.
@property(nonatomic) BOOL capsuleMode,rowsReady,entranceDone;
@property(nonatomic) WXGMenuPhase phase;
@property(nonatomic) BOOL blockReopen;                      // the exit began while WeChat still showed the menu: not opened again until it is hidden (or its rows are back where they were)
@property(nonatomic) NSUInteger exitToken;                  // the exit that may finish the phase (a reopening makes it stale)
@property(nonatomic,strong) NSMutableArray<WXGMenuRow *> *rows;
@property(nonatomic,strong) WXGMenuInkOverlayView *inkOverlay;
@property(nonatomic,weak) WXGSurface *plusSurface;
@property(nonatomic,weak) UIView *menuParent;               // where the glass lives: the host's superview (WeChat moves, fades and hides the host itself when it closes it)
@property(nonatomic,weak) UIControl *plusControl;
@property(nonatomic) CGRect lastPlus;                       // the "+" as last found, in the menu parent's coordinates
@property(nonatomic) CFTimeInterval plusSearchedAt,openAt,exitAt,partsSince,lastPlaced,lastNudge;
@property(nonatomic) NSUInteger entrances,exits,tickRetries;
@property(nonatomic) BOOL watching;                         // a layout the observer asked for (not one WeChat did)
@end
@implementation WXGDecoration
// FIX116 B: the glass lives beside the host (in its superview), not in it: when WeChat lets a menu go, the glass of it goes too.
- (void)dealloc {
    NSArray<WXGMenuRow *> *rows=_rows;
    WXGMenuInkOverlayView *ink=_inkOverlay;
    WXGSurface *plus=_plusSurface;
    if(!rows.count && !ink && !plus)return;
    void (^remove)(void)=^{
        for(WXGMenuRow *row in rows)for(WXGSurface *s in @[row.icon,row.capsule]){s.active=NO;s.hidden=YES;[s removeFromSuperview];}
        [ink stop];[ink removeFromSuperview];
        [plus setHomePlusMenuOpen:NO animated:NO speed:1.];[plus setHomePlusDotsHidden:NO];
    };
    if(NSThread.isMainThread)remove();else dispatch_async(dispatch_get_main_queue(),remove);
}
@end

@interface WXGDecorations ()
@property(nonatomic,strong) NSHashTable<WXGDecoration *> *entries;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSArray *> *dumps;   // FIX114 Z: each kind's last menu, as it is made
@property(nonatomic) NSUInteger mounts,reuses;
- (void)reassertVisiblePaint;
- (void)placeCapsuleMenu:(WXGDecoration *)entry items:(NSArray<UIView *> *)items;
- (void)watchCapsuleMenu:(WXGDecoration *)entry;
- (void)hideRows:(WXGDecoration *)entry remove:(BOOL)remove;
- (void)beginExit:(WXGDecoration *)entry;
- (void)playEntrance:(WXGDecoration *)entry;
- (double)playExit:(WXGDecoration *)entry token:(NSUInteger)token;
@end

static BOOL WXGHomeMenuCapsulesOn(void) {return [WXGConfig.shared extraNumber:@"homeMenuCapsules"]>.5;}
// WeChat's own icon and title inside one of its rows: the largest picture
// (8..64 pt: not a red dot) and the widest label that has text (not a badge).
static void WXGMenuParts(UIView *item,UIImageView **icon,UILabel **label) {
    UIImageView *bestIcon=nil;UILabel *bestLabel=nil;
    for(UIView *v in WXGViews(item,40)) {
        if(v==item || v.hidden || WXGIsPluginView(v))continue;
        if([v isKindOfClass:UILabel.class]) {
            UILabel *l=(id)v;if(l.text.length && (!bestLabel || l.bounds.size.width>bestLabel.bounds.size.width))bestLabel=l;
        }else if([v isKindOfClass:UIImageView.class]) {
            UIImageView *iv=(id)v;CGSize s=iv.bounds.size;
            if(iv.image && s.width>=8 && s.width<=64 && s.height>=8 && s.height<=64 &&
               (!bestIcon || s.width*s.height>bestIcon.bounds.size.width*bestIcon.bounds.size.height))bestIcon=iv;
        }
    }
    *icon=bestIcon;*label=bestLabel;
}
// WeChat's rows of the menu, top to bottom.
static NSArray<UIView *> *WXGMenuItems(UIView *body) {
    NSMutableArray<UIView *> *items=[NSMutableArray array];
    for(UIView *v in WXGViews(body,160))
        if(v!=body && !v.hidden && v.bounds.size.width>40 && v.bounds.size.height>16 &&
           [NSStringFromClass(v.class) isEqual:@"RightTopMenuItemBtn"])[items addObject:v];
    UIWindow *window=body.window;
    CGFloat (^top)(UIView *)=^CGFloat(UIView *v){return [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds),CGRectGetMidY(v.bounds)) toView:window].y;};
    [items sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){CGFloat ya=top(a),yb=top(b);return ya<yb?NSOrderedAscending:ya>yb?NSOrderedDescending:NSOrderedSame;}];
    return items;
}
static CGFloat WXGMenuSnap(CGFloat v,UIView *view) {
    CGFloat scale=view.window.screen.scale>0?view.window.screen.scale:UIScreen.mainScreen.scale;
    return round(v*scale)/scale;
}
// On screen: in a window, on its screen, and neither the view nor anything above it hidden or clear.
static BOOL WXGMenuShown(UIView *view) {
    UIWindow *window=view.window;if(!window)return NO;
    for(UIView *v=view;v;v=v.superview)if(v.hidden || v.alpha<.01)return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:window],window.bounds);
}
// Is there anything to read in WeChat's rows (an icon or a title)? / how opaque is a view, with everything above it.
static BOOL WXGMenuHasParts(NSArray<UIView *> *items) {
    for(UIView *item in items){UIImageView *i=nil;UILabel *l=nil;WXGMenuParts(item,&i,&l);if(i || l.text.length)return YES;}
    return NO;
}
static CGFloat WXGMenuAlpha(UIView *view) {
    CGFloat a=1;for(UIView *v=view;v;v=v.superview)a*=v.alpha;
    return a;
}
// Core Animation keys of one row's expand/collapse.
static NSArray<NSString *> *WXGMenuAnimationKeys(void) {
    return @[@"wxg.menu.transform",@"wxg.menu.alpha"];
}
static void WXGMenuClearAnimations(CALayer *layer) {for(NSString *key in WXGMenuAnimationKeys())[layer removeAnimationForKey:key];}
static void WXGMenuTransformAnimate(CALayer *layer,CATransform3D from,CATransform3D to,double duration,CFTimeInterval begin,BOOL easeOut,NSString *key) {
    CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform"];
    a.fromValue=[NSValue valueWithCATransform3D:from];
    a.toValue=[NSValue valueWithCATransform3D:to];
    a.duration=MAX(duration,.01);a.beginTime=begin;
    // Zero-overshoot ease-out on expand (no post-expand bounce); accelerating ease-in on collapse.
    a.timingFunction=easeOut?[CAMediaTimingFunction functionWithControlPoints:.22f :1.f :.36f :1.f]
                            :[CAMediaTimingFunction functionWithControlPoints:.55f :0.f :1.f :.45f];
    a.fillMode=kCAFillModeBackwards;a.removedOnCompletion=YES;
    [layer addAnimation:a forKey:key];
}
static void WXGMenuFadeAnimate(CALayer *layer,float from,float to,double duration,CFTimeInterval begin,BOOL easeOut,NSString *key) {
    CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue=@(from);a.toValue=@(to);
    a.duration=MAX(duration,.01);a.beginTime=begin;
    a.timingFunction=easeOut?[CAMediaTimingFunction functionWithControlPoints:.22f :1.f :.36f :1.f]
                            :[CAMediaTimingFunction functionWithControlPoints:.55f :0.f :1.f :.45f];
    a.fillMode=kCAFillModeBackwards;a.removedOnCompletion=YES;
    [layer addAnimation:a forKey:key];
}

@implementation WXGDecorations
+ (instancetype)shared {
    static WXGDecorations *manager;static dispatch_once_t once;
    dispatch_once(&once,^{
        manager=[self new];manager.entries=[NSHashTable weakObjectsHashTable];
        // FIX29: just before every Core Animation commit, re-assert the cleared
        // native paint of on-screen menus. WeChat re-skins its reused plus
        // menu while opening it, outside any layout we hook; whatever it set
        // in this run-loop pass is undone before it can be drawn.
        __weak WXGDecorations *weakManager=manager;
        CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999800,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity activity){WXGPerfTimePluginWorkAs("decorations",^{[weakManager reassertVisiblePaint];});});   // FIX102: timed
        if(observer){CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);CFRelease(observer);}
    });
    return manager;
}
- (void)reassertVisiblePaint {
    for(WXGDecoration *entry in _entries.allObjects) {   // (a copy: a layout done below may mount another menu)
        // FIX116 B: a menu WeChat took out of its window while the glass was open: the glass leaves.
        if(entry.capsuleMode && !entry.host.window && !entry.applying) {
            entry.blockReopen=NO;
            if(entry.phase==WXGMenuPhaseOpen)[self beginExit:entry];
        }
        if(!entry.host.window || entry.applying)continue;
        @try {[entry.states reapply];} @catch(__unused NSException *error) {}
        if(entry.capsuleMode || [entry.kind isEqual:@"homeMenu"])[self watchCapsuleMenu:entry];   // FIX116 A
    }
}
// FIX116 A: the menu opening or closing, or its rows moving, happens outside
// any layout we hook (WeChat shows and hides its reused menu by a flag, and
// moves it to close it): noticed here, before the commit, and laid out again
// so the entrance starts with the first frame the menu is on screen in and
// the exit with the first frame WeChat's close would have moved anything in.
- (void)watchCapsuleMenu:(WXGDecoration *)entry {
    UIView *host=entry.host,*body=entry.body;if(!host)return;
    CFTimeInterval now=CACurrentMediaTime();
    if(!body){if(entry.capsuleMode && entry.phase==WXGMenuPhaseOpen)[self beginExit:entry];return;}   // (WeChat let its menu's body go)
    BOOL shown=WXGMenuShown(body);
    if(!entry.capsuleMode) {
        // Plate mode with the setting on: the rows had nothing to read when the
        // menu was last laid out; looked at again (at most every 0.1 s) while it is on screen.
        if(shown && WXGHomeMenuCapsulesOn() && now-entry.lastNudge>.1){entry.lastNudge=now;entry.watching=YES;@try{[self nativeHostLaidOut:host];}@finally{entry.watching=NO;}}
        return;
    }
    if(!shown) {
        // WeChat has hidden it: an open menu leaves (it needs no layout), and the next time it shows, it is open.
        entry.blockReopen=NO;entry.tickRetries=0;
        if(entry.phase==WXGMenuPhaseOpen)[self beginExit:entry];
        return;
    }
    UIView *parent=host.superview;
    CGFloat farthest=0;   // how far WeChat's rows have moved from where the glass was laid out
    if(parent && entry.rowsReady && now-entry.lastPlaced>.05)for(WXGMenuRow *row in entry.rows) {
        UIView *item=row.item;if(!item || !row.drawn)continue;
        CGRect r=[item convertRect:item.bounds toView:parent],was=row.itemFrame;
        farthest=MAX(farthest,MAX(MAX(fabs(r.origin.x-was.origin.x),fabs(r.origin.y-was.origin.y)),MAX(fabs(r.size.width-was.size.width),fabs(r.size.height-was.size.height))));
    }
    BOOL moved=farthest>.5,open=entry.phase==WXGMenuPhaseOpen;
    // A menu that has settled and then moves is WeChat closing it (it slides it away while it fades): the glass leaves, where it is.
    // (while the entrance is still playing only a long way counts: WeChat lays the menu out again a pass after it opens)
    if(open && entry.entranceDone && farthest>(now-entry.openAt>.65?6:40)){[self beginExit:entry];return;}
    BOOL stale=entry.blockReopen && now-entry.exitAt>.8 && WXGMenuAlpha(body)>=.99;   // (still on screen long after the exit: it is not closing any more)
    BOOL need=(!open && !entry.blockReopen) ||                       // opened: the entrance
              (open && (moved || !entry.rowsReady || !entry.entranceDone)) ||
              (!open && entry.blockReopen && (!moved || stale));     // (its rows are back where they were: opened again)
    // (a budget: a menu that never reads right is not laid out on every pass; a layout WeChat does itself, or a flip, gives it back)
    if(need && entry.tickRetries<40) {
        ++entry.tickRetries;entry.watching=YES;
        @try {[self nativeHostLaidOut:host];} @catch(__unused NSException *error) {} @finally {entry.watching=NO;}
    }
}
- (NSString *)kindForHost:(UIView *)view {
    NSString *name=NSStringFromClass(view.class);
    if([name isEqual:@"MMMsgCommonTipsView"])return @"pinnedRow";
    if([name isEqual:@"MainFrameActionFloatView"])return @"homeMenu";
    if([name isEqual:@"MMMenuContentView"])return @"messageMenu";
    if([name isEqual:@"WCOperateFloatView"])return @"momentsMenu";   // FIX108 C: 朋友圈的 赞 / 评论
    return nil;
}
- (UIView *)bodyForHost:(UIView *)host kind:(NSString *)kind {
    if([kind isEqual:@"pinnedRow"]) {
        for(UIView *v in WXGViews(host,100))if([v isKindOfClass:UIControl.class] &&
            [WXGActionNames((id)v) containsObject:@"performBgAction"] && v.bounds.size.width>100)return v.superview;
        return nil;
    }
    NSString *item=[kind isEqual:@"homeMenu"]?@"RightTopMenuItemBtn":[kind isEqual:@"momentsMenu"]?@"WCLikeButton":@"MMMenuItemView";
    for(UIView *v in WXGViews(host,160))if([NSStringFromClass(v.class) isEqual:item] &&
        v.superview!=host && v.superview.bounds.size.width>60)return v.superview;
    return nil;
}
- (void)clearPaint:(WXGDecoration *)entry {
    UIView *host=entry.host,*body=entry.body;WXGStateBag *states=entry.states;
    NSMutableArray *content=[NSMutableArray array];
    NSArray *nodes=WXGViews(host,200);
    for(UIView *v in nodes)if([v isKindOfClass:UIControl.class] || [v isKindOfClass:UILabel.class]) [content addObject:v];
    [states stripChrome:host preserving:content];[states clear:body];
    // The plus menu has a UIImageView *container* around its real buttons.
    // Clear its image pixels, never its alpha or its descendants.
    for(UIView *v=body;v && v!=host.superview;v=v.superview) {
        if([v isKindOfClass:UIImageView.class])[states clearImagePaint:(id)v];else [states clear:v];
        if(v==host)break;
    }
    // FIX115 B: FIX114 Z cleared the views wrapping the menu at its own size
    // here. The "+" menu's host is the whole screen, so those were the home
    // page's own containers (MMUIHookView, the wrapper and transition views):
    // their grey went and the window's white showed behind the title row
    // (user, 02:54). The corners were the glass's own shadow (WXGCommon.h,
    // shadowClipRoot); nothing around the menu is cleared any more.
    for(UIView *v in nodes) {
        if(WXGIsPluginView(v))continue;
        if(![entry.kind isEqual:@"pinnedRow"]) {
            if([v isKindOfClass:UILabel.class])[states adaptLabelColor:(id)v];
            if([v isKindOfClass:UIImageView.class] && v.bounds.size.width>4 && v.bounds.size.width<=48 && v.bounds.size.height<=48)
                [states adaptMonochromeImage:(id)v];
        }
        if([v isKindOfClass:UIControl.class]) {
            [states clear:v];id paint=WXGRead(v,@"_backgroundView");
            if([paint isKindOfClass:UIImageView.class] && [paint isDescendantOfView:v] &&
               ((UIView *)paint).bounds.size.width>=v.bounds.size.width*.85)[states clearImagePaint:paint];
        }
        // Native menu dividers and the small pointer are paint, not actions.
        if(![v isKindOfClass:UIControl.class] && ![v isKindOfClass:UILabel.class] && !v.gestureRecognizers.count && !v.subviews.count) {
            CGRect rect=[v convertRect:v.bounds toView:body];
            BOOL divider=rect.size.height<=1 && rect.size.width>body.bounds.size.width*.35;
            // FIX108 C: the Moments bar's upright line between 赞 and 评论 (black on glass: too hard).
            if([entry.kind isEqual:@"momentsMenu"] && rect.size.width<=1.5 && rect.size.height>body.bounds.size.height*.35)divider=YES;
            BOOL pointer=[entry.kind isEqual:@"messageMenu"] && [v isKindOfClass:UIImageView.class] &&
                rect.size.height<=22 && rect.size.width<=50 && CGRectGetMidY(rect)>CGRectGetMaxY(body.bounds);
            if(divider || pointer)[states hide:v];
        }
    }
    if([entry.kind isEqual:@"pinnedRow"]) {
        // Collapsed stacks have two uninteractive 12pt trailing sheets.
        for(UIView *parent=host.superview;parent;parent=parent.superview) {
            if([NSStringFromClass(parent.class) isEqual:@"MMNewMsgContentNavBar"])break;
            if(parent.bounds.size.height>260)break;
            if(![parent isKindOfClass:UIControl.class])[states clear:parent];
            for(UIView *v in parent.subviews)if(v!=host && !v.subviews.count && !v.gestureRecognizers.count &&
                ![v isKindOfClass:UIControl.class] && ![v isKindOfClass:UILabel.class] &&
                ![v isKindOfClass:UIImageView.class] && v.bounds.size.height<=16 && v.bounds.size.width>body.bounds.size.width*.8)[states clear:v];
        }
    }
    [states reapply];
}
// FIX114 Z: a menu's views (and the views around it) as they are after the
// paint is cleared: what still paints (fill, shadow, image), clips, masks, and
// whose class it is (WeChat, the system, another plugin).
static NSString *WXGDecorationRow(UIView *v,UIView *window,NSString *place) {
    CALayer *l=v.layer;CGRect r=[v convertRect:v.bounds toView:window];
    const char *image=class_getImageName(object_getClass(v));NSString *owner=image?@(image).lastPathComponent:@"?";
    CGFloat fill=l.backgroundColor?CGColorGetAlpha(l.backgroundColor):0;
    return [NSString stringWithFormat:@"%@ %@(%@) %.0f,%.0f %.0fx%.0f 底%.2f 影%.2f/%.0f%@ 圆%.1f%@%@%@%@%@",place,NSStringFromClass(v.class),owner,
            r.origin.x,r.origin.y,r.size.width,r.size.height,fill,l.shadowOpacity,l.shadowRadius,l.shadowPath?@"有路径":@"",l.cornerRadius,
            l.masksToBounds?@" 裁":@"",l.mask?@" 遮罩":@"",v.hidden?@" 隐":@"",v.alpha<.99?[NSString stringWithFormat:@" 透%.2f",v.alpha]:@"",
            [v isKindOfClass:UIVisualEffectView.class]?[NSString stringWithFormat:@" 效果%@",NSStringFromClass(((UIVisualEffectView *)v).effect.class)]:
            ([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image?@" 有图":@"")];
}
- (void)dump:(WXGDecoration *)entry {
    UIView *host=entry.host;UIWindow *w=host.window;if(!host || !w)return;
    NSMutableArray *rows=[NSMutableArray array];NSUInteger depth=0;
    for(UIView *v=host.superview;v && depth<5 && v!=w;v=v.superview,depth++)[rows addObject:WXGDecorationRow(v,w,[NSString stringWithFormat:@"上%lu",(unsigned long)depth+1])];
    for(UIView *v in host.superview.subviews)if(v!=host)[rows addObject:WXGDecorationRow(v,w,@"旁")];
    for(UIView *v in WXGViews(host,40))[rows addObject:WXGDecorationRow(v,w,v==host?@"本":@"内")];
    if(!_dumps)_dumps=[NSMutableDictionary dictionary];
    _dumps[entry.kind]=rows.count>60?[rows subarrayWithRange:NSMakeRange(0,60)]:rows;
}
- (void)nativeHostLaidOut:(UIView *)view {
    if(!NSThread.isMainThread)return;
    if([NSStringFromClass(view.class) isEqual:@"MMMsgTipsMixedListExpandView"]) {
        for(UIView *child in WXGViews(view,40))if([child isKindOfClass:UITableView.class])
            for(UITableViewCell *cell in ((UITableView *)child).visibleCells)
                for(UIView *row in WXGViews(cell.contentView,60))if([NSStringFromClass(row.class) isEqual:@"MMMsgCommonTipsView"])[self nativeHostLaidOut:row];
        return;
    }
    NSString *kind=[self kindForHost:view];if(!kind)return;
    WXGDecoration *entry=objc_getAssociatedObject(view,&WXGDecorationKey);
    // A menu owns this entry through an associated object. Release the temporary
    // capture exclusion on detachment, otherwise entry -> glass -> host forms
    // a retain cycle each time WeChat creates a fresh native menu instance.
    if(!view.window) {
        entry.surface.active=NO;entry.surface.glass.backdropExclusions=@[];
        if(entry.capsuleMode){entry.blockReopen=NO;[self beginExit:entry];}   // FIX116 B: WeChat took the menu away (its own close ends so): the glass leaves, it does not vanish with it
        return;
    }
    if(!WXGPluginEnabled() || !WXGPreferences.shared.nav) {
        if(entry){
            [entry.states restore];entry.surface.active=NO;entry.surface.hidden=YES;entry.surface.glass.backdropExclusions=@[];
            [self hideRows:entry remove:YES];entry.capsuleMode=NO;entry.phase=WXGMenuPhaseClosed;entry.entranceDone=NO;   // FIX116 A
        }return;
    }
    if(entry.applying)return;
    if(!entry) {
        entry=[WXGDecoration new];entry.host=view;entry.kind=kind;entry.states=[WXGStateBag new];
        entry.surface=[WXGSurface new];entry.surface.role=kind;entry.surface.materialOnly=YES;
        entry.surface.glass.keepsAncestorClips=YES;   // FIX114 Y: nothing above the host is opened
        // FIX115 B: the menus' containers between the glass and the menu itself
        // (cleared of their paint) are opened for the shadow (see WXGCommon.h).
        if([kind isEqual:@"messageMenu"] || [kind isEqual:@"homeMenu"])entry.surface.glass.shadowClipRoot=view;   // the two with the grey corners
        entry.surface.userInteractionEnabled=NO;entry.surface.isAccessibilityElement=NO;
        objc_setAssociatedObject(view,&WXGDecorationKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_entries addObject:entry];++_mounts;
    }else ++_reuses;
    if(!entry.watching)entry.tickRetries=0;   // FIX116 A: a layout of WeChat's own gives the observer its budget back
    entry.applying=YES;
    @try {
        UIView *body=[self bodyForHost:view kind:kind];
        if(!body || body.bounds.size.width<40 || body.bounds.size.height<16) {
            entry.validBody=NO;entry.surface.active=NO;entry.surface.hidden=YES;
            if(entry.capsuleMode)[self beginExit:entry];   // FIX116 B: a body that collapses is WeChat closing the menu (only an open menu has anything to leave)
            // FIX28: WeChat lays the plus menu out once before adding its
            // buttons. Its own background must not render meanwhile: clear the
            // host's paint now and look again on the next main-queue turn.
            if(![kind isEqual:@"pinnedRow"]) {
                // FIX108 E: not for the Moments bar: its dark plate is what
                // keeps its white 赞 / 评论 readable until the glass is there
                // (stripped with no body found, it stayed bare on the white feed).
                if(![kind isEqual:@"momentsMenu"]) {
                    [entry.states stripChrome:view preserving:@[]];
                    for(UIView *v in WXGViews(view,80))
                        if([v isKindOfClass:UIImageView.class] && v.bounds.size.width>60)[entry.states clearImagePaint:(id)v];
                    [entry.states reapply];
                }else {
                    // FIX108 F: the same bar collapsing for a pass (opening from
                    // zero width, a quick close and reopen): its glass stays as it
                    // is; a new one never found: WeChat's plate back, and the
                    // paint cleared again in full once its body turns up.
                    if(entry.body && [entry.body isDescendantOfView:view] && entry.lastPaint>0){entry.validBody=YES;entry.surface.hidden=NO;return;}
                    [entry.states restore];entry.lastPaint=0;
                }
                if(entry.earlyRetries<6) {
                    ++entry.earlyRetries;__weak UIView *weakHost=view;
                    dispatch_async(dispatch_get_main_queue(),^{if(weakHost)[self nativeHostLaidOut:weakHost];});
                }
            }
            return;
        }
        entry.earlyRetries=0;
        if(entry.body!=body){[entry.states restore];entry.body=body;entry.lastPaint=0;}
        entry.validBody=YES;
        WXGSurface *surface=entry.surface;
        // FIX116 A: the home menu as glass capsules and round icons, when its
        // rows can be read; until they can (WeChat fills them a pass later) it
        // is painted bare for up to a quarter second, and the plate (below) is
        // the fallback when they never can. A menu that is not on
        // screen keeps the look it has.
        NSArray<UIView *> *items=nil;BOOL capsules=NO;
        if([kind isEqual:@"homeMenu"] && WXGHomeMenuCapsulesOn()) {
            items=WXGMenuItems(body);BOOL content=NO,visible=WXGMenuShown(body);
            for(UIView *item in items){UIImageView *i=nil;UILabel *l=nil;WXGMenuParts(item,&i,&l);if(i || l.text.length){content=YES;break;}}
            CFTimeInterval waited=CACurrentMediaTime();
            if(!visible || content)entry.partsSince=0;
            if(content)capsules=YES;
            else if(!visible)capsules=entry.capsuleMode;
            else if(entry.capsuleMode && entry.phase!=WXGMenuPhaseClosed) {
                // WeChat emptying its rows while the menu is open is most likely its close: the glass leaves (and is no
                // reason to drop it at once); if the rows stay empty, the grace below takes it back to the plate after that.
                if(entry.phase==WXGMenuPhaseOpen)[self beginExit:entry];
                capsules=YES;
            }
            else {
                if(entry.partsSince==0) {
                    // First look at a shown menu whose rows are empty: a quarter second to be filled,
                    // looked at again after 80 ms and when it is over.
                    entry.partsSince=waited;__weak UIView *weakHost=view;
                    for(NSNumber *delay in @[@.08,@.27])
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(weakHost)[self nativeHostLaidOut:weakHost];});
                }
                capsules=waited-entry.partsSince<.25;
            }
        }
        if(entry.capsuleMode!=capsules) {
            // The look changed (the setting, or the rows turned up): the other look is taken down.
            entry.capsuleMode=capsules;[entry.states restore];[self hideRows:entry remove:YES];
            entry.phase=WXGMenuPhaseClosed;entry.entranceDone=NO;entry.blockReopen=NO;entry.lastPaint=0;
        }
        if(capsules){surface.active=NO;surface.hidden=YES;surface.glass.backdropExclusions=@[];}
        else {
        // FIX27: the message long-press menu radius is a setting; the plus menu keeps 18.
        surface.maximumCornerRadius=[kind isEqual:@"pinnedRow"]?MIN(body.bounds.size.height*.5,32):
            [kind isEqual:@"messageMenu"]?WXGConfig.shared.messageMenuCornerRadius:
            [kind isEqual:@"momentsMenu"]?body.bounds.size.height*.5:18;   // FIX108 C: the Moments bar is a capsule
        surface.glass.sourceView=[kind isEqual:@"pinnedRow"]?WXGContentSourceForView(view):(_source?:WXGContentSourceForView(view));
        surface.glass.backdropExclusions=@[view];
        UIView *parent=body;CGRect material=body.bounds;
        if([kind isEqual:@"pinnedRow"]) {
            // Probe: every native tips row has its own 44pt performBgAction.
            // Use that action's rectangle, not a shorter/clipped paint child.
            parent=view;material=[body convertRect:body.bounds toView:parent];
            for(UIView *child in WXGViews(body,80))if([child isKindOfClass:UIControl.class] &&
                [WXGActionNames((id)child) containsObject:@"performBgAction"] && child.bounds.size.height>=16) {
                material=[child convertRect:child.bounds toView:parent];break;
            }
            surface.maximumCornerRadius=MIN(material.size.height*.5,32);
        }
        [surface placeMaterial:material inParent:parent];
        if(parent.subviews.firstObject!=surface)[parent insertSubview:surface atIndex:0];
        }
        CFTimeInterval now=CACurrentMediaTime();
        if(!entry.lastPaint || now-entry.lastPaint>.35 || entry.bodyChildren!=body.subviews.count ||
           entry.hostChildren!=view.subviews.count || entry.appearance!=view.traitCollection.userInterfaceStyle) {
            [self clearPaint:entry];entry.lastPaint=now;
            [self dump:entry];   // FIX114 Z (diagnostics)
            entry.bodyChildren=body.subviews.count;entry.hostChildren=view.subviews.count;
            entry.appearance=view.traitCollection.userInterfaceStyle;
        }else [entry.states reapply];
        if(capsules)[self placeCapsuleMenu:entry items:items];
        else {surface.hidden=NO;surface.active=view.window && WXGVisible(body,view.window);}
    } @catch(NSException *error) {
        WXGLog(@"局部材质 %@：%@",kind,error.reason);[entry.states restore];entry.surface.active=NO;entry.surface.hidden=YES;
        if(entry.capsuleMode){[self hideRows:entry remove:YES];entry.capsuleMode=NO;entry.phase=WXGMenuPhaseClosed;entry.entranceDone=NO;}   // FIX116 A: WeChat's own icons are back, so the glass of them goes
    } @finally {entry.applying=NO;}
}
// ---- FIX116 A: the home menu's capsules and icons ---------------------------
// The "+" in the menu parent's coordinates: the plugin's own button first (it
// is where the glass is), else WeChat's control, else where it was last, else
// the usual corner.
- (CGRect)plusRectFor:(WXGDecoration *)entry parent:(UIView *)parent {
    UIWindow *window=parent.window;
    CGRect found=CGRectNull;
    CGRect own=[WXGIntegrationHost.shared homePlusRectInWindow:window];
    if(!CGRectIsNull(own) && !CGRectIsEmpty(own))found=[parent convertRect:own fromView:window];
    if(CGRectIsNull(found)) {
        CFTimeInterval now=CACurrentMediaTime();UIControl *plus=entry.plusControl;
        if((!plus || plus.window!=window) && now-entry.plusSearchedAt>.6) {
            entry.plusSearchedAt=now;plus=nil;
            for(UIView *v in WXGViews(window,600))
                if([v isKindOfClass:UIControl.class] && !WXGIsPluginView(v) && v.bounds.size.width<=80 &&
                   [WXGActionNames((id)v) containsObject:@"showRightTopMenuBtn"]){plus=(id)v;break;}
            entry.plusControl=plus;
        }
        if(plus.window==window && !plus.hidden) {
            CGRect c=[plus convertRect:plus.bounds toView:parent];
            if(!CGRectIsEmpty(c))found=c;
        }
    }
    if(!CGRectIsNull(found)){entry.lastPlus=found;return found;}
    if(!CGRectIsEmpty(entry.lastPlus))return entry.lastPlus;
    return CGRectMake(parent.bounds.size.width-parent.safeAreaInsets.right-14-44,0,44,44);
}
- (WXGSurface *)glassForRowRole:(NSString *)role {
    WXGSurface *s=[WXGSurface new];s.role=role;s.materialOnly=YES;
    s.glass.keepsAncestorClips=YES;
    s.userInteractionEnabled=NO;s.isAccessibilityElement=NO;s.accessibilityElementsHidden=YES;   // WeChat's rows are what VoiceOver reads
    return s;
}
- (WXGMenuInkOverlayView *)ensureInkOverlay:(WXGDecoration *)entry inParent:(UIView *)parent {
    if(!parent)return nil;
    if(!entry.inkOverlay)entry.inkOverlay=[WXGMenuInkOverlayView new];
    WXGMenuInkOverlayView *ink=entry.inkOverlay;
    if(ink.superview!=parent){[ink removeFromSuperview];[parent addSubview:ink];}
    ink.frame=parent.bounds;
    ink.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    ink.layer.zPosition=20000;
    [parent bringSubviewToFront:ink];
    return ink;
}
- (CGFloat)lastDrawnRowMidY:(WXGDecoration *)entry plusRect:(CGRect)plusRect {
    CGFloat maxY=CGRectGetMidY(plusRect)+120.;BOOL found=NO;
    for(WXGMenuRow *row in entry.rows) {
        if(!row.drawn)continue;
        CGFloat y=CGRectGetMidY(row.iconRect);
        if(!found || y>maxY){maxY=y;found=YES;}
    }
    return maxY;
}
- (void)hideRows:(WXGDecoration *)entry remove:(BOOL)remove {
    [entry.inkOverlay stop];
    if(remove){[entry.inkOverlay removeFromSuperview];entry.inkOverlay=nil;}
    [entry.plusSurface setHomePlusMenuOpen:NO animated:NO speed:1.];
    [entry.plusSurface setHomePlusDotsHidden:NO];
    if(remove)entry.plusSurface=nil;
    for(WXGMenuRow *row in entry.rows) {
        for(WXGSurface *s in @[row.icon,row.capsule]) {
            WXGMenuClearAnimations(s.layer);s.layer.transform=CATransform3DIdentity;
            s.active=NO;s.hidden=YES;s.glass.backdropExclusions=@[];
            if(remove)[s removeFromSuperview];
        }
        if(remove && row.observer){[row.observer.view removeGestureRecognizer:row.observer];row.observer=nil;}
    }
    if(remove)entry.rows=nil;
    entry.rowsReady=NO;
}
// FIX116 B: have WeChat's rows moved since the glass was laid out, by more than `limit` pt? (the rows that are the same views)
- (BOOL)rowsMovedOf:(WXGDecoration *)entry items:(NSArray<UIView *> *)items parent:(UIView *)parent limit:(CGFloat)limit {
    NSUInteger n=MIN(entry.rows.count,items.count);
    for(NSUInteger i=0;i<n;i++) {
        WXGMenuRow *row=entry.rows[i];UIView *item=items[i];
        if(row.item!=item || !row.drawn)continue;
        CGRect r=[item convertRect:item.bounds toView:parent],was=row.itemFrame;
        if(fabs(r.origin.x-was.origin.x)>limit || fabs(r.origin.y-was.origin.y)>limit || fabs(r.size.width-was.size.width)>limit || fabs(r.size.height-was.size.height)>limit)return YES;
    }
    return NO;
}
// FIX116 B: the glass leaves (WXGMenuCascade.h's 5-track 350ms collapse) from the pose it is in,
// at the places it was laid out: whatever WeChat does to its own menu while
// closing it (it moves it, fades it, hides it) no longer reaches the glass.
- (void)beginExit:(WXGDecoration *)entry {
    if(entry.phase!=WXGMenuPhaseOpen)return;
    entry.phase=WXGMenuPhaseExiting;entry.entranceDone=NO;++entry.exits;entry.exitAt=CACurrentMediaTime();
    // Still shown by WeChat (it is only moving it): not opened again before it is hidden (or its rows are back).
    entry.blockReopen=entry.host.window && entry.body && WXGMenuShown(entry.body);
    NSUInteger token=++entry.exitToken;
    double duration=[self playExit:entry token:token];
    __weak WXGDecoration *weakEntry=entry;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((duration+.06)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGDecoration *later=weakEntry;
        if(later && later.exitToken==token && later.phase==WXGMenuPhaseExiting)[self finishExit:later];
    });
}
- (void)finishExit:(WXGDecoration *)entry {
    entry.phase=WXGMenuPhaseClosed;
    [entry.inkOverlay stop];
    [entry.plusSurface setHomePlusMenuOpen:NO animated:NO speed:1.];
    [entry.plusSurface setHomePlusDotsHidden:NO];
    for(WXGMenuRow *row in entry.rows)for(WXGSurface *s in @[row.icon,row.capsule]) {
        WXGMenuClearAnimations(s.layer);s.layer.transform=CATransform3DIdentity;
        s.active=NO;s.hidden=YES;
    }
}
// Returns when all 5 collapse tracks are complete, in seconds (350ms at 1x speed).
- (double)playExit:(WXGDecoration *)entry token:(NSUInteger)token {
    BOOL calm=UIAccessibilityIsReduceMotionEnabled();
    double stagger=WXGMenuClamp([WXGConfig.shared extraNumber:@"homeMenuStagger"],0,80)/1000.0;
    double speed=[WXGConfig.shared extraNumber:@"homeMenuSpeed"];
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    UIView *parent=entry.menuParent?:entry.host.superview;
    UIWindow *win=entry.host.window?:parent.window;
    WXGSurface *plus=entry.plusSurface?:[WXGIntegrationHost.shared homePlusSurfaceInWindow:win];
    entry.plusSurface=plus;
    // Track 1 & 2: close 270-deg arc (30..250ms) and swap x -> + (0..350ms, zero bounce).
    [plus setHomePlusMenuOpen:NO animated:!calm speed:speed];
    // Track 3: respawn ink drops at bottom, sweep rapidly up to 6:00 (0..250ms),
    // then dock precisely into the 5 bottom dots at 350ms and hand back to the static dots.
    if(!calm && parent) {
        CGRect plusRect=[self plusRectFor:entry parent:parent];
        CGFloat lastMidY=[self lastDrawnRowMidY:entry plusRect:plusRect];
        [plus setHomePlusDotsHidden:YES];
        WXGMenuInkOverlayView *ink=[self ensureInkOverlay:entry inParent:parent];
        __weak WXGDecoration *weakEntry=entry;
        [ink playOpen:NO speed:speed plusRect:plusRect lastRowMidY:lastMidY completion:^{
            WXGDecoration *later=weakEntry;
            if(later && later.exitToken==token)[later.plusSurface setHomePlusDotsHidden:NO];
        }];
    }else {
        [entry.inkOverlay stop];
        [plus setHomePlusDotsHidden:NO];
    }

    NSMutableArray<WXGMenuRow *> *drawn=[NSMutableArray array];
    for(WXGMenuRow *row in entry.rows)if(row.drawn && (!row.icon.hidden || !row.capsule.hidden))[drawn addObject:row];
    CFTimeInterval now=CACurrentMediaTime();
    double total=calm?.14:(.350/v);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(NSUInteger k=0;k<drawn.count;k++) {
        WXGMenuRow *row=drawn[k];
        WXGMenuExit e=WXGMenuExitFor((int)(drawn.count-1-k),row.slotDistance,stagger,speed);   // tiny bottom-first offset on icon suction
        if(calm){e.iconDelay=e.capsuleDelay=e.textDelay=0;e.iconFade=e.capsuleFade=e.textDuration=.12;e.iconDuration=e.capsuleDuration=.12;}
        // Track 4: collective accelerating suction straight into the "+" centre.
        if(!row.icon.hidden) {
            CALayer *layer=row.icon.layer,*now_=layer.presentationLayer?:layer;
            float fromAlpha=now_.opacity;CATransform3D fromT=now_.transform;
            WXGMenuClearAnimations(layer);layer.transform=CATransform3DIdentity;layer.opacity=0;
            CFTimeInterval begin=[layer convertTime:now+e.iconDelay fromLayer:nil];
            if(!calm && fromAlpha>.01f) {
                CATransform3D toT=CATransform3DConcat(CATransform3DMakeScale((CGFloat)e.iconScale,(CGFloat)e.iconScale,1.),
                                                      CATransform3DMakeTranslation(0.,(CGFloat)(-e.travel),0.));
                WXGMenuTransformAnimate(layer,fromT,toT,e.iconDuration,begin,NO,@"wxg.menu.transform");
            }
            if(fromAlpha>.01f)WXGMenuFadeAnimate(layer,fromAlpha,0,e.iconFade,begin,NO,@"wxg.menu.alpha");
            total=MAX(total,e.iconDelay+e.iconDuration);
        }
        // Track 5: priority synchronous 100ms vanish at t=0 (zero stagger, clears before icons overlap).
        if(!row.capsule.hidden) {
            CALayer *layer=row.capsule.layer,*text=row.capsule.label.layer,*layerNow=layer.presentationLayer?:layer;
            float fromAlpha=layerNow.opacity;CATransform3D fromT=layerNow.transform;
            WXGMenuClearAnimations(layer);WXGMenuClearAnimations(text);
            layer.transform=CATransform3DIdentity;layer.opacity=0;text.opacity=1;
            CFTimeInterval begin=[layer convertTime:now+e.capsuleDelay fromLayer:nil];
            if(!calm && fromAlpha>.01f) {
                double half=row.capsuleRect.size.width*.5;
                double tx=(1.-e.capsuleScaleX)*half+e.capsuleShift;
                CATransform3D toT=CATransform3DConcat(CATransform3DMakeScale((CGFloat)e.capsuleScaleX,(CGFloat)e.capsuleScaleY,1.),
                                                      CATransform3DMakeTranslation((CGFloat)tx,0.,0.));
                WXGMenuTransformAnimate(layer,fromT,toT,e.capsuleDuration,begin,NO,@"wxg.menu.transform");
            }
            if(fromAlpha>.01f)WXGMenuFadeAnimate(layer,fromAlpha,0,e.capsuleFade,begin,NO,@"wxg.menu.alpha");
            total=MAX(total,e.capsuleDelay+e.capsuleDuration);
        }
    }
    [CATransaction commit];
    return total;
}
// A glass that was hidden (its icon or title not there yet, or left at 0 opacity by the last close) shown now.
- (void)fadeInLate:(WXGSurface *)s {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    WXGMenuClearAnimations(s.layer);WXGMenuClearAnimations(s.label.layer);
    s.layer.transform=CATransform3DIdentity;s.layer.opacity=1;s.label.layer.opacity=1;
    [CATransaction commit];
    if(!UIAccessibilityIsReduceMotionEnabled())WXGMenuFadeAnimate(s.layer,0,1,.2,[s.layer convertTime:CACurrentMediaTime() fromLayer:nil],YES,@"wxg.menu.alpha");
}
- (void)placeCapsuleMenu:(WXGDecoration *)entry items:(NSArray<UIView *> *)items {
    UIView *host=entry.host,*body=entry.body,*parent=host.superview;
    if(!host.window || !body || !parent)return;
    CFTimeInterval now=CACurrentMediaTime();
    if(!WXGMenuShown(body)) {
        // Hidden by WeChat (or faded, or moved off screen): an open menu leaves; the next time it shows, it is open.
        entry.blockReopen=NO;entry.tickRetries=0;entry.partsSince=0;
        [self beginExit:entry];
        return;
    }
    BOOL same=entry.rows.count==items.count;   // (WeChat's rows are the views the glass was made for)
    for(NSUInteger i=0;same && i<items.count;i++)same=entry.rows[i].item==items[i];
    if(entry.phase==WXGMenuPhaseOpen) {
        // A menu that has opened and then moves, or loses its rows, is WeChat closing it (it slides it away
        // while it fades, and empties it): the glass leaves from where it is instead of following. Other rows
        // (WeChat made them anew) are a rebuild, below. (While the entrance is still playing only a long way counts:
        // WeChat lays the menu out again a pass after it opens.)
        if(entry.entranceDone) {
            BOOL settled=now-entry.openAt>.65;
            if(!items.count || (same && [self rowsMovedOf:entry items:items parent:parent limit:settled?6:40])){[self beginExit:entry];return;}
        }
    }else {
        // Closed, or on its way out while WeChat still shows the menu.
        if(entry.blockReopen) {
            // Opened again: rows back where they were, or other rows (a new menu), or it has stood on screen long
            // after the exit; not while there is nothing to read in it, nor while it is still leaving.
            BOOL again=items.count && WXGMenuHasParts(items) &&
                (!same || ![self rowsMovedOf:entry items:items parent:parent limit:3] || (now-entry.exitAt>.8 && WXGMenuAlpha(body)>=.99));
            if(!again)return;
            entry.blockReopen=NO;
        }
        if(!items.count)return;
        entry.phase=WXGMenuPhaseOpen;entry.openAt=now;entry.entranceDone=NO;++entry.exitToken;entry.tickRetries=0;
    }
    if(!items.count){[self hideRows:entry remove:YES];entry.phase=WXGMenuPhaseClosed;return;}
    entry.menuParent=parent;
    // The rows (made anew when WeChat made its own anew).
    if(!same) {
        [self hideRows:entry remove:YES];entry.rows=[NSMutableArray array];
        for(UIView *item in items) {
            WXGMenuRow *row=[WXGMenuRow new];row.item=item;
            row.icon=[self glassForRowRole:@"homeMenuIcon"];row.capsule=[self glassForRowRole:@"homeMenuTitle"];
            WXGMenuRowObserver *observer=[WXGMenuRowObserver new];observer.icon=row.icon;observer.capsule=row.capsule;
            [item addGestureRecognizer:observer];row.observer=observer;
            [entry.rows addObject:row];
        }
        entry.entranceDone=NO;entry.openAt=now;
    }
    // Where WeChat has each row, and the "+" the icons line up with.
    NSMutableArray<NSValue *> *frames=[NSMutableArray array];
    CGFloat minHeight=CGFLOAT_MAX,pitch=CGFLOAT_MAX,lastMid=0;BOOL haveLast=NO;
    for(UIView *item in items) {
        CGRect r=[item convertRect:item.bounds toView:parent];[frames addObject:[NSValue valueWithCGRect:r]];
        minHeight=MIN(minHeight,r.size.height);
        if(haveLast && CGRectGetMidY(r)-lastMid>1)pitch=MIN(pitch,CGRectGetMidY(r)-lastMid);
        lastMid=CGRectGetMidY(r);haveLast=YES;
    }
    CGFloat rowHeight=pitch<CGFLOAT_MAX?MIN(minHeight,pitch):minHeight;
    CGRect plus=[self plusRectFor:entry parent:parent];
    WXGMenuMetrics m=WXGMenuMetricsFor([WXGConfig.shared extraNumber:@"homeMenuIconSize"],rowHeight);
    UIFont *font=[UIFont systemFontOfSize:m.fontSize weight:UIFontWeightSemibold];
    double minX=parent.bounds.origin.x+parent.safeAreaInsets.left+10,centreX=CGRectGetMidX(plus);
    UIView *source=_source?:WXGContentSourceForView(host);
    NSUInteger drawn=0;BOOL late=entry.entranceDone;   // (rows that turn up after the entrance fade in by themselves)
    for(NSUInteger i=0;i<entry.rows.count;i++) {
        WXGMenuRow *row=entry.rows[i];UIView *item=items[i];CGRect r=frames[i].CGRectValue;
        UIImageView *iconView=nil;UILabel *label=nil;WXGMenuParts(item,&iconView,&label);
        NSString *title=label.text;BOOL hasIcon=iconView.image!=nil,hasTitle=title.length>0;
        row.itemFrame=r;row.nativeIcon=iconView;row.nativeLabel=label;row.slotDistance=CGRectGetMidY(r)-CGRectGetMidY(plus);
        row.drawn=hasIcon || hasTitle;
        if(!row.drawn){row.icon.hidden=YES;row.capsule.hidden=YES;row.icon.active=NO;row.capsule.active=NO;continue;}
        ++drawn;
        // WeChat's icon and title are hidden (masked), never moved: the row
        // stays where it is and keeps the touches and the action.
        if(iconView)[entry.states conceal:iconView];
        if(label)[entry.states conceal:label];
        // FIX117 A: and the row itself: what WeChat draws in it while it is held (its grey highlight) is not
        // seen either (a mask: the row keeps its touches and its action; the glass shows the press).
        [entry.states conceal:item];
        CGFloat textWidth=hasTitle?ceil([title sizeWithAttributes:@{NSFontAttributeName:font}].width):0;
        WXGMenuRowBoxes b=WXGMenuRowBoxesFor(CGRectGetMidY(r),centreX,textWidth,m,minX);
        CGRect iconRect=CGRectMake(WXGMenuSnap(b.icon.x,parent),WXGMenuSnap(b.icon.y,parent),b.icon.w,b.icon.h);
        CGRect capsuleRect=CGRectMake(WXGMenuSnap(b.capsule.x,parent),WXGMenuSnap(b.capsule.y,parent),b.capsule.w,b.capsule.h);
        row.iconRect=iconRect;row.capsuleRect=capsuleRect;
        for(WXGSurface *s in @[row.icon,row.capsule]){s.glass.sourceView=source;s.glass.backdropExclusions=@[host];s.glass.shadowClipRoot=parent;}
        if(hasIcon) {
            [row.icon setImage:iconView.image title:nil count:nil];
            if(late && row.icon.hidden)[self fadeInLate:row.icon];
            row.icon.hidden=NO;[row.icon placeMaterial:iconRect inParent:parent];row.icon.active=YES;
        }else{row.icon.hidden=YES;row.icon.active=NO;}
        if(hasTitle) {
            [row.capsule setImage:nil title:title count:nil];
            if(![row.capsule.label.font isEqual:font]){row.capsule.label.font=font;[row.capsule setNeedsLayout];}
            if(late && row.capsule.hidden)[self fadeInLate:row.capsule];
            row.capsule.hidden=NO;[row.capsule placeMaterial:capsuleRect inParent:parent];row.capsule.active=YES;
        }else{row.capsule.hidden=YES;row.capsule.active=NO;}
        row.observer.icon=row.icon;row.observer.capsule=row.capsule;
    }
    entry.rowsReady=drawn>0;entry.lastPlaced=now;
    if(!entry.rowsReady)return;
    if(!entry.entranceDone){entry.entranceDone=YES;++entry.entrances;[self playEntrance:entry];}
}
// 5-track ink-drop particle disintegration expand (600ms at 1x speed):
// Track 1: 270-deg arc retracts CCW; Track 2: + -> x two-stage scale swap;
// Track 3: 5 ink drops fall along sine-wiggle trail; Track 4: staggered glass
// icons ease smoothly into place with ZERO post-expand bounce; Track 5: glass
// capsules slide horizontally out from right-middle (+100ms after icon, dy=0).
- (void)playEntrance:(WXGDecoration *)entry {
    BOOL calm=UIAccessibilityIsReduceMotionEnabled();
    double stagger=WXGMenuClamp([WXGConfig.shared extraNumber:@"homeMenuStagger"],0,80)/1000.0;
    double speed=[WXGConfig.shared extraNumber:@"homeMenuSpeed"];
    UIView *parent=entry.menuParent?:entry.host.superview;
    WXGSurface *plus=[WXGIntegrationHost.shared homePlusSurfaceInWindow:entry.host.window?:parent.window];
    entry.plusSurface=plus;
    [plus setHomePlusDotsHidden:YES];
    [plus setHomePlusMenuOpen:YES animated:!calm speed:speed];
    if(!calm && parent) {
        CGRect plusRect=[self plusRectFor:entry parent:parent];
        CGFloat lastMidY=[self lastDrawnRowMidY:entry plusRect:plusRect];
        WXGMenuInkOverlayView *ink=[self ensureInkOverlay:entry inParent:parent];
        [ink playOpen:YES speed:speed plusRect:plusRect lastRowMidY:lastMidY completion:nil];
    }else {
        [entry.inkOverlay stop];
    }

    CFTimeInterval now=CACurrentMediaTime();int index=0;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(WXGMenuRow *row in entry.rows) {
        if(!row.drawn)continue;
        WXGMenuEntrance e=WXGMenuEntranceFor(index++,row.slotDistance,stagger,speed);
        // Track 4: circular glass icon (ty: -45 -> 0, scale: 0.40 -> 1.0, zero bounce!).
        if(!row.icon.hidden) {
            CALayer *layer=row.icon.layer;
            WXGMenuClearAnimations(layer);layer.transform=CATransform3DIdentity;layer.opacity=1;
            CFTimeInterval begin=[layer convertTime:now+(calm?0.:e.iconDelay) fromLayer:nil];
            if(!calm) {
                CATransform3D fromT=CATransform3DConcat(CATransform3DMakeScale((CGFloat)e.iconScale,(CGFloat)e.iconScale,1.),
                                                        CATransform3DMakeTranslation(0.,(CGFloat)(-e.travel),0.));
                WXGMenuTransformAnimate(layer,fromT,CATransform3DIdentity,e.iconDuration,begin,YES,@"wxg.menu.transform");
            }
            WXGMenuFadeAnimate(layer,0,1,calm?.14:e.iconFade,begin,YES,@"wxg.menu.alpha");
        }
        // Track 5: text glass capsule (dy: 0, horizontal slide from right-middle, zero bounce!).
        if(!row.capsule.hidden) {
            CALayer *layer=row.capsule.layer,*text=row.capsule.label.layer;
            WXGMenuClearAnimations(layer);WXGMenuClearAnimations(text);
            layer.transform=CATransform3DIdentity;layer.opacity=1;text.opacity=1;
            CFTimeInterval begin=[layer convertTime:now+(calm?0.:e.capsuleDelay) fromLayer:nil];
            if(!calm) {
                double half=row.capsuleRect.size.width*.5;
                double tx=(1.-e.capsuleScaleX)*half+e.capsuleShift;
                CATransform3D fromT=CATransform3DConcat(CATransform3DMakeScale((CGFloat)e.capsuleScaleX,(CGFloat)e.capsuleScaleY,1.),
                                                        CATransform3DMakeTranslation((CGFloat)tx,0.,0.));
                WXGMenuTransformAnimate(layer,fromT,CATransform3DIdentity,e.capsuleDuration,begin,YES,@"wxg.menu.transform");
            }
            WXGMenuFadeAnimate(layer,0,1,calm?.14:e.capsuleFade,begin,YES,@"wxg.menu.alpha");
        }
    }
    [CATransaction commit];
}
- (void)refresh {
    if(!WXGPluginEnabled() || !WXGPreferences.shared.nav){[self restore];return;}
    for(WXGDecoration *entry in _entries)if(entry.host.window)[self nativeHostLaidOut:entry.host];
}
- (void)applyConfiguration {
    for(WXGDecoration *entry in _entries) {
        [entry.surface applyConfig];
        for(WXGMenuRow *row in entry.rows){[row.icon applyConfig];[row.capsule applyConfig];}   // FIX116 A
    }
    [self refresh];
}
- (NSArray<WXGSurface *> *)visibleSurfaces {
    NSMutableArray *out=[NSMutableArray array];
    BOOL enabled=WXGPluginEnabled() && WXGPreferences.shared.nav;
    for(WXGDecoration *entry in _entries) {
        if(entry.capsuleMode) {
            // FIX116 A: the rows' glass instead of the plate; FIX116 B: and still while it leaves (WeChat has hidden its menu by then).
            entry.surface.active=NO;
            BOOL live=enabled && entry.rowsReady && ((entry.phase==WXGMenuPhaseOpen && entry.host.window) || entry.phase==WXGMenuPhaseExiting);
            UIView *source=_source?:WXGContentSourceForView(entry.menuParent?:entry.host);
            for(WXGMenuRow *row in entry.rows)for(WXGSurface *s in @[row.icon,row.capsule]) {
                BOOL on=live && row.drawn && !s.hidden && s.superview;
                s.active=on;
                if(on){s.glass.sourceView=source;[out addObject:s];}
            }
            if(live && entry.host.window)[entry.states reapply];
            continue;
        }
        BOOL visible=enabled && entry.validBody && entry.host.window && WXGVisible(entry.body,entry.host.window);
        entry.surface.active=visible;
        if(visible){entry.surface.hidden=NO;[entry.states reapply];entry.surface.glass.sourceView=[entry.kind isEqual:@"pinnedRow"]?WXGContentSourceForView(entry.host):(_source?:WXGContentSourceForView(entry.host));[out addObject:entry.surface];}
    }return out;
}
- (void)restore {
    for(WXGDecoration *entry in _entries) {
        [entry.states restore];entry.surface.active=NO;entry.surface.hidden=YES;entry.surface.glass.backdropExclusions=@[];
        [self hideRows:entry remove:YES];entry.capsuleMode=NO;entry.phase=WXGMenuPhaseClosed;entry.entranceDone=NO;   // FIX116 A
    }
}
- (NSArray *)rowEvidence:(WXGDecoration *)entry {
    NSMutableArray *out=[NSMutableArray array];
    for(WXGMenuRow *row in entry.rows)[out addObject:@{@"drawn":@(row.drawn),@"title":row.capsule.label.text?:@"",
        @"item":NSStringFromCGRect(row.itemFrame),@"icon":NSStringFromCGRect(row.iconRect),@"capsule":NSStringFromCGRect(row.capsuleRect),
        @"slot":@(row.slotDistance),@"nativeIcon":@(row.nativeIcon!=nil),@"nativeLabel":@(row.nativeLabel!=nil)}];
    return out;
}
- (NSDictionary *)evidence {
    NSMutableArray *rows=[NSMutableArray array];
    for(WXGDecoration *entry in _entries)if(entry.host.window)[rows addObject:@{@"kind":entry.kind,@"host":NSStringFromClass(entry.host.class),
        @"visible":@(entry.surface.active),@"nativeActionsRetained":@YES,@"frame":NSStringFromCGRect(entry.body.bounds),
        // FIX116 A
        @"capsuleMode":@(entry.capsuleMode),@"phase":@(entry.phase),@"rowsReady":@(entry.rowsReady),@"entrances":@(entry.entrances),@"exits":@(entry.exits),
        @"blockReopen":@(entry.blockReopen),@"menuParent":entry.menuParent?NSStringFromClass(entry.menuParent.class):@"",
        @"rows":[self rowEvidence:entry]}];
    return @{@"mounts":@(_mounts),@"reuses":@(_reuses),@"hosts":rows,@"lastMenus":_dumps?:@{}};   // FIX114 Z
}
@end
