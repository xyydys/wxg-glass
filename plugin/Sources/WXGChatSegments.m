#import "WXGIntegration.h"
#import "WXGElasticMotion.h"
#import "WXGDockTouchPolicy.h"
#import "WXGPressStretch.h"
#import "WXGDockScript.h"
#import "WXGHomeSearchLayout.h"
#import "WXGHomeCategories.h"
#import "WXGSegmentLayout.h"
#import <malloc/malloc.h>
#import <stdatomic.h>
#import <dlfcn.h>
#import <execinfo.h>

/* FIX113 N: the chat list's segment bar (user: replace the search field
   entirely with a segmented control like the system's: a capsule groove a
   little darker than the background, exactly the search field's size; the
   selected segment a capsule of the background's own colour; pressed and
   held it turns into the lens and slides, a tap switches as the dock does,
   with the dock's parameters for now; the grouping itself can be a demo
   first, reading what is not known yet).

   WXGSegmentBar is the dock's lens on four text segments: a WXGGlassView
   with the dock's surface (its lens, optics, rim, growth, elastic motion,
   tap script, end stretch: WXGDockLayout / WXGDockScript / WXGElasticMotion,
   as WXGDemoBar drives them). FIX113 O: its own range 分组 (glassScopeOverride:
   every glass setting of its own, its background colour the range's
   material) and its own lens and pill parameters (WXGLensSettings of 分组);
   the resting selection is the pill colour. FIX113 P (user: the dock's look,
   tuned from there, rather than the system's segmented control): all of it
   starts from the dock's values (glass, rim, material, the selection colour
   fading while pressed, the selected title in the accent colour).

   WXGChatSegments puts it over the chat list's search bar (the list's table
   header: it scrolls with the list) at the search field's rectangle, hides
   WeChat's bar (alpha, restorable) and gives it back while WeChat's own
   search uses it, when the switch is off, the plugin is off / not authorised
   or not in render-server mode. The grouping (全部 / 未读 / 单聊 / 群聊) is a
   demo: switching filters nothing yet. What the next step needs is read
   (chatList in the diagnostics): the list's data source, the session object
   behind a cell and the path to its user name / unread count, the arrays the
   page keeps, WeChat's contact-label classes. */

static UIFont *WXGSegmentFont(CGFloat size,NSInteger weight,BOOL selected) {
    static const CGFloat weights[5]={-.4,0,.23,.3,.4};
    NSInteger step=(NSInteger)WXGClamp(weight+(selected?1:0),0,4);
    return [UIFont systemFontOfSize:size weight:weights[step]];
}

@class WXGSegmentBar;
@interface WXGSegmentTicker : NSObject
@property(nonatomic,weak) WXGSegmentBar *owner;
- (void)tick:(CADisplayLink *)link;
@end
@interface WXGSegmentItem : UIAccessibilityElement
@property(nonatomic,copy) BOOL (^activate)(void);
@end
@implementation WXGSegmentItem
- (BOOL)accessibilityActivate {return self.activate?self.activate():NO;}
@end

@interface WXGSegmentBar : UIControl <WXGListGroupControl>
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL fitsTitlePair,acceptsReselection;
@property(nonatomic,strong) UIColor *pillColor,*inkColor;
@property(nonatomic,strong) UIColor *accentColor;   // FIX113 P: the selected title's (nil: the ink)
@property(nonatomic,copy) NSArray<NSString *> *titles;   // FIX113 R: the groups' names (1-6)
@property(nonatomic,readonly) CGRect materialRect;
- (void)tick:(CADisplayLink *)link;
- (void)wake;
- (void)refreshLook;
- (CGFloat)currentLensX;
- (void)returnToIndex:(NSInteger)index;   // FIX113 Q: a refused switch (the lens slides back)
- (NSDictionary *)evidence;
@end
@implementation WXGSegmentTicker
- (void)tick:(CADisplayLink *)link {[self.owner tick:link];}
@end

@implementation WXGSegmentBar {
    UIView *_fallbackPill;UIImageView *_fallbackTitles;
    CADisplayLink *_link;WXGSegmentTicker *_ticker;NSInteger _idleFrames;
    UISelectionFeedbackGenerator *_feedback;
    NSArray<WXGSegmentItem *> *_items;
    double _lensX,_velocityX,_targetX,_press,_pressVelocity,_targetPress;
    WXGElasticMotion _elastic;WXGStretchState _endStretch;int _endStretchSide;
    WXGLensFlex _flex;            // FIX126: the system's (two followers of the lens)
    CFTimeInterval _lastTime,_stillSince;
    BOOL _fingerDown,_dragging;CGPoint _touchStart;
    NSInteger _initialSelected,_touchDownIndex,_resumeIndex;
    WXGDockTouchPoint _trackingPoint;double _jumpPlanEnd;
    WXGDockScript _script;double _selectionShown,_selectionCarry;
    CGSize _previousSize;CGFloat _previousGap;
    NSString *_iconKey;
    WXGSegmentSlots _slots;
    float _titleAdvances[2];
    CGFloat _measuredFontSize;
    NSInteger _measuredWeight;
    NSUInteger _downs,_glides,_travels,_drops,_drags,_commits,_draws,_cancels;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.clipsToBounds=NO;self.isAccessibilityElement=NO;
        _resumeIndex=-1;_selectionShown=1;
        _glass=[[WXGGlassView alloc] initWithFrame:self.bounds];_glass.dockSurface=YES;_glass.mainDockOptics=YES;_glass.glassScopeOverride=WXGGlassScopeSegment;_glass.userInteractionEnabled=NO;
        [self addSubview:_glass];
        // Until the overlay's first frame (cold start: the shader may still be
        // on its way) the pill and the titles are plain layers; the background is
        // the glass's own render-server veil, there at once.
        _fallbackPill=[UIView new];_fallbackPill.userInteractionEnabled=NO;_fallbackPill.layer.cornerCurve=kCACornerCurveContinuous;
        [self addSubview:_fallbackPill];
        _fallbackTitles=[UIImageView new];_fallbackTitles.userInteractionEnabled=NO;[self addSubview:_fallbackTitles];
        __weak WXGSegmentBar *weakSelf=self;
        _glass.onReady=^(__unused BOOL ready){WXGSegmentBar *bar=weakSelf;[bar rebuildTitles:YES];[bar wake];};
        _glass.onFirstFrame=^{WXGSegmentBar *bar=weakSelf;if(!bar)return;bar->_fallbackPill.hidden=YES;bar->_fallbackTitles.hidden=YES;};
        _feedback=[UISelectionFeedbackGenerator new];
        _ticker=[WXGSegmentTicker new];_ticker.owner=self;
        _link=[CADisplayLink displayLinkWithTarget:_ticker selector:@selector(tick:)];_link.paused=YES;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        _titles=@[@"全部"];[self makeItems];
    }
    return self;
}
- (void)dealloc {[_link invalidate];}
- (NSInteger)count {return (NSInteger)MAX((NSUInteger)1,MIN(_titles.count,(NSUInteger)WXG_SEGMENTS_MAX));}
- (void)makeItems {
    __weak WXGSegmentBar *weakSelf=self;NSMutableArray *items=[NSMutableArray array];
    for(NSInteger i=0;i<self.count;i++) {
        WXGSegmentItem *item=[[WXGSegmentItem alloc] initWithAccessibilityContainer:self];
        item.accessibilityLabel=_titles[(NSUInteger)i];item.accessibilityHint=@"切换聊天分组";
        item.activate=^BOOL{WXGSegmentBar *bar=weakSelf;if(!bar.active)return NO;[bar commitIndex:i];return YES;};
        [items addObject:item];
    }
    _items=items;self.accessibilityElements=items;
}
// FIX113 R: the groups changed (names, how many): the titles, the slots, the
// lens where the selection is now.
- (void)setTitles:(NSArray<NSString *> *)titles {
    NSArray *clean=titles.count?[titles subarrayWithRange:NSMakeRange(0,MIN(titles.count,(NSUInteger)WXG_SEGMENTS_MAX))]:@[@"全部"];
    if([clean isEqualToArray:_titles?:@[]])return;
    _titles=[clean copy];_measuredFontSize=0;[self makeItems];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,nil);
    [self cancelInteraction];
    if(_selectedIndex>self.count-1)_selectedIndex=self.count-1;
    _previousSize=CGSizeZero;   // layoutSubviews puts the lens on the selection again
    [self setNeedsLayout];[self rebuildTitles:YES];[self wake];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    WXGConfigureDisplayLink(_link,self.window.screen);
    _glass.active=_active && self.window;
    if(!self.window)[self cancelInteraction];
    [self wake];
}
- (void)setActive:(BOOL)active {
    if(_active==active)return;
    _active=active;_glass.active=active && self.window;
    if(!active)[self cancelInteraction];
    [self wake];
}
- (void)wake {
    _idleFrames=0;
    BOOL run=_active && self.window;
    if(run && _link.paused){_lastTime=0;_link.paused=NO;}
    else if(!run)_link.paused=YES;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous && ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])return;
    [_glass invalidateBackdrop];[self wake];
}
#pragma mark Colours and titles
- (void)setPillColor:(UIColor *)color {
    if(color==_pillColor || [color isEqual:_pillColor])return;
    _pillColor=color;_glass.selectionOverride=color;_fallbackPill.backgroundColor=color?:[UIColor colorWithWhite:self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?1:0 alpha:.12];[self wake];
}
- (void)setInkColor:(UIColor *)color {
    if(color==_inkColor || [color isEqual:_inkColor])return;
    _inkColor=color;[self rebuildTitles:NO];[self wake];
}
- (void)setAccentColor:(UIColor *)color {
    if(color==_accentColor || [color isEqual:_accentColor])return;
    _accentColor=color;[self rebuildTitles:NO];[self wake];
}
// R20: synchronize directly with dock's validated R8-Aurora style scaled proportionally by height / 62pt.
- (CGFloat)dockScale {return WXGClamp(_materialRect.size.height/62.,.35,1.);}
- (WXGLensSettings)lens {return [WXGConfig.shared lensSettingsForScope:WXGGlassScopeSegment dark:self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark];}
- (CGFloat)selectionGapForHeight:(CGFloat)height {
    CGFloat s=WXGClamp(height/62.,.35,1.);
    CGFloat inset=WXGConfig.shared.dockPureGlassMode?WXGConfig.shared.selectionInset*s:[self lens].selectionInset;
    return WXGSelectionGap(inset,height);
}
- (CGFloat)selectionGap {return [self selectionGapForHeight:_materialRect.size.height];}
- (void)measureTitlePair {
    if(!_fitsTitlePair || _titles.count!=2)return;
    WXGConfig *config=WXGConfig.shared;
    CGFloat size=WXGClamp([config extraNumber:@"segmentTitleSize"],10,18);
    NSInteger weight=lround([config extraNumber:@"segmentTitleWeight"]);
    if(size==_measuredFontSize && weight==_measuredWeight)return;
    NSDictionary *normal=@{NSFontAttributeName:WXGSegmentFont(size,weight,NO)};
    NSDictionary *selected=@{NSFontAttributeName:WXGSegmentFont(size,weight,YES)};
    for(NSUInteger i=0;i<2;i++) {
        NSString *title=_titles[i];
        _titleAdvances[i]=MAX([title sizeWithAttributes:normal].width,[title sizeWithAttributes:selected].width);
    }
    _measuredFontSize=size;_measuredWeight=weight;
    _previousSize=CGSizeZero;
}
- (CGFloat)preferredTitleWidthForHeight:(CGFloat)height {
    [self measureTitlePair];
    return ceil(WXGTitlePreferredWidth(height,[self selectionGapForHeight:height],_titleAdvances));
}
- (CGFloat)centerForIndex:(NSInteger)index {return CGRectGetMinX(_materialRect)+WXGSegmentCenter(_slots,(int)index);}
- (CGFloat)atlasScale {
    WXGConfig *cfg=WXGConfig.shared;
    CGFloat zoom=cfg.dockPureGlassMode?[cfg pureDockIconZoom]:[self lens].zoom;
    CGFloat grow=cfg.dockPureGlassMode?[cfg pureDockBarGrowth]:[self lens].barGrowth;
    return WXGCaptureScale(self.window.screen.scale?:UIScreen.mainScreen.scale)*MAX(1,zoom)*MAX(1,grow);
}
// The titles at their segments' centres, the whole view's size (the
// glass's icon atlases): the body draws the unselected ones, the lens the
// selected ones (a little heavier), magnified with it.
- (UIImage *)titlesSelected:(BOOL)selected {
    CGSize size=self.bounds.size;if(size.width<1 || size.height<1 || CGRectIsEmpty(_materialRect) || _slots.count!=self.count)return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=[self atlasScale];format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    WXGConfig *c=WXGConfig.shared;
    CGFloat fontSize=WXGClamp([c extraNumber:@"segmentTitleSize"],10,18);
    UIFont *font=WXGSegmentFont(fontSize,lround([c extraNumber:@"segmentTitleWeight"]),selected);
    if(_slots.fontScale>0 && _slots.fontScale<1)font=[font fontWithSize:fontSize*_slots.fontScale];
    UIColor *ink=(selected?_accentColor:nil)?:_inkColor?:[UIColor colorWithWhite:0 alpha:.86];   // FIX113 P: the selected one in the accent colour, as the dock
    NSArray *titles=_titles;NSInteger count=self.count;CGFloat midY=CGRectGetMidY(_materialRect);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:ink};
        for(NSInteger i=0;i<count;i++) {
            CGFloat slot=self->_slots.edges[i+1]-self->_slots.edges[i]-6;
            NSString *title=titles[(NSUInteger)i];CGSize t=[title sizeWithAttributes:attrs];
            if(t.width>slot && slot>10) {   // a long name: smaller to fit its slot
                UIFont *fit=[font fontWithSize:MAX(9,font.pointSize*slot/t.width)];
                NSDictionary *small=@{NSFontAttributeName:fit,NSForegroundColorAttributeName:ink};t=[title sizeWithAttributes:small];
                [title drawAtPoint:CGPointMake([self centerForIndex:i]-t.width*.5,midY-t.height*.5) withAttributes:small];continue;
            }
            [title drawAtPoint:CGPointMake([self centerForIndex:i]-t.width*.5,midY-t.height*.5) withAttributes:attrs];
        }
    }];
}
- (void)refreshLook {[self rebuildTitles:NO];[self setNeedsLayout];[_glass applyStyle];[self wake];}
- (void)rebuildTitles:(BOOL)force {
    [self measureTitlePair];
    if(!CGSizeEqualToSize(_previousSize,self.bounds.size) || fabs(_previousGap-[self selectionGap])>.01)return;
    CGFloat r=0,g=0,b=0,a=0;[(_inkColor?:UIColor.blackColor) getRed:&r green:&g blue:&b alpha:&a];
    CGFloat ar=-1,ag=-1,ab=-1,aa=-1;if(_accentColor)[_accentColor getRed:&ar green:&ag blue:&ab alpha:&aa];
    WXGConfig *c=WXGConfig.shared;
    NSString *key=[NSString stringWithFormat:@"%@/%.3f/%.2f%.2f%.2f%.2f/%.2f%.2f%.2f%.2f/%.1f/%.0f/%.2f/%@",NSStringFromCGRect(_materialRect),[self atlasScale],r,g,b,a,ar,ag,ab,aa,
                   [c extraNumber:@"segmentTitleSize"],[c extraNumber:@"segmentTitleWeight"],[self selectionGap],[_titles componentsJoinedByString:@"|"]];
    if(!force && [key isEqual:_iconKey])return;
    UIImage *normal=[self titlesSelected:NO],*selected=[self titlesSelected:YES];
    if(!normal || !selected)return;
    _iconKey=key;
    [_glass setNormalIcons:normal selectedIcons:selected];
    _fallbackTitles.image=normal;
}
#pragma mark Layout
- (void)layoutSubviews {
    [super layoutSubviews];
    _materialRect=CGRectInset(self.bounds,WXGCanvasPaddingX,WXGCanvasPaddingY);
    if(_materialRect.size.width<8 || _materialRect.size.height<8)return;
    _glass.bounds=(CGRect){CGPointZero,self.bounds.size};_glass.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    _glass.glassRect=_materialRect;
    _fallbackTitles.transform=CGAffineTransformIdentity;_fallbackTitles.frame=self.bounds;
    [self measureTitlePair];
    _slots=WXGMakeSegmentSlots(_materialRect.size.width,[self selectionGap],(int)self.count,_fitsTitlePair?_titleAdvances:NULL);
    if(!CGSizeEqualToSize(_previousSize,self.bounds.size) || fabs(_previousGap-[self selectionGap])>.01) {
        _previousSize=self.bounds.size;_previousGap=[self selectionGap];
        [self cancelInteraction];
        _lensX=[self centerForIndex:_selectedIndex];_targetX=_lensX;_velocityX=0;
        [self rebuildTitles:NO];[_glass invalidateBackdrop];
    }
    for(NSInteger i=0;i<self.count && i<(NSInteger)_items.count;i++) {
        CGFloat slot=_slots.edges[i+1]-_slots.edges[i];
        _items[(NSUInteger)i].accessibilityFrameInContainerSpace=CGRectMake(CGRectGetMinX(_materialRect)+_slots.edges[i],CGRectGetMinY(_materialRect),slot,_materialRect.size.height);
        _items[(NSUInteger)i].accessibilityTraits=UIAccessibilityTraitButton|(i==_selectedIndex?UIAccessibilityTraitSelected:0);
    }
    [self updateGeometry];[self wake];
}
- (void)updateGeometry {
    if(CGRectIsEmpty(_materialRect))return;
    WXGConfig *cfg=WXGConfig.shared;
    BOOL pure=cfg.dockPureGlassMode;
    WXGLensSettings c=[self lens];
    BOOL reduce=UIAccessibilityIsReduceMotionEnabled() || (pure?!cfg.pureDockFlexOn:!c.elasticOn);
    CGFloat press=WXGClamp(_press,0,1),s=[self dockScale];
    float w=(float)_materialRect.size.width,h=(float)_materialRect.size.height,gap=(float)[self selectionGap],anchor=(float)(_lensX-_materialRect.origin.x);
    if(!_slots.count)return;
    float posT=_slots.count>1?WXGSegmentProgress(_slots,anchor):.5f;
    float growth=(float)(pure?[cfg pureDockLensGrowth]:c.growth);
    float barGrow=(float)(pure?[cfg pureDockBarGrowth]:c.barGrowth);
    float endWrap=(float)(pure?[cfg pureDockEndWrap]*s:c.endWrap);
    float liftW=(float)(pure?[cfg pureDockLensLiftWidth]*s:0.);
    WXGDockGeometry g=WXGSegmentGeometry(w,h,gap,anchor,(float)press,growth,barGrow,endWrap,_slots);
    if(liftW>0.f && press>0.f) {
        float add=liftW*(float)press;
        float nw=WXG_MIN(g.lensWidth+add,g.barWidth+2.f*endWrap);
        g.lensX+=(g.lensWidth-nw)*posT;g.lensWidth=nw;
    }
    _glass.lensRestHeight=g.lensHeight;
    if(!reduce) {
        double sx=1,sy=1;
        if(pure)WXGLensFlexAdaptiveScaleAt(_flex,[cfg pureDockFlexParams],press,&sx,&sy);
        else WXGLensFlexScaleAt(_flex,cfg.lensFlexParams,press,&sx,&sy);
        float lw=WXG_MIN((float)(g.lensWidth*sx),g.barWidth+2.f*endWrap),lh=(float)(g.lensHeight*sy);
        lh=(float)WXGLensFlexRestingHeight(lh,g.barHeight,press,1.);
        g.lensX+=(g.lensWidth-lw)*posT;g.lensY+=(g.lensHeight-lh)*.5f;g.lensWidth=lw;g.lensHeight=lh;
    }
    CGRect lens=CGRectMake(_materialRect.origin.x+g.lensX,_materialRect.origin.y+g.lensY,g.lensWidth,g.lensHeight);
    _glass.barScale=g.scale;_glass.lensAnchorX=_materialRect.origin.x+g.anchorX;
    CGFloat selection=_script.phase?_selectionShown:WXGClamp(WXGRestingSelectionWeight((float)press)+_selectionCarry,0,1);
    _selectionShown=selection;
    _glass.lensRect=lens;_glass.pressAmount=press;_glass.selectionWeight=selection;[_glass layoutIfNeeded];
    if(!_fallbackPill.hidden) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        _fallbackPill.frame=lens;_fallbackPill.layer.cornerRadius=MIN(lens.size.width,lens.size.height)*.5;_fallbackPill.alpha=selection;
        [CATransaction commit];
    }
}
#pragma mark Touches (WXGDemoBar's, without WeChat's tabs)
- (BOOL)pointInside:(CGPoint)point withEvent:(__unused UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(CGRectUnion(_materialRect,_glass.lensRect),-4,-6),point);
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    return !self.hidden && self.alpha>.01 && self.userInteractionEnabled && self.enabled && _active && [self pointInside:p withEvent:event]?self:nil;
}
- (void)selectIndex:(NSInteger)index haptic:(BOOL)haptic {
    index=(NSInteger)WXGClamp(index,0,self.count-1);BOOL changed=_selectedIndex!=index;_selectedIndex=index;
    if(!_fingerDown)_targetX=[self centerForIndex:index];
    if(changed && haptic && WXGConfig.shared.haptics){[_feedback selectionChanged];[_feedback prepare];}
    if(changed)for(NSInteger i=0;i<(NSInteger)_items.count;i++)_items[(NSUInteger)i].accessibilityTraits=UIAccessibilityTraitButton|(i==_selectedIndex?UIAccessibilityTraitSelected:0);
}
- (void)setSelectedIndex:(NSInteger)index {
    if(_fingerDown)return;
    [self selectIndex:index haptic:NO];
    if(!_script.phase){_lensX=_targetX;_velocityX=0;}
    [self updateGeometry];[self wake];
}
- (void)returnToIndex:(NSInteger)index {
    if(_script.phase)[self endScript];
    _fingerDown=NO;_targetPress=0;[self selectIndex:index haptic:NO];[self beginTravelToIndex:_selectedIndex];[self wake];
}
// Accessibility: a switch as a tap does it.
- (void)commitIndex:(NSInteger)index {
    index=(NSInteger)WXGClamp(index,0,self.count-1);
    if(_fingerDown || (index==_selectedIndex && !_acceptsReselection))return;
    _initialSelected=_selectedIndex;[self selectIndex:index haptic:NO];[self beginTravelToIndex:index];
    [self sendActionsForControlEvents:UIControlEventValueChanged];[self wake];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(__unused UIEvent *)event {
    if(!_active || CGRectIsEmpty(_materialRect))return NO;
    ++_downs;WXGDockTouchForget(&_trackingPoint);
    CGPoint point=[touch locationInView:self];_initialSelected=_selectedIndex;_fingerDown=YES;
    CGFloat pressBefore=WXGClamp(_press,0,1),selectionBefore=WXGClamp(_selectionShown,0,1);
    _resumeIndex=_script.phase==2?_script.index:-1;
    if(_script.phase)[self endScript];
    _targetPress=1;_press=MAX(_press,.10);[_feedback prepare];[self trackPoint:point];_touchDownIndex=_selectedIndex;
    CGFloat slot=WXGSegmentStep(_slots);
    CGFloat steps=fabs(_targetX-_lensX)/MAX(1,slot);
    _dragging=NO;_touchStart=point;_jumpPlanEnd=0;
    // Both Home bars use the segment travel duration, independent of the tab switch setting.
    if(steps>.3 && !UIAccessibilityIsReduceMotionEnabled()) {
        WXGConfig *c=WXGConfig.shared;double duration=WXGSegmentGlideDuration(steps);
        _script=WXGScriptGlide(CACurrentMediaTime(),_lensX,[self centerForIndex:_selectedIndex],duration,pressBefore,selectionBefore,_selectedIndex,c.dockTapLensShare);
        _jumpPlanEnd=_script.planEnd;++_glides;
    }
    [self wake];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(__unused UIEvent *)event {
    if(!_fingerDown)return YES;
    CGPoint point=[touch locationInView:self];
    if(!_dragging && hypot(point.x-_touchStart.x,point.y-_touchStart.y)>10) {
        _dragging=YES;_jumpPlanEnd=0;
        if(_script.phase==1){[self endScript];++_drags;_targetPress=1;}
    }
    [self trackPoint:point];[self wake];return YES;
}
- (void)trackPoint:(CGPoint)p {
    WXGDockTouchRemember(&_trackingPoint,p.x,p.y);
    CGFloat center=CGRectGetMidX(_materialRect);
    CGFloat x=center+(p.x-center)/MAX(1,_glass.barScale);
    _targetX=WXGClamp(x,[self centerForIndex:0],[self centerForIndex:self.count-1]);
    [self followEndStretch:x];
    [self selectIndex:WXGSegmentAtX(_slots,x-CGRectGetMinX(_materialRect)) haptic:YES];
}
- (void)followEndStretch:(CGFloat)x {
    WXGConfig *c=WXGConfig.shared;
    if(!c.dockEndStretch || UIAccessibilityIsReduceMotionEnabled() || !_fingerDown){[self releaseEndStretch];return;}
    CGFloat lo=[self centerForIndex:0],hi=[self centerForIndex:self.count-1],dead=8;
    int side=x>hi?1:-1;CGFloat over=side>0?x-hi-dead:lo-x-dead;
    _endStretch.tracking=1;
    if(over<=0 || (_endStretchSide && side!=_endStretchSide && fabs(_endStretch.x)>.5)){_endStretch.targetX=0;return;}
    _endStretchSide=side;_endStretch.targetX=WXGRubberBand(over,c.dockEndStretchDistance);
}
- (void)releaseEndStretch {_endStretch.tracking=0;_endStretch.targetX=0;}
- (void)applyEndStretch {
    WXGStretchPose m=WXGDockEndStretchPose(_endStretch.x,_endStretchSide?:1,CGRectGetMinX(_materialRect),CGRectGetMaxX(_materialRect),
                                          CGRectGetMidX(self.bounds),_materialRect.size.height);
    CGAffineTransform t=CGAffineTransformMake(m.a,m.b,m.c,m.d,m.tx,m.ty);
    if(CGAffineTransformEqualToTransform(_glass.transform,t))return;
    [UIView performWithoutAnimation:^{[CATransaction begin];[CATransaction setDisableActions:YES];self.glass.transform=t;[CATransaction commit];}];
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self releaseEndStretch];
    if(!_fingerDown){WXGDockTouchForget(&_trackingPoint);return;}
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
    BOOL inside=hasPoint && CGRectContainsPoint(CGRectInset(_materialRect,-35,-45),CGPointMake(_trackingPoint.x,_trackingPoint.y));
    _fingerDown=NO;
    if(!inside)[self selectIndex:_initialSelected haptic:NO];
    _targetX=[self centerForIndex:_selectedIndex];_targetPress=0;
    WXGDockTouchForget(&_trackingPoint);
    BOOL scriptOnTab=_script.phase==1 && inside && _selectedIndex==_script.index && _selectedIndex!=_initialSelected;
    if(_script.phase==1 && !scriptOnTab)[self endScript];
    if(inside) {
        ++_commits;
        if(scriptOnTab){WXGScriptDrop(&_script,CACurrentMediaTime(),WXGConfig.shared.dockTapDropDuration);++_drops;}
        else if(_selectedIndex!=_initialSelected || _resumeIndex==_selectedIndex)[self beginTravelToIndex:_selectedIndex];
        if(_selectedIndex!=_initialSelected || (_acceptsReselection && !_dragging))[self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    _resumeIndex=-1;[self wake];
}
- (void)cancelTrackingWithEvent:(__unused UIEvent *)event {
    // (diagnostics: the list's scrolling taking the touch away shows here)
    if(_fingerDown){_fingerDown=NO;++_cancels;[self selectIndex:_initialSelected haptic:NO];}
    [self cancelInteraction];
}
// A release animation from where the lens is (WXGScriptTravel, the dock's timing).
- (void)beginTravelToIndex:(NSInteger)index {
    if(UIAccessibilityIsReduceMotionEnabled() || CGRectIsEmpty(_materialRect)){_targetX=[self centerForIndex:index];_targetPress=0;return;}
    WXGConfig *c=WXGConfig.shared;CGFloat slot=MAX(1,WXGSegmentStep(_slots));
    _script=WXGScriptTravel(CACurrentMediaTime(),_lensX,[self centerForIndex:index],slot,WXGClamp(_press,0,1),WXGClamp(_selectionShown,0,1),_jumpPlanEnd,index,
                            1.,c.dockTapDropDuration,c.dockTapLensShare);
    _jumpPlanEnd=0;++_travels;_targetX=[self centerForIndex:index];_targetPress=0;
}
- (void)endScript {
    if(_script.phase)_selectionCarry=WXGClamp(_selectionShown,0,1)-WXGRestingSelectionWeight((float)WXGClamp(_press,0,1));
    _script=(WXGDockScript){0};
}
- (void)cancelInteraction {
    if(_script.phase)[self endScript];
    _resumeIndex=-1;WXGDockTouchForget(&_trackingPoint);
    _fingerDown=NO;_targetPress=0;_targetX=[self centerForIndex:_selectedIndex];
    [self releaseEndStretch];
    if(!_active || !self.window) {
        _elastic=(WXGElasticMotion){0};_press=0;_pressVelocity=0;_lensX=_targetX;_velocityX=0;_selectionCarry=0;
        _endStretch=(WXGStretchState){0};[self applyEndStretch];[self updateGeometry];
    }
}
#pragma mark Frames
- (void)tick:(CADisplayLink *)link {
    if(!_active || !self.window){_link.paused=YES;return;}
    double dt=_lastTime?link.timestamp-_lastTime:(link.targetTimestamp>link.timestamp?link.targetTimestamp-link.timestamp:1.0/60);_lastTime=link.timestamp;
    dt=WXGClamp(dt,1./240,1./20);
    BOOL reduce=UIAccessibilityIsReduceMotionEnabled();CFTimeInterval now=CACurrentMediaTime();
    // As the dock: a hold past the glide becomes the drag's lens; a landing ends at rest.
    if(_script.phase==1 && _fingerDown && now>=_script.planEnd+.02){[self endScript];_targetPress=1;}
    if(_script.phase==1 && !_fingerDown)[self endScript];
    if(_script.phase==2 && now>=_script.end){_lensX=_script.moveTo;[self endScript];_velocityX=0;_press=0;_pressVelocity=0;_targetPress=0;}
    BOOL scripted=_script.phase!=0;
    if(scripted) {
        double rate=0;
        _lensX=WXGScriptMoveAt(&_script,now,&rate);_velocityX=isfinite(rate)?rate:0;
        _press=WXGScriptPressAt(&_script,now,&rate);_pressVelocity=isfinite(rate)?rate:0;
        _selectionShown=WXGScriptSelectValue(&_script,now);
    }else if(_selectionCarry!=0) {
        _selectionCarry*=exp(-dt/.08);
        if(fabs(_selectionCarry)<.002)_selectionCarry=0;
    }
    if(!scripted)WXGSpring(&_lensX,&_velocityX,_targetX,_fingerDown?620:340,_fingerDown?39:29,dt);
    double motionDT=dt;
    if(!_fingerDown && _targetPress<=0 && !reduce)dt*=.80;
    if(!scripted)WXGSpring(&_press,&_pressVelocity,_targetPress,reduce?600:420,reduce?49:31,dt);
    dt=motionDT;
    if(!reduce)WXGElasticStep(&_elastic,_velocityX,dt);else _elastic=(WXGElasticMotion){0};
    if(!reduce && self.count>1) {
        double cellStep=([self centerForIndex:self.count-1]-[self centerForIndex:0])/(double)(self.count-1);
        if(WXGConfig.shared.dockPureGlassMode)WXGLensFlexAdaptiveStep(&_flex,_velocityX,cellStep,WXGConfig.shared.pureDockFlexParams,dt);
        else WXGLensFlexStep(&_flex,_velocityX,cellStep,WXGConfig.shared.lensFlexParams,dt);
    }else _flex=(WXGLensFlex){0};
    if(WXGStretchStep(&_endStretch,dt) || !CGAffineTransformIsIdentity(_glass.transform))[self applyEndStretch];
    BOOL still=!_fingerDown && !scripted && fabs(_press)<.002 && fabs(_pressVelocity)<.01 && fabs(_lensX-_targetX)<.05 && fabs(_velocityX)<1 &&
               fabs(_elastic.stretch)<.0005 && fabs(_elastic.velocity)<.01 && WXGLensFlexStill(_flex) && !_endStretch.tracking && fabs(_endStretch.x)<.01 && _selectionCarry==0;
    if(still){_press=0;_pressVelocity=0;_lensX=_targetX;_velocityX=0;}
    [self updateGeometry];[_glass tick:link.timestamp];++_draws;
    // At rest the overlay keeps its last frame: no ticks until something moves
    // (and nothing is left to draw: a skipped frame, a mask that came late, the
    // first frame; at most 2 s of waiting for those).
    if(still) {
        if(!_idleFrames++)_stillSince=now;
        BOOL pending=_glass.ready && (_glass.needsDraw || !_glass.hasPresentedFrame);   // a glass that cannot draw is not waited for
        if(_idleFrames>10 && (!pending || now-_stillSince>2))_link.paused=YES;
    }else _idleFrames=0;
}
- (CGFloat)currentLensX {return _lensX;}
- (NSDictionary *)evidence {
    return @{@"selected":@(_selectedIndex),@"segments":@(self.count),@"active":@(_active),@"window":@(self.window!=nil),@"frame":NSStringFromCGRect(self.frame),
             @"material":NSStringFromCGRect(_materialRect),@"lens":NSStringFromCGRect(_glass.lensRect),@"press":@(round(_press*1000)/1000),
             @"linkRunning":@(!_link.paused),@"fallbackShown":@(!_fallbackPill.hidden),@"glassReady":@(_glass.ready),@"presented":@(_glass.hasPresentedFrame),
             @"touches":@{@"down":@(_downs),@"glides":@(_glides),@"drops":@(_drops),@"travels":@(_travels),@"drags":@(_drags),@"commits":@(_commits),@"cancelled":@(_cancels)},
             @"ticks":@(_draws),@"renderer":_glass.diagnostics?:@""};
}
@end

#pragma mark - FIX113 N: reading the chat list (diagnostics only)

// A user name's kind, never the name itself.
static NSString *WXGChatUserKind(NSString *s) {
    if(![s isKindOfClass:NSString.class] || s.length<3 || s.length>96)return nil;
    if([s hasSuffix:@"@chatroom"])return @"group";
    if([s hasPrefix:@"gh_"])return @"official";
    if([s hasPrefix:@"wxid_"])return @"person";
    if([s hasSuffix:@"@openim"])return @"openim";
    if([s hasSuffix:@"@stranger"])return @"stranger";
    static NSSet *special;static dispatch_once_t once;
    dispatch_once(&once,^{special=[NSSet setWithArray:@[@"filehelper",@"brandsessionholder",@"brandservicesessionholder",@"notifymessage",@"floatbottle",
        @"medianote",@"newsapp",@"weixin",@"fmessage",@"qmessage",@"tmessage",@"qqmail",@"@placeholder_foldgroup",@"opencustomerservicemsg",@"notification_messages"]];});
    if([special containsObject:s])return [@"special:" stringByAppendingString:s];
    return nil;
}
// A pointer that is an object we may message: a tagged pointer, or a live
// heap block (a freed one has no size). Unretained ivars can dangle.
static BOOL WXGProbeSafe(const void *p) {
    if(!p)return NO;
    if((intptr_t)p<0)return YES;   // arm64 tagged pointer
    return malloc_size(p)>0;
}
// objc4's isScanned: whether the word at `offset` is in an ivar layout.
static BOOL WXGProbeScanned(const uint8_t *layout,ptrdiff_t offset) {
    if(!layout || offset<0)return NO;
    ptrdiff_t index=0,ivarIndex=offset/(ptrdiff_t)sizeof(void *);uint8_t byte;
    while((byte=*layout++)) {
        index+=byte>>4;if(index>ivarIndex)return NO;
        index+=byte&0x0F;if(index>ivarIndex)return YES;
    }
    return NO;
}
// An object ivar's value, only where the object holds it: strong (its
// layout: alive as long as the object) read as memory; weak through the
// runtime's weak load (nil once it deallocates). An ARC class's other object
// ivars are unretained (they can dangle): not followed, NULL. A class with no
// layout at all (manual reference counting, WeChat's older classes) keeps its
// references by hand: a value is taken only when, read as memory (never
// messaged), it is a live heap block whose class is exactly the ivar's
// declared class (a string: one of the string classes).
static Class WXGProbeIsa(const void *p){return object_getClass((__bridge id)(void *)p);}   // no ARC on the pointer（薄包装代替函数指针强转，避开 clang20 -Wcast-function-type-mismatch）
static BOOL WXGProbeStringClass(Class c) {
    static Class known[3];static dispatch_once_t once;
    dispatch_once(&once,^{
        NSString *heap=[NSString stringWithFormat:@"%@%@",@"wxg-probe-",NSUUID.UUID.UUIDString];   // long: a heap string
        known[0]=object_getClass(heap);known[1]=object_getClass([heap mutableCopy]);known[2]=object_getClass(@"wxg");
    });
    return c && (c==known[0] || c==known[1] || c==known[2]);
}
static void *WXGProbeRaw(id obj,Class cls,Ivar ivar) {
    ptrdiff_t offset=ivar_getOffset(ivar);
    if(WXGProbeScanned(class_getWeakIvarLayout(cls),offset)) {
        id loaded=object_getIvar(obj,ivar);   // objc_loadWeak: retained and autoreleased, or nil
        return (__bridge void *)loaded;
    }
    void *raw=*(void *const *)((const char *)(__bridge void *)obj+offset);
    const uint8_t *layout=class_getIvarLayout(cls);
    if(layout)return WXGProbeScanned(layout,offset)?raw:NULL;
    if(!raw)return NULL;
    if((intptr_t)raw<0)return raw;                 // a tagged pointer
    if(malloc_size(raw)==0)return NULL;            // not a live heap block
    const char *type=ivar_getTypeEncoding(ivar);   // @"ClassName"
    if(!type || type[0]!='@' || type[1]!='"')return NULL;
    const char *end=strchr(type+2,'"');if(!end || end-type-2<=0 || end-type-2>=120)return NULL;
    char name[128];memcpy(name,type+2,(size_t)(end-type-2));name[end-type-2]=0;
    Class isa=WXGProbeIsa(raw);
    if(!strcmp(name,"NSString") || !strcmp(name,"NSMutableString"))return WXGProbeStringClass(isa)?raw:NULL;
    Class declared=objc_getClass(name);
    return declared && isa==declared?raw:NULL;
}
static BOOL WXGProbeSkipName(NSString *name) {
    for(NSString *bad in @[@"elegate",@"arent",@"wner",@"arget",@"ontroller",@"weak",@"Weak",@"Window",@"window",@"Navigation",@"navigation"])
        if([name containsString:bad])return YES;
    return NO;
}
static BOOL WXGProbeLeafClass(id v) {
    for(Class c in @[NSNumber.class,NSData.class,NSDate.class,NSURL.class,UIImage.class,UIColor.class,UIFont.class,NSAttributedString.class,CALayer.class,
                     NSDictionary.class,NSSet.class,NSValue.class,NSTimer.class,NSLock.class,NSRecursiveLock.class])if([v isKindOfClass:c])return YES;
    return NO;
}
static void WXGProbeWalk(__unsafe_unretained id obj,NSString *path,int depth,NSMutableArray *hits,NSHashTable *seen,NSInteger *budget) {
    void *key=(__bridge void *)obj;
    if(!obj || depth<0 || *budget<=0 || [seen containsObject:(__bridge id)key])return;
    [seen addObject:(__bridge id)key];--*budget;
    for(Class cls=object_getClass(obj);cls && cls!=NSObject.class && cls!=UIResponder.class && cls!=UIView.class && cls!=UIViewController.class &&
                                         cls!=UITableViewCell.class && cls!=UICollectionViewCell.class && cls!=UIControl.class;cls=class_getSuperclass(cls)) {
        unsigned int n=0;Ivar *ivars=class_copyIvarList(cls,&n);
        for(unsigned int i=0;i<n && *budget>0;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]),*cname=ivar_getName(ivars[i]);
            if(!type || !cname || !type[0])continue;
            NSString *name=@(cname),*here=[path stringByAppendingFormat:@".%@",name];
            if(type[0]=='@') {
                if(WXGProbeSkipName(name) || type[1]=='?')continue;   // blocks, back references
                void *raw=WXGProbeRaw(obj,cls,ivars[i]);
                if(!WXGProbeSafe(raw))continue;
                __unsafe_unretained id v=(__bridge id)raw;
                if([v isKindOfClass:NSString.class]) {
                    NSString *kind=WXGChatUserKind(v);
                    if(kind && hits.count<60)[hits addObject:@{@"path":here,@"kind":kind}];
                }else if([v isKindOfClass:NSArray.class]) {
                    NSArray *a=v;
                    if(a.count && hits.count<60)[hits addObject:@{@"path":here,@"array":@(a.count),@"element":NSStringFromClass([a.firstObject class])?:@""}];
                    for(NSUInteger k=0;k<MIN(a.count,(NSUInteger)2);k++)WXGProbeWalk(a[k],[here stringByAppendingFormat:@"[%lu]",(unsigned long)k],depth-1,hits,seen,budget);
                }else if(!WXGProbeLeafClass(v))WXGProbeWalk(v,here,depth-1,hits,seen,budget);
            }else if(strchr("iIlLqQsSc",type[0]) && ([name rangeOfString:@"nread" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
                                                      [name rangeOfString:@"badge" options:NSCaseInsensitiveSearch].location!=NSNotFound)) {
                long long value=0;const char *base=(const char *)(__bridge void *)obj+ivar_getOffset(ivars[i]);
                switch(type[0]) {   // l / L are 32-bit in type encodings, q / Q 64-bit
                    case 'c':value=*(const signed char *)base;break;case 's':value=*(const short *)base;break;case 'S':value=*(const unsigned short *)base;break;
                    case 'i':case 'l':value=*(const int32_t *)base;break;case 'I':case 'L':value=*(const uint32_t *)base;break;
                    default:value=*(const long long *)base;break;
                }
                if(hits.count<60)[hits addObject:@{@"path":here,@"number":@(value)}];
            }
        }
        free(ivars);
    }
}
static NSArray *WXGProbeHits(id root,NSString *name,int depth,NSInteger budget) {
    NSMutableArray *hits=[NSMutableArray array];
    // Opaque pointers: no weak reference registered on what is visited.
    NSHashTable *seen=[[NSHashTable alloc] initWithOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsOpaquePersonality capacity:64];
    @try {WXGProbeWalk(root,name,depth,hits,seen,&budget);} @catch(NSException *error){[hits addObject:@{@"error":error.reason?:error.name}];}
    return hits;
}
// The object's own ivars: name, type, the value's class (and count).
static NSArray<NSString *> *WXGProbeIvars(id obj,NSUInteger limit) {
    NSMutableArray *out=[NSMutableArray array];
    for(Class cls=object_getClass(obj);cls && cls!=NSObject.class && cls!=UIResponder.class && cls!=UIViewController.class && cls!=UIView.class && out.count<limit;cls=class_getSuperclass(cls)) {
        unsigned int n=0;Ivar *ivars=class_copyIvarList(cls,&n);
        for(unsigned int i=0;i<n && out.count<limit;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]),*cname=ivar_getName(ivars[i]);if(!cname)continue;
            NSString *line=[NSString stringWithFormat:@"%@ %s",@(cname),type?:""];
            if(type && type[0]=='@' && type[1]!='?' && !WXGProbeSkipName(@(cname))) {
                void *raw=WXGProbeRaw(obj,cls,ivars[i]);
                if(WXGProbeSafe(raw)) {
                    __unsafe_unretained id v=(__bridge id)raw;
                    line=[line stringByAppendingFormat:@" = %@",NSStringFromClass([v class])];
                    if([v isKindOfClass:NSArray.class] || [v isKindOfClass:NSDictionary.class] || [v isKindOfClass:NSSet.class])line=[line stringByAppendingFormat:@" (%lu)",(unsigned long)[v count]];
                }
            }
            [out addObject:line];
        }
        free(ivars);
    }
    return out;
}
static NSArray<NSString *> *WXGProbeMethods(Class cls,NSArray<NSString *> *words,NSUInteger limit) {
    NSMutableArray *out=[NSMutableArray array];
    for(Class c=cls;c && c!=NSObject.class && c!=UIResponder.class && c!=UIViewController.class && c!=UIView.class && out.count<limit;c=class_getSuperclass(c))
        for(int meta=0;meta<2 && out.count<limit;meta++) {
            unsigned int n=0;Method *methods=class_copyMethodList(meta?object_getClass(c):c,&n);
            for(unsigned int i=0;i<n && out.count<limit;i++) {
                NSString *name=NSStringFromSelector(method_getName(methods[i]));
                for(NSString *word in words)if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound){[out addObject:[(meta?@"+":@"-") stringByAppendingString:name]];break;}
            }
            free(methods);
        }
    return out;
}
static NSDictionary *WXGChatListProbe(UITableView *table,UIViewController *page) {
    if(!table)return @{@"table":@"none"};
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    out[@"table"]=NSStringFromClass(table.class);
    id source=table.dataSource,delegate=table.delegate;
    out[@"dataSource"]=source?NSStringFromClass([source class]):@"nil";
    out[@"delegate"]=delegate?NSStringFromClass([delegate class]):@"nil";
    out[@"page"]=page?NSStringFromClass(page.class):@"nil";
    NSMutableArray *rows=[NSMutableArray array];NSInteger total=0;
    for(NSInteger s=0;s<MIN(table.numberOfSections,(NSInteger)8);s++){NSInteger n=[table numberOfRowsInSection:s];[rows addObject:@(n)];total+=n;}
    out[@"sections"]=@(table.numberOfSections);out[@"rows"]=rows;
    if(source)out[@"dataSourceIvars"]=WXGProbeIvars(source,90);
    if(page && page!=source)out[@"pageIvars"]=WXGProbeIvars(page,90);
    if(source)out[@"dataSourceMethods"]=WXGProbeMethods([source class],@[@"session",@"cell",@"unread",@"filter",@"reload",@"index"],70);
    // Collections the page / data source keep with about as many items as rows.
    NSMutableArray *lists=[NSMutableArray array];
    for(id owner in [NSSet setWithObjects:source?:NSNull.null,page?:NSNull.null,nil]) {
        if(owner==NSNull.null)continue;
        for(NSDictionary *hit in WXGProbeHits(owner,NSStringFromClass([owner class]),2,260))
            if(hit[@"array"] || hit[@"kind"] || hit[@"number"])[lists addObject:hit];
    }
    out[@"ownerHits"]=lists;
    // What a cell holds: the paths to a user name (by kind) and unread counts.
    NSMutableArray *cells=[NSMutableArray array];
    for(UITableViewCell *cell in table.visibleCells) {
        if(cells.count>=5)break;
        NSIndexPath *path=[table indexPathForCell:cell];
        [cells addObject:@{@"row":path?[NSString stringWithFormat:@"%ld/%ld",(long)path.section,(long)path.row]:@"?",@"class":NSStringFromClass(cell.class),
                           @"hits":WXGProbeHits(cell,@"cell",3,240)}];
    }
    out[@"cells"]=cells;
    if(cells.count){UITableViewCell *first=table.visibleCells.firstObject;out[@"cellIvars"]=WXGProbeIvars(first,70);}
    // WeChat's contact labels (标签): the manager classes and their methods
    // (the binary's class names scanned once per launch, C strings only).
    static NSArray *labels,*labelMethods;
    if(!labels) {
        Class anchor=objc_getClass("NewMainFrameViewController")?:page.class;
        const char *image=anchor?class_getImageName(anchor):NULL;
        NSMutableArray *found=[NSMutableArray array],*methods=[NSMutableArray array];
        if(image) {
            unsigned int n=0;const char **names=objc_copyClassNamesForImage(image,&n);
            for(unsigned int i=0;i<n && found.count<40;i++) {
                const char *name=names[i];
                BOOL topic=strstr(name,"Label") || strstr(name,"ContactTag");
                BOOL owner=strstr(name,"Mgr") || strstr(name,"Manager") || strstr(name,"Service") || strstr(name,"Logic");
                if(topic && owner)[found addObject:@(name)];
            }
            free(names);
            for(NSString *name in [found subarrayWithRange:NSMakeRange(0,MIN(found.count,(NSUInteger)6))]) {
                Class c=objc_getClass(name.UTF8String);if(!c)continue;   // not messaged (no +initialize)
                [methods addObject:@{@"class":name,@"methods":WXGProbeMethods(c,@[@"label",@"tag",@"list",@"contact"],24)}];
            }
        }
        labels=found.copy;labelMethods=methods.copy;
    }
    out[@"labelClasses"]=labels;out[@"labelMethods"]=labelMethods;
    out[@"totalRows"]=@(total);
    return out;
}



#pragma mark - FIX113 R: the user's groups

/* User (10-21 14:15): "cannot set a group, cannot add a new one". The groups
   are the user's: 1-6 of them, each a name and a rule (0 全部 = WeChat's whole
   list, 1 未读, 2 单聊, 3 群聊, 4 自定义 = the chats chosen), in this order on the
   bar; kept in the plugin's defaults (chatGroups.v1), edited on the settings
   page 分组 › 管理分组. Members are WeChat user names (never in diagnostics). */
NSString * const WXGChatGroupsChanged=@"com.runyu.WeChatLiquidGlass.chatGroups";
static NSString * const WXGChatGroupsKey=@"chatGroups.v1";
static NSArray<NSDictionary *> *WXGChatGroupCache;
NSArray<NSDictionary *> *WXGChatGroupDefaults(void) {
    return @[@{@"id":@"all",@"name":@"全部",@"rule":@0,@"members":@[]},@{@"id":@"unread",@"name":@"未读",@"rule":@1,@"members":@[]},
             @{@"id":@"single",@"name":@"单聊",@"rule":@2,@"members":@[]},@{@"id":@"group",@"name":@"群聊",@"rule":@3,@"members":@[]}];
}
static NSArray<NSDictionary *> *WXGChatGroupClean(NSArray *groups) {
    NSMutableArray *clean=[NSMutableArray array];NSMutableSet *ids=[NSMutableSet set];
    for(id item in [groups isKindOfClass:NSArray.class]?groups:@[]) {
        if(![item isKindOfClass:NSDictionary.class] || clean.count>=WXG_SEGMENTS_MAX)continue;
        NSDictionary *g=item;id gid=g[@"id"],name=g[@"name"],rule=g[@"rule"],members=g[@"members"];
        if(![gid isKindOfClass:NSString.class] || ![gid length] || [ids containsObject:gid])continue;
        if(![name isKindOfClass:NSString.class])continue;
        NSString *trimmed=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(!trimmed.length)continue;
        if(trimmed.length>10)trimmed=[trimmed substringWithRange:[trimmed rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,10)]];
        NSInteger r=[rule isKindOfClass:NSNumber.class]?[rule integerValue]:-1;if(r<0 || r>4)continue;
        NSMutableOrderedSet *names=[NSMutableOrderedSet orderedSet];
        if([members isKindOfClass:NSArray.class])for(id m in members)if([m isKindOfClass:NSString.class] && [m length] && [m length]<128 && names.count<3000)[names addObject:m];
        [ids addObject:gid];[clean addObject:@{@"id":gid,@"name":trimmed,@"rule":@(r),@"members":names.array}];
    }
    return clean.count?clean.copy:WXGChatGroupDefaults();
}
NSArray<NSDictionary *> *WXGChatGroupList(void) {
    if(!WXGChatGroupCache)WXGChatGroupCache=WXGChatGroupClean([[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] arrayForKey:WXGChatGroupsKey]);
    return WXGChatGroupCache;
}
void WXGChatGroupSave(NSArray<NSDictionary *> *groups) {
    WXGChatGroupCache=WXGChatGroupClean(groups);
    [[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] setObject:WXGChatGroupCache forKey:WXGChatGroupsKey];
    void (^post)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:WXGChatGroupsChanged object:nil];};
    if(NSThread.isMainThread)post();else dispatch_async(dispatch_get_main_queue(),post);
}

#pragma mark - FIX113 Q: the grouping itself (the chat list filtered)

/* User (10-21 12:57): the groups must really group; his earlier tweak for
   iOS 26 (WCLGSearchGroups 0.1.7) as the reference. As it did: WeChat's home
   list is drawn from MainSessionMgr's topSessions / normalSessions (pinned /
   the rest; totalTopSessionCount the pinned count), made again by
   -rebuildMainSessions (every new message, read, pin ...). Right after
   WeChat's own rebuild those two arrays are filtered for the segment chosen
   (order and objects kept: WeChat's session objects, never copied or
   changed); 全部 leaves them exactly as WeChat made them.

   Safety (the reference's open questions):
   - nothing is hooked until a segment other than 全部 is chosen (the plugin
     on and authorised then); after that the hook only passes through while
     全部 is chosen, the plugin is off or the manager is not the home page's;
   - the manager is the one the home page holds (read as the chat-list probe
     reads ivars: strong / weak layout, never a dangling pointer); every
     method is checked for its exact signature first;
   - before the list is reloaded, the table's own data source must count
     exactly the filtered sessions plus what it counted besides them before
     (the rows not from these arrays): otherwise everything goes back to
     全部 at once and the grouping stays off for this run, in the
     diagnostics (no table ever asked for a row the arrays no longer have);
   - a session's kind from its user name only (no contact lookups): 群聊
     @chatroom (and the folded-groups entry), 单聊 the other personal chats
     (not official accounts gh_ / WeChat's own entries), 未读 any unread or
     @ count. */
static _Atomic(NSInteger) WXGFilterIndex;   // 0 全部, 1 未读, 2 单聊, 3 群聊
static __weak id WXGFilterManager;           // the home page's MainSessionMgr
static _Atomic(NSUInteger) WXGFilterRebuilds,WXGFilterFiltered;
static NSDictionary *WXGFilterLast;          // the last filtering (counts only), under the lock below
static NSObject *WXGFilterLock(void) {static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[NSObject new];});return lock;}
static char WXGSessionTypeOf(Method m,BOOL ret,unsigned index) {
    char type[32]={0};
    if(ret)method_getReturnType(m,type,sizeof type);else method_getArgumentType(m,index,type,sizeof type);
    const char *t=type;while(*t && strchr("rnNoORV",*t))t++;
    return *t;
}
// An object getter / setter / integer getter / setter / void method of exactly that shape.
static Method WXGSessionMethod(id obj,NSString *name,unsigned args) {
    if(!obj)return NULL;Method m=class_getInstanceMethod(object_getClass(obj),NSSelectorFromString(name));
    return m && method_getNumberOfArguments(m)==args?m:NULL;
}
static id WXGSessionGetObject(id obj,NSString *name) {
    Method m=WXGSessionMethod(obj,name,2);if(!m || WXGSessionTypeOf(m,YES,0)!='@')return nil;
    return ((id (*)(id,SEL))objc_msgSend)(obj,NSSelectorFromString(name));
}
static BOOL WXGSessionSetObject(id obj,NSString *name,id value) {
    Method m=WXGSessionMethod(obj,name,3);if(!m || WXGSessionTypeOf(m,YES,0)!='v' || WXGSessionTypeOf(m,NO,2)!='@')return NO;
    ((void (*)(id,SEL,id))objc_msgSend)(obj,NSSelectorFromString(name),value);return YES;
}
static BOOL WXGSessionGetInteger(id obj,NSString *name,long long *out) {
    Method m=WXGSessionMethod(obj,name,2);if(!m)return NO;SEL sel=NSSelectorFromString(name);
    switch(WXGSessionTypeOf(m,YES,0)) {
        case 'q':*out=((long long (*)(id,SEL))objc_msgSend)(obj,sel);return YES;
        case 'Q':*out=(long long)((unsigned long long (*)(id,SEL))objc_msgSend)(obj,sel);return YES;
        case 'i':case 'l':*out=((int (*)(id,SEL))objc_msgSend)(obj,sel);return YES;
        case 'I':case 'L':*out=((unsigned int (*)(id,SEL))objc_msgSend)(obj,sel);return YES;
        default:return NO;
    }
}
static BOOL WXGSessionSetInteger(id obj,NSString *name,long long value) {
    Method m=WXGSessionMethod(obj,name,3);if(!m || WXGSessionTypeOf(m,YES,0)!='v')return NO;SEL sel=NSSelectorFromString(name);
    switch(WXGSessionTypeOf(m,NO,2)) {
        case 'q':case 'Q':((void (*)(id,SEL,long long))objc_msgSend)(obj,sel,value);return YES;
        case 'i':case 'I':case 'l':case 'L':((void (*)(id,SEL,int))objc_msgSend)(obj,sel,(int)value);return YES;
        default:return NO;
    }
}
static BOOL WXGSessionCallVoid(id obj,NSString *name) {
    Method m=WXGSessionMethod(obj,name,2);if(!m || WXGSessionTypeOf(m,YES,0)!='v')return NO;
    ((void (*)(id,SEL))objc_msgSend)(obj,NSSelectorFromString(name));return YES;
}
// What the manager must have, by exact shape; nil when everything is there.
static NSString *WXGSessionAPIMissing(id manager) {
    if(!manager)return @"没有找到首页的 MainSessionMgr";
    NSMutableArray *missing=[NSMutableArray array];
    for(NSString *name in @[@"topSessions",@"normalSessions"]){Method m=WXGSessionMethod(manager,name,2);if(!m || WXGSessionTypeOf(m,YES,0)!='@')[missing addObject:name];}
    for(NSString *name in @[@"setTopSessions:",@"setNormalSessions:"]){Method m=WXGSessionMethod(manager,name,3);if(!m || WXGSessionTypeOf(m,YES,0)!='v' || WXGSessionTypeOf(m,NO,2)!='@')[missing addObject:name];}
    {Method m=WXGSessionMethod(manager,@"totalTopSessionCount",2);if(!m || !strchr("qQiIlL",WXGSessionTypeOf(m,YES,0)))[missing addObject:@"totalTopSessionCount"];}
    {Method m=WXGSessionMethod(manager,@"setTotalTopSessionCount:",3);if(!m || WXGSessionTypeOf(m,YES,0)!='v' || !strchr("qQiIlL",WXGSessionTypeOf(m,NO,2)))[missing addObject:@"setTotalTopSessionCount:"];}
    {Method m=WXGSessionMethod(manager,@"rebuildMainSessions",2);if(!m || WXGSessionTypeOf(m,YES,0)!='v')[missing addObject:@"rebuildMainSessions"];}
    return missing.count?[missing componentsJoinedByString:@" "]:nil;
}
// A session's ivar / property: an object (the user name) or a count.
static id WXGSessionField(id session,const char *name) {
    if(!session)return nil;
    SEL sel=sel_registerName(name);Method m=class_getInstanceMethod(object_getClass(session),sel);
    if(m && method_getNumberOfArguments(m)==2 && WXGSessionTypeOf(m,YES,0)=='@')return ((id (*)(id,SEL))objc_msgSend)(session,sel);
    // FIX113 T: an accessor resolved at its first call (+resolveInstanceMethod:,
    // forwarding: WeChat's generated model classes) has no method yet; the
    // object says whether it answers and with what.
    if(!m && [session respondsToSelector:sel]) {
        NSMethodSignature *sig=[session methodSignatureForSelector:sel];
        if(sig && sig.numberOfArguments==2 && sig.methodReturnType[0]=='@')return ((id (*)(id,SEL))objc_msgSend)(session,sel);
    }
    Ivar ivar=class_getInstanceVariable(object_getClass(session),name);
    if(!ivar){char under[96];snprintf(under,sizeof under,"_%s",name);ivar=class_getInstanceVariable(object_getClass(session),under);}
    const char *type=ivar?ivar_getTypeEncoding(ivar):NULL;
    return type && type[0]=='@'?object_getIvar(session,ivar):nil;
}
static long long WXGSessionCount(id session,const char *name) {
    SEL sel=sel_registerName(name);Method m=class_getInstanceMethod(object_getClass(session),sel);
    if(m && method_getNumberOfArguments(m)==2) {
        switch(WXGSessionTypeOf(m,YES,0)) {
            case 'B':case 'C':return ((unsigned char (*)(id,SEL))objc_msgSend)(session,sel);
            case 'c':return ((signed char (*)(id,SEL))objc_msgSend)(session,sel);
            case 'S':return ((unsigned short (*)(id,SEL))objc_msgSend)(session,sel);
            case 's':return ((short (*)(id,SEL))objc_msgSend)(session,sel);
            case 'I':case 'L':return ((unsigned int (*)(id,SEL))objc_msgSend)(session,sel);
            case 'i':case 'l':return ((int (*)(id,SEL))objc_msgSend)(session,sel);
            case 'Q':case 'q':return ((long long (*)(id,SEL))objc_msgSend)(session,sel);
            default:break;
        }
    }
    Ivar ivar=class_getInstanceVariable(object_getClass(session),name);
    if(!ivar){char under[96];snprintf(under,sizeof under,"_%s",name);ivar=class_getInstanceVariable(object_getClass(session),under);}
    const char *type=ivar?ivar_getTypeEncoding(ivar):NULL;if(!type)return 0;
    const char *base=(const char *)(__bridge void *)session+ivar_getOffset(ivar);
    switch(type[0]) {
        case 'B':case 'C':return *(const uint8_t *)base;case 'c':return *(const int8_t *)base;
        case 'I':case 'L':return *(const uint32_t *)base;case 'i':case 'l':return *(const int32_t *)base;
        case 'Q':case 'q':return *(const long long *)base;case 'S':return *(const uint16_t *)base;case 's':return *(const int16_t *)base;
        default:return 0;
    }
}
static NSString *WXGSessionUserName(id session) {
    id name=WXGSessionField(session,"m_nsUserName");
    if(![name isKindOfClass:NSString.class])name=WXGSessionField(session,"m_nsUsrName");
    return [name isKindOfClass:NSString.class]?name:nil;
}
// 2 单聊, 3 群聊, 0 neither (official accounts, WeChat's own entries).
static NSInteger WXGSessionKind(NSString *name) {
    if(!name.length)return 0;
    if([name hasSuffix:@"@chatroom"] || [name isEqual:@"@placeholder_foldgroup"])return 3;
    if([name hasPrefix:@"gh_"] || [name hasPrefix:@"@"] || [name hasSuffix:@"@stranger"])return 0;
    static NSSet *own;static dispatch_once_t once;
    dispatch_once(&once,^{own=[NSSet setWithArray:@[@"brandsessionholder",@"brandservicesessionholder",@"notifymessage",@"notification_messages",@"newsapp",@"weixin",
        @"fmessage",@"qmessage",@"tmessage",@"medianote",@"floatbottle",@"qqmail",@"qqsync",@"masssendapp",@"opencustomerservicemsg",@"appbrand_notify_message",
        @"appbrandcustomerservicemsg",@"blogapp",@"feedsapp",@"voipapp",@"voicevoipapp",@"voiceinputapp",@"linkedinplugin",@"facebookapp",@"googlecontact",@"officialaccounts"]];});
    return [own containsObject:name]?0:2;
}
static BOOL WXGSessionUnread(id session) {
    static const char *keys[]={"m_uUnReadCount","m_uAtMeCount","m_uAtAllCount","m_uNewNotifyMsgCount"};
    for(size_t i=0;i<sizeof keys/sizeof *keys;i++)if(WXGSessionCount(session,keys[i])>0)return YES;
    return NO;
}
static NSSet<NSString *> *WXGFilterMembers;   // main thread: the custom group's user names (rule 4)
// The five categories are separate from the editable group's persisted rules (0–4).
typedef NS_ENUM(NSInteger,WXGHomeCategoryRule) {
    WXGCategoryPinned=5,WXGCategoryPrivate,WXGCategoryRoom,WXGCategoryService,WXGCategoryWork
};
static NSInteger WXGHomeCategoryForName(NSString *name) {
    if([name containsString:@"@chatroom"])return WXGCategoryRoom;
    if([name containsString:@"@openim"] || [name containsString:@"@im."])return WXGCategoryWork;
    static NSSet *services;static dispatch_once_t once;
    dispatch_once(&once,^{services=[NSSet setWithArray:@[@"brandsessionholder",@"brandservicesessionholder",
        @"opencustomerservicemsg",@"notification_messages",@"weixin",@"filehelper",@"newsapp",@"notifymessage",@"weixingongzhong"]];});
    return [name hasPrefix:@"gh_"] || (name && [services containsObject:name])?WXGCategoryService:WXGCategoryPrivate;
}
static BOOL WXGSessionMatches(id session,NSInteger rule,BOOL pinned) {
    if(rule>=WXGCategoryPinned) {
        if(pinned || rule==WXGCategoryPinned)return pinned && rule==WXGCategoryPinned;
        return WXGHomeCategoryForName(WXGSessionUserName(session))==rule;
    }
    if(rule==1)return WXGSessionUnread(session);
    if(rule==4){NSString *name=WXGSessionUserName(session);return name && [WXGFilterMembers containsObject:name];}
    return WXGSessionKind(WXGSessionUserName(session))==rule;
}
// FIX113 R: WeChat's whole list as its last rebuild on the main thread made it
// (before any filtering), for choosing a custom group's members; and the
// manager that rebuilt it.
static NSArray *WXGFilterSnapshot;
static NSUInteger WXGFilterSnapshotTopCount;
static __weak id WXGLastRebuiltManager;
static BOOL WXGFilterWatching;   // main thread: the bar is up (plugin on, authorised, 分组栏 on)
// Right after WeChat's own rebuild. FIX113 Q (review): only on the main
// thread; a rebuild WeChat runs elsewhere is never filtered (and turns the
// grouping off: two threads rebuilding at once would race in WeChat's own code).
static _Atomic(NSUInteger) WXGFilterOffMain;
static _Atomic(BOOL) WXGFilterLastOK,WXGFilterDisabled;   // disabled: a rebuild seen on another thread (no more filtering)
static long long WXGFilterTopDelta;                     // WeChat's own totalTopSessionCount - topSessions.count (main thread)
static long long WXGFilterWrittenCount=-1;              // the pinned count we wrote last (-1: none since WeChat's own)
static void WXGFilterOffMainSeen(void);   // below (the manager's -filterOffMain)
static void WXGFilterAfterRebuild(id manager) {
    atomic_fetch_add(&WXGFilterRebuilds,1);
    if(!NSThread.isMainThread) {
        atomic_fetch_add(&WXGFilterOffMain,1);
        if(atomic_load(&WXGFilterIndex)>0){atomic_store(&WXGFilterDisabled,YES);dispatch_async(dispatch_get_main_queue(),^{WXGFilterOffMainSeen();});}
        return;
    }
    id home=WXGFilterManager;
    if(WXGFilterWatching && (!home || manager==home)) {   // the home list (or, before one is known, any): the whole list as WeChat made it
        WXGLastRebuiltManager=manager;
        @try {
            NSArray *t=WXGSessionGetObject(manager,@"topSessions"),*n=WXGSessionGetObject(manager,@"normalSessions");
            if([t isKindOfClass:NSArray.class] && [n isKindOfClass:NSArray.class]) {
                WXGFilterSnapshot=[t arrayByAddingObjectsFromArray:n];WXGFilterSnapshotTopCount=t.count;
            }
        } @catch(__unused NSException *error) {}
    }
    NSInteger index=atomic_load(&WXGFilterIndex);
    if(index<1 || index>WXGCategoryWork || atomic_load(&WXGFilterDisabled))return;
    if(!home || manager!=home)return;
    NSArray *top=nil,*normal=nil;long long count=0;BOOL counted=NO,touched=NO;
    @try {
        top=WXGSessionGetObject(manager,@"topSessions");normal=WXGSessionGetObject(manager,@"normalSessions");
        if(![top isKindOfClass:NSArray.class] || ![normal isKindOfClass:NSArray.class]){atomic_store(&WXGFilterLastOK,NO);return;}
        NSMutableArray *keptTop=[NSMutableArray arrayWithCapacity:top.count],*keptNormal=[NSMutableArray arrayWithCapacity:normal.count];
        for(id session in top)if(WXGSessionMatches(session,index,YES))[keptTop addObject:session];
        for(id session in normal)if(WXGSessionMatches(session,index,NO))[keptNormal addObject:session];
        count=(long long)top.count;counted=WXGSessionGetInteger(manager,@"totalTopSessionCount",&count);
        // WeChat's own relation of the count to the array, unless the count is
        // still the one we wrote (its rebuild left it): then the last one known.
        if(counted && count!=WXGFilterWrittenCount)WXGFilterTopDelta=count-(long long)top.count;
        long long written=(index>WXGCategoryPinned)?0:(long long)keptTop.count+(counted?WXGFilterTopDelta:0);
        touched=YES;
        // The count first (never larger than the array it counts), then the arrays.
        BOOL ok=WXGSessionSetInteger(manager,@"setTotalTopSessionCount:",written) &&
                WXGSessionSetObject(manager,@"setTopSessions:",keptTop) && WXGSessionSetObject(manager,@"setNormalSessions:",keptNormal);
        if(!ok){WXGSessionSetObject(manager,@"setNormalSessions:",normal);WXGSessionSetObject(manager,@"setTopSessions:",top);if(counted)WXGSessionSetInteger(manager,@"setTotalTopSessionCount:",count);}
        else WXGFilterWrittenCount=written;
        atomic_store(&WXGFilterLastOK,ok);atomic_fetch_add(&WXGFilterFiltered,1);
        @synchronized(WXGFilterLock()) {
            WXGFilterLast=@{@"index":@(index),@"top":[NSString stringWithFormat:@"%lu → %lu",(unsigned long)top.count,(unsigned long)keptTop.count],
                            @"normal":[NSString stringWithFormat:@"%lu → %lu",(unsigned long)normal.count,(unsigned long)keptNormal.count],
                            @"topCountBefore":@(count),@"topDelta":@(WXGFilterTopDelta),@"written":@(written),@"ok":@(ok),@"t":@(round(WXGSecondsSinceLoad()*10)/10)};
        }
    } @catch(NSException *error) {
        atomic_store(&WXGFilterLastOK,NO);
        if(touched) @try {   // all three back as WeChat made them
            WXGSessionSetObject(manager,@"setNormalSessions:",normal);WXGSessionSetObject(manager,@"setTopSessions:",top);
            if(counted)WXGSessionSetInteger(manager,@"setTotalTopSessionCount:",count);
        } @catch(__unused NSException *again) {}
        @synchronized(WXGFilterLock()){WXGFilterLast=@{@"error":error.reason?:error.name?:@"?",@"t":@(round(WXGSecondsSinceLoad()*10)/10)};}
    }
}
static BOOL WXGFilterHookInstalled;
static BOOL WXGInstallFilterHook(void) {
    if(WXGFilterHookInstalled)return YES;
    Class c=objc_getClass("MainSessionMgr");SEL sel=NSSelectorFromString(@"rebuildMainSessions");
    Method m=c?class_getInstanceMethod(c,sel):NULL;
    if(!m || method_getNumberOfArguments(m)!=2 || WXGSessionTypeOf(m,YES,0)!='v')return NO;
    IMP own=WXGCapturedImplementation(c,sel);Class sup=class_getSuperclass(c);   // FIX115 B: what was there when installed (as before A)
    IMP replacement=imp_implementationWithBlock(^(id manager){
        ((void (*)(id,SEL))WXGThrough(own,sup,sel))(manager,sel);
        WXGFilterAfterRebuild(manager);
    });
    WXGInstallOverride(c,sel,replacement,method_getTypeEncoding(m));
    WXGFilterHookInstalled=YES;
    return YES;
}

/* FIX113 Q (review): while the list is filtered, WeChat may still update the
   home table row by row (insert / delete / move / reload, a batch, scrolling
   to a row) with index paths worked out before the filter ran or from its
   whole list; UIKit would throw ("invalid number of rows") or scroll past the
   end. On the home list's own table class only (WeChat's MainFrameTableView,
   never UITableView itself) and only while filtered, every such update
   becomes one reloadData (a batch: its block run, then reloadData, then its
   completion), and a scroll / selection to a row that is not there is
   dropped. Not filtered: each call goes straight to UIKit. */
static __weak UITableView *WXGFilterTable;
static BOOL WXGFilterGuarding;   // main thread: on before the first filtered rebuild, off only after the whole list is reloaded
static NSInteger WXGFilterUpdateDepth;
static BOOL WXGFilterReloadPending;
static _Atomic(NSUInteger) WXGFilterIntercepts;
static BOOL WXGFilterIntercepting(UITableView *table) {
    return NSThread.isMainThread && WXGFilterGuarding && table && table==WXGFilterTable;
}
static void WXGFilterReload(UITableView *table) {
    atomic_fetch_add(&WXGFilterIntercepts,1);
    if(WXGFilterUpdateDepth>0){WXGFilterReloadPending=YES;return;}
    WXGFilterReloadPending=NO;[table reloadData];
}
// UIKit's counts against the data source's (a mismatch: an endUpdates would throw).
static BOOL WXGFilterCountsDiffer(UITableView *table) {
    id<UITableViewDataSource> source=table.dataSource;if(!source)return YES;
    NSInteger sections=[source respondsToSelector:@selector(numberOfSectionsInTableView:)]?[source numberOfSectionsInTableView:table]:1;
    if(sections!=table.numberOfSections)return YES;
    for(NSInteger s=0;s<sections && s<64;s++)if([source tableView:table numberOfRowsInSection:s]!=[table numberOfRowsInSection:s])return YES;
    return NO;
}
static BOOL WXGFilterRowExists(UITableView *table,NSIndexPath *path) {
    if(![path isKindOfClass:NSIndexPath.class])return NO;
    NSInteger sections=table.numberOfSections;
    return path.section>=0 && path.section<sections && path.row>=0 && path.row<[table numberOfRowsInSection:path.section];
}
static void WXGFilterOverride(Class cls,SEL sel,id block) {
    Method m=class_getInstanceMethod(cls,sel);if(!m)return;
    IMP replacement=imp_implementationWithBlock(block);
    WXGInstallOverride(cls,sel,replacement,method_getTypeEncoding(m));
}
static Class WXGFilterTableClass;
static BOOL WXGInstallTableGuards(UITableView *table) {
    Class cls=[table class];   // the class itself, not a KVO subclass of it
    if(!cls || cls==UITableView.class || !strcmp(class_getName(cls),"UITableView"))return NO;   // never UIKit's own class
    if(WXGFilterTableClass)return WXGFilterTableClass==cls;
    // Each: the original IMP (UIKit's, inherited, or the class's own) captured now
    // (FIX115 B: as before A again).
    Class sup=class_getSuperclass(cls);
    #define WXG_ORIGINAL(sel) WXGCapturedImplementation(cls,sel)   // FIX115 B: as before A
    {SEL sel=@selector(insertRowsAtIndexPaths:withRowAnimation:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSArray *p,UITableViewRowAnimation a){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,NSInteger))WXGThrough(o,sup,sel))(t,sel,p,a);});}
    {SEL sel=@selector(deleteRowsAtIndexPaths:withRowAnimation:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSArray *p,UITableViewRowAnimation a){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,NSInteger))WXGThrough(o,sup,sel))(t,sel,p,a);});}
    {SEL sel=@selector(reloadRowsAtIndexPaths:withRowAnimation:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSArray *p,UITableViewRowAnimation a){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,NSInteger))WXGThrough(o,sup,sel))(t,sel,p,a);});}
    {SEL sel=@selector(moveRowAtIndexPath:toIndexPath:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSIndexPath *a,NSIndexPath *b){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,id))WXGThrough(o,sup,sel))(t,sel,a,b);});}
    {SEL sel=@selector(insertSections:withRowAnimation:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSIndexSet *x,UITableViewRowAnimation a){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,NSInteger))WXGThrough(o,sup,sel))(t,sel,x,a);});}
    {SEL sel=@selector(deleteSections:withRowAnimation:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSIndexSet *x,UITableViewRowAnimation a){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,NSInteger))WXGThrough(o,sup,sel))(t,sel,x,a);});}
    {SEL sel=@selector(reloadSections:withRowAnimation:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSIndexSet *x,UITableViewRowAnimation a){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id,NSInteger))WXGThrough(o,sup,sel))(t,sel,x,a);});}
    {SEL sel=@selector(moveSection:toSection:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSInteger a,NSInteger b){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,NSInteger,NSInteger))WXGThrough(o,sup,sel))(t,sel,a,b);});}
    if([UITableView instancesRespondToSelector:NSSelectorFromString(@"reconfigureRowsAtIndexPaths:")]) {   // iOS 15
        SEL sel=NSSelectorFromString(@"reconfigureRowsAtIndexPaths:");IMP o=WXG_ORIGINAL(sel);
        WXGFilterOverride(cls,sel,^(UITableView *t,NSArray *p){if(WXGFilterIntercepting(t))WXGFilterReload(t);else ((void(*)(id,SEL,id))WXGThrough(o,sup,sel))(t,sel,p);});
    }
    // begin / end: ours while filtered (the rows inside become one reload at
    // the end); an end without our begin is UIKit's.
    static NSInteger ownBegins;
    IMP beginOriginal=WXG_ORIGINAL(@selector(beginUpdates));
    {SEL sel=@selector(beginUpdates);IMP o=beginOriginal;
     WXGFilterOverride(cls,sel,^(UITableView *t){if(WXGFilterIntercepting(t)){++WXGFilterUpdateDepth;++ownBegins;}else ((void(*)(id,SEL))WXGThrough(o,sup,sel))(t,sel);});}
    {SEL sel=@selector(endUpdates);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t){
        if(ownBegins>0 && t==WXGFilterTable && NSThread.isMainThread) {
            --ownBegins;WXGFilterUpdateDepth=MAX(0,WXGFilterUpdateDepth-1);
            if(WXGFilterUpdateDepth)return;
            if(WXGFilterReloadPending || WXGFilterCountsDiffer(t)){WXGFilterReloadPending=NO;[t reloadData];atomic_fetch_add(&WXGFilterIntercepts,1);}
            else {((void(*)(id,SEL))WXGThrough(beginOriginal,sup,@selector(beginUpdates)))(t,@selector(beginUpdates));((void(*)(id,SEL))WXGThrough(o,sup,sel))(t,sel);}   // nothing in it: UIKit's (row heights)
            return;
        }
        ((void(*)(id,SEL))WXGThrough(o,sup,sel))(t,sel);
     });}
    {SEL sel=@selector(performBatchUpdates:completion:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,void (^updates)(void),void (^completion)(BOOL)){
        if(!WXGFilterIntercepting(t)){((void(*)(id,SEL,id,id))WXGThrough(o,sup,sel))(t,sel,updates,completion);return;}
        ++WXGFilterUpdateDepth;
        @try {if(updates)updates();} @finally {WXGFilterUpdateDepth=MAX(0,WXGFilterUpdateDepth-1);}
        if(WXGFilterUpdateDepth){if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(YES);});return;}
        if(WXGFilterReloadPending || WXGFilterCountsDiffer(t)) {
            atomic_fetch_add(&WXGFilterIntercepts,1);WXGFilterReloadPending=NO;[t reloadData];
            if(completion)dispatch_async(dispatch_get_main_queue(),^{completion(YES);});
        }else ((void(*)(id,SEL,id,id))WXGThrough(o,sup,sel))(t,sel,nil,completion);   // nothing in it: UIKit's (row heights)
     });}
    {SEL sel=@selector(scrollToRowAtIndexPath:atScrollPosition:animated:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSIndexPath *p,UITableViewScrollPosition pos,BOOL animated){
        if(WXGFilterIntercepting(t) && !WXGFilterRowExists(t,p)){atomic_fetch_add(&WXGFilterIntercepts,1);return;}
        ((void(*)(id,SEL,id,NSInteger,BOOL))WXGThrough(o,sup,sel))(t,sel,p,pos,animated);
     });}
    {SEL sel=@selector(rectForRowAtIndexPath:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^CGRect(UITableView *t,NSIndexPath *p){
        if(WXGFilterIntercepting(t) && !WXGFilterRowExists(t,p)){atomic_fetch_add(&WXGFilterIntercepts,1);return CGRectZero;}
        return ((CGRect(*)(id,SEL,id))WXGThrough(o,sup,sel))(t,sel,p);
     });}
    {SEL sel=@selector(selectRowAtIndexPath:animated:scrollPosition:);IMP o=WXG_ORIGINAL(sel);
     WXGFilterOverride(cls,sel,^(UITableView *t,NSIndexPath *p,BOOL animated,UITableViewScrollPosition pos){
        if(WXGFilterIntercepting(t) && p && !WXGFilterRowExists(t,p)){atomic_fetch_add(&WXGFilterIntercepts,1);return;}
        ((void(*)(id,SEL,id,BOOL,NSInteger))WXGThrough(o,sup,sel))(t,sel,p,animated,pos);
     });}
    #undef WXG_ORIGINAL
    WXGFilterTableClass=cls;
    return YES;
}
// The MainSessionMgr the home page holds (its ivars, then the list's data
// source's), read without messaging anything that could be gone.
static NSString *WXGManagerPath;   // where it was found (diagnostics: ivar names only)
static id WXGFindManagerIn(id owner,Class manager,int depth,NSString *path,NSHashTable *seen,NSInteger *budget) {
    void *key=(__bridge void *)owner;
    if(!owner || *budget<=0 || [seen containsObject:(__bridge id)key])return nil;
    [seen addObject:(__bridge id)key];
    NSMutableArray *deeper=[NSMutableArray array],*names=[NSMutableArray array];
    for(Class cls=object_getClass(owner);cls && cls!=NSObject.class && cls!=UIResponder.class && cls!=UIViewController.class && cls!=UIView.class;cls=class_getSuperclass(cls)) {
        unsigned int n=0;Ivar *ivars=class_copyIvarList(cls,&n);id found=nil;NSString *foundName=nil;
        for(unsigned int i=0;i<n && !found && *budget>0;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]),*cname=ivar_getName(ivars[i]);
            if(!type || !cname || type[0]!='@' || type[1]=='?')continue;
            --*budget;
            void *raw=WXGProbeRaw(owner,cls,ivars[i]);
            if(!WXGProbeSafe(raw) || (intptr_t)raw<0)continue;
            Class isa=WXGProbeIsa(raw);
            for(Class k=isa;k;k=class_getSuperclass(k))if(k==manager){found=(__bridge id)raw;foundName=@(cname);break;}
            if(found || depth<=0)continue;
            NSString *name=@(cname);
            if([name containsString:@"elegate"] || [name containsString:@"arent"] || [name containsString:@"avigation"] || [name containsString:@"indow"] || [name containsString:@"wner"])continue;
            BOOL leaf=NO;
            for(Class k=isa;k;k=class_getSuperclass(k))
                if(k==NSString.class || k==NSArray.class || k==NSDictionary.class || k==NSSet.class || k==NSNumber.class || k==UIView.class || k==UIImage.class || k==UIColor.class){leaf=YES;break;}
            if(!leaf){[deeper addObject:[NSValue valueWithPointer:raw]];[names addObject:name];}
        }
        free(ivars);
        if(found){WXGManagerPath=[path stringByAppendingFormat:@".%@",foundName];return found;}
    }
    for(NSUInteger i=0;i<deeper.count && *budget>0;i++) {
        __unsafe_unretained id next=(__bridge id)[deeper[i] pointerValue];
        id found=WXGFindManagerIn(next,manager,depth-1,[path stringByAppendingFormat:@".%@",names[i]],seen,budget);
        if(found)return found;
    }
    return nil;
}
// The MainSessionMgr of the home list: in the home page's ivars, or one level
// further (WeChat 8.0.73: NewMainFrameViewController.m_mainFrameLogicController
// holds it; diagnostics 7); else the one that last rebuilt on the main thread.
// Either way applyRule checks the list really follows it.
static id WXGHomeSessionManager(UIViewController *page,UITableView *table) {
    Class manager=objc_getClass("MainSessionMgr");if(!manager)return nil;
    NSHashTable *seen=[[NSHashTable alloc] initWithOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsOpaquePersonality capacity:64];
    NSInteger budget=900;
    id found=page?WXGFindManagerIn(page,manager,2,NSStringFromClass(page.class),seen,&budget):nil;
    id source=table.dataSource;
    if(!found && source && source!=page)found=WXGFindManagerIn(source,manager,2,NSStringFromClass([source class]),seen,&budget);
    if(found)return found;
    id rebuilt=WXGLastRebuiltManager;
    if(rebuilt){WXGManagerPath=@"(最近一次在主线程重建的 MainSessionMgr)";return rebuilt;}
    WXGManagerPath=nil;return nil;
}
// FIX113 R/S: a chat's display name, for the member picker only (never in
// the diagnostics). FIX113 S (user: "many groups and chats have no name;
// read the contacts"): every way WeChat keeps one is tried, and the 通讯录
// page's own contacts are read too (names and the friends not in the chat list).
static NSString *WXGNamedString(id obj,NSArray<NSString *> *keys) {
    if(!obj)return nil;
    for(NSString *key in keys) {
        @try {
            id v=WXGSessionField(obj,key.UTF8String);
            if([v isKindOfClass:NSString.class] && [v length])return v;
            if([v isKindOfClass:NSAttributedString.class] && [v length])return [v string];
        } @catch(__unused NSException *error) {}
    }
    return nil;
}
static NSArray<NSString *> *WXGContactNameKeys(void) {
    return @[@"m_nsRemark",@"getContactDisplayName",@"m_nsNickName",@"getRemark",@"getNickName",@"displayName",@"remark",@"nickname",@"nickName",
             @"m_nsDisplayName",@"m_nsChatRoomNickName"];   // (not m_nsAliasName: the 微信号, an ID)
}
// FIX113 T: whatever this WeChat calls a contact's names: its no-argument
// getters ending in a name word (found once per class; pinyin ones left out).
static NSArray<NSString *> *WXGDiscoveredNameGetters(Class cls) {
    static NSMutableDictionary<NSString *,NSArray *> *cache;if(!cache)cache=[NSMutableDictionary dictionary];
    NSString *key=NSStringFromClass(cls)?:@"";NSArray *known=cache[key];if(known)return known;
    NSMutableArray *out=[NSMutableArray array];NSArray *ends=@[@"Remark",@"remark",@"DisplayName",@"displayName",@"NickName",@"nickName",@"nickname",@"ShowName",@"showName",@"ChatRoomName"];
    for(Class c=cls;c && c!=NSObject.class && out.count<20;c=class_getSuperclass(c)) {
        unsigned int n=0;Method *methods=class_copyMethodList(c,&n);
        for(unsigned int i=0;i<n && out.count<20;i++) {
            NSString *sel=NSStringFromSelector(method_getName(methods[i]));
            if([sel containsString:@":"] || [sel hasPrefix:@"set"] || [sel rangeOfString:@"pinyin" options:NSCaseInsensitiveSearch].location!=NSNotFound ||
               [sel containsString:@"PY"] || [sel containsString:@"QuanPin"] || [out containsObject:sel])continue;
            for(NSString *end in ends)if([sel hasSuffix:end]){[out addObject:sel];break;}
        }
        free(methods);
    }
    cache[key]=out;return out;
}
static NSString *WXGContactTitle(id contact) {
    if(!contact)return nil;
    NSString *user=nil;@try{id u=WXGSessionField(contact,"m_nsUsrName");if([u isKindOfClass:NSString.class])user=u;}@catch(__unused NSException *e){}
    // FIX113 U: the getter list once per class (the address book may hold thousands).
    static NSMutableDictionary<NSString *,NSArray *> *lists;if(!lists)lists=[NSMutableDictionary dictionary];
    NSString *cls=NSStringFromClass(object_getClass(contact))?:@"";NSArray *getters=lists[cls];
    if(!getters){getters=[WXGContactNameKeys() arrayByAddingObjectsFromArray:WXGDiscoveredNameGetters(object_getClass(contact))];lists[cls]=getters;}
    for(NSString *getter in getters) {   // an ID (the user name, wxid_...) is not a name
        NSString *v=WXGNamedString(contact,@[getter]);
        if(v && ![v isEqual:user] && ![v hasPrefix:@"wxid_"] && ![v hasSuffix:@"@chatroom"])return v;
    }
    return nil;
}
// FIX113 Z: calls through the object itself (respondsToSelector: and its
// method signature), as the license code reads the account, which works on the
// tester's WeChat 8.0.73 ("MMContext · CContactMgr"). FIX113 U asked the class
// for the method (class_getInstanceMethod): a service handed out as a proxy,
// or a container that answers getService: by forwarding, has none, so the
// contact service was never found and every chat whose session had not
// loaded its contact yet (280 of 297) showed its ID.
static char WXGSigType(const char *type) {
    while(type && *type && strchr("rnNoORV",*type))type++;
    return type?*type:0;
}
// The selector's signature when it answers with an object and takes these
// argument kinds ('@' object, '#' class or object, 'i' any integer).
static BOOL WXGObjectCallFits(id target,SEL sel,const char *args) {
    if(!target || !sel)return NO;
    NSMethodSignature *sig=nil;
    @try {if([target respondsToSelector:sel])sig=[target methodSignatureForSelector:sel];} @catch(__unused NSException *error) {sig=nil;}
    size_t n=strlen(args);
    if(!sig || sig.numberOfArguments!=2+n || WXGSigType(sig.methodReturnType)!='@')return NO;
    for(size_t i=0;i<n;i++) {
        char t=WXGSigType([sig getArgumentTypeAtIndex:2+i]);
        if(args[i]=='@' && t!='@')return NO;
        if(args[i]=='#' && t!='#' && t!='@')return NO;
        if(args[i]=='i' && !strchr("IiLlQqSsCcB",t))return NO;
    }
    return YES;
}
static id WXGObjectCall0(id target,NSString *name) {
    SEL sel=NSSelectorFromString(name);if(!WXGObjectCallFits(target,sel,""))return nil;
    @try {return ((id (*)(id,SEL))objc_msgSend)(target,sel);} @catch(__unused NSException *error) {return nil;}
}
static id WXGObjectCall1(id target,NSString *name,const char *kind,id arg) {
    SEL sel=NSSelectorFromString(name);if(!WXGObjectCallFits(target,sel,kind))return nil;
    @try {return ((id (*)(id,SEL,id))objc_msgSend)(target,sel,arg);} @catch(__unused NSException *error) {return nil;}
}
static NSString *WXGContactServiceSource;
static NSArray<NSString *> *WXGContactServiceTried;   // diagnostics: each container and what it gave (class names only)
static NSString *WXGContactLookup;                    // the lookup selector that answered last
static id WXGContactService(void) {
    // Asked again after a while: another account has its own context.
    static __weak id cached;static CFTimeInterval cachedAt;
    id service=cached;
    if(cachedAt>0 && CACurrentMediaTime()-cachedAt<5)return service;   // (none found is kept for those 5 s too)
    cachedAt=CACurrentMediaTime();service=nil;
    Class mgr=objc_getClass("CContactMgr");if(!mgr){WXGContactServiceTried=@[@"没有 CContactMgr 类"];return nil;}
    NSMutableArray *tried=[NSMutableArray array];
    // The home list's own session manager holds its account's context
    // (MainSessionMgr.m_context, diagnostics 10); then the current context,
    // then the service centre of older WeChat.
    id managerContext=nil;
    @try {id manager=WXGLastRebuiltManager?:WXGFilterManager;managerContext=manager?WXGSessionField(manager,"m_context"):nil;} @catch(__unused NSException *error) {managerContext=nil;}
    NSArray *containers=@[@[@"MainSessionMgr.m_context",managerContext?:NSNull.null],
                          @[@"MMContext.currentContext",WXGObjectCall0(objc_getClass("MMContext"),@"currentContext")?:NSNull.null],
                          @[@"MMServiceCenter.defaultCenter",WXGObjectCall0(objc_getClass("MMServiceCenter"),@"defaultCenter")?:NSNull.null]];
    for(NSArray *pair in containers) {
        id container=pair[1];
        if(container==NSNull.null){[tried addObject:[pair[0] stringByAppendingString:@"：没有"]];continue;}
        id got=WXGObjectCall1(container,@"getService:","#",(id)mgr);
        [tried addObject:[NSString stringWithFormat:@"%@（%@）：%@",pair[0],NSStringFromClass(object_getClass(container)),
            got?NSStringFromClass(object_getClass(got)):[container respondsToSelector:NSSelectorFromString(@"getService:")]?@"getService: 返回空":@"不响应 getService:"]];
        if(got && !service){service=got;WXGContactServiceSource=pair[0];}
        if(service)break;
    }
    WXGContactServiceTried=tried;
    cached=service;return service;
}
static id WXGContactByName(NSString *name) {
    id service=WXGContactService();if(!service || !name.length)return nil;
    for(NSString *sel in @[@"getContactByName:",@"getContactForSearchByName:",@"getContactWithUserName:",@"getContactByUserName:"]) {
        id contact=WXGObjectCall1(service,sel,"@",name);
        if(contact && ![contact isKindOfClass:NSNull.class]){WXGContactLookup=sel;return contact;}
    }
    return nil;
}
// FIX113 U: the address book through the contact service (friends and saved
// groups), user name -> contact: getContactList:contactType: (1, 0), only
// when it has exactly that shape (two integers in, an object out).
static NSMutableDictionary<NSString *,id> *WXGServiceContacts(id service) {
    NSMutableDictionary *out=[NSMutableDictionary dictionary];if(!service)return out;
    SEL sel=NSSelectorFromString(@"getContactList:contactType:");
    if(!WXGObjectCallFits(service,sel,"ii"))return out;
    id list=nil;
    @try {list=((id (*)(id,SEL,unsigned long long,unsigned long long))objc_msgSend)(service,sel,1,0);} @catch(__unused NSException *error) {list=nil;}
    NSArray *items=[list isKindOfClass:NSArray.class]?[(NSArray *)list copy]:[list isKindOfClass:NSDictionary.class]?[(NSDictionary *)list allValues]:nil;
    if(items.count>20000)return out;
    for(id item in items) {
        NSString *user=nil;
        @try {id u=WXGSessionField(item,"m_nsUsrName");if([u isKindOfClass:NSString.class])user=u;} @catch(__unused NSException *error) {}
        if(user.length && !out[user])out[user]=item;
    }
    return out;
}
static NSDictionary *WXGNameProbe;   // how names were found (counts, classes, method names: no names)
// The 通讯录 page's contacts (its controller's own arrays: UI data, main
// thread), user name -> contact; empty when that tab was not opened yet.
static void WXGCollectContacts(id value,NSMutableDictionary *out,int depth,NSInteger *budget);
static NSMutableDictionary<NSString *,id> *WXGContactsPageContacts(NSString **source) {
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    Class contactsPage=objc_getClass("ContactsViewController");if(!contactsPage)return out;
    UIViewController *found=nil;NSMutableArray *queue=[NSMutableArray array];
    for(UIWindow *w in UIApplication.sharedApplication.windows)if(w.rootViewController)[queue addObject:w.rootViewController];
    for(NSUInteger i=0;i<queue.count && i<200 && !found;i++) {
        UIViewController *c=queue[i];
        if([c isKindOfClass:contactsPage]){found=c;break;}
        [queue addObjectsFromArray:c.childViewControllers];
        if([c isKindOfClass:UITabBarController.class])[queue addObjectsFromArray:((UITabBarController *)c).viewControllers?:@[]];
    }
    if(!found)return out;
    if(source)*source=NSStringFromClass(found.class);
    NSInteger budget=800;
    for(Class cls=object_getClass(found);cls && cls!=UIViewController.class;cls=class_getSuperclass(cls)) {
        unsigned int n=0;Ivar *ivars=class_copyIvarList(cls,&n);
        for(unsigned int i=0;i<n && budget>0;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]);if(!type || type[0]!='@' || type[1]=='?')continue;
            --budget;void *raw=WXGProbeRaw(found,cls,ivars[i]);
            if(!WXGProbeSafe(raw) || (intptr_t)raw<0)continue;
            WXGCollectContacts((__bridge id)raw,out,2,&budget);
        }
        free(ivars);
    }
    return out;
}
static void WXGCollectContacts(id value,NSMutableDictionary *out,int depth,NSInteger *budget) {
    if(!value || depth<0 || *budget<=0 || out.count>8000)return;
    --*budget;
    if([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSSet.class] || [value isKindOfClass:NSOrderedSet.class]) {
        NSArray *items=[value isKindOfClass:NSArray.class]?[(NSArray *)value copy]:[value allObjects];
        if(items.count>20000)return;
        for(id item in items)WXGCollectContacts(item,out,depth-1,budget);
        return;
    }
    if([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *d=[(NSDictionary *)value copy];if(d.count>20000)return;
        for(id item in d.allValues)WXGCollectContacts(item,out,depth-1,budget);
        return;
    }
    if([value isKindOfClass:NSString.class] || [value isKindOfClass:UIView.class] || [value isKindOfClass:NSNumber.class])return;
    NSString *user=nil;
    @try {id u=WXGSessionField(value,"m_nsUsrName");if([u isKindOfClass:NSString.class])user=u;} @catch(__unused NSException *error) {}
    if(user.length){if(!out[user])out[user]=value;return;}
    // A data object of the page (its contacts may be one level further).
    NSString *cname=NSStringFromClass(object_getClass(value));
    if(depth<=0 || !([cname containsString:@"Contact"] || [cname containsString:@"Logic"] || [cname containsString:@"Data"]))return;
    for(Class cls=object_getClass(value);cls && cls!=NSObject.class;cls=class_getSuperclass(cls)) {
        unsigned int n=0;Ivar *ivars=class_copyIvarList(cls,&n);
        for(unsigned int i=0;i<n && *budget>0;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]),*iname=ivar_getName(ivars[i]);if(!type || type[0]!='@' || type[1]=='?')continue;
            if(iname && (strstr(iname,"elegate") || strstr(iname,"arent") || strstr(iname,"ontroller")))continue;
            --*budget;void *raw=WXGProbeRaw(value,cls,ivars[i]);
            if(!WXGProbeSafe(raw) || (intptr_t)raw<0)continue;
            WXGCollectContacts((__bridge id)raw,out,depth-1,budget);
        }
        free(ivars);
    }
}
static NSString *WXGSessionTitle(id session,NSString *name,NSDictionary *contacts,NSMutableDictionary *how) {
    NSString *title=WXGContactTitle(WXGSessionField(session,"m_contact"));
    if(title){how[@"session.m_contact"]=@([how[@"session.m_contact"] integerValue]+1);return title;}
    title=WXGContactTitle(contacts[name]);
    if(title){how[@"addressBook"]=@([how[@"addressBook"] integerValue]+1);return title;}
    title=WXGContactTitle(WXGContactByName(name));
    if(title){how[@"CContactMgr"]=@([how[@"CContactMgr"] integerValue]+1);return title;}
    title=WXGNamedString(session,@[@"m_nsDisplayName",@"displayName",@"sessionName",@"m_nsNickName"]);
    if(title && ![title isEqual:name] && ![title hasPrefix:@"wxid_"]){how[@"session"]=@([how[@"session"] integerValue]+1);return title;}
    how[@"none"]=@([how[@"none"] integerValue]+1);
    return nil;
}
static NSArray<NSString *> *WXGMethodsLike(Class cls,NSArray<NSString *> *words,NSUInteger limit) {
    NSMutableArray *out=[NSMutableArray array];
    for(Class c=cls;c && c!=NSObject.class && out.count<limit;c=class_getSuperclass(c)) {
        unsigned int n=0;Method *methods=class_copyMethodList(c,&n);
        for(unsigned int i=0;i<n && out.count<limit;i++) {
            NSString *sel=NSStringFromSelector(method_getName(methods[i]));
            if([sel containsString:@":"])continue;
            for(NSString *w in words)if([sel rangeOfString:w options:NSCaseInsensitiveSearch].location!=NSNotFound){[out addObject:sel];break;}
        }
        free(methods);
    }
    return out;
}
NSArray<NSDictionary *> *WXGChatSessionChoices(void) {
    if(!NSThread.isMainThread)return @[];
    NSArray *sessions=WXGFilterSnapshot;
    if(!sessions.count) {
        id manager=WXGLastRebuiltManager?:WXGFilterManager;
        @try {
            NSArray *t=manager?WXGSessionGetObject(manager,@"topSessions"):nil,*n=manager?WXGSessionGetObject(manager,@"normalSessions"):nil;
            if([t isKindOfClass:NSArray.class] && [n isKindOfClass:NSArray.class] && atomic_load(&WXGFilterIndex)==0)sessions=[t arrayByAddingObjectsFromArray:n];
        } @catch(__unused NSException *error) {}
    }
    NSString *contactsSource=nil;NSMutableDictionary *contacts=nil;
    @try {contacts=WXGContactsPageContacts(&contactsSource);} @catch(__unused NSException *error) {contacts=[NSMutableDictionary dictionary];}
    NSUInteger bookCount=0;   // FIX113 U: the service's address book too (only when the picker opens)
    @try {
        NSDictionary *book=WXGServiceContacts(WXGContactService());bookCount=book.count;
        for(NSString *user in book)if(!contacts[user])contacts[user]=book[user];
    } @catch(__unused NSException *error) {}
    NSMutableArray *out=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];NSMutableDictionary *how=[NSMutableDictionary dictionary];
    id sampleContact=nil;
    for(id session in sessions) {
        @try {
            NSString *name=WXGSessionUserName(session);
            if(!name.length || [seen containsObject:name] || [name hasPrefix:@"@"])continue;
            NSInteger kind=WXGSessionKind(name);if(kind==0 && ![name hasPrefix:@"gh_"])continue;   // WeChat's own entries
            [seen addObject:name];
            if(!sampleContact)sampleContact=WXGSessionField(session,"m_contact")?:contacts[name]?:WXGContactByName(name);
            NSString *title=WXGSessionTitle(session,name,contacts,how);
            [out addObject:@{@"id":name,@"title":title?:[NSString stringWithFormat:@"%@（%@）",kind==3?@"未命名群聊":@"未命名",name.length>6?[name substringFromIndex:name.length-6]:name],@"kind":@(kind),@"inList":@YES}];
        } @catch(__unused NSException *error) {}
    }
    // Friends and saved groups of the 通讯录 page that are not in the chat list now.
    NSUInteger added=0;
    for(NSString *name in [contacts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if([seen containsObject:name] || [name hasPrefix:@"@"] || [name hasPrefix:@"gh_"])continue;
        NSInteger kind=WXGSessionKind(name);if(kind==0)continue;
        NSString *title=WXGContactTitle(contacts[name]);if(!title)continue;
        [seen addObject:name];++added;
        [out addObject:@{@"id":name,@"title":title,@"kind":@(kind),@"inList":@NO}];
    }
    NSMutableDictionary *probe=[NSMutableDictionary dictionary];
    probe[@"sessions"]=@(sessions.count);probe[@"choices"]=@(out.count);probe[@"how"]=how.copy;
    probe[@"contactsPage"]=contactsSource?:@"(通讯录页还没打开过)";probe[@"contacts"]=@(contacts.count);probe[@"addedFromContacts"]=@(added);
    probe[@"service"]=WXGContactService()?NSStringFromClass(object_getClass(WXGContactService())):@"none";
    probe[@"serviceFrom"]=WXGContactServiceSource?:@"none";probe[@"serviceContacts"]=@(bookCount);
    probe[@"serviceTried"]=WXGContactServiceTried?:@[];probe[@"lookup"]=WXGContactLookup?:@"none";   // FIX113 Z
    id firstSession=sessions.firstObject;
    if(firstSession) {
        probe[@"sessionClass"]=NSStringFromClass(object_getClass(firstSession));
        probe[@"sessionHasContact"]=@(class_getInstanceMethod(object_getClass(firstSession),sel_registerName("m_contact"))!=NULL ||
                                      class_getInstanceVariable(object_getClass(firstSession),"m_contact")!=NULL);
        probe[@"sessionNameMethods"]=WXGMethodsLike(object_getClass(firstSession),@[@"name",@"contact",@"display",@"title"],30);
    }
    if(sampleContact) {
        probe[@"contactClass"]=NSStringFromClass(object_getClass(sampleContact));
        NSArray *methods=WXGMethodsLike(object_getClass(sampleContact),@[@"name",@"remark",@"display",@"nick"],60);
        probe[@"contactNameMethods"]=methods;
        // Which of the name getters give something (yes / no only, never the text).
        NSMutableArray *answers=[NSMutableArray array];
        for(NSString *m in methods) {
            if(!([m hasSuffix:@"Name"] || [m hasSuffix:@"name"] || [m hasSuffix:@"Remark"] || [m hasSuffix:@"remark"]))continue;
            if([m hasPrefix:@"set"] || [m containsString:@"Pinyin"] || [m containsString:@"PinYin"])continue;
            @try {
                id v=WXGSessionField(sampleContact,m.UTF8String);
                BOOL has=([v isKindOfClass:NSString.class] && [v length]) || ([v isKindOfClass:NSAttributedString.class] && [v length]);
                [answers addObject:[NSString stringWithFormat:@"%@=%@",m,has?@"有":@"空"]];
            } @catch(__unused NSException *error) {[answers addObject:[m stringByAppendingString:@"=异常"]];}
            if(answers.count>=24)break;
        }
        probe[@"contactNameAnswers"]=answers;
        probe[@"dynamicGetters"]=@([sampleContact respondsToSelector:NSSelectorFromString(@"m_nsNickName")] &&
                                   !class_getInstanceMethod(object_getClass(sampleContact),NSSelectorFromString(@"m_nsNickName")));
    }
    WXGNameProbe=probe;
    return out;
}
// FIX113 Z: one line for the 选择聊天 page (counts and where names came from;
// never a name), so a screenshot shows why a chat shows its ID.
NSString *WXGChatNameSummary(void) {
    NSDictionary *probe=WXGNameProbe,*how=probe[@"how"];if(![how isKindOfClass:NSDictionary.class])return nil;
    NSInteger total=0;for(NSNumber *n in how.allValues)total+=n.integerValue;
    NSInteger none=[how[@"none"] integerValue],named=total-none;if(total<=0)return nil;
    NSMutableArray *parts=[NSMutableArray array];
    NSDictionary *labels=@{@"session.m_contact":@"聊天自带",@"addressBook":@"通讯录",@"CContactMgr":@"联系人服务",@"session":@"会话"};
    for(NSString *key in @[@"session.m_contact",@"addressBook",@"CContactMgr",@"session"])if([how[key] integerValue]>0)
        [parts addObject:[NSString stringWithFormat:@"%@ %@",labels[key],how[key]]];
    NSString *from=[probe[@"serviceFrom"] isEqual:@"none"]?@"没找到":probe[@"serviceFrom"];
    if(!none)return [NSString stringWithFormat:@"名字全部读到（%@）· 联系人服务：%@",[parts componentsJoinedByString:@" · "],from];
    return [NSString stringWithFormat:@"名字读到 %ld / %ld（%@）· 联系人服务：%@。没读到的显示“未命名（ID 末 6 位）”，导出诊断发给作者能看到原因。",
            (long)named,(long)total,parts.count?[parts componentsJoinedByString:@" · "]:@"无",from];
}
// What the table's data source counts (it is asked directly: no cell made).
static NSInteger WXGDataSourceRows(UITableView *table) {
    id<UITableViewDataSource> source=table.dataSource;
    if(!source || ![source respondsToSelector:@selector(tableView:numberOfRowsInSection:)])return -1;
    NSInteger sections=[source respondsToSelector:@selector(numberOfSectionsInTableView:)]?[source numberOfSectionsInTableView:table]:1,total=0;
    for(NSInteger s=0;s<sections && s<64;s++)total+=[source tableView:table numberOfRowsInSection:s];
    return total;
}

#pragma mark - FIX113 O: floating search

/* User: a switch to keep the segment bar (and the home page's and 通讯录's
   search bars) floating at the title capsule's level instead of scrolling
   away with the list. The segment bar is the plugin's own: it moves into the
   navigation overlay (the title capsule's) and stops below the title row
   (the list's visible top plus its own distance from the header's top).
   WeChat's search bars stay WeChat's: once one scrolls past that line a
   floating capsule (the other glass's material, a magnifier and 搜索) takes
   its place there and the bar is faded out; tapped, the list goes back to
   its top and WeChat's own field is focused (its own search, as a tap on it). */
static CGRect WXGVisibleSearchBox(UIView *bar);
static NSString *const WXGDrawnBoxSource=@"WCSearchBar box";
// Read both ends from one layer tree. While UIKit scrolls the table, its model
// geometry is already at the next commit; mixing model and presentation layers
// would put the title and floating field a frame apart.
static CGRect WXGHomeRect(UIView *source,CGRect rect,UIView *target,BOOL presenting) {
    if(presenting) {
        CALayer *from=source.layer.presentationLayer,*to=target.layer.presentationLayer;
        if(from && to)return [from convertRect:rect toLayer:to];
    }
    return [source convertRect:rect toView:target];
}
static BOOL WXGHomeSearchExposed(UIViewController *page) {
    static Class home;static dispatch_once_t once;
    dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");});
    if(!home || ![page isKindOfClass:home] || !page.viewIfLoaded.window || page.transitionCoordinator)return NO;
    for(UIViewController *child=page;child;child=child.parentViewController) {
        if(child.presentedViewController || child.isBeingDismissed || child.isMovingFromParentViewController)return NO;
        UIViewController *parent=child.parentViewController;
        if([parent isKindOfClass:UINavigationController.class] && ((UINavigationController *)parent).topViewController!=child)return NO;
        if([parent isKindOfClass:UITabBarController.class] && ((UITabBarController *)parent).selectedViewController!=child)return NO;
    }
    return YES;
}
@interface WXGFloatingSearch : UIControl
@property(nonatomic,strong,readonly) WXGSurface *surface;
// FIX114 M: at WeChat's bar's own place: touches go through to WeChat's bar
// (hidden by a mask, not faded: still touchable), its own search opens.
@property(nonatomic) BOOL passThrough;
- (BOOL)copyLookOf:(UIView *)bar;   // FIX114 F: WeChat's own icon, text, font, colours and spacing (NO: not found yet)
@end
@implementation WXGFloatingSearch {
    UIImageView *_icon;UILabel *_label;
    CGRect _iconRect,_labelRect;CGSize _boxSize;BOOL _native;   // FIX114 F: WeChat's, in its box
}
// FIX114 F (user: the capsule never looked like WeChat's box): the look of
// the WCSearchBar it stands in for, so swapping the two (leaving the page,
// coming back) shows nothing changing: its icon at its size, its label's
// text, font and colour, the gap between them.
- (BOOL)copyLookOf:(UIView *)bar {
    static Class custom;static dispatch_once_t once;dispatch_once(&once,^{custom=NSClassFromString(@"WCSearchBar");});
    UIView *wc=custom && [bar isKindOfClass:custom]?bar:nil;
    if(!wc && custom)for(UIView *v in WXGViews(bar,80))if([v isKindOfClass:custom] && !v.hidden){wc=v;break;}
    CGRect box=wc?WXGVisibleSearchBox(wc):CGRectNull;   // in wc
    if(CGRectIsNull(box))return NO;
    // Only what is drawn inside the box: not a hidden 取消 button's title, not
    // a text field's placeholder, not a themed picture elsewhere in the bar.
    BOOL (^shown)(UIView *)=^BOOL(UIView *v) {
        if(WXGIsPluginView(v))return NO;
        for(UIView *u=v;u && u!=wc;u=u.superview)if(u.hidden || u.alpha<.01 || (u!=v && [u isKindOfClass:UITextField.class]))return NO;
        return YES;
    };
    NSMutableArray<UILabel *> *labels=[NSMutableArray array];NSMutableArray<UIImageView *> *images=[NSMutableArray array];
    for(UIView *v in WXGViews(wc,120)) {
        if([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length && shown(v))[labels addObject:(UILabel *)v];
        else if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && shown(v))[images addObject:(UIImageView *)v];
    }
    // The pair: a glyph (8–32 pt) and the text just right of it on its row;
    // of several pairs, the one with the largest text.
    UILabel *label=nil;UIImageView *icon=nil;CGRect t=CGRectNull,i=CGRectNull;
    for(UILabel *l in labels) {
        CGRect lr=[l convertRect:l.bounds toView:wc];
        if(lr.size.width<4 || lr.size.height<4 || !CGRectContainsPoint(box,CGPointMake(CGRectGetMidX(lr),CGRectGetMidY(lr))))continue;
        if(label && lr.size.width*lr.size.height<=t.size.width*t.size.height)continue;
        UIImageView *glyph=nil;CGRect gr=CGRectNull;
        for(UIImageView *g in images) {
            CGRect r=[g convertRect:g.bounds toView:wc];
            if(r.size.width<8 || r.size.width>32 || r.size.height<8 || r.size.height>32 || !CGRectContainsPoint(box,CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r))))continue;
            if(CGRectGetMaxX(r)>CGRectGetMinX(lr)+1 || CGRectGetMinX(lr)-CGRectGetMaxX(r)>16 || fabs(CGRectGetMidY(r)-CGRectGetMidY(lr))>8)continue;
            if(!glyph || CGRectGetMaxX(r)>CGRectGetMaxX(gr)){glyph=g;gr=r;}
        }
        if(glyph){label=l;t=lr;icon=glyph;i=gr;}
    }
    if(!label || !icon)return NO;
    _icon.image=icon.image;_icon.tintColor=icon.tintColor;_icon.contentMode=icon.contentMode;
    _label.font=label.font;_label.textColor=label.textColor;_label.textAlignment=label.textAlignment;
    _label.attributedText=label.attributedText;   // its colours if it draws them that way
    self.accessibilityLabel=label.text;
    _iconRect=CGRectOffset(i,-box.origin.x,-box.origin.y);_labelRect=CGRectOffset(t,-box.origin.x,-box.origin.y);_boxSize=box.size;_native=YES;
    [self setNeedsLayout];
    return YES;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.clipsToBounds=NO;
        _surface=[WXGSurface new];_surface.materialOnly=YES;_surface.userInteractionEnabled=NO;_surface.role=@"floatingSearch";
        [self addSubview:_surface];self.hidden=YES;[_surface applyConfig];
        UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
        _icon=[[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _icon.tintColor=UIColor.secondaryLabelColor;_icon.userInteractionEnabled=NO;[self addSubview:_icon];
        _label=[UILabel new];_label.text=@"搜索";_label.font=[UIFont systemFontOfSize:16];_label.textColor=UIColor.secondaryLabelColor;
        _label.userInteractionEnabled=NO;[self addSubview:_label];
        self.isAccessibilityElement=YES;self.accessibilityLabel=@"搜索";self.accessibilityTraits=UIAccessibilityTraitButton;
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if(_passThrough)return nil;   // FIX114 M
    return [super hitTest:point withEvent:event];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [_surface placeMaterial:self.bounds inParent:self];
    if(_native) {   // Center actual visual icon+title pair inside resized floating capsule.
        CGRect pair=(CGRectIsEmpty(_iconRect) && CGRectIsEmpty(_labelRect))?CGRectMake(0,0,_boxSize.width,_boxSize.height)
            :(CGRectIsEmpty(_iconRect)?_labelRect:(CGRectIsEmpty(_labelRect)?_iconRect:CGRectUnion(_iconRect,_labelRect)));
        CGFloat dx=CGRectGetMidX(self.bounds)-CGRectGetMidX(pair),dy=CGRectGetMidY(self.bounds)-CGRectGetMidY(pair);
        _icon.frame=CGRectOffset(_iconRect,dx,dy);_label.frame=CGRectOffset(_labelRect,dx,dy);return;
    }
    CGSize i=_icon.image.size,t=[_label sizeThatFits:CGSizeMake(200,40)];
    CGFloat total=i.width+5+t.width,x=(self.bounds.size.width-total)*.5,mid=CGRectGetMidY(self.bounds);
    _icon.frame=CGRectMake(round(x),round(mid-i.height*.5),i.width,i.height);
    _label.frame=CGRectMake(round(x+i.width+5),round(mid-t.height*.5),ceil(t.width),ceil(t.height));
}
@end
@interface WXGFloatSlot : NSObject
@property(nonatomic,weak) UIViewController *page;
@property(nonatomic,weak) UITableView *table;
@property(nonatomic,weak) UIView *bar;
@property(nonatomic) CGRect field;   // in the bar
@property(nonatomic) CFTimeInterval scanned;
@property(nonatomic,strong) WXGFloatingSearch *clone;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic,weak) UIView *ownedHeader;
@property(nonatomic,weak) UITextField *editingField;
@property(nonatomic) CGRect naturalFrame;
// FIX114 F: exact: the field is WeChat's drawn box (or the last one seen);
// since: when this bar was found; the look: WeChat's icon and text copied.
@property(nonatomic) BOOL pinned,parked,lookCopied,exact;
@property(nonatomic,weak) UITextField *nativeField;
@property(nonatomic) CGRect lastExact;   // meaningful when exact
@property(nonatomic) CFTimeInterval since,measured,lookTried,lookAgainAt;
@property(nonatomic) NSUInteger misses,lookTries;
@property(nonatomic) UIUserInterfaceStyle lookStyle;
@property(nonatomic) NSUInteger pins,taps;
@end
@implementation WXGFloatSlot
@end

#pragma mark - The manager

// R23: read real live presentation-layer opacity of MFTitleView and its labels
// without installing KVO, swizzling UIKit wrappers, or mounting subviews inside MFTitleView.
static CGFloat WXGPresentedChainAlpha(UIView *v,UIWindow *w) {
    if(!v || !w || v.window!=w)return 0.;
    CGFloat a=1.;
    for(UIView *p=v;p && p!=w;p=p.superview) {
        if(p.hidden)return 0.;
        CALayer *l=p.layer.presentationLayer?:p.layer;
        if(l.hidden)return 0.;
        a*=l.opacity;
        if(a<.005)return 0.;
    }
    return WXGClamp(a,0.,1.);
}
static CGFloat WXGTitleContentPresentedAlpha(UIView *tv) {
    if(!tv)return 0.;
    BOOL hasLabel=NO;CGFloat maxAlpha=0.;
    NSUInteger n=0;
    for(UIView *c in tv.subviews) {
        if(WXGIsPluginView(c))continue;
        if(++n>16)break;
        if([c isKindOfClass:UILabel.class]) {
            UILabel *lb=(UILabel *)c;
            if(!lb.text.length && !lb.attributedText.length)continue;
            hasLabel=YES;
            if(!lb.hidden) {
                CALayer *l=lb.layer.presentationLayer?:lb.layer;
                if(!l.hidden)maxAlpha=MAX(maxAlpha,l.opacity);
            }
        }else if([c isKindOfClass:UIActivityIndicatorView.class] && ((UIActivityIndicatorView *)c).isAnimating) {
            if(!c.hidden) {
                CALayer *l=c.layer.presentationLayer?:c.layer;
                if(!l.hidden)maxAlpha=MAX(maxAlpha,l.opacity);
            }
        }else {
            NSUInteger m=0;
            for(UIView *d in c.subviews) {
                if(WXGIsPluginView(d))continue;
                if(++m>8)break;
                if([d isKindOfClass:UILabel.class]) {
                    UILabel *lb=(UILabel *)d;
                    if(!lb.text.length && !lb.attributedText.length)continue;
                    hasLabel=YES;
                    if(!c.hidden && !lb.hidden) {
                        CALayer *cl=c.layer.presentationLayer?:c.layer;
                        CALayer *dl=lb.layer.presentationLayer?:lb.layer;
                        if(!cl.hidden && !dl.hidden)maxAlpha=MAX(maxAlpha,cl.opacity*dl.opacity);
                    }
                }
            }
        }
    }
    return hasLabel?WXGClamp(maxAlpha,0.,1.):1.;
}

// Keep the search view at its native height. Enlarging a UISearchBar or its
// stack view recentres its contents and feeds that offset back into the next layout.
@interface WXGHomeGroupHeader : UIView
@property(nonatomic,strong) UIView *nativeHeader,*pendingNativeHeader;
@property(nonatomic,strong) WXGStateBag *pendingPaint;
@property(nonatomic) UIViewAutoresizing pendingResize;
@property(nonatomic,weak) UITableView *owner;
@property(nonatomic) UIViewAutoresizing nativeResize;
@property(nonatomic) CGFloat leading,reservedHeight;
@property(nonatomic) CGFloat restInset;
@property(nonatomic) UIEdgeInsets restSafe,checkedRaw,checkedAdjusted;
@property(nonatomic) CGSize restViewport;
@property(nonatomic) BOOL correctingRest,awaitingHomeAppearance,hasNativeInsetRequest;
@property(nonatomic) CGFloat lastNativeTop;
@property(nonatomic) NSUInteger insetAttempts,insetRepairs,deferredSearchAssignments;
@property(nonatomic) CFTimeInterval nextCalibration;
@property(nonatomic) BOOL holdingForSpacer;
@property(nonatomic,strong) UIView *nativeSpacer;
- (void)replaceSearch:(BOOL)replace;
- (void)finishPendingSearchKeeping:(UIView *)next;
@property(nonatomic,strong) UIView *nativeCanvas;
@property(nonatomic,strong) NSMapTable<UIView *,NSArray<NSValue *> *> *nativeInkTransforms;
- (void)restoreNativeInk;
- (void)placeNativeAtLeading:(CGFloat)leading field:(CGRect)field target:(CGRect)target;
@end
@implementation WXGHomeGroupHeader
- (void)finishPendingSearchKeeping:(UIView *)next {
    UIView *pending=_pendingNativeHeader;
    if(!pending)return;
    _pendingNativeHeader=nil;
    if(pending.superview==_nativeCanvas) {
        if(pending!=next)[pending removeFromSuperview];
        pending.autoresizingMask=_pendingResize;
    }else if(pending.autoresizingMask==UIViewAutoresizingFlexibleWidth)pending.autoresizingMask=_pendingResize;
    [_pendingPaint restore];_pendingPaint=nil;
}
// Native callers may size their search field by assigning the frame of tableHeaderView.
// The table must continue to see the height of both rows, including during a pan.
- (void)setFrame:(CGRect)frame {
    if(_reservedHeight>0)frame.size.height=_reservedHeight;
    [super setFrame:frame];
}
- (void)setBounds:(CGRect)bounds {
    if(_reservedHeight>0)bounds.size.height=_reservedHeight;
    [super setBounds:bounds];
}
- (void)replaceSearch:(BOOL)replace {
    if(_nativeCanvas.hidden==replace)return;
    _nativeCanvas.hidden=replace;
    WXGSetSearchHeaderFloating(_nativeCanvas,replace);
}
- (void)restoreNativeInk {
    for(UIView *view in _nativeInkTransforms.keyEnumerator) {
        NSArray<NSValue *> *pair=[_nativeInkTransforms objectForKey:view];
        if(CGAffineTransformEqualToTransform(view.transform,pair.lastObject.CGAffineTransformValue))
            view.transform=pair.firstObject.CGAffineTransformValue;
    }
    [_nativeInkTransforms removeAllObjects];
}
- (void)placeNativeAtLeading:(CGFloat)leading field:(CGRect)field target:(CGRect)target {
    _leading=leading;
    // The canvas owns the display geometry of an unstyled WeChat search row.
    // Its field keeps its native bounds for measurement, editing and hit testing.
    CGSize size=CGSizeMake(self.bounds.size.width,_nativeHeader.bounds.size.height);
    CGFloat sx=1,sy=1;
    CGPoint center=CGPointMake(size.width*.5,leading+size.height*.5);
    if(!CGRectIsEmpty(field) && !CGRectEqualToRect(field,target)) {
        sx=target.size.width/field.size.width;sy=target.size.height/field.size.height;
        center.x=CGRectGetMidX(target)+(size.width*.5-CGRectGetMidX(field))*sx;
        center.y=leading+CGRectGetMidY(target)+(size.height*.5-CGRectGetMidY(field))*sy;
    }
    [self restoreNativeInk];
    if(sx!=1 || sy!=1) {
        if(!_nativeInkTransforms)_nativeInkTransforms=[NSMapTable weakToStrongObjectsMapTable];
        CGPoint fieldCenter=CGPointMake(CGRectGetMidX(field),CGRectGetMidY(field));
        for(UIView *v in WXGViews(_nativeHeader,160)) {
            BOOL label=[v isKindOfClass:UILabel.class];
            BOOL glyph=[v isKindOfClass:UIImageView.class] && v.bounds.size.width<=36 && v.bounds.size.height<=36;
            if((!label && !glyph) || v.hidden || !v.superview)continue;
            CGPoint p=[v.superview convertPoint:v.center toView:_nativeHeader];
            if(!CGRectContainsPoint(field,p))continue;
            CGPoint local=[_nativeHeader convertPoint:fieldCenter toView:v.superview];
            CGAffineTransform saved=v.transform;
            CGAffineTransform t=CGAffineTransformConcat(saved,CGAffineTransformMakeScale(1/sx,1/sy));
            t.tx+=(v.center.x-local.x)*(1/sx-1);t.ty+=(v.center.y-local.y)*(1/sy-1);
            [_nativeInkTransforms setObject:@[[NSValue valueWithCGAffineTransform:saved],[NSValue valueWithCGAffineTransform:t]] forKey:v];
            v.transform=t;
        }
    }
    if(!CGSizeEqualToSize(_nativeCanvas.bounds.size,size))_nativeCanvas.bounds=(CGRect){CGPointZero,size};
    CGAffineTransform transform=CGAffineTransformMakeScale(sx,sy);
    if(!CGAffineTransformEqualToTransform(_nativeCanvas.transform,transform))_nativeCanvas.transform=transform;
    if(!CGPointEqualToPoint(_nativeCanvas.center,center))_nativeCanvas.center=center;
}
@end
UIView *WXGHomeNativeSearchHeader(UIView *header) {
    return [header isKindOfClass:WXGHomeGroupHeader.class]?((WXGHomeGroupHeader *)header).nativeHeader:header;
}
// Reading UISearchBar.searchTextField can create UIKit's otherwise unused
// text field while WeChat is installing its own WCSearchBar.
UITextField *WXGInstalledSearchField(UIView *bar) {
    UITextField *first=nil;
    for(UIView *v in WXGViews(bar,100))if([v isKindOfClass:UITextField.class]) {
        UITextField *field=(UITextField *)v;
        if(field.isFirstResponder)return field;
        if(!first || [field isKindOfClass:UISearchTextField.class])first=field;
    }
    return first;
}

@interface WXGChatSegments (HomeHeaderAssignment)
- (BOOL)reuseRowsForTable:(UITableView *)table nativeHeader:(UIView *)native;
- (void)homeTableInsetChanged:(UITableView *)table;
- (void)traceHomeEvent:(NSString *)event before:(CGFloat)before after:(CGFloat)after;
@end

static NSUInteger WXGHomeHeaderReuses;
static __weak UITableView *WXGGroupedTable;
static __weak WXGHomeGroupHeader *WXGGroupedRows;
static IMP WXGUIKitInsetSetter,WXGUIKitInsetGetter;
static BOOL WXGHasNativeInsetRequest;
static CGFloat WXGNativeInsetRequest;
BOOL WXGHomeTaskbarContains(UIView *view) {
    static Class top,task;static dispatch_once_t once;
    dispatch_once(&once,^{top=NSClassFromString(@"WAMainFrameTopHeaderView");task=NSClassFromString(@"WAMainFrameTaskBarView");});
    for(UIView *v=view;v;v=v.superview) {
        if([v isKindOfClass:top] || [v isKindOfClass:task])return YES;
        if([v isKindOfClass:UITableView.class] && v==WXGGroupedTable)break;
    }
    return NO;
}
BOOL WXGHomeSearchIsStaged(UIView *view) {
    UIView *pending=WXGGroupedRows.pendingNativeHeader;
    return pending && (view==pending || [view isDescendantOfView:pending]);
}
static BOOL WXGHomeSameViewport(WXGHomeGroupHeader *rows,UIScrollView *list) {
    return rows && rows.owner==list && list.window && CGSizeEqualToSize(rows.restViewport,list.bounds.size) &&
        UIEdgeInsetsEqualToEdgeInsets(rows.restSafe,list.window.safeAreaInsets);
}
static BOOL WXGHomeIsConversationTable(UIScrollView *list) {
    static Class home;static dispatch_once_t once;dispatch_once(&once,^{home=NSClassFromString(@"MainFrameTableView");});
    return list && (list==WXGGroupedTable || [list isKindOfClass:home]);
}
CGFloat WXGHomeConversationTop(UIScrollView *list) {
    if(!WXGHomeIsConversationTable(list))return list.adjustedContentInset.top;
    WXGHomeGroupHeader *rows=list==WXGGroupedTable?WXGGroupedRows:nil;
    if(rows.restInset>0 && WXGHomeSameViewport(rows,list))return rows.restInset;
    return WXGHomeInitialConversationTop(list.contentInset.top,list.adjustedContentInset.top,list.bounds.size.height,list.window.screen.scale);
}
BOOL WXGHomeListInNativePull(UIScrollView *list) {
    if(!WXGHomeIsConversationTable(list))return NO;
    CGFloat adjusted=list.adjustedContentInset.top,raw=list.contentInset.top;
    WXGHomeGroupHeader *rows=list==WXGGroupedTable?WXGGroupedRows:nil;
    CGFloat rest=WXGHomeSameViewport(rows,list)?rows.restInset:0.;
    CGFloat offset=list.contentOffset.y,scale=list.window.screen.scale;
    if(rest<=0)rest=WXGHomeInitialConversationTop(raw,adjusted,list.bounds.size.height,scale);
    if(list.refreshControl.refreshing)return YES;
    if(list==WXGGroupedTable && WXGHasNativeInsetRequest && rest>=20. && WXGNativeInsetRequest>rest+1.)return YES;
    // At cold launch UIKit may already be resting at two copies of the chrome
    // height. Let the Home row mount and verify that case even before calibration.
    if((!rows.hasNativeInsetRequest || rows.lastNativeTop==0.) && !list.tracking && !list.dragging && !list.decelerating &&
       WXGHomeAtDuplicatedRest(rest,raw,adjusted,offset,scale))return NO;
    return WXGHomeNativePull(rest,raw,adjusted,offset,list.bounds.size.height,scale);
}
CGFloat WXGHomeListTop(UIScrollView *list) {
    CGFloat top=list.adjustedContentInset.top;
    if(!list || list!=WXGGroupedTable)return top;
    CGFloat raw=list.contentInset.top;
    if(raw==0 || raw==top)return top;
    WXGHomeGroupHeader *rows=(id)WXGGroupedTable.tableHeaderView;
    if(rows!=WXGGroupedRows || list.refreshControl.refreshing || !WXGHomeSameViewport(rows,list))return top;
    return WXGHomeEffectiveTop(rows.restInset,raw,top,list.window.screen.scale);
}
static IMP WXGUIKitHeaderSetter;
static BOOL WXGHomeWritesEnabled;
static double WXGHomeTableLayoutMS,WXGHomeHeaderWorkMS;
typedef struct {
    double cellMS,navigationMS,reloadMS,navigationBuildMS,navigationTraceMS;
    unsigned layouts,cells,navigations,reloads;
} WXGHomeFrameWork;
static WXGHomeFrameWork WXGHomeWork;
static __weak UINavigationBar *WXGHomeWatchedNavigation;
void WXGRecordHomeNavigationWork(UINavigationBar *bar,double buildMS,double traceMS) {
    if(WXGHomeWritesEnabled && bar && bar==WXGHomeWatchedNavigation) {
        WXGHomeWork.navigationBuildMS+=buildMS;WXGHomeWork.navigationTraceMS+=traceMS;
    }
}
// The wrapper is our layout object. Only real native assignments should notify
// MainFrameTableView's own search/taskbar bookkeeping.
static void WXGPublishHomeRows(UITableView *table,WXGHomeGroupHeader *rows) {
    if(WXGUIKitHeaderSetter && table==WXGGroupedTable)
        ((void(*)(id,SEL,id))WXGUIKitHeaderSetter)(table,@selector(setTableHeaderView:),rows);
    else table.tableHeaderView=rows;
}
static void WXGNoteInsetSource(UITableView *table,BOOL requested,CGFloat raw,CGFloat rest);
static void WXGObserveHomeHeader(UITableView *table) {
    Class home=NSClassFromString(@"MainFrameTableView");
    if(!home || ![table isKindOfClass:home])return;
    WXGGroupedTable=table;
    static dispatch_once_t install;dispatch_once(&install,^{
        // WeChat's override owns the transition between its two title/search hosts.
        // Let it run with the native search view. Normalize only at UIKit's storage boundary.
        SEL setter=@selector(setTableHeaderView:);
        Method m=class_getInstanceMethod(UITableView.class,setter);IMP put=method_getImplementation(m);WXGUIKitHeaderSetter=put;
        WXGInstallOverride(UITableView.class,setter,imp_implementationWithBlock(^(UITableView *list,UIView *header){
            if(list!=WXGGroupedTable){((void(*)(id,SEL,id))put)(list,setter,header);return;}
            CFTimeInterval start=WXGHomeWritesEnabled?CACurrentMediaTime():0;
            if(![WXGChatSegments.shared reuseRowsForTable:list nativeHeader:header])((void(*)(id,SEL,id))put)(list,setter,header);
            if(start>0)WXGHomeHeaderWorkMS+=(CACurrentMediaTime()-start)*1000.;
        }),method_getTypeEncoding(m));
        SEL inset=@selector(setContentInset:);
        Method systemSetter=class_getInstanceMethod(UIScrollView.class,inset);
        IMP store=method_getImplementation(systemSetter);WXGUIKitInsetSetter=store;
        WXGUIKitInsetGetter=class_getMethodImplementation(UIScrollView.class,@selector(contentInset));
        WXGInstallOverride(UIScrollView.class,inset,imp_implementationWithBlock(^(UIScrollView *list,UIEdgeInsets value){
            // All other lists, and the real full-height Home taskbar, go straight through.
            WXGHomeGroupHeader *rows=nil;
            if(list==WXGGroupedTable && WXGHasNativeInsetRequest && WXGNativeInsetRequest==0. && value.top>0.) {
                WXGHomeGroupHeader *installed=WXGGroupedRows;
                CGFloat automatic=list.adjustedContentInset.top-list.contentInset.top;
                if(WXGHomeSameViewport(installed,list) &&
                   !list.refreshControl.refreshing && !WXGGroupedTable.editing &&
                   WXGHomeDuplicatesZeroRequest(WXGNativeInsetRequest,value.top,automatic,installed.restInset,list.window.screen.scale)) {
                    rows=installed;value.top=0.;++rows.insetAttempts;
                }
            }
            ((void(*)(id,SEL,UIEdgeInsets))store)(list,inset,value);
            if(rows && WXGHomeSameInset(list.contentInset.top,0,list.window.screen.scale) &&
               WXGHomeSameInset(list.adjustedContentInset.top,rows.restInset,list.window.screen.scale))++rows.insetRepairs;
        }),method_getTypeEncoding(systemSetter));
        IMP own=WXGOwnImplementation(home,inset);Class parent=class_getSuperclass(home);
        WXGInstallOverride(home,inset,imp_implementationWithBlock(^(UITableView *list,UIEdgeInsets requested){
            IMP next=WXGThrough(own,parent,inset);
            if(list!=WXGGroupedTable){((void(*)(id,SEL,UIEdgeInsets))next)(list,inset,requested);return;}
            BOOL had=WXGHasNativeInsetRequest;CGFloat previous=WXGNativeInsetRequest;
            BOOL trace=WXGHomeWritesEnabled && fabs(requested.top-list.contentInset.top)>.01;
            WXGGroupedRows.hasNativeInsetRequest=YES;WXGGroupedRows.lastNativeTop=requested.top;
            WXGHasNativeInsetRequest=YES;WXGNativeInsetRequest=requested.top;
            @try {((void(*)(id,SEL,UIEdgeInsets))next)(list,inset,requested);}
            @finally {WXGHasNativeInsetRequest=had;WXGNativeInsetRequest=previous;}
            if(!had && requested.top==0. && WXGHomeHasTwoNavigationInsets(WXGGroupedRows.restInset,list.contentInset.top,list.adjustedContentInset.top,list.window.screen.scale))
                [WXGChatSegments.shared homeTableInsetChanged:list];
            if(trace)WXGNoteInsetSource(list,YES,requested.top,WXGGroupedRows.restInset);
        }),method_getTypeEncoding(class_getInstanceMethod(home,inset)));
        SEL adjusted=@selector(adjustedContentInsetDidChange);
        m=class_getInstanceMethod(home,adjusted);IMP originalAdjusted=method_getImplementation(m);
        WXGInstallOverride(home,adjusted,imp_implementationWithBlock(^(UITableView *list){
            ((void(*)(id,SEL))originalAdjusted)(list,adjusted);
            if(list==WXGGroupedTable)[WXGChatSegments.shared homeTableInsetChanged:list];
        }),method_getTypeEncoding(m));
    });
}

// Only install the offset observers if the user enables the full Home trace.
enum { WXGHomeWriteCapacity=96, WXGHomeStackDepth=8 };
typedef struct {
    double time;
    CGFloat before,target,after;
    int kind,stackDepth;
    BOOL moving;
    void *stack[WXGHomeStackDepth];
} WXGHomeOffsetWrite;
static WXGHomeOffsetWrite WXGHomeWrites[WXGHomeWriteCapacity];
static NSUInteger WXGHomeWriteCount;
static BOOL WXGHomeInOffsetWrite;
static double WXGHomeLastStack;
static __weak UITableView *WXGHomeWatchedTable;
typedef struct {
    double time,raw,automatic,rest,actualRaw,actualAdjusted,storedTop;
    NSInteger policy;
    BOOL requested;
    int count;
    void *stack[WXGHomeStackDepth];
} WXGHomeInsetWrite;
static WXGHomeInsetWrite WXGHomeInsetWrites[16];
static NSUInteger WXGHomeInsetWriteCount;
static void WXGNoteInsetSource(UITableView *table,BOOL requested,CGFloat raw,CGFloat rest) {
    if(!WXGHomeWritesEnabled || table!=WXGHomeWatchedTable)return;
    CGFloat actualRaw=table.contentInset.top,actualAdjusted=table.adjustedContentInset.top,automatic=actualAdjusted-actualRaw;
    double time=WXGSecondsSinceLoad();
    WXGHomeInsetWrite *last=WXGHomeInsetWriteCount?&WXGHomeInsetWrites[(WXGHomeInsetWriteCount-1)%16]:NULL;
    if(last && last->requested==requested && last->raw==raw && last->actualRaw==actualRaw &&
       last->automatic==automatic && last->policy==table.contentInsetAdjustmentBehavior && time-last->time<.25)return;
    WXGHomeInsetWrite *entry=&WXGHomeInsetWrites[WXGHomeInsetWriteCount++%16];
    entry->time=time;entry->raw=raw;entry->automatic=automatic;entry->rest=rest;entry->requested=requested;
    entry->actualRaw=actualRaw;entry->actualAdjusted=actualAdjusted;entry->policy=table.contentInsetAdjustmentBehavior;
    entry->storedTop=WXGUIKitInsetGetter?((UIEdgeInsets(*)(id,SEL))WXGUIKitInsetGetter)(table,@selector(contentInset)).top:actualRaw;
    entry->count=backtrace(entry->stack,WXGHomeStackDepth);
}

static WXGHomeOffsetWrite *WXGBeginHomeWrite(UITableView *list,CGFloat target,int kind) {
    if(!WXGHomeWritesEnabled || WXGHomeInOffsetWrite || list!=WXGHomeWatchedTable)return NULL;
    CGFloat before=list.contentOffset.y;
    BOOL moving=list.tracking || list.dragging || list.decelerating;
    if(fabs(before-target)<(moving?MAX(64.,list.bounds.size.height*.25):.125))return NULL;
    WXGHomeInOffsetWrite=YES;
    WXGHomeOffsetWrite *write=&WXGHomeWrites[WXGHomeWriteCount++%WXGHomeWriteCapacity];
    write->time=WXGSecondsSinceLoad();write->before=before;write->target=target;write->kind=kind;write->moving=moving;
    // Symbolicate only when exporting. Limit stack collection when UIKit issues several setters at once.
    write->stackDepth=0;
    if(write->time-WXGHomeLastStack>.25) {
        write->stackDepth=backtrace(write->stack,WXGHomeStackDepth);WXGHomeLastStack=write->time;
    }
    return write;
}
static void WXGEndHomeWrite(WXGHomeOffsetWrite *write,UIScrollView *list) {
    if(write){write->after=list.contentOffset.y;WXGHomeInOffsetWrite=NO;}
}
// Observe optional callbacks only if the real delegate already implements them.
// In particular, leave the native drag destination and delegate identity intact.
static void WXGObserveHomeScrollDelegate(UITableView *table) {
    static __weak id last;
    id delegate=table.delegate;
    if(!delegate || delegate==last)return;
    last=delegate;
    static NSMutableSet *installed;
    if(!installed)installed=[NSMutableSet set];
    Class cls=object_getClass(delegate);
    if([installed containsObject:cls])return;
    [installed addObject:cls];
    Class parent=class_getSuperclass(cls);
    SEL release=@selector(scrollViewWillEndDragging:withVelocity:targetContentOffset:);
    Method method=class_getInstanceMethod(cls,release);
    if(method) {
        IMP own=WXGOwnImplementation(cls,release);
        WXGInstallOverride(cls,release,imp_implementationWithBlock(^(id receiver,UIScrollView *list,CGPoint velocity,CGPoint *target){
            ((void(*)(id,SEL,id,CGPoint,CGPoint *))WXGThrough(own,parent,release))(receiver,release,list,velocity,target);
            if(WXGHomeWritesEnabled && list==WXGHomeWatchedTable && target)
                [WXGChatSegments.shared traceHomeEvent:@"nativeDragTarget" before:list.contentOffset.y after:target->y];
        }),method_getTypeEncoding(method));
    }
    SEL end=@selector(scrollViewDidEndScrollingAnimation:);
    method=class_getInstanceMethod(cls,end);
    if(method) {
        IMP own=WXGOwnImplementation(cls,end);
        WXGInstallOverride(cls,end,imp_implementationWithBlock(^(id receiver,UIScrollView *list){
            CGFloat landed=list.contentOffset.y;
            ((void(*)(id,SEL,id))WXGThrough(own,parent,end))(receiver,end,list);
            if(WXGHomeWritesEnabled && list==WXGHomeWatchedTable)
                [WXGChatSegments.shared traceHomeEvent:@"nativeScrollAnimationEnded" before:landed after:list.contentOffset.y];
        }),method_getTypeEncoding(method));
    }
}
static void WXGObserveHomeOffsets(UITableView *table,BOOL enabled) {
    BOOL starting=enabled && !WXGHomeWritesEnabled;
    if(WXGHomeWatchedTable!=table || starting) {
        WXGHomeTableLayoutMS=WXGHomeHeaderWorkMS=0;WXGHomeWork=(WXGHomeFrameWork){0};
    }
    if(!enabled)WXGHomeWatchedNavigation=nil;
    WXGHomeWritesEnabled=enabled;WXGHomeWatchedTable=enabled?table:nil;
    if(!enabled || !table)return;
    if(starting){WXGHomeWriteCount=0;WXGHomeInsetWriteCount=0;WXGHomeLastStack=-1.;}
    Class home=NSClassFromString(@"MainFrameTableView");
    if(!home || ![table isKindOfClass:home])return;
    static dispatch_once_t once;dispatch_once(&once,^{
        SEL layout=@selector(layoutSubviews);
        Class parent=class_getSuperclass(home);IMP layoutOwn=WXGOwnImplementation(home,layout);
        WXGInstallOverride(home,layout,imp_implementationWithBlock(^(UITableView *list){
            CFTimeInterval start=(WXGHomeWritesEnabled && list==WXGHomeWatchedTable)?CACurrentMediaTime():0;
            ((void(*)(id,SEL))WXGThrough(layoutOwn,parent,layout))(list,layout);
            if(start>0){++WXGHomeWork.layouts;WXGHomeTableLayoutMS+=(CACurrentMediaTime()-start)*1000.;}
        }),method_getTypeEncoding(class_getInstanceMethod(home,layout)));
        // Count work on the observed list only. Cell creation can be part of a
        // table layout, so the durations are inclusive and should not be added.
        SEL reload=@selector(reloadData);
        IMP originalReload=WXGOwnImplementation(home,reload);
        WXGInstallOverride(home,reload,imp_implementationWithBlock(^(UITableView *list){
            CFTimeInterval start=(WXGHomeWritesEnabled && list==WXGHomeWatchedTable)?CACurrentMediaTime():0;
            ((void(*)(id,SEL))WXGThrough(originalReload,parent,reload))(list,reload);
            if(start>0){++WXGHomeWork.reloads;WXGHomeWork.reloadMS+=(CACurrentMediaTime()-start)*1000.;}
        }),method_getTypeEncoding(class_getInstanceMethod(home,reload)));
        Class source=NSClassFromString(@"NewMainFrameViewController");
        SEL cell=@selector(tableView:cellForRowAtIndexPath:);
        Method getCell=class_getInstanceMethod(source,cell);
        if(getCell) {
            IMP own=WXGOwnImplementation(source,cell);Class sup=class_getSuperclass(source);
            WXGInstallOverride(source,cell,imp_implementationWithBlock(^UITableViewCell *(id controller,UITableView *list,NSIndexPath *path){
                CFTimeInterval start=(WXGHomeWritesEnabled && list==WXGHomeWatchedTable)?CACurrentMediaTime():0;
                UITableViewCell *result=((id(*)(id,SEL,id,id))WXGThrough(own,sup,cell))(controller,cell,list,path);
                if(start>0){++WXGHomeWork.cells;WXGHomeWork.cellMS+=(CACurrentMediaTime()-start)*1000.;}
                return result;
            }),method_getTypeEncoding(getCell));
        }
        Class nav=NSClassFromString(@"MMUINavigationBar");
        Method navLayout=class_getInstanceMethod(nav,layout);
        if(navLayout) {
            IMP own=WXGOwnImplementation(nav,layout);Class sup=class_getSuperclass(nav);
            WXGInstallOverride(nav,layout,imp_implementationWithBlock(^(UINavigationBar *bar){
                CFTimeInterval start=(WXGHomeWritesEnabled && bar==WXGHomeWatchedNavigation)?CACurrentMediaTime():0;
                ((void(*)(id,SEL))WXGThrough(own,sup,layout))(bar,layout);
                if(start>0){++WXGHomeWork.navigations;WXGHomeWork.navigationMS+=(CACurrentMediaTime()-start)*1000.;}
            }),method_getTypeEncoding(navLayout));
        }
        SEL offset=@selector(setContentOffset:),animated=@selector(setContentOffset:animated:),bounds=@selector(setBounds:);
        Method m=class_getInstanceMethod(home,offset);IMP put=method_getImplementation(m);
        WXGInstallOverride(home,offset,imp_implementationWithBlock(^(UITableView *list,CGPoint p){
            WXGHomeOffsetWrite *w=WXGBeginHomeWrite(list,p.y,0);
            @try {((void(*)(id,SEL,CGPoint))put)(list,offset,p);} @finally {WXGEndHomeWrite(w,list);}
        }),method_getTypeEncoding(m));
        m=class_getInstanceMethod(home,animated);IMP slide=method_getImplementation(m);
        WXGInstallOverride(home,animated,imp_implementationWithBlock(^(UITableView *list,CGPoint p,BOOL animate){
            WXGHomeOffsetWrite *w=WXGBeginHomeWrite(list,p.y,animate?2:1);
            @try {((void(*)(id,SEL,CGPoint,BOOL))slide)(list,animated,p,animate);} @finally {WXGEndHomeWrite(w,list);}
        }),method_getTypeEncoding(m));
        m=class_getInstanceMethod(home,bounds);IMP resize=method_getImplementation(m);
        WXGInstallOverride(home,bounds,imp_implementationWithBlock(^(UITableView *list,CGRect r){
            WXGHomeOffsetWrite *w=WXGBeginHomeWrite(list,r.origin.y,3);
            @try {((void(*)(id,SEL,CGRect))resize)(list,bounds,r);} @finally {WXGEndHomeWrite(w,list);}
        }),method_getTypeEncoding(m));
    });
}
static NSArray *WXGHomeStackEvidence(void *const *frames,int depth) {
    NSMutableArray *stack=[NSMutableArray array];
    for(int j=1;j<depth;j++) {
        Dl_info image={0};
        if(dladdr(frames[j],&image) && image.dli_fname) {
            NSString *name=@(image.dli_fname).lastPathComponent;
            [stack addObject:@{@"image":name,@"offset":@((uintptr_t)frames[j]-(uintptr_t)image.dli_fbase),
                               @"symbol":image.dli_sname?@(image.dli_sname):@""}];
        }
    }
    return stack;
}
static NSArray *WXGHomeInsetEvidence(void) {
    NSMutableArray *events=[NSMutableArray array];
    for(NSUInteger i=WXGHomeInsetWriteCount-MIN(WXGHomeInsetWriteCount,16u);i<WXGHomeInsetWriteCount;i++) {
        WXGHomeInsetWrite e=WXGHomeInsetWrites[i%16];
        [events addObject:@{@"s":@(e.time),@"source":e.requested?@"setContentInset:":@"adjustedInsetObserved",
            @"raw":@(e.raw),@"automatic":@(e.automatic),@"rest":@(e.rest),@"rawReadBack":@(e.actualRaw),
            @"adjustedReadBack":@(e.actualAdjusted),@"storageReadBack":@(e.storedTop),@"policy":@(e.policy),@"stack":WXGHomeStackEvidence(e.stack,e.count)}];
    }
    return events;
}
static NSArray *WXGHomeOffsetEvidence(void) {
    NSMutableArray *events=[NSMutableArray array];
    NSArray *methods=@[@"setContentOffset:",@"setContentOffset:animated:NO",@"setContentOffset:animated:YES",@"setBounds:"];
    NSUInteger count=MIN((NSUInteger)WXGHomeWriteCapacity,WXGHomeWriteCount);
    for(NSUInteger i=WXGHomeWriteCount-count;i<WXGHomeWriteCount;i++) {
        WXGHomeOffsetWrite w=WXGHomeWrites[i%WXGHomeWriteCapacity];NSArray *stack=WXGHomeStackEvidence(w.stack,w.stackDepth);
        [events addObject:@{@"s":@(w.time),@"setter":methods[w.kind],@"before":@(w.before),@"target":@(w.target),
                            @"after":@(w.after),@"moving":@(w.moving),@"stack":stack}];
    }
    return events;
}

typedef struct {
    float t,dt,offset,inset,content,header,leading,chrome,search,group,listLens,titleLens,panel;
    float titleBottom,titleOpacity,searchOpacity,groupOpacity,rawInset,systemInset,restInset,conversationTop,layoutMS,headerWorkMS;
    WXGHomeFrameWork work;
    WXGHomePanelGeometry panelGeometry;
    float callbackInterval;
    unsigned flags;
} WXGHomeFrame;

@interface WXGChatSegments () <WXGHomePagerDelegate>
- (void)restoreChatPositionIfReady;
- (void)followTitleBarInOverlay:(UIView *)overlay page:(UIViewController *)leaf transitioning:(BOOL)transitioning transitionInvolvesHome:(BOOL)transitionInvolvesHome homePanel:(CGFloat)homePanel rowOffset:(CGFloat)rowOffset;
@end

@implementation WXGChatSegments {
    UIControl<WXGListGroupControl> *_bar;
    WXGHomeCategoryBar *_categories;
    WXGHomeGroupPager *_pager;
    UIView *_openedFold;
    __weak UIControl *_deviceButton;
    __weak id _deviceTarget;
    __weak NSArray *_badgeSnapshot;
    NSUInteger _badgeCursor;
    NSInteger _unreadTotals[5];
    CFTimeInterval _nextDeviceCheck,_nextBadgeSeed;
    BOOL _triedInitialCategory;
    __weak id _categoryManager;
    WXGSegmentBar *_titleBar;    // R23: overlay All/Unread group bar tracking native MFTitleView presentation 1:1
    __weak UIView *_titleNavView,*_titlePullView;
    __weak UIView *_titleOverlay;
    WXGStateBag *_titleConceal;  // dedicated conceal bag: never wiped on push to chat -> zero flash on return
    CGRect _titleAvailableRect,_titleRestRect,_titleLastRect;
    BOOL _titleEnglishHint;
    NSMutableArray<NSString *> *_titleTrace;
    NSInteger _titleSelected;
    CFTimeInterval _nextPullTitleLookup;
    CGFloat _traceTitleY,_traceTitleAlpha,_titleRestDelta;
    BOOL _titleHasRestDelta;
    CGRect _titleSampledBounds;
    BOOL _traceTitleHome,_traceTitleTransition;
    __weak UIView *_searchBar,*_container;__weak UITableView *_table;__weak UIViewController *_page;
    NSString *_status,*_fieldSource,*_colorSource;
    NSUInteger _mounts,_moves,_switches,_restores,_nativeSearches;
    NSInteger _selected;
    BOOL _nativeSearching,_observing;
    CGRect _fieldRect;
    NSDictionary *_probe;CFTimeInterval _probeAt;
    __weak UIView *_floatHost;   // FIX114 B: where hostTick last floated the bar (the before-commit pass places it there too)
    NSUInteger _commitPlacements;   // FIX114 B: diagnostics
    NSUInteger _transformMoves,_frameWrites,_skippedLaidOuts;   // R20: pull-down/scroll stutter diagnostics
    double _maxPlaceMS,_maxScrollFrameMS;
    CFTimeInterval _lastScrollFrame;NSUInteger _slowScrollFrames;
    CGPoint _floatBaseOrigin;
    CGSize _floatBaseSize;
    CGFloat _lastFloatY;
    BOOL _hasLastFloatY,_adjustingHeader;
    WXGHomeGroupHeader *_groupHeader;
    CGFloat _nativeHeaderHeight,_lastHeaderWidth;
    CGRect _measuredInNative;
    __weak UIView *_drawnField,*_unrelatedHeader;
    NSUInteger _layoutRevision,_fieldScans,_headerWrites,_startupReveals;
    UIUserInterfaceStyle _measuredStyle;
    __weak UIViewController *_startupPage,*_bookmarkedHome;
    __weak UITableView *_leadingTable;
    CGSize _leadingSize;CGFloat _leadingInset,_leadingSafe,_leadingViewport,_leadingNavH,_layoutLeading;
    NSUInteger _leadingRevision;
    BOOL _leadingHasRow,_returnReady,_returnAppearing,_earlyPositionApplied,_remountAfterScroll;
    CGFloat _savedDepth,_savedHeaderHeight;
    CFTimeInterval _returnWaitUntil;
    NSUInteger _returnRestores;
    CGRect _searchRow;
    NSMutableData *_motionBuffer;
    NSMutableArray<NSDictionary *> *_motionEvents;
    NSUInteger _motionWrite,_motionCount,_motionRevision;
    CFTimeInterval _motionLastTime,_motionLastCallback,_nextPresentationTrace;
    WXGHomeFrame _lastMotion;
    __weak UITableView *_startupTable;
    CFTimeInterval _startupUntil;
    BOOL _startupPending;
    BOOL _layoutLocalSearch,_layoutFloat;CFTimeInterval _measureFallbackAfter;
    CGFloat _startupBefore,_startupAfter,_placedInset,_lastPanel;
    CGRect _placedViewport,_placedHeader;
    CGSize _lastMeasuredBarSize;
    CGRect _naturalFrame;        // FIX113 O: the segment bar's frame in its container (in the list)
    BOOL _segmentCovered;
    BOOL _segmentFloating;       // FIX113 O: it is in the navigation overlay now
    NSMapTable<UIViewController *,WXGFloatSlot *> *_floats;
    NSUInteger _floatMoves;
    NSUInteger _directSearches;   // FIX114 M: capsule taps that opened WeChat's search page at once
    NSMutableArray<NSString *> *_switchLog;
    CGFloat _nativeBottomGap,_groupGap;
    // FIX114 E: the bar's place on screen for about a second after the list's
    // page comes back (from a chat): a jump shows there.
    NSMutableArray<NSString *> *_returnTrace;
    __weak UIViewController *_lastTickPage;
    CFTimeInterval _returnedAt,_fieldRecheck;
    NSUInteger _fieldRechecks;
    CFTimeInterval _capsuleTraceAt;
    NSInteger _rowOffset;        // FIX113 Q: the data source's rows besides the sessions (counted with 全部)
    BOOL _filterBroken;
    NSString *_filterStatus,*_filterBrokenWhy;
    NSString *_selectedGroupID;   // FIX113 R: the group chosen (its id)
    NSUInteger _filterApplies,_filterFails;double _filterMS;
}
+ (instancetype)shared {
    static WXGChatSegments *manager;static dispatch_once_t once;
    dispatch_once(&once,^{manager=[self new];});
    return manager;
}
- (BOOL)wanted {
    return WXGPluginEnabled() && WXGEffectiveRenderMode()>=2 && [WXGConfig.shared extraNumber:@"chatSegments"]>.5;
}
- (BOOL)titleModeWanted {
    return WXGPluginEnabled() && WXGEffectiveRenderMode()>=2 && WXGConfig.shared.homeTitleSegments;
}
- (void)observe {
    if(_observing)return;_observing=YES;
    __weak WXGChatSegments *weakSelf=self;
    CFRunLoopObserverRef commit=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999000,
        ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){[weakSelf beforeCommit];});
    if(commit){CFRunLoopAddObserver(CFRunLoopGetMain(),commit,kCFRunLoopCommonModes);CFRelease(commit);}
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldBegan:) name:UITextFieldTextDidBeginEditingNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldEnded:) name:UITextFieldTextDidEndEditingNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:) name:WXGSettingsChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(groupsChanged:) name:WXGChatGroupsChanged object:nil];   // FIX113 R
}
- (BOOL)slotStillInHomeHeader:(WXGFloatSlot *)slot {
    UIView *header=slot.ownedHeader;
    return header && header==slot.table.tableHeaderView && [slot.bar isDescendantOfView:header] &&
        [header isDescendantOfView:slot.page.viewIfLoaded];
}
- (void)beforeCommit {
    if(WXGBackdropCaptureInProgress())return;
    @try {
        if(_groupHeader && !_adjustingHeader && (_lastTickPage==_page || _returnReady) && _table.window && !WXGHomeListInNativePull(_table)) {
            UIView *published=_table.tableHeaderView;
            if(published==_groupHeader)_unrelatedHeader=nil;
            else if((!published || published!=_unrelatedHeader) && ![self reuseRowsForTable:_table nativeHeader:published])
                _unrelatedHeader=published;
        }
        if(_groupHeader && _table.window && _groupHeader.owner==_table &&
           ((_groupHeader.restInset==0 && !_table.tracking && !_table.decelerating && _lastTickPage==_page && CACurrentMediaTime()>=_groupHeader.nextCalibration) ||
            (_groupHeader.awaitingHomeAppearance && !_table.tracking && !_table.decelerating && !WXGHomeListInNativePull(_table) &&
             (_returnReady || _lastTickPage==_page) && WXGHomeSearchExposed(_page)) ||
            !UIEdgeInsetsEqualToEdgeInsets(_groupHeader.checkedAdjusted,_table.adjustedContentInset) ||
            !UIEdgeInsetsEqualToEdgeInsets(_groupHeader.checkedRaw,_table.contentInset) ||
            !CGSizeEqualToSize(_groupHeader.restViewport,_table.bounds.size) || !UIEdgeInsetsEqualToEdgeInsets(_groupHeader.restSafe,_table.window.safeAreaInsets)))
            [self homeTableInsetChanged:_table];
        if(_returnAppearing && _returnReady)[self restoreChatPositionIfReady];
        if(_titleBar.superview && _lastTickPage==_page && _table.window &&
           !CGRectEqualToRect(_titleSampledBounds,_table.bounds) && WXGHomeSearchExposed(_page))
            [self followTitleBarInOverlay:_titleOverlay page:_page transitioning:NO transitionInvolvesHome:YES homePanel:_lastPanel rowOffset:0];
        if(_bar && _bar.superview) {
            UIView *host=_floatHost;
            if(_segmentFloating && host.window && _table.superview==host &&
               (!CGRectEqualToRect(_placedViewport,_table.bounds) || !CGRectEqualToRect(_placedHeader,_container.frame) ||
                _placedInset!=_table.adjustedContentInset.top) && WXGHomeSearchExposed(_page)) {
                BOOL replace=_groupHeader.nativeCanvas.hidden;
                if(!replace)[self floatNativeOn:_page time:0 homePanel:_lastPanel];
                [self placeSegmentIn:host];++_commitPlacements;
            }
        }
        for(WXGFloatSlot *slot in _floats.objectEnumerator) {
            if(slot.parked && ![self slotStillInHomeHeader:slot]){[self unpin:slot];continue;}
            if(!(slot.pinned && slot.clone.window) && !(slot.parked && slot.ownedHeader.window))continue;
            WXGGlassView *glass=slot.clone.surface.glass;
            NSArray *roots=glass.backdropExclusions;
            NSMutableArray *remaining=nil;
            for(UIView *root in roots) {
                if(![root isDescendantOfView:slot.ownedHeader]) {
                    [slot.states restoreView:root];
                    if(!remaining)remaining=[roots mutableCopy];
                    [remaining removeObjectIdenticalTo:root];
                }else if(![root.layer.mask.name isEqualToString:@"wxg.conceal"])[slot.states conceal:root];
            }
            if(remaining)glass.backdropExclusions=remaining;
        }
    } @catch(__unused NSException *error) {}
}
- (void)discardListForm {
    [_pager invalidate];
    [self restoreCategoryFold];
    if(atomic_load(&WXGFilterIndex)>0 && !(atomic_load(&WXGFilterIndex)==1 && [self titleModeWanted]))
        [self applyRule:0 members:nil name:nil];
    [_bar removeFromSuperview];_bar.active=NO;_bar=nil;_categories=nil;_pager=nil;
    _deviceButton=nil;_deviceTarget=nil;_badgeSnapshot=nil;_badgeCursor=0;_categoryManager=nil;
    _triedInitialCategory=NO;_nextDeviceCheck=0;_nextBadgeSeed=0;
    _selected=-1;_selectedGroupID=nil;_titleBar.acceptsReselection=NO;
    _segmentFloating=NO;_hasLastFloatY=NO;_floatBaseSize=CGSizeZero;_lastMeasuredBarSize=CGSizeZero;
}
- (void)settingsChanged:(__unused NSNotification *)note {
    if(WXGHomeWritesEnabled && [WXGConfig.shared extraNumber:@"homeMotionTrace"]<=.5)WXGObserveHomeOffsets(nil,NO);
    BOOL categories=[WXGConfig.shared extraNumber:@"homeGroupForm"]>.5;
    if(_bar && ((_categories!=nil)!=categories))[self discardListForm];
    if(_pager && _pager.paging!=([WXGConfig.shared extraNumber:@"homeGroupPaging"]>.5)) {
        [_pager cancel];_pager.paging=!_pager.paging;
    }
    if(![self floatWanted])[self restoreFloats];
    if(![self wanted])[self restore];
    else {
        UIViewController *page=_page;if(page)[self updateOnPage:page];
        [_bar refreshLook];
    }
    if(![self titleModeWanted]) {
        [self releaseTitleBar];
        if(![self wanted] && atomic_load(&WXGFilterIndex)>0)[self applyRule:0 members:nil name:nil];
    }else {
        if(_titleBar) {
            BOOL en=WXGConfig.shared.homeTitleSegmentsEnglish || _titleEnglishHint;
            NSArray<NSString *> *titles=en?@[@"All",@"Unread"]:@[@"全部",@"未读"];
            if(![_titleBar.titles isEqualToArray:titles])_titleBar.titles=titles;
            [self fitTitleBarInRect:_titleAvailableRect];
            if(_titleOverlay)[self applyColorsToBar:_titleBar from:_titleOverlay];
            [_titleBar refreshLook];
        }
    }
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)[slot.clone.surface applyConfig];
}
// WeChat's own search took its field (its search button, the dock's search
// handing a text over): its bar is given back while it is used.
- (void)fieldBegan:(NSNotification *)note {
    UIView *field=note.object,*bar=_searchBar;
    UIView *pending=_groupHeader.pendingNativeHeader;
    if(pending && [field isKindOfClass:UITextField.class] && [field isDescendantOfView:pending] &&
       _table.tableHeaderView==_groupHeader) {
        [self reuseRowsForTable:_table nativeHeader:pending];bar=_searchBar;
    }
    // FIX114 F (review): WeChat's own search in a bar a floating capsule
    // covers (it can start while that page is covered or sliding back): its bar back now.
    if([field isKindOfClass:UITextField.class])for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)
        for(UIView *root in slot.clone.surface.glass.backdropExclusions)
            if([field isDescendantOfView:root]){slot.editingField=(UITextField *)field;[self unpin:slot];break;}
    if(!bar || ![field isKindOfClass:UIView.class] || ![field isDescendantOfView:bar])return;
    [_pager cancel];_nativeSearching=YES;_startupPending=NO;_startupUntil=0;++_nativeSearches;
    _lastMeasuredBarSize=CGSizeZero;
    if(_groupHeader){[_groupHeader replaceSearch:NO];[_groupHeader placeNativeAtLeading:0 field:CGRectZero target:CGRectZero];[self applyHeaderHeight:_nativeHeaderHeight onHeader:_groupHeader table:_table];}
    _bar.hidden=YES;_bar.active=NO;_status=@"微信自己的搜索正在用搜索栏，暂时还给它";
}
- (void)fieldEnded:(NSNotification *)note {
    if(!_nativeSearching || ![(UIView *)note.object isDescendantOfView:_searchBar])return;
    // UIKit finishes cancelling its search after resignFirstResponder returns.
    dispatch_async(dispatch_get_main_queue(),^{if(self->_nativeSearching && self->_page)[self updateOnPage:self->_page];});
}
// The chat list's table: WeChat's MainFrameTableView, else a table whose
// header holds a search bar.
- (UITableView *)tableIn:(UIView *)root {
    static Class listClass;static dispatch_once_t once;dispatch_once(&once,^{listClass=NSClassFromString(@"MainFrameTableView");});
    UITableView *fallback=nil;
    for(UIView *v in WXGViews(root,600)) {
        if(![v isKindOfClass:UITableView.class] || WXGIsPluginView(v))continue;
        if(listClass && [v isKindOfClass:listClass])return (UITableView *)v;
        if(!fallback && [self searchBarIn:((UITableView *)v).tableHeaderView])fallback=(UITableView *)v;
    }
    return fallback;
}
- (UIView *)searchBarIn:(UIView *)header {
    header=WXGHomeNativeSearchHeader(header);
    if(!header || WXGHomeTaskbarContains(header))return nil;
    static Class wcBar;static dispatch_once_t once;dispatch_once(&once,^{wcBar=NSClassFromString(@"WCSearchBar");});
    if([header isKindOfClass:UISearchBar.class] || (wcBar && [header isKindOfClass:wcBar]))return header;
    UIView *system=nil,*display=nil;
    for(UIView *v in WXGViews(header,160)) {
        BOOL ui=[v isKindOfClass:UISearchBar.class],wc=[v isKindOfClass:wcBar];
        if((!ui && !wc) || WXGIsPluginView(v) || WXGHomeTaskbarContains(v))continue;
        if(!system && ui)system=v;
        if(!display && wc && !v.hidden)display=v;
    }
    if(display && system && ![display isDescendantOfView:system])return display;
    return system?:display;
}
// The search field's rectangle in the bar: its rounded field (WeChat's white
// capsule, the text field), never the bar's margins.
// FIX114 E: the box a UISearchBar's field draws (its background view, in the
// field), when it is about the field's size; null otherwise.
CGRect WXGSearchFieldBox(UITextField *field) {
    if(!field)return CGRectNull;
    CGSize size=field.bounds.size;
    for(UIView *v in field.subviews) {
        if(WXGIsPluginView(v) || [v isKindOfClass:UILabel.class] || [v isKindOfClass:UIControl.class])continue;
        if([NSStringFromClass(v.class) rangeOfString:@"Background"].location==NSNotFound)continue;
        CGRect r=v.frame;
        if(r.size.width>=size.width*.8 && r.size.width<=size.width+8 && r.size.height>=size.height*.6 && r.size.height<=size.height+8 && r.size.height>=24)return r;
    }
    return CGRectNull;
}
// FIX114 F (probe 10-23, the home page without the plugin: user: the bar and
// the capsule were never the height of WeChat's search box): the home and
// 通讯录 search bars are a UISearchBar (the list's header, 414×55) whose own
// text field (398×32.7, 11 pt down) is hidden under WeChat's WCSearchBar; what
// is seen is that bar's box: a filled rounded UIView (r 6, 398×36, 4 pt down)
// in its stack views. That box, in `bar`; null when there is none.
static UIView *WXGSearchDisplayIn(UIView *bar) {
    static Class custom;static dispatch_once_t once;dispatch_once(&once,^{custom=NSClassFromString(@"WCSearchBar");});
    if(!custom || !bar)return nil;
    if([bar isKindOfClass:custom])return bar;
    for(UIView *v in WXGViews(bar,80))if([v isKindOfClass:custom] && !v.hidden)return v;
    return nil;
}
static CGRect WXGFindVisibleSearchBox(UIView *bar,UIView **paint) {
    UIView *wc=WXGSearchDisplayIn(bar);
    if(!wc)return CGRectNull;
    CGFloat barW=bar.bounds.size.width,bestW=0;CGRect best=CGRectNull;
    for(UIView *v in WXGViews(wc,120)) {
        // Not by its paint or alpha: the local glass clears the box's fill, the
        // plugin fades the bar; by what it is and where it sits.
        if(v==wc || v.hidden || WXGIsPluginView(v) || v.class!=UIView.class || v.layer.cornerRadius<2 || ![v.superview isKindOfClass:UIStackView.class])continue;
        CGRect r=[v convertRect:v.bounds toView:bar];
        if(r.size.height<24 || r.size.height>60 || r.size.width<barW*.4 || r.size.width>barW+.5)continue;
        if(r.size.width>bestW+.5){best=r;bestW=r.size.width;if(paint)*paint=v;}
    }
    return best;
}
static CGRect WXGVisibleSearchBox(UIView *bar) {return WXGFindVisibleSearchBox(bar,NULL);}
- (CGRect)fieldRectIn:(UIView *)bar source:(NSString **)source paint:(UIView **)outPaint {
    CGFloat barW=bar.bounds.size.width;CGRect best=CGRectNull;CGFloat bestW=0;NSString *from=nil;
    UIView *paint=nil;
    CGRect seen=WXGFindVisibleSearchBox(bar,&paint);
    ++_fieldScans;if(outPaint)*outPaint=paint;   // FIX114 F: what is on screen first
    if(!CGRectIsNull(seen)){if(source)*source=WXGDrawnBoxSource;return seen;}
    if([bar isKindOfClass:UISearchBar.class]) {
        UITextField *field=WXGInstalledSearchField(bar);
        if(field && !field.hidden && field.alpha>.01 && field.bounds.size.height>=24 && field.bounds.size.height<=60) {
            best=[field convertRect:field.bounds toView:bar];bestW=best.size.width;from=@"searchTextField";
            // FIX114 E (user: the bar is not the size of WeChat's own field): the
            // box WeChat draws (the field's background view) when it has its own
            // size (a background picture can be taller than the text field).
            CGRect box=WXGSearchFieldBox(field);
            if(!CGRectIsNull(box)){best=[field convertRect:box toView:bar];bestW=best.size.width;from=@"searchTextField background";}
            if(source)*source=from;
            return best;   // (review) WeChat's own field: nothing wider in the bar takes its place
        }
    }
    for(UIView *v in WXGViews(bar,160)) {
        if(v==bar || v.hidden || v.alpha<.01)continue;
        if(WXGIsPluginView(v))continue;
        CGRect r=[v convertRect:v.bounds toView:bar];
        if(r.size.height<24 || r.size.height>60 || r.size.width<barW*.4 || r.size.width>barW-4)continue;
        BOOL rounded=v.layer.cornerRadius>4 || [v isKindOfClass:UITextField.class];
        if(!rounded)continue;
        if(r.size.width>bestW+.5){best=r;bestW=r.size.width;from=[NSString stringWithFormat:@"%@ r%.0f",NSStringFromClass(v.class),v.layer.cornerRadius];}
    }
    if(CGRectIsNull(best) && bar.bounds.size.height>=30) {
        CGFloat h=MIN(36,bar.bounds.size.height-12);
        best=CGRectMake(8,(bar.bounds.size.height-h)*.5,barW-16,h);from=@"bar (no field found)";
    }
    if(source)*source=from;
    return best;
}
static CGRect WXGHomeConfiguredRow(CGRect field,CGFloat width,BOOL group) {
    WXGConfig *cfg=WXGConfig.shared;
    WXGRect base={field.origin.x,field.origin.y,field.size.width,field.size.height};
    return WXGCGRect(WXGHomeRowRect(base,width,
        group?[cfg extraNumber:@"homeGroupWidthPct"]:cfg.homeSearchWidthPct,
        group?[cfg extraNumber:@"homeGroupHeight"]:cfg.homeSearchHeight,group?-1:cfg.homeSearchTopGap));
}
// The table can start underneath a transparent navigation bar or already below it.
// Compute this at the table's resting offset, independently of its current scroll.
- (CGFloat)homeChromeBottomInWindow:(UIWindow *)window {
    CGFloat bottom=CGRectGetMinY(window.bounds)+window.safeAreaInsets.top;
    UINavigationController *nav=_page.navigationController;
    UINavigationBar *bar=nav.navigationBar;
    if(!nav.navigationBarHidden && !bar.hidden && bar.window==window && !CGRectIsEmpty(bar.bounds))
        bottom=MAX(bottom,CGRectGetMaxY([bar convertRect:bar.bounds toView:window]));
    CGFloat row=[WXGIntegrationHost.shared homeRowBottomForPage:_page window:window];
    return isfinite(row)?MAX(bottom,row):bottom;
}
- (CGFloat)leadingForHeader:(UIView *)header table:(UITableView *)table {
    UIWindow *window=table.window;
    if(!window)return 0;
    if(_leadingTable==table && WXGHomeListInNativePull(table))return _layoutLeading;
    CGFloat inset=WXGHomeConversationTop(table);
    CGFloat safe=window.safeAreaInsets.top,navH=_page.navigationController.navigationBar.bounds.size.height;
    CGFloat viewport=CGRectGetMinY([table convertRect:table.bounds toView:window]);
    CGFloat pixel=1./MAX(1.,window.screen.scale)+1e-5;
    BOOL hasRow=isfinite([WXGIntegrationHost.shared homeRowBottomForPage:_page window:window]);
    BOOL same=_leadingTable==table && CGSizeEqualToSize(_leadingSize,table.bounds.size) &&
        fabs(_leadingSafe-safe)<pixel && _leadingRevision==WXGConfigRevision();
    if(same && (_bookmarkedHome || _page.transitionCoordinator || table.tracking || table.dragging || table.decelerating || table.contentOffset.y < -inset ||
       (fabs(_leadingInset-inset)<=pixel && fabs(_leadingViewport-viewport)<=pixel &&
        fabs(_leadingNavH-navH)<=pixel && (!hasRow || _leadingHasRow))))return _layoutLeading;
    _leadingTable=table;_leadingSize=table.bounds.size;_leadingInset=inset;_leadingSafe=safe;_leadingViewport=viewport;
    _leadingNavH=navH;_leadingHasRow=hasRow;_leadingRevision=WXGConfigRevision();
    _layoutLeading=WXGHomePixel(WXGHomeHeaderLeading(viewport,inset,header.frame.origin.y,[self homeChromeBottomInWindow:window]),window.screen.scale);
    return _layoutLeading;
}
// Catch a duplicate that already exists when UIKit changes its safe area or
// when the group first mounts. Read the storage getter as well as the public
// one; never guess at a negative raw inset to compensate for a virtual getter.
- (void)homeTableInsetChanged:(UITableView *)table {
    WXGHomeGroupHeader *rows=_groupHeader;
    if(!rows || table!=WXGGroupedTable || rows.owner!=table || rows.correctingRest || !table.window)return;
    UIWindow *window=table.window;CGFloat scale=window.screen.scale;
    UIEdgeInsets raw=table.contentInset,adjusted=table.adjustedContentInset;
    BOOL newGeometry=!WXGHomeSameViewport(rows,table);
    if(rows.restInset>0 && fabs(adjusted.top-rows.checkedAdjusted.top)>20)
        WXGNoteInsetSource(table,NO,raw.top,rows.restInset);
    rows.awaitingHomeAppearance=NO;
    rows.checkedRaw=raw;rows.checkedAdjusted=adjusted;
    if(newGeometry) {
        rows.restInset=0;rows.restViewport=table.bounds.size;rows.restSafe=window.safeAreaInsets;
    }
    if(_nativeSearching || _page.navigationItem.searchController.isActive ||
       table.refreshControl.refreshing || table.editing)return;
    if(rows.restInset==0 || WXGHomeSameInset(raw.top,0,scale) || WXGHomeSameInset(raw.top,adjusted.top-raw.top,scale)) {
        rows.nextCalibration=CACurrentMediaTime()+.25;
        UINavigationBar *nav=_page.navigationController.navigationBar;
        if(nav.window==window && !nav.hidden && !_page.navigationController.navigationBarHidden) {
            CGFloat bottom=CGRectGetMaxY([nav convertRect:nav.bounds toView:window]);
            CGFloat viewport=[table convertPoint:table.bounds.origin toView:window].y;
            CGFloat rest=WXGHomeRestInset(bottom-viewport,raw.top,adjusted.top,scale);
            if(rest>0)rows.restInset=rest;
        }
    }
    if(!WXGHomeHasTwoNavigationInsets(rows.restInset,raw.top,adjusted.top,scale) ||
       WXGHasNativeInsetRequest || (rows.hasNativeInsetRequest && rows.lastNativeTop!=0.) || !WXGUIKitInsetGetter || !WXGUIKitInsetSetter)return;
    if(table.tracking || table.dragging || table.decelerating || WXGHomeListInNativePull(table)){rows.awaitingHomeAppearance=YES;return;}
    if(!(WXGHomeSearchExposed(_page) || [self showingBookmarkedHome])){rows.awaitingHomeAppearance=YES;return;}
    UIEdgeInsets stored=((UIEdgeInsets(*)(id,SEL))WXGUIKitInsetGetter)(table,@selector(contentInset));
    if(!WXGHomeSameInset(stored.top,rows.restInset,scale))return;
    stored.top=0.;
    CGFloat before=table.contentOffset.y;
    rows.correctingRest=YES;++rows.insetAttempts;
    @try {
        ((void(*)(id,SEL,UIEdgeInsets))WXGUIKitInsetSetter)(table,@selector(setContentInset:),stored);
    } @finally {rows.correctingRest=NO;rows.checkedRaw=table.contentInset;rows.checkedAdjusted=table.adjustedContentInset;}
    BOOL verified=WXGHomeSameInset(rows.checkedRaw.top,0,scale) && WXGHomeSameInset(rows.checkedAdjusted.top,rows.restInset,scale);
    if(verified)++rows.insetRepairs;
    [self traceHomeEvent:verified?@"singleInsetReadBack":@"nativeInsetReadBack" before:before after:table.contentOffset.y];
}
- (void)revealInitialRows:(UITableView *)table {
    if(_bookmarkedHome || (!_startupPending && !_startupUntil) || table!=_startupTable || table.tableHeaderView!=_groupHeader || _nativeSearching)return;
    if(WXGHomeListInNativePull(table)){_startupPending=NO;_startupUntil=0;return;}
    if(!table.window || _bar.window!=table.window)return;
    BOOL touched=table.tracking || table.dragging || table.decelerating;
    if(_startupPending) {
        // Start settling only after both measured rows have reached the window.
        _startupPending=NO;
        _startupUntil=CACurrentMediaTime()+1.2;
    }
    CGFloat rest=-WXGHomeListTop(table);
    CGFloat offset=table.contentOffset.y;
    if(touched || _page.navigationItem.searchController.isActive || CACurrentMediaTime()>_startupUntil ||
       (offset-rest>_groupHeader.bounds.size.height+1 && fabs(offset)>.5) || offset<rest-.5){_startupUntil=0;return;}
    if(WXGHomeShouldReveal(offset,rest,_groupHeader.bounds.size.height,touched)) {
        _startupBefore=offset;_startupAfter=rest;++_startupReveals;
        [self traceHomeEvent:@"coldReveal" before:offset after:rest];
        [UIView performWithoutAnimation:^{[table setContentOffset:CGPointMake(table.contentOffset.x,rest) animated:NO];}];
    }
}
- (void)willPushFrom:(UIViewController *)home to:(UIViewController *)next {
    static Class chat;static dispatch_once_t once;dispatch_once(&once,^{chat=NSClassFromString(@"BaseMsgContentViewController");});
    if(!home || home!=_page || !chat || ![next isKindOfClass:chat] || (!_bar && !_titleBar) || !_table.window || _nativeSearching || WXGHomeListInNativePull(_table))return;
    [_pager cancel];_bookmarkedHome=home;_returnReady=NO;_returnAppearing=NO;_startupPending=NO;_startupUntil=0;
    _savedDepth=MAX(0.,_table.contentOffset.y+WXGHomeListTop(_table));
    _savedHeaderHeight=_table.tableHeaderView.frame.size.height;
    [self traceHomeEvent:@"leaveForChat" before:_table.contentOffset.y after:_table.contentOffset.y];
}
- (BOOL)showingBookmarkedHome {
    if(!_returnAppearing || !_returnReady || !_bookmarkedHome || _page!=_bookmarkedHome || !_page.viewIfLoaded.window ||
       _page.presentedViewController || ![_table isDescendantOfView:_page.viewIfLoaded])return NO;
    id<UIViewControllerTransitionCoordinator> coordinator=_page.transitionCoordinator;
    return _page.navigationController.topViewController==_page || [coordinator viewControllerForKey:UITransitionContextToViewControllerKey]==_page;
}
- (void)willShowHome:(UIViewController *)page {
    if(!page || page!=_bookmarkedHome)return;
    _returnAppearing=YES;_returnReady=YES;_earlyPositionApplied=NO;_returnWaitUntil=CACurrentMediaTime()+.4;
    id<UIViewControllerTransitionCoordinator> coordinator=page.transitionCoordinator;
    if(coordinator)[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){
        if(context.isCancelled && self->_bookmarkedHome==page){self->_returnAppearing=NO;self->_returnReady=NO;[self coverHomeSearchFor:page];}
    }];
    [self restoreChatPositionIfReady];
}
- (void)didShowHome:(UIViewController *)page {
    if(!page || page!=_bookmarkedHome)return;
    // WeChat completes its own viewDidAppear: after the superclass callback.
    dispatch_async(dispatch_get_main_queue(),^{
        if(self->_bookmarkedHome!=page)return;
        self->_returnAppearing=NO;self->_returnReady=YES;self->_returnWaitUntil=CACurrentMediaTime()+.4;
        if([self wanted])[self updateOnPage:page];
        else if(![self->_table isDescendantOfView:page.viewIfLoaded])self->_table=[self tableIn:page.viewIfLoaded];
        [self restoreChatPositionIfReady];
    });
}
- (void)restoreChatPositionIfReady {
    UITableView *table=_table;
    if(!_returnReady || !_bookmarkedHome || _page!=_bookmarkedHome || !table.window ||
       ![table isDescendantOfView:_page.viewIfLoaded] || ([self wanted] && (!_groupHeader || table.tableHeaderView!=_groupHeader)) ||
       !(_returnAppearing?[self showingBookmarkedHome]:WXGHomeSearchExposed(_page)))return;
    if(table.contentSize.height<=0 && CACurrentMediaTime()<_returnWaitUntil)return;
    if(table.tracking || table.dragging || table.decelerating || _nativeSearching || WXGHomeListInNativePull(table)){_returnReady=NO;_returnAppearing=NO;_bookmarkedHome=nil;return;}
    if(_groupHeader && WXGHomeHasTwoNavigationInsets(_groupHeader.restInset,table.contentInset.top,table.adjustedContentInset.top,table.window.screen.scale))
        [self homeTableInsetChanged:table];
    CGFloat before=table.contentOffset.y;
    CGFloat top=WXGHomeListTop(table),height=table.tableHeaderView.frame.size.height;
    if(_returnAppearing && _earlyPositionApplied && fabs(before+top)>.5)return;
    CGFloat depth=WXGHomeDepthAfterResize(_savedDepth,_savedHeaderHeight,height);
    CGFloat target=WXGHomeOffsetAtDepth(_savedDepth,_savedHeaderHeight,height,top,table.adjustedContentInset.bottom,
        table.contentSize.height,table.bounds.size.height);
    // WeChat can publish just the header before it restores its rows on a pop.
    // Give it a chance to supply them before clamping the bookmark to a shorter list.
    if(target+.5<depth-top && CACurrentMediaTime()<_returnWaitUntil)return;
    if(!_returnAppearing){_returnReady=NO;_bookmarkedHome=nil;}
    BOOL corrected=fabs(target-before)>.5/MAX(1.,table.window.screen.scale);
    if(corrected) {
        ++_returnRestores;_earlyPositionApplied=YES;
        [UIView performWithoutAnimation:^{[table setContentOffset:CGPointMake(table.contentOffset.x,target) animated:NO];}];
    }
    if(!_returnAppearing || corrected)[self traceHomeEvent:(_returnAppearing?@"returnBeforeDisplay":@"returnFromChat") before:before after:table.contentOffset.y];
}
- (void)applyHeaderHeight:(CGFloat)needed onHeader:(UIView *)header table:(UITableView *)table {
    if(!header || !table || needed<20)return;
    if(WXGHomeListInNativePull(table)){_remountAfterScroll=YES;return;}
    if(header==_groupHeader)_groupHeader.reservedHeight=needed;
    if(fabs(header.frame.size.height-needed)<=.5)return;
    CGFloat before=table.contentOffset.y,oldHeight=header.frame.size.height;
    CGFloat depth=before+WXGHomeListTop(table);
    _adjustingHeader=YES;++_headerWrites;
    @try {
        [UIView performWithoutAnimation:^{
            CGRect f=header.frame;f.size.height=needed;header.frame=f;
            if(table.tableHeaderView==header) {
                if(header==self->_groupHeader)WXGPublishHomeRows(table,self->_groupHeader);
                else table.tableHeaderView=header;
                if(!self->_bookmarkedHome && !table.tracking && !table.dragging && !table.decelerating &&
                   depth>=oldHeight && !WXGHomeListInNativePull(table)) {
                    CGFloat want=WXGHomeOffsetAtDepth(depth,oldHeight,needed,WXGHomeListTop(table),
                        table.adjustedContentInset.bottom,table.contentSize.height,table.bounds.size.height);
                    if(fabs(want-table.contentOffset.y)>.5)[table setContentOffset:CGPointMake(table.contentOffset.x,want) animated:NO];
                }
            }
        }];
        [self traceHomeEvent:@"headerHeight" before:before after:table.contentOffset.y];
    } @finally {_adjustingHeader=NO;}
}
- (void)restoreResizedHeader {
    WXGHomeGroupHeader *wrapper=_groupHeader;
    if(!wrapper)return;
    UIView *native=wrapper.nativeHeader,*requested=wrapper.pendingNativeHeader;wrapper.reservedHeight=0;
    if(WXGGroupedTable==wrapper.owner){WXGGroupedTable=nil;WXGGroupedRows=nil;}
    for(WXGFloatSlot *slot in _floats.objectEnumerator)if(slot.ownedHeader==wrapper)[self unpin:slot];
    [UIView performWithoutAnimation:^{[wrapper replaceSearch:NO];[wrapper restoreNativeInk];}];
    BOOL ownsNative=native.superview==wrapper.nativeCanvas;
    _adjustingHeader=YES;
    @try {
        [wrapper finishPendingSearchKeeping:nil];
        if(ownsNative) {
            [native removeFromSuperview];
            native.autoresizingMask=wrapper.nativeResize;
        }
        if(wrapper.owner.tableHeaderView==wrapper)
            wrapper.owner.tableHeaderView=requested?:(wrapper.holdingForSpacer?wrapper.nativeSpacer:(ownsNative?native:nil));
    } @finally {_adjustingHeader=NO;}
    _groupHeader=nil;_nativeHeaderHeight=0;
}
// Normalize the native assignment before UITableView ever lays out a shorter header.
- (BOOL)reuseRowsForTable:(UITableView *)table nativeHeader:(UIView *)native {
    WXGHomeGroupHeader *rows=_groupHeader;
    if(!rows || rows.owner!=table || _adjustingHeader)return NO;
    BOOL pendingEditor=native && native==rows.pendingNativeHeader && WXGInstalledSearchField(native).isFirstResponder;
    if(![self wanted] || (!pendingEditor && (_nativeSearching || _page.navigationItem.searchController.isActive))) {
        [rows finishPendingSearchKeeping:nil];return NO;
    }
    if([native isKindOfClass:WXGHomeGroupHeader.class] || (native && [rows isDescendantOfView:native]))return NO;
    if((!pendingEditor && WXGHomeListInNativePull(table)) || WXGHomeTaskbarContains(native)) {
        [rows finishPendingSearchKeeping:nil];_remountAfterScroll=YES;
        return NO;
    }
    UIView *pending=rows.pendingNativeHeader;
    if(pending!=native)[rows finishPendingSearchKeeping:nil];
    UIView *old=rows.nativeHeader;
    BOOL same=native==old;
    UIView *search=same && _searchBar && [_searchBar isDescendantOfView:native]?_searchBar:[self searchBarIn:native];
    // Some Home layouts replace the real field with a blank search-sized spacer while scrolled.
    // A different, unrelated native header (e.g. the mini-program page) retains its own layout.
    BOOL keepEmpty=!native && (_bookmarkedHome || table.tracking || table.dragging || table.decelerating || WXGHomeSearchExposed(_page));
    BOOL plainSpacer=[native isMemberOfClass:UIView.class] && !native.subviews.count;
    // A composite native pull-down panel can contain a search bar of its own.
    // Only adopt the search row, never the enclosing header with its navigation controls.
    if(!same && search && native!=search && native.bounds.size.height>MAX(_nativeHeaderHeight,search.bounds.size.height)+12)return NO;
    if(!WXGHomeKeepsReservation(native!=nil,same,search!=nil,plainSpacer,keepEmpty,native.bounds.size.height,_nativeHeaderHeight))return NO;
    ++WXGHomeHeaderReuses;
    if(!same && [search isKindOfClass:UISearchBar.class] && table.tableHeaderView==rows &&
       !rows.nativeCanvas.hidden && (!native.superview || native.superview==rows.nativeCanvas) &&
       old.superview==rows.nativeCanvas) {
        UITextField *field=WXGInstalledSearchField(search);
        if(WXGHomeWaitsForSearchArtwork(!CGRectIsNull(WXGVisibleSearchBox(old)),!CGRectIsNull(WXGVisibleSearchBox(native)),
                                        field.isFirstResponder || field.text.length,field.placeholder.length || [(UISearchBar *)search placeholder].length)) {
            // The new UIKit shell is empty. Give it normal in-window layout
            // underneath the still-live WCSearchBar until its own artwork arrives.
            if(pending!=native) {
                _adjustingHeader=YES;
                @try {
                    rows.pendingNativeHeader=native;rows.pendingResize=native.autoresizingMask;
                    rows.pendingPaint=[WXGStateBag new];[rows.pendingPaint conceal:native];
                    native.autoresizingMask=UIViewAutoresizingFlexibleWidth;
                    native.frame=(CGRect){CGPointZero,{rows.nativeCanvas.bounds.size.width,native.bounds.size.height}};
                    [rows.nativeCanvas insertSubview:native atIndex:0];[native setNeedsLayout];
                    ++rows.deferredSearchAssignments;
                    [self traceHomeEvent:@"waitingForSearchArtwork" before:table.contentOffset.y after:table.contentOffset.y];
                } @finally {_adjustingHeader=NO;}
            }
            return YES;
        }
    }
    // A transient spacer carries no input or ink of its own. Keep the actual
    // field while we own it, and hand back the requested spacer on teardown.
    rows.holdingForSpacer=!search && !same && old && old.superview==rows.nativeCanvas && _searchBar;
    rows.nativeSpacer=rows.holdingForSpacer?native:nil;
    if(rows.holdingForSpacer){native=old;search=_searchBar;same=YES;}
    if(same && search==_searchBar && (!native || native.superview==rows.nativeCanvas) && table.tableHeaderView==rows)return YES;
    _adjustingHeader=YES;
    @try {
        [UIView performWithoutAnimation:^{
            WXGFloatSlot *slot=[self->_floats objectForKey:self->_page];
            [rows finishPendingSearchKeeping:native];
            if(!same) {
                [rows restoreNativeInk];
                if(old.superview==rows.nativeCanvas) {
                    old.autoresizingMask=rows.nativeResize;
                    [old removeFromSuperview];
                }
                rows.nativeResize=native.autoresizingMask;rows.nativeHeader=native;
            }
            if(!same || search!=self->_searchBar) {
                self->_lastMeasuredBarSize=CGSizeZero;self->_drawnField=nil;self->_fieldRechecks=0;
            }
            if(table.tableHeaderView!=rows)WXGPublishHomeRows(table,rows);
            if(native && native.superview!=rows.nativeCanvas) {
                CGSize size=native.bounds.size;
                native.autoresizingMask=UIViewAutoresizingFlexibleWidth;
                native.frame=(CGRect){CGPointZero,size};
                [rows.nativeCanvas addSubview:native];
            }
            if(native.superview==rows.nativeCanvas)native.autoresizingMask=UIViewAutoresizingFlexibleWidth;
            self->_searchBar=search;
            if(search) {
                [search setNeedsLayout];
                if(WXGPreferences.shared.localSearch && !rows.nativeCanvas.hidden)
                    [WXGLocalGlass.shared hostLaidOut:WXGSearchDisplayIn(native)?:search];
            }
            if(slot.ownedHeader==rows && slot.bar!=search) {
                [slot.states restore];slot.states=nil;slot.bar=search;slot.nativeField=nil;slot.measured=0;slot.exact=NO;slot.field=CGRectNull;
                slot.lookTries=0;slot.lookTried=0;slot.lookCopied=NO;
                if(search)[self claimSearchHeader:rows slot:slot refreshRoots:YES];
                else slot.clone.surface.glass.backdropExclusions=@[];
            }
        }];
    } @finally {_adjustingHeader=NO;}
    [self homeTableInsetChanged:table];
    [self traceHomeEvent:(search?@"nativeSearchAssigned":@"nativeSearchSpacer") before:table.contentOffset.y after:table.contentOffset.y];
    return YES;
}
- (WXGHomeGroupHeader *)groupHeaderFor:(UITableView *)table height:(CGFloat)height {
    if(WXGHomeListInNativePull(table)){_remountAfterScroll=YES;return nil;}
    if(_groupHeader && table.tableHeaderView==_groupHeader)return _groupHeader;
    CGFloat previousHeight=_groupHeader.owner==table?_groupHeader.bounds.size.height:0;
    CGFloat before=table.contentOffset.y;
    CGFloat depth=before+WXGHomeListTop(table);
    [self restoreResizedHeader];
    UIView *native=table.tableHeaderView;
    if(!native || native.bounds.size.height<20)return nil;
    for(WXGFloatSlot *slot in _floats.objectEnumerator)if(slot.ownedHeader==native)[self unpin:slot];
    _adjustingHeader=YES;
    @try {
        CGRect frame=native.frame;
        if(_page!=_startupPage) {
            _startupPage=_page;
            _startupTable=table;
            _startupPending=!(table.tracking || table.dragging || table.decelerating);
            _startupUntil=0;
        }
        CGRect reserved=frame;reserved.size.height=height;
        WXGHomeGroupHeader *wrapper=[[WXGHomeGroupHeader alloc] initWithFrame:reserved];
        WXGObserveHomeHeader(table);
        wrapper.owner=table;wrapper.reservedHeight=height;wrapper.nativeResize=native.autoresizingMask;wrapper.nativeHeader=native;
        _groupHeader=wrapper;if(table==WXGGroupedTable)WXGGroupedRows=wrapper;
        [UIView performWithoutAnimation:^{
            WXGPublishHomeRows(table,wrapper);
            native.autoresizingMask=UIViewAutoresizingFlexibleWidth;
            native.frame=(CGRect){CGPointZero,frame.size};
            UIView *canvas=[[UIView alloc] initWithFrame:native.frame];
            canvas.autoresizingMask=UIViewAutoresizingFlexibleWidth;
            wrapper.nativeCanvas=canvas;[wrapper addSubview:canvas];[canvas addSubview:native];
            if(previousHeight>0 && depth>=previousHeight && !self->_bookmarkedHome && !self->_startupPending && !self->_startupUntil &&
               !table.tracking && !table.dragging && !table.decelerating && !WXGHomeListInNativePull(table)) {
                CGFloat target=WXGHomeOffsetAtDepth(depth,previousHeight,height,WXGHomeListTop(table),
                    table.adjustedContentInset.bottom,table.contentSize.height,table.bounds.size.height);
                if(fabs(target-table.contentOffset.y)>.5)[table setContentOffset:CGPointMake(table.contentOffset.x,target) animated:NO];
            }
        }];
        [self traceHomeEvent:@"mountRows" before:before after:table.contentOffset.y];
    } @finally {_adjustingHeader=NO;}
    return _groupHeader;
}
// The colours: the bar's background is its range's material (分组, the
// settings); the pill the dock's own in R8-Aurora mode (or the page's/set
// colour in legacy mode), the titles the colour set.
- (void)applyColorsToBar:(WXGSegmentBar *)target from:(UIView *)ref {
    if(!target || !ref)return;
    UITraitCollection *traits=ref.traitCollection;BOOL dark=traits.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIColor *bg=nil;NSString *from=nil;
    for(UIView *v=ref.superview;v && ![v isKindOfClass:UIWindow.class];v=v.superview) {
        if(WXGIsPluginView(v) || !v.backgroundColor)continue;
        UIColor *resolved=[v.backgroundColor resolvedColorWithTraitCollection:traits];CGFloat r=0,g=0,b=0,a=0;
        if(![resolved getRed:&r green:&g blue:&b alpha:&a])continue;   // a pattern (a theme's picture): not a colour
        if(a>.9){bg=[UIColor colorWithRed:r green:g blue:b alpha:1];from=NSStringFromClass(v.class);break;}
    }
    if(!bg){bg=dark?[UIColor colorWithWhite:.11 alpha:1]:UIColor.whiteColor;from=@"default";}
    WXGConfig *c=WXGConfig.shared;
    if(c.dockPureGlassMode) {
        target.pillColor=nil;
        target.glass.selectionOverridePressedAlpha=-1;
    }else {
        UIColor *pill=[c extraNumber:@"segmentPillAuto"]>.5?bg:WXGColor([c extraHex:dark?@"segmentDarkPillHex":@"segmentPillHex"]);
        CGFloat pr=1,pg=1,pb=1,pa=1;if(![pill getRed:&pr green:&pg blue:&pb alpha:&pa]){pr=pg=pb=dark?.23:1;pa=1;}
        target.pillColor=[UIColor colorWithRed:pr green:pg blue:pb alpha:pa*WXGClamp([c extraNumber:dark?@"segmentDarkPillOpacity":@"segmentPillOpacity"],0,1)];
        target.glass.selectionOverridePressedAlpha=pa*WXGClamp([c extraNumber:@"segmentPillPressedOpacity"],0,1);
    }
    target.inkColor=WXGColor([c extraHex:dark?@"segmentDarkInkHex":@"segmentInkHex"])?:(dark?UIColor.whiteColor:UIColor.blackColor);
    target.accentColor=[c extraNumber:@"segmentAccentOn"]>.5?WXGColor([c extraHex:@"segmentAccentHex"]):nil;
    if(target==_bar) {
        CGFloat r=0,g=0,b=0,a=0;[bg getRed:&r green:&g blue:&b alpha:&a];
        _colorSource=[NSString stringWithFormat:@"page %@ #%02X%02X%02X; pill %@",from,(int)round(r*255),(int)round(g*255),(int)round(b*255),
                      c.dockPureGlassMode?@"dock":([c extraNumber:@"segmentPillAuto"]>.5?@"page":@"set")];
    }
}
- (void)applyColorsFrom:(UIView *)bar {if(!_categories)[self applyColorsToBar:(WXGSegmentBar *)_bar from:bar];}
- (void)updateOnPage:(UIViewController *)page {
    if(!NSThread.isMainThread || _adjustingHeader)return;
    if(![self wanted]){[self restore];return;}
    [self observe];
    if(!WXGHomeSearchExposed(page))return;
    _page=page;
    UITableView *table=_table && [_table isDescendantOfView:page.view]?_table:[self tableIn:page.view];
    if(WXGHomeListInNativePull(table)){if(!_groupHeader)_table=table;_remountAfterScroll=YES;return;}
    UIView *header=table.tableHeaderView;
    UIView *bar=_searchBar && header==_groupHeader && [_searchBar isDescendantOfView:header]?_searchBar:[self searchBarIn:header];
    if(!table || !header || !bar){_status=!table?@"没有找到聊天列表":!header?@"列表没有表头":@"表头里没有搜索栏";return;}
    if(_table!=table) {
        if(_categories)[self discardListForm];
        [self restoreResizedHeader];
    }
    _table=table;
    if(_searchBar!=bar) {
        _searchBar=bar;_fieldRechecks=0;_lastMeasuredBarSize=CGSizeZero;_drawnField=nil;
    }
    [self mountOver:bar header:header table:table];
}
- (void)searchBarLaidOut:(UIView *)view {
    if(_adjustingHeader || !view)return;
    UIView *pending=_groupHeader.pendingNativeHeader;
    if(pending && pending.superview!=_groupHeader.nativeCanvas){[_groupHeader finishPendingSearchKeeping:nil];pending=nil;}
    if(pending && (view==pending || [view isDescendantOfView:pending] || view==_searchBar) && _table.tableHeaderView==_groupHeader &&
       !WXGHomeListInNativePull(_table))[self reuseRowsForTable:_table nativeHeader:pending];
    if(view!=_searchBar || ![self wanted])return;
    if(!_bar.superview && !WXGHomeSearchExposed(_page))return;
    UITableView *table=_table;UIView *header=table.tableHeaderView;
    if(!table || !header || ![view isDescendantOfView:header])return;
    [self mountOver:view header:header table:table];
}
- (void)mountOver:(UIView *)bar header:(UIView *)header table:(UITableView *)table {
    // A pulled-down mini-program panel may publish its own composite header.
    // It owns that view until the real conversation search row is published again.
    if(WXGHomeListInNativePull(table)){_remountAfterScroll=YES;return;}
    if(WXGHomeTaskbarContains(header) || WXGHomeTaskbarContains(bar))return;
    if(_groupHeader && header!=_groupHeader && header!=_groupHeader.nativeHeader &&
       header!=bar && header.bounds.size.height>MAX(_nativeHeaderHeight,bar.bounds.size.height)+12)return;
    // A departing or covered home page may temporarily lose its native title and safe-area calibration.
    if(_groupHeader && table.tableHeaderView==_groupHeader && (_bookmarkedHome && !_returnReady) && !WXGHomeSearchExposed(_page))return;
    if(_nativeSearching) {
        UITextField *field=WXGInstalledSearchField(bar);
        BOOL using=(field && (field.isFirstResponder || field.text.length)) || _page.presentedViewController!=nil;
        if(!using)for(UIView *v in WXGViews(bar,160))if(v.isFirstResponder || ([v isKindOfClass:UITextField.class] && ((UITextField *)v).text.length)){using=YES;break;}
        if(using)return;
        _nativeSearching=NO;
    }
    WXGHomeGroupHeader *current=_groupHeader;
    if(current && header!=current && (table.tracking || table.dragging || table.decelerating)) {
        // WeChat supplied a different header. Leave its table alone until the gesture finishes.
        _remountAfterScroll=YES;
        return;
    }
    if(current && header==current && _bar.superview && _layoutRevision==WXGConfigRevision() &&
       table.bounds.size.width==_lastHeaderWidth && (table.tracking || table.dragging || table.decelerating)) {
        // The header already reserves the measured field. A replacement field
        // can finish measuring its artwork after the native pan settles.
        _remountAfterScroll=YES;
        return;
    }
    _remountAfterScroll=NO;
    UIView *native=current.nativeHeader;
    UIUserInterfaceStyle style=bar.traitCollection.userInterfaceStyle;
    BOOL local=WXGPreferences.shared.localSearch,floating=[self floatWanted];
    if(current && header==current && bar==_searchBar && _bar.superview &&
       _layoutRevision==WXGConfigRevision() && _layoutLocalSearch==local && _layoutFloat==floating &&
       _measuredStyle==style && CGSizeEqualToSize(bar.bounds.size,_lastMeasuredBarSize) &&
       current.bounds.size.width==_lastHeaderWidth && native.bounds.size.height==_nativeHeaderHeight &&
       current.leading==[self leadingForHeader:current table:table] &&
       CGRectEqualToRect([bar convertRect:_fieldRect toView:native],_measuredInNative) &&
       (_drawnField?([_drawnField isDescendantOfView:bar] && !_drawnField.hidden &&
          CGRectEqualToRect([_drawnField convertRect:_drawnField.bounds toView:bar],_fieldRect)):
          (![_fieldSource isEqualToString:WXGDrawnBoxSource] && CACurrentMediaTime()<_measureFallbackAfter))) {
        ++_skippedLaidOuts;[self revealInitialRows:table];return;
    }
    NSString *source=nil;UIView *paint=nil;
    CGRect field=[self fieldRectIn:bar source:&source paint:&paint];
    if(CGRectIsNull(field) || field.size.width<80){_status=@"等待原生搜索框布局";return;}
    if(header!=current)WXGReleaseLocalSearchHeaderHeight(table);
    native=WXGHomeNativeSearchHeader(header);
    CGFloat nativeHeight=native.bounds.size.height,width=table.bounds.size.width;
    CGRect measured=[bar convertRect:field toView:native];
    WXGRect box={measured.origin.x,measured.origin.y,measured.size.width,measured.size.height};
    if(!WXGHomeSearchFieldReady(box,native.bounds.size.width,nativeHeight))return;
    CGRect group=WXGHomeConfiguredRow(measured,width,YES);
    CGRect search=WXGHomeConfiguredRow(measured,width,NO);
    BOOL coexist=[WXGConfig.shared extraNumber:@"homeGroupCoexists"]>.5;
    _groupGap=coexist?[WXGConfig.shared extraNumber:@"homeSearchGroupGap"]:0;
    WXGRect searchBox={search.origin.x,search.origin.y,search.size.width,search.size.height};
    WXGHomeGroupLayout stack=WXGHomeRows(coexist,box,nativeHeight,searchBox,group.size.height,_groupGap);
    CGFloat leading=[self leadingForHeader:header table:table];
    CGFloat height=WXGHomePixel(leading+stack.headerHeight,table.window.screen.scale);
    WXGHomeGroupHeader *container=[self groupHeaderFor:table height:height];
    if(!container)return;
    if(!_bar && [WXGConfig.shared extraNumber:@"homeGroupForm"]>.5) {
        _categories=[[WXGHomeCategoryBar alloc] initWithFrame:CGRectZero];
        _categories.titles=@[@"置顶",@"私聊",@"群聊",@"服务",@"企业"];
        _selected=-1;_categories.selectedIndex=-1;_bar=_categories;
        [_categories addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventValueChanged];
        _pager=[[WXGHomeGroupPager alloc] initWithTable:table delegate:self];
        _pager.paging=[WXGConfig.shared extraNumber:@"homeGroupPaging"]>.5;
    }else if(!_bar) {
        _bar=[[WXGSegmentBar alloc] initWithFrame:CGRectZero];
        [_bar addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        NSArray *groups=WXGChatGroupList();NSInteger index=-1;
        for(NSUInteger i=0;i<groups.count;i++)if([groups[i][@"id"] isEqual:_selectedGroupID])index=(NSInteger)i;
        if(index<0 || atomic_load(&WXGFilterIndex)==0){NSInteger whole=[self wholeListIndex];if(whole>=0)index=whole;}
        _selected=MAX(0,index);_selectedGroupID=groups[(NSUInteger)_selected][@"id"];
        _bar.titles=[self groupNames];
        _bar.selectedIndex=_selected;
        NSDictionary *chosen=groups[(NSUInteger)_selected];
        if([chosen[@"rule"] integerValue]!=0 && atomic_load(&WXGFilterIndex)==0) {
            __weak WXGChatSegments *weakSelf=self;
            dispatch_async(dispatch_get_main_queue(),^{WXGChatSegments *me=weakSelf;if(me && me->_bar && !me->_categories && [me wanted])[me applyGroup:chosen];});
        }
    }
    _nativeHeaderHeight=nativeHeight;
    [self homeTableInsetChanged:table];
    [UIView performWithoutAnimation:^{
        [container replaceSearch:!coexist];
        [container placeNativeAtLeading:leading field:measured target:(local || floating || !coexist)?measured:search];
    }];
    _nativeBottomGap=stack.bottomGap;_searchRow=CGRectOffset(search,0,leading);
    group.origin.y=WXGHomePixel(leading+stack.groupY,table.window.screen.scale);
    [self applyHeaderHeight:height onHeader:container table:table];
    _naturalFrame=CGRectInset(group,-WXGCanvasPaddingX,-WXGCanvasPaddingY);
    _fieldRect=field;_fieldSource=source;_drawnField=paint;
    _measuredInNative=measured;_measureFallbackAfter=CACurrentMediaTime()+.5;
    _lastMeasuredBarSize=bar.bounds.size;_lastHeaderWidth=container.bounds.size.width;
    _layoutRevision=WXGConfigRevision();_measuredStyle=style;_layoutLocalSearch=local;_layoutFloat=floating;
    CGRect frame=[self listFrame];
    if(container!=_container)_segmentFloating=NO;
    if(!_segmentFloating)[UIView performWithoutAnimation:^{
        if(self->_bar.superview!=container){[container addSubview:self->_bar];++self->_mounts;}
        else if(container.subviews.lastObject!=self->_bar)[container bringSubviewToFront:self->_bar];
        if(!CGAffineTransformIsIdentity(self->_bar.transform))self->_bar.transform=CGAffineTransformIdentity;
        if(!CGRectEqualToRect(self->_bar.frame,frame)){self->_bar.frame=frame;++self->_moves;}
    }];
    _container=container;
    [self applyColorsFrom:bar];
    WXGInstallFilterHook();
    WXGFilterWatching=YES;
    _bar.hidden=_segmentCovered;_bar.active=!_segmentCovered;
    _status=coexist?@"搜索框与分组栏共存":@"分组栏替换搜索框";
    [self restoreChatPositionIfReady];
    [self revealInitialRows:table];
}
- (CGRect)listFrame {return _naturalFrame;}

- (BOOL)canPageHome {
    return _categories && _categories.active && _pager.table==_table && _table.window && _table.tableHeaderView==_groupHeader &&
        !_table.editing && !_nativeSearching && !WXGHomeListInNativePull(_table) && !_page.navigationItem.searchController.isActive &&
        _lastPanel<.12 && !_segmentCovered && !_bookmarkedHome && WXGHomeSearchExposed(_page);
}
- (NSInteger)homePageCount {return _categories.deviceTitle.length?4:5;}
- (NSInteger)homePageIndex {return _selected>=0?_selected:(atomic_load(&WXGFilterIndex)==1?-2:-1);}
- (CGRect)homeMessageViewportIn:(UIView *)parent {
    UITableView *table=_table;
    if(!parent.window || table.superview!=parent)return CGRectZero;
    CGRect area=CGRectIntersection(parent.bounds,[table convertRect:table.bounds toView:parent]);
    if(CGRectIsEmpty(area))return CGRectZero;
    CGFloat chrome=[self homeChromeBottomInWindow:table.window];
    CGFloat top=MAX(CGRectGetMinY(area),[parent convertPoint:CGPointMake(0,chrome) fromView:table.window].y);
    if(_bar.window==table.window && !_bar.hidden) {
        CGRect material=CGRectInset(_bar.bounds,WXGCanvasPaddingX,WXGCanvasPaddingY);
        top=MAX(top,CGRectGetMaxY([_bar convertRect:material toView:parent]));
    }
    return CGRectMake(CGRectGetMinX(area),top,area.size.width,MAX(0,CGRectGetMaxY(area)-top));
}
- (void)previewHomePageFrom:(NSInteger)from to:(NSInteger)to fraction:(CGFloat)fraction {
    if(!_pager.busy && from==to)[_categories returnToIndex:(to<0?-1:to)];
    else [_categories showFrom:from to:to progress:fraction];
}
- (void)rememberHomeCategory {
    [NSUserDefaults.standardUserDefaults setInteger:(_selected+1) forKey:@"WXGHomeLastCategory"];
}
// Only open a native folded pinned section after its data source confirms zero rows.
// Undo only the expansion we initiated when leaving the pinned category.
- (NSInteger)pinnedSectionRows {
    id<UITableViewDataSource> source=_table.dataSource;
    if(!source || ![source respondsToSelector:@selector(numberOfSectionsInTableView:)] ||
       [source numberOfSectionsInTableView:_table]<3)return -1;
    return [source tableView:_table numberOfRowsInSection:1];
}
- (void)expandCategoryFold {
    if(!WXGFilterSnapshotTopCount || [self pinnedSectionRows]!=0)return;
    Class kind=NSClassFromString(@"MainFrameSectionFoldView");
    if(!kind)return;
    for(NSInteger section=0;section<2;section++) {
        for(int footer=0;footer<=1;footer++) {
            UIView *root=footer?[_table footerViewForSection:section]:[_table headerViewForSection:section];
            if(!root) {
                id<UITableViewDelegate> d=_table.delegate;
                if(footer && [d respondsToSelector:@selector(tableView:viewForFooterInSection:)])root=[d tableView:_table viewForFooterInSection:section];
                if(!footer && [d respondsToSelector:@selector(tableView:viewForHeaderInSection:)])root=[d tableView:_table viewForHeaderInSection:section];
            }
            if(!root)continue;
            UIView *fold=[root isKindOfClass:kind]?root:nil;
            if(!fold)for(UIView *child in WXGViews(root,24))if([child isKindOfClass:kind]){fold=child;break;}
            if(fold && WXGSessionCallVoid(fold,@"onSingleTap")){_openedFold=fold;return;}
        }
    }
}
- (void)restoreCategoryFold {
    UIView *ours=_openedFold;_openedFold=nil;
    if(ours && atomic_load(&WXGFilterIndex)==WXGCategoryPinned && [self pinnedSectionRows]>0)
        WXGSessionCallVoid(ours,@"onSingleTap");
}
- (BOOL)showHomePage:(NSInteger)index {
    if(!_categories || index < -2 || index >= [self homePageCount])return NO;
    if(index!=0)[self restoreCategoryFold];
    _startupPending=NO;_startupUntil=0;
    NSInteger rule=index==-2?1:index==-1?0:WXGCategoryPinned+index;
    BOOL ok=[self applyRule:rule members:nil name:index<0?nil:_categories.titles[(NSUInteger)index]];
    _selected=ok && index>=0?index:-1;
    if(!_pager.busy)[_categories returnToIndex:_selected];
    _titleBar.acceptsReselection=_selected>=0;
    NSInteger title=atomic_load(&WXGFilterIndex)==1?1:0;
    if(_titleSelected!=title){_titleSelected=title;[_titleBar returnToIndex:title];}
    if(ok && index==0)[self expandCategoryFold];
    return ok;
}
- (void)categoryTapped:(WXGHomeCategoryBar *)sender {
    if(![self canPageHome])return;
    NSInteger index=sender.tappedIndex;
    if(index==4 && _categories.deviceTitle.length) {
        [self updateDeviceCategory];
        if(_categories.deviceTitle.length) {
            if(_deviceButton.window==_table.window && [_deviceButton isDescendantOfView:_table])
                [_deviceButton sendActionsForControlEvents:UIControlEventTouchUpInside];
            else if(_deviceTarget)WXGSessionCallVoid(_deviceTarget,@"showLogoutWebOnline");
            return;
        }
    }
    if(index==_selected)return;
    [_pager selectPage:index];
}
static NSString *WXGLoginPlatform(NSString *text) {
    if(![text isKindOfClass:NSString.class] || !text.length)return nil;
    NSString *lower=text.lowercaseString;
    if([lower containsString:@"ipad"])return @"iPad";
    if([lower containsString:@"mac"])return @"Mac";
    if([lower containsString:@"win"] || [lower containsString:@"电脑"])return @"Win";
    if([lower containsString:@"android"] || [lower containsString:@"安卓"])return @"安卓";
    if([lower containsString:@"平板"])return @"平板";
    return nil;
}
- (void)updateDeviceCategory {
    UITableView *t=_table;
    NSInteger rows=t.numberOfSections?[t numberOfRowsInSection:0]:0;
    Class kind=NSClassFromString(@"MFWebMMBtn");
    BOOL sawAll=YES;NSString *title=nil;UIControl *button=nil;id handler=nil;
    for(NSInteger i=0;i<MIN(2,rows) && !handler;i++) {
        UITableViewCell *cell=[t cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
        if(!cell){sawAll=NO;continue;}
        for(UIView *v in WXGViews(cell.contentView,40)) {
            if([v isKindOfClass:UILabel.class] && !title)title=WXGLoginPlatform(((UILabel *)v).text);
            if(!kind || ![v isKindOfClass:kind] || ![v isKindOfClass:UIControl.class])continue;
            UIControl *c=(UIControl *)v;
            for(id target in c.allTargets) {
                if([[c actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] containsObject:@"showLogoutWebOnline"]) {
                    button=c;handler=target;break;
                }
            }
        }
        if(!handler)title=nil;
    }
    if(!handler && !sawAll && _deviceTarget)return;
    NSString *device=handler?(title?:@"已登录"):nil;
    if(device && _selected==4){[self showHomePage:-1];[self rememberHomeCategory];}
    _deviceTarget=handler;_deviceButton=button;_categories.deviceTitle=device;
}
- (void)updateCategoriesAt:(CFTimeInterval)time {
    // Only touch native cells while idle. While filtered, badges use the full list
    // captured before filtering, in bounded batches outside the vertical pan.
    if(time>=_nextDeviceCheck) {
        _nextDeviceCheck=time+1.;
        [self updateDeviceCategory];
    }
    if(!_triedInitialCategory && WXGFilterSnapshot.count && _table.dataSource && _table.numberOfSections && [self canPageHome] && !_startupPending) {
        _triedInitialCategory=YES;
        NSInteger saved=[NSUserDefaults.standardUserDefaults integerForKey:@"WXGHomeLastCategory"]-1;
        if(saved>=0 && saved<[self homePageCount] && atomic_load(&WXGFilterIndex)==0)[self showHomePage:saved];
    }
    if(!WXGFilterSnapshot && time>=_nextBadgeSeed && atomic_load(&WXGFilterIndex)==0) {
        _nextBadgeSeed=time+2.;
        id manager=_categoryManager?:WXGHomeSessionManager(_page,_table);
        if(manager) {
            _categoryManager=manager;
            NSArray *t=WXGSessionGetObject(manager,@"topSessions"),*n=WXGSessionGetObject(manager,@"normalSessions");
            if([t isKindOfClass:NSArray.class] && [n isKindOfClass:NSArray.class]) {
                WXGFilterSnapshot=[t arrayByAddingObjectsFromArray:n];WXGFilterSnapshotTopCount=t.count;
            }
        }
    }
    NSArray *snapshot=WXGFilterSnapshot;
    if(!snapshot)return;
    BOOL changed=snapshot!=_badgeSnapshot;
    if(changed){_badgeSnapshot=snapshot;_badgeCursor=0;memset(_unreadTotals,0,sizeof _unreadTotals);}
    if(!changed && _badgeCursor>=snapshot.count)return;
    NSUInteger limit=MIN(snapshot.count,_badgeCursor+24);
    for(;_badgeCursor<limit;_badgeCursor++) {
        id session=snapshot[_badgeCursor];NSInteger count=WXGSessionCount(session,"m_uUnReadCount");
        if(count<=0)continue;
        NSInteger kind=_badgeCursor<WXGFilterSnapshotTopCount?WXGCategoryPinned:WXGHomeCategoryForName(WXGSessionUserName(session));
        NSInteger *total=&_unreadTotals[kind-WXGCategoryPinned];
        if(WXGSessionCount(session,"m_bShowUnReadAsRedDot")){if(!*total)*total=-1;}
        else *total=MIN(100,MAX(0,*total)+MIN(100,count));
    }
    if(_badgeCursor==snapshot.count) {
        _categories.unreadCounts=@[@(_unreadTotals[0]),@(_unreadTotals[1]),@(_unreadTotals[2]),@(_unreadTotals[3]),@(_unreadTotals[4])];
    }
}
- (void)takeProbe {
    UITableView *table=_table;if(!table)return;
    CFTimeInterval start=CACurrentMediaTime();
    NSDictionary *probe=WXGChatListProbe(table,_page);
    NSMutableDictionary *stamped=[probe mutableCopy];stamped[@"ms"]=@(round((CACurrentMediaTime()-start)*10000)/10);
    stamped[@"since"]=@(round(WXGSecondsSinceLoad()*10)/10);
    _probe=stamped;_probeAt=CACurrentMediaTime();
}
// R23: Home All/Unread title group bar mounted cleanly in _navigationOverlay
// (zero swizzles, zero KVO, zero subviews inside MFTitleView) while concealing
// native MFTitleView(s) via a dedicated bag (zero flash on return from chat)
// using the list offset on Home and the native presentation during navigation.
- (void)concealHomeTitlesNav:(UIView *)navTitle pull:(UIView *)pullTitle {
    if(![self titleModeWanted])return;
    if(!_titleConceal)_titleConceal=[WXGStateBag new];
    if(navTitle)[_titleConceal conceal:navTitle];
    if(pullTitle && pullTitle!=navTitle)[_titleConceal conceal:pullTitle];
    [_titleConceal reapply];
}
- (void)fitTitleBarInRect:(CGRect)available {
    if(_titleAvailableRect.size.height!=available.size.height)_titleHasRestDelta=NO;
    _titleAvailableRect=available;
    CGFloat width=MIN(available.size.width,[_titleBar preferredTitleWidthForHeight:available.size.height]);
    _titleRestRect=CGRectMake(CGRectGetMidX(available)-width*.5,CGRectGetMinY(available),width,available.size.height);
    if(!CGSizeEqualToSize(_titleLastRect.size,_titleRestRect.size))_titleLastRect=CGRectZero;
}
- (void)updateTitleBarOnPage:(UIViewController *)page inOverlay:(UIView *)overlay rect:(CGRect)rect navTitle:(UIView *)navTitle pullTitle:(UIView *)pullTitle englishHint:(BOOL)englishHint {
    if(!NSThread.isMainThread)return;
    if(![self titleModeWanted]) {[self releaseTitleBar];return;}
    if(!page || !overlay || CGRectIsEmpty(rect) || rect.size.width<40 || rect.size.height<20) {
        [self hideTitleBar];return;
    }
    [self observe];
    if(page.isViewLoaded && page.view.window) {
        _page=page;
        if(!_table || ![_table isDescendantOfView:page.view])_table=[self tableIn:page.view];
        WXGInstallFilterHook();WXGFilterWatching=YES;
    }
    if(englishHint)_titleEnglishHint=YES;
    if(navTitle)_titleNavView=navTitle;
    if(pullTitle && pullTitle!=navTitle)_titlePullView=pullTitle;
    _titleOverlay=overlay;
    [self concealHomeTitlesNav:_titleNavView pull:_titlePullView];

    if(!_titleBar) {
        _titleBar=[[WXGSegmentBar alloc] initWithFrame:CGRectZero];
        _titleBar.fitsTitlePair=YES;
        _titleBar.autoresizingMask=UIViewAutoresizingNone;
        [_titleBar addTarget:self action:@selector(titleSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    }
    BOOL en=WXGConfig.shared.homeTitleSegmentsEnglish || _titleEnglishHint;
    NSArray<NSString *> *titles=en?@[@"All",@"Unread"]:@[@"全部",@"未读"];
    if(![_titleBar.titles isEqualToArray:titles])_titleBar.titles=titles;
    [self fitTitleBarInRect:rect];
    NSInteger liveIdx=atomic_load(&WXGFilterIndex)==1?1:0;
    if(_titleSelected!=liveIdx){_titleSelected=liveIdx;_titleBar.selectedIndex=liveIdx;}
    [self applyColorsToBar:_titleBar from:overlay];
    [self followTitleBarInOverlay:overlay page:page transitioning:(page.transitionCoordinator!=nil) transitionInvolvesHome:YES homePanel:_lastPanel rowOffset:0];
}
- (void)followTitleBarInOverlay:(UIView *)overlay page:(UIViewController *)leaf transitioning:(BOOL)transitioning transitionInvolvesHome:(BOOL)transitionInvolvesHome homePanel:(CGFloat)homePanel rowOffset:(CGFloat)rowOffset {
    (void)rowOffset;
    if(!_titleBar && !_titleConceal)return;
    if(![self titleModeWanted]) {[self releaseTitleBar];return;}
    static Class homeClass;static dispatch_once_t homeOnce;
    dispatch_once(&homeOnce,^{homeClass=NSClassFromString(@"NewMainFrameViewController");});
    BOOL onHome=homeClass && [leaf isKindOfClass:homeClass];
    BOOL allowShow=overlay && overlay.window && !CGRectIsEmpty(_titleRestRect) && (onHome || (transitioning && transitionInvolvesHome));
    if(_titleConceal && (onHome || (transitioning && transitionInvolvesHome))) {
        if(_titleNavView && ![_titleNavView.layer.mask.name isEqualToString:@"wxg.conceal"])[_titleConceal conceal:_titleNavView];
        if(_titlePullView && ![_titlePullView.layer.mask.name isEqualToString:@"wxg.conceal"])[_titleConceal conceal:_titlePullView];
    }
    if(!allowShow) {
        [self hideTitleBar];
        return;
    }
    if(!_titleBar)return;
    UIWindow *w=overlay.window;
    UIView *navTitle=_titleNavView,*pullTitle=_titlePullView;
    // Lazily discover WeChat's secondary pull-down MFTitleView inside MainFrameTableView once if missing.
    if((!pullTitle || pullTitle.window!=w) && onHome && _table.window==w && !_table.tracking && !_table.decelerating && CACurrentMediaTime()>=_nextPullTitleLookup) {
        _nextPullTitleLookup=CACurrentMediaTime()+.25;
        static Class mfTitleCls;static dispatch_once_t mfOnce;
        dispatch_once(&mfOnce,^{mfTitleCls=NSClassFromString(@"MFTitleView");});
        if(mfTitleCls) {
            for(UIView *v in WXGViews(_table,90)) {
                if(v!=navTitle && [v isKindOfClass:mfTitleCls]) {
                    pullTitle=v;_titlePullView=v;
                    [self concealHomeTitlesNav:navTitle pull:pullTitle];
                    break;
                }
            }
        }
    }
    BOOL listDriven=onHome && !transitioning && _table && _table.window==w && !_nativeSearching && !leaf.navigationItem.searchController.isActive;
    CGFloat navAlpha=!listDriven && navTitle?WXGPresentedChainAlpha(navTitle,w)*WXGTitleContentPresentedAlpha(navTitle):0.;
    CGFloat pullAlpha=!listDriven && pullTitle?WXGPresentedChainAlpha(pullTitle,w)*WXGTitleContentPresentedAlpha(pullTitle):0.;
    UIView *activeHost=nil;CGFloat shownAlpha=0.;
    if(listDriven) {
        shownAlpha=1.;
    }else if(pullTitle && pullAlpha>navAlpha+.02) {
        activeHost=pullTitle;shownAlpha=pullAlpha;
    }else if(navTitle && navAlpha>.005) {
        activeHost=navTitle;shownAlpha=navAlpha;
    }else if(pullTitle && pullAlpha>.005) {
        activeHost=pullTitle;shownAlpha=pullAlpha;
    }else if(!navTitle && !pullTitle && onHome && !transitioning) {
        shownAlpha=1.;
    }
    // R25: bridge WeChat's 1-3 frame navTitle <-> pullTitle handoff gap during
    // partial pull-down & release using the host's homePullAlphaFloor (same
    // floor that protects the "+" button), and keep the Metal bar warm while
    // on Home so it never blinks re-presenting a frame.
    CGFloat pullFloor=(onHome && !transitioning)?[WXGIntegrationHost.shared homePullAlphaFloor]:0.;
    if(pullFloor>.01 && shownAlpha<pullFloor)shownAlpha=pullFloor;
    if(homePanel>.005)shownAlpha=MIN(shownAlpha,WXGClamp(1.-homePanel,0.,1.));
    BOOL visible=shownAlpha>=.01;
    CGRect rect=_titleRestRect;
    if(listDriven) {
        CGFloat sc=w.screen.scale;
        CGFloat pull=WXGHomePullTranslation(_table.contentOffset.y,WXGHomeConversationTop(_table),sc);
        if(!_titleHasRestDelta && pull==0 && navTitle.window==w) {
            CGFloat mid=CGRectGetMidY([navTitle convertRect:navTitle.bounds toView:overlay]);
            CGFloat delta=mid-CGRectGetMidY(_titleRestRect);
            if(isfinite(delta) && fabs(delta)<_titleRestRect.size.height*.5) {
                _titleRestDelta=delta;_titleHasRestDelta=YES;
            }
        }
        rect.origin.y=WXGHomePixel(rect.origin.y+(_titleHasRestDelta?_titleRestDelta:0),sc)+pull;
        _titleSampledBounds=_table.bounds;_titleLastRect=rect;
    }else if(activeHost && visible) {
        CGRect r=WXGHomeRect(activeHost,activeHost.bounds,overlay,transitioning);
        CGPoint c=CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r));
        if(isfinite(c.x) && isfinite(c.y) && (fabs(c.x)>1. || fabs(c.y)>1.) && c.y>-rect.size.height && c.y<w.bounds.size.height+rect.size.height) {
            CGFloat sc=w.screen.scale?:3.;
            CGFloat rx=round((c.x-rect.size.width*.5)*sc)/sc;
            if(!transitioning)rx=WXGClamp(rx,CGRectGetMinX(_titleAvailableRect),CGRectGetMaxX(_titleAvailableRect)-rect.size.width);
            CGFloat ry=round((c.y-rect.size.height*.5)*sc)/sc;
            rect=CGRectMake(rx,ry,rect.size.width,rect.size.height);
            _titleLastRect=rect;
        }
    }else if(pullFloor>.01 && !CGRectIsEmpty(_titleLastRect)) {
        rect=_titleLastRect;
    }
    BOOL keepWarm=onHome && !transitioning;
    BOOL mountShown=visible || keepWarm;
    CGRect target=CGRectInset(rect,-WXGCanvasPaddingX,-WXGCanvasPaddingY);
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(mountShown && self->_titleBar.superview!=overlay)[overlay addSubview:self->_titleBar];
        if(mountShown) {
            CGRect cur=self->_titleBar.frame;
            if(fabs(cur.origin.x-target.origin.x)>.25 || fabs(cur.origin.y-target.origin.y)>.25 ||
               fabs(cur.size.width-target.size.width)>.25 || fabs(cur.size.height-target.size.height)>.25) {
                self->_titleBar.frame=target;
            }
        }
        if(fabs(self->_titleBar.alpha-shownAlpha)>.005)self->_titleBar.alpha=shownAlpha;
        BOOL hide=!mountShown;
        if(self->_titleBar.hidden!=hide)self->_titleBar.hidden=hide;
        [CATransaction commit];
    }];
    _titleBar.acceptsReselection=_categories && _selected>=0;
    _titleBar.userInteractionEnabled=visible && !transitioning;
    _titleBar.active=mountShown && overlay.window!=nil;
    if(!_titleTrace || _traceTitleHome!=onHome || _traceTitleTransition!=transitioning ||
       fabs(_traceTitleAlpha-shownAlpha)>.01 || _traceTitleY!=rect.origin.y) {
        if(!_titleTrace)_titleTrace=[NSMutableArray array];
        _traceTitleHome=onHome;_traceTitleTransition=transitioning;_traceTitleAlpha=shownAlpha;_traceTitleY=rect.origin.y;
        if(_titleTrace.count>=16)[_titleTrace removeObjectAtIndex:0];
        [_titleTrace addObject:[NSString stringWithFormat:@"%.2f h:%d t:%d a:%.2f y:%.1f",WXGSecondsSinceLoad(),onHome,transitioning,shownAlpha,rect.origin.y]];
    }
}
- (void)titleSegmentChanged:(WXGSegmentBar *)bar {
    [_pager cancel];[self restoreCategoryFold];
    _bookmarkedHome=nil;_returnReady=NO;
    [self traceHomeEvent:@"titleGroup" before:_table.contentOffset.y after:_table.contentOffset.y];
    NSInteger idx=(NSInteger)WXGClamp(bar.selectedIndex,0,1);
    _titleSelected=idx;++_switches;
    NSInteger rule=idx==1?1:0;
    NSString *name=idx==1?@"未读":@"全部";
    BOOL ok=[self applyRule:rule members:nil name:name];
    if(!_switchLog)_switchLog=[NSMutableArray array];
    if(_switchLog.count>=20)[_switchLog removeObjectAtIndex:0];
    [_switchLog addObject:[NSString stringWithFormat:@"%.1f s title #%ld rule %ld %@",WXGSecondsSinceLoad(),(long)idx,(long)rule,ok?@"ok":_filterStatus?:@"?"]];
    if(!ok) {
        _titleSelected=0;[bar returnToIndex:0];
        if(_categories && atomic_load(&WXGFilterIndex)==0){_selected=-1;[_categories returnToIndex:-1];}
    }else if(_categories) {
        _selected=-1;[_categories returnToIndex:-1];[self rememberHomeCategory];
    }else if(_bar) {
        NSArray<NSDictionary *> *groups=WXGChatGroupList();
        for(NSUInteger i=0;i<groups.count;i++)if([groups[i][@"rule"] integerValue]==rule) {
            _selected=(NSInteger)i;_selectedGroupID=groups[i][@"id"];[_bar returnToIndex:(NSInteger)i];break;
        }
    }
}
- (void)hideTitleBar {
    if(!_titleBar)return;
    _titleBar.userInteractionEnabled=NO;
    _titleBar.active=NO;_titleBar.hidden=YES;
    [_titleBar removeFromSuperview];
}
- (void)releaseTitleBar {
    [self hideTitleBar];
    [_titleConceal restore];
    _titleConceal=nil;_titleHasRestDelta=NO;_titleSampledBounds=CGRectNull;
    _titleNavView=nil;_titlePullView=nil;_titleOverlay=nil;_titleAvailableRect=CGRectZero;_titleRestRect=CGRectZero;_titleLastRect=CGRectZero;
}
- (void)segmentChanged:(WXGSegmentBar *)bar {
    _bookmarkedHome=nil;_returnReady=NO;
    [self traceHomeEvent:@"listGroup" before:_table.contentOffset.y after:_table.contentOffset.y];
    _startupPending=NO;_startupUntil=0;
    NSArray<NSDictionary *> *groups=WXGChatGroupList();
    NSInteger previous=_selected;
    _selected=(NSInteger)WXGClamp(bar.selectedIndex,0,(NSInteger)groups.count-1);++_switches;
    NSDictionary *group=groups[(NSUInteger)_selected];
    BOOL ok=[self applyGroup:group];   // FIX113 Q / R
    if(!_switchLog)_switchLog=[NSMutableArray array];
    if(_switchLog.count>=20)[_switchLog removeObjectAtIndex:0];
    [_switchLog addObject:[NSString stringWithFormat:@"%.1f s #%ld rule %@ %@",WXGSecondsSinceLoad(),(long)_selected,group[@"rule"],ok?@"ok":_filterStatus?:@"?"]];
    if(_switches<=3 || !ok)WXGLog(@"聊天分组：切到第 %ld 组，%@",(long)_selected+1,_filterStatus?:@"");
    if(ok) {
        _selectedGroupID=group[@"id"];
        if(_titleBar){NSInteger ti=[group[@"rule"] integerValue]==1?1:0;_titleSelected=ti;[_titleBar returnToIndex:ti];}
    }else {   // back to the group that shows WeChat's whole list (none: the bar stays, the list is whole), said in the diagnostics
        NSInteger whole=[self wholeListIndex];
        if(whole>=0){_selected=whole;_selectedGroupID=groups[(NSUInteger)whole][@"id"];[bar returnToIndex:whole];}
        else {_selected=previous;_selectedGroupID=nil;[bar returnToIndex:previous];}
    }
}
// The first group showing WeChat's whole list (-1: none).
- (NSInteger)wholeListIndex {
    NSArray *groups=WXGChatGroupList();
    for(NSUInteger i=0;i<groups.count;i++)if([groups[i][@"rule"] integerValue]==0)return (NSInteger)i;
    return -1;
}
- (BOOL)applyGroup:(NSDictionary *)group {
    NSInteger rule=[group[@"rule"] integerValue];
    NSSet *members=rule==4?[NSSet setWithArray:group[@"members"]?:@[]]:nil;
    return [self applyRule:rule members:members name:group[@"name"]?:@""];
}
// FIX113 R: the groups changed in the settings: the bar's titles, and the
// list again for the group chosen (or the whole list when it is gone).
- (void)groupsChanged:(__unused NSNotification *)note {
    if(_categories)return;
    if(!_bar || ![self wanted]){_selected=0;_selectedGroupID=nil;return;}   // no bar: nothing filtered from here
    NSArray<NSDictionary *> *groups=WXGChatGroupList();
    NSInteger index=-1;
    for(NSUInteger i=0;i<groups.count;i++)if([groups[i][@"id"] isEqual:_selectedGroupID])index=(NSInteger)i;
    if(index<0){NSInteger whole=[self wholeListIndex];index=whole>=0?whole:0;}
    _selected=index;_selectedGroupID=groups[(NSUInteger)index][@"id"];
    if(_bar){_bar.titles=[self groupNames];[_bar returnToIndex:index];}
    if(atomic_load(&WXGFilterIndex)>0 || [groups[(NSUInteger)index][@"rule"] integerValue]!=0) {
        if(![self applyGroup:groups[(NSUInteger)index]]){NSInteger whole=[self wholeListIndex];if(whole>=0){_selected=whole;_selectedGroupID=groups[(NSUInteger)whole][@"id"];[_bar returnToIndex:whole];}else _selectedGroupID=nil;}
    }
}
- (NSArray<NSString *> *)groupNames {
    NSMutableArray *names=[NSMutableArray array];
    for(NSDictionary *group in WXGChatGroupList())[names addObject:group[@"name"]?:@"?"];
    return names;
}
// FIX113 Q: the list filtered for this segment (0: WeChat's own list again).
// WeChat's pinned count back if its rebuild left the one we wrote.
- (void)restoreTopCount:(id)manager {
    @try {
        NSArray *top=WXGSessionGetObject(manager,@"topSessions");long long count=0;
        if(WXGFilterWrittenCount>=0 && [top isKindOfClass:NSArray.class] && WXGSessionGetInteger(manager,@"totalTopSessionCount",&count) && count==WXGFilterWrittenCount)
            WXGSessionSetInteger(manager,@"setTotalTopSessionCount:",(long long)top.count+WXGFilterTopDelta);
    } @catch(__unused NSException *error) {}
    WXGFilterWrittenCount=-1;
}
// The whole list again: the rebuild unfiltered (row updates during it still
// become reloads), then one reload, then UIKit's own updates again.
- (void)rebuildWhole:(id)manager table:(UITableView *)table {
    atomic_store(&WXGFilterIndex,0);
    if(manager) {
        @try {WXGSessionCallVoid(manager,@"rebuildMainSessions");} @catch(__unused NSException *error) {}
        [self restoreTopCount:manager];
    }
    [table reloadData];
    WXGFilterGuarding=NO;
}
- (BOOL)failFilter:(NSString *)why {
    // Whatever was filtered before this refused switch goes back first.
    if(atomic_load(&WXGFilterIndex)>0) {
        if(atomic_load(&WXGFilterOffMain)>0 || atomic_load(&WXGFilterDisabled))[self filterOffMain];
        else [self rebuildWhole:WXGFilterManager table:WXGFilterTable?:_table];
    }
    _filterStatus=why;++_filterFails;return NO;
}
- (BOOL)applyRule:(NSInteger)index members:(NSSet *)members name:(NSString *)name {
    CFTimeInterval start=CACurrentMediaTime();
    UITableView *table=_table;UIViewController *page=_page;
    if(index<=0 || index>WXGCategoryWork) {
        if(atomic_load(&WXGFilterIndex)>0) {
            if(atomic_load(&WXGFilterOffMain)>0 || atomic_load(&WXGFilterDisabled))[self filterOffMain];   // no rebuild of ours then
            else [self rebuildWhole:WXGFilterManager table:WXGFilterTable?:table];
        }
        _filterStatus=@"全部（微信自己的列表）";_filterMS=(CACurrentMediaTime()-start)*1000;
        return YES;
    }
    if(_filterBroken)return [self failFilter:_filterBrokenWhy?:@"这次运行里分组筛选已停用"];
    if(!table || !page)return [self failFilter:@"没有聊天列表"];
    if(atomic_load(&WXGFilterOffMain)>0 || atomic_load(&WXGFilterDisabled))return [self failFilter:@"微信在后台线程重建会话列表，分组筛选在这台微信上不安全，没有启用"];
    id manager=_categories?(_categoryManager?:WXGHomeSessionManager(page,table)):WXGHomeSessionManager(page,table);
    if(_categories)_categoryManager=manager;
    NSString *missing=WXGSessionAPIMissing(manager);
    if(missing)return [self failFilter:[@"会话管理器缺少：" stringByAppendingString:missing]];
    if(!WXGInstallFilterHook())return [self failFilter:@"挂不上 rebuildMainSessions"];
    if(!WXGInstallTableGuards(table))return [self failFilter:[NSString stringWithFormat:@"首页列表是 %@，不是微信自己的表格类，不能安全拦截逐行更新",NSStringFromClass([table class])]];
    @try {
        if(atomic_load(&WXGFilterIndex)==0 || WXGFilterManager!=manager || WXGFilterTable!=table) {
            // What the data source counts besides the sessions, with WeChat's whole list.
            if(atomic_load(&WXGFilterIndex)!=0)[self rebuildWhole:WXGFilterManager table:WXGFilterTable];
            NSArray *top=WXGSessionGetObject(manager,@"topSessions"),*normal=WXGSessionGetObject(manager,@"normalSessions");
            NSInteger rows=WXGDataSourceRows(table);
            if(![top isKindOfClass:NSArray.class] || ![normal isKindOfClass:NSArray.class] || rows<0)return [self failFilter:@"读不到会话数组或行数"];
            _rowOffset=rows-(NSInteger)(top.count+normal.count);
        }
        WXGFilterManager=manager;WXGFilterTable=table;WXGFilterGuarding=YES;WXGFilterMembers=[members copy]?:[NSSet set];
        atomic_store(&WXGFilterLastOK,NO);atomic_store(&WXGFilterIndex,index);
        WXGSessionCallVoid(manager,@"rebuildMainSessions");
        NSArray *top=WXGSessionGetObject(manager,@"topSessions"),*normal=WXGSessionGetObject(manager,@"normalSessions");
        NSInteger rows=WXGDataSourceRows(table);
        BOOL filtered=atomic_load(&WXGFilterLastOK);
        BOOL arrays=[top isKindOfClass:NSArray.class] && [normal isKindOfClass:NSArray.class];
        BOOL follows=filtered && arrays && rows-(NSInteger)(top.count+normal.count)==_rowOffset;
        // FIX113 S: or the list's sections show it (a banner row that came or
        // went since the count before - after coming back from a chat - is
        // not the list ignoring the arrays): a section with exactly the
        // filtered chats, the pinned ones in another (fewer when folded).
        if(!follows && filtered && arrays) {
            id<UITableViewDataSource> source=table.dataSource;
            NSInteger sections=[source respondsToSelector:@selector(numberOfSectionsInTableView:)]?[source numberOfSectionsInTableView:table]:1;
            NSInteger normalAt=-1,topAt=-1;
            for(NSInteger sct=0;sct<sections && sct<64;sct++) {
                NSInteger n=[source tableView:table numberOfRowsInSection:sct];
                if(normalAt<0 && n==(NSInteger)normal.count && (normal.count>0 || sct>0))normalAt=sct;
            }
            for(NSInteger sct=0;sct<sections && sct<64;sct++)
                if(sct!=normalAt && [source tableView:table numberOfRowsInSection:sct]<=(NSInteger)top.count){topAt=sct;if(sct==normalAt-1)break;}
            if(normalAt>=0 && topAt>=0){follows=YES;_rowOffset=rows-(NSInteger)(top.count+normal.count);}
        }
        if(!follows) {
            [self rebuildWhole:manager table:table];
            // Not for the rest of the run: the next try is checked again.
            NSString *why=!filtered?@"筛选没有生效（会话数组读写失败），已回到全部":
                [NSString stringWithFormat:@"列表的行数不跟着会话数组变（%ld 行，数组 %lu + %lu，另有 %ld 行），已回到全部",
                 (long)rows,(unsigned long)top.count,(unsigned long)normal.count,(long)_rowOffset];
            return [self failFilter:why];
        }
        [table reloadData];
        ++_filterApplies;_filterMS=(CACurrentMediaTime()-start)*1000;
        _filterStatus=[NSString stringWithFormat:@"规则 %ld（%lu 字）：%lu 个置顶 + %lu 个",(long)index,(unsigned long)name.length,(unsigned long)top.count,(unsigned long)normal.count];
        return YES;
    } @catch(NSException *error) {
        [self rebuildWhole:manager table:table];
        _filterBroken=YES;_filterBrokenWhy=[@"筛选出错：" stringByAppendingString:error.reason?:error.name?:@"?"];
        return [self failFilter:_filterBrokenWhy];
    }
}
// A rebuild on another thread while filtered: that rebuild already left the
// whole list (it was not filtered); the grouping goes off for this run.
- (void)filterOffMain {
    if(atomic_load(&WXGFilterIndex)==0 && !WXGFilterGuarding)return;
    atomic_store(&WXGFilterIndex,0);
    id manager=WXGFilterManager;if(manager)[self restoreTopCount:manager];
    [WXGFilterTable?:_table reloadData];WXGFilterGuarding=NO;   // the arrays WeChat's next rebuild makes whole again
    _filterBroken=YES;_filterBrokenWhy=@"微信在后台线程重建会话列表，分组筛选已停用";_filterStatus=_filterBrokenWhy;
    if(_categories){_selected=-1;[_categories returnToIndex:-1];_titleSelected=0;[_titleBar returnToIndex:0];return;}
    NSInteger whole=[self wholeListIndex];NSArray *groups=WXGChatGroupList();
    if(whole>=0){_selected=whole;_selectedGroupID=groups[(NSUInteger)whole][@"id"];[_bar returnToIndex:whole];}else _selectedGroupID=nil;
}
- (BOOL)floatWanted {
    return WXGPluginEnabled() && WXGEffectiveRenderMode()>=2 && [WXGConfig.shared extraNumber:@"searchFloat"]>.5;
}
// Convert the reserved row using the table, whose viewport stays in the page
// even when UITableView detaches the offscreen header's subviews.
static CGRect WXGHomeFloatingFrame(UITableView *table,UIView *header,CGRect row,UIView *host) {
    CGRect content=CGRectOffset(row,header.frame.origin.x,header.frame.origin.y);
    CGRect view=[table convertRect:content toView:host];
    CGFloat viewport=CGRectGetMinY([table convertRect:table.bounds toView:host]);
    view.origin.y=WXGHomeFloatingRowY(viewport,WXGHomeConversationTop(table),header.frame.origin.y,row.origin.y,
        table.contentOffset.y,host.window.screen.scale);
    return view;
}
/* FIX113 T (user: "with the search bar / groups floating, why can the blur
   still touch it?"): floating is in the page itself, just above the list and
   the edge fade's blur bands (WXGEdgeFade puts them just above the list in
   the list's superview, and fades the list by a mask: anything in the list
   is faded and blurred near the top), at its place in the list or held below
   the title row: never under the fade or the blur, under everything WeChat
   lays over the page (its navigation bar, the + menu), and it moves with the
   page in a push / pop. */
static void WXGRaiseAboveList(UIView *view,UIView *host,UITableView *table) {
    static Class blur,cover;static dispatch_once_t once;
    dispatch_once(&once,^{blur=NSClassFromString(@"WXGEdgeBlurView");cover=NSClassFromString(@"WXGEdgeCoverView");});
    NSArray<UIView *> *subs=host.subviews;
    NSUInteger anchor=[subs indexOfObjectIdenticalTo:table];
    for(NSUInteger k=0;k<subs.count;k++) {
        UIView *v=subs[k];if(v==view)continue;
        if((blur && [v isKindOfClass:blur]) || (cover && [v isKindOfClass:cover]))anchor=anchor==NSNotFound?k:MAX(anchor,k);
    }
    NSUInteger mine=[subs indexOfObjectIdenticalTo:view];
    if(view.superview==host && mine!=NSNotFound && (anchor==NSNotFound || mine>anchor))return;
    [UIView performWithoutAnimation:^{
        if(anchor!=NSNotFound && subs[anchor]!=view)[host insertSubview:view aboveSubview:subs[anchor]];
        else [host addSubview:view];
    }];
}
// The segment bar floating: in the page (`host`, the list's superview) at its
// place in the list, held below the title row; nil: back in the list.
- (void)placeSegmentIn:(UIView *)host {
    UIControl<WXGListGroupControl> *bar=_bar;UIView *container=_container;UITableView *table=_table;
    if(!bar)return;
    CFTimeInterval t0=CACurrentMediaTime();
    if(!container) {
        if(_segmentFloating){bar.transform=CGAffineTransformIdentity;[bar removeFromSuperview];_segmentFloating=NO;_hasLastFloatY=NO;_floatBaseSize=CGSizeZero;++_floatMoves;}
        return;
    }
    BOOL live=table && table.tableHeaderView==container;
    CGRect inList=[self listFrame];
    if(!host || !live || !table.tableHeaderView || table.superview!=host) {
        if(_segmentFloating || bar.superview!=container || !CGAffineTransformIsIdentity(bar.transform) || !CGRectEqualToRect(bar.frame,inList)) {
            [UIView performWithoutAnimation:^{
                [CATransaction begin];[CATransaction setDisableActions:YES];
                if(bar.superview!=container)[container addSubview:bar];
                bar.transform=CGAffineTransformIdentity;
                bar.frame=inList;
                [CATransaction commit];
            }];
            if(_segmentFloating)++_floatMoves;
            _segmentFloating=NO;_hasLastFloatY=NO;_floatBaseSize=CGSizeZero;++_frameWrites;
        }
        return;
    }
    CGRect frame=WXGHomeFloatingFrame(table,container,inList,host);
    BOOL movedParent=bar.superview!=host;
    if(movedParent)++_floatMoves;
    WXGRaiseAboveList(bar,host,table);
    // R20: transform-only vertical tracking eliminates per-frame UIKit layout
    // churn on NewMainFrameViewController.view during pull-down / scroll-up.
    BOOL baseMatches=!movedParent && _segmentFloating &&
        CGSizeEqualToSize(_floatBaseSize,frame.size) && fabs(_floatBaseOrigin.x-frame.origin.x)<.5;
    if(baseMatches) {
        if(!_hasLastFloatY || fabs(_lastFloatY-frame.origin.y)>=.05) {
            CGFloat dy=frame.origin.y-_floatBaseOrigin.y;
            [CATransaction begin];[CATransaction setDisableActions:YES];
            bar.transform=CGAffineTransformMakeTranslation(0,dy);
            [CATransaction commit];
            _lastFloatY=frame.origin.y;_hasLastFloatY=YES;++_transformMoves;
        }
    }else {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];[CATransaction setDisableActions:YES];
            bar.transform=CGAffineTransformIdentity;
            bar.bounds=CGRectMake(0,0,frame.size.width,frame.size.height);
            bar.center=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
            [CATransaction commit];
        }];
        _floatBaseOrigin=frame.origin;_floatBaseSize=frame.size;_lastFloatY=frame.origin.y;_hasLastFloatY=YES;++_frameWrites;
    }
    _segmentFloating=YES;_placedViewport=table.bounds;_placedHeader=container.frame;_placedInset=table.adjustedContentInset.top;
    double ms=(CACurrentMediaTime()-t0)*1000.;
    if(ms>_maxPlaceMS)_maxPlaceMS=ms;
}
- (WXGFloatSlot *)floatSlotFor:(UIViewController *)page {
    if(!_floats){[self observe];_floats=[NSMapTable weakToStrongObjectsMapTable];}
    WXGFloatSlot *slot=[_floats objectForKey:page];
    if(!slot){slot=[WXGFloatSlot new];slot.page=page;[_floats setObject:slot forKey:page];}
    return slot;
}
- (void)unpin:(WXGFloatSlot *)slot {
    UIView *header=slot.ownedHeader;
    slot.ownedHeader=nil;slot.pinned=NO;slot.parked=NO;
    if(slot.clone){
        slot.clone.hidden=YES;slot.clone.surface.active=NO;
        if(header){slot.clone.surface.glass.backdropExclusions=@[];slot.clone.surface.glass.sourceView=nil;}
    }
    if(slot.states){[slot.states restore];slot.states=nil;}
    if(header)WXGSetSearchHeaderFloating(header,NO);
}
- (void)restoreFloats {
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects){[self unpin:slot];[slot.clone removeFromSuperview];slot.clone=nil;}
    [_floats removeAllObjects];
}
// Hide our material before UIKit snapshots the outgoing page. The old field
// stays concealed until Home is visible again, including behind translucent
// sheets. Only the specific home header already claimed by this slot is held.
- (void)coverHomeSearchFor:(UIViewController *)controller {
    if(!controller)return;
    if(controller==_page){[_pager cancel];_startupPending=NO;_startupUntil=0;}
    for(WXGFloatSlot *slot in _floats.objectEnumerator) {
        if(!slot.pinned)continue;
        for(UIViewController *c=slot.page;c;c=c.parentViewController) {
            if(c!=controller)continue;
            slot.parked=YES;slot.pinned=NO;
            slot.clone.hidden=YES;slot.clone.surface.active=NO;
            [slot.clone removeFromSuperview];
            break;
        }
    }
    if(_bar && !_segmentCovered && (_segmentFloating || [self floatWanted])) {
        for(UIViewController *c=_page;c;c=c.parentViewController)if(c==controller) {
            _segmentCovered=YES;_bar.hidden=YES;_bar.active=NO;_floatHost=nil;
            if(_segmentFloating)[self placeSegmentIn:nil];
            break;
        }
    }
}
// FIX114 F: the slot's field: WeChat's drawn box; not found now but seen
// before: that one (never the hidden text field under it); never seen: the
// field fieldRectIn: falls back to, counted as a miss. Another size of the
// box: its icon and text are copied again.
- (void)measureSlot:(WXGFloatSlot *)slot now:(CFTimeInterval)now {
    NSString *source=nil;CGRect f=[self fieldRectIn:slot.bar source:&source paint:NULL];slot.measured=now;
    if(!slot.nativeField || ![slot.nativeField isDescendantOfView:slot.bar]) {
        slot.nativeField=WXGInstalledSearchField(slot.bar);
    }
    BOOL fits=!CGRectIsEmpty(f) && CGRectContainsRect(CGRectInset(slot.bar.bounds,-1.,-1.),f);
    if(fits && [source isEqualToString:WXGDrawnBoxSource]) {
        if(slot.exact && !CGSizeEqualToSize(f.size,slot.lastExact.size))slot.lookCopied=NO;
        slot.field=f;slot.lastExact=f;slot.exact=YES;slot.misses=0;
    }else if(slot.exact)slot.field=slot.lastExact;
    else{slot.field=fits?f:CGRectNull;if(now-slot.since>=1)++slot.misses;}
}
// Some header layouts put WCSearchBar beside the UIKit bar. Only conceal
// an additional search host when it paints this same field.
static NSArray<UIView *> *WXGFloatPaintRoots(UIView *bar,UIView *header,CGRect field) {
    if(header==bar)return @[bar];
    Class wc=NSClassFromString(@"WCSearchBar");
    if(!wc)return @[bar];
    CGRect material=[bar convertRect:field toView:header];
    for(UIView *view in WXGViews(header,100)) {
        if((![view isKindOfClass:wc] && ![view isKindOfClass:UISearchBar.class]) || view.hidden ||
           WXGHomeSearchIsStaged(view) || [view isDescendantOfView:bar])continue;
        if([bar isDescendantOfView:view])return @[view];
        CGRect other=[view convertRect:view.bounds toView:header];
        CGRect intersection=CGRectIntersection(material,other);
        if(!CGRectIsEmpty(intersection) && intersection.size.width>=material.size.width*.8 &&
           intersection.size.height>=material.size.height*.8)return @[bar,view];
    }
    return @[bar];
}
- (void)claimSearchHeader:(UIView *)header slot:(WXGFloatSlot *)slot refreshRoots:(BOOL)refreshRoots {
    if(slot.ownedHeader!=header) {
        if(slot.ownedHeader)[self unpin:slot];
        for(WXGFloatSlot *other in _floats.objectEnumerator)
            if(other!=slot && other.ownedHeader==header)[self unpin:other];
        slot.ownedHeader=header;
        WXGSetSearchHeaderFloating(header,YES);
        slot.clone.surface.glass.sourceView=WXGContentSourceForView(slot.bar)?:slot.page.view;
        refreshRoots=YES;
    }
    WXGGlassView *glass=slot.clone.surface.glass;
    if(refreshRoots) {
        NSArray *roots=!slot.bar?@[]:CGRectIsNull(slot.field)?@[slot.bar]:WXGFloatPaintRoots(slot.bar,header,slot.field);
        for(UIView *old in glass.backdropExclusions)if(![roots containsObject:old])[slot.states restoreView:old];
        if(![glass.backdropExclusions isEqualToArray:roots])glass.backdropExclusions=roots;
    }
    if(!slot.states)slot.states=[WXGStateBag new];
    for(UIView *root in glass.backdropExclusions)if(![root.layer.mask.name isEqualToString:@"wxg.conceal"])[slot.states conceal:root];
}
// Only the visible Home page may own a floating copy of its table header.
- (void)floatNativeOn:(UIViewController *)page time:(CFTimeInterval)time homePanel:(CGFloat)homePanel {
    WXGFloatSlot *slot=[self floatSlotFor:page];
    UITableView *table=slot.table;UIView *bar=slot.bar;
    CFTimeInterval now=CACurrentMediaTime();
    BOOL grouped=page==_page && _groupHeader && _table.tableHeaderView==_groupHeader;
    if(grouped) {
        table=_table;bar=_searchBar;
    }else if((!table || !bar || ![table isDescendantOfView:page.view] || ![bar isDescendantOfView:table.tableHeaderView]) && now-slot.scanned>.5) {
        slot.scanned=now;table=[self tableIn:page.view];bar=[self searchBarIn:table.tableHeaderView];
    }
    if(WXGHomeTaskbarContains(bar)){[self unpin:slot];return;}
    if(bar!=slot.bar) {
        if(!grouped && slot.bar)[self unpin:slot];
        slot.nativeField=nil;slot.exact=NO;slot.misses=0;slot.since=now;slot.lookCopied=NO;slot.lookTries=0;slot.lookAgainAt=0;
        slot.measured=0;slot.field=CGRectNull;
    }
    slot.table=table;slot.bar=bar;
    if(bar) {
        BOOL due=slot.measured==0 || (slot.exact?now-slot.measured>(slot.pinned?1:.5):(now-slot.measured>(now-slot.since<1?.12:.5) && slot.misses<80));
        if(due)[self measureSlot:slot now:now];
    }
    UIView *header=table.tableHeaderView,*host=table.superview;
    BOOL live=bar && [bar isDescendantOfView:header] && !CGRectIsNull(slot.field);
    if(!table || !header || !host.window || (!live && (!grouped || CGRectIsEmpty(_searchRow))) || _nativeSearching){[self unpin:slot];return;}
    if(!grouped && header.bounds.size.height<CGRectGetMaxY([bar convertRect:slot.field toView:header])-.5){[self unpin:slot];return;}
    if(!grouped)for(UIView *v=bar;v && v!=table;v=v.superview)if(v.hidden){[self unpin:slot];return;}
    if(slot.editingField.isFirstResponder || page.navigationItem.searchController.isActive || slot.nativeField.isFirstResponder ||
       slot.nativeField.text.length || (!grouped && bar.alpha<.01 && !slot.pinned)){[self unpin:slot];return;}
    slot.editingField=nil;
    if(!slot.clone) {
        slot.clone=[[WXGFloatingSearch alloc] initWithFrame:CGRectZero];
        [slot.clone addTarget:self action:@selector(floatingTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    WXGFloatingSearch *clone=slot.clone;
    UIUserInterfaceStyle style=bar.traitCollection.userInterfaceStyle;
    if(bar && slot.lookCopied && style!=slot.lookStyle){slot.lookCopied=NO;slot.lookTries=0;slot.lookTried=0;slot.lookAgainAt=now+.5;}
    if(slot.lookAgainAt && now>=slot.lookAgainAt){slot.lookAgainAt=0;slot.lookCopied=NO;slot.lookTries=0;slot.lookTried=0;}
    if(bar && !slot.lookCopied && slot.exact && slot.lookTries<90 && (now-slot.lookTried>(now-slot.since<1?.12:.5))) {
        slot.lookTried=now;if(now-slot.since>=1)++slot.lookTries;
        if((slot.lookCopied=[clone copyLookOf:bar])){slot.lookStyle=style;slot.lookTries=0;}
    }
    if(!grouped && !slot.pinned && !slot.exact && now-slot.since<1)return;
    UIWindow *window=host.window;CGFloat scale=window.screen.scale;
    CGRect frame,natural;
    bool atNative=false;
    if(grouped) {
        frame=WXGHomeFloatingFrame(table,header,_searchRow,host);
        natural=[table convertRect:CGRectOffset(_searchRow,header.frame.origin.x,header.frame.origin.y) toView:host];
        atNative=live && fabs(frame.origin.y-natural.origin.y)<=.5;
    }else {
        CGRect inNative=[bar convertRect:slot.field toView:header];
        CGRect custom=WXGHomeConfiguredRow(inNative,header.bounds.size.width,NO);
        natural=WXGHomeRect(header,custom,host,NO);frame=natural;
        CGFloat viewport=CGRectGetMinY([table convertRect:table.bounds toView:host]);
        UINavigationBar *nav=page.navigationController.navigationBar;
        BOOL expectsNav=nav && !nav.hidden && !page.navigationController.navigationBarHidden;
        CGFloat chrome=expectsNav && nav.window==window?CGRectGetMaxY([nav convertRect:nav.bounds toView:host]):NAN;
        CGFloat row=[WXGIntegrationHost.shared homeRowBottomForPage:page window:window];
        if(isfinite(row)) {
            CGFloat y=[window convertPoint:CGPointMake(0,row) toView:host].y;chrome=isfinite(chrome)?MAX(chrome,y):y;expectsNav=YES;
        }
        CGFloat safe=[window convertPoint:CGPointMake(0,window.safeAreaInsets.top) toView:host].y;
        CGFloat inset=WXGHomeConversationTop(table);
        CGFloat pin=WXGFloatSearchPlacement(-CGFLOAT_MAX,custom.origin.y-header.bounds.origin.y,viewport,inset,
            expectsNav,chrome,safe,&atNative);
        if(!isfinite(pin)){[self unpin:slot];return;}
        CGFloat rest=WXGHomeFloatingRowY(viewport,inset,header.frame.origin.y,custom.origin.y-header.bounds.origin.y,-inset,scale);
        frame.origin.y=MAX(rest,WXGHomePixel(pin,scale))+WXGHomePullTranslation(table.contentOffset.y,inset,scale);
        atNative=fabs(frame.origin.y-natural.origin.y)<=.5;
    }
    frame.origin.x=WXGHomePixel(frame.origin.x,scale);
    frame.origin.y=WXGHomePixel(frame.origin.y,scale);
    frame.size.width=WXGHomePixel(frame.size.width,scale);
    frame.size.height=WXGHomePixel(frame.size.height,scale);
    slot.naturalFrame=natural;
    CGRect nativeField=live && bar.window==window?WXGHomeRect(bar,slot.field,host,NO):CGRectNull;
    clone.passThrough=atNative && !CGRectIsNull(nativeField) && CGRectContainsRect(CGRectInset(nativeField,-.5,-.5),frame);
    WXGRaiseAboveList(clone,host,table);
    BOOL claim=!slot.pinned || slot.measured==now || slot.ownedHeader!=header;
    CGPoint center=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    BOOL resize=!CGSizeEqualToSize(clone.bounds.size,frame.size),move=!CGPointEqualToPoint(clone.center,center);
    if(claim || resize || move || !clone.surface.active || clone.hidden) {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];[CATransaction setDisableActions:YES];
            if(claim)[self claimSearchHeader:header slot:slot refreshRoots:slot.measured==now];
            if(resize)clone.bounds=(CGRect){CGPointZero,frame.size};
            if(move)clone.center=center;
            if(!clone.surface.active)clone.surface.active=YES;
            if(clone.hidden)clone.hidden=NO;
            [CATransaction commit];
        }];
    }
    if(!slot.pinned){slot.pinned=YES;slot.parked=NO;++slot.pins;}
    if(time>0)[clone.surface tick:time];
}
// The floating capsule tapped (held below the title row: WeChat's bar has
// scrolled away). FIX114 M (user: straight to the search page, nothing in
// between): WeChat's own search entry when the page has one (the home page's
// search button: the search page opens at once); else as before: the list
// back to its top, then WeChat's own field focused.
- (void)floatingTapped:(WXGFloatingSearch *)clone {
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects) {
        if(slot.clone!=clone)continue;
        ++slot.taps;UITableView *table=slot.table;UIView *bar=slot.bar,*header=table.tableHeaderView;
        [self coverHomeSearchFor:slot.page];
        if([WXGIntegrationHost.shared openWeChatSearchOn:slot.page]){++_directSearches;break;}
        [self unpin:slot];
        if(table && header && !WXGHomeListInNativePull(table))[table setContentOffset:CGPointMake(table.contentOffset.x,CGRectGetMinY(header.frame)-WXGHomeListTop(table)) animated:NO];
        dispatch_async(dispatch_get_main_queue(),^{
            UITextField *field=[bar isKindOfClass:UISearchBar.class]?((UISearchBar *)bar).searchTextField:nil;
            if(!field)for(UIView *v in WXGViews(bar,160))if([v isKindOfClass:UITextField.class] && !v.hidden){field=(UITextField *)v;break;}
            [field becomeFirstResponder];
        });
        break;
    }
}
// FIX113 O: every frame of the host (before Core Animation's commit, so the
// floating views move with the list in the same frame). FIX113 T: in the
// page itself, so also through a push / pop (the page carries them).
- (void)hostTick:(CFTimeInterval)time page:(UIViewController *)leaf overlay:(UIView *)overlay transitioning:(BOOL)transitioning transitionInvolvesHome:(BOOL)transitionInvolvesHome homePanel:(CGFloat)homePanel rowOffset:(CGFloat)rowOffset {
    BOOL floatOn=[self floatWanted];
    UITableView *table=_table;UIView *host=table.superview;
    BOOL nativePull=WXGHomeListInNativePull(table);
    if(_bar.window && leaf==_page && !transitioning && (table.dragging || table.decelerating)) {
        if(_lastScrollFrame>0 && time>_lastScrollFrame) {
            double interval=(time-_lastScrollFrame)*1000;
            _maxScrollFrameMS=MAX(_maxScrollFrameMS,interval);
            if(interval>33.5)++_slowScrollFrames;
        }
        _lastScrollFrame=time;
    }else _lastScrollFrame=0;
    if(_pager.busy)[_pager checkGestureOnHome:leaf==_page && !transitioning && !_nativeSearching && !nativePull];
    if(_categories && leaf==_page && !transitioning && !_nativeSearching && !_pager.busy && !_bookmarkedHome &&
       !nativePull && !table.tracking && !table.dragging && !table.decelerating && table.window)
        [self updateCategoriesAt:time];
    BOOL returning=[self showingBookmarkedHome];
    BOOL homeVisible=returning || (!transitioning && (floatOn || _segmentCovered) && WXGHomeSearchExposed(leaf));
    BOOL onPage=returning || leaf==_page;
    BOOL exposed=floatOn && homeVisible;
    if((_startupPending || _startupUntil) && (nativePull || table.tracking || table.dragging || table.decelerating ||
       (_lastTickPage==_page && (leaf!=_page || transitioning)))) {
        _startupPending=NO;_startupUntil=0;
    }
    if(_segmentFloating && (!homeVisible || !onPage))[self coverHomeSearchFor:_page];
    if(_segmentCovered && homeVisible && onPage) {
        _segmentCovered=NO;
        _bar.hidden=_nativeSearching;_bar.active=!_nativeSearching;
    }
    if(_remountAfterScroll && !nativePull && !_nativeSearching && leaf==_page && !transitioning && !table.tracking && !table.dragging && !table.decelerating) {
        _remountAfterScroll=NO;
        UIView *pending=_groupHeader.pendingNativeHeader;
        if(pending && table.tableHeaderView==_groupHeader)[self reuseRowsForTable:table nativeHeader:pending];
        [self updateOnPage:leaf];
    }
    if(leaf==_page && _returnReady) {
        if(nativePull || table.tracking || table.dragging || table.decelerating){_returnReady=NO;_returnAppearing=NO;_bookmarkedHome=nil;}
        else if(!transitioning)[self restoreChatPositionIfReady];
    }
    UIView *floatHost=exposed && host.window && onPage?host:nil;
    if(returning && ![floatHost isDescendantOfView:_page.viewIfLoaded])floatHost=nil;
    // FIX114 E / F: arriving on the home page: where the bar / capsule is drawn, each tick, ~1 s.
    static Class homeClass;static dispatch_once_t homeOnce;dispatch_once(&homeOnce,^{homeClass=NSClassFromString(@"NewMainFrameViewController");});
    BOOL arrived=leaf && _lastTickPage!=leaf;
    if(arrived && homeClass && [leaf isKindOfClass:homeClass]){_returnedAt=time;_returnTrace=[NSMutableArray array];}
    if(arrived) {
        _fieldRechecks=0;
        if(leaf==_page && table.tableHeaderView==_groupHeader && _groupHeader)[self homeTableInsetChanged:table];
    }
    _lastTickPage=leaf;
    // FIX114 F: measured before WeChat laid out its box (the field's 32.7 pt
    // instead): measured again twice a second, 6 times per arrival / bar, not
    // while the page slides.
    if(_bar.superview && _searchBar && leaf==_page && !nativePull && !transitioning && !table.tracking && !table.decelerating && _fieldRechecks<6 && ![_fieldSource isEqualToString:WXGDrawnBoxSource] && time-_fieldRecheck>.5) {
        _fieldRecheck=time;++_fieldRechecks;
        if(!CGRectIsNull(WXGVisibleSearchBox(_searchBar))){_lastMeasuredBarSize=CGSizeZero;[self searchBarLaidOut:_searchBar];}
    }
    _lastPanel=homePanel;
    BOOL replace=onPage && _groupHeader.nativeCanvas.hidden;
    UIViewController *floatPage=returning?_page:leaf;
    WXGFloatSlot *activeSlot=exposed?[_floats objectForKey:floatPage]:nil;
    if(replace && activeSlot.ownedHeader)[self unpin:activeSlot];
    if(exposed && !replace && (!returning || floatHost))[self floatNativeOn:floatPage time:time homePanel:homePanel];
    _floatHost=(_groupHeader && table.tableHeaderView==_groupHeader)?floatHost:nil;
    if(_bar && _bar.superview) {
        if((_startupPending || _startupUntil) && !transitioning && leaf==_page) {
            if(_groupHeader.leading!=[self leadingForHeader:_groupHeader table:table])[self searchBarLaidOut:_searchBar];
            [self revealInitialRows:table];
        }
        [self placeSegmentIn:_floatHost];
    }
    [self followTitleBarInOverlay:overlay page:leaf transitioning:transitioning transitionInvolvesHome:transitionInvolvesHome homePanel:homePanel rowOffset:rowOffset];
    if(_bar.window && _returnTrace && time-_returnedAt<1.2 && _returnTrace.count<90) {
        CGRect r=[_bar convertRect:_bar.bounds toView:nil];UIView *field=_searchBar;
        NSString *line=[NSString stringWithFormat:@"y%.1f h%.1f %@%@ field y%.1f",r.origin.y+WXGCanvasPaddingY,r.size.height-2*WXGCanvasPaddingY,
            _segmentFloating?@"float":@"list",transitioning?@" T":@"",field.window?[field convertRect:field.bounds toView:nil].origin.y:-1];
        if(![_returnTrace.lastObject hasSuffix:line])   // only what changed
            [_returnTrace addObject:[NSString stringWithFormat:@"%.3f %@",time-_returnedAt,line]];
    }
    // FIX114 F: the floating capsule (分组栏 off) and WeChat's drawn box, from
    // the slide back on: “capsule hidden” = WeChat's own bar shows there.
    if(_returnTrace && time-_returnedAt<1.2 && _returnTrace.count<90 && time-_capsuleTraceAt>=.03 && homeClass && [leaf isKindOfClass:homeClass] && !(_bar && _page==leaf)) {
        _capsuleTraceAt=time;
        WXGFloatSlot *slot=[_floats objectForKey:leaf];WXGFloatingSearch *clone=slot.clone;UIView *bar=slot.bar;
        if(clone.window || bar.window) {
            CGRect c=clone.window && !clone.hidden?[clone convertRect:clone.bounds toView:nil]:CGRectNull;
            CGRect b=bar.window?WXGVisibleSearchBox(bar):CGRectNull;if(!CGRectIsNull(b))b=[bar convertRect:b toView:nil];
            NSString *line=[NSString stringWithFormat:@"capsule %@ box %@%@",CGRectIsNull(c)?@"hidden":[NSString stringWithFormat:@"y%.1f h%.1f",c.origin.y,c.size.height],
                CGRectIsNull(b)?@"-":[NSString stringWithFormat:@"y%.1f h%.1f",b.origin.y,b.size.height],transitioning?@" T":@""];
            if(![_returnTrace.lastObject hasSuffix:line])[_returnTrace addObject:[NSString stringWithFormat:@"%.3f %@",time-_returnedAt,line]];
        }
    }
    if((leaf && leaf==_page) || (transitioning && transitionInvolvesHome))[self traceHomeFrame:time transitioning:transitioning panel:homePanel];
    else _motionLastTime=0;
    if(!floatOn){if(_floats.count)[self restoreFloats];return;}
    for(WXGFloatSlot *slot in _floats.objectEnumerator) {
        if(slot.pinned && (!exposed || slot.page!=floatPage))[self coverHomeSearchFor:slot.page];
    }

}
- (void)traceHomeEvent:(NSString *)event before:(CGFloat)before after:(CGFloat)after {
    if(!_motionEvents)_motionEvents=[NSMutableArray array];
    if(_motionEvents.count==128)[_motionEvents removeObjectAtIndex:0];
    NSMutableDictionary *sample=[@{@"s":@(WXGSecondsSinceLoad()),@"event":event,@"before":@(before),@"after":@(after),
        @"inset":@(_table.adjustedContentInset.top),@"rawTop":@(_table.contentInset.top),
        @"automaticTop":@(_table.adjustedContentInset.top-_table.contentInset.top),@"header":@(_groupHeader.bounds.size.height),
        @"insetPolicy":@(_table.contentInsetAdjustmentBehavior),
        @"depthSaved":@(_savedDepth),@"group":@(_selected)} mutableCopy];
    if([event isEqual:@"nativeSearchAssigned"] || [event isEqual:@"waitingForSearchArtwork"]) {
        UIView *shown=_groupHeader.nativeHeader;
        sample[@"hasWCSearchBox"]=@(!CGRectIsNull(WXGVisibleSearchBox(shown)));
        sample[@"systemFieldInstalled"]=@(WXGInstalledSearchField(shown)!=nil);
        sample[@"replacementWaiting"]=@(_groupHeader.pendingNativeHeader!=nil);
    }
    [_motionEvents addObject:sample];
}
// Full captures include the presentation tree so navigation alpha and geometry
// can be distinguished from the model values read on normal, lightweight captures.
static float WXGHomeTraceY(UIView *view,CGFloat y,UIWindow *window,BOOL full) {
    CGPoint point=CGPointMake(CGRectGetMidX(view.bounds),y);
    if(full) {
        CALayer *from=view.layer.presentationLayer,*to=window.layer.presentationLayer;
        if(from && to)return [from convertPoint:point toLayer:to].y;
    }
    return [view convertPoint:point toView:window].y;
}
// Scalars only on the display link. Boxing takes place once at export.
- (void)traceHomeFrame:(CFTimeInterval)time transitioning:(BOOL)transitioning panel:(CGFloat)panel {
    UITableView *table=_table;UIWindow *window=table.window;
    if(!window || (!_bar && !_titleBar)){_motionLastTime=_motionLastCallback=0;return;}
    NSUInteger revision=WXGConfigRevision();
    if(!_motionBuffer || revision!=_motionRevision) {
        NSUInteger cap=[WXGConfig.shared extraNumber:@"homeMotionTrace"]>.5?14400:960;
        if(_motionBuffer.length!=cap*sizeof(WXGHomeFrame)) {
            _motionBuffer=[NSMutableData dataWithLength:cap*sizeof(WXGHomeFrame)];
            _motionWrite=_motionCount=0;_motionLastTime=_motionLastCallback=0;
        }
        _motionRevision=revision;
    }
    NSUInteger cap=_motionBuffer.length/sizeof(WXGHomeFrame);
    BOOL full=cap==14400;
    if(full!=WXGHomeWritesEnabled || (WXGHomeWritesEnabled && WXGHomeWatchedTable!=table))
        WXGObserveHomeOffsets(table,full);
    if(full){WXGHomeWatchedNavigation=_page.navigationController.navigationBar;WXGObserveHomeScrollDelegate(table);}
    BOOL panelCapture=full && (panel>.001 || WXGHomeListInNativePull(table));
    BOOL presentation=full && time>=_nextPresentationTrace &&
        (transitioning || table.tracking || table.dragging || table.decelerating || panelCapture);
    if(presentation)_nextPresentationTrace=time+1./30.;
    unsigned flags=(presentation<<9) | table.tracking | (table.dragging<<1) | (table.decelerating<<2) | (transitioning<<3) |
        (_segmentFloating<<4) | (_groupHeader.nativeCanvas.hidden<<5) | (_returnReady<<6) | (_nativeSearching<<7) |
        ((_groupHeader && table.tableHeaderView==_groupHeader)<<8);
    float dt=_motionLastTime?(float)((time-_motionLastTime)*1000):0;_motionLastTime=time;
    WXGFloatSlot *slot=[_floats objectForKey:_page];
    CFTimeInterval now=WXGSecondsSinceLoad();
    WXGHomeFrame frame={.t=(float)now,.dt=dt,.offset=(float)table.contentOffset.y,
        .work=WXGHomeWork,.callbackInterval=_motionLastCallback?(now-_motionLastCallback)*1000.:0,
        .inset=(float)table.adjustedContentInset.top,.content=(float)table.contentSize.height,
        .header=(float)table.tableHeaderView.frame.size.height,.leading=(float)_groupHeader.leading,
        .chrome=(float)[WXGIntegrationHost.shared homeRowBottomForPage:_page window:window],
        .search=-1,.group=-1,.listLens=_bar?(float)_bar.currentLensX:-1,.titleLens=_titleBar?(float)_titleBar.currentLensX:-1,
        .rawInset=table.contentInset.top,.systemInset=table.adjustedContentInset.top-table.contentInset.top,
        .restInset=_groupHeader.restInset,.conversationTop=WXGHomeConversationTop(table),.layoutMS=WXGHomeTableLayoutMS,.headerWorkMS=WXGHomeHeaderWorkMS,
        .titleBottom=-1,.titleOpacity=-1,.searchOpacity=-1,.groupOpacity=-1,.panel=(float)panel,.flags=flags};
    _motionLastCallback=now;WXGHomeTableLayoutMS=WXGHomeHeaderWorkMS=0;WXGHomeWork=(WXGHomeFrameWork){0};
    if(panelCapture && presentation)frame.panelGeometry=WXGReadHomePanelGeometry(_page);
    if(!isfinite(frame.chrome))frame.chrome=-1;
    if(_searchBar.window==window && !_searchBar.hidden && _groupHeader.window==window && !_groupHeader.nativeCanvas.hidden && !_nativeSearching) {
        frame.search=WXGHomeTraceY(_groupHeader,_searchRow.origin.y,window,presentation);
        frame.searchOpacity=presentation?WXGPresentedChainAlpha(_searchBar,window):_searchBar.alpha;
    }
    if(slot.pinned && !slot.clone.hidden && slot.clone.window==window) {
        frame.search=WXGHomeTraceY(slot.clone,CGRectGetMinY(slot.clone.bounds),window,presentation);
        frame.searchOpacity=presentation?WXGPresentedChainAlpha(slot.clone,window):slot.clone.alpha;
    }
    if(_bar.window==window && !_bar.hidden) {
        frame.group=WXGHomeTraceY(_bar,WXGCanvasPaddingY,window,presentation);
        frame.groupOpacity=presentation?WXGPresentedChainAlpha(_bar,window):_bar.alpha;
    }
    if(_titleBar.window==window && !_titleBar.hidden) {
        frame.titleBottom=WXGHomeTraceY(_titleBar,CGRectGetMaxY(_titleBar.bounds)-WXGCanvasPaddingY,window,presentation);
        frame.titleOpacity=presentation?WXGPresentedChainAlpha(_titleBar,window):_titleBar.alpha;
    }
    if(cap==960 && _motionCount && dt>0 && dt<25 && frame.offset==_lastMotion.offset && frame.inset==_lastMotion.inset &&
       frame.header==_lastMotion.header && frame.leading==_lastMotion.leading && frame.content==_lastMotion.content &&
       frame.rawInset==_lastMotion.rawInset && frame.systemInset==_lastMotion.systemInset &&
       frame.flags==_lastMotion.flags && frame.chrome==_lastMotion.chrome && frame.panel==_lastMotion.panel &&
       frame.listLens==_lastMotion.listLens && frame.titleLens==_lastMotion.titleLens &&
       frame.search==_lastMotion.search && frame.group==_lastMotion.group && frame.titleBottom==_lastMotion.titleBottom &&
       frame.titleOpacity==_lastMotion.titleOpacity && frame.searchOpacity==_lastMotion.searchOpacity && frame.groupOpacity==_lastMotion.groupOpacity)return;
    ((WXGHomeFrame *)_motionBuffer.mutableBytes)[_motionWrite%cap]=frame;
    ++_motionWrite;_motionCount=MIN(cap,_motionCount+1);_lastMotion=frame;
}
- (NSDictionary *)homeMotionEvidence {
    NSUInteger cap=_motionBuffer.length/sizeof(WXGHomeFrame);
    const WXGHomeFrame *ring=_motionBuffer.bytes;
    NSMutableArray *frames=[NSMutableArray arrayWithCapacity:_motionCount];
    NSMutableArray *panelSamples=[NSMutableArray array];
    for(NSUInteger i=0;i<_motionCount;i++) {
        WXGHomeFrame f=ring[(_motionWrite-_motionCount+i)%cap];
        [frames addObject:@[@(f.t),@(f.dt),@(f.offset),@(f.inset),@(f.content),@(f.header),@(f.leading),@(f.chrome),
                            @(f.search),@(f.group),@(f.listLens),@(f.titleLens),@(f.panel),@(f.flags),
                            @(f.titleBottom),@(f.titleOpacity),@(f.searchOpacity),@(f.groupOpacity),@(f.rawInset),@(f.systemInset),@(f.restInset),@(f.conversationTop),@(f.layoutMS),@(f.headerWorkMS),
                            @(f.callbackInterval),@(f.work.layouts),@(f.work.cells),@(f.work.cellMS),@(f.work.reloads),@(f.work.reloadMS),@(f.work.navigations),@(f.work.navigationMS),@(f.work.navigationBuildMS),@(f.work.navigationTraceMS)]];
        WXGHomePanelGeometry p=f.panelGeometry;
        if(p.windowWidth>0)[panelSamples addObject:@[@(f.t),@(f.offset),@(p.windowWidth),@(p.headerBottom),@(p.sectionBoundsWidth),@(p.sectionScreenWidth),@(p.cellBoundsWidth),@(p.cellScreenWidth),@(p.iconBoundsWidth),@(p.iconScreenWidth)]];
    }
    return @{@"columns":@[@"seconds",@"intervalMS",@"offsetY",@"adjustedTop",@"contentHeight",@"headerHeight",@"leading",
                         @"titleRowBottom",@"searchWindowY",@"groupWindowY",@"groupLensX",@"titleLensX",@"pullPanel",@"flags",
                         @"visibleTitleBottomY",@"titleAlpha",@"searchAlpha",@"groupAlpha",@"rawContentTop",@"automaticTop",@"restTop",@"conversationTop",@"tableLayoutMS",@"nativeHeaderAssignmentMS",
                         @"callbackIntervalMS",@"tableLayouts",@"cellsConfigured",@"cellConfigurationMS",@"tableReloads",@"tableReloadMS",@"navigationLayouts",@"navigationLayoutMS",@"pluginNavigationBuildMS",@"navigationTraceMS"],
             @"panelGeometry":@{@"columns":@[@"seconds",@"offsetY",@"windowWidth",@"headerScreenBottom",@"gridBoundsWidth",@"gridScreenWidth",@"cellBoundsWidth",@"cellScreenWidth",@"iconBoundsWidth",@"iconScreenWidth"],@"samples":panelSamples},
             @"flagBits":@[@"tracking",@"dragging",@"decelerating",@"transition",@"floating",@"replaceSearch",@"pendingReturn",@"nativeSearch",@"groupHeaderInstalled",@"presentationGeometry"],
             @"full":@(cap==14400),@"capacity":@(cap),@"written":@(_motionWrite),@"frames":frames,@"events":_motionEvents.copy?:@[],
             @"offsetWrites":WXGHomeOffsetEvidence(),@"insetWrites":WXGHomeInsetEvidence(),@"headerReuses":@(WXGHomeHeaderReuses),@"restInsetAttempts":@(_groupHeader.insetAttempts),@"insetRepairs":@(_groupHeader.insetRepairs),
             @"insetPolicy":@(_table.contentInsetAdjustmentBehavior),@"rawInsets":NSStringFromUIEdgeInsets(_table.contentInset),
             @"adjustedInsets":NSStringFromUIEdgeInsets(_table.adjustedContentInset),@"deferredSearchAssignments":@(_groupHeader.deferredSearchAssignments),@"returnCorrections":@(_returnRestores)};
}
- (void)suspendFloating {
    [_pager cancel];
    for(WXGFloatSlot *slot in _floats.objectEnumerator)[self coverHomeSearchFor:slot.page];
    if(_segmentFloating)[self coverHomeSearchFor:_page];
    [self hideTitleBar];
}
- (void)restoreAll {if(WXGHomeWritesEnabled)WXGObserveHomeOffsets(nil,NO);[self restoreFloats];[self releaseTitleBar];[self restore];}
- (void)restore {
    BOOL hadList=_bar!=nil;
    if(_categories)[self discardListForm];
    if(hadList || ![self titleModeWanted]){_bookmarkedHome=nil;_returnReady=NO;_returnAppearing=NO;}
    _remountAfterScroll=NO;_leadingTable=nil;
    if(![self titleModeWanted] && atomic_load(&WXGFilterIndex)>0)[self applyRule:0 members:nil name:nil];
    _selected=0;_selectedGroupID=nil;
    if(![self titleModeWanted]){WXGFilterWatching=NO;WXGFilterSnapshot=nil;}
    [self restoreResizedHeader];
    _hasLastFloatY=NO;_floatBaseSize=CGSizeZero;_lastMeasuredBarSize=CGSizeZero;_startupPending=NO;_startupUntil=0;
    if(!hadList)return;
    _segmentFloating=NO;_segmentCovered=NO;
    _bar.transform=CGAffineTransformIdentity;
    [_bar removeFromSuperview];_bar.active=NO;_bar=nil;
    _searchBar=nil;_container=nil;_nativeSearching=NO;
    ++_restores;_status=@"已恢复微信的搜索栏";
}
- (NSDictionary *)evidence {
    UITableView *table=_table;
    if(table && !table.tracking && !table.dragging && !table.decelerating && !_page.transitionCoordinator &&
       [self wanted] && (!_probe || CACurrentMediaTime()-_probeAt>5))[self takeProbe];
    NSMutableArray *floats=[NSMutableArray array];
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects) {
        NSMutableArray *roots=[NSMutableArray array];
        for(UIView *root in slot.clone.surface.glass.backdropExclusions)[roots addObject:@{
            @"class":NSStringFromClass(root.class),@"concealed":@([root.layer.mask.name isEqualToString:@"wxg.conceal"])}];
        [floats addObject:@{@"page":slot.page?NSStringFromClass(slot.page.class):@"",@"bar":slot.bar?NSStringFromClass(slot.bar.class):@"",
                            @"field":NSStringFromCGRect(slot.field),@"pinned":@(slot.pinned),@"pins":@(slot.pins),@"taps":@(slot.taps),
                            @"naturalInListHost":slot.pinned?NSStringFromCGRect(slot.naturalFrame):@"",@"sourceRoots":roots,
                            @"parked":@(slot.parked),@"ownsHeader":@(slot.ownedHeader!=nil),@"clone":slot.clone?NSStringFromCGRect(slot.clone.frame):@"",
                            @"passThrough":@(slot.clone.passThrough),@"directSearches":@(_directSearches)}];
    }
    UIView *bar=_searchBar;WXGConfig *cfg=WXGConfig.shared;
    return @{@"switch":@([cfg extraNumber:@"chatSegments"]>.5),@"wanted":@([self wanted]),@"status":_status?:@"",
             @"listForm":_categories?@"categories":@"custom",@"pageTransition":_pager?(_pager.paging?@"paging":@"fade"):@"",
             @"mounted":@(_bar.superview!=nil),@"container":_container?NSStringFromClass(_container.class):@"",
             @"searchBar":bar?[NSString stringWithFormat:@"%@ %@ alpha %.2f",NSStringFromClass(bar.class),NSStringFromCGRect(bar.frame),bar.alpha]:@"",
             @"field":NSStringFromCGRect(_fieldRect),@"fieldSource":_fieldSource?:@"",@"colors":_colorSource?:@"",
             @"counts":@{@"mounts":@(_mounts),@"moves":@(_moves),@"switches":@(_switches),@"restores":@(_restores),@"nativeSearches":@(_nativeSearches)},
             @"stutter":@{@"fieldScans":@(_fieldScans),@"headerWrites":@(_headerWrites),@"startupReveals":@(_startupReveals),@"offsetBefore":@(_startupBefore),@"offsetAfter":@(_startupAfter),@"transformMoves":@(_transformMoves),@"frameWrites":@(_frameWrites),@"skippedLaidOuts":@(_skippedLaidOuts),@"maxPlaceMS":@(round(_maxPlaceMS*100)/100),@"maxScrollFrameMS":@(round(_maxScrollFrameMS*10)/10),@"scrollFramesOver33ms":@(_slowScrollFrames)},
             @"customSearch":@{@"widthPct":@(cfg.homeSearchWidthPct),@"height":@(cfg.homeSearchHeight),@"topGap":@(cfg.homeSearchTopGap),
                               @"groupWidthPct":@([cfg extraNumber:@"homeGroupWidthPct"]),@"groupHeight":@([cfg extraNumber:@"homeGroupHeight"]),@"leading":@(_groupHeader.leading),@"nativeHeaderH":@(_nativeHeaderHeight),@"resizedHeaderH":@(_groupHeader.frame.size.height)},
             @"titleBar":@{@"wanted":@([self titleModeWanted]),@"mounted":@(_titleBar.superview!=nil),@"selected":@(_titleSelected),
                           @"navTitleInWindow":@(_titleNavView.window!=nil),
                           @"pullTitleInWindow":@(_titlePullView.window!=nil),
                           @"alpha":@(_titleBar?_titleBar.alpha:0),@"hidden":@(_titleBar?_titleBar.hidden:YES),
                           @"frame":_titleBar?NSStringFromCGRect(_titleBar.frame):@"",@"trace":_titleTrace?:@[],@"bar":_titleBar?[_titleBar evidence]:@{}},
             @"selected":@(_selected),@"groups":[self groupsEvidence],@"switchLog":_switchLog?:@[],
             @"bar":_bar?[_bar evidence]:@{},@"chatList":_probe?:@{},
             @"float":@{@"switch":@([cfg extraNumber:@"searchFloat"]>.5),@"segmentFloating":@(_segmentFloating),@"moves":@(_floatMoves),@"native":floats},
             @"gap":@{@"searchToGroup":@(_groupGap),@"groupToList":@(_nativeBottomGap)},@"returnTrace":_returnTrace?:@[],
             @"searchBarRehides":@0,@"commitPlacements":@(_commitPlacements),
             @"sessionFilter":[self filterEvidence]};
}
// FIX113 Q: whether the grouping can work here and what it did (counts only).
- (NSArray *)groupsEvidence {
    if(_categories)return _categories.titles;
    NSMutableArray *out=[NSMutableArray array];   // rules and member counts only (no names)
    for(NSDictionary *group in WXGChatGroupList())[out addObject:[NSString stringWithFormat:@"rule %@ members %lu name %lu字",group[@"rule"],(unsigned long)[group[@"members"] count],(unsigned long)[group[@"name"] length]]];
    return out;
}
- (NSDictionary *)filterEvidence {
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    out[@"index"]=@(atomic_load(&WXGFilterIndex));out[@"hooked"]=@(WXGFilterHookInstalled);out[@"broken"]=@(_filterBroken);
    out[@"status"]=_filterStatus?:@"还没有切过分组";out[@"applies"]=@(_filterApplies);out[@"fails"]=@(_filterFails);
    out[@"ms"]=@(round(_filterMS*10)/10);out[@"rowOffset"]=@(_rowOffset);
    out[@"rebuilds"]=@(atomic_load(&WXGFilterRebuilds));out[@"filtered"]=@(atomic_load(&WXGFilterFiltered));
    out[@"offMainRebuilds"]=@(atomic_load(&WXGFilterOffMain));out[@"intercepts"]=@(atomic_load(&WXGFilterIntercepts));
    out[@"tableGuards"]=WXGFilterTableClass?NSStringFromClass(WXGFilterTableClass):@"";if(_filterBrokenWhy)out[@"brokenWhy"]=_filterBrokenWhy;
    @synchronized(WXGFilterLock()){if(WXGFilterLast)out[@"last"]=WXGFilterLast;}
    UITableView *table=_table;UIViewController *page=_page;
    if(table && page) {
        @try {
            id manager=WXGHomeSessionManager(page,table);
            out[@"manager"]=manager?NSStringFromClass(object_getClass(manager)):@"none";
            out[@"managerPath"]=WXGManagerPath?:@"";
            if(WXGNameProbe)out[@"memberNames"]=WXGNameProbe;
            out[@"snapshot"]=@(WXGFilterSnapshot.count);
            // FIX113 R: what holds the list's data, in case it is not these arrays (types and counts only).
            if(manager) {
                out[@"managerIvars"]=WXGProbeIvars(manager,60);
                out[@"managerMethods"]=WXGProbeMethods(object_getClass(manager),@[@"ession",@"rebuild",@"reload",@"delegate"],60);
            }
            for(Class cls=object_getClass(page);cls && cls!=UIViewController.class;cls=class_getSuperclass(cls)) {
                Ivar ivar=NULL;unsigned int n=0;Ivar *list=class_copyIvarList(cls,&n);   // declared by this class
                for(unsigned int k=0;k<n;k++)if(!strcmp(ivar_getName(list[k])?:"","m_mainFrameLogicController")){ivar=list[k];break;}
                free(list);if(!ivar)continue;
                void *raw=WXGProbeRaw(page,cls,ivar);
                if(WXGProbeSafe(raw) && (intptr_t)raw>0) {
                    __unsafe_unretained id logic=(__bridge id)raw;
                    out[@"logicIvars"]=WXGProbeIvars(logic,70);
                    out[@"logicMethods"]=WXGProbeMethods(object_getClass(logic),@[@"ession",@"cellData",@"count",@"reload",@"filter"],70);
                }
                break;
            }
            out[@"api"]=WXGSessionAPIMissing(manager)?:@"ok";
            NSArray *top=manager?WXGSessionGetObject(manager,@"topSessions"):nil,*normal=manager?WXGSessionGetObject(manager,@"normalSessions"):nil;
            if([top isKindOfClass:NSArray.class] && [normal isKindOfClass:NSArray.class]) {
                NSInteger kinds[4]={0},unread=0,named=0;NSMutableSet *classes=[NSMutableSet set];
                for(NSArray *list in @[top,normal])for(id session in list) {
                    if(classes.count<4)[classes addObject:NSStringFromClass(object_getClass(session))];
                    NSString *name=WXGSessionUserName(session);if(name)++named;
                    ++kinds[WXGSessionKind(name)];if(WXGSessionUnread(session))++unread;
                }
                long long topCount=-1;WXGSessionGetInteger(manager,@"totalTopSessionCount",&topCount);
                out[@"sessions"]=@{@"top":@(top.count),@"normal":@(normal.count),@"topCount":@(topCount),@"named":@(named),@"single":@(kinds[2]),
                                   @"group":@(kinds[3]),@"other":@(kinds[0]),@"unread":@(unread),@"classes":classes.allObjects,
                                   @"filtered":@(atomic_load(&WXGFilterIndex)>0)};
                out[@"dataSourceRows"]=@(WXGDataSourceRows(table));
            }
        } @catch(NSException *error) {out[@"error"]=error.reason?:error.name?:@"?";}
    }
    return out;
}
@end
static void WXGFilterOffMainSeen(void) {[WXGChatSegments.shared filterOffMain];}
