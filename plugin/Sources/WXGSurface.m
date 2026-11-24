#import "WXGIntegration.h"
#import "WXGPresentationMath.h"
#import "WXGButtonPress.h"
#import "WXGPressStretch.h"
#import "WXGMenuCascade.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
// FIX80: the stretch settings (WXGPressStretch.h).
static WXGStretchStyle WXGCurrentStretchStyle(void) {
    WXGConfig *c=WXGConfig.shared;
    return (WXGStretchStyle){c.pressStretchAmount,c.pressStretchCapsule,c.pressStretchMax,c.pressStretchFollow};
}

@interface WXGSurface ()
@property(nonatomic,strong) WXGGlassView *glass;
@property(nonatomic,strong) UIVisualEffectView *fallback;
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *label,*countLabel;
@property(nonatomic) CGRect materialRect;
@property(nonatomic) double press,velocity,target;
@property(nonatomic) double touchX,touchY,touchTargetX,touchTargetY,touchVelocityX,touchVelocityY;
@property(nonatomic) CFTimeInterval lastTick;
@property(nonatomic,strong) UIImpactFeedbackGenerator *feedback;
@property(nonatomic) BOOL trackingInside;
@property(nonatomic) NSUInteger forwardedTaps;
@property(nonatomic,copy) NSString *textLayoutKey;
@property(nonatomic) CGPoint textCorrection;
@property(nonatomic,strong) UIImage *sourceImage;
@property(nonatomic) UIUserInterfaceStyle sourceStyle;
@property(nonatomic,weak) UIView *nativeIconSource;
@property(nonatomic) BOOL preservesNativeIconColors;
@property(nonatomic,strong) UIColor *resolvedNativeTint;
@property(nonatomic) CGPoint nativeReference,nativeReferenceX,nativeReferenceY;
@property(nonatomic,weak) UIView *referenceParent;
@property(nonatomic) BOOL referenceValid,followingDeparture;
@property(nonatomic) CGPoint stretchStart;   // FIX68: where the finger touched down
@end
/* FIX68: hold-and-drag stretch (WXGPressStretch.h). FIX69: the glass stays
   pressed and pulled for as long as the finger is down, however far it goes;
   only a release within this distance of the glass is a tap (UIKit keeps a
   control's touch "inside" for a similar margin), further out it is given up. */
static const CGFloat WXGStretchSlop=40;
static BOOL WXGStretchWanted(void) {return WXGConfig.shared.pressStretch && !UIAccessibilityIsReduceMotionEnabled();}
@interface WXGSurface (WXGTouchObserving)
- (BOOL)observedTouchBegan:(UITouch *)touch;
- (void)observedTouchMoved:(UITouch *)touch;
- (void)observedTouchEnded;
@end
/* FIX70: watches one touch for a material-only surface. It stays "possible"
   (so it never takes the touch from WeChat's views), cannot prevent or be
   prevented by other recognizers, and fails when the touch ends. */
@interface WXGTouchObserver : UIGestureRecognizer
@property(nonatomic,weak) WXGSurface *surface;
@property(nonatomic,weak) UITouch *followed;
@end
@implementation WXGTouchObserver
- (instancetype)initWithSurface:(WXGSurface *)surface {
    if((self=[super initWithTarget:nil action:NULL])) {
        _surface=surface;self.cancelsTouchesInView=NO;self.delaysTouchesBegan=NO;self.delaysTouchesEnded=NO;
    }
    return self;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {(void)other;return NO;}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {(void)other;return NO;}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if(_followed){for(UITouch *touch in touches)[self ignoreTouch:touch forEvent:event];return;}
    UITouch *touch=touches.anyObject;
    if(!touch || ![_surface observedTouchBegan:touch]){self.state=UIGestureRecognizerStateFailed;return;}
    _followed=touch;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;if(_followed && [touches containsObject:_followed])[_surface observedTouchMoved:_followed];
}
- (void)finish:(NSSet<UITouch *> *)touches {
    if(!_followed || ![touches containsObject:_followed])return;
    _followed=nil;[_surface observedTouchEnded];self.state=UIGestureRecognizerStateFailed;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {(void)event;[self finish:touches];}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {(void)event;[self finish:touches];}
- (void)reset {
    [super reset];
    if(_followed){_followed=nil;[_surface observedTouchEnded];}
}
@end
/* FIX71: WeChat's own views on a material-only glass (the input field's
   text, its buttons, the home page's top-left icon) render with the glass's
   pose through an additive transform animation on their layers: what is
   drawn moves and deforms with the glass, while their model geometry (frames,
   WeChat's layout, hit testing, text selection) is untouched. */
static NSString * const WXGFollowKey=@"wxg.stretch";
static void WXGFollowPose(CALayer *layer,CGAffineTransform t) {
    if(CGAffineTransformIsIdentity(t)){[layer removeAnimationForKey:WXGFollowKey];return;}
    CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform"];
    NSValue *value=[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(t)];
    a.fromValue=value;a.toValue=value;a.additive=YES;a.duration=1e6;
    a.fillMode=kCAFillModeForwards;a.removedOnCompletion=NO;
    [layer addAnimation:a forKey:WXGFollowKey];
}

// Track 1 (270 deg solid arc + 5 bottom dots) & Track 2 (two-stage + <-> x swap, zero bounce)
// drawn crisply inside the home "+" glass button.
@interface WXGHomePlusTriggerView : UIView
- (void)setMenuOpen:(BOOL)open animated:(BOOL)animated speed:(double)speed;
- (void)setDotsHidden:(BOOL)hidden;
- (void)updateInkColor;
@end
@implementation WXGHomePlusTriggerView {
    CAShapeLayer *_arcLayer;
    CALayer *_symbolRotLayer;
    CAShapeLayer *_symbolLayer;
    CALayer *_dots[WXGMenuParticleCount];
    CGSize _builtSize;
    BOOL _menuOpen;
    BOOL _dotsHidden;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.backgroundColor=UIColor.clearColor;self.opaque=NO;
        _arcLayer=[CAShapeLayer layer];
        _arcLayer.fillColor=UIColor.clearColor.CGColor;
        _arcLayer.lineCap=kCALineCapRound;
        _arcLayer.lineWidth=1.8;
        _arcLayer.strokeStart=0;
        _arcLayer.strokeEnd=1;
        [self.layer addSublayer:_arcLayer];
        for(int i=0;i<WXGMenuParticleCount;i++) {
            CALayer *dot=[CALayer layer];
            _dots[i]=dot;
            [self.layer addSublayer:dot];
        }
        _symbolRotLayer=[CALayer layer];
        [self.layer addSublayer:_symbolRotLayer];
        _symbolLayer=[CAShapeLayer layer];
        _symbolLayer.fillColor=UIColor.clearColor.CGColor;
        _symbolLayer.lineCap=kCALineCapRound;
        _symbolLayer.lineWidth=1.85;
        [_symbolRotLayer addSublayer:_symbolLayer];
        [self updateInkColor];
    }
    return self;
}
- (void)updateInkColor {
    UIColor *ink=[UIColor.labelColor resolvedColorWithTraitCollection:self.traitCollection];
    CGColorRef cg=ink.CGColor;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _arcLayer.strokeColor=cg;
    _symbolLayer.strokeColor=cg;
    for(int i=0;i<WXGMenuParticleCount;i++)_dots[i].backgroundColor=cg;
    [CATransaction commit];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(!previous || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])[self updateInkColor];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize sz=self.bounds.size;
    if(sz.width<4 || sz.height<4)return;
    if(CGSizeEqualToSize(sz,_builtSize))return;
    _builtSize=sz;
    CGFloat side=MIN(sz.width,sz.height);
    CGPoint center=CGPointMake(sz.width*.5,sz.height*.5);
    CGFloat ringR=(CGFloat)WXGMenuRingRadius(side);
    CGFloat dotD=(CGFloat)WXGMenuRingDotDiameter();
    CGFloat arm=round(side*.165*2)/2;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _arcLayer.frame=self.bounds;
    // 135 deg (7:30) clockwise to 45 deg (4:30) = 270 deg solid arc.
    UIBezierPath *arc=[UIBezierPath bezierPathWithArcCenter:center radius:ringR
        startAngle:(CGFloat)(135.*M_PI/180.) endAngle:(CGFloat)(45.*M_PI/180.) clockwise:YES];
    _arcLayer.path=arc.CGPath;
    _arcLayer.lineWidth=MAX(1.6,MIN(2.0,side*.041));
    for(int i=0;i<WXGMenuParticleCount;i++) {
        double a=WXGMenuRingDotAngle(i);
        CALayer *dot=_dots[i];
        dot.bounds=CGRectMake(0,0,dotD,dotD);
        dot.cornerRadius=dotD*.5;
        dot.position=CGPointMake(center.x+ringR*(CGFloat)cos(a),center.y+ringR*(CGFloat)sin(a));
        dot.hidden=_dotsHidden;
    }
    CGRect symBounds=CGRectMake(0,0,arm*2+4,arm*2+4);
    _symbolRotLayer.bounds=symBounds;
    _symbolRotLayer.position=center;
    _symbolLayer.bounds=symBounds;
    _symbolLayer.position=CGPointMake(symBounds.size.width*.5,symBounds.size.height*.5);
    CGPoint sc=CGPointMake(symBounds.size.width*.5,symBounds.size.height*.5);
    UIBezierPath *plus=[UIBezierPath bezierPath];
    [plus moveToPoint:CGPointMake(sc.x-arm,sc.y)];[plus addLineToPoint:CGPointMake(sc.x+arm,sc.y)];
    [plus moveToPoint:CGPointMake(sc.x,sc.y-arm)];[plus addLineToPoint:CGPointMake(sc.x,sc.y+arm)];
    _symbolLayer.path=plus.CGPath;
    _symbolLayer.lineWidth=MAX(1.7,MIN(2.1,side*.043));
    [CATransaction commit];
    [self updateInkColor];
}
- (void)setDotsHidden:(BOOL)hidden {
    if(_dotsHidden==hidden)return;
    _dotsHidden=hidden;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(int i=0;i<WXGMenuParticleCount;i++)_dots[i].hidden=hidden;
    [CATransaction commit];
}
- (void)setMenuOpen:(BOOL)open animated:(BOOL)animated speed:(double)speed {
    if(animated && _menuOpen==open)return;
    _menuOpen=open;
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    CAShapeLayer *arcNow=(CAShapeLayer *)_arcLayer.presentationLayer?:_arcLayer;
    CALayer *rotNow=_symbolRotLayer.presentationLayer?:_symbolRotLayer;
    CALayer *scaleNow=_symbolLayer.presentationLayer?:_symbolLayer;
    CGFloat curStroke=arcNow.strokeEnd;
    CATransform3D rt=rotNow.transform,st=scaleNow.transform;
    double curRot=atan2(rt.m12,rt.m11);if(!isfinite(curRot))curRot=0.;
    double curScale=hypot(st.m11,st.m12);if(curScale<.1 || !isfinite(curScale))curScale=1.;
    double targetRot=open?M_PI_4:0.;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    [_arcLayer removeAnimationForKey:@"wxg.plus.arc"];
    [_symbolRotLayer removeAnimationForKey:@"wxg.plus.rot"];
    [_symbolLayer removeAnimationForKey:@"wxg.plus.scale"];
    _arcLayer.strokeEnd=open?0.:1.;
    _symbolRotLayer.transform=open?CATransform3DMakeRotation((CGFloat)M_PI_4,0,0,1):CATransform3DIdentity;
    _symbolLayer.transform=CATransform3DIdentity;
    if(animated) {
        CFTimeInterval now=CACurrentMediaTime();
        // Track 1: 270 deg arc trim
        CABasicAnimation *arcAnim=[CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        arcAnim.fromValue=@(curStroke);arcAnim.toValue=@(open?0.:1.);
        arcAnim.duration=(open?.150:.220)/v;
        arcAnim.beginTime=[_arcLayer convertTime:now+(open?0.:.030/v) fromLayer:nil];
        arcAnim.timingFunction=open?[CAMediaTimingFunction functionWithControlPoints:.4f :0.f :1.f :1.f]
                                   :[CAMediaTimingFunction functionWithControlPoints:.22f :1.f :.36f :1.f];
        arcAnim.fillMode=kCAFillModeBackwards;arcAnim.removedOnCompletion=YES;
        [_arcLayer addAnimation:arcAnim forKey:@"wxg.plus.arc"];

        // Track 2: two-stage scale swap (+ <-> x) with zero-overshoot smooth recovery (no bounce)
        if(fabs(curRot-targetRot)>.05) {
            double total=(open?.400:.350)/v;
            double midFrac=open?(.250/.400):(.180/.350);
            CAKeyframeAnimation *scaleAnim=[CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            scaleAnim.values=@[@(curScale),@0.45,@1.0];
            scaleAnim.keyTimes=@[@0.0,@(midFrac),@1.0];
            scaleAnim.timingFunctions=@[
                [CAMediaTimingFunction functionWithControlPoints:.4f :0.f :.6f :1.f],
                [CAMediaTimingFunction functionWithControlPoints:.22f :1.f :.36f :1.f]
            ];
            scaleAnim.duration=total;
            scaleAnim.fillMode=kCAFillModeBackwards;scaleAnim.removedOnCompletion=YES;
            [_symbolLayer addAnimation:scaleAnim forKey:@"wxg.plus.scale"];

            // Discrete mode requires keyTimes.count == values.count + 1 ([0, midFrac, 1]).
            CAKeyframeAnimation *rotAnim=[CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
            rotAnim.calculationMode=kCAAnimationDiscrete;
            rotAnim.values=@[@(curRot),@(targetRot)];
            rotAnim.keyTimes=@[@0.0,@(midFrac),@1.0];
            rotAnim.duration=total;
            rotAnim.fillMode=kCAFillModeBackwards;rotAnim.removedOnCompletion=YES;
            [_symbolRotLayer addAnimation:rotAnim forKey:@"wxg.plus.rot"];
        }else if(fabs(curScale-1.)>.01) {
            // Interrupted before the midpoint swap: recover smoothly to 1.0 without dipping again.
            CABasicAnimation *recover=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
            recover.fromValue=@(curScale);recover.toValue=@1.0;
            recover.duration=.170/v;
            recover.timingFunction=[CAMediaTimingFunction functionWithControlPoints:.22f :1.f :.36f :1.f];
            recover.fillMode=kCAFillModeBackwards;recover.removedOnCompletion=YES;
            [_symbolLayer addAnimation:recover forKey:@"wxg.plus.scale"];
        }
    }
    [CATransaction commit];
}
@end

@implementation WXGSurface {
    WXGStretchState _stretch;
    WXGTouchObserver *_touchObserver;
    NSHashTable<UIView *> *_followers;
    BOOL _followTouching;                 // FIX72: an observed touch is down
    NSArray<NSString *> *_followerNames;  // FIX72: diagnostics
    BOOL _traitsPending;                  // FIX114 M: an appearance change while out of a window
    UIImage *_resolvedFrom;               // FIX114 M: the artwork and traits the icon was last drawn from
    UITraitCollection *_resolvedTraits;   // light / dark, contrast, level, bold text
    UIColor *_resolvedTint;
    NSString *_resolvedRole;
    BOOL _resolvedPreserve;
    UIImageView *_trailingView;           // FIX114 M: trailingSymbol
    WXGHomePlusTriggerView *_plusTriggerView;
    CFTimeInterval _lastFollow;           // FIX114 T: holdsPlace's fade
    CFTimeInterval _hostAwaySince;        // FIX114 U: holdsPlace: the native view out of the window since
}
- (void)setHomePlusTrigger:(BOOL)trigger {
    if(_homePlusTrigger==trigger)return;
    _homePlusTrigger=trigger;
    if(trigger && !_plusTriggerView) {
        _plusTriggerView=[WXGHomePlusTriggerView new];
        [self addSubview:_plusTriggerView];
    }
    _plusTriggerView.hidden=!trigger;
    if(trigger){_iconView.hidden=YES;if(_nativeContent)_nativeContent.hidden=YES;}
    else{_iconView.hidden=!_sourceImage;if(_nativeContent)_nativeContent.hidden=NO;[_plusTriggerView setMenuOpen:NO animated:NO speed:1.];[_plusTriggerView setDotsHidden:NO];}
    [self setNeedsLayout];
}
- (void)setHomePlusMenuOpen:(BOOL)open animated:(BOOL)animated speed:(double)speed {
    if(!_homePlusTrigger || !_plusTriggerView)return;
    [_plusTriggerView setMenuOpen:open animated:animated speed:speed];
}
- (void)setHomePlusDotsHidden:(BOOL)hidden {
    if(!_plusTriggerView)return;
    [_plusTriggerView setDotsHidden:hidden];
}
- (void)setNativeContent:(UIView *)content {   // FIX114 V
    if(content==_nativeContent)return;
    [_nativeContent removeFromSuperview];_nativeContent=content;
    if(content){content.userInteractionEnabled=NO;content.isAccessibilityElement=NO;content.accessibilityElementsHidden=YES;content.hidden=_homePlusTrigger;[self addSubview:content];}
    [self setNeedsLayout];
}
- (void)setNativeContentOrigin:(CGPoint)origin {
    if(CGPointEqualToPoint(origin,_nativeContentOrigin))return;
    _nativeContentOrigin=origin;[self setNeedsLayout];
}
- (void)setTrailingSymbol:(UIImage *)symbol {
    if(symbol==_trailingSymbol)return;
    _trailingSymbol=symbol;
    if(symbol && !_trailingView) {
        _trailingView=[UIImageView new];_trailingView.userInteractionEnabled=NO;_trailingView.contentMode=UIViewContentModeScaleAspectFit;
        _trailingView.tintColor=UIColor.systemGray2Color;   // iOS 26: #AEAEB2 on white (measured 173,173,173)
        [self addSubview:_trailingView];
    }
    _trailingView.image=symbol;_trailingView.hidden=symbol==nil;
    [self setNeedsLayout];
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.clipsToBounds=NO;
        self.layer.shadowColor=UIColor.blackColor.CGColor;self.layer.shadowOpacity=0;self.layer.shadowRadius=18;self.layer.shadowOffset=CGSizeMake(0,8);
        _fallback=[[UIVisualEffectView alloc]initWithEffect:nil];
        _fallback.userInteractionEnabled=NO;_fallback.clipsToBounds=YES;_fallback.layer.cornerCurve=kCACornerCurveContinuous;
        [self addSubview:_fallback];
        _glass=[[WXGGlassView alloc]initWithFrame:self.bounds];_glass.buttonPressEffect=YES;[self addSubview:_glass];
        _iconView=[UIImageView new];_iconView.userInteractionEnabled=NO;_iconView.contentMode=UIViewContentModeScaleAspectFit;[self addSubview:_iconView];
        _label=[UILabel new];_label.textAlignment=NSTextAlignmentCenter;_label.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _label.opaque=NO;_label.backgroundColor=UIColor.clearColor;
        _label.lineBreakMode=NSLineBreakByTruncatingTail;[self addSubview:_label];
        _countLabel=[UILabel new];_countLabel.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        _countLabel.textAlignment=NSTextAlignmentCenter;   // FIX114 L (user: always a black capsule with white digits; dark mode should be the other way round)
        _countLabel.textColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?UIColor.blackColor:UIColor.whiteColor;}];
        _countLabel.backgroundColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?UIColor.whiteColor:UIColor.blackColor;}];
        _countLabel.clipsToBounds=YES;_countLabel.layer.cornerCurve=kCACornerCurveContinuous;[self addSubview:_countLabel];
        _feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];
        // WXGGlassView owns a shared, explicitly BGRA 1x1 transparent texture.
        // A transparent UIKit UIImage can be alpha-only and fail MTK decoding.
        __weak WXGSurface *weak=self;
        _glass.onReady=^(BOOL ready){WXGSurface *s=weak;if(!s)return;s.glass.hidden=!ready || s.plain;[s applyConfig];};
        _glass.onFirstFrame=^{WXGSurface *s=weak;if(!s)return;s.fallback.hidden=YES;};
        // Semantic colour follows this surface's actual appearance immediately;
        // a previous page's cached background cannot repaint new-theme glyphs.
        _label.textColor=UIColor.labelColor;_iconView.tintColor=UIColor.labelColor;
        self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    }return self;
}
- (void)setActive:(BOOL)active {if(_active==active)return;_active=active;_glass.active=active && !_plain;
    if(!active && _touchObserver){[_touchObserver.view removeGestureRecognizer:_touchObserver];_touchObserver=nil;}
    if(!active){_target=_press=_velocity=0;_touchX=_touchY=_touchTargetX=_touchTargetY=_touchVelocityX=_touchVelocityY=0;_stretch=(WXGStretchState){0};_glass.pressAmount=0;_lastTick=0;_followingDeparture=NO;[self updateContentTransform];}}
// FIX28: in render-server mode the fallback tint never shows: the live glass
// renders as soon as it is configured, and the tint read as a grey flash on a
// freshly opened plus menu.
static BOOL WXGFallbackAllowed(void) {return WXGEffectiveRenderMode()<2;}
- (void)setPlain:(BOOL)plain {_plain=plain;_glass.hidden=plain || (!_glass.ready && WXGFallbackAllowed());_fallback.hidden=plain || _glass.hasPresentedFrame || !WXGFallbackAllowed();_glass.active=_active && !plain;}
- (void)placeMaterial:(CGRect)rect inParent:(UIView *)parent {
    // FIX114 M (crash): moved straight into the new parent. Taken out first,
    // it left the window and came back, and its colours were resolved again
    // on every move (UIKit's appearance setters: a hang when moved in a loop).
    if(self.superview!=parent){if(parent)[parent addSubview:self];else [self removeFromSuperview];}
    CGRect canvas=CGRectInset(rect,-WXGCanvasPaddingX,-WXGCanvasPaddingY);
    CGRect material=CGRectMake(WXGCanvasPaddingX,WXGCanvasPaddingY,rect.size.width,rect.size.height);
    BOOL sizeChanged=!CGRectEqualToRect(material,_materialRect);
    // Layout can run during an interactive transition. UIView.frame is undefined
    // under a non-identity transform; never feed last frame's presentation delta
    // back into the next model-sized canvas.
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(self.followsNative)self.transform=CGAffineTransformIdentity;
        if(!CGRectEqualToRect(self.frame,canvas))self.frame=canvas;
        if(self.followsNative)self.restingFrame=canvas;
        if(sizeChanged){self.textLayoutKey=nil;self.textCorrection=CGPointZero;self.materialRect=material;[self setNeedsLayout];}
        [self layoutIfNeeded];
        [CATransaction commit];
    }];
}
- (void)bindMotionHost:(UIView *)host owner:(UIViewController *)owner {
    BOOL sameDeparture=_followingDeparture && _motionHost==host && _motionOwner==owner && _referenceParent==self.superview;
    if(_motionHost!=host || _motionOwner!=owner){_textLayoutKey=nil;_textCorrection=CGPointZero;[self setNeedsLayout];}
    _motionHost=host;_motionOwner=owner;_followsNative=host!=nil;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.transform=CGAffineTransformIdentity;
        // frame is only a model rectangle after the previous presentation
        // transform is removed. Saving it sooner remembers a scaled/shifted box.
        self.restingFrame=self.frame;
        [CATransaction commit];
    }];
    // UIKit may lay out the outgoing item again before the incoming view is
    // attached. Such a rebind must not replace the frozen start with its endpoint.
    if(!sameDeparture){_followingDeparture=NO;_referenceValid=NO;[self rememberNativeReference];}
}
- (void)rememberNativeReference {
    UIView *host=_motionHost,*parent=self.superview;if(!host || !parent || !host.window)return;
    CGPoint mid=CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds));
    _nativeReference=[host.layer convertPoint:mid toLayer:parent.layer];
    _nativeReferenceX=[host.layer convertPoint:CGPointMake(mid.x+1,mid.y) toLayer:parent.layer];
    _nativeReferenceY=[host.layer convertPoint:CGPointMake(mid.x,mid.y+1) toLayer:parent.layer];
    _referenceParent=parent;_referenceValid=YES;
}
- (void)beginNativeDeparture {
    if(!_followsNative)return;
    if(!_referenceValid)[self rememberNativeReference];
    _followingDeparture=YES;
}
- (void)followNativePresentation {
    if(!_followsNative || !_motionHost || !self.superview)return;
    UIView *host=_motionHost;UIView *parent=self.superview;
    // FIX114 T (diagnostics_13: at the start of every swipe back the chat's
    // avatar and capsule went for about 80 ms: WeChat's title was out of the
    // window as it swapped it): held in place, it stays as it is meanwhile.
    // FIX114 U (diagnostics_14: still about 95 ms gone at the start of each
    // swipe back: WeChat swaps its title before the host has seen the
    // transition): not only during one; at most half a second.
    BOOL holding=_holdsPlace && !self.hidden;CFTimeInterval now=CACurrentMediaTime();
    if(!host.window || host.window!=parent.window) {
        if(holding){if(!_hostAwaySince)_hostAwaySince=now;if(now-_hostAwaySince<.5)return;}
        _hostAwaySince=0;self.hidden=YES;return;
    }
    _hostAwaySince=0;
    CALayer *model=host.layer,*present=model.presentationLayer;
    CALayer *destination=parent.layer.presentationLayer;
    if(!present || !destination){present=model;destination=parent.layer;}
    CGPoint middle=CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds));
    CGPoint normal=[model convertPoint:middle toLayer:parent.layer];
    CGPoint shown=[present convertPoint:middle toLayer:destination];
    CGPoint nx=[model convertPoint:CGPointMake(middle.x+1,middle.y) toLayer:parent.layer];
    CGPoint ny=[model convertPoint:CGPointMake(middle.x,middle.y+1) toLayer:parent.layer];
    CGPoint px=[present convertPoint:CGPointMake(middle.x+1,middle.y) toLayer:destination];
    CGPoint py=[present convertPoint:CGPointMake(middle.x,middle.y+1) toLayer:destination];
    if(_followingDeparture && _referenceValid && _referenceParent==parent) {
        // The outgoing model already holds the animation's END position.
        // Its glass was laid out at the pre-transition position: compare with
        // that saved basis, including while the native gesture reverses.
        normal=_nativeReference;nx=_nativeReferenceX;ny=_nativeReferenceY;
    }else if(!_followingDeparture) {
        _nativeReference=normal;_nativeReferenceX=nx;_nativeReferenceY=ny;
        _referenceParent=parent;_referenceValid=YES;
    }
    WXGAffine delta=WXGPresentationDelta((WXGPoint){normal.x,normal.y},(WXGPoint){nx.x,nx.y},(WXGPoint){ny.x,ny.y},
      (WXGPoint){shown.x,shown.y},(WXGPoint){px.x,px.y},(WXGPoint){py.x,py.y},(WXGPoint){CGRectGetMidX(_restingFrame),CGRectGetMidY(_restingFrame)});
    if(!_nativeTransitionActive || _holdsPlace)delta=(WXGAffine){1,0,0,1,0,0};   // FIX114 S: held in place
    CGFloat alpha=1;BOOL hidden=NO;
    for(UIView *v=host;v && v!=parent;v=v.superview){
        if([parent isDescendantOfView:v])break;
        CALayer *layer=v.layer.presentationLayer?:v.layer;
        alpha*=layer.opacity;if(layer.hidden){hidden=YES;break;}

    }
    _nativeAlpha=alpha;_nativeHidden=hidden;
    // FIX114 T: a held glass fades at most this fast (a fade of WeChat's title
    // passes; a swap's one frame at 0 opacity or hidden is no blink).
    if(holding) {
        double dt=_lastFollow>0?MIN(MAX(now-_lastFollow,0),1/30.):1/60.;CGFloat step=MAX(.06,dt*9);
        if(hidden){hidden=NO;alpha=0;}
        alpha=WXGClamp(alpha,self.alpha-step,self.alpha+step);
    }
    _lastFollow=now;
    if(_alphaFloor>.001){if(hidden){hidden=NO;alpha=0;}alpha=MAX(alpha,_alphaFloor);}   // FIX93
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.transform=CGAffineTransformMake(delta.a,delta.b,delta.c,delta.d,delta.tx,delta.ty);
        self.alpha=WXGClamp(alpha,0,1);self.hidden=hidden || alpha<.001;
        [CATransaction commit];
    }];
}
- (void)setMaximumCornerRadius:(CGFloat)radius {
    if(_maximumCornerRadius==radius)return;_maximumCornerRadius=radius;
    _glass.maximumCornerRadius=radius;[self setNeedsLayout];
}

// FIX108 C: the same artwork handed over as a new image object (the home
// "+" got one every frame of a pull-down: cropped and re-tinted every frame).
static BOOL WXGSameArtwork(UIImage *a,UIImage *b) {
    if(a==b)return YES;if(!a || !b)return NO;
    return a.imageAsset && a.imageAsset==b.imageAsset && CGSizeEqualToSize(a.size,b.size) && a.scale==b.scale && a.renderingMode==b.renderingMode;
}
- (void)setImage:(UIImage *)image title:(NSString *)title count:(NSString *)count {
    if(image && _sourceImage && image!=_sourceImage && WXGSameArtwork(_sourceImage,image))image=_sourceImage;
    BOOL imageChanged=_sourceImage!=image || _sourceStyle!=self.traitCollection.userInterfaceStyle;
    if(imageChanged){_sourceImage=image;[self resolveSourceImage];}
    BOOL hideIcon=_homePlusTrigger || !image;
    if(!imageChanged && [_label.text?:@"" isEqual:title?:@""] && [_countLabel.text?:@"" isEqual:count?:@""] && _iconView.hidden==hideIcon)return;
    if(![_label.text isEqual:title]){_label.text=title;_textLayoutKey=nil;_textCorrection=CGPointZero;}
    if(![_countLabel.text isEqual:count])_countLabel.text=count;
    _iconView.hidden=hideIcon;_label.hidden=!title.length;_countLabel.hidden=!count.length;
    self.accessibilityLabel=count.length?[NSString stringWithFormat:@"返回，%@ 条未读",count]:title.length?title:self.role;
    [self setNeedsLayout];
}
// FIX109: a photo, not an icon: the title's avatar and the chat page's avatar button.
static BOOL WXGPhotoRole(NSString *role) {return [role isEqual:@"avatar"] || [role isEqual:@"chatAvatarButton"];}
- (void)resolveSourceImage {
    _sourceStyle=self.traitCollection.userInterfaceStyle;
    UITraitCollection *traits=_preservesNativeIconColors && _nativeIconSource?_nativeIconSource.traitCollection:self.traitCollection;
    UIImage *image=_sourceImage.imageAsset?[_sourceImage.imageAsset imageWithTraitCollection:traits]:_sourceImage;
    UIColor *tint=_preservesNativeIconColors?(_nativeIconSource.tintColor?:UIColor.labelColor):UIColor.labelColor;
    _resolvedNativeTint=[tint resolvedColorWithTraitCollection:traits];
    // FIX114 M (crash): UIKit's appearance setters are slow (each one looks
    // through the class's methods); a value already set is not set again,
    // and the same artwork under the same appearance is not cropped again.
    BOOL sameTraits=_resolvedTraits && ![traits hasDifferentColorAppearanceComparedToTraitCollection:_resolvedTraits] && traits.legibilityWeight==_resolvedTraits.legibilityWeight;
    BOOL redraw=!(_sourceImage==_resolvedFrom && sameTraits && (tint==_resolvedTint || [tint isEqual:_resolvedTint]) &&
                  _preservesNativeIconColors==_resolvedPreserve && (_role==_resolvedRole || [_role isEqual:_resolvedRole]) && (image || !_iconView.image));
    if(redraw) {
        _resolvedFrom=_sourceImage;_resolvedTraits=traits;_resolvedTint=tint;_resolvedPreserve=_preservesNativeIconColors;_resolvedRole=[_role copy];
        [traits performAsCurrentTraitCollection:^{
            UIImage *cropped=image && !WXGPhotoRole(self.role)?WXGCropInk(image,tint):image;
            // Video uses native original artwork or its actual template tint;
            // a white glyph is not evidence that it should become labelColor.
            BOOL adaptive=!self.preservesNativeIconColors && !WXGPhotoRole(self.role) && WXGImageIsMonochrome(image);
            UIImage *shown=adaptive?[cropped imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]:cropped;
            if(self.iconView.image!=shown)self.iconView.image=shown;
        }];
    }
    if(_label.textColor!=UIColor.labelColor)_label.textColor=UIColor.labelColor;
    UIColor *iconTint=_iconTint?:_resolvedNativeTint;
    if(!(_iconView.tintColor==iconTint || [_iconView.tintColor isEqual:iconTint]))_iconView.tintColor=iconTint;
    if(([_role isEqual:@"avatar"] && _plain) || [_role isEqual:@"chatAvatarButton"])[self styleAvatarRing];
}
// FIX94: about 1.5 pt of translucent grey at the avatar's edge, drawn over the
// photo inside its circle (a mid grey reads on light and dark photos alike).
// FIX95: its width and colour (with opacity, per appearance) are settings.
- (void)styleAvatarRing {
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    WXGConfig *c=WXGConfig.shared;
    UIColor *ring=WXGColor([c avatarBorderHexDark:dark])?:[UIColor colorWithWhite:dark?.62:.5 alpha:dark?.42:.32];
    CGFloat width=WXGClamp(c.avatarBorderWidth,0,4);
    _iconView.layer.borderWidth=width<.01?0:MIN(width,_iconView.bounds.size.width*.25);
    _iconView.layer.borderColor=ring.CGColor;
}
- (void)setIconTint:(UIColor *)tint {
    if(tint==_iconTint || [tint isEqual:_iconTint])return;
    _iconTint=tint;_iconView.tintColor=tint?:_resolvedNativeTint;
}
- (void)setNativeIconSource:(UIView *)source preservingColors:(BOOL)preserve {
    BOOL changed=_nativeIconSource!=source || _preservesNativeIconColors!=preserve;
    _nativeIconSource=source;_preservesNativeIconColors=preserve;
    UIColor *color=[(source.tintColor?:UIColor.labelColor) resolvedColorWithTraitCollection:source.traitCollection?:self.traitCollection];
    if(changed || (preserve && ![_resolvedNativeTint isEqual:color]))[self resolveSourceImage];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous && ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])return;
    // FIX114 M (crash): out of a window the traits are not the page's; the
    // work is done once it is back in one.
    if(!self.window){_traitsPending=YES;return;}
    _traitsPending=NO;[self resolveSourceImage];[self applyConfig];[_plusTriggerView updateInkColor];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if(!self.window || !_traitsPending)return;
    _traitsPending=NO;
    if(_sourceStyle!=self.traitCollection.userInterfaceStyle){[self resolveSourceImage];[self applyConfig];[_plusTriggerView updateInkColor];}
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(CGRectIsEmpty(_materialRect))return;
    [UIView performWithoutAnimation:^{
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _iconView.transform=_label.transform=_countLabel.transform=CGAffineTransformIdentity;
    if(_trailingView)_trailingView.transform=CGAffineTransformIdentity;   // FIX114 M
    if(_plusTriggerView){_plusTriggerView.transform=CGAffineTransformIdentity;_plusTriggerView.frame=_materialRect;}
    _glass.transform=CGAffineTransformIdentity;
    _glass.frame=self.bounds;_glass.glassRect=_materialRect;
    CGFloat radius=MIN(_materialRect.size.width,_materialRect.size.height)*.5;
    if(_maximumCornerRadius>0)radius=MIN(radius,_maximumCornerRadius);
    _fallback.transform=CGAffineTransformIdentity;
    _fallback.frame=_materialRect;_fallback.layer.cornerRadius=radius;
    self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:_materialRect cornerRadius:radius].CGPath;
    self.layer.shadowOpacity=0;
    double h=_materialRect.size.height,w=_materialRect.size.width;
    CGFloat iconMax=MIN(26,h*.50);
    if([_role isEqual:@"dictation"])iconMax=MIN(20,h*.48);
    if([_role isEqual:@"send"])iconMax=MIN(28,h*.80);
    // FIX88: the (filled) smiley about the microphone's height beside it (it
    // was a 26 pt disc next to a 17 pt microphone).
    if([_role isEqual:@"emoji"])iconMax=MIN(19,h*.67);
    if([_role isEqual:@"avatar"])iconMax=MAX(24,h-10);
    BOOL photo=[_role isEqual:@"avatar"] && _plain;
    if([_role isEqual:@"chatAvatarButton"] && _iconView.image) {
        // FIX109: the chat's avatar in the button's glass, a circle inset by
        // the setting (0 = the whole glass), aspect-filled, with the avatar ring.
        CGFloat side=MIN(w,h),inset=WXGClamp([WXGConfig.shared extraNumber:@"chatAvatarInset"],0,side*.3),d=MAX(8,side-2*inset);
        _iconView.contentMode=UIViewContentModeScaleAspectFill;
        _iconView.frame=CGRectMake(CGRectGetMidX(_materialRect)-d*.5,CGRectGetMidY(_materialRect)-d*.5,d,d);_iconView.clipsToBounds=YES;
        _iconView.layer.cornerCurve=kCACornerCurveCircular;_iconView.layer.cornerRadius=d*.5;
        [self styleAvatarRing];
    } else if(photo && _iconView.image) {
        // FIX94: the title's avatar is the photo itself at the glass's size
        // (no glass): it fills the whole circle, aspect-filled so it never
        // shows an edge or a notch, with a thin grey translucent ring.
        _iconView.contentMode=UIViewContentModeScaleAspectFill;
        _iconView.frame=_materialRect;_iconView.clipsToBounds=YES;
        _iconView.layer.cornerCurve=kCACornerCurveCircular;_iconView.layer.cornerRadius=MIN(w,h)*.5;
        [self styleAvatarRing];
    } else if(_iconView.image) {
        _iconView.contentMode=UIViewContentModeScaleAspectFit;_iconView.layer.borderWidth=0;
        WXGRect r=WXGCenteredInk(w,h,_iconView.image.size.width,_iconView.image.size.height,iconMax);
        if(_naturalIconSize) {   // FIX113: the glyph's own size (cropped to its ink: WeChat's own size on screen)
            CGFloat iw=_iconView.image.size.width,ih=_iconView.image.size.height,fit=MIN(1,MIN(w*.92/MAX(iw,.01),h*.92/MAX(ih,.01)));
            r=(WXGRect){(w-iw*fit)*.5,(h-ih*fit)*.5,iw*fit,ih*fit};
        }
        if(_countLabel.text.length)r.x=(h-r.w)*.5;
        CGRect iconFrame=CGRectOffset(WXGCGRect(r),_materialRect.origin.x,_materialRect.origin.y);
        if(_naturalIconSize) {   // FIX113 C: at its own size, on whole device pixels (not resampled between them)
            CGFloat px=self.traitCollection.displayScale>0?self.traitCollection.displayScale:UIScreen.mainScreen.scale;
            iconFrame.origin=CGPointMake(round(iconFrame.origin.x*px)/px,round(iconFrame.origin.y*px)/px);
        }
        _iconView.frame=iconFrame;
        _iconView.clipsToBounds=[_role isEqual:@"avatar"];
        _iconView.layer.cornerRadius=_iconView.clipsToBounds?MIN(r.w,r.h)*.5:0;
    }
    _label.frame=CGRectInset(_materialRect,10,0);
    // FIX115 K (hang on 发起群聊, 10-26 13:03: a glass with no text rendered its
    // empty label on every layout — never "available", so never remembered —
    // and a layer render lays out every dirty view above it first: in a page
    // being presented that is the whole page, the plugin's hooks in it, more
    // glasses, more renders): only a label with text is measured.
    if(!_label.hidden && _label.text.length && !_iconView.image && self.window) {
        NSString *key=[NSString stringWithFormat:@"%@/%@/%.3f/%@/%.1f",_label.text,_label.font.fontName,_label.font.pointSize,NSStringFromCGSize(_label.bounds.size),self.window.screen.scale];
        if(![_textLayoutKey isEqual:key]) {
            NSDictionary *pixel=WXGRenderedInkEvidence(_label);
            if([pixel[@"available"] boolValue]) {
                NSArray *p=pixel[@"windowRect"];CGRect r=CGRectMake([p[0] doubleValue],[p[1] doubleValue],[p[2] doubleValue],[p[3] doubleValue]);
                CGRect material=[self convertRect:_materialRect toView:self.window];
                _textCorrection=CGPointMake(CGRectGetMidX(material)-CGRectGetMidX(r),CGRectGetMidY(material)-CGRectGetMidY(r));
            }
            _textLayoutKey=key;   // FIX115 K (review): once per key, ink or not (a label with no ink rendered on every layout)
        }
        _label.frame=CGRectOffset(_label.frame,_textCorrection.x,_textCorrection.y);
    }
    // FIX114 M: the trailing symbol after the text, the two centred together.
    if(_trailingView && _trailingSymbol && !_label.hidden && _label.text.length && !_iconView.image) {
        CGSize s=_trailingSymbol.size;
        CGFloat sh=_trailingSymbolHeight>0?MIN(_trailingSymbolHeight,h*.7):MIN(12,h*.4),sw=s.height>0?sh*s.width/s.height:sh*.4;
        CGFloat gap=_trailingGap>0?_trailingGap:7;
        CGFloat textW=MIN(ceil([_label.text sizeWithAttributes:@{NSFontAttributeName:_label.font}].width),CGRectGetWidth(_label.frame));
        WXGTrailingPlace place=WXGTrailingLayoutBiased(CGRectGetMidX(_materialRect),textW,gap,sw,_trailingBias);
        _label.frame=CGRectOffset(_label.frame,place.textMidX-CGRectGetMidX(_materialRect),0);
        CGFloat x=place.symbolX;
        _trailingView.transform=CGAffineTransformIdentity;
        _trailingView.frame=CGRectMake(x,CGRectGetMidY(_materialRect)-sh*.5,sw,sh);
        _trailingView.hidden=NO;
    }else if(_trailingView)_trailingView.hidden=YES;
    if(_nativeContent) {   // FIX114 V: where the native control is relative to its glass, on whole device pixels
        CGFloat px=self.traitCollection.displayScale>0?self.traitCollection.displayScale:UIScreen.mainScreen.scale;
        CGSize size=_nativeContent.bounds.size;
        CGFloat x=round((_materialRect.origin.x+_nativeContentOrigin.x)*px)/px,y=round((_materialRect.origin.y+_nativeContentOrigin.y)*px)/px;
        _nativeContent.transform=CGAffineTransformIdentity;
        _nativeContent.center=CGPointMake(x+size.width*.5,y+size.height*.5);
    }
    if(_countLabel.text.length) {
        CGSize sz=[_countLabel.text sizeWithAttributes:@{NSFontAttributeName:_countLabel.font}];
        CGFloat s=h/44,bh=MIN(20*s,h*.48),bw=MAX(bh,sz.width+12*s);
        _countLabel.frame=CGRectMake(CGRectGetMaxX(_materialRect)-14*s-bw,CGRectGetMidY(_materialRect)-bh*.5,bw,bh);
        _countLabel.layer.cornerRadius=bh*.5;
    }
    [self updateContentTransform];
    [_glass layoutIfNeeded];_glass.hidden=_plain || (!_glass.ready && WXGFallbackAllowed());_fallback.hidden=_plain || _glass.hasPresentedFrame || !WXGFallbackAllowed();
    [CATransaction commit];
    }];
}
// FIX73: what the clipping views above this glass still show, in this view's
// space (CGRectInfinite: nothing clips). The chat input bar's glass sits in
// WeChat's input panel, which clips: pulled past it, the glass was cut off.
- (CGRect)stretchClip {
    CGRect clip=CGRectInfinite;
    for(UIView *v=self.superview;v && v!=self.window;v=v.superview) {
        if(v.clipsToBounds)clip=CGRectIntersection(clip,[v convertRect:v.bounds toView:self]);
        CALayer *mask=v.layer.mask;   // a mask clips to (at most) its own frame
        if(mask && !CGRectIsEmpty(mask.frame))clip=CGRectIntersection(clip,[v.layer convertRect:mask.frame toLayer:self.layer]);
    }
    return clip;
}
// FIX73: the share (0..1) of the pull `ox, oy` that keeps the posed glass
// inside that clip (never tighter than where the press alone takes it).
- (double)stretchShareX:(double)ox y:(double)oy press:(WXGButtonPressPose)press {
    if((ox==0 && oy==0) || CGRectIsEmpty(_materialRect))return 1;
    CGRect clip=[self stretchClip];
    if(CGRectIsInfinite(clip) || CGRectIsNull(clip) || CGRectIsEmpty(clip))return 1;
    CGFloat radius=MIN(_materialRect.size.width,_materialRect.size.height)*.5;
    if(_maximumCornerRadius>0)radius=MIN(radius,_maximumCornerRadius);
    double cx=CGRectGetMidX(_materialRect),cy=CGRectGetMidY(_materialRect);
    return WXGStretchFit(press,ox,oy,_materialRect.size.width,_materialRect.size.height,radius,WXGCurrentStretchStyle(),
                         CGRectGetMinX(clip)-cx,CGRectGetMinY(clip)-cy,CGRectGetMaxX(clip)-cx,CGRectGetMaxY(clip)-cy);
}
- (void)updateContentTransform {
    WXGButtonPressPose press=WXGButtonPress(_press,_touchX,_touchY,UIAccessibilityIsReduceMotionEnabled());
    // FIX68: the press pose, then the drag stretch (identity while at rest).
    // FIX73: never past a clipping parent (also the release's overshoot).
    double ox=_stretch.x,oy=_stretch.y,share=[self stretchShareX:ox y:oy press:press];
    WXGStretchPose pose=WXGStretchPoseMake(press,ox*share,oy*share,_materialRect.size.width,_materialRect.size.height,WXGCurrentStretchStyle());
    CGPoint materialCentre=CGPointMake(CGRectGetMidX(_materialRect),CGRectGetMidY(_materialRect));
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        NSMutableArray<UIView *> *children=[@[self.glass,self.fallback,self.iconView,self.label,self.countLabel] mutableCopy];
        if(_trailingView)[children addObject:_trailingView];
        if(_plusTriggerView && !_plusTriggerView.hidden)[children addObject:_plusTriggerView];
        if(_nativeContent)[children addObject:_nativeContent];   // FIX114 V: pressed and stretched with the glass
        for(UIView *child in children) {
            CGPoint centre=child.center;double tx=0,ty=0;
            WXGStretchChildOffset(pose,centre.x-materialCentre.x,centre.y-materialCentre.y,&tx,&ty);
            child.transform=CGAffineTransformMake(pose.a,pose.b,pose.c,pose.d,tx,ty);
        }
        [self poseFollowers:pose centre:materialCentre];
        [CATransaction commit];
    }];
}
- (void)dealloc {
    for(UIView *view in _followers.allObjects)[view.layer removeAnimationForKey:WXGFollowKey];
    if(_touchObserver)[_touchObserver.view removeGestureRecognizer:_touchObserver];
}
// FIX71: the native views on this glass take the same pose (about the
// glass's centre); at rest their animations go and the list is dropped.
- (void)poseFollowers:(WXGStretchPose)pose centre:(CGPoint)centre {
    if(!_followers.count)return;
    BOOL rest=fabs(pose.a-1)<1e-4 && fabs(pose.d-1)<1e-4 && fabs(pose.b)<1e-4 && fabs(pose.c)<1e-4 && fabs(pose.tx)<.01 && fabs(pose.ty)<.01;
    for(UIView *view in _followers.allObjects) {
        CALayer *layer=view.layer,*parent=layer.superlayer;
        if(rest || !parent || view.window!=self.window){[layer removeAnimationForKey:WXGFollowKey];continue;}
        CGPoint anchor=[parent convertPoint:layer.position toLayer:self.layer];
        double tx=0,ty=0;WXGStretchChildOffset(pose,anchor.x-centre.x,anchor.y-centre.y,&tx,&ty);
        WXGFollowPose(layer,CGAffineTransformMake(pose.a,pose.b,pose.c,pose.d,tx,ty));
    }
    // FIX72: FIX71 dropped the list here at touch-down already (the pose is
    // still at rest then), so nothing ever followed: only once the touch is up.
    if(rest && !_followTouching)[_followers removeAllObjects];
}
// FIX71: the outermost views inside `root` that lie on this glass (never
// this glass itself, nor a view holding it).
- (void)collectFollowersIn:(UIView *)root {
    if(!_followers)_followers=[NSHashTable weakObjectsHashTable];
    CGRect area=CGRectInset(_materialRect,-2,-2);
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root];
    for(NSUInteger i=0;i<queue.count && i<400;i++) {
        UIView *view=queue[i];
        if(view==self || view.hidden)continue;
        BOOL holdsSelf=[self isDescendantOfView:view];
        CGRect r=[view convertRect:view.bounds toView:self];
        if(!holdsSelf && view!=root && CGRectContainsRect(area,r) && r.size.width>0 && r.size.height>0){[_followers addObject:view];continue;}
        if(!holdsSelf && !CGRectIntersectsRect(area,r))continue;
        [queue addObjectsFromArray:view.subviews];
    }
    NSMutableArray *names=[NSMutableArray array];
    for(UIView *view in _followers.allObjects)if(names.count<8)[names addObject:NSStringFromClass(view.class)];
    _followerNames=names;
}
// FIX68: how far the glass follows the finger: the setting is for a 44 pt
// button, smaller and larger glass a little less / more.
- (double)stretchLimit {
    CGFloat side=MIN(_materialRect.size.width,_materialRect.size.height);
    return WXGConfig.shared.pressStretchDistance*WXGClamp(side/44,.75,1.25);
}
- (BOOL)stretchInside:(CGPoint)point {
    return CGRectContainsPoint(CGRectInset(_materialRect,-WXGStretchSlop,-WXGStretchSlop),point);
}
// FIX75: the input field and the home page's top-left glass have their own switch.
- (BOOL)stretches {return WXGStretchWanted() && !_plain && !_pressFixed && (!_materialOnly || WXGConfig.shared.pressStretchNative);}
- (void)setPressFixed:(BOOL)fixed {
    if(_pressFixed==fixed)return;
    _pressFixed=fixed;
    if(fixed){_followTouching=NO;[self releaseFinger];[self setExternalPressed:NO];}
}
- (void)followFinger:(CGPoint)point inside:(BOOL)inside {
    if(!inside || ![self stretches]){_stretch.tracking=0;_stretch.targetX=_stretch.targetY=0;return;}
    // FIX69: (inside is now the whole touch when stretching)
    _stretch.tracking=1;
    // FIX115 L: the finger travels `ratio` points per point of pull.
    double ratio=MAX(1,[WXGConfig.shared extraNumber:@"pressStretchRatio"]);
    WXGStretchTarget(&_stretch,(point.x-_stretchStart.x)/ratio,(point.y-_stretchStart.y)/ratio,[self stretchLimit]);
    // FIX73: the target itself stops where a clipping parent would cut the
    // glass, so the release springs back from there without a pause.
    double share=[self stretchShareX:_stretch.targetX y:_stretch.targetY press:WXGButtonPress(1,_touchTargetX,_touchTargetY,NO)];
    _stretch.targetX*=share;_stretch.targetY*=share;
}
- (void)releaseFinger {_stretch.tracking=0;_stretch.targetX=_stretch.targetY=0;}
- (void)observeTouchesInView:(UIView *)view {
    if(_touchObserver.view==view && view)return;
    if(_touchObserver){[_touchObserver.view removeGestureRecognizer:_touchObserver];_touchObserver=nil;}
    if(!view)return;
    _touchObserver=[[WXGTouchObserver alloc]initWithSurface:self];
    [view addGestureRecognizer:_touchObserver];
}
- (BOOL)observedTouchBegan:(UITouch *)touch {
    if(!_active || self.hidden || !self.window || !_materialOnly || _pressFixed || CGRectIsEmpty(_materialRect))return NO;
    CGPoint point=[touch locationInView:self];
    if(!CGRectContainsPoint(CGRectInset(_materialRect,-4,-4),point))return NO;
    [self updatePressDirection:point];_stretchStart=point;[self followFinger:point inside:YES];[self setExternalPressed:YES];
    // FIX71: WeChat's views on this glass move and deform with it.
    for(UIView *view in _followers.allObjects)[view.layer removeAnimationForKey:WXGFollowKey];
    [_followers removeAllObjects];_followTouching=YES;
    if([self stretches] && _touchObserver.view)[self collectFollowersIn:_touchObserver.view];
    return YES;
}
- (void)observedTouchMoved:(UITouch *)touch {
    CGPoint point=[touch locationInView:self];
    [self updatePressDirection:point];[self followFinger:point inside:YES];
}
- (void)observedTouchEnded {_followTouching=NO;[self releaseFinger];[self setExternalPressed:NO];}
- (void)applyConfig {
    if(_sourceStyle!=self.traitCollection.userInterfaceStyle)[self resolveSourceImage];
    WXGConfig *c=WXGConfig.shared;
    [_glass applyStyle];[_glass invalidateBackdrop];
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIColor *t=WXGColor([c materialHexForScope:WXGGlassScopeOther dark:dark]);
    CGFloat opacity=CGColorGetAlpha(t.CGColor)*[c materialOpacityForScope:WXGGlassScopeOther dark:dark];
    _fallback.contentView.backgroundColor=[t colorWithAlphaComponent:WXGClamp(opacity,0,1)];
    _fallback.layer.borderWidth=0; // The shared TEST9 directional rim owns the border.
    _fallback.hidden=_plain || (_glass.ready && _glass.hasPresentedFrame) || !WXGFallbackAllowed();
    _glass.hidden=_plain || (!_glass.ready && WXGFallbackAllowed());[self setNeedsLayout];
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    (void)event;if(_materialOnly)return NO;
    CGFloat dx=MAX(0,(44-_materialRect.size.width)*.5),dy=MAX(0,(44-_materialRect.size.height)*.5);
    return CGRectContainsPoint(CGRectInset(_materialRect,-dx,-dy),p);
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    return !_materialOnly && !self.hidden && self.alpha>.01 && self.enabled && [self pointInside:p withEvent:event]?self:nil;
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;if(!_active || (!_original && !_perform))return NO;
    CGPoint location=[touch locationInView:self];
    [self updatePressDirection:location];_stretchStart=location;[self followFinger:location inside:YES];
    _trackingInside=YES;[self setExternalPressed:YES];[_feedback prepare];return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint location=[touch locationInView:self];[self updatePressDirection:location];
    // FIX68/69: stretching, the glass stays pressed and follows the finger
    // until it is lifted; whether that is a tap is decided at the release.
    BOOL stretching=WXGStretchWanted() && !_plain;
    _trackingInside=stretching?[self stretchInside:location]:[self pointInside:location withEvent:event];
    [self followFinger:location inside:stretching || _trackingInside];
    [self setExternalPressed:stretching || _trackingInside];return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL stretching=WXGStretchWanted() && !_plain;
    CGPoint location=touch?[touch locationInView:self]:CGPointZero;
    BOOL inside=touch && (stretching?[self stretchInside:location]:[self pointInside:location withEvent:event]);
    [self releaseFinger];
    _trackingInside=NO;[self setExternalPressed:NO];if(inside)[self activateOriginal];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {(void)event;[self releaseFinger];_trackingInside=NO;[self setExternalPressed:NO];}
// FIX69: while a finger holds and pulls this glass, a pan elsewhere (a list
// behind it, a full-screen back swipe) does not take the touch away; the
// screen-edge back swipe still can.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if(self.tracking && recognizer.view!=self && WXGStretchWanted() && !_plain &&
       [recognizer isKindOfClass:UIPanGestureRecognizer.class] && ![recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class])return NO;
    return [super gestureRecognizerShouldBegin:recognizer];
}
- (void)updatePressDirection:(CGPoint)point {
    _touchTargetX=WXGClamp((point.x-CGRectGetMidX(_materialRect))/MAX(1,_materialRect.size.width*.5),-1,1);
    _touchTargetY=WXGClamp((point.y-CGRectGetMidY(_materialRect))/MAX(1,_materialRect.size.height*.5),-1,1);
}
- (void)setExternalPressed:(BOOL)pressed {_target=pressed && !_pressFixed?1:0;if(!_target)_touchTargetX=_touchTargetY=0;if(_plain)[_pressProxy setExternalPressed:pressed];}
- (void)activateOriginal {
    if(!_active)return;
    if(_perform){++_forwardedTaps;if(WXGConfig.shared.haptics)[_feedback impactOccurred];_perform();return;}
    UIControl *original=_original;
    if(!original || !WXGCanForward(original))return;
    ++_forwardedTaps;
    if(WXGConfig.shared.haptics)[_feedback impactOccurred];
    UIControlEvents events=(original.allControlEvents & UIControlEventTouchUpInside)?UIControlEventTouchUpInside:UIControlEventPrimaryActionTriggered;
    [WXGIntegrationHost.shared recordForward:@{@"role":_role?:@"",@"targetControlClass":NSStringFromClass(original.class),@"selectors":WXGActionNames(original),@"event":@(events),@"tap":@(_forwardedTaps)}];
    /* Real control remains the sender; this preserves WeChat's logic objects,
       analytics and attachment / dictation state machines. */
    [original sendActionsForControlEvents:events];
    [WXGIntegrationHost.shared schedule];
}
- (BOOL)accessibilityActivate {if(!_active || (!_original && !_perform))return NO;[self activateOriginal];return YES;}
- (void)tick:(CFTimeInterval)time {
    if(!_active || !self.window)return;
    if(_preservesNativeIconColors && [_nativeIconSource isKindOfClass:UIImageView.class]) {
        UIImage *native=((UIImageView *)_nativeIconSource).image;
        UIColor *tint=[_nativeIconSource.tintColor resolvedColorWithTraitCollection:_nativeIconSource.traitCollection];
        if((native && native!=_sourceImage) || ![_resolvedNativeTint isEqual:tint]) {
            if(native)_sourceImage=native;[self resolveSourceImage];
        }
    }
    double oldPress=_press,oldX=_touchX,oldY=_touchY;double dt=_lastTick?time-_lastTick:1./60;_lastTick=time;
    WXGSpring(&_press,&_velocity,_target,420,31,dt);
    WXGSpring(&_touchX,&_touchVelocityX,_touchTargetX,320,30,dt);
    WXGSpring(&_touchY,&_touchVelocityY,_touchTargetY,320,30,dt);
    BOOL stretched=WXGStretchStep(&_stretch,dt);   // FIX68
    double p=WXGClamp(_press,0,1);
    // Optical pressure operates on the SAME body. Its fixed glassRect keeps the
    // distance field reusable; UIKit deforms that body and all artwork together.
    _glass.barScale=1;_glass.pressAmount=UIAccessibilityIsReduceMotionEnabled()?0:p;_glass.lensRect=CGRectZero;
    if(stretched || fabs(oldPress-_press)>.0001 || fabs(oldX-_touchX)>.0001 || fabs(oldY-_touchY)>.0001)[self updateContentTransform];
    [_glass layoutIfNeeded];[_glass tick:time];
}
- (NSDictionary *)evidence {
    CGRect r=self.window?[self convertRect:_materialRect toView:self.window]:CGRectZero;
    UIView *content=_iconView.image?_iconView:_label;
    CGRect i=WXGWindowRect(content,self.window);
    /* Native pixel ROI at rest supplements geometry. During a press we report
       transformed frame projection, avoiding a root-layer transform twice. */
    NSDictionary *pixel=fabs(_press)<.001 && WXGStretchResting(&_stretch)?WXGRenderedInkEvidence(content):@{@"available":@NO,@"reason":@"press_transform"};
    if([pixel[@"available"] boolValue]) {
        NSArray *p=pixel[@"windowRect"];i=CGRectMake([p[0] doubleValue],[p[1] doubleValue],[p[2] doubleValue],[p[3] doubleValue]);
    }
    CGRect clip=[self stretchClip];   // FIX73
    id clipEvidence=@"none";
    if(!CGRectIsInfinite(clip) && !CGRectIsNull(clip) && self.window) {
        CGRect wc=[self convertRect:clip toView:self.window];
        clipEvidence=@[@(round(wc.origin.x*10)/10),@(round(wc.origin.y*10)/10),@(round(wc.size.width*10)/10),@(round(wc.size.height*10)/10)];
    }
    CGPoint expected=CGPointMake(_countLabel.text.length?r.origin.x+r.size.height*.5:CGRectGetMidX(r),CGRectGetMidY(r));
    CGPoint d=CGPointMake(CGRectGetMidX(i)-expected.x,CGRectGetMidY(i)-expected.y);
    return @{@"role":_role?:@"unknown",@"surfaceID":[NSString stringWithFormat:@"%p",self],@"materialRect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],
             @"inkRect":@[@(i.origin.x),@(i.origin.y),@(i.size.width),@(i.size.height)],
             @"inkCenterDelta":@[@(d.x),@(d.y)],@"hasIcon":@(_iconView.image!=nil),@"isCountCapsule":@(_countLabel.text.length>0),
             @"expectedInkCenter":@[@(expected.x),@(expected.y)],
             @"pixelInk":pixel,
             @"iconImageSize":@[@(_iconView.image.size.width),@(_iconView.image.size.height)],@"titleFontSize":@(_label.font.pointSize),
             @"hasText":@(_label.text.length>0),@"textCorrection":@[@(_textCorrection.x),@(_textCorrection.y)],
             @"materialLayers":_glass.layerEvidence,@"fallbackVisible":@(!_fallback.hidden),
             @"originalClass":_original?NSStringFromClass(_original.class):@"none",
             @"actions":WXGActionNames(_original),@"forwardedTaps":@(_forwardedTaps),@"metalFirstFrame":@(_glass.hasPresentedFrame),
             @"renderer":_glass.diagnostics,@"stretchFollowers":_followerNames?:@[],@"stretchClip":clipEvidence,@"textLength":@(_label.text.length),@"countDigits":@(_countLabel.text.length)};
}
@end
