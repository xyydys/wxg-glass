#import "WXGIntegration.h"
#import "WXGBackdropSample.h"

/* FIX107: more of WeChat in glass (the probe's captures, WeChat 8.0.73 / 8.0.78).
   Each element keeps WeChat's own view, actions and layout; only its paint is
   taken away (restorably, kept away before every commit) and a material-only
   glass (WXGSurface, the "other glass" settings) goes in its place, as the
   lowest subview of the painted view (or right above a button's background
   image view), so it moves, hides and fades with it:

   search  — search fields as capsules: WCSearchBar (home, 通讯录, settings:
             the white UIView in its stacks), WCWebSearchBar (the search page:
             the grey UIView), FavSearchBar (收藏: the bar itself), WeChat's
             Swift WCSearchTextField (表情搜索: its white sibling), and system
             UISearchBar fields (新的朋友: their background view) unless a
             WCSearchBar covers them;
   tile    — the plus panel's 8 AttachmentButtons: rounded squares with the
             radius of WeChat's own tile image, pressed with the button;
   key     — the emoji board's 发送 / 删除 (onTapSendButton / onTapDeleteButton):
             capsules; 发送 takes the colour of WeChat's background image for
             its state (green when there is something to send) as its tint;
   tab     — the emoji board's group strip: the selected group's white square
             (one per cell, WeChat hides all but the selected one);
   sheet   — the forward / share sheet (MMScrollActionSheetContainerView, the
             image viewer's and the article's "…" alike): one lightweight glass
             for its whole background instead of WeChat's blur, a stronger
             tint so its labels stay readable.

   FIX108 (the probe's TEST5 picks, WeChat 8.0.73, iOS 15.7):
   title   — the title in the title bar (首页“微信(n)”, 通讯录, 发现, 聊天信息, …):
             a capsule behind WeChat's own label(s), inside its title view
             (MFTitleView / MMTitleView, 1 pt wide, the labels around its
             centre), as tall as the plugin's title-bar buttons; a long or
             two-line title (a web page's) and one the host draws itself (the
             chat page) stay as they are. The photo picker's album title
             (MMDropableTitleView): its grey pill (the button's fill, radius
             16) becomes the glass, pressed with it;
   navButton — the title bar's buttons the host leaves native (web pages, pages
             presented over the tabs: the × of a link, the album, 收藏, 卡包,
             a link's “···”): a round glass (a capsule for a text button) behind
             WeChat's own icon, the size of the plugin's other title-bar glass.

   FIX108 B (review): a presented page's buttons decided from their own
   navigation (the host never takes a page under a cover as its route); the
   display link idles once nothing needs a tick (a title on every page kept it
   at the screen's rate); the title's rectangle cached on a cheap key; pixel,
   not point, rounding (only for computed rectangles); a glass already there is
   kept through a one-pass collapse; the dark glass for white ink follows the
   appearance; title-bar glass clamped like the host's in a short (landscape)
   bar and to the gap to the next button; a back button with a count gets a
   capsule around both.

   Render-server ("同步") mode only. The glass runs on its own display link
   while one of them is on screen (also on pages the host leaves native, the
   article's sheet), ticking a glass only while it is new, changed or pressed. */

typedef NS_ENUM(NSInteger,WXGLocalKind) {WXGLocalSearch,WXGLocalTile,WXGLocalKey,WXGLocalTab,WXGLocalSheet,WXGLocalTitle,WXGLocalNavButton};
static NSString *WXGLocalKindName(WXGLocalKind kind) {
    switch(kind) {
        case WXGLocalSearch:return @"search";
        case WXGLocalTile:return @"tile";
        case WXGLocalKey:return @"key";
        case WXGLocalTab:return @"tab";
        case WXGLocalSheet:return @"sheet";
        case WXGLocalTitle:return @"title";
        case WXGLocalNavButton:return @"navButton";
    }
    return @"?";
}
static const CGFloat WXGLocalSheetRadius=26;

@interface WXGLocalEntry : NSObject
@property(nonatomic) WXGLocalKind kind;
@property(nonatomic,weak) UIView *host;       // the hooked view that found it
@property(nonatomic,weak) UIView *anchor;     // the glass's parent
@property(nonatomic,weak) UIView *paint;      // the view whose paint went (may be the anchor)
@property(nonatomic,weak) UIView *below;      // the glass sits right above it (a button's background image view)
@property(nonatomic,weak) UIView *measure;    // the glass covers its bounds (in the anchor)
@property(nonatomic,weak) UIControl *button;  // pressed with it
@property(nonatomic,copy) CGRect (^frame)(void);   // FIX108: the glass's rectangle in the anchor, when no view's bounds give it
@property(nonatomic,copy) UIColor *(^ink)(void);   // FIX108 B: what is drawn on it (white: a dark glass)
@property(nonatomic) UIUserInterfaceStyle inkTraitStyle;
@property(nonatomic,strong) UIColor *lastInk;
@property(nonatomic) NSUInteger unseenTurns;   // FIX108 E: turns in a row with nothing shown under it
@property(nonatomic) BOOL recheckPending;       // FIX114 A: a look again is scheduled (the debounce must finish though nothing lays out)
@property(nonatomic,copy) CGFloat (^shown)(void);              // FIX109: how visible WeChat's own paint is (the group selection's)
@property(nonatomic,copy) CGFloat (^radiusFor)(CGSize size);   // FIX109: the radius setting, read again when the settings change
@property(nonatomic) NSUInteger radiusRevision;
@property(nonatomic) CFTimeInterval coldTick;                 // FIX109: last tick of a glass that has not drawn yet
@property(nonatomic,copy) CGRect (^titleMeasure)(UIColor **ink,CGFloat *shown);   // FIX109: a title's capsule, ink and visibility in one look
@property(nonatomic) NSUInteger hostShape,skins;   // FIX109: the search host's subviews when looked at, theme pictures hidden
@property(nonatomic,strong) NSHashTable<UIView *> *skinViews;
@property(nonatomic,copy) NSArray<NSString *> *bands;   // FIX113 F: the emoji search bar's band cleared around this field
@property(nonatomic,strong) WXGSurface *surface;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic) CGFloat radius;          // 0 = capsule
@property(nonatomic) CGFloat nativeRadius;    // WeChat's own (tiles: measured from its image; group selection: its layer)
@property(nonatomic) BOOL mounted,applying,send,tintKnown;
@property(nonatomic) UIControlState lastState;
@property(nonatomic) NSUInteger revision;
@property(nonatomic) UIUserInterfaceStyle style;
@property(nonatomic) NSInteger dirty;         // frames still to tick
@property(nonatomic) CFTimeInterval activatedAt,pressUntil;
@end
@implementation WXGLocalEntry
@end

static char WXGLocalAnchorKey,WXGLocalHostKey,WXGLocalRetryKey;
static WXGLocalEntry *WXGLocalEntryOfAnchor(UIView *view) {return view?objc_getAssociatedObject(view,&WXGLocalAnchorKey):nil;}

// A breadth-first walk that also goes into table / collection cells (WXGViews
// stops at cells), never into the plugin's own views.
static NSArray<UIView *> *WXGLocalViews(UIView *root,NSUInteger limit) {
    if(!root)return @[];
    NSMutableArray *queue=[NSMutableArray arrayWithObject:root];
    for(NSUInteger i=0;i<queue.count && queue.count<limit;i++) {
        UIView *v=queue[i];if(i && WXGIsPluginView(v))continue;
        for(UIView *child in v.subviews){if(queue.count>=limit)break;if(!WXGIsPluginView(child))[queue addObject:child];}
    }
    return queue;
}
static BOOL WXGLocalFilled(UIView *v) {
    UIColor *color=v.backgroundColor;if(!color)return NO;
    return CGColorGetAlpha([color resolvedColorWithTraitCollection:v.traitCollection].CGColor)>.3;
}
static BOOL WXGLocalOnlyPluginChildren(UIView *v) {
    for(UIView *child in v.subviews)if(!WXGIsPluginView(child))return NO;
    return YES;
}
// FIX109: a cheap sign that views were added or removed in a host or its
// direct children (a theme's picture put in after the host's layout).
static NSUInteger WXGLocalSubviewShape(UIView *host) {
    NSUInteger h=host.subviews.count;
    for(UIView *v in host.subviews)h=h*31+v.subviews.count;
    return h;
}
// A plain UIView painted as a field or a selection: exactly UIView, a fill,
// nothing of WeChat's inside. One already ours (fill cleared) still counts.
static BOOL WXGLocalPlainPaint(UIView *v,BOOL allowHidden) {
    if(!v || v.class!=UIView.class)return NO;
    if(WXGLocalEntryOfAnchor(v))return YES;
    if(!allowHidden && (v.hidden || v.alpha<.01))return NO;
    return WXGLocalOnlyPluginChildren(v) && WXGLocalFilled(v);
}
// The corner radius of a rounded-rectangle image as drawn at `size`: along the
// diagonal its edge is r(1 - 1/√2) in from the corner.
static CGFloat WXGLocalImageCorner(UIImage *image,CGSize size) {
    if(!image || size.width<8 || size.height<8)return 0;
    size_t w=(size_t)MIN(256,ceil(size.width*2)),h=(size_t)MIN(256,ceil(size.height*2));
    NSMutableData *data=[NSMutableData dataWithLength:w*h*4];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(data.mutableBytes,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);if(!context)return 0;
    UIGraphicsPushContext(context);[image drawInRect:CGRectMake(0,0,w,h)];UIGraphicsPopContext();CGContextRelease(context);
    const uint8_t *px=data.bytes;size_t n=MIN(w,h)/2;double entry=-1;
    for(size_t i=0;i<n;i++)if(px[(i*w+i)*4+3]>127){entry=i+.5;break;}
    if(entry<0)return 0;
    double points=entry*size.width/(double)w;
    return (CGFloat)MIN(points/(1-M_SQRT1_2),MIN(size.width,size.height)*.5);
}
// The colour of a (usually 1×1) background image, if it is a colour at all
// (saturated): 发送's green. Grey / white gives nil (plain glass).
static UIColor *WXGLocalImageTint(UIImage *image) {
    if(!image)return nil;
    static NSMapTable<UIImage *,id> *cache;if(!cache)cache=[NSMapTable weakToStrongObjectsMapTable];
    id known=[cache objectForKey:image];if(known)return known==NSNull.null?nil:known;
    uint8_t px[4*4*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(px,4,4,8,16,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    UIColor *tint=nil;
    if(context) {
        UIGraphicsPushContext(context);[image drawInRect:CGRectMake(0,0,4,4)];UIGraphicsPopContext();CGContextRelease(context);
        double r=0,g=0,b=0,a=0;for(int i=0;i<16;i++){r+=px[i*4];g+=px[i*4+1];b+=px[i*4+2];a+=px[i*4+3];}
        if(a>16*255*.5) {
            r/=a;g/=a;b/=a;   // premultiplied sums over the alpha sum: the straight colour
            double hi=MAX(r,MAX(g,b)),lo=MIN(r,MIN(g,b));
            if(hi>.3 && hi-lo>.25)tint=[UIColor colorWithRed:r green:g blue:b alpha:1];
        }
    }
    [cache setObject:tint?:NSNull.null forKey:image];
    return tint;
}

// FIX107 B: a radius setting's continuous radius (0 = WeChat's own `native`),
// at most half the short side. FIX109: kept with the glass and read again
// whenever the settings change (the emoji board is kept by WeChat and laid
// out again only when its size changes: a new radius waited for that).
static CGFloat (^WXGLocalRadiusSetting(NSString *key,CGFloat native))(CGSize) {
    return ^CGFloat(CGSize size){
        CGFloat custom=[WXGConfig.shared extraNumber:key],half=MIN(size.width,size.height)*.5;
        return custom>.01?MIN(custom,half):MIN(native,half);
    };
}

@interface WXGLocalGlass ()
- (void)tick:(CADisplayLink *)link;
@end
@interface WXGLocalTicker : NSObject
@property(nonatomic,weak) WXGLocalGlass *owner;
@end
@implementation WXGLocalTicker
- (void)tick:(CADisplayLink *)link {[self.owner tick:link];}
@end

@implementation WXGLocalGlass {
    NSHashTable<WXGLocalEntry *> *_entries;
    CADisplayLink *_link;
    CFTimeInterval _idleSince;
    NSUInteger _mounts,_unmounts,_ticks,_layouts;
    NSMutableDictionary<NSString *,NSString *> *_lastSkip;
    NSDictionary *_lastSearchBand;   // FIX113 F: the emoji search field's surroundings, last looked at
    NSDictionary *_emojiQuickJump;   // FIX113 Q: the quick jump's field, its capsule and band, last seen
    NSHashTable<UIViewController *> *_emojiPagesSeen;   // FIX113 N: each 表情搜索 page captured once
    NSMutableArray<NSDictionary *> *_emojiCaptures;
    NSUInteger _emojiPageSerial;
    NSHashTable<UIView *> *_hosts;   // every host seen (to mount again a kind switched back on)
    CFTimeInterval _lastWake;
    NSUInteger _remeasures,_retries,_wakes;
    Class _wcSearchBar,_webSearchBar,_favSearchBar,_swiftField,_tile,_board,_qqPage,_tabCell,_sheet,_emoticonSearch;
    Class _homeTitle,_pageTitle,_dropTitle,_barButton;   // FIX108
    Class _navContent;   // FIX109: the bar's own title label (插件)
    BOOL _wasAvailable;   // FIX108 C
    BOOL _coldWake;       // FIX109
    BOOL _themeFirst;     // FIX109: 搜索框让主题优先 as last applied
}
+ (instancetype)shared {
    static WXGLocalGlass *manager;static dispatch_once_t once;
    dispatch_once(&once,^{
        manager=[self new];
        // Just before every commit: WeChat can paint its fields, tiles and keys
        // again outside any layout we see (theme, state, reuse).
        __weak WXGLocalGlass *weakManager=manager;
        CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999800,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity activity){WXGPerfTimePluginWorkAs("localGlass",^{[weakManager reassert];});});
        if(observer){CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);CFRelease(observer);}
    });
    return manager;
}
// The Swift field by its module name, or its mangled one (each class once:
// hooked twice it would run twice).
static NSString *WXGLocalSwiftFieldName(void) {
    if(NSClassFromString(@"WeChat.WCSearchTextField"))return @"WeChat.WCSearchTextField";
    return NSClassFromString(@"_TtC6WeChat17WCSearchTextField")?@"_TtC6WeChat17WCSearchTextField":nil;
}
+ (NSArray<NSString *> *)hostClassNames {
    NSMutableArray *names=[@[@"WCSearchBar",@"WCWebSearchBar",@"FavSearchBar",@"UISearchBar",
        @"AttachmentButton",@"EmoticonBoardView",@"EmoticonBoardCrossCollectionQQEmojiPageCell",@"EmoticonBoardDynamicTabBarCollectionCell",
        @"MMScrollActionSheetContainerView",@"MFTitleView",@"MMTitleView",@"MMDropableTitleView",@"MMBarButton",@"_UINavigationBarContentView"] mutableCopy];
    NSString *field=WXGLocalSwiftFieldName();if(field)[names addObject:field];
    // FIX108 B: a listed class whose superclass is listed too is not hooked
    // again (its layout reaches the superclass's hook through super; hooked
    // twice it would run twice). kindForHost goes by isKindOfClass anyway.
    NSMutableArray *classes=[NSMutableArray array];for(NSString *name in names){Class c=NSClassFromString(name);if(c)[classes addObject:c];}
    NSMutableArray *kept=[NSMutableArray array];
    for(NSString *name in names) {
        Class c=NSClassFromString(name);if(!c)continue;BOOL covered=NO;
        for(Class other in classes)if(other!=c && [c isSubclassOfClass:other]){covered=YES;break;}
        if(!covered)[kept addObject:name];
    }
    return kept;
}
- (instancetype)init {
    if((self=[super init])) {
        _entries=[NSHashTable weakObjectsHashTable];_hosts=[NSHashTable weakObjectsHashTable];_lastSkip=[NSMutableDictionary dictionary];
        _wcSearchBar=NSClassFromString(@"WCSearchBar");_webSearchBar=NSClassFromString(@"WCWebSearchBar");_favSearchBar=NSClassFromString(@"FavSearchBar");
        NSString *field=WXGLocalSwiftFieldName();_swiftField=field?NSClassFromString(field):nil;
        _tile=NSClassFromString(@"AttachmentButton");_board=NSClassFromString(@"EmoticonBoardView");
        _qqPage=NSClassFromString(@"EmoticonBoardCrossCollectionQQEmojiPageCell");_tabCell=NSClassFromString(@"EmoticonBoardDynamicTabBarCollectionCell");
        _sheet=NSClassFromString(@"MMScrollActionSheetContainerView");_emoticonSearch=NSClassFromString(@"NewEmoticonSearchViewController");
        _homeTitle=NSClassFromString(@"MFTitleView");_pageTitle=NSClassFromString(@"MMTitleView");
        _dropTitle=NSClassFromString(@"MMDropableTitleView");_barButton=NSClassFromString(@"MMBarButton");
        _navContent=NSClassFromString(@"_UINavigationBarContentView");
        _themeFirst=WXGPreferences.shared.localSearchThemeFirst;
    }return self;
}
static BOOL WXGLocalAvailable(void) {return WXGPluginEnabled() && WXGEffectiveRenderMode()>=2;}
- (BOOL)wants:(WXGLocalKind)kind {return [self wants:kind available:WXGLocalAvailable()];}
- (BOOL)wants:(WXGLocalKind)kind available:(BOOL)available {
    if(!available)return NO;
    WXGPreferences *p=WXGPreferences.shared;
    switch(kind) {
        case WXGLocalSearch:return p.localSearch;
        case WXGLocalTile:return p.localPanel;
        case WXGLocalKey:case WXGLocalTab:return p.localEmoji;
        case WXGLocalSheet:return p.localSheet;
        case WXGLocalTitle:return p.localTitle;
        case WXGLocalNavButton:return p.localNavButtons && p.nav;
    }
    return NO;
}
- (void)skip:(UIView *)host because:(NSString *)reason {
    // Diagnostics only: why a hooked view got no glass (last reason per class).
    _lastSkip[NSStringFromClass(host.class)?:@"?"]=reason;
    [self unmountHost:host];
}
// The host's own layout comes before its descendants' in the same pass: a
// field still zero-sized now may be ready a moment later (three tries).
- (void)skip:(UIView *)host because:(NSString *)reason retry:(BOOL)retry {
    [self skip:host because:reason];
    if(!retry)return;
    // FIX108 C: five tries over about 2.3 s (the home search field at launch
    // was not ready within FIX107's three tries in 0.24 s and stayed native
    // until the next layout, a tab switch).
    static const double delays[]={.08,.15,.3,.6,1.2};
    NSInteger tries=[objc_getAssociatedObject(host,&WXGLocalRetryKey) integerValue];if(tries>=5)return;
    objc_setAssociatedObject(host,&WXGLocalRetryKey,@(tries+1),OBJC_ASSOCIATION_RETAIN_NONATOMIC);++_retries;
    __weak UIView *weakHost=host;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delays[tries]*NSEC_PER_SEC)),dispatch_get_main_queue(),^{UIView *h=weakHost;if(h.window)[self hostLaidOut:h];});
}

#pragma mark - Mounting

- (void)unmount:(WXGLocalEntry *)entry {
    if(!entry.mounted)return;
    entry.mounted=NO;++_unmounts;
    [entry.states restore];
    entry.surface.active=NO;entry.surface.hidden=YES;[entry.surface removeFromSuperview];
}
- (void)unmountHost:(UIView *)host {
    WXGLocalEntry *entry=host?objc_getAssociatedObject(host,&WXGLocalHostKey):nil;
    if(entry && entry.host==host)[self unmount:entry];
}
- (WXGLocalEntry *)entry:(WXGLocalKind)kind anchor:(UIView *)anchor host:(UIView *)host {
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(anchor);
    if(!entry) {
        entry=[WXGLocalEntry new];entry.kind=kind;entry.anchor=anchor;entry.states=[WXGStateBag new];
        WXGSurface *surface=[WXGSurface new];surface.role=[@"local." stringByAppendingString:WXGLocalKindName(kind)];
        surface.materialOnly=YES;surface.userInteractionEnabled=NO;surface.isAccessibilityElement=NO;surface.accessibilityElementsHidden=YES;
        entry.surface=surface;
        objc_setAssociatedObject(anchor,&WXGLocalAnchorKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_entries addObject:entry];
    }
    // The host that found it last (two hosts can find one field: the search
    // page's bar and the Swift field inside it).
    WXGLocalEntry *previous=objc_getAssociatedObject(host,&WXGLocalHostKey);
    if(previous && previous!=entry && previous.host==host)[self unmount:previous];
    entry.host=host;objc_setAssociatedObject(host,&WXGLocalHostKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return entry;
}
// The glass's rectangle in the anchor: `measure`'s bounds.
static CGRect WXGLocalMaterial(UIView *measure,UIView *anchor) {
    if(!measure || !anchor)return CGRectNull;
    return measure==anchor?anchor.bounds:[measure convertRect:measure.bounds toView:anchor];
}
// FIX108 B: a computed rectangle on whole device pixels (a size such as
// 41.4 pt stays one size on both axes); a measured one exactly as the view is.
static CGRect WXGLocalPixelRect(CGRect r,UIView *anchor) {
    if(CGRectIsNull(r) || CGRectIsInfinite(r))return CGRectNull;
    CGFloat scale=anchor.window.screen.scale?:UIScreen.mainScreen.scale;if(scale<1)scale=1;
    return CGRectMake(round(r.origin.x*scale)/scale,round(r.origin.y*scale)/scale,round(r.size.width*scale)/scale,round(r.size.height*scale)/scale);
}
static CGRect WXGLocalComputed(CGRect (^frame)(void),UIView *anchor) {
    CGRect r=frame?frame():CGRectNull;if(CGRectIsNull(r) || CGRectIsInfinite(r))return CGRectNull;
    CGFloat scale=anchor.window.screen.scale?:UIScreen.mainScreen.scale;if(scale<1)scale=1;
    return CGRectMake(round(r.origin.x*scale)/scale,round(r.origin.y*scale)/scale,round(r.size.width*scale)/scale,round(r.size.height*scale)/scale);
}
static CGRect WXGLocalEntryMaterial(WXGLocalEntry *entry) {
    if(entry.frame)return WXGLocalComputed(entry.frame,entry.anchor);
    return WXGLocalMaterial(entry.measure,entry.anchor);
}
- (void)mount:(WXGLocalKind)kind host:(UIView *)host anchor:(UIView *)anchor paint:(UIView *)paint below:(UIView *)below
      measure:(UIView *)measure radius:(CGFloat)radius button:(UIControl *)button prepare:(void (^)(WXGStateBag *states))prepare {
    [self mount:kind host:host anchor:anchor paint:paint below:below measure:measure frame:nil radius:radius button:button prepare:prepare];
}
- (void)mount:(WXGLocalKind)kind host:(UIView *)host anchor:(UIView *)anchor paint:(UIView *)paint below:(UIView *)below
      measure:(UIView *)measure frame:(CGRect (^)(void))frame radius:(CGFloat)radius button:(UIControl *)button prepare:(void (^)(WXGStateBag *states))prepare {
    if(!anchor)return;
    // Nothing is made (no glass, no entry) unless it is wanted and shown.
    WXGLocalEntry *existing=WXGLocalEntryOfAnchor(anchor);
    if(![self wants:kind]){if(existing)[self unmount:existing];return;}
    if(!anchor.window){existing.surface.active=NO;return;}
    CGRect material=frame?WXGLocalComputed(frame,anchor):WXGLocalMaterial(measure,anchor);
    if(CGRectIsNull(material) || material.size.width<1 || material.size.height<1) {
        if(existing.mounted)return;   // a glass already there stays (a one-pass collapse)
        [self skip:host because:@"还没有尺寸" retry:YES];return;
    }
    WXGLocalEntry *entry=[self entry:kind anchor:anchor host:host];
    if(entry.applying)return;
    objc_setAssociatedObject(host,&WXGLocalRetryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    entry.applying=YES;
    @try {
        if(entry.paint && entry.paint!=paint)[entry.states restore];   // WeChat swapped its paint view
        entry.paint=paint;entry.below=below;entry.button=button;entry.radius=radius;entry.measure=measure;entry.frame=frame;
        if(prepare)prepare(entry.states);
        [entry.states reapply];
        WXGSurface *surface=entry.surface;
        BOOL reshaped=fabs(surface.maximumCornerRadius-radius)>.01;   // FIX107 B: the radius settings
        surface.maximumCornerRadius=radius;surface.pressFixed=button==nil;
        if(kind==WXGLocalSheet && !surface.glass.lightweight){surface.glass.lightweight=YES;[surface.glass invalidateBackdrop];}
        surface.glass.sourceView=WXGContentSourceForView(anchor);
        CGRect now=surface.superview==anchor?surface.materialRect:CGRectNull;
        CGRect wanted=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,material.size.width,material.size.height);
        BOOL moved=surface.superview!=anchor || !CGRectEqualToRect(now,wanted) ||
            !CGPointEqualToPoint(surface.frame.origin,CGPointMake(material.origin.x-WXGCanvasPaddingX,material.origin.y-WXGCanvasPaddingY));
        if(moved)[surface placeMaterial:material inParent:anchor];
        // Lowest (or right above the button's background image view), under
        // WeChat's icons and labels.
        if(below && below.superview==anchor) {
            NSUInteger at=[anchor.subviews indexOfObjectIdenticalTo:below];
            if(at==NSNotFound || at+1>=anchor.subviews.count || anchor.subviews[at+1]!=surface)[anchor insertSubview:surface aboveSubview:below];
        }else if(anchor.subviews.firstObject!=surface)[anchor insertSubview:surface atIndex:0];
        surface.hidden=NO;
        BOOL fresh=!entry.mounted;
        if(!entry.mounted){entry.mounted=YES;++_mounts;entry.tintKnown=NO;entry.dirty=30;entry.revision=0;}
        if(moved || reshaped)entry.dirty=MAX(entry.dirty,12);
        // FIX108 C: woken only for work (every host layout woke it for 0.5 s).
        if(fresh || moved || reshaped || entry.dirty>0 || !surface.active)[self ensureLink:anchor.window.screen];
    } @catch(NSException *error) {
        WXGLog(@"更多玻璃 %@：%@",WXGLocalKindName(kind),error.reason);[self unmount:entry];
    } @finally {entry.applying=NO;}
}

#pragma mark - The elements

- (NSInteger)kindForHost:(UIView *)view {
    if((_wcSearchBar && [view isKindOfClass:_wcSearchBar]) || (_webSearchBar && [view isKindOfClass:_webSearchBar]) ||
       (_favSearchBar && [view isKindOfClass:_favSearchBar]) || (_swiftField && [view isKindOfClass:_swiftField]) || [view isKindOfClass:UISearchBar.class])
        return WXGLocalSearch;
    if(_tile && [view isKindOfClass:_tile])return WXGLocalTile;
    if((_board && [view isKindOfClass:_board]) || (_qqPage && [view isKindOfClass:_qqPage]))return WXGLocalKey;
    if(_tabCell && [view isKindOfClass:_tabCell])return WXGLocalTab;
    if(_sheet && [view isKindOfClass:_sheet])return WXGLocalSheet;
    if((_homeTitle && [view isKindOfClass:_homeTitle]) || (_pageTitle && [view isKindOfClass:_pageTitle]) || (_dropTitle && [view isKindOfClass:_dropTitle]))return WXGLocalTitle;
    if(_barButton && [view isKindOfClass:_barButton])return WXGLocalNavButton;
    if(_navContent && [view isKindOfClass:_navContent])return WXGLocalTitle;   // FIX109
    if([self fallbackField:view])return WXGLocalSearch;
    return -1;
}
// The emoji search field found by name when its Swift class was not.
- (BOOL)fallbackField:(UIView *)view {
    return !_swiftField && [view isKindOfClass:UITextField.class] && [NSStringFromClass(view.class) hasSuffix:@"WCSearchTextField"];
}
- (void)hostLaidOut:(UIView *)view {
    if(!NSThread.isMainThread || !view || WXGIsPluginView(view))return;
    ++_layouts;
    @try {
        WXGLocalEntry *own=objc_getAssociatedObject(view,&WXGLocalHostKey);if(own.host!=view)own=nil;
        if(!view.window){own.surface.active=NO;return;}
        NSInteger kind=[self kindForHost:view];if(kind<0)return;
        [_hosts addObject:view];
        // Off, not authorised, not render-server mode, or this kind switched
        // off: no scan, no glass (FIX105: no trace when not authorised).
        if(![self wants:(WXGLocalKind)kind]){if(own)[self unmount:own];return;}
        if(_wcSearchBar && [view isKindOfClass:_wcSearchBar])[self searchBar:view];
        else if(_webSearchBar && [view isKindOfClass:_webSearchBar])[self searchBar:view];
        else if(_favSearchBar && [view isKindOfClass:_favSearchBar])[self paintedBar:view];
        else if(_swiftField && [view isKindOfClass:_swiftField])[self fieldSibling:view];
        else if(_tile && [view isKindOfClass:_tile])[self tile:view];
        else if((_board && [view isKindOfClass:_board]) || (_qqPage && [view isKindOfClass:_qqPage]))[self keysIn:view];
        else if(_tabCell && [view isKindOfClass:_tabCell])[self tabCell:view];
        else if(_sheet && [view isKindOfClass:_sheet])[self sheet:view];
        else if(_dropTitle && [view isKindOfClass:_dropTitle])[self dropableTitle:view];
        else if(_navContent && [view isKindOfClass:_navContent])[self systemTitle:view];
        else if(kind==WXGLocalTitle)[self titleView:view];
        else if(kind==WXGLocalNavButton)[self navButton:view];
        else if([view isKindOfClass:UISearchBar.class])[self systemSearchBar:(UISearchBar *)view];
        else if([self fallbackField:view])[self fieldSibling:view];
    } @catch(NSException *error) {WXGLog(@"更多玻璃：%@",error.reason);}
}
// Fallback for the emoji search sheet if the Swift field class was not found.
- (void)controllerLaidOut:(UIViewController *)controller {
    [self noteEmojiSearchPage:controller];   // FIX113 N: diagnostics, whatever finds the field
    if(_swiftField || !_emoticonSearch || ![controller isKindOfClass:_emoticonSearch] || !controller.isViewLoaded || !controller.view.window)return;
    if(![self wants:WXGLocalSearch])return;
    for(UIView *v in WXGLocalViews(controller.view,260))
        if([v isKindOfClass:UITextField.class] && [NSStringFromClass(v.class) hasSuffix:@"WCSearchTextField"]){[_hosts addObject:v];[self fieldSibling:v];}
}
// FIX113 N (user: catch what goes wrong when 表情搜索 is opened from the
// text in the input bar): each time that page comes on screen its search
// field's surroundings are recorded three times (0.3 / 0.9 / 1.8 s; the first
// six pages of a launch; class names as the runtime has them): how it
// was opened (the field holding text: the input bar's quick jump; empty: the
// emoji panel's search), the field's ancestors, every view level with it
// (class, frame, fill, alpha, corner), the search glass on that page, and the
// views that could draw a band: filled or a picture, visible, not ours, at
// least the field's width, at most 3.2 fields tall, across the field's height.
// Diagnostics only (emojiSearchCaptures; the last three pages).
static NSString *WXGLocalFillText(UIView *v) {
    UIColor *color=v.backgroundColor?[v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection]:nil;
    CGColorRef cg=color?color.CGColor:v.layer.backgroundColor;
    if(!cg || CGColorGetAlpha(cg)<.01)return nil;
    UIColor *c=[UIColor colorWithCGColor:cg];CGFloat r=0,g=0,b=0,a=0;
    if(![c getRed:&r green:&g blue:&b alpha:&a]){CGFloat white=0;[c getWhite:&white alpha:&a];r=g=b=white;}
    return [NSString stringWithFormat:@"#%02X%02X%02X/%.2f",(int)round(r*255),(int)round(g*255),(int)round(b*255),a];
}
static BOOL WXGLocalShownChain(UIView *v,UIView *root) {
    for(UIView *a=v;a;a=a.superview){if(a.hidden || a.alpha<.01)return NO;if(a==root)break;}
    return YES;
}
- (void)noteEmojiSearchPage:(UIViewController *)page {
    if(!_emoticonSearch || ![page isKindOfClass:_emoticonSearch] || !page.isViewLoaded || !page.view.window || !WXGPluginEnabled())return;
    if(!_emojiPagesSeen)_emojiPagesSeen=[NSHashTable weakObjectsHashTable];
    if([_emojiPagesSeen containsObject:page] || _emojiPageSerial>=6)return;   // the first six pages of a launch
    [_emojiPagesSeen addObject:page];
    NSUInteger serial=++_emojiPageSerial;CFTimeInterval opened=CACurrentMediaTime();
    __weak UIViewController *weakPage=page;__weak WXGLocalGlass *weakSelf=self;
    for(NSNumber *delay in @[@.3,@.9,@1.8])   // after the page's own appearance
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            WXGPerfTimePluginWorkAs("localGlass",^{[weakSelf captureEmojiSearch:weakPage serial:serial opened:opened last:delay.doubleValue>1];});
        });
}
- (void)captureEmojiSearch:(UIViewController *)page serial:(NSUInteger)serial opened:(CFTimeInterval)opened last:(BOOL)last {
    if(!page.isViewLoaded || !page.view.window)return;
    @try {
        UIWindow *w=page.view.window;UIView *root=page.view;
        UITextField *field=nil;
        for(UIView *v in WXGLocalViews(root,700)) {
            if(![v isKindOfClass:UITextField.class] || v.hidden)continue;
            if(!field || [@(class_getName(v.class)) hasSuffix:@"SearchTextField"])field=(UITextField *)v;
            if([@(class_getName(v.class)) hasSuffix:@"SearchTextField"])break;
        }
        NSMutableDictionary *capture=[NSMutableDictionary dictionary];
        capture[@"page"]=@(serial);capture[@"ms"]=@(round((CACurrentMediaTime()-opened)*1000));
        UIViewController *presenter=page.presentingViewController;NSArray *stack=page.navigationController.viewControllers;
        NSMutableArray *names=[NSMutableArray array];
        for(UIViewController *c in [stack subarrayWithRange:NSMakeRange(stack.count>3?stack.count-3:0,MIN(stack.count,(NSUInteger)3))])[names addObject:NSStringFromClass(c.class)];
        capture[@"context"]=@{@"presenter":presenter?NSStringFromClass(presenter.class):@"",@"parent":page.parentViewController?NSStringFromClass(page.parentViewController.class):@"",@"stack":names};
        if(!field){capture[@"field"]=@"没有找到输入框";[self keepEmojiCapture:capture];return;}
        CGRect f=[field convertRect:field.bounds toView:w];
        capture[@"field"]=[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f",@(class_getName(field.class)),f.origin.x,f.origin.y,f.size.width,f.size.height];
        capture[@"opened"]=field.text.length?@"带文字（输入框快捷跳转）":@"空（表情面板的搜索）";
        capture[@"textLength"]=@(field.text.length);capture[@"focused"]=@(field.isFirstResponder);
        NSMutableArray *chain=[NSMutableArray array];
        for(UIView *a=field.superview;a && chain.count<8;a=a.superview) {
            CGRect r=[a convertRect:a.bounds toView:w];
            [chain addObject:[NSString stringWithFormat:@"%@%@ %.0f,%.0f %.0fx%.0f fill %@ alpha %.2f r%.0f%@",a==root?@"(page) ":@"",@(class_getName(a.class)),
                              r.origin.x,r.origin.y,r.size.width,r.size.height,WXGLocalFillText(a)?:@"-",a.alpha,a.layer.cornerRadius,a.hidden?@" hidden":@""]];
            if(a==root)break;
        }
        capture[@"ancestors"]=chain;
        NSMutableArray *level=[NSMutableArray array],*suspects=[NSMutableArray array];
        CGFloat top=CGRectGetMinY(f)-24,bottom=CGRectGetMaxY(f)+24;
        NSMutableArray<UIView *> *views=[NSMutableArray arrayWithObject:root];
        for(NSUInteger i=0;i<views.count && views.count<900;i++)for(UIView *child in views[i].subviews)[views addObject:child];   // plugin views included
        for(UIView *v in views) {
            if(v==root || v==field || [field isDescendantOfView:v])continue;
            CGRect r=[v convertRect:v.bounds toView:w];
            if(CGRectGetMaxY(r)<top || CGRectGetMinY(r)>bottom || r.size.width<4 || r.size.height<2)continue;
            if(r.size.height>f.size.height*6)continue;   // the page's big containers (in the ancestors if they hold the field)
            BOOL plugin=WXGIsPluginView(v),shown=WXGLocalShownChain(v,root);
            NSString *fill=WXGLocalFillText(v);
            BOOL image=([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image) || v.layer.contents;
            if(level.count<48)[level addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f fill %@ alpha %.2f r%.0f%@%@%@",@(class_getName(v.class)),
                r.origin.x,r.origin.y,r.size.width,r.size.height,fill?:@"-",v.alpha,v.layer.cornerRadius,shown?@"":@" (not shown)",plugin?@" (ours)":@"",image?@" image":@""]];
            if(plugin || !shown || (!fill && !image))continue;
            if(r.size.width<f.size.width-2 || r.size.height>f.size.height*3.2 || CGRectGetMinY(r)>CGRectGetMaxY(f) || CGRectGetMaxY(r)<CGRectGetMinY(f))continue;
            [suspects addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f fill %@%@",@(class_getName(v.class)),r.origin.x,r.origin.y,r.size.width,r.size.height,fill?:@"-",image?@" image":@""]];
        }
        capture[@"level"]=level;capture[@"suspects"]=suspects;
        NSMutableArray *glass=[NSMutableArray array];
        for(WXGLocalEntry *entry in _entries.allObjects) {
            UIView *anchor=entry.anchor;
            if(entry.kind!=WXGLocalSearch || !anchor || ![anchor isDescendantOfView:root])continue;
            CGRect r=[anchor convertRect:anchor.bounds toView:w];
            [glass addObject:[NSString stringWithFormat:@"%@ on %@ %.0f,%.0f %.0fx%.0f mounted %d active %d drawn %d bands %lu",@(class_getName(entry.host.class)),
                              @(class_getName(anchor.class)),r.origin.x,r.origin.y,r.size.width,r.size.height,entry.mounted,entry.surface.active,
                              entry.surface.glass.hasPresentedFrame,(unsigned long)entry.bands.count]];
        }
        capture[@"glass"]=glass;
        NSMutableDictionary *skips=[NSMutableDictionary dictionary];
        [_lastSkip enumerateKeysAndObjectsUsingBlock:^(NSString *key,NSString *reason,__unused BOOL *stop){if([key containsString:@"Search"] || [key containsString:@"Field"])skips[key]=reason;}];
        capture[@"skipped"]=skips;
        [self keepEmojiCapture:capture];
        if(last && serial<=6)WXGLog(@"表情搜索 #%lu（%@）：输入框 %@，可能画出条带的视图 %lu 个%@",(unsigned long)serial,capture[@"opened"],capture[@"field"],(unsigned long)suspects.count,
                                    suspects.count?[@"：" stringByAppendingString:suspects.firstObject]:@"");
    } @catch(NSException *error){WXGLog(@"表情搜索记录失败：%@",error.reason);}
}
- (void)keepEmojiCapture:(NSDictionary *)capture {
    if(!_emojiCaptures)_emojiCaptures=[NSMutableArray array];
    [_emojiCaptures addObject:capture];
    while(_emojiCaptures.count>9)[_emojiCaptures removeObjectAtIndex:0];
}
// FIX109: what a theme plugin draws for a search field: a picture the
// field's size behind or over it (ThemeBox: a UIImageView under WCSearchBar's
// stack, the stack's frame, with WeChat's white fill emptied). Not a small
// icon, not a whole-page background.
static NSArray<UIView *> *WXGLocalFieldSkins(UIView *host,UIView *paint) {
    CGRect field=[paint convertRect:paint.bounds toView:host];
    NSMutableArray *skins=[NSMutableArray array];if(field.size.width<1 || field.size.height<1)return skins;
    // Each edge within a few points of the field's (not the bar's own
    // background, not a view holding the field, not a small icon).
    CGFloat dx=MAX(4,field.size.width*.15),dy=MAX(4,field.size.height*.15);
    for(UIView *v in WXGLocalViews(host,160)) {
        if(v==host || v==paint || ![v isKindOfClass:UIImageView.class] || WXGIsPluginView(v) || [paint isDescendantOfView:v] || !WXGLocalOnlyPluginChildren(v))continue;
        if(!((UIImageView *)v).image && !v.layer.contents)continue;
        CGRect r=[v convertRect:v.bounds toView:host];
        if(fabs(CGRectGetMinX(r)-CGRectGetMinX(field))>dx || fabs(CGRectGetMaxX(r)-CGRectGetMaxX(field))>dx ||
           fabs(CGRectGetMinY(r)-CGRectGetMinY(field))>dy || fabs(CGRectGetMaxY(r)-CGRectGetMaxY(field))>dy)continue;
        [skins addObject:v];
    }
    return skins;
}
// WCSearchBar / WCWebSearchBar: the filled plain view in their stacks. FIX109:
// also one a theme emptied (a plain rounded view, the field's size, nothing
// inside) unless the theme is to keep the field.
static BOOL WXGLocalShownIn(UIView *v,UIView *root);
static BOOL WXGLocalFieldCandidate(UIView *v,UIView *bar,BOOL emptied) {
    if(emptied) {
        // FIX109 E: only where WeChat's field sits (in the bar's stack views),
        // never edge to edge (the emoji search sheet's header got a second,
        // bar-wide capsule over its field).
        if(!v || v.class!=UIView.class || v.hidden || v.alpha<.01 || v.layer.cornerRadius<=0 || !WXGLocalOnlyPluginChildren(v) ||
           ![v.superview isKindOfClass:UIStackView.class])return NO;
    }else if(!WXGLocalPlainPaint(v,NO))return NO;
    CGRect r=[v convertRect:v.bounds toView:bar];
    return r.size.height>=24 && r.size.height<=(emptied?44:60) && r.size.width>=bar.bounds.size.width*.4 && (!emptied || r.size.width<=bar.bounds.size.width-6);
}
- (void)searchBar:(UIView *)bar {
    WXGLocalEntry *known=objc_getAssociatedObject(bar,&WXGLocalHostKey);
    UIView *paint=known.host==bar && [known.anchor isDescendantOfView:bar]?known.anchor:nil;
    BOOL themeFirst=WXGPreferences.shared.localSearchThemeFirst;
    // FIX109: not ours now (restored): a field the theme emptied stays the theme's.
    if(paint && themeFirst && !known.mounted && !WXGLocalFilled(paint))paint=nil;
    if(!paint)for(NSUInteger pass=0;pass<(themeFirst?1:2) && !paint;pass++) {
        CGFloat best=0;
        for(UIView *v in WXGLocalViews(bar,120)) {
            if(v==bar || !WXGLocalFieldCandidate(v,bar,pass==1))continue;
            CGFloat width=[v convertRect:v.bounds toView:bar].size.width;
            if(width>best){best=width;paint=v;}
        }
    }
    if(!paint){[self skip:bar because:themeFirst?@"没有找到搜索框底色（主题优先时，主题清空了底色就不加玻璃）":@"没有找到搜索框底色" retry:YES];return;}
    // FIX109: a theme's picture of the field: hidden under the glass (default),
    // or the field left to the theme (主题优先). Only in WeChat's own search
    // bars (a text field's own background picture is not a theme's).
    // Looked for again only when the bar's views changed (reassert notices).
    NSArray<UIView *> *skins=known.mounted && known.anchor==paint && known.skinViews && WXGLocalSubviewShape(bar)==known.hostShape?
        known.skinViews.allObjects:WXGLocalFieldSkins(bar,paint);
    if(skins.count && themeFirst){[self skip:bar because:@"搜索框主题优先：主题换了搜索框的图"];return;}
    [self field:paint host:bar skins:skins];
}
- (void)field:(UIView *)paint host:(UIView *)host {[self field:paint host:host skins:@[]];}
// FIX109 E: one search glass per field: another one already over most of this
// rectangle (two hosts finding two different views for one field) — the
// smaller, the field's own size, stays; the larger goes or is not made.
// Only within one page (its controller or one holding the other): two pages'
// bars at the same place while one is pushed over the other are two fields.
static UIViewController *WXGLocalOwner(UIView *view) {
    for(UIResponder *r=view;r;r=r.nextResponder)if([r isKindOfClass:UIViewController.class])return (UIViewController *)r;
    return nil;
}
static BOOL WXGLocalSamePage(UIView *a,UIView *b) {
    UIViewController *x=WXGLocalOwner(a),*y=WXGLocalOwner(b);if(!x || !y)return NO;
    for(UIViewController *c=x;c;c=c.parentViewController)if(c==y)return YES;
    for(UIViewController *c=y;c;c=c.parentViewController)if(c==x)return YES;
    return NO;
}
- (BOOL)searchGlassClashes:(UIView *)anchor material:(CGRect)local host:(UIView *)host {
    UIWindow *w=anchor.window;if(!w || CGRectIsNull(local) || !WXGLocalShownIn(anchor,nil))return NO;
    CGRect mine=[anchor convertRect:local toView:w];CGFloat myArea=mine.size.width*mine.size.height;
    for(WXGLocalEntry *other in _entries.allObjects) {
        if(!other.mounted || other.kind!=WXGLocalSearch || other.anchor==anchor || other.anchor.window!=w)continue;
        if(!WXGLocalShownIn(other.anchor,nil) || !WXGLocalSamePage(anchor,other.anchor))continue;
        CGRect material=WXGLocalEntryMaterial(other);if(CGRectIsNull(material))continue;
        CGRect theirs=[other.anchor convertRect:material toView:w],i=CGRectIntersection(mine,theirs);
        if(CGRectIsNull(i))continue;
        CGFloat theirArea=theirs.size.width*theirs.size.height,overlap=i.size.width*i.size.height;
        if(overlap<MIN(myArea,theirArea)*.5)continue;
        if(theirArea<=myArea){[self skip:host because:@"和另一块搜索框玻璃重叠（保留输入框大小的那块）"];return YES;}
        [self unmount:other];
    }
    return NO;
}
- (void)field:(UIView *)paint host:(UIView *)host skins:(NSArray<UIView *> *)skins {
    // FIX113 O: one glass per field: one this host mounted on another view
    // before (its paint chosen differently then) goes.
    for(WXGLocalEntry *other in _entries.allObjects)
        if(other.mounted && other.kind==WXGLocalSearch && other.host==host && other.anchor && other.anchor!=paint)[self unmount:other];
    if([self searchGlassClashes:paint material:paint.bounds host:host])return;
    [self mount:WXGLocalSearch host:host anchor:paint paint:paint below:nil measure:paint radius:0 button:nil
        prepare:^(WXGStateBag *states){[states clear:paint];[states allowOverflow:paint];for(UIView *skin in skins)[states hide:skin];}];
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(paint);
    if(entry.mounted) {
        entry.hostShape=WXGLocalSubviewShape(host);entry.skins=skins.count;
        NSHashTable *table=[NSHashTable weakObjectsHashTable];for(UIView *skin in skins)[table addObject:skin];entry.skinViews=table;
        [self clearSearchBandAround:entry];
    }
}
// FIX113 F: 表情搜索 opened from the text in the input bar (its quick jump,
// not the emoji panel's search): WeChat paints a band around the field, bar
// wide and a lighter grey, that the panel's way leaves clear. Its fill goes
// with the field's glass (and comes back with it): only on that page, only
// filled views around the field (one of its first few ancestors or a sibling
// of one) as wide as the field at least, no taller than 2.2 fields.
- (void)clearSearchBandAround:(WXGLocalEntry *)entry {
    UIView *paint=entry.paint?:entry.anchor;UIWindow *w=paint.window;
    if(!_emoticonSearch || !w || entry.kind!=WXGLocalSearch)return;
    UIViewController *page=nil;
    for(UIViewController *c=WXGLocalOwner(paint);c;c=c.parentViewController)if([c isKindOfClass:_emoticonSearch]){page=c;break;}
    if(!page || !page.isViewLoaded)return;
    CGRect field=[paint convertRect:paint.bounds toView:w];
    if(field.size.height<8)return;
    NSMutableArray<NSString *> *cleared=[NSMutableArray array],*chain=[NSMutableArray array];
    // FIX113 H (诊断 5: the field's paint sits right in the sheet's root view,
    // so F looked at nothing): up to and including the page's own view; of
    // that one only its other subviews (its own fill is the sheet).
    UIView *branch=paint;NSUInteger depth=0;
    for(UIView *a=paint.superview;a && depth<5;a=a.superview,depth++) {
        BOOL root=a==page.view;
        NSMutableArray<UIView *> *candidates=[NSMutableArray array];if(!root)[candidates addObject:a];
        for(UIView *v in a.subviews)if(v!=branch && !WXGIsPluginView(v))[candidates addObject:v];
        CGRect ar=[a convertRect:a.bounds toView:w];CGFloat alpha=a.backgroundColor?CGColorGetAlpha([a.backgroundColor resolvedColorWithTraitCollection:a.traitCollection].CGColor):0;
        [chain addObject:[NSString stringWithFormat:@"%@%@ %.0f,%.0f %.0fx%.0f fill %.2f subviews %lu",root?@"(page) ":@"",NSStringFromClass(a.class),ar.origin.x,ar.origin.y,ar.size.width,ar.size.height,alpha,(unsigned long)a.subviews.count]];
        for(UIView *v in candidates) {
            CGRect r=[v convertRect:v.bounds toView:w];
            // (diagnostics: the siblings level with the field, filled or not)
            if(v!=a && CGRectGetMinY(r)<=CGRectGetMaxY(field) && CGRectGetMaxY(r)>=CGRectGetMinY(field) && chain.count<24) {
                CGFloat va=v.backgroundColor?CGColorGetAlpha([v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection].CGColor):0;
                [chain addObject:[NSString stringWithFormat:@"  · %@ %.0f,%.0f %.0fx%.0f fill %.2f%@%@",NSStringFromClass(v.class),r.origin.x,r.origin.y,r.size.width,r.size.height,va,
                                  v.hidden?@" hidden":@"",[v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image?@" image":@""]];
            }
            if(v.hidden || v.alpha<.01 || !WXGLocalFilled(v))continue;
            if(r.size.height>field.size.height*2.2 || CGRectGetMinY(r)>CGRectGetMidY(field) || CGRectGetMaxY(r)<CGRectGetMidY(field) ||
               CGRectGetMinX(r)>CGRectGetMinX(field)+1 || CGRectGetMaxX(r)<CGRectGetMaxX(field)-1)continue;
            // FIX113 R (user: a white band around the field, 14:14 screenshot):
            // in the quick jump's layout the page-wide grey band is the row's
            // own background (the page's view under it is white); with the
            // glass on the field's capsule only (FIX113 Q) it stays as WeChat
            // paints it, like the sheet's grey above and below it.
            if(root)continue;
            [entry.states clear:v];
            [cleared addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f",NSStringFromClass(v.class),r.origin.x,r.origin.y,r.size.width,r.size.height]];
        }
        if(root)break;
        branch=a;
    }
    if(cleared.count || entry.bands.count)entry.bands=cleared;
    _lastSearchBand=@{@"t":@(round(CACurrentMediaTime()*10)/10),@"field":[NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f",field.origin.x,field.origin.y,field.size.width,field.size.height],
                      @"cleared":cleared.copy,@"around":chain.copy};
}
// FavSearchBar (收藏): the bar is its own filled, rounded field.
- (void)paintedBar:(UIView *)bar {
    CGRect b=bar.bounds;
    BOOL painted=WXGLocalEntryOfAnchor(bar).mounted || (WXGLocalFilled(bar) && bar.layer.cornerRadius>0);
    if(!painted || b.size.height<24 || b.size.height>60){[self skip:bar because:@"不是带底色的搜索框"];return;}
    if([self searchGlassClashes:bar material:bar.bounds host:bar])return;   // FIX109 E
    [self mount:WXGLocalSearch host:bar anchor:bar paint:bar below:nil measure:bar radius:0 button:nil
        prepare:^(WXGStateBag *states){[states clear:bar];}];
}
// WeChat's Swift WCSearchTextField (表情搜索; the search page's, inside its
// bar): the filled plain sibling around it.
// FIX113 Q (user: a capture of 表情搜索 opened by the input bar's quick jump,
// WGP 10-21 12:51, iOS 15.7 / WeChat 8.0.73; "adapt that one exactly"): the
// field sits right in the page's own view (white), beside it in that view a
// white UIView of the field's height with corner radius 4 (16,0 382x36: the
// capsule) and a grey #EDEDED UIView the page's width, 52 tall from the same
// top (the band the panel's way does not have). The glass goes on the capsule
// only, never on the band (cleared with the glass, clearSearchBandAround);
// with no capsule yet, nothing (looked at again on the next layout).
- (BOOL)emojiQuickJumpField:(UIView *)field {
    if(!_emoticonSearch)return NO;
    UIView *parent=field.superview;UIViewController *page=nil;
    for(UIViewController *c=WXGLocalOwner(field);c;c=c.parentViewController)if([c isKindOfClass:_emoticonSearch]){page=c;break;}
    if(!page || !page.isViewLoaded || !parent || parent!=page.view)return NO;   // only that layout
    CGRect f=field.frame;CGFloat parentW=parent.bounds.size.width;
    if(f.size.height<24 || f.size.height>60 || parentW<100)return NO;
    UIView *capsule=nil;CGFloat best=CGFLOAT_MAX;NSMutableArray<NSString *> *bands=[NSMutableArray array];
    for(UIView *s in parent.subviews) {
        if(s==field || WXGIsPluginView(s) || !WXGLocalPlainPaint(s,NO))continue;
        CGRect r=s.frame;
        BOOL level=CGRectGetMinY(r)<=CGRectGetMinY(f)+3 && CGRectGetMaxY(r)>=CGRectGetMaxY(f)-3;
        if(!level || CGRectGetMinX(r)>CGRectGetMinX(f)+1 || CGRectGetMaxX(r)<CGRectGetMaxX(f)-1)continue;
        if(r.size.width>=parentW-6) {   // the page-wide band: never the glass's
            [bands addObject:[NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f",r.origin.x,r.origin.y,r.size.width,r.size.height]];
            continue;
        }
        if(fabs(r.size.height-f.size.height)>4)continue;
        CGFloat area=r.size.width*r.size.height;if(area<best){best=area;capsule=s;}
    }
    CGRect c=capsule?capsule.frame:CGRectNull;
    _emojiQuickJump=@{@"t":@(round(CACurrentMediaTime()*10)/10),@"field":[NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f",f.origin.x,f.origin.y,f.size.width,f.size.height],
                      @"capsule":capsule?[NSString stringWithFormat:@"%.0f,%.0f %.0fx%.0f r%.0f",c.origin.x,c.origin.y,c.size.width,c.size.height,capsule.layer.cornerRadius]:@"",
                      @"bands":bands.copy,@"text":@([field isKindOfClass:UITextField.class] && ((UITextField *)field).text.length>0)};
    if(!capsule) {
        // A glass already on its capsule stays (a passing layout, not a reason to drop it).
        for(WXGLocalEntry *entry in _entries.allObjects)
            if(entry.mounted && entry.kind==WXGLocalSearch && entry.host==field && entry.anchor.superview==parent && entry.anchor.frame.size.width<parentW-6)return YES;
        [self skip:field because:@"表情搜索（快捷跳转）：还没有输入框自己的底色，不用整条底带" retry:YES];return YES;
    }
    [self field:capsule host:field];
    return YES;
}
- (void)fieldSibling:(UIView *)field {
    UIView *parent=field.superview;if(!parent)return;
    if([self emojiQuickJumpField:field])return;   // FIX113 Q
    // FIX113 O (诊断 6: 表情搜索 opened from the input bar's text has, beside
    // the field's own capsule 382 x 36, a bar-wide 414 x 52 view in the same
    // parent; the widest won and a full-width capsule was the band): the
    // smallest plain paint around the field, never one edge to edge.
    // (An edge-to-edge one only when it is the only one: a parent the
    // capsule's own size.)
    CGRect f=field.frame;UIView *paint=nil,*wide=nil;CGFloat best=CGFLOAT_MAX,bestWide=CGFLOAT_MAX,parentW=parent.bounds.size.width;
    for(UIView *s in parent.subviews) {
        if(s==field || !WXGLocalPlainPaint(s,NO))continue;
        CGRect r=s.frame;
        if(r.size.height<24 || r.size.height>60)continue;
        if(CGRectGetMinY(r)>CGRectGetMidY(f) || CGRectGetMaxY(r)<CGRectGetMidY(f))continue;
        if(CGRectGetMinX(r)>CGRectGetMinX(f)+1 || CGRectGetMaxX(r)<CGRectGetMaxX(f)-1)continue;
        CGFloat area=r.size.width*r.size.height;
        if(parentW>0 && r.size.width>=parentW-6){if(area<bestWide){bestWide=area;wide=s;}continue;}
        if(area<best){best=area;paint=s;}
    }
    if(!paint)paint=wide;
    if(!paint){[self skip:field because:@"输入框旁边没有底色" retry:YES];return;}
    [self field:paint host:field];
}
// System search bars (新的朋友's MMUISearchBar): the field's background view.
- (void)systemSearchBar:(UISearchBar *)bar {
    for(UIView *v=bar.superview;v;v=v.superview)if(WXGIsPluginView(v))return;
    if(_wcSearchBar)for(UIView *v in WXGLocalViews(bar,80))if([v isKindOfClass:_wcSearchBar] && !v.hidden && v.alpha>.01) {
        [self skip:bar because:@"被 WCSearchBar 盖住"];return;   // the WCSearchBar's own field is used
    }
    UITextField *field=nil;
    if([bar respondsToSelector:@selector(searchTextField)])field=bar.searchTextField;
    if(!field){id value=WXGRead(bar,@"searchField");if([value isKindOfClass:UITextField.class])field=value;}
    if(!field || field.hidden || field.alpha<.01 || field.bounds.size.height<24 || field.bounds.size.height>60){[self skip:bar because:@"没有可用的输入框" retry:YES];return;}
    WXGLocalEntry *known=WXGLocalEntryOfAnchor(field);
    UIView *background=known.paint && known.paint.superview==field?known.paint:nil;
    if(!background)for(UIView *v in field.subviews) {
        if(WXGIsPluginView(v) || [v isKindOfClass:UILabel.class] || [v isKindOfClass:UIControl.class])continue;
        if([NSStringFromClass(v.class) rangeOfString:@"Background"].location==NSNotFound)continue;
        if(v.bounds.size.width>=field.bounds.size.width*.8 && v.bounds.size.height>=field.bounds.size.height*.6){background=v;break;}
    }
    if(!background){[self skip:bar because:@"输入框没有背景视图" retry:YES];return;}
    if([self searchGlassClashes:field material:field.bounds host:bar])return;   // FIX109 E
    // The field's own bounds: its background view's frame is set later in this
    // layout pass (re-measured before the commit anyway). FIX114 E (user: the
    // capsule is not the size of WeChat's own field): the box that background
    // draws once it has its own size (a picture taller than the text field).
    __weak UITextField *weakField=field;
    [self mount:WXGLocalSearch host:bar anchor:field paint:background below:nil measure:nil frame:^CGRect{
            UITextField *f=weakField;if(!f)return CGRectNull;
            CGRect box=WXGSearchFieldBox(f);return CGRectIsNull(box)?f.bounds:box;}
         radius:0 button:nil prepare:^(WXGStateBag *states){[states hide:background];}];
}
// A button's background image view: the image view showing its current
// background image (or, once cleared, the one we cleared).
- (UIImageView *)backgroundViewOf:(UIButton *)button known:(WXGLocalEntry *)known {
    if([known.below isKindOfClass:UIImageView.class] && known.below.superview==button)return (UIImageView *)known.below;
    UIImage *image=button.currentBackgroundImage;
    if(image)for(UIView *v in button.subviews)if([v isKindOfClass:UIImageView.class] && !WXGIsPluginView(v) && ((UIImageView *)v).image==image)return (UIImageView *)v;
    id value=WXGRead(button,@"_backgroundView");
    if([value isKindOfClass:UIImageView.class] && ((UIView *)value).superview==button)return value;
    return nil;
}
// The plus panel's AttachmentButtons.
- (void)tile:(UIView *)view {
    if(![view isKindOfClass:UIButton.class])return;
    UIButton *button=(UIButton *)view;WXGLocalEntry *known=WXGLocalEntryOfAnchor(button);
    UIImageView *background=[self backgroundViewOf:button known:known];
    if(!background || background.bounds.size.width<24 || background.bounds.size.height<24){[self skip:button because:@"方块没有背景图"];return;}
    CGSize size=background.bounds.size;
    CGFloat native=known.nativeRadius;
    if(native<=0)native=WXGLocalImageCorner(button.currentBackgroundImage,size);
    if(native<=1)native=MIN(size.width,size.height)*.22;
    // FIX107 B: the setting's continuous radius, 0 = WeChat's own.
    CGFloat (^radiusFor)(CGSize)=WXGLocalRadiusSetting(@"localTileRadius",native);
    [self mount:WXGLocalTile host:button anchor:button paint:background below:background measure:background radius:radiusFor(size) button:button
        prepare:^(WXGStateBag *states){[states clearImagePaint:background];}];
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(button);
    if(entry.mounted){entry.nativeRadius=native;entry.radiusFor=radiusFor;entry.radiusRevision=WXGConfigRevision();}
}
// The emoji board's 发送 / 删除.
- (void)keysIn:(UIView *)host {
    // Not into the emoji grid's own cells (small cells: the faces), only the
    // board's page cells (the keys sit beside the grid in the page cell).
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:host];
    for(NSUInteger i=0;i<queue.count && queue.count<500;i++) {
        UIView *v=queue[i];
        if(i && ([v isKindOfClass:UICollectionViewCell.class] || [v isKindOfClass:UITableViewCell.class]) &&
           (v.bounds.size.width<120 || v.bounds.size.height<120))continue;
        for(UIView *child in v.subviews)if(!WXGIsPluginView(child))[queue addObject:child];
    }
    for(UIView *v in queue) {
        if(![v isKindOfClass:UIButton.class])continue;
        NSArray *actions=WXGActionNames((id)v);
        BOOL send=[actions containsObject:@"onTapSendButton"],remove=[actions containsObject:@"onTapDeleteButton"];
        if(send || remove)[self key:(UIButton *)v send:send host:host];
    }
}
- (void)key:(UIButton *)button send:(BOOL)send host:(UIView *)host {
    (void)host;   // the button is its own host: the board and the page cell both find it
    CGRect b=button.bounds;
    if(b.size.width<24 || b.size.height<24 || b.size.height>64){[self skip:button because:@"按键尺寸不对"];return;}
    WXGLocalEntry *known=WXGLocalEntryOfAnchor(button);
    UIImageView *background=[self backgroundViewOf:button known:known];
    if(background && (background.bounds.size.width<b.size.width*.8 || background.bounds.size.height<b.size.height*.8))background=nil;
    [self mount:WXGLocalKey host:button anchor:button paint:background?:button below:background measure:button radius:0 button:button
        prepare:^(WXGStateBag *states){
            [states allowOverflow:button];   // WeChat rounds it by clipping (4.8 pt)
            [states clear:button];
            if(background)[states clearImagePaint:background];
        }];
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(button);
    if(entry.send!=send){entry.send=send;entry.tintKnown=NO;}
}
// The emoji board's group strip: each cell's white square (hidden unless selected).
// FIX109: the glass is no longer inside the square (its fill cleared) but
// right above it, and the square's pixels are masked away: WeChat keeps
// showing and hiding (or filling and emptying) its square as it likes, and
// the glass shows exactly while the square would, at once (a new group's
// glass stayed hidden, the old one's white came back: the glass "went").
// The radius setting is read again on every settings change.
static char WXGLocalTabPaintKey;
static CGFloat WXGLocalSelectionShown(UIView *paint,UIView *anchor) {
    if(!paint || paint.superview!=anchor)return 0;
    UIColor *fill=paint.backgroundColor;
    CGFloat a=fill?CGColorGetAlpha([fill resolvedColorWithTraitCollection:paint.traitCollection].CGColor):0;
    if(a<.02)return 0;
    return paint.hidden?0:WXGClamp(paint.alpha,0,1);
}
- (void)tabCell:(UIView *)cell {
    WXGLocalEntry *known=objc_getAssociatedObject(cell,&WXGLocalHostKey);
    UIView *paint=known.host==cell && known.paint.superview==known.anchor && [known.paint isDescendantOfView:cell]?known.paint:nil;
    // A plain view with nothing inside, rounded, nearly the cell's size: one
    // already known, filled or hidden first; else (emptied while not
    // selected) one showing nothing.
    if(!paint)for(NSUInteger pass=0;pass<2 && !paint;pass++)for(UIView *v in WXGLocalViews(cell,24)) {
        if(v==cell || v.class!=UIView.class || !WXGLocalOnlyPluginChildren(v) || v.layer.cornerRadius<=0 || !v.superview)continue;
        if(!pass && !objc_getAssociatedObject(v,&WXGLocalTabPaintKey) && !WXGLocalFilled(v) && !v.hidden)continue;
        CGRect r=[v convertRect:v.bounds toView:cell];
        if(r.size.width>=cell.bounds.size.width*.6 && r.size.height>=cell.bounds.size.height*.6){paint=v;break;}
    }
    if(!paint){[self skip:cell because:@"分组格里没有选中底色" retry:YES];return;}
    objc_setAssociatedObject(paint,&WXGLocalTabPaintKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *anchor=paint.superview;
    // FIX107 B: the setting's continuous radius, 0 = WeChat's own (its layer's, 8 pt).
    CGFloat native=known.nativeRadius>0?known.nativeRadius:MAX(6,paint.layer.cornerRadius);
    CGFloat (^radiusFor)(CGSize)=WXGLocalRadiusSetting(@"localTabRadius",native);
    [self mount:WXGLocalTab host:cell anchor:anchor paint:paint below:paint measure:paint radius:radiusFor(paint.bounds.size) button:nil
        prepare:^(WXGStateBag *states){[states conceal:paint];}];
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(anchor);if(!entry.mounted)return;
    entry.nativeRadius=native;entry.radiusFor=radiusFor;entry.radiusRevision=WXGConfigRevision();
    __weak UIView *weakPaint=paint,*weakAnchor=anchor;
    entry.shown=^CGFloat{return WXGLocalSelectionShown(weakPaint,weakAnchor);};
    [self followShown:entry immediately:YES];
}
// The forward / share sheet: its blur goes, one glass for the whole background.
- (void)sheet:(UIView *)container {
    CGRect b=container.bounds;
    if(b.size.width<200 || b.size.height<120){[self skip:container because:@"弹层太小"];return;}
    WXGLocalEntry *known=WXGLocalEntryOfAnchor(container);
    UIVisualEffectView *effect=[known.paint isKindOfClass:UIVisualEffectView.class] && known.paint.superview==container?(UIVisualEffectView *)known.paint:nil;
    if(!effect)for(UIView *v in container.subviews)
        if([v isKindOfClass:UIVisualEffectView.class] && !WXGIsPluginView(v) && v.bounds.size.width>=b.size.width*.9 && v.bounds.size.height>=b.size.height*.8){effect=(id)v;break;}
    if(!effect){[self skip:container because:@"弹层里没有毛玻璃背景"];return;}
    if(effect.contentView.subviews.count){[self skip:container because:@"毛玻璃里有内容，保留原样"];return;}
    [self mount:WXGLocalSheet host:container anchor:container paint:effect below:nil measure:container radius:WXGLocalSheetRadius button:nil
        prepare:^(WXGStateBag *states){[states hide:effect];}];
}

// FIX108 helpers. The plugin's title-bar glass height (its buttons' size),
// clamped like the host's in a short (landscape) bar.
static UINavigationBar *WXGLocalBarOf(UIView *view) {
    NSUInteger depth=0;for(UIView *p=view;p && depth<14;p=p.superview,depth++)if([p isKindOfClass:UINavigationBar.class])return (UINavigationBar *)p;
    return nil;
}
static WXGMetrics WXGLocalBarMetrics(UIView *view) {
    UIWindow *w=view.window;
    WXGMetrics m=WXGMeasure(w.bounds.size.width-w.safeAreaInsets.left-w.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
    UINavigationBar *bar=WXGLocalBarOf(view);CGFloat height=bar?bar.bounds.size.height:44;
    if(m.button>MAX(36,height))m=WXGMeasure(440*MAX(36,height)/44,1);
    return m;
}
static CGRect WXGLocalFrameIn(UIView *v,UIView *ancestor,CGRect r);
// FIX114 C (user: the title capsules on the home page and in a chat cut off
// at the top): WeChat's title text sits a third of a point above the bar's
// middle there, so its capsule (the bar's height) stood that far above the
// bar, and what clips the bar took its top line. A capsule is kept inside
// its title bar (by frames: no content shift counts), or, with none around
// it (the home page's row), inside the views that clip it while the title
// row is not moved down (moved, those are opened). Only small corrections
// (a title placed higher or lower on purpose, or scrolled past a clip, is
// left as it is: its capsule never parts from its text).
static CGRect WXGLocalInsideBar(UIView *anchor,CGRect r) {
    if(CGRectIsNull(r) || CGRectIsEmpty(r) || !anchor.window)return r;
    UINavigationBar *bar=WXGLocalBarOf(anchor);CGFloat lo,hi;
    if(bar) {
        CGFloat top=WXGLocalFrameIn(anchor,bar,CGRectZero).origin.y;
        lo=CGRectGetMinY(bar.bounds)-top;hi=CGRectGetMaxY(bar.bounds)-top;
    }else {
        if(WXGTitleRowOffset(1)>.01)return r;
        CGRect clip=CGRectInfinite;NSUInteger depth=0;
        // (review) not past a list: a title WeChat moves into its list (the
        // home pull-down) scrolls past the list's edge, and is not held there.
        for(UIView *v=anchor.superview;v && depth<12 && ![v isKindOfClass:UIWindow.class] && ![v isKindOfClass:UIScrollView.class];v=v.superview,depth++)
            if(v.clipsToBounds)clip=CGRectIntersection(clip,[v convertRect:v.bounds toView:anchor]);
        if(CGRectIsInfinite(clip) || CGRectIsNull(clip))return r;
        lo=CGRectGetMinY(clip);hi=CGRectGetMaxY(clip);
    }
    if(hi-lo<r.size.height-.01)return r;
    CGFloat y=WXGClamp(r.origin.y,lo,hi-r.size.height);
    if(fabs(y-r.origin.y)>2)return r;
    r.origin.y=y;return r;
}
static BOOL WXGLocalLight(UIColor *color,UITraitCollection *traits) {
    if(!color)return NO;
    CGFloat r=0,g=0,b=0,a=0;
    if(![[color resolvedColorWithTraitCollection:traits] getRed:&r green:&g blue:&b alpha:&a] || a<.3)return NO;
    return .299*r+.587*g+.114*b>.65;
}
static BOOL WXGLocalShownIn(UIView *v,UIView *root) {
    for(UIView *p=v;p && p!=root;p=p.superview)if(p.hidden || p.alpha<.01)return NO;
    return YES;
}
// Where a label's text is drawn in its bounds (vertically centred; by its alignment across).
static CGRect WXGLocalTextRect(UILabel *label) {
    CGRect b=label.bounds,t=[label textRectForBounds:b limitedToNumberOfLines:label.numberOfLines];
    CGFloat w=MIN(t.size.width,b.size.width),h=MIN(t.size.height,b.size.height),x=0;
    NSTextAlignment alignment=label.textAlignment;
    if(alignment==NSTextAlignmentNatural)alignment=label.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft?NSTextAlignmentRight:NSTextAlignmentLeft;
    if(alignment==NSTextAlignmentCenter)x=(b.size.width-w)*.5;else if(alignment==NSTextAlignmentRight)x=b.size.width-w;
    return CGRectMake(b.origin.x+x,b.origin.y+(b.size.height-h)*.5,w,h);
}
// FIX108 B: what a title's rectangle depends on, cheaply (no text layout):
// its subviews and theirs (identity, shown, alpha, frame), the labels' text,
// font, colour and lines, a running spinner, the window width, the size
// setting, the bar height.
static NSUInteger WXGLocalViewKey(UIView *v,NSUInteger h) {
    CGRect f=v.frame;
    h=h*131+(NSUInteger)(uintptr_t)(__bridge void *)v;
    h=h*131+(v.hidden?1:0)+(NSUInteger)(v.alpha*100)*3;
    h=h*131+(NSUInteger)(long)(f.origin.x*8)*7+(NSUInteger)(long)(f.origin.y*8)*13+(NSUInteger)(long)(f.size.width*8)*17+(NSUInteger)(long)(f.size.height*8)*19;
    if([v isKindOfClass:UILabel.class]){UILabel *l=(UILabel *)v;h=h*131+l.text.hash+l.attributedText.hash*3+l.font.hash*5+l.textColor.hash*7+(NSUInteger)l.textAlignment+(NSUInteger)l.numberOfLines*11;}
    else if([v isKindOfClass:UIActivityIndicatorView.class])h=h*131+(((UIActivityIndicatorView *)v).isAnimating?7:1);
    else if([v isKindOfClass:UIImageView.class])h=h*131+(NSUInteger)(uintptr_t)(__bridge void *)((UIImageView *)v).image;
    return h*131+v.subviews.count;
}
static NSUInteger WXGLocalTitleKey(UIView *view) {
    UIWindow *w=view.window;UINavigationBar *bar=WXGLocalBarOf(view);
    NSUInteger h=(NSUInteger)(w.bounds.size.width*4)*31+(NSUInteger)(WXGPreferences.shared.sizeScale*1000)*17+(NSUInteger)(bar.bounds.size.height*4);
    NSUInteger n=0;
    for(UIView *v in view.subviews) {
        if(WXGIsPluginView(v))continue;if(++n>16)break;
        h=WXGLocalViewKey(v,h);
        NSUInteger m=0;
        for(UIView *c in v.subviews) {
            if(WXGIsPluginView(c))continue;if(++m>8)break;h=WXGLocalViewKey(c,h);
            // FIX114 A: one level more (a label WeChat hides there, three down,
            // left the cached "shown" stale: an empty capsule stayed).
            NSUInteger k=0;for(UIView *d in c.subviews){if(WXGIsPluginView(d))continue;if(++k>8)break;h=WXGLocalViewKey(d,h);}
        }
    }
    return h;
}
static CGFloat WXGLocalAlphaIn(UIView *v,UIView *root) {
    CGFloat a=1;for(UIView *p=v;p && p!=root;p=p.superview){if(p.hidden)return 0;a*=p.alpha;}
    return a;
}
static char WXGLocalTitleCacheKey;
// The title's ink (its shown labels' text, icons, a spinning 收取中 indicator)
// with the capsule around it, in the title view; null for no text, a long or
// two-line title. FIX108 C: also how visible the text is (the most visible
// label's opacity within the title view): the glass shows only as much (the
// home pull-down hides the bar's labels, not the title view). Cached on the
// view until its key changes.
static CGRect WXGLocalTitleFrame(UIView *view,UIColor **ink,CGFloat *visibility) {
    if(visibility)*visibility=0;
    UIWindow *w=view.window;if(!w)return CGRectNull;
    NSUInteger key=WXGLocalTitleKey(view);
    NSArray *cached=objc_getAssociatedObject(view,&WXGLocalTitleCacheKey);
    if(cached.count>=4 && [cached[0] unsignedIntegerValue]==key) {
        if(ink)*ink=cached[2]==NSNull.null?nil:cached[2];
        if(visibility)*visibility=[cached[3] doubleValue];
        return [cached[1] CGRectValue];
    }
    CGRect box=CGRectNull,result=CGRectNull;UILabel *main=nil;CGFloat shown=0;BOOL hiddenText=NO;
    for(UIView *v in WXGLocalViews(view,40)) {
        if(v==view || WXGIsPluginView(v))continue;
        if(!WXGLocalShownIn(v,view)) {
            // FIX108 F: text WeChat has hidden (the home pull-down), not text
            // that is momentarily empty: the glass goes at once.
            if([v isKindOfClass:UILabel.class] && (((UILabel *)v).text.length || ((UILabel *)v).attributedText.length))hiddenText=YES;
            continue;
        }
        CGRect r;
        if([v isKindOfClass:UILabel.class]) {
            UILabel *label=(UILabel *)v;if(!label.text.length && !label.attributedText.length)continue;
            r=[label convertRect:WXGLocalTextRect(label) toView:view];
            if(!main || label.font.pointSize*r.size.width>main.font.pointSize*main.bounds.size.width)main=label;
            shown=MAX(shown,WXGLocalAlphaIn(label,view));
        }else if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && v.bounds.size.width>=6 && v.bounds.size.height>=6)r=[v convertRect:v.bounds toView:view];
        else if([v isKindOfClass:UIActivityIndicatorView.class] && ((UIActivityIndicatorView *)v).isAnimating)r=[v convertRect:v.bounds toView:view];
        else continue;
        box=CGRectIsNull(box)?r:CGRectUnion(box,r);
    }
    if(main && !CGRectIsNull(box) && box.size.width>=4 && box.size.width<=w.bounds.size.width*.6 && box.size.height<=30) {
        WXGMetrics m=WXGLocalBarMetrics(view);
        CGFloat h=m.button,width=WXGCapsuleWidth(box.size.width,0,h,14*m.scale,w.bounds.size.width*.7);
        result=CGRectMake(CGRectGetMidX(box)-width*.5,CGRectGetMidY(box)-h*.5,width,h);
    }else shown=hiddenText && !main?-1:0;   // -1: hidden by WeChat (hide now); 0: nothing yet (debounced)
    UIColor *color=main.textColor;
    objc_setAssociatedObject(view,&WXGLocalTitleCacheKey,@[@(key),[NSValue valueWithCGRect:result],color?:NSNull.null,@(shown)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(ink)*ink=color;if(visibility)*visibility=shown;
    return result;
}
// The title in WeChat's title view (首页 MFTitleView, the others' MMTitleView).
- (void)titleView:(UIView *)view {
    if(view.layer.mask){[self skip:view because:@"标题由插件自己画（聊天页）"];return;}
    BOOL wasMounted=WXGLocalEntryOfAnchor(view).mounted;   // FIX108 F
    // A glass already there stays through a one-pass collapse (mount keeps it).
    if(CGRectIsNull(WXGLocalTitleFrame(view,NULL,NULL)) && !WXGLocalEntryOfAnchor(view).mounted){[self skip:view because:@"没有标题文字，或标题太长 / 两行" retry:YES];return;}
    __weak UIView *weakView=view;
    [self mount:WXGLocalTitle host:view anchor:view paint:nil below:nil measure:nil frame:^CGRect{UIView *v=weakView;return v?WXGLocalInsideBar(v,WXGLocalTitleFrame(v,NULL,NULL)):CGRectNull;}
         radius:0 button:nil prepare:^(WXGStateBag *states){[states allowOverflow:view];}];
    [self setInk:^UIColor *{UIColor *c=nil;UIView *v=weakView;if(v)WXGLocalTitleFrame(v,&c,NULL);return c;} of:view];
    WXGLocalEntryOfAnchor(view).titleMeasure=^CGRect(UIColor **ink,CGFloat *shown){UIView *v=weakView;if(!v){if(shown)*shown=0;return CGRectNull;}return WXGLocalInsideBar(v,WXGLocalTitleFrame(v,ink,shown));};
    [self followShown:WXGLocalEntryOfAnchor(view) immediately:!wasMounted];
}
// FIX109: a title the bar draws itself (navigationItem.title: 插件): its label
// is a direct child of the bar's content view (iOS 16 and later: inside a
// title control there). Not a title view's page (those have no such label).
static UILabel *WXGLocalSystemTitleLabel(UIView *content,BOOL *hiddenText) {
    UILabel *best=nil;
    for(UIView *v in content.subviews) {
        if(WXGIsPluginView(v))continue;
        UILabel *label=nil;
        if([v isKindOfClass:UILabel.class])label=(UILabel *)v;
        else if([NSStringFromClass(v.class) containsString:@"TitleControl"]) {
            if(v.hidden || v.alpha<.01 || v.layer.mask){if(hiddenText)*hiddenText=YES;continue;}
            for(UIView *c in v.subviews)if([c isKindOfClass:UILabel.class]){label=(UILabel *)c;break;}
        }
        if(!label || (!label.text.length && !label.attributedText.length))continue;
        if(label.hidden || label.alpha<.01 || label.layer.mask){if(hiddenText)*hiddenText=YES;continue;}
        if(!best || WXGLocalAlphaIn(label,content)>WXGLocalAlphaIn(best,content))best=label;
    }
    return best;
}
static char WXGLocalSystemTitleCacheKey;
static CGRect WXGLocalSystemTitleFrame(UIView *content,UIColor **ink,CGFloat *visibility) {
    if(visibility)*visibility=0;if(ink)*ink=nil;
    UIWindow *w=content.window;if(!w)return CGRectNull;
    BOOL hiddenText=NO;UILabel *label=WXGLocalSystemTitleLabel(content,&hiddenText);
    if(!label){if(visibility)*visibility=hiddenText?-1:0;return CGRectNull;}
    UINavigationBar *bar=WXGLocalBarOf(content);
    NSUInteger key=WXGLocalViewKey(label,(NSUInteger)(w.bounds.size.width*4)*31+(NSUInteger)(WXGPreferences.shared.sizeScale*1000)*17+(NSUInteger)(bar.bounds.size.height*4)+(NSUInteger)(content.bounds.size.height*8)*7);
    if(label.superview!=content)key=WXGLocalViewKey(label.superview,key);
    NSArray *cached=objc_getAssociatedObject(content,&WXGLocalSystemTitleCacheKey);
    CGRect result=CGRectNull;CGFloat shown=WXGLocalAlphaIn(label,content);
    if(cached.count==2 && [cached[0] unsignedIntegerValue]==key)result=[cached[1] CGRectValue];
    else {
        // FIX114 C (review): by frames (the content view's own move down must not count).
        CGRect box=WXGLocalFrameIn(label,content,WXGLocalTextRect(label));
        if(box.size.width>=4 && box.size.width<=w.bounds.size.width*.6 && box.size.height<=30) {
            WXGMetrics m=WXGLocalBarMetrics(content);
            CGFloat h=m.button,width=WXGCapsuleWidth(box.size.width,0,h,14*m.scale,w.bounds.size.width*.7);
            // Inside the content view (it clips on some pages), centred on the text otherwise.
            CGFloat y=CGRectGetMidY(box)-h*.5,height=content.bounds.size.height;
            if(height>=h)y=WXGClamp(y,0,height-h);
            result=CGRectMake(CGRectGetMidX(box)-width*.5,y,width,h);
        }
        objc_setAssociatedObject(content,&WXGLocalSystemTitleCacheKey,@[@(key),[NSValue valueWithCGRect:result]],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(CGRectIsNull(result))shown=0;
    if(ink)*ink=label.textColor;if(visibility)*visibility=shown;
    return result;
}
// FIX112: where the title's capsule is (or would be: the same geometry) in the
// window, for the host's buttons to sit at its height: the page's title view
// (WeChat's MMTitleView: most pages; measured even when the host conceals it,
// a chat's), else the bar's own title text (not when the bar's content is the
// host's, masked).
CGRect WXGLocalTitleCapsuleRect(UINavigationBar *bar,UIView *titleView,UIWindow *window) {
    static Class content;static dispatch_once_t once;dispatch_once(&once,^{content=NSClassFromString(@"_UINavigationBarContentView");});
    if(!bar || !window || bar.window!=window)return CGRectNull;
    if(titleView && titleView.window==window && !titleView.hidden && [titleView isDescendantOfView:bar]) {
        CGFloat shown=0;CGRect r=WXGLocalInsideBar(titleView,WXGLocalTitleFrame(titleView,NULL,&shown));
        // FIX114 C: by frames up to the bar (the bar's content drawn moved
        // down by the title row's offset must not count: the host adds it).
        if(!CGRectIsNull(r) && shown>.5)return [bar convertRect:WXGLocalFrameIn(titleView,bar,r) toView:window];
    }
    if(!content)return CGRectNull;
    for(UIView *v in bar.subviews) {
        if(![v isKindOfClass:content] || v.hidden || v.alpha<.01 || v.layer.mask)continue;
        CGFloat shown=0;CGRect r=WXGLocalSystemTitleFrame(v,NULL,&shown);
        if(CGRectIsNull(r) || shown<.5)continue;
        return [v convertRect:r toView:window];
    }
    return CGRectNull;
}
- (void)systemTitle:(UIView *)content {
    if(content.layer.mask){[self skip:content because:@"导航栏内容被遮住（宿主接管）"];return;}   // reassert would take it off again
    BOOL wasMounted=WXGLocalEntryOfAnchor(content).mounted;
    if(CGRectIsNull(WXGLocalSystemTitleFrame(content,NULL,NULL)) && !wasMounted){[self skip:content because:@"导航栏没有自己的标题文字（用的是标题视图）"];return;}
    __weak UIView *weakContent=content;
    [self mount:WXGLocalTitle host:content anchor:content paint:nil below:nil measure:nil frame:^CGRect{UIView *v=weakContent;return v?WXGLocalSystemTitleFrame(v,NULL,NULL):CGRectNull;}
         radius:0 button:nil prepare:nil];
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(content);if(!entry.mounted)return;
    [self setInk:^UIColor *{UIColor *c=nil;UIView *v=weakContent;if(v)WXGLocalSystemTitleFrame(v,&c,NULL);return c;} of:content];
    entry.titleMeasure=^CGRect(UIColor **ink,CGFloat *shown){UIView *v=weakContent;if(!v){if(shown)*shown=0;return CGRectNull;}return WXGLocalSystemTitleFrame(v,ink,shown);};
    [self followShown:entry immediately:!wasMounted];
}
// The photo picker's album title: WeChat's own grey pill (a button's fill) becomes the glass.
- (void)dropableTitle:(UIView *)view {
    UIButton *pill=nil;
    for(UIView *v in view.subviews) {
        if(![v isKindOfClass:UIButton.class] || WXGIsPluginView(v))continue;
        CGSize b=v.bounds.size;BOOL ours=WXGLocalEntryOfAnchor(v).mounted;
        if(b.height>=24 && b.height<=48 && b.width>=b.height && (ours || (WXGLocalFilled(v) && v.layer.cornerRadius>=8))){pill=(UIButton *)v;break;}
    }
    if(!pill){[self skip:view because:@"相册标题没有底色胶囊" retry:YES];return;}
    [self mount:WXGLocalTitle host:view anchor:pill paint:pill below:nil measure:pill radius:0 button:pill
        prepare:^(WXGStateBag *states){[states clear:pill];[states allowOverflow:pill];}];
    __weak UIView *weakView=view;
    [self setInk:^UIColor *{UIView *v=weakView;for(UIView *x in v.subviews)if([x isKindOfClass:UILabel.class] && !x.hidden)return ((UILabel *)x).textColor;return nil;} of:pill];
}
// A title-bar button's icon / title without UIButton's lazy getters (they
// would make the image view or label of a button that has none).
static void WXGLocalButtonParts(UIButton *button,UIImageView **icon,UILabel **title) {
    for(UIView *v in button.subviews) {
        if(WXGIsPluginView(v) || v.hidden || v.alpha<.01)continue;
        if(icon && !*icon && [v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && v.bounds.size.width>=8 && v.bounds.size.height>=8)*icon=(UIImageView *)v;
        else if(title && !*title && [v isKindOfClass:UILabel.class] && (((UILabel *)v).text.length || ((UILabel *)v).attributedText.length) && v.bounds.size.width>=4)*title=(UILabel *)v;
    }
}
// A round glass behind the icon (as wide as the gap to the next button allows),
// a capsule behind a title, or around both (a back button with a count).
// FIX109: the photo picker's close button (left of WeChat's album pill, an
// icon) as tall as that pill, so the two glasses in the bar match; every other
// button as before. Looked at a few times a second.
static char WXGLocalMatchKey;
static CGFloat WXGLocalNavMatch(UIButton *button) {
    NSArray *cached=objc_getAssociatedObject(button,&WXGLocalMatchKey);CFTimeInterval now=CACurrentMediaTime();
    if(cached.count==2 && now-[cached[0] doubleValue]<.25)return [cached[1] doubleValue];
    static Class drop;static dispatch_once_t once;dispatch_once(&once,^{drop=NSClassFromString(@"MMDropableTitleView");});
    CGFloat match=0;UINavigationBar *bar=WXGLocalBarOf(button);
    if(bar && drop && CGRectGetMidX([button convertRect:button.bounds toView:bar])<CGRectGetMidX(bar.bounds)*.6)
        for(UIView *v in WXGLocalViews(bar,120)) {
            if(![v isKindOfClass:drop] || !WXGLocalShownIn(v,bar))continue;
            for(UIView *c in v.subviews) {
                if(![c isKindOfClass:UIButton.class] || WXGIsPluginView(c))continue;
                CGSize b=c.bounds.size;if(b.height>=24 && b.height<=48 && b.width>=b.height){match=b.height;break;}
            }
            break;
        }
    objc_setAssociatedObject(button,&WXGLocalMatchKey,@[@(now),@(match)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return match;
}
// FIX114 B (review): a subview's rectangle in an ancestor by frames alone:
// the ancestor's content shift (its layer's sublayerTransform, FIX114 B)
// must not count, or the glass placed from it would be shifted twice and
// the side shift measured from shifted icons would undo itself.
static CGRect WXGLocalFrameIn(UIView *v,UIView *ancestor,CGRect r) {
    UIView *p=v;
    for(NSUInteger depth=0;p && p!=ancestor && depth<16;p=p.superview,depth++) {
        r.origin.x+=p.frame.origin.x-p.bounds.origin.x;r.origin.y+=p.frame.origin.y-p.bounds.origin.y;
    }
    return p==ancestor?r:[v convertRect:r toView:ancestor];
}
static CGRect WXGLocalNavButtonFrame(UIButton *button,CGFloat limit,UIColor **ink) {
    UIWindow *w=button.window;if(!w)return CGRectNull;
    WXGMetrics m=WXGLocalBarMetrics(button);CGFloat h=MIN(m.button,MAX(28,limit));
    UIImageView *icon=nil;UILabel *title=nil;WXGLocalButtonParts(button,&icon,&title);
    if(icon && !title){CGFloat match=WXGLocalNavMatch(button);if(match>0)h=MIN(match,MAX(28,limit));}
    if(ink)*ink=title?title.textColor:icon.image.renderingMode==UIImageRenderingModeAlwaysOriginal?nil:icon.tintColor;
    CGRect iconRect=icon?WXGLocalFrameIn(icon,button,icon.bounds):CGRectNull;
    CGRect titleRect=title?WXGLocalFrameIn(title,button,WXGLocalTextRect(title)):CGRectNull;
    if(icon && !title)return CGRectMake(CGRectGetMidX(iconRect)-h*.5,CGRectGetMidY(iconRect)-h*.5,h,h);
    if(!title)return CGRectNull;
    CGRect ink2=icon?CGRectUnion(iconRect,titleRect):titleRect;
    CGFloat width=WXGCapsuleWidth(ink2.size.width,0,h,(icon?10:14)*m.scale,w.bounds.size.width*.36);
    width=MIN(width,MAX(h,limit));   // FIX108 C: not into the next button's glass
    return CGRectMake(CGRectGetMidX(ink2)-width*.5,CGRectGetMidY(titleRect)-h*.5,width,h);
}
// The room to the nearest other button on the same row of the bar (centre to
// centre, less a gap): two round glasses must not overlap.
static CGFloat WXGLocalNeighbourRoom(UIButton *button) {
    UINavigationBar *bar=WXGLocalBarOf(button);if(!bar)return CGFLOAT_MAX;
    CGRect mine=[button convertRect:button.bounds toView:bar];CGFloat room=CGFLOAT_MAX;
    for(UIView *v in WXGLocalViews(bar,120)) {
        if(v==button || ![v isKindOfClass:UIButton.class] || WXGIsPluginView(v) || !WXGLocalShownIn(v,bar) || [v isDescendantOfView:button] || [button isDescendantOfView:v])continue;
        CGRect r=[v convertRect:v.bounds toView:bar];
        if(fabs(CGRectGetMidY(r)-CGRectGetMidY(mine))>(r.size.height+mine.size.height)*.25)continue;
        room=MIN(room,fabs(CGRectGetMidX(r)-CGRectGetMidX(mine))-4);
    }
    return room;
}
// FIX108 E: the room looked at a few times a second, not every turn (a walk of the bar).
static char WXGLocalRoomKey;
static CGFloat WXGLocalNavRoom(UIButton *button) {
    NSArray *cached=objc_getAssociatedObject(button,&WXGLocalRoomKey);CFTimeInterval now=CACurrentMediaTime();
    if(cached.count==2 && now-[cached[0] doubleValue]<.25)return [cached[1] doubleValue];
    CGFloat room=WXGLocalNeighbourRoom(button);
    objc_setAssociatedObject(button,&WXGLocalRoomKey,@[@(now),@(room)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return room;
}
// FIX114 B (user: on some pages the top buttons stay where WeChat has them,
// their glass crowded against the screen's side): the buttons of a side of
// the bar are drawn shifted together (their contents: WeChat's icon / text and
// the glass, a subview) so the outermost one's glass keeps the title row's
// margin (safe area + m.edge, as the plugin's own buttons); only inward. The
// buttons themselves and their touches stay where WeChat put them. Looked at
// a few times a second per bar side.
static char WXGLocalSideShiftKey;
static CGFloat WXGLocalSideShift(UIButton *button) {
    UINavigationBar *bar=WXGLocalBarOf(button);UIWindow *w=button.window;if(!bar || !w)return 0;
    CGFloat width=w.bounds.size.width;
    CGRect mine=[button convertRect:button.bounds toView:w];BOOL left=CGRectGetMidX(mine)<width*.5;
    NSArray *cached=objc_getAssociatedObject(bar,&WXGLocalSideShiftKey);CFTimeInterval now=CACurrentMediaTime();
    if(cached.count==3 && now-[cached[0] doubleValue]<.25)return [cached[left?1:2] doubleValue];
    CGFloat shift[2]={0,0};UIButton *outer[2]={nil,nil};CGFloat outerX[2]={CGFLOAT_MAX,-CGFLOAT_MAX};
    for(UIView *v in WXGLocalViews(bar,120)) {
        if(![v isKindOfClass:UIButton.class] || WXGIsPluginView(v) || !WXGLocalShownIn(v,bar) || ![WXGIntegrationHost.shared leavesNavigationControlNative:v])continue;
        CGRect r=[v convertRect:v.bounds toView:w];if(r.size.width<8 || r.size.height<8)continue;
        if(fabs(CGRectGetMidY(r)-CGRectGetMidY(mine))>MAX(r.size.height,mine.size.height)*.5)continue;
        int side=CGRectGetMidX(r)<width*.5?0:1;
        if(side==0?CGRectGetMinX(r)<outerX[0]:CGRectGetMaxX(r)>outerX[1]){outer[side]=(UIButton *)v;outerX[side]=side==0?CGRectGetMinX(r):CGRectGetMaxX(r);}
    }
    // (review) Only when the outermost one has a glass of ours: a button left
    // without (its own background, a green 完成) is not moved, and the others
    // must not move toward it.
    for(int side=0;side<2;side++) {
        WXGLocalEntry *e=outer[side]?WXGLocalEntryOfAnchor(outer[side]):nil;
        if(!e.mounted || e.kind!=WXGLocalNavButton)outer[side]=nil;
    }
    WXGMetrics m=WXGLocalBarMetrics(button);CGFloat scale=w.screen.scale?:3;
    for(int side=0;side<2;side++) {
        UIButton *b=outer[side];if(!b)continue;
        CGRect glass=WXGLocalNavButtonFrame(b,WXGLocalNavRoom(b),NULL);if(CGRectIsNull(glass))continue;
        CGRect r=[b convertRect:glass toView:w];
        // FIX114 C: the margin is a setting (顶部按钮离屏幕两边); both ways
        // (a smaller margin than WeChat's moves its buttons out).
        CGFloat edge=WXGTitleRowEdge(m.scale),lo=w.safeAreaInsets.left+edge,hi=width-w.safeAreaInsets.right-edge;
        CGFloat need=side==0?lo-CGRectGetMinX(r):hi-CGRectGetMaxX(r);
        shift[side]=fabs(need)<.5 || fabs(need)>32?0:round(need*scale)/scale;
    }
    objc_setAssociatedObject(bar,&WXGLocalSideShiftKey,@[@(now),@(shift[0]),@(shift[1])],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return left?shift[0]:shift[1];
}
- (void)navButton:(UIView *)view {
    if(![view isKindOfClass:UIButton.class])return;
    UIButton *button=(UIButton *)view;
    // Not in a title bar, a page the host takes, or a button with its own glass.
    if(![WXGIntegrationHost.shared leavesNavigationControlNative:button]){[self skip:view because:@"顶部按钮适配已接管，或不在导航栏"];return;}
    BOOL mounted=WXGLocalEntryOfAnchor(view).mounted;
    if(!mounted && (button.currentBackgroundImage || WXGLocalFilled(view))){[self skip:view because:@"按钮自己有底色（如绿色完成）"];return;}
    // Hidden or faded: the glass is inside the button and hides with it.
    if(CGRectIsNull(WXGLocalNavButtonFrame(button,WXGLocalNavRoom(button),NULL)) && !mounted){[self skip:view because:@"按钮没有图标或文字" retry:YES];return;}
    __weak UIButton *weakButton=button;
    // FIX108 C: the room to the next button looked at again each time (one can appear beside it).
    [self mount:WXGLocalNavButton host:view anchor:view paint:nil below:nil measure:nil frame:^CGRect{UIButton *b=weakButton;return b?WXGLocalInsideBar(b,WXGLocalNavButtonFrame(b,WXGLocalNavRoom(b),NULL)):CGRectNull;}
         radius:0 button:button prepare:^(WXGStateBag *states){[states allowOverflow:view];}];
    [self setInk:^UIColor *{UIColor *c=nil;UIButton *b=weakButton;if(b)WXGLocalNavButtonFrame(b,CGFLOAT_MAX,&c);return c;} of:view];
    [self followShown:WXGLocalEntryOfAnchor(view) immediately:!mounted];
}
// White text or icons (the photo picker's dark bar, dark mode): a dark glass
// under them. FIX108 B: kept with the entry and looked at again whenever the
// appearance changes (reassert), not only on a layout.
- (void)setInk:(UIColor *(^)(void))ink of:(UIView *)anchor {
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(anchor);if(!entry.mounted)return;
    entry.ink=ink;[self matchInk:entry];
}
- (BOOL)matchInk:(WXGLocalEntry *)entry {
    UIView *anchor=entry.anchor;if(!anchor)return NO;
    entry.inkTraitStyle=anchor.traitCollection.userInterfaceStyle;
    UIColor *ink=entry.ink?entry.ink():nil;entry.lastInk=ink;
    UIUserInterfaceStyle style=WXGLocalLight(ink,anchor.traitCollection)?UIUserInterfaceStyleDark:UIUserInterfaceStyleUnspecified;
    if(entry.surface.overrideUserInterfaceStyle!=style){entry.surface.overrideUserInterfaceStyle=style;entry.dirty=MAX(entry.dirty,20);return YES;}
    return NO;
}

// FIX108 C: a computed glass shows only while what it sits behind shows: a
// title's text, at that text's opacity (pulled down, the home page hides the
// title bar's labels and not the title view: FIX108 B left an empty capsule
// there), a button's icon or title. Hidden, never torn down. FIX108 E: hidden
// after two turns in a row with nothing under it (a title collapsing for one
// layout pass no longer blinks); the visibility comes in measured once.
- (void)followShown:(WXGLocalEntry *)entry immediately:(BOOL)now {
    if(!entry.mounted || (!entry.frame && !entry.shown) || !entry.anchor)return;
    CGFloat alpha=1;
    if(entry.shown){alpha=entry.shown();now=YES;}   // FIX109: the group selection, at once
    else if(entry.titleMeasure)entry.titleMeasure(NULL,&alpha);
    else if(CGRectIsNull(WXGLocalEntryMaterial(entry)))alpha=0;
    [self follow:entry shown:alpha immediately:now];
}
- (void)follow:(WXGLocalEntry *)entry shown:(CGFloat)alpha immediately:(BOOL)now {
    WXGSurface *surface=entry.surface;BOOL nothing=alpha<.01;
    if(alpha<0){now=YES;alpha=0;}   // FIX108 F: WeChat hid the text: no debounce
    entry.unseenTurns=nothing?entry.unseenTurns+1:0;
    if(nothing && !now && entry.unseenTurns<2) {
        // FIX114 A (user: pulling the home list down sometimes left an empty
        // title capsule where the title was): WeChat took the title's text
        // away and nothing laid out or committed again, so the second look
        // the debounce waits for never came. It is taken shortly anyway.
        if(!entry.recheckPending && !surface.hidden) {
            entry.recheckPending=YES;__weak WXGLocalEntry *weakEntry=entry;__weak WXGLocalGlass *weakSelf=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.15*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                WXGLocalEntry *e=weakEntry;WXGLocalGlass *me=weakSelf;if(!e || !me)return;
                e.recheckPending=NO;
                if(e.mounted && e.anchor.window)@try {[me followShown:e immediately:NO];} @catch(__unused NSException *error) {}
            });
        }
        return;
    }
    if(surface.hidden!=nothing){surface.hidden=nothing;if(!nothing)entry.dirty=MAX(entry.dirty,12);}
    if(!nothing && fabs(surface.alpha-alpha)>.01)surface.alpha=WXGClamp(alpha,0,1);
}

#pragma mark - Running

- (void)ensureLink:(UIScreen *)screen {
    if(!_link) {
        WXGLocalTicker *ticker=[WXGLocalTicker new];ticker.owner=self;
        _link=[CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    WXGConfigureDisplayLink(_link,screen);
    _idleSince=0;if(_link.paused)_link.paused=NO;
}
// The tint of a glass: the sheet's own (readable labels), 发送's colour.
- (BOOL)updateTint:(WXGLocalEntry *)entry force:(BOOL)force {
    WXGGlassView *glass=entry.surface.glass;UIColor *tint=nil;
    if(entry.kind==WXGLocalSheet) {
        if(!force && glass.veilOverride)return NO;
        BOOL dark=entry.surface.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
        tint=dark?[UIColor colorWithRed:.11 green:.11 blue:.12 alpha:.58]:[UIColor colorWithWhite:1 alpha:.58];
    }else if(entry.kind==WXGLocalKey && entry.send) {
        UIButton *button=(UIButton *)entry.button;if(![button isKindOfClass:UIButton.class])return NO;
        UIControlState state=button.state;
        if(!force && entry.tintKnown && state==entry.lastState)return NO;
        entry.lastState=state;entry.tintKnown=YES;
        UIColor *color=WXGLocalImageTint([button backgroundImageForState:state]?:[button backgroundImageForState:UIControlStateNormal]);
        tint=color?[color colorWithAlphaComponent:.82]:nil;
    }else return NO;
    if(tint==glass.veilOverride || [tint isEqual:glass.veilOverride])return NO;
    glass.veilOverride=tint;return YES;
}
- (void)tick:(CADisplayLink *)link {
    WXGPerfTimePluginWorkAs("localGlass",^{[self tickBody:link];});
}
- (void)tickBody:(CADisplayLink *)link {
    // FIX108 B: running only while some glass needs a tick (new, changed,
    // pressed, cold); the render-server backdrop needs none. A title capsule on
    // every page kept it at the screen's rate (reassert wakes it).
    BOOL busy=NO,undrawn=NO,available=WXGLocalAvailable();NSUInteger revision=WXGConfigRevision();CFTimeInterval now=link.timestamp;
    for(WXGLocalEntry *entry in _entries.allObjects) {
        WXGSurface *surface=entry.surface;UIView *anchor=entry.anchor;
        if(!entry.mounted || !anchor || surface.superview!=anchor)continue;
        if(![self wants:entry.kind available:available]){[self unmount:entry];continue;}
        UIWindow *window=anchor.window;
        // FIX109: a glass hidden with what it is behind (an unselected group,
        // a hidden title) rests like one off screen.
        if(!window || surface.hidden || !WXGVisible(anchor,window)){if(surface.active)surface.active=NO;continue;}
        if(!surface.active) {
            surface.active=YES;[surface applyConfig];[self updateTint:entry force:YES];
            if(entry.button)[surface observeTouchesInView:entry.button];
            entry.activatedAt=now;entry.dirty=MAX(entry.dirty,20);
        }
        UIUserInterfaceStyle style=surface.traitCollection.userInterfaceStyle;
        if(entry.revision!=revision || entry.style!=style) {
            if(entry.revision)[surface applyConfig];
            entry.revision=revision;entry.style=style;[self updateTint:entry force:YES];entry.dirty=MAX(entry.dirty,20);
        }else if([self updateTint:entry force:NO])entry.dirty=MAX(entry.dirty,20);
        UIControl *button=entry.button;
        if(button && (button.highlighted || button.tracking))entry.pressUntil=now+.9;
        // Not drawn yet: every frame for 3 s; then (FIX109: a glass that missed
        // its first 3 s stayed empty for good) one more try about every second
        // for 30 s, which does not keep the link running: it idles and is
        // woken again for the next try.
        BOOL undrawnNow=!surface.glass.hasPresentedFrame,early=undrawnNow && now-entry.activatedAt<3;
        BOOL late=undrawnNow && !early && now-entry.activatedAt<30 && now-entry.coldTick>=.9;
        BOOL work=entry.dirty>0 || early || now<entry.pressUntil;
        if(!work && !late){if(undrawnNow && now-entry.activatedAt<30)undrawn=YES;continue;}
        if(undrawnNow)entry.coldTick=now;
        if(work)busy=YES;else undrawn=YES;
        if(entry.dirty>0)--entry.dirty;
        [surface layoutIfNeeded];[surface.glass layoutIfNeeded];[surface tick:now];++_ticks;
    }
    if(busy)_idleSince=0;
    else if(!_idleSince)_idleSince=now;
    else if(now-_idleSince>.5) {
        link.paused=YES;
        // FIX109: woken again shortly for a glass still not drawn (its next try).
        if(undrawn && !_coldWake) {
            _coldWake=YES;__weak WXGLocalGlass *weakSelf=self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                WXGLocalGlass *me=weakSelf;if(!me)return;me->_coldWake=NO;
                if(me->_link.paused){me->_idleSince=0;me->_link.paused=NO;}
            });
        }
    }
}
// Before every commit (this observer runs just ahead of Core Animation's, so
// a size settled in that commit's layout is caught on the next turn; the
// display link keeps turns coming while a glass is visible): paint kept away,
// the glass re-measured (a field resized by its own layout after its host's:
// 新的朋友's field narrowing for 取消) or put back if WeChat took it out of its
// parent, and the display link woken for a glass back on screen without any
// layout (a panel slid in, a list header scrolled back).
- (void)reassert {
    // FIX108 C: switched on after WeChat's views had laid out (the plugin's
    // licence or render mode settled after launch): look at every host again.
    BOOL available=WXGLocalAvailable();
    if(available!=_wasAvailable) {
        _wasAvailable=available;
        if(available)dispatch_async(dispatch_get_main_queue(),^{[self applyConfiguration];});
    }
    BOOL idle=!_link || _link.paused,wake=NO;NSUInteger revision=WXGConfigRevision();
    NSMutableArray<UIView *> *again=nil;NSMutableSet<UINavigationBar *> *bars=nil;
    for(WXGLocalEntry *entry in _entries) {
        UIView *anchor=entry.anchor;
        if(!entry.mounted || entry.applying || !anchor.window)continue;
        @try {
            // FIX114 C: the bars with a title-bar glass of ours: their content
            // moved down with the title row (the host does it on its pages;
            // this covers the ones it leaves: web pages, sheets).
            if(entry.kind==WXGLocalNavButton || entry.kind==WXGLocalTitle) {
                UINavigationBar *bar=WXGLocalBarOf(anchor);
                if(bar){if(!bars)bars=[NSMutableSet set];[bars addObject:bar];}
            }
            // FIX109: views added to a search field's host after its layout (a
            // theme's picture of the field): looked at again after this pass.
            if(entry.kind==WXGLocalSearch && entry.host && WXGLocalSubviewShape(entry.host)!=entry.hostShape) {
                entry.hostShape=WXGLocalSubviewShape(entry.host);
                if(!again)again=[NSMutableArray array];[again addObject:entry.host];
            }
            // FIX108: a title-bar button the host has taken over since (its own
            // glass), a title view the host now draws itself (the chat page).
            if(entry.kind==WXGLocalNavButton && ![WXGIntegrationHost.shared leavesNavigationControlNative:entry.button]){[self unmount:entry];continue;}
            if(entry.kind==WXGLocalTitle && !entry.paint && anchor.layer.mask){[self unmount:entry];continue;}
            [entry.states reapply];
            WXGSurface *surface=entry.surface;
            // FIX108 E: each glass measured once per turn (rectangle, what is
            // drawn on it, how visible it is), not three times.
            CGRect material;UIColor *ink=nil;CGFloat shown=1;BOOL inkKnown=NO;
            if(entry.titleMeasure){material=WXGLocalPixelRect(entry.titleMeasure(&ink,&shown),anchor);inkKnown=YES;}
            else if(entry.kind==WXGLocalNavButton && [entry.button isKindOfClass:UIButton.class]) {
                UIButton *b=(UIButton *)entry.button;
                material=WXGLocalPixelRect(WXGLocalInsideBar(b,WXGLocalNavButtonFrame(b,WXGLocalNavRoom(b),&ink)),anchor);shown=CGRectIsNull(material)?0:1;inkKnown=YES;
            }else material=WXGLocalEntryMaterial(entry);
            if(!CGRectIsNull(material) && material.size.width>=1 && material.size.height>=1) {
                CGRect shown=surface.materialRect;CGPoint origin=surface.frame.origin;
                if(surface.superview!=anchor || fabs(shown.size.width-material.size.width)>.25 || fabs(shown.size.height-material.size.height)>.25 ||
                   fabs(origin.x+WXGCanvasPaddingX-material.origin.x)>.25 || fabs(origin.y+WXGCanvasPaddingY-material.origin.y)>.25) {
                    [surface placeMaterial:material inParent:anchor];
                    if(entry.below.superview==anchor)[anchor insertSubview:surface aboveSubview:entry.below];
                    else if(anchor.subviews.firstObject!=surface)[anchor insertSubview:surface atIndex:0];
                    entry.dirty=MAX(entry.dirty,12);++_remeasures;wake=YES;
                }
            }
            // FIX114 B: a native title-bar button drawn at the title row's margin.
            if(entry.kind==WXGLocalNavButton && [entry.button isKindOfClass:UIButton.class])
                [entry.states shiftContents:anchor x:WXGLocalSideShift((UIButton *)entry.button)];
            // FIX108: the title-bar kinds stay under WeChat's icons and labels (a
            // button can reorder its subviews); FIX107's kinds as before.
            if((entry.kind==WXGLocalTitle || entry.kind==WXGLocalNavButton) && surface.superview==anchor && !entry.below && anchor.subviews.firstObject!=surface)
                [anchor insertSubview:surface atIndex:0];
            // FIX108 C: shown only with what it is behind (a title's text).
            if(entry.shown)[self follow:entry shown:entry.shown() immediately:YES];   // FIX109: WeChat's group selection
            else if(entry.frame)[self follow:entry shown:shown immediately:NO];
            // FIX109: a radius setting changed while WeChat had no reason to lay
            // its view out again (the emoji board is kept between chats).
            if(entry.radiusFor && entry.radiusRevision!=revision) {
                entry.radiusRevision=revision;
                CGFloat radius=entry.radiusFor(surface.materialRect.size);
                if(fabs(surface.maximumCornerRadius-radius)>.01){surface.maximumCornerRadius=radius;entry.radius=radius;entry.dirty=MAX(entry.dirty,12);if(!surface.hidden)wake=YES;}
            }
            // FIX108 B/C/E: white or dark ink again after the appearance or the
            // ink changed (not while there is none: a hidden title has none).
            if(entry.ink) {
                BOOL trait=entry.inkTraitStyle!=anchor.traitCollection.userInterfaceStyle;
                if(!inkKnown)ink=entry.ink();   // FIX108 F: the album title's label, every turn (a few subviews)
                if(ink && (trait || !(ink==entry.lastInk || [ink isEqual:entry.lastInk])) && [self matchInk:entry])wake=YES;
                else if(trait)entry.inkTraitStyle=anchor.traitCollection.userInterfaceStyle;
            }
            // FIX108 B: woken only for work: shown but not yet active, pressed,
            // still dirty, the appearance or the settings changed.
            // Only for a glass on screen: the tick leaves the others alone, so
            // their state never settles and they would wake it on every turn.
            if(idle && !wake && surface.superview==anchor && !surface.hidden && WXGVisible(anchor,anchor.window)) {
                UIControl *button=entry.button;
                if((button && (button.highlighted || button.tracking)) || entry.dirty>0 || entry.revision!=revision ||
                   (entry.kind==WXGLocalKey && entry.send && (!entry.tintKnown || button.state!=entry.lastState)) ||   // 发送 turned green / grey
                   entry.style!=surface.traitCollection.userInterfaceStyle || !surface.active)wake=YES;
            }
        } @catch(__unused NSException *error) {}
    }
    if(wake && (!_link || _link.paused)){UIWindow *window=nil;for(WXGLocalEntry *entry in _entries)if(entry.anchor.window){window=entry.anchor.window;break;}
        [self ensureLink:window.screen];++_wakes;_lastWake=CACurrentMediaTime();}
    for(UINavigationBar *bar in bars)@try {WXGMoveBarContent(bar);} @catch(__unused NSException *error) {}
    for(UIView *host in again)[self hostLaidOut:host];
}
- (void)applyConfiguration {
    BOOL available=WXGLocalAvailable();
    // FIX109: 搜索框让主题优先 switched: every search glass goes first, so the
    // fields are looked at again as the theme (or WeChat) paints them.
    BOOL themeFirst=WXGPreferences.shared.localSearchThemeFirst,themeSwitched=themeFirst!=_themeFirst;_themeFirst=themeFirst;
    for(WXGLocalEntry *entry in _entries.allObjects) {
        if(![self wants:entry.kind available:available] || (themeSwitched && entry.kind==WXGLocalSearch)){[self unmount:entry];continue;}
        if(entry.mounted)[entry.surface applyConfig];
    }
    if(!available)return;
    for(UIView *host in _hosts.allObjects)if(host.window)[self hostLaidOut:host];   // mounts again a kind switched back on
}
- (void)navigationRouteChanged {
    if(!_barButton || ![self wants:WXGLocalNavButton])return;
    for(UIView *host in _hosts.allObjects)if(host.window && [host isKindOfClass:_barButton])[self hostLaidOut:host];
}
- (void)releaseTransientResources {
    for(WXGLocalEntry *entry in _entries.allObjects)[entry.surface.glass releaseTransientResources];
}
- (void)restore {
    for(WXGLocalEntry *entry in _entries.allObjects)[self unmount:entry];
    _link.paused=YES;
}
- (NSDictionary *)evidence {
    NSMutableDictionary *counts=[NSMutableDictionary dictionary];NSMutableArray *rows=[NSMutableArray array];
    for(WXGLocalEntry *entry in _entries.allObjects) {
        if(!entry.mounted)continue;
        NSString *kind=WXGLocalKindName(entry.kind);counts[kind]=@([counts[kind] integerValue]+1);
        UIView *anchor=entry.anchor;if(!anchor.window || rows.count>=24)continue;
        CGRect r=[entry.surface convertRect:entry.surface.materialRect toView:anchor.window];
        [rows addObject:@{@"kind":kind,@"host":NSStringFromClass(entry.host.class)?:@"?",@"anchor":NSStringFromClass(anchor.class)?:@"?",
            @"rect":@[@(round(r.origin.x*10)/10),@(round(r.origin.y*10)/10),@(round(r.size.width*10)/10),@(round(r.size.height*10)/10)],
            @"radius":@(round(entry.radius*10)/10),@"active":@(entry.surface.active),@"tinted":@(entry.surface.glass.veilOverride!=nil),
            @"glassReady":@(entry.surface.glass.ready),@"firstFrame":@(entry.surface.glass.hasPresentedFrame),@"hidden":@(entry.surface.hidden),@"themeSkins":@(entry.skins),@"bandsCleared":entry.bands?:@[]}];
    }
    WXGPreferences *p=WXGPreferences.shared;
    return @{@"switches":@{@"search":@(p.localSearch),@"searchThemeFirst":@(p.localSearchThemeFirst),@"panel":@(p.localPanel),@"emoji":@(p.localEmoji),@"sheet":@(p.localSheet),@"title":@(p.localTitle),@"navButtons":@(p.localNavButtons)},
             @"renderMode":@(WXGEffectiveRenderMode()),@"mounted":counts,@"mounts":@(_mounts),@"unmounts":@(_unmounts),@"layouts":@(_layouts),
             @"remeasures":@(_remeasures),@"retries":@(_retries),@"wakes":@(_wakes),
             @"ticks":@(_ticks),@"linkRunning":@(_link && !_link.paused),@"skipped":_lastSkip.copy,@"onScreen":rows,@"emojiSearchBand":_lastSearchBand?:@{},@"emojiQuickJump":_emojiQuickJump?:@{},@"emojiSearchCaptures":_emojiCaptures?:@[],
             @"classes":@{@"WCSearchBar":@(_wcSearchBar!=nil),@"WCWebSearchBar":@(_webSearchBar!=nil),@"FavSearchBar":@(_favSearchBar!=nil),
                          @"WCSearchTextField":@(_swiftField!=nil),@"AttachmentButton":@(_tile!=nil),@"EmoticonBoardView":@(_board!=nil),
                          @"QQEmojiPageCell":@(_qqPage!=nil),@"TabBarCell":@(_tabCell!=nil),@"ActionSheet":@(_sheet!=nil),
                          @"MFTitleView":@(_homeTitle!=nil),@"MMTitleView":@(_pageTitle!=nil),@"MMDropableTitleView":@(_dropTitle!=nil),@"MMBarButton":@(_barButton!=nil),@"NavBarContent":@(_navContent!=nil)}};
}
@end
