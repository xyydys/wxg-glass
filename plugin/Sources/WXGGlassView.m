// FIX47: WXGMeshOptics has trailing bar fields; the positional initializers
// below intentionally leave them zero (= off).
#pragma clang diagnostic ignored "-Wmissing-field-initializers"
#import "WXGIntegration.h"
#import <Metal/Metal.h>
#import <MetalKit/MTKTextureLoader.h>
typedef float WXGFloat4 __attribute__((ext_vector_type(4)));
_Static_assert(sizeof(WXGFloat4)==16,"Float4 ABI");
// FIX103: the glass shader (WXGGlass.metal) is not compiled into the plugin;
// it comes from the unlock server (WXGUnlock.m). WXGShaderSource.h stays in
// the source tree for tools/check_msl.py and the shader simulator only.
#include "WXGDistanceField.h"
#include "WXGSourceMapping.h"
#include "WXGBackdropCopy.h"
#include "WXGLensOptics.h"
#include "WXGMeshRefraction.h"
#include "WXGEdgeMaskBand.h"
#include "WXGRimGlow.h"
#include "WXGRimDetail.h"

/* One GPU device and one compiled TEST9 pipeline for every capsule. */
id<MTLDevice> WXGSharedDevice(void) {
    static id<MTLDevice> device;static dispatch_once_t once;
    dispatch_once(&once,^{device=MTLCreateSystemDefaultDevice();});return device;
}
static id<MTLCommandQueue> WXGSharedQueue(void) {
    static id<MTLCommandQueue> queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=[WXGSharedDevice() newCommandQueue];});return queue;
}
static id<MTLTexture> WXGTransparentTexture(void) {
    static id<MTLTexture> texture;static dispatch_once_t once;
    dispatch_once(&once,^{
        MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
        d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
        texture=[WXGSharedDevice() newTextureWithDescriptor:d];
        const uint32_t transparent=0;
        [texture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&transparent bytesPerRow:4];
    });return texture;
}
static void WXGPrepareMetal(void (^completion)(id<MTLRenderPipelineState>,id<MTLComputePipelineState>,id<MTLComputePipelineState>,NSString *)) {
    static dispatch_once_t once;static dispatch_group_t group;
    static id<MTLRenderPipelineState> state;static id<MTLComputePipelineState> blur,copy;static NSString *failure;
    dispatch_once(&once,^{
        group=dispatch_group_create();dispatch_group_enter(group);
        // FIX103: compiled when the unlock server's shader is here (at launch
        // from the cached ticket; the first time, after the server answers).
        // Until then every glass view waits, as it did for the compile.
        // FIX104: the cached one is handed over by the cache read itself, off
        // main, a few ms after the plugin loads (no wait for a main turn).
        WXGUnlockWhenShaderReady(^(NSString *shader){
            @autoreleasepool {
                NSError *error=nil;id<MTLDevice> device=WXGSharedDevice();
                MTLCompileOptions *options=[MTLCompileOptions new];options.fastMathEnabled=YES;options.languageVersion=MTLLanguageVersion2_1;
                id<MTLLibrary> library=[device newLibraryWithSource:[shader stringByAppendingString:[NSString stringWithUTF8String:WXGBackdropCopySource]] options:options error:&error];
                if(library) {
                    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
                    d.vertexFunction=[library newFunctionWithName:@"wxgVertex"];d.fragmentFunction=[library newFunctionWithName:@"wxgFragment"];
                    d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;d.colorAttachments[0].blendingEnabled=YES;
                    d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                    d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                    if(d.vertexFunction && d.fragmentFunction)state=[device newRenderPipelineStateWithDescriptor:d error:&error];
                    id<MTLFunction> fn=[library newFunctionWithName:@"wxgBlur"];
                    if(fn)blur=[device newComputePipelineStateWithFunction:fn error:&error];
                    id<MTLFunction> copyFn=[library newFunctionWithName:@"wxgCopyBackdrop"];
                    if(copyFn)copy=[device newComputePipelineStateWithFunction:copyFn error:&error];
                }
                failure=error.localizedDescription?:@"TEST9 Metal 管线初始化失败";
                dispatch_group_leave(group);
            }
        });
    });
    if(dispatch_group_wait(group,DISPATCH_TIME_NOW)==0){completion(state,blur,copy,failure);return;}
    dispatch_group_notify(group,dispatch_get_main_queue(),^{completion(state,blur,copy,failure);});
}

void WXGPrewarmGlassPipeline(void) {
    WXGPrepareMetal(^(__unused id<MTLRenderPipelineState> state,__unused id<MTLComputePipelineState> blur,
        __unused id<MTLComputePipelineState> copy,__unused NSString *failure){});
}

typedef struct { WXGFloat4 viewport,bar,lens,material,appearance,optics,lensOptics,selectionColor,borderColor,motion,rim,tintColor,sync,style,glow,extra,glow2,glowColor2,extra2; } WXGUniforms;
_Static_assert(sizeof(WXGUniforms)==304,"Metal uniform ABI");   // FIX86: glow; FIX88: extra; FIX89: glow2, glowColor2; FIX97: extra2 (19 float4)
// FIX27: rim brightness, 0..2: below 1 darkens, above 1 mixes toward white.
static UIColor *WXGBrightened(UIColor *color,CGFloat brightness) {
    CGFloat r=0,g=0,b=0,a=0;
    if(![color getRed:&r green:&g blue:&b alpha:&a])return color;
    if(brightness<=1){r*=brightness;g*=brightness;b*=brightness;}
    else {CGFloat t=MIN(1,brightness-1);r+=(1-r)*t;g+=(1-g)*t;b+=(1-b)*t;}
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
_Static_assert(sizeof(WXGCopyUniforms)==48,"Backdrop copy ABI");
_Static_assert(sizeof(WXGGaussianKernel)==440,"Metal Gaussian ABI");

// Both surfaces are submitted together. Own their drawables explicitly instead
// of borrowing a second MTKView's cached currentDrawable outside its draw cycle.
@interface WXGMetalSurface : UIView
@property(nonatomic,readonly) CAMetalLayer *metalLayer;
@property(nonatomic) CGSize drawableSize;
@end
@implementation WXGMetalSurface
+ (Class)layerClass { return CAMetalLayer.class; }
- (CAMetalLayer *)metalLayer { return (CAMetalLayer *)self.layer; }
- (CGSize)drawableSize { return self.metalLayer.drawableSize; }
- (void)setDrawableSize:(CGSize)size { self.metalLayer.drawableSize=size; }
@end

// FIX18: render-server glass. CABackdropLayer is the private QuartzCore class
// behind UIVisualEffectView: the render server captures what lies beneath it
// and applies its filters while compositing each displayed frame. Nothing is
// read back into this process and it can never lag the content.
@protocol WXGCAFilterFactory <NSObject>
+ (id)filterWithType:(NSString *)type;
@end
static Class WXGBackdropLayerClass(void) {
    static Class cls;static dispatch_once_t once;
    dispatch_once(&once,^{cls=NSClassFromString(@"CABackdropLayer");});
    return cls;
}
static BOOL WXGFilterFactoryAvailable(void) {
    Class cls=NSClassFromString(@"CAFilter");
    return cls && [cls respondsToSelector:@selector(filterWithType:)];
}
static id WXGMakeBlurFilter(CGFloat radius) {
    if(!WXGFilterFactoryAvailable())return nil;
    id filter=[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    @try {
        [filter setValue:@(radius) forKey:@"inputRadius"];
        [filter setValue:@YES forKey:@"inputNormalizeEdges"];
    } @catch(__unused NSException *error) {}
    return filter;
}
CALayer *WXGMakeTravelBackdropLayer(CGFloat blurRadius) {
    Class cls=NSClassFromString(@"CABackdropLayer");if(!cls)return nil;
    CALayer *layer=[cls layer];
    @try {
        CGFloat screen=UIScreen.mainScreen.scale;
        [layer setValue:@YES forKey:@"enabled"];
        [layer setValue:@(screen) forKey:@"scale"];layer.contentsScale=screen;layer.rasterizationScale=screen;
        [layer setValue:@(MAX(2.,blurRadius*3.)) forKey:@"marginWidth"];
        NSMutableArray *filters=[NSMutableArray array];
        id blur=blurRadius>=.2?WXGMakeBlurFilter(blurRadius):nil;if(blur)[filters addObject:blur];
        id saturate=WXGFilterFactoryAvailable()?[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorSaturate"]:nil;
        @try {[saturate setValue:@1.15 forKey:@"inputAmount"];} @catch(__unused NSException *error) {saturate=nil;}
        if(saturate)[filters addObject:saturate];
        layer.filters=filters.count?filters:nil;
    } @catch(__unused NSException *error) {return nil;}
    return layer;
}
NSInteger WXGEffectiveRenderMode(void) {
    NSInteger mode=WXGConfig.shared.renderMode;
    if(mode<=0 || !WXGBackdropLayerClass())return 0;
    return mode>2?2:mode;
}
// FIX20: render-server refraction. The same private mesh transform the
// CC liquid-glass tweaks put on their backdrop layers; vertices come from
// WXGBuildRefractionMesh (the TEST9 field and offset curve). Layouts follow
// QuartzCore's CAMeshVertex / CAMeshFace; unit coordinates; no depth.
typedef struct { CGFloat x,y,z; } WXGMeshPoint3D;
typedef struct { CGPoint from; WXGMeshPoint3D to; } WXGMeshVertex;
typedef struct { unsigned int indices[4]; float w[4]; } WXGMeshFace;
@protocol WXGMeshTransformFactory <NSObject>
+ (id)meshTransformWithVertexCount:(NSUInteger)vertexCount vertices:(WXGMeshVertex *)vertices
                         faceCount:(NSUInteger)faceCount faces:(WXGMeshFace *)faces depthNormalization:(NSString *)depthNormalization;
@end
static Class WXGMeshTransformClass(void) {
    static Class cls;static dispatch_once_t once;
    dispatch_once(&once,^{
        cls=NSClassFromString(@"CAMutableMeshTransform")?:NSClassFromString(@"CAMeshTransform");
        if(cls && ![cls respondsToSelector:@selector(meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:)])cls=nil;
    });
    return cls;
}
static BOOL WXGMeshOpticsClose(WXGMeshOptics a,WXGMeshOptics b) {
    return fabsf(a.width-b.width)<.25f && fabsf(a.height-b.height)<.25f && fabsf(a.fieldScale-b.fieldScale)<.0005f &&
        fabsf(a.radius-b.radius)<.05f && fabsf(a.edgeWidth-b.edgeWidth)<.01f && fabsf(a.refraction-b.refraction)<.005f &&
        fabsf(a.offsetScale-b.offsetScale)<.0005f && fabsf(a.zoomBefore-b.zoomBefore)<.0005f && fabsf(a.zoomAfter-b.zoomAfter)<.0005f &&
        fabsf(a.dispersion-b.dispersion)<.005f && a.channel==b.channel && fabsf(a.topRatio-b.topRatio)<.005f && fabsf(a.sharpness-b.sharpness)<.01f &&
        fabsf(a.barLeft-b.barLeft)<.25f && fabsf(a.barTop-b.barTop)<.25f && fabsf(a.barRight-b.barRight)<.25f && fabsf(a.barBottom-b.barBottom)<.25f &&
        fabsf(a.endLeft-b.endLeft)<.005f && fabsf(a.endRight-b.endRight)<.005f &&
        fabsf(a.dispersionWidth-b.dispersionWidth)<.01f && fabsf(a.dispersionTopRatio-b.dispersionTopRatio)<.005f;   // FIX88
}
// FIX23: contour-following mesh (see WXGBuildContourMesh). Static glass gets
// the fine quality; the lens, rebuilt while it grows, a lighter one.
static const WXGMeshQuality WXGMeshQualityBody={.06f,.10f,24.f},WXGMeshQualityLens={.20f,.16f,24.f};
enum { WXGMeshCapacity=20000 };
// FIX30: identical optics give identical meshes (every navigation button has
// the same size and parameters), so finished transforms are shared. A new page
// no longer rebuilds 3-6 contour meshes per button inside the tab switch.
@interface WXGMeshCacheEntry : NSObject
@property(nonatomic,strong) id mesh;
@property(nonatomic,strong) NSMutableData *storage;
@property(nonatomic) NSUInteger vertices;
@property(nonatomic) NSInteger subdivision;
@end
@implementation WXGMeshCacheEntry
@end
static NSCache<NSData *,WXGMeshCacheEntry *> *WXGMeshCache(void) {
    static NSCache *cache;static dispatch_once_t once;
    // A press animation of the lens is 33 steps x 3 colour channels; meshes
    // are 50-130 KB each, so the cache is bounded by bytes as well.
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=200;cache.totalCostLimit=12*1024*1024;});
    return cache;
}
static NSUInteger WXGMeshCacheHits,WXGMeshCacheMisses;
static id WXGBuildMeshTransform(WXGMeshOptics optics,WXGMeshQuality quality,NSUInteger *vertexCount,NSMutableData **storage,NSInteger *subdivision);
static id WXGMakeMeshTransform(WXGMeshOptics optics,WXGMeshQuality quality,NSUInteger *vertexCount,NSMutableData **storage,NSInteger *subdivision) {
    // Key: the exact optics and quality, rounded so float noise cannot split it.
    float key[25]={roundf(optics.width*100),roundf(optics.height*100),roundf(optics.fieldScale*1000),roundf(optics.radius*100),
        roundf(optics.edgeWidth*100),roundf(optics.refraction*1000),roundf(optics.offsetScale*1000),roundf(optics.zoomBefore*1000),
        roundf(optics.zoomAfter*1000),roundf(optics.dispersion*1000),optics.channel,roundf(optics.topRatio*1000),roundf(optics.sharpness*100),
        roundf(quality.ringError*1000),roundf(quality.arcStep*1000),roundf(quality.straightStep*100),
        roundf(optics.barLeft*10),roundf(optics.barTop*10),roundf(optics.barRight*10),roundf(optics.barBottom*10),
        roundf(optics.endLeft*1000),roundf(optics.endRight*1000),roundf(optics.dispersionWidth*100),roundf(optics.dispersionTopRatio*1000),0};
    NSData *cacheKey=[NSData dataWithBytes:key length:sizeof key];
    WXGMeshCacheEntry *entry=[WXGMeshCache() objectForKey:cacheKey];
    if(entry) {
        ++WXGMeshCacheHits;
        if(vertexCount)*vertexCount=entry.vertices;
        if(storage)*storage=entry.storage;
        if(subdivision)*subdivision=entry.subdivision;
        return entry.mesh;
    }
    ++WXGMeshCacheMisses;
    NSUInteger count=0;NSMutableData *data=nil;NSInteger steps=-99;
    CFTimeInterval buildStart=CACurrentMediaTime();
    id mesh=WXGBuildMeshTransform(optics,quality,&count,&data,&steps);
    WXGProfileAdd(WXGProfileMesh,(CACurrentMediaTime()-buildStart)*1000);WXGProfileMeshBuilt();
    if(mesh) {
        entry=[WXGMeshCacheEntry new];entry.mesh=mesh;entry.storage=data;entry.vertices=count;entry.subdivision=steps;
        [WXGMeshCache() setObject:entry forKey:cacheKey cost:data.length];
    }
    if(vertexCount)*vertexCount=count;
    if(storage)*storage=data;
    if(subdivision)*subdivision=steps;
    return mesh;
}
static id WXGBuildMeshTransform(WXGMeshOptics optics,WXGMeshQuality quality,NSUInteger *vertexCount,NSMutableData **storage,NSInteger *subdivision) {
    if(subdivision)*subdivision=-99;
    Class cls=WXGMeshTransformClass();if(!cls)return nil;
    static WXGMeshPoint points[WXGMeshCapacity];static unsigned int indices[WXGMeshCapacity][4];
    int faceCount=0,count=WXGBuildContourMesh(optics,quality,points,WXGMeshCapacity,indices,WXGMeshCapacity,&faceCount);
    if(count<4 || faceCount<1)return nil;
    NSUInteger faces=(NSUInteger)faceCount;
    // Kept alive alongside the mesh, in case the transform references it.
    NSMutableData *data=[NSMutableData dataWithLength:sizeof(WXGMeshVertex)*(NSUInteger)count+sizeof(WXGMeshFace)*faces];
    WXGMeshVertex *vertices=data.mutableBytes;WXGMeshFace *quads=(WXGMeshFace *)(vertices+count);
    for(int k=0;k<count;k++)vertices[k]=(WXGMeshVertex){CGPointMake(points[k].fromX,points[k].fromY),{points[k].toX,points[k].toY,0}};
    for(NSUInteger n=0;n<faces;n++)quads[n]=(WXGMeshFace){{indices[n][0],indices[n][1],indices[n][2],indices[n][3]},{0,0,0,0}};
    id mesh=nil;
    @try {
        mesh=[(Class<WXGMeshTransformFactory>)cls meshTransformWithVertexCount:(NSUInteger)count vertices:vertices
                                                                    faceCount:faces faces:quads depthNormalization:@"none"];
        // FIX24: smoothing OFF, verified. The factory returns the immutable
        // class, which has no setter, so FIX20-23 kept its default automatic
        // subdivision: it averages neighbouring vertices, dragging the steep
        // edge mapping into the undistorted interior and pinching the point
        // where the rings meet (the bright centre spot and ring banding).
        // A mutable copy takes the explicit 0.
        SEL setter=NSSelectorFromString(@"setSubdivisionSteps:");
        if(mesh && ![mesh respondsToSelector:setter] && [mesh respondsToSelector:@selector(mutableCopyWithZone:)]) {
            id mutableMesh=[mesh mutableCopy];
            if(mutableMesh)mesh=mutableMesh;
        }
        if([mesh respondsToSelector:setter])[mesh setValue:@0 forKey:@"subdivisionSteps"];
        if(subdivision) {
            id steps=[mesh valueForKey:@"subdivisionSteps"];
            *subdivision=[steps respondsToSelector:@selector(integerValue)]?[steps integerValue]:-98;
        }
    } @catch(__unused NSException *error) {mesh=nil;}
    if(vertexCount)*vertexCount=(NSUInteger)count;
    if(storage)*storage=data;
    return mesh;
}
// FIX23: per-channel isolation for render-server dispersion. The 4x5 matrix
// is passed in QuartzCore's CAColorMatrix layout (20 floats).
typedef struct { float m[20]; } WXGColorMatrix;
static id WXGMakeChannelFilter(NSInteger channel) {
    if(!WXGFilterFactoryAvailable() || channel<1 || channel>3)return nil;
    id filter=[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"];
    WXGColorMatrix matrix={{0}};
    // FIX27: this channel's row of TEST9's 5% saturation (Rec.709 weights),
    // so one matrix pass replaces colorSaturate + isolation per layer.
    const float s=1.05f,weights[3]={.2126f,.7152f,.0722f};
    int row=(int)channel-1;
    for(int column=0;column<3;column++)matrix.m[row*5+column]=(1.f-s)*weights[column]+(column==row?s:0.f);
    matrix.m[18]=1.f;                           /* alpha = alpha */
    @try {
        [filter setValue:[NSValue valueWithBytes:&matrix objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
    } @catch(__unused NSException *error) {filter=nil;}
    return filter;
}
static id WXGMakePlusLighter(void) {
    id filter=WXGFilterFactoryAvailable()?[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"plusL"]:nil;
    return filter?:@"plusL";
}
@interface WXGSyncBackdropView : UIView
@property(nonatomic,readonly) CGFloat radius;
@property(nonatomic,readonly) BOOL live,filtered;
@property(nonatomic,readonly) BOOL meshApplied,meshAccepted;
@property(nonatomic,readonly) NSUInteger meshVertices;
@property(nonatomic,readonly) NSInteger meshSubdivision;
@property(nonatomic,readonly) double defaultCaptureScale,appliedCaptureScale,requestedCaptureScale;
@property(nonatomic) CGFloat captureLimit;   // FIX59: 0 none, else at most this scale
- (void)applyCaptureScale;
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius;
// FIX23: channel 0 full colour; 1/2/3 keep only red/green/blue. Green and blue
// add onto red (plusL), so three backdrops with per-channel meshes make RGB
// dispersion in the render server.
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel;
@property(nonatomic,readonly) NSInteger channel;
- (void)applyRefraction:(WXGMeshOptics)optics enabled:(BOOL)enabled;
- (void)applyRefraction:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality enabled:(BOOL)enabled;
@end
@implementation WXGSyncBackdropView {
    WXGMeshOptics _meshOptics;
    NSMutableData *_meshStorage;
}
+ (Class)layerClass {return WXGBackdropLayerClass()?:CALayer.class;}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;_radius=-1;
    }
    return self;
}
- (BOOL)live {Class cls=WXGBackdropLayerClass();return cls && [self.layer isKindOfClass:cls];}
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius {[self configureGroup:group radius:radius channel:0];}
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel {
    if(!self.live)return;
    radius=MAX(0,radius);
    if(_radius>=0 && fabs(radius-_radius)<.05 && channel==_channel)return;
    BOOL first=_radius<0;_radius=radius;_channel=channel;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        if(first) {
            // One group per glass: its body and lens share one capture taken
            // beneath the body, so the lens never sees the body's own icons.
            id initial=[self.layer valueForKey:@"scale"];
            _defaultCaptureScale=[initial respondsToSelector:@selector(doubleValue)]?[initial doubleValue]:-1;
            [self.layer setValue:group forKey:@"groupName"];
            [self.layer setValue:@YES forKey:@"enabled"];
        }
        // FIX27: a blur under 0.2 pt is invisible but still a full pass.
        id filter=radius>=.2?WXGMakeBlurFilter(radius):nil;
        NSMutableArray *filters=[NSMutableArray array];
        if(filter)[filters addObject:filter];
        id isolate=channel>0?WXGMakeChannelFilter(channel):nil;
        if(isolate)[filters addObject:isolate];
        else {
            // TEST9 adds 5% saturation to the face (wxgBody); match it here.
            id saturate=WXGFilterFactoryAvailable()?[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorSaturate"]:nil;
            @try {[saturate setValue:@1.05 forKey:@"inputAmount"];} @catch(__unused NSException *error) {saturate=nil;}
            if(saturate)[filters addObject:saturate];
        }
        // FIX27: capture a margin around the glass so the blur at its edge
        // samples real content instead of the capture border (a thin dark rim).
        [self.layer setValue:@(MAX(2.,radius*3.)) forKey:@"marginWidth"];
        self.layer.filters=filters.count?filters:nil;
        // Red is drawn normally; green and blue add onto it (plus-lighter).
        self.layer.compositingFilter=channel>1?WXGMakePlusLighter():nil;
        _filtered=filter!=nil;
    } @catch(__unused NSException *error) {}
    [CATransaction commit];
}
// FIX26: capture at the screen's pixel density. With 1.0 the backdrop came out
// at one pixel per point on a 3x screen: blocky, stair-stepped text once the
// blur is off. The mesh pass may also rasterise at the layer's own scale, so
// contentsScale and rasterizationScale follow too. "同步模式采样倍率" 0 = screen.
- (void)applyCaptureScale {
    if(!self.live)return;
    CGFloat screen=self.window.screen.scale?:UIScreen.mainScreen.scale;
    CGFloat requested=WXGConfig.shared.syncCaptureScale;
    CGFloat scale=requested>.01?requested:screen;
    if(_captureLimit>.01)scale=MIN(scale,_captureLimit);   // FIX59
    // Compared with what was requested: if the system clamps the value, the
    // read-back differs and must not trigger a re-apply on every frame.
    if(fabs(scale-_requestedCaptureScale)<.01)return;
    _requestedCaptureScale=scale;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        [self.layer setValue:@(scale) forKey:@"scale"];
        self.layer.contentsScale=MAX(scale,screen);self.layer.rasterizationScale=MAX(scale,screen);
        id applied=[self.layer valueForKey:@"scale"];
        _appliedCaptureScale=[applied respondsToSelector:@selector(doubleValue)]?[applied doubleValue]:scale;
    } @catch(__unused NSException *error) {_appliedCaptureScale=scale;}
    [CATransaction commit];
}
- (void)applyRefraction:(WXGMeshOptics)optics enabled:(BOOL)enabled {
    [self applyRefraction:optics quality:WXGMeshQualityBody enabled:enabled];
}
- (void)applyRefraction:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality enabled:(BOOL)enabled {
    if(!self.live)return;
    if(!enabled || !WXGMeshTransformClass()) {
        if(_meshApplied) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            @try {[self.layer setValue:nil forKey:@"meshTransform"];} @catch(__unused NSException *error) {}
            [CATransaction commit];
            _meshApplied=NO;_meshAccepted=NO;_meshStorage=nil;_meshVertices=0;
        }
        return;
    }
    if(_meshApplied && WXGMeshOpticsClose(optics,_meshOptics))return;
    NSUInteger count=0;NSMutableData *storage=nil;
    NSInteger steps=-99;
    id mesh=WXGMakeMeshTransform(optics,quality,&count,&storage,&steps);
    _meshSubdivision=steps;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {[self.layer setValue:mesh forKey:@"meshTransform"];} @catch(__unused NSException *error) {mesh=nil;}
    [CATransaction commit];
    _meshOptics=optics;_meshApplied=mesh!=nil;_meshStorage=storage;_meshVertices=count;
    // The CC tweaks log when a backdrop refuses the mesh; record the same.
    // The layer may store a copy, so accepted means "a mesh is set", not identity.
    _meshAccepted=mesh && [self.layer respondsToSelector:NSSelectorFromString(@"setMeshTransform:")] &&
        [self.layer valueForKey:@"meshTransform"]!=nil;
}
@end
// FIX39: the Metal veil's fade toward the outline, as an alpha mask for its
// render-server stand-in: 1 - 0.82*edge^2 with edge = 1 - smoothstep(0,width,
// distance inside the capsule / rounded rect), exactly as the shader does.
static UIImage *WXGVeilFadeMask(CGSize size,CGFloat radius,CGFloat width) {
    size_t w=(size_t)MAX(2,ceil(size.width)),h=(size_t)MAX(2,ceil(size.height));
    if(w>4096 || h>4096 || width<=.01)return nil;
    CGContextRef context=CGBitmapContextCreate(NULL,w,h,8,w,NULL,(CGBitmapInfo)kCGImageAlphaOnly);
    if(!context)return nil;
    uint8_t *data=CGBitmapContextGetData(context);size_t row=CGBitmapContextGetBytesPerRow(context);
    double hw=w*.5,hh=h*.5,r=radius>0?MIN(radius,MIN(hw,hh)):MIN(hw,hh);
    for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++) {
        double qx=fabs(x+.5-hw)-(hw-r),qy=fabs(y+.5-hh)-(hh-r);
        double sdf=hypot(fmax(qx,0),fmax(qy,0))+fmin(fmax(qx,qy),0)-r;
        double t=WXGClamp(fmax(-sdf,0)/width,0,1),edge=1-t*t*(3-2*t);
        data[y*row+x]=(uint8_t)lround(WXGClamp(1-.82*edge*edge,0,1)*255);
    }
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);
    if(!image)return nil;
    UIImage *result=[UIImage imageWithCGImage:image];CGImageRelease(image);
    return result;
}
NSArray<UIView *> *WXGMakeTravelLensBackdrops(CGSize size,CGFloat press,NSString *group) {
    if(size.width<2 || size.height<2 || !NSClassFromString(@"CABackdropLayer"))return @[];
    WXGConfig *c=WXGConfig.shared;
    // FIX37: the optics of the lens at `press`, like the real lens: resting
    // glass blending into the independent lens parameters as it lifts.
    press=WXGClamp(press,0,1);
    WXGScopeOptics dock=[c opticsForDock:YES];   // FIX58: the tap lens belongs to the dock
    WXGOpticalValues resting={(float)dock.refraction,(float)dock.dispersion,(float)dock.edgeWidth};
    WXGOpticalValues pressed={(float)c.lensRefraction,(float)c.lensDispersion,(float)c.lensEdgeWidth};
    WXGOpticalValues optical=WXGPressedOptics(resting,pressed,(float)press);
    BOOL split=c.syncDispersion && WXGFilterFactoryAvailable() && !c.performanceMode;   // FIX59
    NSMutableArray<UIView *> *views=[NSMutableArray array];
    for(NSInteger i=0;i<(split?3:1);i++) {
        WXGSyncBackdropView *v=[[WXGSyncBackdropView alloc]initWithFrame:(CGRect){CGPointZero,size}];
        if(!v.live)return @[];
        [v configureGroup:group.length?group:@"wxg.travel" radius:(dock.blur+(c.lensBlur-dock.blur)*press)*c.syncBlurScale channel:split?i+1:0];
        v.captureLimit=c.performanceMode?2:0;[v applyCaptureScale];
        WXGMeshOptics o={(float)size.width,(float)size.height,1.f,0.f,optical.edgeWidth,optical.refraction,(float)press,1.f,1.f+(float)(press*(c.lensZoom-1)),
            split?optical.dispersion*1.55f*(float)press:0.f,split?(i==0?1.f:i==2?-1.f:0.f):0.f,(float)c.lensTopEdgeRatio,(float)c.lensEdgeSharpness};
        // FIX88: the lens's own dispersion range, only with dispersion on (0 =
        // the refraction band, so no wider mesh band for nothing).
        if(split && optical.dispersion>0.f){o.dispersionWidth=(float)(dock.edgeWidth+(c.lensDispersionWidth-dock.edgeWidth)*press);o.dispersionTopRatio=(float)c.lensDispersionTopRatio;}
        [v applyRefraction:o quality:WXGMeshQualityLens enabled:YES];
        [views addObject:v];
    }
    return views;
}

// Only the opacity field is stretched, never the stroke. CALayer still draws
// the constant-width continuous border at the current size on every frame.
// Four corner masks share one smooth 256px field; no image is regenerated when
// the lens grows or moves. This also avoids a conic gradient centred on the
// entire long capsule, which would fade the straight middle incorrectly.
// FIX78: this fade is one layer tree (WXGRimFadeLayer), used by the rim and,
// unchanged, by the background-coloured line, so both fade identically.
// FIX86: the tree itself (four straight edges, four corner windows over one
// field by direction) is WXGRimFieldLayer, shared with the iOS 27-like rim's
// level along the outline (WXGRimLevelLayer).
@interface WXGRimFieldLayer : CALayer
- (void)layoutForBounds:(CGRect)bounds radius:(CGFloat)r;
@end
@implementation WXGRimFieldLayer {
    // FIX27: straight edges split by side, so the top/left and bottom/right halves
    // can fade separately (the corner field carries the same split).
    CALayer *_topMask,*_bottomMask,*_leftMask,*_rightMask;
    NSArray<CALayer *> *_cornerMasks,*_cornerFields;
    UIImage *_fieldImage;
}
- (instancetype)init {
    if((self=[super init])) {
        _topMask=[CALayer layer];_bottomMask=[CALayer layer];_leftMask=[CALayer layer];_rightMask=[CALayer layer];
        for(CALayer *edge in @[_topMask,_bottomMask,_leftMask,_rightMask]) {
            edge.backgroundColor=UIColor.whiteColor.CGColor;[self addSublayer:edge];
        }
        NSMutableArray *windows=[NSMutableArray array],*fields=[NSMutableArray array];
        for(int i=0;i<4;i++) {
            CALayer *window=[CALayer layer],*field=[CALayer layer]; window.masksToBounds=YES;
            [window addSublayer:field]; [self addSublayer:window];
            [windows addObject:window]; [fields addObject:field];
        }
        _cornerMasks=windows;_cornerFields=fields;
    }
    return self;
}
// The four straight edges' levels and the corners' field: `level` of the
// direction from the corner's centre (unit x right, y down), cached by `key`.
- (void)applyTop:(CGFloat)top bottom:(CGFloat)bottom left:(CGFloat)left right:(CGFloat)right
        fieldKey:(NSString *)key level:(float (^)(float nx,float ny))level {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _topMask.backgroundColor=[UIColor colorWithWhite:1 alpha:WXGClamp(top,0,1)].CGColor;
    _bottomMask.backgroundColor=[UIColor colorWithWhite:1 alpha:WXGClamp(bottom,0,1)].CGColor;
    _leftMask.backgroundColor=[UIColor colorWithWhite:1 alpha:WXGClamp(left,0,1)].CGColor;
    _rightMask.backgroundColor=[UIColor colorWithWhite:1 alpha:WXGClamp(right,0,1)].CGColor;
    static NSCache<NSString *,UIImage *> *fields;static dispatch_once_t once;
    dispatch_once(&once,^{fields=[NSCache new];fields.countLimit=16;});
    _fieldImage=[fields objectForKey:key];
    if(!_fieldImage) {
        const size_t side=256;
        NSMutableData *pixels=[NSMutableData dataWithLength:side*side*4]; uint8_t *bytes=pixels.mutableBytes;
        for(size_t y=0;y<side;y++) for(size_t x=0;x<side;x++) {
            float nx=(float)x+.5f-side*.5f,ny=(float)y+.5f-side*.5f,length=MAX(hypotf(nx,ny),.01f);
            float v=level(nx/length,ny/length);
            uint8_t b=(uint8_t)lroundf(255*(v<0?0:v>1?1:v));
            size_t i=(y*side+x)*4; bytes[i]=b; bytes[i+1]=b; bytes[i+2]=b; bytes[i+3]=b;
        }
        CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGImageRef cg=CGImageCreate(side,side,8,32,side*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast,provider,NULL,YES,kCGRenderingIntentDefault);
        _fieldImage=[UIImage imageWithCGImage:cg];
        [fields setObject:_fieldImage forKey:key];
        CGImageRelease(cg); CGColorSpaceRelease(space); CGDataProviderRelease(provider);
    }
    for(CALayer *field in _cornerFields) field.contents=(__bridge id)_fieldImage.CGImage;
    [CATransaction commit];
}
- (void)layoutForBounds:(CGRect)bounds radius:(CGFloat)r {
    CGFloat w=bounds.size.width,h=bounds.size.height;
    self.frame=bounds;
    CGFloat straightW=MAX(0,w-2*r),straightH=MAX(0,h-2*r);
    _topMask.frame=CGRectMake(r,0,straightW,h*.5);_bottomMask.frame=CGRectMake(r,h*.5,straightW,h*.5);
    _leftMask.frame=CGRectMake(0,r,w*.5,straightH);_rightMask.frame=CGRectMake(w*.5,r,w*.5,straightH);
    for(NSUInteger i=0;i<4;i++) {
        BOOL right=(i&1)!=0,bottom=(i&2)!=0;
        _cornerMasks[i].frame=CGRectMake(right?w-r:0,bottom?h-r:0,r,r);
        _cornerFields[i].frame=CGRectMake(right?-r:0,bottom?-r:0,2*r,2*r);
    }
}
@end
@interface WXGRimFadeLayer : WXGRimFieldLayer
- (void)setFade:(CGFloat)fade topLeft:(CGFloat)topLeft bottomRight:(CGFloat)bottomRight;
@property(nonatomic,readonly) CGFloat fade;
@end
@implementation WXGRimFadeLayer {
    CGFloat _fade,_fadeTopLeft,_fadeBottomRight;
}
- (instancetype)init {
    if((self=[super init])){_fade=-1;_fadeTopLeft=-1;_fadeBottomRight=-1;}
    return self;
}
- (CGFloat)fade {return _fade;}
- (void)setFade:(CGFloat)fade topLeft:(CGFloat)topLeft bottomRight:(CGFloat)bottomRight {
    if(_fade==fade && _fadeTopLeft==topLeft && _fadeBottomRight==bottomRight) return;
    _fade=fade;_fadeTopLeft=topLeft;_fadeBottomRight=bottomRight;
    CGFloat topLeftAlpha=1-WXGClamp(topLeft,0,1),bottomRightAlpha=1-WXGClamp(bottomRight,0,1);
    [self applyTop:topLeftAlpha bottom:bottomRightAlpha left:topLeftAlpha right:bottomRightAlpha
          fieldKey:[NSString stringWithFormat:@"fade|%.4f|%.4f|%.4f",fade,topLeft,bottomRight]
             level:^float(float nx,float ny){return WXGRimStrengthTLBR(nx,ny,(float)fade,(float)topLeft,(float)bottomRight);}];
}
@end
// FIX86: the iOS 27-like rim's level along the outline (WXGRimGlow.h): the
// straight edges at their direction's level, the corners WXGRimGlowLevel of
// the direction from the corner's centre (continuous with both edges at the
// corner windows' sides). A capsule has no side edges: its two ends are
// corners. FIX87: the highlight's direction is an angle (0 the top and
// bottom brightest, 90 the two ends, between the diagonals); the top and
// bottom edges share a level, so do the two sides.
@interface WXGRimLevelLayer : WXGRimFieldLayer
- (void)setEndLevel:(CGFloat)endLevel sharpness:(CGFloat)sharpness angle:(CGFloat)angle;
@end
@implementation WXGRimLevelLayer {
    CGFloat _endLevel,_sharpness,_angle;
}
- (instancetype)init {
    if((self=[super init])){_endLevel=-1;_sharpness=-1;_angle=-1;}
    return self;
}
- (void)setEndLevel:(CGFloat)endLevel sharpness:(CGFloat)sharpness angle:(CGFloat)angle {
    if(_endLevel==endLevel && _sharpness==sharpness && _angle==angle)return;
    _endLevel=endLevel;_sharpness=sharpness;_angle=angle;
    CGFloat edges=(CGFloat)WXGRimGlowLevel(0,1,angle,endLevel,sharpness),sides=(CGFloat)WXGRimGlowLevel(1,0,angle,endLevel,sharpness);
    [self applyTop:edges bottom:edges left:sides right:sides fieldKey:[NSString stringWithFormat:@"level|%.4f|%.4f|%.3f",endLevel,sharpness,angle]
             level:^float(float nx,float ny){return (float)WXGRimGlowLevel(nx,ny,angle,endLevel,sharpness);}];
}
@end
// FIX75: the rim's details (WXGRimDetail.h). FIX78: everything is a Core
// Animation border or a shadow cast by one, on the rim's own continuous
// corners. FIX79: the line's two sides fade in 0.1 pt steps over their own
// widths (outer: from the outline in, inner: from the line's inner edge
// out), in opacity or in brightness. Each step is one more border, nested in
// the line, so the shading has exactly the rim's shape. The inner shadow is a
// thick border just outside the inner edge, clipped away, whose blurred
// shadow falls inward.
typedef struct {
    CGFloat outer,inner;                   // side fade widths (pt)
    CGFloat edge;                          // level at the very sides (1 = no fade)
    BOOL darken;                           // fade the brightness instead of the opacity
    CGFloat shadowRadius,shadowOpacity;    // inner shadow softness (pt) and opacity
    CGFloat shadowColor[3];
} WXGRimDetail;
// One border per band: the outline inset by the band's inset, with the corner
// radius inset with it, the band's width and opacity. Layers are pooled in z
// order (placed first = lowest); returns how many are in use.
static NSUInteger WXGRimPlaceBands(CALayer *holder,NSMutableArray<CALayer *> *pool,NSUInteger used,const WXGRimBands *bands,
                                   CGSize size,CGFloat radius,CGFloat red,CGFloat green,CGFloat blue,CGFloat scale) {
    for(int k=0;k<bands->count;k++) {
        CGFloat inset=(CGFloat)bands->inset[k],width=(CGFloat)bands->width[k],alpha=(CGFloat)bands->alpha[k];
        CGRect frame=CGRectInset((CGRect){CGPointZero,size},inset,inset);
        if(width<.001 || alpha<.001 || CGRectIsEmpty(frame))continue;
        CALayer *band;
        if(used<pool.count)band=pool[used];
        else {band=[CALayer layer];band.cornerCurve=kCACornerCurveContinuous;[holder addSublayer:band];[pool addObject:band];}
        ++used;
        band.hidden=NO;band.frame=frame;band.contentsScale=scale;
        band.cornerRadius=MAX(0,radius-inset);band.borderWidth=width;
        band.borderColor=[UIColor colorWithRed:red green:green blue:blue alpha:WXGClamp(alpha,0,1)].CGColor;
    }
    return used;
}
static void WXGRimHideBands(NSArray<CALayer *> *pool,NSUInteger used) {for(NSUInteger i=used;i<pool.count;i++)pool[i].hidden=YES;}
_Static_assert(WXG_RIM_GLOW_MAX_BANDS<=2*WXG_RIM_MAX_STEPS+1,"the glow's steps fit WXGRimBands");
static WXGRimBands WXGRimFullBand(double w) {WXGRimBands b;b.count=1;b.inset[0]=0;b.width[0]=w;b.alpha[0]=1;return b;}
// FIX89: one highlight of the iOS 27-like rim: its nested bands (its colour)
// under its level along the outline (the mask), the group at its opacity.
@interface WXGRimGlowLayer : CALayer
- (void)applyShape:(WXGRimGlowShape)shape bounds:(CGRect)bounds radius:(CGFloat)r scale:(CGFloat)scale;
@property(nonatomic,readonly) NSUInteger bandsShown;
@end
@implementation WXGRimGlowLayer {
    WXGRimLevelLayer *_level;
    NSMutableArray<CALayer *> *_bands;
    double _key[10];
}
- (instancetype)init {
    if((self=[super init])) {
        self.allowsGroupOpacity=YES;
        _level=[WXGRimLevelLayer layer];self.mask=_level;
        _bands=[NSMutableArray array];
    }
    return self;
}
- (void)applyShape:(WXGRimGlowShape)shape bounds:(CGRect)bounds radius:(CGFloat)r scale:(CGFloat)scale {
    if(shape.alpha<.002 || shape.width<.01){self.hidden=YES;return;}
    self.hidden=NO;
    self.opacity=(float)WXGClamp(shape.alpha,0,1);
    [_level setEndLevel:shape.endLevel sharpness:shape.sharpness angle:shape.angle];
    CGSize size=bounds.size;
    // Never past the middle of the shorter side.
    double width=MIN(shape.width,MIN(size.width,size.height)*.5);
    double key[10]={size.width,size.height,r,scale,width,shape.falloff,shape.red,shape.green,shape.blue,1};
    if(!memcmp(key,_key,sizeof key))return;
    memcpy(_key,key,sizeof key);
    self.frame=bounds;
    // The corner windows at least as large as the glow is wide: with a small
    // corner radius (a settings card at 卡片圆角 0) the side bands would
    // otherwise reach under the top / bottom edges' full level.
    [_level layoutForBounds:(CGRect){CGPointZero,size} radius:MAX(r,(CGFloat)MIN(width,MIN(size.width,size.height)*.5))];
    WXGRimBands bands;
    bands.count=WXGRimGlowBands(width,shape.falloff,scale,WXG_RIM_GLOW_MAX_BANDS,bands.inset,bands.width,bands.alpha);
    NSUInteger used=WXGRimPlaceBands(self,_bands,0,&bands,size,r,shape.red,shape.green,shape.blue,scale);
    WXGRimHideBands(_bands,used);_bandsShown=used;
}
@end
static NSHashTable *WXGRimViews;            // FIX74: every rim, for the export
@interface WXGRimView : UIView
@property(nonatomic) CGFloat maximumCornerRadius;
- (void)configureWidth:(CGFloat)width color:(UIColor *)color fade:(CGFloat)fade topLeft:(CGFloat)topLeft bottomRight:(CGFloat)bottomRight;
- (void)configureDetail:(const WXGRimDetail *)detail;   // FIX75: NULL = the plain rim
// FIX86: the iOS 27-like rim (WXGRimGlow.h) instead of the line: a light
// fading inward from the outline. FIX89: `count` of them (0 = off), each with
// its own colour and opacity (in the shape), the later drawn over the earlier.
- (void)configureGlows:(const WXGRimGlowShape *)shapes count:(NSInteger)count;
// FIX76: the line is drawn by the colour-sampling view above; this one keeps
// the inner shadow only.
@property(nonatomic) BOOL lineHidden;
// FIX79: under that line, black over the line's whole width at this opacity
// (the sampled colour is then added on top at each step's level, so the
// steps show it darkened); 0 = none.
@property(nonatomic) CGFloat underlayAlpha;
- (NSDictionary *)rimEvidence;
@end
@implementation WXGRimView {
    WXGRimFadeLayer *_fadeMask;
    CGFloat _width;
    UIColor *_color;
    BOOL _detailed,_stacked;
    WXGRimDetail _detail;
    CALayer *_lineStack,*_shadowClip,*_shadowRing;
    NSMutableArray<CALayer *> *_bands;
    NSUInteger _bandsShown;
    double _stackKey[12];
    BOOL _glow;                            // FIX86
    NSInteger _glowCount;                  // FIX89: the highlights
    WXGRimGlowShape _glowShapes[WXGRimGlowCount];
    NSMutableArray<WXGRimGlowLayer *> *_glowLayers;
}
- (instancetype)init {
    if((self=[super initWithFrame:CGRectZero])) {
        self.userInteractionEnabled=NO; self.opaque=NO; self.backgroundColor=UIColor.clearColor;
        self.layer.cornerCurve=kCACornerCurveContinuous;
        _fadeMask=[WXGRimFadeLayer layer];self.layer.mask=_fadeMask;
        if(!WXGRimViews)WXGRimViews=[NSHashTable weakObjectsHashTable];
        [WXGRimViews addObject:self];
    } return self;
}
- (void)configureWidth:(CGFloat)width color:(UIColor *)color fade:(CGFloat)fade topLeft:(CGFloat)topLeft bottomRight:(CGFloat)bottomRight {
    _width=width;_color=color;
    [self applyLine];
    [_fadeMask setFade:fade topLeft:topLeft bottomRight:bottomRight];
    if(_glow)[self setNeedsLayout];        // the glow's colour is laid out
}
- (void)setLineHidden:(BOOL)hidden {
    if(_lineHidden==hidden)return;
    _lineHidden=hidden;[self applyLine];[self setNeedsLayout];
}
- (void)setUnderlayAlpha:(CGFloat)alpha {
    if(fabs(_underlayAlpha-alpha)<.0005)return;
    _underlayAlpha=alpha;[self applyLine];[self setNeedsLayout];
}
- (void)configureDetail:(const WXGRimDetail *)detail {
    BOOL detailed=detail!=NULL;
    if(detailed==_detailed && (!detailed || !memcmp(detail,&_detail,sizeof _detail)))return;
    _detailed=detailed;
    if(detail)_detail=*detail;
    [self applyLine];[self setNeedsLayout];
}
- (void)configureGlows:(const WXGRimGlowShape *)shapes count:(NSInteger)count {
    count=shapes?MAX(0,MIN(count,(NSInteger)WXGRimGlowCount)):0;
    BOOL glow=count>0;
    if(glow==_glow && count==_glowCount && (!glow || !memcmp(shapes,_glowShapes,sizeof(WXGRimGlowShape)*(size_t)count)))return;
    _glow=glow;_glowCount=count;
    if(glow)memcpy(_glowShapes,shapes,sizeof(WXGRimGlowShape)*(size_t)count);
    [self applyLine];[self setNeedsLayout];
}
- (BOOL)stepped {return !_glow && _detailed && WXGRimStepped(_width,_detail.outer,_detail.inner,_detail.edge);}
// Plain line (no details, or nothing to shade): the view's own border, as in
// FIX72. Shaded sides: the bands in `_lineStack` instead.
- (void)applyLine {
    CGFloat r=0,g=0,b=0,a=0;
    if(![_color getRed:&r green:&g blue:&b alpha:&a]){r=g=b=1;a=0;}
    _stacked=[self stepped] && (!_lineHidden || _underlayAlpha>.002);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.layer.borderWidth=(_lineHidden || _stacked || _glow)?0:_width;
    self.layer.borderColor=[UIColor colorWithRed:r green:g blue:b alpha:a].CGColor;
    if(!_stacked)_lineStack.hidden=YES;
    if(!_glow)for(CALayer *layer in _glowLayers)layer.hidden=YES;
    [CATransaction commit];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height,r=MIN(w,h)*.5;
    if(_maximumCornerRadius>0)r=MIN(r,_maximumCornerRadius);
    self.layer.cornerRadius=r; self.layer.contentsScale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    [_fadeMask layoutForBounds:self.bounds radius:r];
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    [self layoutShadowRadius:r scale:scale];
    [self layoutLineRadius:r scale:scale];
    [self layoutGlowRadius:r scale:scale];
    [CATransaction commit];
}
// FIX86: the iOS 27-like rim: nested bands of the glass's own outline (Core
// Animation borders on its continuous corners, as the stepped line), all
// from the outline, each about 1 px wider than the last, composited into a
// light fading inward over the width (WXGRimGlowBands); so the rim is
// exactly as wide at the corners as along the top, whatever the shape. Over
// them, the level along the outline (WXGRimLevelLayer); the group at the
// highlight's opacity. FIX89: one WXGRimGlowLayer per highlight, in order.
- (void)layoutGlowRadius:(CGFloat)r scale:(CGFloat)scale {
    if(!_glow){for(CALayer *layer in _glowLayers)layer.hidden=YES;return;}
    if(!_glowLayers)_glowLayers=[NSMutableArray array];
    while((NSInteger)_glowLayers.count<_glowCount){WXGRimGlowLayer *layer=[WXGRimGlowLayer layer];[self.layer addSublayer:layer];[_glowLayers addObject:layer];}
    for(NSInteger i=0;i<(NSInteger)_glowLayers.count;i++) {
        if(i<_glowCount)[_glowLayers[i] applyShape:_glowShapes[i] bounds:self.bounds radius:r scale:scale];
        else _glowLayers[i].hidden=YES;
    }
}
- (void)layoutLineRadius:(CGFloat)r scale:(CGFloat)scale {
    if(!_stacked){_lineStack.hidden=YES;return;}
    if(!_lineStack) {
        // Group opacity: the bands are composited together first, then the
        // whole line at the rim's opacity.
        _lineStack=[CALayer layer];_lineStack.allowsGroupOpacity=YES;_bands=[NSMutableArray array];
        if(_shadowClip)[self.layer insertSublayer:_lineStack above:_shadowClip];else [self.layer addSublayer:_lineStack];
    }
    _lineStack.hidden=NO;
    CGFloat cr=0,cg=0,cb=0,ca=0;
    if(![_color getRed:&cr green:&cg blue:&cb alpha:&ca]){cr=cg=cb=1;ca=0;}
    CGSize size=self.bounds.size;
    double key[12]={size.width,size.height,r,scale,_width,_detail.outer,_detail.inner,_detail.edge,_detail.darken+2.*_lineHidden,cr,cg,cb};
    _lineStack.opacity=(float)WXGClamp(_lineHidden?_underlayAlpha:ca,0,1);
    if(!memcmp(key,_stackKey,sizeof key))return;
    memcpy(_stackKey,key,sizeof key);
    _lineStack.frame=self.bounds;
    NSUInteger used=0;
    if(_lineHidden) {
        WXGRimBands full=WXGRimFullBand(_width);
        used=WXGRimPlaceBands(_lineStack,_bands,used,&full,size,r,0,0,0,scale);
    }else if(_detail.darken) {
        // Brightness: the whole line at full strength, then black bands from
        // each side inward, more of them toward the very side.
        WXGRimBands full=WXGRimFullBand(_width),dim=WXGRimDimBands(_width,_detail.outer,_detail.inner,_detail.edge);
        used=WXGRimPlaceBands(_lineStack,_bands,used,&full,size,r,cr,cg,cb,scale);
        used=WXGRimPlaceBands(_lineStack,_bands,used,&dim,size,r,0,0,0,scale);
    }else {
        // Opacity: nested bands, each one step narrower on both sides.
        WXGRimBands steps=WXGRimAlphaBands(_width,_detail.outer,_detail.inner,_detail.edge);
        used=WXGRimPlaceBands(_lineStack,_bands,used,&steps,size,r,cr,cg,cb,scale);
    }
    WXGRimHideBands(_bands,used);_bandsShown=used;
}
- (void)layoutShadowRadius:(CGFloat)r scale:(CGFloat)scale {
    BOOL shadow=_detailed && _detail.shadowOpacity>.002 && _detail.shadowRadius>.01;
    if(!shadow){_shadowClip.hidden=YES;return;}
    if(!_shadowClip) {
        _shadowClip=[CALayer layer];_shadowClip.masksToBounds=YES;_shadowClip.cornerCurve=kCACornerCurveContinuous;
        _shadowRing=[CALayer layer];_shadowRing.cornerCurve=kCACornerCurveContinuous;_shadowRing.shadowOffset=CGSizeZero;
        _shadowRing.shouldRasterize=YES;
        [_shadowClip addSublayer:_shadowRing];[self.layer insertSublayer:_shadowClip atIndex:0];
    }
    _shadowClip.hidden=NO;
    // The inner shadow: the clip is the inside of the line (the rim's own
    // shape inset by its width); the ring is a thick border starting half a
    // point outside it (so none of it shows), its shadow blurs inward.
    CGRect inner=CGRectInset(self.bounds,_width,_width);
    if(inner.size.width<1 || inner.size.height<1){_shadowClip.hidden=YES;return;}
    CGFloat innerRadius=MAX(0,r-_width),thick=MAX(4,_detail.shadowRadius*3),gap=.5;
    _shadowClip.frame=inner;_shadowClip.cornerRadius=innerRadius;
    _shadowRing.frame=CGRectInset((CGRect){CGPointZero,inner.size},-(thick+gap),-(thick+gap));
    _shadowRing.cornerRadius=innerRadius+thick+gap;_shadowRing.borderWidth=thick;
    UIColor *color=[UIColor colorWithRed:_detail.shadowColor[0] green:_detail.shadowColor[1] blue:_detail.shadowColor[2] alpha:1];
    _shadowRing.borderColor=color.CGColor;_shadowRing.shadowColor=color.CGColor;
    _shadowRing.shadowOpacity=(float)WXGClamp(_detail.shadowOpacity,0,1);_shadowRing.shadowRadius=_detail.shadowRadius;
    _shadowRing.rasterizationScale=scale;
}
- (NSArray *)glowEvidence {
    NSMutableArray *out=[NSMutableArray array];
    for(NSInteger i=0;i<_glowCount;i++) {
        WXGRimGlowShape g=_glowShapes[i];
        [out addObject:@{@"width":@(g.width),@"falloff":@(g.falloff),@"endLevel":@(g.endLevel),@"sharpness":@(g.sharpness),@"angle":@(g.angle),
                         @"colour":@[@(round(g.red*1000)/1000),@(round(g.green*1000)/1000),@(round(g.blue*1000)/1000)],@"opacity":@(round(g.alpha*1000)/1000),
                         @"bands":@(i<(NSInteger)_glowLayers.count?_glowLayers[i].bandsShown:0)}];
    }
    return out;
}
- (NSDictionary *)rimEvidence {
    return @{@"details":@(_detailed),@"width":@(round(_width*100)/100),@"outerFade":@(_detailed?_detail.outer:0),@"innerFade":@(_detailed?_detail.inner:0),
             @"sideLevel":@(_detailed?_detail.edge:1),@"darken":@(_detailed && _detail.darken),@"stepped":@(_stacked),@"bands":@(_stacked?_bandsShown:0),
             @"underlay":@(round(_underlayAlpha*1000)/1000),@"shadowOpacity":@(_detailed?_detail.shadowOpacity:0),@"shadowRadius":@(_detailed?_detail.shadowRadius:0),
             @"fade":@(_fadeMask.fade),@"size":@[@(round(self.bounds.size.width*10)/10),@(round(self.bounds.size.height*10)/10)],
             @"cornerRadius":@(round(self.layer.cornerRadius*10)/10),@"lineHidden":@(_lineHidden),@"onScreen":@(self.window!=nil && !self.hidden),
             @"glow":_glow?[self glowEvidence]:@NO};
}
@end
// FIX76/78: the line coloured from what is behind the glass. The view's own
// layer is a backdrop in the glass's backdrop group (it reuses the glass's
// capture of the page behind it), blurred and colour-matrixed
// (WXGRimSampleMatrix). FIX78: its mask is the rim itself, made of the same
// layers as WXGRimView: Core Animation borders with the rim's continuous
// corners, under the same fade layer tree. Nothing is drawn into images, so
// the line has exactly the rim's shape, at every size, every frame. FIX79:
// the mask is the stepped opacity bands; for darkened sides the line is
// added (plus-lighter) over the black the rim view puts under it, so a step
// at level L shows the colour times L at the line's opacity.
typedef struct { CGFloat saturation,contrast,gain,lift,brightness,blur,captureScale; BOOL plusLighter; } WXGRimSample;
static NSHashTable *WXGRimTintViews;
@interface WXGRimTintView : UIView
@property(nonatomic) CGFloat maximumCornerRadius;
@property(nonatomic,copy) NSString *backdropGroup;
// Returns whether the coloured line is in use (then the rim must hide its own).
- (BOOL)configureWidth:(CGFloat)width alpha:(CGFloat)alpha outer:(CGFloat)outer inner:(CGFloat)inner edge:(CGFloat)edge
             overBlack:(BOOL)overBlack fade:(CGFloat)fade sample:(const WXGRimSample *)sample;
- (NSDictionary *)tintEvidence;
@end
@implementation WXGRimTintView {
    CALayer *_maskRoot,*_ringHolder;
    NSMutableArray<CALayer *> *_bands;
    NSUInteger _bandsShown;
    WXGRimFadeLayer *_fadeMask;
    NSString *_appliedGroup;
    CGFloat _width,_alpha,_outer,_inner,_edge,_appliedScale,_appliedBlur;
    WXGRimSample _sample;
    BOOL _on,_overBlack,_matrixApplied,_appliedPlus,_blendSet;
    WXGRimMatrix _appliedMatrix;
}
+ (Class)layerClass {return WXGBackdropLayerClass()?:CALayer.class;}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.hidden=YES;
        // The mask: a plain container holding the rim's bands; the fade is on
        // that holder (never on an ancestor of the backdrop itself).
        _maskRoot=[CALayer layer];_ringHolder=[CALayer layer];_bands=[NSMutableArray array];
        [_maskRoot addSublayer:_ringHolder];
        _fadeMask=[WXGRimFadeLayer layer];_ringHolder.mask=_fadeMask;
        if([self live])@try {[self.layer setValue:@YES forKey:@"enabled"];} @catch(__unused NSException *error) {}
        self.layer.mask=_maskRoot;
        if(!WXGRimTintViews)WXGRimTintViews=[NSHashTable weakObjectsHashTable];
        [WXGRimTintViews addObject:self];
    }
    return self;
}
- (BOOL)live {Class cls=WXGBackdropLayerClass();return cls && [self.layer isKindOfClass:cls];}
- (BOOL)configureWidth:(CGFloat)width alpha:(CGFloat)alpha outer:(CGFloat)outer inner:(CGFloat)inner edge:(CGFloat)edge
             overBlack:(BOOL)overBlack fade:(CGFloat)fade sample:(const WXGRimSample *)sample {
    BOOL on=sample && [self live] && width>.01;
    if(!on){_on=NO;if(!self.hidden)self.hidden=YES;return NO;}
    _on=YES;_width=width;_alpha=alpha;_outer=outer;_inner=inner;_edge=edge;_overBlack=overBlack;_sample=*sample;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    [_fadeMask setFade:fade topLeft:0 bottomRight:0];
    [self layoutRing];
    [self applyStyle];
    [CATransaction commit];
    return YES;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(!_on)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    [self layoutRing];
    [CATransaction commit];
}
- (void)layoutRing {
    CGRect bounds=self.bounds;
    CGFloat w=bounds.size.width,h=bounds.size.height,r=MIN(w,h)*.5;
    if(_maximumCornerRadius>0)r=MIN(r,_maximumCornerRadius);
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    _maskRoot.frame=bounds;_ringHolder.frame=bounds;
    // One full band when nothing is shaded (the plain line).
    WXGRimBands steps=WXGRimAlphaBands(_width,_outer,_inner,_edge);
    NSUInteger used=WXGRimPlaceBands(_ringHolder,_bands,0,&steps,bounds.size,r,1,1,1,scale);
    WXGRimHideBands(_bands,used);_bandsShown=used;
    [_fadeMask layoutForBounds:bounds radius:r];
    _ringHolder.opacity=(float)WXGClamp(_alpha,0,1);
}
- (void)applyStyle {
    BOOL show=_alpha>.002;
    if(self.hidden==show)self.hidden=!show;
    if(!show)return;
    WXGRimMatrix m=WXGRimSampleMatrix(_sample.saturation,_sample.contrast,_sample.gain,_sample.lift,_sample.brightness);
    @try {
        if(_backdropGroup && ![_appliedGroup isEqual:_backdropGroup]){[self.layer setValue:_backdropGroup forKey:@"groupName"];_appliedGroup=_backdropGroup;}
        CGFloat screen=self.window.screen.scale?:UIScreen.mainScreen.scale,scale=_sample.captureScale>.01?_sample.captureScale:screen;
        if(fabs(scale-_appliedScale)>.01) {
            [self.layer setValue:@(scale) forKey:@"scale"];self.layer.contentsScale=MAX(scale,screen);self.layer.rasterizationScale=MAX(scale,screen);
            _appliedScale=scale;
        }
        if(!_matrixApplied || memcmp(&m,&_appliedMatrix,sizeof m) || fabs(_appliedBlur-_sample.blur)>.01) {
            NSMutableArray *filters=[NSMutableArray array];
            id blur=_sample.blur>=.2?WXGMakeBlurFilter(_sample.blur):nil;
            if(blur)[filters addObject:blur];
            id matrix=WXGFilterFactoryAvailable()?[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"]:nil;
            [matrix setValue:[NSValue valueWithBytes:&m objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
            if(matrix)[filters addObject:matrix];
            [self.layer setValue:@(MAX(2.,_sample.blur*3.)) forKey:@"marginWidth"];
            self.layer.filters=filters.count?filters:nil;
            _appliedMatrix=m;_matrixApplied=YES;_appliedBlur=_sample.blur;
        }
        BOOL plus=_sample.plusLighter || _overBlack;
        if(!_blendSet || _appliedPlus!=plus) {
            self.layer.compositingFilter=plus?WXGMakePlusLighter():nil;_appliedPlus=plus;_blendSet=YES;
        }
    } @catch(__unused NSException *error) {}
}
- (NSDictionary *)tintEvidence {
    return @{@"on":@(_on),@"shown":@(_on && !self.hidden && self.window!=nil),@"opacity":@(round(_alpha*1000)/1000),@"width":@(round(_width*100)/100),
             @"outerFade":@(_outer),@"innerFade":@(_inner),@"sideLevel":@(_edge),@"bands":@(_bandsShown),@"overBlack":@(_overBlack),
             @"group":_appliedGroup?:@"none",@"plusLighter":@(_appliedPlus),@"captureScale":@(_appliedScale),
             @"size":@[@(round(self.bounds.size.width*10)/10),@(round(self.bounds.size.height*10)/10)]};
}
@end
// FIX74: every rim at once, for the diagnostics export (any page).
NSDictionary *WXGRimSummary(void) {
    NSUInteger shown=0,detailed=0,tinted=0,hiddenLines=0;NSMutableArray *samples=[NSMutableArray array],*tints=[NSMutableArray array];
    for(WXGRimView *view in WXGRimViews.allObjects) {
        NSDictionary *e=[view rimEvidence];
        if(![e[@"onScreen"] boolValue])continue;
        ++shown;if([e[@"details"] boolValue])++detailed;
        if([e[@"lineHidden"] boolValue])++hiddenLines;
        if(samples.count<8)[samples addObject:e];
    }
    for(WXGRimTintView *view in WXGRimTintViews.allObjects) {
        NSDictionary *e=[view tintEvidence];
        if(![e[@"shown"] boolValue])continue;
        ++tinted;if(tints.count<8)[tints addObject:e];
    }
    WXGConfig *c=WXGConfig.shared;
    NSArray *names=@[@"classic",@"sampled",@"glow"];
    NSDictionary *styles=@{@"dock":names[[c rimStyleForScope:WXGGlassScopeDock]],@"other":names[[c rimStyleForScope:WXGGlassScopeOther]],
                           @"bubble":names[[c rimStyleForScope:WXGGlassScopeBubble]]};
    return @{@"details":@(c.rimDetails),@"sampleColor":@(c.rimSampleColor),@"styles":styles,@"rimsOnScreen":@(shown),@"detailedOnScreen":@(detailed),
             @"classicLinesHidden":@(hiddenLines),@"backgroundLinesOnScreen":@(tinted),@"all":@(WXGRimViews.count),@"samples":samples,@"tints":tints};
}

@interface WXGBackdropFrame : NSObject
@property(nonatomic,strong) id<MTLBuffer> pixels;
@property(nonatomic,strong) id<MTLTexture> texture, blurTemp, blurred, lensBlurTemp, lensBlurred;
@property(nonatomic) CGContextRef context;
@property(nonatomic) NSUInteger width,height,stride,busy;
@property(nonatomic) BOOL needsBlur,needsLensBlur;
@property(nonatomic,strong) WXGBackdropSample *pendingSample;
@property(nonatomic) CGAffineTransform copyTransform;
@property(nonatomic) CGFloat copyScale;
@property(nonatomic) CFTimeInterval sourceCapturedAt;
@property(nonatomic) CGFloat blurSigma,lensBlurSigma;
@end
@implementation WXGBackdropFrame
- (void)dealloc { [_pendingSample releaseLease];if(_context)CGContextRelease(_context); }
@end

@interface WXGGlassView ()
@property(nonatomic) NSUInteger resumes,canvasGeneration;
@property(nonatomic) CFTimeInterval drawWait;
@property(nonatomic,strong) NSHashTable<UIView *> *weakBackdropExclusions;
@property(nonatomic,strong) WXGMetalSurface *metal, *lensMetal;
@property(nonatomic,strong) UIView *bodyClip, *lensClip;
@property(nonatomic,strong) WXGRimView *bodyRim, *lensRim;
@property(nonatomic,strong) WXGRimTintView *bodyTint;   // FIX76
@property(nonatomic,strong) id<MTLTexture> bodyMask;
@property(nonatomic) CGRect maskRect;
@property(nonatomic) CGSize maskSize;
@property(nonatomic) CGFloat maskScale, maskCornerRadius;
@property(nonatomic) BOOL maskPending;
@property(nonatomic) NSUInteger maskRequest;
@property(nonatomic) NSUInteger backdropRevision,activationGeneration;
@property(nonatomic) CGRect capturedSourceRect;
@property(nonatomic) CGAffineTransform capturedCopyTransform;
@property(nonatomic) BOOL needsDraw;
@property(nonatomic,strong) id<MTLDevice> gpu;
@property(nonatomic,strong) id<MTLCommandQueue> queue;
@property(nonatomic,strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic,strong) id<MTLComputePipelineState> blurPipeline,backdropCopyPipeline;
@property(nonatomic,strong) MTKTextureLoader *textureLoader;
@property(nonatomic,strong) id<MTLTexture> normalIcons, selectedIcons;
@property(nonatomic,strong) NSMutableArray<WXGBackdropFrame *> *pool;
@property(nonatomic,strong) WXGBackdropFrame *currentFrame;
@property(nonatomic,strong) dispatch_semaphore_t inFlight;
@property(nonatomic) BOOL ready,capturing,hasPresentedFrame;
@property(nonatomic) CFTimeInterval lastCapture,lastDraw,statisticsStart;
@property(nonatomic) CGFloat captureMilliseconds,toneLevel;
@property(nonatomic) NSUInteger captures,draws,skippedFrames,captureFailures,poolSkips;
@property(nonatomic) double drawableAcquireMS,lastGPUms;
@property(nonatomic) NSUInteger completedFrames;
@property(atomic) NSUInteger presentedFrames,presentedBackdropUpdates,presentedRevision;
@property(atomic) CFTimeInterval lastPresentedTime;
@property(atomic) double presentIntervalMS,presentedBackdropAgeMS;
@property(nonatomic,copy) NSString *failure;
@end

// FIX16: post-commit glass frames. The host's display callback updates every
// surface's geometry first; the glass copy/blur/optics then run after Core
// Animation has committed this runloop pass (see WXGIntegrationHost). Reading
// presentation layers before the commit returns MODEL values for animations
// started earlier in the same pass, i.e. the animation's END state.
static NSUInteger WXGGlassDeferDepth;
static NSMutableArray<WXGGlassView *> *WXGPendingGlass;
void WXGBeginDeferredGlassTicks(void) {NSCAssert(NSThread.isMainThread,@"glass deferral thread");++WXGGlassDeferDepth;}
void WXGEndDeferredGlassTicks(void) {NSCAssert(NSThread.isMainThread,@"glass deferral thread");if(WXGGlassDeferDepth)--WXGGlassDeferDepth;}
NSUInteger WXGDeferredGlassTickCount(void) {return WXGPendingGlass.count;}
@interface WXGGlassView ()
- (void)runTick:(CFTimeInterval)time;
- (void)clearPendingTick;
- (void)applySyncMode;
- (void)updateEdgeMask:(WXGConfig *)c;
- (void)applyStack:(NSArray<WXGSyncBackdropView *> *)stack visible:(BOOL)visible split:(BOOL)split radius:(CGFloat)radius
            optics:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality mesh:(BOOL)mesh;
@end
// FIX19: with presentsWithTransaction the drawables join the Core Animation
// transaction that carries WeChat's own frame, so both are displayed together.
// All glass command buffers share one queue; waiting for the last one to be
// scheduled covers every earlier one, so the main thread waits once per frame.
static BOOL WXGPresentBatching;
static NSMutableArray<id<CAMetalDrawable>> *WXGBatchDrawables;
static id<MTLCommandBuffer> WXGBatchLastBuffer;
static double WXGLastScheduleWaitMS;
double WXGGlassScheduleWaitMS(void) {return WXGLastScheduleWaitMS;}
void WXGFlushDeferredGlassTicks(void) {
    NSCAssert(NSThread.isMainThread,@"glass deferral thread");
    if(!WXGPendingGlass.count)return;
    NSArray<WXGGlassView *> *pending=WXGPendingGlass.copy;[WXGPendingGlass removeAllObjects];
    if(!WXGBatchDrawables)WXGBatchDrawables=[NSMutableArray array];
    WXGPresentBatching=YES;
    @try {for(WXGGlassView *glass in pending)[glass runTick:CACurrentMediaTime()];}
    @finally {
        WXGPresentBatching=NO;
        if(WXGBatchDrawables.count) {
            CFTimeInterval wait=CACurrentMediaTime();
            [WXGBatchLastBuffer waitUntilScheduled];
            WXGLastScheduleWaitMS=(CACurrentMediaTime()-wait)*1000;
            for(id<CAMetalDrawable> drawable in WXGBatchDrawables)[drawable present];
        }
        [WXGBatchDrawables removeAllObjects];WXGBatchLastBuffer=nil;
    }
}
void WXGDropDeferredGlassTicks(void) {
    NSArray<WXGGlassView *> *pending=WXGPendingGlass.copy;[WXGPendingGlass removeAllObjects];
    for(WXGGlassView *glass in pending)[glass clearPendingTick];
}

@implementation WXGGlassView {
    BOOL _tickPending;
    CFTimeInterval _pendingTickTime;
    NSInteger _syncMode;
    CALayer *_veilFallback;
    NSString *_veilMaskKey;
    NSUInteger _veilRevision,_veilReorders;
    NSString *_syncGroup;
    NSArray<UIColor *> *_lensOutlineColors;NSArray<NSNumber *> *_lensOutlineWidths;   // FIX88 (FIX89: one per highlight)
    WXGSyncBackdropView *_bodyBackdrop,*_lensBackdrop;
    // FIX20: unblurred backdrop for TEST9's clear refracted edge ring.
    WXGSyncBackdropView *_edgeBackdrop;
    CALayer *_edgeMask;
    // FIX23: [0] red or full colour, [1] green, [2] blue (render-server dispersion).
    NSArray<WXGSyncBackdropView *> *_bodyStack,*_edgeStack,*_lensStack;
    NSArray<CALayer *> *_edgeMasks;
    float _edgeMaskKey[5];
    // FIX57: last end relaxation of the lens band (0 FIX47 band .. 1 top width).
    float _endReachLeft,_endReachRight;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO; self.opaque=NO;
        _inFlight=dispatch_semaphore_create(2); _toneLevel=.8; _barScale=1; _pool=[NSMutableArray array]; _selectionWeight=-1;
        WXGCalmRegister(self);   // FIX85/88: measured for 平稳背景时加强材质 when that is on
        WXGRegisterBackdropView(self);
        _gpu=WXGSharedDevice();
        if(!_gpu) { _failure=@"此设备没有可用 Metal device"; WXGLog(@"%@",_failure); return self; }
        _queue=WXGSharedQueue();
        _normalIcons=_selectedIcons=WXGTransparentTexture();_needsDraw=YES; _textureLoader=[[MTKTextureLoader alloc] initWithDevice:_gpu];
        _bodyClip=[[UIView alloc] initWithFrame:CGRectZero]; _lensClip=[[UIView alloc] initWithFrame:CGRectZero];
        for(UIView *clip in @[_bodyClip,_lensClip]) {
            clip.userInteractionEnabled=NO; clip.opaque=NO; clip.backgroundColor=UIColor.clearColor;
            clip.clipsToBounds=YES; clip.layer.cornerCurve=kCACornerCurveContinuous;
            [self addSubview:clip];
        }
        _metal=[self makeMetalView]; _lensMetal=[self makeMetalView];
        [_bodyClip addSubview:_metal]; [_lensClip addSubview:_lensMetal];
        _syncGroup=[NSString stringWithFormat:@"wxg.glass.%p",self];
        // Bottom to top inside the body clip: body R,G,B, edge-ring R,G,B, Metal.
        NSMutableArray *bodyStack=[NSMutableArray array],*edgeStack=[NSMutableArray array],*lensStack=[NSMutableArray array],*masks=[NSMutableArray array];
        for(int i=0;i<3;i++) {
            WXGSyncBackdropView *b=[[WXGSyncBackdropView alloc] initWithFrame:CGRectZero],*e=[[WXGSyncBackdropView alloc] initWithFrame:CGRectZero];
            WXGSyncBackdropView *l=[[WXGSyncBackdropView alloc] initWithFrame:CGRectZero];
            b.hidden=e.hidden=l.hidden=YES;
            [bodyStack addObject:b];[edgeStack addObject:e];[lensStack addObject:l];
            CALayer *mask=[CALayer layer];mask.contentsGravity=kCAGravityResize;[masks addObject:mask];
        }
        _bodyStack=bodyStack;_edgeStack=edgeStack;_lensStack=lensStack;_edgeMasks=masks;
        for(WXGSyncBackdropView *v in _bodyStack)[_bodyClip insertSubview:v belowSubview:_metal];
        for(WXGSyncBackdropView *v in _edgeStack)[_bodyClip insertSubview:v belowSubview:_metal];
        // FIX35: the material veil as a plain render-server layer, shown until
        // the first Metal overlay frame (cold start: target material at once).
        _veilFallback=[CALayer layer];_veilFallback.hidden=YES;
        [_bodyClip.layer insertSublayer:_veilFallback below:_metal.layer];
        for(WXGSyncBackdropView *v in _lensStack)[_lensClip insertSubview:v belowSubview:_lensMetal];
        _bodyBackdrop=_bodyStack[0];_edgeBackdrop=_edgeStack[0];_lensBackdrop=_lensStack[0];_edgeMask=_edgeMasks[0];
        _bodyRim=[WXGRimView new]; _lensRim=[WXGRimView new];
        [self insertSubview:_bodyRim belowSubview:_lensClip]; [self addSubview:_lensRim];
        // FIX95 drew the lens on circular corners to match the shader; FIX96
        // keeps Core Animation's continuous ones (the tester: circular corners
        // look like Android) and the shader's capsule follows them instead
        // (WXGContinuousCorrection, measured on the tester's phone).
        _bodyTint=[[WXGRimTintView alloc] initWithFrame:CGRectZero];
        [self insertSubview:_bodyTint aboveSubview:_bodyRim];
        __weak WXGGlassView *weakSelf=self;
        WXGPrepareMetal(^(id<MTLRenderPipelineState> state,id<MTLComputePipelineState> blur,id<MTLComputePipelineState> copy,NSString *failure) {
            WXGGlassView *view=weakSelf;if(!view)return;
            view.pipeline=state;view.blurPipeline=blur;view.backdropCopyPipeline=copy;view.ready=state && blur && copy;
            if(!view.ready)view.failure=failure;
            if(view.onReady)view.onReady(view.ready);[view invalidateBackdrop];
        });
    } return self;
}
- (WXGMetalSurface *)makeMetalView {
    WXGMetalSurface *view=[[WXGMetalSurface alloc] initWithFrame:self.bounds];
    view.metalLayer.device=_gpu; view.metalLayer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    view.metalLayer.framebufferOnly=YES;view.metalLayer.maximumDrawableCount=3;
    view.metalLayer.allowsNextDrawableTimeout=YES; view.metalLayer.opaque=NO;
    view.opaque=NO; view.backgroundColor=UIColor.clearColor; view.userInteractionEnabled=NO;
    return view;
}
- (void)setGlassRect:(CGRect)rect { if(CGRectEqualToRect(_glassRect,rect)) return; _glassRect=rect; [self setNeedsLayout]; }
- (void)setBarScale:(CGFloat)scale { if(_barScale==scale) return; _barScale=MAX(1,scale); [self setNeedsLayout]; }
- (CGRect)drawnBarRect { return CGRectInset(_glassRect,-_glassRect.size.width*(_barScale-1)*.5,-_glassRect.size.height*(_barScale-1)*.5); }
- (void)setLensRect:(CGRect)rect { if(CGRectEqualToRect(_lensRect,rect)) return; _lensRect=rect; [self setNeedsLayout]; }
- (NSString *)renderState {
    NSArray<CALayer *> *order=_bodyClip.layer.sublayers;
    CGFloat veilAlpha=_veilFallback.backgroundColor?CGColorGetAlpha(_veilFallback.backgroundColor):-1;
    return [NSString stringWithFormat:@"玻璃 隐%d 透%.2f 窗%d 活%d 就绪%d 首帧%d | 区 %.0fx%.0f 夹 %.0fx%.0f | 遮盖 隐%d %.0fx%.0f α%.2f 位%lu/%lu 重排%lu | 模糊层 隐%d | Metal 隐%d",
        self.hidden,self.alpha,self.window!=nil,_active,_ready,_hasPresentedFrame,_glassRect.size.width,_glassRect.size.height,
        _bodyClip.bounds.size.width,_bodyClip.bounds.size.height,_veilFallback.hidden,_veilFallback.bounds.size.width,_veilFallback.bounds.size.height,veilAlpha,
        (unsigned long)[order indexOfObjectIdenticalTo:_veilFallback],(unsigned long)order.count,(unsigned long)_veilReorders,_bodyBackdrop.hidden,_metal.hidden];
}
- (void)setOverlayHidden:(BOOL)hidden {
    if(_overlayHidden==hidden)return;
    _overlayHidden=hidden;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _metal.hidden=hidden;_lensMetal.hidden=hidden;
    [CATransaction commit];
}
- (void)setLensSuppressed:(BOOL)suppressed {
    if(_lensSuppressed==suppressed)return;
    _lensSuppressed=suppressed;_needsDraw=YES;[self setNeedsLayout];
}
- (void)setPressAmount:(CGFloat)amount { if(fabs(_pressAmount-amount)<.0001)return;_pressAmount=amount;_needsDraw=YES;[self setNeedsLayout]; }
- (void)setSelectionWeight:(CGFloat)weight {   // FIX98
    if(weight>=0)weight=MIN(weight,1);else weight=-1;
    if(fabs(_selectionWeight-weight)<.0005)return;
    _selectionWeight=weight;_needsDraw=YES;
}
- (void)setMaximumCornerRadius:(CGFloat)radius {if(_maximumCornerRadius==radius)return;_maximumCornerRadius=radius;_bodyMask=nil;_needsDraw=YES;[self setNeedsLayout];}
- (CGFloat)radiusForRect:(CGRect)rect scale:(CGFloat)scale {return _maximumCornerRadius>0?MIN(MIN(rect.size.width,rect.size.height)*.5,_maximumCornerRadius*scale):MIN(rect.size.width,rect.size.height)*.5;}
- (void)applyStyle { _needsDraw=YES;[self setNeedsLayout]; [self layoutIfNeeded]; }
// UIKit rasterization remains on main. The exact TEST9 distance transform and
// float conversion run on one serial worker; there is at most one job per view.
- (void)refreshBodyMask {
    CGFloat scale=[self screenScale],corner=_maximumCornerRadius;
    CGRect rect=_glassRect;CGSize size=self.bounds.size;
    if(!_gpu || _maskPending || CGRectIsEmpty(rect) || CGRectIsEmpty(self.bounds))return;
    if(_bodyMask && CGRectEqualToRect(_maskRect,rect) && CGSizeEqualToSize(_maskSize,size) && _maskScale==scale && _maskCornerRadius==corner)return;
    @try {
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
        format.scale=scale;format.opaque=NO;format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        CALayer *shape=[CALayer layer];shape.bounds=(CGRect){CGPointZero,rect.size};
        shape.cornerRadius=[self radiusForRect:rect scale:1];shape.cornerCurve=kCACornerCurveContinuous;
        shape.masksToBounds=YES;shape.contentsScale=scale;shape.backgroundColor=UIColor.whiteColor.CGColor;
        UIImage *mask=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
            CGContextTranslateCTM(context.CGContext,rect.origin.x,rect.origin.y);[shape renderInContext:context.CGContext];
        }];
        CGImageRef cg=mask.CGImage;if(!cg)return;
        size_t w=CGImageGetWidth(cg),h=CGImageGetHeight(cg),stride=CGImageGetBytesPerRow(cg);
        CGImageAlphaInfo info=CGImageGetAlphaInfo(cg);
        BOOL first=info==kCGImageAlphaPremultipliedFirst || info==kCGImageAlphaFirst;
        BOOL last=info==kCGImageAlphaPremultipliedLast || info==kCGImageAlphaLast;
        if(CGImageGetBitsPerPixel(cg)!=32 || CGImageGetBitsPerComponent(cg)!=8 || !(first || last))return;
        size_t ai=first?0:3;
        if((CGImageGetBitmapInfo(cg)&kCGBitmapByteOrderMask)==kCGBitmapByteOrder32Little)ai=3-ai;
        NSData *bytes=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(cg)));
        if(!bytes || !w || !h || bytes.length<stride*h)return;
        id<MTLDevice> gpu=_gpu;NSUInteger request=++_maskRequest;_maskPending=YES;
        static dispatch_queue_t worker;static dispatch_once_t once;
        dispatch_once(&once,^{worker=dispatch_queue_create("com.runyu.wxglass.distance",DISPATCH_QUEUE_SERIAL);});
        __weak WXGGlassView *weakSelf=self;
        dispatch_async(worker,^{@autoreleasepool {
            id<MTLTexture> texture=nil;NSString *failure=nil;
            @try {
                const uint8_t *raw=bytes.bytes;
                NSMutableData *alpha=[NSMutableData dataWithLength:w*h],*field=[NSMutableData dataWithLength:w*h*sizeof(float)];
                uint8_t *a=alpha.mutableBytes;
                for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++)a[y*w+x]=raw[y*stride+x*4+ai];
                if(WXGMakeNativeDistance(a,(int)w,(int)h,(float)scale,field.mutableBytes)) {
                    NSMutableData *encoded=[NSMutableData dataWithLength:w*h*sizeof(__fp16)];
                    const float *distance=field.bytes;__fp16 *half=encoded.mutableBytes;
                    for(size_t i=0;i<w*h;i++)half[i]=(__fp16)distance[i];
                    MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR16Float width:w height:h mipmapped:NO];
                    desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead;
                    texture=[gpu newTextureWithDescriptor:desc];
                    [texture replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:encoded.bytes bytesPerRow:w*sizeof(__fp16)];
                }
                if(!texture)failure=@"原生轮廓距离生成失败，使用胶囊距离回退";
            } @catch(NSException *error){failure=error.reason?:error.name;}
            dispatch_async(dispatch_get_main_queue(),^{
                WXGGlassView *view=weakSelf;if(!view || view.maskRequest!=request)return;
                view.maskPending=NO;
                if(!CGRectEqualToRect(view.glassRect,rect) || !CGSizeEqualToSize(view.bounds.size,size) ||
                   [view screenScale]!=scale || view.maximumCornerRadius!=corner){[view setNeedsLayout];return;}
                if(failure){view.failure=failure;return;}
                view.bodyMask=texture;view.maskRect=rect;view.maskSize=size;view.maskScale=scale;view.maskCornerRadius=corner;
                view.needsDraw=YES;
            });
        }});
    } @catch(NSException *error){_failure=error.reason?:error.name;}
}
// FIX85: whose optics and rim this glass uses.
- (WXGGlassScope)glassScope {return _dockSurface?WXGGlassScopeDock:_bubbleSurface?WXGGlassScopeBubble:WXGGlassScopeOther;}
- (void)setBubbleSurface:(BOOL)bubble {
    if(_bubbleSurface==bubble)return;
    _bubbleSurface=bubble;_needsDraw=YES;[self setNeedsLayout];[self invalidateBackdrop];
}
- (void)setCalmFactor:(CGFloat)factor {
    factor=WXGClamp(isfinite(factor)?factor:0,0,1);
    if(fabs(factor-_calmFactor)<.004)return;
    _calmFactor=factor;
    if(WXGConfig.shared.calmMaterialEnabled && !_veilOverride){_needsDraw=YES;[self setNeedsLayout];}
}
- (void)setVeilOverrideFade:(CGFloat)fade {
    if(fabs(fade-_veilOverrideFade)<.01)return;
    _veilOverrideFade=fade;_needsDraw=YES;[self setNeedsLayout];
}
- (void)setVeilOverride:(UIColor *)color {
    if(color==_veilOverride || [color isEqual:_veilOverride])return;
    _veilOverride=color;_needsDraw=YES;[self setNeedsLayout];
}
- (NSString *)backdropGroupName {return WXGEffectiveRenderMode()>=2 && _bodyStack.count?_syncGroup:nil;}
- (UIColor *)veilColor {return _veilFallback.backgroundColor?[UIColor colorWithCGColor:_veilFallback.backgroundColor]:nil;}
- (NSArray<UIColor *> *)lensOutlineColors {return _lensOutlineColors?:@[];}
- (NSArray<NSNumber *> *)lensOutlineWidths {return _lensOutlineWidths?:@[];}
- (void)setRimAlwaysDark:(BOOL)always {
    if(_rimAlwaysDark==always)return;
    _rimAlwaysDark=always;_needsDraw=YES;[self setNeedsLayout];
}
- (BOOL)darkAppearance {return self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if(previous && ![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])return;
    _needsDraw=YES;[self setNeedsLayout];[self invalidateBackdrop];
}
- (CGFloat)screenScale { return WXGCaptureScale(self.window.screen.scale?:UIScreen.mainScreen.scale); }
- (void)layoutSubviews {
    [super layoutSubviews]; _needsDraw=YES;CGFloat scale=[self screenScale]; WXGConfig *c=WXGConfig.shared;
    CGSize size=CGSizeMake(MAX(1,round(self.bounds.size.width*scale)),MAX(1,round(self.bounds.size.height*scale)));
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect drawnBar=[self drawnBarRect];
    _bodyClip.frame=drawnBar; _lensClip.frame=_lensRect;
    _lensClip.hidden=_lensSuppressed;
    {
        [CATransaction begin];[CATransaction setDisableActions:YES];   // a standalone layer: no implicit animations
        WXGConfig *v=WXGConfig.shared;BOOL darkVeil=[self darkAppearance];
        UIColor *veil=WXGColor(_dockSurface?(darkVeil?v.dockDarkMaterialHex:v.dockMaterialHex):(darkVeil?v.darkMaterialHex:v.materialHex));
        CGFloat veilAlpha=_dockSurface?(darkVeil?v.dockDarkMaterialOpacity:v.dockMaterialOpacity):(darkVeil?v.darkMaterialOpacity:v.materialOpacity);
        // FIX85/88: on a calm background (WXGCalmBackdrop.m) the coverage moves
        // toward the calm value, as far as the background is calm.
        if(!_veilOverride && v.calmMaterialEnabled && _calmFactor>.001)
            veilAlpha+=([v calmMaterialOpacityForDock:_dockSurface dark:darkVeil]-veilAlpha)*_calmFactor;
        _veilFallback.frame=_bodyClip.bounds;
        // FIX39: the same veil the shader draws: 22% stronger unless "clear
        // material", faded toward the outline when edge weakening is on.
        // (Plain opacity made it visibly thinner at cold start and while the
        // dock's tap animation hides the Metal overlay.)
        CGFloat veilStrength=WXGClamp(CGColorGetAlpha(veil.CGColor)*veilAlpha*(1.22-.22*(v.clearMaterial?1:0)),0,1);
        if(_veilOverride){veil=_veilOverride;veilStrength=WXGClamp(CGColorGetAlpha(veil.CGColor),0,1);}   // FIX82
        _veilFallback.backgroundColor=[veil colorWithAlphaComponent:veilStrength].CGColor;
        BOOL fadeOn=_dockSurface?v.dockMaterialEdgeFadeEnabled:v.materialEdgeFadeEnabled;
        CGFloat fadeWidth=_dockSurface?v.dockMaterialEdgeFade:v.materialEdgeFade;
        if(_veilOverride){fadeOn=_veilOverrideFade>.01;fadeWidth=_veilOverrideFade;}   // FIX83
        // The fade is computed for the unscaled glass and stretched with the
        // body during a press (no new mask per frame of a press).
        CGSize veilSize=CGRectIsEmpty(_glassRect)?_bodyClip.bounds.size:_glassRect.size;
        NSString *maskKey=fadeOn && fadeWidth>.01?[NSString stringWithFormat:@"%.0fx%.0f/%.1f/%.1f",veilSize.width,veilSize.height,_maximumCornerRadius,fadeWidth]:nil;
        if(![maskKey isEqual:_veilMaskKey]) {
            _veilMaskKey=maskKey;
            UIImage *fade=maskKey?WXGVeilFadeMask(veilSize,_maximumCornerRadius,fadeWidth):nil;
            if(fade) {
                if(!_veilFallback.mask)_veilFallback.mask=[CALayer layer];
                _veilFallback.mask.contents=(__bridge id)fade.CGImage;
            }else _veilFallback.mask=nil;
        }
        _veilFallback.mask.frame=_veilFallback.bounds;
        // FIX40: in render-server mode this layer IS the body veil, always
        // (the Metal body pass no longer draws one): identical at cold start,
        // before/after the first Metal frame and during the tap animation.
        _veilFallback.hidden=WXGEffectiveRenderMode()<2;
        // FIX42: the veil must sit right below the Metal overlay, above every
        // blur layer (an opaque backdrop above it would hide it completely).
        NSArray<CALayer *> *order=_bodyClip.layer.sublayers;
        NSUInteger veilAt=[order indexOfObjectIdenticalTo:_veilFallback],metalAt=[order indexOfObjectIdenticalTo:_metal.layer];
        if(metalAt!=NSNotFound && veilAt+1!=metalAt){[_bodyClip.layer insertSublayer:_veilFallback below:_metal.layer];++_veilReorders;}
        [CATransaction commit];
    }
    _bodyClip.layer.cornerRadius=[self radiusForRect:drawnBar scale:_barScale];
    _lensClip.layer.cornerRadius=[self radiusForRect:_lensRect scale:_lensRect.size.height/MAX(1,_glassRect.size.height)];
    // FIX27: bar rim and lens rim each have a colour and opacity per
    // appearance; brightness, widths and the three fades are per appearance too.
    BOOL dark=[self darkAppearance];
    // FIX86: the rim's settings of this appearance, or always the dark ones
    // (视频号's buttons over video).
    BOOL rimDark=dark || _rimAlwaysDark;
    // FIX58: the dock's body rim (and the brightness / fade its lens rim shares)
    // is set apart from the rim of every other glass.
    // FIX85: by scope (the bubbles have their own) and by rim style.
    WXGGlassScope scope=self.glassScope;
    WXGScopeRim rim=[c rimForScope:scope dark:rimDark];
    CGFloat brightness=rim.brightness;
    UIColor *barColor=WXGBrightened(WXGColor([c rimHexForScope:scope dark:rimDark]),brightness);
    UIColor *lensColor=WXGBrightened(WXGColor(rimDark?c.darkLensRimHex:c.lensRimHex),brightness);
    CGFloat barAlpha=CGColorGetAlpha(barColor.CGColor)*rim.opacity;
    CGFloat lensAlpha=CGColorGetAlpha(lensColor.CGColor)*(rimDark?c.darkLensRimOpacity:c.lensRimOpacity);
    CGFloat sideFade=rim.fade,topLeft=rimDark?c.darkRimFadeTopLeft:c.rimFadeTopLeft,bottomRight=rimDark?c.darkRimFadeBottomRight:c.rimFadeBottomRight;
    _bodyRim.frame=drawnBar; _lensRim.frame=_lensRect;
    _lensRim.hidden=_lensSuppressed;
    _bodyRim.maximumCornerRadius=_maximumCornerRadius*_barScale;
    _lensRim.maximumCornerRadius=_maximumCornerRadius*_lensRect.size.height/MAX(1,_glassRect.size.height);
    [_bodyRim setNeedsLayout];[_lensRim setNeedsLayout];
    // FIX76/78: the line coloured from the background (the colour matrix of
    // WXGRimSampleMatrix on this glass's backdrop), one or the other: then
    // the classic colour rows are unused and the classic line is off (also
    // the bar outline the shader draws inside the dock's lens); opacity,
    // width, brightness, fade and details apply. Settings cards (no backdrop
    // of their own) take the veil colour through the same matrix. FIX78: the
    // dock's lens (the selection) keeps the plain rim of FIX72, no details.
    // FIX86: the style of this glass's own range (dock / other glass / bubbles).
    WXGRimStyle style=[c rimStyleForScope:scope];
    BOOL sampling=style==WXGRimStyleSampled,glow=style==WXGRimStyleGlow;
    WXGRimSampleTuning tuning=[c rimSampleTuningDark:rimDark];
    CGFloat lensWidth=rimDark?c.darkLensBorderWidth:c.lensBorderWidth,lensOpacity=rimDark?c.darkLensRimOpacity:c.lensRimOpacity;
    if(sampling) {
        CGFloat vr=1,vg=1,vb=1,va=1;
        [(_veilOverride?:WXGColor(_dockSurface?(dark?c.dockDarkMaterialHex:c.dockMaterialHex):(dark?c.darkMaterialHex:c.materialHex))) getRed:&vr green:&vg blue:&vb alpha:&va];
        double in[3]={vr,vg,vb},out[3];
        WXGRimApplyMatrix(WXGRimSampleMatrix(tuning.saturation,tuning.contrast,tuning.gain,tuning.lift,brightness),in,out);
        UIColor *sampled=[UIColor colorWithRed:WXGClamp(out[0],0,1) green:WXGClamp(out[1],0,1) blue:WXGClamp(out[2],0,1) alpha:1];
        // The lens and the settings cards have no colour-sampling line: they
        // take this colour (the veil through the same processing), never the
        // classic colour, so only one colour scheme is ever on screen.
        lensColor=sampled;lensAlpha=lensOpacity;
        if(_lightweight){barColor=sampled;barAlpha=rim.opacity;}
    }
    [_bodyRim configureWidth:rim.width color:[barColor colorWithAlphaComponent:barAlpha]
                        fade:sideFade topLeft:topLeft bottomRight:bottomRight];
    // FIX86: the iOS 27-like rim: a light fading inward over its width; no
    // details, no colour sampling. FIX89: its two highlights, each its own
    // colour and direction, both in either appearance; no fade along the
    // outline (rimForScope gives it none).
    WXGRimGlowShape shapes[WXGRimGlowCount];
    for(NSInteger i=0;i<WXGRimGlowCount;i++)shapes[i]=[c rimGlowForScope:scope index:i];
    [_bodyRim configureGlows:glow?shapes:NULL count:glow?WXGRimGlowCount:0];
    CGFloat lensRimAlpha=WXGPressedBorderAlpha(_pressAmount);
    [_lensRim configureWidth:lensWidth color:[lensColor colorWithAlphaComponent:lensAlpha*lensRimAlpha]
                        fade:sideFade topLeft:topLeft bottomRight:bottomRight];
    [_lensRim configureDetail:NULL];_lensRim.lineHidden=NO;_lensRim.underlayAlpha=0;
    // FIX75 / FIX79: the rim's details (stepped side fades, inner shadow) on
    // the body rim, from the current appearance's settings.
    WXGRimDetail detail={0,0,1,NO,0,0,{0,0,0}};
    if(c.rimDetails && !glow) {
        CGFloat sr=0,sg=0,sb=0,sa=1;
        [WXGColor(rimDark?c.darkRimInnerShadowHex:c.rimInnerShadowHex) getRed:&sr green:&sg blue:&sb alpha:&sa];
        detail=(WXGRimDetail){rimDark?c.darkRimOuterFade:c.rimOuterFade,rimDark?c.darkRimInnerFade:c.rimInnerFade,rimDark?c.darkRimSideLevel:c.rimSideLevel,
            rimDark?c.darkRimSideDarken:c.rimSideDarken,rimDark?c.darkRimInnerShadowRadius:c.rimInnerShadowRadius,
            sa*(rimDark?c.darkRimInnerShadowOpacity:c.rimInnerShadowOpacity),{sr,sg,sb}};
        [_bodyRim configureDetail:&detail];
    }else [_bodyRim configureDetail:NULL];
    _bodyTint.frame=drawnBar;
    _bodyTint.maximumCornerRadius=_bodyRim.maximumCornerRadius;
    _bodyTint.backdropGroup=_syncGroup;
    if(sampling && !_lightweight) {
        CGFloat screen=self.window.screen.scale?:UIScreen.mainScreen.scale,capture=c.syncCaptureScale>.01?c.syncCaptureScale:screen;
        if(c.performanceMode)capture=MIN(capture,2);
        WXGRimSample sample={tuning.saturation,tuning.contrast,tuning.gain,tuning.lift,brightness,tuning.blur,capture,c.rimSamplePlusLighter};
        // Darkened sides: black under the line (the rim view), the sampled
        // colour added over it at each step's level. With plus-lighter on,
        // adding less is already the darker step.
        BOOL overBlack=c.rimDetails && detail.darken && !sample.plusLighter && WXGRimStepped(rim.width,detail.outer,detail.inner,detail.edge);
        BOOL on=[_bodyTint configureWidth:rim.width alpha:rim.opacity outer:detail.outer inner:detail.inner edge:detail.edge
                                overBlack:overBlack fade:sideFade sample:&sample];
        _bodyRim.underlayAlpha=on && overBlack?rim.opacity:0;
        _bodyRim.lineHidden=on;
    }else {
        [_bodyTint configureWidth:0 alpha:0 outer:0 inner:0 edge:1 overBlack:NO fade:0 sample:NULL];
        _bodyRim.underlayAlpha=0;_bodyRim.lineHidden=NO;
    }
    [_bodyRim layoutIfNeeded]; [_lensRim layoutIfNeeded];
    // Each surface retains a fixed full-resolution canvas. Moving or growing the
    // lens moves only its native clipping view; it does not reallocate a drawable.
    for(WXGSyncBackdropView *v in _bodyStack)v.frame=_bodyClip.bounds;
    for(WXGSyncBackdropView *v in _edgeStack)v.frame=_bodyClip.bounds;
    for(WXGSyncBackdropView *v in _lensStack)v.frame=_lensClip.bounds;
    for(CALayer *mask in _edgeMasks)mask.frame=_edgeBackdrop.bounds;
    _metal.frame=CGRectMake(-drawnBar.origin.x,-drawnBar.origin.y,self.bounds.size.width,self.bounds.size.height);
    _lensMetal.frame=CGRectMake(-_lensRect.origin.x,-_lensRect.origin.y,self.bounds.size.width,self.bounds.size.height);
    _metal.contentScaleFactor=scale; _lensMetal.contentScaleFactor=scale;
    if(!CGSizeEqualToSize(_metal.drawableSize,size)) {
        _metal.drawableSize=size; _lensMetal.drawableSize=size;
        [_pool removeAllObjects];_currentFrame=nil;++_canvasGeneration;
        // A previous canvas must never be stretched into the resized drawable.
        // FIX27: in render-server mode the overlay holds no background pixels,
        // only veil, rims and icons; hiding it until the GPU answers made new
        // or resized glass blink once (plus button after a pull-down bounce,
        // a fresh plus menu). It stays visible and is redrawn in this pass.
        if(WXGEffectiveRenderMode()<2){_hasPresentedFrame=NO;_metal.hidden=YES;_lensMetal.hidden=YES;}
        [self invalidateBackdrop];
    }
    [CATransaction commit];
    // FIX30: a NEW glass gets its backdrop layers in this layout pass (so it
    // is never empty for a frame), but nothing is drawn here. FIX27/28 drew
    // the Metal overlay synchronously in every layout and activation: a tab
    // switch lays out and activates every glass of the new page, and the dock
    // lays out on every frame of the lens animation, so each paid an extra
    // encode-and-wait inside UIKit's switch (WeChat's switch time went from
    // ~2 ms to 25-55 ms). The overlay is drawn by the next display tick.
    // FIX33: the backdrop needs no Metal, so it is configured even before the
    // shader pipeline is ready (cold start): material first, overlay later.
    if(_active && WXGEffectiveRenderMode()>=2 && _bodyBackdrop.hidden)[self applySyncMode];
    // Prewarm the dock before the first touch. Other surfaces request the field
    // only when pressed; an unpressed editor never pays for a distance transform.
    // FIX60: not while the outline animates (its overlay is hidden then), nor
    // for a glass whose overlay is hidden: only the overlay reads the field.
    if(_shapeAnimating)return;
    if(!CGRectEqualToRect(_maskRect,_glassRect) || !CGSizeEqualToSize(_maskSize,self.bounds.size))_bodyMask=nil;
    if(_deferShapeField)return;   // 离散底栏: capsule distance while the outline moves
    if(!_overlayHidden && (_dockSurface || (!_buttonPressEffect && _pressAmount>.005)))[self refreshBodyMask];
}
- (void)setShapeAnimating:(BOOL)animating {
    if(_shapeAnimating==animating)return;
    _shapeAnimating=animating;if(!animating)[self setNeedsLayout];
}
- (void)setDeferShapeField:(BOOL)defer {
    if(_deferShapeField==defer)return;
    _deferShapeField=defer;if(!defer)[self setNeedsLayout];
}
- (BOOL)needsBackdropCapture {return YES;}
- (BOOL)directDemoCapture {
    // FIX4: the dock also consumes the shared ROI. Its independent full-3x
    // CPU readback cost 17-20ms on the supplied A12 trace, on top of navigation.
    // Metal output, TEST9 refraction, lens, icons and Gaussian stay full scale.
    return NO;
}
- (void)setActive:(BOOL)active {
    if(_active==active)return;_active=active;++_activationGeneration;
    if(active) {
        ++_resumes;_statisticsStart=CACurrentMediaTime();_captures=_draws=0;[self invalidateBackdrop];
        // FIX28: a glass that becomes active (a fresh plus menu, a rebound
        // button) gets its backdrop and overlay in this same pass, so there is
        // never a frame showing a placeholder in its place.
        if(self.window && WXGEffectiveRenderMode()>=2) {
            // FIX30/33: configure only; the next tick draws, and only a drawn
            // overlay counts as presented.
            if(_bodyBackdrop.hidden)[self applySyncMode];
            _needsDraw=YES;
        }
    }
    else {
        for(WXGBackdropFrame *f in _pool)if(f.pendingSample){[f.pendingSample releaseLease];f.pendingSample=nil;}
        // Keep the displayed frame; retire spare triple buffers offscreen.
        [_pool removeAllObjects];if(_currentFrame)[_pool addObject:_currentFrame];
        // Keep the raw page frame, but not four full-size Gaussian scratch
        // textures for every cached page. In-flight commands retain their own
        // resources; the next visible use rebuilds only these scratch buffers.
        _currentFrame.blurTemp=nil;_currentFrame.blurred=nil;
        _currentFrame.lensBlurTemp=nil;_currentFrame.lensBlurred=nil;
        _currentFrame.needsBlur=_currentFrame.needsLensBlur=YES;
    }
    // Suspend only. Existing CAMetalLayer contents and the current frame survive.
}
- (void)preparePresentation {
    [self layoutIfNeeded];
    // Native setup callbacks may prewarm geometry, never read back textures.
    if(_active && _ready && self.window && _currentFrame)[self drawMetalFrame];
}
// Weak membership prevents an input/tool host from being retained by its own glass.
- (NSArray<UIView *> *)backdropExclusions {return _weakBackdropExclusions.allObjects?:@[];}
- (void)setBackdropExclusions:(NSArray<UIView *> *)views {
    NSHashTable *next=[NSHashTable weakObjectsHashTable];
    for(UIView *view in views)if([view isKindOfClass:UIView.class])[next addObject:view];
    BOOL changed=next.count!=_weakBackdropExclusions.count;
    if(!changed)for(UIView *view in next)if(![_weakBackdropExclusions containsObject:view]){changed=YES;break;}
    if(changed){_weakBackdropExclusions=next;[self invalidateBackdrop];}
}
- (void)setSourceView:(UIView *)sourceView { if(_sourceView==sourceView) return; _sourceView=sourceView; [self invalidateBackdrop]; }
- (void)invalidateBackdrop { _lastCapture=0;_backdropRevision=0;_needsDraw=YES;_currentFrame.needsBlur=YES;_currentFrame.needsLensBlur=YES; }
- (void)releaseTransientResources { if(_active)return;[_pool removeAllObjects];_currentFrame=nil;_bodyMask=nil;_hasPresentedFrame=NO;++_maskRequest;_maskPending=NO; }

- (id<MTLTexture>)iconTexture:(UIImage *)image {
    if(!image.CGImage || !_gpu) return WXGTransparentTexture();
    NSError *error=nil;
    id<MTLTexture> texture=[_textureLoader newTextureWithCGImage:image.CGImage options:@{
        MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft,MTKTextureLoaderOptionSRGB:@NO,
        MTKTextureLoaderOptionAllocateMipmaps:@NO,MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead)
    } error:&error];
    if(!texture) _failure=error.localizedDescription; return texture?:WXGTransparentTexture();
}
// FIX21: icon atlases are decoded and uploaded off the main thread; the dock
// hands the finished textures to the glass. A private loader per call keeps
// this independent of the glass's own loader.
id<MTLTexture> WXGMakeIconTexture(UIImage *image) {
    id<MTLDevice> device=WXGSharedDevice();
    if(!image.CGImage || !device)return nil;
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:device];
    return [loader newTextureWithCGImage:image.CGImage options:@{
        MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft,MTKTextureLoaderOptionSRGB:@NO,
        MTKTextureLoaderOptionAllocateMipmaps:@NO,MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead)
    } error:NULL];
}
- (void)setNormalIconTexture:(id<MTLTexture>)normal selectedIconTexture:(id<MTLTexture>)selected {
    if(normal)_normalIcons=normal;if(selected)_selectedIcons=selected;_needsDraw=YES;
}
- (void)setNormalIcons:(UIImage *)normal selectedIcons:(UIImage *)selected {
    _normalIcons=[self iconTexture:normal]; _selectedIcons=[self iconTexture:selected];_needsDraw=YES;
}
- (id<MTLTexture>)privateTexture:(NSUInteger)width height:(NSUInteger)height {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:MAX(1,width) height:MAX(1,height) mipmapped:NO];
    d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    return [_gpu newTextureWithDescriptor:d];
}
- (WXGBackdropFrame *)newFrame {
    NSUInteger width=(NSUInteger)_metal.drawableSize.width,height=(NSUInteger)_metal.drawableSize.height;
    if(width<1 || height<1 || width>4096 || height>2048)return nil;
    WXGBackdropFrame *f=[WXGBackdropFrame new];f.width=width;f.height=height;
    // The shared scene buffer is already a Metal texture. Each glass needs only its
    // private destination, not another CPU bitmap/UIImage copy at screen scale.
    f.texture=[self privateTexture:width height:height];return f.texture?f:nil;
}
- (void)capture {
    if(_capturing || !_sourceView || !self.window || CGRectIsEmpty(self.bounds))return;
    CGAffineTransform transform;CGFloat copyScale;CGRect canvasRect;
    WXGBackdropSample *sample=WXGBackdropForGlassCopy(self,&transform,&copyScale,&canvasRect);if(!sample)return;
    WXGBackdropFrame *f=nil;
    for(WXGBackdropFrame *candidate in _pool)if(!candidate.busy && candidate!=_currentFrame){f=candidate;break;}
    if(!f && _pool.count<3){f=[self newFrame];if(f)[_pool addObject:f];}
    if(!f && _currentFrame && !_currentFrame.busy)f=_currentFrame;
    if(!f){++_poolSkips;return;}
    CFTimeInterval begin=CACurrentMediaTime();
    [f.pendingSample releaseLease];[sample acquireLease];f.pendingSample=sample;
    f.copyTransform=transform;f.copyScale=copyScale;f.sourceCapturedAt=sample.capturedAt;
    f.needsBlur=f.needsLensBlur=YES;_currentFrame=f;_needsDraw=YES;
    _backdropRevision=sample.revision;_capturedSourceRect=canvasRect;_capturedCopyTransform=transform;
    _toneLevel=sample.toneLevel;++_captures;
    _captureMilliseconds=(CACurrentMediaTime()-begin)*1000;
}
- (CFTimeInterval)lastBackdropCopyTime {return _lastCapture;}
- (BOOL)wantsBackdropCopy {
    if(!_active || !_ready || self.hidden || !self.window)return NO;
    CGAffineTransform transform;CGRect canvasRect;
    WXGBackdropSample *sample=WXGBackdropForGlassCopy(self,&transform,NULL,&canvasRect);
    return sample && (!_currentFrame || sample.revision!=_backdropRevision ||
        !CGAffineTransformEqualToTransform(transform,_capturedCopyTransform) || !CGRectEqualToRect(canvasRect,_capturedSourceRect));
}
- (void)tick:(CFTimeInterval)time {
    if(WXGGlassDeferDepth) {
        // One deferred tick per pass; the display timestamp is kept for timing
        // statistics, the post-commit flush supplies nothing else.
        _pendingTickTime=time;
        if(!_tickPending){_tickPending=YES;if(!WXGPendingGlass)WXGPendingGlass=[NSMutableArray array];[WXGPendingGlass addObject:self];}
        return;
    }
    [self runTick:time];
}
- (void)clearPendingTick {_tickPending=NO;}
- (void)runTick:(CFTimeInterval)now {
    CFTimeInterval time=_tickPending?_pendingTickTime:now;_tickPending=NO;
    if(!_active || !WXGPresentedVisible(self) || self.hidden || CGRectIsEmpty(_glassRect) || CGRectIsEmpty(self.bounds))return;
    if(_veilRevision!=WXGConfigRevision()){_veilRevision=WXGConfigRevision();[self setNeedsLayout];}
    CFTimeInterval syncStart=CACurrentMediaTime();
    [self applySyncMode];
    WXGProfileAdd(WXGProfileSync,(CACurrentMediaTime()-syncStart)*1000);
    if(!_ready)return;   // FIX33: backdrop live already; the overlay waits for Metal
    // Render-server mode needs no scene read: the backdrop is live. Only
    // geometry, press and icon changes redraw the overlay.
    if(_syncMode<2 && self.wantsBackdropCopy){_lastCapture=time;[self capture];}
    _lastDraw=time;
    // FIX44: no frames for a hidden overlay (the dock's tap animation): they
    // only took GPU time from the render server. drawNow still draws.
    if(_needsDraw && !_overlayHidden){CFTimeInterval drawStart=CACurrentMediaTime();[self drawMetalFrame];WXGProfileAdd(WXGProfileDraw,(CACurrentMediaTime()-drawStart)*1000);}
}
// 0 readback (FIX17), 1 hybrid: live blurred body + readback refraction band,
// 2 render server: live body and lens, overlay draws veil, rims, selection, icons.
- (void)applySyncMode {
    NSInteger mode=WXGEffectiveRenderMode();
    if(mode!=_syncMode){_syncMode=mode;[self invalidateBackdrop];}
    WXGConfig *c=WXGConfig.shared;CGFloat scale=c.syncBlurScale;
    BOOL body=mode>=1,lens=mode>=2 && !CGRectIsEmpty(_lensRect) && !_lensSuppressed;
    // FIX20/23: render-server refraction from the TEST9 field (mode 2 only; the
    // hybrid mode keeps its readback edge band). FIX23: contour mesh, built in
    // unscaled glass units so a press (bar growth) never rebuilds it, and RGB
    // dispersion as three channel backdrops with their own meshes.
#ifdef WXG_MESH_OFF
    // 自测专用（默认不定义）：强制关掉网格折射，只走纯着色器(TEST9 field)，用来对比观感、
    // 评估「把折射全收进着色器」的可行性。split / lensMesh 都由 mesh 派生，随之一并关闭。
    BOOL mesh=NO;
#else
    BOOL mesh=mode>=2 && c.syncMeshRefraction;
#endif
    // FIX59: lightweight glass (settings cards) and 流畅模式: one backdrop.
    BOOL lean=_lightweight || c.performanceMode;
    BOOL split=mesh && c.syncDispersion && WXGFilterFactoryAvailable() && !lean;
    // FIX31: optics follow the press in 1/32 steps and the lens size in 0.5 pt
    // steps, so consecutive frames of a press reuse a mesh instead of building
    // three new contour meshes every frame (the zoom step is under 0.7%).
    float press=roundf((float)WXGClamp(_pressAmount,0,1)*32.f)/32.f;
    WXGScopeOptics scoped=[c opticsForScope:self.glassScope];   // FIX58 (FIX85: by scope)
    WXGMeshOptics bodyOptics={(float)_glassRect.size.width,(float)_glassRect.size.height,1.f,(float)_maximumCornerRadius,(float)scoped.edgeWidth,
        (float)(scoped.refraction*(_buttonPressEffect?1+.35*press:1)),1.f,_buttonPressEffect?1.f+.04f*press:1.f,1.f,
        (float)(scoped.dispersion*.85),0.f,0.f,0.f};
    BOOL bodyMesh=mesh && body && bodyOptics.width>1 && bodyOptics.height>1;
    [self applyStack:_bodyStack visible:body split:split radius:scoped.blur*scale optics:bodyOptics quality:WXGMeshQualityBody mesh:bodyMesh];
    BOOL ring=bodyMesh && scoped.blurCoverage<99.5 && scoped.blur*scale>.01 && !lean;
    [self applyStack:_edgeStack visible:ring split:split radius:0 optics:bodyOptics quality:WXGMeshQualityBody mesh:ring];
    if(ring)[self updateEdgeMask:c];
    WXGMeshOptics lensOptics=bodyOptics;CGFloat lensBlur=0;BOOL lensMesh=NO;
    _endReachLeft=_endReachRight=0.f;
    if(lens) {
        WXGOpticalValues resting={(float)scoped.refraction,(float)scoped.dispersion,(float)scoped.edgeWidth};
        WXGOpticalValues pressed={(float)c.lensRefraction,(float)c.lensDispersion,(float)c.lensEdgeWidth};
        WXGOpticalValues optical=WXGPressedOptics(resting,pressed,press);
        CGSize size=_lensClip.bounds.size;
        size.width=round(size.width*2)/2;size.height=round(size.height*2)/2;
        float radius=(float)(_maximumCornerRadius*_lensRect.size.height/MAX(1,_glassRect.size.height));
        lensOptics=(WXGMeshOptics){(float)size.width,(float)size.height,1.f,radius,optical.edgeWidth,optical.refraction,press,
            1.f,1.f+press*(float)(c.lensZoom-1),optical.dispersion*1.55f*press,0.f,(float)c.lensTopEdgeRatio,(float)c.lensEdgeSharpness};
        // FIX47: the bar relative to the lens: a lens end past the bar's end
        // narrows to the top/bottom rim. Far bar ends are clamped (they cannot
        // matter there) so the mesh cache holds while the lens is mid-dock.
        if(_dockSurface) {
            CGRect bar=[self drawnBarRect];CGFloat reach=optical.edgeWidth*2+12;
            CGFloat left=CGRectGetMinX(bar)-CGRectGetMinX(_lensRect),right=CGRectGetMaxX(bar)-CGRectGetMinX(_lensRect);
            lensOptics.barLeft=(float)(round(MAX(left,-reach)*2)/2);lensOptics.barRight=(float)(round(MIN(right,size.width+reach)*2)/2);
            lensOptics.barTop=(float)(round((CGRectGetMinY(bar)-CGRectGetMinY(_lensRect))*2)/2);
            lensOptics.barBottom=(float)(round((CGRectGetMaxY(bar)-CGRectGetMinY(_lensRect))*2)/2);
        }
        // FIX57: at the bar's ends the band relaxes toward the top/bottom width,
        // exactly as the shader does for the bar seen through the lens. In 1/8
        // steps; zero (nothing rebuilt) while the band cannot show it.
        if(c.lensTopEdgeRatio<1 && press>0.f && (optical.refraction>0.f || optical.dispersion>0.f)) {
            CGRect bar=[self drawnBarRect];
            float barX0=(float)CGRectGetMinX(bar),barX1=(float)CGRectGetMaxX(bar);
            float lensX0=(float)CGRectGetMinX(_lensRect),lensX1=(float)CGRectGetMaxX(_lensRect);
            lensOptics.endLeft=roundf(WXGLensEndReach(barX0,barX1,lensX0,lensX1,-1)*8.f)/8.f;
            lensOptics.endRight=roundf(WXGLensEndReach(barX0,barX1,lensX0,lensX1,1)*8.f)/8.f;
        }
        _endReachLeft=lensOptics.endLeft;_endReachRight=lensOptics.endRight;
        // FIX88: the lens's colour split over its own band (resting: the
        // glass's refraction band, as before), narrowing above / below.
        if(_dockSurface && split && optical.dispersion>0.f) {
            lensOptics.dispersionWidth=(float)(round((scoped.edgeWidth+(c.lensDispersionWidth-scoped.edgeWidth)*press)*4)/4);
            lensOptics.dispersionTopRatio=(float)c.lensDispersionTopRatio;
        }
        lensBlur=(scoped.blur+(c.lensBlur-scoped.blur)*press)*scale;
        lensMesh=mesh && size.width>1 && size.height>1;
    }
    [self applyStack:_lensStack visible:lens split:split radius:lensBlur optics:lensOptics quality:WXGMeshQualityLens mesh:lensMesh];
}
// One colour stack: [0] alone in full colour, or red/green/blue with the
// channel's own refraction (red samples outward, blue inward, as wxgRGB).
- (void)applyStack:(NSArray<WXGSyncBackdropView *> *)stack visible:(BOOL)visible split:(BOOL)split radius:(CGFloat)radius
            optics:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality mesh:(BOOL)mesh {
    for(NSUInteger i=0;i<stack.count;i++) {
        WXGSyncBackdropView *view=stack[i];
        BOOL show=visible && (i==0 || split);
        if(view.hidden==show)view.hidden=!show;
        if(!show){[view applyRefraction:optics quality:quality enabled:NO];continue;}
        [view configureGroup:_syncGroup radius:radius channel:split?(NSInteger)i+1:0];
        view.captureLimit=_lightweight || WXGConfig.shared.performanceMode?2:0;[view applyCaptureScale];
        WXGMeshOptics channelOptics=optics;
        channelOptics.channel=split?(i==0?1.f:i==2?-1.f:0.f):0.f;
        if(!split)channelOptics.dispersion=0.f;
        [view applyRefraction:channelOptics quality:quality enabled:mesh];
    }
}
// Exactly the shader's sharp weight, generated at the unscaled glass size and
// stretched with the clip (the field scales with the bar), so a press does
// not regenerate it. Rebuilt only when size, radius, edge or coverage change.
- (void)updateEdgeMask:(WXGConfig *)c {
    WXGScopeOptics scoped=[c opticsForScope:self.glassScope];   // FIX58 (FIX85: by scope)
    float key[5]={(float)_glassRect.size.width,(float)_glassRect.size.height,(float)_maximumCornerRadius,(float)scoped.edgeWidth,(float)(scoped.blurCoverage*.01)};
    BOOL same=_edgeMask.contents!=nil;
    for(int i=0;i<5 && same;i++)if(fabsf(key[i]-_edgeMaskKey[i])>.01f)same=NO;
    if(!same) {
        CGFloat scale=MIN(2,[self screenScale]);
        size_t w=(size_t)ceil(key[0]*scale),h=(size_t)ceil(key[1]*scale);
        CGImageRef image=NULL;
        if(w>=2 && h>=2 && w<=4096 && h<=4096) {
            CGContextRef ctx=CGBitmapContextCreate(NULL,w,h,8,w,NULL,(CGBitmapInfo)kCGImageAlphaOnly);
            if(ctx) {
                uint8_t *bytes=CGBitmapContextGetData(ctx);size_t stride=CGBitmapContextGetBytesPerRow(ctx);
                // FIX58: same bytes, the field evaluated along the outline only.
                WXGFillRingMask(bytes,w,h,stride,(float)scale,key);
                image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);
            }
        }
        [CATransaction begin];[CATransaction setDisableActions:YES];
        for(CALayer *mask in _edgeMasks)mask.contents=(__bridge id)image;
        [CATransaction commit];
        if(image)CGImageRelease(image);
        memcpy(_edgeMaskKey,key,sizeof(key));
    }
    for(NSUInteger i=0;i<_edgeStack.count && i<_edgeMasks.count;i++)if(_edgeStack[i].layer.mask!=_edgeMasks[i]) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        _edgeMasks[i].frame=_edgeStack[i].bounds;_edgeStack[i].layer.mask=_edgeMasks[i];
        [CATransaction commit];
    }
}
- (BOOL)encodeBackdropCopy:(id<MTLCommandBuffer>)buffer frame:(WXGBackdropFrame *)f {
    WXGBackdropSample *sample=f.pendingSample;if(!sample)return YES;
    CGAffineTransform t=f.copyTransform;CGRect r=sample.rect;CGFloat scale=MAX(1,f.copyScale);
    WXGCopyUniforms copy;
    if(!WXGMakeCopyUniforms((WXGSourceTransform){t.a,t.b,t.c,t.d,t.tx,t.ty},scale,
                       r.origin.x,r.origin.y,r.size.width,r.size.height,&copy)){_failure=@"背景坐标无效";return NO;}
    id<MTLComputeCommandEncoder> encoder=[buffer computeCommandEncoder];if(!encoder)return NO;
    [encoder setComputePipelineState:_backdropCopyPipeline];[encoder setTexture:sample.texture atIndex:0];[encoder setTexture:f.texture atIndex:1];
    [encoder setBytes:&copy length:sizeof(copy) atIndex:0];
    [encoder dispatchThreadgroups:MTLSizeMake((f.width+15)/16,(f.height+7)/8,1) threadsPerThreadgroup:MTLSizeMake(16,8,1)];
    [encoder endEncoding];
    // Transfer the pending lease to this command. Reuse is forbidden until GPU
    // completion, even if UIKit detaches the originating page in the meantime.
    f.pendingSample=nil;
    [buffer addCompletedHandler:^(__unused id<MTLCommandBuffer> completed){
        dispatch_async(dispatch_get_main_queue(),^{[sample releaseLease];});
    }];
    return YES;
}
- (BOOL)encodeBlur:(id<MTLCommandBuffer>)buffer frame:(WXGBackdropFrame *)f sigma:(CGFloat)sigma lens:(BOOL)lens {
    // Restore TEST9: one full-resolution separable Gaussian, cached per frame.
    id<MTLTexture> temp=lens?f.lensBlurTemp:f.blurTemp,blurred=lens?f.lensBlurred:f.blurred;
    if(!temp)temp=[self privateTexture:f.width height:f.height];
    if(!blurred)blurred=[self privateTexture:f.width height:f.height];
    if(lens){f.lensBlurTemp=temp;f.lensBlurred=blurred;}else{f.blurTemp=temp;f.blurred=blurred;}
    if(!temp || !blurred){_failure=@"高斯缓存分配失败";return NO;}
    WXGGaussianKernel weights=WXGMakeGaussian(sigma);
    for(NSUInteger axis=0;axis<2;axis++) {
        id<MTLComputeCommandEncoder> e=[buffer computeCommandEncoder];[e setComputePipelineState:_blurPipeline];
        [e setTexture:axis?temp:f.texture atIndex:0];[e setTexture:axis?blurred:temp atIndex:1];
        WXGFloat4 params={(float)(axis?0:1./f.width),(float)(axis?1./f.height:0),(float)sigma,0};
        [e setBytes:&params length:sizeof(params) atIndex:0];[e setBytes:&weights length:sizeof(weights) atIndex:1];
        [e dispatchThreadgroups:MTLSizeMake((f.width+15)/16,(f.height+7)/8,1) threadsPerThreadgroup:MTLSizeMake(16,8,1)];[e endEncoding];
    }
    if(lens){f.needsLensBlur=NO;f.lensBlurSigma=sigma;}else{f.needsBlur=NO;f.blurSigma=sigma;}return YES;
}
- (void)drawMetalFrame {
    BOOL withTransaction=WXGConfig.shared.syncPresent;
    if(_metal.metalLayer.presentsWithTransaction!=withTransaction) {
        _metal.metalLayer.presentsWithTransaction=withTransaction;_lensMetal.metalLayer.presentsWithTransaction=withTransaction;
    }
    WXGBackdropFrame *f=_currentFrame;BOOL pure=_syncMode>=2;
    if(!_ready || (!f && !pure) || !_normalIcons || !_selectedIcons || !_active) return;
    // FIX34: drawNow may wait a few ms for the previous GPU frame; the
    // per-frame path never waits.
    dispatch_time_t inFlightLimit=_drawWait>0?dispatch_time(DISPATCH_TIME_NOW,(int64_t)(_drawWait*NSEC_PER_SEC)):DISPATCH_TIME_NOW;
    if(dispatch_semaphore_wait(_inFlight,inFlightLimit)!=0) { ++_skippedFrames; return; }
    BOOL hasLens=!CGRectIsEmpty(_lensRect) && !_lensSuppressed;
    CFTimeInterval acquireStart=CACurrentMediaTime();
    id<CAMetalDrawable> bodyDrawable=[_metal.metalLayer nextDrawable],lensDrawable=hasLens?[_lensMetal.metalLayer nextDrawable]:nil;
    _drawableAcquireMS=(CACurrentMediaTime()-acquireStart)*1000;
    id<MTLCommandBuffer> buffer=[_queue commandBuffer];
    if(!bodyDrawable || (hasLens && !lensDrawable) || !buffer) { ++_skippedFrames; dispatch_semaphore_signal(_inFlight); return; }
    WXGConfig *c=WXGConfig.shared; WXGScopeOptics scoped=[c opticsForScope:self.glassScope];   // FIX58 (FIX85: by scope)
    BOOL rimDark=[self darkAppearance] || _rimAlwaysDark;                       // FIX86
    WXGScopeRim rim=[c rimForScope:self.glassScope dark:rimDark];
    CGFloat sigma=scoped.blur*[self screenScale];
    CGFloat desiredLensSigma=c.lensBlur*[self screenScale];
    // FIX18: render-server mode binds an empty texture to every background
    // slot; the shader multiplies those samples by zero. No copy, no Gaussian.
    id<MTLTexture> raw=WXGTransparentTexture(),soft=raw,lensSoft=raw;
    if(!pure) {
    if(sigma>.01){if(!f.blurTemp)f.blurTemp=[self privateTexture:f.width height:f.height];if(!f.blurred)f.blurred=[self privateTexture:f.width height:f.height];}
    BOOL independent=hasLens && _pressAmount>.001 && desiredLensSigma>.01 && fabs(desiredLensSigma-sigma)>.01;
    if(independent){if(!f.lensBlurTemp)f.lensBlurTemp=[self privateTexture:f.width height:f.height];if(!f.lensBlurred)f.lensBlurred=[self privateTexture:f.width height:f.height];}
    if((sigma>.01 && (!f.blurTemp || !f.blurred)) || (independent && (!f.lensBlurTemp || !f.lensBlurred))){dispatch_semaphore_signal(_inFlight);return;}
    if(![self encodeBackdropCopy:buffer frame:f]){dispatch_semaphore_signal(_inFlight);return;}
    if(sigma>.01 && (f.needsBlur || fabs(f.blurSigma-sigma)>.01) && ![self encodeBlur:buffer frame:f sigma:sigma lens:NO]){dispatch_semaphore_signal(_inFlight);return;}
    CGFloat lensSigma=c.lensBlur*[self screenScale];
    lensSoft=f.texture;
    if(hasLens && _pressAmount>.001 && lensSigma>.01) {
        if(fabs(lensSigma-sigma)<.01)lensSoft=f.blurred;
        else {
            if((f.needsLensBlur || fabs(f.lensBlurSigma-lensSigma)>.01) && ![self encodeBlur:buffer frame:f sigma:lensSigma lens:YES]){dispatch_semaphore_signal(_inFlight);return;}
            lensSoft=f.lensBlurred;
        }
    }
    raw=f.texture;soft=sigma>.01?f.blurred:f.texture;
    }
    WXGUniforms u={0};
    u.viewport=(WXGFloat4){(float)self.bounds.size.width,(float)self.bounds.size.height,(float)[self screenScale],(float)fmod(_lastDraw,1000)};
    u.bar=(WXGFloat4){(float)_glassRect.origin.x,(float)_glassRect.origin.y,(float)_glassRect.size.width,(float)_glassRect.size.height};
    u.lens=(WXGFloat4){(float)_lensRect.origin.x,(float)_lensRect.origin.y,(float)_lensRect.size.width,(float)_lensRect.size.height};
    // FIX33: a suppressed lens is parked far outside the bar (a real size, so
    // the shape field stays finite): every icon unselected, no pill.
    if(_lensSuppressed)u.lens=(WXGFloat4){-4000.f,-4000.f,(float)MAX(_lensRect.size.width,40),(float)MAX(_lensRect.size.height,30)};
    u.material=(WXGFloat4){(float)_pressAmount,(float)scoped.refraction,(float)scoped.dispersion,(float)scoped.blur};
    u.lensOptics=(WXGFloat4){(float)c.lensRefraction,(float)c.lensDispersion,(float)c.lensEdgeWidth,(float)(c.lensBlurCoverage*.01)};
    u.appearance=(WXGFloat4){[self darkAppearance]?1.f:0.f,c.clearMaterial?1.f:0.f,_bodyMask?1.f:0.f,0};
    BOOL darkStyle=[self darkAppearance];
    // FIX86: the iOS 27-like rim: the bar outline the shader draws (inside
    // the dock's lens) is the same light, over the rim's width. FIX89: its two
    // highlights: the first in glow / optics.y / borderColor, the second in
    // glow2 / extra.x / glowColor2.
    BOOL glowRim=[c rimStyleForScope:self.glassScope]==WXGRimStyleGlow;
    WXGRimGlowShape glows[WXGRimGlowCount];
    for(NSInteger i=0;i<WXGRimGlowCount;i++)glows[i]=[c rimGlowForScope:self.glassScope index:i];
    // FIX87: x = 1 + the highlight's angle in radians (0 = off).
    WXGFloat4 (^glowParams)(WXGRimGlowShape)=^WXGFloat4(WXGRimGlowShape g){
        return (WXGFloat4){(float)(1+WXGClamp(g.angle,0,180)*M_PI/180),(float)g.endLevel,(float)g.sharpness,(float)g.falloff};
    };
    u.glow=glowRim?glowParams(glows[0]):(WXGFloat4){0,0,0,0};
    u.glow2=glowRim?glowParams(glows[1]):(WXGFloat4){0,0,0,0};
    u.glowColor2=glowRim?(WXGFloat4){(float)glows[1].red,(float)glows[1].green,(float)glows[1].blue,(float)glows[1].alpha}:(WXGFloat4){0,0,0,0};
    u.optics=(WXGFloat4){(float)c.lensZoom,(float)(glowRim?glows[0].width:rim.width),(float)c.bodyPinch,(float)scoped.edgeWidth};
    // FIX88: y / z the lens's own dispersion range and its top / bottom ratio
    // (WXGLensDispersionWidth). FIX89: x the second highlight's width.
    // FIX94: w the margin of the bar following the lens' rim (dock only; 0 off).
    u.extra=(WXGFloat4){glowRim?(float)glows[1].width:0.f,(float)c.lensDispersionWidth,(float)c.lensDispersionTopRatio,
                        _dockSurface && c.lensBarFollow?(float)c.lensBarMargin:0.f};
    // FIX97: the colour split of the bar seen through the dock's lens; z the
    // page behind it as the shader assumes it (black in dark mode, white in
    // light), for the channels CA's single alpha covers too much.
    // FIX98: w 1 + the selection colour's weight when the dock sets one.
    BOOL barSplit=_dockSurface && c.lensBarDispersionOn;
    u.extra2=(WXGFloat4){barSplit?(float)c.lensBarDispersion:0.f,barSplit?(float)c.lensBarDispersionNearRim:0.f,[self darkAppearance]?0.f:1.f,
                         _selectionWeight>=0?(float)(1+_selectionWeight):0.f};
    CGFloat r=0,g=0,b=0,a=0;
    [WXGColor([self darkAppearance]?c.darkSelectionHex:c.selectionHex) getRed:&r green:&g blue:&b alpha:&a];
    CGFloat selectionAlpha=c.selectionOpacity+(c.pressedOpacity-c.selectionOpacity)*WXGClamp(_pressAmount,0,1);
    u.selectionColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*selectionAlpha)};
    // FIX27: the bar contour seen inside the lens uses the bar rim of this appearance.
    [WXGBrightened(WXGColor([c rimHexForScope:self.glassScope dark:rimDark]),rim.brightness) getRed:&r green:&g blue:&b alpha:&a];
    if([c rimStyleForScope:self.glassScope]==WXGRimStyleSampled) {   // FIX86: this glass's range
        // FIX78: with the colour from the background, the bar outline seen in
        // the lens takes the lens rim's colour (the veil through the same
        // processing), never the classic colour: one colour scheme only.
        CGFloat vr=1,vg=1,vb=1,va=1;
        [WXGColor(_dockSurface?(darkStyle?c.dockDarkMaterialHex:c.dockMaterialHex):(darkStyle?c.darkMaterialHex:c.materialHex)) getRed:&vr green:&vg blue:&vb alpha:&va];
        double in[3]={vr,vg,vb},out[3];
        WXGRimSampleTuning tuning=[c rimSampleTuningDark:rimDark];
        WXGRimApplyMatrix(WXGRimSampleMatrix(tuning.saturation,tuning.contrast,tuning.gain,tuning.lift,rim.brightness),in,out);
        r=WXGClamp(out[0],0,1);g=WXGClamp(out[1],0,1);b=WXGClamp(out[2],0,1);a=1;
    }
    u.borderColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*rim.opacity)};
    if(glowRim)u.borderColor=(WXGFloat4){(float)glows[0].red,(float)glows[0].green,(float)glows[0].blue,(float)glows[0].alpha};   // FIX89
    // FIX88: the outline the dock's tap animation draws in its lens: the rim
    // as the shader draws it there. The shader's rim strength (its top /
    // bottom fades) at the top and the bottom, averaged. FIX89: the iOS
    // 27-like rim as one thin line per highlight, at its level on the top and
    // bottom edges (what the lens mostly shows of the bar).
    float fadeTL=(float)(rimDark?c.darkRimFadeTopLeft:c.rimFadeTopLeft),fadeBR=(float)(rimDark?c.darkRimFadeBottomRight:c.rimFadeBottomRight);
    CGFloat rimLevel=.5*(WXGRimStrengthTLBR(0,-1,(float)rim.fade,fadeTL,fadeBR)+WXGRimStrengthTLBR(0,1,(float)rim.fade,fadeTL,fadeBR));
    if(glowRim) {
        NSMutableArray *colors=[NSMutableArray array],*widths=[NSMutableArray array];
        for(NSInteger i=0;i<WXGRimGlowCount;i++) {
            WXGRimGlowShape gl=glows[i];
            CGFloat level=WXGRimGlowLevel(0,1,gl.angle,gl.endLevel,gl.sharpness);
            [colors addObject:[UIColor colorWithRed:gl.red green:gl.green blue:gl.blue alpha:WXGClamp(gl.alpha*level,0,1)]];
            [widths addObject:@(gl.width>.01?MAX(.75,MIN(gl.width*.5,2.)):0)];
        }
        _lensOutlineColors=colors;_lensOutlineWidths=widths;
    }else {
        _lensOutlineColors=@[[UIColor colorWithRed:r green:g blue:b alpha:WXGClamp(a*rim.opacity*rimLevel,0,1)]];
        _lensOutlineWidths=@[@(rim.width)];
    }
    // FIX29: the dock and the other glass each have a switch and a range for
    // the edge weakening; off (or a range of 0) = full coverage to the outline.
    BOOL edgeFade=_dockSurface?c.dockMaterialEdgeFadeEnabled:c.materialEdgeFadeEnabled;
    CGFloat edgeFadeRange=_dockSurface?c.dockMaterialEdgeFade:c.materialEdgeFade;
    u.motion=(WXGFloat4){(float)_barScale,edgeFade && edgeFadeRange>.01?1.f:0.f,(float)(scoped.blurCoverage*.01),(float)_lensAnchorX};
    // Opacity is per appearance now, so no extra dark gain (y = 1).
    u.rim=(WXGFloat4){(float)rim.fade,1.f,(float)(rimDark?c.darkLensBorderWidth:c.lensBorderWidth),(float)_maximumCornerRadius};
    BOOL dark=darkStyle;
    // FIX27: the dock has its own material veil; every other glass shares one.
    NSString *materialHex=_dockSurface?(dark?c.dockDarkMaterialHex:c.dockMaterialHex):(dark?c.darkMaterialHex:c.materialHex);
    CGFloat materialOpacity=_dockSurface?(dark?c.dockDarkMaterialOpacity:c.dockMaterialOpacity):(dark?c.darkMaterialOpacity:c.materialOpacity);
    // FIX88: the calm adjustment as on the render-server veil (layoutSubviews),
    // so the bar seen inside the lens matches the bar outside it.
    if(!_veilOverride && c.calmMaterialEnabled && _calmFactor>.001)
        materialOpacity+=([c calmMaterialOpacityForDock:_dockSurface dark:dark]-materialOpacity)*_calmFactor;
    [WXGColor(materialHex) getRed:&r green:&g blue:&b alpha:&a];
    u.tintColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*materialOpacity)};
    // FIX40: w = 1: the body veil is the render-server layer; the body pass
    // draws icons only (the lens pass keeps its own veil).
    u.sync=(WXGFloat4){(float)_syncMode,(float)c.lensTopEdgeRatio,(float)c.lensEdgeSharpness,_syncMode>=2?1.f:0.f};
    u.style=(WXGFloat4){(float)edgeFadeRange,
        (float)(rimDark?c.darkRimFadeTopLeft:c.rimFadeTopLeft),(float)(rimDark?c.darkRimFadeBottomRight:c.rimFadeBottomRight),0};
    NSUInteger canvasWidth=(pure || !f)?bodyDrawable.texture.width:f.width,canvasHeight=(pure || !f)?bodyDrawable.texture.height:f.height;
    for(NSUInteger surface=0;surface<(hasLens?2u:1u);surface++) {
        u.appearance.w=(!surface && _buttonPressEffect)?-1.f:(float)surface;
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=surface?lensDrawable.texture:bodyDrawable.texture;
        pass.colorAttachments[0].loadAction=MTLLoadActionClear;
        pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
        id<MTLRenderCommandEncoder> encoder=[buffer renderCommandEncoderWithDescriptor:pass];
        [encoder setRenderPipelineState:_pipeline]; [encoder setFragmentBytes:&u length:sizeof(u) atIndex:0];
        // FIX35: during the dock's tap animation the overlay is the bar only;
        // the animation layers draw every icon (none doubled under the lens).
        id<MTLTexture> normalIcons=_lensSuppressed?WXGTransparentTexture():_normalIcons,selectedIcons=_lensSuppressed?WXGTransparentTexture():_selectedIcons;
        [encoder setFragmentTexture:raw atIndex:0]; [encoder setFragmentTexture:normalIcons atIndex:1];
        [encoder setFragmentTexture:selectedIcons atIndex:2]; [encoder setFragmentTexture:soft atIndex:3];
        [encoder setFragmentTexture:_bodyMask?:raw atIndex:4];
        [encoder setFragmentTexture:lensSoft?:raw atIndex:5];
        // Lens clips can move before the previous GPU drawable is displayed.
        // Render the complete lens canvas, so stale rectangular scissor edges
        // cannot cut the new native rounded contour during a fast switch.
        CGRect bounds=surface?self.bounds:[self drawnBarRect]; CGFloat scale=[self screenScale];
        NSUInteger x=(NSUInteger)MAX(0,floor(bounds.origin.x*scale)),y=(NSUInteger)MAX(0,floor(bounds.origin.y*scale));
        NSUInteger right=(NSUInteger)MIN(canvasWidth,ceil(CGRectGetMaxX(bounds)*scale)),bottom=(NSUInteger)MIN(canvasHeight,ceil(CGRectGetMaxY(bounds)*scale));
        if(right>x && bottom>y) {
            [encoder setScissorRect:(MTLScissorRect){x,y,right-x,bottom-y}];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        }
        [encoder endEncoding];
    }
    NSUInteger generation=_activationGeneration,canvas=_canvasGeneration;_needsDraw=NO; ++f.busy; ++_draws; dispatch_semaphore_t semaphore=_inFlight; __weak WXGGlassView *weakSelf=self;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        dispatch_semaphore_signal(semaphore);
        dispatch_async(dispatch_get_main_queue(),^{
            if(f.busy) --f.busy;
            if(completed.status==MTLCommandBufferStatusCompleted) {
                ++weakSelf.completedFrames;
                weakSelf.lastGPUms=MAX(0,(completed.GPUEndTime-completed.GPUStartTime)*1000);
            }
            if(completed.status==MTLCommandBufferStatusCompleted && weakSelf.active && weakSelf.activationGeneration==generation && weakSelf.canvasGeneration==canvas && !weakSelf.hasPresentedFrame) {
                weakSelf.metal.hidden=NO;weakSelf.lensMetal.hidden=NO;
                weakSelf.hasPresentedFrame=YES;
                WXGLog(@"TEST4 首个 Metal 帧已完成");
                if(weakSelf.onFirstFrame) weakSelf.onFirstFrame();
            }
            if(completed.status==MTLCommandBufferStatusError) {
                weakSelf.backdropRevision=0;weakSelf.needsDraw=YES;weakSelf.failure=completed.error.localizedDescription; WXGLog(@"GPU 错误：%@",completed.error.localizedDescription);
            }
        });
    }];
    NSUInteger submittedRevision=_backdropRevision;CFTimeInterval capturedAt=f.sourceCapturedAt;
    [bodyDrawable addPresentedHandler:^(id<MTLDrawable> drawable){
        CFTimeInterval time=drawable.presentedTime;WXGGlassView *view=weakSelf;if(!view || time<=0)return;
        BOOL fresh=NO;
        @synchronized(view) {
            if(time<=view.lastPresentedTime)return;
            if(view.lastPresentedTime>0)view.presentIntervalMS=(time-view.lastPresentedTime)*1000;
            view.lastPresentedTime=time;view.presentedFrames+=1;
            if(submittedRevision!=view.presentedRevision){view.presentedRevision=submittedRevision;view.presentedBackdropUpdates+=1;fresh=YES;}
            view.presentedBackdropAgeMS=MAX(0,time-capturedAt)*1000;
        }
        // FIX17: the first presentation of a new background measures how long
        // a read takes to reach the screen; prediction targets that moment.
        if(fresh && capturedAt>0) {
            double latency=time-capturedAt;
            dispatch_async(dispatch_get_main_queue(),^{WXGBackdropRecordPresentationLatency(latency);});
        }
    }];
    if(_metal.metalLayer.presentsWithTransaction) {
        [buffer commit];
        if(WXGPresentBatching) {
            WXGBatchLastBuffer=buffer;[WXGBatchDrawables addObject:bodyDrawable];if(lensDrawable)[WXGBatchDrawables addObject:lensDrawable];
        }else {
            [buffer waitUntilScheduled];[bodyDrawable present];[lensDrawable present];
        }
    }else {
        [buffer presentDrawable:bodyDrawable];if(lensDrawable)[buffer presentDrawable:lensDrawable];[buffer commit];
    }
    // FIX33: in render-server mode the overlay just encoded is presented with
    // this transaction, so this is the moment fallbacks may go. FIX27-32 said
    // "presented" on activation instead; at cold start WeChat keeps the main
    // thread busy, no overlay was drawn yet and the dock showed a bare blur
    // bar without icons or pill.
    if(pure && !_hasPresentedFrame) {
        _hasPresentedFrame=YES;
        if(_onFirstFrame)_onFirstFrame();
    }
}
- (BOOL)drawNow {
    if(!_ready || !_active || !self.window)return NO;
    NSUInteger before=_draws;
    _needsDraw=YES;_drawWait=.012;[self drawMetalFrame];_drawWait=0;
    return _draws!=before;
}
- (NSString *)diagnostics {
    double elapsed=MAX(.001,_lastDraw-_statisticsStart);
    return [NSString stringWithFormat:@"TEST9 %@\nGPU：%@\n输出：%.0f × %.0f，%.1fx；背景独立采样（实测速率见 backdrop）\n图标纹理：%lu × %lu\n采样请求：%ld；设备上限：%ld；背景更新平均 %.1f 次/秒\n渲染提交平均 %.1f 次/秒；GPU 复制准备 %.2f ms（共享采样见 backdrop 字段）\n采样回退：%lu；GPU 忙：%lu；缓冲忙：%lu\n外形/线框：系统 continuous；白边方向渐隐；透镜框仅按压\n镜内原生距离场：%@\n背景源：%@\n错误：%@",
        _ready?@"原折射曲线 / 高斯模糊 + RGB":@"初始化中",_gpu.name?:@"无",
        _metal.drawableSize.width,_metal.drawableSize.height,[self screenScale],(unsigned long)_normalIcons.width,(unsigned long)_normalIcons.height,
        (long)WXGConfig.shared.captureFPS,(long)WXGScreenCaptureFPS(self.window.screen),_captures/elapsed,_draws/elapsed,_captureMilliseconds,
        (unsigned long)_captureFailures,(unsigned long)_skippedFrames,(unsigned long)_poolSkips,_bodyMask?@"已生成":@"无，使用近似回退",NSStringFromClass(_sourceView.class),_failure?:@"无"];
}
- (NSDictionary *)frameMetrics {
    return @{@"view":[NSString stringWithFormat:@"%p",self],@"source":[NSString stringWithFormat:@"%p",_sourceView],
        @"ready":@(_ready),@"active":@(_active),@"hasFrame":@(_hasPresentedFrame),
        @"copies":@(_captures),@"completedFrames":@(_completedFrames),@"presentedFrames":@(self.presentedFrames),
        @"presentedBackdropUpdates":@(self.presentedBackdropUpdates),@"presentIntervalMS":@(self.presentIntervalMS),
        @"presentedBackdropAgeMS":@(self.presentedBackdropAgeMS),@"gpuMS":@(_lastGPUms),
        @"acquireMS":@(_drawableAcquireMS),@"gpuBusySkips":@(_skippedFrames),@"bufferBusySkips":@(_poolSkips)};
}
- (NSDictionary *)layerEvidence {
    NSMutableArray *layers=[NSMutableArray array];
    NSMutableArray *views=[NSMutableArray array];
    if(_bodyClip)[views addObject:_bodyClip];if(_lensClip)[views addObject:_lensClip];
    if(_metal)[views addObject:_metal];if(_lensMetal)[views addObject:_lensMetal];
    if(_bodyRim)[views addObject:_bodyRim];if(_lensRim)[views addObject:_lensRim];
    for(UIView *v in views) {
        CGRect r=WXGWindowRect(v,self.window);
        [layers addObject:@{@"class":NSStringFromClass(v.class),@"layerClass":NSStringFromClass(v.layer.class),@"hidden":@(v.hidden),@"alpha":@(v.alpha),
            @"rect":@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)],@"cornerRadius":@(v.layer.cornerRadius),@"clips":@(v.clipsToBounds)}];
    }
    return @{@"layers":layers,@"ready":@(_ready),@"hasPresentedFrame":@(_hasPresentedFrame),@"toneLevel":@(_toneLevel),@"press":@(_pressAmount),
        @"resumes":@(_resumes),@"canvasGeneration":@(_canvasGeneration),@"directDemoCapture":@(self.directDemoCapture),@"persistentDrawable":@YES,
        @"completedFrames":@(_completedFrames),@"presentedFrames":@(self.presentedFrames),@"presentedBackdropUpdates":@(self.presentedBackdropUpdates),@"presentIntervalMS":@(self.presentIntervalMS),@"presentedBackdropAgeMS":@(self.presentedBackdropAgeMS),@"backgroundCopies":@(_captures),@"backgroundRevision":@(_backdropRevision),@"lastBackgroundCopyTime":@(_lastCapture),@"lastGPUms":@(_lastGPUms),@"drawableAcquireMS":@(_drawableAcquireMS),
        @"blurBackend":@"TEST9_full_resolution_separable_Gaussian",@"sourceClass":_sourceView?NSStringFromClass(_sourceView.class):@"none",@"snapshotBackend":self.directDemoCapture?@"demo_direct_hierarchy":@"model_tree_pre_commit_transaction_present_FIX20",@"presentsWithTransaction":@(_metal.metalLayer.presentsWithTransaction),
        @"renderMode":@(_syncMode),@"requestedRenderMode":@(WXGConfig.shared.renderMode),@"backdropLayerClass":@(WXGBackdropLayerClass()!=nil),@"filterFactory":@(WXGFilterFactoryAvailable()),
        @"bodyBackdropLive":@(_bodyBackdrop.live && !_bodyBackdrop.hidden),@"bodyBackdropFiltered":@(_bodyBackdrop.filtered),@"bodyBackdropRadius":@(_bodyBackdrop.radius),
        @"lensBackdropLive":@(_lensBackdrop.live && !_lensBackdrop.hidden),@"lensBackdropRadius":@(_lensBackdrop.radius),
        @"meshTransformClass":@(WXGMeshTransformClass()!=nil),@"bodyMeshApplied":@(_bodyBackdrop.meshApplied),@"bodyMeshAccepted":@(_bodyBackdrop.meshAccepted),
        @"bodyMeshVertices":@(_bodyBackdrop.meshVertices),@"lensMeshAccepted":@(_lensBackdrop.meshAccepted),
        @"edgeRingLive":@(_edgeBackdrop.live && !_edgeBackdrop.hidden),@"edgeRingMeshAccepted":@(_edgeBackdrop.meshAccepted),
        @"syncDispersionLayers":@(!_bodyStack[1].hidden),@"greenMeshAccepted":@(_bodyStack[1].meshAccepted),@"blueMeshAccepted":@(_bodyStack[2].meshAccepted),
        @"lensMeshVertices":@(_lensBackdrop.meshVertices),@"endReach":@[@(_endReachLeft),@(_endReachRight)],@"meshBuilder":@"contour_zipper_FIX57",@"meshCacheHits":@(WXGMeshCacheHits),@"meshCacheMisses":@(WXGMeshCacheMisses),
        @"backdropDefaultScale":@(_bodyBackdrop.defaultCaptureScale),@"backdropAppliedScale":@(_bodyBackdrop.appliedCaptureScale),
        @"backdropRequestedScale":@(_bodyBackdrop.requestedCaptureScale),
        @"meshSubdivisionSteps":@(_bodyBackdrop.meshSubdivision),@"lensMeshSubdivisionSteps":@(_lensBackdrop.meshSubdivision),@"backdropRevision":@(_backdropRevision),@"maximumCornerRadius":@(_maximumCornerRadius),@"rim":[_bodyRim rimEvidence]?:@{},@"lensRim":[_lensRim rimEvidence]?:@{},@"rimTint":[_bodyTint tintEvidence]?:@{},@"samplingRequested":@(WXGConfig.shared.captureFPS),@"samplingCap":@(WXGScreenCaptureFPS(self.window.screen)),@"screenMaximumFPS":@(self.window.screen.maximumFramesPerSecond),@"captureScale":@([self screenScale]),
        @"buttonPressEffect":@(_buttonPressEffect),@"lensBlur":@(WXGConfig.shared.lensBlur),@"lensBlurCoverage":@(WXGConfig.shared.lensBlurCoverage),@"fullLensCanvas":@YES,@"bodyMaskNative":@(_bodyMask!=nil),@"drawableWidth":@(_metal.drawableSize.width),@"drawableHeight":@(_metal.drawableSize.height)};
}
@end
