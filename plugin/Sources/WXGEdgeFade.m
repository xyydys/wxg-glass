#import "WXGSettingsKit.h"
#import "WXGEdgeFadeMath.h"
#import <objc/runtime.h>
#import <objc/message.h>

/* FIX64: 页面渐隐 + 模糊.
   - Fade: the author's WeChatFade 1.1, as it was: the page's main list
     (resolved the same way: its table ivars / properties, then the largest
     wide list on the page, scored by size, class and name) gets a
     CAGradientLayer as its layer mask, 129 stops of smoothstep alpha
     (WXGEdgeFadeMath.h), the mask moved to the list's bounds origin whenever
     the list scrolls or lays out (setBounds: / layoutSubviews of the list's
     class, as WeChatFade hooked MMTableView), the list's own mask restored
     when the fade goes away.
   - Blur: the shared edge-effect project's variable blur: a CABackdropLayer
     at half resolution with CAFilter "variableBlur", its mask image the
     Telegram EdgeEffect table (strongest at the screen edge, none at the band's
     inner end). One band at the list's top, one at its bottom, placed just
     above the list in the list's superview (below the input bar, the
     navigation bar and the dock), following the list's frame. The backdrop is
     the band view's own layer, so the band moves and resizes with the list in
     WeChat's own animations (keyboard).
   - Pages: 聊天页 (BaseMsgContentViewController) and 其余页面 (home, contacts,
     Moments, chat settings: single and group), each with its own top / bottom
     fade, top / bottom blur and blur strength (WXGConfig edge* keys). No
     display link: the controllers' appearance and layout (the host's hooks)
     and the list's own geometry changes drive everything.
   FIX65: a strength for each edge (0-8); 其余页面 also WeChat's settings page
   (NewSettingViewController) and our own settings pages (WXGSettingsPage).
   Our pages keep their list unmasked (the glass cards in it are backdrops,
   which a mask above them breaks): a copy of the page's wallpaper, masked to
   the inverse of the fade, lies over the list instead, under the bands.
   FIX66: the mask fades the list's own background colour with its content
   (the chat list without a wallpaper and WeChat's settings list paint the
   page grey themselves, nothing opaque behind them: the edges went black).
   A plate of the list's background colour under the list keeps it.
   FIX69: Moments still went black: its list paints nothing itself (no
   background colour) and nothing opaque is behind it. The plate's colour is
   now the list's own paint (its colour, else its table / collection
   background view's); without one, when nothing opaque is behind the list
   (an ancestor's background or a sibling below covering it: a wallpaper),
   the system background (white / black).
   FIX70: Moments' list does paint (#111111), but only its overscroll shows
   that: its full-width cells (white) are the page. When the visible cells'
   paint is far from the list's own (luminance apart by more than 0.35) the
   plate takes the cells' paint.
   FIX67: the home list's pull-down mini-program panel (part of the list) gets
   no fade and no blur: as it opens (WXGHomePanelProgressForController) a solid
   layer inside the mask covers the gradient and the bands' blur goes to 0. */

typedef NS_ENUM(NSInteger,WXGEdgeScope) {WXGEdgeScopeNone=-1,WXGEdgeScopeChat=0,WXGEdgeScopeOther=1};
typedef struct {CGFloat fadeTop,fadeBottom,blurTop,blurBottom,blurTopRadius,blurBottomRadius;} WXGEdgeValues;

static WXGEdgeValues WXGEdgeValuesForScope(WXGEdgeScope scope) {
    WXGConfig *c=WXGConfig.shared;
    if(scope==WXGEdgeScopeChat)
        return (WXGEdgeValues){c.edgeChatFadeTop,c.edgeChatFadeBottom,c.edgeChatBlurTop,c.edgeChatBlurBottom,c.edgeChatBlurTopRadius,c.edgeChatBlurBottomRadius};
    return (WXGEdgeValues){c.edgeOtherFadeTop,c.edgeOtherFadeBottom,c.edgeOtherBlurTop,c.edgeOtherBlurBottom,c.edgeOtherBlurTopRadius,c.edgeOtherBlurBottomRadius};
}
static BOOL WXGEdgeFadeWanted(void) {return WXGPluginEnabled() && WXGPreferences.shared.edgeFade;}

static WXGEdgeScope WXGEdgeScopeForController(UIViewController *controller) {
    static Class chat[2],other[6];static dispatch_once_t once;
    dispatch_once(&once,^{
        chat[0]=NSClassFromString(@"BaseMsgContentViewController");chat[1]=NSClassFromString(@"MMMsgContentViewController");
        NSArray<NSString *> *names=@[@"NewMainFrameViewController",@"ContactsViewController",@"WCTimeLineViewController",
                                     @"AddContactToChatRoomViewController",@"ChatRoomInfoViewController",@"NewSettingViewController"];
        for(NSUInteger i=0;i<names.count;i++)other[i]=NSClassFromString(names[i]);
    });
    if(!controller)return WXGEdgeScopeNone;
    for(NSUInteger i=0;i<2;i++)if(chat[i] && [controller isKindOfClass:chat[i]])return WXGEdgeScopeChat;
    for(NSUInteger i=0;i<6;i++)if(other[i] && [controller isKindOfClass:other[i]])return WXGEdgeScopeOther;
    if([controller isKindOfClass:WXGSettingsPage.class])return WXGEdgeScopeOther;   // our own settings pages
    return WXGEdgeScopeNone;
}

#pragma mark - Blur band

static Class WXGEdgeBackdropClass(void) {
    static Class cls;static dispatch_once_t once;
    dispatch_once(&once,^{cls=NSClassFromString(@"CABackdropLayer");});
    return cls;
}
static id WXGEdgeFilter(NSString *name) {
    Class filterClass=NSClassFromString(@"CAFilter");SEL selector=NSSelectorFromString(@"filterWithName:");
    if(!filterClass || ![filterClass respondsToSelector:selector])return nil;
    return ((id (*)(id,SEL,NSString *))objc_msgSend)(filterClass,selector,name);
}
static BOOL WXGEdgeVariableBlurAvailable(void) {
    static BOOL available;static dispatch_once_t once;
    dispatch_once(&once,^{available=WXGEdgeBackdropClass() && WXGEdgeFilter(@"variableBlur")!=nil;});
    return available;
}
/* The variable blur's mask, stretched over the band: black, alpha = the
   blur strength, row 0 at the band's top. 4 x 256 px, one per edge. */
static CGImageRef WXGEdgeBlurMaskImage(BOOL bottomEdge) {
    static CGImageRef images[2];
    CGImageRef *slot=&images[bottomEdge?1:0];
    if(*slot)return *slot;
    const size_t w=4,h=256;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,w,h,8,w*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if(!context)return NULL;
    uint8_t *bytes=CGBitmapContextGetData(context);size_t stride=CGBitmapContextGetBytesPerRow(context);
    for(size_t row=0;row<h;row++) {
        float u=((bottomEdge?(float)(h-1-row):(float)row)+.5f)/(float)h;
        uint8_t alpha=(uint8_t)lroundf(255.f*WXGEdgeBlurStrength(u));
        for(size_t x=0;x<w;x++) {
            uint8_t *p=bytes+row*stride+x*4;
            p[0]=p[1]=p[2]=0;p[3]=alpha;
        }
    }
    *slot=CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return *slot;
}

@interface WXGEdgeBlurView : UIView
@property(nonatomic,readonly) BOOL bottomEdge;
@property(nonatomic,readonly) CGFloat blurRadius;
@property(nonatomic,readonly) BOOL variable;
- (instancetype)initWithBottomEdge:(BOOL)bottomEdge;
- (void)setBlurRadius:(CGFloat)radius;
@end
@implementation WXGEdgeBlurView {
    CAGradientLayer *_fallbackMask;
}
/* The band's own layer is the backdrop (as UIKit's own blur views do), so
   frame changes inside WeChat's animations carry it along. */
+ (Class)layerClass {return WXGEdgeBackdropClass()?:CALayer.class;}
- (instancetype)initWithBottomEdge:(BOOL)bottomEdge {
    if((self=[super initWithFrame:CGRectZero])) {
        _bottomEdge=bottomEdge;_blurRadius=-1;
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;
        self.layer.name=bottomEdge?@"WXGEdgeBlur.bottom":@"WXGEdgeBlur.top";
        CALayer *layer=self.layer;
        if([layer isKindOfClass:WXGEdgeBackdropClass()]) {
            // Blur is low-frequency: half-resolution capture (the shared project's Tier-2 setting).
            if([layer respondsToSelector:NSSelectorFromString(@"setScale:")])[layer setValue:@.5 forKey:@"scale"];
        }
        _variable=WXGEdgeVariableBlurAvailable();
    }
    return self;
}
- (void)setBlurRadius:(CGFloat)radius {
    if(fabs(radius-_blurRadius)<.05)return;
    _blurRadius=radius;
    CALayer *layer=self.layer;
    if(![layer isKindOfClass:WXGEdgeBackdropClass()])return;
    id filter=nil;
    if(_variable) {
        filter=WXGEdgeFilter(@"variableBlur");
        CGImageRef mask=WXGEdgeBlurMaskImage(_bottomEdge);
        if(filter && mask) {
            [filter setValue:@(radius) forKey:@"inputRadius"];
            [filter setValue:(__bridge id)mask forKey:@"inputMaskImage"];
            [filter setValue:@YES forKey:@"inputNormalizeEdges"];
        }else filter=nil;
    }
    if(!filter) {
        // No variable blur: a plain blur faded by the same table.
        filter=WXGEdgeFilter(@"gaussianBlur");
        [filter setValue:@(radius) forKey:@"inputRadius"];
        if(!_fallbackMask) {
            _fallbackMask=[CAGradientLayer layer];
            NSMutableArray *colors=[NSMutableArray array],*locations=[NSMutableArray array];
            for(NSUInteger i=0;i<=32;i++) {
                float t=i/32.f,u=_bottomEdge?1.f-t:t;
                [colors addObject:(__bridge id)[UIColor colorWithWhite:0 alpha:WXGEdgeBlurStrength(u)].CGColor];
                [locations addObject:@(t)];
            }
            _fallbackMask.colors=colors;_fallbackMask.locations=locations;
            _fallbackMask.startPoint=CGPointMake(.5,0);_fallbackMask.endPoint=CGPointMake(.5,1);
            layer.mask=_fallbackMask;[self setNeedsLayout];
        }
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    layer.filters=filter?@[filter]:nil;
    [CATransaction commit];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(_fallbackMask && !CGRectEqualToRect(_fallbackMask.frame,self.bounds)) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        _fallbackMask.frame=self.bounds;
        [CATransaction commit];
    }
}
@end

#pragma mark - Page

/* Our settings pages' wallpaper copy, and the list background plate (their
   own classes: the host's scans skip them). */
@interface WXGEdgeCoverView : UIImageView
@end
@implementation WXGEdgeCoverView
@end
@interface WXGEdgePlateView : UIView
@end
@implementation WXGEdgePlateView
@end
/* FIX106 I (user: 聊天设置 always opened with its first rows under the title
   bar). FIX106 I's own log on 聊天信息 (single and group): WeChat's list there
   is never adjusted by UIKit (contentInsetAdjustmentBehavior never) and its
   own top inset was 0, while it was the page's SECOND subview, the plate in
   front of it. WeChat gives a page's list its top inset only while the list
   is the page's first subview (as UIKit's old automatic insets did); 设置 sets
   its own and was not affected. Where the list leads its parent the plate now
   goes after it in the subviews, drawn below it by a lower zPosition: the
   list stays first, the plate stays a view (the glass sampler keeps skipping
   it and keeps splitting the page, whose sublayers stay all views). */
static BOOL WXGEdgeListLeads(UIScrollView *list) {
    for(UIView *v in list.superview.subviews) {
        if(v==list)return YES;
        if(!WXGIsPluginView(v))return NO;   // our own views aside (an older plate below it)
    }
    return NO;
}

@interface WXGEdgePage : NSObject
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIScrollView *scrollView;
@property(nonatomic) WXGEdgeScope scope;
@property(nonatomic,strong) CAGradientLayer *mask;
@property(nonatomic,strong) CALayer *maskSolid;          // FIX67: opacity = the panel's progress
@property(nonatomic) BOOL homePanel;                      // the home page: its list holds the mini-program panel
@property(nonatomic) BOOL topBarInList;                   // FIX94: WeChat's title bar buttons are in the list (pulled down)
@property(nonatomic,strong) CALayer *maskTopSolid;        // FIX94: over the top fade only, opacity 1 while they are
@property(nonatomic) CGFloat panel,topRadius,bottomRadius;
@property(nonatomic,strong) CALayer *originalMask;
@property(nonatomic,strong) WXGEdgeBlurView *topBlur,*bottomBlur;
@property(nonatomic,weak) UIImageView *coverSource;      // our settings pages: their wallpaper
@property(nonatomic,strong) UIImageView *cover;
@property(nonatomic,strong) UIView *plate;               // the list's background colour, under the list
@property(nonatomic,strong) UIColor *plateFallback;      // FIX69: nothing opaque behind a see-through list
@property(nonatomic,copy) NSString *plateSource;
@property(nonatomic,strong) CAGradientLayer *coverMask;
@property(nonatomic) CGSize maskSize,appliedSize,coverSize;
@property(nonatomic) CGFloat maskTop,maskBottom,blurTopExtent,blurBottomExtent,fadeTop,fadeBottom;
@property(nonatomic) CGFloat coverListY,coverListHeight,coverTop,coverBottom;
@property(nonatomic) CGRect syncedBounds;
@property(nonatomic) CFTimeInterval lastResolve;
@property(nonatomic) NSUInteger resolves,attaches,maskBuilds,maskSyncs;
@property(nonatomic,copy) NSString *blurNote;
- (void)refresh:(BOOL)force;
- (void)syncGeometry;
- (void)detach;
@end

static NSHashTable<WXGEdgePage *> *WXGEdgePages;
static char WXGEdgePageKey;
/* FIX84: which page a list belongs to, kept on the list itself (an associated
   link holding the page weakly). Until FIX83 this was a table of 16 list
   pointers: a page that went away with its list (every closed chat, every
   closed settings page) left its pointer behind, because the page's weak
   list was already nil when it was freed. After a dozen chats the table was
   full and every new list took slot 0, the first list registered: the home
   page's. The home list's scrolling then no longer reached its page, so the
   mask (in the list's scrolling coordinates) stayed where it was and scrolled
   away with the content, hiding the messages below it. The link has no limit,
   dies with the list, and a page that is gone reads as nil. */
@interface WXGEdgeListLink : NSObject
@property(nonatomic,weak) WXGEdgePage *page;
@end
@implementation WXGEdgeListLink
@end
static char WXGEdgeListLinkKey;
static NSUInteger WXGEdgeRelinks;   // pages found unlinked from their list and linked again
static void WXGEdgeListRegister(UIScrollView *list,WXGEdgePage *page) {
    if(!list)return;
    WXGEdgeListLink *link=objc_getAssociatedObject(list,&WXGEdgeListLinkKey);
    if(page) {
        if(link.page==page)return;
        if(!link){link=[WXGEdgeListLink new];objc_setAssociatedObject(list,&WXGEdgeListLinkKey,link,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        link.page=page;
    }else if(link)objc_setAssociatedObject(list,&WXGEdgeListLinkKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void WXGEdgeListUnregister(UIScrollView *list,WXGEdgePage *page) {
    if(!list)return;
    WXGEdgeListLink *link=objc_getAssociatedObject(list,&WXGEdgeListLinkKey);
    if(link && (!link.page || link.page==page))WXGEdgeListRegister(list,nil);
}
static WXGEdgePage *WXGEdgePageForList(UIScrollView *list) {
    WXGEdgeListLink *link=objc_getAssociatedObject(list,&WXGEdgeListLinkKey);
    WXGEdgePage *page=link.page;
    return page.scrollView==list?page:nil;
}

#pragma mark List hooks

static BOOL WXGEdgeClassOwns(Class cls,SEL selector) {
    unsigned int count=0;Method *methods=class_copyMethodList(cls,&count);BOOL owns=NO;
    for(unsigned int i=0;i<count && !owns;i++)owns=method_getName(methods[i])==selector;
    free(methods);
    return owns;
}
static void WXGEdgeListChanged(UIScrollView *list) {
    if(WXGBackdropCaptureInProgress())return;
    WXGEdgePage *page=WXGEdgePageForList(list);
    if(page)WXGPerfTimePluginWorkAs("edgeFade",^{[page syncGeometry];});   // FIX84: counted in the frame-rate log
}
/* The list's class (once): its setBounds: / setFrame: / setCenter: /
   layoutSubviews run as before, then the page follows. A method the class
   inherits is added, calling the superclass's current implementation. */
static void WXGEdgeHookListClass(Class cls) {
    static NSMutableSet *hooked;
    if(!cls)return;
    if(!hooked)hooked=[NSMutableSet set];
    if([hooked containsObject:cls])return;
    [hooked addObject:cls];
    Class superclass=class_getSuperclass(cls);
    for(NSString *name in @[@"setBounds:",@"setFrame:"]) {
        SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(cls,selector);if(!method)continue;
        BOOL owns=WXGEdgeClassOwns(cls,selector);IMP original=owns?method_getImplementation(method):NULL;
        IMP replacement=imp_implementationWithBlock(^(UIScrollView *list,CGRect rect){
            IMP imp=original?:class_getMethodImplementation(superclass,selector);
            ((void (*)(id,SEL,CGRect))imp)(list,selector,rect);
            WXGEdgeListChanged(list);
        });
        if(owns)method_setImplementation(method,replacement);
        else class_addMethod(cls,selector,replacement,method_getTypeEncoding(method));
    }
    {
        SEL selector=@selector(setCenter:);Method method=class_getInstanceMethod(cls,selector);
        if(method) {
            BOOL owns=WXGEdgeClassOwns(cls,selector);IMP original=owns?method_getImplementation(method):NULL;
            IMP replacement=imp_implementationWithBlock(^(UIScrollView *list,CGPoint point){
                IMP imp=original?:class_getMethodImplementation(superclass,selector);
                ((void (*)(id,SEL,CGPoint))imp)(list,selector,point);
                WXGEdgeListChanged(list);
            });
            if(owns)method_setImplementation(method,replacement);
            else class_addMethod(cls,selector,replacement,method_getTypeEncoding(method));
        }
    }
    {
        SEL selector=@selector(layoutSubviews);Method method=class_getInstanceMethod(cls,selector);
        if(method) {
            BOOL owns=WXGEdgeClassOwns(cls,selector);IMP original=owns?method_getImplementation(method):NULL;
            IMP replacement=imp_implementationWithBlock(^(UIScrollView *list){
                IMP imp=original?:class_getMethodImplementation(superclass,selector);
                ((void (*)(id,SEL))imp)(list,selector);
                WXGEdgeListChanged(list);
            });
            if(owns)method_setImplementation(method,replacement);
            else class_addMethod(cls,selector,replacement,method_getTypeEncoding(method));
        }
    }
}

#pragma mark List resolver (WeChatFade 1.1)

static NSString *WXGEdgeLowerClassName(Class cls) {
    static NSMutableDictionary<NSValue *,NSString *> *names;
    if(!names)names=[NSMutableDictionary dictionary];
    NSValue *key=[NSValue valueWithPointer:(__bridge const void *)cls];
    NSString *name=names[key];
    if(!name){name=NSStringFromClass(cls).lowercaseString?:@"";names[key]=name;}
    return name;
}
static CGFloat WXGEdgeListScore(UIScrollView *list,UIView *root,BOOL chat) {
    if(!list || !root || [list isKindOfClass:UITextView.class] || list.hidden || list.alpha<.01)return -CGFLOAT_MAX;
    CGRect rect=[list convertRect:list.bounds toView:root];
    if(rect.size.width<root.bounds.size.width*.55 || rect.size.height<220)return -CGFLOAT_MAX;
    CGFloat rootArea=MAX(root.bounds.size.width*root.bounds.size.height,1);
    CGFloat score=rect.size.width*rect.size.height/rootArea*100;
    if([list isKindOfClass:UITableView.class])score+=90;
    if([list isKindOfClass:UICollectionView.class])score+=75;
    if(list.contentSize.height>list.bounds.size.height+20)score+=20;
    if(fabs(rect.size.width-root.bounds.size.width)<20)score+=20;
    NSString *name=WXGEdgeLowerClassName(list.class);
    if([name containsString:@"table"])score+=25;
    if([name containsString:@"list"])score+=15;
    if(chat) {
        if([name isEqualToString:@"mmtableview"])score+=180;
        if([name containsString:@"message"] || [name containsString:@"msg"] || [name containsString:@"chat"])score+=55;
    }else if([name containsString:@"main"] || [name containsString:@"session"] || [name containsString:@"conversation"])score+=35;
    return score;
}
static void WXGEdgeCollectLists(UIView *view,NSMutableArray<UIScrollView *> *out,NSUInteger depth) {
    if(!view || depth>14 || WXGIsPluginView(view))return;
    if([view isKindOfClass:UIScrollView.class] && ![view isKindOfClass:UITextView.class])[out addObject:(UIScrollView *)view];
    // Cells hold no page list (and are most of a long list's views).
    if([view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class])return;
    for(UIView *child in view.subviews)WXGEdgeCollectLists(child,out,depth+1);
}
static BOOL WXGEdgeHasKey(id object,NSString *key) {
    if([object respondsToSelector:NSSelectorFromString(key)])return YES;
    for(Class c=object_getClass(object);c;c=class_getSuperclass(c))
        if(class_getInstanceVariable(c,key.UTF8String) || class_getInstanceVariable(c,[@"_" stringByAppendingString:key].UTF8String))return YES;
    return NO;
}
static UIScrollView *WXGEdgeResolveList(UIViewController *controller,BOOL chat) {
    if(!controller.isViewLoaded)return nil;
    UIView *root=controller.view;
    NSArray<NSString *> *keys=chat?@[@"m_tableView",@"tableView",@"messageTableView",@"m_oTableView",@"listView",@"scrollView"]
                                  :@[@"m_tableView",@"tableView",@"sessionTableView",@"conversationTableView",@"listView",@"scrollView"];
    UIScrollView *best=nil;CGFloat bestScore=-CGFLOAT_MAX;
    for(NSString *key in keys) {
        if(!WXGEdgeHasKey(controller,key))continue;
        id value=WXGRead(controller,key);
        if(![value isKindOfClass:UIScrollView.class] || ![(UIView *)value isDescendantOfView:root])continue;
        CGFloat score=WXGEdgeListScore(value,root,chat)+100;
        if(score>bestScore){best=value;bestScore=score;}
    }
    NSMutableArray<UIScrollView *> *lists=[NSMutableArray array];
    WXGEdgeCollectLists(root,lists,0);
    for(UIScrollView *list in lists) {
        CGFloat score=WXGEdgeListScore(list,root,chat);
        if(score>bestScore){best=list;bestScore=score;}
    }
    return bestScore>-CGFLOAT_MAX?best:nil;
}

#pragma mark Background behind the list

/* FIX69: what the list's content sits on: its own background colour, else its
   background view's (table / collection); nil when the list is see-through. */
static UIColor *WXGEdgeListPaint(UIScrollView *list,NSString **source) {
    UIColor *color=list.backgroundColor;
    if(color && CGColorGetAlpha(color.CGColor)>.01){if(source)*source=@"list";return color;}
    UIView *backing=[list isKindOfClass:UITableView.class]?((UITableView *)list).backgroundView:
                    [list isKindOfClass:UICollectionView.class]?((UICollectionView *)list).backgroundView:nil;
    color=backing && !backing.hidden?backing.backgroundColor:nil;
    if(color && CGColorGetAlpha(color.CGColor)>.01){if(source)*source=@"backgroundView";return color;}
    return nil;
}
/* FIX70: the paint of the list's visible full-width cells (their colour, their
   content view's or their background view's), nil when they paint nothing. */
static UIColor *WXGEdgeCellPaint(UIScrollView *list) {
    NSArray<UIView *> *cells=nil;
    if([list isKindOfClass:UITableView.class])cells=((UITableView *)list).visibleCells;
    else if([list isKindOfClass:UICollectionView.class])cells=((UICollectionView *)list).visibleCells;
    CGFloat width=list.bounds.size.width;
    for(UIView *cell in cells) {
        if(cell.hidden || cell.bounds.size.width<width*.9)continue;
        UIView *content=[cell isKindOfClass:UITableViewCell.class]?((UITableViewCell *)cell).contentView:
                        [cell isKindOfClass:UICollectionViewCell.class]?((UICollectionViewCell *)cell).contentView:nil;
        UIView *backing=[cell isKindOfClass:UITableViewCell.class]?((UITableViewCell *)cell).backgroundView:
                        [cell isKindOfClass:UICollectionViewCell.class]?((UICollectionViewCell *)cell).backgroundView:nil;
        for(UIColor *color in @[cell.backgroundColor?:UIColor.clearColor,content.backgroundColor?:UIColor.clearColor,backing.backgroundColor?:UIColor.clearColor])
            if(CGColorGetAlpha(color.CGColor)>.99)return color;
    }
    return nil;
}
static CGFloat WXGEdgeLuminance(UIColor *color,UITraitCollection *traits) {
    CGFloat r=0,g=0,b=0,a=0;
    if(![[color resolvedColorWithTraitCollection:traits] getRed:&r green:&g blue:&b alpha:&a])return -1;
    return .299*r+.587*g+.114*b;
}
/* Something opaque already behind a see-through list, up to the page: an
   ancestor with an opaque background, or a sibling below the list (at any
   level) covering it with an opaque colour or an image (a chat wallpaper). */
static BOOL WXGEdgeBackdropBehind(UIScrollView *list,UIView *page) {
    UIView *child=list;
    for(UIView *v=list.superview;v;child=v,v=v.superview) {
        CGRect listRect=[v convertRect:list.bounds fromView:list];
        for(UIView *s in v.subviews) {
            if(s==child)break;
            if(s.hidden || s.alpha<.99 || WXGIsPluginView(s))continue;
            CGRect r=[v convertRect:s.bounds fromView:s];
            if(!CGRectContainsRect(CGRectInset(r,-1,-1),listRect))continue;
            BOOL opaque=s.backgroundColor && CGColorGetAlpha(s.backgroundColor.CGColor)>.99;
            BOOL image=[s isKindOfClass:UIImageView.class] && ((UIImageView *)s).image;
            if(opaque || image)return YES;
        }
        if(v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor)>.99)return YES;
        if(v==page)break;
    }
    return NO;
}

#pragma mark Page

@implementation WXGEdgePage
- (instancetype)init {
    if((self=[super init])) {
        _maskSize=_appliedSize=_coverSize=CGSizeMake(-1,-1);_maskTop=_maskBottom=-1;_syncedBounds=CGRectNull;
        _coverListY=_coverListHeight=_coverTop=_coverBottom=-1;
    }
    return self;
}
- (void)dealloc {
    UIScrollView *list=_scrollView;
    if(list && _mask && list.layer.mask==_mask)list.layer.mask=_originalMask;
    if(list)WXGEdgeListUnregister(list,nil);   // this page is already nil in the link
    [_plate removeFromSuperview];[_cover removeFromSuperview];[_topBlur removeFromSuperview];[_bottomBlur removeFromSuperview];
}
- (void)detachList {
    UIScrollView *list=_scrollView;
    if(list) {
        if(_mask && list.layer.mask==_mask) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            list.layer.mask=_originalMask;
            [CATransaction commit];
        }
        WXGEdgeListUnregister(list,self);
    }
    [_plate removeFromSuperview];[_cover removeFromSuperview];[_topBlur removeFromSuperview];[_bottomBlur removeFromSuperview];
    _plate=nil;_plateFallback=nil;_cover=nil;_topBlur=_bottomBlur=nil;
    _scrollView=nil;_mask=nil;_maskSolid=nil;_maskTopSolid=nil;_originalMask=nil;_panel=0;_topBarInList=NO;
    _maskSize=_appliedSize=_coverSize=CGSizeMake(-1,-1);_maskTop=_maskBottom=-1;_syncedBounds=CGRectNull;
    _coverListY=_coverListHeight=_coverTop=_coverBottom=-1;
    _fadeTop=_fadeBottom=_blurTopExtent=_blurBottomExtent=0;
}
- (void)detach {[self detachList];}
- (void)attach:(UIScrollView *)list {
    [self detachList];
    if(!list)return;
    _scrollView=list;++_attaches;
    WXGEdgeListRegister(list,self);
    WXGEdgeHookListClass(list.class);
}
- (void)refresh:(BOOL)force {
    UIViewController *controller=_controller;
    if(!controller.isViewLoaded || !WXGEdgeFadeWanted()){[self detachList];return;}
    UIScrollView *list=_scrollView;UIView *root=controller.view;
    BOOL stale=!list || ![list isDescendantOfView:root] || list.hidden || (root.window && !list.window);
    CFTimeInterval now=CACurrentMediaTime();
    // Appearing, a lost list, or (while laying out) at most once a second:
    // WeChat builds some lists late.
    if(force || stale || now-_lastResolve>1.0) {
        _lastResolve=now;++_resolves;
        UIScrollView *found=nil;UIImageView *wallpaper=nil;
        if([controller isKindOfClass:WXGSettingsPage.class]) {
            // Our own settings pages: their list and wallpaper are known.
            WXGSettingsPage *settings=(WXGSettingsPage *)controller;
            found=settings.scrollView;wallpaper=settings.wallpaperView;
        }else found=WXGEdgeResolveList(controller,_scope==WXGEdgeScopeChat);
        if(found!=list){[self attach:found];list=found;}
        _coverSource=wallpaper;
    }
    if(!list)return;
    // FIX84: the list must lead back to this page, or its scrolling would not
    // move the mask (it never should be unlinked now; counted if it is).
    if(WXGEdgePageForList(list)!=self) {
        WXGEdgeListRegister(list,self);++WXGEdgeRelinks;
        if(WXGEdgeRelinks<=8)WXGLog(@"渐隐：%@ 的列表重新关联",NSStringFromClass(controller.class));
    }
    [self applyValues:force];
}
/* `view` just above `anchor` in `parent` (placed again only when it is not
   above it), its frame set without animating from an old one, even inside a
   transition's layout pass. */
- (void)place:(UIView *)view above:(UIView *)anchor parent:(UIView *)parent frame:(CGRect)frame {
    NSArray<UIView *> *siblings=parent.subviews;
    NSUInteger anchorIndex=[siblings indexOfObjectIdenticalTo:anchor],index=[siblings indexOfObjectIdenticalTo:view];
    if(view.superview==parent && anchorIndex!=NSNotFound && index!=NSNotFound && index>anchorIndex)return;
    [UIView performWithoutAnimation:^{
        [parent insertSubview:view aboveSubview:anchor];
        view.frame=frame;
    }];
}
/* `view` just below `list` (placed again only when it is not below it). */
- (void)place:(UIView *)view below:(UIView *)list parent:(UIView *)parent frame:(CGRect)frame {
    NSArray<UIView *> *siblings=parent.subviews;
    NSUInteger listIndex=[siblings indexOfObjectIdenticalTo:list],index=[siblings indexOfObjectIdenticalTo:view];
    if(view.superview==parent && listIndex!=NSNotFound && index!=NSNotFound && index<listIndex)return;
    [UIView performWithoutAnimation:^{
        if(view.layer.zPosition!=0)view.layer.zPosition=0;
        [parent insertSubview:view belowSubview:list];
        view.frame=frame;
    }];
}
/* FIX106 I: `view` drawn below `list` while after it in the subviews (a lower
   zPosition), so the list stays its parent's first subview. Placed again only
   when it is not after it or not lower. */
- (void)place:(UIView *)view behind:(UIView *)list parent:(UIView *)parent frame:(CGRect)frame {
    NSArray<UIView *> *siblings=parent.subviews;
    NSUInteger listIndex=[siblings indexOfObjectIdenticalTo:list],index=[siblings indexOfObjectIdenticalTo:view];
    if(view.superview==parent && listIndex!=NSNotFound && index!=NSNotFound && index>listIndex &&
       view.layer.zPosition<list.layer.zPosition)return;
    [UIView performWithoutAnimation:^{
        view.layer.zPosition=list.layer.zPosition-1;
        [parent insertSubview:view aboveSubview:list];
        view.frame=frame;
    }];
}
- (CGRect)listRect {
    UIScrollView *list=_scrollView;UIView *parent=list.superview;
    return parent?[parent convertRect:list.bounds fromView:list]:CGRectZero;
}
- (void)applyValues:(BOOL)force {
    UIScrollView *list=_scrollView;if(!list)return;
    CGSize size=list.bounds.size;
    if(size.width<1 || size.height<1)return;
    _appliedSize=size;
    WXGEdgeValues v=WXGEdgeValuesForScope(_scope);
    CGFloat top=WXGEdgeBand(v.fadeTop,size.height),bottom=WXGEdgeBand(v.fadeBottom,size.height);
    _fadeTop=top;_fadeBottom=bottom;
    UIView *parent=list.superview;UIImageView *source=_coverSource;
    BOOL fading=top>0 || bottom>0;
    // WeChat's pages: the list's own mask (WeChatFade).
    CALayer *current=list.layer.mask;
    if(source || !fading) {
        if(_mask && current==_mask) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            list.layer.mask=_originalMask;
            [CATransaction commit];
        }
    }else {
        if(!_mask) {
            _mask=[CAGradientLayer layer];_mask.name=@"WXGEdgeFadeMask";
            _mask.anchorPoint=CGPointZero;_mask.startPoint=CGPointMake(.5,0);_mask.endPoint=CGPointMake(.5,1);
            _mask.contentsScale=UIScreen.mainScreen.scale;
            _maskSolid=[CALayer layer];_maskSolid.backgroundColor=UIColor.whiteColor.CGColor;
            _maskSolid.anchorPoint=CGPointZero;_maskSolid.opacity=0;
            [_mask addSublayer:_maskSolid];
            _maskTopSolid=[CALayer layer];_maskTopSolid.backgroundColor=UIColor.whiteColor.CGColor;
            _maskTopSolid.anchorPoint=CGPointZero;_maskTopSolid.opacity=0;
            [_mask addSublayer:_maskTopSolid];
        }
        if(current!=_mask) {
            // The list's own mask (WeChat's, if any) comes back with the fade off.
            if(current)_originalMask=current;
            [CATransaction begin];[CATransaction setDisableActions:YES];
            list.layer.mask=_mask;
            [CATransaction commit];
            _syncedBounds=CGRectNull;
        }
        [self buildMaskForSize:size top:top bottom:bottom force:force];
    }
    // The mask fades the list's own background colour too; behind the list
    // there may be nothing opaque (the chat without a wallpaper, WeChat's
    // settings: black edges). A plate of that colour under the list keeps the
    // background and hides only the content.
    // FIX69: the list's own paint, else (nothing opaque behind it) the system background.
    NSString *paintSource=nil;
    UIColor *listColor=WXGEdgeListPaint(list,&paintSource),*cellColor=WXGEdgeCellPaint(list);
    // FIX70: the cells are the page when the list's own paint is far from theirs (Moments).
    if(listColor && cellColor) {
        CGFloat a=WXGEdgeLuminance(listColor,list.traitCollection),b=WXGEdgeLuminance(cellColor,list.traitCollection);
        if(a>=0 && b>=0 && fabs(a-b)>.35){listColor=nil;paintSource=@"cells";}
    }
    BOOL behind=WXGEdgeBackdropBehind(list,_controller.view);
    _plateFallback=listColor?nil:[paintSource isEqual:@"cells"]?cellColor:!behind?(cellColor?:UIColor.systemBackgroundColor):nil;
    if(!listColor && ![paintSource isEqual:@"cells"] && !behind)paintSource=cellColor?@"cells":@"systemBackground";
    UIColor *plateColor=listColor?:_plateFallback;
    _plateSource=plateColor?paintSource:@"none";
    if(!source && fading && parent && plateColor) {
        if(!_plate){_plate=[WXGEdgePlateView new];_plate.userInteractionEnabled=NO;}
        if(![_plate.backgroundColor isEqual:plateColor])_plate.backgroundColor=plateColor;
        // FIX106 I: behind the list (after it, drawn lower) where the list leads
        // its parent on WeChat's other pages; the chat page as before.
        if(_scope!=WXGEdgeScopeChat && WXGEdgeListLeads(list))[self place:_plate behind:list parent:parent frame:[self listRect]];
        else [self place:_plate below:list parent:parent frame:[self listRect]];
    }else if(_plate){[_plate removeFromSuperview];_plate=nil;}
    // Our settings pages: their glass cards sit in the list, and a mask above
    // a backdrop breaks it. The list stays unmasked; a copy of the page's
    // wallpaper comes in over it towards the edges instead (the wallpaper does
    // not scroll, so this is what the faded list would show).
    if(source && fading && parent && source.superview==parent) {
        if(!_cover) {
            _cover=[WXGEdgeCoverView new];_cover.userInteractionEnabled=NO;_cover.clipsToBounds=YES;
            _coverMask=[CAGradientLayer layer];_coverMask.anchorPoint=CGPointZero;
            _coverMask.startPoint=CGPointMake(.5,0);_coverMask.endPoint=CGPointMake(.5,1);
            _cover.layer.mask=_coverMask;
            _coverListY=-1;
        }
        _cover.image=source.image;_cover.contentMode=source.contentMode;
        [self place:_cover above:list parent:parent frame:source.frame];
    }else if(_cover){[_cover removeFromSuperview];_cover=nil;}
    // The blur bands, top and bottom each with its own strength.
    CGFloat topRadius=MAX(0,v.blurTopRadius),bottomRadius=MAX(0,v.blurBottomRadius);
    _topRadius=topRadius;_bottomRadius=bottomRadius;
    // A list that is the page's own view has no place inside the page that
    // moves with it.
    BOOL placeable=parent && list!=_controller.view && WXGEdgeBackdropClass();
    _blurNote=!parent?@"列表没有父视图":list==_controller.view?@"列表就是页面本身，不加模糊":!WXGEdgeBackdropClass()?@"系统没有 CABackdropLayer":
        (WXGEdgeVariableBlurAvailable()?@"variableBlur":@"gaussianBlur（没有 variableBlur）");
    _blurTopExtent=placeable && topRadius>.01?WXGEdgeBand(v.blurTop,size.height):0;
    _blurBottomExtent=placeable && bottomRadius>.01?WXGEdgeBand(v.blurBottom,size.height):0;
    UIView *anchor=_cover?:list;
    _topBlur=[self band:_topBlur wanted:_blurTopExtent>0 bottom:NO radius:topRadius*(1-_panel) parent:parent anchor:anchor];
    _bottomBlur=[self band:_bottomBlur wanted:_blurBottomExtent>0 bottom:YES radius:bottomRadius*(1-_panel) parent:parent anchor:anchor];
    [self syncGeometry];
}
- (void)buildMaskForSize:(CGSize)size top:(CGFloat)top bottom:(CGFloat)bottom force:(BOOL)force {
    if(!force && CGSizeEqualToSize(size,_maskSize) && fabs(top-_maskTop)<=.1 && fabs(bottom-_maskBottom)<=.1)return;
    NSMutableArray *colors=[NSMutableArray arrayWithCapacity:WXG_EDGE_FADE_STOPS],*locations=[NSMutableArray arrayWithCapacity:WXG_EDGE_FADE_STOPS];
    CGFloat height=MAX(size.height,1);
    for(NSUInteger i=0;i<WXG_EDGE_FADE_STOPS;i++) {
        CGFloat location=(CGFloat)i/(WXG_EDGE_FADE_STOPS-1);
        CGFloat alpha=WXGEdgeFadeAlpha(location*height,height,top,bottom);
        [colors addObject:(__bridge id)[UIColor colorWithWhite:1 alpha:alpha].CGColor];
        [locations addObject:@(location)];
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _mask.colors=colors;_mask.locations=locations;
    [CATransaction commit];
    _maskSize=size;_maskTop=top;_maskBottom=bottom;++_maskBuilds;
}
/* The wallpaper copy's mask: inside the list's rect the inverse of the fade
   (opaque at the list's edges), nothing outside it. */
- (void)buildCoverMaskForHeight:(CGFloat)height listY:(CGFloat)listY listHeight:(CGFloat)listHeight {
    NSMutableArray *colors=[NSMutableArray arrayWithCapacity:WXG_EDGE_FADE_STOPS],*locations=[NSMutableArray arrayWithCapacity:WXG_EDGE_FADE_STOPS];
    CGFloat h=MAX(height,1);
    for(NSUInteger i=0;i<WXG_EDGE_FADE_STOPS;i++) {
        CGFloat location=(CGFloat)i/(WXG_EDGE_FADE_STOPS-1),y=location*h-listY;
        CGFloat alpha=y<0 || y>listHeight?0:1-WXGEdgeFadeAlpha(y,listHeight,_fadeTop,_fadeBottom);
        [colors addObject:(__bridge id)[UIColor colorWithWhite:1 alpha:alpha].CGColor];
        [locations addObject:@(location)];
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _coverMask.colors=colors;_coverMask.locations=locations;
    [CATransaction commit];
    _coverListY=listY;_coverListHeight=listHeight;_coverTop=_fadeTop;_coverBottom=_fadeBottom;++_maskBuilds;
}
- (WXGEdgeBlurView *)band:(WXGEdgeBlurView *)band wanted:(BOOL)wanted bottom:(BOOL)bottom radius:(CGFloat)radius
                   parent:(UIView *)parent anchor:(UIView *)anchor {
    if(!wanted){[band removeFromSuperview];return nil;}
    if(!band)band=[[WXGEdgeBlurView alloc] initWithBottomEdge:bottom];
    [band setBlurRadius:radius];
    [self place:band above:anchor parent:parent frame:[self bandFrame:bottom]];
    return band;
}
/* A band in the list's superview: the list's visible rect, top or bottom
   extent (never more than the list). */
- (CGRect)bandFrame:(BOOL)bottom {
    UIScrollView *list=_scrollView;UIView *parent=list.superview;
    if(!parent)return CGRectZero;
    CGRect rect=[parent convertRect:list.bounds fromView:list];
    CGFloat extent=MIN(bottom?_blurBottomExtent:_blurTopExtent,rect.size.height);
    return CGRectMake(rect.origin.x,bottom?CGRectGetMaxY(rect)-extent:rect.origin.y,rect.size.width,extent);
}
/* The list scrolled, moved, resized or laid out: the mask follows its bounds
   (it lives in the list's scrolling coordinates), the bands and the
   wallpaper copy its frame. A new size re-applies everything (bands longer
   than the list, the mask's stops). */
- (void)syncGeometry {
    UIScrollView *list=_scrollView;if(!list)return;
    CGSize size=list.bounds.size;
    if(size.width>=1 && size.height>=1 && !CGSizeEqualToSize(size,_appliedSize)){[self applyValues:NO];return;}
    // FIX67: the mini-program panel opening on the home list. FIX94: also
    // while WeChat has its title bar buttons (and title) in the list's header
    // (pulled down): no fade, no blur over them.
    CGFloat panel=_homePanel?WXGHomePanelProgressForController(_controller):0;
    BOOL topBar=_homePanel && WXGHomeTopBarInList(list);
    BOOL panelChanged=fabs(panel-_panel)>.004 || (panel==0)!=(_panel==0) || (panel==1)!=(_panel==1) || topBar!=_topBarInList;
    if(panelChanged){_panel=panel;_topBarInList=topBar;}
    if(_mask && list.layer.mask==_mask) {
        CGRect bounds=list.layer.bounds;
        if(!CGRectEqualToRect(bounds,_syncedBounds) || panelChanged) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            _mask.position=bounds.origin;_mask.bounds=CGRectMake(0,0,bounds.size.width,bounds.size.height);
            _maskSolid.frame=_mask.bounds;_maskSolid.opacity=(float)_panel;
            if(_maskTopSolid){_maskTopSolid.frame=CGRectMake(0,0,bounds.size.width,MIN(bounds.size.height,_fadeTop+1));_maskTopSolid.opacity=_topBarInList?1:0;}
            [CATransaction commit];
            _syncedBounds=bounds;++_maskSyncs;
        }
    }
    if(!_plate && !_cover && !_topBlur && !_bottomBlur)return;
    UIView *parent=list.superview;UIImageView *source=_coverSource;
    if(!parent || (_plate && _plate.superview!=parent) || (_cover && (_cover.superview!=parent || source.superview!=parent)) ||
       (_topBlur && _topBlur.superview!=parent) || (_bottomBlur && _bottomBlur.superview!=parent)) {
        // Moved to another container: placed again on the next refresh.
        [_plate removeFromSuperview];[_cover removeFromSuperview];[_topBlur removeFromSuperview];[_bottomBlur removeFromSuperview];
        _plate=nil;_cover=nil;_topBlur=_bottomBlur=nil;
        return;
    }
    // Inside WeChat's own animation (the keyboard moving the list) the
    // plate and the bands animate with it.
    BOOL hidden=list.hidden || list.alpha<.01;
    if(_plate) {
        // WeChat may change it (a wallpaper set: clear, nothing to keep then).
        // The cells' paint (FIX70) is re-read on the next layout.
        UIColor *paint=([_plateSource isEqual:@"list"] || [_plateSource isEqual:@"backgroundView"]?WXGEdgeListPaint(list,NULL):nil)?:_plateFallback?:UIColor.clearColor;
        if(![_plate.backgroundColor isEqual:paint])_plate.backgroundColor=paint;
        CGRect frame=[self listRect];
        if(!CGRectEqualToRect(_plate.frame,frame))_plate.frame=frame;
        if(_plate.hidden!=hidden)_plate.hidden=hidden;
    }
    if(_cover) {
        if(_cover.image!=source.image)_cover.image=source.image;   // light / dark wallpaper
        CGRect frame=source.frame;
        if(!CGRectEqualToRect(_cover.frame,frame))_cover.frame=frame;
        if(!CGRectEqualToRect(_coverMask.frame,_cover.bounds)) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            _coverMask.frame=_cover.bounds;
            [CATransaction commit];
        }
        CGRect rect=[parent convertRect:list.bounds fromView:list];
        CGFloat listY=CGRectGetMinY(rect)-CGRectGetMinY(frame);
        if(fabs(listY-_coverListY)>.1 || fabs(rect.size.height-_coverListHeight)>.1 || !CGSizeEqualToSize(frame.size,_coverSize) ||
           fabs(_fadeTop-_coverTop)>.1 || fabs(_fadeBottom-_coverBottom)>.1) {
            _coverSize=frame.size;
            [self buildCoverMaskForHeight:frame.size.height listY:listY listHeight:rect.size.height];
        }
        if(_cover.hidden!=hidden)_cover.hidden=hidden;
    }
    for(WXGEdgeBlurView *band in @[_topBlur?:NSNull.null,_bottomBlur?:NSNull.null]) {
        if(![band isKindOfClass:WXGEdgeBlurView.class])continue;
        CGRect frame=[self bandFrame:band.bottomEdge];
        if(!CGRectEqualToRect(band.frame,frame))band.frame=frame;
        // FIX94: the top band also gives way to WeChat's title bar in the list.
        CGFloat cover=band.bottomEdge?_panel:(_topBarInList?1:_panel);
        if(panelChanged)[band setBlurRadius:(band.bottomEdge?_bottomRadius:_topRadius)*(1-cover)];
        BOOL bandHidden=hidden || cover>.99;
        if(band.hidden!=bandHidden)band.hidden=bandHidden;
    }
}
- (NSDictionary *)evidence {
    UIScrollView *list=_scrollView;UIViewController *controller=_controller;
    WXGEdgeValues v=WXGEdgeValuesForScope(_scope);
    NSMutableDictionary *d=[@{@"page":controller?NSStringFromClass(controller.class):@"none",@"scope":_scope==WXGEdgeScopeChat?@"chat":@"other",
        @"list":list?NSStringFromClass(list.class):@"none",@"resolves":@(_resolves),@"attaches":@(_attaches),@"maskBuilds":@(_maskBuilds),
        @"settings":@{@"fadeTop":@(v.fadeTop),@"fadeBottom":@(v.fadeBottom),@"blurTop":@(v.blurTop),@"blurBottom":@(v.blurBottom),
                      @"blurTopRadius":@(v.blurTopRadius),@"blurBottomRadius":@(v.blurBottomRadius)},
        @"blur":_blurNote?:@"none",@"fade":_coverSource?@"wallpaperCover":@"listMask",@"miniProgramPanel":@(_panel),@"topBarInList":@(_topBarInList)} mutableCopy];
    if(list) {
        d[@"listFrame"]=NSStringFromCGRect(list.frame);d[@"listInWindow"]=@(list.window!=nil);
        d[@"maskAttached"]=@(_mask && list.layer.mask==_mask);d[@"keptOriginalMask"]=@(_originalMask!=nil);
        d[@"fadeBands"]=@[@(_fadeTop),@(_fadeBottom)];
        // FIX84: the list leads back to this page; the mask sits on the list's
        // scroll position (lag 0 when it follows the scrolling).
        d[@"linked"]=@(WXGEdgePageForList(list)==self);d[@"maskSyncs"]=@(_maskSyncs);
        if(_mask && list.layer.mask==_mask)
            d[@"maskLag"]=@(round((_mask.position.y-list.layer.bounds.origin.y)*10)/10);
    }
    if(_cover)d[@"coverFrame"]=NSStringFromCGRect(_cover.frame);
    if(_plate) {
        CGFloat r=0,g=0,b=0,a=0;[_plate.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
        d[@"backgroundPlate"]=@{@"frame":NSStringFromCGRect(_plate.frame),@"rgba":@[@(r),@(g),@(b),@(a)],@"source":_plateSource?:@"none",
                               @"behindList":@(_plate.layer.zPosition<0)};   // FIX106 I: after the list, drawn lower
    }
    if(list.superview)d[@"listIndex"]=@([list.superview.subviews indexOfObjectIdenticalTo:list]);
    if(_topBlur)d[@"topBlurFrame"]=NSStringFromCGRect(_topBlur.frame);
    if(_bottomBlur)d[@"bottomBlurFrame"]=NSStringFromCGRect(_bottomBlur.frame);
    return d;
}
@end

#pragma mark - Entry points

/* FIX67: WeChat's mini-program panel on the home page: a header view inside
   the chat list, pulled down from above. Its bottom edge on screen gives the
   progress (WXGHomePanelProgress). The view is looked up once (again at most
   twice a second while missing) and kept weakly per controller. */
@interface WXGHomePanelProbe : NSObject
@property(nonatomic,weak) UIView *header;
@property(nonatomic) CFTimeInterval lastSearch;
@end
@implementation WXGHomePanelProbe
@end
static char WXGHomePanelProbeKey;
CGFloat WXGHomePanelProgressForController(UIViewController *home) {
    static Class panelClass;static dispatch_once_t once;
    dispatch_once(&once,^{panelClass=NSClassFromString(@"WAMainFrameTopHeaderView")?:NSClassFromString(@"WAMainFrameTaskBarView");});
    if(!panelClass || !home.isViewLoaded)return 0;
    UIView *root=home.view;UIWindow *w=root.window;
    if(!w)return 0;
    WXGHomePanelProbe *probe=objc_getAssociatedObject(home,&WXGHomePanelProbeKey);
    if(!probe){probe=[WXGHomePanelProbe new];objc_setAssociatedObject(home,&WXGHomePanelProbeKey,probe,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIView *header=probe.header;
    if(!header || header.window!=w || ![header isDescendantOfView:root]) {
        CFTimeInterval now=CACurrentMediaTime();
        if(now-probe.lastSearch<.5)return 0;
        probe.lastSearch=now;header=nil;
        NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root];
        for(NSUInteger i=0;i<queue.count && i<600 && !header;i++) {
            UIView *v=queue[i];
            if([v isKindOfClass:panelClass]){header=v;break;}
            if([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class] || WXGIsPluginView(v))continue;
            [queue addObjectsFromArray:v.subviews];
        }
        probe.header=header;
        if(!header)return 0;
    }
    if(header.hidden)return 0;
    CGRect rect=[header convertRect:header.bounds toView:nil];
    return WXGHomePanelProgress((float)(CGRectGetMaxY(rect)/MAX(w.bounds.size.height,1)));
}

static void WXGEdgeFadeObserve(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        WXGEdgePages=[NSHashTable weakObjectsHashTable];
        for(NSString *name in @[WXGSettingsChanged,@"WXGIntegrationChanged"])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){
                for(WXGEdgePage *page in WXGEdgePages.allObjects)[page refresh:NO];
            }];
    });
}
void WXGEdgeFadeNoteController(UIViewController *controller,BOOL appearing) {
    if(!controller.isViewLoaded)return;
    WXGEdgeScope scope=WXGEdgeScopeForController(controller);
    if(scope==WXGEdgeScopeNone)return;
    WXGEdgePage *page=objc_getAssociatedObject(controller,&WXGEdgePageKey);
    if(!page) {
        if(!WXGEdgeFadeWanted())return;
        WXGEdgeFadeObserve();
        page=[WXGEdgePage new];page.controller=controller;page.scope=scope;
        static Class home;static dispatch_once_t once;dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");});
        page.homePanel=home && [controller isKindOfClass:home];
        objc_setAssociatedObject(controller,&WXGEdgePageKey,page,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [WXGEdgePages addObject:page];
    }
    [page refresh:appearing];
}
void WXGEdgeFadeSyncController(UIViewController *controller) {
    WXGEdgePage *page=controller?objc_getAssociatedObject(controller,&WXGEdgePageKey):nil;
    [page syncGeometry];
}
NSDictionary *WXGEdgeFadeEvidence(void) {
    NSMutableArray *pages=[NSMutableArray array];
    for(WXGEdgePage *page in WXGEdgePages.allObjects)if(page.controller)[pages addObject:page.evidence];
    return @{@"enabled":@(WXGPreferences.shared.edgeFade),@"active":@(WXGEdgeFadeWanted()),
             @"variableBlur":@(WXGEdgeVariableBlurAvailable()),@"relinks":@(WXGEdgeRelinks),@"pages":pages};
}
