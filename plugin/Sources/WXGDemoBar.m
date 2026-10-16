#import "WXGElasticMotion.h"
#import "WXGCommon.h"
#import "WXGNativeIcons.h"
#import "WXGDockTouchPolicy.h"
#import "WXGLensOptics.h"
#import "WXGBackdropSample.h"
#import "WXGDockSearchLayout.h"
#import "WXGPressStretch.h"
#import "WXGTravelVeil.h"
#import "WXGDockScript.h"
#import "WXGDockDiscrete.h"

// FIX21: everything the dock icon atlas depends on, captured on the main
// thread, so the two large atlases are drawn and uploaded on a background
// queue instead of stalling a tab switch.
@interface WXGIconJob : NSObject
@property(nonatomic) CGSize size;
@property(nonatomic) CGFloat scale;
@property(nonatomic) CGRect materialRect;
@property(nonatomic,copy) NSArray<NSNumber *> *centers;
@property(nonatomic) BOOL darkInk,useNative;
@property(nonatomic) NSInteger selectedIndex;
// FIX106 D: each tab's artwork, ready to draw (the trait variant picked and
// tinted on the main thread: WXGDockTabArtwork), its title and colour, per
// state. The queue only draws: -[UIImage imageAsset] creates and registers
// an asset the first time and is not thread-safe - read on this queue while
// the main thread read the same images (the discrete dock), it crashed
// (EXC_BAD_ACCESS in -[UIImageAsset _unsafe_registerImage:...], cold start).
@property(nonatomic,copy) NSArray *normalArt,*selectedArt;   // UIImage or NSNull
@property(nonatomic,copy) NSArray<UIColor *> *normalColors,*selectedColors;
@property(nonatomic,copy) NSArray<NSString *> *titles;
@property(nonatomic) CGFloat iconShift,titleShift;   // FIX89: from where they were (pt, + down)
@property(nonatomic) CGFloat titleSize;              // FIX91
@property(nonatomic) NSInteger titleWeight;          // FIX91: 0 light .. 4 bold
@property(nonatomic) BOOL bolderSelected;
@end
@implementation WXGIconJob
@end
static dispatch_queue_t WXGDockIconQueue(void) {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.runyu.wxg.dock-icons",DISPATCH_QUEUE_SERIAL);});
    return queue;
}
// FIX42: cubic-bezier easing (control points x1,y1,x2,y2), evaluated on the
// CPU for the touch-down glide so it matches the render-server glide.
static double WXGBezierEase(double x,double x1,double y1,double x2,double y2) {
    x=WXGClamp(x,0,1);double t=x;
    for(int i=0;i<8;i++) {
        double cx=3*x1*t*(1-t)*(1-t)+3*x2*t*t*(1-t)+t*t*t-x;
        double dx=3*x1*(1-t)*(1-t)+6*(x2-x1)*t*(1-t)+3*(1-x2)*t*t;
        if(fabs(cx)<1e-5 || fabs(dx)<1e-6)break;
        t=WXGClamp(t-cx/dx,0,1);
    }
    return 3*y1*t*(1-t)*(1-t)+3*y2*t*t*(1-t)+t*t*t;
}
// FIX44: the hole under the travelling lens is a static alpha image (opaque
// everywhere except a capsule at its centre) whose position and bounds are
// animated: no path is re-tessellated per frame. The capsule is 1/12 of the
// image width and 1/7 of its height, so the opaque part always covers the
// whole dock around the lens.
#define WXG_HOLE_KW 12.
#define WXG_HOLE_KH 7.
static UIImage *WXGTravelHoleImage(void) {
    static UIImage *image;static dispatch_once_t once;
    dispatch_once(&once,^{
        const size_t hw=96,hh=62,w=(size_t)(hw*WXG_HOLE_KW),h=(size_t)(hh*WXG_HOLE_KH);
        CGContextRef context=CGBitmapContextCreate(NULL,w,h,8,w,NULL,(CGBitmapInfo)kCGImageAlphaOnly);
        if(!context)return;
        CGContextSetRGBFillColor(context,0,0,0,1);CGContextFillRect(context,CGRectMake(0,0,w,h));
        CGContextSetBlendMode(context,kCGBlendModeClear);
        CGPathRef hole=CGPathCreateWithRoundedRect(CGRectMake((w-hw)*.5,(h-hh)*.5,hw,hh),hh*.5*.999,hh*.5*.999,NULL);
        CGContextAddPath(context,hole);CGContextFillPath(context);CGPathRelease(hole);
        CGImageRef made=CGBitmapContextCreateImage(context);CGContextRelease(context);
        if(made){image=[UIImage imageWithCGImage:made];CGImageRelease(made);}
    });
    return image;
}
// One tab's artwork as the dock shows it: WeChat's own (the variant for its
// traits, tinted when it is a template) or the SF symbol (drawn at the size
// shown: 24 pt for the atlas's 26 pt box), and the colour its title takes.
// MAIN THREAD ONLY (FIX106 D): it reads -[UIImage imageAsset].
static UIImage *WXGDockTabArtwork(WXGNativeIconPair *pair,NSInteger i,BOOL selected,BOOL darkInk,CGFloat iconSize,UIColor **textColor) {
    NSArray *symbols=@[@"bubble.left.and.bubble.right",@"person.2",@"safari",@"person.crop.circle"];
    NSArray *filled=@[@"bubble.left.and.bubble.right.fill",@"person.2.fill",@"safari.fill",@"person.crop.circle.fill"];
    i=MAX(0,MIN(3,i));
    UIColor *color=selected?[UIColor colorWithRed:.03 green:.72 blue:.38 alpha:1]:
        (darkInk?[UIColor colorWithWhite:.10 alpha:.92]:[UIColor colorWithWhite:.97 alpha:.97]);
    UIImage *icon=selected?pair.selectedImage:pair.normalImage;
    if(icon) {
        UIImage *variant=icon.imageAsset?[icon.imageAsset imageWithTraitCollection:pair.traits]:nil;
        if(variant)icon=variant;
        BOOL templ=selected?pair.selectedTemplate:pair.normalTemplate;
        UIColor *nativeTint=selected?pair.selectedTint:pair.normalTint;
        if(templ)icon=[icon imageWithTintColor:nativeTint?:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        UIColor *native=selected?pair.selectedTextColor:pair.normalTextColor;
        color=native?:(templ?nativeTint:nil)?:color;
    } else {
        UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:MAX(12,round(iconSize*24/26)) weight:UIImageSymbolWeightMedium];
        icon=[UIImage systemImageNamed:selected?filled[i]:symbols[i] withConfiguration:config];
        if(!icon)icon=[UIImage systemImageNamed:i==0?@"bubble.left":@"circle" withConfiguration:config];
        icon=[icon imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    if(textColor)*textColor=color;
    return icon;
}
static UIImage *WXGRenderDockIcons(WXGIconJob *job,BOOL selected,BOOL fallback) {
    if(!job || job.size.width<1 || job.size.height<1)return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=job.scale;format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc] initWithSize:job.size format:format];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        // FIX106 D: only what the job holds (resolved on the main thread).
        for(NSInteger i=0;i<4;i++) {
            BOOL useSelected=fallback?(i==job.selectedIndex):selected;
            NSArray *art=useSelected?job.selectedArt:job.normalArt;
            NSArray<UIColor *> *colors=useSelected?job.selectedColors:job.normalColors;
            id artwork=i<(NSInteger)art.count?art[(NSUInteger)i]:nil;
            UIImage *icon=[artwork isKindOfClass:UIImage.class]?artwork:nil;
            UIColor *color=i<(NSInteger)colors.count?colors[(NSUInteger)i]:UIColor.grayColor;
            NSString *title=i<(NSInteger)job.titles.count?job.titles[(NSUInteger)i]:@"";
            CGFloat cx=i<(NSInteger)job.centers.count?job.centers[i].doubleValue:0,cy=CGRectGetMidY(job.materialRect)-8+job.iconShift;
            CGFloat ratio=MIN(28/MAX(icon.size.width,1),26/MAX(icon.size.height,1));
            CGSize sz=CGSizeMake(icon.size.width*ratio,icon.size.height*ratio);
            [icon drawInRect:CGRectMake(cx-sz.width/2,cy-sz.height/2,sz.width,sz.height)];
            // FIX91: size and weight from the settings (10.5 pt, medium /
            // semibold when selected before: too heavy at the dock's size).
            static const CGFloat weights[5]={-.4,0,.23,.3,.4};   // UIFontWeightLight .. UIFontWeightBold
            NSInteger step=MAX(0,MIN(4,job.titleWeight+((useSelected && job.bolderSelected)?1:0)));
            UIFont *font=[UIFont systemFontOfSize:job.titleSize>1?job.titleSize:10 weight:weights[step]];
            NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:color};
            CGSize text=[title sizeWithAttributes:attrs];
            [title drawAtPoint:CGPointMake(cx-text.width/2,CGRectGetMidY(job.materialRect)+10+job.titleShift) withAttributes:attrs];
        }
    }];
}

static NSString *WXGDiscreteEnglish(NSInteger i) {
    NSArray *names=@[@"Chats",@"Contacts",@"Discover",@"Me"];
    return i>=0 && i<4?names[i]:@"";
}
// The icon's size in a box `size` tall and 2 pt wider (the atlas: 28 x 26).
static CGSize WXGDiscreteIconSize(UIImage *icon,CGFloat size) {
    if(!icon || icon.size.width<1 || icon.size.height<1)return CGSizeMake(size,size);
    CGFloat ratio=MIN((size+2)/icon.size.width,size/icon.size.height);
    return CGSizeMake(icon.size.width*ratio,icon.size.height*ratio);
}

@interface WXGTickProxy : NSObject
@property(nonatomic,weak) WXGDemoBar *owner;
- (void)tick:(CADisplayLink *)link;
@end
@interface WXGAccessibleItem : UIAccessibilityElement
@property(nonatomic,copy) BOOL (^activate)(void);
@end
@implementation WXGAccessibleItem
- (BOOL)accessibilityActivate { return self.activate?self.activate():NO; }
@end

@interface WXGDemoBar ()
@property(nonatomic) WXGElasticMotion elasticMotion;
// FIX68: the bar's end pushed out past the last tab (x only), and which end.
@property(nonatomic) WXGStretchState endStretch;
@property(nonatomic) int endStretchSide;
@property(nonatomic,strong) WXGGlassView *glass;
@property(nonatomic,strong) UIVisualEffectView *fallback;
@property(nonatomic,strong) UIView *fallbackLens;
@property(nonatomic,strong) UIImageView *fallbackIcons;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic,strong) WXGTickProxy *tickProxy;
@property(nonatomic,strong) UISelectionFeedbackGenerator *feedback;
@property(nonatomic,strong) WXGNativeIcons *nativeIcons;
@property(nonatomic,weak) UITabBarController *nativeTabs;
@property(nonatomic) BOOL previousNativeIcons;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) NSInteger initialSelected;
@property(nonatomic) BOOL fingerDown;
@property(nonatomic) BOOL darkInk;
@property(nonatomic) double lensX, velocityX, targetX;
@property(nonatomic) double press, pressVelocity, targetPress;
@property(nonatomic) CFTimeInterval lastTime,previewStart;
@property(nonatomic) NSUInteger downCount,moveCount;
@property(nonatomic) WXGDockTouchPoint trackingPoint;
@property(nonatomic) NSUInteger trackingEnds,trackingCancels,trackingCommits,nilTrackingEnds,interactionAborts;
@property(nonatomic,copy) NSString *lastTrackingReason;
@property(nonatomic) NSInteger lastCommittedIndex;
@property(nonatomic) CGSize previousSize;
@property(nonatomic) CGFloat previousInset, iconScale;
@property(nonatomic) CGRect iconMaterialRect;
@property(nonatomic,copy) NSString *iconLayout;   // FIX89: the icon / title placement the atlas was drawn with
@property(nonatomic) NSUInteger iconGeneration,rescanToken,asyncIconBuilds;
@property(nonatomic) BOOL iconsReady;
@property(nonatomic) CGRect materialRect;
@property(nonatomic,strong) NSArray<WXGAccessibleItem *> *a11yItems;
@property(nonatomic,strong) NSArray<UILabel *> *badges;
// FIX33: render-server tap animation (iOS 26 style). While it runs, the
// per-frame dock rests at the target with its own lens suppressed; these
// Core Animation layers carry the lens across, untouched by main-thread work.
@property(nonatomic) BOOL travelling,dragging,jumping;
@property(nonatomic) CFTimeInterval jumpStart,jumpDuration,jumpPlanEnd;
@property(nonatomic) CGFloat jumpFromX;
@property(nonatomic) CGPoint touchStart;
@property(nonatomic) NSUInteger travelToken,travels,neutralFrameMisses;
@property(nonatomic,strong) UIView *travelView;
@property(nonatomic,strong) CALayer *travelLens,*travelTint,*travelBackdrop,*travelIconHolder,*travelIconZoom,*travelIconImage,*travelIconMask;
@property(nonatomic,strong) UIImage *selectedAtlas,*normalAtlas;
@property(nonatomic,strong) CALayer *travelNormalIcons;
@property(nonatomic,strong) NSArray<UIView *> *travelBackdrops;
@property(nonatomic,copy) NSString *travelBackdropKey;
@property(nonatomic,strong) UIImage *tintedAtlas,*tintedSource;
@property(nonatomic,strong) UIColor *tintedColor;
@property(nonatomic,strong) CALayer *travelHole;
// FIX44: the travel in phases: 1 = touch-down glide (held lifted at the
// target, render server), 2 = release animation ending in the pill.
@property(nonatomic) NSInteger travelPhase,travelIndex;
@property(nonatomic) CFTimeInterval travelPlanEnd;
@property(nonatomic) CGPoint travelFrom,travelTo;
@property(nonatomic) CGSize travelStartSize,travelRestSize,travelLiftSize;
@property(nonatomic) CGFloat travelStartPress,travelPillAlpha,travelRimAlpha;
@property(nonatomic) double travelSetupMS;
@property(nonatomic,strong) UIColor *travelSelection,*travelRim;
@property(nonatomic) NSUInteger glides,drops,handovers,glideCancels;
// FIX88: the tap animation draws the bar seen through its lens like the real
// lens (inset, 45-degree joins, the material's edge fade, the bar's outline)
// and the bar grows with the lift; the move it follows; holds handed over to
// the real lens; touch ends that did not switch (diagnostics).
@property(nonatomic,strong) CALayer *travelVeil;
@property(nonatomic,strong) NSMutableArray<CAShapeLayer *> *travelVeilBands;
@property(nonatomic,strong) NSArray<CAShapeLayer *> *travelOutlines;   // FIX89: one per line the lens draws (two for the iOS 27-like rim)
@property(nonatomic) BOOL travelVeilOn;
@property(nonatomic) NSInteger travelVeilCount;
@property(nonatomic) float *travelVeilDepths;
@property(nonatomic) CFTimeInterval travelMoveStart,travelMoveDuration;
@property(nonatomic) CGPoint travelMoveFrom,travelMoveTo;
@property(nonatomic) NSUInteger holdHandovers,uncommittedEnds;
// FIX95: the tap animation is the real lens on a script (WXGDockScript.h);
// the render-server one (above) only with 点按时用简化透镜.
@property(nonatomic) WXGDockScript script;
@property(nonatomic) NSUInteger scriptGlides,scriptDrops,scriptTravels,scriptDrags;
@property(nonatomic) NSInteger resumeIndex;   // a landing a new touch interrupted (-1 none): released there, it lands again
// FIX100: the tab WeChat was asked to switch to at this touch-down (-1 none),
// and whether the request went out.
@property(nonatomic) NSInteger earlyIndex;
@property(nonatomic) BOOL earlySent;
// FIX101: after a switch, the lens waits for the main thread to be calm:
// since when (0 not waiting), the clock it was held at, the calm frames seen.
@property(nonatomic) CFTimeInterval calmWaitFrom,calmHoldClock,calmLastTick;
@property(nonatomic) NSInteger calmFrames;
@property(nonatomic) double tapCalmWait,tapCaughtUp;
@property(nonatomic,strong) NSMutableArray *tapSlowFrames;
@property(nonatomic,readwrite) BOOL switchedAtTouchDown;
// FIX98: the script's clock (real time, a stalled frame one capped step:
// WXGScriptClockStep), the selection colour's weight shown (1 the pill), and
// what was left between a script's colour and the press' when it ended (it
// decays), and how often the clock skipped a stall.
@property(nonatomic) CFTimeInterval animClock,animClockReal;
@property(nonatomic) double selectionShown,selectionCarry,clockLostMS;
@property(nonatomic) NSUInteger clockStalls;
// FIX99: when the host last forwarded a switch (real time), and the first taps'
// timing (diagnostics `taps`: since launch, planned / actual length, longest
// frame, the switch's place in it).
@property(nonatomic) CFTimeInterval switchAt,tapStartReal,tapSwitchAt,tapLastFrame,tapLongestFrame;
@property(nonatomic) double tapLostAtStart;
@property(nonatomic) BOOL tapOpen;
@property(nonatomic) NSInteger tapKind;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *tapRecords;
@property(nonatomic) CFTimeInterval touchDownTime;
@property(nonatomic) NSInteger touchDownIndex;
// FIX60: the search morph (tabs <-> round close button) and the close button.
@property(nonatomic) BOOL morphing,closeTracking;
@property(nonatomic) CGRect morphShape;
@property(nonatomic) CGFloat morphProgress;
@property(nonatomic) NSUInteger morphToken,morphs;
@property(nonatomic,strong) UIView *morphView;
@property(nonatomic,strong) CALayer *morphMask,*morphContent,*morphNormal,*morphHole,*morphPill,*morphSelected;
@property(nonatomic,strong) UIImageView *closeIcon;
@property(nonatomic,strong) WXGAccessibleItem *closeItem;
// 离散底栏 (WXGDockDiscrete.h): the pieces' glass (one per capsule in use),
// each tab's content (clip, icon unselected / selected, 中文 / English
// title), how many capsules are in use, whether the bar glass / the pieces
// stay on through a crossfade (the search morph), and the counts.
@property(nonatomic,readwrite) BOOL discreteShown;
@property(nonatomic,strong) UIView *discreteView;
@property(nonatomic,strong) NSMutableArray<WXGGlassView *> *pieces;
@property(nonatomic,strong) NSArray<UIView *> *tabClips;
@property(nonatomic,strong) NSArray<UIImageView *> *tabIcons,*tabSelectedIcons;
@property(nonatomic,strong) NSArray<UILabel *> *tabTitles,*tabSubtitles;
@property(nonatomic) NSInteger pieceCount;
@property(nonatomic) BOOL discreteDirty,classicLingers,piecesLinger,discreteLaying;
@property(nonatomic) NSUInteger discreteFadeToken,discreteSwitches,discreteShows;
@property(nonatomic) CGRect discreteRowRect;
- (void)tick:(CADisplayLink *)link;
- (void)endTravel:(NSUInteger)token;
- (BOOL)beginTravelToIndex:(NSInteger)index;
- (BOOL)beginGlideToIndex:(NSInteger)index duration:(CFTimeInterval)duration;
- (void)dropTravel;
- (void)cancelGlide;
- (void)handOverTravelToFinger;
- (void)finishTravelNow;
- (void)ensureTravelLayers;
- (void)revealAfterTravel:(NSUInteger)token attempt:(NSUInteger)attempt;
@end
@implementation WXGTickProxy
- (void)tick:(CADisplayLink *)link { [self.owner tick:link]; }
@end

@implementation WXGDemoBar {
    // 离散底栏: each tab's expansion (0 ball .. 1 wide) and its velocity, the
    // bridges between neighbours (connected), and where each tab was laid
    // (material space), its text block's width and its icon's centre.
    double _discreteE[WXGDiscreteTabs],_discreteV[WXGDiscreteTabs];
    double _bridge[WXGDiscreteTabs-1],_bridgeV[WXGDiscreteTabs-1];
    double _gather[WXGDiscreteTabs],_gatherV[WXGDiscreteTabs];   // FIX106 C: icon offsets (cells + gap), springs
    float _tabX[WXGDiscreteTabs],_tabW[WXGDiscreteTabs];
    CGFloat _tabTextW[WXGDiscreteTabs];
    CGPoint _tabIconCentre[WXGDiscreteTabs];
    WXGDiscreteMetrics _discreteMetrics;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor; self.opaque=NO; self.clipsToBounds=NO;
        self.layer.shadowColor=UIColor.blackColor.CGColor;self.layer.shadowOpacity=.10;self.layer.shadowRadius=20;self.layer.shadowOffset=CGSizeMake(0,8);
        self.isAccessibilityElement=NO; _darkInk=YES; _resumeIndex=-1; _selectionShown=1; _earlyIndex=-1;
        _nativeIcons=[WXGNativeIcons new]; _previousNativeIcons=WXGConfig.shared.useWeChatIcons;
        _fallback=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        _fallback.userInteractionEnabled=NO; _fallback.clipsToBounds=YES;
        _fallback.layer.cornerCurve=kCACornerCurveContinuous;
        [self addSubview:_fallback];
        _fallbackLens=[UIView new]; _fallbackLens.userInteractionEnabled=NO;
        _fallbackLens.backgroundColor=[UIColor.whiteColor colorWithAlphaComponent:.22];
        _fallbackLens.layer.borderWidth=0; _fallbackLens.layer.cornerCurve=kCACornerCurveContinuous;
        [self addSubview:_fallbackLens];
        _fallbackIcons=[UIImageView new]; _fallbackIcons.userInteractionEnabled=NO;
        [self addSubview:_fallbackIcons];
        _glass=[[WXGGlassView alloc] initWithFrame:self.bounds];_glass.dockSurface=YES; _glass.hidden=YES;
        [self addSubview:_glass];
        // FIX34: render-server glass is visible before its overlay is ready, so
        // the fallback lens and icons sit above it, not under its blur.
        [self bringSubviewToFront:_fallbackLens];[self bringSubviewToFront:_fallbackIcons];
        __weak WXGDemoBar *weakSelf=self;
        _glass.onReady=^(BOOL ready) {
            WXGDemoBar *bar=weakSelf; if (!bar) return;
            // 离散底栏: the pieces draw the dock; the bar glass and its
            // fallbacks stay out of sight (unless it lingers in a crossfade).
            if(bar.discreteShown && !bar.classicLingers) {
                bar.glass.hidden=YES;bar.fallback.hidden=YES;bar.fallbackLens.hidden=YES;bar.fallbackIcons.hidden=YES;
                [bar rebuildIcons];[bar setActive:bar.active];return;
            }
            // FIX33: render-server glass shows its live backdrop before the
            // overlay is ready, so the fallback blur bar is not needed there.
            BOOL live=WXGConfig.shared.renderMode>=2;
            bar.glass.hidden=!ready && !live;
            BOOL rendered=(ready && bar.glass.hasPresentedFrame) || (live && bar.discreteShows>0);   // 离散底栏 (see updateGeometry)
            // FIX42: the fallback material bar stays until the glass has drawn
            // its first frame, render-server mode included (cold start).
            (void)live;bar.fallback.hidden=rendered; bar.fallbackLens.hidden=rendered; bar.fallbackIcons.hidden=rendered;
            [bar rebuildIcons]; [bar setActive:bar.active];
            [bar.glass setNeedsLayout]; [bar.glass layoutIfNeeded];
            [bar.glass invalidateBackdrop];
        };
        _glass.onFirstFrame=^{
            WXGDemoBar *bar=weakSelf; if(!bar) return;
            bar.fallback.hidden=YES; bar.fallbackLens.hidden=YES; bar.fallbackIcons.hidden=YES;
        };
        // WeChat owns light/dark appearance. Moving chat imagery or a menu's
        // dimming layer must not change material colours or rebuild icon textures.
        _darkInk=self.traitCollection.userInterfaceStyle!=UIUserInterfaceStyleDark;
        _feedback=[UISelectionFeedbackGenerator new];
        _tickProxy=[WXGTickProxy new]; _tickProxy.owner=self;
        _displayLink=[CADisplayLink displayLinkWithTarget:_tickProxy selector:@selector(tick:)];
        WXGConfigureDisplayLink(_displayLink,self.window.screen); _displayLink.paused=YES;
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        NSMutableArray *items=[NSMutableArray array];
        NSArray *names=@[@"微信",@"通讯录",@"发现",@"我"];
        for (NSInteger i=0;i<4;i++) {
            WXGAccessibleItem *item=[[WXGAccessibleItem alloc] initWithAccessibilityContainer:self];
            item.accessibilityLabel=names[i]; item.accessibilityHint=@"切换微信页面";
            item.activate=^BOOL{ if(!weakSelf.active)return NO;[weakSelf selectIndex:i haptic:NO];[weakSelf sendActionsForControlEvents:UIControlEventValueChanged];return YES; };
            [items addObject:item];
        }
        _a11yItems=items; self.accessibilityElements=items;
        _showsClose=YES;
        _closeItem=[[WXGAccessibleItem alloc] initWithAccessibilityContainer:self];
        _closeItem.accessibilityLabel=@"关闭搜索";_closeItem.accessibilityTraits=UIAccessibilityTraitButton;
        _closeItem.activate=^BOOL{ WXGDemoBar *bar=weakSelf;if(!bar.active || !bar.searchMode)return NO;[bar sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];return YES; };
        NSMutableArray *badges=[NSMutableArray array];
        for(NSInteger i=0;i<4;i++) {
            UILabel *b=[UILabel new];b.textColor=UIColor.whiteColor;b.backgroundColor=UIColor.systemRedColor;
            b.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];b.textAlignment=NSTextAlignmentCenter;
            b.clipsToBounds=YES;b.hidden=YES;b.userInteractionEnabled=NO;[self addSubview:b];[badges addObject:b];
        }_badges=badges;
    } return self;
}
- (void)dealloc { [_displayLink invalidate]; free(_travelVeilDepths); }
- (void)didMoveToWindow {
    [super didMoveToWindow]; WXGConfigureDisplayLink(_displayLink,self.window.screen);[self setActive:_active];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous && ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])return;
    _darkInk=self.traitCollection.userInterfaceStyle!=UIUserInterfaceStyleDark;
    [_nativeIcons invalidateAppearance];
    if(_nativeTabs)[_nativeIcons updateFromTabController:_nativeTabs];
    [self rebuildIcons];[_glass invalidateBackdrop];
    for(WXGGlassView *piece in [_pieces copy])[piece invalidateBackdrop];
}
- (void)setExternallyDriven:(BOOL)external {_externallyDriven=external;[self setActive:_active];}
- (void)setActive:(BOOL)active {
    BOOL changed=_active!=active,wasPaused=_displayLink.paused;
    _active=active; _glass.active=active && (!_discreteShown || _classicLingers);
    for(NSInteger j=0;j<(NSInteger)_pieces.count;j++)_pieces[j].active=active && (_discreteShown || _piecesLinger) && j<_pieceCount;
    _displayLink.paused=_externallyDriven || !(active && self.window);
    if(changed || (wasPaused && !_displayLink.paused)) _lastTime=0;
    if(changed && !active) [self cancelInteraction];
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    // FIX60: searching, only the round close button takes touches.
    if(_searchMode)return _showsClose && CGRectContainsPoint(CGRectInset(_morphing?_morphShape:_materialRect,-6,-6),point);
    // 离散底栏: the row of capsules (the gaps between them included).
    if(_discreteShown && !CGRectIsEmpty(_discreteRowRect))return CGRectContainsPoint(CGRectInset(_discreteRowRect,-6,-10),point);
    return CGRectContainsPoint(CGRectInset(CGRectUnion(_fallback.frame,_glass.lensRect),-4,-6),point);
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    return !self.hidden && self.alpha>.01 && self.userInteractionEnabled && self.enabled && [self pointInside:p withEvent:event]?self:nil;
}
- (CGFloat)selectionGap { return WXGSelectionGap(WXGConfig.shared.selectionInset,_materialRect.size.height); }
- (CGFloat)slotWidth { return WXGSelectionWidth(_materialRect.size.width,[self selectionGap]); }
- (CGFloat)centerForIndex:(NSInteger)index { return CGRectGetMinX(_materialRect)+WXGSelectionCenter(_materialRect.size.width,[self selectionGap],(int)index); }
- (void)layoutSubviews {
    [super layoutSubviews];
    _materialRect=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,MAX(1,self.bounds.size.width-2*WXGCanvasPaddingX),WXGConfig.shared.height);
    CGRect outline=_morphing?_morphShape:_materialRect;
    self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:outline cornerRadius:MIN(outline.size.width,outline.size.height)*.5].CGPath;
    _fallback.frame=_materialRect; _fallback.layer.cornerRadius=_materialRect.size.height/2;
    _fallbackIcons.transform=CGAffineTransformIdentity; _fallbackIcons.frame=self.bounds;
    // FIX68: bounds and centre (the end stretch may transform the glass).
    _glass.bounds=(CGRect){CGPointZero,self.bounds.size};_glass.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    _glass.glassRect=outline;
    _morphView.frame=self.bounds;
    if(_discreteView) {
        _discreteView.frame=self.bounds;_discreteDirty=YES;
        for(WXGGlassView *piece in [_pieces copy]){piece.bounds=(CGRect){CGPointZero,self.bounds.size};piece.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));}
    }
    if (!CGSizeEqualToSize(_previousSize,self.bounds.size) || _previousInset!=[self selectionGap]) {
        _previousInset=[self selectionGap];
        _previousSize=self.bounds.size; [self cancelInteraction];
        _lensX=[self centerForIndex:_selectedIndex]; _targetX=_lensX; _velocityX=0;
        [self rebuildIcons]; [_glass invalidateBackdrop];
    }
    for (NSInteger i=0;i<4;i++) {
        CGRect r=CGRectMake(CGRectGetMinX(_materialRect)+[self selectionGap]+[self slotWidth]*i,CGRectGetMinY(_materialRect),[self slotWidth],_materialRect.size.height);
        _a11yItems[i].accessibilityFrameInContainerSpace=r;
    }
    [self updateGeometry];
    [self layoutBadges];
}
- (void)applyConfig {
    [self setNeedsLayout]; [self layoutIfNeeded]; [_glass invalidateBackdrop]; [_glass applyStyle];
    CGFloat scale=WXGCaptureScale(self.window.screen.scale?:UIScreen.mainScreen.scale)*WXGConfig.shared.lensZoom*WXGConfig.shared.barGrowth;
    BOOL nativeChanged=_previousNativeIcons!=WXGConfig.shared.useWeChatIcons;
    _previousNativeIcons=WXGConfig.shared.useWeChatIcons;
    if(nativeChanged || !CGRectEqualToRect(_iconMaterialRect,_materialRect) || fabs(_iconScale-scale)>.001 || ![_iconLayout isEqual:[self iconLayoutKey]]){[self rebuildIcons];[self layoutBadges];}
    // 离散底栏: on / off, the pieces' glass style, titles (sizes may have changed).
    [self syncDiscreteVisibility];
    BOOL light=WXGConfig.shared.dockDiscreteLight;
    for(WXGGlassView *piece in [_pieces copy]) {
        if(piece.lightweight!=light){piece.lightweight=light;[piece setNeedsLayout];}
        [piece invalidateBackdrop];[piece applyStyle];
    }
    [self loadDiscreteContent];
    if(_discreteShown){_discreteDirty=YES;[self updateDiscreteGeometry];[self layoutBadges];}
}
- (void)updateNativeIconsFromTabController:(UITabBarController *)tabs {
    _nativeTabs=tabs;
    if(WXGConfig.shared.useWeChatIcons && [_nativeIcons updateFromTabController:tabs]) [self rebuildIcons];
}
- (WXGIconJob *)iconJob {
    if(self.bounds.size.width<1 || self.bounds.size.height<1)return nil;
    WXGIconJob *job=[WXGIconJob new];job.size=self.bounds.size;
    job.scale=WXGCaptureScale(self.window.screen.scale ?: UIScreen.mainScreen.scale)*WXGConfig.shared.lensZoom*WXGConfig.shared.barGrowth;
    job.materialRect=_materialRect;job.darkInk=_darkInk;job.useNative=WXGConfig.shared.useWeChatIcons;job.selectedIndex=_selectedIndex;
    NSMutableArray<NSNumber *> *centers=[NSMutableArray array];
    for(NSInteger i=0;i<4;i++)[centers addObject:@([self centerForIndex:i])];
    job.centers=centers;
    // FIX106 D: the artwork resolved here, on the main thread (WXGDockTabArtwork
    // reads -[UIImage imageAsset]); the icon queue only draws it. (iconJob is
    // main-thread only anyway: it reads the view's bounds and window.)
    NSArray *names=@[@"微信",@"通讯录",@"发现",@"我"];
    NSArray<WXGNativeIconPair *> *items=_nativeIcons.items;
    NSMutableArray *normalArt=[NSMutableArray array],*selectedArt=[NSMutableArray array],*normalColors=[NSMutableArray array],*selectedColors=[NSMutableArray array],*titles=[NSMutableArray array];
    for(NSInteger i=0;i<4;i++) {
        WXGNativeIconPair *pair=job.useNative && i<(NSInteger)items.count?items[(NSUInteger)i]:nil;
        UIColor *normalColor=nil,*selectedColor=nil;
        UIImage *normal=WXGDockTabArtwork(pair,i,NO,_darkInk,26,&normalColor),*selected=WXGDockTabArtwork(pair,i,YES,_darkInk,26,&selectedColor);
        [normalArt addObject:normal?:(id)NSNull.null];[selectedArt addObject:selected?:(id)NSNull.null];
        [normalColors addObject:normalColor?:UIColor.grayColor];[selectedColors addObject:selectedColor?:UIColor.grayColor];
        [titles addObject:pair.title.length?pair.title:names[(NSUInteger)i]];
    }
    job.normalArt=normalArt;job.selectedArt=selectedArt;job.normalColors=normalColors;job.selectedColors=selectedColors;job.titles=titles;
    job.iconShift=[self iconShift];job.titleShift=[self titleShift];
    WXGConfig *c=WXGConfig.shared;job.titleSize=c.dockTitleSize;job.titleWeight=c.dockTitleWeight;job.bolderSelected=c.dockTitleBolderSelected;
    return job;
}
// FIX89: the icons and titles from where they were (icon centre 8 pt above
// the bar's middle, titles from 10 pt below it, a 5 pt gap between the icon's
// 26 pt box and the title): the gap opens / closes evenly about the middle of
// the two, and the offset moves both.
- (CGFloat)iconShift {WXGConfig *c=WXGConfig.shared;return c.dockIconOffset-(c.dockIconTitleGap-5)*.5;}
- (CGFloat)titleShift {WXGConfig *c=WXGConfig.shared;return c.dockIconOffset+(c.dockIconTitleGap-5)*.5;}
- (NSString *)iconLayoutKey {
    WXGConfig *c=WXGConfig.shared;
    return [NSString stringWithFormat:@"%.2f/%.2f/%.2f/%ld/%d",[self iconShift],[self titleShift],c.dockTitleSize,(long)c.dockTitleWeight,c.dockTitleBolderSelected];
}
- (UIImage *)iconImageSelected:(BOOL)selected fallback:(BOOL)fallback {
    return WXGRenderDockIcons([self iconJob],selected,fallback);
}
- (void)rebuildIcons {
    _iconLayout=[self iconLayoutKey];   // FIX89
    _iconMaterialRect=_materialRect; _iconScale=WXGCaptureScale(self.window.screen.scale?:UIScreen.mainScreen.scale)*WXGConfig.shared.lensZoom*WXGConfig.shared.barGrowth;
    WXGIconJob *job=[self iconJob];NSUInteger generation=++_iconGeneration;
    if(!_iconsReady || !job) {
        // First atlas synchronously, so the dock never shows without icons.
        UIImage *selected=WXGRenderDockIcons(job,YES,NO),*normal=WXGRenderDockIcons(job,NO,NO);
        [_glass setNormalIcons:normal selectedIcons:selected];
        _selectedAtlas=selected;_normalAtlas=normal;_iconsReady=job!=nil;
        if(_morphing)[self loadMorphContent];
    } else {
        // Later rebuilds (a tab's artwork first seen, theme, size) keep the
        // current atlas on screen until the new one is ready; newest wins.
        ++_asyncIconBuilds;__weak WXGDemoBar *weakSelf=self;
        dispatch_async(WXGDockIconQueue(),^{
            UIImage *normal=WXGRenderDockIcons(job,NO,NO),*selected=WXGRenderDockIcons(job,YES,NO);
            id<MTLTexture> normalTexture=WXGMakeIconTexture(normal),selectedTexture=WXGMakeIconTexture(selected);
            dispatch_async(dispatch_get_main_queue(),^{
                WXGDemoBar *bar=weakSelf;if(!bar || generation!=bar.iconGeneration)return;
                bar.selectedAtlas=selected;bar.normalAtlas=normal;
                if(bar.morphing)[bar loadMorphContent];
                if(normalTexture && selectedTexture)[bar.glass setNormalIconTexture:normalTexture selectedIconTexture:selectedTexture];
                else [bar.glass setNormalIcons:normal selectedIcons:selected];
            });
        });
    }
    if(!(_glass.ready && _glass.hasPresentedFrame)) _fallbackIcons.image=[self iconImageSelected:NO fallback:YES];
    NSArray *names=@[@"微信",@"通讯录",@"发现",@"我"];
    for(NSInteger i=0;i<4;i++) {
        _a11yItems[i].accessibilityTraits=UIAccessibilityTraitButton|(i==_selectedIndex?UIAccessibilityTraitSelected:0);
        NSString *title=WXGConfig.shared.useWeChatIcons && i<(NSInteger)_nativeIcons.items.count?_nativeIcons.items[i].title:nil;
        _a11yItems[i].accessibilityLabel=title.length?title:names[i];
    }
    [self loadDiscreteContent];   // 离散底栏: same artwork, theme and titles
}
// FIX21: WeChat shows a tab's selected (accent) artwork only once that tab is
// selected, sometimes after its own short icon animation. Rescan at 0.12,
// 0.35 and 0.75 s instead of waiting for the 0.8 s sampling interval, so the
// accent in the lens follows the switch; the newest selection cancels older.
- (void)rescanNativeIconsAfterSelection {
    if(!WXGConfig.shared.useWeChatIcons)return;
    NSUInteger token=++_rescanToken;
    // FIX32: after the lens animation (~0.4 s), not during it: a rescan that
    // finds a changed icon ends in an icon-atlas upload on the main thread.
    // FIX99: and never while a tap's lens is still on its way (the scan reads
    // WeChat's buttons on the main thread): it waits for the landing.
    for(NSNumber *delay in @[@.45,@.9])[self rescanNativeIconsAfter:delay.doubleValue token:token tries:0];
}
- (void)rescanNativeIconsAfter:(double)delay token:(NSUInteger)token tries:(NSInteger)tries {
    __weak WXGDemoBar *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGDemoBar *bar=weakSelf;
        if(!bar || token!=bar.rescanToken || !bar.nativeTabs)return;
        if(bar.script.phase && tries<20){[bar rescanNativeIconsAfter:.1 token:token tries:tries+1];return;}
        [bar.nativeIcons expireSampling];[bar updateNativeIconsFromTabController:bar.nativeTabs];
    });
}
- (void)selectIndex:(NSInteger)index haptic:(BOOL)haptic {
    index=(NSInteger)WXGClamp(index,0,3); BOOL changed=_selectedIndex!=index; _selectedIndex=index;
    if (!_fingerDown) _targetX=[self centerForIndex:index];
    if (changed && haptic && WXGConfig.shared.haptics) { [_feedback selectionChanged]; [_feedback prepare]; }
    if (changed) {
        if(_discreteShown){_discreteDirty=YES;++_discreteSwitches;}   // 离散底栏: the springs take it from here
        [self rescanNativeIconsAfterSelection];
        if(_morphing)[self loadMorphContent];   // FIX60: the pill follows WeChat's tab
        // All selected variants live in one texture: dragging reveals each through
        // the lens mask without replacing text or icons during the gesture.
        if(!(_glass.ready && _glass.hasPresentedFrame)) _fallbackIcons.image=[self iconImageSelected:NO fallback:YES];
        for(NSInteger i=0;i<4;i++) _a11yItems[i].accessibilityTraits=UIAccessibilityTraitButton|(i==_selectedIndex?UIAccessibilityTraitSelected:0);
    }
}
- (CGRect)closeTouchRect {return CGRectInset(_morphing?_morphShape:_materialRect,-24,-24);}
- (void)setClosePressed:(BOOL)pressed {
    CGAffineTransform target=pressed?CGAffineTransformMakeScale(.84,.84):CGAffineTransformIdentity;
    if(CGAffineTransformEqualToTransform(_closeIcon.transform,target))return;
    [UIView animateWithDuration:pressed?.12:.22 delay:0 usingSpringWithDamping:.62 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
                     animations:^{self.closeIcon.transform=target;} completion:nil];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (!_active) return NO;
    // FIX60: searching, the bar is only the round close button.
    if(_searchMode){_closeTracking=YES;[self setClosePressed:YES];if(WXGConfig.shared.haptics)[_feedback prepare];return YES;}
    if(_morphing)return NO;   // the tabs are still coming back
    if(_discreteShown)return [self beginDiscreteTracking:touch];   // 离散底栏
    ++_downCount; _previewStart=0;
    _lastTrackingReason=@"began";WXGDockTouchForget(&_trackingPoint);
    CGPoint point=[touch locationInView:self]; _initialSelected=_selectedIndex; _fingerDown=YES;_touchDownTime=CACurrentMediaTime();
    if(_travelling)[self endTravel:_travelToken];
    // FIX95: a new touch takes the lens from where it is; a landing it cut
    // short lands again if released on that tab (and holds WeChat's switch).
    // FIX98: its press and colour too (before the touch-down bump below).
    CGFloat pressBefore=WXGClamp(_press,0,1),selectionBefore=WXGClamp(_selectionShown,0,1);
    _resumeIndex=_script.phase==2?_script.index:-1;
    if(_script.phase)[self endScript];
    // FIX35: touch-down moves the lifted lens to the touched tab at once, so
    // it can be slid left and right (FIX33's lift-in-place is gone).
    _targetPress=1; _press=MAX(_press,.10); [_feedback prepare]; [self trackPoint:point];_touchDownIndex=_selectedIndex;   // FIX88
    // FIX42: a touch on another tab glides there on the release animation's
    // curve instead of the drag spring (which crossed the bar in ~0.1 s).
    // FIX43 (user): nearly distance-independent: 0.28 s x (0.85 + 0.05 x tabs),
    // i.e. 1 tab 0.252 s, 2 tabs 0.266 s, 3 tabs 0.28 s. Dragging switches to
    // the follow spring.
    CGFloat slot=MAX(1,([self centerForIndex:3]-[self centerForIndex:0])/3);
    CGFloat steps=fabs(_targetX-_lensX)/slot;
    _dragging=NO;_touchStart=point;_jumping=steps>.3;_jumpPlanEnd=0;
    if(_jumping){_jumpFromX=_lensX;_jumpStart=CACurrentMediaTime();_jumpDuration=.28*(.85+.05*MIN(steps,3.));_jumpPlanEnd=_jumpStart+_jumpDuration;}
    // FIX44: the glide runs in the render server (main-thread tween only as a
    // fallback), so a busy main thread cannot make it stutter.
    if(_jumping && [self beginGlideToIndex:_selectedIndex duration:_jumpDuration])_jumping=NO;
    // FIX95: otherwise the real lens glides there on the same curve, lifted
    // as the render-server one was, frame by frame (tick).
    // (Not with Reduce Motion, nor as a fallback of 简化透镜: there the
    // FIX42 tween runs and WeChat switches at once, as before.)
    // FIX98: slower (点按动画时长倍数 on the FIX43 time), from the press and
    // colour it had, on the script's clock (its plan too, for a travel).
    if(_jumping && !UIAccessibilityIsReduceMotionEnabled() && !WXGConfig.shared.dockTapSimpleTravel) {
        _script=WXGScriptGlide([self animationNow],_lensX,[self centerForIndex:_selectedIndex],_jumpDuration*WXGConfig.shared.dockTapDurationScale,
                               pressBefore,selectionBefore,_selectedIndex,WXGConfig.shared.dockTapLensShare);
        [self beginTapRecord:1];
        _jumpPlanEnd=_script.planEnd;
        ++_scriptGlides;_jumping=NO;
    }
    // FIX100 (user: WeChat's own tab bar switches at once; why should the two
    // fight?): WeChat's tab bar switches as the finger goes down, so its page
    // work (0.05-0.5 s of main thread, more on a first visit) comes at once.
    // 按下时 does the same, on the next run-loop turn (FIX102: no longer two
    // frames later: they showed nothing and cost 30 ms): the lens stops
    // through WeChat's work, the script is moved on by that long
    // (tabSwitchForwardedFrom:) and it glides on over the new page.
    _earlyIndex=-1;_earlySent=NO;
    if(steps>.3 && _selectedIndex!=_initialSelected && WXGConfig.shared.dockTapSwitchAtTouchDown && self.tabSwitchRequest) {
        NSInteger index=_selectedIndex;_earlyIndex=index;
        __weak WXGDemoBar *weakSelf=self;
        dispatch_async(dispatch_get_main_queue(),^{
            WXGDemoBar *bar=weakSelf;
            if(!bar || bar.earlyIndex!=index || !bar.tabSwitchRequest || !bar.fingerDown)return;
            bar.earlySent=bar.tabSwitchRequest(index);
        });
    }
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if(_closeTracking){(void)event;[self setClosePressed:CGRectContainsPoint([self closeTouchRect],[touch locationInView:self])];return YES;}
    if(!_fingerDown)return YES;   // FIX89: an interaction already cancelled (e.g. the settings long press) ignores later moves
    if(_discreteShown){[self continueDiscreteTracking:touch];return YES;}   // 离散底栏
    (void)event; ++_moveCount;CGPoint point=[touch locationInView:self];
    if(!_dragging && hypot(point.x-_touchStart.x,point.y-_touchStart.y)>10) {
        _dragging=YES;_jumping=NO;_jumpPlanEnd=0;
        if(_travelling && _travelPhase==1)[self handOverTravelToFinger];
        if(_script.phase==1){[self endScript];++_scriptDrags;_targetPress=1;}   // FIX95: the drag spring from where the glide is
    }
    [self trackPoint:point]; return YES;
}
- (void)trackPoint:(CGPoint)p {
    WXGDockTouchRemember(&_trackingPoint,p.x,p.y);
    CGFloat center=CGRectGetMidX(_materialRect);
    CGFloat x=center+(p.x-center)/MAX(1,_glass.barScale);
    _targetX=WXGClamp(x,[self centerForIndex:0],[self centerForIndex:3]);
    [self followEndStretch:x];   // FIX68
    // p.y deliberately has no influence on lens geometry.
    [self selectIndex:WXGSlot(x,CGRectGetMinX(_materialRect)+[self selectionGap],_materialRect.size.width-2*[self selectionGap],4) haptic:YES];
}
// FIX68: the finger past the last tab (beyond an 8 pt dead zone) pushes that
// end of the bar out with a rubber band; the other end stays (WXGPressStretch.h).
- (void)followEndStretch:(CGFloat)x {
    WXGConfig *c=WXGConfig.shared;
    if(!c.dockEndStretch || UIAccessibilityIsReduceMotionEnabled() || _searchMode || _morphing || !_fingerDown){[self releaseEndStretch];return;}
    CGFloat lo=[self centerForIndex:0],hi=[self centerForIndex:3],dead=8;
    int side=x>hi?1:-1;
    CGFloat over=side>0?x-hi-dead:lo-x-dead;
    _endStretch.tracking=1;
    if(over<=0 || (_endStretchSide && side!=_endStretchSide && fabs(_endStretch.x)>.5)){_endStretch.targetX=0;return;}
    CGFloat room=side>0?_endStretchRoomRight:_endStretchRoomLeft;
    double limit=room>0?MIN(c.dockEndStretchDistance,room):c.dockEndStretchDistance;
    _endStretchSide=side;_endStretch.targetX=WXGRubberBand(over,limit);
}
- (void)releaseEndStretch {_endStretch.tracking=0;_endStretch.targetX=0;}
- (void)applyEndStretch {
    WXGStretchPose m=WXGDockEndStretchPose(_endStretch.x,_endStretchSide?:1,CGRectGetMinX(_materialRect),CGRectGetMaxX(_materialRect),
                                          CGRectGetMidX(self.bounds),_materialRect.size.height);
    CGAffineTransform t=CGAffineTransformMake(m.a,m.b,m.c,m.d,m.tx,m.ty);
    if(CGAffineTransformEqualToTransform(_glass.transform,t) && (!_travelView || CGAffineTransformEqualToTransform(_travelView.transform,t)))return;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.glass.transform=t;if(self.travelView)self.travelView.transform=t;
        [CATransaction commit];
    }];
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if(_closeTracking) {
        (void)event;_closeTracking=NO;[self setClosePressed:NO];
        BOOL inside=touch && touch.phase!=UITouchPhaseCancelled && CGRectContainsPoint([self closeTouchRect],[touch locationInView:self]);
        if(inside && _searchMode && _active){if(WXGConfig.shared.haptics)[_feedback selectionChanged];[self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];}
        return;
    }
    if(_discreteShown && _fingerDown){[self endDiscreteTracking:touch event:event];return;}   // 离散底栏
    ++_trackingEnds;if(!touch)++_nilTrackingEnds;
    [self releaseEndStretch];   // FIX68
    if(!_fingerDown){_lastTrackingReason=@"end_without_tracking";WXGDockTouchForget(&_trackingPoint);return;}
    BOOL cancelledPhase=touch.phase==UITouchPhaseCancelled,confirmedEnd=touch!=nil;
    if(!touch)for(UITouch *candidate in event.allTouches) {
        UIView *target=candidate.view;
        if(target!=self && ![target isDescendantOfView:self])continue;
        if(candidate.phase==UITouchPhaseCancelled){cancelledPhase=YES;break;}
        if(candidate.phase==UITouchPhaseEnded)confirmedEnd=YES;
    }
    BOOL inactive=!_active || !self.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    // UIKit also uses nil when cancelTracking calls through. A saved point may
    // complete only an actual ended event, never an ambiguous nil cancellation.
    BOOL cancelled=cancelledPhase || inactive || !confirmedEnd;
    CGPoint supplied=touch?[touch locationInView:self]:CGPointZero;
    BOOL hasPoint=WXGDockTouchResolve(&_trackingPoint,touch!=nil,cancelled,supplied.x,supplied.y);
    CGPoint p=CGPointMake(_trackingPoint.x,_trackingPoint.y);
    BOOL inside=hasPoint && CGRectContainsPoint(CGRectInset(_materialRect,-35,-45),p);
    _fingerDown=NO;_jumping=NO;
    // FIX100: WeChat already switched at the touch: a release outside (or a
    // touch the system ended) stays on that tab, as WeChat's own bar does.
    BOOL keptEarly=!inside && _earlySent && _earlyIndex>=0;
    if(keptEarly){inside=YES;[self selectIndex:_earlyIndex haptic:NO];}
    if (!inside) [self selectIndex:_initialSelected haptic:NO];
    _targetX=[self centerForIndex:_selectedIndex]; _targetPress=0;
    _lastTrackingReason=inactive?@"ended_inactive":(cancelledPhase?@"ended_cancelled":(!confirmedEnd?@"nil_end_unconfirmed":
        (inside?(touch?@"committed":@"committed_saved_point"):(hasPoint?@"ended_outside":@"ended_without_point"))));
    if(keptEarly)_lastTrackingReason=@"kept_touch_down_switch";
    WXGDockTouchForget(&_trackingPoint);
    // FIX88: a touch that ends without switching is logged with its reason.
    // (A tap on the tab already selected is not one; a press that began on
    // another tab and ends back on the selected one is.)
    if((!inside || (_selectedIndex==_initialSelected && _touchDownIndex!=_initialSelected)) && ++_uncommittedEnds<=20)
        WXGLog(@"底栏：松手没有切换（%@，按下 %.2f s，按在第 %ld 个，松手时第 %ld 个，原来第 %ld 个）",_lastTrackingReason,CACurrentMediaTime()-_touchDownTime,
               (long)_touchDownIndex+1,(long)_selectedIndex+1,(long)_initialSelected+1);
    // FIX44: a touch-down glide still in the render server drops into the pill
    // when released on its own (new) tab; otherwise the per-frame lens takes
    // over from where the glide is on screen.
    if(_travelling && _travelPhase==1 && !(inside && _selectedIndex==_travelIndex && _selectedIndex!=_initialSelected))[self cancelGlide];
    // FIX95: the scripted glide likewise lands on its tab, or stops here.
    BOOL scriptOnTab=_script.phase==1 && inside && _selectedIndex==_script.index && _selectedIndex!=_initialSelected;
    if(_script.phase==1 && !scriptOnTab)[self endScript];
    if(inside) {
        ++_trackingCommits;_lastCommittedIndex=_selectedIndex;
        // FIX33: the move is in the render server and committed BEFORE WeChat
        // switches pages, so WeChat's work cannot stall the animation.
        // FIX95: the real lens instead holds WeChat's switch until it is down
        // (the host waits for holdsTabSwitch), so it never stalls either.
        // FIX98: until the moment chosen (切换页面的时机: at the release, when
        // the lens has nearly arrived, or once it is down); a stall after it
        // only pauses the lens (the script's clock).
        if(_travelling && _travelPhase==1)[self dropTravel];
        else if(scriptOnTab){WXGScriptDrop(&_script,[self animationNow],WXGConfig.shared.dockTapDropDuration);++_scriptDrops;}
        else if(_selectedIndex!=_initialSelected || _resumeIndex==_selectedIndex)[self beginTravelToIndex:_selectedIndex];
        _switchedAtTouchDown=_earlySent && _earlyIndex==_selectedIndex;   // FIX100
        [self sendActionsForControlEvents:UIControlEventValueChanged];
        _switchedAtTouchDown=NO;
    }
    _resumeIndex=-1;_earlyIndex=-1;_earlySent=NO;
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    if(_closeTracking){_closeTracking=NO;[self setClosePressed:NO];return;}
    ++_trackingCancels;_lastTrackingReason=@"tracking_cancelled";
    if(_fingerDown && ++_uncommittedEnds<=20)WXGLog(@"底栏：触摸被系统取消（按下 %.2f s），没有切换",CACurrentMediaTime()-_touchDownTime);   // FIX88
    // FIX100: a switch WeChat already made at the touch stays.
    if (_fingerDown) { _fingerDown=NO; [self selectIndex:_earlySent && _earlyIndex>=0?_earlyIndex:_initialSelected haptic:NO]; }
    [self cancelInteraction];
}
- (void)ensureTravelLayers {
    if(_travelView)return;
    _travelView=[[UIView alloc]initWithFrame:self.bounds];_travelView.userInteractionEnabled=NO;_travelView.hidden=YES;
    [self insertSubview:_travelView aboveSubview:_glass];
    // Unselected icons, masked by the moving hole image.
    _travelNormalIcons=[CALayer layer];_travelHole=[CALayer layer];
    _travelHole.contents=(__bridge id)WXGTravelHoleImage().CGImage;
    _travelNormalIcons.mask=_travelHole;
    // The lens clips everything in it: refracting backdrop (inserted per
    // travel), pill tint and the magnified selected icons (FIX44: no mask).
    _travelLens=[CALayer layer];_travelLens.masksToBounds=YES;_travelLens.cornerCurve=kCACornerCurveContinuous;
    _travelTint=[CALayer layer];_travelTint.anchorPoint=CGPointZero;_travelTint.position=CGPointZero;
    _travelIconZoom=[CALayer layer];_travelIconImage=[CALayer layer];_travelIconImage.anchorPoint=CGPointZero;
    [_travelIconZoom addSublayer:_travelIconImage];
    // FIX88: the bar seen through the lens (bands of the veil, its outline),
    // under the selection tint and the icons; paths in the lens's own space.
    _travelVeil=[CALayer layer];_travelVeil.anchorPoint=CGPointZero;_travelVeil.position=CGPointZero;_travelVeil.hidden=YES;
    _travelVeilBands=[NSMutableArray array];
    NSMutableArray *outlines=[NSMutableArray array];
    for(int i=0;i<2;i++){CAShapeLayer *line=[CAShapeLayer layer];line.fillColor=nil;line.hidden=YES;[_travelVeil addSublayer:line];[outlines addObject:line];}
    _travelOutlines=outlines;
    [_travelLens addSublayer:_travelVeil];
    [_travelLens addSublayer:_travelTint];[_travelLens addSublayer:_travelIconZoom];
    [_travelView.layer addSublayer:_travelNormalIcons];[_travelView.layer addSublayer:_travelLens];
}
- (NSArray<CALayer *> *)travelLayers {
    NSMutableArray *layers=[NSMutableArray arrayWithObjects:_travelLens,_travelTint,_travelIconZoom,_travelIconImage,_travelNormalIcons,_travelHole,nil];
    [layers addObjectsFromArray:_travelOutlines];
    [layers addObjectsFromArray:_travelVeilBands];
    return layers;
}
- (NSArray<CALayer *> *)travelShapeLayers {
    NSMutableArray *layers=[NSMutableArray arrayWithObjects:_travelLens,_travelTint,nil];
    for(UIView *v in _travelBackdrops)[layers addObject:v.layer];
    return layers;
}
- (NSString *)travelBackdropKeyForSize:(CGSize)size {
    WXGConfig *c=WXGConfig.shared;WXGScopeOptics dock=[c opticsForDock:YES];   // FIX58: the dock's own resting optics
    return [NSString stringWithFormat:@"%.1fx%.1f/%d/%.3f/%.3f/%.2f/%.3f/%.2f/%.2f/%.2f/%.3f/%.3f/%.2f/%.2f/%.3f",size.width,size.height,c.syncDispersion,
        c.lensRefraction,c.lensDispersion,c.lensEdgeWidth,c.lensZoom,c.lensBlur,dock.blur,c.syncBlurScale,dock.refraction,dock.dispersion,dock.edgeWidth,
        c.lensDispersionWidth,c.lensDispersionTopRatio];
}
// FIX88: the capture group of the travel backdrops: the dock glass's (the
// lens then sees the page without the dock's veil, as the real lens does) or
// their own. Set per travel, so the prewarm (drawn at opacity 0.001) never
// joins the glass's group.
- (void)applyTravelGroup:(NSString *)group {
    NSString *name=group.length?group:@"wxg.travel";
    for(UIView *v in _travelBackdrops) {
        @try {
            id current=[v.layer valueForKey:@"groupName"];
            if(![current isEqual:name])[v.layer setValue:name forKey:@"groupName"];
        } @catch(__unused NSException *error) {}
    }
}
// FIX88: the veil the tap animation draws in its lens: the dock glass's own
// veil colour and edge fade (WXGTravelVeilBands), and the bar's outline as
// the real lens draws it. Only when the travel backdrops share the glass's
// capture (the page without the veil); otherwise they show the veil already.
- (void)loadTravelVeil {
    NSString *group=_glass.backdropGroupName;UIColor *veil=_glass.veilColor;
    _travelVeilOn=group.length && veil;
    _travelVeil.hidden=!_travelVeilOn;
    if(!_travelVeilOn){_travelVeilCount=0;return;}
    WXGConfig *c=WXGConfig.shared;
    BOOL fade=c.dockMaterialEdgeFadeEnabled && c.dockMaterialEdgeFade>.01;
    CGFloat r=0,g=0,b=0,a=0;[veil getRed:&r green:&g blue:&b alpha:&a];
    float depths[8],alphas[8];
    int k=WXGTravelVeilBands((float)a,fade?(float)c.dockMaterialEdgeFade:0.f,8,depths,alphas);
    if(!_travelVeilDepths)_travelVeilDepths=calloc(8,sizeof(float));
    memcpy(_travelVeilDepths,depths,sizeof(float)*(size_t)k);_travelVeilCount=k;
    UIColor *solid=[UIColor colorWithRed:r green:g blue:b alpha:1];   // held: its CGColor lives as long as it does
    for(NSInteger i=0;i<8;i++) {
        if(i>=(NSInteger)_travelVeilBands.count) {
            CAShapeLayer *band=[CAShapeLayer layer];band.strokeColor=nil;
            [_travelVeil insertSublayer:band below:_travelOutlines.firstObject];[_travelVeilBands addObject:band];
        }
        CAShapeLayer *band=_travelVeilBands[i];
        band.hidden=i>=k;band.fillColor=solid.CGColor;band.opacity=i<k?alphas[i]:0;
    }
    // FIX89: each line the real lens draws (the iOS 27-like rim: one per
    // highlight, the second over the first).
    NSArray<UIColor *> *colors=_glass.lensOutlineColors;NSArray<NSNumber *> *widths=_glass.lensOutlineWidths;
    for(NSUInteger i=0;i<_travelOutlines.count;i++) {
        CAShapeLayer *line=_travelOutlines[i];
        UIColor *color=i<colors.count?colors[i]:nil;CGFloat width=i<widths.count?widths[i].doubleValue:0;
        line.hidden=!color || width<.01 || CGColorGetAlpha(color.CGColor)<.002;
        line.strokeColor=color.CGColor;line.lineWidth=line.hidden?0:width;
    }
}
// Where the travel lens's centre is at `time` (the glide's curve).
- (CGPoint)travelCentreAt:(CFTimeInterval)time {
    double u=WXGClamp((time-_travelMoveStart)/MAX(.05,_travelMoveDuration),0,1),e=WXGBezierEase(u,.40,0,.30,1);
    return CGPointMake(_travelMoveFrom.x+(_travelMoveTo.x-_travelMoveFrom.x)*e,_travelMoveFrom.y+(_travelMoveTo.y-_travelMoveFrom.y)*e);
}
// The veil path for one keyframe, in the lens's own space: the bar (grown by
// `scale` about its centre) inset under the lens, moved in by `extra`.
- (CGPathRef)newTravelVeilPathForLens:(CGSize)size centre:(CGPoint)centre press:(CGFloat)press scale:(CGFloat)scale extra:(CGFloat)extra {
    enum {N=48};float points[4*N];
    CGFloat bx=CGRectGetMidX(_materialRect),by=CGRectGetMidY(_materialRect),H=_materialRect.size.height;
    float x0=(float)(centre.x-size.width*.5-2),x1=(float)(centre.x+size.width*.5+2);
    // FIX94: the bar following the lens' rim, as the shader draws it.
    WXGConfig *c=WXGConfig.shared;WXGScopeOptics dock=[c opticsForDock:YES];
    WXGLensFollow follow={(float)(dock.edgeWidth+(c.lensEdgeWidth-dock.edgeWidth)*WXGClamp(press,0,1)),(float)c.lensTopEdgeRatio,(float)c.lensEdgeSharpness,
                          c.lensBarFollow?(float)c.lensBarMargin:0.f};
    WXGTravelVeilOutline((float)bx,(float)by,(float)(_materialRect.size.width*scale),(float)(H*scale),(float)centre.x,(float)centre.y,
                         (float)size.width,(float)size.height,(float)(H*scale),(float)press,(float)c.bodyPinch,(float)extra,x0,x1,N,points,&follow);
    CGFloat ox=centre.x-size.width*.5,oy=centre.y-size.height*.5;
    CGMutablePathRef path=CGPathCreateMutable();
    for(int i=0;i<2*N;i++) {
        CGFloat x=points[2*i]-ox,y=points[2*i+1]-oy;
        if(i)CGPathAddLineToPoint(path,NULL,x,y);else CGPathMoveToPoint(path,NULL,x,y);
    }
    CGPathCloseSubpath(path);
    return path;
}
// FIX88: the bar grows with the lift (as the real lens's press does): the
// dock glass, the unselected icons and the badges, scaled about the bar's
// centre; the icons' hole stays under the lens.
- (CATransform3D)travelScaleTransform:(CGFloat)s forLayer:(CALayer *)layer {
    CGPoint centre=CGPointMake(CGRectGetMidX(_materialRect),CGRectGetMidY(_materialRect));
    CGPoint anchor=CGPointMake(layer.bounds.size.width*layer.anchorPoint.x,layer.bounds.size.height*layer.anchorPoint.y);
    CATransform3D m=CATransform3DMakeScale(s,s,1);m.m41=(1-s)*(centre.x-anchor.x);m.m42=(1-s)*(centre.y-anchor.y);
    return m;
}
// The bar's growth at this press, as the per-frame layout scales it.
- (CGFloat)travelBarScaleForPress:(CGFloat)press {
    WXGConfig *c=WXGConfig.shared;
    if(UIAccessibilityIsReduceMotionEnabled() || c.barGrowth<=1.0005)return 1;
    return 1+(c.barGrowth-1)*WXGClamp(press,0,1);
}
// Where a keyframe animation (these key times, one timing function per
// segment, linear values) is at u (0..1 of its duration): its segment and the
// eased fraction within it, exactly as Core Animation evaluates it.
static void WXGKeyframeAt(NSArray<NSNumber *> *times,NSArray<CAMediaTimingFunction *> *timing,double u,NSUInteger *segment,double *fraction) {
    NSUInteger n=times.count,i=0;
    if(n<2){*segment=0;*fraction=0;return;}
    while(i+2<n && u>times[i+1].doubleValue)i++;
    double t0=times[i].doubleValue,t1=times[i+1].doubleValue,local=t1>t0+1e-9?WXGClamp((u-t0)/(t1-t0),0,1):1;
    float a[2]={0,0},b[2]={1,1};
    CAMediaTimingFunction *f=i<timing.count?timing[i]:nil;
    if(f){[f getControlPointAtIndex:1 values:a];[f getControlPointAtIndex:2 values:b];}
    *segment=i;*fraction=WXGBezierEase(local,a[0],a[1],b[0],b[1]);
}
// FIX88: everything that follows both the lens's shape and its glide, in
// dense linear keyframes (every 1/60 s) computed here from the same curves,
// so nothing drifts between keyframes: the bar's growth (dock glass, the
// unselected icons and their hole, the badges), the selected icons' zoom
// (the lens zoom on the grown bar), and the veil's bands and outline.
- (void)animateTravelExtras:(NSArray<NSValue *> *)sizes press:(NSArray<NSNumber *> *)press times:(NSArray<NSNumber *> *)times
                     timing:(NSArray<CAMediaTimingFunction *> *)timing duration:(CFTimeInterval)duration {
    WXGConfig *c=WXGConfig.shared;CFTimeInterval now=CACurrentMediaTime();
    CGPoint barCentre=CGPointMake(CGRectGetMidX(_materialRect),CGRectGetMidY(_materialRect));
    CGFloat zoomGain=c.lensZoom-1;
    BOOL grow=[self travelBarScaleForPress:1]>1.0005;
    NSInteger count=MAX(2,MIN(121,(NSInteger)ceil(MAX(0,duration)*60)+1));
    NSMutableArray *keyTimes=[NSMutableArray array],*glassScale=[NSMutableArray array],*iconScale=[NSMutableArray array],*holeShift=[NSMutableArray array];
    NSMutableArray *holeSizes=[NSMutableArray array],*zooms=[NSMutableArray array],*iconShift=[NSMutableArray array],*scales=[NSMutableArray array];
    NSMutableArray<NSMutableArray *> *bandPaths=[NSMutableArray array],*outlinePaths=[NSMutableArray array];
    for(NSUInteger k=0;k<_travelOutlines.count;k++)[outlinePaths addObject:[NSMutableArray array]];
    for(NSInteger k=0;k<_travelVeilCount;k++)[bandPaths addObject:[NSMutableArray array]];
    for(NSInteger f=0;f<count;f++) {
        double u=(double)f/(double)(count-1),e=0;NSUInteger i=0;
        WXGKeyframeAt(times,timing,u,&i,&e);
        NSUInteger j=MIN(i+1,sizes.count-1);
        CGSize a=sizes[i].CGSizeValue,b=sizes[j].CGSizeValue;
        CGSize size=CGSizeMake(a.width+(b.width-a.width)*e,a.height+(b.height-a.height)*e);
        CGFloat p=WXGClamp(press[i].doubleValue+(press[j].doubleValue-press[i].doubleValue)*e,0,1),s=[self travelBarScaleForPress:p];
        CGPoint lens=[self travelCentreAt:now+u*duration];
        [keyTimes addObject:@(u)];[scales addObject:@(s)];
        [glassScale addObject:[NSValue valueWithCATransform3D:[self travelScaleTransform:s forLayer:_glass.layer]]];
        [iconScale addObject:[NSValue valueWithCATransform3D:[self travelScaleTransform:s forLayer:_travelNormalIcons]]];
        [holeShift addObject:[NSValue valueWithCGPoint:CGPointMake((lens.x-barCentre.x)*(1/s-1),(lens.y-barCentre.y)*(1/s-1))]];
        [holeSizes addObject:[NSValue valueWithCGSize:CGSizeMake(size.width*WXG_HOLE_KW/s,size.height*WXG_HOLE_KH/s)]];
        [zooms addObject:@((1+p*zoomGain)*s)];
        [iconShift addObject:[NSValue valueWithCGPoint:CGPointMake((lens.x-barCentre.x)*(1-1/s),(lens.y-barCentre.y)*(1-1/s))]];
        for(NSInteger k=0;k<_travelVeilCount;k++) {
            CGPathRef path=[self newTravelVeilPathForLens:size centre:lens press:p scale:s extra:_travelVeilDepths[k]*s];
            [bandPaths[k] addObject:(__bridge id)path];CGPathRelease(path);
        }
        for(NSUInteger k=0;_travelVeilOn && k<_travelOutlines.count;k++) {
            CAShapeLayer *line=_travelOutlines[k];if(line.hidden)continue;
            CGPathRef path=[self newTravelVeilPathForLens:size centre:lens press:p scale:s extra:line.lineWidth*.5];
            [outlinePaths[k] addObject:(__bridge id)path];CGPathRelease(path);
        }
    }
    CAKeyframeAnimation *(^frames)(NSString *,NSArray *,BOOL)=^CAKeyframeAnimation *(NSString *path,NSArray *values,BOOL additive) {
        CAKeyframeAnimation *a=[CAKeyframeAnimation animationWithKeyPath:path];
        a.values=values;a.keyTimes=keyTimes;a.calculationMode=kCAAnimationLinear;a.duration=MAX(duration,1e-3);a.additive=additive;
        a.fillMode=kCAFillModeForwards;a.removedOnCompletion=NO;return a;
    };
    [_travelIconZoom addAnimation:frames(@"transform.scale",zooms,NO) forKey:@"zoom"];
    [_travelHole addAnimation:frames(@"bounds.size",holeSizes,NO) forKey:@"holeSize"];
    if(grow) {
        [_glass.layer addAnimation:frames(@"transform",glassScale,YES) forKey:@"wxg.travelScale"];
        [_travelNormalIcons addAnimation:frames(@"transform",iconScale,YES) forKey:@"wxg.travelScale"];
        [_travelHole addAnimation:frames(@"position",holeShift,YES) forKey:@"wxg.travelScale"];
        [_travelIconImage addAnimation:frames(@"position",iconShift,YES) forKey:@"wxg.travelScale"];
        for(UILabel *badge in _badges) {
            if(badge.hidden)continue;
            // layoutBadges scales the badge's top-left corner about the bar's centre.
            NSMutableArray *shift=[NSMutableArray array];CGRect frame=badge.frame;CGPoint b=frame.origin;
            for(NSNumber *value in scales) {
                CGFloat s=value.doubleValue;
                [shift addObject:[NSValue valueWithCGPoint:CGPointMake((b.x-barCentre.x)*(s-1),(b.y-barCentre.y)*(s-1))]];
            }
            [badge.layer addAnimation:frames(@"position",shift,YES) forKey:@"wxg.travelScale"];
        }
    }
    for(NSInteger k=0;k<_travelVeilCount;k++) {
        CAShapeLayer *band=_travelVeilBands[k];
        [band addAnimation:frames(@"path",bandPaths[k],NO) forKey:@"veil"];band.path=(__bridge CGPathRef)bandPaths[k].lastObject;
    }
    for(NSUInteger k=0;k<_travelOutlines.count;k++) {
        if(!_travelVeilOn || !outlinePaths[k].count)continue;
        CAShapeLayer *line=_travelOutlines[k];
        [line addAnimation:frames(@"path",outlinePaths[k],NO) forKey:@"veil"];line.path=(__bridge CGPathRef)outlinePaths[k].lastObject;
    }
}
- (void)removeTravelScale {
    [_glass.layer removeAnimationForKey:@"wxg.travelScale"];
    for(UILabel *badge in _badges)[badge.layer removeAnimationForKey:@"wxg.travelScale"];
}
- (void)loadTravelColors {
    WXGConfig *c=WXGConfig.shared;BOOL light=_darkInk;
    _travelSelection=WXGColor(light?c.selectionHex:c.darkSelectionHex)?:[UIColor colorWithWhite:light?.85:.35 alpha:1];
    _travelPillAlpha=CGColorGetAlpha(_travelSelection.CGColor)*c.selectionOpacity;
    _travelRim=WXGColor(light?c.lensRimHex:c.darkLensRimHex)?:UIColor.whiteColor;
    _travelRimAlpha=CGColorGetAlpha(_travelRim.CGColor)*(light?c.lensRimOpacity:c.darkLensRimOpacity);
    _travelLens.borderWidth=light?c.lensBorderWidth:c.darkLensBorderWidth;
}
// The selection colour is clear at the lift (0.9) and back at rest; rim and
// zoom follow the press, as on the real lens.
- (UIColor *)travelTintForPress:(CGFloat)press {return [_travelSelection colorWithAlphaComponent:_travelPillAlpha*(1-WXGClamp(press/.90,0,1))];}
- (UIColor *)travelRimForPress:(CGFloat)press {return [_travelRim colorWithAlphaComponent:_travelRimAlpha*WXGPressedBorderAlpha((float)press)];}
- (CGSize)travelSizeForPress:(CGFloat)press {
    CGFloat t=WXGClamp(press/.90,0,1.15);
    return CGSizeMake(_travelRestSize.width+(_travelLiftSize.width-_travelRestSize.width)*t,_travelRestSize.height+(_travelLiftSize.height-_travelRestSize.height)*t);
}
- (CGFloat)travelPressForSize:(CGSize)size {
    CGFloat span=_travelLiftSize.height-_travelRestSize.height;
    if(fabs(span)<.5)return _travelStartPress;
    return WXGClamp(.90*(size.height-_travelRestSize.height)/span,0,1);
}
// Model (final) values of everything that follows the lens shape.
- (void)setTravelShapeModel:(CGSize)size press:(CGFloat)press {
    for(CALayer *layer in [self travelShapeLayers])layer.bounds=(CGRect){CGPointZero,size};
    _travelLens.cornerRadius=size.height*.5;
    _travelLens.borderColor=[self travelRimForPress:press].CGColor;
    _travelTint.backgroundColor=[self travelTintForPress:press].CGColor;
    // FIX88: on the grown bar (s): the zoom on top of it, the hole in the
    // icons' own (unscaled) space.
    CGFloat s=[self travelBarScaleForPress:press],z=(1+press*(WXGConfig.shared.lensZoom-1))*s;
    _travelIconZoom.position=CGPointMake(size.width*.5,size.height*.5);_travelIconZoom.transform=CATransform3DMakeScale(z,z,1);
    _travelHole.bounds=(CGRect){CGPointZero,CGSizeMake(size.width*WXG_HOLE_KW/s,size.height*WXG_HOLE_KH/s)};
}
// One clock for the lens shape: size, corner, pill tint, rim, zoom, hole.
- (void)animateTravelSizes:(NSArray<NSValue *> *)sizes press:(NSArray<NSNumber *> *)press times:(NSArray<NSNumber *> *)times
                    timing:(NSArray<CAMediaTimingFunction *> *)timing duration:(CFTimeInterval)duration {
    NSMutableArray *radii=[NSMutableArray array],*tints=[NSMutableArray array],*rims=[NSMutableArray array],*centres=[NSMutableArray array];
    for(NSUInteger i=0;i<sizes.count;i++) {
        CGSize size=sizes[i].CGSizeValue;CGFloat p=press[i].doubleValue;
        [radii addObject:@(size.height*.5)];
        [tints addObject:(__bridge id)[self travelTintForPress:p].CGColor];
        [rims addObject:(__bridge id)[self travelRimForPress:p].CGColor];
        [centres addObject:[NSValue valueWithCGPoint:CGPointMake(size.width*.5,size.height*.5)]];
    }
    CAKeyframeAnimation *(^frames)(NSString *,NSArray *)=^CAKeyframeAnimation *(NSString *path,NSArray *values) {
        CAKeyframeAnimation *a=[CAKeyframeAnimation animationWithKeyPath:path];
        a.values=values;a.keyTimes=times;a.timingFunctions=timing;a.duration=duration;return a;
    };
    for(CALayer *layer in [self travelShapeLayers])[layer addAnimation:frames(@"bounds.size",sizes) forKey:@"size"];
    [_travelLens addAnimation:frames(@"cornerRadius",radii) forKey:@"radius"];
    [_travelTint addAnimation:frames(@"backgroundColor",tints) forKey:@"tint"];
    [_travelLens addAnimation:frames(@"borderColor",rims) forKey:@"rim"];
    [_travelIconZoom addAnimation:frames(@"position",centres) forKey:@"centre"];
    [self setTravelShapeModel:sizes.lastObject.CGSizeValue press:press.lastObject.doubleValue];
    [self animateTravelExtras:sizes press:press times:times timing:timing duration:duration];   // FIX88: zoom, hole size, growth, veil
}
// One glide for everything that moves: lens, hole (+), selected icons (-).
- (void)animateTravelMoveFrom:(CGPoint)c0 to:(CGPoint)c1 duration:(CFTimeInterval)duration {
    CAMediaTimingFunction *glide=[CAMediaTimingFunction functionWithControlPoints:.40 :0 :.30 :1];
    CABasicAnimation *(^move)(CGPoint,CGPoint)=^CABasicAnimation *(CGPoint a,CGPoint b) {
        CABasicAnimation *m=[CABasicAnimation animationWithKeyPath:@"position"];
        m.fromValue=[NSValue valueWithCGPoint:a];m.toValue=[NSValue valueWithCGPoint:b];m.duration=MAX(.05,duration);m.timingFunction=glide;return m;
    };
    _travelMoveStart=CACurrentMediaTime();_travelMoveDuration=MAX(.05,duration);_travelMoveFrom=c0;_travelMoveTo=c1;   // FIX88
    [_travelLens addAnimation:move(c0,c1) forKey:@"move"];
    [_travelHole addAnimation:move(c0,c1) forKey:@"move"];
    [_travelIconImage addAnimation:move(CGPointMake(-c0.x,-c0.y),CGPointMake(-c1.x,-c1.y)) forKey:@"move"];
    _travelLens.position=c1;_travelHole.position=c1;_travelIconImage.position=CGPointMake(-c1.x,-c1.y);
}
// FIX33-44: the tap animation in the render server. While it runs, the
// dock's Metal overlay is hidden (and no longer drawn), its lens suppressed;
// these layers draw the unselected icons (hole under the lens) and a lens that
// refracts what is really beneath it, holding WeChat's selected icons.
// Shared set-up (call inside a transaction): the per-frame dock rests at the
// target and the travel layers start where the real lens is.
- (BOOL)prepareTravelToIndex:(NSInteger)index {
    if(!WXGConfig.shared.dockTapSimpleTravel || UIAccessibilityIsReduceMotionEnabled() || !_glass.ready || !_glass.hasPresentedFrame ||
       !_selectedAtlas.CGImage || !_normalAtlas.CGImage || CGRectIsEmpty(_materialRect) || !self.window)return NO;
    CFTimeInterval setupStart=CACurrentMediaTime();
    WXGConfig *c=WXGConfig.shared;
    float w=(float)_materialRect.size.width,h=(float)_materialRect.size.height,gap=(float)[self selectionGap];
    CGFloat minX=_materialRect.origin.x,minY=_materialRect.origin.y;
    CGFloat fromX=_lensX,toX=[self centerForIndex:index],fromPress=WXGClamp(_press,0,1);
    WXGDockGeometry from=WXGDockLayout(w,h,gap,(float)(fromX-minX),(float)fromPress,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    WXGDockGeometry rest=WXGDockLayout(w,h,gap,(float)(toX-minX),0,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    // FIX88: lifted with the bar's growth, as the per-frame lens is at 0.9
    // (a held press hands over to it without a jump in size).
    WXGDockGeometry lift=WXGDockLayout(w,h,gap,(float)(toX-minX),.90f,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    WXGDockGeometry mesh=WXGDockLayout(w,h,gap,w*.5f,.90f,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    _travelFrom=CGPointMake(minX+from.lensX+from.lensWidth*.5,minY+from.lensY+from.lensHeight*.5);
    _travelTo=CGPointMake(minX+rest.lensX+rest.lensWidth*.5,minY+rest.lensY+rest.lensHeight*.5);
    _travelStartSize=CGSizeMake(from.lensWidth,from.lensHeight);
    _travelRestSize=CGSizeMake(rest.lensWidth,rest.lensHeight);
    _travelLiftSize=CGSizeMake(lift.lensWidth,lift.lensHeight);
    _travelStartPress=fromPress;_travelIndex=index;
    CGSize meshSize=CGSizeMake(mesh.lensWidth,mesh.lensHeight);NSString *backdropKey=[self travelBackdropKeyForSize:meshSize];

    _travelling=YES;++_travels;
    _lensX=toX;_targetX=toX;_velocityX=0;_press=0;_pressVelocity=0;_targetPress=0;_elasticMotion=(WXGElasticMotion){0};
    _glass.lensSuppressed=YES;_glass.overlayHidden=YES;[self updateGeometry];
    [self ensureTravelLayers];[self loadTravelColors];
    _travelView.bounds=(CGRect){CGPointZero,self.bounds.size};_travelView.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));_travelView.hidden=NO;
    // Nothing holding a backdrop is ever faded (FIX37: a backdrop under an
    // opacity below 1 renders as a flat dark fill).
    [_travelView.layer removeAllAnimations];_travelView.layer.opacity=1;
    for(UIView *old in _travelBackdrops)[old.layer removeFromSuperlayer];
    if(!_travelBackdrops.count || ![backdropKey isEqual:_travelBackdropKey]){_travelBackdrops=WXGMakeTravelLensBackdrops(meshSize,.90,_glass.backdropGroupName);_travelBackdropKey=backdropKey;}
    [self applyTravelGroup:_glass.backdropGroupName];   // FIX88: built (or prewarmed) in their own group
    unsigned depth=0;
    for(UIView *v in _travelBackdrops) {
        CALayer *layer=v.layer;[layer removeAllAnimations];layer.anchorPoint=CGPointZero;layer.position=CGPointZero;layer.opacity=1;
        [_travelLens insertSublayer:layer atIndex:depth++];
    }
    for(CALayer *layer in [self travelLayers])[layer removeAllAnimations];
    [self removeTravelScale];[self loadTravelVeil];   // FIX88
    _travelIconImage.contents=(__bridge id)_selectedAtlas.CGImage;_travelIconImage.contentsScale=_selectedAtlas.scale;
    _travelIconImage.bounds=(CGRect){CGPointZero,self.bounds.size};
    _travelNormalIcons.contents=(__bridge id)_normalAtlas.CGImage;_travelNormalIcons.contentsScale=_normalAtlas.scale;
    _travelNormalIcons.frame=self.bounds;
    [self setTravelShapeModel:_travelStartSize press:fromPress];
    _travelLens.position=_travelFrom;_travelHole.position=_travelFrom;_travelIconImage.position=CGPointMake(-_travelFrom.x,-_travelFrom.y);
    _travelSetupMS=MAX(_travelSetupMS,(CACurrentMediaTime()-setupStart)*1000);
    return YES;
}
// FIX44 phase 1, at touch-down on another tab: the glide runs in the render
// server too (it was a main-thread tween that stuttered whenever WeChat was
// busy, e.g. right after launch). The lens lifts to 90% and is held lifted at
// the target until the finger lifts (dropTravel) or drags (hand-over).
- (BOOL)beginGlideToIndex:(NSInteger)index duration:(CFTimeInterval)duration {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(![self prepareTravelToIndex:index]){[CATransaction commit];return NO;}
    _travelPhase=1;_travelPlanEnd=CACurrentMediaTime()+duration;++_glides;
    CGFloat p0=_travelStartPress,lifted=MAX(.90,p0);CGSize held=[self travelSizeForPress:lifted];
    [self animateTravelMoveFrom:_travelFrom to:_travelTo duration:duration];   // FIX88: first (the veil follows it)
    [self animateTravelSizes:@[[NSValue valueWithCGSize:_travelStartSize],[NSValue valueWithCGSize:held],[NSValue valueWithCGSize:held]]
                       press:@[@(p0),@(lifted),@(lifted)] times:@[@0,@.55,@1]
                      timing:@[[CAMediaTimingFunction functionWithControlPoints:.42 :0 :.58 :1],[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]]
                    duration:duration];
    [CATransaction commit];
    [CATransaction flush];   // in the render server before anything else runs
    return YES;
}
// Release on the glide's tab: drop into the pill, landing on the plan (at
// least 0.1 s from now); the glide itself keeps running.
- (void)dropTravel {
    if(!_travelling || _travelPhase!=1)return;
    _travelPhase=2;++_drops;
    CFTimeInterval now=CACurrentMediaTime();
    CFTimeInterval land=MAX(now+.10,_travelPlanEnd),dropStart=land-.09,end=land+.05,duration=end-now;
    CALayer *shown=_travelLens.presentationLayer?:_travelLens;
    CGSize current=shown.bounds.size;CGFloat p=[self travelPressForSize:current],lifted=MAX(.90,_travelStartPress);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    [self animateTravelSizes:@[[NSValue valueWithCGSize:current],[NSValue valueWithCGSize:[self travelSizeForPress:lifted]],
                               [NSValue valueWithCGSize:_travelRestSize],[NSValue valueWithCGSize:_travelRestSize]]
                       press:@[@(p),@(lifted),@0,@0]
                       times:@[@0,@((dropStart-now)/duration),@((land-now)/duration),@1]
                      timing:@[[CAMediaTimingFunction functionWithControlPoints:.42 :0 :.58 :1],
                               [CAMediaTimingFunction functionWithControlPoints:.45 :0 :.35 :1],
                               [CAMediaTimingFunction functionWithControlPoints:0 :0 :.58 :1]]
                    duration:duration];
    [CATransaction commit];
    [CATransaction flush];
    NSUInteger token=++_travelToken;__weak WXGDemoBar *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((duration+.03)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf endTravel:token];});
}
// FIX88: the anchor (what the per-frame layout is asked for) that puts its
// lens's centre at x at this press. A lifted lens sits a little off its anchor
// (it grows past the bar's ends), and the layout is linear in the anchor
// between the first and the last tab, so it inverts exactly.
- (CGFloat)anchorForLensCentreX:(CGFloat)x press:(CGFloat)press {
    WXGConfig *c=WXGConfig.shared;
    float w=(float)_materialRect.size.width,h=(float)_materialRect.size.height,gap=(float)[self selectionGap];
    CGFloat minX=_materialRect.origin.x,first=[self centerForIndex:0],last=[self centerForIndex:3];
    WXGDockGeometry a=WXGDockLayout(w,h,gap,(float)(first-minX),(float)press,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    WXGDockGeometry b=WXGDockLayout(w,h,gap,(float)(last-minX),(float)press,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    CGFloat c0=minX+a.lensX+a.lensWidth*.5,c1=minX+b.lensX+b.lensWidth*.5;
    if(fabs(c1-c0)<1 || !isfinite(c0) || !isfinite(c1))return x;
    return first+(last-first)*WXGClamp((x-c0)/(c1-c0),0,1);
}
// The per-frame lens takes over exactly where the glide is on screen: same
// centre, size (so press) and grown bar.
- (void)handOverTravelToFinger {
    if(!_travelling || _travelPhase!=1)return;
    ++_handovers;
    CALayer *shown=_travelLens.presentationLayer?:_travelLens;
    _press=[self travelPressForSize:shown.bounds.size];_pressVelocity=0;
    _lensX=[self anchorForLensCentreX:shown.position.x press:_press];_velocityX=0;
    _elasticMotion=(WXGElasticMotion){0};   // nothing the glide's per-frame shadow built up (finger jitter)
    [self finishTravelNow];
    _targetPress=1;
}
- (void)cancelGlide {
    if(!_travelling || _travelPhase!=1)return;
    ++_glideCancels;
    CALayer *shown=_travelLens.presentationLayer?:_travelLens;
    _press=[self travelPressForSize:shown.bounds.size];_pressVelocity=0;
    _lensX=[self anchorForLensCentreX:shown.position.x press:_press];_velocityX=0;
    _elasticMotion=(WXGElasticMotion){0};   // nothing the glide's per-frame shadow built up (finger jitter)
    [self finishTravelNow];
}
// Release animation without a glide in flight (a drag that ends on another
// tab, or no render-server glide): FIX43 timing, nearly distance-independent:
// 0.27 s x (0.85 + 0.05 x tabs); a main-thread glide's plan is honoured.
- (BOOL)beginTravelToIndex:(NSInteger)index {
    // FIX95: the real lens on the same timing (WXGScriptTravel).
    // FIX98: x the duration scale, the drop of its own length, from the colour shown.
    if(!WXGConfig.shared.dockTapSimpleTravel && !UIAccessibilityIsReduceMotionEnabled() && !CGRectIsEmpty(_materialRect)) {
        CGFloat slot=MAX(1,([self centerForIndex:3]-[self centerForIndex:0])/3);
        WXGConfig *c=WXGConfig.shared;
        _script=WXGScriptTravel([self animationNow],_lensX,[self centerForIndex:index],slot,WXGClamp(_press,0,1),WXGClamp(_selectionShown,0,1),_jumpPlanEnd,index,
                                c.dockTapDurationScale,c.dockTapDropDuration,c.dockTapLensShare);
        [self beginTapRecord:2];
        _jumpPlanEnd=0;++_scriptTravels;_targetX=[self centerForIndex:index];_targetPress=0;
        return YES;
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(![self prepareTravelToIndex:index]){[CATransaction commit];return NO;}
    _travelPhase=2;
    CGFloat slotWidth=MAX(1,([self centerForIndex:3]-[self centerForIndex:0])/3);
    CGFloat remaining=fabs(_travelTo.x-_travelFrom.x)/slotWidth;
    CFTimeInterval now=CACurrentMediaTime();
    CFTimeInterval move=remaining<.05?0:(_jumpPlanEnd>now?MAX(.12,_jumpPlanEnd-now):.27*(.85+.05*MIN(remaining,3.)));
    CFTimeInterval dropTime=.09,settle=.05,duration=(move>0?move:dropTime)+settle;
    _jumpPlanEnd=0;
    CGFloat p0=_travelStartPress,lifted=remaining>=.5?MAX(.90,p0):p0;
    CFTimeInterval peakAt=move*.55,dropAt=MAX(peakAt+.02,move-dropTime);
    NSArray *press=@[@(p0),@(lifted),@(lifted*.94),@.04,@0];
    NSArray *sizes=@[[NSValue valueWithCGSize:_travelStartSize],[NSValue valueWithCGSize:[self travelSizeForPress:lifted]],
                     [NSValue valueWithCGSize:[self travelSizeForPress:lifted*.94]],[NSValue valueWithCGSize:[self travelSizeForPress:.04]],
                     [NSValue valueWithCGSize:_travelRestSize]];
    NSArray *times=move>0?@[@0,@(peakAt/duration),@(MIN(dropAt,move-.01)/duration),@(move/duration),@1]:
                          @[@0,@(.01/duration),@(.02/duration),@(dropTime/duration),@1];
    [self animateTravelMoveFrom:_travelFrom to:_travelTo duration:move];   // FIX88: first (the veil follows it)
    [self animateTravelSizes:sizes press:press times:times
                      timing:@[[CAMediaTimingFunction functionWithControlPoints:.42 :0 :.58 :1],
                               [CAMediaTimingFunction functionWithControlPoints:.40 :0 :.60 :1],
                               [CAMediaTimingFunction functionWithControlPoints:.45 :0 :.35 :1],
                               [CAMediaTimingFunction functionWithControlPoints:0 :0 :.58 :1]]
                    duration:duration];
    [CATransaction commit];
    [CATransaction flush];   // in the render server before WeChat starts switching
    NSUInteger token=++_travelToken;__weak WXGDemoBar *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((duration+.03)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf endTravel:token];});
    return YES;
}
// Hands back to the per-frame dock: its lens returns (where the dock state
// says), the overlay is redrawn, and in the same commit the overlay is shown
// and the travel layers go (instant: both show the same lens).
- (void)endTravel:(NSUInteger)token {
    if(!_travelling || token!=_travelToken)return;
    [self finishTravelNow];
}
- (void)finishTravelNow {
    if(!_travelling)return;
    _travelling=NO;_travelPhase=0;NSUInteger token=++_travelToken;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    [self removeTravelScale];   // FIX88: the per-frame layout scales the bar from here
    _glass.lensSuppressed=_morphing;[self updateGeometry];   // FIX60: a search morph keeps the lens away
    [CATransaction commit];
    [self revealAfterTravel:token attempt:0];
}
- (void)revealAfterTravel:(NSUInteger)token attempt:(NSUInteger)attempt {
    if(_travelling || token!=_travelToken)return;
    if(![_glass drawNow] && attempt<6) {
        __weak WXGDemoBar *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.016*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf revealAfterTravel:token attempt:attempt+1];});
        return;
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _glass.overlayHidden=_morphing;   // FIX60: the search morph draws the tabs itself
    for(CALayer *layer in [self travelLayers])[layer removeAllAnimations];
    for(UIView *v in _travelBackdrops){[v.layer removeAllAnimations];[v.layer removeFromSuperlayer];}
    _travelView.hidden=YES;
    [CATransaction commit];
}
- (BOOL)restingOnSelectedTab {
    return _fingerDown && !_travelling && !_script.phase && !_dragging && _touchDownIndex==_initialSelected && _selectedIndex==_initialSelected;
}
- (void)cancelInteraction {
    if(_fingerDown){++_interactionAborts;_lastTrackingReason=@"interaction_cancelled";}
    if(_travelling && _travelPhase==1)[self cancelGlide];
    if(_script.phase)[self endScript];   // FIX95
    _resumeIndex=-1;_earlyIndex=-1;_earlySent=NO;
    WXGDockTouchForget(&_trackingPoint);
    _fingerDown=NO; _previewStart=0; _targetPress=0; _targetX=[self centerForIndex:_selectedIndex];
    [self releaseEndStretch];   // FIX68
    if (!_active) { _elasticMotion=(WXGElasticMotion){0};_press=0; _pressVelocity=0; _lensX=_targetX; _velocityX=0; _endStretch=(WXGStretchState){0};[self applyEndStretch]; }
}
- (NSDictionary *)dockInteractionMetrics {
    return @{@"began":@(_downCount),@"moved":@(_moveCount),@"ended":@(_trackingEnds),
        @"cancelled":@(_trackingCancels),@"committed":@(_trackingCommits),@"nilEnded":@(_nilTrackingEnds),
        @"aborted":@(_interactionAborts),@"asyncIconBuilds":@(_asyncIconBuilds),@"iconGeneration":@(_iconGeneration),@"tracking":@(_fingerDown),@"selectedIndex":@(_selectedIndex),
        @"lastCommittedIndex":@(_lastCommittedIndex),@"reason":_lastTrackingReason?:@"none",@"renderServerTaps":@(_travels),@"travelling":@(_travelling),@"neutralFrameMisses":@(_neutralFrameMisses),
        @"glides":@(_glides),@"drops":@(_drops),@"handovers":@(_handovers),@"glideCancels":@(_glideCancels),
        @"holdHandovers":@(_holdHandovers),@"tapAnimation":WXGConfig.shared.dockTapSimpleTravel?@"renderServerShape":@"realLens",
        @"scriptGlides":@(_scriptGlides),@"scriptDrops":@(_scriptDrops),@"scriptTravels":@(_scriptTravels),@"scriptDrags":@(_scriptDrags),@"scripted":@(_script.phase),@"selectionShown":@(round(_selectionShown*1000)/1000),
        @"clockStalls":@(_clockStalls),@"clockLostMS":@(round(_clockLostMS)),@"tapDurationScale":@(WXGConfig.shared.dockTapDurationScale),@"tapLensShare":@(WXGConfig.shared.dockTapLensShare),@"taps":_tapRecords?:@[],
        @"tapDrop":@(WXGConfig.shared.dockTapDropDuration),@"tapSwitchWhen":@(WXGConfig.shared.dockTapSwitchWhen),@"uncommittedEnds":@(_uncommittedEnds),@"travelVeil":@(_travelVeilOn),@"travelVeilBands":@(_travelVeilCount),@"travelSetupMaxMS":@(round(_travelSetupMS*10)/10),
        @"lastPoint":@[@(_trackingPoint.x),@(_trackingPoint.y)],@"hasTrackingPoint":@(_trackingPoint.valid),
        @"searchMode":@(_searchMode),@"morphing":@(_morphing),@"morphs":@(_morphs),
        @"discrete":@(_discreteShown),@"discretePieces":@(_pieceCount),@"discreteSwitches":@(_discreteSwitches),@"discreteShows":@(_discreteShows)};
}
- (void)tick:(CADisplayLink *)link {
    if (!_active || !self.window) return;
    double dt=_lastTime?link.timestamp-_lastTime:(link.targetTimestamp>link.timestamp?link.targetTimestamp-link.timestamp:1.0/60); _lastTime=link.timestamp;
    [self syncDiscreteVisibility];
    if(_discreteShown){[self tickDiscrete:link dt:dt];return;}   // 离散底栏
    if(_piecesLinger)for(NSInteger j=0;j<_pieceCount && j<(NSInteger)_pieces.count;j++)[_pieces[j] tick:link.timestamp];
    if(_previewStart>0 && !_fingerDown) {
        double t=CACurrentMediaTime()-_previewStart;
        if(t<3) { _targetPress=1; _targetX=[self centerForIndex:0]+([self centerForIndex:3]-[self centerForIndex:0])*(.5-.5*cos(M_PI*t/3)); }
        else { _previewStart=0; _targetPress=0; [self selectIndex:3 haptic:NO]; }
    }
    BOOL reduceMotion=UIAccessibilityIsReduceMotionEnabled();
    // FIX88: a press held on another tab: once the render-server glide has
    // arrived, the real lens takes over (the one a drag summons: refraction,
    // inset bar, the bar grown), and the release commits as a drag does.
    if(_travelling && _travelPhase==1 && _fingerDown && CACurrentMediaTime()>=_travelPlanEnd+.02){++_holdHandovers;[self handOverTravelToFinger];}
    // FIX95: the scripted tap: a hold past the glide becomes the drag's lens
    // (pressed fully, following the finger); a landing ends at rest.
    CFTimeInterval scriptNow=[self animationNow];   // FIX98: the script's clock
    [self tapFrameAt:link.timestamp];   // FIX99
    // FIX101 (user: smooth at times, then not: cold start, after a chat):
    // WeChat's work right after a tab switch comes as a few long frames
    // (0.1-0.7 s on the tester's phone, spread over the next ~0.5 s). The lens
    // waits where it is through them (the script moves on with the clock, so
    // nothing changes on screen) until three frames in a row are on time, 0.6 s
    // at most; then the rest of it runs at full smoothness.
    if(_calmWaitFrom>0 && _script.phase) {
        CFTimeInterval real=CACurrentMediaTime();
        double nominal=link.duration>.001?link.duration:(link.targetTimestamp>link.timestamp?link.targetTimestamp-link.timestamp:1./60);
        double interval=_calmLastTick>0?real-_calmLastTick:0;_calmLastTick=real;
        int calm=(int)_calmFrames;BOOL waiting=WXGScriptCalmWait(&calm,interval,nominal,real-_calmWaitFrom)!=0;_calmFrames=calm;
        double held=scriptNow-_calmHoldClock;
        if(held>0){WXGScriptShift(&_script,held);if(_jumpPlanEnd>0)_jumpPlanEnd+=held;_tapCalmWait+=held;}
        _calmHoldClock=scriptNow;
        if(!waiting) {
            // Go: from real time again (no lag left from the busy frames).
            _calmWaitFrom=0;
            double lag=real-_animClock;
            if(lag>0){WXGScriptShift(&_script,lag);if(_jumpPlanEnd>0)_jumpPlanEnd+=lag;_animClock=real;scriptNow=real;}
            _animClockReal=real;
        }
    }else _calmWaitFrom=0;
    if(_script.phase==1 && _fingerDown && scriptNow>=_script.planEnd+.02){++_holdHandovers;[self endScript];_targetPress=1;}
    if(_script.phase==1 && !_fingerDown)[self endScript];   // (never left by endTracking: defensive)
    if(_script.phase==2 && scriptNow>=_script.end) {
        // Where the script put it (the springs take it on if the tab changed meanwhile).
        _lensX=_script.moveTo;[self endScript];_velocityX=0;_press=0;_pressVelocity=0;_targetPress=0;
    }
    BOOL scripted=_script.phase!=0;
    if(scripted) {
        double rate=0;
        _lensX=WXGScriptMoveAt(&_script,scriptNow,&rate);_velocityX=isfinite(rate)?rate:0;
        _press=WXGScriptPressAt(&_script,scriptNow,&rate);_pressVelocity=isfinite(rate)?rate:0;
        _selectionShown=WXGScriptSelectValue(&_script,scriptNow);   // FIX98
        if(_calmWaitFrom>0){_velocityX=0;_pressVelocity=0;}   // FIX101: waiting, it stands still (no motion stretch)
    }else if(_selectionCarry!=0) {
        _selectionCarry*=exp(-dt/.08);   // FIX98: a script's colour hands over to the press' in ~0.2 s
        if(fabs(_selectionCarry)<.002)_selectionCarry=0;
    }
    // Lift, travel and release stay concurrent; native tab selection commits at touch-up.
    if(!scripted && _jumping && _fingerDown) {
        CFTimeInterval u=(CACurrentMediaTime()-_jumpStart)/MAX(.05,_jumpDuration);
        if(u>=1){_lensX=_targetX;_velocityX=0;_jumping=NO;}
        else {
            double e=WXGBezierEase(u,.40,0,.30,1),e2=WXGBezierEase(MIN(1,u+.01),.40,0,.30,1);
            CGFloat previous=_lensX;_lensX=_jumpFromX+(_targetX-_jumpFromX)*e;
            _velocityX=(_targetX-_jumpFromX)*(e2-e)/(.01*MAX(.05,_jumpDuration));
            if(!isfinite(_velocityX))_velocityX=(_lensX-previous)/MAX(dt,1e-3);
        }
    } else if(!scripted)WXGSpring(&_lensX,&_velocityX,_targetX,_fingerDown?620:340,_fingerDown?39:29,dt);
    double motionDT=dt;
    if(!_fingerDown && _targetPress<=0 && !reduceMotion)dt*=.80;
    if(!scripted)WXGSpring(&_press,&_pressVelocity,_targetPress,reduceMotion?600:420,reduceMotion?49:31,dt);
    dt=motionDT;
    // Elastic deformation is always on (no setting); Reduce Motion still disables it.
    if(!reduceMotion)WXGElasticStep(&_elasticMotion,_velocityX,dt);
    else _elasticMotion=(WXGElasticMotion){0};
    if(WXGStretchStep(&_endStretch,dt) || !CGAffineTransformIsIdentity(_glass.transform))[self applyEndStretch];   // FIX68
    [self updateGeometry]; [self layoutBadges]; [_glass tick:link.timestamp];
}
- (void)updateGeometry {
    if(CGRectIsEmpty(_materialRect)) return;
    [self syncDiscreteVisibility];
    if(_discreteShown){_discreteDirty=YES;[self updateDiscreteGeometry];return;}   // 离散底栏
    WXGConfig *c=WXGConfig.shared;
    CGFloat press=WXGClamp(_press,0,1);
    CGFloat stretch=UIAccessibilityIsReduceMotionEnabled()?0:WXGClamp(fabs(_velocityX)/2200,0,.10)*press;
    WXGDockGeometry g=WXGDockLayout(_materialRect.size.width,_materialRect.size.height,[self selectionGap],
        _lensX-_materialRect.origin.x,press,c.lensGrowth,stretch,c.barGrowth,c.endWrap);
    if(!UIAccessibilityIsReduceMotionEnabled())g=WXGElasticLayout(_materialRect.size.width,_materialRect.size.height,[self selectionGap],
        _lensX-_materialRect.origin.x,press,c.lensGrowth,stretch,_elasticMotion,c.barGrowth,c.endWrap);
    CGRect bar=CGRectMake(_materialRect.origin.x+g.barX,_materialRect.origin.y+g.barY,g.barWidth,g.barHeight);
    CGRect lens=CGRectMake(_materialRect.origin.x+g.lensX,_materialRect.origin.y+g.lensY,g.lensWidth,g.lensHeight);
    _glass.barScale=g.scale; _glass.lensAnchorX=_materialRect.origin.x+g.anchorX;
    // FIX98: the selection colour: the script's while one runs, else by the
    // press (WXGRestingSelectionWeight, now gradual) plus what a script left.
    CGFloat selection=_script.phase?_selectionShown:WXGClamp(WXGRestingSelectionWeight(press)+_selectionCarry,0,1);
    _selectionShown=selection;
    _glass.lensRect=lens; _glass.pressAmount=press; _glass.selectionWeight=selection; [_glass layoutIfNeeded];
    BOOL live=WXGConfig.shared.renderMode>=2;
    _glass.hidden=!_glass.ready && !live;
    // 离散底栏: the bar glass woken from the pieces (the search morph) has its
    // live backdrop at once in render-server mode: no fallback blur bar.
    BOOL presented=(_glass.ready && _glass.hasPresentedFrame) || (live && _discreteShows>0);
    _fallback.hidden=presented;_fallbackLens.hidden=presented || _travelling;_fallbackIcons.hidden=presented;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _fallback.frame=bar; _fallback.layer.cornerRadius=MIN(bar.size.width,bar.size.height)*.5;
    _fallbackIcons.transform=CGAffineTransformMakeScale(g.scale,g.scale);
    _fallbackLens.frame=lens; _fallbackLens.layer.cornerRadius=MIN(g.lensWidth,g.lensHeight)*.5;
    UIColor *tint=WXGColor(_darkInk?c.materialHex:c.darkMaterialHex);
    _fallback.contentView.backgroundColor=[tint colorWithAlphaComponent:CGColorGetAlpha(tint.CGColor)*(_darkInk?c.materialOpacity:c.darkMaterialOpacity)];
    UIColor *border=WXGColor(c.borderHex);
    _fallback.layer.borderWidth=c.dockBorderWidth;
    _fallback.layer.borderColor=[border colorWithAlphaComponent:CGColorGetAlpha(border.CGColor)*c.borderOpacity*(_darkInk?1:c.darkRimGain)].CGColor;
    _fallbackLens.layer.borderWidth=c.lensBorderWidth;
    _fallbackLens.layer.borderColor=[border colorWithAlphaComponent:CGColorGetAlpha(border.CGColor)*c.borderOpacity*(_darkInk?1:c.darkRimGain)*WXGPressedBorderAlpha(press)].CGColor;
    UIColor *selectionColor=WXGColor(_darkInk?c.selectionHex:c.darkSelectionHex);
    _fallbackLens.backgroundColor=[selectionColor colorWithAlphaComponent:CGColorGetAlpha(selectionColor.CGColor)*(c.selectionOpacity+(c.pressedOpacity-c.selectionOpacity)*press)*selection];
    [CATransaction commit];
}
- (void)syncSelectedIndex:(NSInteger)index {
    if(_fingerDown)return;
    [self selectIndex:index haptic:NO];[self updateGeometry];
}
- (void)updateBadges:(NSArray<NSString *> *)badges {
    for(NSInteger i=0;i<4;i++) {
        NSString *v=i<(NSInteger)badges.count?badges[i]:@"";
        // FIX36: WeChat's dot (发现) is a plain red dot: no glyph on it.
        BOOL dot=[v isEqual:@"•"];NSString *shown=dot?@"":v;
        if(![_badges[i].text isEqual:shown])_badges[i].text=shown;
        _badges[i].tag=dot?1:0;
        _badges[i].hidden=!v.length;
        _a11yItems[i].accessibilityValue=dot?@"有新内容":v.length?[NSString stringWithFormat:@"%@ 条未读",v]:nil;
    }[self layoutBadges];
}
- (void)layoutBadges {
    if(_discreteShown) {
        // 离散底栏 (FIX106 B, user: the badge covered the wide tab's icon and
        // titles): on each capsule's top-right corner (its end cap at 45
        // degrees), a ball's and the wide one's alike, gliding with its width.
        WXGDiscreteMetrics m=_discreteMetrics;
        CGFloat oy=round((_materialRect.origin.y+m.originY)*2)/2,ch=round(m.cell*2)/2;
        for(NSInteger i=0;i<4;i++) {
            UILabel *b=_badges[i];if(b.hidden)continue;
            BOOL dot=b.tag==1;CGFloat h=dot?8:17;
            CGFloat w=dot?8:MAX(h,[b.text sizeWithAttributes:@{NSFontAttributeName:b.font}].width+7);
            float cx=0,cy=0;
            WXGDiscreteBadgeCentre((float)(_materialRect.origin.x+_tabX[i]),(float)oy,_tabW[i],(float)ch,&cx,&cy);
            // FIX106 C: a ball's badge goes with its icon (gathered in a joined
            // run), at the same corner a lone ball's has; the wide capsule's
            // stays on its right end; between, by how wide the tab is.
            float r=(float)ch*.5f,k=.70710678f,e=(float)WXGClamp(_discreteE[i],0,1);
            float bx=(float)_tabIconCentre[i].x+r*k,by=(float)(oy+ch*.5)-r*k;
            cx=bx+(cx-bx)*e;cy=by+(cy-by)*e;
            // Its round left end on that point (nudged 1.5 pt outward): longer
            // counts grow outward, away from the titles.
            b.frame=CGRectMake(round((cx+1.5-h*.5)*2)/2,round((cy-1.5-h*.5)*2)/2,w,h);b.layer.cornerRadius=h*.5;
        }
        return;
    }
    CGFloat scale=_glass.barScale,center=CGRectGetMidX(_materialRect),cy=CGRectGetMidY(_materialRect);
    for(NSInteger i=0;i<4;i++) {
        UILabel *b=_badges[i];if(b.hidden)continue;
        BOOL dot=b.tag==1;CGFloat h=dot?8:17;
        CGFloat w=dot?8:MAX(h,[b.text sizeWithAttributes:@{NSFontAttributeName:b.font}].width+7);
        CGFloat x=center+([self centerForIndex:i]+8-center)*scale,y=cy+(-22+[self iconShift])*scale;   // FIX89: with the icon
        // FIX68: with the bar's end stretch.
        CGAffineTransform t=_glass.transform;CGFloat gx=CGRectGetMidX(self.bounds),gy=CGRectGetMidY(self.bounds);
        CGFloat mx=x+w*.5,my=y+h*.5;
        x=gx+(mx-gx)*t.a+t.tx-w*.5;y=gy+(my-gy)*t.d+t.ty-h*.5;
        b.frame=CGRectMake(x,y,w,h);b.layer.cornerRadius=h*.5;
    }
}
- (void)previewLens { if(!_active) return; _previewStart=CACurrentMediaTime(); _targetPress=1; }
- (NSString *)nativeIconSummary {return _nativeIcons.diagnostics;}
- (NSString *)renderState {
    return [NSString stringWithFormat:@"底栏 隐%d 透%.2f %.0fx%.0f 外观%@ | 备用 底板隐%d 透镜隐%d 图标隐%d | %@",self.hidden,self.alpha,self.bounds.size.width,self.bounds.size.height,
        _darkInk?@"浅":@"深",_fallback.hidden,_fallbackLens.hidden,_fallbackIcons.hidden,
        _discreteShown?[NSString stringWithFormat:@"%@ | %@",[self discreteSummary],_pieces.firstObject.renderState?:@"-"]:_glass.renderState];
}
// FIX39: the tap animation's layers and refracting backdrop, built while idle
// so the first taps after launch do not pay for them.
- (void)prewarmTravel {
    if(_discreteShown)return;   // 离散底栏: no lens travel
    if(_travelling || CGRectIsEmpty(_materialRect) || !self.window || !WXGConfig.shared.dockTapSimpleTravel ||
       !_selectedAtlas.CGImage || !_normalAtlas.CGImage)return;
    WXGConfig *c=WXGConfig.shared;
    float w=(float)_materialRect.size.width,h=(float)_materialRect.size.height,gap=(float)[self selectionGap];
    WXGDockGeometry g=WXGDockLayout(w,h,gap,w*.5f,.90f,(float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);   // as prepareTravelToIndex
    CGSize size=CGSizeMake(g.lensWidth,g.lensHeight);NSString *key=[self travelBackdropKeyForSize:size];
    [self ensureTravelLayers];
    if(!_travelBackdrops.count || ![key isEqual:_travelBackdropKey]){_travelBackdrops=WXGMakeTravelLensBackdrops(size,.90,nil);_travelBackdropKey=key;}
    [self applyTravelGroup:nil];   // FIX88: never the glass's group under opacity 0.001
    // FIX44: draw the travel layers once, invisibly (opacity 0.001), so the
    // render server sets up their pipelines now rather than on the first tap.
    [CATransaction begin];[CATransaction setDisableActions:YES];
    [self loadTravelColors];
    unsigned depth=0;
    for(UIView *v in _travelBackdrops){CALayer *layer=v.layer;layer.anchorPoint=CGPointZero;layer.position=CGPointZero;[_travelLens insertSublayer:layer atIndex:depth++];}
    _travelIconImage.contents=(__bridge id)_selectedAtlas.CGImage;_travelIconImage.contentsScale=_selectedAtlas.scale;
    _travelIconImage.bounds=(CGRect){CGPointZero,self.bounds.size};
    _travelNormalIcons.contents=(__bridge id)_normalAtlas.CGImage;_travelNormalIcons.contentsScale=_normalAtlas.scale;
    _travelNormalIcons.frame=self.bounds;
    CGPoint centre=CGPointMake(CGRectGetMidX(_materialRect),CGRectGetMidY(_materialRect));
    [self setTravelShapeModel:size press:.90];
    _travelLens.position=centre;_travelHole.position=centre;_travelIconImage.position=CGPointMake(-centre.x,-centre.y);
    _travelView.bounds=(CGRect){CGPointZero,self.bounds.size};_travelView.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));_travelView.layer.opacity=.001f;_travelView.hidden=NO;
    [CATransaction commit];
    __weak WXGDemoBar *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WXGDemoBar *bar=weakSelf;if(!bar || bar.travelling)return;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        bar.travelView.hidden=YES;bar.travelView.layer.opacity=1;
        for(UIView *v in bar.travelBackdrops)[v.layer removeFromSuperlayer];
        [CATransaction commit];
    });
}
#pragma mark - 离散底栏 (discrete dock)
/* The selected tab is a wide capsule (icon on the left, 中文 title above the
   English one), the others are balls; a switch springs every tab's width
   (WXGDockDiscrete.h). Each capsule is its own dock glass (the dock's
   material, optics and rim), the icons and titles plain views above them.
   The bar glass sleeps meanwhile; while searching the bar takes over again
   (the search morph is the bar's), the two crossfading. */
static const CFTimeInterval WXGDiscreteFade=.2;
static NSString * const WXGDiscreteFadeKey=@"wxg.discreteFade";
- (BOOL)discreteWanted {return WXGConfig.shared.dockDiscrete && !_searchMode && !_morphing;}
// Toward the search button (its side is the one with stretch room), else centred.
- (int)discreteAlign {return _endStretchRoomLeft>0?-1:(_endStretchRoomRight>0?1:0);}
- (void)ensureDiscreteViews {
    if(_discreteView)return;
    _discreteView=[[UIView alloc]initWithFrame:self.bounds];
    _discreteView.userInteractionEnabled=NO;_discreteView.hidden=YES;_discreteView.backgroundColor=UIColor.clearColor;
    UIView *badge=_badges.firstObject;
    if(badge.superview==self)[self insertSubview:_discreteView belowSubview:badge];else [self addSubview:_discreteView];
    _pieces=[NSMutableArray array];
    NSMutableArray *clips=[NSMutableArray array],*icons=[NSMutableArray array],*selectedIcons=[NSMutableArray array];
    NSMutableArray *titles=[NSMutableArray array],*subtitles=[NSMutableArray array];
    for(NSInteger i=0;i<4;i++) {
        UIView *clip=[UIView new];clip.userInteractionEnabled=NO;clip.clipsToBounds=YES;
        clip.backgroundColor=UIColor.clearColor;clip.layer.cornerCurve=kCACornerCurveContinuous;
        UIImageView *normal=[UIImageView new],*selected=[UIImageView new];
        normal.contentMode=UIViewContentModeScaleAspectFit;selected.contentMode=UIViewContentModeScaleAspectFit;
        normal.userInteractionEnabled=NO;selected.userInteractionEnabled=NO;
        UILabel *title=[UILabel new],*subtitle=[UILabel new];
        for(UILabel *label in @[title,subtitle]) {
            label.backgroundColor=UIColor.clearColor;label.opaque=NO;label.numberOfLines=1;label.userInteractionEnabled=NO;
            label.textAlignment=NSTextAlignmentLeft;label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=.7;
            label.lineBreakMode=NSLineBreakByClipping;label.hidden=YES;
        }
        // FIX106 C: the titles clipped to their capsule, the icons free (above,
        // in the dock's space): gathered in a joined run they reach past their cell.
        [clip addSubview:title];[clip addSubview:subtitle];
        [_discreteView addSubview:clip];[_discreteView addSubview:normal];[_discreteView addSubview:selected];
        [clips addObject:clip];[icons addObject:normal];[selectedIcons addObject:selected];[titles addObject:title];[subtitles addObject:subtitle];
    }
    _tabClips=clips;_tabIcons=icons;_tabSelectedIcons=selectedIcons;_tabTitles=titles;_tabSubtitles=subtitles;
    [self loadDiscreteContent];
}
// The glass of capsule j (made on first use, under every tab's content).
- (WXGGlassView *)pieceAtIndex:(NSInteger)j {
    while((NSInteger)_pieces.count<=j) {
        WXGGlassView *piece=[[WXGGlassView alloc]initWithFrame:self.bounds];
        piece.dockSurface=YES;piece.userInteractionEnabled=NO;piece.hidden=YES;
        piece.deferShapeField=YES;piece.lightweight=WXGConfig.shared.dockDiscreteLight;
        piece.sourceView=_glass.sourceView;piece.backdropExclusions=_glass.backdropExclusions;
        __weak WXGDemoBar *weakSelf=self;
        piece.onReady=^(BOOL ready){(void)ready;WXGDemoBar *bar=weakSelf;if(!bar || !bar.discreteShown)return;bar.discreteDirty=YES;[bar updateDiscreteGeometry];};
        [_discreteView insertSubview:piece atIndex:(NSInteger)_pieces.count];
        [_pieces addObject:piece];
    }
    return _pieces[(NSUInteger)j];
}
- (void)propagateGlassSources {
    UIView *source=_glass.sourceView;NSArray<UIView *> *exclusions=_glass.backdropExclusions?:@[];
    for(WXGGlassView *piece in [_pieces copy]) {
        piece.sourceView=source;
        if(![piece.backdropExclusions isEqualToArray:exclusions])piece.backdropExclusions=exclusions;
    }
}
- (NSArray<WXGGlassView *> *)renderGlasses {
    if(!_discreteShown)return @[_glass];
    NSInteger n=MIN(_pieceCount,(NSInteger)_pieces.count);
    return n>0?[_pieces subarrayWithRange:NSMakeRange(0,(NSUInteger)n)]:@[];
}
- (NSArray<WXGGlassView *> *)allGlasses {return _pieces.count?[@[_glass] arrayByAddingObjectsFromArray:_pieces]:@[_glass];}
// Icons, titles, colours and fonts: the same artwork the atlas uses (WeChat's
// own or the symbols), the 中文 title (WeChat's) and its English name.
- (void)loadDiscreteContent {
    if(!_tabClips.count)return;
    WXGConfig *c=WXGConfig.shared;
    NSArray *names=@[@"微信",@"通讯录",@"发现",@"我"];
    static const CGFloat weights[5]={-.4,0,.23,.3,.4};   // UIFontWeightLight .. UIFontWeightBold
    NSInteger step=MAX(0,MIN(4,c.dockTitleWeight));
    // FIX106 B: their own sizes (the bar's titles stay as they are).
    UIFont *zh=[UIFont systemFontOfSize:c.dockDiscreteTitleSize weight:weights[MIN(4,step+1)]];
    UIFont *en=[UIFont systemFontOfSize:c.dockDiscreteSubtitleSize weight:weights[step]];
    CGFloat iconSize=c.dockDiscreteIconSize;
    for(NSInteger i=0;i<4;i++) {
        WXGNativeIconPair *pair=c.useWeChatIcons && i<(NSInteger)_nativeIcons.items.count?_nativeIcons.items[(NSUInteger)i]:nil;
        UIColor *accent=nil;
        _tabIcons[(NSUInteger)i].image=WXGDockTabArtwork(pair,i,NO,_darkInk,iconSize,NULL);
        _tabSelectedIcons[(NSUInteger)i].image=WXGDockTabArtwork(pair,i,YES,_darkInk,iconSize,&accent);
        NSString *title=pair.title.length?pair.title:names[(NSUInteger)i],*english=WXGDiscreteEnglish(i);
        if([title caseInsensitiveCompare:english]==NSOrderedSame)english=@"";   // WeChat in English: one title
        UILabel *t=_tabTitles[(NSUInteger)i],*s=_tabSubtitles[(NSUInteger)i];
        t.text=title;t.font=zh;t.textColor=accent;
        s.text=english;s.font=en;s.textColor=[accent colorWithAlphaComponent:CGColorGetAlpha(accent.CGColor)*.7];
        CGFloat w=[title sizeWithAttributes:@{NSFontAttributeName:zh}].width;
        if(english.length)w=MAX(w,[english sizeWithAttributes:@{NSFontAttributeName:en}].width);
        _tabTextW[i]=ceil(w)+1;
    }
    _discreteDirty=YES;
}
- (BOOL)discreteSettled {
    for(int i=0;i<WXGDiscreteTabs;i++)
        if(fabs(_discreteE[i]-(i==_selectedIndex?1.:0.))>.002 || fabs(_discreteV[i])>.02)return NO;
    int connected=WXGConfig.shared.dockDiscreteConnected?1:0;
    for(int i=0;i<WXGDiscreteTabs-1;i++)
        if(_bridge[i]!=WXGDiscreteBridgeTarget(connected,(int)_selectedIndex,i))return NO;   // constant-rate steps land exactly
    double gather[WXGDiscreteTabs];
    WXGDiscreteGatherTargets(connected,(int)_selectedIndex,(float)WXGConfig.shared.dockDiscreteGather,gather);
    for(int i=0;i<WXGDiscreteTabs;i++)if(fabs(_gather[i]-gather[i])>.002 || fabs(_gatherV[i])>.02)return NO;
    return YES;
}
- (void)fadeDiscreteFrom:(float)from to:(float)to {
    CALayer *layer=_discreteView.layer;
    [layer removeAnimationForKey:WXGDiscreteFadeKey];
    [CATransaction begin];[CATransaction setDisableActions:YES];layer.opacity=to;[CATransaction commit];
    if(fabsf(from-to)<.01f)return;
    CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue=@(from);fade.toValue=@(to);fade.duration=WXGDiscreteFade;
    fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:fade forKey:WXGDiscreteFadeKey];
}
// The bar glass goes to sleep (after the crossfade, if one ran).
- (void)retireClassicGlass {
    _classicLingers=NO;
    if(!_discreteShown)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _glass.active=NO;_glass.hidden=YES;_glass.deferShapeField=YES;   // asleep: no distance field for it either
    _fallback.hidden=YES;_fallbackLens.hidden=YES;_fallbackIcons.hidden=YES;
    [CATransaction commit];
}
// The pieces go to sleep (after the crossfade, if one ran).
- (void)retirePieces {
    _piecesLinger=NO;
    if(_discreteShown)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(WXGGlassView *piece in [_pieces copy]){piece.active=NO;piece.hidden=YES;}
    [_discreteView.layer removeAnimationForKey:WXGDiscreteFadeKey];
    _discreteView.hidden=YES;_discreteView.layer.opacity=1;
    [CATransaction commit];
}
// Into or out of the discrete dock: settings (at once) or the search morph
// (a crossfade: the outgoing glass stays on under / over the incoming one).
- (void)syncDiscreteVisibility {
    BOOL want=[self discreteWanted];
    if(want==_discreteShown)return;
    BOOL animated=self.window!=nil && _discreteShows>0 && (_searchMode || _morphing || (_morphView && !_morphView.hidden));
    NSUInteger token=++_discreteFadeToken;
    __weak WXGDemoBar *weakSelf=self;
    _discreteShown=want;
    if(want) {
        ++_discreteShows;
        [self ensureDiscreteViews];
        // From where WeChat is: the selected tab wide, no spring running.
        for(int i=0;i<WXGDiscreteTabs;i++){_discreteE[i]=i==_selectedIndex?1:0;_discreteV[i]=0;}
        int connected=WXGConfig.shared.dockDiscreteConnected?1:0;
        for(int i=0;i<WXGDiscreteTabs-1;i++){_bridge[i]=WXGDiscreteBridgeTarget(connected,(int)_selectedIndex,i);_bridgeV[i]=0;}
        WXGDiscreteGatherTargets(connected,(int)_selectedIndex,(float)WXGConfig.shared.dockDiscreteGather,_gather);
        for(int i=0;i<WXGDiscreteTabs;i++)_gatherV[i]=0;
        _piecesLinger=NO;_discreteDirty=YES;
        BOOL wasHidden=_discreteView.hidden;
        CALayer *shown=_discreteView.layer.presentationLayer;
        float from=wasHidden?0.f:(shown?shown.opacity:_discreteView.layer.opacity);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        _discreteView.hidden=NO;
        _fallback.hidden=YES;_fallbackLens.hidden=YES;_fallbackIcons.hidden=YES;
        [CATransaction commit];
        [self propagateGlassSources];
        [self loadDiscreteContent];
        [self updateDiscreteGeometry];
        if(animated) {
            _classicLingers=YES;
            [self fadeDiscreteFrom:from to:1];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(WXGDiscreteFade*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                WXGDemoBar *bar=weakSelf;if(!bar || bar.discreteFadeToken!=token)return;[bar retireClassicGlass];
            });
        }else {
            [self fadeDiscreteFrom:1 to:1];
            [self retireClassicGlass];
        }
        [self layoutBadges];
    }else {
        _classicLingers=NO;
        _glass.deferShapeField=NO;_glass.active=_active;
        BOOL live=WXGConfig.shared.renderMode>=2;
        _glass.hidden=!_glass.ready && !live;
        [_glass setNeedsLayout];[_glass invalidateBackdrop];
        // The bar's lens takes up at rest on the tab (tick / updateGeometry go on from here).
        _lensX=[self centerForIndex:_selectedIndex];_targetX=_lensX;_velocityX=0;_press=0;_pressVelocity=0;_targetPress=0;
        if(!CGRectIsEmpty(_materialRect))
            self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:_materialRect cornerRadius:_materialRect.size.height*.5].CGPath;
        if(animated && _discreteView && !_discreteView.hidden) {
            _piecesLinger=YES;
            CALayer *shown=_discreteView.layer.presentationLayer;
            [self fadeDiscreteFrom:shown?shown.opacity:_discreteView.layer.opacity to:0];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(WXGDiscreteFade*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                WXGDemoBar *bar=weakSelf;if(!bar || bar.discreteFadeToken!=token)return;[bar retirePieces];
            });
        }else [self retirePieces];
    }
}
- (void)tickDiscrete:(CADisplayLink *)link dt:(double)dt {
    WXGConfig *c=WXGConfig.shared;BOOL reduce=UIAccessibilityIsReduceMotionEnabled();
    // Every tab on the same spring (so the row never moves, WXGDockDiscrete.h);
    // Reduce Motion: critically damped and quick.
    double stiffness=0,friction=0;
    WXGDiscreteSpringConstants(reduce?1.:c.dockDiscreteDamping,reduce?.3:c.dockDiscreteResponse,&stiffness,&friction);
    for(int i=0;i<WXGDiscreteTabs;i++)WXGSpring(&_discreteE[i],&_discreteV[i],i==_selectedIndex?1.:0.,stiffness,friction,dt);
    // FIX106 B: the joins and splits (connected) start with the switch and are
    // done ~0.35 x its response in (one capsule while the new tab still widens).
    double bridgeTime=WXGDiscreteBridgeDuration(reduce?.3:c.dockDiscreteResponse);
    int connected=c.dockDiscreteConnected?1:0;
    for(int i=0;i<WXGDiscreteTabs-1;i++){_bridge[i]=WXGDiscreteBridgeStep(_bridge[i],WXGDiscreteBridgeTarget(connected,(int)_selectedIndex,i),WXGClamp(dt,0,.064),bridgeTime);_bridgeV[i]=0;}
    // FIX106 C: the joined balls' icons gather on the widths' spring.
    double gather[WXGDiscreteTabs];
    WXGDiscreteGatherTargets(connected,(int)_selectedIndex,(float)c.dockDiscreteGather,gather);
    for(int i=0;i<WXGDiscreteTabs;i++)WXGSpring(&_gather[i],&_gatherV[i],gather[i],stiffness,friction,dt);
    // What the host reads of the lens (lensArrived / lensAtRest, the license's
    // quiet check, a held switch): at rest on the selected tab, never pressed.
    _targetX=[self centerForIndex:_selectedIndex];_lensX=_targetX;_velocityX=0;
    _press=0;_pressVelocity=0;_targetPress=0;_elasticMotion=(WXGElasticMotion){0};
    BOOL moving=![self discreteSettled];
    if(moving || _discreteDirty){[self updateDiscreteGeometry];[self layoutBadges];_discreteDirty=moving;}
    for(NSInteger j=0;j<_pieceCount && j<(NSInteger)_pieces.count;j++)[_pieces[(NSUInteger)j] tick:link.timestamp];
    if(_classicLingers)[_glass tick:link.timestamp];
}
- (void)updateDiscreteGeometry {
    if(CGRectIsEmpty(_materialRect) || !_discreteView)return;
    // A piece's layout can call back here (its ready callback): the next frame redoes it.
    if(_discreteLaying){_discreteDirty=YES;return;}
    _discreteLaying=YES;
    @try {[self layDiscreteGeometry];}
    @finally {_discreteLaying=NO;}
}
- (void)layDiscreteGeometry {
    WXGConfig *c=WXGConfig.shared;int align=[self discreteAlign];
    WXGDiscreteMetrics m=WXGDiscreteFit((float)_materialRect.size.width,(float)_materialRect.size.height,(float)c.dockDiscreteBall,
                                        (float)c.dockDiscreteGap,(float)c.dockDiscreteWide,align);
    _discreteMetrics=m;
    WXGDiscreteLayout(m,_discreteE,align,_tabX,_tabW);
    WXGDiscreteRun runs[WXGDiscreteTabs];
    int count=WXGDiscreteRuns(_tabX,_tabW,_bridge,m.gap,runs);
    CGFloat ox=_materialRect.origin.x,oy=round((_materialRect.origin.y+m.originY)*2)/2,h=round(m.cell*2)/2;
    _discreteRowRect=CGRectMake(ox+_tabX[0],oy,_tabX[WXGDiscreteTabs-1]+_tabW[WXGDiscreteTabs-1]-_tabX[0],h);
    BOOL live=c.renderMode>=2,settled=[self discreteSettled],pill=c.dockDiscretePill,keep=_discreteShown || _piecesLinger;
    CGFloat selectionGap=WXGSelectionGap((float)c.selectionInset,(float)h);
    CGSize size=self.bounds.size;CGPoint centre=CGPointMake(size.width*.5,size.height*.5);
    UIBezierPath *shadow=[UIBezierPath bezierPath];
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int j=0;j<count;j++) {
        WXGGlassView *piece=[self pieceAtIndex:j];
        if(!CGSizeEqualToSize(piece.bounds.size,size)){piece.bounds=(CGRect){CGPointZero,size};piece.center=centre;}
        // Half-point steps: the meshes and the field are reused within a step.
        CGFloat x0=round((ox+runs[j].x)*2)/2,x1=round((ox+runs[j].x+runs[j].w)*2)/2;
        CGRect rect=CGRectMake(x0,oy,MAX(1,x1-x0),h);
        piece.glassRect=rect;
        // 选中胶囊: the original pill on the capsule's widest tab, growing from
        // its centre as the tab widens (and shrinking away as it narrows).
        int best=-1;double widest=0;
        for(int t=runs[j].first;t<=runs[j].last;t++)if(_discreteE[t]>widest){widest=_discreteE[t];best=t;}
        CGFloat grow=pill && best>=0?WXGDiscreteSmooth(.04f,.7f,(float)widest):0;
        if(grow>.01) {
            CGRect cell=CGRectInset(CGRectMake(ox+_tabX[best],oy,_tabW[best],h),selectionGap,selectionGap);
            CGRect lens=CGRectInset(cell,cell.size.width*(1-grow)*.5,cell.size.height*(1-grow)*.5);
            piece.lensRect=CGRectMake(round(lens.origin.x*2)/2,round(lens.origin.y*2)/2,round(lens.size.width*2)/2,round(lens.size.height*2)/2);
            piece.lensAnchorX=CGRectGetMidX(lens);piece.selectionWeight=grow;
        }else {piece.lensRect=CGRectZero;piece.selectionWeight=0;}
        piece.barScale=1;piece.pressAmount=0;piece.deferShapeField=!settled;
        piece.active=_active && keep;
        piece.hidden=!keep || (!piece.ready && !live);
        [piece layoutIfNeeded];
        [shadow appendPath:[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:rect.size.height*.5]];
    }
    for(NSInteger j=count;j<(NSInteger)_pieces.count;j++){WXGGlassView *piece=_pieces[(NSUInteger)j];piece.active=NO;piece.hidden=YES;piece.lensRect=CGRectZero;}
    _pieceCount=count;
    if(_discreteShown)self.layer.shadowPath=shadow.CGPath;
    [self layoutDiscreteContent];
    for(NSInteger i=0;i<4;i++)_a11yItems[(NSUInteger)i].accessibilityFrameInContainerSpace=CGRectMake(ox+_tabX[i],oy,_tabW[i],h);
    [CATransaction commit];
}
// Each tab's icon and titles, clipped to its own capsule: a ball shows its
// icon centred; widening, the icon slides left and the titles fade in to its
// right (after ~45% of the way), the block centred in the capsule.
- (void)layoutDiscreteContent {
    if(!_tabClips.count)return;
    WXGConfig *c=WXGConfig.shared;WXGDiscreteMetrics m=_discreteMetrics;
    CGFloat ox=_materialRect.origin.x,oy=round((_materialRect.origin.y+m.originY)*2)/2,h=round(m.cell*2)/2;
    CGFloat wideW=WXGDiscreteTabWidth(m,1),spacing=MAX(4,round(h*.11)),lift=c.dockIconOffset;
    for(int i=0;i<WXGDiscreteTabs;i++) {
        UIView *clip=_tabClips[(NSUInteger)i];
        CGRect cell=CGRectMake(ox+_tabX[i],oy,_tabW[i],h);
        clip.frame=cell;clip.layer.cornerRadius=MIN(cell.size.width,cell.size.height)*.5;
        CGFloat e=WXGClamp(_discreteE[i],0,1);
        UIImageView *normal=_tabIcons[(NSUInteger)i],*selected=_tabSelectedIcons[(NSUInteger)i];
        CGFloat iconSize=MIN(c.dockDiscreteIconSize,h*.82);   // never past the ball
        CGSize ns=WXGDiscreteIconSize(normal.image,iconSize),ss=WXGDiscreteIconSize(selected.image,iconSize);
        CGFloat iconW=MAX(ns.width,ss.width);
        // The titles as wide as they are, at most what the wide capsule leaves
        // (a fifth of its height clear at each end); too little: icon only.
        CGFloat textW=MIN(_tabTextW[i],MAX(0,wideW-iconW-spacing-h*.4));
        BOOL text=textW>=14 && _tabTitles[(NSUInteger)i].text.length>0;
        float textX=0;
        // FIX106 H: the centred block moved left by 宽位内容左移 when wide (in
        // step with the expansion; never past the icon on the left cap's centre).
        CGFloat iconX=WXGDiscreteContentShifted(0,(float)cell.size.width,(float)h,(float)iconW,(float)spacing,text?(float)textW:0.f,
                                                (float)e,(float)c.dockDiscreteContentShift,&textX);
        // FIX106 C: connected, gathered toward the run's middle (a spring, so
        // it glides as the balls join or split). The titles move with it.
        CGFloat gather=_gather[i]*(m.cell+m.gap);
        iconX+=gather;textX+=(float)gather;
        CGFloat cy=h*.5+lift;
        // The icons are not clipped to their cell (gathered, they reach past it).
        CGPoint centre=CGPointMake(round((cell.origin.x+iconX)*4)/4,round((cell.origin.y+cy)*4)/4);
        normal.bounds=(CGRect){CGPointZero,ns};normal.center=centre;normal.alpha=1-e;
        selected.bounds=(CGRect){CGPointZero,ss};selected.center=centre;selected.alpha=e;
        _tabIconCentre[i]=centre;
        CGFloat reveal=text?WXGDiscreteSmooth(.45f,1.f,(float)e):0;
        UILabel *title=_tabTitles[(NSUInteger)i],*subtitle=_tabSubtitles[(NSUInteger)i];
        title.hidden=reveal<.01;subtitle.hidden=title.hidden || subtitle.text.length==0;
        if(!title.hidden) {
            CGFloat th=ceil(title.font.lineHeight),sh=subtitle.hidden?0:ceil(subtitle.font.lineHeight);
            CGFloat top=cy-(th+sh)*.5,slide=(1-reveal)*6;
            title.frame=CGRectMake(textX+slide,top,textW,th);title.alpha=reveal;
            if(!subtitle.hidden){subtitle.frame=CGRectMake(textX+slide,top+th,textW,sh);subtitle.alpha=reveal;}
        }
    }
}
- (NSInteger)discreteTabAt:(CGPoint)point {
    return WXGDiscreteTabAt(_tabX,_tabW,_discreteMetrics.gap,(float)(point.x-_materialRect.origin.x));
}
// A touch: the tab under the finger is selected at once (and, 按下时, WeChat
// is asked to switch, as the bar does); dragging past 10 pt follows the finger.
- (BOOL)beginDiscreteTracking:(UITouch *)touch {
    ++_downCount;_previewStart=0;_lastTrackingReason=@"began";WXGDockTouchForget(&_trackingPoint);
    if(_travelling)[self endTravel:_travelToken];
    if(_script.phase)[self endScript];
    CGPoint point=[touch locationInView:self];
    _initialSelected=_selectedIndex;_fingerDown=YES;_touchDownTime=CACurrentMediaTime();
    _dragging=NO;_touchStart=point;_jumping=NO;_jumpPlanEnd=0;_resumeIndex=-1;_targetPress=0;
    WXGDockTouchRemember(&_trackingPoint,point.x,point.y);
    [_feedback prepare];
    [self selectIndex:[self discreteTabAt:point] haptic:YES];
    _touchDownIndex=_selectedIndex;
    _earlyIndex=-1;_earlySent=NO;
    if(_selectedIndex!=_initialSelected && WXGConfig.shared.dockTapSwitchAtTouchDown && self.tabSwitchRequest) {
        NSInteger index=_selectedIndex;_earlyIndex=index;
        __weak WXGDemoBar *weakSelf=self;
        dispatch_async(dispatch_get_main_queue(),^{
            WXGDemoBar *bar=weakSelf;
            if(!bar || bar.earlyIndex!=index || !bar.tabSwitchRequest || !bar.fingerDown)return;
            bar.earlySent=bar.tabSwitchRequest(index);
        });
    }
    return YES;
}
- (void)continueDiscreteTracking:(UITouch *)touch {
    ++_moveCount;CGPoint point=[touch locationInView:self];
    WXGDockTouchRemember(&_trackingPoint,point.x,point.y);
    if(!_dragging && hypot(point.x-_touchStart.x,point.y-_touchStart.y)>10)_dragging=YES;
    if(_dragging)[self selectIndex:[self discreteTabAt:point] haptic:YES];   // a tap's slip never changes the tab
}
// The release: as the bar's (FIX88 / FIX100), without the lens.
- (void)endDiscreteTracking:(UITouch *)touch event:(UIEvent *)event {
    ++_trackingEnds;if(!touch)++_nilTrackingEnds;
    BOOL cancelledPhase=touch.phase==UITouchPhaseCancelled,confirmedEnd=touch!=nil;
    if(!touch)for(UITouch *candidate in event.allTouches) {
        UIView *target=candidate.view;
        if(target!=self && ![target isDescendantOfView:self])continue;
        if(candidate.phase==UITouchPhaseCancelled){cancelledPhase=YES;break;}
        if(candidate.phase==UITouchPhaseEnded)confirmedEnd=YES;
    }
    BOOL inactive=!_active || !self.window || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;
    BOOL cancelled=cancelledPhase || inactive || !confirmedEnd;
    CGPoint supplied=touch?[touch locationInView:self]:CGPointZero;
    BOOL hasPoint=WXGDockTouchResolve(&_trackingPoint,touch!=nil,cancelled,supplied.x,supplied.y);
    CGPoint p=CGPointMake(_trackingPoint.x,_trackingPoint.y);
    BOOL inside=hasPoint && CGRectContainsPoint(CGRectInset(_materialRect,-35,-45),p);
    _fingerDown=NO;_dragging=NO;_jumping=NO;
    BOOL keptEarly=!inside && _earlySent && _earlyIndex>=0;
    if(keptEarly){inside=YES;[self selectIndex:_earlyIndex haptic:NO];}
    if(!inside)[self selectIndex:_initialSelected haptic:NO];
    _targetX=[self centerForIndex:_selectedIndex];_targetPress=0;
    _lastTrackingReason=inactive?@"ended_inactive":(cancelledPhase?@"ended_cancelled":(!confirmedEnd?@"nil_end_unconfirmed":
        (inside?(touch?@"committed":@"committed_saved_point"):(hasPoint?@"ended_outside":@"ended_without_point"))));
    if(keptEarly)_lastTrackingReason=@"kept_touch_down_switch";
    WXGDockTouchForget(&_trackingPoint);
    if((!inside || (_selectedIndex==_initialSelected && _touchDownIndex!=_initialSelected)) && ++_uncommittedEnds<=20)
        WXGLog(@"底栏（离散）：松手没有切换（%@，按下 %.2f s，按在第 %ld 个，松手时第 %ld 个，原来第 %ld 个）",_lastTrackingReason,CACurrentMediaTime()-_touchDownTime,
               (long)_touchDownIndex+1,(long)_selectedIndex+1,(long)_initialSelected+1);
    if(inside) {
        ++_trackingCommits;_lastCommittedIndex=_selectedIndex;
        _switchedAtTouchDown=_earlySent && _earlyIndex==_selectedIndex;   // FIX100
        [self sendActionsForControlEvents:UIControlEventValueChanged];
        _switchedAtTouchDown=NO;
    }
    _resumeIndex=-1;_earlyIndex=-1;_earlySent=NO;
}
- (NSString *)discreteSummary {
    WXGConfig *c=WXGConfig.shared;
    return [NSString stringWithFormat:@"离散底栏 %@%@ | 胶囊 %ld 块 | 球 %.1f pt 间距 %.1f 宽 %.2f 格 | 相连 %d 胶囊 %d 轻量 %d | 弹簧 %.2f/%.2fs | 切换 %lu 次 已静止 %d",
        _discreteShown?@"开":@"关",_classicLingers?@"(淡入)":_piecesLinger?@"(淡出)":@"",(long)_pieceCount,_discreteMetrics.cell,_discreteMetrics.gap,_discreteMetrics.wide,
        c.dockDiscreteConnected,c.dockDiscretePill,c.dockDiscreteLight,c.dockDiscreteDamping,c.dockDiscreteResponse,(unsigned long)_discreteSwitches,[self discreteSettled]];
}
#pragma mark - FIX60 search morph
// While the dock search is open (or opening / closing) the bar's glass takes
// the outline the host computes (capsule -> round close button). The tabs
// are then drawn by plain layers, exactly as at rest (unselected icons with
// a hole at the pill, the pill tint, the selected icons inside it), so they
// can fade and blur out (nothing here holds a backdrop: FIX37). The Metal
// overlay and the lens return, drawn first, once the outline is back.
- (void)setSearchMode:(BOOL)searchMode {
    if(_searchMode==searchMode)return;
    _searchMode=searchMode;
    if(_closeTracking){_closeTracking=NO;[self setClosePressed:NO];}
    if(searchMode){if(_travelling)[self finishTravelNow];[self cancelInteraction];}
    self.accessibilityElements=searchMode?(_showsClose?@[_closeItem]:@[]):_a11yItems;
}
- (void)setShowsClose:(BOOL)showsClose {
    if(_showsClose==showsClose)return;
    _showsClose=showsClose;
    if(_searchMode)self.accessibilityElements=showsClose?@[_closeItem]:@[];
    if(!showsClose)_closeIcon.alpha=0;
}
- (void)ensureMorphLayers {
    if(_morphView)return;
    _morphView=[[UIView alloc]initWithFrame:self.bounds];_morphView.userInteractionEnabled=NO;_morphView.hidden=YES;
    [self insertSubview:_morphView aboveSubview:_glass];
    _morphMask=[CALayer layer];_morphMask.backgroundColor=UIColor.blackColor.CGColor;_morphMask.cornerCurve=kCACornerCurveContinuous;
    _morphView.layer.mask=_morphMask;
    _morphContent=[CALayer layer];
    _morphNormal=[CALayer layer];_morphHole=[CALayer layer];
    _morphHole.contents=(__bridge id)WXGTravelHoleImage().CGImage;_morphNormal.mask=_morphHole;
    _morphPill=[CALayer layer];_morphPill.masksToBounds=YES;_morphPill.cornerCurve=kCACornerCurveContinuous;
    _morphSelected=[CALayer layer];[_morphPill addSublayer:_morphSelected];
    [_morphContent addSublayer:_morphNormal];[_morphContent addSublayer:_morphPill];
    [_morphView.layer addSublayer:_morphContent];
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
    UIImage *glyph=[[UIImage systemImageNamed:@"xmark" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _closeIcon=[[UIImageView alloc]initWithImage:glyph];
    _closeIcon.tintColor=UIColor.labelColor;_closeIcon.contentMode=UIViewContentModeCenter;_closeIcon.alpha=0;
    [_morphView addSubview:_closeIcon];
}
// The tabs exactly as the overlay draws them at rest.
- (void)loadMorphContent {
    if(!_morphView || CGRectIsEmpty(_materialRect))return;
    WXGConfig *c=WXGConfig.shared;[self loadTravelColors];
    float w=(float)_materialRect.size.width,h=(float)_materialRect.size.height,gap=(float)[self selectionGap];
    WXGDockGeometry rest=WXGDockLayout(w,h,gap,(float)([self centerForIndex:_selectedIndex]-_materialRect.origin.x),0,
                                       (float)c.lensGrowth,0,(float)c.barGrowth,(float)c.endWrap);
    CGRect pill=CGRectMake(_materialRect.origin.x+rest.lensX,_materialRect.origin.y+rest.lensY,rest.lensWidth,rest.lensHeight);
    CGSize size=self.bounds.size;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _morphContent.frame=self.bounds;_morphNormal.frame=self.bounds;
    _morphNormal.contents=(__bridge id)_normalAtlas.CGImage;_morphNormal.contentsScale=_normalAtlas.scale>0?_normalAtlas.scale:1;
    _morphHole.bounds=CGRectMake(0,0,pill.size.width*WXG_HOLE_KW,pill.size.height*WXG_HOLE_KH);
    _morphHole.position=CGPointMake(CGRectGetMidX(pill),CGRectGetMidY(pill));
    _morphPill.frame=pill;_morphPill.cornerRadius=pill.size.height*.5;
    _morphPill.backgroundColor=[self travelTintForPress:0].CGColor;
    _morphSelected.frame=CGRectMake(-pill.origin.x,-pill.origin.y,size.width,size.height);
    _morphSelected.contents=(__bridge id)_selectedAtlas.CGImage;_morphSelected.contentsScale=_selectedAtlas.scale>0?_selectedAtlas.scale:1;
    [CATransaction commit];
}
- (void)beginMorph {
    [self ensureMorphLayers];
    if(_travelling)[self finishTravelNow];
    [self cancelInteraction];
    _morphing=YES;++_morphToken;++_morphs;
    [self loadMorphContent];
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _morphView.frame=self.bounds;_morphView.hidden=NO;
    _glass.shapeAnimating=YES;_glass.lensSuppressed=YES;_glass.overlayHidden=YES;
    [CATransaction commit];
    [self syncDiscreteVisibility];   // 离散底栏: the bar takes over for the morph (crossfade)
}
- (void)setSearchShape:(CGRect)shape progress:(CGFloat)progress {
    progress=WXGClamp(progress,0,1);
    BOOL rest=progress<.001 && fabs(CGRectGetMinX(shape)-CGRectGetMinX(_materialRect))<.25 && fabs(shape.size.width-_materialRect.size.width)<.25 &&
        fabs(CGRectGetMinY(shape)-CGRectGetMinY(_materialRect))<.25 && fabs(shape.size.height-_materialRect.size.height)<.25;
    if(rest || CGRectIsEmpty(_materialRect)){if(_morphing)[self endMorph];return;}
    if(!_morphing)[self beginMorph];
    _morphShape=shape;_morphProgress=progress;
    CGFloat radius=MIN(shape.size.width,shape.size.height)*.5;
    float fade=WXGDockSearchTabsFade((float)progress),close=WXGDockSearchCloseReveal((float)progress);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _glass.glassRect=shape;
    self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:shape cornerRadius:radius].CGPath;
    _morphMask.frame=shape;_morphMask.cornerRadius=radius;
    _morphContent.opacity=1.f-fade;
    _closeIcon.alpha=_showsClose?close:0;
    CGSize glyph=_closeIcon.image.size;
    _closeIcon.bounds=CGRectMake(0,0,MAX(24,glyph.width),MAX(24,glyph.height));
    _closeIcon.center=CGPointMake(CGRectGetMidX(shape),CGRectGetMidY(shape));
    CGFloat badges=1-WXGDockSearchSmooth(0.f,.3f,(float)progress);
    for(UILabel *b in _badges)b.alpha=badges;
    [CATransaction commit];
}
- (void)endMorph {
    if(!_morphing)return;
    _morphing=NO;NSUInteger token=++_morphToken;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _glass.glassRect=_materialRect;_glass.lensSuppressed=_travelling;
    self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:_materialRect cornerRadius:_materialRect.size.height*.5].CGPath;
    _morphContent.opacity=1;_closeIcon.alpha=0;
    for(UILabel *b in _badges)b.alpha=1;
    [self updateGeometry];
    [CATransaction commit];
    _glass.shapeAnimating=NO;
    [self revealAfterMorph:token attempt:0];
}
// As after the tap animation: the overlay is drawn first, then shown and the
// plain layers removed in one commit (both show the same tabs).
- (void)revealAfterMorph:(NSUInteger)token attempt:(NSUInteger)attempt {
    if(_morphing || token!=_morphToken)return;
    if(!_travelling && ![_glass drawNow] && attempt<6) {
        __weak WXGDemoBar *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.016*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf revealAfterMorph:token attempt:attempt+1];});
        return;
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!_travelling)_glass.overlayHidden=NO;
    _morphView.hidden=YES;
    [CATransaction commit];
}
- (BOOL)lensArrived {return !_fingerDown && fabs(_lensX-_targetX)<2 && fabs(_velocityX)<120;}
// FIX95: WeChat's tab switch waits while the real lens is on its way (the
// glide of a touch still down, the landing until the lens is down).
// FIX98: until the moment chosen (WXGScriptHoldsSwitch).
- (BOOL)holdsTabSwitch {return [self holdsTabSwitchAtMoment:WXGConfig.shared.dockTapSwitchMoment];}
- (BOOL)holdsTabSwitchAtMoment:(NSInteger)moment {
    if(!_script.phase)return NO;
    return WXGScriptHoldsSwitch(&_script,[self animationNow],(int)moment)!=0;
}
// FIX99: the host is about to forward a tab switch: the stall that follows
// (and the slow frames after it) pause the lens (WXGScriptClockAdvance).
- (void)noteTabSwitchForwarding {
    _switchAt=CACurrentMediaTime();
    if(_tapOpen)_tapSwitchAt=_switchAt;
}
// FIX102: after a pause the rest runs a little faster (WXGScriptCatchUp), so a
// tap still lands close to when it would have (user: FIX101 felt slower).
- (void)catchUpAfterPause:(double)pause {
    if(!_script.phase || !WXGConfig.shared.dockTapCatchUp)return;
    double f=WXGScriptCatchUp(&_script,_animClock,pause);
    if(f<1 && _jumpPlanEnd>0)_jumpPlanEnd=_animClock+(_jumpPlanEnd-_animClock)*f;
    if(f<1)_tapCaughtUp+=(1-f);
}
// FIX100: and it has returned: the script moves on by exactly that long (the
// lens is where it stopped, however long WeChat took), the clock is real time
// again, and the busy frames of the next 0.8 s are capped from here.
- (void)tabSwitchForwardedFrom:(CFTimeInterval)before {
    CFTimeInterval real=CACurrentMediaTime();
    double stall=real-before;
    if(_script.phase && stall>.002) {
        // Where the script was when the switch began (the clock plus the time
        // not counted yet), shown from now: shift it so the clock is real time.
        double since=MAX(0,MIN(before-_animClockReal,WXGScriptClockCap));
        double shift=real-_animClock-since;
        if(shift>0){WXGScriptShift(&_script,shift);if(_jumpPlanEnd>0)_jumpPlanEnd+=shift;_clockLostMS+=shift*1000;++_clockStalls;}
        _animClock=real;_animClockReal=real;
        if(shift>0)[self catchUpAfterPause:shift];   // FIX102
    }
    _switchAt=real;
    // FIX101: and waits for WeChat's busy frames to pass before it goes on.
    if(_script.phase && WXGConfig.shared.dockTapWaitForCalm){_calmWaitFrom=real;_calmHoldClock=_animClock;_calmLastTick=0;_calmFrames=0;}
}
// FIX99: the first 12 taps after launch (diagnostics `taps`; the first 6 also
// logged): planned against actual length, the longest frame, where the switch
// went, so a sluggish cold start shows what it was.
- (void)beginTapRecord:(NSInteger)kind {
    if(_tapOpen)[self finishTapRecord:NO];
    if(_tapRecords.count>=12)return;
    _tapOpen=YES;_tapKind=kind;_tapStartReal=CACurrentMediaTime();_tapSwitchAt=0;_tapLastFrame=0;_tapLongestFrame=0;_tapLostAtStart=_clockLostMS;
    _tapCalmWait=0;_tapCaughtUp=0;_tapSlowFrames=[NSMutableArray array];
}
- (void)tapFrameAt:(CFTimeInterval)timestamp {
    if(!_tapOpen)return;
    if(_tapLastFrame>0 && timestamp-_tapLastFrame>_tapLongestFrame)_tapLongestFrame=timestamp-_tapLastFrame;
    // FIX101: each frame over 25 ms: when (from the touch) and how long.
    if(_tapLastFrame>0 && timestamp-_tapLastFrame>.025 && _tapSlowFrames.count<10)
        [_tapSlowFrames addObject:@[@(round((_tapLastFrame-_tapStartReal)*1000)),@(round((timestamp-_tapLastFrame)*1000))]];
    _tapLastFrame=timestamp;
}
- (void)finishTapRecord:(BOOL)landed {
    if(!_tapOpen)return;
    _tapOpen=NO;if(!_tapRecords)_tapRecords=[NSMutableArray array];
    CFTimeInterval real=CACurrentMediaTime();
    double planned=_script.phase==2?(_script.end-_script.moveStart)*1000:-1,actual=(real-_tapStartReal)*1000;
    double switchAt=_tapSwitchAt>0?(_tapSwitchAt-_tapStartReal)*1000:-1;
    NSDictionary *record=@{@"since":@(round((WXGSecondsSinceLoad()-(real-_tapStartReal))*10)/10),@"kind":_tapKind==1?@"glide":@"travel",
        @"to":@(_script.index+1),@"landed":@(landed),@"plannedMS":@(round(planned)),@"actualMS":@(round(actual)),
        @"longestFrameMS":@(round(_tapLongestFrame*1000)),@"switchAtMS":@(round(switchAt)),@"pausedMS":@(round(_clockLostMS-_tapLostAtStart)),
        @"calmWaitMS":@(round(_tapCalmWait*1000)),@"catchUp":@(round(_tapCaughtUp*100)/100),@"slowFrames":_tapSlowFrames?:@[]};
    [_tapRecords addObject:record];
    if(_tapRecords.count<=6)
        WXGLog(@"底栏：点按 #%lu（启动后 %.1f s，%@到第 %ld 个）：%@计划 %.0f ms，实际 %.0f ms，最长一帧 %.0f ms，微信切换%@，暂停 %.0f ms，等空闲 %.0f ms，慢帧 %lu 个",
               (unsigned long)_tapRecords.count,[record[@"since"] doubleValue],_tapKind==1?@"点按":@"松手",(long)_script.index+1,landed?@"":@"（被打断）",
               planned,actual,_tapLongestFrame*1000,switchAt>=0?[NSString stringWithFormat:@"在第 %.0f ms",switchAt]:@"不在动画里",_clockLostMS-_tapLostAtStart,
               _tapCalmWait*1000,(unsigned long)_tapSlowFrames.count);
}
// FIX98: the colour a script showed carries on from there (decaying in tick).
// A glide's plan (for a travel taking over) goes back to real time: the clock
// may lag it by a stall, and is real time again once no script runs.
- (void)endScript {
    if(_tapOpen)[self finishTapRecord:_script.phase==2 && _animClock>=_script.end];
    if(_script.phase)_selectionCarry=WXGClamp(_selectionShown,0,1)-WXGRestingSelectionWeight(WXGClamp(_press,0,1));
    if(_script.phase==1 && _jumpPlanEnd>0){CFTimeInterval clock=[self animationNow];_jumpPlanEnd+=CACurrentMediaTime()-clock;}
    _script=(WXGDockScript){0};
}
// FIX98: the script's clock. Each call advances it by the real time since the
// last: WeChat's tab switch and the frames after it stall the main thread
// 0.1-0.3 s; the lens then pauses and carries on from where it was instead of
// jumping ahead. FIX99: only around a switch this dock forwarded (one 60 Hz
// frame per step there, at most 0.5 s behind); elsewhere real time, so a busy
// cold start no longer plays the tap in slow motion.
- (CFTimeInterval)animationNow {
    // Between scripts it is real time again (no lag left for the next one).
    CFTimeInterval real=CACurrentMediaTime();
    if(_animClockReal<=0 || !_script.phase){_animClockReal=real;_animClock=real;return real;}
    CFTimeInterval next=WXGScriptClockAdvance(_animClock,_animClockReal,real,_switchAt);   // FIX99: capped only around a forwarded switch
    double lost=(real-_animClockReal)-(next-_animClock);
    if(lost>.001){++_clockStalls;_clockLostMS+=lost*1000;}
    _animClock=next;_animClockReal=real;
    if(lost>.01)[self catchUpAfterPause:lost];   // FIX102
    return next;
}
// 离散底栏: at rest once every spring has settled too (the license's quiet check).
- (BOOL)lensAtRest {return self.lensArrived && _targetPress<=0 && _press<.06 && (!_discreteShown || [self discreteSettled]);}
- (NSString *)diagnostics {
    WXGConfig *c=WXGConfig.shared;
    WXGScopeOptics dock=[c opticsForDock:YES];
    return [NSString stringWithFormat:@"TEST9 呼出/收回；运动形变 %@；按压 %.3f；速度 %.1f pt/s；形变 %.3f\n底栏：折射 %.2f / 色散 %.2f / 宽度 %.1f pt\n透镜：折射 %.2f / 色散 %.2f / 宽度 %.1f pt\n底栏模糊 %.2f pt / 覆盖 %.0f%%\n%@",
        @"elastic",WXGClamp(_press,0,1),_velocityX,_elasticMotion.stretch,
        dock.refraction,dock.dispersion,dock.edgeWidth,c.lensRefraction,c.lensDispersion,c.lensEdgeWidth,dock.blur,dock.blurCoverage,
        _discreteShown?[[self discreteSummary] stringByAppendingFormat:@"\n%@",_pieces.firstObject.diagnostics?:@""]:_glass.diagnostics];
}
@end
