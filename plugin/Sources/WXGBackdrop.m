#import "WXGIntegration.h"
#import "WXGRenderPolicy.h"
#import "WXGBackdropROI.h"
#import "WXGBackdropTraversal.h"
#import "WXGMotionPrediction.h"

@interface WXGBackdropSample ()
@property(nonatomic,strong) id<MTLTexture> texture;
@property(nonatomic,weak) UIView *coordinateView;
@property(nonatomic,strong) id<MTLBuffer> pixels;
@property(nonatomic) CGContextRef context;
@property(nonatomic) CGRect rect;
@property(nonatomic) NSUInteger revision,leases,width,height,stride;
@property(nonatomic) CGFloat scale,toneLevel;
@property(nonatomic) CFTimeInterval capturedAt;
@property(nonatomic) BOOL requiresUpload;
@property(nonatomic) WXGROISet coverage;
@property(nonatomic) BOOL modelTree;
@end
@implementation WXGBackdropSample
- (void)acquireLease {NSCAssert(NSThread.isMainThread,@"sample lease thread");++_leases;}
- (void)releaseLease {NSCAssert(NSThread.isMainThread,@"sample lease thread");NSCAssert(_leases>0,@"unbalanced sample lease");if(_leases)--_leases;}
- (void)dealloc {if(_context)CGContextRelease(_context);}
@end
@class WXGBackdropRegion;
@interface WXGBackdropConsumer : NSObject
@property(nonatomic,weak) WXGBackdropRegion *region;
@property(nonatomic,strong) WXGBackdropSample *sample;
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic) CGFloat copyScale;
@property(nonatomic) CGSize canvasPixels;
@property(nonatomic) WXGROIRect canvas,footprint;
// FIX19: the same glass mapped through MODEL layers, used with model-tree samples.
@property(nonatomic) CGAffineTransform modelTransform;
@property(nonatomic) WXGROIRect modelCanvas,modelFootprint;
@property(nonatomic) BOOL hasModel;
// FIX22: an ancestor of this glass is animating; its on-screen position is the
// presentation (predicted) one even when the background is the model tree.
@property(nonatomic) BOOL animated;
@end
static void WXGUseModelMapping(WXGBackdropConsumer *consumer) {
    if(!consumer.hasModel)return;
    consumer.transform=consumer.modelTransform;consumer.canvas=consumer.modelCanvas;consumer.footprint=consumer.modelFootprint;
}
@implementation WXGBackdropConsumer
@end
@interface WXGBackdropRegion : NSObject
@property(nonatomic,weak) UIView *source;
@property(nonatomic) CGRect requestedRect;
@property(nonatomic,strong) WXGBackdropSample *sample;
@property(nonatomic,strong) NSMutableArray<WXGBackdropSample *> *pool;
@property(nonatomic,copy) NSArray<UIView *> *exclusions;
@property(nonatomic,strong) NSMutableArray<WXGBackdropConsumer *> *consumers;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *slowBranches;
@property(nonatomic) WXGROISet requestedCoverage;
@property(nonatomic) NSUInteger presentationExclusions,epoch,captures,branches,fallbacks,busySkips,coverageRefreshes,coverageRejects,culledViews,unsplitExclusions,spatialSplits,atomicGuards,forcedSplitPaintApproximations;
@property(nonatomic) NSUInteger layerReads,nativeReads,inspectedLayers;
// FIX16 main-thread budget and animation-aware splitting.
@property(nonatomic) NSUInteger budgetHolds,animationSplits;
// FIX19 model-tree (FIX4) read and its gates.
@property(nonatomic) NSUInteger modelReads,presentationReads,animationHolds,consecutiveHolds,specialFallbacks,modelVisited,modelPruned;
@property(nonatomic) BOOL consumerAnimated,consumerFresh;
@property(nonatomic,copy) NSString *lastPath;
// FIX21: forced reads for glass that has no frame (e.g. resized by the keyboard).
@property(nonatomic) BOOL consumerNeedsFrame;
@property(nonatomic) NSUInteger forcedFrameReads,forcedStreak;
@property(nonatomic,strong) UIColor *baseFill;
@property(nonatomic) NSUInteger substitutedLayers,substitutionReads;
@property(nonatomic) double costAverage,shareReadMS,measuredShare;
@property(nonatomic) CFTimeInterval lastRead,shareWindowStart;
@property(nonatomic) CFTimeInterval captured,attempted,firstCapture;
@property(nonatomic) CGFloat scale;
@property(nonatomic) double milliseconds,intervalMS,fillMS,hierarchyMS,layerMS,flushMS,uploadMS,nativeReadArea;
@end
@implementation WXGBackdropRegion
@end
static NSMapTable<UIView *,WXGBackdropRegion *> *WXGRegions;
static NSMapTable<WXGGlassView *,WXGBackdropConsumer *> *WXGConsumers;
static NSHashTable<WXGGlassView *> *WXGRegistered;
static NSUInteger WXGRevision,WXGCaptures,WXGFailures,WXGSceneEpoch=1,WXGCaptureDepth;
static NSUInteger WXGVisited,WXGBranches,WXGFallbacks,WXGBatch;
static double WXGLastCost,WXGMaxCost;
static CFTimeInterval WXGLastFrame=-1;
static WXGROIRect WXGROIFromCGRect(CGRect r) {return (WXGROIRect){r.origin.x,r.origin.y,r.size.width,r.size.height};}
static CGRect WXGCGRectFromROI(WXGROIRect r) {return CGRectMake(r.x,r.y,r.w,r.h);}
static CGFloat WXGConsumerScale(WXGGlassView *glass) {return WXGCaptureScale(glass.window.screen.scale?:UIScreen.mainScreen.scale);}
static CGSize WXGConsumerCanvas(WXGGlassView *glass,CGFloat scale) {
    return CGSizeMake(MAX(1,round(glass.bounds.size.width*scale)),MAX(1,round(glass.bounds.size.height*scale)));
}
BOOL WXGBackdropCaptureInProgress(void) {return WXGCaptureDepth>0;}
void WXGRegisterBackdropView(WXGGlassView *view) {
    if(!WXGRegistered)WXGRegistered=[NSHashTable weakObjectsHashTable];[WXGRegistered addObject:view];
}
UIView *WXGContentSourceForView(UIView *view) {
    for(UIResponder *r=view;r;r=r.nextResponder)if([r isKindOfClass:UIViewController.class]) {
        UIViewController *vc=(id)r;
        if(![vc isKindOfClass:UINavigationController.class] && ![vc isKindOfClass:UITabBarController.class] &&
           vc.isViewLoaded && ![NSStringFromClass(vc.class) hasPrefix:@"WXG"] && vc.view!=view.window)return vc.view;
    }
    return view.window.rootViewController.view;
}
CGAffineTransform WXGPresentedTransform(UIView *view,UIView *source) {
    if(!view || !source)return CGAffineTransformIdentity;
    CALayer *a=view.layer.presentationLayer,*b=source.layer.presentationLayer;
    // Never mix a presentation layer with a model layer. New mounts use their
    // model-local basis composed with the nearest committed native ancestor.
    UIView *anchor=view;CGAffineTransform local=CGAffineTransformIdentity;
    if(!a && b) {
        while(anchor.superview && !anchor.layer.presentationLayer)anchor=anchor.superview;
        if(anchor.layer.presentationLayer) {
            CGPoint o=[view convertPoint:CGPointZero toView:anchor];
            CGPoint x=[view convertPoint:CGPointMake(1,0) toView:anchor],y=[view convertPoint:CGPointMake(0,1) toView:anchor];
            local=CGAffineTransformMake(x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y);a=anchor.layer.presentationLayer;
        }
    }
    if(!a || !b){a=view.layer;b=source.layer;local=CGAffineTransformIdentity;}
    CGPoint q=CGPointApplyAffineTransform(CGPointZero,local);
    CGPoint qx=CGPointApplyAffineTransform(CGPointMake(1,0),local),qy=CGPointApplyAffineTransform(CGPointMake(0,1),local);
    CGPoint o,x,y;
    if(view.window && source.window && view.window!=source.window) {
        CALayer *aw=a==view.layer?view.window.layer:(view.window.layer.presentationLayer?:view.window.layer);
        CALayer *bw=b==source.layer?source.window.layer:(source.window.layer.presentationLayer?:source.window.layer);
        CGPoint (^bridge)(CGPoint)=^CGPoint(CGPoint point){
            CGPoint screen=[a convertPoint:point toLayer:aw];
            CGPoint destination=[source.window convertPoint:screen fromWindow:view.window];
            return [bw convertPoint:destination toLayer:b];
        };
        o=bridge(q);x=bridge(qx);y=bridge(qy);
    }else{o=[a convertPoint:q toLayer:b];x=[a convertPoint:qx toLayer:b];y=[a convertPoint:qy toLayer:b];}
    return CGAffineTransformMake(x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y);
}
CGRect WXGPresentedBounds(UIView *view,UIView *source) {
    if(!view || !source)return CGRectNull;
    CGRect bounds=view.layer.presentationLayer?((CALayer *)view.layer.presentationLayer).bounds:view.bounds;
    return CGRectApplyAffineTransform(bounds,WXGPresentedTransform(view,source));
}
static UIColor *WXGBaseFill(UIView *source) {
    UITraitCollection *traits=source.traitCollection;
    for(UIView *view=source;view;view=view.superview) {
        UIColor *color=[view.backgroundColor resolvedColorWithTraitCollection:traits];
        if(color && CGColorGetAlpha(color.CGColor)>=.99)return color;
    }
    return traits.userInterfaceStyle==UIUserInterfaceStyleDark?UIColor.blackColor:UIColor.whiteColor;
}
// FIX19: the model-layer counterpart of WXGPresentedTransform (bounds coordinates).
static CGAffineTransform WXGModelTransform(UIView *view,UIView *source) {
    if(!view || !source)return CGAffineTransformIdentity;
    CGPoint o=[view convertPoint:CGPointZero toView:source];
    CGPoint x=[view convertPoint:CGPointMake(1,0) toView:source],y=[view convertPoint:CGPointMake(0,1) toView:source];
    return CGAffineTransformMake(x.x-o.x,x.y-o.y,y.x-o.x,y.y-o.y,o.x,o.y);
}
BOOL WXGPresentedVisible(UIView *view) {
    if(!view.window)return NO;
    CGFloat alpha=1;
    for(UIView *v=view;v;v=v.superview) {
        CALayer *layer=v.layer.presentationLayer?:v.layer;
        if(layer.hidden)return NO;alpha*=layer.opacity;if(alpha<.001)return NO;
    }
    return CGRectIntersectsRect(WXGPresentedBounds(view,view.window),view.window.bounds);
}
void WXGInvalidateSharedBackdrop(void) {++WXGSceneEpoch;}

// FIX17 display-time prediction. The read happens at t; the glass drawable is
// seen at D. UIKit push/pop/keyboard animations are evaluated by the render
// server AT D, so a plain read lags them by D - t (25-80 pt during a push).
// D is estimated from measured capture-to-presentation latency, and every
// transform is advanced from ITS OWN evaluation time, which also removes the
// within-read skew between branches drawn early and late in a long read.
static double WXGPresentLatency;
static CFTimeInterval WXGFrameTarget,WXGDisplayEstimate,WXGLastReadTime;
static double WXGModelLead,WXGLastAnimationLead;
static BOOL WXGFrameInteractive,WXGFrameTransition;
static NSMapTable<UIView *,NSValue *> *WXGMotion;
static NSUInteger WXGPredictedViews;
static double WXGMaxPredictShift;
void WXGBackdropSetFrameTiming(CFTimeInterval targetTimestamp,BOOL interactive,BOOL transition) {
    WXGFrameTarget=targetTimestamp;WXGFrameInteractive=interactive;WXGFrameTransition=transition;
}
void WXGBackdropRecordPresentationLatency(double seconds) {
    if(!isfinite(seconds) || seconds<=0 || seconds>.2)return;
    WXGPresentLatency=WXGPresentLatency>0?WXGPresentLatency*.8+seconds*.2:seconds;
}
static CGAffineTransform WXGPredictTransform(UIView *view,UIView *source,CGAffineTransform presented,CFTimeInterval evaluated) {
    if(!view || !source || WXGDisplayEstimate<=0)return presented;
    if(!WXGMotion || WXGMotion.count>4000)WXGMotion=[NSMapTable weakToStrongObjectsMapTable];
    CGPoint model=[view convertPoint:CGPointZero toView:source];
    WXGMotionSample now={presented.tx,presented.ty,model.x,model.y,evaluated};
    WXGMotionTrack track={0};NSValue *stored=[WXGMotion objectForKey:view];
    if(stored)[stored getValue:&track size:sizeof(track)];
    double dx=0,dy=0;
    if(track.count>0) {
        double lead=WXGDisplayEstimate-evaluated;WXGLastAnimationLead=lead;
        WXGMotionPredict2(WXGMotionOlder(track,evaluated),WXGMotionBase(track,evaluated),now,lead,WXGModelLead,WXGFrameInteractive,160,&dx,&dy);
    }
    track=WXGMotionRecord(track,now);
    [WXGMotion setObject:[NSValue valueWithBytes:&track objCType:@encode(WXGMotionTrack)] forKey:view];
    if(dx==0 && dy==0)return presented;
    ++WXGPredictedViews;WXGMaxPredictShift=MAX(WXGMaxPredictShift,hypot(dx,dy));
    presented.tx+=dx;presented.ty+=dy;
    return presented;
}

static WXGBackdropSample *WXGNewSample(CGRect rect,CGFloat scale) {
    NSUInteger width=(NSUInteger)ceil(rect.size.width*scale),height=(NSUInteger)ceil(rect.size.height*scale);
    if(!width || !height || width>4096 || height>4096)return nil;
    WXGBackdropSample *s=[WXGBackdropSample new];s.rect=rect;s.scale=scale;s.width=width;s.height=height;
    id<MTLDevice> gpu=WXGSharedDevice();
    NSUInteger alignment=MAX((NSUInteger)64,[gpu minimumLinearTextureAlignmentForPixelFormat:MTLPixelFormatBGRA8Unorm]);
    s.stride=((width*4+alignment-1)/alignment)*alignment;
    s.pixels=[gpu newBufferWithLength:s.stride*height options:MTLResourceStorageModeShared];
    if(!s.pixels)return nil;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    s.texture=[s.pixels newTextureWithDescriptor:d offset:0 bytesPerRow:s.stride];
    if(!s.texture){s.texture=[gpu newTextureWithDescriptor:d];s.requiresUpload=YES;}
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    s.context=CGBitmapContextCreate(s.pixels.contents,width,height,8,s.stride,color,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(color);return s.texture && s.context?s:nil;
}
static BOOL WXGNativeChrome(UIView *view) {
    NSString *n=NSStringFromClass(view.class);
    return [view isKindOfClass:UINavigationBar.class] || [view isKindOfClass:UITabBar.class] ||
        [n isEqual:@"MMNewMsgContentNavBar"] || [n isEqual:@"FakeNavigationBar"] ||
        [n isEqual:@"MMInputToolView"] || [n isEqual:@"InputToolViewBar"];
}
static BOOL WXGExcludedPaintRoot(UIView *view,NSSet *blocked) {
    return [blocked containsObject:view] || WXGIsPluginView(view) || WXGNativeChrome(view) ||
        [view.layer.mask.name isEqualToString:@"wxg.conceal"];
}
static void WXGDrawContainerPaint(UIView *view,CGContextRef ctx) {
    // Split containers normally carry just a background. Do not manufacture a
    // detached copy of native drawing/Metal/video layers: it loses their pixels.
    CALayer *layer=view.layer.presentationLayer?:view.layer;
    if(layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor)>0) {
        CGContextSetFillColorWithColor(ctx,layer.backgroundColor);
        CGFloat radius=MIN(layer.cornerRadius,MIN(layer.bounds.size.width,layer.bounds.size.height)*.5);
        CGPathRef path=CGPathCreateWithRoundedRect(layer.bounds,radius,radius,NULL);
        CGContextAddPath(ctx,path);CGContextFillPath(ctx);CGPathRelease(path);
    }
    if(layer.contents && CFGetTypeID((__bridge CFTypeRef)layer.contents)==CGImageGetTypeID()) {
        CGImageRef cg=(__bridge CGImageRef)layer.contents;
        UIImage *image=[UIImage imageWithCGImage:cg scale:MAX(1,layer.contentsScale) orientation:UIImageOrientationUp];
        [image drawInRect:layer.bounds];
    }
}
// Use the actual current layer order. UIKit's UITableView can reorder CALayers
// without rewriting subviews; FIX14 treated this as a whole-screen read guard.
// An unowned layer still prevents optional splitting: its paint must survive.
static NSArray<UIView *> *WXGOrderedNativeChildren(UIView *view,BOOL *exact) {
    NSArray<UIView *> *views=view.subviews;NSArray<CALayer *> *layers=view.layer.sublayers;
    *exact=layers.count==views.count;
    if(!*exact || !views.count)return views;
    NSMutableArray<UIView *> *ordered=[NSMutableArray arrayWithCapacity:views.count];
    BOOL hasZ=NO;
    for(CALayer *layer in layers) {
        id delegate=layer.delegate;UIView *child=nil;
        if([delegate isKindOfClass:UIView.class] && ((UIView *)delegate).superview==view && ((UIView *)delegate).layer==layer)child=delegate;
        else for(UIView *candidate in views)if(candidate.layer==layer){child=candidate;break;}
        if(!child){*exact=NO;return views;}
        [ordered addObject:child];
        CALayer *shown=layer.presentationLayer?:layer;
        if(shown.zPosition!=0)hasZ=YES;
    }
    if(!hasZ)return ordered;
    return [ordered sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a,UIView *b){
        CALayer *x=a.layer.presentationLayer?:a.layer,*y=b.layer.presentationLayer?:b.layer;
        return (NSComparisonResult)WXGBackdropCompareZ(x.zPosition,y.zPosition);
    }];
}
// Optional spatial splitting is only for geometry whose self-paint and clip we
// can reproduce. All other subtrees remain atomic, but ordinary layer backing
// stores can now be read without a synchronous UIKit compositor snapshot.
static NSString *WXGContainerSplitGuard(UIView *view,BOOL exactChildOrder) {
    if(!view.subviews.count)return @"leaf";
    if([view isKindOfClass:UIVisualEffectView.class] || [view isKindOfClass:UIImageView.class] ||
       [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIControl.class])return @"nativeMediaOrControl";
    CALayer *layer=view.layer,*shown=layer.presentationLayer?:layer;
    if(layer.class!=CALayer.class)return @"customLayerClass";
    if(shown.mask)return @"mask";
    if(shown.contents)return @"ownContents";
    if(shown.borderWidth>0)return @"border";
    if(shown.shadowOpacity>0)return @"shadow";
    if(!CATransform3DIsAffine(shown.transform) || !CATransform3DIsIdentity(shown.sublayerTransform))return @"layerTransform";
    if(shown.filters.count || shown.backgroundFilters.count || shown.compositingFilter)return @"layerFilter";
    // UIView drawRect overrides have their own backing store, which is not
    // necessarily exposed as layer.contents. Do not replace that paint by a
    // plain background. Public UIKit scroll containers provide child content.
    Class base=UIView.class;
    if([view isKindOfClass:UITableView.class])base=UITableView.class;
    else if([view isKindOfClass:UICollectionView.class])base=UICollectionView.class;
    else if([view isKindOfClass:UIScrollView.class])base=UIScrollView.class;
    if(class_getMethodImplementation(view.class,@selector(drawRect:))!=class_getMethodImplementation(base,@selector(drawRect:)))return @"customDrawRect";
    if(!exactChildOrder)return @"nonViewSublayer";
    // CA continuous/individually rounded corners are not circular CG paths.
    // Keep their native subtree compositor rather than approximate the clip.
    if(shown.cornerRadius>0 && (shown.maskedCorners!=15 || ![shown.cornerCurve isEqual:kCACornerCurveCircular]))return @"nonCircularCorners";
    return nil;
}
// FIX16: classify with MODEL layers only. -presentationLayer builds a copy per
// call and FIX15 called it for every layer of every branch on each read; class,
// contents type, filters and 3-D flags are identical in the presentation copy.
//
// UIKit text/drawRect views keep their pixels in a CABackingStore, not a
// CGImage. FIX15 sent every such branch (practically every chat cell, label
// and title) to drawViewHierarchy, which costs a native compositor round trip
// of roughly 3 ms plus a per-area cost even for a 130x40 pt view (FIX14 log).
// renderInContext draws backing stores directly, so they stay on the CPU path.
static BOOL WXGRasterizableContents(id contents) {
    if(!contents)return YES;
    CFTypeID type=CFGetTypeID((__bridge CFTypeRef)contents);
    if(type==CGImageGetTypeID())return YES;
    static CFTypeID backingStore=0;static NSMutableSet<NSNumber *> *rejected;
    if(backingStore && type==backingStore)return YES;
    if([rejected containsObject:@(type)])return NO;
    NSString *name=CFBridgingRelease(CFCopyTypeIDDescription(type));
    if([name isEqualToString:@"CABackingStore"] || [NSStringFromClass(object_getClass(contents)) isEqualToString:@"CABackingStore"]) {
        backingStore=type;return YES;
    }
    if(!rejected)rejected=[NSMutableSet set];
    if(rejected.count<32)[rejected addObject:@(type)];
    return NO;
}
// Render-server-only content (video, Metal/GL, backdrops, portals, remote or
// hosted layers, emitters, replicators, tiled layers) cannot be flattened by
// renderInContext. Everything else that is an ordinary 2-D layer subclass,
// including app-defined async text/image layers, is drawn from its contents.
static NSString *WXGSpecialLayerClass(Class cls) {
    static NSMapTable *cache;static NSArray<NSString *> *tokens;
    if(!cache) {
        cache=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsOpaquePersonality
                                    valueOptions:NSPointerFunctionsStrongMemory];
        tokens=@[@"Backdrop",@"Portal",@"Metal",@"EAGL",@"OpenGL",@"Player",@"SampleBuffer",@"Video",@"Camera",@"Capture",
                 @"Emitter",@"Replicator",@"TransformLayer",@"LayerHost",@"Remote",@"Plugin",@"Tiled",@"SCN",@"SpriteKit",
                 @"Filter",@"Effect",@"Replicant"];
    }
    NSString *hit=[cache objectForKey:cls];
    if(hit)return hit.length?hit:nil;
    NSString *reason=@"";
    for(Class c=cls;c && c!=CALayer.class && !reason.length;c=class_getSuperclass(c)) {
        NSString *name=NSStringFromClass(c);
        if([name hasPrefix:@"WK"]){reason=[@"specialLayer:" stringByAppendingString:name];break;}
        for(NSString *token in tokens)if([name rangeOfString:token].location!=NSNotFound) {
            reason=[@"specialLayer:" stringByAppendingString:name];break;
        }
    }
    [cache setObject:reason forKey:cls];
    return reason.length?reason:nil;
}
// Inspect the LIVE subtree on each read; never cache an eligibility result for
// a layer, because a player/effect can be attached later. Only the per-class
// answer is cached. Remaining special branches keep drawViewHierarchy.
static NSString *WXGLayerRasterGuard(CALayer *layer,NSUInteger depth,NSUInteger *visited) {
    if(++*visited>768 || depth>24)return @"layerTreeBudget";
    if(layer.hidden || layer.opacity<.001)return nil;
    NSString *special=WXGSpecialLayerClass(layer.class);if(special)return special;
    if(!WXGRasterizableContents(layer.contents))return @"nonImageContents";
    // FIX21: colour filters and blend modes (e.g. inside WeChat's home-list
    // cells) are drawn unfiltered: a tiny tint difference under a blurred glass,
    // versus a ~3 ms native compositor read per cell. Only backdrop filters,
    // which sample the screen behind them, still need the compositor.
    if(layer.backgroundFilters.count)return @"layerBackdropFilter";
    if(!CATransform3DIsAffine(layer.transform) || !CATransform3DIsAffine(layer.sublayerTransform))return @"layer3D";
    // The branch root is drawn from its presentation copy. An animation
    // running on a layer BELOW the root is the case where a flattened copy can
    // show the animation's end state instead of what is on screen (inserted
    // rows, cross-fades, spinners). Such branches are split or read natively.
    if(depth>0 && layer.animationKeys.count)return @"animatingSublayer";
    if(layer.mask){NSString *guard=WXGLayerRasterGuard(layer.mask,depth+1,visited);if(guard)return guard;}
    for(CALayer *child in layer.sublayers){NSString *guard=WXGLayerRasterGuard(child,depth+1,visited);if(guard)return guard;}
    return nil;
}
static BOOL WXGNavigationWrapper(UIView *view) {
    NSString *n=NSStringFromClass(view.class);
    return [n isEqual:@"UINavigationTransitionView"] || [n isEqual:@"UITransitionView"] ||
      [n isEqual:@"UILayoutContainerView"] || [n isEqual:@"UIViewControllerWrapperView"] ||
      [n isEqual:@"_UIParallaxDimmingView"] || [n isEqual:@"MMUIHookView"];
}
static void WXGClipPresentedContainer(CGContextRef ctx,CALayer *shown,CGAffineTransform transform) {
    CGFloat radius=MIN(shown.cornerRadius,MIN(shown.bounds.size.width,shown.bounds.size.height)*.5);
    CGPathRef local=CGPathCreateWithRoundedRect(shown.bounds,radius,radius,NULL);
    CGPathRef path=CGPathCreateCopyByTransformingPath(local,&transform);
    CGContextAddPath(ctx,path);CGContextClip(ctx);CGPathRelease(path);CGPathRelease(local);
}
// Ordinary scene wrappers and large scroll views are traversed BEFORE UIKit is
// asked for pixels. Reading one full UINavigationTransitionView under a 19%
// CGContext clip still cost 35 ms on the supplied A18 Pro diagnostic.
static BOOL WXGDrawClean(UIView *view,UIView *source,const WXGROISet *coverage,NSSet *blocked,NSSet *split,
                        CGContextRef ctx,CGFloat inheritedAlpha,WXGBackdropRegion *region) {
    ++WXGVisited;
    if(WXGExcludedPaintRoot(view,blocked))return YES;
    CALayer *shown=view.layer.presentationLayer?:view.layer;
    if(shown.hidden || shown.opacity<.001)return YES;
    CFTimeInterval evaluated=CACurrentMediaTime();
    CGAffineTransform transform=WXGPredictTransform(view,source,WXGPresentedTransform(view,source),evaluated);
    CGRect rect=WXGCGRectFromROI(WXGBackdropTransformedBounds(WXGROIFromCGRect(shown.bounds),
        (WXGSourceTransform){transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty}));
    BOOL outside=!WXGROIIntersects(coverage,WXGROIFromCGRect(CGRectInset(rect,-12,-12)));
    BOOL externalLayers=view.layer.sublayers.count>view.subviews.count;
    BOOL plainLeaf=!view.subviews.count && !view.layer.sublayers.count && shown.shadowOpacity<=0;
    if(outside && (shown.masksToBounds || plainLeaf)){++region.culledViews;return YES;}
    // An unclipped custom layer can paint outside its UIView bounds. Keep that
    // native branch; only ordinary out-of-bounds containers may be traversed.
    BOOL required=[split containsObject:view] || (outside && view.subviews.count && !externalLayers);
    BOOL exactChildOrder=NO;NSArray<UIView *> *children=WXGOrderedNativeChildren(view,&exactChildOrder);
    NSString *guard=WXGContainerSplitGuard(view,exactChildOrder);BOOL safe=guard==nil;
    BOOL spatial=WXGBackdropNeedsSpatialSplit(WXGROIFromCGRect(rect),WXGROIArea(coverage,WXGROIFromCGRect(rect)),
                    source.bounds.size.width*source.bounds.size.height,view.subviews.count>0,safe,
                    [view isKindOfClass:UIScrollView.class],WXGNavigationWrapper(view));
    BOOL divided=required || spatial;
    if(spatial && !required)++region.spatialSplits;
    if(!safe && !required && view.subviews.count)++region.atomicGuards;
    if(required && !safe && !outside)++region.forcedSplitPaintApproximations;
    BOOL good=YES;
    NSString *rasterGuard=nil;NSUInteger inspected=0;
    if(!divided) {
        rasterGuard=WXGLayerRasterGuard(view.layer,0,&inspected);
        region.inspectedLayers+=inspected;
        // A safe container whose child is animating is split, so that child
        // becomes its own presentation-drawn branch instead of a native read.
        if(rasterGuard && safe && view.subviews.count && [rasterGuard isEqualToString:@"animatingSublayer"]) {
            divided=YES;++region.animationSplits;
        }
    }
    if(!divided) {
      CGContextSaveGState(ctx);
      @try {
        CGContextConcatCTM(ctx,transform);CGContextSetAlpha(ctx,inheritedAlpha);
        ++region.branches;++WXGBranches;
        CFTimeInterval branchStart=CACurrentMediaTime();
        if(!rasterGuard) {
            // renderInContext's root is bounds-local. The outer transform maps
            // native local coordinates (including scroll bounds.origin) to the
            // scene; offset the raster origin once, never twice.
            CGContextTranslateCTM(ctx,shown.bounds.origin.x,shown.bounds.origin.y);
            [shown renderInContext:ctx];good=YES;++region.layerReads;
        }else {
            good=[view drawViewHierarchyInRect:shown.bounds afterScreenUpdates:NO];
            ++region.nativeReads;region.nativeReadArea+=MAX(0,rect.size.width*rect.size.height);
        }
        double branchMS=(CACurrentMediaTime()-branchStart)*1000;
        if(rasterGuard)region.hierarchyMS+=branchMS;else region.layerMS+=branchMS;
        NSUInteger position=0;
        while(position<region.slowBranches.count && [region.slowBranches[position][@"milliseconds"] doubleValue]>=branchMS)++position;
        if(position<6) {
            [region.slowBranches insertObject:@{@"class":NSStringFromClass(view.class),@"rect":NSStringFromCGRect(rect),@"milliseconds":@(branchMS),@"success":@(good),@"atomicGuard":@(!safe),@"atomicReason":guard?:@"none",@"layerClass":NSStringFromClass(view.layer.class),@"backend":rasterGuard?@"nativeCompositor":@"currentLayer",@"rasterGuard":rasterGuard?:@"none",@"inspectedLayers":@(inspected),@"presentationLayer":@(shown!=view.layer)} atIndex:position];
            if(region.slowBranches.count>6)[region.slowBranches removeLastObject];
        }
        if(!good) {
            ++region.fallbacks;++WXGFallbacks;
            // A special renderer cannot be recovered by flattening a CALayer.
            // Retain the last valid publication only for an actual read failure,
            // and expose that failure in diagnostics.
        }
      }@finally {CGContextRestoreGState(ctx);}
      return good;
    }
    CGContextSaveGState(ctx);
    // Multiplying each child alpha would darken overlaps during native page
    // fades. Composite the split container as one transparency group instead.
    BOOL grouped=inheritedAlpha*shown.opacity<.999,beganGroup=NO;
    @try {
        if(shown.masksToBounds)WXGClipPresentedContainer(ctx,shown,transform);
        if(grouped){CGContextSetAlpha(ctx,inheritedAlpha*shown.opacity);CGContextBeginTransparencyLayer(ctx,NULL);beganGroup=YES;}
        CGFloat alpha=grouped?1:inheritedAlpha*shown.opacity;
        if(!outside) {
            CGContextSaveGState(ctx);
            @try {CGContextConcatCTM(ctx,transform);CGContextSetAlpha(ctx,alpha);WXGDrawContainerPaint(view,ctx);}
            @finally {CGContextRestoreGState(ctx);}
        }
        for(UIView *child in children)if(!WXGDrawClean(child,source,coverage,blocked,split,ctx,alpha,region))good=NO;
    }@finally {if(beganGroup)CGContextEndTransparencyLayer(ctx);CGContextRestoreGState(ctx);}
    return good;
}
// FIX19: FIX4's model-tree read. The MODEL tree is the state this display
// frame is about to commit; the presentation tree and the render server are a
// frame behind it for scrolling and layout. Plugin, excluded, native-chrome and
// off-ROI subtrees are hidden on the model only for one renderInContext and
// restored inside the same disabled-action transaction, so the commit never
// sees a change. While a Core Animation animation is in flight the model holds
// its END state (what made FIX4's layers look frozen/ahead), so those frames,
// and frames with render-server-only content, use the presentation path.
typedef struct { BOOL animated,fresh,special,overflow; NSUInteger visited; } WXGModelScan;
// Layer+key -> last frame time it was seen animating. An animation not seen
// in an earlier pass may not be committed yet, so its presentation value is
// still the end state: that frame is held (at most two in a row).
static NSMutableDictionary<NSString *,NSNumber *> *WXGAnimationSeen;
static CFTimeInterval WXGScanTime;
static void WXGScanLayerAnimations(CALayer *layer,WXGModelScan *scan) {
    NSArray<NSString *> *keys=layer.animationKeys;if(!keys.count)return;
    scan->animated=YES;
    if(!WXGAnimationSeen)WXGAnimationSeen=[NSMutableDictionary dictionary];
    for(NSString *key in keys) {
        NSString *identity=[NSString stringWithFormat:@"%p|%@",layer,key];
        if(!WXGAnimationSeen[identity])scan->fresh=YES;
        WXGAnimationSeen[identity]=@(WXGScanTime);
    }
}
static void WXGExpireAnimationHistory(void) {
    if(WXGAnimationSeen.count<256)return;
    NSMutableArray<NSString *> *old=[NSMutableArray array];
    [WXGAnimationSeen enumerateKeysAndObjectsUsingBlock:^(NSString *key,NSNumber *time,__unused BOOL *stop){
        if(WXGScanTime-time.doubleValue>1)[old addObject:key];
    }];
    [WXGAnimationSeen removeObjectsForKeys:old];
}
static BOOL WXGLayerNeedsCompositor(CALayer *layer) {
    if(WXGSpecialLayerClass(layer.class) || !WXGRasterizableContents(layer.contents))return YES;
    if(layer.backgroundFilters.count)return YES;
    return !CATransform3DIsAffine(layer.transform) || !CATransform3DIsAffine(layer.sublayerTransform);
}
static void WXGModelScanTree(UIView *view,UIView *source,const WXGROISet *coverage,NSSet *blocked,
                             NSMutableArray<CALayer *> *prune,NSMutableArray<CALayer *> *animated,NSMutableArray<UIView *> *excluded,WXGModelScan *scan,BOOL movingAncestor) {
    if(scan->overflow)return;
    if(++scan->visited>3000){scan->overflow=YES;return;}
    CALayer *layer=view.layer;
    if(view!=source && WXGExcludedPaintRoot(view,blocked)){
        [excluded addObject:view];
        if(!layer.hidden)[prune addObject:layer];
        return;
    }
    if(layer.hidden || layer.opacity<.001)return;
    // Model rects are END positions while an ancestor animates (a page sliding
    // out has an off-screen model frame), so such subtrees are never pruned
    // by geometry; the CG clip still limits what is drawn.
    BOOL moving=movingAncestor || layer.animationKeys.count>0;
    BOOL outside=NO;
    if(view!=source) {
        CGRect rect=[view convertRect:view.bounds toView:source];
        outside=!WXGROIIntersects(coverage,WXGROIFromCGRect(CGRectInset(rect,-12,-12)));
        // Non-clipping containers can draw children outside their bounds.
        if(outside && !moving && (view.clipsToBounds || !view.subviews.count)){[prune addObject:layer];return;}
        if(!outside || moving) {
            if(WXGLayerNeedsCompositor(layer))scan->special=YES;
            for(CALayer *sub in layer.sublayers)if(![sub.delegate isKindOfClass:UIView.class]) {
                if(WXGLayerNeedsCompositor(sub))scan->special=YES;
            }
        }
    }
    // Any traversed container may carry visible children into the ROI, so its
    // animation matters even when its own bounds are outside it.
    // Holds for not-yet-committed animations only when the layer is in the ROI.
    if(layer.animationKeys.count) {
        if(outside && !movingAncestor)scan->animated=YES;else WXGScanLayerAnimations(layer,scan);
        [animated addObject:layer];
    }
    for(UIView *child in view.subviews)WXGModelScanTree(child,source,coverage,blocked,prune,animated,excluded,scan,moving);
}
// FIX22: FIX4's model tree with in-flight animations placed where they are on
// screen. For one renderInContext each animating layer's model geometry is set
// to its presentation value, advanced to the display time, then restored in the
// same disabled-action transaction, so the commit never sees a change (FIX4
// already hides layers the same way). Without this the model holds the
// animation's END state: FIX4's frozen layers and the input box jumping from
// start to end during the keyboard animation.
@interface WXGLayerOverride : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic) CGPoint position;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CATransform3D transform;
@property(nonatomic) float opacity;
@end
@implementation WXGLayerOverride
@end
static NSMapTable<CALayer *,NSValue *> *WXGLayerMotion;
static CGPoint WXGPredictLayerPosition(CALayer *layer,CGPoint shown,CGPoint model,CFTimeInterval now) {
    if(WXGDisplayEstimate<=0)return shown;
    if(!WXGLayerMotion || WXGLayerMotion.count>2000)WXGLayerMotion=[NSMapTable weakToStrongObjectsMapTable];
    WXGMotionSample sample={shown.x,shown.y,model.x,model.y,now};
    WXGMotionTrack track={0};NSValue *stored=[WXGLayerMotion objectForKey:layer];
    if(stored)[stored getValue:&track size:sizeof(track)];
    double dx=0,dy=0;
    if(track.count>0)WXGMotionPredict2(WXGMotionOlder(track,now),WXGMotionBase(track,now),sample,WXGDisplayEstimate-now,0,
                                       WXGFrameInteractive,160,&dx,&dy);
    track=WXGMotionRecord(track,sample);
    [WXGLayerMotion setObject:[NSValue valueWithBytes:&track objCType:@encode(WXGMotionTrack)] forKey:layer];
    if(dx!=0 || dy!=0)++WXGPredictedViews;
    return CGPointMake(shown.x+dx,shown.y+dy);
}
static void WXGApplyPresentationOverrides(NSArray<CALayer *> *layers,NSMutableArray<WXGLayerOverride *> *saved) {
    CFTimeInterval now=CACurrentMediaTime();
    for(CALayer *layer in layers) {
        CALayer *shown=layer.presentationLayer;if(!shown)continue;
        WXGLayerOverride *o=[WXGLayerOverride new];
        o.layer=layer;o.position=layer.position;o.bounds=layer.bounds;o.transform=layer.transform;o.opacity=layer.opacity;
        [saved addObject:o];
        layer.position=WXGPredictLayerPosition(layer,shown.position,o.position,now);
        // The bounds ORIGIN follows (animated scroll offsets); the size stays,
        // because a size change would schedule an extra native layout.
        CGRect bounds=o.bounds;bounds.origin=shown.bounds.origin;
        if(!CGRectEqualToRect(bounds,o.bounds))layer.bounds=bounds;
        if(!CATransform3DEqualToTransform(shown.transform,o.transform))layer.transform=shown.transform;
        if(shown.opacity!=o.opacity)layer.opacity=shown.opacity;
    }
}
static void WXGRestoreOverrides(NSArray<WXGLayerOverride *> *saved) {
    for(WXGLayerOverride *o in saved.reverseObjectEnumerator) {
        CALayer *layer=o.layer;
        layer.position=o.position;
        if(!CGRectEqualToRect(layer.bounds,o.bounds))layer.bounds=o.bounds;
        if(!CATransform3DEqualToTransform(layer.transform,o.transform))layer.transform=o.transform;
        if(layer.opacity!=o.opacity)layer.opacity=o.opacity;
    }
}
static void WXGScanConsumerAncestors(WXGGlassView *glass,UIView *source,WXGModelScan *scan) {
    for(UIView *v=glass;v && v!=source.superview;v=v.superview)WXGScanLayerAnimations(v.layer,scan);
}
static void WXGCollectRemainingExclusions(UIView *view,NSSet *blocked,NSMutableArray<UIView *> *excluded) {
    for(UIView *child in view.subviews) {
        if(WXGExcludedPaintRoot(child,blocked)){[excluded addObject:child];continue;}
        if(!child.hidden)WXGCollectRemainingExclusions(child,blocked,excluded);
    }
}
static void WXGCaptureRegion(WXGBackdropRegion *r,NSSet *blocked,NSSet *split,CFTimeInterval frameTime) {
    UIView *source=r.source;if(!source.window)return;
    NSUInteger epoch=WXGSceneEpoch;
    CFTimeInterval begin=CACurrentMediaTime();r.attempted=frameTime;r.branches=r.fallbacks=r.culledViews=r.spatialSplits=r.atomicGuards=r.forcedSplitPaintApproximations=0;
    r.layerReads=r.nativeReads=r.inspectedLayers=0;
    r.fillMS=r.hierarchyMS=r.layerMS=r.flushMS=r.uploadMS=r.nativeReadArea=0;r.slowBranches=[NSMutableArray array];
    CGFloat scale=r.scale?:WXGBackdropInitialScale(source.window.screen.scale,source.window.screen.maximumFramesPerSecond);
    CGRect roi=r.requestedRect;WXGBackdropSample *sample=nil;
    // Geometry uses a screen-stable, padded atlas; keyboard travel does not
    // resize buffers every frame. All glass in this scene shares this one read.
    for(WXGBackdropSample *s in r.pool.copy)if(s.leases==0 && s!=r.sample) {
        if(CGSizeEqualToSize(s.rect.size,roi.size) && s.scale==scale){sample=s;break;}
        [r.pool removeObjectIdenticalTo:s];
    }
    if(!sample && r.pool.count<3){sample=WXGNewSample(roi,scale);if(sample)[r.pool addObject:sample];}
    if(!sample){++r.busySkips;r.milliseconds=(CACurrentMediaTime()-begin)*1000;return;}
    r.lastRead=frameTime;
    sample.rect=roi;sample.coordinateView=source;CGContextRef ctx=sample.context;BOOL good=NO,held=NO,modelPathUsed=NO;
    ++WXGCaptureDepth;CGContextSaveGState(ctx);UIGraphicsPushContext(ctx);
    @try {
        CGContextTranslateCTM(ctx,0,sample.height);CGContextScaleCTM(ctx,scale,-scale);
        CGContextTranslateCTM(ctx,-roi.origin.x,-roi.origin.y);
        WXGROISet coverage=r.requestedCoverage;
        CGRect clips[WXG_ROI_CAPACITY];for(size_t i=0;i<coverage.count;i++)clips[i]=WXGCGRectFromROI(coverage.rects[i]);
        CGContextClipToRects(ctx,clips,coverage.count);
        CFTimeInterval stage=CACurrentMediaTime();
        // FIX21: what shows through where no sampled view paints is the first
        // opaque background up the chain (often the window), not plain white.
        UIColor *base=WXGBaseFill(source);r.baseFill=base;
        [base setFill];UIRectFill(roi);r.fillMS=(CACurrentMediaTime()-stage)*1000;
        // FIX19 path choice: model tree (FIX4) unless something animates or
        // needs the native compositor; fresh animations hold one frame.
        WXGModelScan scan={0};NSMutableArray<CALayer *> *prune=[NSMutableArray array],*animatedLayers=[NSMutableArray array];
        // FIX22: animations and native transitions stay on the model tree,
        // corrected per layer; only compositor-only content needs the other path.
        BOOL wantModel=WXGConfig.shared.samplerSource==0;
        NSMutableArray<UIView *> *excluded=[NSMutableArray array];
        WXGModelScanTree(source,source,&coverage,blocked,prune,animatedLayers,excluded,&scan,NO);
        r.modelVisited=scan.visited;r.modelPruned=prune.count;
        // Never hold a frame that a hidden (resized) glass is waiting for.
        BOOL fresh=(scan.fresh || r.consumerFresh) && !r.consumerNeedsFrame;
        if(fresh && r.consecutiveHolds<2) {
            ++r.animationHolds;++r.consecutiveHolds;held=YES;r.lastPath=@"holdFreshAnimation";
        }else {
            r.consecutiveHolds=0;
            if(wantModel && !scan.special && !scan.overflow) {
                NSMutableArray<WXGLayerOverride *> *overrides=[NSMutableArray array];
                [CATransaction begin];[CATransaction setDisableActions:YES];
                @try {
                    WXGApplyPresentationOverrides(animatedLayers,overrides);
                    for(CALayer *layer in prune)layer.hidden=YES;
                    // renderInContext places the root's bounds.origin at the
                    // context origin; source coordinates are bounds coordinates.
                    CGContextSaveGState(ctx);
                    CGContextTranslateCTM(ctx,source.bounds.origin.x,source.bounds.origin.y);
                    CFTimeInterval branchStart=CACurrentMediaTime();
                    [source.layer renderInContext:ctx];
                    r.layerMS+=(CACurrentMediaTime()-branchStart)*1000;
                    CGContextRestoreGState(ctx);
                    good=YES;modelPathUsed=YES;++r.modelReads;
                    r.substitutedLayers=overrides.count;if(overrides.count)++r.substitutionReads;
                    r.lastPath=overrides.count?@"modelTreeAnimated":@"modelTree";
                }@finally {
                    for(CALayer *layer in prune)layer.hidden=NO;
                    WXGRestoreOverrides(overrides);
                    [CATransaction commit];
                }
            }else {
                if(scan.special || scan.overflow)++r.specialFallbacks;
                r.lastPath=!wantModel?@"presentationSelected":scan.overflow?@"presentationTreeBudget":@"presentationCompositorContent";
                // A compositor read of an atomic ancestor includes every descendant.
                // Split on the same native chrome, conceal masks and plugin roots
                // that the model path pruned, including masks without a glass.
                if(scan.overflow){[excluded removeAllObjects];WXGCollectRemainingExclusions(source,blocked,excluded);}
                NSMutableSet *boundaries=[split mutableCopy];
                for(UIView *root in excluded)for(UIView *p=root.superview;p;p=p.superview){
                    if([boundaries containsObject:p])break;
                    [boundaries addObject:p];
                    if(p==source)break;
                }
                r.presentationExclusions=excluded.count;
                good=WXGDrawClean(source,source,&coverage,blocked,boundaries,ctx,1,r);++r.presentationReads;
            }
        }
        stage=CACurrentMediaTime();CGContextFlush(ctx);r.flushMS=(CACurrentMediaTime()-stage)*1000;
        if(good && epoch==WXGSceneEpoch) {
            stage=CACurrentMediaTime();
            if(sample.requiresUpload)[sample.texture replaceRegion:MTLRegionMake2D(0,0,sample.width,sample.height) mipmapLevel:0 withBytes:sample.pixels.contents bytesPerRow:sample.stride];
            r.uploadMS=(CACurrentMediaTime()-stage)*1000;
            // Coverage and revision describe this successful read only. Pixels
            // left in this recycled buffer outside the clip are never exposed.
            sample.coverage=coverage;sample.modelTree=modelPathUsed;
            sample.revision=++WXGRevision;sample.capturedAt=begin;
            sample.toneLevel=source.window.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?.2:.8;
            if(r.captured)r.intervalMS=(frameTime-r.captured)*1000;else r.firstCapture=frameTime;
            r.captured=frameTime;r.sample=sample;r.epoch=epoch;++r.captures;++WXGCaptures;
        }else if(!held)++WXGFailures;
    }@catch(NSException *error){++WXGFailures;WXGLog(@"场景采样失败：%@",error.reason);}
    @finally {UIGraphicsPopContext();CGContextRestoreGState(ctx);--WXGCaptureDepth;}
    r.milliseconds=(CACurrentMediaTime()-begin)*1000;
    // FIX16: budget bookkeeping covers every actual read, successful or not.
    r.costAverage=WXGBackdropCostAverage(r.costAverage,r.milliseconds);
    if(!r.shareWindowStart)r.shareWindowStart=frameTime;
    r.shareReadMS+=r.milliseconds;
    if(frameTime-r.shareWindowStart>=1) {
        r.measuredShare=r.shareReadMS/1000./MAX(.001,frameTime-r.shareWindowStart);
        r.shareReadMS=0;r.shareWindowStart=frameTime;
    }
    // Spend less work per read on slow devices, instead of dropping animation
    // stages or alternating buttons. Drawable/optics/blur resolution is unchanged.
    r.scale=WXGBackdropNextScale(scale,r.milliseconds,WXGScreenCaptureFPS(source.window.screen),source.window.screen.scale,r.captures);
}
static BOOL WXGExclusionCanPaint(UIView *root,UIView *source,const WXGROISet *coverage) {
    // Test the entire excluded root, not the glass child: an unready glass can
    // be hidden while its enclosing surface still shows the fallback material.
    CGFloat alpha=1;
    for(UIView *view=root;view;view=view.superview) {
        CALayer *shown=view.layer.presentationLayer?:view.layer;
        if(shown.hidden)return NO;alpha*=shown.opacity;if(alpha<.001)return NO;
        if(view==source)break;
    }
    // Unclipped children may extend outside their root; keep those exclusions.
    if(root.clipsToBounds && !WXGROIIntersects(coverage,WXGROIFromCGRect(CGRectInset(WXGPresentedBounds(root,source),-12,-12))))return NO;
    return YES;
}
void WXGBeginBackdropFrame(NSArray<WXGGlassView *> *views,BOOL moving,CFTimeInterval frameTime) {
    NSCAssert(NSThread.isMainThread,@"Backdrop coordinator thread");(void)moving;
    if(WXGBackdropCaptureInProgress() || frameTime<=WXGLastFrame)return;WXGLastFrame=frameTime;
    {
        CFTimeInterval now=CACurrentMediaTime();
        CFTimeInterval target=WXGFrameTarget>frameTime?WXGFrameTarget:frameTime+1./60;
        double frame=MIN(.05,MAX(1./240,target-frameTime));
        double latency=WXGPresentLatency>0?WXGPresentLatency:MAX(0,target-now)+frame;
        WXGDisplayEstimate=WXGConfig.shared.motionPrediction?now+latency:0;
        // FIX19: with the glass presented in the same transaction as the frame,
        // model-driven motion (scroll) is shown together: no model lead.
        WXGModelLead=WXGConfig.shared.syncPresent?0:WXGDisplayEstimate-target;WXGPredictedViews=0;WXGMaxPredictShift=0;
        WXGScanTime=frameTime;WXGExpireAnimationHistory();
    }
    if(!WXGRegions)WXGRegions=[NSMapTable weakToStrongObjectsMapTable];
    if(!WXGConsumers)WXGConsumers=[NSMapTable weakToStrongObjectsMapTable];
    [WXGConsumers removeAllObjects];
    NSMutableArray<WXGBackdropRegion *> *active=[NSMutableArray array];
    // FIX18 render-server mode reads nothing; inactive atlases are released below.
    BOOL renderServerOnly=WXGEffectiveRenderMode()>=2;
    for(WXGGlassView *glass in views) {
        if(renderServerOnly)continue;
        // Layout/cache ownership stays with each page. Optical pixels instead
        // come from the CURRENT composited scene: stationary navigation items
        // can straddle two pages during a return. One scene read serves both.
        UIView *owner=glass.sourceView;
        UIView *source=owner.window.rootViewController.view;
        if(!glass.active || !glass.ready || glass.hidden || !WXGPresentedVisible(glass) || !glass.window || !source.window || glass.window.screen!=source.window.screen || CGRectIsEmpty(glass.bounds))continue;
        WXGBackdropRegion *r=[WXGRegions objectForKey:source];
        if(!r){r=[WXGBackdropRegion new];r.source=source;r.pool=[NSMutableArray array];[WXGRegions setObject:r forKey:source];}
        if(![active containsObject:r]) {
            [active addObject:r];r.exclusions=@[];r.consumers=[NSMutableArray array];r.requestedCoverage=(WXGROISet){0};
            r.consumerAnimated=NO;r.consumerFresh=NO;r.consumerNeedsFrame=NO;
            // The window atlas stays fixed while native page/keyboard layers
            // move through it. No endpoint or previous-page snapshot is reused.
            r.requestedRect=CGRectIntegral(CGRectInset(source.bounds,-40,-40));
        }
        WXGBackdropConsumer *consumer=[WXGBackdropConsumer new];consumer.region=r;
        if(!glass.hasPresentedFrame)r.consumerNeedsFrame=YES;
        WXGModelScan ancestors={0};WXGScanConsumerAncestors(glass,source,&ancestors);
        if(ancestors.animated)r.consumerAnimated=YES;if(ancestors.fresh)r.consumerFresh=YES;
        consumer.animated=ancestors.animated;
        consumer.transform=WXGPredictTransform(glass,source,WXGPresentedTransform(glass,source),CACurrentMediaTime());
        consumer.copyScale=WXGConsumerScale(glass);
        consumer.canvasPixels=WXGConsumerCanvas(glass,consumer.copyScale);
        CGAffineTransform t=consumer.transform;WXGROIRect canvas,footprint;
        CGFloat captureScale=r.scale?:WXGBackdropInitialScale(source.window.screen.scale,source.window.screen.maximumFramesPerSecond);
        // Guard covers both the next allocation and a still-valid older sample.
        CGFloat guardScale=r.sample?MIN(captureScale,r.sample.scale):captureScale;
        if(!WXGROICanvas((WXGSourceTransform){t.a,t.b,t.c,t.d,t.tx,t.ty},consumer.canvasPixels.width,consumer.canvasPixels.height,
                         consumer.copyScale,WXGROIFromCGRect(r.requestedRect),guardScale,&canvas,&footprint))continue;
        consumer.canvas=canvas;consumer.footprint=footprint;
        WXGROISet requested=r.requestedCoverage;WXGROIAdd(&requested,footprint,WXGROIFromCGRect(r.requestedRect));r.requestedCoverage=requested;
        {
            CGAffineTransform m=WXGModelTransform(glass,source);WXGROIRect modelCanvas,modelFootprint;
            if(WXGROICanvas((WXGSourceTransform){m.a,m.b,m.c,m.d,m.tx,m.ty},consumer.canvasPixels.width,consumer.canvasPixels.height,
                            consumer.copyScale,WXGROIFromCGRect(r.requestedRect),guardScale,&modelCanvas,&modelFootprint)) {
                consumer.modelTransform=m;consumer.modelCanvas=modelCanvas;consumer.modelFootprint=modelFootprint;consumer.hasModel=YES;
                // Usually identical to the presented footprint (then not added twice).
                WXGROISet withModel=r.requestedCoverage;WXGROIAdd(&withModel,modelFootprint,WXGROIFromCGRect(r.requestedRect));r.requestedCoverage=withModel;
            }
        }
        [r.consumers addObject:consumer];[WXGConsumers setObject:consumer forKey:glass];
        NSMutableOrderedSet *exclude=[NSMutableOrderedSet orderedSetWithArray:r.exclusions];
        [exclude addObjectsFromArray:glass.backdropExclusions?:@[]];r.exclusions=exclude.array;
    }
    CFTimeInterval begin=CACurrentMediaTime();WXGVisited=WXGBranches=WXGFallbacks=WXGBatch=0;
    for(WXGBackdropRegion *r in active) {
        if(!r.requestedCoverage.count)continue;
        double fps=WXGScreenCaptureFPS(r.source.window.screen);
        BOOL valid=r.sample && r.epoch==WXGSceneEpoch;
        WXGROISet previous=r.sample?r.sample.coverage:(WXGROISet){0};
        BOOL covered=valid,previousModel=r.sample.modelTree;
        for(WXGBackdropConsumer *consumer in r.consumers) {
            WXGROIRect footprint=previousModel && consumer.hasModel && !consumer.animated?consumer.modelFootprint:consumer.footprint;
            if(!WXGROICovers(&previous,footprint)){covered=NO;break;}
        }
        // FIX16: the cadence is additionally bounded by a main-thread budget.
        // A new scene still reads at once; an uncovered (moved) canvas uses a
        // relaxed budget; a covered canvas keeps the user's share. Timing uses
        // the last actual read, so failed reads are charged too.
        CFTimeInterval lastReadTime=MAX(r.captured,r.lastRead);
        // FIX17: a native page transition counts as moving (relaxed share):
        // every skipped read during a slide is a full frame of visible drag.
        BOOL steady=covered && !WXGFrameTransition;
        BOOL due=WXGBackdropDueWithBudget(frameTime,lastReadTime,fps,valid,steady,r.costAverage,WXGConfig.shared.captureBudget);
        // A glass hidden since a resize (keyboard changes the input bar height)
        // shows nothing until it gets a frame: read now, budget aside.
        // Bounded: a glass that cannot present (e.g. no GPU) must not force
        // every frame forever; 12 consecutive forced reads cover any resize.
        if(!r.consumerNeedsFrame)r.forcedStreak=0;
        if(r.consumerNeedsFrame && !due && r.forcedStreak<12){due=YES;++r.forcedFrameReads;++r.forcedStreak;}
        if(!due && WXGBackdropDue(frameTime,lastReadTime,fps,covered))++r.budgetHolds;
        if(due) {
            if(valid && !covered)++r.coverageRefreshes;
            NSMutableSet *blocked=[NSMutableSet set];
            for(UIView *view in r.exclusions)if(view!=r.source && [view isDescendantOfView:r.source])[blocked addObject:view];
            for(WXGGlassView *glass in WXGRegistered)if([glass isDescendantOfView:r.source]) {
                UIView *root=glass;
                while(root.superview!=r.source && WXGIsPluginView(root.superview))root=root.superview;
                if(root!=r.source)[blocked addObject:root];
            }
            NSMutableSet *split=[NSMutableSet setWithObject:r.source];r.unsplitExclusions=0;
            WXGROISet requested=r.requestedCoverage;
            for(UIView *view in blocked) {
                if(!WXGExclusionCanPaint(view,r.source,&requested)){++r.unsplitExclusions;continue;}
                for(UIView *p=view.superview;p;p=p.superview){[split addObject:p];if(p==r.source)break;}
            }
            WXGLastReadTime=CACurrentMediaTime();
            WXGCaptureRegion(r,blocked,split,frameTime);++WXGBatch;
        }
        // Failed reads and exhausted pools leave the prior publication intact.
        // Only consumers whose full canvas is covered may use that publication.
        WXGROISet published=r.sample?r.sample.coverage:(WXGROISet){0};
        BOOL modelSample=r.sample.modelTree;
        for(WXGBackdropConsumer *consumer in r.consumers) {
            // A model-tree sample is paired with the model mapping of the glass,
            // a presentation sample with its (predicted) presentation mapping.
            if(modelSample && !consumer.animated)WXGUseModelMapping(consumer);
            if(r.sample && r.epoch==WXGSceneEpoch && WXGROICovers(&published,consumer.footprint))consumer.sample=r.sample;
            else ++r.coverageRejects;
        }
        r.exclusions=@[];
    }
    // Release inactive scene atlases; the surface's last drawable is retained.
    for(WXGBackdropRegion *r in WXGRegions.objectEnumerator)if(![active containsObject:r]) {
        r.sample=nil;r.consumers=nil;r.exclusions=@[];r.captured=0;r.lastRead=0;r.intervalMS=0;for(WXGBackdropSample *s in r.pool.copy)if(!s.leases)[r.pool removeObjectIdenticalTo:s];
    }
    WXGLastCost=(CACurrentMediaTime()-begin)*1000;WXGMaxCost=MAX(WXGMaxCost,WXGLastCost);
}
WXGBackdropSample *WXGBackdropForGlassCopy(WXGGlassView *glass,CGAffineTransform *transform,CGFloat *scale,CGRect *canvasRect) {
    WXGBackdropConsumer *consumer=[WXGConsumers objectForKey:glass];WXGBackdropRegion *r=consumer.region;
    if(!r || !consumer.sample || r.sample!=consumer.sample || r.source!=glass.sourceView.window.rootViewController.view || r.epoch!=WXGSceneEpoch)return nil;
    // A native callback may resize a new mount during the read. Do not stretch
    // the old canvas or copy newly exposed pixels until the next coordinator pass.
    CGFloat currentScale=WXGConsumerScale(glass);
    if(currentScale!=consumer.copyScale || !CGSizeEqualToSize(WXGConsumerCanvas(glass,currentScale),consumer.canvasPixels))return nil;
    if(transform)*transform=consumer.transform;if(scale)*scale=consumer.copyScale;if(canvasRect)*canvasRect=WXGCGRectFromROI(consumer.canvas);
    return consumer.sample;
}
WXGBackdropSample *WXGBackdropForGlass(WXGGlassView *glass,CGRect *sourceRect,NSUInteger *revision) {
    WXGBackdropSample *sample=WXGBackdropForGlassCopy(glass,NULL,NULL,NULL);
    if(sourceRect)*sourceRect=sample?sample.rect:CGRectNull;if(revision)*revision=sample.revision;return sample;
}
NSDictionary *WXGBackdropEvidence(void) {
    NSMutableArray *regions=[NSMutableArray array];
    for(WXGBackdropRegion *r in WXGRegions.objectEnumerator)if(r.source.window && r.sample && regions.count<12) {
        NSUInteger leased=0;for(WXGBackdropSample *s in r.pool)leased+=s.leases>0;
        WXGROISet coverage=r.sample.coverage;WXGROIRect atlas=WXGROIFromCGRect(r.sample.rect);
        double activeArea=WXGROIArea(&coverage,atlas),atlasArea=atlas.w*atlas.h;
        NSMutableArray *clips=[NSMutableArray arrayWithCapacity:coverage.count];
        for(size_t i=0;i<coverage.count;i++)[clips addObject:NSStringFromCGRect(WXGCGRectFromROI(coverage.rects[i]))];
        [regions addObject:@{@"sourceClass":NSStringFromClass(r.source.class),@"sourceID":[NSString stringWithFormat:@"%p",r.source],
            @"rect":NSStringFromCGRect(r.sample.rect),@"captures":@(r.captures),@"revision":@(r.sample.revision),
            @"ageMS":@(MAX(0,CACurrentMediaTime()-r.captured)*1000),@"intervalMS":@(r.intervalMS),
            @"measuredCaptureFPS":@(r.intervalMS>0?1000/r.intervalMS:0),@"costMS":@(r.milliseconds),@"scale":@(r.sample.scale),
            @"branchDraws":@(r.branches),@"modelFallbacks":@(r.fallbacks),@"buffers":@(r.pool.count),@"leasedBuffers":@(leased),@"busySkips":@(r.busySkips),
            @"coverageRects":clips,@"activeROIPixels":@(activeArea*r.sample.scale*r.sample.scale),@"atlasPixels":@(r.sample.width*r.sample.height),@"roiFraction":@(atlasArea>0?activeArea/atlasArea:0),
            @"presentationExclusions":@(r.presentationExclusions),@"spatialSplits":@(r.spatialSplits),@"atomicGuards":@(r.atomicGuards),@"forcedSplitPaintApproximations":@(r.forcedSplitPaintApproximations),@"nativeReadAreaPoints":@(r.nativeReadArea),@"coverageRefreshes":@(r.coverageRefreshes),@"coverageRejects":@(r.coverageRejects),@"culledViews":@(r.culledViews),@"unsplitExclusions":@(r.unsplitExclusions),
            @"layerReads":@(r.layerReads),@"nativeReads":@(r.nativeReads),@"inspectedLayers":@(r.inspectedLayers),
            @"costAverageMS":@(r.costAverage),@"budgetHolds":@(r.budgetHolds),@"animationSplits":@(r.animationSplits),
            @"measuredMainThreadShare":@(r.measuredShare),@"budgetPercent":@(WXGConfig.shared.captureBudget),
            @"lastPath":r.lastPath?:@"none",@"forcedFrameReads":@(r.forcedFrameReads),
            @"substitutedLayers":@(r.substitutedLayers),@"substitutionReads":@(r.substitutionReads),
            @"baseFill":r.baseFill?[NSString stringWithFormat:@"%@",r.baseFill]:@"none",@"modelReads":@(r.modelReads),@"presentationReads":@(r.presentationReads),
            @"animationHolds":@(r.animationHolds),@"compositorFallbacks":@(r.specialFallbacks),@"modelVisited":@(r.modelVisited),@"modelPruned":@(r.modelPruned),
            @"fillMS":@(r.fillMS),@"nativeHierarchyMS":@(r.hierarchyMS),@"currentLayerMS":@(r.layerMS),@"flushMS":@(r.flushMS),@"uploadMS":@(r.uploadMS),@"slowBranches":r.slowBranches?:@[]}];
    }
    return @{@"backend":@"FIX22_model_tree_presentation_overrides_pre_commit",@"regions":regions,
        @"filteredLayersRasterized":@YES,
        @"samplerSource":@(WXGConfig.shared.samplerSource),@"syncPresent":@(WXGConfig.shared.syncPresent),
        @"renderMode":@(WXGEffectiveRenderMode()),@"requestedRenderMode":@(WXGConfig.shared.renderMode),
        @"prediction":@{@"enabled":@(WXGConfig.shared.motionPrediction),@"latencyMS":@(WXGPresentLatency*1000),
            @"displayLeadMS":@(MAX(0,WXGDisplayEstimate-WXGLastReadTime)*1000),@"lastAnimationLeadMS":@(WXGLastAnimationLead*1000),
            @"modelLeadMS":@(WXGModelLead*1000),@"predictedViews":@(WXGPredictedViews),@"maxShiftPt":@(WXGMaxPredictShift),
            @"interactive":@(WXGFrameInteractive),@"transition":@(WXGFrameTransition),@"trackedViews":@(WXGMotion.count)},
        @"mainThreadBudget":@YES,@"backingStoreRaster":@YES,@"animatingSublayerGuard":@YES,
        @"allDueScenesPerDisplayTick":@YES,@"transitionPaused":@NO,@"consumerCopyBackend":@"GPU",
        @"liveVisibilityMutations":@NO,@"nativeRootRasterization":@NO,@"workerInFlight":@NO,
        @"fullConsumerCanvasCoverage":@YES,@"frozenCopyMapping":@YES,@"disjointROIClip":@YES,@"nativeTreePrunedBeforeRead":@YES,
        @"lastBatchScenes":@(WXGBatch),@"lastVisitedViews":@(WXGVisited),@"hierarchyDraws":@(WXGBranches),@"leafFallbacks":@(WXGFallbacks),
        @"captures":@(WXGCaptures),@"failures":@(WXGFailures),@"sceneEpoch":@(WXGSceneEpoch),
        @"lastMilliseconds":@(WXGLastCost),@"maxMilliseconds":@(WXGMaxCost),
        @"samplingCap":@(WXGScreenCaptureFPS(UIScreen.mainScreen)),@"requestedFPS":@(WXGConfig.shared.captureFPS),
        @"note":@"Requested cap is not measured FPS; scene intervalMS reports capture, glass presentedFrames reports actual presentation."};
}
