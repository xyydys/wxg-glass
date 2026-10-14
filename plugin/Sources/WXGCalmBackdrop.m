#import "WXGIntegration.h"
#import "WXGCalmMath.h"

/* FIX85: 平稳背景时加强材质 (材质强度与范围 → 平稳背景).
   Apple's glass gets close to opaque when what is behind it hardly changes.
   With the switch on, every few tenths of a second each page the glass sits
   on (its source view) is rendered once, small (about 4 pt per pixel), from
   its model layers, with the plugin's own views hidden; each glass's area
   (plus 6 pt) is measured (WXGCalmMath.h: the colour spread, 0 for a plain
   colour) and its calm value eased toward the result. The glass then moves its
   material coverage toward the "平稳时" value by that much (WXGGlassView).
   Not measured: the liquid bubbles and 视频号 capsules (their own tint or
   none) and lightweight glass (the settings cards, on a decorative wallpaper).
   The interval grows when a render costs more (0.3 s, 0.6 s, 1.2 s); the
   time is counted in the frame-rate log. */

static NSHashTable<WXGGlassView *> *WXGCalmGlasses;
@interface WXGCalmState : NSObject
@property(nonatomic) double sigma,target;
@property(nonatomic) BOOL measured,media;
@property(nonatomic) CGRect rect;
@property(nonatomic,weak) UIView *source;
@property(nonatomic) CFTimeInterval measuredAt;
@end
@implementation WXGCalmState
@end
static NSMapTable<WXGGlassView *,WXGCalmState *> *WXGCalmStates;

void WXGCalmRegister(WXGGlassView *glass) {
    if(!glass)return;
    if(!WXGCalmGlasses)WXGCalmGlasses=[NSHashTable weakObjectsHashTable];
    [WXGCalmGlasses addObject:glass];
}

@interface WXGCalmMonitor : NSObject
+ (instancetype)shared;
- (void)apply;
@end
@implementation WXGCalmMonitor {
    NSTimer *_timer;
    NSTimeInterval _interval;
    double _lastMS,_averageMS,_maxMS;
    NSUInteger _renders,_skips;
    BOOL _observing;
}
+ (instancetype)shared {static WXGCalmMonitor *m;static dispatch_once_t once;dispatch_once(&once,^{m=[self new];});return m;}
- (BOOL)wanted {return WXGConfig.shared.calmMaterialEnabled && WXGPluginEnabled();}
- (void)apply {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self apply];});return;}
    if(!_observing) {
        _observing=YES;
        for(NSString *name in @[WXGSettingsChanged,@"WXGIntegrationChanged"])
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(apply) name:name object:nil];
    }
    if([self wanted]) {
        if(!_timer)[self scheduleInterval:.3];
    }else if(_timer) {
        [_timer invalidate];_timer=nil;
        for(WXGGlassView *glass in WXGCalmGlasses.allObjects)glass.calmFactor=0;
        [WXGCalmStates removeAllObjects];
    }
}
- (void)scheduleInterval:(NSTimeInterval)interval {
    if(_timer && fabs(interval-_interval)<.01)return;
    [_timer invalidate];_interval=interval;
    _timer=[NSTimer timerWithTimeInterval:interval target:self selector:@selector(tick) userInfo:nil repeats:YES];
    _timer.tolerance=interval*.2;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (BOOL)measures:(WXGGlassView *)glass {
    return glass.window && !glass.hidden && glass.alpha>.01 && glass.active && !glass.veilOverride && !glass.bubbleSurface && !glass.lightweight;
}
- (void)tick {
    if(![self wanted]){[self apply];return;}
    // Not while a list is dragged or decelerating (the page moves under the
    // glass anyway; the render would cost frames).
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive || WXGBackdropCaptureInProgress() ||
       [NSRunLoop.currentRunLoop.currentMode isEqualToString:UITrackingRunLoopMode]){++_skips;return;}
    __block double spent=0;
    WXGPerfTimePluginWork(^{
        CFTimeInterval begin=CACurrentMediaTime();
        [self measure];
        spent=(CACurrentMediaTime()-begin)*1000;
    });
    _lastMS=spent;_averageMS=_averageMS>0?_averageMS*.8+spent*.2:spent;_maxMS=MAX(_maxMS,spent);
    [self scheduleInterval:_averageMS<4?.3:_averageMS<10?.6:1.2];
}
// FIX85 (review): video and Metal content is blank in renderInContext, so
// glass over it would read as calm: such layers' rects (in the source) count
// as a busy background. Our own views are skipped.
static void WXGCalmMediaRects(CALayer *root,UIView *source,NSMutableArray<NSValue *> *out) {
    static NSArray<Class> *classes;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableArray *list=[NSMutableArray array];
        for(NSString *name in @[@"AVPlayerLayer",@"AVSampleBufferDisplayLayer",@"CAMetalLayer",@"CAEAGLLayer"]){Class cls=NSClassFromString(name);if(cls)[list addObject:cls];}
        classes=list;
    });
    NSMutableArray<CALayer *> *queue=[NSMutableArray arrayWithObject:root];
    for(NSUInteger i=0;i<queue.count && i<1500;i++) {
        CALayer *layer=queue[i];
        if(layer.hidden || layer.opacity<.01)continue;
        id delegate=layer.delegate;
        if([delegate isKindOfClass:UIView.class] && WXGIsPluginView(delegate))continue;
        BOOL media=NO;
        for(Class cls in classes)if([layer isKindOfClass:cls]){media=YES;break;}
        if(media){[out addObject:[NSValue valueWithCGRect:[source.layer convertRect:layer.bounds fromLayer:layer]]];continue;}
        if(layer.sublayers.count)[queue addObjectsFromArray:layer.sublayers];
    }
}
// The outermost plugin view between a glass and the source (hidden while the
// source is rendered), nil when the glass is not inside it.
static UIView *WXGCalmPluginAncestor(UIView *view,UIView *source) {
    UIView *outermost=nil;
    for(UIView *v=view;v;v=v.superview) {
        if(v==source)return outermost;
        if(WXGIsPluginView(v))outermost=v;
    }
    return nil;
}
- (void)measure {
    if(!WXGCalmStates)WXGCalmStates=[NSMapTable weakToStrongObjectsMapTable];
    NSArray<WXGGlassView *> *all=WXGCalmGlasses.allObjects;
    NSMapTable<UIView *,NSMutableArray<WXGGlassView *> *> *groups=[NSMapTable strongToStrongObjectsMapTable];
    for(WXGGlassView *glass in all) {
        if(![self measures:glass])continue;
        UIView *source=glass.sourceView?:glass.window.rootViewController.view;
        if(!source.window || source.window!=glass.window)continue;
        NSMutableArray *list=[groups objectForKey:source];
        if(!list){list=[NSMutableArray array];[groups setObject:list forKey:source];}
        [list addObject:glass];
    }
    WXGConfig *c=WXGConfig.shared;
    for(UIView *source in groups.keyEnumerator.allObjects) {
        NSArray<WXGGlassView *> *glasses=[groups objectForKey:source];
        CGRect bounds=source.bounds,unionRect=CGRectNull;
        NSMutableArray<NSValue *> *rects=[NSMutableArray array];
        for(WXGGlassView *glass in glasses) {
            CGRect material=CGRectIsEmpty(glass.glassRect)?glass.bounds:glass.glassRect;
            CGRect r=CGRectIntersection(CGRectInset([glass convertRect:material toView:source],-6,-6),bounds);
            [rects addObject:[NSValue valueWithCGRect:r]];
            if(!CGRectIsNull(r) && !CGRectIsEmpty(r))unionRect=CGRectUnion(unionRect,r);
        }
        if(CGRectIsNull(unionRect) || CGRectIsEmpty(unionRect))continue;
        CGFloat scale=.25;
        if(unionRect.size.width*scale>512 || unionRect.size.height*scale>512)scale=512/MAX(unionRect.size.width,unionRect.size.height);
        size_t width=(size_t)MAX(1,ceil(unionRect.size.width*scale)),height=(size_t)MAX(1,ceil(unionRect.size.height*scale));
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx=CGBitmapContextCreate(NULL,width,height,8,width*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        if(!ctx)continue;
        // What shows where the page paints nothing: its window's colour.
        UIColor *base=UIColor.systemBackgroundColor;
        for(UIColor *candidate in @[source.backgroundColor?:UIColor.clearColor,source.window.backgroundColor?:UIColor.clearColor])
            if(CGColorGetAlpha([candidate resolvedColorWithTraitCollection:source.traitCollection].CGColor)>.01){base=candidate;break;}
        base=[base resolvedColorWithTraitCollection:source.traitCollection];
        CGFloat br=1,bg=1,bb=1,ba=1;[base getRed:&br green:&bg blue:&bb alpha:&ba];
        CGContextSetRGBFillColor(ctx,br,bg,bb,1);CGContextFillRect(ctx,CGRectMake(0,0,width,height));
        CGContextTranslateCTM(ctx,0,height);CGContextScaleCTM(ctx,scale,-scale);   // UIKit coordinates
        CGContextTranslateCTM(ctx,-unionRect.origin.x,-unionRect.origin.y);
        // The plugin's own views (any glass's) are not background.
        NSMutableSet<UIView *> *hide=[NSMutableSet set];
        for(WXGGlassView *glass in all)if(glass.window==source.window) {
            UIView *ancestor=WXGCalmPluginAncestor(glass,source);
            if(ancestor && !ancestor.layer.hidden)[hide addObject:ancestor];
        }
        [CATransaction begin];[CATransaction setDisableActions:YES];
        for(UIView *v in hide)v.layer.hidden=YES;
        @try {[source.layer renderInContext:ctx];}
        @catch(__unused NSException *error) {}
        for(UIView *v in hide)v.layer.hidden=NO;
        [CATransaction commit];
        ++_renders;
        NSMutableArray<NSValue *> *media=[NSMutableArray array];
        WXGCalmMediaRects(source.layer,source,media);
        CFTimeInterval now=CACurrentMediaTime();
        const uint8_t *pixels=CGBitmapContextGetData(ctx);size_t stride=CGBitmapContextGetBytesPerRow(ctx);
        for(NSUInteger i=0;i<glasses.count;i++) {
            WXGGlassView *glass=glasses[i];CGRect r=rects[i].CGRectValue;
            if(CGRectIsNull(r) || CGRectIsEmpty(r))continue;
            int x0=(int)floor((r.origin.x-unionRect.origin.x)*scale),y0=(int)floor((r.origin.y-unionRect.origin.y)*scale);
            int x1=(int)ceil((CGRectGetMaxX(r)-unionRect.origin.x)*scale),y1=(int)ceil((CGRectGetMaxY(r)-unionRect.origin.y)*scale);
            x0=MAX(0,x0);y0=MAX(0,y0);x1=MIN((int)width,x1);y1=MIN((int)height,y1);
            double sigma=WXGCalmSigma(pixels,stride,x0,y0,x1,y1);
            BOOL overMedia=NO;
            for(NSValue *value in media)if(CGRectIntersectsRect(value.CGRectValue,r)){overMedia=YES;break;}
            if(overMedia)sigma=1;   // video / Metal behind: never calm
            WXGCalmState *state=[WXGCalmStates objectForKey:glass];
            // A glass reused on another page, or back after a while, starts
            // from its new measurement (no easing from the old page's value).
            BOOL fresh=!state || state.source!=source || now-state.measuredAt>MAX(1.,_interval*3);
            if(!state){state=[WXGCalmState new];[WXGCalmStates setObject:state forKey:glass];}
            state.source=source;state.measuredAt=now;state.media=overMedia;
            state.sigma=sigma;state.target=WXGCalmTarget(sigma,c.calmThreshold,c.calmRange);state.measured=YES;
            state.rect=[source convertRect:r toView:nil];
            glass.calmFactor=WXGCalmStep(glass.calmFactor,state.target,fresh,.45);
        }
        CGContextRelease(ctx);
    }
}
- (NSDictionary *)evidence {
    NSMutableArray *samples=[NSMutableArray array];
    for(WXGGlassView *glass in WXGCalmGlasses.allObjects) {
        WXGCalmState *state=[WXGCalmStates objectForKey:glass];
        if(!state || ![self measures:glass] || samples.count>=12)continue;
        [samples addObject:@{@"rect":NSStringFromCGRect(state.rect),@"spread":@(round(state.sigma*10000)/10000),
                             @"target":@(round(state.target*1000)/1000),@"calm":@(round(glass.calmFactor*1000)/1000),@"media":@(state.media),
                             @"scope":glass.dockSurface?@"dock":@"other"}];
    }
    WXGConfig *c=WXGConfig.shared;
    return @{@"enabled":@(c.calmMaterialEnabled),@"running":@(_timer!=nil),@"interval":@(_interval),@"renders":@(_renders),@"skips":@(_skips),
             @"lastMS":@(round(_lastMS*100)/100),@"averageMS":@(round(_averageMS*100)/100),@"maxMS":@(round(_maxMS*100)/100),
             @"threshold":@(c.calmThreshold),@"range":@(c.calmRange),@"samples":samples};
}
@end

void WXGCalmApplyPreferences(void) {[WXGCalmMonitor.shared apply];}
NSDictionary *WXGCalmEvidence(void) {return [WXGCalmMonitor.shared evidence];}
NSString *WXGCalmSummaryText(void) {
    NSDictionary *e=WXGCalmEvidence();
    if(![e[@"enabled"] boolValue])return @"“平稳背景时加强材质”没有打开。";
    NSArray *samples=e[@"samples"];
    if(!samples.count)return @"还没有测量结果：回到有玻璃的页面停一下再看（设置页的卡片不测量）。";
    NSMutableString *text=[NSMutableString stringWithFormat:@"判定阈值 %.3f，过渡范围 %.3f；每次测量约 %.1f ms，间隔 %.1f 秒。\n\n",
        [e[@"threshold"] doubleValue],[e[@"range"] doubleValue],[e[@"averageMS"] doubleValue],[e[@"interval"] doubleValue]];
    CGFloat height=UIScreen.mainScreen.bounds.size.height;
    for(NSDictionary *s in samples) {
        CGRect r=CGRectFromString(s[@"rect"]);
        NSString *where=CGRectGetMidY(r)<height*.25?@"顶部":CGRectGetMidY(r)>height*.75?@"底部":@"中部";
        [text appendFormat:@"%@%@（x %.0f）：变化程度 %.3f → 平稳 %.0f%%\n",where,[s[@"scope"] isEqual:@"dock"]?@"底栏":@"玻璃",CGRectGetMinX(r),
            [s[@"spread"] doubleValue],[s[@"calm"] doubleValue]*100];
    }
    [text appendString:@"\n变化程度：玻璃后面那一块背景缩小后颜色的标准差（0 是纯色，文字页一般零点零几，照片和壁纸 0.1 以上）。低于阈值算平稳，用“平稳时材质遮盖”；高于阈值加过渡范围用原来的材质遮盖；中间平滑过渡。"];
    return text;
}
