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

@protocol WXGMenuCAFilterFactory <NSObject>
+ (id)filterWithType:(NSString *)type;
@end
static id WXGMenuMakeBlurFilter(double radius) {
    Class cls=NSClassFromString(@"CAFilter");
    if(!cls || ![cls respondsToSelector:@selector(filterWithType:)])return nil;
    id f=[(Class<WXGMenuCAFilterFactory>)cls filterWithType:@"gaussianBlur"];
    if(!f)return nil;
    @try {
        [f setValue:@"wxgMenuBlur" forKey:@"name"];
        [f setValue:@(radius) forKey:@"inputRadius"];
        [f setValue:@NO forKey:@"inputNormalizeEdges"];
    } @catch(__unused NSException *e) {}
    return f;
}

// Track 3: stateless ink-drop particle renderer driven at 120Hz by WXGDecorations's
// single normalized progress p in [0, 1] (synced 1:1 with the "+" button & menu rows).
@interface WXGMenuInkOverlayView : UIView
- (void)renderProgress:(double)p count:(int)count stagger:(double)stagger plusRect:(CGRect)plusRect targets:(NSArray<NSValue *> *)targets;
- (void)hideAll;
@end

@implementation WXGMenuInkOverlayView {
    CAShapeLayer *_dots[WXGMenuMaxParticles];
    BOOL _dotBlurred[WXGMenuMaxParticles];
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.hidden=YES;
        self.layer.zPosition=20000;
        CGFloat scale=UIScreen.mainScreen.scale;
        for(int i=0;i<WXGMenuMaxParticles;i++) {
            CAShapeLayer *dot=[CAShapeLayer layer];
            dot.hidden=YES;dot.contentsScale=scale;
            dot.bounds=CGRectMake(0,0,60,60);
            dot.strokeColor=NULL;
            dot.allowsEdgeAntialiasing=YES;
            dot.edgeAntialiasingMask=kCALayerLeftEdge|kCALayerRightEdge|kCALayerTopEdge|kCALayerBottomEdge;
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
    for(int i=0;i<WXGMenuMaxParticles;i++)_dots[i].fillColor=cg;
    [CATransaction commit];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(!previous || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])[self updateInkColor];
}
- (void)hideAll {
    if(self.hidden)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int i=0;i<WXGMenuMaxParticles;i++) {
        _dots[i].hidden=YES;
        if(_dotBlurred[i]){_dots[i].filters=nil;_dotBlurred[i]=NO;}
    }
    self.hidden=YES;
    [CATransaction commit];
}
- (void)renderProgress:(double)p count:(int)count stagger:(double)stagger plusRect:(CGRect)plusRect targets:(NSArray<NSValue *> *)targets {
    int n=WXGMenuClampCount(count);
    if(n<=0 || !targets.count || p<=.0001 || p>=.9999){[self hideAll];return;}
    [self updateInkColor];
    CGFloat screenScale=self.traitCollection.displayScale>0?self.traitCollection.displayScale:UIScreen.mainScreen.scale;
    double plusMidX=CGRectGetMidX(plusRect),plusMidY=CGRectGetMidY(plusRect);
    double buttonSize=MIN(plusRect.size.width,plusRect.size.height);
    if(buttonSize<20.)buttonSize=44.;
    BOOL anyVisible=NO;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int i=0;i<WXGMenuMaxParticles;i++) {
        CAShapeLayer *dot=_dots[i];
        if(i>=n || (NSUInteger)i>=targets.count) {
            dot.hidden=YES;
            if(_dotBlurred[i]){dot.filters=nil;_dotBlurred[i]=NO;}
            continue;
        }
        CGPoint dst=targets[(NSUInteger)i].CGPointValue;
        WXGMenuParticle pt=WXGMenuDotForProgress(i,n,p,stagger,plusMidX,plusMidY,buttonSize,dst.x,dst.y);
        if(pt.diameter<=.15 || pt.alpha<=.005) {
            dot.hidden=YES;
            if(_dotBlurred[i]){dot.filters=nil;_dotBlurred[i]=NO;}
            continue;
        }
        anyVisible=YES;
        dot.hidden=NO;
        dot.contentsScale=screenScale;
        CGFloat d=(CGFloat)pt.diameter;
        CGRect circle=CGRectMake(30.-d*.5,30.-d*.5,d,d);
        CGPathRef circlePath=CGPathCreateWithEllipseInRect(circle,NULL);
        dot.path=circlePath;
        CGPathRelease(circlePath);
        dot.position=CGPointMake((CGFloat)pt.x,(CGFloat)pt.y);
        dot.opacity=(float)pt.alpha;
        if(pt.blurRadius>.15) {
            if(!_dotBlurred[i]) {
                id f=WXGMenuMakeBlurFilter(pt.blurRadius);
                if(f){dot.filters=@[f];_dotBlurred[i]=YES;}
            }else {
                @try {[dot setValue:@(pt.blurRadius) forKeyPath:@"filters.wxgMenuBlur.inputRadius"];} @catch(__unused NSException *e) {}
            }
        }else if(_dotBlurred[i]) {
            dot.filters=nil;_dotBlurred[i]=NO;
        }
    }
    self.hidden=!anyVisible;
    [CATransaction commit];
}
@end

// Weak proxy so CADisplayLink never retains WXGDecorations.
@interface WXGMenuLinkProxy : NSObject
@property(nonatomic,weak) WXGDecorations *target;
@end
@interface WXGDecorations (MenuTick)
- (void)menuTick:(CADisplayLink *)link;
@end
@implementation WXGMenuLinkProxy
- (void)tick:(CADisplayLink *)link {
    WXGDecorations *t=_target;
    if(!t){[link invalidate];return;}
    [t menuTick:link];
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
@property(nonatomic) NSUInteger exitToken;
@property(nonatomic,strong) NSMutableArray<WXGMenuRow *> *rows;
@property(nonatomic,weak) WXGSurface *plusSurface;
@property(nonatomic,weak) UIView *menuParent;               // where the glass lives: the host's superview (WeChat moves, fades and hides the host itself when it closes it)
@property(nonatomic,weak) UIControl *plusControl;
@property(nonatomic) CGRect lastPlus;                       // the "+" as last found, in the menu parent's coordinates
@property(nonatomic) CFTimeInterval plusSearchedAt,openAt,exitAt,partsSince,lastPlaced,lastNudge;
@property(nonatomic) NSUInteger entrances,exits,tickRetries;
@property(nonatomic) BOOL watching;                         // a layout the observer asked for (not one WeChat did)
@end
@implementation WXGDecoration
// FIX116 B / R24: clean up only this entry's own row views on dealloc; NEVER touch
// the shared "+" button here (another MainFrameActionFloatView may already own it).
- (void)dealloc {
    NSArray<WXGMenuRow *> *rows=_rows;
    if(!rows.count)return;
    void (^remove)(void)=^{
        for(WXGMenuRow *row in rows)for(WXGSurface *s in @[row.icon,row.capsule]){s.active=NO;s.hidden=YES;[s removeFromSuperview];}
    };
    if(NSThread.isMainThread)remove();else dispatch_async(dispatch_get_main_queue(),remove);
}
@end

@interface WXGDecorations ()
@property(nonatomic,strong) NSHashTable<WXGDecoration *> *entries;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSArray *> *dumps;   // FIX114 Z: each kind's last menu, as it is made
@property(nonatomic) NSUInteger mounts,reuses;
// R24: single-owner, single-clock home "+" menu animation state.
@property(nonatomic,strong) WXGDecoration *activeHomeMenu;
@property(nonatomic,strong) WXGMenuInkOverlayView *sharedInkOverlay;
@property(nonatomic,strong) CADisplayLink *menuLink;
@property(nonatomic) double menuProgress,menuTarget,menuSpeed,menuStagger;
@property(nonatomic) CGFloat settledMenuGap;
@property(nonatomic) CFTimeInterval menuLastTime;
@property(nonatomic) NSUInteger menuToken;
- (void)reassertVisiblePaint;
- (void)placeCapsuleMenu:(WXGDecoration *)entry items:(NSArray<UIView *> *)items;
- (void)watchCapsuleMenu:(WXGDecoration *)entry;
- (void)hideRows:(WXGDecoration *)entry remove:(BOOL)remove;
- (void)beginExit:(WXGDecoration *)entry;
- (void)playEntrance:(WXGDecoration *)entry;
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
static CGRect WXGMenuUnshiftedRectIn(UIView *v,UIView *root) {
    if(!v || !root)return CGRectNull;
    CGRect r=v.bounds;
    if(v==root)return r;
    if(![v isDescendantOfView:root])return [v convertRect:r toView:root];
    for(UIView *p=v;p && p!=root;p=p.superview) {
        if(!p.superview)return [v convertRect:v.bounds toView:root];
        CGPoint ap=p.layer.anchorPoint;CGSize sz=p.bounds.size;
        r.origin.x+=p.center.x-ap.x*sz.width-p.bounds.origin.x;
        r.origin.y+=p.center.y-ap.y*sz.height-p.bounds.origin.y;
    }
    return r;
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
static void WXGMenuSetLayerBlur(CALayer *layer,double radius) {
    if(!layer)return;
    if(radius<=.15) {
        if(layer.filters.count)layer.filters=nil;
        return;
    }
    if(layer.filters.count) {
        @try {[layer setValue:@(radius) forKeyPath:@"filters.wxgMenuBlur.inputRadius"];return;} @catch(__unused NSException *e) {}
    }
    id f=WXGMenuMakeBlurFilter(radius);
    if(f)layer.filters=@[f];
}

@implementation WXGDecorations
+ (instancetype)shared {
    static WXGDecorations *manager;static dispatch_once_t once;
    dispatch_once(&once,^{
        manager=[self new];manager.entries=[NSHashTable weakObjectsHashTable];
        manager.menuSpeed=1.;manager.menuStagger=.045;
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
    // Also watch activeHomeMenu if WeChat already dropped its weak host reference while open.
    if(_activeHomeMenu && _activeHomeMenu.phase==WXGMenuPhaseOpen && !_activeHomeMenu.host.window && !_activeHomeMenu.applying) {
        [self beginExit:_activeHomeMenu];
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
        CGRect r=WXGMenuUnshiftedRectIn(item,parent),was=row.itemFrame;
        if(CGRectIsNull(r))continue;
        CGFloat d=MAX(MAX(0.,r.origin.y-was.origin.y),MAX(fabs(r.size.width-was.size.width),fabs(r.size.height-was.size.height)));
        farthest=MAX(farthest,d);
    }
    BOOL moved=farthest>.5,open=entry.phase==WXGMenuPhaseOpen;
    // R25: only treat downward row collapse as WeChat closing once settled (>0.45s after open).
    if(open && entry.entranceDone && now-entry.openAt>.45 && farthest>16){[self beginExit:entry];return;}
    BOOL stale=entry.blockReopen && now-entry.exitAt>.25 && WXGMenuAlpha(body)>=.95;   // (still on screen after exit: open again)
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
- (WXGMenuInkOverlayView *)ensureSharedInkOverlayInParent:(UIView *)parent {
    if(!parent)return nil;
    if(!_sharedInkOverlay)_sharedInkOverlay=[WXGMenuInkOverlayView new];
    WXGMenuInkOverlayView *ink=_sharedInkOverlay;
    if(ink.superview!=parent){[ink removeFromSuperview];[parent addSubview:ink];}
    ink.frame=parent.bounds;
    ink.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    ink.layer.zPosition=20000;
    [parent bringSubviewToFront:ink];
    return ink;
}
- (NSArray<NSValue *> *)drawnIconTargets:(WXGDecoration *)entry {
    NSMutableArray<NSValue *> *out=[NSMutableArray array];
    for(WXGMenuRow *row in entry.rows) {
        if(!row.drawn)continue;
        [out addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(row.iconRect),CGRectGetMidY(row.iconRect))]];
    }
    return out;
}
- (void)stopMenuLink {
    if(_menuLink){[_menuLink invalidate];_menuLink=nil;}
}
- (void)ensureMenuLinkForWindow:(UIWindow *)window {
    if(_menuLink)return;
    WXGMenuLinkProxy *proxy=[WXGMenuLinkProxy new];proxy.target=self;
    _menuLink=[CADisplayLink displayLinkWithTarget:proxy selector:@selector(tick:)];
    WXGConfigureDisplayLink(_menuLink,window.screen?:UIScreen.mainScreen);
    [_menuLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _menuLastTime=CACurrentMediaTime();
}
- (WXGSurface *)resolveHomePlusFor:(WXGDecoration *)entry {
    UIView *parent=entry.menuParent?:entry.host.superview;
    UIWindow *win=entry.host.window?:parent.window?:_source.window;
    WXGSurface *plus=[WXGIntegrationHost.shared homePlusSurfaceInWindow:win];
    if(!plus && entry.plusSurface.window)plus=entry.plusSurface;
    if(plus)entry.plusSurface=plus;
    return plus;
}
// R24: single deterministic frame renderer for the entire "+" trigger, flying
// ink dots, circular glass icons, and text capsules at progress p in [0, 1].
- (void)applyHomeMenuProgress:(double)p {
    WXGDecoration *entry=_activeHomeMenu;
    p=WXGMenuClamp(p,0.,1.);
    BOOL calm=UIAccessibilityIsReduceMotionEnabled();
    WXGSurface *plus=entry?[self resolveHomePlusFor:entry]:(_source.window?[WXGIntegrationHost.shared homePlusSurfaceInWindow:_source.window]:nil);
    if(!entry) {
        [_sharedInkOverlay hideAll];
        [plus setHomePlusProgress:0. dotsHidden:NO];
        return;
    }
    NSArray<NSValue *> *targets=[self drawnIconTargets:entry];
    int n=(int)targets.count;
    if(n>=1 && n<=WXGMenuMaxParticles)[plus setHomePlusDotCount:n];
    BOOL dotsHidden=(p>.0001) && (!calm || p>=.9999);
    [plus setHomePlusProgress:p dotsHidden:dotsHidden];

    UIView *parent=entry.menuParent?:entry.host.superview;
    if(!calm && parent && parent.window && n>0 && p>.0001 && p<.9999) {
        CGRect plusRect=[self plusRectFor:entry parent:parent];
        WXGMenuInkOverlayView *ink=[self ensureSharedInkOverlayInParent:parent];
        [ink renderProgress:p count:n stagger:_menuStagger plusRect:plusRect targets:targets];
    }else {
        [_sharedInkOverlay hideAll];
    }

    int idx=0;
    BOOL settledOpen=(p>=.9999);
    BOOL settledClosed=(p<=.0001);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(WXGMenuRow *row in entry.rows) {
        if(!row.drawn)continue;
        int curIdx=idx++;
        BOOL hasIcon=row.icon.iconView.image!=nil;
        BOOL hasTitle=row.capsule.label.text.length>0;
        if(hasIcon) {
            WXGMenuRowPose ip=calm
                ?(WXGMenuRowPose){p,1.,1.,0.,0.,0.}
                :WXGMenuRowIconForProgress(curIdx,n>0?n:WXGMenuParticleCount,p,_menuStagger);
            BOOL vis=!settledClosed && ip.alpha>.005;
            row.icon.hidden=!vis;
            row.icon.active=vis;
            if(vis) {
                row.icon.layer.opacity=(float)(settledOpen?1.:ip.alpha);
                row.icon.layer.transform=settledOpen?CATransform3DIdentity:CATransform3DMakeScale((CGFloat)ip.scaleX,(CGFloat)ip.scaleY,1.);
                WXGMenuSetLayerBlur(row.icon.iconView.layer,(settledOpen || calm)?0.:ip.blurRadius);
            }else {
                row.icon.layer.opacity=0.f;
                row.icon.layer.transform=CATransform3DIdentity;
                WXGMenuSetLayerBlur(row.icon.iconView.layer,0.);
            }
        }else {
            row.icon.hidden=YES;row.icon.active=NO;
            WXGMenuSetLayerBlur(row.icon.iconView.layer,0.);
        }
        if(hasTitle) {
            double halfW=row.capsuleRect.size.width*.5;
            WXGMenuRowPose cp=calm
                ?(WXGMenuRowPose){p,1.,1.,0.,0.,0.}
                :WXGMenuRowCapsuleForProgress(curIdx,n>0?n:WXGMenuParticleCount,p,_menuStagger,halfW);
            BOOL vis=!settledClosed && cp.alpha>.005;
            row.capsule.hidden=!vis;
            row.capsule.active=vis;
            if(vis) {
                row.capsule.layer.opacity=(float)(settledOpen?1.:cp.alpha);
                row.capsule.layer.transform=settledOpen
                    ?CATransform3DIdentity
                    :CATransform3DConcat(CATransform3DMakeScale((CGFloat)cp.scaleX,(CGFloat)cp.scaleY,1.),
                                         CATransform3DMakeTranslation((CGFloat)cp.dx,0.,0.));
            }else {
                row.capsule.layer.opacity=0.f;
                row.capsule.layer.transform=CATransform3DIdentity;
            }
        }else {
            row.capsule.hidden=YES;row.capsule.active=NO;
        }
    }
    [CATransaction commit];
}
- (void)finishActiveHomeMenuClose {
    WXGDecoration *entry=_activeHomeMenu;
    [self stopMenuLink];
    _menuProgress=0.;_menuTarget=0.;
    [_sharedInkOverlay hideAll];
    WXGSurface *plus=entry?[self resolveHomePlusFor:entry]:(_source.window?[WXGIntegrationHost.shared homePlusSurfaceInWindow:_source.window]:nil);
    [plus setHomePlusProgress:0. dotsHidden:NO];
    if(entry) {
        entry.phase=WXGMenuPhaseClosed;
        for(WXGMenuRow *row in entry.rows)for(WXGSurface *s in @[row.icon,row.capsule]) {
            s.layer.transform=CATransform3DIdentity;s.layer.opacity=0.f;
            WXGMenuSetLayerBlur(s.iconView.layer,0.);
            s.active=NO;s.hidden=YES;
        }
    }
    _activeHomeMenu=nil;
}
- (void)menuTick:(CADisplayLink *)link {
    (void)link;
    WXGDecoration *entry=_activeHomeMenu;
    UIView *parent=entry.menuParent?:entry.host.superview;
    if(!entry || !parent || !parent.window) {
        [self finishActiveHomeMenuClose];
        return;
    }
    CFTimeInterval now=CACurrentMediaTime();
    double dt=_menuLastTime>0.?WXGMenuClamp(now-_menuLastTime,0.,.05):(1./120.);
    _menuLastTime=now;
    double dur=_menuTarget>_menuProgress?WXGMenuOpenDuration(_menuSpeed):WXGMenuCloseDuration(_menuSpeed);
    if(dur<.05)dur=.05;
    if(_menuTarget>_menuProgress) {
        _menuProgress=MIN(_menuTarget,_menuProgress+dt/dur);
    }else if(_menuTarget<_menuProgress) {
        _menuProgress=MAX(_menuTarget,_menuProgress-dt/dur);
    }
    [self applyHomeMenuProgress:_menuProgress];
    if(fabs(_menuProgress-_menuTarget)<=1e-5) {
        _menuProgress=_menuTarget;
        if(_menuTarget<=0.) {
            [self finishActiveHomeMenuClose];
        }else {
            [self stopMenuLink];
            [self applyHomeMenuProgress:1.];
        }
    }
}
- (void)dismissMenuAutomatically:(WXGDecoration *)entry {
    if(!entry || entry!=_activeHomeMenu || entry.phase!=WXGMenuPhaseOpen)return;
    UIView *host=entry.host;
    if(host && host.window) {
        for(NSString *name in @[@"hide",@"dismiss",@"onTapBackground",@"onTapBg",@"hideMenu"]) {
            SEL sel=NSSelectorFromString(name);
            if([host respondsToSelector:sel]) {
                ((void (*)(id,SEL))objc_msgSend)(host,sel);
                return;
            }
        }
    }
    UIControl *btn=entry.plusSurface.original?:entry.plusControl;
    if(btn && btn.window && WXGCanForward(btn)) {
        [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }
    [self beginExit:entry];
}
- (void)hideRows:(WXGDecoration *)entry remove:(BOOL)remove {
    BOOL ownsPlus=(entry && entry==_activeHomeMenu);
    if(ownsPlus) {
        [self stopMenuLink];
        _menuProgress=0.;_menuTarget=0.;
        [_sharedInkOverlay hideAll];
        if(remove){[_sharedInkOverlay removeFromSuperview];_sharedInkOverlay=nil;}
        [[self resolveHomePlusFor:entry] setHomePlusProgress:0. dotsHidden:NO];
        _activeHomeMenu=nil;
    }
    if(remove)entry.plusSurface=nil;
    for(WXGMenuRow *row in entry.rows) {
        for(WXGSurface *s in @[row.icon,row.capsule]) {
            s.layer.transform=CATransform3DIdentity;s.layer.opacity=1.f;
            WXGMenuSetLayerBlur(s.iconView.layer,0.);
            s.active=NO;s.hidden=YES;s.glass.backdropExclusions=@[];
            if(remove)[s removeFromSuperview];
        }
        if(remove && row.observer){[row.observer.view removeGestureRecognizer:row.observer];row.observer=nil;}
    }
    if(remove)entry.rows=nil;
    entry.rowsReady=NO;
}
// FIX116 B / R25: compare unshifted (transform-invariant) row frames. Ignore
// transient X/upward settle shifts so popup settle never triggers a false exit.
- (BOOL)rowsMovedOf:(WXGDecoration *)entry items:(NSArray<UIView *> *)items parent:(UIView *)parent limit:(CGFloat)limit {
    NSUInteger n=MIN(entry.rows.count,items.count);
    for(NSUInteger i=0;i<n;i++) {
        WXGMenuRow *row=entry.rows[i];UIView *item=items[i];
        if(row.item!=item || !row.drawn)continue;
        CGRect r=WXGMenuUnshiftedRectIn(item,parent),was=row.itemFrame;
        if(CGRectIsNull(r))continue;
        if(r.origin.y-was.origin.y>limit || fabs(r.size.width-was.size.width)>limit || fabs(r.size.height-was.size.height)>limit)return YES;
    }
    return NO;
}
// FIX116 B / R24: reverse progress smoothly from its current value back to 0.
// Only the active home menu drives the shared "+" trigger and ink overlay.
- (void)beginExit:(WXGDecoration *)entry {
    if(!entry || entry.phase!=WXGMenuPhaseOpen)return;
    entry.phase=WXGMenuPhaseExiting;entry.entranceDone=NO;++entry.exits;entry.exitAt=CACurrentMediaTime();
    entry.blockReopen=entry.host.window && entry.body && WXGMenuShown(entry.body);
    ++entry.exitToken;
    if(entry!=_activeHomeMenu) {
        entry.phase=WXGMenuPhaseClosed;
        for(WXGMenuRow *row in entry.rows)for(WXGSurface *s in @[row.icon,row.capsule]) {
            s.layer.transform=CATransform3DIdentity;WXGMenuSetLayerBlur(s.iconView.layer,0.);
            s.active=NO;s.hidden=YES;
        }
        return;
    }
    ++_menuToken;
    _menuSpeed=WXGMenuClamp([WXGConfig.shared extraNumber:@"homeMenuSpeed"],.5,2.);
    _menuStagger=WXGMenuClamp([WXGConfig.shared extraNumber:@"homeMenuStagger"],0,80)/1000.0;
    _menuTarget=0.;
    if(UIAccessibilityIsReduceMotionEnabled() || _menuProgress<=.0001) {
        [self finishActiveHomeMenuClose];
        return;
    }
    UIWindow *win=entry.host.window?:entry.menuParent.window?:_source.window;
    [self applyHomeMenuProgress:_menuProgress];
    [self ensureMenuLinkForWindow:win];
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
    CGRect plus=[self plusRectFor:entry parent:parent];
    if(entry.phase==WXGMenuPhaseOpen) {
        if(entry.entranceDone) {
            if(!items.count || (same && now-entry.openAt>.45 && [self rowsMovedOf:entry items:items parent:parent limit:16])){[self beginExit:entry];return;}
        }
    }else {
        if(entry.blockReopen) {
            CGRect f0=items.count?WXGMenuUnshiftedRectIn(items.firstObject,parent):CGRectNull;
            CGFloat g0=CGRectIsNull(f0)?999.:CGRectGetMinY(f0)-CGRectGetMaxY(plus);
            BOOL settledAgain=g0>=-2. && g0<=28. && WXGMenuAlpha(body)>=.95 && now-entry.exitAt>.25;
            BOOL again=items.count && WXGMenuHasParts(items) &&
                (!same || ![self rowsMovedOf:entry items:items parent:parent limit:3] || settledAgain);
            if(!again)return;
            entry.blockReopen=NO;
        }
        if(!items.count)return;
        entry.phase=WXGMenuPhaseOpen;entry.openAt=now;entry.entranceDone=NO;++entry.exitToken;entry.tickRetries=0;
    }
    if(!items.count){[self hideRows:entry remove:YES];entry.phase=WXGMenuPhaseClosed;return;}
    entry.menuParent=parent;
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
    NSMutableArray<NSValue *> *frames=[NSMutableArray array];
    CGFloat minHeight=CGFLOAT_MAX,pitch=CGFLOAT_MAX,lastMid=0;BOOL haveLast=NO;
    for(UIView *item in items) {
        CGRect r=WXGMenuUnshiftedRectIn(item,parent);
        if(CGRectIsNull(r) || r.size.height<10)r=[item convertRect:item.bounds toView:parent];
        if(item.bounds.size.height>=20)r.size.height=item.bounds.size.height;
        [frames addObject:[NSValue valueWithCGRect:r]];
        minHeight=MIN(minHeight,r.size.height);
        if(haveLast && CGRectGetMidY(r)-lastMid>1)pitch=MIN(pitch,CGRectGetMidY(r)-lastMid);
        lastMid=CGRectGetMidY(r);haveLast=YES;
    }
    CGFloat rowHeight=pitch<CGFLOAT_MAX?MIN(minHeight,pitch):minHeight;
    CGFloat rowPitch=pitch<CGFLOAT_MAX && pitch>=24 && pitch<=80?pitch:MAX(44.,rowHeight);
    // R25: guard against WeChat's mid-animation popup displacement on rapid tap
    // (seen at y=214 instead of y=105). When row0 is sane below "+", learn its
    // gap; when displaced, anchor deterministically below "+".
    if(frames.count) {
        CGRect f0=frames.firstObject.CGRectValue;
        CGFloat rawGap=CGRectGetMinY(f0)-CGRectGetMaxY(plus);
        if(rawGap>=-2. && rawGap<=28.) {
            _settledMenuGap=MAX(2.,rawGap);
        }else {
            CGFloat baseY=CGRectGetMaxY(plus)+(_settledMenuGap>0.?_settledMenuGap:6.);
            for(NSUInteger i=0;i<frames.count;i++) {
                CGRect f=frames[i].CGRectValue;
                f.origin.y=baseY+(CGFloat)i*rowPitch;
                frames[i]=[NSValue valueWithCGRect:f];
            }
        }
    }
    WXGMenuMetrics m=WXGMenuMetricsFor([WXGConfig.shared extraNumber:@"homeMenuIconSize"],rowHeight);
    UIFont *font=[UIFont systemFontOfSize:m.fontSize weight:UIFontWeightSemibold];
    double minX=parent.bounds.origin.x+parent.safeAreaInsets.left+10,centreX=CGRectGetMidX(plus);
    UIView *source=_source?:WXGContentSourceForView(host);
    BOOL animatingOpen=entry.entranceDone && entry==_activeHomeMenu && _menuProgress<.9999;
    NSUInteger drawn=0;
    for(NSUInteger i=0;i<entry.rows.count;i++) {
        WXGMenuRow *row=entry.rows[i];UIView *item=items[i];CGRect r=frames[i].CGRectValue;
        UIImageView *iconView=nil;UILabel *label=nil;WXGMenuParts(item,&iconView,&label);
        NSString *title=label.text;BOOL hasIcon=iconView.image!=nil,hasTitle=title.length>0;
        row.itemFrame=r;row.nativeIcon=iconView;row.nativeLabel=label;row.slotDistance=CGRectGetMidY(r)-CGRectGetMidY(plus);
        row.drawn=hasIcon || hasTitle;
        if(!row.drawn){row.icon.hidden=YES;row.capsule.hidden=YES;row.icon.active=NO;row.capsule.active=NO;continue;}
        ++drawn;
        if(iconView)[entry.states conceal:iconView];
        if(label)[entry.states conceal:label];
        [entry.states conceal:item];
        CGFloat textWidth=hasTitle?ceil([title sizeWithAttributes:@{NSFontAttributeName:font}].width):0;
        WXGMenuRowBoxes b=WXGMenuRowBoxesFor(CGRectGetMidY(r),centreX,textWidth,m,minX);
        CGRect iconRect=CGRectMake(WXGMenuSnap(b.icon.x,parent),WXGMenuSnap(b.icon.y,parent),b.icon.w,b.icon.h);
        CGRect capsuleRect=CGRectMake(WXGMenuSnap(b.capsule.x,parent),WXGMenuSnap(b.capsule.y,parent),b.capsule.w,b.capsule.h);
        BOOL iconMoved=!CGRectEqualToRect(row.iconRect,iconRect) && (fabs(row.iconRect.origin.x-iconRect.origin.x)>2. || fabs(row.iconRect.origin.y-iconRect.origin.y)>2. || fabs(row.iconRect.size.width-iconRect.size.width)>2. || fabs(row.iconRect.size.height-iconRect.size.height)>2.);
        BOOL capMoved=!CGRectEqualToRect(row.capsuleRect,capsuleRect) && (fabs(row.capsuleRect.origin.x-capsuleRect.origin.x)>2. || fabs(row.capsuleRect.origin.y-capsuleRect.origin.y)>2. || fabs(row.capsuleRect.size.width-capsuleRect.size.width)>2. || fabs(row.capsuleRect.size.height-capsuleRect.size.height)>2.);
        for(WXGSurface *s in @[row.icon,row.capsule]){s.glass.sourceView=source;s.glass.backdropExclusions=@[host];s.glass.shadowClipRoot=parent;}
        if(hasIcon) {
            [row.icon setImage:iconView.image title:nil count:nil];
            if(!animatingOpen || row.icon.superview!=parent || iconMoved) {
                row.iconRect=iconRect;
                [row.icon placeMaterial:iconRect inParent:parent];
            }
        }else{row.iconRect=iconRect;row.icon.hidden=YES;row.icon.active=NO;}
        if(hasTitle) {
            [row.capsule setImage:nil title:title count:nil];
            if(![row.capsule.label.font isEqual:font]){row.capsule.label.font=font;[row.capsule setNeedsLayout];}
            if(!animatingOpen || row.capsule.superview!=parent || capMoved) {
                row.capsuleRect=capsuleRect;
                [row.capsule placeMaterial:capsuleRect inParent:parent];
            }
        }else{row.capsuleRect=capsuleRect;row.capsule.hidden=YES;row.capsule.active=NO;}
        row.observer.icon=row.icon;row.observer.capsule=row.capsule;
    }
    entry.rowsReady=drawn>0;entry.lastPlaced=now;
    if(!entry.rowsReady)return;
    if(!entry.entranceDone){entry.entranceDone=YES;++entry.entrances;[self playEntrance:entry];}
    else if(entry==_activeHomeMenu)[self applyHomeMenuProgress:_menuProgress];
}
// R24 single-clock expand: transfers exclusive ownership of the "+" trigger &
// ink overlay to `entry`, then advances unified progress p smoothly -> 1.0
// (reversing seamlessly from current p if a previous menu was mid-close!).
- (void)playEntrance:(WXGDecoration *)entry {
    WXGDecoration *prev=_activeHomeMenu;
    if(prev && prev!=entry) {
        // Retire the previous menu's rows cleanly WITHOUT resetting the shared "+" button.
        prev.phase=WXGMenuPhaseClosed;prev.entranceDone=NO;
        for(WXGMenuRow *row in prev.rows)for(WXGSurface *s in @[row.icon,row.capsule]) {
            s.layer.transform=CATransform3DIdentity;WXGMenuSetLayerBlur(s.iconView.layer,0.);
            s.active=NO;s.hidden=YES;[s removeFromSuperview];
        }
        prev.rowsReady=NO;
    }
    _activeHomeMenu=entry;
    NSUInteger openToken=++_menuToken;
    _menuSpeed=WXGMenuClamp([WXGConfig.shared extraNumber:@"homeMenuSpeed"],.5,2.);
    _menuStagger=WXGMenuClamp([WXGConfig.shared extraNumber:@"homeMenuStagger"],0,80)/1000.0;
    _menuTarget=1.;

    int drawnCount=(int)[self drawnIconTargets:entry].count;
    WXGSurface *plus=[self resolveHomePlusFor:entry];
    if(drawnCount>=1 && drawnCount<=WXGMenuMaxParticles) {
        [plus setHomePlusDotCount:drawnCount];
        NSUserDefaults *ud=NSUserDefaults.standardUserDefaults;
        if([ud integerForKey:@"WXGHomeMenuLastItemCount"]!=drawnCount)[ud setInteger:drawnCount forKey:@"WXGHomeMenuLastItemCount"];
    }

    if(UIAccessibilityIsReduceMotionEnabled()) {
        [self stopMenuLink];
        _menuProgress=1.;
        [self applyHomeMenuProgress:1.];
    }else {
        UIWindow *win=entry.host.window?:entry.menuParent.window?:_source.window;
        [self applyHomeMenuProgress:_menuProgress];
        [self ensureMenuLinkForWindow:win];
    }

    // Optional auto-close timer (seconds after menu opens).
    CGFloat autoClose=WXGConfig.shared.homeMenuAutoClose;
    if(autoClose>=.5) {
        __weak WXGDecoration *weakEntry=entry;
        __weak WXGDecorations *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(autoClose*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            WXGDecorations *s=weakSelf;WXGDecoration *later=weakEntry;
            if(s && later && s.menuToken==openToken && s.activeHomeMenu==later && later.phase==WXGMenuPhaseOpen)[s dismissMenuAutomatically:later];
        });
    }
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
    [self finishActiveHomeMenuClose];
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
    WXGSurface *plus=_activeHomeMenu.plusSurface;
    if(!plus && _source.window)plus=[WXGIntegrationHost.shared homePlusSurfaceInWindow:_source.window];
    NSInteger savedCount=[NSUserDefaults.standardUserDefaults integerForKey:@"WXGHomeMenuLastItemCount"];
    return @{@"mounts":@(_mounts),@"reuses":@(_reuses),@"hosts":rows,@"lastMenus":_dumps?:@{},
             @"plusDotCountSaved":@(savedCount),@"menuProgress":@(round(_menuProgress*1000.)/1000.),@"menuTarget":@(_menuTarget),
             @"plusTrigger":plus?[plus evidence][@"plusTrigger"]?:@{}:@{}};   // FIX114 Z
}
@end
