#import "WXGIntegration.h"
#import "WXGInputPolicy.h"
#import "WXGInputSettledGeometry.h"
#import "WXGInputRepairPolicy.h"
#import <objc/runtime.h>

static WXGRect WXGInputRect(CGRect r) {return (WXGRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
/* FIX113 / R25: the two-ended bar's icons: crisp unclipped vector glyphs
   matching exact optical diameter across emoji/send/keyboard/voice/plus, or,
   when switched off, WeChat's own native button artwork. */
static BOOL WXGInputSystemIcons(void) {return [WXGConfig.shared extraNumber:@"inputSystemIcons"]>.5;}
// FIX115 J: the capsule's height, the plus' size, the side margin and the gap (基本设置).
static WXGInputSize WXGInputConfiguredSize(void) {
    WXGConfig *c=WXGConfig.shared;
    return (WXGInputSize){[c extraNumber:@"inputPillHeight"],[c extraNumber:@"inputPlusSize"],[c extraNumber:@"inputSideMargin"],[c extraNumber:@"inputPlusGap"]};
}
// WeChat's own artwork: only a button's image (never a background picture
// found among its subviews: the send key's green plate, the dictation host's backing).
static UIImage *WXGInputNativeArtwork(UIControl *native) {
    return [native isKindOfClass:UIButton.class]?((UIButton *)native).currentImage:nil;
}
static void WXGInputSetActionIcon(WXGSurface *surface,NSString *vectorName,CGFloat diameter,UIControl *native) {
    UIImage *own=WXGInputSystemIcons()?nil:WXGInputNativeArtwork(native);
    if(own) {
        surface.vectorIconName=nil;
        if(!surface.naturalIconSize){surface.naturalIconSize=YES;[surface setNeedsLayout];}
        [surface setImage:own title:nil count:nil];
    }else {
        if(surface.naturalIconSize){surface.naturalIconSize=NO;[surface setNeedsLayout];}
        surface.vectorIconDiameter=diameter;
        surface.vectorIconName=vectorName;
        [surface setImage:nil title:nil count:nil];
    }
}

/* FIX87: the emoji button's shape, to tell WeChat's two images apart (a
   smiley; a keyboard while its expression panel is up): 16 x 16 alpha, so
   colour and appearance do not matter. */
static NSData *WXGInputImagePrint(UIImage *image) {
    CGImageRef cg=image.CGImage;
    if(!cg)return nil;
    uint8_t pixels[256]={0};
    CGContextRef context=CGBitmapContextCreate(pixels,16,16,8,16,NULL,(CGBitmapInfo)kCGImageAlphaOnly);
    if(!context)return nil;
    CGContextDrawImage(context,CGRectMake(0,0,16,16),cg);
    CGContextRelease(context);
    return [NSData dataWithBytes:pixels length:sizeof pixels];
}
static double WXGInputPrintDistance(NSData *a,NSData *b) {
    if(a.length!=256 || b.length!=256)return 0;
    const uint8_t *x=a.bytes,*y=b.bytes;double sum=0;
    for(int i=0;i<256;i++)sum+=fabs((double)x[i]-(double)y[i]);
    return sum/(256*255.);
}
/* R25: native MMGrowDictationIconView active check covering all observed states
   (green 24x24 circle, 32x32 pulse halo, MMLoadingIndicatorView, and the
   green/white mic UIImageViews inside MMTransparentButton). */
static BOOL WXGInputDictationNativeActive(UIView *icon,UIControl *button) {
    if(!icon || !icon.window)return NO;
    if(button && button.selected)return YES;
    NSMutableArray<CALayer *> *queue=[NSMutableArray arrayWithObject:icon.layer];
    for(NSUInteger i=0;i<queue.count && i<64;i++) {
        CALayer *layer=queue[i];
        if(layer.animationKeys.count)return YES;
        if(layer.sublayers)[queue addObjectsFromArray:layer.sublayers];
    }
    CGFloat iconW=icon.bounds.size.width;
    for(UIView *sub in icon.subviews) {
        if(sub.hidden || sub.alpha<=.05)continue;
        if([sub isKindOfClass:UIControl.class]) {
            NSMutableArray<UIImageView *> *mics=[NSMutableArray array];
            for(UIView *child in sub.subviews)if([child isKindOfClass:UIImageView.class])[mics addObject:(UIImageView *)child];
            if(mics.count>=2) {
                for(NSUInteger i=1;i<mics.count;i++)if(!mics[i].hidden && mics[i].alpha>.05)return YES;
                if(mics[0].hidden || mics[0].alpha<.5)return YES;
            }
            if(sub!=button)return YES;
            continue;
        }
        // Skip the static wide VoiceBgMask wrapper (52x40 vs 32x40 icon).
        if([NSStringFromClass(sub.class) isEqual:@"UIView"] && sub.bounds.size.width>iconW+6.)continue;
        if([NSStringFromClass(sub.class) isEqual:@"UIView"] && sub.bounds.size.width>=16. && sub.bounds.size.height>=16.)return YES;
        NSString *cls=NSStringFromClass(sub.class);
        if([cls containsString:@"Loading"] || [cls containsString:@"Wave"] || [cls containsString:@"Record"] || [cls containsString:@"Dictation"])return YES;
    }
    for(UIView *v in WXGViews(icon,48)) {
        if(v==icon || v.hidden || v.alpha<=.05)continue;
        if([v isKindOfClass:UIImageView.class] && (((UIImageView *)v).isAnimating || ((UIImageView *)v).animationImages.count))return YES;
        if([v isKindOfClass:UIActivityIndicatorView.class])return YES;
    }
    return NO;
}

/* R25: forward both pointInside:withEvent: and hitTest:withEvent: on
   InputToolViewBar, MMGrowTextView, and MMGrowDictationIconView so touches on
   the repositioned dictation button always reach MMTransparentButton's
   iconClicked action and never get stolen by siblings or clipped by _grow. */
static char WXGDictationTouchTargetKey;
@interface WXGWeakBox : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,weak) id adapter;
@end
@implementation WXGWeakBox
@end
@interface WXGInputAdapter (WXGDockDictationTouch)
- (void)noteDictationTouched;
- (UIControl *)liveDictationControlIn:(UIView *)dictation window:(UIWindow *)w;
@end
static void WXGSetDictationTouchTarget(UIView *host,UIView *target,id adapter) {
    if(!host)return;
    if(!target){objc_setAssociatedObject(host,&WXGDictationTouchTargetKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;}
    WXGWeakBox *box=objc_getAssociatedObject(host,&WXGDictationTouchTargetKey);
    if(!box){box=[WXGWeakBox new];objc_setAssociatedObject(host,&WXGDictationTouchTargetKey,box,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    box.view=target;
    box.adapter=adapter;
}
static BOOL WXGInstallDictationTouchHook(UIView *host) {
    if(!host || WXGIsPluginView(host))return NO;
    static NSMutableSet<NSString *> *hooked;static dispatch_once_t once;
    dispatch_once(&once,^{hooked=[NSMutableSet set];});
    Class cls=[host class];
    NSString *key=NSStringFromClass(cls);
    if(!cls || !key || cls==UIView.class || cls==UIControl.class || cls==UIResponder.class || [key hasPrefix:@"NSKVONotifying_"])return NO;
    if([hooked containsObject:key])return YES;
    SEL piSel=@selector(pointInside:withEvent:);
    Method piM=class_getInstanceMethod(cls,piSel);
    if(!piM)return NO;
    IMP piOwn=WXGCapturedImplementation(cls,piSel);Class superclass=class_getSuperclass(cls);
    IMP piRep=imp_implementationWithBlock(^BOOL(UIView *self,CGPoint p,UIEvent *ev) {
        BOOL hit=((BOOL (*)(id,SEL,CGPoint,UIEvent *))WXGThrough(piOwn,superclass,piSel))(self,piSel,p,ev);
        WXGWeakBox *box=objc_getAssociatedObject(self,&WXGDictationTouchTargetKey);
        UIView *target=box.view;
        BOOL matched=hit;
        if(!matched && target && !target.hidden && target.alpha>.01 && [target isDescendantOfView:self]) {
            CGRect r=[target convertRect:target.bounds toView:self];
            if(CGRectContainsPoint(CGRectInset(r,-8,-8),p))matched=YES;
        }
        return matched;
    });
    WXGInstallOverride(cls,piSel,piRep,method_getTypeEncoding(piM));

    SEL htSel=@selector(hitTest:withEvent:);
    Method htM=class_getInstanceMethod(cls,htSel);
    if(htM) {
        IMP htOwn=WXGCapturedImplementation(cls,htSel);
        IMP htRep=imp_implementationWithBlock(^UIView *(UIView *self,CGPoint p,UIEvent *ev) {
            UIView *ownHit=((UIView *(*)(id,SEL,CGPoint,UIEvent *))WXGThrough(htOwn,superclass,htSel))(self,htSel,p,ev);
            WXGWeakBox *box=objc_getAssociatedObject(self,&WXGDictationTouchTargetKey);
            UIView *target=box.view;
            if(target && !target.hidden && target.alpha>.01 && target.window && [target isDescendantOfView:self]) {
                // Never steal taps destined for sibling WXGSurface buttons (e.g. emoji or plus).
                if(self!=target && ownHit && [ownHit isKindOfClass:WXGSurface.class])return ownHit;
                CGRect r=self==target?self.bounds:[target convertRect:target.bounds toView:self];
                CGRect touchBox=self==target?CGRectInset(r,-4,-6):CGRectInset(r,-2,-6);
                if(CGRectContainsPoint(touchBox,p)) {
                    if([box.adapter respondsToSelector:@selector(noteDictationTouched)])[box.adapter noteDictationTouched];
                    UIControl *btn=[box.adapter respondsToSelector:@selector(liveDictationControlIn:window:)]?[box.adapter liveDictationControlIn:target window:target.window]:nil;
                    UIView *cand=nil;
                    if(self!=target) {
                        cand=[target hitTest:[self convertPoint:p toView:target] withEvent:ev];
                    }else if(ownHit && ownHit!=self) {
                        cand=ownHit;
                    }
                    // Skip non-interactive wrappers like the 52x40 VoiceBgMask container.
                    if(cand && ([cand isKindOfClass:UIControl.class] || cand.gestureRecognizers.count>0 || (btn && [cand isDescendantOfView:btn])))return cand;
                    if(btn)return btn;
                    return target;
                }
            }
            return ownHit;
        });
        WXGInstallOverride(cls,htSel,htRep,method_getTypeEncoding(htM));
    }
    [hooked addObject:key];
    return YES;
}

static void WXGSetInputForeground(UIView *panel,WXGSurface *mic,WXGSurface *emoji) {
    NSArray<UIView *> *ordered=emoji?@[mic,emoji]:@[mic];
    NSArray<UIView *> *children=panel.subviews;
    uintptr_t desired[2]={0},actual[2]={0};size_t count=ordered.count;
    size_t available=MIN(count,children.count);
    for(size_t i=0;i<count;i++)desired[i]=(uintptr_t)(__bridge void *)ordered[i];
    for(size_t i=0;i<available;i++)actual[i]=(uintptr_t)(__bridge void *)children[children.count-available+i];
    // Test the FINAL suffix before touching the hierarchy. Moving mic then
    // emoji unconditionally dirties the native panel on every CA layout pass.
    if(WXGInputSuffixMatches(actual,available,desired,count))return;
    for(UIView *view in ordered)if(view.superview==panel && panel.subviews.lastObject!=view)
        [panel bringSubviewToFront:view];
}

@interface WXGInputAdapter ()
@property(nonatomic) BOOL installed,layingOut,suspended,usingNativeLayout;
@property(nonatomic,strong) WXGNativeInputAdapter *nativeAdapter;
@property(nonatomic,weak) UIView *tool,*panel,*grow,*dictation;
@property(nonatomic,weak) UITextView *editor;
@property(nonatomic,weak) UIControl *attachment,*dictationButton,*sendButton,*voiceButton,*emojiButton;
@property(nonatomic,weak) UIControl *recordButton;
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,strong) WXGStateBag *states;
@property(nonatomic,strong) NSArray<WXGSurface *> *surfaces;
@property(nonatomic) CGFloat nativeGrowHeight,nativeTextHeight;
@property(nonatomic) CGFloat singleLineHeight;
@property(nonatomic) CGRect lastGrowFrame,lastRecordFrame,lastEmojiFrame,lastDictationFrame,lastMicSlotRect;
@property(nonatomic) BOOL lastVoiceMode,usingNativeDictation,dictationTouchHooked,pluginHidDictation;
@property(nonatomic) BOOL lastEditing,lastHasText,lastEditorVisible;
@property(nonatomic) CFTimeInterval dictationHoldUntil;
@property(nonatomic,strong) NSMutableArray<NSString *> *dictationTrace;
@property(nonatomic) NSUInteger lastPanelChildCount,lastGrowChildCount,dictationPlacements,dictationBackings;
@property(nonatomic) WXGInputAction rightAction;
@property(nonatomic) CFTimeInterval lastBindingScan,lastPaintScan;
@property(nonatomic,copy) NSString *status;
// FIX87: the emoji button's state (smiley / keyboard), learned from its shape.
@property(nonatomic,strong) UIImage *emojiNativeImage;
@property(nonatomic,strong) NSData *emojiNativePrint;
@property(nonatomic) CFTimeInterval emojiPrintSince,restingSince;
@property(nonatomic) BOOL emojiPanel;
@property(nonatomic) double emojiDistance;
@end
// FIX87: the shape of WeChat's smiley emoji button, learned once per run.
static NSData *WXGEmojiFacePrint;
@implementation WXGInputAdapter
@synthesize installed=_installed,surfaces=_surfaces,tool=_tool;
- (BOOL)installed {return _usingNativeLayout?_nativeAdapter.installed:_installed;}
- (NSArray<WXGSurface *> *)surfaces {return _usingNativeLayout?_nativeAdapter.surfaces:_surfaces;}
- (UIView *)tool {return _usingNativeLayout?_nativeAdapter.tool:_tool;}
- (instancetype)init {
    if((self=[super init])) {
        WXGSurface *plus=[WXGSurface new],*pill=[WXGSurface new],*mic=[WXGSurface new],*emoji=[WXGSurface new];
        plus.role=@"attachment";plus.vectorIconName=@"plus";plus.vectorIconDiameter=23.;
        plus.accessibilityLabel=@"微信附件菜单";
        pill.role=@"input";pill.materialOnly=YES;pill.userInteractionEnabled=NO;pill.isAccessibilityElement=NO;pill.pressFixed=YES;   // FIX87 / R25
        mic.role=@"dictation";mic.plain=YES;mic.pressProxy=pill;
        emoji.role=@"emoji";emoji.plain=YES;emoji.pressProxy=pill;emoji.accessibilityLabel=@"微信表情";
        _surfaces=@[plus,pill,mic,emoji];
    }return self;
}
- (void)noteDictationTouched {
    _dictationHoldUntil=MAX(_dictationHoldUntil,CACurrentMediaTime()+1.6);
}
- (UIView *)viewValue:(NSString *)key on:(id)object {
    id v=WXGRead(object,key);return [v isKindOfClass:UIView.class]?v:nil;
}
- (UIControl *)controlValue:(NSString *)key on:(id)object {
    id v=WXGRead(object,key);return [v isKindOfClass:UIControl.class]?v:nil;
}
- (UIControl *)liveDictationControlIn:(UIView *)dictation window:(UIWindow *)w {
    if(!dictation || !w)return nil;
    UIControl *fallback=nil;
    for(UIView *v in WXGViews(dictation,48)) {
        if(![v isKindOfClass:UIControl.class] || v.window!=w || v.hidden || v.alpha<=.01)continue;
        UIControl *c=(UIControl *)v;
        if(WXGCanForward(c))return c;
        if(!fallback)fallback=c;
    }
    return fallback;
}
- (void)bindOptionalActions {
    _lastBindingScan=CACurrentMediaTime();_dictation=nil;UIControl *button=nil;
    for(UIView *v in WXGViews(_grow,90)) {
        if([NSStringFromClass(v.class) isEqual:@"MMGrowDictationIconView"]){_dictation=v;break;}
    }
    if(!_dictation && _panel) {
        for(UIView *v in WXGViews(_panel,120)) {
            if([NSStringFromClass(v.class) isEqual:@"MMGrowDictationIconView"]){_dictation=v;break;}
        }
    }
    for(UIView *v in WXGViews(_dictation,32))
        if([v isKindOfClass:UIControl.class] && [WXGActionNames((id)v) containsObject:@"iconClicked"]){button=(id)v;break;}
    if(!button)button=[self liveDictationControlIn:_dictation window:_window];
    _dictationButton=button;
    _attachment=[self controlValue:@"_attachmentButton" on:_tool];
    _sendButton=[self controlValue:@"sendButton" on:_tool];
    _voiceButton=[self controlValue:@"_inputModeChangeButton" on:_tool];
    _recordButton=[self controlValue:@"_recordButton" on:_tool];
    _emojiButton=nil;
    for(UIView *v in WXGViews(_panel,100))if([v isKindOfClass:UIControl.class]) {
        NSArray *actions=WXGActionNames((id)v);
        if(!_sendButton && [actions containsObject:@"onTapSendButton"])_sendButton=(id)v;
        if(!_voiceButton && [actions containsObject:@"onInputModeChangeButtonClicked:"])_voiceButton=(id)v;
        if([actions containsObject:@"onExpressionButtonClicked:"])_emojiButton=(id)v;
    }
    _lastEditing=_editor.isFirstResponder;_lastHasText=_editor.text.length>0;
    _lastEditorVisible=WXGVisible(_editor,_window);
    _lastPanelChildCount=_panel.subviews.count;_lastGrowChildCount=_grow.subviews.count;
}
- (void)rememberNativeFrame:(UIView *)view lastApplied:(CGRect)last {
    if(!view)return;WXGViewState *state=[_states remember:view];state.restoreGeometry=YES;
    WXGRect saved=WXGInputRect(state.originalFrame),current=WXGInputRect(view.frame);
    WXGRect native=WXGInputNativeFrame(saved,current,WXGInputRect(last),!CGRectIsNull(last));
    [state updateNativeFrame:WXGCGRect(native)];
}
// R25: strip the static wide VoiceBgMask backing wrapper (52x40, which has
// userInteractionEnabled=YES in WeChat) inside MMGrowDictationIconView while
// keeping all active green-circle/halo/loading/button subviews untouched.
- (void)concealDictationBacking {
    if(!_dictation || !_states)return;
    for(UIView *view in _dictation.subviews) {
        if([view isKindOfClass:UIControl.class] || view.gestureRecognizers.count ||
           ![NSStringFromClass(view.class) isEqual:@"UIView"] || view.bounds.size.width<=_dictation.bounds.size.width+6)continue;
        if(view.subviews.count!=1 || ![view.subviews.firstObject isKindOfClass:UIImageView.class])continue;
        UIImageView *paint=(id)view.subviews.firstObject;
        if(paint.bounds.size.width>=_dictation.bounds.size.width*1.4 && !paint.animationImages.count && !paint.layer.animationKeys.count) {
            if(!view.layer.mask)++_dictationBackings;
            [_states conceal:view];
        }else {
            [_states unconceal:view];
        }
    }
}
- (void)clearDictationTouchTargets {
    if(_dictation) {
        WXGSetDictationTouchTarget(_dictation,nil,nil);
        for(UIView *a=_dictation.superview;a && a!=_panel;a=a.superview)WXGSetDictationTouchTarget(a,nil,nil);
    }
    if(_grow)WXGSetDictationTouchTarget(_grow,nil,nil);
    if(_panel)WXGSetDictationTouchTarget(_panel,nil,nil);
}
- (void)placeNativeDictation:(CGRect)windowRect {
    UIView *icon=_dictation;UIView *parent=icon.superview;
    if(!icon || !parent || !_window)return;
    if(_pluginHidDictation) {
        [_states restoreView:icon];
        _pluginHidDictation=NO;
    }
    [self rememberNativeFrame:icon lastApplied:_lastDictationFrame];
    CGRect inParent=[_window convertRect:windowRect toView:parent];
    CGSize sz=icon.bounds.size;
    if(sz.width<8 || sz.height<8)sz=inParent.size;
    CGRect target=CGRectMake(round(CGRectGetMidX(inParent)-sz.width*.5),round(CGRectGetMidY(inParent)-sz.height*.5),sz.width,sz.height);
    if(!CGRectEqualToRect(icon.frame,target)) {
        [UIView performWithoutAnimation:^{icon.frame=target;}];
        ++_dictationPlacements;
    }
    _lastDictationFrame=icon.frame;
    if(WXGInstallDictationTouchHook(icon))_dictationTouchHooked=YES;
    WXGSetDictationTouchTarget(icon,icon,self);
    for(UIView *a=parent;a && a!=_panel;a=a.superview) {
        [_states allowOverflow:a];
        if(WXGInstallDictationTouchHook(a))_dictationTouchHooked=YES;
        WXGSetDictationTouchTarget(a,icon,self);
    }
    if(_panel) {
        if(WXGInstallDictationTouchHook(_panel))_dictationTouchHooked=YES;
        WXGSetDictationTouchTarget(_panel,icon,self);
    }
    [self concealDictationBacking];
}
- (BOOL)installInController:(UIViewController *)vc window:(UIWindow *)w {
    if(WXGPreferences.shared.nativeInputTest) {
        if(!_usingNativeLayout){[self restore];_nativeAdapter=_nativeAdapter?:[WXGNativeInputAdapter new];_usingNativeLayout=YES;}
        return [_nativeAdapter installInController:vc window:w];
    }
    if(_usingNativeLayout){[_nativeAdapter restore];_usingNativeLayout=NO;}
    if(_installed && _controller==vc && _grow.window==w && [_grow isDescendantOfView:vc.view] &&
       [self viewValue:@"_textView" on:_tool]==_grow && [self viewValue:@"_toolPanelView" on:_tool]==_panel){[self setSuspended:NO];return YES;}
    if(_installed)[self restore];
    UIView *tool=nil;
    for(UIView *v in WXGViews(vc.view,1200))if([NSStringFromClass(v.class) isEqual:@"MMInputToolView"]){tool=v;break;}
    WXGClaimInputTool(tool,self);
    UIView *panel=[self viewValue:@"_toolPanelView" on:tool],*grow=[self viewValue:@"_textView" on:tool];
    UIControl *attachment=[self controlValue:@"_attachmentButton" on:tool];
    UIControl *record=[self controlValue:@"_recordButton" on:tool];
    UITextView *editor=nil;
    for(UIView *v in WXGViews(grow,80))if([v isKindOfClass:UITextView.class]){editor=(id)v;break;}
    if(!tool || !panel || !grow || !editor || (!WXGVisible(grow,w) && !WXGVisible(record,w)) || !WXGCanForward(attachment)) {
        _status=@"等待原生编辑器/附件按钮布局完成，将在布局与页面回归时重试";return NO;
    }
    _tool=tool;_panel=panel;_grow=grow;_editor=editor;_attachment=attachment;_window=w;_controller=vc;
    _states=[WXGStateBag new];
    [_states remember:grow].restoreGeometry=YES;
    _nativeGrowHeight=MAX(40,grow.bounds.size.height);_nativeTextHeight=MAX(24,editor.bounds.size.height);
    _singleLineHeight=MIN(grow.bounds.size.height,MAX(24,editor.font.lineHeight+editor.textContainerInset.top+
        editor.textContainerInset.bottom+MAX(0,grow.bounds.size.height-editor.bounds.size.height)));
    _lastGrowFrame=_lastRecordFrame=_lastEmojiFrame=_lastDictationFrame=_lastMicSlotRect=CGRectNull;
    [self bindOptionalActions];
    _surfaces[0].original=attachment;
    for(WXGSurface *s in _surfaces) {
        s.glass.sourceView=vc.view;s.glass.backdropExclusions=@[tool];s.active=YES;s.hidden=NO;[s applyConfig];
    }
    _suspended=NO;_installed=YES;_status=@"两端输入：原生语音转文字按钮位移保留全部功能；未编辑切换语音，有文字发送";
    [self clearPaint];[self layout];return YES;
}
- (void)clearPaint {
    _lastPaintScan=CACurrentMediaTime();UIView *background=[self viewValue:@"_toolView" on:_tool];
    NSMutableArray *protected=[NSMutableArray arrayWithObjects:_grow,_editor,nil];
    if(_recordButton)[protected addObject:_recordButton];
    if(_dictation)[protected addObject:_dictation];
    [_states clear:_tool];[_states stripChrome:background preserving:protected];
    [_states stripChrome:_panel preserving:protected];
    [_states clear:_grow];[_states clear:_editor];
    UIView *growBG=[self viewValue:@"_backgroundView" on:_grow];
    if(growBG && growBG!=_grow && [growBG isDescendantOfView:_grow])[_states hide:growBG];
    [_states hide:[self viewValue:@"_fakeTextBackgroundView" on:_tool]];
    if(_recordButton) {
        [_states clear:_recordButton];
        UIView *paint=[self viewValue:@"_backgroundView" on:_recordButton];
        if([paint isKindOfClass:UIImageView.class] && [paint isDescendantOfView:_recordButton])[_states hide:paint];
    }
    // Some builds put the toolbar separator and safe-area fill beside _toolView.
    for(UIView *v in _tool.subviews) {
        if(v==_panel || v==background || [_panel isDescendantOfView:v])continue;
        NSString *n=NSStringFromClass(v.class).lowercaseString;
        if([n containsString:@"background"] || [n containsString:@"separator"] ||
           (v.bounds.size.height<=2 && v.bounds.size.width>_panel.bounds.size.width*.8))
            [_states stripChrome:v preserving:protected];
    }
    if(WXGCanForward(_attachment))[_states hide:_attachment];
    if(WXGCanForward(_voiceButton))[_states hide:_voiceButton];
}
- (void)layout {
    if(WXGBackdropCaptureInProgress() || WXGNativeInputLayoutInProgress())return;
    if(_usingNativeLayout){[_nativeAdapter layout];return;}
    if(!_installed || _layingOut || _suspended)return;
    if(_grow && !_grow.window){[self setSuspended:YES];return;}
    if(!_panel || !_window || !_grow || !_editor || _grow.window!=_window)return;
    _layingOut=YES;
    @try {
        UIView *grow=_grow;UITextView *editor=_editor;UIWindow *w=_window;
        BOOL bindingChanged=_lastEditing!=editor.isFirstResponder || _lastHasText!=(editor.text.length>0) ||
            _lastEditorVisible!=WXGVisible(editor,w) || _lastPanelChildCount!=_panel.subviews.count || _lastGrowChildCount!=grow.subviews.count;
        if(bindingChanged || CACurrentMediaTime()-_lastBindingScan>.35 || (_sendButton && _sendButton.window!=w) || (_dictationButton && _dictationButton.window!=w))[self bindOptionalActions];
        BOOL holdingVoice=WXGVisible(_recordButton,w) && (!WXGVisible(grow,w) || !WXGVisible(editor,w));
        UIView *content=holdingVoice?_recordButton:grow;
        if(!WXGVisible(_panel,w) || !WXGVisible(content,w)) {
            for(WXGSurface *surface in _surfaces){surface.hidden=YES;surface.active=NO;}return;
        }
        [self rememberNativeFrame:content lastApplied:holdingVoice?_lastRecordFrame:_lastGrowFrame];
        CGRect nativeRect=WXGWindowRect(content,w);
        _nativeGrowHeight=MAX(40,content.bounds.size.height);_nativeTextHeight=MAX(24,editor.bounds.size.height);
        if(!holdingVoice && !editor.text.length && !editor.markedTextRange)_singleLineHeight=nativeRect.size.height;
        WXGInputSize size=WXGInputConfiguredSize();   // FIX115 J
        WXGInputGeometry g=WXGInputBottomAnchoredLayoutSized(w.bounds.size.width,w.safeAreaInsets.left,w.safeAreaInsets.right,
            WXGInputRect(nativeRect),_singleLineHeight,_nativeTextHeight,WXGPreferences.shared.sizeScale,size);
        WXGSurface *plus=_surfaces[0],*pill=_surfaces[1],*mic=_surfaces[2];
        WXGMetrics m=WXGMeasure(w.bounds.size.width-w.safeAreaInsets.left-w.safeAreaInsets.right,WXGPreferences.shared.sizeScale);
        BOOL hasEmoji=_emojiButton && _emojiButton.window==w && !_emojiButton.hidden && WXGCanForward(_emojiButton);
        CGFloat emojiDiameter=MIN(g.mic.h,MAX(32.*m.scale,m.inputButton*.82));
        CGRect emojiRect=CGRectMake(g.mic.x-emojiDiameter-3.*m.scale,g.mic.y+g.mic.h*.5-emojiDiameter*.5,emojiDiameter,emojiDiameter);
        CGFloat iconD=round(WXGClamp(g.mic.h*.64,21.,25.)*2.)/2.;
        CGFloat base=g.mic.h/.9;
        pill.maximumCornerRadius=MIN(g.pill.h*.5,MAX(24*m.scale,base*.5));
        [pill placeMaterial:[w convertRect:WXGCGRect(g.pill) toView:_panel] inParent:_panel];
        [pill observeTouchesInView:_tool?:_panel];
        CGFloat firstAction=hasEmoji?CGRectGetMinX(emojiRect):g.mic.x;
        CGFloat gap=6*m.scale;
        WXGRect textPill=g.pill;CGFloat inset=holdingVoice?0:WXGInputTextInset(base,m.inputButton);
        textPill.x+=inset;textPill.w=MAX(40,textPill.w-inset);
        WXGRect host=WXGInputContentHost(WXGInputRect(nativeRect),textPill,firstAction,gap);
        CGRect target=[w convertRect:WXGCGRect(host) toView:content.superview];
        BOOL changed=!CGRectEqualToRect(content.frame,target);
        [UIView performWithoutAnimation:^{WXGSetInputHostFrame(content,target,[self.states remember:content]);}];
        if(changed)[content setNeedsLayout];
        if(holdingVoice)_lastRecordFrame=content.frame;else _lastGrowFrame=content.frame;
        if(bindingChanged || holdingVoice!=_lastVoiceMode || CACurrentMediaTime()-_lastPaintScan>.35)[self clearPaint];
        _lastVoiceMode=holdingVoice;
        [_states reapply];
        UIView *branch=content;
        while(branch.superview && branch.superview!=_panel)branch=branch.superview;
        if(branch.superview==_panel && [_panel.subviews indexOfObject:pill]>[_panel.subviews indexOfObject:branch])
            [_panel insertSubview:pill belowSubview:branch];
        [plus placeMaterial:[w convertRect:WXGCGRect(g.plus) toView:_panel] inParent:_panel];
        CGRect micSlot=WXGCGRect(g.mic);_lastMicSlotRect=micSlot;
        [mic placeMaterial:[w convertRect:micSlot toView:_panel] inParent:_panel];
        UIControl *liveDictBtn=_dictation?[self liveDictationControlIn:_dictation window:w]:nil;
        CFTimeInterval nowT=CACurrentMediaTime();
        BOOL inGrace=!holdingVoice && nowT<_dictationHoldUntil;
        if(_pluginHidDictation && _dictation && (editor.isFirstResponder || inGrace || liveDictBtn!=nil)) {
            [_states restoreView:_dictation];
            _pluginHidDictation=NO;
        }
        BOOL dictationAnimating=_dictation && WXGInputDictationNativeActive(_dictation,liveDictBtn?:_dictationButton);
        if(dictationAnimating)_dictationHoldUntil=MAX(_dictationHoldUntil,nowT+.65);
        BOOL dictationControlOK=(_dictationButton.window==w && WXGCanForward(_dictationButton)) || (liveDictBtn!=nil);
        BOOL nativeDictationReady=!holdingVoice && _dictation && _dictation.superview && _dictation.window==w &&
            !_dictation.hidden && _dictation.alpha>.01 && (dictationControlOK || dictationAnimating || inGrace);
        _rightAction=WXGInputRightAction(editor.isFirstResponder,holdingVoice,editor.text.length>0,
            _voiceButton.window==w && WXGCanForward(_voiceButton),nativeDictationReady,
            _sendButton.window==w && WXGCanForward(_sendButton));
        BOOL keyboard=_rightAction==WXGInputActionKeyboard;
        if(holdingVoice || keyboard)_dictationHoldUntil=0;
        else if(nativeDictationReady && ((editor.isFirstResponder && dictationAnimating) || dictationAnimating || inGrace))
            _rightAction=WXGInputActionDictation;
        BOOL sending=_rightAction==WXGInputActionSend,dictating=_rightAction==WXGInputActionDictation;
        BOOL useNativeDictation=dictating && nativeDictationReady;
        if(useNativeDictation!=_usingNativeDictation || inGrace || dictationAnimating) {
            if(!_dictationTrace)_dictationTrace=[NSMutableArray array];
            NSString *note=[NSString stringWithFormat:@"%.2f use:%d act:%ld resp:%d txt:%d hold:%d anim:%d grace:%d ctrl:%@ hid:%d",
                WXGSecondsSinceLoad(),useNativeDictation,(long)_rightAction,editor.isFirstResponder,editor.text.length>0,
                holdingVoice,dictationAnimating,inGrace,liveDictBtn?NSStringFromClass(liveDictBtn.class):@"none",_dictation.hidden];
            if(![_dictationTrace.lastObject isEqualToString:note]) {
                if(_dictationTrace.count>=16)[_dictationTrace removeObjectAtIndex:0];
                [_dictationTrace addObject:note];
            }
        }
        _usingNativeDictation=useNativeDictation;
        plus.original=_attachment;
        WXGInputSetActionIcon(plus,@"plus",iconD,_attachment);
        plus.enabled=WXGCanForward(_attachment);plus.hidden=!plus.enabled;pill.hidden=NO;
        if(useNativeDictation) {
            mic.original=nil;mic.perform=nil;mic.enabled=NO;mic.hidden=YES;
            [self placeNativeDictation:micSlot];
        }else {
            [self clearDictationTouchTargets];
            if(_dictation){[_states hide:_dictation];_pluginHidDictation=YES;}
            mic.original=sending?_sendButton:_rightAction!=WXGInputActionUnavailable?_voiceButton:nil;
            mic.perform=nil;mic.enabled=WXGCanForward(mic.original);mic.hidden=!mic.enabled;
            NSString *role=sending?@"send":keyboard?@"keyboardMode":@"voiceMode";
            if(![mic.role isEqual:role]) {
                mic.role=role;
                mic.accessibilityLabel=sending?@"微信发送消息":keyboard?@"切换到文字输入":@"切换到按住说话";
            }
            WXGInputSetActionIcon(mic,sending?@"send":keyboard?@"keyboard":@"voiceMode",iconD,mic.original);
        }
        for(WXGSurface *surface in _surfaces)surface.active=!surface.hidden;
        if((useNativeDictation || mic.enabled) && WXGCanForward(_sendButton))[_states hide:_sendButton];else [_states restoreView:_sendButton];
        WXGSurface *emoji=_surfaces[3];emoji.original=hasEmoji?_emojiButton:nil;
        emoji.hidden=!hasEmoji;emoji.active=hasEmoji;emoji.enabled=hasEmoji;
        if(hasEmoji) {
            [self updateEmojiState];
            WXGInputSetActionIcon(emoji,_emojiPanel?@"keyboard":@"emoji",iconD,_emojiButton);
            emoji.accessibilityLabel=_emojiPanel?@"切换到键盘":@"微信表情";
            [emoji placeMaterial:[w convertRect:emojiRect toView:_panel] inParent:_panel];
            [_states conceal:_emojiButton];
        }else [_states restoreView:_emojiButton];
        WXGSetInputForeground(_panel,mic,hasEmoji?emoji:nil);
    } @catch(NSException *e) {WXGLog(@"输入栏布局异常：%@",e.reason);[self restore];}
    @finally {_layingOut=NO;}
}
// FIX87: the expression panel is up when WeChat's button shows another shape
// than its smiley. The smiley is learned while nothing is up (the input row
// resting at the bottom, not editing) and the button's shape has stayed the
// same for a moment (at a tap, the image changes before the row moves).
- (void)updateEmojiState {
    CFTimeInterval now=CACurrentMediaTime();
    UIImage *native=WXGButtonImage(_emojiButton);
    if(native!=_emojiNativeImage) {
        NSData *print=WXGInputImagePrint(native);
        if(!_emojiNativePrint || !print || WXGInputPrintDistance(print,_emojiNativePrint)>.02)_emojiPrintSince=now;
        _emojiNativeImage=native;_emojiNativePrint=print;
    }
    CGRect row=WXGWindowRect(_panel,_window);
    BOOL resting=!_editor.isFirstResponder && !CGRectIsEmpty(row) && CGRectGetMaxY(row)>=_window.bounds.size.height-_window.safeAreaInsets.bottom-40;
    if(!resting)_restingSince=0;else if(!_restingSince)_restingSince=now;
    if(resting && _emojiNativePrint && now-_restingSince>=.4 && now-_emojiPrintSince>=.4)WXGEmojiFacePrint=_emojiNativePrint;
    _emojiDistance=WXGEmojiFacePrint && _emojiNativePrint?WXGInputPrintDistance(WXGEmojiFacePrint,_emojiNativePrint):0;
    _emojiPanel=_emojiDistance>.06;
}
- (void)reapplyPaint {
    if(_usingNativeLayout){[_nativeAdapter reapplyPaint];return;}
    if(_installed && _tool.window){[_states reapply];if(_usingNativeDictation)[self concealDictationBacking];}
}
- (void)setSuspended:(BOOL)suspended {
    if(_usingNativeLayout){[_nativeAdapter setSuspended:suspended];return;}
    if(_suspended==suspended)return;_suspended=suspended;
    if(suspended)[self clearDictationTouchTargets];
    for(WXGSurface *surface in _surfaces)surface.active=!suspended && _installed;
    if(!suspended){[_states reapply];[self layout];}
}
- (void)restore {
    if(_usingNativeLayout){[_nativeAdapter restore];_usingNativeLayout=NO;}
    if(!_installed)return;
    _installed=NO;
    [self clearDictationTouchTargets];
    for(WXGSurface *s in _surfaces){s.active=NO;s.original=nil;s.glass.backdropExclusions=@[];s.hidden=YES;[s removeFromSuperview];}
    _surfaces[2].perform=nil;_surfaces[2].iconTint=nil;
    _emojiNativeImage=nil;_emojiNativePrint=nil;_emojiPanel=NO;_restingSince=0;_usingNativeDictation=NO;
    _pluginHidDictation=NO;_dictationHoldUntil=0;
    WXGReleaseInputHost(_grow);WXGReleaseInputTool(_tool,self);[_states restore];_states=nil;
    [_grow setNeedsLayout];[_panel setNeedsLayout];[_tool setNeedsLayout];
    _tool=_panel=_grow=_dictation=nil;_editor=nil;_attachment=_dictationButton=_sendButton=_voiceButton=_emojiButton=_recordButton=nil;_controller=nil;
    _lastGrowFrame=_lastRecordFrame=_lastEmojiFrame=_lastDictationFrame=_lastMicSlotRect=CGRectNull;_rightAction=WXGInputActionUnavailable;WXGInvalidateSharedBackdrop();
}
- (NSDictionary *)evidence {
    if(_usingNativeLayout)return _nativeAdapter.evidence;
    NSMutableArray *surfaces=[NSMutableArray array];for(WXGSurface *s in _surfaces)if(s.active)[surfaces addObject:s.evidence];
    CGRect r=WXGWindowRect(_editor,_window),dr=_dictation?WXGWindowRect(_dictation,_window):CGRectNull;
    NSMutableArray *dictSub=[NSMutableArray array];
    if(_dictation)for(UIView *v in WXGViews(_dictation,24))if(v!=_dictation) {
        [dictSub addObject:[NSString stringWithFormat:@"%@ h%d a%.1f %@",NSStringFromClass(v.class),v.hidden,v.alpha,NSStringFromCGRect(v.frame)]];
    }
    return @{@"installed":@(_installed),@"status":_status?:@"等待聊天页",@"surfaces":surfaces,
             @"editorClass":_editor?NSStringFromClass(_editor.class):@"none",@"originalEditorRetained":@(_editor!=nil),
             @"firstResponder":@(_editor.isFirstResponder),@"editorRect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],
             @"nativeGrowHeight":@(_nativeGrowHeight),@"attachmentActions":WXGActionNames(_attachment),
             @"voiceModeActions":WXGActionNames(_voiceButton),@"rightAction":@(_rightAction),@"voiceRecordingVisible":@(_lastVoiceMode),
             @"recordButtonClass":_recordButton?NSStringFromClass(_recordButton.class):@"none",@"nativeRecordGesturesRetained":@YES,
             @"dictationActions":WXGActionNames(_dictationButton),@"paintAndLayout":_states.evidence?:@[],
             @"emoji":@{@"panel":@(_emojiPanel),@"distance":@(round(_emojiDistance*1000)/1000),@"faceLearned":@(WXGEmojiFacePrint!=nil),
                        @"nativeSelected":@(_emojiButton.selected),@"nativeImage":_emojiNativeImage?[NSString stringWithFormat:@"%p %.0fx%.0f",_emojiNativeImage,_emojiNativeImage.size.width,_emojiNativeImage.size.height]:@"none"},
             @"dictation":@{@"nativeMode":@YES,@"active":@(_usingNativeDictation),@"animating":@(WXGInputDictationNativeActive(_dictation,_dictationButton)),
                            @"dictationClass":_dictation?NSStringFromClass(_dictation.class):@"none",
                            @"dictationFrame":CGRectIsNull(dr)?@"none":NSStringFromCGRect(dr),
                            @"micSlotRect":CGRectIsNull(_lastMicSlotRect)?@"none":NSStringFromCGRect(_lastMicSlotRect),
                            @"placements":@(_dictationPlacements),@"backingsConcealed":@(_dictationBackings),@"touchHooked":@(_dictationTouchHooked),
                            @"subviews":dictSub,@"trace":_dictationTrace?:@[]}};
}
@end
