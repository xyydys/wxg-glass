#import "WXGIntegration.h"
#import "WXGIconAlignment.h"
#import "WXGMonochrome.h"
#import "WXGInputWidthPolicy.h"
#import <pthread.h>

// An opt-in guard on MMGrowTextView ONLY. No UIView/CALayer global setters,
// no child UITextView frame or textContainer writes, no forced layout in setters.
static char WXGInputWidthKey;
static NSUInteger WXGInputLayoutDepth;
void WXGBeginNativeInputLayout(void) {++WXGInputLayoutDepth;}
void WXGEndNativeInputLayout(void) {if(WXGInputLayoutDepth)--WXGInputLayoutDepth;}
BOOL WXGNativeInputLayoutInProgress(void) {return WXGInputLayoutDepth>0;}
@interface WXGInputWidthBinding : NSObject
@property(nonatomic,weak) UIView *parent;
@property(nonatomic,weak) WXGViewState *state;
@property(nonatomic) CGRect target;
@property(nonatomic) BOOL writing;
@end
@implementation WXGInputWidthBinding
@end
static WXGRect WXGWidthRect(CGRect r) {return (WXGRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static BOOL WXGWidthBindingApplies(UIView *view,WXGInputWidthBinding *binding) {
    return binding && binding.state && !binding.writing && view.superview==binding.parent &&
        view.window && CGAffineTransformIsIdentity(view.transform) && WXGPluginEnabled() && WXGPreferences.shared.input;
}
// FIX115 A: overrides are installed and listed here (see WXGIntegration.h; B: they call what was there when installed).
static NSMutableArray<NSDictionary *> *WXGOverrides;
IMP WXGOwnImplementation(Class cls,SEL selector) {
    if(!cls || !selector)return NULL;
    unsigned int count=0;Method *methods=class_copyMethodList(cls,&count);IMP own=NULL;
    for(unsigned int i=0;i<count;i++)if(method_getName(methods[i])==selector){own=method_getImplementation(methods[i]);break;}
    free(methods);
    return own;
}
void WXGInstallOverride(Class cls,SEL selector,IMP replacement,const char *types) {
    if(!cls || !selector || !replacement)return;
    BOOL added=class_addMethod(cls,selector,replacement,types);
    if(!added)class_replaceMethod(cls,selector,replacement,types);
    if(!WXGOverrides)WXGOverrides=[NSMutableArray array];
    if(WXGOverrides.count<160)[WXGOverrides addObject:@{@"class":@(class_getName(cls)),@"selector":NSStringFromSelector(selector),
        @"inherited":@(added),@"imp":[NSValue valueWithPointer:(const void *)replacement]}];
}
// Per override: whether the class still calls ours first (NO: something
// replaced it on that class later, which then calls ours or not, its choice).
NSArray<NSDictionary *> *WXGOverrideEvidence(void) {
    NSMutableArray *list=[NSMutableArray array];
    for(NSDictionary *o in WXGOverrides) {
        Class cls=objc_getClass([o[@"class"] UTF8String]);SEL selector=NSSelectorFromString(o[@"selector"]);
        IMP now=cls?WXGOwnImplementation(cls,selector):NULL;
        [list addObject:@{@"method":[NSString stringWithFormat:@"%@.%@",o[@"class"],o[@"selector"]],
            @"how":[o[@"inherited"] boolValue]?@"继承的方法（调用时向父类取当前实现）":@"类自己的方法（原地替换）",
            @"oursOnTop":@(now==[o[@"imp"] pointerValue])}];
    }
    return list;
}
static void WXGInstallInputWidthHooks(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"MMGrowTextView");if(!cls)return;
        Class superclass=class_getSuperclass(cls);
        for(NSString *name in @[@"setFrame:",@"setBounds:"]) {
            SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(cls,selector);if(!method)continue;
            NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if(signature.numberOfArguments!=3 || strcmp(signature.methodReturnType,@encode(void)) ||
               strcmp([signature getArgumentTypeAtIndex:2],@encode(CGRect)))continue;
            IMP own=WXGCapturedImplementation(cls,selector);BOOL frame=[name isEqual:@"setFrame:"];
            IMP replacement=imp_implementationWithBlock(^(UIView *view,CGRect incoming){
                IMP original=WXGThrough(own,superclass,selector);
                WXGInputWidthBinding *binding=objc_getAssociatedObject(view,&WXGInputWidthKey);
                if(!WXGWidthBindingApplies(view,binding)){((void(*)(id,SEL,CGRect))original)(view,selector,incoming);return;}
                CGRect accepted=incoming;
                if(frame) {
                    WXGRect saved=WXGInputRememberHorizontal(WXGWidthRect(binding.state.originalFrame),WXGWidthRect(incoming),WXGWidthRect(binding.target));
                    [binding.state updateNativeFrame:WXGCGRect(saved)];
                    accepted=WXGCGRect(WXGInputAcceptHorizontal(WXGWidthRect(incoming),WXGWidthRect(binding.target)));
                }else {
                    CGRect saved=binding.state.originalFrame;
                    if(fabs(incoming.size.width-binding.target.size.width)>.01)saved.size.width=incoming.size.width;
                    saved.size.height=incoming.size.height;[binding.state updateNativeFrame:saved];
                    accepted.size.width=binding.target.size.width;
                }
                binding.writing=YES;
                @try {((void(*)(id,SEL,CGRect))original)(view,selector,accepted);}
                @finally {binding.writing=NO;}
            });
            WXGInstallOverride(cls,selector,replacement,method_getTypeEncoding(method));
        }
        // WeChat also lays out this one host via bounds + center. A frame-only
        // guard lets that path move the narrowed editor back to its native x.
        SEL selector=@selector(setCenter:);Method method=class_getInstanceMethod(cls,selector);
        if(method) {
            IMP own=WXGCapturedImplementation(cls,selector);
            IMP replacement=imp_implementationWithBlock(^(UIView *view,CGPoint incoming){
                IMP original=WXGThrough(own,superclass,selector);
                WXGInputWidthBinding *binding=objc_getAssociatedObject(view,&WXGInputWidthKey);
                if(!WXGWidthBindingApplies(view,binding)){((void(*)(id,SEL,CGPoint))original)(view,selector,incoming);return;}
                CGPoint accepted=incoming;
                accepted.x=WXGInputAcceptedCenterX(WXGWidthRect(binding.target),view.bounds.size.width);
                if(fabs(incoming.x-accepted.x)>.01) {
                    CGRect saved=binding.state.originalFrame;
                    saved.origin.x=incoming.x-saved.size.width*.5;[binding.state updateNativeFrame:saved];
                }
                binding.writing=YES;
                @try {((void(*)(id,SEL,CGPoint))original)(view,selector,accepted);}
                @finally {binding.writing=NO;}
            });
            WXGInstallOverride(cls,selector,replacement,method_getTypeEncoding(method));
        }
    });
}
void WXGSetInputHostFrame(UIView *view,CGRect frame,WXGViewState *state) {
    if(!view || !view.superview || !state)return;
    Class grow=NSClassFromString(@"MMGrowTextView");
    if(!grow || ![view isKindOfClass:grow]){if(!CGRectEqualToRect(view.frame,frame))view.frame=frame;return;}
    WXGInstallInputWidthHooks();
    WXGInputWidthBinding *binding=objc_getAssociatedObject(view,&WXGInputWidthKey);
    if(!binding){binding=[WXGInputWidthBinding new];objc_setAssociatedObject(view,&WXGInputWidthKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    binding.parent=view.superview;binding.state=state;binding.target=frame;binding.writing=YES;
    @try {if(!CGRectEqualToRect(view.frame,frame))view.frame=frame;}
    @finally {binding.writing=NO;}
}
void WXGReleaseInputHost(UIView *view) {
    if(view)objc_setAssociatedObject(view,&WXGInputWidthKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSMapTable<UIView *,id> *WXGInputOwners;
void WXGClaimInputTool(UIView *tool,id owner) {
    if(!tool || !owner)return;
    if(!WXGInputOwners)WXGInputOwners=[NSMapTable weakToWeakObjectsMapTable];
    id previous=[WXGInputOwners objectForKey:tool];
    if(previous && previous!=owner){[previous restore];[tool setNeedsLayout];[tool layoutIfNeeded];}
    [WXGInputOwners setObject:owner forKey:tool];
}
void WXGReleaseInputTool(UIView *tool,id owner) {
    if(tool && [WXGInputOwners objectForKey:tool]==owner)[WXGInputOwners removeObjectForKey:tool];
}
id WXGRead(id object,NSString *key) {
    if(!object || !key.length) return nil;
    /* Read object ivars first; never reinterpret scalars or call arbitrary
       private methods using an assumed Objective-C ABI. */
    for(Class c=object_getClass(object);c;c=class_getSuperclass(c)) {
        for(NSString *name in @[key,[key hasPrefix:@"_"]?[key substringFromIndex:1]:[@"_" stringByAppendingString:key]]) {
            Ivar iv=class_getInstanceVariable(c,name.UTF8String);
            if(iv && ivar_getTypeEncoding(iv)[0]=='@') return object_getIvar(object,iv);
        }
    }
    @try { return [object valueForKey:key]; } @catch(__unused NSException *e) { return nil; }
}
// FIX60: NSStringFromClass on every visited view cost 27-53 ms on the first
// scan of a tab page (FIX59 diagnostics, treeScanMS): the first request for a
// Swift class's name demangles it. Our own views are recognised by class.
BOOL WXGIsPluginView(UIView *view) {
    static Class classes[24];static NSUInteger count;static dispatch_once_t once;
    dispatch_once(&once,^{
        for(NSString *name in @[@"WXGGlassView",@"WXGSurface",@"WXGDemoBar",@"WXGDockSearch",@"WXGOverlay",@"WXGRimView",@"WXGMetalSurface",
                                @"WXGSyncBackdropView",@"WXGFloatingSearch",@"WXGSettingsCard",@"WXGSettingsRow",@"WXGSettingsScrollView",@"WXGEdgeBlurView",@"WXGEdgeCoverView",@"WXGEdgePlateView",
                                @"WXGBubbleGlass",@"WXGPerfHUDView",@"WXGSegmentBar",@"WXGHomePlusTriggerView",@"WXGMenuInkOverlayView",@"WXGMenuMorphView",@"WXGVectorIconView"]) {
            Class cls=NSClassFromString(name);if(cls && count<24)classes[count++]=cls;
        }
    });
    for(NSUInteger i=0;i<count;i++)if([view isKindOfClass:classes[i]])return YES;
    return NO;
}
NSArray<UIView *> *WXGViews(UIView *root,NSUInteger limit) {
    if(!root) return @[];
    NSMutableArray *queue=[NSMutableArray arrayWithObject:root],*out=[NSMutableArray array];
    for(NSUInteger i=0;i<queue.count && out.count<limit;i++) {
        UIView *v=queue[i]; [out addObject:v];
        if([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class] || WXGIsPluginView(v)) continue;
        if(queue.count<limit) [queue addObjectsFromArray:v.subviews];
    } return out;
}
BOOL WXGVisible(UIView *v,UIWindow *window) {
    if(!v || v.window!=window) return NO;
    for(UIView *a=v;a;a=a.superview) if(a.hidden || a.alpha<.01) return NO;
    return CGRectIntersectsRect(WXGWindowRect(v,window),window.bounds);
}
CGRect WXGWindowRect(UIView *v,UIWindow *window) { return v && window?[v convertRect:v.bounds toView:window]:CGRectZero; }
CGRect WXGRectInSource(UIView *view,UIView *source) {
    if(!view || !source)return CGRectNull;
    if(view.window==source.window)return [view convertRect:view.bounds toView:source];
    if(!view.window || !source.window || view.window.screen!=source.window.screen)return CGRectNull;
    CGRect rect=[view convertRect:view.bounds toView:view.window];
    rect=[source.window convertRect:rect fromWindow:view.window];
    return [source convertRect:rect fromView:source.window];
}
CGRect WXGCGRect(WXGRect r) { return CGRectMake(r.x,r.y,r.w,r.h); }
NSDictionary *WXGRenderedInkEvidence(UIView *view) {
    if(!view || view.hidden || !view.window || CGRectIsEmpty(view.bounds))return @{@"available":@NO};
    [view.layer displayIfNeeded];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=view.window.screen.scale;
    format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIImage *roi=[[[UIGraphicsImageRenderer alloc]initWithSize:view.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *c){
        CGContextTranslateCTM(c.CGContext,-view.bounds.origin.x,-view.bounds.origin.y);[view.layer renderInContext:c.CGContext];
    }];
    CGImageRef cg=roi.CGImage;CGImageAlphaInfo info=CGImageGetAlphaInfo(cg);
    BOOL first=info==kCGImageAlphaPremultipliedFirst || info==kCGImageAlphaFirst,last=info==kCGImageAlphaPremultipliedLast || info==kCGImageAlphaLast;
    if(!cg || CGImageGetBitsPerPixel(cg)!=32 || CGImageGetBitsPerComponent(cg)!=8 || !(first || last))return @{@"available":@NO};
    size_t w=CGImageGetWidth(cg),h=CGImageGetHeight(cg),stride=CGImageGetBytesPerRow(cg),ai=first?0:3;
    if((CGImageGetBitmapInfo(cg)&kCGBitmapByteOrderMask)==kCGBitmapByteOrder32Little)ai=3-ai;
    CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(cg));if(!data)return @{@"available":@NO};
    const uint8_t *p=CFDataGetBytePtr(data);size_t x0=w,y0=h,x1=0,y1=0;BOOL found=NO;
    for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++)if(p[y*stride+x*4+ai]>=16) {
        x0=MIN(x0,x);y0=MIN(y0,y);x1=MAX(x1,x);y1=MAX(y1,y);found=YES;
    }
    CFRelease(data);if(!found)return @{@"available":@NO};
    CGFloat scale=format.scale;CGRect local=CGRectMake(view.bounds.origin.x+x0/scale,view.bounds.origin.y+y0/scale,(x1-x0+1)/scale,(y1-y0+1)/scale);
    CGRect window=[view convertRect:local toView:view.window];
    return @{@"available":@YES,@"method":@"UIView_layer_ROI_alpha16_projection",@"threshold":@16,@"scale":@(scale),
        @"bounds_px":@[@(x0),@(y0),@(x1-x0+1),@(y1-y0+1)],@"windowRect":@[@(window.origin.x),@(window.origin.y),@(window.size.width),@(window.size.height)]};
}
NSArray<NSString *> *WXGActionNames(UIControl *control) {
    NSMutableArray *names=[NSMutableArray array];
    for(id target in control.allTargets) {
        for(UIControlEvents event=1;event<=UIControlEventPrimaryActionTriggered;event<<=1)
            if(control.allControlEvents & event)for(NSString *selector in [control actionsForTarget:target forControlEvent:event])
                if(![names containsObject:selector]) [names addObject:selector];
    } return names;
}
BOOL WXGCanForward(UIControl *control) {
    if(!control || !control.enabled) return NO;
    return (control.allControlEvents & (UIControlEventTouchUpInside|UIControlEventPrimaryActionTriggered))!=0;
}
UIImage *WXGButtonImage(UIControl *button) {
    if([button isKindOfClass:UIButton.class]) {
        UIButton *b=(id)button;
        if(b.currentImage) return b.currentImage;
    }
    for(UIView *v in WXGViews(button,32)) {
        if([v isKindOfClass:UIImageView.class] && !v.hidden && v.alpha>.01) {
            UIImageView *iv=(id)v;
            if(iv.image && iv.bounds.size.width>4 && iv.bounds.size.height>4 && iv.bounds.size.width<80)
                return iv.image;
        }
    } return nil;
}
BOOL WXGImageIsMonochrome(UIImage *image) {
    if(!image)return NO;
    static NSMapTable *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSMapTable weakToStrongObjectsMapTable];});
    NSNumber *known=[cache objectForKey:image];if(known)return known.boolValue;
    // One bounded raster per resource, never a screen snapshot or per-frame readback.
    uint8_t pixels[32*32*4]={0};CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(pixels,32,32,8,128,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);if(!ctx)return NO;
    UIGraphicsPushContext(ctx);[image drawInRect:CGRectMake(0,0,32,32)];UIGraphicsPopContext();CGContextRelease(ctx);
    BOOL mono=WXGMonochromeRGBA(pixels,32*32);[cache setObject:@(mono) forKey:image];return mono;
}
UIImage *WXGCropInk(UIImage *image,UIColor *tint) {
    if(!image || image.size.width<=0 || image.size.height<=0) return nil;
    static NSMapTable<UIImage *,NSMutableDictionary<NSString *,UIImage *> *> *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSMapTable weakToStrongObjectsMapTable];});
    NSString *key=[NSString stringWithFormat:@"%@-%ld-%ld",tint,(long)image.renderingMode,(long)UITraitCollection.currentTraitCollection.userInterfaceStyle];
    NSMutableDictionary *variants=[cache objectForKey:image];UIImage *cached=variants[key];if(cached)return cached;
    UIImage *src=image.renderingMode==UIImageRenderingModeAlwaysTemplate?[image imageWithTintColor:tint?:UIColor.labelColor renderingMode:UIImageRenderingModeAlwaysOriginal]:image;
    UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat]; f.scale=MAX(1,MIN(3,image.scale));f.opaque=NO;
    f.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    // SF Symbols may draw optical/baseline ink outside their nominal rect.
    // Rasterize into padding before finding the alpha bounds, so filled send
    // circles do not lose their top/bottom pixels.
    CGFloat padding=image.isSymbolImage?4:0;
    CGSize canvas=CGSizeMake(src.size.width+2*padding,src.size.height+2*padding);
    UIImage *raster=[[[UIGraphicsImageRenderer alloc] initWithSize:canvas format:f] imageWithActions:^(UIGraphicsImageRendererContext *c){
        (void)c;[src drawInRect:CGRectMake(padding,padding,src.size.width,src.size.height)];
    }];
    size_t w=CGImageGetWidth(raster.CGImage),h=CGImageGetHeight(raster.CGImage);
    if(!w || !h || w*h>1024*1024) return src;
    CGImageRef cg=raster.CGImage;CGImageAlphaInfo info=CGImageGetAlphaInfo(cg);
    BOOL first=info==kCGImageAlphaPremultipliedFirst || info==kCGImageAlphaFirst;
    BOOL last=info==kCGImageAlphaPremultipliedLast || info==kCGImageAlphaLast;
    if(CGImageGetBitsPerPixel(cg)!=32 || CGImageGetBitsPerComponent(cg)!=8 || !(first || last))return src;
    size_t ai=first?0:3,stride=CGImageGetBytesPerRow(cg);
    if((CGImageGetBitmapInfo(cg)&kCGBitmapByteOrderMask)==kCGBitmapByteOrder32Little)ai=3-ai;
    CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(cg));if(!data)return src;
    size_t minX=w,minY=h,maxX=0,maxY=0;BOOL found=NO;const uint8_t *p=CFDataGetBytePtr(data);
    // FIX114 A (user: the top-right "+" looked cut at its edges): the faint
    // antialiased edge pixels count as ink too (from 16/255 they were cut
    // off, the glyph's ends lost their soft edge).
    for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++)if(p[y*stride+x*4+ai]>=3) {
        minX=MIN(minX,x);minY=MIN(minY,y);maxX=MAX(maxX,x);maxY=MAX(maxY,y);found=YES;
    }
    CFRelease(data);
    if(!found) return nil;
    /* Crop uses the raster's top-left coordinate system, including oriented
       source images. Bounding-box centre is now the actual glyph centre. */
    CGImageRef cropped=CGImageCreateWithImageInRect(raster.CGImage,CGRectMake(minX,minY,maxX-minX+1,maxY-minY+1));
    UIImage *out=cropped?[UIImage imageWithCGImage:cropped scale:f.scale orientation:UIImageOrientationUp]:src;
    if(cropped)CGImageRelease(cropped);
    if(image.isSymbolImage || image.renderingMode==UIImageRenderingModeAlwaysTemplate)out=[out imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if(out){if(!variants){variants=[NSMutableDictionary dictionary];[cache setObject:variants forKey:image];}variants[key]=out;}return out;
}

@implementation WXGPreferences
+ (instancetype)shared {static WXGPreferences *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];[p adoptBuildDefaults];});return p;}
- (NSArray *)keys {return @[@"enabled",@"nav",@"dock",@"input",@"avatarTitle",@"homeSearch",@"nativeInputTest",@"adaptiveIdle",@"sizeScale",
                            @"dockSearch",@"dockSearchLeading",@"hideTopSearch",@"edgeFade",@"bubbles",@"perfMonitor",@"perfHUD",
                            @"localSearch",@"localPanel",@"localEmoji",@"localSheet",@"localTitle",@"localNavButtons",@"localSearchThemeFirst",@"chatAvatarButton"];}
- (void)loadBuiltIn {
    _enabled=_nav=_dock=_input=YES;_adaptiveIdle=YES;_homeSearch=NO;_avatarTitle=NO;_sizeScale=1;
    _dockSearch=YES;_dockSearchLeading=NO;_hideTopSearch=NO;   // FIX60
    _edgeFade=YES;   // FIX64
    _bubbles=YES;    // FIX82
    _perfMonitor=_perfHUD=NO;   // FIX84
    _localSearch=_localPanel=_localEmoji=_localSheet=YES;   // FIX107
    _localTitle=_localNavButtons=YES;   // FIX108
    _localSearchThemeFirst=NO;_chatAvatarButton=YES;   // FIX109
}
- (void)resetToBuildDefaults {   // FIX115 H
    WXGPreferences *builtIn=[[WXGPreferences alloc] initBuiltIn];NSDictionary *build=WXGBuildDefaultSection(@"integration");
    for(NSString *k in [self keys]) {
        if([@[@"enabled",@"homeSearch",@"perfMonitor",@"perfHUD"] containsObject:k])continue;
        id v=build[k];if(![v isKindOfClass:NSNumber.class] || !isfinite([v doubleValue]))v=[builtIn valueForKey:k];
        if(v)[self setValue:v forKey:k];
    }
    [self save];
}
// FIX114 G: the switches' built-in values only (nothing read or written).
- (instancetype)initBuiltIn {
    if((self=[super init]))[self loadBuiltIn];
    return self;
}
// FIX114 G: as WXGConfig's adoptBuildDefaults: a switch (or 整体大小) still at
// the previous build's default (its value there, else the built-in one)
// moves to this build's; one the person changed stays. Not the main switch,
// 首页搜索 or the frame-rate logs (never part of a build's defaults).
- (void)adoptBuildDefaults {
    NSUserDefaults *suite=[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"];
    NSString *stamp=WXGBuildDefaultsStamp();
    if(!stamp.length || [[suite stringForKey:@"defaultsStamp.integration"] isEqualToString:stamp])return;
    NSDictionary *stored=nil;
    NSDictionary *previous=WXGPreviousBuildDefaultSection(@"integration"),*current=WXGBuildDefaultSection(@"integration");
    NSUInteger moved=0,kept=0;NSString *failure=nil;
    @try {   // FIX114 G (review): inside +shared at launch: never throws out; the stamp written whatever happens
        stored=[suite dictionaryForKey:@"integration.test1"];
        // The previous defaults known (that build had a set); a section it
        // lacked: the built-in switches were its defaults.
        if(stored.count && WXGPreviousBuildDefaultSection(@"config").count) {
            WXGPreferences *builtIn=[[WXGPreferences alloc] initBuiltIn];
            id (^valid)(id)=^id(id v){return [v isKindOfClass:NSNumber.class] && isfinite([v doubleValue])?v:nil;};
            for(NSString *k in [self keys]) {
                if([@[@"enabled",@"homeSearch",@"perfMonitor",@"perfHUD"] containsObject:k])continue;
                // A switch this phone never stored is at its built-in value (init
                // applies a build's switches only to a fresh install).
                id base=[builtIn valueForKey:k],old=valid(stored[k])?(valid(previous[k])?:base):base,now=valid(current[k])?:base;
                if(!now || WXGSameSettingValue(old,now))continue;
                if(WXGSameSettingValue([self valueForKey:k],old)){[self setValue:now forKey:k];++moved;}
                else ++kept;
            }
            if(moved) {
                _homeSearch=NO;if(!isfinite(_sizeScale))_sizeScale=1;_sizeScale=WXGBound(_sizeScale,.85,1.2);
                [suite setObject:[self dictionaryWithValuesForKeys:[self keys]] forKey:@"integration.test1"];
            }
        }
    }@catch(NSException *error) {
        failure=error.reason?:error.name?:@"exception";
    }@finally {
        [suite setObject:stamp forKey:@"defaultsStamp.integration"];
    }
    WXGNoteDefaultsAdoption(@"integration",@{@"stored":@(stored.count>0),@"moved":@(moved),@"kept":@(kept),@"error":failure?:@""});
}
- (instancetype)init {
    if((self=[super init])) {
        [self loadBuiltIn];
        NSDictionary *d=[[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] dictionaryForKey:@"integration.test1"];
        // FIX84: a fresh install starts from this build's switches, if it has
        // any (WXGBuildProfile.h); the main switch and the logs are not among them.
        if(!d) {
            NSDictionary *build=WXGBuildDefaultSection(@"integration");
            for(NSString *k in [self keys])
                if(![@[@"enabled",@"homeSearch",@"perfMonitor",@"perfHUD"] containsObject:k] && [build[k] isKindOfClass:NSNumber.class] && isfinite([build[k] doubleValue]))
                    [self setValue:build[k] forKey:k];
        }
        for(NSString *k in [self keys]) if([d[k] isKindOfClass:NSNumber.class]) [self setValue:d[k] forKey:k];
        _homeSearch=NO;
        if(!isfinite(_sizeScale)) _sizeScale=1;_sizeScale=WXGBound(_sizeScale,.85,1.2);
    }return self;
}
- (void)save {
    _homeSearch=NO;
    _sizeScale=WXGBound(_sizeScale,.85,1.2);
    [[[NSUserDefaults alloc] initWithSuiteName:@"com.runyu.WeChatLiquidGlass"] setObject:[self dictionaryWithValuesForKeys:[self keys]] forKey:@"integration.test1"];
    [NSNotificationCenter.defaultCenter postNotificationName:@"WXGIntegrationChanged" object:nil];
}
@end
// FIX29: an image view whose paint we cleared keeps showing nothing even when
// UIKit redisplays it or WeChat sets its image again (the plus menu is reused
// and re-skinned on every opening, which brought the grey background back).
// While guarded, setImage: stores the native image and shows a transparent
// image of the same size, so intrinsic size and layout stay untouched.
@interface WXGImagePaintGuard : NSObject
@property(nonatomic,strong) UIImage *nativeImage;
@end
@implementation WXGImagePaintGuard
@end
static char WXGImagePaintGuardKey;
static IMP WXGOriginalSetImage;
static UIImage *WXGTransparentImageLike(UIImage *image) {
    if(!image || image.size.width<=0 || image.size.height<=0)return image?[UIImage new]:nil;
    static NSCache<NSString *,UIImage *> *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=24;});
    NSString *key=[NSString stringWithFormat:@"%.2fx%.2f@%.1f",image.size.width,image.size.height,image.scale];
    UIImage *clear=[cache objectForKey:key];
    if(!clear) {
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
        format.scale=image.scale;format.opaque=NO;
        clear=[[[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *context){}];
        if(clear)[cache setObject:clear forKey:key];
    }
    return clear?:image;
}
static void WXGInstallImagePaintGuard(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Method method=class_getInstanceMethod(UIImageView.class,@selector(setImage:));if(!method)return;
        WXGOriginalSetImage=method_getImplementation(method);
        IMP replacement=imp_implementationWithBlock(^(UIImageView *view,UIImage *image){
            WXGImagePaintGuard *guard=objc_getAssociatedObject(view,&WXGImagePaintGuardKey);
            if(guard){guard.nativeImage=image;image=WXGTransparentImageLike(image);}
            ((void(*)(id,SEL,UIImage *))WXGOriginalSetImage)(view,@selector(setImage:),image);
        });
        WXGInstallOverride(UIImageView.class,@selector(setImage:),replacement,method_getTypeEncoding(method));   // UIImageView's own: in place, as before (FIX115 A: listed)
    });
}
static void WXGGuardImagePaint(UIImageView *view) {
    WXGInstallImagePaintGuard();
    if(!WXGOriginalSetImage || objc_getAssociatedObject(view,&WXGImagePaintGuardKey))return;
    WXGImagePaintGuard *guard=[WXGImagePaintGuard new];guard.nativeImage=view.image;
    objc_setAssociatedObject(view,&WXGImagePaintGuardKey,guard,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void(*)(id,SEL,UIImage *))WXGOriginalSetImage)(view,@selector(setImage:),WXGTransparentImageLike(guard.nativeImage));
}
static void WXGReleaseImagePaint(UIImageView *view) {
    WXGImagePaintGuard *guard=objc_getAssociatedObject(view,&WXGImagePaintGuardKey);if(!guard)return;
    objc_setAssociatedObject(view,&WXGImagePaintGuardKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.image=guard.nativeImage;
}
@interface WXGViewState ()
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic) BOOL originallyHidden,opaque,clips;
@property(nonatomic,strong) UIColor *color;
@property(nonatomic) CGFloat borderWidth,cornerRadius;
@property(nonatomic) float shadowOpacity;
@property(nonatomic) BOOL changedAlpha,changedPaint,changedEffect,changedContents,changedMask,changedClips;
// FIX47: when set, the background is painted this colour instead of cleared.
@property(nonatomic,strong) UIColor *paintColor;
@property(nonatomic,strong) CALayer *originalMask,*concealMask;
@property(nonatomic) BOOL changedUnmask;               // FIX115 J
@property(nonatomic) BOOL changedFillGuard;            // FIX115 L
@property(nonatomic,strong) CALayer *unmaskedOriginal;
// FIX115 Q: drawn round (a corner radius and clipping of the plugin's), restorably.
@property(nonatomic) BOOL changedRound,roundMasks;
@property(nonatomic) CGFloat roundRadius,roundOriginalRadius;
@property(nonatomic,copy) NSString *roundCurve;
// FIX115 Q (review): a button's (normal) title colour of the plugin's, restorably.
@property(nonatomic) BOOL changedTitleColor;
@property(nonatomic,strong) UIColor *titleNormal,*titleApplied;
@end
static char WXGUnmaskedOwnKey;   // FIX115 J: WeChat's own mask while unmask: has it off (WXGOwnMask)
/* FIX115 K (user, 13:07: the coloured 完成 still cut to WeChat's rounded box):
   WeChat can set its mask again after the plugin's layout hook (later in the
   same layout), so taking it off there was not enough. While a layer's mask is
   off for a glass, a mask WeChat sets is kept as its own (given back when the
   glass goes) and not put on; the plugin's hiding masks pass. */
static NSHashTable<CALayer *> *WXGUnmaskedLayers;
static void (*WXGSetMaskOriginal)(id,SEL,CALayer *);
static void WXGSetMaskGuarded(CALayer *layer,SEL cmd,CALayer *mask) {
    if(mask && pthread_main_np() && [WXGUnmaskedLayers containsObject:layer] && ![mask.name isEqualToString:@"wxg.conceal"]) {
        id view=layer.delegate;
        if([view isKindOfClass:UIView.class])objc_setAssociatedObject(view,&WXGUnmaskedOwnKey,mask,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(layer.mask)WXGSetMaskOriginal(layer,cmd,nil);   // (a hiding mask being replaced: replaced by nothing)
        return;
    }
    WXGSetMaskOriginal(layer,cmd,mask);
}
static void WXGInstallMaskGuard(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        WXGUnmaskedLayers=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];
        Method m=class_getInstanceMethod(CALayer.class,@selector(setMask:));
        if(m){WXGSetMaskOriginal=(void (*)(id,SEL,CALayer *))method_getImplementation(m);method_setImplementation(m,(IMP)WXGSetMaskGuarded);}
    });
}
/* FIX115 L (user, 20:43, probe 20:31: 聊天背景's 完成 still showed WeChat's
   faint fill (white 0.102) as a box round the capsule: WeChat paints the
   button's fill again after the plugin cleared it, in the same frame). While
   a coloured button's glass is there, a fill set on its layer is kept as
   WeChat's (the glass's tint, given back when the glass goes) and the layer
   shows none; a clear one (the plugin's) passes. */
static NSHashTable<CALayer *> *WXGFillGuardedLayers;
static char WXGGuardedFillKey;
static void (*WXGSetLayerBackgroundOriginal)(id,SEL,CGColorRef);
static void WXGSetLayerBackgroundGuarded(CALayer *layer,SEL cmd,CGColorRef color) {
    if(color && CGColorGetAlpha(color)>0 && pthread_main_np() && [WXGFillGuardedLayers containsObject:layer]) {
        objc_setAssociatedObject(layer,&WXGGuardedFillKey,[UIColor colorWithCGColor:color],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(layer.backgroundColor)WXGSetLayerBackgroundOriginal(layer,cmd,NULL);
        return;
    }
    WXGSetLayerBackgroundOriginal(layer,cmd,color);
}
static void WXGInstallFillGuard(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        WXGFillGuardedLayers=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];
        Method m=class_getInstanceMethod(CALayer.class,@selector(setBackgroundColor:));
        if(m){WXGSetLayerBackgroundOriginal=(void (*)(id,SEL,CGColorRef))method_getImplementation(m);method_setImplementation(m,(IMP)WXGSetLayerBackgroundGuarded);}
    });
}
@interface WXGViewState ()
@property(nonatomic,strong) UIImage *originalImage,*adaptiveImage;
@property(nonatomic) BOOL changedImagePaint;
@property(nonatomic) BOOL changedImage;
@property(nonatomic,strong) UIColor *nativeLabelColor;
@property(nonatomic) BOOL changedLabelColor;
@property(nonatomic,strong) UIColor *originalTint;
@property(nonatomic) BOOL originalAccessibilityHidden;
@property(nonatomic,strong) UIVisualEffect *effect;
@property(nonatomic,strong) id contents;
@property(nonatomic) CGRect alignedFrame,normalizedInk;
@property(nonatomic,strong) UIImage *alignmentImage;
@property(nonatomic) UIViewContentMode alignmentMode;
@property(nonatomic,weak) UIView *alignmentHost;
@property(nonatomic) BOOL alignmentWriting;
// FIX113 E: shiftContents:x:.
@property(nonatomic) BOOL changedSublayerTransform,changedTransform;
@property(nonatomic) CATransform3D originalSublayerTransform,appliedSublayerTransform;
@property(nonatomic) CGAffineTransform originalTransform,appliedTransform;
@property(nonatomic) CGFloat contentShift;
@property(nonatomic) CGFloat contentShiftY;   // FIX114 C: the title row moved down (顶部按钮往下移)
@end
static char WXGNativeIconKey;
@interface WXGIconBinding : NSObject
@property(nonatomic,weak) WXGViewState *state;
@end
@implementation WXGIconBinding
@end
static WXGViewState *WXGLockedIcon(UIImageView *view) {
    WXGIconBinding *binding=objc_getAssociatedObject(view,&WXGNativeIconKey);WXGViewState *s=binding.state;
    return s && !s.alignmentWriting && s.alignmentHost && [view isDescendantOfView:s.alignmentHost] &&
        view.window && CGAffineTransformIsIdentity(view.transform) && WXGPluginEnabled() && WXGPreferences.shared.nav?s:nil;
}
void WXGInstallNativeIconGuard(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        // Only UIImageViews explicitly registered by MainFrameLeftBarView's
        // correction use this path. Other native/third-party images pass through.
        // FIX115 B: what UIImageView had when installed (its own, or UIView's then).
        Class cls=UIImageView.class,superclass=class_getSuperclass(cls);
        for(NSString *name in @[@"setFrame:",@"setBounds:"]) {
            SEL sel=NSSelectorFromString(name);Method method=class_getInstanceMethod(cls,sel);if(!method)continue;
            IMP own=WXGCapturedImplementation(cls,sel);
            BOOL frame=[name isEqual:@"setFrame:"];
            IMP replacement=imp_implementationWithBlock(^(UIImageView *view,CGRect incoming){
                IMP original=WXGThrough(own,superclass,sel);
                WXGViewState *state=WXGLockedIcon(view);CGRect accepted=incoming;
                if(state) {
                    if(frame && !CGRectEqualToRect(incoming,state.alignedFrame))[state updateNativeFrame:incoming];
                    if(frame)accepted=state.alignedFrame;else accepted.size=state.alignedFrame.size;
                    state.alignmentWriting=YES;
                }
                @try {
                    if(state)[UIView performWithoutAnimation:^{((void(*)(id,SEL,CGRect))original)(view,sel,accepted);}];
                    else ((void(*)(id,SEL,CGRect))original)(view,sel,accepted);
                }@finally {if(state)state.alignmentWriting=NO;}
            });
            WXGInstallOverride(cls,sel,replacement,method_getTypeEncoding(method));
        }
        SEL sel=@selector(setCenter:);Method method=class_getInstanceMethod(cls,sel);if(!method)return;
        IMP own=WXGCapturedImplementation(cls,sel);
        IMP replacement=imp_implementationWithBlock(^(UIImageView *view,CGPoint incoming){
            IMP original=WXGThrough(own,superclass,sel);
            WXGViewState *state=WXGLockedIcon(view);CGPoint accepted=incoming;
            if(state){accepted=CGPointMake(CGRectGetMidX(state.alignedFrame),CGRectGetMidY(state.alignedFrame));state.alignmentWriting=YES;}
            @try {
                if(state)[UIView performWithoutAnimation:^{((void(*)(id,SEL,CGPoint))original)(view,sel,accepted);}];
                else ((void(*)(id,SEL,CGPoint))original)(view,sel,accepted);
            }@finally {if(state)state.alignmentWriting=NO;}
        });
        WXGInstallOverride(cls,sel,replacement,method_getTypeEncoding(method));
    });
}
@implementation WXGViewState
- (instancetype)initWithView:(UIView *)v {
    if((self=[super init])) {_view=v;_originalFrame=v.frame;_originalAlpha=v.alpha;_originallyHidden=v.hidden;
        _color=v.backgroundColor;_opaque=v.opaque;_clips=v.clipsToBounds;_borderWidth=v.layer.borderWidth;_cornerRadius=v.layer.cornerRadius;_shadowOpacity=v.layer.shadowOpacity;}
    return self;
}
- (void)updateNativeFrame:(CGRect)frame { _originalFrame=frame; }
- (void)restore {
    UIView *v=_view;if(!v) return;
    if(_alignmentHost)objc_setAssociatedObject(v,&WXGNativeIconKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(_changedClips)v.clipsToBounds=_clips;
    if(_changedAlpha)v.alpha=_originalAlpha;
    if(_changedMask){if(v.layer.mask==_concealMask)v.layer.mask=_originalMask;v.accessibilityElementsHidden=_originalAccessibilityHidden;}
    if(_changedUnmask) {   // FIX115 J (and laid out again: a button resized meanwhile reshapes its own mask)
        [WXGUnmaskedLayers removeObject:v.layer];   // FIX115 K: WeChat's masks pass again
        CALayer *own=objc_getAssociatedObject(v,&WXGUnmaskedOwnKey)?:_unmaskedOriginal;
        objc_setAssociatedObject(v,&WXGUnmaskedOwnKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(!v.layer.mask && own){v.layer.mask=own;[v setNeedsLayout];}
    }
    if(_adaptiveImage && [v isKindOfClass:UIImageView.class]){UIImageView *iv=(id)v;if(iv.image==_adaptiveImage){iv.image=_originalImage;iv.tintColor=_originalTint;}}
    if(_changedLabelColor && [v isKindOfClass:UILabel.class] && [((UILabel *)v).textColor isEqual:UIColor.labelColor])((UILabel *)v).textColor=_nativeLabelColor;
    if(_changedFillGuard) {   // FIX115 L: WeChat's last fill (set while guarded) is what goes back
        [WXGFillGuardedLayers removeObject:v.layer];_changedFillGuard=NO;
        UIColor *latest=objc_getAssociatedObject(v.layer,&WXGGuardedFillKey);
        objc_setAssociatedObject(v.layer,&WXGGuardedFillKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(latest && _changedPaint)_color=latest;
    }
    if(_changedPaint){v.backgroundColor=_color;v.opaque=_opaque;v.layer.borderWidth=_borderWidth;v.layer.shadowOpacity=_shadowOpacity;}
    if(_changedEffect && [v isKindOfClass:UIVisualEffectView.class])((UIVisualEffectView *)v).effect=_effect;
    if(_changedImage && [v isKindOfClass:UIImageView.class])WXGReleaseImagePaint((UIImageView *)v);
    if(_changedContents && !_changedImage)v.layer.contents=_contents;
    if(_restoreGeometry && !CGRectEqualToRect(v.frame,_originalFrame)) v.frame=_originalFrame;
    if(_changedSublayerTransform){[CATransaction begin];[CATransaction setDisableActions:YES];v.layer.sublayerTransform=_originalSublayerTransform;[CATransaction commit];}
    if(_changedTransform){[UIView performWithoutAnimation:^{v.transform=self->_originalTransform;}];_changedTransform=NO;}
    if(_changedTitleColor && [v isKindOfClass:UIButton.class]) {   // FIX115 Q (review)
        UIButton *b=(UIButton *)v;
        [b setTitleColor:_titleNormal forState:UIControlStateNormal];
        _changedTitleColor=NO;
    }
    if(_changedRound) {   // FIX115 Q
        [CATransaction begin];[CATransaction setDisableActions:YES];
        v.layer.cornerRadius=_roundOriginalRadius;v.layer.masksToBounds=_roundMasks;if(_roundCurve)v.layer.cornerCurve=_roundCurve;
        [CATransaction commit];_changedRound=NO;
    }
}
@end
@interface WXGLayerState : NSObject
@property(nonatomic,weak) CALayer *layer;
@property(nonatomic) BOOL hidden;
@end
@implementation WXGLayerState
@end
static BOOL WXGContainsContent(UIView *root,NSArray<UIView *> *protected) {
    for(UIView *v in protected)if(v==root || [v isDescendantOfView:root])return YES;
    for(UIView *v in WXGViews(root,100))
        if([v isKindOfClass:UIControl.class] || [v isKindOfClass:UILabel.class] || [v isKindOfClass:UITextView.class] ||
           [v isKindOfClass:UIScrollView.class] || v.gestureRecognizers.count)return YES;
    return NO;
}
@interface WXGStateBag ()
@property(nonatomic,strong) NSMapTable<UIView *,WXGViewState *> *states;
@property(nonatomic,strong) NSMapTable<CALayer *,WXGLayerState *> *layers;
@property(nonatomic) BOOL reapplying;
@end
@implementation WXGStateBag
- (instancetype)init {if((self=[super init])){_states=[NSMapTable weakToStrongObjectsMapTable];_layers=[NSMapTable weakToStrongObjectsMapTable];}return self;}
- (WXGViewState *)remember:(UIView *)v {
    if(!v) return nil;WXGViewState *s=[_states objectForKey:v];if(!s){s=[[WXGViewState alloc]initWithView:v];[_states setObject:s forKey:v];}return s;
}
- (void)hide:(UIView *)v {
    if(!v)return;WXGViewState *s=[self remember:v];
    if(s.changedAlpha && v.alpha>0)s.originalAlpha=v.alpha;
    s.changedAlpha=YES;if(v.alpha!=0)v.alpha=0;
}
- (void)adaptMonochromeImage:(UIImageView *)view {
    if(!view.image)return;WXGViewState *s=[self remember:view];
    if(view.image!=s.adaptiveImage && (view.image!=s.originalImage || !s.adaptiveImage)) {
        if(!WXGImageIsMonochrome(view.image))return;
        s.originalImage=view.image;s.originalTint=view.tintColor;
        s.adaptiveImage=[view.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if(s.adaptiveImage){
        if(view.image!=s.adaptiveImage)view.image=s.adaptiveImage;
        if(![view.tintColor isEqual:UIColor.labelColor])view.tintColor=UIColor.labelColor;
    }
}
// FIX114 V: another bag's hiding mask is never a view's own (two bags hiding
// one view, the first one's mask would otherwise be put back as the original).
// FIX115 J: while unmask: has WeChat's own mask off, that one is still the
// view's own: a bag concealing the view meanwhile (the host taking over a
// coloured title-bar button) puts it back, not nil.
static CALayer *WXGOwnMask(UIView *v) {
    CALayer *mask=v.layer.mask;
    if(!mask)mask=objc_getAssociatedObject(v,&WXGUnmaskedOwnKey);
    return [mask.name isEqualToString:@"wxg.conceal"]?nil:mask;
}
- (void)conceal:(UIView *)v {
    if(!v)return;WXGViewState *s=[self remember:v];
    if(!s.changedMask){s.originalMask=WXGOwnMask(v);s.originalAccessibilityHidden=v.accessibilityElementsHidden;s.concealMask=[CALayer layer];s.concealMask.name=@"wxg.conceal";s.changedMask=YES;}
    // Keep native alpha/hidden/transform and their presentation animations intact.
    // An empty mask hides only the pixels replaced by a full TEST4 surface.
    if(v.layer.mask!=s.concealMask){s.originalMask=WXGOwnMask(v);v.layer.mask=s.concealMask;}
    if(!v.accessibilityElementsHidden)v.accessibilityElementsHidden=YES;
}
- (void)unconceal:(UIView *)v {
    WXGViewState *s=v?[_states objectForKey:v]:nil;if(!s.changedMask)return;
    if(v.layer.mask==s.concealMask)v.layer.mask=s.originalMask;
    v.accessibilityElementsHidden=s.originalAccessibilityHidden;
    s.changedMask=NO;s.originalMask=nil;s.concealMask=nil;
}
- (void)adaptLabelColor:(UILabel *)label {
    if(!label)return;WXGViewState *s=[self remember:label];
    if(![label.textColor isEqual:UIColor.labelColor])s.nativeLabelColor=label.textColor;
    s.changedLabelColor=YES;if(![label.textColor isEqual:UIColor.labelColor])label.textColor=UIColor.labelColor;
}
- (void)shiftContents:(UIView *)v x:(CGFloat)dx {[self shiftContents:v x:dx y:0];}
// FIX114 C: across and down (the title row's margin and its offset).
- (void)shiftContents:(UIView *)v x:(CGFloat)dx y:(CGFloat)dy {
    if(!v)return;
    WXGViewState *s=[_states objectForKey:v];
    if(!s && fabs(dx)<.01 && fabs(dy)<.01)return;
    s=[self remember:v];
    if(!s.changedSublayerTransform){s.changedSublayerTransform=YES;s.originalSublayerTransform=v.layer.sublayerTransform;}
    s.contentShift=fabs(dx)<.01?0:dx;s.contentShiftY=fabs(dy)<.01?0:dy;
    s.appliedSublayerTransform=s.contentShift!=0 || s.contentShiftY!=0?CATransform3DTranslate(s.originalSublayerTransform,s.contentShift,s.contentShiftY,0):s.originalSublayerTransform;
    if(!CATransform3DEqualToTransform(v.layer.sublayerTransform,s.appliedSublayerTransform)) {
        [CATransaction begin];[CATransaction setDisableActions:YES];v.layer.sublayerTransform=s.appliedSublayerTransform;[CATransaction commit];
    }
}
- (void)shiftView:(UIView *)v x:(CGFloat)dx y:(CGFloat)dy {
    if(!v)return;
    if(v.subviews.count>0) {
        WXGViewState *prev=[_states objectForKey:v];
        if(prev.changedTransform) {
            prev.changedTransform=NO;prev.appliedTransform=prev.originalTransform;
            if(!CGAffineTransformEqualToTransform(v.transform,prev.originalTransform))
                [UIView performWithoutAnimation:^{v.transform=prev.originalTransform;}];
        }
        [self shiftContents:v x:dx y:dy];return;
    }
    WXGViewState *s=[_states objectForKey:v];
    if(!s && fabs(dx)<.01 && fabs(dy)<.01)return;
    s=[self remember:v];
    if(s.changedSublayerTransform) {
        s.changedSublayerTransform=NO;s.contentShift=0;s.contentShiftY=0;s.appliedSublayerTransform=s.originalSublayerTransform;
        if(!CATransform3DEqualToTransform(v.layer.sublayerTransform,s.originalSublayerTransform)) {
            [CATransaction begin];[CATransaction setDisableActions:YES];v.layer.sublayerTransform=s.originalSublayerTransform;[CATransaction commit];
        }
    }
    if(!s.changedTransform){s.changedTransform=YES;s.originalTransform=v.transform;}
    CGFloat tx=fabs(dx)<.01?0:dx,ty=fabs(dy)<.01?0:dy;
    s.contentShift=tx;s.contentShiftY=ty;
    s.appliedTransform=(tx!=0 || ty!=0)?CGAffineTransformConcat(s.originalTransform,CGAffineTransformMakeTranslation(tx,ty)):s.originalTransform;
    if(!CGAffineTransformEqualToTransform(v.transform,s.appliedTransform))
        [UIView performWithoutAnimation:^{v.transform=s.appliedTransform;}];
}
- (CGFloat)contentShiftOf:(UIView *)v {WXGViewState *s=v?[_states objectForKey:v]:nil;return s.changedSublayerTransform?s.contentShift:0;}
- (CGPoint)contentOffsetOf:(UIView *)v {WXGViewState *s=v?[_states objectForKey:v]:nil;return s.changedSublayerTransform?CGPointMake(s.contentShift,s.contentShiftY):CGPointZero;}
- (void)allowOverflow:(UIView *)v {
    if(!v)return;WXGViewState *s=[self remember:v];
    // FIX114 C (review): the original taken when this bag first changes it, not
    // when the bag first met the view (another bag may have opened it since).
    if(!s.changedClips) {
        // FIX114 M (review): a view a drop shadow holds open: its own value from there.
        BOOL clips=v.clipsToBounds,without=NO;
        if(WXGShadowAdoptOverflow(v,&without))clips=without;
        s.clips=clips;s.changedClips=YES;
    }
    if(v.clipsToBounds)v.clipsToBounds=NO;
}
// FIX115 J: the fill WeChat last gave a view this bag cleared (-clear: keeps
// every later one it finds; the first one from when the bag met the view).
- (UIColor *)nativeColorOf:(UIView *)v {
    WXGViewState *s=v?[_states objectForKey:v]:nil;
    UIColor *guarded=s.changedFillGuard?objc_getAssociatedObject(v.layer,&WXGGuardedFillKey):nil;   // FIX115 L: the latest of all
    return guarded?:(s.changedPaint?s.color:v.backgroundColor);
}
// FIX115 L: the view's fill cleared, and kept clear against WeChat painting it again.
- (void)guardFill:(UIView *)v {
    if(!v || !pthread_main_np())return;
    WXGViewState *s=[self remember:v];
    if(!s.changedFillGuard){WXGInstallFillGuard();[WXGFillGuardedLayers addObject:v.layer];s.changedFillGuard=YES;}
    [self clear:v];
}
// FIX115 J: never one of the plugin's hiding masks. (Setting a layer's mask
// does not ask for a layout: WeChat itself sets this one in every layout.)
- (void)unmask:(UIView *)v {
    if(!v || !pthread_main_np())return;WXGViewState *s=[self remember:v];
    WXGInstallMaskGuard();[WXGUnmaskedLayers addObject:v.layer];   // FIX115 K
    CALayer *mask=v.layer.mask;
    if(!mask || [mask.name isEqualToString:@"wxg.conceal"]){s.changedUnmask=YES;return;}
    s.unmaskedOriginal=mask;v.layer.mask=nil;
    objc_setAssociatedObject(v,&WXGUnmaskedOwnKey,mask,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    s.changedUnmask=YES;
}
// FIX115 Q: a view drawn round with this radius (its corner radius and
// clipping; WeChat's own values back on restore; set again on reapply).
- (void)round:(UIView *)v radius:(CGFloat)radius {
    if(!v || !(radius>0))return;WXGViewState *s=[self remember:v];
    if(!s.changedRound){s.changedRound=YES;s.roundOriginalRadius=v.layer.cornerRadius;s.roundMasks=v.layer.masksToBounds;s.roundCurve=v.layer.cornerCurve;}
    s.roundRadius=radius;
    if(fabs(v.layer.cornerRadius-radius)>.01 || !v.layer.masksToBounds || ![v.layer.cornerCurve isEqualToString:kCACornerCurveCircular]) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        v.layer.cornerRadius=radius;v.layer.masksToBounds=YES;v.layer.cornerCurve=kCACornerCurveCircular;
        [CATransaction commit];
    }
}
// FIX115 Q (review: UIButton sets its label's colour from its title colours
// at every layout and state change, so the label's own colour does not hold):
// the button's (normal) title colour itself, WeChat's back on
// restore; one WeChat sets again is taken as its own and replaced on reapply.
- (void)titleColor:(UIButton *)button color:(UIColor *)color {
    if(![button isKindOfClass:UIButton.class] || !color)return;WXGViewState *s=[self remember:button];
    UIColor *normal=[button titleColorForState:UIControlStateNormal];
    if(!s.changedTitleColor){s.changedTitleColor=YES;s.titleNormal=normal;}
    else if(normal && ![normal isEqual:s.titleApplied])s.titleNormal=normal;
    s.titleApplied=color;
    if(![normal isEqual:color])[button setTitleColor:color forState:UIControlStateNormal];
}
- (void)clear:(UIView *)v {
    if(!v)return;WXGViewState *s=[self remember:v];
    // Keep later native theme changes restorable as well (not our own paint).
    if(s.changedPaint && v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor)>0 && ![v.backgroundColor isEqual:s.paintColor])s.color=v.backgroundColor;
    else if(s.changedPaint && !v.backgroundColor && !v.layer.backgroundColor)s.color=nil;   // FIX115 K (review): WeChat emptied it (the plugin only ever sets clear)
    if(v.layer.shadowOpacity>0)s.shadowOpacity=v.layer.shadowOpacity;
    s.changedPaint=YES;
    if(s.paintColor){if(![v.backgroundColor isEqual:s.paintColor])v.backgroundColor=s.paintColor;return;}
    if(![v.backgroundColor isEqual:UIColor.clearColor])v.backgroundColor=UIColor.clearColor;
    if(v.opaque)v.opaque=NO;if(v.layer.borderWidth)v.layer.borderWidth=0;
    if(v.layer.shadowOpacity)v.layer.shadowOpacity=0;
}
// FIX47: paint a background another colour, restorably (re-asserted by
// reapply like a cleared one; restore gives the original back).
- (void)paint:(UIView *)v color:(UIColor *)color {
    if(!v || !color)return;WXGViewState *s=[self remember:v];
    if(!s.changedPaint && v.backgroundColor)s.color=v.backgroundColor;
    s.paintColor=color;[self clear:v];
}
- (void)clearImagePaint:(UIImageView *)view {
    if(!view)return;WXGViewState *s=[self remember:view];
    // Keep UIImage/intrinsic size and its child controls intact. These captured
    // paint hosts draw their bitmap in layer.contents; suppress only those pixels.
    if(view.layer.contents){s.contents=view.layer.contents;s.changedContents=YES;view.layer.contents=nil;}
    s.changedImagePaint=YES;
    // FIX29: keep the image itself out, not just this frame's pixels.
    if(view.image){WXGGuardImagePaint(view);s.changedImage=YES;}
    [self clear:view];
}
- (BOOL)centerNativeImage:(UIImageView *)image inHost:(UIView *)host maximumInk:(CGFloat)maximum {
    if(!image.image || !image.window || !image.superview || ![image isDescendantOfView:host] ||
       !CGAffineTransformIsIdentity(image.transform) || image.animationImages.count)return NO;
    if(image.contentMode!=UIViewContentModeScaleToFill && image.contentMode!=UIViewContentModeScaleAspectFit && image.contentMode!=UIViewContentModeScaleAspectFill)return NO;
    WXGViewState *state=[self remember:image];
    state.alignmentWriting=YES;
    @try {
    if(!state.restoreGeometry || !CGRectEqualToRect(image.frame,state.alignedFrame)) {
        if(!CGSizeEqualToSize(image.frame.size,state.originalFrame.size))state.alignmentImage=nil;
        [state updateNativeFrame:image.frame];
    }
    if(state.alignmentImage!=image.image || state.alignmentMode!=image.contentMode) {
        // Measure only when the native image/layout changes, never per display tick.
        if(!CGRectEqualToRect(image.frame,state.originalFrame))[UIView performWithoutAnimation:^{image.frame=state.originalFrame;}];
        NSDictionary *metrics=WXGRenderedInkEvidence(image);
        if(![metrics[@"available"] boolValue] || CGRectIsEmpty(image.bounds))return NO;
        NSArray *r=metrics[@"windowRect"];
        CGRect local=[image convertRect:CGRectMake([r[0] doubleValue],[r[1] doubleValue],[r[2] doubleValue],[r[3] doubleValue]) fromView:image.window];
        state.normalizedInk=CGRectMake((local.origin.x-image.bounds.origin.x)/image.bounds.size.width,
            (local.origin.y-image.bounds.origin.y)/image.bounds.size.height,local.size.width/image.bounds.size.width,local.size.height/image.bounds.size.height);
        state.alignmentImage=image.image;state.alignmentMode=image.contentMode;
    }
    CGPoint center=[host convertPoint:CGPointMake(CGRectGetMidX(host.bounds),CGRectGetMidY(host.bounds)) toView:image.superview];
    // FIX114 C (user: the home page's star stayed where it was when its glass
    // moved to the title row's margin): the host's contents are drawn shifted
    // (shiftContents: its layer's sublayerTransform), the image with them; but
    // a point taken from the host into a view inside it comes back with that
    // shift taken off (the layers' conversion counts the sublayerTransform),
    // so the image was set back by the shift each time it was aligned. By
    // frames alone while the host is shifted (the same point without it).
    WXGViewState *hostState=[_states objectForKey:host];
    if(hostState.changedSublayerTransform && (hostState.contentShift!=0 || hostState.contentShiftY!=0) && image.superview!=host) {
        CGPoint offset=CGPointZero;UIView *p=image.superview;NSUInteger depth=0;
        for(;p && p!=host && depth<16;p=p.superview,depth++){offset.x+=p.frame.origin.x-p.bounds.origin.x;offset.y+=p.frame.origin.y-p.bounds.origin.y;}
        if(p==host)center=CGPointMake(CGRectGetMidX(host.bounds)-offset.x,CGRectGetMidY(host.bounds)-offset.y);
    }
    CGRect f=state.originalFrame,n=state.normalizedInk;
    WXGRect result=WXGAlignedImageFrame((WXGRect){f.origin.x,f.origin.y,f.size.width,f.size.height},
        (WXGRect){n.origin.x,n.origin.y,n.size.width,n.size.height},center.x,center.y,maximum);
    state.alignedFrame=WXGCGRect(result);state.restoreGeometry=YES;
    if(!CGRectEqualToRect(image.frame,state.alignedFrame))[UIView performWithoutAnimation:^{image.frame=state.alignedFrame;}];
    state.alignmentHost=host;
    WXGIconBinding *binding=objc_getAssociatedObject(image,&WXGNativeIconKey);
    if(!binding){binding=[WXGIconBinding new];objc_setAssociatedObject(image,&WXGNativeIconKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    binding.state=state;
    return YES;
    }@finally {state.alignmentWriting=NO;}
}
- (void)hideDecorationLayer:(CALayer *)layer {
    WXGLayerState *s=[_layers objectForKey:layer];
    if(!s){s=[WXGLayerState new];s.layer=layer;s.hidden=layer.hidden;[_layers setObject:s forKey:layer];}
    if(!layer.hidden)layer.hidden=YES;
}
- (void)stripChrome:(UIView *)root preserving:(NSArray<UIView *> *)content {
    if(!root)return;
    for(UIView *v in WXGViews(root,200)) {
        if(WXGIsPluginView(v))continue;
        BOOL protected=NO;for(UIView *p in content)if(v==p || [v isDescendantOfView:p]){protected=YES;break;}
        for(UIView *parent=v==root?nil:v.superview;parent && parent!=root;parent=parent.superview)
            if([parent isKindOfClass:UIControl.class] || [parent isKindOfClass:UILabel.class] || [parent isKindOfClass:UITextView.class] ||
               [parent isKindOfClass:UIScrollView.class] || parent.gestureRecognizers.count){protected=YES;break;}
        if(protected || (v!=root && v.gestureRecognizers.count) || [v isKindOfClass:UIControl.class] || [v isKindOfClass:UILabel.class] || [v isKindOfClass:UITextView.class] || [v isKindOfClass:UIScrollView.class])continue;
        NSString *name=NSStringFromClass(v.class).lowercaseString;
        BOOL paintOnly=!WXGContainsContent(v,content);
        BOOL line=v.bounds.size.height<=2 && v.bounds.size.width>root.bounds.size.width*.5;
        BOOL background=[name containsString:@"background"] || [name containsString:@"backdrop"] || [name containsString:@"shadow"] || [name containsString:@"separator"];
        if(v!=root && paintOnly && ([v isKindOfClass:UIVisualEffectView.class] || line || background ||
           ([v isKindOfClass:UIImageView.class] && v.bounds.size.width>=root.bounds.size.width*.8))) {
            [self hide:v];continue;
        }
        // A blur with controls inside must keep its contentView interactive.
        if([v isKindOfClass:UIVisualEffectView.class]) {
            [self clearEffect:(UIVisualEffectView *)v];
        } else if(![v isKindOfClass:UIImageView.class]) {
            [self clear:v];
            if(v.layer.contents){WXGViewState *state=[self remember:v];
                if(!state.changedContents)state.contents=v.layer.contents;
                state.changedContents=YES;v.layer.contents=nil;
            }
        }
        for(CALayer *layer in v.layer.sublayers) {
            if([layer.delegate isKindOfClass:UIView.class])continue;
            NSString *n=(layer.name?:NSStringFromClass(layer.class)).lowercaseString;
            BOOL separator=layer.bounds.size.height<=2 && layer.bounds.size.width>=root.bounds.size.width*.5;
            if(separator || [n containsString:@"separator"] || [n containsString:@"backdrop"] ||
               ([layer isKindOfClass:CAGradientLayer.class] && layer.bounds.size.width>=root.bounds.size.width*.8))[self hideDecorationLayer:layer];
        }
    }
}
- (void)clearEffect:(UIVisualEffectView *)view {
    WXGViewState *state=[self remember:view];
    if(!state.changedEffect || view.effect)state.effect=view.effect;
    state.changedEffect=YES;
    if(view.effect)view.effect=nil;
}
- (void)reapply {
    if(_reapplying)return;_reapplying=YES;
    @try {
    for(WXGViewState *s in _states.objectEnumerator){
        // Hold the weak target once for this pass; nested native setters must
        // not recursively enumerate and reapply the same bag.
        UIView *view=s.view;if(!view)continue;
        if(s.changedClips && view.clipsToBounds)view.clipsToBounds=NO;
        if(s.changedMask)[self conceal:view];
        if(s.changedUnmask && view.layer.mask)[self unmask:view];   // FIX115 J: one WeChat set again
        if(s.changedRound)[self round:view radius:s.roundRadius];    // FIX115 Q
        if(s.changedTitleColor && s.titleApplied && [view isKindOfClass:UIButton.class])[self titleColor:(UIButton *)view color:s.titleApplied];   // FIX115 Q
        if(s.changedLabelColor && [view isKindOfClass:UILabel.class])[self adaptLabelColor:(id)view];
        if(s.adaptiveImage && [view isKindOfClass:UIImageView.class])[self adaptMonochromeImage:(id)view];
        if(s.changedImagePaint && [view isKindOfClass:UIImageView.class])[self clearImagePaint:(id)view];
        if(s.changedAlpha)[self hide:view];if(s.changedPaint)[self clear:view];
        if(s.changedEffect && [view isKindOfClass:UIVisualEffectView.class]) {
            UIVisualEffectView *v=(id)view;if(v.effect){s.effect=v.effect;v.effect=nil;}
        }
        if(s.changedContents && view.layer.contents){s.contents=view.layer.contents;view.layer.contents=nil;}
        if(s.changedSublayerTransform && !CATransform3DEqualToTransform(view.layer.sublayerTransform,s.appliedSublayerTransform)) {
            [CATransaction begin];[CATransaction setDisableActions:YES];view.layer.sublayerTransform=s.appliedSublayerTransform;[CATransaction commit];
        }
        if(s.changedTransform && !CGAffineTransformEqualToTransform(view.transform,s.appliedTransform))
            [UIView performWithoutAnimation:^{view.transform=s.appliedTransform;}];
    }
    for(WXGLayerState *s in _layers.objectEnumerator){CALayer *layer=s.layer;if(layer && !layer.hidden)layer.hidden=YES;}
    }@finally {_reapplying=NO;}
}
- (void)restoreView:(UIView *)v {WXGViewState *s=[_states objectForKey:v];[s restore];[_states removeObjectForKey:v];}
- (void)restore {
    for(WXGViewState *s in _states.objectEnumerator)[s restore];[_states removeAllObjects];
    for(WXGLayerState *s in _layers.objectEnumerator)s.layer.hidden=s.hidden;[_layers removeAllObjects];
}
- (NSArray<NSDictionary *> *)evidence {
    NSMutableArray *out=[NSMutableArray array];
    for(UIView *v in _states.keyEnumerator) {
        WXGViewState *s=[_states objectForKey:v];CGRect r=WXGWindowRect(v,v.window);
        CGFloat red=0,g=0,b=0,a=0;BOOL color=[v.backgroundColor getRed:&red green:&g blue:&b alpha:&a];
        CGFloat r0=0,g0=0,b0=0,a0=0;BOOL originalColor=[s.color getRed:&r0 green:&g0 blue:&b0 alpha:&a0];
        NSString *effect=[v isKindOfClass:UIVisualEffectView.class]?NSStringFromClass(((UIVisualEffectView *)v).effect.class):@"none";
        NSMutableArray *layers=[NSMutableArray array];for(CALayer *l in v.layer.sublayers)if(layers.count<8)[layers addObject:NSStringFromClass(l.class)];
        [out addObject:@{@"class":NSStringFromClass(v.class),@"rect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],
            @"alpha":@(v.alpha),@"hidden":@(v.hidden),@"originalAlpha":@(s.originalAlpha),@"originalHidden":@(s.originallyHidden),
            @"nativeIconAligned":@(s.alignmentImage!=nil),@"nativeFrame":NSStringFromCGRect(s.originalFrame),@"alignedFrame":NSStringFromCGRect(s.alignedFrame),
            @"backgroundRGBA":color?@[@(red),@(g),@(b),@(a)]:@[],@"opaque":@(v.opaque),@"effectClass":effect?:@"nil",
            @"originalBackgroundRGBA":originalColor?@[@(r0),@(g0),@(b0),@(a0)]:@[],
            @"layerClass":NSStringFromClass(v.layer.class),@"layerOpacity":@(v.layer.opacity),@"layerHidden":@(v.layer.hidden),
            @"zPosition":@(v.layer.zPosition),@"borderWidth":@(v.layer.borderWidth),@"cornerRadius":@(v.layer.cornerRadius),@"sublayerClasses":layers}];
    }
    for(WXGLayerState *state in _layers.objectEnumerator) {
        CALayer *layer=state.layer;if(!layer)continue;
        [out addObject:@{@"layerOnly":@YES,@"class":NSStringFromClass(layer.class),
                        @"hidden":@(layer.hidden),@"originalHidden":@(state.hidden),@"frame":NSStringFromCGRect(layer.frame)}];
    }
    return out;
}
@end
