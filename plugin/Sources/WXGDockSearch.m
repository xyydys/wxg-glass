#import "WXGIntegration.h"
#import "WXGButtonPress.h"
#import "WXGPressStretch.h"
#import "WXGDockSearchLayout.h"
// FIX80: the stretch settings (WXGPressStretch.h).
static WXGStretchStyle WXGCurrentStretchStyle(void) {
    WXGConfig *c=WXGConfig.shared;
    return (WXGStretchStyle){c.pressStretchAmount,c.pressStretchCapsule,c.pressStretchMax,c.pressStretchFollow};
}

// FIX60: the dock's search button (interface in WXGCommon.h). One glass with
// the dock's own optics, rim and material, whose outline the host animates
// (WXGDockSearchLayout.h). In render-server mode this glass's Metal overlay
// draws nothing (veil and rim are layers there), so it stays hidden.
// FIX63: the search field (magnifier + text) is a separate view the host
// places over whichever glass ends on the left: this button's own glass when
// the button sits on the left (it widens into the field, the magnifier rides
// its leading edge), the dock's capsule when the button sits on the right
// (the field fades in over it, this button turns into the close button).
@interface WXGDockFieldView : UIView
@end
@implementation WXGDockFieldView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if(self.hidden || self.alpha<.01 || !self.userInteractionEnabled || ![self pointInside:point withEvent:event])return nil;
    return [super hitTest:point withEvent:event]?:self;
}
@end

@interface WXGDockSearch () <UITextFieldDelegate>
@property(nonatomic,strong) WXGGlassView *glass;
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) UIView *fieldView,*glyphs;
@property(nonatomic,strong) UIImageView *icon,*magnifier,*closeGlyph;
@property(nonatomic) CGRect shape,fieldFrame;
@property(nonatomic) CGFloat reveal,magnifierAlpha,closeAlpha;
@property(nonatomic) BOOL rides;
@property(nonatomic) double press,velocity,target;
@property(nonatomic) double touchX,touchY,touchTargetX,touchTargetY,touchVelocityX,touchVelocityY;
@property(nonatomic) CFTimeInterval lastTick;
@property(nonatomic,strong) UIImpactFeedbackGenerator *feedback;
@property(nonatomic) CGPoint stretchStart;   // FIX68
@end
/* FIX68: hold-and-drag stretch (WXGPressStretch.h), as the other glass buttons. */
static const CGFloat WXGDockStretchSlop=40;
static BOOL WXGDockStretchWanted(void) {return WXGConfig.shared.pressStretch && !UIAccessibilityIsReduceMotionEnabled();}

static UIImageView *WXGDockGlyph(NSString *name,CGFloat size) {
    UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
    UIImageView *view=[[UIImageView alloc]initWithImage:[[UIImage systemImageNamed:name withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    view.contentMode=UIViewContentModeCenter;view.tintColor=UIColor.labelColor;view.userInteractionEnabled=NO;
    return view;
}

@implementation WXGDockSearch {
    WXGStretchState _stretch;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.clipsToBounds=NO;
        // The dock's own shadow, so the two read as one row.
        self.layer.shadowColor=UIColor.blackColor.CGColor;self.layer.shadowOpacity=.10;self.layer.shadowRadius=20;self.layer.shadowOffset=CGSizeMake(0,8);
        // FIX61: no shadow until there is an outline (without a path the shadow
        // is taken from the content: the backdrop layers' rectangles).
        self.layer.shadowPath=[UIBezierPath bezierPath].CGPath;
        _glass=[[WXGGlassView alloc]initWithFrame:self.bounds];_glass.dockSurface=YES;_glass.buttonPressEffect=YES;
        _glass.overlayHidden=WXGEffectiveRenderMode()>=2;
        [self addSubview:_glass];
        // This button's own glyphs (button on the right): magnifier -> close.
        _glyphs=[UIView new];_glyphs.userInteractionEnabled=NO;[self addSubview:_glyphs];
        _magnifier=WXGDockGlyph(@"magnifyingglass",20);_closeGlyph=WXGDockGlyph(@"xmark",19);
        _closeGlyph.alpha=0;[_glyphs addSubview:_magnifier];[_glyphs addSubview:_closeGlyph];
        // The field, placed by the host.
        _fieldView=[WXGDockFieldView new];_fieldView.clipsToBounds=YES;_fieldView.layer.cornerCurve=kCACornerCurveContinuous;
        _fieldView.userInteractionEnabled=NO;_fieldView.hidden=YES;
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(fieldTapped)];
        tap.cancelsTouchesInView=NO;[_fieldView addGestureRecognizer:tap];
        _icon=WXGDockGlyph(@"magnifyingglass",20);[_fieldView addSubview:_icon];
        _field=[UITextField new];_field.delegate=self;_field.borderStyle=UITextBorderStyleNone;
        _field.font=[UIFont systemFontOfSize:17];_field.textColor=UIColor.labelColor;
        _field.tintColor=[UIColor colorWithRed:.03 green:.76 blue:.38 alpha:1];
        _field.attributedPlaceholder=[[NSAttributedString alloc]initWithString:@"搜索" attributes:@{NSForegroundColorAttributeName:UIColor.secondaryLabelColor}];
        _field.returnKeyType=UIReturnKeySearch;_field.enablesReturnKeyAutomatically=YES;
        _field.autocorrectionType=UITextAutocorrectionTypeNo;_field.clearButtonMode=UITextFieldViewModeWhileEditing;
        _field.accessibilityLabel=@"搜索";_field.alpha=0;_field.hidden=YES;
        [_fieldView addSubview:_field];
        _feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];
        self.isAccessibilityElement=YES;self.accessibilityLabel=@"搜索";self.accessibilityTraits=UIAccessibilityTraitButton;
    }return self;
}
- (void)setActive:(BOOL)active {
    if(_active==active)return;
    _active=active;_glass.active=active;
    if(!active){_target=_press=_velocity=0;_touchX=_touchY=_touchTargetX=_touchTargetY=_touchVelocityX=_touchVelocityY=0;_stretch=(WXGStretchState){0};_glass.pressAmount=0;_lastTick=0;[self updatePressTransform];}
}
- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if(hidden)_fieldView.hidden=YES;else [self layoutField];
}
- (void)setExpanded:(BOOL)expanded {
    if(_expanded==expanded)return;
    _expanded=expanded;_target=0;_touchTargetX=_touchTargetY=0;_stretch.tracking=0;_stretch.targetX=_stretch.targetY=0;
    [self updateAccessibility];
    // The host decides about the keyboard: handing over to WeChat's own
    // field, that field takes it from ours without a dip.
    if(expanded)_field.hidden=NO;
    else _field.text=@"";
    [self layoutField];
}
- (void)setClosesWhenOpen:(BOOL)closes {_closesWhenOpen=closes;[self updateAccessibility];}
- (void)updateAccessibility {
    BOOL closeButton=_expanded && _closesWhenOpen;
    self.isAccessibilityElement=!_expanded || closeButton;
    self.accessibilityLabel=closeButton?@"关闭搜索":@"搜索";
}
- (void)applyConfig {
    _glass.overlayHidden=WXGEffectiveRenderMode()>=2;
    [_glass applyStyle];[_glass invalidateBackdrop];
}
- (void)setShape:(CGRect)shape magnifier:(CGFloat)magnifier close:(CGFloat)close {
    _shape=shape;_magnifierAlpha=WXGClamp(magnifier,0,1);_closeAlpha=WXGClamp(close,0,1);
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        [self layoutShape];
        [CATransaction commit];
    }];
}
- (void)setFieldFrame:(CGRect)frame reveal:(CGFloat)reveal iconRides:(BOOL)rides {
    _fieldFrame=frame;_reveal=WXGClamp(reveal,0,1);_rides=rides;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        [self layoutField];
        [CATransaction commit];
    }];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        [self layoutShape];
        [CATransaction commit];
    }];
}
// Called without animations. Bounds and centre (never frame): the press
// transform may be applied.
- (void)layoutShape {
    CGRect shape=_shape;
    _glass.bounds=(CGRect){CGPointZero,self.bounds.size};_glass.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    _glyphs.bounds=_glass.bounds;_glyphs.center=_glass.center;
    if(CGRectIsEmpty(shape))return;
    _glass.glassRect=shape;
    CGFloat radius=MIN(shape.size.width,shape.size.height)*.5;
    self.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:shape cornerRadius:radius].CGPath;
    CGPoint mid=CGPointMake(CGRectGetMidX(shape),CGRectGetMidY(shape));
    for(UIImageView *glyph in @[_magnifier,_closeGlyph]) {
        CGSize size=glyph.image.size;glyph.bounds=CGRectMake(0,0,MAX(24,size.width),MAX(24,size.height));glyph.center=mid;
    }
    _magnifier.alpha=_magnifierAlpha;_closeGlyph.alpha=_closeAlpha;
    [self updatePressTransform];
}
- (void)layoutField {
    CGRect frame=_fieldFrame;
    if(CGRectIsEmpty(frame) || self.hidden){_fieldView.hidden=YES;return;}
    CGFloat w=frame.size.width,h=frame.size.height,text=WXGDockSearchFieldReveal((float)_reveal);
    _fieldView.bounds=CGRectMake(0,0,w,h);_fieldView.center=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    _fieldView.layer.cornerRadius=MIN(w,h)*.5;
    CGSize glyph=_icon.image.size;CGFloat iconW=MAX(24,glyph.width),iconH=MAX(24,glyph.height);
    // Riding: the round button's magnifier moves to the field's leading edge.
    // Otherwise it fades in there with the text.
    CGFloat iconX=_rides?h*.5+((16+iconW*.5)-h*.5)*_reveal:16+iconW*.5;
    _icon.bounds=CGRectMake(0,0,iconW,iconH);_icon.center=CGPointMake(iconX,h*.5);_icon.alpha=_rides?1:text;
    CGFloat fieldX=iconX+iconW*.5+6;
    _field.frame=CGRectMake(fieldX,0,MAX(1,w-fieldX-12),h);
    _field.alpha=text;_field.hidden=!_expanded && text<.01 && !_field.isFirstResponder;
    _fieldView.hidden=!_rides && text<.01 && !_expanded && !_field.isFirstResponder;
    _fieldView.userInteractionEnabled=_expanded;
    [self updatePressTransform];
}
- (void)fieldTapped {if(_expanded && !_field.isFirstResponder)[_field becomeFirstResponder];}
- (void)updatePressTransform {
    WXGButtonPressPose press=WXGButtonPress(_press,_touchX,_touchY,UIAccessibilityIsReduceMotionEnabled());
    // FIX68: the press pose, then the drag stretch.
    WXGStretchPose pose=WXGStretchPoseMake(press,_stretch.x,_stretch.y,_shape.size.width,_shape.size.height,WXGCurrentStretchStyle());
    CGPoint centre=CGPointMake(CGRectGetMidX(_shape),CGRectGetMidY(_shape));
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        for(UIView *child in @[self.glass,self.glyphs]) {
            CGPoint c=child.center;double dx=0,dy=0;
            WXGStretchChildOffset(pose,c.x-centre.x,c.y-centre.y,&dx,&dy);
            child.transform=CGAffineTransformMake(pose.a,pose.b,pose.c,pose.d,dx,dy);
        }
        // The riding magnifier is this button's glyph while round: it bulges along
        // (it sits at the glass's centre then).
        BOOL along=self.rides && !self.expanded;
        self.fieldView.transform=along?CGAffineTransformMake(pose.a,pose.b,pose.c,pose.d,pose.tx,pose.ty):CGAffineTransformIdentity;
        [CATransaction commit];
    }];
}
- (double)stretchLimit {
    CGFloat side=MIN(_shape.size.width,_shape.size.height);
    return WXGConfig.shared.pressStretchDistance*WXGClamp(side/44,.75,1.25);
}
- (BOOL)stretchInside:(CGPoint)point {
    return !CGRectIsEmpty(_shape) && CGRectContainsPoint(CGRectInset(_shape,-WXGDockStretchSlop,-WXGDockStretchSlop),point);
}
- (void)followFinger:(CGPoint)point inside:(BOOL)inside {
    if(!inside || !WXGDockStretchWanted()){_stretch.tracking=0;_stretch.targetX=_stretch.targetY=0;return;}
    _stretch.tracking=1;
    WXGStretchTarget(&_stretch,point.x-_stretchStart.x,point.y-_stretchStart.y,[self stretchLimit]);
}
- (void)releaseFinger {_stretch.tracking=0;_stretch.targetX=_stretch.targetY=0;}
- (void)tick:(CFTimeInterval)time {
    if(!_active || !self.window)return;
    double dt=_lastTick?time-_lastTick:1./60;_lastTick=time;
    double oldPress=_press,oldX=_touchX,oldY=_touchY;
    BOOL stretched=WXGStretchStep(&_stretch,dt);   // FIX68
    WXGSpring(&_press,&_velocity,_target,420,31,dt);
    WXGSpring(&_touchX,&_touchVelocityX,_touchTargetX,320,30,dt);
    WXGSpring(&_touchY,&_touchVelocityY,_touchTargetY,320,30,dt);
    _glass.pressAmount=UIAccessibilityIsReduceMotionEnabled()?0:WXGClamp(_press,0,1);
    if(stretched || fabs(oldPress-_press)>.0001 || fabs(oldX-_touchX)>.0001 || fabs(oldY-_touchY)>.0001)[self updatePressTransform];
    [_glass layoutIfNeeded];[_glass tick:time];
}

#pragma mark - Touches

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    if(CGRectIsEmpty(_shape))return NO;
    CGFloat dx=MAX(0,(44-_shape.size.width)*.5)+4,dy=MAX(0,(44-_shape.size.height)*.5)+4;
    return CGRectContainsPoint(CGRectInset(_shape,-dx,-dy),point);
}
// Round: the search button. Open on the right: the close button. Open on
// the left: the field view above takes the touches.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if(self.hidden || self.alpha<.01 || !self.userInteractionEnabled || !self.enabled || ![self pointInside:point withEvent:event])return nil;
    if(_expanded && !_closesWhenOpen)return nil;
    return self;
}
- (void)updatePressDirection:(CGPoint)point {
    _touchTargetX=WXGClamp((point.x-CGRectGetMidX(_shape))/MAX(1,_shape.size.width*.5),-1,1);
    _touchTargetY=WXGClamp((point.y-CGRectGetMidY(_shape))/MAX(1,_shape.size.height*.5),-1,1);
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;if(!_active)return NO;
    CGPoint point=[touch locationInView:self];
    [self updatePressDirection:point];_target=1;[_feedback prepare];
    _stretchStart=point;[self followFinger:point inside:YES];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point=[touch locationInView:self];
    // FIX69: stretching, pressed and pulled until the finger is lifted.
    BOOL stretching=WXGDockStretchWanted(),inside=stretching || [self pointInside:point withEvent:event];
    [self updatePressDirection:point];_target=inside?1:0;
    [self followFinger:point inside:inside];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point=touch?[touch locationInView:self]:CGPointZero;
    BOOL inside=touch && touch.phase!=UITouchPhaseCancelled &&
        (WXGDockStretchWanted()?[self stretchInside:point]:[self pointInside:point withEvent:event]);
    [self releaseFinger];
    _target=0;_touchTargetX=_touchTargetY=0;
    if(!inside || !_active)return;
    if(WXGConfig.shared.haptics)[_feedback impactOccurred];
    if(_expanded){if(_closesWhenOpen && _onClose)_onClose();return;}
    [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {(void)event;[self releaseFinger];_target=0;_touchTargetX=_touchTargetY=0;}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if(self.tracking && recognizer.view!=self && WXGDockStretchWanted() &&
       [recognizer isKindOfClass:UIPanGestureRecognizer.class] && ![recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class])return NO;
    return [super gestureRecognizerShouldBegin:recognizer];
}
- (BOOL)accessibilityActivate {
    if(!_active)return NO;
    if(_expanded){if(_closesWhenOpen && _onClose){_onClose();return YES;}return NO;}
    [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];return YES;
}

#pragma mark - Field

// FIX62: only while open. When WeChat's search page closes, UIKit gives the
// focus back to the field that had it before (ours) and the keyboard stayed
// up over a closed dock; refused now.
- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {(void)textField;return _expanded;}
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *text=[textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(text.length && _onSubmit)_onSubmit(text);
    return NO;
}
@end
