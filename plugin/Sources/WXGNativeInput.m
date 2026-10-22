#import "WXGIntegration.h"
#import "WXGNativeInputGeometry.h"
#import "WXGCompactInputGeometry.h"
#import "WXGInputPolicy.h"

/* Only host width and control origins are adjusted. Native TextKit, record
   gestures, dictation animation and each control's bounds/actions stay native. */
@interface WXGNativeInputAdapter ()
@property(nonatomic) BOOL installed,layingOut,suspended;
@property(nonatomic,weak) UIView *tool,*panel,*grow,*dictation,*centerHost;
@property(nonatomic,weak) UITextView *editor;
@property(nonatomic,weak) UIControl *attachment,*dictationButton,*sendButton,*voiceButton,*emojiButton;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic,strong) NSArray<WXGSurface *> *surfaces;
@property(nonatomic,strong) NSHashTable<UIControl *> *nativeControls;
@property(nonatomic,strong) NSMapTable<UIView *,NSValue *> *appliedFrames;
@property(nonatomic,strong) NSMapTable<UIControl *,NSDictionary *> *inkCache;
@property(nonatomic) CFTimeInterval lastBindingScan,lastPaintScan;
@property(nonatomic) BOOL lastEditorVisible;
@property(nonatomic) CGFloat singleLineHeight;
@property(nonatomic) NSUInteger lastPanelChildCount,lastGrowChildCount;
@property(nonatomic) NSUInteger dictationBackings;   // FIX113: dictation backings concealed (diagnostics)
@property(nonatomic,copy) NSString *status;
@end

static BOOL WXGInputUsableRect(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) && isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) && rect.size.width>1 && rect.size.height>1;
}
static NSArray *WXGInputRectEvidence(CGRect rect) {
    if(!WXGInputUsableRect(rect))return @[];
    return @[@(rect.origin.x),@(rect.origin.y),@(rect.size.width),@(rect.size.height)];
}

@implementation WXGNativeInputAdapter
- (instancetype)init {
    if((self=[super init])) {
        WXGSurface *left=[WXGSurface new],*center=[WXGSurface new],*right=[WXGSurface new];
        left.role=@"nativeInputLeft";center.role=@"nativeInputCenter";right.role=@"nativeInputRight";
        center.pressFixed=YES;   // FIX87: the text capsule never presses or stretches
        _surfaces=@[left,center,right];_nativeControls=[NSHashTable weakObjectsHashTable];
        _appliedFrames=[NSMapTable weakToStrongObjectsMapTable];_inkCache=[NSMapTable weakToStrongObjectsMapTable];
        for(WXGSurface *surface in _surfaces) {
            surface.materialOnly=YES;surface.isAccessibilityElement=NO;
            surface.userInteractionEnabled=NO;surface.hidden=YES;
        }
    }return self;
}
- (UIView *)viewValue:(NSString *)key on:(id)object {
    id value=WXGRead(object,key);return [value isKindOfClass:UIView.class]?value:nil;
}
- (UIControl *)controlValue:(NSString *)key on:(id)object {
    id value=WXGRead(object,key);return [value isKindOfClass:UIControl.class]?value:nil;
}
- (void)bindOptionalActions {
    _lastBindingScan=CACurrentMediaTime();_dictation=nil;_dictationButton=nil;_emojiButton=nil;
    _lastEditorVisible=WXGVisible(_editor,_window);
    _lastPanelChildCount=_panel.subviews.count;_lastGrowChildCount=_grow.subviews.count;
    _attachment=[self controlValue:@"_attachmentButton" on:_tool];
    _sendButton=[self controlValue:@"sendButton" on:_tool];
    _voiceButton=[self controlValue:@"_inputModeChangeButton" on:_tool];
    [_nativeControls removeAllObjects];
    NSMutableOrderedSet<UIView *> *views=[NSMutableOrderedSet orderedSetWithArray:WXGViews(_panel,180)];
    [views addObjectsFromArray:WXGViews(_grow,90)];
    for(UIView *view in views) {
        if(WXGIsPluginView(view))continue;
        if([NSStringFromClass(view.class) isEqual:@"MMGrowDictationIconView"])_dictation=view;
        if(![view isKindOfClass:UIControl.class])continue;
        UIControl *control=(id)view;[_nativeControls addObject:control];
        NSArray *actions=WXGActionNames(control);
        if([actions containsObject:@"iconClicked"] && [view isDescendantOfView:_grow])_dictationButton=control;
        if(!_sendButton && [actions containsObject:@"onTapSendButton"])_sendButton=control;
        if([actions containsObject:@"onExpressionButtonClicked:"])_emojiButton=control;
    }
    if(_attachment)[_nativeControls addObject:_attachment];
    if(_voiceButton)[_nativeControls addObject:_voiceButton];
    if(_sendButton)[_nativeControls addObject:_sendButton];
    // Names/actions are diagnostic evidence only. All touch phases, gestures,
    // IME commits and voice state transitions continue through native controls.
}
- (BOOL)installInController:(UIViewController *)vc window:(UIWindow *)window {
    UIView *currentGrow=[self viewValue:@"_textView" on:_tool];
    UIView *currentPanel=[self viewValue:@"_toolPanelView" on:_tool];
    if(_installed && _controller==vc && _tool && [_tool isDescendantOfView:vc.view] &&
       (!currentGrow || currentGrow==_grow) && (!currentPanel || currentPanel==_panel)) {
        _window=window;[self setSuspended:NO];[self layout];return YES;
    }
    if(_installed)[self restore];
    UIView *tool=nil;
    for(UIView *view in WXGViews(vc.view,1200))if([NSStringFromClass(view.class) isEqual:@"MMInputToolView"]){tool=view;break;}
    WXGClaimInputTool(tool,self);
    UIView *panel=[self viewValue:@"_toolPanelView" on:tool],*grow=[self viewValue:@"_textView" on:tool];
    if(!tool || !panel || !grow) {
        _status=@"等待原生输入宿主；不替代原生输入、语音或发送动作";return NO;
    }
    _tool=tool;_panel=panel;_grow=grow;_window=window;_controller=vc;
    for(UIView *view in WXGViews(grow,80))if([view isKindOfClass:UITextView.class]){_editor=(id)view;break;}
    _states=[WXGStateBag new];[self bindOptionalActions];
    for(WXGSurface *surface in _surfaces) {
        surface.glass.sourceView=vc.view;surface.glass.backdropExclusions=@[tool];
        [surface applyConfig];
    }
    _singleLineHeight=0;_installed=YES;_suspended=NO;
    _status=@"三段：左圆、右侧图标等距，原生文字容器让位；保留听写动画与长按录音";
    [self clearPaint];[self layout];return YES;
}
- (void)clearPaint {
    if(!_states || !_tool)return;
    _lastPaintScan=CACurrentMediaTime();
    NSMutableArray<UIView *> *protected=[NSMutableArray array];
    if(_editor)[protected addObject:_editor];
    if(_dictation)[protected addObject:_dictation];
    for(UIControl *control in _nativeControls)if(control)[protected addObject:control];
    UIView *background=[self viewValue:@"_toolView" on:_tool];
    [_states clear:_tool];[_states stripChrome:background preserving:protected];
    [_states stripChrome:_panel preserving:protected];
    [_states stripChrome:_grow preserving:protected];
    [_states clear:_grow];[_states clear:_editor];
    // These are documented background objects from the existing input binding.
    // Do not hide their parent: native dictation, caret and marked text may be
    // descendants of the same grow view.
    for(UIView *root in @[_grow,_tool]) {
        NSString *key=root==_grow?@"_backgroundView":@"_fakeTextBackgroundView";
        UIView *paint=[self viewValue:key on:root];
        if(paint && paint!=root && [paint isDescendantOfView:root]) {
            BOOL content=NO;
            for(UIView *child in WXGViews(paint,80)) {
                if([child isKindOfClass:UIControl.class] || [child isKindOfClass:UILabel.class] ||
                   [child isKindOfClass:UITextView.class] || child.gestureRecognizers.count){content=YES;break;}
            }
            if(content)[_states stripChrome:paint preserving:protected];else [_states hide:paint];
        }
    }
    [self concealDictationBacking];
    UIView *record=[self viewValue:@"_recordButton" on:_tool];
    UIImageView *recordPaint=(id)[self viewValue:@"_backgroundView" on:record];
    if([recordPaint isKindOfClass:UIImageView.class] && [recordPaint isDescendantOfView:record])[_states clearImagePaint:recordPaint];
    // Retain the control artwork and actual gestures.
    for(UIControl *control in _nativeControls)[_states clear:control];
    for(UIView *view in _tool.subviews) {
        if(view==_panel || view==background || [_panel isDescendantOfView:view])continue;
        NSString *name=NSStringFromClass(view.class).lowercaseString;
        if([name containsString:@"background"] || [name containsString:@"separator"] ||
           (view.bounds.size.height<=2 && view.bounds.size.width>_panel.bounds.size.width*.8))
            [_states stripChrome:view preserving:protected];
    }
}
// The recorded dictation host has a 52x40 static backing wrapper with a
// 72x72 image, beside 24/32pt green animation views and a loading spinner.
// Preserve the whole dictation subtree above, then remove only that wrapper.
// FIX113: looked at on every layout pass (a few subviews), not with the
// 0.35 s paint scan, and as soon as WeChat lays the dictation icon out (the
// host hooks it): WeChat puts a new wrapper in or shows it again as the
// icon changes state, and it showed for a moment before going. Masked, not
// faded: WeChat's own alpha changes cannot bring it back between passes.
- (void)concealDictationBacking {
    if(!_dictation || !_states)return;
    for(UIView *view in _dictation.subviews) {
        if([view isKindOfClass:UIControl.class] || view.gestureRecognizers.count ||
           ![NSStringFromClass(view.class) isEqual:@"UIView"] || view.bounds.size.width<=_dictation.bounds.size.width+8)continue;
        if(view.subviews.count!=1 || ![view.subviews.firstObject isKindOfClass:UIImageView.class])continue;
        UIImageView *paint=(id)view.subviews.firstObject;
        if(paint.bounds.size.width>=_dictation.bounds.size.width*1.5 && !paint.animationImages.count && !paint.layer.animationKeys.count) {
            if(!view.layer.mask)++_dictationBackings;
            [_states conceal:view];
        }
    }
}
- (void)placeNative:(UIView *)view windowRect:(CGRect)rect {
    if(!view || [view isKindOfClass:UITextView.class] || !view.superview || !WXGInputUsableRect(rect))return;
    WXGViewState *state=[_states remember:view];NSValue *last=[_appliedFrames objectForKey:view];
    CGRect a=state.originalFrame,b=view.frame,c=last?last.CGRectValue:CGRectZero;
    WXGRect native=WXGInputNativeFrame((WXGRect){a.origin.x,a.origin.y,a.size.width,a.size.height},
        (WXGRect){b.origin.x,b.origin.y,b.size.width,b.size.height},(WXGRect){c.origin.x,c.origin.y,c.size.width,c.size.height},last!=nil);
    [state updateNativeFrame:WXGCGRect(native)];state.restoreGeometry=YES;
    CGRect target=[_window convertRect:rect toView:view.superview];
    BOOL changed=!CGRectEqualToRect(view.frame,target);
    if(changed)[UIView performWithoutAnimation:^{
        if(view==self.grow)WXGSetInputHostFrame(view,target,state);else view.frame=target;
    }];
    else if(view==_grow)WXGSetInputHostFrame(view,target,state);
    // The surrounding native input pass owns recursion and caret layout.
    // Changing an action origin does not require a nested layoutIfNeeded.
    if(changed && view==_grow)[view setNeedsLayout];
    [_appliedFrames setObject:[NSValue valueWithCGRect:view.frame] forKey:view];
}
- (CGRect)inkForControl:(UIControl *)control {
    UIImageView *image=[control isKindOfClass:UIButton.class]?((UIButton *)control).imageView:nil;
    if(!image.image)for(UIView *v in WXGViews(control,24))if([v isKindOfClass:UIImageView.class] &&
        ((UIImageView *)v).image && !v.hidden && v.alpha>.01 && v.bounds.size.width>4 && v.bounds.size.width<=48){image=(id)v;break;}
    NSString *stamp=[NSString stringWithFormat:@"%p/%@/%@/%ld",image.image,NSStringFromCGSize(control.bounds.size),NSStringFromCGRect(image.frame),(long)control.traitCollection.userInterfaceStyle];
    NSDictionary *cached=[_inkCache objectForKey:control];
    if([cached[@"stamp"] isEqual:stamp])return [cached[@"rect"] CGRectValue];
    CGFloat size=MIN(26,MIN(control.bounds.size.width,control.bounds.size.height));
    CGRect rect=CGRectMake(CGRectGetMidX(control.bounds)-size*.5,CGRectGetMidY(control.bounds)-size*.5,size,size);
    NSDictionary *measured=WXGRenderedInkEvidence(image);
    if([measured[@"available"] boolValue]) {
        NSArray *r=measured[@"windowRect"];CGRect window=CGRectMake([r[0] doubleValue],[r[1] doubleValue],[r[2] doubleValue],[r[3] doubleValue]);
        CGRect candidate=[_window convertRect:window toView:control];if(WXGInputUsableRect(candidate))rect=candidate;
    }
    [_inkCache setObject:@{@"stamp":stamp,@"rect":[NSValue valueWithCGRect:rect]} forKey:control];return rect;
}
- (void)placeControl:(UIControl *)control ink:(CGRect)ink x:(CGFloat)x y:(CGFloat)y {
    if(!control)return;CGRect rect=WXGWindowRect(control,_window);
    CGPoint old=[control convertPoint:CGPointMake(CGRectGetMidX(ink),CGRectGetMidY(ink)) toView:_window];
    rect.origin.x+=x-old.x;rect.origin.y+=y-old.y;[self placeNative:control windowRect:rect];
}
- (UIView *)visibleCenterHost {
    BOOL growVisible=WXGVisible(_grow,_window);
    if(growVisible && WXGVisible(_editor,_window))return _grow;
    // In hold-to-talk mode WeChat hides the editor and exposes a wide native
    // control in the same slot. It may have a private class/action name; use
    // its existing geometry, never manufacture a replacement voice action.
    CGRect reference=WXGWindowRect(_grow,_window);UIView *best=nil;CGFloat bestScore=0;
    if(!WXGInputUsableRect(reference))return nil;
    for(UIControl *control in _nativeControls) {
        if(!WXGVisible(control,_window))continue;
        CGRect rect=WXGWindowRect(control,_window);
        if(rect.size.width<MAX(100,reference.size.width*.55) || rect.size.height<24 || rect.size.height>160)continue;
        CGRect overlap=CGRectIntersection(rect,reference);
        CGFloat score=CGRectIsNull(overlap)?0:overlap.size.width*overlap.size.height;
        if(score>bestScore){best=control;bestScore=score;}
    }
    return best ?: (growVisible ? _grow : nil);
}
- (CGRect)sideRectLeft:(BOOL)left center:(CGRect)center {
    CGRect result=CGRectNull;
    for(UIControl *control in _nativeControls) {
        if(control==_centerHost || [control isDescendantOfView:_centerHost] || !WXGVisible(control,_window))continue;
        CGRect rect=WXGWindowRect(control,_window);
        if(!WXGInputUsableRect(rect) || rect.size.height>MAX(64,center.size.height) || rect.size.width>110)continue;
        BOOL side=left?CGRectGetMaxX(rect)<=CGRectGetMinX(center)+1:CGRectGetMinX(rect)>=CGRectGetMaxX(center)-1;
        if(!side || CGRectGetMaxY(rect)<=CGRectGetMinY(center) || CGRectGetMinY(rect)>=CGRectGetMaxY(center))continue;
        result=CGRectIsNull(result)?rect:CGRectUnion(result,rect);
    }
    return result;
}
- (void)placeSurface:(WXGSurface *)surface windowRect:(CGRect)rect {
    BOOL visible=WXGInputUsableRect(rect);
    surface.hidden=!visible;surface.active=visible && !_suspended;
    if(!visible)return;
    surface.maximumCornerRadius=surface==_surfaces[0]?rect.size.height*.5:MIN(rect.size.height*.5,24*WXGPreferences.shared.sizeScale);
    [surface placeMaterial:[_window convertRect:rect toView:_panel] inParent:_panel];
    [surface observeTouchesInView:_tool?:_panel];   // FIX70: WeChat's controls take the touches
    // All glass sits behind the untouched native controls, including long
    // press/drag-cancel voice recording and the real IME-aware send action.
    // Keep a stable prefix [left, center, right]. Moving each surface to index 0
    // rotated all three on every keystroke and invalidated the panel repeatedly.
    NSUInteger index=[_surfaces indexOfObjectIdenticalTo:surface];
    if(index!=NSNotFound && [_panel.subviews indexOfObjectIdenticalTo:surface]!=index)
        [_panel insertSubview:surface atIndex:MIN(index,_panel.subviews.count-1)];
}
- (void)layout {
    if(WXGBackdropCaptureInProgress() || WXGNativeInputLayoutInProgress())return;
    if(!_installed || _layingOut || _suspended)return;
    if(!_tool || !_panel || !_grow || !_window)return;
    // A detached/hidden page, system sheet or a voice-mode switch is not a
    // destroyed input binding. Retain the surfaces and their presented frame.
    if(_tool.window!=_window || _panel.window!=_window)return;
    _layingOut=YES;
    @try {
        if(!_editor || ![_editor isDescendantOfView:_grow]) {
            _editor=nil;for(UIView *view in WXGViews(_grow,80))if([view isKindOfClass:UITextView.class]){_editor=(id)view;break;}
        }
        BOOL bindingChanged=_lastEditorVisible!=WXGVisible(_editor,_window) ||
            _lastPanelChildCount!=_panel.subviews.count || _lastGrowChildCount!=_grow.subviews.count;
        if(bindingChanged || CACurrentMediaTime()-_lastBindingScan>.35)[self bindOptionalActions];
        UIView *center=[self visibleCenterHost];
        if(!center) {
            for(WXGSurface *surface in _surfaces){surface.hidden=YES;surface.active=NO;}
            _centerHost=nil;return;
        }
        _centerHost=center;
        if(bindingChanged || CACurrentMediaTime()-_lastPaintScan>.35)[self clearPaint];
        else [self concealDictationBacking];   // FIX113: every pass
        [_states reapply];
        CGRect native=WXGWindowRect(center,_window);
        if(!WXGInputUsableRect(native))return;
        CGFloat minimum=WXGMeasure(_window.bounds.size.width-_window.safeAreaInsets.left-_window.safeAreaInsets.right,WXGPreferences.shared.sizeScale).inputButton;
        // Learn the real blank native row. Never infer caret/wrapping from our glass.
        if(center==_grow && _editor && _editor.text.length==0 && !_editor.markedTextRange)
            _singleLineHeight=MAX(minimum,native.size.height);
        if(_singleLineHeight<=0) {
            CGFloat line=_editor.font.lineHeight+_editor.textContainerInset.top+_editor.textContainerInset.bottom;
            CGFloat chrome=MAX(0,_grow.bounds.size.height-_editor.bounds.size.height);
            _singleLineHeight=MAX(minimum,MIN(native.size.height,line+chrome));
        }
        UIControl *rightAction=WXGVisible(_sendButton,_window)?_sendButton:WXGVisible(_attachment,_window)?_attachment:nil;
        NSMutableArray<UIControl *> *rightControls=[NSMutableArray array];
        if(WXGVisible(_emojiButton,_window))[rightControls addObject:_emojiButton];
        if(rightAction && rightAction!=_emojiButton)[rightControls addObject:rightAction];
        CGRect first=rightControls.count?[self inkForControl:rightControls[0]]:CGRectZero;
        CGRect second=rightControls.count>1?[self inkForControl:rightControls[1]]:CGRectZero;
        WXGCompactInput shape=WXGCompactInputLayout(_window.bounds.size.width,_window.safeAreaInsets.left,_window.safeAreaInsets.right,
            (WXGRect){native.origin.x,native.origin.y,native.size.width,native.size.height},_singleLineHeight,first.size.width,second.size.width,(int)rightControls.count);
        CGRect content=native;content.origin.x=shape.center.x;content.size.width=shape.center.w;
        [self placeNative:center windowRect:content];
        if(WXGVisible(_voiceButton,_window))[self placeControl:_voiceButton ink:[self inkForControl:_voiceButton] x:shape.leftInkX y:shape.sideMidY];
        for(NSUInteger i=0;i<rightControls.count;i++)[self placeControl:rightControls[i] ink:i?second:first x:shape.rightInkX[i] y:shape.sideMidY];
        [self placeSurface:_surfaces[0] windowRect:WXGCGRect(shape.left)];
        [self placeSurface:_surfaces[1] windowRect:WXGCGRect(shape.center)];
        [self placeSurface:_surfaces[2] windowRect:WXGCGRect(shape.right)];
    } @catch(NSException *exception) {
        // Keep native editing available even if a particular WeChat build
        // cannot expose a stable geometry. Paint can always be restored.
        WXGLog(@"输入材质布局异常：%@",exception.reason);[self restore];
    } @finally {_layingOut=NO;}
}
- (void)reapplyPaint {
    if(_installed && _tool.window)[_states reapply];
}
- (void)setSuspended:(BOOL)suspended {
    if(_suspended==suspended)return;_suspended=suspended;
    for(WXGSurface *surface in _surfaces)surface.active=!suspended && _installed && !surface.hidden;
    if(!suspended){[_states reapply];[self layout];}
}
- (void)restore {
    if(!_installed)return;_installed=NO;
    for(WXGSurface *surface in _surfaces) {
        surface.active=NO;surface.glass.backdropExclusions=@[];surface.hidden=YES;[surface removeFromSuperview];
    }
    WXGReleaseInputHost(_grow);WXGReleaseInputTool(_tool,self);[_states restore];_states=nil;[_nativeControls removeAllObjects];
    [_appliedFrames removeAllObjects];[_inkCache removeAllObjects];[_grow setNeedsLayout];[_panel setNeedsLayout];
    _tool=_panel=_grow=_dictation=_centerHost=nil;_editor=nil;
    _attachment=_dictationButton=_sendButton=_voiceButton=_emojiButton=nil;_controller=nil;
    WXGInvalidateSharedBackdrop();
}
- (NSDictionary *)evidence {
    NSMutableArray *surfaces=[NSMutableArray array],*controls=[NSMutableArray array];
    for(WXGSurface *surface in _surfaces)[surfaces addObject:surface.evidence];
    for(UIControl *control in _nativeControls)if(controls.count<20) {
        [controls addObject:@{@"class":NSStringFromClass(control.class),@"visible":@(WXGVisible(control,_window)),
            @"rect":WXGInputRectEvidence(WXGWindowRect(control,_window)),@"actions":WXGActionNames(control),
            @"enabled":@(control.enabled),@"allControlEvents":@(control.allControlEvents),@"nativeHitTestingRetained":@YES}];
    }
    NSMutableDictionary *editor=[NSMutableDictionary dictionary];
    if(_editor) {
        editor[@"class"]=NSStringFromClass(_editor.class);editor[@"firstResponder"]=@(_editor.isFirstResponder);
        editor[@"rect"]=WXGInputRectEvidence(WXGWindowRect(_editor,_window));
        editor[@"bounds"]=NSStringFromCGRect(_editor.bounds);editor[@"textLength"]=@(_editor.text.length);
        editor[@"contentOffset"]=NSStringFromCGPoint(_editor.contentOffset);editor[@"contentSize"]=NSStringFromCGSize(_editor.contentSize);
        editor[@"contentInset"]=NSStringFromUIEdgeInsets(_editor.contentInset);editor[@"textContainerInset"]=NSStringFromUIEdgeInsets(_editor.textContainerInset);
        editor[@"textContainerSize"]=NSStringFromCGSize(_editor.textContainer.size);
        editor[@"lineFragmentPadding"]=@(_editor.textContainer.lineFragmentPadding);
        editor[@"selectedRange"]=NSStringFromRange(_editor.selectedRange);editor[@"hasMarkedText"]=@(_editor.markedTextRange!=nil);
        @try {UITextRange *range=_editor.selectedTextRange;if(range)editor[@"caretRect"]=NSStringFromCGRect([_editor caretRectForPosition:range.end]);}
        @catch(__unused NSException *exception) {editor[@"caretRect"]=@"unavailable";}
    }
    return @{@"installed":@(_installed),@"suspended":@(_suspended),@"status":_status?:@"等待聊天页",@"surfaces":surfaces,
        @"geometryPolicy":@"compact host width and native control origins; untouched TextKit, bounds and actions",@"nativeEditorGeometryUntouched":@YES,
        @"dictationAnimationRetained":@YES,@"dictationBackingsConcealed":@(_dictationBackings),@"leftCircle":@YES,@"rightGlyphGapsEqual":@YES,
        @"centerHostClass":_centerHost?NSStringFromClass(_centerHost.class):@"none",
        @"growRect":WXGInputRectEvidence(WXGWindowRect(_grow,_window)),@"editor":editor,@"nativeControls":controls,
        @"paintAndLayout":_states.evidence?:@[]};
}
@end
