#import "WXGIntegration.h"
#import "WXGElasticMotion.h"
#import "WXGDockTouchPolicy.h"
#import "WXGPressStretch.h"
#import "WXGDockScript.h"
#import <malloc/malloc.h>
#import <stdatomic.h>

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

// FIX113 R: the groups are the user's (WXGChatGroupList, 1-6 of them); the
// dock's layout for n segments instead of its 4 tabs (WXGDockLayout /
// WXGElasticLayout with the slot count as a parameter, nothing else changed).
#define WXG_SEGMENTS_MAX 6
static inline float WXGSegWidth(float width,float gap,int n) {return WXG_MAX(1.f,(width-2.f*gap)/(float)WXG_MAX(1,n));}
static inline float WXGSegCenter(float width,float gap,int index,int n) {
    if(index<0)index=0;if(index>n-1)index=n-1;
    return gap+WXGSegWidth(width,gap,n)*(index+.5f);
}
static WXGDockGeometry WXGSegLayout(float width,float height,float gap,float anchor,float press,float growth,float stretch,float barGrowth,float wrap,int n) {
    press=WXGOClamp(press,0.f,1.f);
    WXGDockGeometry g;
    g.scale=1.f+(barGrowth-1.f)*press;
    g.barWidth=width*g.scale;g.barHeight=height*g.scale;
    g.barX=(width-g.barWidth)*.5f;g.barY=(height-g.barHeight)*.5f;
    float first=WXGSegCenter(width,gap,0,n),last=WXGSegCenter(width,gap,n-1,n);
    float t=WXGOClamp((anchor-first)/WXG_MAX(1.f,last-first),0.f,1.f);
    g.anchorX=first+(last-first)*t;
    g.lensWidth=WXGLensWidth(WXGSegWidth(width,gap,n),height,press,growth,stretch)*g.scale;
    g.lensHeight=WXGLensHeight(height,gap,press,growth,stretch)*g.scale;
    float outside=gap*g.scale*(1.f-press)-wrap*press;
    g.lensX=g.barX+outside+t*(g.barWidth-2.f*outside-g.lensWidth);
    g.lensY=(height-g.lensHeight)*.5f;
    return g;
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

@interface WXGSegmentBar : UIControl
@property(nonatomic,strong,readonly) WXGGlassView *glass;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic) BOOL active;
@property(nonatomic,strong) UIColor *pillColor,*inkColor;
@property(nonatomic,strong) UIColor *accentColor;   // FIX113 P: the selected title's (nil: the ink)
@property(nonatomic,copy) NSArray<NSString *> *titles;   // FIX113 R: the groups' names (1-6)
@property(nonatomic,readonly) CGRect materialRect;
- (void)tick:(CADisplayLink *)link;
- (void)wake;
- (void)refreshLook;
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
    NSUInteger _downs,_glides,_travels,_drops,_drags,_commits,_draws,_cancels;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.clipsToBounds=NO;self.isAccessibilityElement=NO;
        _resumeIndex=-1;_selectionShown=1;
        _glass=[[WXGGlassView alloc] initWithFrame:self.bounds];_glass.dockSurface=YES;_glass.glassScopeOverride=WXGGlassScopeSegment;_glass.userInteractionEnabled=NO;
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
    _titles=[clean copy];[self makeItems];
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
    if(_link.paused==run)_link.paused=!run;
    if(run)_lastTime=0;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous && ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])return;
    [_glass invalidateBackdrop];[self wake];
}
#pragma mark Colours and titles
- (void)setPillColor:(UIColor *)color {
    if(color==_pillColor || [color isEqual:_pillColor])return;
    _pillColor=color;_glass.selectionOverride=color;_fallbackPill.backgroundColor=color;[self wake];
}
- (void)setInkColor:(UIColor *)color {
    if(color==_inkColor || [color isEqual:_inkColor])return;
    _inkColor=color;[self rebuildTitles:NO];[self wake];
}
- (void)setAccentColor:(UIColor *)color {
    if(color==_accentColor || [color isEqual:_accentColor])return;
    _accentColor=color;[self rebuildTitles:NO];[self wake];
}
// FIX113 O: the segment bar's own lens (size, growth, zoom, pill inset).
- (WXGLensSettings)lens {return [WXGConfig.shared lensSettingsForScope:WXGGlassScopeSegment dark:self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark];}
- (CGFloat)selectionGap {return WXGSelectionGap([self lens].selectionInset,_materialRect.size.height);}
- (CGFloat)centerForIndex:(NSInteger)index {return CGRectGetMinX(_materialRect)+WXGSegCenter(_materialRect.size.width,[self selectionGap],(int)index,(int)self.count);}
- (CGFloat)atlasScale {
    WXGLensSettings l=[self lens];
    return WXGCaptureScale(self.window.screen.scale?:UIScreen.mainScreen.scale)*MAX(1,l.zoom)*MAX(1,l.barGrowth);
}
// The four titles at their segments' centres, the whole view's size (the
// glass's icon atlases): the body draws the unselected ones, the lens the
// selected ones (a little heavier), magnified with it.
- (UIImage *)titlesSelected:(BOOL)selected {
    CGSize size=self.bounds.size;if(size.width<1 || size.height<1 || CGRectIsEmpty(_materialRect))return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=[self atlasScale];format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    WXGConfig *c=WXGConfig.shared;
    CGFloat fontSize=WXGClamp([c extraNumber:@"segmentTitleSize"],10,18);
    static const CGFloat weights[5]={-.4,0,.23,.3,.4};   // light .. bold; the selected one a step heavier
    NSInteger step=(NSInteger)WXGClamp(lround([c extraNumber:@"segmentTitleWeight"])+(selected?1:0),0,4);
    UIFont *font=[UIFont systemFontOfSize:fontSize weight:weights[step]];
    UIColor *ink=(selected?_accentColor:nil)?:_inkColor?:[UIColor colorWithWhite:0 alpha:.86];   // FIX113 P: the selected one in the accent colour, as the dock
    NSArray *titles=_titles;NSInteger count=self.count;CGFloat midY=CGRectGetMidY(_materialRect);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
        NSDictionary *attrs=@{NSFontAttributeName:font,NSForegroundColorAttributeName:ink};
        CGFloat slot=WXGSegWidth(self->_materialRect.size.width,[self selectionGap],(int)count)-6;
        for(NSInteger i=0;i<count;i++) {
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
    if(!CGSizeEqualToSize(_previousSize,self.bounds.size) || fabs(_previousGap-[self selectionGap])>.01) {
        _previousSize=self.bounds.size;_previousGap=[self selectionGap];
        [self cancelInteraction];
        _lensX=[self centerForIndex:_selectedIndex];_targetX=_lensX;_velocityX=0;
        [self rebuildTitles:NO];[_glass invalidateBackdrop];
    }
    for(NSInteger i=0;i<self.count && i<(NSInteger)_items.count;i++) {
        CGFloat slot=WXGSegWidth(_materialRect.size.width,[self selectionGap],(int)self.count);
        _items[(NSUInteger)i].accessibilityFrameInContainerSpace=CGRectMake(CGRectGetMinX(_materialRect)+[self selectionGap]+slot*i,CGRectGetMinY(_materialRect),slot,_materialRect.size.height);
        _items[(NSUInteger)i].accessibilityTraits=UIAccessibilityTraitButton|(i==_selectedIndex?UIAccessibilityTraitSelected:0);
    }
    [self updateGeometry];[self wake];
}
- (void)updateGeometry {
    if(CGRectIsEmpty(_materialRect))return;
    WXGLensSettings c=[self lens];BOOL reduce=UIAccessibilityIsReduceMotionEnabled() || !c.elasticOn;   // FIX113 Y: the deformation can be off
    CGFloat press=WXGClamp(_press,0,1);
    float w=(float)_materialRect.size.width,h=(float)_materialRect.size.height,gap=(float)[self selectionGap],anchor=(float)(_lensX-_materialRect.origin.x);
    int n=(int)self.count;
    // The segment bar's own lens, then the system's deformation (as the dock's: WXGLensFlex.h).
    WXGDockGeometry g=WXGSegLayout(w,h,gap,anchor,(float)press,(float)c.growth,0,(float)c.barGrowth,(float)c.endWrap,n);
    _glass.lensRestHeight=g.lensHeight;   // FIX113 Y: undeformed
    if(!reduce) {
        double sx=1,sy=1;WXGLensFlexScale(_flex,WXGConfig.shared.lensFlexParams,&sx,&sy);   // FIX126: as the system's lens
        float lw=WXG_MIN((float)(g.lensWidth*sx),g.barWidth+2.f*(float)c.endWrap),lh=(float)(g.lensHeight*sy);
        lh=(float)WXGLensFlexRestingHeight(lh,g.barHeight,press,1.);   // FIX134: down, never cut by the bar
        g.lensX+=(g.lensWidth-lw)*.5f;g.lensY+=(g.lensHeight-lh)*.5f;g.lensWidth=lw;g.lensHeight=lh;
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
    if(_fingerDown || index==_selectedIndex)return;
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
    CGFloat slot=WXGSegWidth(_materialRect.size.width,[self selectionGap],(int)self.count);
    CGFloat steps=fabs(_targetX-_lensX)/MAX(1,slot);
    _dragging=NO;_touchStart=point;_jumpPlanEnd=0;
    // As the dock's tap: the real lens glides to the touched segment on the
    // FIX43 timing (x 点按动画时长倍数), lifted, from the press and colour it had.
    if(steps>.3 && !UIAccessibilityIsReduceMotionEnabled()) {
        WXGConfig *c=WXGConfig.shared;double duration=.28*(.85+.05*MIN(steps,3.));
        _script=WXGScriptGlide(CACurrentMediaTime(),_lensX,[self centerForIndex:_selectedIndex],duration*c.dockTapDurationScale,pressBefore,selectionBefore,_selectedIndex,c.dockTapLensShare);
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
    [self selectIndex:WXGSlot(x,CGRectGetMinX(_materialRect)+[self selectionGap],_materialRect.size.width-2*[self selectionGap],(int)self.count) haptic:YES];
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
        if(_selectedIndex!=_initialSelected)[self sendActionsForControlEvents:UIControlEventValueChanged];
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
    WXGConfig *c=WXGConfig.shared;CGFloat slot=MAX(1,WXGSegWidth(_materialRect.size.width,[self selectionGap],(int)self.count));
    _script=WXGScriptTravel(CACurrentMediaTime(),_lensX,[self centerForIndex:index],slot,WXGClamp(_press,0,1),WXGClamp(_selectionShown,0,1),_jumpPlanEnd,index,
                            c.dockTapDurationScale,c.dockTapDropDuration,c.dockTapLensShare);
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
    if(!reduce && self.count>1)WXGLensFlexStep(&_flex,_velocityX,([self centerForIndex:self.count-1]-[self centerForIndex:0])/(double)(self.count-1),WXGConfig.shared.lensFlexParams,dt);   // FIX126
    else _flex=(WXGLensFlex){0};
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
            case 'I':case 'L':return ((unsigned int (*)(id,SEL))objc_msgSend)(session,sel);
            case 'i':case 'l':return ((int (*)(id,SEL))objc_msgSend)(session,sel);
            case 'Q':case 'q':return ((long long (*)(id,SEL))objc_msgSend)(session,sel);
            default:break;
        }
    }
    Ivar ivar=class_getInstanceVariable(object_getClass(session),name);
    const char *type=ivar?ivar_getTypeEncoding(ivar):NULL;if(!type)return 0;
    const char *base=(const char *)(__bridge void *)session+ivar_getOffset(ivar);
    switch(type[0]) {
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
static BOOL WXGSessionMatches(id session,NSInteger rule) {
    if(rule==1)return WXGSessionUnread(session);
    if(rule==4){NSString *name=WXGSessionUserName(session);return name && [WXGFilterMembers containsObject:name];}
    return WXGSessionKind(WXGSessionUserName(session))==rule;
}
// FIX113 R: WeChat's whole list as its last rebuild on the main thread made it
// (before any filtering), for choosing a custom group's members; and the
// manager that rebuilt it.
static NSArray *WXGFilterSnapshot;
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
            if([t isKindOfClass:NSArray.class] && [n isKindOfClass:NSArray.class])WXGFilterSnapshot=[t arrayByAddingObjectsFromArray:n];
        } @catch(__unused NSException *error) {}
    }
    NSInteger index=atomic_load(&WXGFilterIndex);
    if(index<1 || index>4 || atomic_load(&WXGFilterDisabled))return;
    if(!home || manager!=home)return;
    NSArray *top=nil,*normal=nil;long long count=0;BOOL counted=NO,touched=NO;
    @try {
        top=WXGSessionGetObject(manager,@"topSessions");normal=WXGSessionGetObject(manager,@"normalSessions");
        if(![top isKindOfClass:NSArray.class] || ![normal isKindOfClass:NSArray.class]){atomic_store(&WXGFilterLastOK,NO);return;}
        NSMutableArray *keptTop=[NSMutableArray arrayWithCapacity:top.count],*keptNormal=[NSMutableArray arrayWithCapacity:normal.count];
        for(id session in top)if(WXGSessionMatches(session,index))[keptTop addObject:session];
        for(id session in normal)if(WXGSessionMatches(session,index))[keptNormal addObject:session];
        count=(long long)top.count;counted=WXGSessionGetInteger(manager,@"totalTopSessionCount",&count);
        // WeChat's own relation of the count to the array, unless the count is
        // still the one we wrote (its rebuild left it): then the last one known.
        if(counted && count!=WXGFilterWrittenCount)WXGFilterTopDelta=count-(long long)top.count;
        long long written=(long long)keptTop.count+(counted?WXGFilterTopDelta:0);
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
// FIX114 F: `leaf` pushed over `below` in the same navigation stack.
static BOOL WXGPushedOver(UIViewController *below,UIViewController *leaf) {
    UINavigationController *nav=leaf.navigationController;
    if(!below || !nav || below.navigationController!=nav)return NO;
    NSArray *stack=nav.viewControllers;
    NSUInteger i=[stack indexOfObjectIdenticalTo:below],j=NSNotFound;
    for(UIViewController *c=leaf;c && j==NSNotFound;c=c.parentViewController)j=[stack indexOfObjectIdenticalTo:c];
    return i!=NSNotFound && j!=NSNotFound && i<j;
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
        [self addSubview:_surface];_surface.active=YES;[_surface applyConfig];
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
    if(_native) {   // where WeChat draws them, the box centred on ours
        CGFloat dx=(self.bounds.size.width-_boxSize.width)*.5,dy=(self.bounds.size.height-_boxSize.height)*.5;
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
// FIX114 F: exact: the field is WeChat's drawn box (or the last one seen);
// since: when this bar was found; the look: WeChat's icon and text copied.
@property(nonatomic) BOOL pinned,lookCopied,exact;
@property(nonatomic) CGRect lastExact;   // meaningful when exact
@property(nonatomic) CFTimeInterval since,measured,lookTried,lookAgainAt;
@property(nonatomic) NSUInteger misses,lookTries;
@property(nonatomic) UIUserInterfaceStyle lookStyle;
@property(nonatomic) NSUInteger pins,taps;
@end
@implementation WXGFloatSlot
@end

#pragma mark - The manager

@implementation WXGChatSegments {
    WXGSegmentBar *_bar;
    __weak UIView *_searchBar,*_container;__weak UITableView *_table;__weak UIViewController *_page;
    WXGStateBag *_states;
    NSString *_status,*_fieldSource,*_colorSource;
    NSUInteger _mounts,_moves,_switches,_restores,_nativeSearches;
    NSInteger _selected;
    BOOL _nativeSearching,_observing;
    CGRect _fieldRect;
    NSDictionary *_probe;CFTimeInterval _probeAt;
    __weak UIView *_hiddenBar;   // the bar faded out by us (its alpha was WeChat's own then)
    __weak UIView *_floatHost;   // FIX114 B: where hostTick last floated the bar (the before-commit pass places it there too)
    NSUInteger _rehides,_commitPlacements;   // FIX114 B: diagnostics
    CGRect _naturalFrame;        // FIX113 O: the segment bar's frame in its container (in the list)
    BOOL _segmentFloating;       // FIX113 O: it is in the navigation overlay now
    NSMapTable<UIViewController *,WXGFloatSlot *> *_floats;
    NSUInteger _floatMoves;
    NSUInteger _directSearches;   // FIX114 M: capsule taps that opened WeChat's search page at once
    NSMutableArray<NSString *> *_switchLog;
    CGFloat _gapDelta;           // FIX114 E: moved down with the title row (顶部按钮往下移; 0: where WeChat's field is)
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
- (void)observe {
    if(_observing)return;_observing=YES;
    // FIX114 B (user: pulled down, the bar and the title row move at different
    // speeds, the gap changes; an extra capsule shows now and then): before
    // every Core Animation commit (just ahead of it), the floating bar is put
    // where the list is in that same commit (hostTick ran on the display
    // link, a frame behind the scrolling on a slow phone), and WeChat's search
    // bar is faded out again if WeChat brought it back (it does, pulling the
    // list down: its own search bar then showed at its place, empty).
    __weak WXGChatSegments *weakSelf=self;
    CFRunLoopObserverRef commit=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999000,
        ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){[weakSelf beforeCommit];});
    if(commit){CFRunLoopAddObserver(CFRunLoopGetMain(),commit,kCFRunLoopCommonModes);CFRelease(commit);}
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldBegan:) name:UITextFieldTextDidBeginEditingNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:) name:WXGSettingsChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(groupsChanged:) name:WXGChatGroupsChanged object:nil];   // FIX113 R
}
- (void)beforeCommit {
    if(!_bar || !_bar.superview || WXGBackdropCaptureInProgress())return;
    @try {
        UIView *hidden=_hiddenBar;
        if(hidden && !_nativeSearching && hidden.alpha>.01 && _states){[_states hide:hidden];++_rehides;}
        UIView *host=_floatHost;
        if(_segmentFloating && host && host.window && _table.superview==host){[self placeSegmentIn:host];++_commitPlacements;}
    } @catch(__unused NSException *error) {}
}
- (void)settingsChanged:(__unused NSNotification *)note {
    if(![self wanted]){[self restore];return;}
    UIViewController *page=_page;if(page)[self updateOnPage:page];
    [_bar refreshLook];   // its lens, pill inset and titles may have changed
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)[slot.clone.surface applyConfig];
}
// WeChat's own search took its field (its search button, the dock's search
// handing a text over): its bar is given back while it is used.
- (void)fieldBegan:(NSNotification *)note {
    UIView *field=note.object,*bar=_searchBar;
    // FIX114 F (review): WeChat's own search in a bar a floating capsule
    // covers (it can start while that page is covered or sliding back): its bar back now.
    if([field isKindOfClass:UIView.class])for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)
        if(slot.pinned && slot.bar && [field isDescendantOfView:slot.bar])[self unpin:slot];
    if(!bar || ![field isKindOfClass:UIView.class] || ![field isDescendantOfView:bar])return;
    _nativeSearching=YES;++_nativeSearches;
    [_states restore];_states=nil;_hiddenBar=nil;
    _bar.hidden=YES;_bar.active=NO;_status=@"微信自己的搜索正在用搜索栏，暂时还给它";
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
    if(!header)return nil;
    static Class wcBar;static dispatch_once_t once;dispatch_once(&once,^{wcBar=NSClassFromString(@"WCSearchBar");});
    if([header isKindOfClass:UISearchBar.class] || (wcBar && [header isKindOfClass:wcBar]))return header;
    UIView *found=nil;
    for(UIView *v in WXGViews(header,160)) {
        if(WXGIsPluginView(v))continue;
        if([v isKindOfClass:UISearchBar.class])return v;
        if(!found && wcBar && [v isKindOfClass:wcBar])found=v;
    }
    return found;
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
static CGRect WXGVisibleSearchBox(UIView *bar) {
    static Class custom;static dispatch_once_t once;dispatch_once(&once,^{custom=NSClassFromString(@"WCSearchBar");});
    if(!custom || !bar)return CGRectNull;
    UIView *wc=[bar isKindOfClass:custom]?bar:nil;
    if(!wc)for(UIView *v in WXGViews(bar,80))if([v isKindOfClass:custom] && !v.hidden){wc=v;break;}
    if(!wc)return CGRectNull;
    CGFloat barW=bar.bounds.size.width,bestW=0;CGRect best=CGRectNull;
    for(UIView *v in WXGViews(wc,120)) {
        // Not by its paint or alpha: the local glass clears the box's fill, the
        // plugin fades the bar; by what it is and where it sits.
        if(v==wc || v.hidden || WXGIsPluginView(v) || v.class!=UIView.class || v.layer.cornerRadius<2 || ![v.superview isKindOfClass:UIStackView.class])continue;
        CGRect r=[v convertRect:v.bounds toView:bar];
        if(r.size.height<24 || r.size.height>60 || r.size.width<barW*.4 || r.size.width>barW+.5)continue;
        if(r.size.width>bestW+.5){best=r;bestW=r.size.width;}
    }
    return best;
}
- (CGRect)fieldRectIn:(UIView *)bar source:(NSString **)source {
    CGFloat barW=bar.bounds.size.width;CGRect best=CGRectNull;CGFloat bestW=0;NSString *from=nil;
    CGRect seen=WXGVisibleSearchBox(bar);   // FIX114 F: what is on screen first
    if(!CGRectIsNull(seen)){if(source)*source=WXGDrawnBoxSource;return seen;}
    if([bar isKindOfClass:UISearchBar.class]) {
        UITextField *field=((UISearchBar *)bar).searchTextField;
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
// The colours: the bar's background is its range's material (分组, the
// settings); the pill the page's own background colour (or the one set),
// the titles the colour set.
- (void)applyColorsFrom:(UIView *)bar {
    UITraitCollection *traits=bar.traitCollection;BOOL dark=traits.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIColor *bg=nil;NSString *from=nil;
    for(UIView *v=bar.superview;v && ![v isKindOfClass:UIWindow.class];v=v.superview) {
        if(WXGIsPluginView(v) || !v.backgroundColor)continue;
        UIColor *resolved=[v.backgroundColor resolvedColorWithTraitCollection:traits];CGFloat r=0,g=0,b=0,a=0;
        if(![resolved getRed:&r green:&g blue:&b alpha:&a])continue;   // a pattern (a theme's picture): not a colour
        if(a>.9){bg=[UIColor colorWithRed:r green:g blue:b alpha:1];from=NSStringFromClass(v.class);break;}
    }
    if(!bg){bg=dark?[UIColor colorWithWhite:.11 alpha:1]:UIColor.whiteColor;from=@"default";}
    WXGConfig *c=WXGConfig.shared;
    UIColor *pill=[c extraNumber:@"segmentPillAuto"]>.5?bg:WXGColor([c extraHex:dark?@"segmentDarkPillHex":@"segmentPillHex"]);
    CGFloat pr=1,pg=1,pb=1,pa=1;if(![pill getRed:&pr green:&pg blue:&pb alpha:&pa]){pr=pg=pb=dark?.23:1;pa=1;}
    _bar.pillColor=[UIColor colorWithRed:pr green:pg blue:pb alpha:pa*WXGClamp([c extraNumber:dark?@"segmentDarkPillOpacity":@"segmentPillOpacity"],0,1)];
    _bar.glass.selectionOverridePressedAlpha=pa*WXGClamp([c extraNumber:@"segmentPillPressedOpacity"],0,1);   // FIX113 P: fades into the lens as the dock's
    _bar.inkColor=WXGColor([c extraHex:dark?@"segmentDarkInkHex":@"segmentInkHex"])?:(dark?UIColor.whiteColor:UIColor.blackColor);
    _bar.accentColor=[c extraNumber:@"segmentAccentOn"]>.5?WXGColor([c extraHex:@"segmentAccentHex"]):nil;
    CGFloat r=0,g=0,b=0,a=0;[bg getRed:&r green:&g blue:&b alpha:&a];
    _colorSource=[NSString stringWithFormat:@"page %@ #%02X%02X%02X; pill %@",from,(int)round(r*255),(int)round(g*255),(int)round(b*255),
                  [c extraNumber:@"segmentPillAuto"]>.5?@"page":@"set"];
}
- (void)updateOnPage:(UIViewController *)page {
    if(!NSThread.isMainThread)return;
    if(![self wanted]){[self restore];return;}
    [self observe];
    if(!page.isViewLoaded || !page.view.window)return;   // another tab: left as it is
    _page=page;
    UITableView *table=_table && [_table isDescendantOfView:page.view]?_table:[self tableIn:page.view];
    UIView *header=table.tableHeaderView,*bar=[self searchBarIn:header];
    if(!table || !header || !bar){_status=!table?@"没有找到聊天列表":!header?@"列表没有表头":@"表头里没有搜索栏";return;}
    _table=table;
    [self mountOver:bar header:header table:table];
}
- (void)searchBarLaidOut:(UIView *)view {
    if(view!=_searchBar || !_bar.superview || ![self wanted])return;
    UITableView *table=_table;UIView *header=table.tableHeaderView;
    if(!table || !header || ![view isDescendantOfView:header])return;
    [self mountOver:view header:header table:table];
}
- (void)mountOver:(UIView *)bar header:(UIView *)header table:(UITableView *)table {
    if(_nativeSearching) {
        UITextField *field=[bar isKindOfClass:UISearchBar.class]?((UISearchBar *)bar).searchTextField:nil;
        BOOL using=(field && (field.isFirstResponder || field.text.length)) || _page.presentedViewController!=nil;
        if(!using)for(UIView *v in WXGViews(bar,160))if(v.isFirstResponder || ([v isKindOfClass:UITextField.class] && ((UITextField *)v).text.length)){using=YES;break;}
        if(using)return;
        _nativeSearching=NO;
    }
    // A bar at alpha 0 that is not ours (WeChat's own search transition):
    // not now, or restoring would give it back invisible. FIX113 O: one the
    // floating search faded (分组栏 switched on while the list was scrolled)
    // is given back first, then taken over.
    WXGFloatSlot *floated=nil;
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)if(slot.pinned && slot.bar==bar){floated=slot;break;}
    if(bar!=_hiddenBar && bar.alpha<.01 && !floated){_status=@"搜索栏此刻是透明的（微信在做动画），稍后再取代";return;}
    NSString *source=nil;CGRect field=[self fieldRectIn:bar source:&source];
    if(CGRectIsNull(field) || field.size.width<80){_status=@"搜索栏里没有找到输入框";return;}
    if(floated)[self unpin:floated];
    _fieldRect=field;_fieldSource=source;
    // In the header (it scrolls with the list); a header that IS the bar:
    // in the table, at the bar's place (the bar is faded out).
    UIView *container=header==bar?table:header;
    if(!_bar) {
        _bar=[[WXGSegmentBar alloc] initWithFrame:CGRectZero];
        [_bar addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        // FIX113 R: the group chosen before (this run), else the whole list's.
        NSArray *groups=WXGChatGroupList();NSInteger index=-1;
        for(NSUInteger i=0;i<groups.count;i++)if([groups[i][@"id"] isEqual:_selectedGroupID])index=(NSInteger)i;
        if(index<0 || atomic_load(&WXGFilterIndex)==0){NSInteger whole=[self wholeListIndex];if(whole>=0)index=whole;}
        _selected=MAX(0,index);_selectedGroupID=groups[(NSUInteger)_selected][@"id"];
        _bar.titles=[self groupNames];
        _bar.selectedIndex=_selected;
        // No group shows the whole list: the one shown is applied once the bar is up.
        NSDictionary *chosen=groups[(NSUInteger)_selected];
        if([chosen[@"rule"] integerValue]!=0 && atomic_load(&WXGFilterIndex)==0) {
            __weak WXGChatSegments *weakSelf=self;
            dispatch_async(dispatch_get_main_queue(),^{WXGChatSegments *me=weakSelf;if(me && me->_bar && [me wanted])[me applyGroup:chosen];});
        }
    }
    _bar.titles=[self groupNames];
    // FIX114 E (user: “at the native search box's size and place: stable”):
    // exactly WeChat's field (FIX113 P / Q's width, extra height and gap to
    // the title row are gone).
    _naturalFrame=CGRectInset([bar convertRect:field toView:container],-WXGCanvasPaddingX,-WXGCanvasPaddingY);
    CGRect frame=[self listFrame];
    if(container!=_container)_segmentFloating=NO;   // a new list: in it first
    if(!_segmentFloating)[UIView performWithoutAnimation:^{   // floating: hostTick places it
        if(self->_bar.superview!=container){[container addSubview:self->_bar];++self->_mounts;}
        else if(container.subviews.lastObject!=self->_bar)[container bringSubviewToFront:self->_bar];
        if(!CGRectEqualToRect(self->_bar.frame,frame)){self->_bar.frame=frame;++self->_moves;}
    }];
    _container=container;
    if(bar!=_searchBar && _searchBar)[_states restoreView:_searchBar];
    if(bar!=_searchBar)_fieldRechecks=0;
    _searchBar=bar;
    if(!_states)_states=[WXGStateBag new];
    [_states hide:bar];_hiddenBar=bar;
    [self applyColorsFrom:bar];
    WXGInstallFilterHook();   // FIX113 Q: passes through until a group is chosen; it notes which thread WeChat rebuilds on
    WXGFilterWatching=YES;
    _bar.hidden=NO;_bar.active=YES;   // FIX113 S: not by the window (a layout while a chat was open left it inactive: no taps after coming back)
    _status=@"已取代搜索框";
}
// Its frame in the list: where WeChat's field is (moved down with the title row, FIX114 C).
- (CGRect)listFrame {return CGRectOffset(_naturalFrame,0,_gapDelta);}
// FIX114 C / E: the bar stays where WeChat's field is; only when the title
// row is moved down (顶部按钮往下移) it moves down with it, so the row never
// covers it (inside the list's header).
- (void)updateGapOn:(UIViewController *)leaf overlay:(UIView *)overlay transitioning:(BOOL)transitioning {
    // (review) Another page on top (a chat pushed / popping): kept as it is, or
    // it jumps while the list's page slides and again when it is back.
    if(leaf!=_page)return;
    CGFloat follow=WXGPreferences.shared.nav?[WXGIntegrationHost.shared titleRowOffsetForPage:leaf]:0;
    if(!isfinite(follow))return;   // the row not laid out for it yet
    if(follow<.01){_gapDelta=0;return;}
    UIView *container=_container;UITableView *table=_table;UIView *header=table.tableHeaderView;
    if(!_bar || !container || leaf!=_page || !overlay.window || !table || !header || transitioning)return;   // kept as it was
    if(!(container==table || [container isDescendantOfView:table]))return;
    // The glass stays inside the header (outside it, it could not be touched
    // and would lie over the first chat).
    CGRect material=CGRectInset(_naturalFrame,WXGCanvasPaddingX,WXGCanvasPaddingY);
    CGRect area=container==table?header.frame:container.bounds;
    CGFloat lo=CGRectGetMinY(area)-CGRectGetMinY(material),hi=CGRectGetMaxY(area)-CGRectGetMaxY(material);
    _gapDelta=hi>=lo?WXGClamp(follow,lo,hi):0;
}
- (void)takeProbe {
    UITableView *table=_table;if(!table)return;
    CFTimeInterval start=CACurrentMediaTime();
    NSDictionary *probe=WXGChatListProbe(table,_page);
    NSMutableDictionary *stamped=[probe mutableCopy];stamped[@"ms"]=@(round((CACurrentMediaTime()-start)*10000)/10);
    stamped[@"since"]=@(round(WXGSecondsSinceLoad()*10)/10);
    _probe=stamped;_probeAt=CACurrentMediaTime();
}
- (void)segmentChanged:(WXGSegmentBar *)bar {
    NSArray<NSDictionary *> *groups=WXGChatGroupList();
    NSInteger previous=_selected;
    _selected=(NSInteger)WXGClamp(bar.selectedIndex,0,(NSInteger)groups.count-1);++_switches;
    NSDictionary *group=groups[(NSUInteger)_selected];
    BOOL ok=[self applyGroup:group];   // FIX113 Q / R
    if(!_switchLog)_switchLog=[NSMutableArray array];
    if(_switchLog.count>=20)[_switchLog removeObjectAtIndex:0];
    [_switchLog addObject:[NSString stringWithFormat:@"%.1f s #%ld rule %@ %@",WXGSecondsSinceLoad(),(long)_selected,group[@"rule"],ok?@"ok":_filterStatus?:@"?"]];
    if(_switches<=3 || !ok)WXGLog(@"聊天分组：切到第 %ld 组，%@",(long)_selected+1,_filterStatus?:@"");
    if(ok)_selectedGroupID=group[@"id"];
    else {   // back to the group that shows WeChat's whole list (none: the bar stays, the list is whole), said in the diagnostics
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
    if(index<=0 || index>4) {
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
    id manager=WXGHomeSessionManager(page,table);
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
    NSInteger whole=[self wholeListIndex];NSArray *groups=WXGChatGroupList();
    if(whole>=0){_selected=whole;_selectedGroupID=groups[(NSUInteger)whole][@"id"];[_bar returnToIndex:whole];}else _selectedGroupID=nil;
}
- (BOOL)floatWanted {
    return WXGPluginEnabled() && WXGEffectiveRenderMode()>=2 && [WXGConfig.shared extraNumber:@"searchFloat"]>.5;
}
// Where a field of `header` stops in `overlay`: the list's visible top (below
// the title row) plus the field's own distance from the header's top; and
// the field's natural top there now.
static CGFloat WXGFloatPinnedTop(UITableView *table,UIView *header,CGFloat fieldTop,UIView *overlay) {
    CGRect tableRect=[table convertRect:table.bounds toView:overlay];
    CGFloat visibleTop=CGRectGetMinY(tableRect)+table.adjustedContentInset.top;
    CGFloat headerTop=[header convertRect:header.bounds toView:overlay].origin.y;
    return visibleTop+(fieldTop-headerTop);
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
    WXGSegmentBar *bar=_bar;UIView *container=_container;UITableView *table=_table;
    if(!bar)return;
    if(!container) {   // its list went away while it floated: not left over the page (mounted again on the next refresh)
        if(_segmentFloating){[bar removeFromSuperview];_segmentFloating=NO;++_floatMoves;}
        return;
    }
    // A header WeChat replaced (the old one no longer in the list): back into it, out of sight, until mounted again.
    BOOL live=table && (container==table || [container isDescendantOfView:table]);
    CGRect inList=[self listFrame];
    if(!host || !live || !table.tableHeaderView || table.superview!=host) {
        if(_segmentFloating || bar.superview!=container || !CGRectEqualToRect(bar.frame,inList)) {
            [UIView performWithoutAnimation:^{[container addSubview:bar];bar.frame=inList;}];
            if(_segmentFloating)++_floatMoves;
            _segmentFloating=NO;
        }
        return;
    }
    CGRect natural=[container convertRect:inList toView:host];
    CGFloat fieldTop=CGRectGetMinY(natural)+WXGCanvasPaddingY;
    CGFloat pinned=WXGFloatPinnedTop(table,table.tableHeaderView,fieldTop,host);
    CGRect frame=natural;
    // FIX114 E: where WeChat's field is (pulled down too: FIX114 A's hold at
    // the title row's distance is gone); scrolled up, it stops under the row.
    if(fieldTop<pinned)frame.origin.y+=pinned-fieldTop;
    if(bar.superview!=host)++_floatMoves;
    WXGRaiseAboveList(bar,host,table);
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(!CGRectEqualToRect(bar.frame,frame))bar.frame=frame;
        [CATransaction commit];
    }];
    _segmentFloating=YES;
}
- (WXGFloatSlot *)floatSlotFor:(UIViewController *)page {
    if(!_floats)_floats=[NSMapTable weakToStrongObjectsMapTable];
    WXGFloatSlot *slot=[_floats objectForKey:page];
    if(!slot){slot=[WXGFloatSlot new];slot.page=page;[_floats setObject:slot forKey:page];}
    return slot;
}
- (void)unpin:(WXGFloatSlot *)slot {
    if(slot.clone && !slot.clone.hidden)slot.clone.hidden=YES;
    if(slot.states){[slot.states restore];slot.states=nil;}
    slot.pinned=NO;
}
- (void)restoreFloats {
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects){[self unpin:slot];[slot.clone removeFromSuperview];slot.clone=nil;}
    [_floats removeAllObjects];
}
// WeChat's own search being used on this page (its field focused or holding
// text, its search controller up): its bar is left alone.
- (BOOL)nativeSearchActive:(UIView *)bar page:(UIViewController *)page {
    if(page.presentedViewController || page.navigationItem.searchController.isActive)return YES;
    for(UIView *v in WXGViews(bar,160))if(v.isFirstResponder || ([v isKindOfClass:UITextField.class] && ((UITextField *)v).text.length))return YES;
    return NO;
}
// FIX114 F: the slot's field: WeChat's drawn box; not found now but seen
// before: that one (never the hidden text field under it); never seen: the
// field fieldRectIn: falls back to, counted as a miss. Another size of the
// box: its icon and text are copied again.
- (void)measureSlot:(WXGFloatSlot *)slot now:(CFTimeInterval)now {
    NSString *source=nil;CGRect f=[self fieldRectIn:slot.bar source:&source];slot.measured=now;
    if([source isEqualToString:WXGDrawnBoxSource]) {
        if(slot.exact && !CGSizeEqualToSize(f.size,slot.lastExact.size))slot.lookCopied=NO;
        slot.field=f;slot.lastExact=f;slot.exact=YES;slot.misses=0;
    }else if(slot.exact)slot.field=slot.lastExact;
    else{slot.field=f;if(now-slot.since>=1)++slot.misses;}   // the first second's frames not counted (120 Hz)
}
// WeChat's own search bar on 首页 (no segment bar there) or 通讯录: FIX113 T: a
// glass capsule in its place all the time (in the page above the fade and
// blur, held below the title row when the list goes up), WeChat's bar faded.
- (void)floatNativeOn:(UIViewController *)page time:(CFTimeInterval)time {
    WXGFloatSlot *slot=[self floatSlotFor:page];
    UITableView *table=slot.table;UIView *bar=slot.bar;
    CFTimeInterval now=CACurrentMediaTime();
    if((!table || !bar || ![table isDescendantOfView:page.view] || ![bar isDescendantOfView:table.tableHeaderView]) && now-slot.scanned>.5) {
        slot.scanned=now;table=[self tableIn:page.view];bar=[self searchBarIn:table.tableHeaderView];
        if(bar!=slot.bar) {   // FIX114 F: another bar: measured and shown afresh (not at the old one's place)
            if(slot.bar)[self unpin:slot];
            slot.exact=NO;slot.misses=0;slot.since=now;slot.lookCopied=NO;slot.lookTries=0;slot.lookAgainAt=0;
        }
        slot.table=table;slot.bar=bar;slot.measured=0;
        if(!bar)slot.field=CGRectNull;
    }
    // FIX114 F: WeChat's drawn box. Until it is found (WeChat lays out its
    // stack views after the bar): every frame for a second, then twice a
    // second, 80 more times at most; found: again each second (0.5 s unpinned).
    if(bar) {
        BOOL due=slot.measured==0 || (slot.exact?now-slot.measured>(slot.pinned?1:.5):(now-slot.since<1 || (now-slot.measured>.5 && slot.misses<80)));
        if(due)[self measureSlot:slot now:now];
    }
    UIView *header=table.tableHeaderView,*host=table.superview;
    if(!table || !bar || !header || !host.window || ![bar isDescendantOfView:header] || CGRectIsNull(slot.field) || _nativeSearching){[self unpin:slot];return;}
    // The header folded away (隐藏聊天列表顶部搜索栏) or the bar hidden: nothing to keep in view.
    if(header.bounds.size.height<CGRectGetMaxY([bar convertRect:slot.field toView:header])-.5){[self unpin:slot];return;}
    for(UIView *v=bar;v && v!=table;v=v.superview)if(v.hidden){[self unpin:slot];return;}
    // WeChat's own search using its bar (or fading it for that): left alone.
    if([self nativeSearchActive:bar page:page] || (bar.alpha<.01 && !slot.pinned)){[self unpin:slot];return;}
    if(!slot.pinned && slot.measured!=now)[self measureSlot:slot now:now];   // FIX114 F: as it is now (after WeChat's search: its full width again)
    if(!slot.clone) {
        slot.clone=[[WXGFloatingSearch alloc] initWithFrame:CGRectZero];
        [slot.clone addTarget:self action:@selector(floatingTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    WXGFloatingSearch *clone=slot.clone;
    // FIX114 F: WeChat's icon and text: each frame in the first second, then
    // twice a second, 90 more tries at most; light / dark switched: now and once
    // more half a second later (WeChat may set fixed colours per theme).
    UIUserInterfaceStyle style=bar.traitCollection.userInterfaceStyle;
    if(slot.lookCopied && style!=slot.lookStyle){slot.lookCopied=NO;slot.lookTries=0;slot.lookTried=0;slot.lookAgainAt=now+.5;}
    if(slot.lookAgainAt && now>=slot.lookAgainAt){slot.lookAgainAt=0;slot.lookCopied=NO;slot.lookTries=0;slot.lookTried=0;}
    if(!slot.lookCopied && slot.exact && slot.lookTries<90 && (now-slot.since<1 || now-slot.lookTried>.5)) {
        slot.lookTried=now;if(now-slot.since>=1)++slot.lookTries;
        if((slot.lookCopied=[clone copyLookOf:bar])){slot.lookStyle=style;slot.lookTries=0;}
    }
    // First shown once both are WeChat's, so it never changes in front of the
    // user; WeChat's own bar (its glass the same box) until then, a second at most.
    if(!slot.pinned && !(slot.exact && slot.lookCopied) && now-slot.since<1)return;
    CGRect natural=[bar convertRect:slot.field toView:host];
    CGFloat pinned=WXGFloatPinnedTop(table,header,CGRectGetMinY(natural),host);
    CGRect frame=natural;if(CGRectGetMinY(natural)<pinned)frame.origin.y=pinned;
    // FIX114 M (user: tapping the home page's search box stuck with a field
    // up that took no typing): at the bar's own place a tap is WeChat's own
    // (its bar takes it: its search opens as without the plugin); held below
    // the title row (the bar scrolled away) the capsule takes it.
    clone.passThrough=CGRectGetMinY(natural)>=pinned-.5;
    WXGRaiseAboveList(clone,host,table);
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(!CGRectEqualToRect(clone.frame,frame))clone.frame=frame;
        clone.hidden=NO;
        [CATransaction commit];
    }];
    if(!slot.pinned){slot.pinned=YES;++slot.pins;}
    if(!slot.states)slot.states=[WXGStateBag new];
    [slot.states conceal:bar];   // FIX114 M: hidden by a mask (a faded view takes no touches)
    [clone.surface tick:time];
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
        [self unpin:slot];
        if([WXGIntegrationHost.shared openWeChatSearchOn:slot.page]){++_directSearches;break;}
        if(table && header)[table setContentOffset:CGPointMake(table.contentOffset.x,CGRectGetMinY(header.frame)-table.adjustedContentInset.top) animated:NO];
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
- (void)hostTick:(CFTimeInterval)time page:(UIViewController *)leaf overlay:(UIView *)overlay transitioning:(BOOL)transitioning {
    BOOL floatOn=[self floatWanted];
    [self updateGapOn:leaf overlay:overlay transitioning:transitioning];   // FIX113 Q
    UITableView *table=_table;UIView *host=table.superview;
    UIView *floatHost=floatOn && host.window && (leaf==_page || transitioning)?host:nil;_floatHost=floatHost;
    // FIX114 E / F: arriving on the home page: where the bar / capsule is drawn, each tick, ~1 s.
    static Class homeClass;static dispatch_once_t homeOnce;dispatch_once(&homeOnce,^{homeClass=NSClassFromString(@"NewMainFrameViewController");});
    BOOL arrived=leaf && _lastTickPage!=leaf;
    if(arrived && homeClass && [leaf isKindOfClass:homeClass]){_returnedAt=time;_returnTrace=[NSMutableArray array];}
    if(arrived)_fieldRechecks=0;
    _lastTickPage=leaf;
    // FIX114 F: measured before WeChat laid out its box (the field's 32.7 pt
    // instead): measured again twice a second, 6 times per arrival / bar, not
    // while the page slides.
    if(_bar.superview && _searchBar && leaf==_page && !transitioning && _fieldRechecks<6 && ![_fieldSource isEqualToString:WXGDrawnBoxSource] && time-_fieldRecheck>.5) {
        _fieldRecheck=time;++_fieldRechecks;
        if(!CGRectIsNull(WXGVisibleSearchBox(_searchBar)))[self searchBarLaidOut:_searchBar];
    }
    if(_bar && _bar.superview)[self placeSegmentIn:floatHost];
    if(_bar.window && _returnTrace && time-_returnedAt<1.2 && _returnTrace.count<90) {
        CGRect r=[_bar convertRect:_bar.bounds toView:nil];UIView *field=_searchBar;
        NSString *line=[NSString stringWithFormat:@"y%.1f h%.1f %@%@ field y%.1f",r.origin.y+WXGCanvasPaddingY,r.size.height-2*WXGCanvasPaddingY,
            _segmentFloating?@"float":@"list",transitioning?@" T":@"",field.window?[field convertRect:field.bounds toView:nil].origin.y:-1];
        if(![_returnTrace.lastObject hasSuffix:line])   // only what changed
            [_returnTrace addObject:[NSString stringWithFormat:@"%.3f %@",time-_returnedAt,line]];
    }
    UIView *hidden=_hiddenBar;   // FIX114 B: kept faded out
    if(_bar.superview && hidden && !_nativeSearching && hidden.alpha>.01 && _states){[_states hide:hidden];++_rehides;}
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
    if(!floatOn){if(_floats.count)[self restoreFloats];return;}
    // FIX114 F (review): capsules floatNativeOn does not see this tick (their
    // page sliding, or on screen under / beside a pushed one): still over
    // WeChat's bar in the same list and that bar kept faded (WeChat may give
    // it its alpha back), else WeChat's bar back. A page gone: its capsule too.
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects) {
        if(!slot.page){[self unpin:slot];[slot.clone removeFromSuperview];slot.clone=nil;continue;}
        if(!slot.pinned || !slot.clone.window || (slot.page==leaf && !transitioning))continue;
        UIView *bar=slot.bar;UITableView *table=slot.table;
        if(!bar || !table || ![bar isDescendantOfView:table.tableHeaderView] || slot.clone.superview!=table.superview || [self nativeSearchActive:bar page:slot.page]){[self unpin:slot];continue;}
        if(slot.states)[slot.states conceal:bar];   // FIX114 M (review): masked, not faded (it must still take touches back on its page)
    }
    if(transitioning)return;   // each page keeps what it shows while it slides
    // FIX114 F: a page pushed over this one in its navigation stack (a chat):
    // the capsule stays (the page carries it off screen and back), so coming
    // back shows no swap from WeChat's bar to it. Anything else: WeChat's bar.
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)if(slot.page!=leaf && !WXGPushedOver(slot.page,leaf))[self unpin:slot];
    if(!leaf.isViewLoaded || !leaf.view.window)return;
    static Class home,contacts;static dispatch_once_t once;
    dispatch_once(&once,^{home=NSClassFromString(@"NewMainFrameViewController");contacts=NSClassFromString(@"ContactsViewController");});
    BOOL native=(contacts && [leaf isKindOfClass:contacts]) || (home && [leaf isKindOfClass:home] && !(_bar && _page==leaf));
    if(native)[self floatNativeOn:leaf time:time];
}
// FIX113 O: a page left native (web, Flutter, these settings): the floating
// capsules go and WeChat's bars come back; the segment bar back in its list.
- (void)suspendFloating {
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)[self unpin:slot];
    if(_segmentFloating)[self placeSegmentIn:nil];
}
- (void)restoreAll {[self restoreFloats];[self restore];}
// The segment bar only: the floating capsules of WeChat's own bars are
// hostTick's (分组栏 off with 悬浮 on keeps them).
- (void)restore {
    if(atomic_load(&WXGFilterIndex)>0)[self applyRule:0 members:nil name:nil];   // FIX113 Q: WeChat's whole list back
    _selected=0;_selectedGroupID=nil;WXGFilterWatching=NO;WXGFilterSnapshot=nil;
    if(!_bar && !_states)return;
    _segmentFloating=NO;
    [_bar removeFromSuperview];_bar.active=NO;_bar=nil;
    [_states restore];_states=nil;_searchBar=nil;_container=nil;_nativeSearching=NO;_hiddenBar=nil;
    ++_restores;_status=@"已恢复微信的搜索栏";
}
// The chat list is read only here: the diagnostics (shown or exported) and
// the settings opening over the page; never while WeChat is used.
- (NSDictionary *)evidence {
    UITableView *table=_table;
    if(table && [self wanted] && (!_probe || CACurrentMediaTime()-_probeAt>5))[self takeProbe];   // FIX113 O: off screen too (settings opened from another tab)
    NSMutableArray *floats=[NSMutableArray array];
    for(WXGFloatSlot *slot in _floats.objectEnumerator.allObjects)
        [floats addObject:@{@"page":slot.page?NSStringFromClass(slot.page.class):@"",@"bar":slot.bar?NSStringFromClass(slot.bar.class):@"",
                            @"field":NSStringFromCGRect(slot.field),@"pinned":@(slot.pinned),@"pins":@(slot.pins),@"taps":@(slot.taps),
                            @"clone":slot.clone?NSStringFromCGRect(slot.clone.frame):@"",@"passThrough":@(slot.clone.passThrough),@"directSearches":@(_directSearches)}];
    UIView *bar=_searchBar;
    return @{@"switch":@([WXGConfig.shared extraNumber:@"chatSegments"]>.5),@"wanted":@([self wanted]),@"status":_status?:@"",
             @"mounted":@(_bar.superview!=nil),@"container":_container?NSStringFromClass(_container.class):@"",
             @"searchBar":bar?[NSString stringWithFormat:@"%@ %@ alpha %.2f",NSStringFromClass(bar.class),NSStringFromCGRect(bar.frame),bar.alpha]:@"",
             @"field":NSStringFromCGRect(_fieldRect),@"fieldSource":_fieldSource?:@"",@"colors":_colorSource?:@"",
             @"counts":@{@"mounts":@(_mounts),@"moves":@(_moves),@"switches":@(_switches),@"restores":@(_restores),@"nativeSearches":@(_nativeSearches)},
             @"selected":@(_selected),@"groups":[self groupsEvidence],@"switchLog":_switchLog?:@[],
             @"bar":_bar?[_bar evidence]:@{},@"chatList":_probe?:@{},
             @"float":@{@"switch":@([WXGConfig.shared extraNumber:@"searchFloat"]>.5),@"segmentFloating":@(_segmentFloating),@"moves":@(_floatMoves),@"native":floats},
             @"gap":@{@"delta":@(_gapDelta)},@"returnTrace":_returnTrace?:@[],
             @"searchBarRehides":@(_rehides),@"commitPlacements":@(_commitPlacements),   // FIX114 B
             @"sessionFilter":[self filterEvidence]};
}
// FIX113 Q: whether the grouping can work here and what it did (counts only).
- (NSArray *)groupsEvidence {
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
