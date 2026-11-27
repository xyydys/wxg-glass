#import "WXGIntegration.h"
#import "WXGBackdropSample.h"
#import "WXGHomeSearchLayout.h"

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

/* FIX115 J (user, 10-26 12:17, probe WGP 12:04 / 12:09 on the XS Max, iOS 15.7,
   WeChat 8.0.73: "应该就只有两类。一个搜索和几个按钮，按钮好像原本都带了颜色就也
   做成带颜色的胶囊就行"):
   search — 发起群聊 / 选择联系人's field (MultiSelectContactsViewController): a
            NewContactsSearchPanelView (398 x 36, white, radius 6, clipping;
            the chosen contacts' avatars scroll in it, the SearchPanelTextField
            over all of it): the panel is its own painted field, like 收藏's.
   tint   — WeChat's coloured buttons (FixTitleColorButton: 完成 in 字体大小 /
            聊天背景's title bar, 完成 in the contact picker's bottom bar): a
            glass capsule tinted with the fill WeChat gives the button for its
            state (green when it can be pressed; its grey when not: plain
            glass), WeChat's own title on it. WeChat rounds them with a mask
            layer of their own (taken off while the glass is there). In a title
            bar as tall as the bar's other glass and at least as wide as the
            button; elsewhere the button's own size. Only where WeChat keeps its
            buttons (in a title bar: the pages the host leaves native). */
typedef NS_ENUM(NSInteger,WXGLocalKind) {WXGLocalSearch,WXGLocalTile,WXGLocalKey,WXGLocalTab,WXGLocalSheet,WXGLocalTitle,WXGLocalNavButton,WXGLocalTint,WXGLocalMoments};
static NSString *WXGLocalKindName(WXGLocalKind kind) {
    switch(kind) {
        case WXGLocalSearch:return @"search";
        case WXGLocalTile:return @"tile";
        case WXGLocalKey:return @"key";
        case WXGLocalTab:return @"tab";
        case WXGLocalSheet:return @"sheet";
        case WXGLocalTitle:return @"title";
        case WXGLocalNavButton:return @"navButton";
        case WXGLocalTint:return @"tint";
        case WXGLocalMoments:return @"moments";   // FIX115 Q
    }
    return @"?";
}
static const CGFloat WXGLocalSheetRadius=26;

// FIX114 U: a title-bar glass held apart from its entry (the entry lives only
// as long as WeChat's button; the glass outlives it, back into the pool).
@class WXGLocalEntry;
@interface WXGLocalGlassHolder : NSObject
@property(nonatomic,strong) WXGSurface *glass;
@property(nonatomic,weak) WXGLocalEntry *entry;
@end
@implementation WXGLocalGlassHolder
@end
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
@property(nonatomic) BOOL moveCheckPending;     // FIX114 M: kept through a move out of the bar; the half-second look is scheduled
@property(nonatomic) BOOL veiled;               // FIX114 S: a title-bar button hidden (WeChat's icon and the glass) through a push / pop
@property(nonatomic,weak) UIViewController *navPage;   // FIX114 N: a title-bar button's page and side when mounted
@property(nonatomic) BOOL navLeft;
@property(nonatomic) NSInteger navSide;                // FIX114 Q: 0 left, 1 right, from the page's bar items (-1 unknown)
@property(nonatomic) CGFloat navWidth;                 // FIX114 Q: the button's width (to tell two buttons of a side apart)
@property(nonatomic) CGRect navRect;                   // its place in the window then
@property(nonatomic,copy) CGFloat (^shown)(void);              // FIX109: how visible WeChat's own paint is (the group selection's)
@property(nonatomic,copy) CGFloat (^radiusFor)(CGSize size);   // FIX109: the radius setting, read again when the settings change
@property(nonatomic) NSUInteger radiusRevision;
@property(nonatomic) CFTimeInterval coldTick;                 // FIX109: last tick of a glass that has not drawn yet
@property(nonatomic,copy) CGRect (^titleMeasure)(UIColor **ink,CGFloat *shown);   // FIX109: a title's capsule, ink and visibility in one look
@property(nonatomic) NSUInteger hostShape,skins;   // FIX109: the search host's subviews when looked at, theme pictures hidden
@property(nonatomic,strong) NSHashTable<UIView *> *skinViews;
@property(nonatomic,copy) NSArray<NSString *> *bands;   // FIX113 F: the emoji search bar's band cleared around this field
@property(nonatomic,strong) UIColor *lastFill;    // FIX115 J: a coloured button's fill its tint was made from
@property(nonatomic,strong) WXGSurface *surface;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic) CGFloat radius;          // 0 = capsule
@property(nonatomic) CGFloat nativeRadius;    // WeChat's own (tiles: measured from its image; group selection: its layer)
@property(nonatomic) BOOL mounted,applying,send,tintKnown;
@property(nonatomic) UIControlState lastState;
@property(nonatomic) NSUInteger revision;
@property(nonatomic) UIUserInterfaceStyle style;
@property(nonatomic) NSInteger dirty;         // frames still to tick
@property(nonatomic) NSUInteger orderTurn,orderMoves;   // FIX115 K: moves back under WeChat's content this turn
@property(nonatomic) NSUInteger fightTurn,fightRun;     // FIX115 K: turns in a row the budget ran out (3: no more moves)
@property(nonatomic) NSUInteger openedClips;            // FIX115 K: title-bar containers opened for it
@property(nonatomic) CFTimeInterval activatedAt,pressUntil;
@end
@implementation WXGLocalEntry
@end
// FIX115 K / L: changes of a host's glass this turn, and its rests after a layout loop (noteChange:).
@interface WXGLocalLoopState : NSObject
@property(nonatomic) NSUInteger turn,count,until,trips;
@end
@implementation WXGLocalLoopState
@end
static char WXGLocalLoopKey;
static char WXGLocalAnchorKey,WXGLocalHostKey,WXGLocalRetryKey;
static char WXGLocalFloatingSearchHeaderKey;

static BOOL WXGLocalInsideFloatingHeader(UIView *view) {
    for(UIView *parent=view;parent;parent=parent.superview)
        if(objc_getAssociatedObject(parent,&WXGLocalFloatingSearchHeaderKey))return YES;
    return NO;
}
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
- (void)titleContentChanged:(UIView *)view;   // FIX115 F
- (void)redrawAfterForeground;                 // FIX117 A
@end
/* FIX115 F (user, 08:21, diagnostics_3 with E's frame trace: pulling the home
   list down, the title capsule still lags its text: the text gone with the
   capsule still there for 1-5 frames, back with the capsule still away for 1-11
   frames (5.324 -> 5.418)): WeChat hides / shows the title's label itself (a
   direct child of the title view; it changes during its own layout, inside Core
   Animation's commit, after the plugin's pass before the commit), so the
   capsule followed a turn or more later. The title view's own labels, pictures
   and spinner are now watched (key-value observing of their hidden and alpha):
   the capsule follows in the same call, so in the same commit and inside the
   same animation as WeChat's change. The watcher belongs to the watched view
   (an associated object); KVO lets go of a view that goes away by itself. */
static char WXGTitleWatchKey,WXGTitleWatchContext;
@interface WXGTitleWatch : NSObject
@property(nonatomic,weak) UIView *title;
@end
@implementation WXGTitleWatch
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(context!=&WXGTitleWatchContext){[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];return;}
    UIView *title=_title;if(!title || !NSThread.isMainThread)return;
    [WXGLocalGlass.shared titleContentChanged:title];
}
@end
@interface WXGLocalTicker : NSObject
@property(nonatomic,weak) WXGLocalGlass *owner;
@end
@implementation WXGLocalTicker
- (void)tick:(CADisplayLink *)link {[self.owner tick:link];}
@end

static UINavigationBar *WXGLocalBarOf(UIView *view);                                    // FIX114 M
static UIViewController *WXGLocalNavOwner(UIView *control,UINavigationController **navOut);
static BOOL WXGLocalNavDeparting(UIView *control);
static NSInteger WXGLocalNavSide(UIView *control,UIViewController *page);   // FIX114 Q
static BOOL WXGLocalTintMounted(UIView *v);                                  // FIX115 J
static BOOL WXGLocalHasFill(UIView *v);
/* FIX115 J (review): a title-bar button that paints its own fill — a picture
   or a fill as before, one our tinted glass now stands on (its fill cleared),
   or one of WeChat's coloured buttons with any fill (its faint grey when it
   cannot be pressed too) while their glass is on: ours to tint, never the
   host's to take over (it took a grey one, then dropped it once green). */
static BOOL WXGLocalOwnPaint(UIView *v) {
    if(![v isKindOfClass:UIButton.class])return NO;
    UIButton *b=(UIButton *)v;
    if(b.currentBackgroundImage || WXGLocalFilled(b) || WXGLocalTintMounted(b))return YES;
    static Class color;static dispatch_once_t once;dispatch_once(&once,^{color=NSClassFromString(@"FixTitleColorButton");});
    return color && [b isKindOfClass:color] && WXGLocalHasFill(b) && WXGPluginEnabled() && WXGEffectiveRenderMode()>=2 &&
        [WXGConfig.shared extraNumber:@"localColorButtons"]>.5;
}
@interface WXGLocalSearchAlignCache : NSObject
@property(nonatomic) BOOL valid,customHome,editing,hasContent;
@property(nonatomic) NSUInteger hostShape;
@property(nonatomic) CGRect material,paintBounds;
@property(nonatomic) CGFloat dx,dy;
@property(nonatomic) CFTimeInterval scannedAt;
@property(nonatomic,weak) UITextField *textField;
@property(nonatomic,strong) NSHashTable<UIView *> *targets;
@end
@implementation WXGLocalSearchAlignCache
@end
@implementation WXGLocalGlass {
    NSHashTable<WXGLocalEntry *> *_entries;
    CADisplayLink *_link;
    NSUInteger _foregroundRedraws,_inactiveTicks;   // FIX117 A
    CFTimeInterval _idleSince;
    NSUInteger _mounts,_unmounts,_ticks,_layouts;
    NSMutableDictionary<NSString *,NSString *> *_lastSkip;
    NSDictionary *_lastSearchBand;   // FIX113 F: the emoji search field's surroundings, last looked at
    NSDictionary *_lastSearchAlign;  // R21: custom home search icon+title centering diagnostics
    __weak WXGLocalEntry *_homePlaceholder;
    __weak UITextField *_homeBackingField;
    WXGStateBag *_homeBackingInk;
    NSDictionary *_emojiQuickJump;   // FIX113 Q: the quick jump's field, its capsule and band, last seen
    NSHashTable<UIViewController *> *_emojiPagesSeen;   // FIX113 N: each 表情搜索 page captured once
    NSMutableArray<NSDictionary *> *_emojiCaptures;
    NSUInteger _emojiPageSerial;
    NSHashTable<UIView *> *_hosts;   // every host seen (to mount again a kind switched back on)
    CFTimeInterval _lastWake;
    NSUInteger _remeasures,_retries,_wakes;
    NSUInteger _titleWatches,_titleWatchFollows;   // FIX115 F
    NSUInteger _departHides;   // FIX114 L
    NSUInteger _transientKeeps;   // FIX114 M: title-bar buttons kept through a move out of the bar
    NSUInteger _adoptions;        // FIX114 N: a replaced title-bar button's glass taken over by the new one
    NSMutableArray<WXGSurface *> *_navSurfacePool;   // FIX114 Q: title-bar glasses used before, for the next buttons
    NSUInteger _poolReuses;
    NSUInteger _veils,_reveals;   // FIX114 S / T: leaving buttons hidden, shown again
    // FIX114 T: every title-bar glass and the entry it is in (weak): the glass of
    // a button WeChat let go of (its entry gone with it) back to the pool.
    // FIX114 U (diagnostics_14: reclaimedGlass 0): a weak-valued map table drops
    // the pair (and the glass) when the entry goes; held in an array instead.
    NSMutableArray<WXGLocalGlassHolder *> *_navGlassOwners;
    NSUInteger _reclaimed;
    // FIX114 T: hidden old buttons whose glass a replacement took, still on
    // screen: their states, put back once they leave (WeChat could use one again).
    NSMutableArray<NSArray *> *_veiledLeftovers;
    NSMutableArray<NSDictionary *> *_shiftLog;   // FIX114 M: the last changes of a native button's side shift
    Class _wcSearchBar,_webSearchBar,_favSearchBar,_swiftField,_tile,_board,_qqPage,_tabCell,_sheet,_emoticonSearch;
    Class _homeTitle,_pageTitle,_dropTitle,_barButton;   // FIX108
    Class _navContent;   // FIX109: the bar's own title label (插件)
    Class _contactSearch,_colorButton;   // FIX115 J
    Class _headImage,_operateButton,_timelineTable;   // FIX115 Q
    NSUInteger _tintChanges;             // FIX115 J: a coloured button's tint changed (its state)
    NSUInteger _turn;                    // FIX115 K: run-loop turns (reassert)
    NSUInteger _orderFights,_loopStops;  // FIX115 K: moves refused (a view reordering its own subviews), hosts stopped for a layout loop
    NSMutableArray<NSString *> *_pressCovers;   // FIX115 M: WeChat's press covers hidden on coloured buttons (the last few)
    BOOL _wasAvailable;   // FIX108 C
    BOOL _coldWake;       // FIX109
    BOOL _themeFirst;     // FIX109: 搜索框让主题优先 as last applied
    BOOL _adjustingHomeHeader;
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
        // FIX117 A (user, 11-04: back from the background the home title capsule was sometimes solid pink, pure
        // #FF00FF: the system's colour for a drawable it could not use): every glass of this loop drawn again,
        // its backdrop taken anew, as the app is active again (a frame encoded while it was going to the
        // background is refused by the GPU and its drawable is left undefined; the title's glass, always on,
        // was never redrawn after it).
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note){[weakManager redrawAfterForeground];}];
    });
    return manager;
}
- (void)redrawAfterForeground {
    UIWindow *window=nil;NSUInteger n=0;
    for(WXGLocalEntry *entry in _entries.allObjects) {
        if(!entry.mounted || !entry.surface)continue;
        [entry.surface.glass invalidateBackdrop];entry.dirty=MAX(entry.dirty,20);++n;
        if(!window)window=entry.anchor.window;
    }
    ++_foregroundRedraws;
    if(n)[self ensureLink:window.screen];
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
        @"MMScrollActionSheetContainerView",@"MFTitleView",@"MMTitleView",@"MMDropableTitleView",@"MMBarButton",@"_UINavigationBarContentView",
        @"NewContactsSearchPanelView",@"FixTitleColorButton",@"WCTimeLineOperateButtonView",@"MMHeadImageView"] mutableCopy];   // FIX115 J; FIX115 Q
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
        _contactSearch=NSClassFromString(@"NewContactsSearchPanelView");_colorButton=NSClassFromString(@"FixTitleColorButton");   // FIX115 J
        _headImage=NSClassFromString(@"MMHeadImageView");_operateButton=NSClassFromString(@"WCTimeLineOperateButtonView");_timelineTable=NSClassFromString(@"WCTimelineTableView");   // FIX115 Q
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
        case WXGLocalTint:return [WXGConfig.shared extraNumber:@"localColorButtons"]>.5;   // FIX115 J
        case WXGLocalMoments:return [WXGConfig.shared extraNumber:@"localMoments"]>.5;     // FIX115 Q
    }
    return NO;
}
- (void)skip:(UIView *)host because:(NSString *)reason {
    // Diagnostics only: why a hooked view got no glass (last reason per class).
    _lastSkip[NSStringFromClass(host.class)?:@"?"]=reason;
    [self unmountHost:host];
}
- (void)setFloating:(BOOL)floating forSearchHeader:(UIView *)header {
    if(!header || floating==(objc_getAssociatedObject(header,&WXGLocalFloatingSearchHeaderKey)!=nil))return;
    objc_setAssociatedObject(header,&WXGLocalFloatingSearchHeaderKey,floating?@YES:nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(floating) {
        // Include replacements mounted by either UISearchBar or WCSearchBar.
        for(WXGLocalEntry *entry in _entries.allObjects)
            if(entry.mounted && entry.kind==WXGLocalSearch && [entry.anchor isDescendantOfView:header])[self unmount:entry];
    }else if(header.window) {
        for(UIView *host in _hosts.allObjects)
            if([host isDescendantOfView:header] && [self kindForHost:host]==WXGLocalSearch)[host setNeedsLayout];
    }
}
void WXGSetSearchHeaderFloating(UIView *header,BOOL floating) {
    [WXGLocalGlass.shared setFloating:floating forSearchHeader:header];
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

// FIX114 R: a title-bar button in the title-bar trace (WXGHost.m): its page,
// side, width and which button it is.
static NSString *WXGLocalTraceName(WXGLocalEntry *entry,UIView *button) {
    UIView *b=button?:(entry.button?(UIView *)entry.button:entry.anchor);
    UIViewController *page=WXGLocalNavOwner(b,NULL)?:entry.navPage;
    NSInteger side=page?WXGLocalNavSide(b,page):-1;
    return [NSString stringWithFormat:@"%@ %@ 宽%.1f %@#%03lx",WXGNavTracePage(page),side==0?@"左":side==1?@"右":@"?",b.bounds.size.width,
            NSStringFromClass(b.class)?:@"?",(unsigned long)((((uintptr_t)(__bridge void *)b)>>4)&0xfff)];
}
// FIX114 M (user: entering a chat, its top buttons jumped twice): a title-bar
// button the host says is not WeChat's to keep because it is out of the bar
// or the window for a moment (UIKit moves the items between its containers
// as a push ends) kept its glass torn down: its content shift went back to 0
// for that frame and came again. Now it is kept as it is while it is out,
// and taken down only if it is still out half a second later.
- (BOOL)keepThroughMove:(WXGLocalEntry *)entry {
    if(!entry.mounted || entry.kind!=WXGLocalNavButton)return NO;
    UIView *button=entry.button?(UIView *)entry.button:entry.anchor;
    // In a bar and still a page's button: the host took it. FIX114 P (user,
    // 10:45: still missing and jumping; diagnostics_11: entering a chat and in
    // a swipe back WeChat puts new buttons in and the old ones are no page's
    // any more for a moment while still in the bar): such a button is kept
    // too, so its replacement takes its glass, as drawn.
    if(button.window && WXGLocalBarOf(button) && WXGLocalNavOwner(button,NULL))return NO;
    // Left as it is (the glass is inside the button: it goes wherever the
    // button is put, and hiding it would blink for that frame).
    if(entry.moveCheckPending)return YES;   // (review) one look per move, not one per turn
    entry.moveCheckPending=YES;++_transientKeeps;
    if(WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"按钮离开栏或页面，玻璃先留着 %@（%@%@）",WXGLocalTraceName(entry,button),
                                         button.window?@"在窗口":@"不在窗口",WXGLocalBarOf(button)?@" 在栏里":@" 不在栏里"]);
    __weak WXGLocalEntry *weakEntry=entry;__weak WXGLocalGlass *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGLocalEntry *e=weakEntry;WXGLocalGlass *me=weakSelf;if(e)e.moveCheckPending=NO;
        if(!e || !me || !e.mounted)return;
        UIView *b=e.button?(UIView *)e.button:e.anchor;
        BOOL drop=!b.window || !WXGLocalBarOf(b) || ![WXGIntegrationHost.shared leavesNavigationControlNative:b];
        if(WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"0.5 s 后再看 %@：%@",WXGLocalTraceName(e,b),drop?@"卸下玻璃":@"回来了，留着"]);
        if(drop)[me unmount:e];
    });
    return YES;
}
- (void)noteShift:(WXGLocalEntry *)entry from:(CGFloat)from to:(CGFloat)to {
    if(!_shiftLog)_shiftLog=[NSMutableArray array];
    UIView *b=entry.button?(UIView *)entry.button:entry.anchor;UIWindow *w=b.window;
    CGRect r=w?[b convertRect:b.bounds toView:w]:CGRectNull;
    [_shiftLog addObject:@{@"t":@(round(WXGSecondsSinceLoad()*100)/100),@"from":@(round(from*10)/10),@"to":@(round(to*10)/10),
                           @"side":CGRectIsNull(r)?@"?":(CGRectGetMidX(r)<w.bounds.size.width*.5?@"left":@"right"),
                           @"departing":@(WXGLocalNavDeparting(b)),@"page":NSStringFromClass(WXGLocalNavOwner(b,NULL).class)?:@"?"}];
    if(_shiftLog.count>16)[_shiftLog removeObjectAtIndex:0];
    if(WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"挪 %.1f → %.1f %@%@",from,to,WXGLocalTraceName(entry,b),WXGLocalNavDeparting(b)?@"（离开的页面）":@""]);
}
- (void)unmount:(WXGLocalEntry *)entry {
    if(!entry.mounted)return;
    if(entry==_homePlaceholder)[self releaseHomeBackingField];
    if(entry.kind==WXGLocalNavButton && entry.anchor){CGFloat was=[entry.states contentShiftOf:entry.anchor];if(fabs(was)>.01)[self noteShift:entry from:was to:0];}
    entry.mounted=NO;entry.veiled=NO;++_unmounts;   // FIX114 S: its mask goes with the states' restore
    if(entry.kind==WXGLocalNavButton && WXGNavTraceOn())WXGNavTraceEvent([@"卸下玻璃 " stringByAppendingString:WXGLocalTraceName(entry,nil)]);   // FIX114 R
    [entry.states restore];
    if(entry.openedClips){WXGReleaseClipHolds(entry);entry.openedClips=0;}   // FIX115 K
    entry.surface.active=NO;entry.surface.hidden=YES;[entry.surface removeFromSuperview];
    // FIX114 Q: a title-bar glass kept for the next button (a few at most).
    if(entry.kind==WXGLocalNavButton && entry.surface) {
        if(!_navSurfacePool)_navSurfacePool=[NSMutableArray array];
        if(_navSurfacePool.count<6 && ![_navSurfacePool containsObject:entry.surface])[_navSurfacePool addObject:entry.surface];
        entry.surface=nil;   // mounted again: one from the pool, or a new one (mount:)
    }
}
- (void)unmountHost:(UIView *)host {
    WXGLocalEntry *entry=host?objc_getAssociatedObject(host,&WXGLocalHostKey):nil;
    if(entry && entry.host==host)[self unmount:entry];
}
/* FIX114 N (user, 08:35: entering a chat the native back button's capsule
   still jumps twice; diagnostics_9: each entry's left side shift went 0 ->
   8.3 pt twice, half a second apart, with nothing taking it back between):
   WeChat puts a new back button in once the page is in (its unread count),
   and the new button got a new glass (drawn a few frames later) and its
   shift on the next turn, showing WeChat's place and no capsule meanwhile.
   A title-bar button that replaces one of the same page and side at the same
   place (the old one gone from the bar) takes over the old one's glass, as
   drawn, and its shift at once. */
- (WXGLocalEntry *)replacedNavEntryFor:(UIView *)anchor {
    UIViewController *page=WXGLocalNavOwner(anchor,NULL);
    if(!anchor.window || !page)return nil;
    // FIX114 Q (diagnostics_12: 6 glasses taken over for about 16 buttons WeChat
    // put in, after a push and after every cancelled swipe back): the old and
    // the new button were matched by where they were on screen, and in a push
    // or a swipe they are on their way (a right button was once in the screen's
    // left half). Now by the page's side the bar items put them on, and of
    // several old ones on that side the one closest in width.
    NSInteger side=WXGLocalNavSide(anchor,page);if(side<0)return nil;
    WXGLocalEntry *best=nil;CGFloat bestGap=CGFLOAT_MAX;
    for(WXGLocalEntry *e in _entries.allObjects) {
        if(e.kind!=WXGLocalNavButton || !e.mounted || !e.surface || e.anchor==anchor || e.navPage!=page || e.navSide!=side)continue;
        UIView *old=e.anchor;
        if(old.window && WXGLocalBarOf(old) && WXGLocalNavOwner(old,NULL))continue;   // still a button of the page (FIX114 P: one no page holds any more can be replaced)
        CGFloat gap=fabs(e.navWidth-anchor.bounds.size.width);
        if(gap<bestGap){best=e;bestGap=gap;}
    }
    return best;
}
// A glass for an entry: FIX114 Q: for a title-bar button one used before
// when there is one (its layers made and drawn once: it shows at once; a new
// one takes a few frames), as the plugin's own buttons reuse theirs.
/* FIX114 T (diagnostics_13: after every cancelled swipe back the chat's two
   buttons came with a new glass, drawn frames later: the capsules missing):
   WeChat lets its old buttons go at the end, and an entry lives only as long
   as its button, so their glass went with them and the pool never got it.
   Every title-bar glass is held here with its entry; one whose entry is gone
   is taken out of the dead button and goes to the pool. */
- (void)noteNavGlass:(WXGLocalEntry *)entry {
    if(entry.kind!=WXGLocalNavButton || !entry.surface)return;
    if(!_navGlassOwners)_navGlassOwners=[NSMutableArray array];
    for(WXGLocalGlassHolder *h in _navGlassOwners)if(h.glass==entry.surface){h.entry=entry;return;}
    WXGLocalGlassHolder *h=[WXGLocalGlassHolder new];h.glass=entry.surface;h.entry=entry;[_navGlassOwners addObject:h];
    if(_navGlassOwners.count>32)[_navGlassOwners removeObjectAtIndex:0];
}
- (void)reclaimNavGlass {
    if(!_navGlassOwners.count)return;
    for(WXGLocalGlassHolder *h in _navGlassOwners.copy) {
        WXGLocalEntry *entry=h.entry;WXGSurface *glass=h.glass;
        if(entry && entry.surface==glass)continue;
        [_navGlassOwners removeObject:h];
        if(entry || !glass)continue;   // moved on with an entry of its own (adopted, pooled): noted there
        if(!_navSurfacePool)_navSurfacePool=[NSMutableArray array];
        if(_navSurfacePool.count<6 && ![_navSurfacePool containsObject:glass]) {
            glass.active=NO;glass.hidden=YES;[glass removeFromSuperview];
            [_navSurfacePool addObject:glass];++_reclaimed;
        }
    }
}
- (WXGSurface *)surfaceFor:(WXGLocalKind)kind {
    if(kind==WXGLocalNavButton)[self reclaimNavGlass];   // FIX114 T
    if(kind==WXGLocalNavButton && _navSurfacePool.count) {
        WXGSurface *pooled=_navSurfacePool.lastObject;[_navSurfacePool removeLastObject];++_poolReuses;return pooled;
    }
    WXGSurface *surface=[WXGSurface new];surface.role=[@"local." stringByAppendingString:WXGLocalKindName(kind)];
    surface.materialOnly=YES;surface.userInteractionEnabled=NO;surface.isAccessibilityElement=NO;surface.accessibilityElementsHidden=YES;
    return surface;
}
- (WXGLocalEntry *)entry:(WXGLocalKind)kind anchor:(UIView *)anchor host:(UIView *)host {
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(anchor);
    if(!entry) {
        entry=[WXGLocalEntry new];entry.kind=kind;entry.anchor=anchor;entry.states=[WXGStateBag new];
        WXGLocalEntry *replaced=kind==WXGLocalNavButton?[self replacedNavEntryFor:anchor]:nil;   // FIX114 N
        NSUInteger reusedBefore=_poolReuses;
        if(replaced) {
            if(WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"新按钮 %@ 接手旧按钮的玻璃（旧的 %@）",WXGLocalTraceName(entry,anchor),WXGLocalTraceName(replaced,nil)]);
            entry.surface=replaced.surface;replaced.surface=nil;replaced.mounted=NO;
            // FIX114 P: the old button keeps its shift while it is still on screen
            // (WeChat takes it out a moment later; put back, its icon jumped).
            if(!replaced.anchor.window)[replaced.states restore];
            else if(replaced.anchor) {   // FIX114 T: as it is (hidden, moved) until it goes, then put back
                if(!_veiledLeftovers)_veiledLeftovers=[NSMutableArray array];
                NSPointerArray *weakAnchor=[NSPointerArray weakObjectsPointerArray];[weakAnchor addPointer:(__bridge void *)replaced.anchor];
                [_veiledLeftovers addObject:@[weakAnchor,replaced.states]];
                if(_veiledLeftovers.count>12)[_veiledLeftovers removeObjectAtIndex:0];
            }
            [_entries removeObject:replaced];++_adoptions;
            UIView *old=replaced.anchor;if(old && WXGLocalEntryOfAnchor(old)==replaced)objc_setAssociatedObject(old,&WXGLocalAnchorKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIView *oldHost=replaced.host;if(oldHost && objc_getAssociatedObject(oldHost,&WXGLocalHostKey)==replaced)objc_setAssociatedObject(oldHost,&WXGLocalHostKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }else {
            entry.surface=[self surfaceFor:kind];
            if(kind==WXGLocalNavButton && WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"新按钮 %@ %@",WXGLocalTraceName(entry,anchor),_poolReuses>reusedBefore?@"用留下的玻璃":@"新建玻璃"]);
        }
        objc_setAssociatedObject(anchor,&WXGLocalAnchorKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_entries addObject:entry];
        if(kind==WXGLocalNavButton)[self noteNavGlass:entry];   // FIX114 T
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
/* FIX115 K (hang opening 发起群聊, 10-26 13:03): putting the glass back at
   the bottom of WeChat's view asks that view for a layout; a view that puts
   one of its own subviews back to the bottom in its layout answers with
   another, in the same commit, for ever. At most two such moves per glass per
   run-loop turn (one that has just been put in is always moved down). */
- (BOOL)mayReorder:(WXGLocalEntry *)entry {
    if(entry.fightRun>=3)return NO;   // (review) a view that wins every turn: left as it orders itself (until mounted again)
    if(entry.orderTurn!=_turn){entry.orderTurn=_turn;entry.orderMoves=0;}
    if(entry.orderMoves>=2) {
        ++_orderFights;
        if(entry.fightTurn!=_turn){entry.fightRun=entry.fightTurn+1==_turn?entry.fightRun+1:1;entry.fightTurn=_turn;}
        return NO;
    }
    if(![self noteChange:entry.host])return NO;   // FIX115 L: a move is a change (the loop guard)
    ++entry.orderMoves;return YES;
}
- (void)keepUnderContent:(WXGLocalEntry *)entry arriving:(BOOL)arriving {
    UIView *anchor=entry.anchor,*below=entry.below;WXGSurface *surface=entry.surface;
    if(!anchor || surface.superview!=anchor)return;
    NSArray<UIView *> *subs=anchor.subviews;
    if(below && below.superview==anchor) {
        NSUInteger at=[subs indexOfObjectIdenticalTo:below];
        BOOL right=at!=NSNotFound && at+1<subs.count && subs[at+1]==surface;
        if(!right && (arriving || [self mayReorder:entry]))[anchor insertSubview:surface aboveSubview:below];
    }else if(subs.firstObject!=surface && (arriving || [self mayReorder:entry]))[anchor insertSubview:surface atIndex:0];
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
    if(kind==WXGLocalSearch && WXGLocalInsideFloatingHeader(anchor)) {
        if(existing.mounted)[self unmount:existing];
        return;
    }
    if(![self wants:kind]){if(existing)[self unmount:existing];return;}
    if([self hostResting:host])return;   // FIX115 K
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
        if(!entry.surface){entry.surface=[self surfaceFor:kind];if(kind==WXGLocalNavButton)[self noteNavGlass:entry];}   // FIX114 Q: given back to the pool when it was taken down
        WXGSurface *surface=entry.surface;
        BOOL reshaped=fabs(surface.maximumCornerRadius-radius)>.01;   // FIX107 B: the radius settings
        surface.maximumCornerRadius=radius;surface.pressFixed=button==nil;
        if(kind==WXGLocalSheet && !surface.glass.lightweight){surface.glass.lightweight=YES;[surface.glass invalidateBackdrop];}
        surface.glass.sourceView=WXGContentSourceForView(anchor);
        CGRect now=surface.superview==anchor?surface.materialRect:CGRectNull;
        CGRect wanted=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,material.size.width,material.size.height);
        BOOL moved=surface.superview!=anchor || !CGRectEqualToRect(now,wanted) ||
            !CGPointEqualToPoint(surface.frame.origin,CGPointMake(material.origin.x-WXGCanvasPaddingX,material.origin.y-WXGCanvasPaddingY));
        BOOL arriving=surface.superview!=anchor;   // FIX115 K: put in now (on top): always moved down
        if(moved)[surface placeMaterial:material inParent:anchor];
        // Lowest (or right above the button's background image view), under
        // WeChat's icons and labels. FIX115 K: once in, moved back down at most
        // twice a turn (mayReorder:).
        [self keepUnderContent:entry arriving:arriving];
        // FIX115 K / L: a change of this glass counted for its host (the loop
        // guard); stopped by it (here or inside this very mount): taken down.
        if((arriving || moved || reshaped) && ![self noteChange:host]){entry.mounted=YES;[self unmount:entry];return;}
        if([self hostResting:host]){entry.mounted=YES;[self unmount:entry];return;}
        surface.hidden=NO;
        BOOL fresh=!entry.mounted;
        if(!entry.mounted){entry.mounted=YES;++_mounts;entry.tintKnown=NO;entry.dirty=30;entry.revision=0;entry.fightRun=0;}
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
       (_favSearchBar && [view isKindOfClass:_favSearchBar]) || (_swiftField && [view isKindOfClass:_swiftField]) || [view isKindOfClass:UISearchBar.class] ||
       (_contactSearch && [view isKindOfClass:_contactSearch]))   // FIX115 J
        return WXGLocalSearch;
    // FIX115 J (review: never an MMBarButton: those stay navButton's, whatever the class tree).
    if(_colorButton && [view isKindOfClass:_colorButton] && !(_barButton && [view isKindOfClass:_barButton]))return WXGLocalTint;
    if((_operateButton && [view isKindOfClass:_operateButton]) || [self momentsBannerOf:view])return WXGLocalMoments;   // FIX115 Q
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
/* FIX115 K: the last guard against a layout loop through the plugin (a view
   laid out again and again inside one commit freezes WeChat). FIX115 L
   (review; user, 20:43: LoadControl's title-bar buttons lost their glass):
   what is counted is the plugin changing a host's glass (put in, moved,
   reshaped, moved back under WeChat's content), not every layout — a view
   WeChat lays out many times while nothing of ours changes is no loop. More
   than 40 changes for one host in one run-loop turn: its glass is taken down
   (WeChat's own look back) and it is left alone for 60 turns, then twice as
   long each time (at most 3840); never for good. */
- (BOOL)hostResting:(UIView *)view {
    WXGLocalLoopState *st=view?objc_getAssociatedObject(view,&WXGLocalLoopKey):nil;
    return st && st.until && _turn<st.until;
}
- (BOOL)noteChange:(UIView *)view {
    if(!view)return YES;
    WXGLocalLoopState *st=objc_getAssociatedObject(view,&WXGLocalLoopKey);
    if(!st){st=[WXGLocalLoopState new];objc_setAssociatedObject(view,&WXGLocalLoopKey,st,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(st.turn!=_turn){st.turn=_turn;st.count=0;}
    if(++st.count<=40)return YES;
    ++st.trips;st.until=_turn+((NSUInteger)60<<MIN(st.trips-1,(NSUInteger)6));st.count=0;++_loopStops;
    WXGLog(@"更多玻璃：%@ 一轮里玻璃被改了 40 次以上（布局循环），先撤掉，%lu 轮后再试（第 %lu 次）",NSStringFromClass(view.class),(unsigned long)(st.until-_turn),(unsigned long)st.trips);
    _lastSkip[NSStringFromClass(view.class)?:@"?"]=@"一轮里玻璃被改了 40 次以上（布局循环），先撤掉玻璃，过一会儿再试";
    return NO;
}
- (void)hostLaidOut:(UIView *)view {
    if(!NSThread.isMainThread || !view || _adjustingHomeHeader || WXGIsPluginView(view))return;
    ++_layouts;
    @try {
        WXGLocalEntry *own=objc_getAssociatedObject(view,&WXGLocalHostKey);if(own.host!=view)own=nil;
        if(!view.window){own.surface.active=NO;return;}
        NSInteger kind=[self kindForHost:view];if(kind<0)return;
        [_hosts addObject:view];
        // Off, not authorised, not render-server mode, or this kind switched
        // off: no scan, no glass (FIX105: no trace when not authorised).
        if(![self wants:(WXGLocalKind)kind]){if(own)[self unmount:own];return;}
        // The floating row exclusively owns this header's paint. Skip native lookups
        // and conflict scans as well as mounting a second glass underneath it.
        if(kind==WXGLocalSearch && (WXGLocalInsideFloatingHeader(view) || WXGHomeSearchIsStaged(view) || WXGHomeTaskbarContains(view))){if(own.mounted)[self unmount:own];return;}
        if([self hostResting:view]){if(own)[self unmount:own];return;}   // FIX115 K / L
        if(_wcSearchBar && [view isKindOfClass:_wcSearchBar])[self searchBar:view];
        else if(_webSearchBar && [view isKindOfClass:_webSearchBar])[self searchBar:view];
        else if(_favSearchBar && [view isKindOfClass:_favSearchBar])[self paintedBar:view open:NO];
        else if(_contactSearch && [view isKindOfClass:_contactSearch])[self paintedBar:view open:YES];   // FIX115 J
        else if(kind==WXGLocalTint)[self colorButton:view];                                              // FIX115 J
        else if(kind==WXGLocalMoments)[self moments:view];                                               // FIX115 Q
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
static char WXGLocalHomeHeaderHKey,WXGLocalAppliedHeaderHKey;
static UIViewController *WXGLocalOwner(UIView *view);
static UITableView *WXGLocalHomeTableFor(UIView *view) {
    static Class mainTable,home;static dispatch_once_t once;
    dispatch_once(&once,^{mainTable=NSClassFromString(@"MainFrameTableView");home=NSClassFromString(@"NewMainFrameViewController");});
    for(UIView *v=view;v;v=v.superview)if([v isKindOfClass:UITableView.class]) {
        UITableView *t=(UITableView *)v;
        if(!t.tableHeaderView || ![view isDescendantOfView:t.tableHeaderView])return nil;
        return ([v isKindOfClass:mainTable] || [WXGLocalOwner(t) isKindOfClass:home])?t:nil;
    }
    return nil;
}
static CGRect WXGLocalFrameIn(UIView *v,UIView *ancestor,CGRect r);
static CGRect WXGLocalTextRect(UILabel *label);
static CGRect WXGLocalUnshiftedRectIn(UIView *v,UIView *root,CGRect r) {
    if(!v || !root || CGRectIsNull(r))return CGRectNull;
    if(v==root)return r;
    if(![v isDescendantOfView:root])return [v convertRect:r toView:root];
    for(UIView *p=v;p && p!=root;p=p.superview) {
        if(!p.superview)return CGRectNull;
        CGPoint ap=p.layer.anchorPoint;CGSize sz=p.bounds.size;
        r.origin.x+=p.center.x-ap.x*sz.width-p.bounds.origin.x;
        r.origin.y+=p.center.y-ap.y*sz.height-p.bounds.origin.y;
    }
    return r;
}
static CGRect WXGLocalResolvedHomePaintRect(UIView *paint,UIView *header) {
    if(![paint isDescendantOfView:header])return CGRectNull;
    CGRect r=WXGLocalUnshiftedRectIn(paint,header,paint.bounds);
    WXGRect field={r.origin.x-header.bounds.origin.x,r.origin.y-header.bounds.origin.y,r.size.width,r.size.height};
    return WXGHomeSearchFieldReady(field,header.bounds.size.width,header.bounds.size.height)?r:CGRectNull;
}
static UIView *WXGLocalSearchWrapUnder(UIView *v,UIView *paint,UIView *host) {
    UIView *best=v;
    for(UIView *a=v.superview;a && a!=host && a!=paint;a=a.superview) {
        if([paint isDescendantOfView:a])break;
        best=a;
    }
    return best;
}
static BOOL WXGLocalSearchCollectContent(UIView *host,UIView *paint,NSHashTable<UIView *> *skins,CGRect paintInHost,CGRect *outBoxInHost,NSArray<UIView *> **outTargets,UITextField **outField,BOOL *outEditing) {
    if(outBoxInHost)*outBoxInHost=CGRectNull;
    if(outTargets)*outTargets=@[];
    if(outField)*outField=nil;
    if(outEditing)*outEditing=NO;
    if(!host || !paint || CGRectIsNull(paintInHost))return NO;
    CGRect searchZone=CGRectInset(paintInHost,-24,-24);
    UILabel *bestLabel=nil;CGRect bestLabelRect=CGRectNull;
    NSMutableArray<UIImageView *> *icons=nil;
    for(UIView *v in WXGLocalViews(host,140)) {
        if([v isKindOfClass:UITextField.class]) {
            UITextField *tf=(UITextField *)v;
            if(outField && !*outField)*outField=tf;
            if(tf.isFirstResponder || tf.text.length>0) {
                if(outEditing)*outEditing=YES;
                return NO;
            }
            continue;
        }
        if(WXGIsPluginView(v) || [skins containsObject:v] || !WXGLocalShownIn(v,host))continue;
        if(!bestLabel && [v isKindOfClass:UILabel.class]) {
            UILabel *l=(UILabel *)v;NSString *txt=l.text?:l.attributedText.string;
            if(!txt.length || txt.length>24)continue;
            CGRect tr=WXGLocalUnshiftedRectIn(l,host,WXGLocalTextRect(l));
            if(CGRectIsNull(tr) || tr.size.width<4 || tr.size.height<4)continue;
            if(!CGRectContainsPoint(searchZone,CGPointMake(CGRectGetMidX(tr),CGRectGetMidY(tr))))continue;
            bestLabel=l;bestLabelRect=tr;
        }else if([v isKindOfClass:UIImageView.class]) {
            UIImageView *iv=(UIImageView *)v;
            if(!iv.image || iv.bounds.size.width<6 || iv.bounds.size.height<6 || iv.bounds.size.width>36 || iv.bounds.size.height>36)continue;
            if(!icons)icons=[NSMutableArray array];
            [icons addObject:iv];
        }
    }
    UIImageView *bestIcon=nil;CGRect bestIconRect=CGRectNull;CGFloat bestScore=CGFLOAT_MAX;
    for(UIImageView *iv in icons) {
        CGRect ir=WXGLocalUnshiftedRectIn(iv,host,iv.bounds);
        if(CGRectIsNull(ir) || ir.size.width<4 || ir.size.height<4)continue;
        if(!CGRectContainsPoint(searchZone,CGPointMake(CGRectGetMidX(ir),CGRectGetMidY(ir))))continue;
        if(bestLabel) {
            CGFloat dy=fabs(CGRectGetMidY(ir)-CGRectGetMidY(bestLabelRect));
            if(dy>20)continue;
            CGFloat dx=fabs(CGRectGetMaxX(ir)-CGRectGetMinX(bestLabelRect))+dy*2.;
            if(dx<bestScore){bestScore=dx;bestIcon=iv;bestIconRect=ir;}
        }else {bestIcon=iv;bestIconRect=ir;break;}
    }
    if(!bestLabel && !bestIcon)return NO;
    CGRect box=(!CGRectIsNull(bestIconRect) && !CGRectIsNull(bestLabelRect))?CGRectUnion(bestIconRect,bestLabelRect):(bestLabel?bestLabelRect:bestIconRect);
    if(outBoxInHost)*outBoxInHost=box;
    if(outTargets) {
        UIView *wIcon=bestIcon?WXGLocalSearchWrapUnder(bestIcon,paint,host):nil;
        UIView *wLabel=bestLabel?WXGLocalSearchWrapUnder(bestLabel,paint,host):nil;
        NSMutableArray<UIView *> *targets=[NSMutableArray array];
        if(wIcon)[targets addObject:wIcon];
        if(wLabel && ![targets containsObject:wLabel])[targets addObject:wLabel];
        *outTargets=targets;
    }
    return YES;
}
static char WXGLocalSearchShiftedKey,WXGLocalSearchAlignCacheKey;
- (void)syncSearchAlignment:(WXGLocalEntry *)entry material:(CGRect)material force:(BOOL)force {
    if(!entry || entry.kind!=WXGLocalSearch || !entry.host || !entry.anchor)return;
    UIView *host=entry.host,*paint=entry.anchor;
    BOOL isHome=WXGLocalHomeTableFor(host)!=nil;
    WXGConfig *cfg=WXGConfig.shared;
    BOOL customHome=isHome && (cfg.homeSearchWidthPct>.5 || cfg.homeSearchHeight>.5 || cfg.homeSearchTopGap>=0);
    CGRect paintInHost=WXGLocalUnshiftedRectIn(paint,host,paint.bounds);
    // R24: wait until UIStackView finishes cold-start positioning before shifting content.
    if(customHome && (CGRectIsNull(paintInHost) || paintInHost.origin.y<-1.))return;
    WXGLocalSearchAlignCache *cache=objc_getAssociatedObject(entry,&WXGLocalSearchAlignCacheKey);
    UITextField *cachedTF=cache.textField;
    BOOL cachedEditing=cachedTF && (cachedTF.isFirstResponder || cachedTF.text.length>0);
    CFTimeInterval now=CACurrentMediaTime();
    if(!force && cache && cache.valid && cache.customHome==customHome && cache.hostShape==entry.hostShape &&
       CGRectEqualToRect(cache.material,material) && CGRectEqualToRect(cache.paintBounds,paint.bounds) &&
       cachedEditing==cache.editing) {
        BOOL alive=!cache.hasContent || cache.targets.count>0;
        if(alive && cache.hasContent) {
            for(UIView *v in cache.targets.allObjects) {
                if(!v.superview || ![v isDescendantOfView:host]){alive=NO;break;}
            }
        }
        if(alive && (cache.hasContent || !customHome || cachedEditing || now-cache.scannedAt<.25)) {
            CGFloat dx=cache.hasContent?cache.dx:0,dy=cache.hasContent?cache.dy:0;
            for(UIView *v in cache.targets.allObjects)[entry.states shiftView:v x:dx y:dy];
            return;
        }
    }
    NSHashTable<UIView *> *prev=objc_getAssociatedObject(entry,&WXGLocalSearchShiftedKey);
    CGRect contentBoxInHost=CGRectNull;NSArray<UIView *> *targets=@[];UITextField *tf=nil;BOOL editing=NO;
    BOOL hasContent=customHome && !CGRectIsNull(material) && !CGRectIsEmpty(material) && !CGRectIsNull(paintInHost) &&
        WXGLocalSearchCollectContent(host,paint,entry.skinViews,paintInHost,&contentBoxInHost,&targets,&tf,&editing);
    if(!cache){cache=[WXGLocalSearchAlignCache new];objc_setAssociatedObject(entry,&WXGLocalSearchAlignCacheKey,cache,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    cache.valid=YES;cache.scannedAt=now;cache.customHome=customHome;cache.hostShape=entry.hostShape;
    cache.material=material;cache.paintBounds=paint.bounds;cache.textField=tf;cache.editing=editing;cache.hasContent=hasContent && targets.count>0;
    if(!hasContent || !targets.count) {
        cache.dx=0;cache.dy=0;cache.targets=nil;
        for(UIView *v in prev.allObjects)[entry.states shiftView:v x:0 y:0];
        objc_setAssociatedObject(entry,&WXGLocalSearchShiftedKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CGRect matInHost=CGRectOffset(material,paintInHost.origin.x-paint.bounds.origin.x,paintInHost.origin.y-paint.bounds.origin.y);
    CGFloat dx=CGRectGetMidX(matInHost)-CGRectGetMidX(contentBoxInHost);
    CGFloat dy=CGRectGetMidY(matInHost)-CGRectGetMidY(contentBoxInHost);
    if(fabs(dx)<.25)dx=0;
    if(fabs(dy)<.25)dy=0;
    cache.dx=dx;cache.dy=dy;
    NSHashTable<UIView *> *next=[NSHashTable weakObjectsHashTable];
    for(UIView *v in targets) {
        [next addObject:v];
        if(dx!=0 || dy!=0 || [prev containsObject:v])[entry.states shiftView:v x:dx y:dy];
    }
    cache.targets=next;
    for(UIView *v in prev.allObjects)if(![next containsObject:v])[entry.states shiftView:v x:0 y:0];
    objc_setAssociatedObject(entry,&WXGLocalSearchShiftedKey,next,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    _lastSearchAlign=@{@"dx":@(round(dx*10)/10),@"dy":@(round(dy*10)/10),
                       @"contentBox":NSStringFromCGRect(contentBoxInHost),@"material":NSStringFromCGRect(matInHost),
                       @"targets":@(targets.count)};
}
- (void)searchBar:(UIView *)bar {
    WXGLocalEntry *known=objc_getAssociatedObject(bar,&WXGLocalHostKey);
    if(WXGHomeTaskbarContains(bar)){if(known.mounted && known.kind==WXGLocalSearch)[self unmount:known];return;}
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
    NSArray<UIView *> *skins=known.mounted && known.anchor==paint && known.skinViews && WXGLocalSubviewShape(bar)==known.hostShape?
        known.skinViews.allObjects:WXGLocalFieldSkins(bar,paint);
    if(skins.count && themeFirst){[self skip:bar because:@"搜索框主题优先：主题换了搜索框的图"];return;}
    [self field:paint host:bar skins:skins];
}
- (void)field:(UIView *)paint host:(UIView *)host {[self field:paint host:host skins:@[]];}
static UIViewController *WXGLocalOwner(UIView *view) {
    for(UIResponder *r=view;r;r=r.nextResponder)if([r isKindOfClass:UIViewController.class])return (UIViewController *)r;
    return nil;
}
- (void)releaseHomeBackingField {
    [_homeBackingInk restore];_homeBackingInk=nil;_homeBackingField=nil;_homePlaceholder=nil;
}
- (void)coverBackingFieldOf:(WXGLocalEntry *)entry inHeader:(UIView *)header {
    if(!header || !entry.mounted || ![entry.host isKindOfClass:_wcSearchBar] ||
       ![entry.host isDescendantOfView:header])return;
    UITextField *field=nil;
    for(UIView *v in WXGViews(header,100)) {
        if([v isKindOfClass:UISearchTextField.class] && ![v isDescendantOfView:entry.host] && ![entry.host isDescendantOfView:v]){field=(UITextField *)v;break;}
    }
    if(!field || field.isFirstResponder || field.text.length || !WXGLocalShownIn(entry.host,header) ||
       WXGLocalOwner(header).navigationItem.searchController.isActive ||
       !CGRectContainsPoint([entry.anchor convertRect:entry.anchor.bounds toView:header],
                            [field convertPoint:CGPointMake(CGRectGetMidX(field.bounds),CGRectGetMidY(field.bounds)) toView:header])) {
        if(_homePlaceholder==entry)[self releaseHomeBackingField];return;
    }
    if(_homePlaceholder!=entry || _homeBackingField!=field) {
        [self releaseHomeBackingField];_homePlaceholder=entry;_homeBackingField=field;_homeBackingInk=[WXGStateBag new];
    }
    [_homeBackingInk conceal:field];
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
        // A UIKit field can finish layout just before WeChat installs the WC
        // placeholder. Its smaller background must yield to the actual drawn box.
        if([host isKindOfClass:_wcSearchBar] && [other.host isKindOfClass:UISearchBar.class] &&
           ![other.host isKindOfClass:_wcSearchBar]) {
            UITableView *home=WXGLocalHomeTableFor(host);
            if(home && WXGLocalHomeTableFor(other.host)==home){[self unmount:other];continue;}
        }
        if(theirArea<=myArea){[self skip:host because:@"和另一块搜索框玻璃重叠（保留输入框大小的那块）"];return YES;}
        [self unmount:other];
    }
    return NO;
}
// Only own a table-header height when an explicit vertical customization grows it.
// Ignore a height that WeChat replaced during its own layout.
- (void)resizeSearchHeader:(UIView *)header table:(UITableView *)table height:(CGFloat)height {
    if(table.tableHeaderView!=header || WXGHomeListInNativePull(table) || WXGHomeTaskbarContains(header) || fabs(header.frame.size.height-height)<=.5)return;
    _adjustingHomeHeader=YES;
    @try {
        [UIView performWithoutAnimation:^{
            CGRect frame=header.frame;frame.size.height=height;header.frame=frame;
            table.tableHeaderView=header;
        }];
    } @finally {_adjustingHomeHeader=NO;}
}
void WXGReleaseLocalSearchHeaderHeight(UITableView *table) {
    if(WXGHomeListInNativePull(table))return;
    UIView *header=table.tableHeaderView;
    NSNumber *base=objc_getAssociatedObject(header,&WXGLocalHomeHeaderHKey);
    NSNumber *applied=objc_getAssociatedObject(header,&WXGLocalAppliedHeaderHKey);
    if(!applied)return;
    objc_setAssociatedObject(header,&WXGLocalHomeHeaderHKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(header,&WXGLocalAppliedHeaderHKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(base && fabs(applied.doubleValue-header.frame.size.height)<.5)
        [WXGLocalGlass.shared resizeSearchHeader:header table:table height:base.doubleValue];
}
static CGRect WXGLocalCustomSearchMaterial(UIView *paint,UIView *header,CGRect natural) {
    WXGConfig *config=WXGConfig.shared;
    WXGRect native={natural.origin.x-header.bounds.origin.x,natural.origin.y-header.bounds.origin.y,
                    natural.size.width,natural.size.height};
    WXGRect row=WXGHomeRowRect(native,header.bounds.size.width,config.homeSearchWidthPct,config.homeSearchHeight,config.homeSearchTopGap);
    return CGRectMake(paint.bounds.origin.x+row.x-native.x,paint.bounds.origin.y+row.y-native.y,row.w,row.h);
}
- (void)field:(UIView *)paint host:(UIView *)host skins:(NSArray<UIView *> *)skins {
    if(WXGHomeTaskbarContains(host)) {
        WXGLocalEntry *entry=objc_getAssociatedObject(host,&WXGLocalHostKey);
        if(entry.mounted && entry.kind==WXGLocalSearch)[self unmount:entry];
        return;
    }
    UITableView *homeTable=WXGLocalHomeTableFor(host);
    BOOL nativePull=homeTable && WXGHomeListInNativePull(homeTable);
    WXGLocalEntry *known=WXGLocalEntryOfAnchor(paint);
    // The existing material follows its paint view without per-scroll mounting.
    // A replaced anchor still needs its first coat in this same layout.
    if(nativePull && known.mounted && known.host==host && known.surface.superview==paint &&
       WXGLocalSubviewShape(host)==known.hostShape)return;
    for(WXGLocalEntry *other in _entries.allObjects)
        if(other.mounted && other.kind==WXGLocalSearch && other.host==host && other.anchor && other.anchor!=paint)[self unmount:other];
    WXGConfig *cfg=WXGConfig.shared;
    BOOL customHome=homeTable && (cfg.homeSearchWidthPct>.5 || cfg.homeSearchHeight>.5 || cfg.homeSearchTopGap>=0);
    UIView *homeHeader=WXGHomeNativeSearchHeader(homeTable.tableHeaderView);
    NSNumber *baseHeight=homeHeader?objc_getAssociatedObject(homeHeader,&WXGLocalHomeHeaderHKey):nil;
    NSNumber *applied=homeHeader?objc_getAssociatedObject(homeHeader,&WXGLocalAppliedHeaderHKey):nil;
    BOOL vertical=customHome && ![WXGChatSegments.shared wanted] && homeHeader==homeTable.tableHeaderView && (cfg.homeSearchHeight>.5 || cfg.homeSearchTopGap>=0);
    if(!nativePull && applied && (!vertical || fabs(applied.doubleValue-homeHeader.frame.size.height)>.5)) {
        if(!vertical && fabs(applied.doubleValue-homeHeader.frame.size.height)<=.5)
            [self resizeSearchHeader:homeHeader table:homeTable height:baseHeight.doubleValue];
        objc_setAssociatedObject(homeHeader,&WXGLocalHomeHeaderHKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(homeHeader,&WXGLocalAppliedHeaderHKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        baseHeight=nil;
    }
    if(customHome && homeHeader) {
        CGRect nat=WXGLocalResolvedHomePaintRect(paint,homeHeader);
        if(CGRectIsNull(nat)){[self skip:host because:@"等待首页搜索框完成原生布局" retry:YES];return;}
        if(vertical && !nativePull) {
            CGFloat nativeH=baseHeight?baseHeight.doubleValue:homeHeader.frame.size.height;
            WXGRect field={nat.origin.x,nat.origin.y-homeHeader.bounds.origin.y,nat.size.width,nat.size.height};
            CGFloat needed=WXGHomeSearchRequiredHeaderHeight(field,nativeH,cfg.homeSearchHeight,cfg.homeSearchTopGap);
            if(fabs(homeHeader.frame.size.height-needed)>.5) {
                objc_setAssociatedObject(homeHeader,&WXGLocalHomeHeaderHKey,@(nativeH),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(homeHeader,&WXGLocalAppliedHeaderHKey,@(needed),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [self resizeSearchHeader:homeHeader table:homeTable height:needed];
            }
        }
        CGRect targetInPaint=WXGLocalCustomSearchMaterial(paint,homeHeader,nat);
        if([self searchGlassClashes:paint material:targetInPaint host:host])return;
        __weak UIView *weakPaint=paint,*weakHeader=homeHeader;
        [self mount:WXGLocalSearch host:host anchor:paint paint:paint below:nil measure:nil
            frame:^CGRect{
                UIView *p=weakPaint,*hdr=weakHeader;if(!p || !hdr)return CGRectNull;
                CGRect natural=WXGLocalResolvedHomePaintRect(p,hdr);
                return CGRectIsNull(natural)?CGRectNull:WXGLocalCustomSearchMaterial(p,hdr,natural);
            }
            radius:0 button:nil
            prepare:^(WXGStateBag *states){
                [states clear:paint];
                for(UIView *a=paint;a && a!=homeTable;a=a.superview){[states allowOverflow:a];if(a==homeHeader)break;}
                for(UIView *skin in skins)[states hide:skin];
            }];
    }else {
        if([self searchGlassClashes:paint material:paint.bounds host:host])return;
        [self mount:WXGLocalSearch host:host anchor:paint paint:paint below:nil measure:paint radius:0 button:nil
            prepare:^(WXGStateBag *states){[states clear:paint];[states allowOverflow:paint];for(UIView *skin in skins)[states hide:skin];}];
    }
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(paint);
    if(entry.mounted) {
        entry.hostShape=WXGLocalSubviewShape(host);entry.skins=skins.count;
        NSHashTable *table=[NSHashTable weakObjectsHashTable];for(UIView *skin in skins)[table addObject:skin];entry.skinViews=table;
        [self clearSearchBandAround:entry];
        [self syncSearchAlignment:entry material:WXGLocalEntryMaterial(entry) force:YES];
        if(homeHeader)[self coverBackingFieldOf:entry inHeader:homeHeader];
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
// FavSearchBar (收藏): the bar is its own filled, rounded field. FIX115 J:
// the contact picker's NewContactsSearchPanelView too; it clips (WeChat's
// radius 6), so it is opened (`open`) for the capsule's rim and shadow (the
// avatars' scroll view inside clips itself). FIX115 K: the glass is kept at
// its bottom within the turn's move budget (it lays out its own subviews).
- (void)paintedBar:(UIView *)bar open:(BOOL)open {
    CGRect b=bar.bounds;
    BOOL painted=WXGLocalEntryOfAnchor(bar).mounted || (WXGLocalFilled(bar) && bar.layer.cornerRadius>0);
    if(!painted || b.size.height<24 || b.size.height>60){[self skip:bar because:@"不是带底色的搜索框"];return;}
    if([self searchGlassClashes:bar material:bar.bounds host:bar])return;   // FIX109 E
    [self mount:WXGLocalSearch host:bar anchor:bar paint:bar below:nil measure:bar radius:0 button:nil
        prepare:^(WXGStateBag *states){[states clear:bar];if(open)[states allowOverflow:bar];}];
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
    UITableView *home=WXGLocalHomeTableFor(bar);
    UIView *native=WXGHomeNativeSearchHeader(home.tableHeaderView);
    UIView *root=native && [bar isDescendantOfView:native]?native:bar;
    if(_wcSearchBar)for(UIView *v in WXGLocalViews(root,80))if([v isKindOfClass:_wcSearchBar] && WXGLocalShownIn(v,root)) {
        if(home)[self coverBackingFieldOf:objc_getAssociatedObject(v,&WXGLocalHostKey) inHeader:native];
        [self skip:bar because:@"被 WCSearchBar 盖住"];return;   // the WCSearchBar's own field is used
    }
    UITextField *field=home?WXGInstalledSearchField(bar):bar.searchTextField;
    if(!home && !field){id value=WXGRead(bar,@"searchField");if([value isKindOfClass:UITextField.class])field=value;}
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
/* FIX115 Q (user, 10-27 01:02, probe WGP_20261027_005317 on the XS Max /
   iOS 15.7, WeChat 8.0.73): 朋友圈. ① The "N条新消息" banner: a plain UIButton
   180 × 40 in a cell of WCTimelineTableView, WeChat's grey rounded box its
   background image, the text its title, an MMHeadImageView 31 × 31 at its
   left (rounded-square photo, its middle on the left end's centre). Glass
   capsule instead of the box (height / 2), the avatar round (concentric with
   the capsule's end: "头像应该要贴合胶囊条变圆且同心"), the text in the
   appearance's label colour. ② WCTimeLineOperateButtonView, the ·· button
   that brings out 赞 / 评论: 44 × 28, its image the grey 32 × 20 box, the dots
   their own image view over it. A capsule glass the box's size instead. The
   comment area stays WeChat's ("评论区不用管"). */
- (UIButton *)momentsBannerOf:(UIView *)view {
    if(!_headImage || !_timelineTable || ![view isKindOfClass:_headImage])return nil;
    UIView *b=view.superview;
    if(!b || b.class!=UIButton.class)return nil;
    CGSize size=b.bounds.size;
    if(size.height<24 || size.height>64 || size.width<size.height*2)return nil;
    NSUInteger depth=0;
    for(UIView *p=b.superview;p && depth<6;p=p.superview,depth++)if([p isKindOfClass:_timelineTable])return (UIButton *)b;
    return nil;
}
- (void)moments:(UIView *)view {
    if(_operateButton && [view isKindOfClass:_operateButton]){if([view isKindOfClass:UIButton.class])[self operateButton:(UIButton *)view];return;}
    UIButton *banner=[self momentsBannerOf:view];if(banner)[self momentsBanner:banner];
}
- (void)operateButton:(UIButton *)button {
    UIImageView *box=button.imageView;   // WeChat's grey box (the dots: an image view of their own above it)
    if(!box.image || box.hidden || box.bounds.size.width<16 || box.bounds.size.height<12 || box.bounds.size.height>40){[self skip:button because:@"·· 按钮没有底框"];return;}
    [self mount:WXGLocalMoments host:button anchor:button paint:box below:box measure:box radius:box.bounds.size.height*.5 button:button
        prepare:^(WXGStateBag *states){[states clearImagePaint:box];}];
    // (review) One on every post: the light glass (one backdrop layer, as the
    // share sheet's), so a scroll through 朋友圈 stays cheap.
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(button);
    if(entry.mounted && entry.surface && !entry.surface.glass.lightweight){entry.surface.glass.lightweight=YES;[entry.surface.glass invalidateBackdrop];}
}
- (void)momentsBanner:(UIButton *)button {
    WXGLocalEntry *known=WXGLocalEntryOfAnchor(button);
    UIImageView *background=[self backgroundViewOf:button known:known];
    if(!background)for(UIView *v in button.subviews)
        if([v isKindOfClass:UIImageView.class] && !WXGIsPluginView(v) && v.bounds.size.width>=button.bounds.size.width*.9 && v.bounds.size.height>=button.bounds.size.height*.9){background=(UIImageView *)v;break;}
    if(!background || background.bounds.size.height<24){[self skip:button because:@"新消息横幅没有背景图"];return;}
    NSMutableArray<UIView *> *heads=[NSMutableArray array];
    for(UIView *v in button.subviews)if([v isKindOfClass:_headImage] && v.bounds.size.width>8 && v.bounds.size.height>8)[heads addObject:v];
    // (review) The text's colour as the button's title colour: UIButton gives its
    // label that colour again at every layout and state change.
    [self mount:WXGLocalMoments host:button anchor:button paint:background below:background measure:background radius:background.bounds.size.height*.5 button:button
        prepare:^(WXGStateBag *states){
            [states clearImagePaint:background];
            for(UIView *head in heads)[states round:head radius:MIN(head.bounds.size.width,head.bounds.size.height)*.5];
            [states titleColor:button color:UIColor.labelColor];
        }];
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
// FIX115 F / R25: watch all nested subviews of the title view (WeChat nests
// labels 2-3 levels deep inside MFTitleView) and sync sibling home titles
// together on the exact handoff frame.
- (void)watchTitle:(UIView *)view {
    for(UIView *c in WXGLocalViews(view,40)) {
        if(c==view || WXGIsPluginView(c))continue;
        WXGTitleWatch *existing=objc_getAssociatedObject(c,&WXGTitleWatchKey);
        if(existing){existing.title=view;continue;}
        if(![c isKindOfClass:UILabel.class] && ![c isKindOfClass:UIImageView.class] && ![c isKindOfClass:UIActivityIndicatorView.class] && c.class!=UIView.class)continue;
        WXGTitleWatch *watch=[WXGTitleWatch new];watch.title=view;
        objc_setAssociatedObject(c,&WXGTitleWatchKey,watch,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try {for(NSString *k in @[@"hidden",@"alpha"])[c addObserver:watch forKeyPath:k options:0 context:&WXGTitleWatchContext];}
        @catch(__unused NSException *error) {}
        ++_titleWatches;
    }
}
- (void)titleContentChanged:(UIView *)view {
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(view);
    if(!view.window || entry.applying)return;
    BOOL homeTitle=_homeTitle && [view isKindOfClass:_homeTitle];
    if(homeTitle) {
        // The ordinary Home title and the taskbar title may reuse a label
        // nested deeper than the cheap layout key. Re-read native ink now.
        objc_setAssociatedObject(view,&WXGLocalTitleCacheKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(!entry.mounted) {
            if([self wants:WXGLocalTitle] && ![WXGChatSegments.shared titleModeWanted])[view setNeedsLayout];
            return;
        }
    }
    if(!entry.mounted || entry.kind!=WXGLocalTitle || entry.surface.superview!=view)return;
    ++_titleWatchFollows;
    @try {
        [self followShown:entry immediately:NO];
        if(_homeTitle && [view isKindOfClass:_homeTitle]) {
            UIWindow *w=view.window;
            for(WXGLocalEntry *other in _entries.allObjects) {
                if(other==entry || !other.mounted || other.kind!=WXGLocalTitle || other.applying)continue;
                if(other.anchor.window==w && [other.anchor isKindOfClass:_homeTitle])[self followShown:other immediately:NO];
            }
        }
    } @catch(__unused NSException *error) {}
}
static UIViewController *WXGLocalPageController(UIView *view) {
    UIViewController *owner=WXGLocalOwner(view);
    if([owner isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav=(UINavigationController *)owner;
        for(UIViewController *vc in nav.viewControllers) {
            if(vc.isViewLoaded && (vc.navigationItem.titleView==view || [view isDescendantOfView:vc.view]))return vc;
        }
        return nav.topViewController?:nav.visibleViewController;
    }
    return owner;
}
static BOOL WXGLocalTitleAllowedForView(UIView *view) {
    static Class contactsCls,discoverCls;static dispatch_once_t once;
    dispatch_once(&once,^{
        contactsCls=NSClassFromString(@"ContactsViewController");
        discoverCls=NSClassFromString(@"FindFriendEntryViewController");
    });
    UIViewController *page=WXGLocalPageController(view);
    if(!page)return YES;
    if(contactsCls && [page isKindOfClass:contactsCls])return WXGConfig.shared.contactsTitleCapsule;
    if(discoverCls && [page isKindOfClass:discoverCls])return WXGConfig.shared.discoverTitleCapsule;
    return YES;
}
// The title in WeChat's title view (首页 MFTitleView, the others' MMTitleView).
- (void)titleView:(UIView *)view {
    if(_homeTitle && [view isKindOfClass:_homeTitle] && [WXGChatSegments.shared titleModeWanted]) {
        WXGLocalEntry *was=WXGLocalEntryOfAnchor(view);if(was.mounted && was.kind==WXGLocalTitle)[self unmount:was];
        [self skip:view because:@"首页标题已拓展为分组栏"];return;
    }
    if(!WXGLocalTitleAllowedForView(view)) {
        WXGLocalEntry *was=WXGLocalEntryOfAnchor(view);if(was.mounted && was.kind==WXGLocalTitle)[self unmount:was];
        [self skip:view because:@"当前页面标题胶囊开关已关闭"];return;
    }
    // FIX114 V (user's screenshot, 23:46: a capsule with the chat's name and no
    // avatar in a swipe back): WeChat's new title view for the chat got a
    // capsule here; a chat title the plugin draws is hidden, never glassed.
    if([WXGIntegrationHost.shared concealsChatTitleView:view]) {
        WXGLocalEntry *was=WXGLocalEntryOfAnchor(view);if(was.mounted && was.kind==WXGLocalTitle)[self unmount:was];
        [self skip:view because:@"聊天标题由插件自己画（头像模式）"];return;
    }
    if(view.layer.mask){[self skip:view because:@"标题由插件自己画（聊天页）"];return;}
    BOOL wasMounted=WXGLocalEntryOfAnchor(view).mounted;   // FIX108 F
    // A glass already there stays through a one-pass collapse (mount keeps it).
    if(CGRectIsNull(WXGLocalTitleFrame(view,NULL,NULL)) && !wasMounted) {
        // The close-area twin may be laid out hidden. Observe it before its
        // first mount so showing its text can install the glass in that pass.
        if(_homeTitle && [view isKindOfClass:_homeTitle])[self watchTitle:view];
        [self skip:view because:@"没有标题文字，或标题太长 / 两行" retry:YES];return;
    }
    __weak UIView *weakView=view;
    [self mount:WXGLocalTitle host:view anchor:view paint:nil below:nil measure:nil frame:^CGRect{UIView *v=weakView;return v?WXGLocalInsideBar(v,WXGLocalTitleFrame(v,NULL,NULL)):CGRectNull;}
         radius:0 button:nil prepare:^(WXGStateBag *states){[states allowOverflow:view];}];
    [self setInk:^UIColor *{UIColor *c=nil;UIView *v=weakView;if(v)WXGLocalTitleFrame(v,&c,NULL);return c;} of:view];
    WXGLocalEntryOfAnchor(view).titleMeasure=^CGRect(UIColor **ink,CGFloat *shown){UIView *v=weakView;if(!v){if(shown)*shown=0;return CGRectNull;}return WXGLocalInsideBar(v,WXGLocalTitleFrame(v,ink,shown));};
    if(WXGLocalEntryOfAnchor(view).mounted)[self watchTitle:view];   // FIX115 F
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
    if(!WXGLocalTitleAllowedForView(content)) {
        WXGLocalEntry *was=WXGLocalEntryOfAnchor(content);if(was.mounted && was.kind==WXGLocalTitle)[self unmount:was];
        [self skip:content because:@"当前页面标题胶囊开关已关闭"];return;
    }
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
/* FIX114 L (user: WeChat's own back button draws its unread count in a
   small capsule; our glass capsule should keep the same margin to it all
   round): the count's own capsule, when it has one: the label's background,
   or a view right behind the label (its own colour or picture, about the
   label's height). CGRectNull when the count is bare text. */
static NSDictionary *WXGLocalLastPill;
// FIX114 M: the page whose bar items hold this control (nil: none found).
static UIViewController *WXGLocalNavOwner(UIView *control,UINavigationController **navOut) {
    UINavigationBar *bar=WXGLocalBarOf(control);id delegate=bar.delegate;
    if(navOut)*navOut=nil;
    if(!control || ![delegate isKindOfClass:UINavigationController.class])return nil;
    UINavigationController *nav=delegate;if(navOut)*navOut=nav;
    NSMutableArray<UIViewController *> *pages=[nav.viewControllers.reverseObjectEnumerator.allObjects mutableCopy]?:[NSMutableArray array];
    // FIX114 O (review): a page being popped is out of the stack from the
    // pop's start (a swipe back too): its buttons are still its own.
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
    return nil;
}
// FIX114 L: the page whose bar items hold this control is not the top one.
static BOOL WXGLocalNavDeparting(UIView *control) {
    UINavigationController *nav=nil;UIViewController *owner=WXGLocalNavOwner(control,&nav),*top=nav.topViewController;
    return owner && top && owner!=top;
}
// FIX114 M (user: in a half swipe back the chat's right button got smaller;
// entering a chat its buttons jumped twice): during a push or a pop both
// pages' items are in the bar. The room to the next button and the side's
// shift were measured against the other page's buttons too (the home page's
// own button under the chat's 「…」 left it no room). Only buttons of the
// same page count now (when the page is known for both).
// FIX114 M: drawn by nothing: hidden by an empty mask (the host's conceal:
// a button whose glass the host draws itself) up to `root`.
static BOOL WXGLocalMaskedOut(UIView *v,UIView *root) {
    for(UIView *p=v;p && p!=root;p=p.superview) {
        CALayer *mask=p.layer.mask;
        if(mask && !mask.contents && !mask.sublayers.count && (CGRectIsEmpty(mask.bounds) || !mask.backgroundColor))return YES;
    }
    return NO;
}
static BOOL WXGLocalSameNavPage(UIView *a,UIView *b) {
    UIViewController *pa=WXGLocalNavOwner(a,NULL),*pb=WXGLocalNavOwner(b,NULL);
    return !pa || !pb || pa==pb;
}
static BOOL WXGLocalPainted(UIView *v) {
    CGColorRef c=v.layer.backgroundColor;
    if(c && CGColorGetAlpha(c)>.05)return YES;
    return [v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image!=nil;
}
static CGRect WXGLocalCountPill(UIButton *button,UILabel *title,UIImageView *icon,NSString **source) {
    if(!title)return CGRectNull;
    CGRect text=WXGLocalFrameIn(title,button,WXGLocalTextRect(title)),label=WXGLocalFrameIn(title,button,title.bounds);
    CGPoint mid=CGPointMake(CGRectGetMidX(text),CGRectGetMidY(text));
    if(WXGLocalPainted(title) && label.size.height<=text.size.height+20){if(source)*source=@"label";return label;}
    UIView *parent=title.superview;
    if(parent && parent!=button && WXGLocalPainted(parent)) {
        CGRect r=WXGLocalFrameIn(parent,button,parent.bounds);
        if(CGRectContainsPoint(r,mid) && r.size.height<=text.size.height+20 && r.size.width<=text.size.width+40){if(source)*source=NSStringFromClass(parent.class);return r;}
    }
    CGRect best=CGRectNull;
    for(UIView *v in button.subviews) {
        if(v==title || v==icon || WXGIsPluginView(v) || v.hidden || v.alpha<.01 || !WXGLocalPainted(v))continue;
        CGRect r=WXGLocalFrameIn(v,button,v.bounds);
        if(!CGRectContainsPoint(r,mid) || r.size.height<text.size.height-1 || r.size.height>text.size.height+20 || r.size.width>text.size.width+40)continue;
        if(CGRectIsNull(best) || r.size.width*r.size.height<best.size.width*best.size.height){best=r;if(source)*source=NSStringFromClass(v.class);}
    }
    return best;
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
    // FIX114 L: a count in its own capsule: the glass ends that capsule's
    // top / bottom margin past it (the left side as before).
    NSString *source=nil;CGRect pill=icon?WXGLocalCountPill(button,title,icon,&source):CGRectNull;
    if(!CGRectIsNull(pill) && pill.size.height<h-1) {
        CGFloat pad=10*m.scale,margin=MAX(2,(h-pill.size.height)*.5);
        CGRect body=CGRectUnion(iconRect,pill);
        CGFloat left=CGRectGetMinX(body)-pad,width=MAX(h,CGRectGetMaxX(pill)+margin-left);
        width=MIN(MIN(width,w.bounds.size.width*.36),MAX(h,limit));
        WXGLocalLastPill=@{@"source":source?:@"",@"pill":@[@(pill.origin.x),@(pill.origin.y),@(pill.size.width),@(pill.size.height)],
                           @"text":@[@(titleRect.origin.x),@(titleRect.size.width)],@"margin":@(round(margin*10)/10),@"width":@(round(width*10)/10)};
        return CGRectMake(left,CGRectGetMidY(pill)-h*.5,width,h);
    }
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
        if(!WXGLocalSameNavPage(v,button) || WXGLocalMaskedOut(v,bar))continue;   // FIX114 M
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
// the bar are drawn shifted (their contents: WeChat's icon / text and the
// glass, a subview); the buttons themselves and their touches stay where
// WeChat put them.
/* FIX114 O (user, 09:07: entering a chat the three still jump together; the
   plugin's own buttons never do; 通讯录's two buttons not like the home page's).
   diagnostics_10: entering a chat the left side's shift was worked out as
   28.3 pt, then 8.3 pt 0.26 s later, the right side's 0 then -8.3 pt: the
   shift was measured from where the buttons were on screen, and in a push
   they are on their way in. The plugin's own buttons are placed by the row's
   numbers alone. Now WeChat's buttons are too: each button of a side gets the
   slot the plugin's own row gives it (the outermost at 顶部按钮离屏幕两边,
   the next a gap (m.gap) further in, each glass its full size, like the home
   page), and its shift is that slot less where WeChat puts it when the page
   has settled: the bar's side, WeChat's margin there (16 pt; learned from a
   settled page, per page class), and the buttons' places relative to the
   outermost one (they move together, so a push does not change them). No
   measurement of a moving button; a button faded out (通讯录's search one)
   keeps its slot. A side with a button of its own colour (a green 完成) is
   left as WeChat has it (as before). */
static NSMutableDictionary<NSString *,NSNumber *> *WXGLocalMargins;
static NSString *WXGLocalMarginKey(UIViewController *page,BOOL left) {return [NSString stringWithFormat:@"%@|%@",page?NSStringFromClass(page.class):@"*",left?@"L":@"R"];}
static CGFloat WXGLocalNativeMargin(UIViewController *page,BOOL left) {
    NSNumber *v=WXGLocalMargins[WXGLocalMarginKey(page,left)]?:WXGLocalMargins[WXGLocalMarginKey(nil,left)];
    return v?v.doubleValue:16;
}
static void WXGLocalLearnMargin(UIViewController *page,BOOL left,CGFloat margin) {
    if(!isfinite(margin) || margin<0 || margin>48)return;
    if(!WXGLocalMargins)WXGLocalMargins=[NSMutableDictionary dictionary];
    margin=round(margin*3)/3;
    WXGLocalMargins[WXGLocalMarginKey(page,left)]=@(margin);WXGLocalMargins[WXGLocalMarginKey(nil,left)]=@(margin);
}
// Which of the page's sides holds the control: 0 left, 1 right, -1 neither.
static NSInteger WXGLocalNavSide(UIView *control,UIViewController *page) {
    UINavigationItem *item=page.navigationItem;if(!item || !control)return -1;
    for(UIBarButtonItem *b in item.leftBarButtonItems?:@[])if(b.customView && (control==b.customView || [control isDescendantOfView:b.customView]))return 0;
    for(UIBarButtonItem *b in item.rightBarButtonItems?:@[])if(b.customView && (control==b.customView || [control isDescendantOfView:b.customView]))return 1;
    return -1;
}
static BOOL WXGLocalHiddenIn(UIView *v,UIView *root) {for(UIView *p=v;p && p!=root;p=p.superview)if(p.hidden)return YES;return NO;}
// The slots of one side of a page: button (pointer) -> shift, or nil when
// that side is left as WeChat has it. Cached a quarter second per page and
// side, and worked out again for a button it does not know.
static char WXGLocalSlotKey;
static NSUInteger WXGLocalSlotBuilds;
// (review) What the side's layout depends on, cheaply (no text layout): each
// button's place relative to the first and size, its subviews' frames, shown
// state and a label's text (a count appearing widens the back button).
static NSUInteger WXGLocalSlotSignature(NSArray<UIButton *> *buttons,UIView *bar) {
    NSUInteger h=buttons.count;CGRect first=CGRectNull;
    for(UIButton *b in buttons) {
        if(!b.superview)return 0;
        CGRect f=WXGLocalFrameIn(b,bar,b.bounds);if(CGRectIsNull(first))first=f;
        h=h*131+(NSUInteger)(long)lround((CGRectGetMinX(f)-CGRectGetMinX(first))*4)*7+(NSUInteger)(long)lround(f.size.width*4)*13+(NSUInteger)(long)lround(f.size.height*4)*17;
        for(UIView *v in b.subviews) {
            if(WXGIsPluginView(v))continue;
            CGRect r=v.frame;
            h=h*131+(NSUInteger)(long)lround(r.origin.x*4)*3+(NSUInteger)(long)lround(r.size.width*4)*5+(NSUInteger)(long)lround(r.size.height*4)*7+(v.hidden?11:0)+(v.alpha<.01?19:0);
            if([v isKindOfClass:UILabel.class])h=h*131+((UILabel *)v).text.hash;
            else if([v isKindOfClass:UIImageView.class])h=h*131+(NSUInteger)(uintptr_t)(__bridge void *)((UIImageView *)v).image;   // FIX114 P: an icon given later
        }
    }
    return h?:1;
}
static NSDictionary<NSValue *,NSNumber *> *WXGLocalSlots(UIButton *button,BOOL *inLayout) {
    if(inLayout)*inLayout=NO;
    UINavigationBar *bar=WXGLocalBarOf(button);UIWindow *w=button.window;if(!bar || !w)return nil;
    UINavigationController *nav=nil;UIViewController *page=WXGLocalNavOwner(button,&nav);if(!page)return nil;
    NSInteger side=WXGLocalNavSide(button,page);if(side<0)return nil;
    NSString *key=[NSString stringWithFormat:@"%p|%ld",page,(long)side];NSValue *mine=[NSValue valueWithNonretainedObject:button];
    NSMutableDictionary *cache=objc_getAssociatedObject(bar,&WXGLocalSlotKey);
    if(![cache isKindOfClass:NSMutableDictionary.class]){cache=[NSMutableDictionary dictionary];objc_setAssociatedObject(bar,&WXGLocalSlotKey,cache,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    // {time, shifts (NSNull: the side left as WeChat has it), painted, outside
    // (buttons asked that are not in it -> their own signature then), buttons
    // (weak), signature}
    NSDictionary *cached=cache[key];CFTimeInterval now=CACurrentMediaTime();
    BOOL fresh=cached && now-[cached[@"time"] doubleValue]<.25;
    if(fresh) {
        NSPointerArray *was=cached[@"buttons"];NSArray *alive=was.allObjects;
        if(alive.count==was.count && WXGLocalSlotSignature(alive,bar)==[cached[@"signature"] unsignedIntegerValue]) {
            NSDictionary *known=[cached[@"shifts"] isKindOfClass:NSDictionary.class]?cached[@"shifts"]:nil;
            if(known[mine]){if(inLayout)*inLayout=YES;return known;}
            if(cached[@"painted"])return nil;
            // FIX114 P (diagnostics_11: the chat's 「…」 got its shift 0.26 s after
            // the back button, every time): it had asked before WeChat gave it its
            // icon, and that answer was kept for a quarter second. A button not in
            // the layout is answered from the cache only while it is as it was then.
            NSNumber *asked=((NSDictionary *)cached[@"outside"])[mine];
            if(asked && asked.unsignedIntegerValue==WXGLocalSlotSignature(@[button],bar))return nil;
        }
    }
    ++WXGLocalSlotBuilds;
    BOOL left=side==0;
    // (review) A side with bar items that are not WeChat's own views (a system
    // item), or with the system back button beside them: left as it is.
    UINavigationItem *item=page.navigationItem;
    BOOL foreign=NO;
    for(UIBarButtonItem *b in (left?item.leftBarButtonItems:item.rightBarButtonItems)?:@[])if(!b.customView){foreign=YES;break;}
    if(left && item.leftItemsSupplementBackButton && !item.hidesBackButton && nav.viewControllers.firstObject!=page)foreign=YES;
    NSMutableArray<UIButton *> *buttons=[NSMutableArray array];BOOL painted=foreign;
    if(!painted)for(UIView *v in WXGLocalViews(bar,160)) {
        if(![v isKindOfClass:UIButton.class] || WXGIsPluginView(v) || WXGLocalHiddenIn(v,bar))continue;
        if(WXGLocalNavOwner(v,NULL)!=page || WXGLocalNavSide(v,page)!=side)continue;
        if(![WXGIntegrationHost.shared leavesNavigationControlNative:v])continue;
        UIButton *b=(UIButton *)v;
        if(WXGLocalOwnPaint(b)){painted=YES;break;}   // FIX115 J: a coloured one ours to tint counts too
        if(CGRectIsNull(WXGLocalNavButtonFrame(b,CGFLOAT_MAX,NULL)))continue;
        BOOL nested=NO;for(UIButton *o in buttons)if([b isDescendantOfView:o] || [o isDescendantOfView:b]){nested=YES;break;}
        if(!nested)[buttons addObject:b];
    }
    NSMutableDictionary *outside=fresh && [cached[@"outside"] isKindOfClass:NSDictionary.class]?[(NSDictionary *)cached[@"outside"] mutableCopy]:[NSMutableDictionary dictionary];   // (review) not one rebuild each per turn
    if(cache.count>8)[cache removeAllObjects];
    if(painted || !WXGPreferences.shared.localNavButtons || !buttons.count) {
        outside[mine]=@(WXGLocalSlotSignature(@[button],bar));
        NSMutableDictionary *entry=[@{@"time":@(now),@"shifts":NSNull.null,@"outside":outside,@"buttons":[NSPointerArray weakObjectsPointerArray],@"signature":@(WXGLocalSlotSignature(@[],bar))} mutableCopy];
        if(painted)entry[@"painted"]=@YES;
        cache[key]=entry;
        if(WXGNavTraceOn())WXGNavTraceEventOnce([@"slot|" stringByAppendingString:key],[NSString stringWithFormat:@"槽位 %@ %@：不挪（%@）",WXGNavTracePage(page),left?@"左":@"右",
            foreign?@"有不是微信自己画的项":painted?@"按钮有底图":!WXGPreferences.shared.localNavButtons?@"顶部按钮玻璃关着":@"没找到按钮"]);   // FIX114 R
        return nil;
    }
    // Outermost first, by their places relative to one another (frames only).
    NSMutableDictionary<NSValue *,NSValue *> *frames=[NSMutableDictionary dictionary];
    for(UIButton *b in buttons)frames[[NSValue valueWithNonretainedObject:b]]=[NSValue valueWithCGRect:WXGLocalFrameIn(b,bar,b.bounds)];
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *a,UIButton *b) {
        CGRect fa=frames[[NSValue valueWithNonretainedObject:a]].CGRectValue,fb=frames[[NSValue valueWithNonretainedObject:b]].CGRectValue;
        CGFloat ka=left?CGRectGetMinX(fa):-CGRectGetMaxX(fa),kb=left?CGRectGetMinX(fb):-CGRectGetMaxX(fb);
        return ka<kb?NSOrderedAscending:ka>kb?NSOrderedDescending:NSOrderedSame;
    }];
    if(buttons.count>8)[buttons removeObjectsInRange:NSMakeRange(8,buttons.count-8)];
    UIButton *outer=buttons.firstObject;
    // (review) All in the bar's own coordinates (a page shown smaller under a
    // sheet scales the window's): the bar's width and safe area, and WeChat's
    // margin learned there when the page has settled (no push / pop, on top).
    CGFloat barW=bar.bounds.size.width;
    if(!nav.transitionCoordinator && nav.topViewController==page) {
        CGRect f=frames[[NSValue valueWithNonretainedObject:outer]].CGRectValue;
        CGFloat learned=left?CGRectGetMinX(f)-CGRectGetMinX(bar.bounds):CGRectGetMaxX(bar.bounds)-CGRectGetMaxX(f);
        if(f.size.width>1 && learned>=2 && learned<=40)WXGLocalLearnMargin(page,left,learned);   // (review) not a button not laid out yet
    }
    CGFloat margin=WXGLocalNativeMargin(page,left);
    WXGMetrics m=WXGLocalBarMetrics(button);CGFloat scale=w.screen.scale?:3;
    // FIX115 S: a 视频号 page's own margin (finderEdge), as the title row's there.
    CGFloat edge=[NSStringFromClass(page.class) hasPrefix:@"WCFinder"]?WXGFinderRowEdge(m.scale):WXGTitleRowEdge(m.scale);
    UIEdgeInsets safe=bar.safeAreaInsets;
    CGFloat x=left?CGRectGetMinX(bar.bounds)+safe.left+edge:CGRectGetMaxX(bar.bounds)-safe.right-edge;
    int n=(int)buttons.count;WXGNavSlotButton slots[8];double out[8];
    for(int i=0;i<n;i++) {
        UIButton *b=buttons[(NSUInteger)i];
        CGRect f=frames[[NSValue valueWithNonretainedObject:b]].CGRectValue,glass=WXGLocalNavButtonFrame(b,CGFLOAT_MAX,NULL);
        slots[i]=(WXGNavSlotButton){CGRectGetMinX(f),CGRectGetMaxX(f),CGRectGetMinX(glass),CGRectGetMaxX(glass),b.bounds.size.width};
    }
    WXGNavSlotShifts(left,slots,n,CGRectGetMinX(bar.bounds),CGRectGetMinX(bar.bounds)+barW,margin,x,m.gap,out);
    // (review) A layout this does not know (a shift over 64 pt): the whole side as WeChat has it.
    BOOL wild=NO;for(int i=0;i<n;i++)if(fabs(out[i])>64)wild=YES;
    NSPointerArray *kept=[NSPointerArray weakObjectsPointerArray];for(UIButton *b in buttons)[kept addPointer:(__bridge void *)b];
    NSUInteger signature=WXGLocalSlotSignature(buttons,bar);
    if(WXGNavTraceOn()) {   // FIX114 R
        NSMutableArray *list=[NSMutableArray array];for(int i=0;i<n;i++)[list addObject:[NSString stringWithFormat:@"%.1f",out[i]]];
        WXGNavTraceEventOnce([@"slot|" stringByAppendingString:key],[NSString stringWithFormat:@"槽位 %@ %@：%d 个按钮，微信边距 %.1f，挪 %@%@",WXGNavTracePage(page),left?@"左":@"右",n,margin,
            [list componentsJoinedByString:@" / "],wild?@"（超过 64 pt，不挪）":@""]);
    }
    if(wild) {
        cache[key]=@{@"time":@(now),@"shifts":NSNull.null,@"painted":@YES,@"outside":outside,@"buttons":kept,@"signature":@(signature)};
        return nil;
    }
    NSMutableDictionary<NSValue *,NSNumber *> *shifts=[NSMutableDictionary dictionary];
    for(int i=0;i<n;i++) {
        CGFloat shift=round(out[i]*scale)/scale;
        shifts[[NSValue valueWithNonretainedObject:buttons[(NSUInteger)i]]]=@(fabs(shift)<.5?0:shift);
    }
    BOOL member=shifts[mine]!=nil;if(!member)outside[mine]=@(WXGLocalSlotSignature(@[button],bar));
    cache[key]=@{@"time":@(now),@"shifts":shifts,@"outside":outside,@"buttons":kept,@"signature":@(signature)};
    if(inLayout)*inLayout=member;
    return member?shifts:nil;
}
// This button's shift (0 when its side is left as WeChat has it).
static CGFloat WXGLocalSideShift(UIButton *button) {
    BOOL in=NO;NSDictionary *shifts=WXGLocalSlots(button,&in);
    return in?[shifts[[NSValue valueWithNonretainedObject:button]] doubleValue]:0;
}
// The glass's size limit: its full size in a slot (no neighbour that close),
// else as wide as the gap to the next button allows (as before).
static CGFloat WXGLocalNavLimit(UIButton *button) {
    BOOL in=NO;WXGLocalSlots(button,&in);
    return in?CGFLOAT_MAX:WXGLocalNavRoom(button);
}
// FIX114 O: how visible WeChat shows a button now (its and its parents'
// opacity as drawn, up to the bar): a departing page's glass fades with it.
static CGFloat WXGLocalPresentedAlpha(UIView *view,UIView *root) {
    CGFloat alpha=1;
    for(UIView *p=view;p && p!=root;p=p.superview) {
        CALayer *l=p.layer.presentationLayer?:p.layer;
        if(l.hidden)return 0;alpha*=l.opacity;if(alpha<.005)return 0;
    }
    return alpha;
}
/* FIX114 S (user, 13:12: "跟那个自己画的同一个逻辑，只要在返回过程中左右的
   两个元素就完全消失"): a leaving page's title-bar buttons are hidden whole,
   WeChat's icon and the glass in it (an empty mask: UIKit's own fades of the
   button cannot bring it back).
   FIX114 T (user, 13:48: "照样，反而还把进入后的按钮出现延迟了"; diagnostics_13,
   the trace): S hid the arriving page's buttons too and held them a moment
   after the push: the delay. Now only the page that leaves (a pop or a swipe
   back: the chat; a push: the page under) loses its buttons, from the moment
   the push / pop starts; the arriving page's are never hidden. A hidden
   button no page holds any more (WeChat replaced it) stays hidden until it
   goes; one whose page shows it again (a cancelled swipe that kept it) comes
   back over 0.15 s. */
static UIViewController *WXGLocalNavLeaving(UIView *button) {
    UINavigationBar *bar=WXGLocalBarOf(button);id delegate=bar.delegate;
    if(![delegate isKindOfClass:UINavigationController.class])return nil;
    UINavigationController *nav=delegate;id<UIViewControllerTransitionCoordinator> c=nav.transitionCoordinator;
    if(!c)return nil;
    // A push or a pop in this navigation, not a sheet presenting it.
    UIViewController *from=[c viewControllerForKey:UITransitionContextFromViewControllerKey],*to=[c viewControllerForKey:UITransitionContextToViewControllerKey];
    return to.navigationController==nav && (!from.navigationController || from.navigationController==nav)?from:nil;
}
- (BOOL)veilNav:(WXGLocalEntry *)entry {
    if(entry.kind!=WXGLocalNavButton || !entry.mounted)return NO;
    UIView *button=entry.button?(UIView *)entry.button:entry.anchor;if(!button || !button.window)return entry.veiled;
    UIViewController *owner=WXGLocalNavOwner(button,NULL),*page=owner?:entry.navPage,*leaving=WXGLocalNavLeaving(button);
    if(leaving && page==leaving) {
        if(!entry.veiled) {
            entry.veiled=YES;[entry.states conceal:button];++_veils;
            if(WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"离开的页面，藏起 %@",WXGLocalTraceName(entry,button)]);
        }
        return YES;
    }
    if(entry.veiled && owner) {
        entry.veiled=NO;[entry.states unconceal:button];++_reveals;
        if(WXGNavTraceOn())WXGNavTraceEvent([NSString stringWithFormat:@"页面又显示它，显示 %@ 挪%.1f",WXGLocalTraceName(entry,button),[entry.states contentShiftOf:button]]);
        CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue=@0;fade.toValue=@(button.layer.opacity);fade.duration=.15;
        fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [button.layer addAnimation:fade forKey:@"wxg.navReveal"];
    }
    return entry.veiled;
}
/* FIX114 T (diagnostics_13: at the end of a push WeChat puts new buttons in
   and the old ones, no page's any more, are on screen a moment longer: their
   shift went back to 0 (no layout holds them) and their icons jumped to
   WeChat's place before the new ones showed: entering a chat, the buttons
   jumped twice): a button no page holds keeps the shift it has. */
static CGFloat WXGLocalKeptShift(WXGLocalEntry *entry,UIButton *button) {
    return WXGLocalNavOwner(button,NULL)?WXGLocalSideShift(button):[entry.states contentShiftOf:button];
}
- (void)navButton:(UIView *)view {
    if(![view isKindOfClass:UIButton.class])return;
    UIButton *button=(UIButton *)view;
    // Not in a title bar, a page the host takes, or a button with its own glass.
    if(![WXGIntegrationHost.shared leavesNavigationControlNative:button]) {
        if([self keepThroughMove:WXGLocalEntryOfAnchor(view)])return;   // FIX114 M
        [self skip:view because:@"顶部按钮适配已接管，或不在导航栏"];return;
    }
    if(WXGLocalTintMounted(view))return;   // FIX115 J (review): the coloured glass is there (never remounted as a navButton)
    BOOL mounted=WXGLocalEntryOfAnchor(view).mounted;
    if(!mounted && WXGLocalOwnPaint(view)){[self skip:view because:@"按钮自己有底色（如绿色完成）"];return;}
    // Hidden or faded: the glass is inside the button and hides with it.
    if(CGRectIsNull(WXGLocalNavButtonFrame(button,WXGLocalNavLimit(button),NULL)) && !mounted){[self skip:view because:@"按钮没有图标或文字" retry:YES];return;}
    __weak UIButton *weakButton=button;
    // FIX108 C: the room to the next button looked at again each time (one can appear beside it).
    [self mount:WXGLocalNavButton host:view anchor:view paint:nil below:nil measure:nil frame:^CGRect{UIButton *b=weakButton;return b?WXGLocalInsideBar(b,WXGLocalNavButtonFrame(b,WXGLocalNavLimit(b),NULL)):CGRectNull;}
         radius:0 button:button prepare:^(WXGStateBag *states){[states allowOverflow:view];}];
    [self setInk:^UIColor *{UIColor *c=nil;UIButton *b=weakButton;if(b)WXGLocalNavButtonFrame(b,CGFLOAT_MAX,&c);return c;} of:view];
    // FIX114 N: its page, side and place (a button replacing it takes its
    // glass), and its side's shift now, not on the next turn (one frame at
    // WeChat's place showed as a jump).
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(view);
    if(entry.mounted && button.window) {
        UIWindow *w=button.window;CGRect r=[button convertRect:button.bounds toView:w];
        // FIX114 T: the page and side it was last a button of (a button WeChat
        // has replaced keeps them: its replacement takes its glass by them).
        UIViewController *owner=WXGLocalNavOwner(button,NULL);
        if(owner){entry.navPage=owner;entry.navSide=WXGLocalNavSide(button,owner);entry.navWidth=button.bounds.size.width;}   // FIX114 Q
        entry.navLeft=CGRectGetMidX(r)<w.bounds.size.width*.5;entry.navRect=r;
        // FIX114 P: a departing page's button too (the slots do not depend on
        // where a push or pop has the buttons; a button WeChat put in as the page
        // left stayed at WeChat's place).
        CGFloat was=[entry.states contentShiftOf:view],to=WXGLocalKeptShift(entry,button);   // FIX114 T
        if(fabs(was-to)>.01){[self noteShift:entry from:was to:to];[entry.states shiftContents:view x:to];}
    }
    [self openClipsAbove:entry];   // FIX115 K: 取消 cut to its button's size by its containers
    [self veilNav:entry];   // FIX114 S / T: the leaving page's, hidden whole
    [self followShown:entry immediately:!mounted];
}
// FIX115 J: WeChat's coloured buttons (FixTitleColorButton). Any visible fill
// counts (its grey when it cannot be pressed too); the tint is the fill when
// it is a colour at all (saturated), else plain glass.
static BOOL WXGLocalHasFill(UIView *v) {
    UIColor *c=v.backgroundColor;if(!c)return NO;
    return CGColorGetAlpha([c resolvedColorWithTraitCollection:v.traitCollection].CGColor)>.02;
}
static UIColor *WXGLocalFillTint(UIColor *color,UITraitCollection *traits) {
    if(!color)return nil;
    UIColor *c=traits?[color resolvedColorWithTraitCollection:traits]:color;
    CGFloat r=0,g=0,b=0,a=0;
    if(![c getRed:&r green:&g blue:&b alpha:&a]){CGFloat white=0;if(![c getWhite:&white alpha:&a])return nil;r=g=b=white;}
    if(a<.5)return nil;
    CGFloat hi=MAX(r,MAX(g,b)),lo=MIN(r,MIN(g,b));
    return hi>.3 && hi-lo>.25?[UIColor colorWithRed:WXGClamp(r,0,1) green:WXGClamp(g,0,1) blue:WXGClamp(b,0,1) alpha:1]:nil;
}
// (review) As drawn: a dynamic colour made anew each time is the same fill.
static BOOL WXGLocalSameFill(UIColor *a,UIColor *b,UITraitCollection *traits) {
    if(a==b || [a isEqual:b])return YES;
    if(!a || !b)return NO;
    UIColor *x=traits?[a resolvedColorWithTraitCollection:traits]:a,*y=traits?[b resolvedColorWithTraitCollection:traits]:b;
    return CGColorEqualToColor(x.CGColor,y.CGColor);
}
static BOOL WXGLocalTintMounted(UIView *v) {
    WXGLocalEntry *entry=WXGLocalEntryOfAnchor(v);
    return entry.kind==WXGLocalTint && entry.mounted;
}
// In a title bar: as tall as the bar's other glass, as wide as its title
// (with the same padding as a text button's capsule) and never narrower than
// the button, centred on it; never into the next button's glass.
static CGRect WXGLocalTintNavFrame(UIButton *button) {
    UIWindow *w=button.window;if(!w)return CGRectNull;
    WXGMetrics m=WXGLocalBarMetrics(button);CGFloat h=m.button;
    UILabel *title=nil;WXGLocalButtonParts(button,NULL,&title);
    CGFloat text=title?WXGLocalTextRect(title).size.width:0;
    CGRect b=button.bounds;
    CGFloat width=MAX(b.size.width,WXGCapsuleWidth(text,0,h,14*m.scale,w.bounds.size.width*.36));
    width=MIN(width,MAX(MAX(h,b.size.width),WXGLocalNavRoom(button)));
    return CGRectMake(CGRectGetMidX(b)-width*.5,CGRectGetMidY(b)-h*.5,width,h);
}
- (void)colorButton:(UIView *)view {
    if(![view isKindOfClass:UIButton.class])return;
    UIButton *button=(UIButton *)view;CGRect b=button.bounds;BOOL mounted=WXGLocalTintMounted(button);
    if(b.size.width<1 || b.size.height<1){if(!mounted)[self skip:view because:@"还没有尺寸" retry:YES];return;}
    if(b.size.width<24 || b.size.height<20 || b.size.height>64){[self skip:view because:@"带颜色的按钮尺寸不对"];return;}
    UINavigationBar *bar=WXGLocalBarOf(button);
    // (review) Out of its bar for a moment (UIKit moves the items between its
    // containers as a push ends; FIX114 M): kept at its title-bar size.
    if(!bar && mounted && WXGLocalEntryOfAnchor(button).frame)return;
    // A title bar's button the host draws in its own glass (its pages): not ours.
    if(bar && ![WXGIntegrationHost.shared leavesNavigationControlNative:button]){[self skip:view because:@"顶部按钮适配已接管"];return;}
    if(!mounted && !WXGLocalHasFill(button)){[self skip:view because:@"按钮没有底色" retry:YES];return;}
    __weak UIButton *weakButton=button;
    CGRect (^frame)(void)=bar?^CGRect{UIButton *x=weakButton;return x?WXGLocalInsideBar(x,WXGLocalTintNavFrame(x)):CGRectNull;}:nil;
    [self mount:WXGLocalTint host:view anchor:view paint:view below:nil measure:bar?nil:view frame:frame radius:0 button:button
        prepare:^(WXGStateBag *states){[states allowOverflow:view];[states unmask:view];[states guardFill:view];}];   // FIX115 L: its fill kept off
    if(bar)[self openClipsAbove:WXGLocalEntryOfAnchor(view)];   // FIX115 K
    [self hideCoversOn:WXGLocalEntryOfAnchor(view)];             // FIX115 M
}
/* FIX115 M (user, 21:03, screenshot: the login page's green button, held:
   square grey corners round the capsule, the capsule paler): WeChat's own
   press look on these buttons is a translucent cover laid over the whole
   button while it is held, rounded by the mask the glass takes off — its
   square corners showed. The glass presses itself: anything on the button
   that covers it (most of its size: a view other than its title, or a layer
   of no view with a fill or a picture) is hidden while the glass is there
   (a view by an empty mask, so WeChat's fades cannot show it; a layer by
   hidden), looked at on every layout of the button and every turn. What was
   hidden is noted (diagnostics: localGlass.pressCovers). */
static BOOL WXGLocalCovering(CGRect r,CGRect b) {
    return r.size.width>=b.size.width*.8 && r.size.height>=b.size.height*.8 &&
        CGRectGetMidX(r)>=CGRectGetMinX(b) && CGRectGetMidX(r)<=CGRectGetMaxX(b) && CGRectGetMidY(r)>=CGRectGetMinY(b) && CGRectGetMidY(r)<=CGRectGetMaxY(b);
}
- (void)hideCoversOn:(WXGLocalEntry *)entry {
    UIView *button=entry.anchor;
    if(!entry.mounted || entry.kind!=WXGLocalTint || !button)return;
    CGRect b=button.bounds;if(b.size.width<1 || b.size.height<1)return;
    NSMutableSet<CALayer *> *viewLayers=[NSMutableSet set];
    for(UIView *v in button.subviews) {
        [viewLayers addObject:v.layer];
        if(v==entry.surface || WXGIsPluginView(v) || [v isKindOfClass:UILabel.class])continue;
        // Never the button's own picture (an icon as big as the button).
        if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image &&
           (![button isKindOfClass:UIButton.class] || ((UIImageView *)v).image==((UIButton *)button).currentImage))continue;
        if(!WXGLocalCovering(v.frame,b) || [v.layer.mask.name isEqualToString:@"wxg.conceal"])continue;   // (already hidden)
        [entry.states conceal:v];[self noteCover:NSStringFromClass(v.class) frame:v.frame];
    }
    for(CALayer *l in button.layer.sublayers.copy) {
        if([viewLayers containsObject:l] || l.hidden || [l.delegate isKindOfClass:UIView.class])continue;
        if(!l.backgroundColor && !l.contents && ![l isKindOfClass:CAShapeLayer.class] && ![l isKindOfClass:CAGradientLayer.class])continue;
        if(!WXGLocalCovering(l.frame,b))continue;
        [entry.states hideDecorationLayer:l];[self noteCover:NSStringFromClass(l.class) frame:l.frame];
    }
}
- (void)noteCover:(NSString *)name frame:(CGRect)f {
    if(!_pressCovers)_pressCovers=[NSMutableArray array];
    [_pressCovers addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f %.0fx%.0f",name,f.origin.x,f.origin.y,f.size.width,f.size.height]];
    if(_pressCovers.count>8)[_pressCovers removeObjectAtIndex:0];
}
/* FIX115 K (user, 13:07: 完成 and 取消 "被那个方框完全切割掉了", not the size of
   the other title-bar buttons): a title-bar glass is larger than WeChat's
   button (as tall as the bar's other glass), and the containers the title bar
   holds a custom button in can clip to the button's own size. Every view from
   the glass up to its title bar (not the bar) that clips it — its rim and
   shadow included — is held open until the glass goes (WXGHoldClipOpen). */
- (void)openClipsAbove:(WXGLocalEntry *)entry {
    UIView *anchor=entry.anchor;WXGSurface *surface=entry.surface;
    if(!entry.mounted || !anchor || surface.superview!=anchor)return;
    UINavigationBar *bar=WXGLocalBarOf(anchor);if(!bar)return;
    NSUInteger depth=0,opened=0;
    for(UIView *p=anchor.superview;p && p!=bar && depth<10;p=p.superview,depth++) {
        // Only the containers of a button (never the bar's own content view, the bar's width).
        if(!p.clipsToBounds || p.bounds.size.width>=bar.bounds.size.width*.8)continue;
        CGRect r=[surface convertRect:surface.bounds toView:p];
        if(CGRectContainsRect(CGRectInset(p.bounds,-.5,-.5),r))continue;
        // (review) Held with the shadows' count (WXGHoldClipOpen): several glasses and
        // bags opening one container give it back right whoever lets go last.
        WXGHoldClipOpen(p,entry);++opened;
    }
    entry.openedClips=MAX(entry.openedClips,opened);
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
    if(entry.kind==WXGLocalNavButton && WXGLocalNavDeparting(entry.button)) {   // FIX114 L; O: fades with WeChat's button
        CGFloat faded=WXGLocalPresentedAlpha(entry.button,WXGLocalBarOf(entry.anchor));alpha=faded<.01?-1:1;now=YES;
    }
    [self follow:entry shown:alpha immediately:now];
}
- (void)follow:(WXGLocalEntry *)entry shown:(CGFloat)alpha immediately:(BOOL)now {
    WXGSurface *surface=entry.surface;BOOL nothing=alpha<.01;
    BOOL homeTitle=entry.kind==WXGLocalTitle && _homeTitle && [entry.anchor isKindOfClass:_homeTitle];
    // A Home title glass is a child of the native title that actually draws
    // its text. Show and hide its material in the same commit as that text.
    if(homeTitle)now=YES;
    if(alpha<0){alpha=0;now=YES;}
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
    // FIX114 Y (user, 01:25: the home title capsule flickers as the list is
    // pulled down; diagnostics_18: WeChat hides and shows its title as the
    // pull goes, and the glass came back 2-4 frames after the text: hidden, it
    // had been switched off and was drawn again first): a title's glass goes
    // to 0 opacity instead, still drawn, and comes back in the same frame.
    if(entry.kind==WXGLocalTitle) {
        if(surface.hidden){surface.hidden=NO;entry.dirty=MAX(entry.dirty,12);}
        CGFloat target=nothing?0:WXGClamp(alpha,0,1);
        BOOL woke=surface.alpha<.05 && target>.05;
        if(fabs(surface.alpha-target)>.01)surface.alpha=target;
        if(woke && homeTitle && surface.active){[surface layoutIfNeeded];[surface tick:CACurrentMediaTime()];}
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
    }else if(entry.kind==WXGLocalTint) {   // FIX115 J: the fill WeChat last gave the button (cleared by us)
        UIView *anchor=entry.anchor;if(!anchor)return NO;
        UIColor *fill=[entry.states nativeColorOf:anchor];
        if(!force && entry.tintKnown && WXGLocalSameFill(fill,entry.lastFill,anchor.traitCollection))return NO;
        if(entry.tintKnown && !WXGLocalSameFill(fill,entry.lastFill,anchor.traitCollection))++_tintChanges;
        entry.lastFill=fill;entry.tintKnown=YES;
        UIColor *color=WXGLocalFillTint(fill,anchor.traitCollection);
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
    // FIX117 A: nothing drawn while the app is not active (the GPU refuses work from the background and the
    // drawable is left undefined: pink); the link rests, and becoming active draws everything again.
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){++_inactiveTicks;_link.paused=YES;_idleSince=0;return;}
    BOOL busy=NO,undrawn=NO,available=WXGLocalAvailable();NSUInteger revision=WXGConfigRevision();CFTimeInterval now=link.timestamp;
    for(WXGLocalEntry *entry in _entries.allObjects) {
        WXGSurface *surface=entry.surface;UIView *anchor=entry.anchor;
        if(!entry.mounted || !anchor || surface.superview!=anchor)continue;
        if(![self wants:entry.kind available:available]){[self unmount:entry];continue;}
        UIWindow *window=anchor.window;
        // FIX109: a glass hidden with what it is behind (an unselected group,
        // a hidden title) rests like one off screen.
        BOOL shown=window && !surface.hidden && WXGVisible(anchor,window);
        // FIX115 E / R25: keep title glasses warm while on screen (and keep
        // home MFTitleView pullTitle warm even slightly above window top so it
        // never cold-starts Metal on pull-down).
        if(!shown && entry.kind==WXGLocalTitle && window && !surface.hidden) {
            CGRect warmBounds=(_homeTitle && [anchor isKindOfClass:_homeTitle])?CGRectInset(window.bounds,0,-180):window.bounds;
            if(CGRectIntersectsRect(WXGWindowRect(anchor,window),warmBounds))shown=YES;
        }
        if(!shown){if(surface.active)surface.active=NO;continue;}
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
    if(_homeBackingInk) {
        UIView *wc=_homePlaceholder.host;
        UIView *header=WXGHomeNativeSearchHeader(WXGLocalHomeTableFor(wc).tableHeaderView);
        if(!_homePlaceholder.mounted || !header || !_homeBackingField.window || _homeBackingField.isFirstResponder ||
           _homeBackingField.text.length || ![_homeBackingField isDescendantOfView:header] ||
           !WXGLocalShownIn(wc,header) || WXGLocalOwner(header).navigationItem.searchController.isActive)
            [self releaseHomeBackingField];
        else [_homeBackingInk reapply];
    }
    ++_turn;   // FIX115 K: a new run-loop turn (the layout guard and the move budget count per turn)
    // FIX108 C: switched on after WeChat's views had laid out (the plugin's
    // licence or render mode settled after launch): look at every host again.
    BOOL available=WXGLocalAvailable();
    if(available!=_wasAvailable) {
        _wasAvailable=available;
        if(available)dispatch_async(dispatch_get_main_queue(),^{[self applyConfiguration];});
    }
    // FIX114 T: the hidden leftovers back as they were once off screen (or a page's again).
    if(_veiledLeftovers.count)for(NSArray *pair in _veiledLeftovers.copy) {
        UIView *old=[(NSPointerArray *)pair[0] allObjects].firstObject;
        if(!old){[_veiledLeftovers removeObject:pair];continue;}
        if(!old.window || WXGLocalNavOwner(old,NULL)){[(WXGStateBag *)pair[1] restore];[_veiledLeftovers removeObject:pair];}
    }
    BOOL idle=!_link || _link.paused,wake=NO;NSUInteger revision=WXGConfigRevision();
    NSMutableArray<UIView *> *again=nil;NSMutableSet<UINavigationBar *> *bars=nil;
    for(WXGLocalEntry *entry in _entries) {
        UIView *anchor=entry.anchor;
        if(!entry.mounted || entry.applying || !anchor.window)continue;
        if([self hostResting:entry.host]){[self unmount:entry];continue;}   // FIX115 L: stopped by the loop guard
        @try {
            // FIX114 C: the bars with a title-bar glass of ours: their content
            // moved down with the title row (the host does it on its pages;
            // this covers the ones it leaves: web pages, sheets).
            if(entry.kind==WXGLocalNavButton || entry.kind==WXGLocalTitle || entry.kind==WXGLocalTint) {   // FIX115 J: a coloured 完成 in the bar too
                UINavigationBar *bar=WXGLocalBarOf(anchor);
                if(bar){if(!bars)bars=[NSMutableSet set];[bars addObject:bar];}
                // FIX115 J: a coloured title-bar button the host has taken into its own glass since.
                if(bar && entry.kind==WXGLocalTint && ![WXGIntegrationHost.shared leavesNavigationControlNative:anchor]){[self unmount:entry];continue;}
            }
            // FIX109: views added to a search field's host after its layout (a
            // theme's picture of the field): looked at again after this pass.
            if(entry.kind==WXGLocalSearch && entry.host && WXGLocalSubviewShape(entry.host)!=entry.hostShape) {
                entry.hostShape=WXGLocalSubviewShape(entry.host);
                if(!again)again=[NSMutableArray array];[again addObject:entry.host];
            }
            // FIX108: a title-bar button the host has taken over since (its own
            // glass), a title view the host now draws itself (the chat page).
            if(entry.kind==WXGLocalNavButton && ![WXGIntegrationHost.shared leavesNavigationControlNative:entry.button]){if(![self keepThroughMove:entry])[self unmount:entry];continue;}
            // FIX114 S / T: a leaving page's button hidden whole.
            if(entry.kind==WXGLocalNavButton)[self veilNav:entry];
            // FIX114 L (user: with 其它页面顶部按钮也保持微信原生, coming back from
            // a chat left pieces of its top buttons' capsules on the page instead of
            // them going at once like the plugin's own buttons): a native button of a
            // page that is no longer the top one (popped, or pushed under: both pages'
            // items are in the bar during the transition) loses its capsule at once;
            // it comes back with its page on top again (a cancelled swipe).
            // FIX114 O (user: in a half swipe back the capsules went missing):
            // a departing page's capsule fades with WeChat's button (its opacity as
            // drawn), as the plugin's own buttons do, instead of going at once;
            // gone when the button is (L's leftovers came from glass not fading).
            if(entry.kind==WXGLocalNavButton && WXGLocalNavDeparting(entry.button)) {
                // (review) The capsule is inside the button: UIKit's fade of the
                // button reaches it already (its own alpha as well squared it);
                // it is only taken away once the button is gone.
                CGFloat faded=WXGLocalPresentedAlpha(entry.button,WXGLocalBarOf(anchor));
                [self follow:entry shown:faded<.01?-1:1 immediately:YES];++_departHides;
                if([entry.button isKindOfClass:UIButton.class]) {   // FIX114 P: its slot as well
                    CGFloat was=[entry.states contentShiftOf:anchor],to=WXGLocalKeptShift(entry,(UIButton *)entry.button);
                    if(fabs(was-to)>.01){[self noteShift:entry from:was to:to];[entry.states shiftContents:anchor x:to];}
                }
                if(faded>.01 && faded<.99)wake=YES;   // looked at every frame until it is gone
                continue;
            }
            if(entry.kind==WXGLocalTitle && ((!entry.paint && anchor.layer.mask) || !WXGLocalTitleAllowedForView(anchor) || (_homeTitle && [anchor isKindOfClass:_homeTitle] && [WXGChatSegments.shared titleModeWanted]))){[self unmount:entry];continue;}
            [entry.states reapply];
            if(entry.kind==WXGLocalTint)[self hideCoversOn:entry];   // FIX115 M: a press cover put on since
            WXGSurface *surface=entry.surface;
            // FIX108 E: each glass measured once per turn (rectangle, what is
            // drawn on it, how visible it is), not three times.
            CGRect material;UIColor *ink=nil;CGFloat shown=1;BOOL inkKnown=NO;
            if(entry.titleMeasure){material=WXGLocalPixelRect(entry.titleMeasure(&ink,&shown),anchor);inkKnown=YES;}
            else if(entry.kind==WXGLocalNavButton && [entry.button isKindOfClass:UIButton.class]) {
                UIButton *b=(UIButton *)entry.button;
                material=WXGLocalPixelRect(WXGLocalInsideBar(b,WXGLocalNavButtonFrame(b,WXGLocalNavLimit(b),&ink)),anchor);inkKnown=YES;
                shown=CGRectIsNull(material)?0:1;
            }else material=WXGLocalEntryMaterial(entry);
            if(!CGRectIsNull(material) && material.size.width>=1 && material.size.height>=1) {
                CGRect shown=surface.materialRect;CGPoint origin=surface.frame.origin;
                if(surface.superview!=anchor || fabs(shown.size.width-material.size.width)>.25 || fabs(shown.size.height-material.size.height)>.25 ||
                   fabs(origin.x+WXGCanvasPaddingX-material.origin.x)>.25 || fabs(origin.y+WXGCanvasPaddingY-material.origin.y)>.25) {
                    BOOL arriving=surface.superview!=anchor;
                    [surface placeMaterial:material inParent:anchor];
                    [self keepUnderContent:entry arriving:arriving];   // FIX115 K: within the turn's move budget
                    if(entry.kind==WXGLocalNavButton || entry.kind==WXGLocalTint)[self openClipsAbove:entry];   // FIX115 K: grown: its containers looked at again
                    entry.dirty=MAX(entry.dirty,12);++_remeasures;wake=YES;
                }
            }
            if(entry.kind==WXGLocalSearch)[self syncSearchAlignment:entry material:material force:NO];
            // FIX114 B: a native title-bar button drawn at the title row's margin.
            if(entry.kind==WXGLocalNavButton && [entry.button isKindOfClass:UIButton.class]) {
                CGFloat was=[entry.states contentShiftOf:anchor],to=WXGLocalKeptShift(entry,(UIButton *)entry.button);   // FIX114 T
                if(fabs(was-to)>.01)[self noteShift:entry from:was to:to];   // FIX114 M (diagnostics)
                [entry.states shiftContents:anchor x:to];
            }
            // FIX108: the title-bar kinds stay under WeChat's icons and labels (a
            // button can reorder its subviews); FIX107's kinds as before.
            if((entry.kind==WXGLocalTitle || entry.kind==WXGLocalNavButton || entry.kind==WXGLocalTint) && surface.superview==anchor && !entry.below && anchor.subviews.firstObject!=surface)
                [self keepUnderContent:entry arriving:NO];   // FIX115 K: within the turn's move budget
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
                   (entry.kind==WXGLocalTint && (!entry.tintKnown || !WXGLocalSameFill([entry.states nativeColorOf:anchor],entry.lastFill,anchor.traitCollection))) ||   // FIX115 J: 完成 turned green / grey
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
// FIX114 T: the title-bar buttons with a glass of ours on screen (the trace:
// also the old ones no page holds any more).
- (NSArray<UIView *> *)navButtonAnchors {
    NSMutableArray<UIView *> *out=[NSMutableArray array];
    for(WXGLocalEntry *entry in _entries.allObjects)if(entry.kind==WXGLocalNavButton && entry.mounted && entry.anchor.window && out.count<12)[out addObject:entry.anchor];
    return out;
}
- (void)releaseTransientResources {
    for(WXGLocalEntry *entry in _entries.allObjects)[entry.surface.glass releaseTransientResources];
}
- (void)restore {
    [self releaseHomeBackingField];
    for(WXGLocalEntry *entry in _entries.allObjects)[self unmount:entry];
    _link.paused=YES;
}
// FIX115 K (diagnostics): from a title-bar glass's view up to its bar: each
// container's class, size, whether it clips or has a mask (the next round can
// see what cut a glass).
static NSArray<NSString *> *WXGLocalClipChain(UIView *anchor) {
    UINavigationBar *bar=WXGLocalBarOf(anchor);if(!bar)return @[];
    NSMutableArray *out=[NSMutableArray array];NSUInteger depth=0;
    for(UIView *p=anchor;p && depth<10;p=p.superview,depth++) {
        [out addObject:[NSString stringWithFormat:@"%@ %.0fx%.0f%@%@",NSStringFromClass(p.class),p.bounds.size.width,p.bounds.size.height,
                        p.clipsToBounds?@" clips":@"",p.layer.mask?@" mask":@""]];
        if(p==bar)break;
    }
    return out;
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
            @"glassReady":@(entry.surface.glass.ready),@"firstFrame":@(entry.surface.glass.hasPresentedFrame),@"hidden":@(entry.surface.hidden),@"themeSkins":@(entry.skins),@"bandsCleared":entry.bands?:@[],
            @"openedClips":@(entry.openedClips),@"chain":WXGLocalClipChain(anchor)}];
    }
    WXGPreferences *p=WXGPreferences.shared;WXGConfig *cfg=WXGConfig.shared;
    return @{@"switches":@{@"search":@(p.localSearch),@"searchThemeFirst":@(p.localSearchThemeFirst),@"panel":@(p.localPanel),@"emoji":@(p.localEmoji),@"sheet":@(p.localSheet),@"title":@(p.localTitle),@"contactsTitle":@(cfg.contactsTitleCapsule),@"discoverTitle":@(cfg.discoverTitleCapsule),@"navButtons":@(p.localNavButtons),@"colorButtons":@([cfg extraNumber:@"localColorButtons"]>.5)},
             @"homeSystemFieldMasked":@(_homeBackingInk!=nil),@"renderMode":@(WXGEffectiveRenderMode()),@"mounted":counts,@"mounts":@(_mounts),@"unmounts":@(_unmounts),@"layouts":@(_layouts),
             @"remeasures":@(_remeasures),@"tintChanges":@(_tintChanges),@"orderFights":@(_orderFights),@"loopStops":@(_loopStops),@"pressCovers":_pressCovers?:@[],@"titleWatches":@(_titleWatches),@"titleWatchFollows":@(_titleWatchFollows),@"retries":@(_retries),@"wakes":@(_wakes),@"departHides":@(_departHides),@"lastCountPill":WXGLocalLastPill?:@{},
             @"transientKeeps":@(_transientKeeps),@"sideShiftChanges":_shiftLog?:@[],@"adoptions":@(_adoptions),@"poolReuses":@(_poolReuses),@"pooled":@(_navSurfacePool.count),@"transitionVeils":@(_veils),@"transitionReveals":@(_reveals),@"reclaimedGlass":@(_reclaimed),
             @"slotBuilds":@(WXGLocalSlotBuilds),@"nativeMargins":WXGLocalMargins?:@{},   // FIX114 O
             @"ticks":@(_ticks),@"foregroundRedraws":@(_foregroundRedraws),@"inactiveTicks":@(_inactiveTicks),@"linkRunning":@(_link && !_link.paused),@"skipped":_lastSkip.copy,@"onScreen":rows,@"homeSearchAlign":_lastSearchAlign?:@{},@"emojiSearchBand":_lastSearchBand?:@{},@"emojiQuickJump":_emojiQuickJump?:@{},@"emojiSearchCaptures":_emojiCaptures?:@[],
             @"classes":@{@"WCSearchBar":@(_wcSearchBar!=nil),@"WCWebSearchBar":@(_webSearchBar!=nil),@"FavSearchBar":@(_favSearchBar!=nil),
                          @"WCSearchTextField":@(_swiftField!=nil),@"AttachmentButton":@(_tile!=nil),@"EmoticonBoardView":@(_board!=nil),
                          @"QQEmojiPageCell":@(_qqPage!=nil),@"TabBarCell":@(_tabCell!=nil),@"ActionSheet":@(_sheet!=nil),
                          @"MFTitleView":@(_homeTitle!=nil),@"MMTitleView":@(_pageTitle!=nil),@"MMDropableTitleView":@(_dropTitle!=nil),@"MMBarButton":@(_barButton!=nil),@"NavBarContent":@(_navContent!=nil),
                          @"NewContactsSearchPanelView":@(_contactSearch!=nil),@"FixTitleColorButton":@(_colorButton!=nil)}};
}
@end
// FIX114 V
CGRect WXGNativeNavGlassRect(UIView *button) {
    return [button isKindOfClass:UIButton.class]?WXGLocalNavButtonFrame((UIButton *)button,CGFLOAT_MAX,NULL):CGRectNull;
}
BOOL WXGNativeNavButtonFilled(UIView *button) {
    // FIX115 J: one whose fill our tinted glass has taken (or will) still paints its own.
    return WXGLocalOwnPaint(button);
}
