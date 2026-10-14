#import "WXGIntegration.h"
#import "WXGBubbleRules.h"

/* FIX82: liquid chat bubbles. A WeChat text message (TextMessageCellView)
   draws its bubble as a YYAsyncImageView inside a body view that also holds
   the RichTextView; the body's bounds are the bubble without its tail. The
   same body gets one lightweight glass (as the settings cards: one backdrop,
   no Metal canvas) as its lowest subview, tinted with the bubble colour
   (FIX83: weakening toward the outline like the other glass's material) and
   shaped by WXGBubbleRules.h (FIX85: its own optics and rim, the "气泡"
   range of the glass settings); the native image is hidden (alpha, restorable)
   and kept hidden before every commit, also when WeChat swaps in another
   image view (long press, selection). The glass's optics and rim are those of
   the bubbles' own (FIX85; before: the "other glass"). The way to find the body is the one the user's MixBubble
   uses. */

@interface WXGBubbleGlass : UIView
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic) BOOL outgoing;
@property(nonatomic) CGFloat radius;
- (void)tick:(CFTimeInterval)time;
@end
@implementation WXGBubbleGlass {
    NSUInteger _appliedRevision;
    UIUserInterfaceStyle _appliedStyle;
    BOOL _appliedOutgoing,_dirty;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=NO;
        self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        _glass=[[WXGGlassView alloc]initWithFrame:CGRectZero];
        _glass.overlayHidden=YES;_glass.userInteractionEnabled=NO;
        // FIX85: the bubbles' own optics and rim (the "气泡" range); one
        // backdrop unless 完整玻璃 is on.
        _glass.bubbleSurface=YES;_glass.lightweight=!WXGConfig.shared.bubbleFullGlass;
        [self addSubview:_glass];_dirty=YES;
    }return self;
}
- (UIColor *)tint {
    WXGConfig *c=WXGConfig.shared;BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    return WXGColor(dark?(_outgoing?c.darkBubbleOutgoingHex:c.darkBubbleIncomingHex):(_outgoing?c.bubbleOutgoingHex:c.bubbleIncomingHex));
}
// FIX83: the tint weakens toward the outline over the bubble page's range.
- (CGFloat)tintFade {WXGConfig *c=WXGConfig.shared;return c.bubbleEdgeFadeEnabled?c.bubbleEdgeFade:0;}
- (void)setOutgoing:(BOOL)outgoing {if(_outgoing==outgoing)return;_outgoing=outgoing;_dirty=YES;_glass.veilOverride=[self tint];}
- (void)setRadius:(CGFloat)radius {if(fabs(_radius-radius)<.01)return;_radius=radius;_dirty=YES;[self setNeedsLayout];}
- (void)didMoveToWindow {[super didMoveToWindow];_glass.active=self.window!=nil;_dirty=YES;}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {[super traitCollectionDidChange:previous];_dirty=YES;_glass.veilOverride=[self tint];}
- (void)layoutSubviews {
    [super layoutSubviews];
    _dirty=YES;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        CGRect b=self.bounds;
        self.glass.frame=CGRectInset(b,-WXGCanvasPaddingX,-WXGCanvasPaddingY);
        self.glass.glassRect=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,b.size.width,b.size.height);
        // 0 would mean a capsule to the glass; a square corner is 0.5 pt.
        self.glass.maximumCornerRadius=MAX(.5,MIN(self.radius,MIN(b.size.width,b.size.height)*.5));
        if(!self.glass.veilOverride)self.glass.veilOverride=[self tint];
        self.glass.veilOverrideFade=[self tintFade];
        [self.glass layoutIfNeeded];
        [CATransaction commit];
    }];
}
// Only a new, resized, recoloured or re-themed bubble does any work; the
// render server keeps the glass live in between.
- (void)tick:(CFTimeInterval)time {
    if(!self.window || self.hidden)return;
    UIUserInterfaceStyle style=self.traitCollection.userInterfaceStyle;
    if(!_dirty && _appliedRevision==WXGConfigRevision() && _appliedStyle==style && _appliedOutgoing==_outgoing)return;
    _glass.veilOverride=[self tint];_glass.veilOverrideFade=[self tintFade];
    BOOL lean=!WXGConfig.shared.bubbleFullGlass;
    if(_glass.lightweight!=lean){_glass.lightweight=lean;[_glass invalidateBackdrop];[_glass setNeedsLayout];}
    [self layoutIfNeeded];[_glass layoutIfNeeded];
    if(!WXGPresentedVisible(_glass))return;   // stays stale until it is on screen
    [_glass tick:time];
    _appliedRevision=WXGConfigRevision();_appliedStyle=style;_appliedOutgoing=_outgoing;_dirty=NO;
}
@end

static char WXGBubbleEntryKey;
@interface WXGBubbleEntry : NSObject
@property(nonatomic,weak) UIView *host,*body,*image,*rich;
@property(nonatomic) NSUInteger children;   // the body's direct subviews when last scanned
@property(nonatomic,strong) WXGBubbleGlass *view;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic) BOOL applying;
@end
@implementation WXGBubbleEntry
@end

static BOOL WXGBubbleClassContains(UIView *view,NSString *fragment) {
    return [NSStringFromClass(view.class) rangeOfString:fragment options:NSCaseInsensitiveSearch].location!=NSNotFound;
}
static BOOL WXGBubbleImageView(UIView *view) {return !WXGIsPluginView(view) && WXGBubbleClassContains(view,@"YYAsyncImageView");}
// The body's direct subviews by identity (no class names): a rescan only
// when WeChat adds, removes or swaps one.
static NSUInteger WXGBubbleChildren(UIView *body) {
    NSUInteger key=body.subviews.count*0x9E3779B1u;
    for(UIView *child in body.subviews)key=(key^(NSUInteger)(__bridge void *)child)*1099511628211ull;
    return key;
}
static void WXGBubbleCollectBody(UIView *node,NSUInteger depth,UIView *__strong *best,CGFloat *bestArea) {
    if(!node || depth>5 || WXGIsPluginView(node))return;
    BOOL rich=NO,image=NO;
    for(UIView *child in node.subviews) {
        if(!rich && WXGBubbleClassContains(child,@"RichTextView"))rich=YES;
        if(!image && WXGBubbleImageView(child))image=YES;
    }
    CGRect b=node.bounds;
    if(rich && image && !node.hidden && node.alpha>.01 && b.size.width>8 && b.size.height>8) {
        CGFloat area=b.size.width*b.size.height;
        if(!*best || area<*bestArea){*best=node;*bestArea=area;}
    }
    for(UIView *child in node.subviews)WXGBubbleCollectBody(child,depth+1,best,bestArea);
}
// The smallest view (five levels down at most) that directly holds both the
// RichTextView and the bubble image: some WeChat builds wrap it in a taller
// container that also holds the time header.
static UIView *WXGBubbleBody(UIView *host) {
    UIView *best=nil;CGFloat area=CGFLOAT_MAX;
    for(UIView *child in host.subviews)WXGBubbleCollectBody(child,0,&best,&area);
    return best;
}
static BOOL WXGBubbleOutgoing(UIView *host,UIView *image) {
    id model=WXGRead(host,@"m_viewModel")?:WXGRead(host,@"_viewModel");
    SEL selector=NSSelectorFromString(@"isSender");
    if(model && [model respondsToSelector:selector]) {
        const char *type=[model methodSignatureForSelector:selector].methodReturnType;
        if(type && (type[0]=='B' || type[0]=='c'))return ((BOOL(*)(id,SEL))objc_msgSend)(model,selector);
    }
    return WXGBubbleOutgoingFromImage(image.frame.origin.x);
}

@implementation WXGBubbles {
    NSHashTable<WXGBubbleEntry *> *_entries;
    double _reference;
    NSUInteger _mounts,_layouts,_restores;
}
+ (instancetype)shared {
    static WXGBubbles *manager;static dispatch_once_t once;
    dispatch_once(&once,^{
        manager=[self new];
        // Before every commit: WeChat may show its bubble image again (or put
        // a new one in) outside any layout we see; hide it before it is drawn.
        __weak WXGBubbles *weakManager=manager;
        CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999800,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity activity){WXGPerfTimePluginWork(^{[weakManager reassert];});});   // FIX84: timed
        if(observer){CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);CFRelease(observer);}
    });
    return manager;
}
- (instancetype)init {if((self=[super init])){_entries=[NSHashTable weakObjectsHashTable];_reference=0;}return self;}
- (BOOL)wanted {return WXGPluginEnabled() && WXGPreferences.shared.bubbles && WXGEffectiveRenderMode()>=2;}
- (void)restoreEntry:(WXGBubbleEntry *)entry {
    [entry.states restore];[entry.view removeFromSuperview];entry.view.hidden=YES;
    entry.body=entry.image=entry.rich=nil;entry.children=0;++_restores;
}
// Every bubble image directly in the body (WeChat may add a second one for a
// long press or selection): hidden by alpha, restorably.
- (void)hideNativeIn:(WXGBubbleEntry *)entry {
    UIView *body=entry.body;NSUInteger children=WXGBubbleChildren(body);
    if(children==entry.children)return;
    entry.image=entry.rich=nil;
    for(UIView *child in body.subviews) {
        if(WXGBubbleImageView(child)){if(!entry.image)entry.image=child;[entry.states hide:child];}
        else if(!entry.rich && WXGBubbleClassContains(child,@"RichTextView"))entry.rich=child;
    }
    entry.children=children;
}
- (void)reassert {
    BOOL wanted=[self wanted];
    for(WXGBubbleEntry *entry in _entries) {
        if(!entry.host.window || !entry.body || entry.applying)continue;
        if(!wanted){[self restoreEntry:entry];continue;}
        @try {[self hideNativeIn:entry];[entry.states reapply];} @catch(__unused NSException *error) {}
    }
}
// The smallest one-line body on screen (WXGBubbleRules.h); kept while no
// one-line bubble is visible.
- (void)updateReference {
    double smallest=0;
    for(WXGBubbleEntry *entry in _entries) {
        UIView *body=entry.body;if(!body.window)continue;
        double h=body.bounds.size.height;
        if(WXGBubbleOneLine(h) && (smallest==0 || h<smallest))smallest=h;
    }
    if(smallest>0 && fabs(smallest-_reference)>.01) {
        _reference=smallest;
        for(WXGBubbleEntry *entry in _entries)if(entry.body.window) {
            CGSize size=entry.body.bounds.size;entry.view.radius=WXGBubbleRadius(size.width,size.height,_reference);
        }
    }
}
- (void)textCellLaidOut:(UIView *)host {
    if(!NSThread.isMainThread || !host)return;
    WXGBubbleEntry *entry=objc_getAssociatedObject(host,&WXGBubbleEntryKey);
    if(entry.applying || !host.window)return;
    if(![self wanted]){if(entry.body)[self restoreEntry:entry];return;}
    UIView *body=entry.body;
    if(!body || body.hidden || ![body isDescendantOfView:host])body=WXGBubbleBody(host);
    if(!body){if(entry.body)[self restoreEntry:entry];return;}
    if(!entry) {
        entry=[WXGBubbleEntry new];entry.host=host;entry.states=[WXGStateBag new];entry.view=[[WXGBubbleGlass alloc]initWithFrame:CGRectZero];
        objc_setAssociatedObject(host,&WXGBubbleEntryKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_entries addObject:entry];++_mounts;
    }
    entry.applying=YES;++_layouts;
    @try {
        if(entry.body!=body){[entry.states restore];entry.body=body;entry.children=0;}
        [self hideNativeIn:entry];
        UIView *image=entry.image,*rich=entry.rich;
        if(!image || !rich){[self restoreEntry:entry];return;}
        [entry.states clear:rich];   // its own background, if WeChat gives it one (never its text)
        [entry.states reapply];
        WXGBubbleGlass *view=entry.view;
        if(view.superview!=body || body.subviews.firstObject!=view)[body insertSubview:view atIndex:0];
        view.hidden=NO;
        view.outgoing=WXGBubbleOutgoing(host,image);
        [self updateReference];
        CGRect bounds=body.bounds;
        view.radius=WXGBubbleRadius(bounds.size.width,bounds.size.height,_reference);
        if(!CGRectEqualToRect(view.frame,bounds)) {
            [UIView performWithoutAnimation:^{[CATransaction begin];[CATransaction setDisableActions:YES];view.frame=bounds;[CATransaction commit];}];
        }
    } @catch(NSException *error) {
        WXGLog(@"液态气泡：%@",error.reason);[self restoreEntry:entry];
    } @finally {entry.applying=NO;}
}
- (void)tick:(CFTimeInterval)time {
    for(WXGBubbleEntry *entry in _entries)if(entry.host.window && entry.body && entry.view.superview)[entry.view tick:time];
}
- (void)applyConfiguration {
    if(![self wanted]){[self restore];return;}
    for(WXGBubbleEntry *entry in _entries)if(entry.host.window)[entry.host setNeedsLayout];
}
- (void)restore {for(WXGBubbleEntry *entry in _entries)if(entry.body)[self restoreEntry:entry];}
- (NSDictionary *)evidence {
    NSMutableArray *rows=[NSMutableArray array];NSUInteger shown=0;
    for(WXGBubbleEntry *entry in _entries) {
        if(!entry.host.window || !entry.body || !entry.view.superview)continue;
        ++shown;
        if(rows.count<8)[rows addObject:@{@"outgoing":@(entry.view.outgoing),@"radius":@(round(entry.view.radius*10)/10),
            @"size":@[@(round(entry.body.bounds.size.width*10)/10),@(round(entry.body.bounds.size.height*10)/10)],
            @"body":NSStringFromClass(entry.body.class),@"glassReady":@(entry.view.glass.ready)}];
    }
    return @{@"enabled":@([self wanted]),@"mounts":@(_mounts),@"layouts":@(_layouts),@"restores":@(_restores),@"onScreen":@(shown),
             @"oneLineReference":@(_reference),@"samples":rows};
}
@end
