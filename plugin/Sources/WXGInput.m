#import "WXGIntegration.h"
#import "WXGInputPolicy.h"
#import "WXGInputSettledGeometry.h"
#import "WXGInputRepairPolicy.h"
#import <objc/runtime.h>

static WXGRect WXGInputRect(CGRect r) {return (WXGRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
/* FIX113: the two-ended bar's icons: the plugin's set (SF Symbols, the emoji
   key as Face ID) or, switched off, WeChat's own artwork of the control each
   button stands in for (the set's symbol where WeChat shows none). */
static BOOL WXGInputSystemIcons(void) {return [WXGConfig.shared extraNumber:@"inputSystemIcons"]>.5;}
// FIX115 J: the capsule's height, the plus' size, the side margin and the gap (基本设置).
static WXGInputSize WXGInputConfiguredSize(void) {
    WXGConfig *c=WXGConfig.shared;
    return (WXGInputSize){[c extraNumber:@"inputPillHeight"],[c extraNumber:@"inputPlusSize"],[c extraNumber:@"inputSideMargin"],[c extraNumber:@"inputPlusGap"]};
}
static UIImage *WXGInputSymbol(NSString *name) {
    static NSMutableDictionary<NSString *,UIImage *> *cache;if(!cache)cache=[NSMutableDictionary dictionary];
    UIImage *image=cache[name];
    if(!image){image=[UIImage systemImageNamed:name];if(image)cache[name]=image;}
    return image;
}
// WeChat's own artwork: only a button's image (never a background picture
// found among its subviews: the send key's green plate, the dictation host's backing).
static UIImage *WXGInputNativeArtwork(UIControl *native) {
    return [native isKindOfClass:UIButton.class]?((UIButton *)native).currentImage:nil;
}
static UIImage *WXGInputIcon(NSString *symbol,UIControl *native) {
    if(!WXGInputSystemIcons()){UIImage *own=WXGInputNativeArtwork(native);if(own)return own;}
    return WXGInputSymbol(symbol);
}
// FIX113: WeChat's artwork at WeChat's own size; the set's symbols in the plugin's boxes.
static void WXGInputSetIcon(WXGSurface *surface,UIImage *image,UIControl *native) {
    BOOL own=image && image==WXGInputNativeArtwork(native);
    if(surface.naturalIconSize!=own){surface.naturalIconSize=own;[surface setNeedsLayout];}
    [surface setImage:image title:nil count:nil];
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
/* FIX87: what can show that WeChat's voice-to-text is running. Its icon view
   (MMGrowDictationIconView, hidden under the plugin's mic) is expected to
   animate or change state while it listens: the animations on its layers,
   animating image views, its button's selected state, and the integer /
   BOOL instance variables of WeChat's own classes (not UIKit's) whose names
   speak of state, compared with a snapshot from before the tap. The full
   set goes to the diagnostics so the next build can keep only what works. */
static BOOL WXGInputWatchedIvar(const char *name) {
    NSString *n=[@(name) lowercaseString];
    for(NSString *word in @[@"record",@"listen",@"dictat",@"recogn",@"work",@"start",@"run",@"activ",@"state",@"status",@"speak",@"voice",@"animat",@"play",@"busy",@"loading"])
        if([n containsString:word])return YES;
    return NO;
}
static BOOL WXGInputAppClass(Class cls) {
    const char *image=class_getImageName(cls);
    return image && strstr(image,".app/")!=NULL;   // WeChat's binary or its embedded frameworks
}
static NSDictionary<NSString *,id> *WXGInputScalarIvars(id object,BOOL watchedOnly) {
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    for(Class cls=object?object_getClass(object):Nil;cls && out.count<48;cls=class_getSuperclass(cls)) {
        if(!WXGInputAppClass(cls))continue;
        unsigned int count=0;Ivar *ivars=class_copyIvarList(cls,&count);
        for(unsigned int i=0;i<count && out.count<48;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]),*name=ivar_getName(ivars[i]);
            if(!type || !name || (watchedOnly && !WXGInputWatchedIvar(name)))continue;
            const uint8_t *base=(const uint8_t *)(__bridge void *)object+ivar_getOffset(ivars[i]);
            id value=nil;double real=NAN;BOOL floating=NO;
            switch(type[0]) {
                case 'B':value=@(*(const bool *)base);break;
                case 'c':value=@(*(const signed char *)base);break;
                case 'C':value=@(*(const unsigned char *)base);break;
                case 's':value=@(*(const short *)base);break;
                case 'S':value=@(*(const unsigned short *)base);break;
                case 'i':case 'l':value=@(*(const int *)base);break;
                case 'I':case 'L':value=@(*(const unsigned int *)base);break;
                case 'q':value=@(*(const long long *)base);break;
                case 'Q':value=@(*(const unsigned long long *)base);break;
                case 'f':floating=!watchedOnly;real=*(const float *)base;break;
                case 'd':floating=!watchedOnly;real=*(const double *)base;break;
                default:break;
            }
            // Diagnostics only; JSON cannot hold NaN or infinity.
            if(floating)value=isfinite(real)?@(real):[NSString stringWithFormat:@"%f",real];
            if(value)out[[NSString stringWithFormat:@"%s.%s",class_getName(cls),name]]=value;
        }
        free(ivars);
    }
    return out;
}
static NSDictionary *WXGInputDictationSignals(UIView *icon,UIControl *button,BOOL detail) {
    if(!icon)return @{};
    NSUInteger animations=0,images=0;NSMutableArray *keys=[NSMutableArray array],*classes=[NSMutableArray array];
    NSMutableArray<CALayer *> *queue=[NSMutableArray arrayWithObject:icon.layer];
    for(NSUInteger i=0;i<queue.count && i<96;i++) {
        CALayer *layer=queue[i];
        for(NSString *key in layer.animationKeys){++animations;if(detail && keys.count<12)[keys addObject:key];}
        if(layer.sublayers)[queue addObjectsFromArray:layer.sublayers];
    }
    for(UIView *view in WXGViews(icon,48)) {
        if([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).isAnimating)++images;
        if(detail && classes.count<16)[classes addObject:[NSString stringWithFormat:@"%@%@",NSStringFromClass(view.class),view.hidden?@"(hidden)":@""]];
    }
    NSMutableDictionary *ivars=[NSMutableDictionary dictionaryWithDictionary:WXGInputScalarIvars(icon,YES)];
    [ivars addEntriesFromDictionary:WXGInputScalarIvars(button,YES)];
    NSMutableDictionary *out=[@{@"animations":@(animations),@"animatingImages":@(images),@"selected":@(button.selected),@"ivars":ivars,
                                @"inWindow":@(icon.window!=nil)} mutableCopy];
    if(detail){out[@"animationKeys"]=keys;out[@"views"]=classes;out[@"allIvars"]=WXGInputScalarIvars(icon,NO);}
    return out;
}
// What differs from the reference now: signal name -> its current value.
static NSDictionary<NSString *,id> *WXGInputDictationChanges(NSDictionary *now,NSDictionary *idle) {
    if(!now.count || !idle.count)return @{};
    NSMutableDictionary *changes=[NSMutableDictionary dictionary];
    if([now[@"animations"] unsignedIntegerValue]>[idle[@"animations"] unsignedIntegerValue])changes[@"animations"]=now[@"animations"];
    if([now[@"animatingImages"] unsignedIntegerValue]>[idle[@"animatingImages"] unsignedIntegerValue])changes[@"animatingImages"]=now[@"animatingImages"];
    if([now[@"selected"] boolValue] && ![idle[@"selected"] boolValue])changes[@"selected"]=@YES;
    NSDictionary *a=now[@"ivars"],*b=idle[@"ivars"];
    for(NSString *key in a)if(b[key] && ![a[key] isEqual:b[key]])changes[key]=a[key];
    return changes;
}
// Once listening was read: still listening while any of the signals that
// showed it still shows it (an animation above the reference count, the
// selected state, a variable still at its listening value; a variable that
// moves on to a third value, or a counter, does not keep it on).
static BOOL WXGInputDictationStillOn(NSDictionary *now,NSDictionary *idle,NSDictionary *on) {
    if(!now.count || !on.count)return NO;
    NSDictionary *ivars=now[@"ivars"];
    for(NSString *key in on) {
        if([key isEqual:@"animations"] || [key isEqual:@"animatingImages"]){if([now[key] unsignedIntegerValue]>[idle[key] unsignedIntegerValue])return YES;}
        else if([key isEqual:@"selected"]){if([now[@"selected"] boolValue])return YES;}
        else if([ivars[key] isEqual:on[key]])return YES;
    }
    return NO;
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
@property(nonatomic) CGRect lastGrowFrame,lastRecordFrame,lastEmojiFrame;
@property(nonatomic) BOOL lastVoiceMode;
@property(nonatomic) BOOL lastEditing,lastHasText,lastEditorVisible;
@property(nonatomic) NSUInteger lastPanelChildCount,lastGrowChildCount;
@property(nonatomic) WXGInputAction rightAction;
@property(nonatomic) CFTimeInterval lastBindingScan,lastPaintScan;
@property(nonatomic,copy) NSString *status;
// FIX87: the emoji button's state (smiley / keyboard), learned from its shape.
@property(nonatomic,strong) UIImage *emojiNativeImage;
@property(nonatomic,strong) NSData *emojiNativePrint;
@property(nonatomic) CFTimeInterval emojiPrintSince,restingSince;
@property(nonatomic) BOOL emojiPanel;
@property(nonatomic) double emojiDistance;
// FIX87: voice-to-text started from the plugin's mic.
@property(nonatomic) BOOL dictationSession,dictationReadable,dictationOn;
@property(nonatomic,weak) UIView *dictationIcon;
@property(nonatomic,weak) UIControl *dictationControl;
@property(nonatomic) CFTimeInterval dictationStartAt,dictationOnSince,dictationOffSince,dictationResignAt,dictationStopAt;
@property(nonatomic,copy) NSString *dictationText,*dictationEndReason;
@property(nonatomic,strong) NSDictionary *dictationIdle,*dictationLast,*dictationOnValues,*dictationChanges;
@property(nonatomic,strong) NSTimer *dictationTimer;
@property(nonatomic,strong) UILabel *dictationHint;
@property(nonatomic) NSUInteger dictationSessions,dictationReadableSessions;
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
        plus.role=@"attachment";[plus setImage:WXGInputSymbol(@"plus") title:nil count:nil];
        plus.accessibilityLabel=@"微信附件菜单";
        pill.role=@"input";pill.materialOnly=YES;pill.isAccessibilityElement=NO;pill.pressFixed=YES;   // FIX87
        mic.role=@"dictation";mic.plain=YES;mic.pressProxy=pill;
        emoji.role=@"emoji";emoji.plain=YES;emoji.pressProxy=pill;emoji.accessibilityLabel=@"微信表情";
        _surfaces=@[plus,pill,mic,emoji];
    }return self;
}
- (UIView *)viewValue:(NSString *)key on:(id)object {
    id v=WXGRead(object,key);return [v isKindOfClass:UIView.class]?v:nil;
}
- (UIControl *)controlValue:(NSString *)key on:(id)object {
    id v=WXGRead(object,key);return [v isKindOfClass:UIControl.class]?v:nil;
}
- (void)bindOptionalActions {
    _lastBindingScan=CACurrentMediaTime();_dictation=nil;UIControl *button=nil;
    for(UIView *v in WXGViews(_grow,90)) {
        if([NSStringFromClass(v.class) isEqual:@"MMGrowDictationIconView"]){_dictation=v;break;}
    }
    for(UIView *v in WXGViews(_dictation,24))
        if([v isKindOfClass:UIControl.class] && [WXGActionNames((id)v) containsObject:@"iconClicked"]){button=(id)v;break;}
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
    _lastGrowFrame=_lastRecordFrame=_lastEmojiFrame=CGRectNull;
    [self bindOptionalActions];
    _surfaces[0].original=attachment;
    for(WXGSurface *s in _surfaces) {
        s.glass.sourceView=vc.view;s.glass.backdropExclusions=@[tool];s.active=YES;s.hidden=NO;[s applyConfig];
    }
    _suspended=NO;_installed=YES;_status=@"两端输入：未编辑切换语音，编辑空框听写，有文字发送；保留原生长按录音";
    [self clearPaint];[self layout];return YES;
}
- (void)clearPaint {
    _lastPaintScan=CACurrentMediaTime();UIView *background=[self viewValue:@"_toolView" on:_tool];
    NSMutableArray *protected=[NSMutableArray arrayWithObjects:_grow,_editor,nil];
    if(_recordButton)[protected addObject:_recordButton];
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
    // Only suppress a native action when the replacement has a real target.
    if(WXGCanForward(_dictationButton))[_states hide:_dictation];
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
        CGFloat emojiDiameter=MIN(28,m.inputButton*.72);
        CGRect emojiRect=CGRectMake(g.mic.x-emojiDiameter-5*m.scale,g.mic.y+g.mic.h*.5-emojiDiameter*.5,emojiDiameter,emojiDiameter);
        // FIX115 J: a single line is always a whole capsule (a taller one than
        // TEST9's too); more lines keep that radius.
        CGFloat base=g.mic.h/.9;
        pill.maximumCornerRadius=MIN(g.pill.h*.5,MAX(24*m.scale,base*.5));
        [pill placeMaterial:[w convertRect:WXGCGRect(g.pill) toView:_panel] inParent:_panel];
        [pill observeTouchesInView:_tool?:_panel];   // FIX70: the text view and the buttons take the touches
        // The logs show MMGrowTextView reassigning its child to x=6,width=w-9
        // after our old editor.frame write. Keep native TextKit/caret ownership
        // and size only the host, with the action columns outside its bounds.
        CGFloat firstAction=hasEmoji?CGRectGetMinX(emojiRect):g.mic.x;
        // Action spacing must not feed back from TextKit's changing scroll inset.
        CGFloat gap=6*m.scale;
        // FIX115 J: the text starts further in when the capsule is taller than
        // TEST9's (its round end is wider), so it keeps the same distance to it.
        // (按住说话 keeps the whole capsule: its title is centred in it.)
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
        [mic placeMaterial:[w convertRect:WXGCGRect(g.mic) toView:_panel] inParent:_panel];
        _rightAction=WXGInputRightAction(editor.isFirstResponder,holdingVoice,editor.text.length>0,
            _voiceButton.window==w && WXGCanForward(_voiceButton),_dictationButton.window==w && WXGCanForward(_dictationButton),
            _sendButton.window==w && WXGCanForward(_sendButton));
        // FIX87: while WeChat is seen listening, the mic stays its stop button
        // even once text has come in (it turned into send at the first word).
        // Only while WeChat's own state can be read: otherwise the plugin
        // could hold a stop button for a dictation that has already ended.
        [self updateDictation];
        UIControl *stopControl=_dictationControl?:_dictationButton;
        BOOL holdStop=_dictationSession && _dictationReadable && _dictationOn && !_dictationStopAt && stopControl.window==w && WXGCanForward(stopControl);
        if(holdStop)_rightAction=WXGInputActionDictation;
        BOOL sending=_rightAction==WXGInputActionSend,dictating=_rightAction==WXGInputActionDictation,keyboard=_rightAction==WXGInputActionKeyboard;
        BOOL listening=_dictationSession && !_dictationStopAt && dictating;   // the listening look
        mic.original=sending?_sendButton:dictating?(holdStop?stopControl:_dictationButton):_rightAction!=WXGInputActionUnavailable?_voiceButton:nil;
        __weak WXGInputAdapter *weakSelf=self;
        mic.perform=dictating?^{[weakSelf dictationTapped];}:nil;
        mic.enabled=WXGCanForward(mic.original);plus.original=_attachment;
        WXGInputSetIcon(plus,WXGInputIcon(@"plus",_attachment),_attachment);   // FIX113
        mic.hidden=!mic.enabled;plus.enabled=WXGCanForward(_attachment);plus.hidden=!plus.enabled;pill.hidden=NO;
        for(WXGSurface *surface in _surfaces)surface.active=!surface.hidden;
        NSString *role=sending?@"send":listening?@"dictating":dictating?@"dictation":keyboard?@"keyboardMode":@"voiceMode";
        if(![mic.role isEqual:role]) {
            mic.role=role;
            mic.accessibilityLabel=sending?@"微信发送消息":listening?@"结束语音转文字":dictating?@"微信语音转文字":keyboard?@"切换到文字输入":@"切换到按住说话";
        }
        // FIX113: the set's symbol, or WeChat's own artwork of that control.
        WXGInputSetIcon(mic,WXGInputIcon(sending?@"arrow.up.circle.fill":listening?@"waveform":dictating?@"mic":keyboard?@"keyboard":@"waveform",mic.original),mic.original);
        [self showListening:listening mic:mic pill:pill editor:editor actionsFrom:firstAction];
        if(mic.enabled && WXGCanForward(_sendButton))[_states hide:_sendButton];else [_states restoreView:_sendButton];
        // Do not resize/reposition the native button: its internal layout runs
        // again on every keystroke. A plain proxy uses the original action and
        // current artwork, on the same fixed bottom baseline as the mic.
        WXGSurface *emoji=_surfaces[3];emoji.original=hasEmoji?_emojiButton:nil;
        emoji.hidden=!hasEmoji;emoji.active=hasEmoji;emoji.enabled=hasEmoji;
        if(hasEmoji) {
            // FIX87: Apple's symbol, or the keyboard while WeChat's expression
            // panel is up (as WeChat's own button does). FIX113: Face ID in
            // place of the smiley; or WeChat's own artwork (its smiley /
            // keyboard as it shows them) when the set is switched off.
            [self updateEmojiState];
            UIImage *face=WXGInputSymbol(@"faceid")?:WXGInputSymbol(@"face.smiling.fill");
            UIImage *own=WXGInputSystemIcons()?nil:WXGInputNativeArtwork(_emojiButton);
            WXGInputSetIcon(emoji,own?:(_emojiPanel?WXGInputSymbol(@"keyboard"):face),_emojiButton);
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
        // A new image object of the same shape is not a change.
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
// FIX87: the plugin's mic in its voice-to-text role. A tap starts a session
// (WeChat's icon state just before it is the reference) or asks to stop one,
// and is passed on to WeChat's own button as before.
- (void)dictationTapped {
    CFTimeInterval now=CACurrentMediaTime();
    UIControl *button=_dictationSession?(_dictationControl?:_dictationButton):_dictationButton;
    if(!WXGCanForward(button))return;
    if(_dictationSession) {
        // Readable: the look goes now, the session when WeChat shows it
        // stopped (or the look comes back if it did not stop).
        if(_dictationReadable)_dictationStopAt=now;else [self endDictation:@"再点一次"];
    }else {
        _dictationIdle=WXGInputDictationSignals(_dictation,_dictationButton,NO);
        _dictationIcon=_dictation;_dictationControl=_dictationButton;
        _dictationSession=YES;_dictationReadable=_dictationOn=NO;_dictationOnValues=_dictationChanges=_dictationLast=nil;
        _dictationOnSince=_dictationOffSince=_dictationResignAt=_dictationStopAt=0;
        _dictationStartAt=now;_dictationText=_editor.text?:@"";_dictationEndReason=nil;++_dictationSessions;
        [_dictationTimer invalidate];
        __weak WXGInputAdapter *weakSelf=self;
        _dictationTimer=[NSTimer timerWithTimeInterval:.3 repeats:YES block:^(__unused NSTimer *timer){[weakSelf dictationTick];}];
        [NSRunLoop.mainRunLoop addTimer:_dictationTimer forMode:NSRunLoopCommonModes];
        WXGLog(@"语音转文字：开始");
    }
    UIControlEvents events=(button.allControlEvents & UIControlEventTouchUpInside)?UIControlEventTouchUpInside:UIControlEventPrimaryActionTriggered;
    [WXGIntegrationHost.shared recordForward:@{@"role":@"dictation",@"targetControlClass":NSStringFromClass(button.class),@"selectors":WXGActionNames(button),@"event":@(events),@"session":@(_dictationSession)}];
    [button sendActionsForControlEvents:events];
    [WXGIntegrationHost.shared layoutInput];
}
// The end rules run here too, so a session ends even while the input row is
// not being laid out; the look goes through the host's gated input layout.
- (void)dictationTick {
    if(!_dictationSession){[_dictationTimer invalidate];_dictationTimer=nil;return;}
    [self updateDictation];
    if(_dictationSession)[WXGIntegrationHost.shared layoutInput];
}
- (void)endDictation:(NSString *)reason {
    if(!_dictationSession)return;
    _dictationSession=NO;_dictationOn=NO;_dictationStopAt=0;_dictationEndReason=reason;
    [_dictationTimer invalidate];_dictationTimer=nil;
    // The look goes at once; the mic's icon follows at the next layout.
    WXGSurface *mic=_surfaces.count>2?_surfaces[2]:nil;
    mic.iconTint=nil;[mic.iconView.layer removeAnimationForKey:@"wxg.dictationPulse"];_dictationHint.hidden=YES;
    WXGLog(@"语音转文字：结束（%@，微信状态%@）",reason,_dictationReadable?@"读得到":@"读不到");
    [WXGIntegrationHost.shared schedule];
}
// Whether WeChat listens: the signals that differ from the reference for a
// whole second make the state readable; from then on it is listening while
// those signals still show it, and the session ends a second after they
// stop. Unreadable: the look stays until text comes in (WeChat's own text is
// then the feedback, and the mic is send again as before), the field loses
// the keyboard, a second tap, or 12 seconds.
- (void)updateDictation {
    if(!_dictationSession)return;
    CFTimeInterval now=CACurrentMediaTime();
    UIView *icon=_dictationIcon;
    NSDictionary *signals=WXGInputDictationSignals(icon,_dictationControl,NO);
    NSDictionary *changes=WXGInputDictationChanges(signals,_dictationIdle);
    _dictationLast=signals;if(changes.count)_dictationChanges=changes;
    BOOL on;
    if(_dictationReadable)on=WXGInputDictationStillOn(signals,_dictationIdle,_dictationOnValues);
    else {
        on=changes.count>0;
        if(!on)_dictationOnSince=0;
        else {
            if(!_dictationOnSince)_dictationOnSince=now;
            if(now-_dictationOnSince>=1.) {
                _dictationReadable=YES;_dictationOnValues=changes;++_dictationReadableSessions;
                WXGLog(@"语音转文字：读得到微信的状态（%@）",[changes.allKeys componentsJoinedByString:@"、"]);
            }
        }
    }
    _dictationOn=on;
    if(on)_dictationOffSince=0;else if(!_dictationOffSince)_dictationOffSince=now;
    if(_dictationStopAt && _dictationReadable && on && now-_dictationStopAt>1.5)_dictationStopAt=0;   // the stop did not take
    UITextView *editor=_editor;
    if(editor.isFirstResponder)_dictationResignAt=0;else if(!_dictationResignAt)_dictationResignAt=now;
    BOOL textArrived=editor && ![editor.text?:@"" isEqualToString:_dictationText?:@""];
    NSString *end=nil;
    if(!editor)end=@"输入栏不在了";
    else if(_dictationResignAt && now-_dictationResignAt>.5)end=@"输入框收起了键盘";
    else if(_dictationReadable && _dictationOffSince && now-_dictationOffSince>1.)end=_dictationStopAt?@"再点一次":@"微信已停止";
    else if(!_dictationReadable && textArrived && now-_dictationStartAt>1.5)end=@"出字了（读不到微信状态）";
    else if(!_dictationReadable && !icon.window && now-_dictationStartAt>1.)end=@"听写图标不在了";
    else if(!_dictationReadable && now-_dictationStartAt>12)end=@"12 秒还读不到微信状态";
    else if(now-_dictationStartAt>90)end=@"超过 90 秒";
    if(end)[self endDictation:end];
}
// FIX87: the listening look: the mic becomes a red, gently pulsing waveform;
// while the field is still empty, "正在听写…" where the text will appear.
- (void)showListening:(BOOL)listening mic:(WXGSurface *)mic pill:(WXGSurface *)pill editor:(UITextView *)editor actionsFrom:(CGFloat)firstAction {
    mic.iconTint=listening?UIColor.systemRedColor:nil;
    CALayer *icon=mic.iconView.layer;
    BOOL pulse=listening && !UIAccessibilityIsReduceMotionEnabled();
    if(pulse && ![icon animationForKey:@"wxg.dictationPulse"]) {
        CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue=@1;animation.toValue=@.35;animation.duration=.7;animation.autoreverses=YES;animation.repeatCount=HUGE_VALF;
        animation.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        animation.removedOnCompletion=NO;
        [icon addAnimation:animation forKey:@"wxg.dictationPulse"];
    }else if(!pulse)[icon removeAnimationForKey:@"wxg.dictationPulse"];
    BOOL hint=listening && !editor.text.length && !editor.markedTextRange && pill.window;
    if(!hint){_dictationHint.hidden=YES;return;}
    if(!_dictationHint) {
        _dictationHint=[UILabel new];_dictationHint.userInteractionEnabled=NO;_dictationHint.text=@"正在听写…";
        _dictationHint.isAccessibilityElement=NO;
    }
    if(_dictationHint.superview!=pill)[pill addSubview:_dictationHint];
    UIFont *font=editor.font?:[UIFont systemFontOfSize:17];
    _dictationHint.font=font;_dictationHint.textColor=UIColor.secondaryLabelColor;
    CGFloat line=ceil(font.lineHeight);
    // Where the first character goes: the caret at the start (it carries the
    // text view's scroll offset and insets).
    UITextPosition *start=editor.beginningOfDocument;
    CGRect caret=start?[editor caretRectForPosition:start]:CGRectNull;
    CGRect at=CGRectIsNull(caret) || CGRectIsInfinite(caret) || !isfinite(caret.origin.x) || !isfinite(caret.origin.y)?CGRectNull:[editor convertRect:caret toView:pill];
    CGFloat left,top;
    if(!CGRectIsNull(at)){left=CGRectGetMinX(at)+1;top=CGRectGetMidY(at)-line*.5;}
    else {
        CGRect text=[editor convertRect:editor.bounds toView:pill];
        left=CGRectGetMinX(text)+editor.textContainerInset.left+editor.textContainer.lineFragmentPadding;
        top=CGRectGetMinY(text)+editor.textContainerInset.top;
    }
    CGFloat right=[pill convertPoint:CGPointMake(firstAction,0) fromView:nil].x-4;   // firstAction: window coordinates
    _dictationHint.frame=CGRectMake(left,top,MAX(0,right-left),line);
    _dictationHint.hidden=NO;
}
- (void)dealloc {[_dictationTimer invalidate];}
- (void)reapplyPaint {
    if(_usingNativeLayout){[_nativeAdapter reapplyPaint];return;}
    if(_installed && _tool.window)[_states reapply];
}
- (void)setSuspended:(BOOL)suspended {
    if(_usingNativeLayout){[_nativeAdapter setSuspended:suspended];return;}
    if(_suspended==suspended)return;_suspended=suspended;
    if(suspended)[self endDictation:@"离开聊天"];   // FIX87
    for(WXGSurface *surface in _surfaces)surface.active=!suspended && _installed;
    if(!suspended){[_states reapply];[self layout];}
}
- (void)restore {
    if(_usingNativeLayout){[_nativeAdapter restore];_usingNativeLayout=NO;}
    if(!_installed)return;
    _installed=NO;
    for(WXGSurface *s in _surfaces){s.active=NO;s.original=nil;s.glass.backdropExclusions=@[];s.hidden=YES;[s removeFromSuperview];}
    // FIX87
    [self endDictation:@"输入栏还原"];_surfaces[2].perform=nil;_surfaces[2].iconTint=nil;
    [_surfaces[2].iconView.layer removeAnimationForKey:@"wxg.dictationPulse"];[_dictationHint removeFromSuperview];_dictationHint=nil;
    _emojiNativeImage=nil;_emojiNativePrint=nil;_emojiPanel=NO;_restingSince=0;_dictationIcon=nil;_dictationControl=nil;
    WXGReleaseInputHost(_grow);WXGReleaseInputTool(_tool,self);[_states restore];_states=nil;
    [_grow setNeedsLayout];[_panel setNeedsLayout];[_tool setNeedsLayout];
    _tool=_panel=_grow=_dictation=nil;_editor=nil;_attachment=_dictationButton=_sendButton=_voiceButton=_emojiButton=_recordButton=nil;_controller=nil;
    _lastGrowFrame=_lastRecordFrame=_lastEmojiFrame=CGRectNull;_rightAction=WXGInputActionUnavailable;WXGInvalidateSharedBackdrop();
}
- (NSDictionary *)evidence {
    if(_usingNativeLayout)return _nativeAdapter.evidence;
    NSMutableArray *surfaces=[NSMutableArray array];for(WXGSurface *s in _surfaces)if(s.active)[surfaces addObject:s.evidence];
    CGRect r=WXGWindowRect(_editor,_window);
    return @{@"installed":@(_installed),@"status":_status?:@"等待聊天页",@"surfaces":surfaces,
             @"editorClass":_editor?NSStringFromClass(_editor.class):@"none",@"originalEditorRetained":@(_editor!=nil),
             @"firstResponder":@(_editor.isFirstResponder),@"editorRect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],
             @"nativeGrowHeight":@(_nativeGrowHeight),@"attachmentActions":WXGActionNames(_attachment),
             @"voiceModeActions":WXGActionNames(_voiceButton),@"rightAction":@(_rightAction),@"voiceRecordingVisible":@(_lastVoiceMode),
             @"recordButtonClass":_recordButton?NSStringFromClass(_recordButton.class):@"none",@"nativeRecordGesturesRetained":@YES,
             @"dictationActions":WXGActionNames(_dictationButton),@"paintAndLayout":_states.evidence?:@[],
             // FIX87
             @"emoji":@{@"panel":@(_emojiPanel),@"distance":@(round(_emojiDistance*1000)/1000),@"faceLearned":@(WXGEmojiFacePrint!=nil),
                        @"nativeSelected":@(_emojiButton.selected),@"nativeImage":_emojiNativeImage?[NSString stringWithFormat:@"%p %.0fx%.0f",_emojiNativeImage,_emojiNativeImage.size.width,_emojiNativeImage.size.height]:@"none"},
             @"dictation":@{@"session":@(_dictationSession),@"sessions":@(_dictationSessions),@"readable":@(_dictationReadable),@"readableSessions":@(_dictationReadableSessions),
                            @"on":@(_dictationOn),@"stopAsked":@(_dictationStopAt>0),@"lastEnd":_dictationEndReason?:@"none",@"onValues":_dictationOnValues?:@{},
                            @"changes":_dictationChanges?:@{},@"idle":_dictationIdle?:@{},@"last":_dictationLast?:@{},
                            @"icon":WXGInputDictationSignals(_dictation,_dictationButton,YES)}};
}
@end
