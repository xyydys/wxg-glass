// FIX47: WXGMeshOptics has trailing bar fields; the positional initializers
// below intentionally leave them zero (= off).
#pragma clang diagnostic ignored "-Wmissing-field-initializers"
#import "WXGIntegration.h"
#import <Metal/Metal.h>
#import <MetalKit/MTKTextureLoader.h>
#import <objc/runtime.h>
typedef float WXGFloat4 __attribute__((ext_vector_type(4)));
_Static_assert(sizeof(WXGFloat4)==16,"Float4 ABI");
// FIX103: the glass shader (WXGGlass.metal) is not compiled into the plugin;
// it comes from the unlock server (WXGUnlock.m). WXGShaderSource.h stays in
// the source tree for tools/check_msl.py and the shader simulator only.
#include "WXGDistanceField.h"
#include "WXGSourceMapping.h"
#include "WXGBackdropCopy.h"
#include "WXGLensOptics.h"
#include "WXGKyantOptics.h"
#include "WXGBuildIdentity.h"
#include "WXGShaderSource.h"
#include "WXGOriginalShaderSource.h"
#include "WXGMeshRefraction.h"
#include "WXGEdgeMaskBand.h"
#include "WXGRimGlow.h"
#include "WXGRim26.h"
#include "WXGRimDetail.h"
#include "WXGCapsule26.h"
#include "WXGDropShadow.h"
#import "WXGMenuMorphMaterial.h"
#include <pthread.h>

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
// FIX113 I: the share of the lens' rim offset cancelled (the shader knows it).
static volatile BOOL WXGShaderLensCancel;
static volatile BOOL WXGShaderKyantOptics;
static NSString *WXGOpticsCompileError;
BOOL WXGLensCancelAvailable(void) {return WXGShaderLensCancel;}
CGFloat WXGLensCancel(void) {return WXGShaderLensCancel?WXGClamp([WXGConfig.shared extraNumber:@"lensOffsetCancel"],0,1):0;}
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
                shader=[NSString stringWithUTF8String:WXGMetalSource];
                NSError *error=nil;id<MTLDevice> device=WXGSharedDevice();
                MTLCompileOptions *options=[MTLCompileOptions new];options.fastMathEnabled=YES;options.languageVersion=MTLLanguageVersion2_1;
                id<MTLLibrary> library=[device newLibraryWithSource:[shader stringByAppendingString:[NSString stringWithUTF8String:WXGBackdropCopySource]] options:options error:&error];
                BOOL referenceCompiled=library!=nil;
                if(!library) {
                    WXGOpticsCompileError=error.localizedDescription?:@"reference shader compile failed";
                    WXGLog(@"%s 透镜着色器编译失败，回到 FIX135：%@",WXG_BUILD_DIAGNOSTIC_REVISION,WXGOpticsCompileError);
                    shader=[NSString stringWithUTF8String:WXGOriginalMetalSource];error=nil;
                    library=[device newLibraryWithSource:[shader stringByAppendingString:[NSString stringWithUTF8String:WXGBackdropCopySource]] options:options error:&error];
                }
                WXGShaderLensCancel=[shader rangeOfString:@"WXG_LENS_CANCEL"].location!=NSNotFound;
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
                WXGShaderKyantOptics=referenceCompiled && state && blur && copy;
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
- (id)CA_interpolateValue:(id)other byFraction:(float)fraction;
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
        fabsf(a.dispersionWidth-b.dispersionWidth)<.01f && fabsf(a.dispersionTopRatio-b.dispersionTopRatio)<.005f &&   // FIX88
        fabsf(a.padX-b.padX)<.25f && fabsf(a.padY-b.padY)<.25f && fabsf(a.cancel-b.cancel)<.005f &&   // FIX113 H / I
        fabsf(a.sbLeft-b.sbLeft)<.25f && fabsf(a.sbTop-b.sbTop)<.25f && fabsf(a.sbRight-b.sbRight)<.25f && fabsf(a.sbBottom-b.sbBottom)<.25f &&
        fabsf(a.sbRadius-b.sbRadius)<.05f && fabsf(a.shrinkPress-b.shrinkPress)<.005f && fabsf(a.shrinkPinch-b.shrinkPinch)<.0005f &&   // FIX113 U
        fabsf(a.shrinkExtra-b.shrinkExtra)<.125f &&   // FIX113 Y
        fabsf(a.transition-b.transition)<.0005f &&   // FIX114 I
        fabsf(a.softStretch-b.softStretch)<.005f && fabsf(a.softPower-b.softPower)<.005f && fabsf(a.softWidth-b.softWidth)<.05f &&   // FIX114 J
        fabsf(a.curveHeight-b.curveHeight)<.01f && fabsf(a.curveAmount-b.curveAmount)<.01f && fabsf(a.curveSqueeze-b.curveSqueeze)<.01f &&
        a.kyantMode==b.kyantMode && fabsf(a.kyantHeight-b.kyantHeight)<.01f &&
        fabsf(a.kyantAmount-b.kyantAmount)<.01f && a.kyantChannel==b.kyantChannel &&
        fabsf(a.shrinkFlat-b.shrinkFlat)<.5f;
}
// FIX114 A: while the lens moves (pressed, travelling, deforming with the
// drag), a mesh a little off still serves: within 2 pt of size and 2.5 pt of
// the bar's edges, 0.04 of press, 6% of curve/kyant depth, so a mesh is not
// rebuilt on every frame of a tab switch. The exact one is built once it rests.
static BOOL WXGMeshOpticsNear(WXGMeshOptics a,WXGMeshOptics b) {
    WXGMeshOptics t=b;
    BOOL endNear=a.sbLeft>-5000.f || a.sbRight<5000.f || b.sbLeft>-5000.f || b.sbRight<5000.f;
    float wTol=endNear?.75f:3.0f,endTol=endNear?.5f:3.5f;
    if(fabsf(a.width-b.width)<wTol && fabsf(a.height-b.height)<3.0f)t.width=a.width,t.height=a.height;
    if(fabsf(a.sbLeft-b.sbLeft)<endTol && fabsf(a.sbRight-b.sbRight)<endTol && fabsf(a.sbTop-b.sbTop)<2.5f && fabsf(a.sbBottom-b.sbBottom)<2.5f)
        t.sbLeft=a.sbLeft,t.sbRight=a.sbRight,t.sbTop=a.sbTop,t.sbBottom=a.sbBottom;
    if(fabsf(a.barLeft-b.barLeft)<2.0f && fabsf(a.barRight-b.barRight)<2.0f && fabsf(a.barTop-b.barTop)<2.0f && fabsf(a.barBottom-b.barBottom)<2.0f)
        t.barLeft=a.barLeft,t.barRight=a.barRight,t.barTop=a.barTop,t.barBottom=a.barBottom;
    if(fabsf(a.shrinkPress-b.shrinkPress)<.04f)t.shrinkPress=a.shrinkPress;
    if(fabsf(a.shrinkExtra-b.shrinkExtra)<1.5f)t.shrinkExtra=a.shrinkExtra;
    if(fabsf(a.zoomBefore-b.zoomBefore)<.006f && fabsf(a.zoomAfter-b.zoomAfter)<.006f)t.zoomBefore=a.zoomBefore,t.zoomAfter=a.zoomAfter;
    // (review) What follows the press during a tap: the rim offset's scale
    // (= press), the refraction, width, dispersion and radius on their way
    // from resting to pressed.
    if(fabsf(a.offsetScale-b.offsetScale)<.04f)t.offsetScale=a.offsetScale;
    if(fabsf(a.refraction-b.refraction)<.04f*fmaxf(1.f,fabsf(a.refraction)))t.refraction=a.refraction;
    if(fabsf(a.edgeWidth-b.edgeWidth)<fmaxf(.5f,.06f*fabsf(a.edgeWidth)))t.edgeWidth=a.edgeWidth;
    if(fabsf(a.dispersion-b.dispersion)<.08f)t.dispersion=a.dispersion;
    if(fabsf(a.dispersionWidth-b.dispersionWidth)<.4f)t.dispersionWidth=a.dispersionWidth;
    if(fabsf(a.radius-b.radius)<.75f)t.radius=a.radius;
    if(fabsf(a.curveHeight-b.curveHeight)<fmaxf(.5f,.06f*fabsf(a.curveHeight)))t.curveHeight=a.curveHeight;
    if(fabsf(a.curveAmount-b.curveAmount)<fmaxf(.8f,.06f*fabsf(a.curveAmount)))t.curveAmount=a.curveAmount;
    if(fabsf(a.kyantHeight-b.kyantHeight)<fmaxf(.5f,.06f*fabsf(a.kyantHeight)))t.kyantHeight=a.kyantHeight;
    if(fabsf(a.kyantAmount-b.kyantAmount)<fmaxf(.8f,.06f*fabsf(a.kyantAmount)))t.kyantAmount=a.kyantAmount;
    return WXGMeshOpticsClose(a,t);
}
// FIX23: contour-following mesh (see WXGBuildContourMesh). Static glass gets
// the fine quality; the lens, rebuilt while it grows, a lighter one.
static const WXGMeshQuality WXGMeshQualityBody={.06f,.10f,24.f},WXGMeshQualityLens={.20f,.16f,24.f};
// FIX113 U: a lens showing the smaller bar: the bar's outline crosses the
// rings at the lens' ends, so finer arcs and straight steps there.
// R11: lighter motion-tier quality while sliding / rapidly switching, refining to LensBar once settled.
static const WXGMeshQuality WXGMeshQualityLensBar={.12f,.08f,8.f},WXGMeshQualityLensMove={.20f,.12f,16.f};
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
    // are 30-130 KB each, so keep enough headroom for rapid continuous tab switches.
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=400;cache.totalCostLimit=24*1024*1024;});
    return cache;
}
static NSUInteger WXGMeshCacheHits,WXGMeshCacheMisses;
static id WXGBuildMeshTransform(WXGMeshOptics optics,WXGMeshQuality quality,NSUInteger *vertexCount,NSMutableData **storage,NSInteger *subdivision);
static id WXGMakeMeshTransform(WXGMeshOptics optics,WXGMeshQuality quality,NSUInteger *vertexCount,NSMutableData **storage,NSInteger *subdivision) {
    // Key: the exact optics and quality, rounded so float noise cannot split it.
    float key[48]={roundf(optics.width*100),roundf(optics.height*100),roundf(optics.fieldScale*1000),roundf(optics.radius*100),
        roundf(optics.edgeWidth*100),roundf(optics.refraction*1000),roundf(optics.offsetScale*1000),roundf(optics.zoomBefore*1000),
        roundf(optics.zoomAfter*1000),roundf(optics.dispersion*1000),optics.channel,roundf(optics.topRatio*1000),roundf(optics.sharpness*100),
        roundf(quality.ringError*1000),roundf(quality.arcStep*1000),roundf(quality.straightStep*100),
        roundf(optics.barLeft*10),roundf(optics.barTop*10),roundf(optics.barRight*10),roundf(optics.barBottom*10),
        roundf(optics.endLeft*1000),roundf(optics.endRight*1000),roundf(optics.dispersionWidth*100),roundf(optics.dispersionTopRatio*1000),
        roundf(optics.padX*10),roundf(optics.padY*10),roundf(optics.cancel*1000),
        roundf(optics.sbLeft*10),roundf(optics.sbTop*10),roundf(optics.sbRight*10),roundf(optics.sbBottom*10),roundf(optics.sbRadius*100),
        roundf(optics.shrinkPress*1000),roundf(optics.shrinkPinch*10000),roundf(optics.shrinkExtra*4),roundf(optics.transition*1000),
        roundf(optics.softStretch*100),roundf(optics.softPower*100),roundf(optics.softWidth*4),
        roundf(optics.curveHeight*100),roundf(optics.curveAmount*100),roundf(optics.curveSqueeze*100),optics.kyantMode,roundf(optics.kyantHeight*100),
        roundf(optics.kyantAmount*100),optics.kyantChannel,optics.shrinkFlat};   // FIX113 H / I / U / Y, FIX114 I / J, FIX122, R11
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
static id WXGCreateMesh(Class cls,NSUInteger count,WXGMeshVertex *vertices,NSUInteger faces,WXGMeshFace *quads,NSInteger *subdivision) {
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
    id mesh=WXGCreateMesh(cls,(NSUInteger)count,vertices,faces,quads,subdivision);
    if(vertexCount)*vertexCount=(NSUInteger)count;
    if(storage)*storage=data;
    return mesh;
}
// FIX23: per-channel isolation for render-server dispersion. The 4x5 matrix
// is passed in QuartzCore's CAColorMatrix layout (20 floats).
typedef struct { float m[20]; } WXGColorMatrix;
// FIX114 J: TEST9's 5% saturation unless the range sets its own (and a brightness).
static const WXGBackdropTone WXGBackdropToneTest9={1.05,0};
static id WXGMakeChannelFilter(NSInteger channel,BOOL plain,WXGBackdropTone tone) {
    if(!WXGFilterFactoryAvailable() || channel<1 || channel>3)return nil;
    id filter=[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"];
    WXGColorMatrix matrix={{0}};
    // FIX27: this channel's row of TEST9's 5% saturation (Rec.709 weights),
    // so one matrix pass replaces colorSaturate + isolation per layer.
    // FIX113 U: plain (a lens seeing the bar, already saturated): none.
    // FIX114 J: the range's saturation, its brightness added to the row.
    const float s=plain?1.f:(float)tone.saturation,weights[3]={.2126f,.7152f,.0722f};
    int row=(int)channel-1;
    for(int column=0;column<3;column++)matrix.m[row*5+column]=(1.f-s)*weights[column]+(column==row?s:0.f);
    if(!plain)matrix.m[row*5+4]=(float)tone.brightness;
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
static id WXGMakeSpectralFilter(NSInteger tapIndex) {
    if(!WXGFilterFactoryAvailable() || tapIndex<0 || tapIndex>=WXG_KYANT_SPECTRAL_TAPS)return nil;
    id filter=[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"];
    WXG_K_F3 w=WXGKyantSpectralRGBWeight((int)tapIndex);
    WXGColorMatrix matrix={{0}};
    matrix.m[0]=w.x;
    matrix.m[6]=w.y;
    matrix.m[12]=w.z;
    // Every tap samples an opaque scene. Keep its alpha valid; plusL adds the
    // weighted RGB of later taps. Zero-alpha colored samples may be discarded
    // by the render server before additive compositing.
    matrix.m[18]=1.f;
    @try {
        [filter setValue:[NSValue valueWithBytes:&matrix objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];
    } @catch(__unused NSException *error) {filter=nil;}
    return filter;
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
// FIX113 U: the capture group may change (the lens' own, to see the bar);
// plain: no 5% saturation (what it captures has it already).
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel plain:(BOOL)plain;
// FIX114 J: with the range's saturation and brightness (not when plain).
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel plain:(BOOL)plain tone:(WXGBackdropTone)tone;
- (void)configureSpectralGroup:(NSString *)group tapIndex:(NSInteger)tapIndex radius:(CGFloat)radius;
@property(nonatomic,readonly) WXGBackdropTone tone;
@property(nonatomic,readonly) NSInteger channel;
@property(nonatomic,readonly,copy) NSString *group;
- (void)applyRefraction:(WXGMeshOptics)optics enabled:(BOOL)enabled;
- (void)applyRefraction:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality enabled:(BOOL)enabled;
- (BOOL)applyRefraction:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality enabled:(BOOL)enabled loose:(BOOL)loose;   // FIX114 A: NO when a near mesh was kept
@end
@implementation WXGSyncBackdropView {
    WXGMeshOptics _meshOptics;
    WXGMeshQuality _meshQuality;
    NSMutableData *_meshStorage;
    BOOL _plain;
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
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel {[self configureGroup:group radius:radius channel:channel plain:NO];}
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel plain:(BOOL)plain {
    [self configureGroup:group radius:radius channel:channel plain:plain tone:WXGBackdropToneTest9];
}
- (void)configureGroup:(NSString *)group radius:(CGFloat)radius channel:(NSInteger)channel plain:(BOOL)plain tone:(WXGBackdropTone)tone {
    if(!self.live)return;
    radius=MAX(0,radius);
    BOOL sameGroup=(!group && !_group) || [group isEqualToString:_group];
    BOOL sameTone=fabs(tone.saturation-_tone.saturation)<.0005 && fabs(tone.brightness-_tone.brightness)<.0005;
    if(_radius>=0 && fabs(radius-_radius)<.05 && channel==_channel && sameGroup && plain==_plain && sameTone)return;
    BOOL first=_radius<0;_radius=radius;_channel=channel;_plain=plain;_tone=tone;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        if(first) {
            id initial=[self.layer valueForKey:@"scale"];
            _defaultCaptureScale=[initial respondsToSelector:@selector(doubleValue)]?[initial doubleValue]:-1;
            [self.layer setValue:@YES forKey:@"enabled"];
        }
        if(first || !sameGroup) {
            // One group per glass: its body backdrops share one capture taken
            // beneath the body. FIX113 U: the lens has its own group when it
            // is to see the bar (the bar's veil, rim and icons beneath it);
            // in the body's group it sees the page only.
            [self.layer setValue:group forKey:@"groupName"];
            _group=[group copy];
        }
        // FIX27: a blur under 0.2 pt is invisible but still a full pass.
        id filter=radius>=.2?WXGMakeBlurFilter(radius):nil;
        NSMutableArray *filters=[NSMutableArray array];
        if(filter)[filters addObject:filter];
        id isolate=channel>0?WXGMakeChannelFilter(channel,plain,tone):nil;
        if(isolate)[filters addObject:isolate];
        else if(!plain) {
            // TEST9 adds 5% saturation to the face (wxgBody); match it here.
            // FIX114 J: the range's own saturation, then its brightness.
            id saturate=WXGFilterFactoryAvailable()?[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorSaturate"]:nil;
            @try {[saturate setValue:@(tone.saturation) forKey:@"inputAmount"];} @catch(__unused NSException *error) {saturate=nil;}
            if(saturate)[filters addObject:saturate];
            if(fabs(tone.brightness)>.0005 && WXGFilterFactoryAvailable()) {
                id lift=[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"];
                WXGColorMatrix m={{0}};
                for(int row=0;row<3;row++){m.m[row*5+row]=1.f;m.m[row*5+4]=(float)tone.brightness;}
                m.m[18]=1.f;
                @try {[lift setValue:[NSValue valueWithBytes:&m objCType:"{CAColorMatrix=ffffffffffffffffffff}"] forKey:@"inputColorMatrix"];} @catch(__unused NSException *error) {lift=nil;}
                if(lift)[filters addObject:lift];
            }
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
- (void)configureSpectralGroup:(NSString *)group tapIndex:(NSInteger)tapIndex radius:(CGFloat)radius {
    if(!self.live)return;
    BOOL sameGroup=(!group && !_group) || [group isEqualToString:_group];
    NSInteger encodedChannel=100+tapIndex;
    radius=MAX(0,radius);
    if(_radius>=0 && fabs(_radius-radius)<.05 && _channel==encodedChannel && sameGroup && _plain)return;
    BOOL first=_radius<0;_radius=radius;_channel=encodedChannel;_plain=YES;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        if(first) {
            id initial=[self.layer valueForKey:@"scale"];
            _defaultCaptureScale=[initial respondsToSelector:@selector(doubleValue)]?[initial doubleValue]:-1;
            [self.layer setValue:@YES forKey:@"enabled"];
        }
        if(first || !sameGroup) {
            [self.layer setValue:group forKey:@"groupName"];
            _group=[group copy];
        }
        id spec=WXGMakeSpectralFilter(tapIndex);
        [self.layer setValue:@(MAX(2.,radius*3.)) forKey:@"marginWidth"];
        id blur=radius>=.2?WXGMakeBlurFilter(radius):nil;
        NSMutableArray *filters=[NSMutableArray array];
        if(blur)[filters addObject:blur];if(spec)[filters addObject:spec];
        self.layer.filters=filters.count?filters:nil;
        self.layer.compositingFilter=tapIndex>0?WXGMakePlusLighter():nil;
        _filtered=blur!=nil;
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
    [self applyRefraction:optics quality:quality enabled:enabled loose:NO];
}
- (BOOL)applyRefraction:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality enabled:(BOOL)enabled loose:(BOOL)loose {
    if(!self.live)return YES;
    if(!enabled || !WXGMeshTransformClass()) {
        if(_meshApplied) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            @try {[self.layer setValue:nil forKey:@"meshTransform"];} @catch(__unused NSException *error) {}
            [CATransaction commit];
            _meshApplied=NO;_meshAccepted=NO;_meshStorage=nil;_meshVertices=0;
        }
        return YES;
    }
    BOOL sameQuality=fabsf(quality.ringError-_meshQuality.ringError)<.001f &&
        fabsf(quality.arcStep-_meshQuality.arcStep)<.001f && fabsf(quality.straightStep-_meshQuality.straightStep)<.05f;
    if(_meshApplied && (loose || sameQuality) && WXGMeshOpticsClose(optics,_meshOptics))return YES;
    if(_meshApplied && loose && WXGMeshOpticsNear(optics,_meshOptics))return NO;
    NSUInteger count=0;NSMutableData *storage=nil;
    NSInteger steps=-99;
    id mesh=WXGMakeMeshTransform(optics,quality,&count,&storage,&steps);
    _meshSubdivision=steps;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {[self.layer setValue:mesh forKey:@"meshTransform"];} @catch(__unused NSException *error) {mesh=nil;}
    [CATransaction commit];
    _meshOptics=optics;_meshQuality=quality;_meshApplied=mesh!=nil;_meshStorage=storage;_meshVertices=count;
    // The CC tweaks log when a backdrop refuses the mesh; record the same.
    // The layer may store a copy, so accepted means "a mesh is set", not identity.
    _meshAccepted=mesh && [self.layer respondsToSelector:NSSelectorFromString(@"setMeshTransform:")] &&
        [self.layer valueForKey:@"meshTransform"]!=nil;
    return YES;
}
@end
// A moving compositor lens and the regular dock use the same padded R8 field.
// bar and lens are in the same coordinate space, size is the rounded mesh size.
static WXGMeshOptics WXGPureDockLensOptics(WXGConfig *c, CGRect lens, CGRect bar, CGSize size,
                                           CGFloat radius, CGFloat restHeight, float press, CGFloat dockScale,
                                           BOOL shrink, CGFloat *padding) {
    float shortSide=(float)MIN(size.width,size.height);
    CGFloat barH=MAX(1.,bar.size.height);
    float r8Band=(float)([c pureDockR8Band]*dockScale),r8Depth=(float)([c pureDockR8Depth]*dockScale),r8Disp=(float)[c pureDockR8Dispersion];
    WXGMeshOptics lensOptics=(WXGMeshOptics){(float)size.width,(float)size.height,1.f,radius,MAX(.5f,r8Band*press),0.f,1.f,
        1.f,1.f,r8Disp,0.f,0.f,0.f};
    lensOptics.kyantMode=1.f;
    lensOptics.zoomAfter=1.f;
    lensOptics.kyantHeight=r8Band*press;
    lensOptics.kyantAmount=r8Depth*press;
    lensOptics.shrinkFlat=[c pureDockInnerFlat]?1.f:0.f;
    CGFloat pad=0;
    if(shrink && press>0.f) {
        CGFloat pinch=WXGClamp([c pureDockInnerBarShrink],0.,.55);
        CGFloat full=barH*.5*pinch;
        CGFloat refShort=MIN((CGFloat)shortSide,restHeight>1?restHeight*.82:(CGFloat)shortSide);
        CGFloat spectralDisp=r8Disp>0.f && WXGFilterFactoryAvailable()?r8Disp:0.;
        CGFloat ring=spectralDisp>0?4.5*spectralDisp/(1.+.25*spectralDisp):0.;
        CGFloat farSide=MAX(0.,1.55*(CGFloat)r8Depth-refShort);
        pad=MIN(64.,ceil((full+MAX(ring,farSide)+4.)/2.)*2.);
        CGFloat reach=barH*.65+4.;
        CGFloat left=CGRectGetMinX(bar)-CGRectGetMinX(lens),right=CGRectGetMaxX(bar)-CGRectGetMinX(lens);
        lensOptics.sbLeft=left<-reach?-10000.f:(float)(round(left*2)/2);
        lensOptics.sbRight=right>size.width+reach?10000.f:(float)(round(right*2)/2);
        lensOptics.sbTop=(float)(round((CGRectGetMinY(bar)-CGRectGetMinY(lens))*2)/2);
        lensOptics.sbBottom=(float)(round((CGRectGetMaxY(bar)-CGRectGetMinY(lens))*2)/2);
        lensOptics.sbRadius=0;
        lensOptics.shrinkPress=press;
        lensOptics.shrinkPinch=(float)(round(pinch*1000.)/1000.);
        CGFloat restH=restHeight>1?round(restHeight*2)/2:size.height;
        lensOptics.shrinkExtra=(float)((restH-size.height)*.5);
        lensOptics.padX=lensOptics.padY=(float)pad;lensOptics.width+=(float)(2*pad);lensOptics.height+=(float)(2*pad);
        lensOptics.sbLeft+=(float)pad;lensOptics.sbRight+=(float)pad;lensOptics.sbTop+=(float)pad;lensOptics.sbBottom+=(float)pad;
    }
    *padding=pad;
    return lensOptics;
}

@interface WXGTravelMeshPhases : NSObject
@property(nonatomic,copy) NSArray *meshes,*storage;
@property(nonatomic) CGFloat peakPress;
@end
@implementation WXGTravelMeshPhases
@end
static char WXGTravelMeshPhasesKey;
enum { WXGTravelLiftSteps=4 };

// Animate the sampling coordinates. All phases use the lifted mesh's topology:
// QuartzCore interpolates compatible CAMeshTransforms on the render server.
static BOOL WXGPrepareTravelMeshPhases(CALayer *layer,WXGMeshOptics optics,CGFloat peakPress) {
    NSUInteger count=0;NSMutableData *source=nil;
    id full=WXGMakeMeshTransform(optics,WXGMeshQualityLensMove,&count,&source,NULL);
    if(![full respondsToSelector:@selector(CA_interpolateValue:byFraction:)] || !count ||
       source.length<=count*sizeof(WXGMeshVertex))return NO;
    NSUInteger faces=(source.length-count*sizeof(WXGMeshVertex))/sizeof(WXGMeshFace);
    NSMutableArray *meshes=[NSMutableArray array],*storage=[NSMutableArray array];
    for(int phase=0;phase<WXGTravelLiftSteps;phase++) {
        float t=(float)phase/WXGTravelLiftSteps;
        WXGMeshOptics state=optics;
        state.kyantHeight*=t;state.kyantAmount*=t;state.shrinkPress*=t;
        NSMutableData *data=[source mutableCopy];
        WXGMeshVertex *vertices=data.mutableBytes;
        for(NSUInteger j=0;j<count;j++) {
            WXGMeshVertex *v=&vertices[j];
            if(phase==0) {v->from=CGPointMake(v->to.x,v->to.y);continue;}
            float sx,sy;
            WXGMeshSource(state,(float)v->to.x*state.width,(float)v->to.y*state.height,&sx,&sy);
            v->from=CGPointMake(WXGMeshUnit(sx,state.width),WXGMeshUnit(sy,state.height));
        }
        id mesh=WXGCreateMesh(WXGMeshTransformClass(),count,vertices,faces,(WXGMeshFace *)(vertices+count),NULL);
        if(!mesh)return NO;
        [meshes addObject:mesh];[storage addObject:data];
    }
    [meshes addObject:full];[storage addObject:source];
    WXGTravelMeshPhases *track=[WXGTravelMeshPhases new];
    track.meshes=meshes;track.storage=storage;track.peakPress=peakPress;
    objc_setAssociatedObject(layer,&WXGTravelMeshPhasesKey,track,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

void WXGAnimatePureTravelRefraction(CALayer *layer,NSArray<NSNumber *> *press,NSArray<NSNumber *> *times,
                                    CFTimeInterval start,CFTimeInterval duration) {
    WXGTravelMeshPhases *track=objc_getAssociatedObject(layer,&WXGTravelMeshPhasesKey);
    if(!track || press.count<2 || press.count!=times.count || duration<=0)return;
    NSMutableArray *values=[NSMutableArray array],*keys=[NSMutableArray array];
    double (^phaseAt)(NSUInteger)=^double(NSUInteger i){return WXGTravelLiftSteps*WXGClamp(press[i].doubleValue/track.peakPress,0,1);};
    void (^add)(double,double)=^(double time,double phase) {
        if(keys.count && fabs(time-[keys.lastObject doubleValue])<1e-6)return;
        int nearest=(int)round(phase),lo=(int)floor(phase);
        id mesh=track.meshes[nearest];
        if(fabs(phase-nearest)>.001 && lo<WXGTravelLiftSteps) {
            @try {mesh=[track.meshes[lo] CA_interpolateValue:track.meshes[lo+1] byFraction:(float)(phase-lo)]?:mesh;}
            @catch(__unused NSException *e) {}
        }
        [keys addObject:@(time)];[values addObject:mesh];
    };
    // Submit only the lift thresholds and local extrema. During a hold the
    // render server needs two copies of the held mesh, regardless of its FPS.
    add(0,phaseAt(0));
    double a=phaseAt(0);
    int previousDirection=0;
    for(NSUInteger i=1;i<press.count;i++) {
        double b=phaseAt(i),t0=times[i-1].doubleValue,t1=times[i].doubleValue;
        int direction=(b>a+1e-7)-(b<a-1e-7);
        if(i>1 && direction!=previousDirection)add(t0,a);
        if(direction) {
            int knot=direction>0?(int)floor(a)+1:(int)ceil(a)-1;
            for(;direction>0?knot<=b:knot>=b;knot+=direction)
                add(t0+(t1-t0)*(knot-a)/(b-a),knot);
        }
        a=b;previousDirection=direction;
    }
    add(1,a);
    CAKeyframeAnimation *animation=[CAKeyframeAnimation animationWithKeyPath:@"meshTransform"];
    animation.values=values;animation.keyTimes=keys;animation.duration=duration;
    animation.beginTime=[layer convertTime:start fromLayer:nil];animation.calculationMode=kCAAnimationLinear;
    animation.fillMode=kCAFillModeBoth;animation.removedOnCompletion=NO;
    [layer addAnimation:animation forKey:@"meshTransform"];
}

BOOL WXGApplyPureTravelGlyphRefraction(CALayer *canvas,CGSize size,CGFloat padding,CGFloat press) {
    if (!canvas || !WXGShaderKyantOptics || ![canvas respondsToSelector:NSSelectorFromString(@"setMeshTransform:")] ||
        size.width<2 || size.height<2 || padding<0 || press<=0) return NO;
    CGSize rounded=CGSizeMake(round(size.width),round(size.height));
    CGRect rect=(CGRect){CGPointZero,size};
    CGFloat unused=0;
    WXGMeshOptics optics=WXGPureDockLensOptics(WXGConfig.shared,rect,rect,rounded,0,0,
                                               roundf((float)WXGClamp(press,0,1)*32.f)/32.f,1,NO,&unused);
    // wxgKyantLensOverlay: the glyph's central ray never takes the bar end
    // warp or the inner selection's vertical shrink. Tile zoom happens in
    // the canvas before the mesh, around each tile's own stationary anchor.
    optics.padX=optics.padY=(float)padding;
    optics.width+=(float)(2*padding);optics.height+=(float)(2*padding);
    optics.dispersion=0;
    NSMutableData *storage=nil;
    id mesh=WXGMakeMeshTransform(optics,WXGMeshQualityLensMove,NULL,&storage,NULL);
    if(!mesh)return NO;
    @try {
        [canvas setValue:mesh forKey:@"meshTransform"];
        if(![canvas valueForKey:@"meshTransform"])return NO;
    } @catch(__unused NSException *error) {return NO;}
    return WXGPrepareTravelMeshPhases(canvas,optics,press);
}

NSArray<UIView *> *WXGMakePureTravelLensBackdrops(CGRect lens,CGRect bar,CGFloat restHeight,CGFloat press,
                                                  NSString *group,CGFloat *padding) {
    if (padding) *padding=0;
#ifdef WXG_MESH_OFF
    return @[];
#else
    WXGConfig *c=WXGConfig.shared;
    if (!WXGShaderKyantOptics || WXGEffectiveRenderMode()<2 || !c.syncMeshRefraction ||
        !c.dockPureGlassMode || !WXGBackdropLayerClass() || !WXGMeshTransformClass() ||
        lens.size.width<2 || lens.size.height<2 || CGRectIsEmpty(bar) || press<=0) return @[];
    CGSize meshSize=CGSizeMake(round(lens.size.width),round(lens.size.height));
    CGFloat pad=0;
    float lift=roundf((float)WXGClamp(press,0,1)*32.f)/32.f;
    WXGMeshOptics optics=WXGPureDockLensOptics(c,lens,bar,meshSize,0,restHeight,lift,1,YES,&pad);
    BOOL spectral=optics.dispersion>0 && WXGFilterFactoryAvailable();
    NSInteger count=spectral?WXG_KYANT_SPECTRAL_TAPS:1;
    NSString *captureGroup=group.length?group:NSUUID.UUID.UUIDString;
    NSMutableArray<UIView *> *views=[NSMutableArray arrayWithCapacity:count];
    CGRect rect=CGRectInset((CGRect){CGPointZero,lens.size},-pad,-pad);
    for (NSInteger i=0;i<count;i++) {
        WXGSyncBackdropView *view=[[WXGSyncBackdropView alloc] initWithFrame:rect];
        if (!view.live) return @[];
        if (spectral) {
            [view configureSpectralGroup:captureGroup tapIndex:i radius:0];
            if (!view.layer.filters.count || (i>0 && !view.layer.compositingFilter)) return @[];
        } else {
            [view configureGroup:captureGroup radius:0 channel:0 plain:YES tone:(WXGBackdropTone){1,0}];
            optics.dispersion=0;
        }
        view.captureLimit=c.performanceMode?2:0;
        [view applyCaptureScale];
        optics.kyantChannel=spectral?WXGKyantSpectralOffset((int)i):0;
        [view applyRefraction:optics quality:WXGMeshQualityLensMove enabled:YES];
        if (!view.meshAccepted || !WXGPrepareTravelMeshPhases(view.layer,optics,press)) return @[];
        [views addObject:view];
    }
    if (padding) *padding=pad;
    return views;
#endif
}

NSArray<UIView *> *WXGMakeTravelLensBackdrops(CGSize size,CGFloat press,NSString *group,BOOL seesBar,CGFloat barHeight) {
    if(size.width<2 || size.height<2 || !NSClassFromString(@"CABackdropLayer"))return @[];
    WXGConfig *c=WXGConfig.shared;
    // FIX37: the optics of the lens at `press`, like the real lens: resting
    // glass blending into the independent lens parameters as it lifts.
    press=WXGClamp(press,0,1);
    WXGScopeOptics dock=[c opticsForDock:YES];   // FIX58: the tap lens belongs to the dock
    // The dock's lens: the curve, its band and depth shares of its short side (applySyncMode).
    WXGLensSettings TL=[c lensSettingsForScope:WXGGlassScopeDock dark:NO];
    float kd=roundf((float)TL.split*100.f)/100.f;
    BOOL split=kd>0.f && c.syncDispersion && WXGFilterFactoryAvailable();
    BOOL darkTone=UIScreen.mainScreen.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    NSMutableArray<UIView *> *views=[NSMutableArray array];
    CGSize padded=size;
    for(NSInteger i=0;i<(split?3:1);i++) {
        WXGSyncBackdropView *v=[[WXGSyncBackdropView alloc]initWithFrame:(CGRect){CGPointZero,padded}];
        if(!v.live)return @[];
        // FIX113 U: seeing the bar (its own group), only the lens' own blur.
        CGFloat radius=(seesBar?c.lensBlur*press:dock.blur+(c.lensBlur-dock.blur)*press)*c.syncBlurScale;
        [v configureGroup:group.length?group:@"wxg.travel" radius:radius channel:split?i+1:0 plain:seesBar tone:[c backdropToneForScope:WXGGlassScopeDock dark:darkTone]];
        v.captureLimit=c.performanceMode?2:0;[v applyCaptureScale];
        float shortSide=(float)MIN(padded.width,padded.height);
        float band=roundf((float)TL.band*shortSide*(float)press*4.f)/4.f,depth=roundf((float)TL.depth*shortSide*(float)press*4.f)/4.f;
        WXGMeshOptics o={(float)padded.width,(float)padded.height,1.f,0.f,WXG_MAX(band,.5f),0.f,1.f,1.f,1.f+(float)(press*(TL.zoom-1)),
            split?kd:0.f,split?(i==0?1.f:i==2?-1.f:0.f):0.f,0.f,0.f};
        o.curveHeight=band>.01f && depth>.01f?band:0.f;o.curveAmount=depth;o.curveSqueeze=(float)TL.squeeze;
        // FIX113 U: seeing the bar, the smaller bar as the dock's lens shows
        // it (centred on the lens; the travel crosses the bar, so no ends).
        if(seesBar && barHeight>2 && barHeight<padded.height) {
            o.sbLeft=-10000.f;o.sbRight=10000.f;o.sbTop=(float)((padded.height-barHeight)*.5);o.sbBottom=(float)((padded.height+barHeight)*.5);
            o.shrinkPress=(float)press;o.shrinkPinch=(float)WXGClamp(c.bodyPinch,0,.30);
        }
        [v applyRefraction:o quality:WXGMeshShrinks(o)?WXGMeshQualityLensBar:WXGMeshQualityLens enabled:YES];
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
// FIX133: a capsule's outline as iOS 26 draws it (WXGCapsule26.h: its long
// edges sink toward the round ends from half a radius before them), in its
// own box moved by (dx, dy), as a closed sub-path.
static void WXGCapsule26AddOutline(CGMutablePathRef path,CGSize size,CGFloat dx,CGFloat dy) {
    enum { capacity=4*WXG_CAPSULE26_QUARTER_MAX };
    double xs[capacity],ys[capacity];
    int n=WXGCapsule26Outline(size.width,size.height,xs,ys,capacity);
    if(n<3)return;
    CGPathMoveToPoint(path,NULL,dx+(CGFloat)xs[0],dy+(CGFloat)ys[0]);
    for(int i=1;i<n;i++)CGPathAddLineToPoint(path,NULL,dx+(CGFloat)xs[i],dy+(CGFloat)ys[i]);
    CGPathCloseSubpath(path);
}
// The band `width` deep inside that outline (filled even-odd: the outline
// and the outline of the capsule that much smaller; the dip is a share of
// the radius, so the two run parallel to within 0.02 pt). Kept by size:
// every glass of a size shares its bands' paths.
static CGPathRef WXGCapsule26Band(CGSize size,CGFloat width) {
    static NSCache<NSString *,UIBezierPath *> *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=160;});
    NSString *key=[NSString stringWithFormat:@"%.2f|%.2f|%.3f",size.width,size.height,width];
    UIBezierPath *kept=[cache objectForKey:key];
    if(kept)return kept.CGPath;
    CGMutablePathRef path=CGPathCreateMutable();
    WXGCapsule26AddOutline(path,size,0,0);
    CGSize inner=CGSizeMake(size.width-2*width,size.height-2*width);
    if(inner.width>.5 && inner.height>.5)WXGCapsule26AddOutline(path,inner,width,width);
    kept=[UIBezierPath bezierPathWithCGPath:path];CGPathRelease(path);
    [cache setObject:kept forKey:key];
    return kept.CGPath;
}
// One border per band: the outline inset by the band's inset, with the corner
// radius inset with it, the band's width and opacity. Layers are pooled in z
// order (placed first = lowest); returns how many are in use.
// FIX133: on a capsule the bands are filled shapes along iOS 26's own
// outline (WXGCapsule26Band) instead of Core Animation borders, whose
// capsule stays straight almost up to its round ends.
static NSUInteger WXGRimPlaceBands(CALayer *holder,NSMutableArray<CALayer *> *pool,NSUInteger used,const WXGRimBands *bands,
                                   CGSize size,CGFloat radius,CGFloat red,CGFloat green,CGFloat blue,CGFloat scale) {
    BOOL capsule=WXGCapsule26Applies(size.width,size.height,radius);
    for(int k=0;k<bands->count;k++) {
        CGFloat inset=(CGFloat)bands->inset[k],width=(CGFloat)bands->width[k],alpha=(CGFloat)bands->alpha[k];
        CGRect frame=CGRectInset((CGRect){CGPointZero,size},inset,inset);
        if(width<.001 || alpha<.001 || CGRectIsEmpty(frame))continue;
        CAShapeLayer *band;
        if(used<pool.count)band=(CAShapeLayer *)pool[used];
        else {
            band=[CAShapeLayer layer];band.cornerCurve=kCACornerCurveContinuous;band.fillRule=kCAFillRuleEvenOdd;band.strokeColor=nil;band.lineWidth=0;band.fillColor=nil;
            [holder addSublayer:band];[pool addObject:band];
        }
        ++used;
        band.hidden=NO;band.frame=frame;band.contentsScale=scale;
        UIColor *colour=[UIColor colorWithRed:red green:green blue:blue alpha:WXGClamp(alpha,0,1)];   // (kept while its CGColor is handed over)
        if(capsule) {
            band.cornerRadius=0;band.borderWidth=0;
            band.path=WXGCapsule26Band(frame.size,width);band.fillColor=colour.CGColor;
        }else {
            band.path=nil;band.fillColor=nil;
            band.cornerRadius=MAX(0,radius-inset);band.borderWidth=width;band.borderColor=colour.CGColor;
        }
    }
    return used;
}
static void WXGRimHideBands(NSArray<CALayer *> *pool,NSUInteger used) {for(NSUInteger i=used;i<pool.count;i++)pool[i].hidden=YES;}
_Static_assert(WXG_RIM_GLOW_MAX_BANDS<=2*WXG_RIM_MAX_STEPS+1,"the glow's steps fit WXGRimBands");
// FIX89: one highlight of the iOS 27-like rim: its nested bands (its colour)
// under its level along the outline (the mask), the group at its opacity.
@interface WXGRimGlowLayer : CALayer
- (void)applyShape:(WXGRimGlowShape)shape bounds:(CGRect)bounds radius:(CGFloat)r scale:(CGFloat)scale;
@property(nonatomic,readonly) NSUInteger bandsShown;
@end
@implementation WXGRimGlowLayer {
    WXGRimLevelLayer *_level;
    NSMutableArray<CALayer *> *_bands;
    double _key[9];
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
    double key[9]={size.width,size.height,r,scale,width,shape.falloff,shape.red,shape.green,shape.blue};
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
static NSHashTable *WXGRimViews;            // every iOS 27 rim, for the export
// The iOS 27 边框 (WXGRimGlow.h): lights fading inward from the outline,
// nested bands of the glass's own outline (Core Animation borders on its
// continuous corners), each about 1 px wider than the last, under their level
// along the outline (WXGRimLevelLayer); one WXGRimGlowLayer per highlight,
// each with its own colour and opacity, the later over the earlier.
// (The iOS 26 边框 is WXGRim26View below.)
@interface WXGRimView : UIView
@property(nonatomic) CGFloat maximumCornerRadius;
- (void)configureGlows:(const WXGRimGlowShape *)shapes count:(NSInteger)count;   // 0 = off
- (NSDictionary *)rimEvidence;
@end
@implementation WXGRimView {
    NSInteger _glowCount;
    WXGRimGlowShape _glowShapes[WXGRimGlowCount];
    NSMutableArray<WXGRimGlowLayer *> *_glowLayers;
}
- (instancetype)init {
    if((self=[super initWithFrame:CGRectZero])) {
        self.userInteractionEnabled=NO; self.opaque=NO; self.backgroundColor=UIColor.clearColor;
        self.layer.cornerCurve=kCACornerCurveContinuous;
        if(!WXGRimViews)WXGRimViews=[NSHashTable weakObjectsHashTable];
        [WXGRimViews addObject:self];
    } return self;
}
- (void)configureGlows:(const WXGRimGlowShape *)shapes count:(NSInteger)count {
    count=shapes?MAX(0,MIN(count,(NSInteger)WXGRimGlowCount)):0;
    if(count==_glowCount && (!count || !memcmp(shapes,_glowShapes,sizeof(WXGRimGlowShape)*(size_t)count)))return;
    _glowCount=count;
    if(count)memcpy(_glowShapes,shapes,sizeof(WXGRimGlowShape)*(size_t)count);
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height,r=MIN(w,h)*.5;
    if(_maximumCornerRadius>0)r=MIN(r,_maximumCornerRadius);
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    self.layer.cornerRadius=r; self.layer.contentsScale=scale;
    if(_glowCount && !_glowLayers)_glowLayers=[NSMutableArray array];
    while((NSInteger)_glowLayers.count<_glowCount){WXGRimGlowLayer *layer=[WXGRimGlowLayer layer];[self.layer addSublayer:layer];[_glowLayers addObject:layer];}
    for(NSInteger i=0;i<(NSInteger)_glowLayers.count;i++) {
        if(i<_glowCount)[_glowLayers[i] applyShape:_glowShapes[i] bounds:self.bounds radius:r scale:scale];
        else _glowLayers[i].hidden=YES;
    }
    [CATransaction commit];
}
- (NSDictionary *)rimEvidence {
    NSMutableArray *glows=[NSMutableArray array];
    for(NSInteger i=0;i<_glowCount;i++) {
        WXGRimGlowShape g=_glowShapes[i];
        [glows addObject:@{@"width":@(g.width),@"falloff":@(g.falloff),@"endLevel":@(g.endLevel),@"sharpness":@(g.sharpness),@"angle":@(g.angle),
                           @"colour":@[@(round(g.red*1000)/1000),@(round(g.green*1000)/1000),@(round(g.blue*1000)/1000)],@"opacity":@(round(g.alpha*1000)/1000),
                           @"bands":@(i<(NSInteger)_glowLayers.count?_glowLayers[i].bandsShown:0)}];
    }
    return @{@"on":@(_glowCount>0),@"glow":glows,@"size":@[@(round(self.bounds.size.width*10)/10),@(round(self.bounds.size.height*10)/10)],
             @"cornerRadius":@(round(self.layer.cornerRadius*10)/10),@"onScreen":@(self.window!=nil && !self.hidden)};
}
@end
// FIX123 iOS 26 边框 (WXGRim26.h): the system's own recipe, read from the
// structure dump and the 8x captures of probe/ on iOS 26.6.
// The rim itself is WXGRim26RingLayer below (Core Animation borders: no image).
static NSValue *WXGRim26MatrixValue(WXGRimMatrix m) {return [NSValue valueWithBytes:&m objCType:"{CAColorMatrix=ffffffffffffffffffff}"];}
// FIX125: the rim's alpha as Core Animation's own shapes on the glass' own
// continuous corner (WXGRim26.h, WXGRim26BandsFor): white borders one pixel
// wider each from the outline (WXGRimPlaceBands, as the earlier styles'
// lines), the lights' set under the level along the outline (a
// WXGRimFieldLayer, as the iOS 27-like rim's), the faint line's set plain;
// one over the other they show WXGRim26Alpha. The render server draws every
// edge of it on the same curve as the glass' clip: no outline of our own,
// nothing to clip, no tips. Its opacity is the rim's strength.
@interface WXGRim26RingLayer : CALayer
- (void)applyShape:(WXGRim26Shape)shape bounds:(CGRect)bounds radius:(CGFloat)r scale:(CGFloat)scale;
@property(nonatomic,readonly) NSUInteger bandsShown;
@end
@implementation WXGRim26RingLayer {
    CALayer *_lights,*_plain;WXGRimFieldLayer *_level;
    NSMutableArray<CALayer *> *_lightBands,*_plainBands;
    double _key[12];BOOL _applied;
}
- (instancetype)init {
    if((self=[super init])) {
        _plain=[CALayer layer];[self addSublayer:_plain];
        _lights=[CALayer layer];_level=[WXGRimFieldLayer layer];_lights.mask=_level;[self addSublayer:_lights];
        _lightBands=[NSMutableArray array];_plainBands=[NSMutableArray array];
    }
    return self;
}
static WXGRimBands WXGRim26RimBands(WXGRim26Bands b) {
    WXGRimBands out;memset(&out,0,sizeof out);
    int room=(int)(sizeof out.inset/sizeof *out.inset);
    out.count=b.count<room?b.count:room;
    for(int k=0;k<out.count;k++){out.inset[k]=0;out.width[k]=b.width[k];out.alpha[k]=b.alpha[k];}
    return out;
}
- (void)applyShape:(WXGRim26Shape)shape bounds:(CGRect)bounds radius:(CGFloat)r scale:(CGFloat)scale {
    double key[12]={shape.height,shape.curve,shape.angle,shape.key,shape.fill,shape.spread,shape.ring,
                    round(bounds.size.width*2.)*.5,round(bounds.size.height*2.)*.5,round(r*2.)*.5,scale,shape.floor};
    self.frame=bounds;
    if(_applied && !memcmp(key,_key,sizeof key))return;
    memcpy(_key,key,sizeof key);_applied=YES;
    CGRect inner=(CGRect){CGPointZero,bounds.size};
    _lights.frame=inner;_plain.frame=inner;
    WXGRimBands lights=WXGRim26RimBands(WXGRim26BandsFor(0,shape,scale)),plain=WXGRim26RimBands(WXGRim26BandsFor(1,shape,scale));
    NSUInteger used=WXGRimPlaceBands(_lights,_lightBands,0,&lights,inner.size,r,1,1,1,scale);
    WXGRimHideBands(_lightBands,used);_bandsShown=used;
    used=WXGRimPlaceBands(_plain,_plainBands,0,&plain,inner.size,r,1,1,1,scale);
    WXGRimHideBands(_plainBands,used);_bandsShown+=used;
    [_level applyTop:(CGFloat)WXGRim26Along(0,-1,shape) bottom:(CGFloat)WXGRim26Along(0,1,shape) left:(CGFloat)WXGRim26Along(-1,0,shape) right:(CGFloat)WXGRim26Along(1,0,shape)
            fieldKey:[NSString stringWithFormat:@"rim26|%.2f|%.3f|%.3f|%.3f|%.3f",shape.angle,shape.key,shape.fill,shape.spread,shape.floor]
               level:^float(float nx,float ny){return (float)WXGRim26Along(nx,ny,shape);}];
    [_level layoutForBounds:inner radius:r];
}
@end
// FIX123: the system draws the rim as a white layer under the filter
// vibrantColorMatrix: every pixel the glass already drawn under it turned by
// the matrix, mixed by the layer's alpha. Here, the same result from parts
// known to work on any system: a copy of what lies under the rim (its own
// backdrop group: the glass and the page around it; no blur, a low
// resolution) through the same matrix (a plain colorMatrix), shown through
// the rim's alpha as its mask (FIX125: WXGRim26RingLayer; the mask's root is a
// plain container, as the 取自背景 line's). Glass with no backdrop of its
// own: the veil through the matrix, as a solid layer under the same mask.
@interface WXGRim26Paint : UIView
@property(nonatomic,readonly) WXGRim26RingLayer *ring;   // its opacity is the rim's strength
- (void)configureGroup:(NSString *)group matrix:(WXGRimMatrix)m captureScale:(CGFloat)captureScale solid:(UIColor *)solid;
@end
@implementation WXGRim26Paint {CALayer *_solid,*_maskRoot;NSString *_appliedGroup;CGFloat _appliedScale;WXGRimMatrix _appliedMatrix;BOOL _matrixApplied,_enabled;}
+ (Class)layerClass {return WXGBackdropLayerClass()?:CALayer.class;}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.hidden=YES;
        _solid=[CALayer layer];_solid.hidden=YES;[self.layer addSublayer:_solid];
        _maskRoot=[CALayer layer];_ring=[WXGRim26RingLayer layer];[_maskRoot addSublayer:_ring];self.layer.mask=_maskRoot;
        _enabled=YES;
    }
    return self;
}
- (BOOL)live {Class cls=WXGBackdropLayerClass();return cls && [self.layer isKindOfClass:cls];}
- (void)layoutSubviews {[super layoutSubviews];_maskRoot.frame=self.bounds;_solid.frame=self.bounds;}
- (void)configureGroup:(NSString *)group matrix:(WXGRimMatrix)m captureScale:(CGFloat)captureScale solid:(UIColor *)solid {
    BOOL useSolid=solid!=nil || ![self live] || !WXGFilterFactoryAvailable();
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _maskRoot.frame=self.bounds;_solid.frame=self.bounds;_solid.hidden=!useSolid;
    if(useSolid) {
        double in[3],out[3];CGFloat r=1,g=1,b=1,a=1;[solid?:UIColor.grayColor getRed:&r green:&g blue:&b alpha:&a];
        in[0]=r;in[1]=g;in[2]=b;WXGRim26Colour(m.m,in,1,out);
        _solid.backgroundColor=[UIColor colorWithRed:out[0] green:out[1] blue:out[2] alpha:1].CGColor;
    }
    @try {
        if([self live]) {
            if(_enabled==useSolid){[self.layer setValue:@(!useSolid) forKey:@"enabled"];_enabled=!useSolid;}
            if(!useSolid) {
                if(group && ![_appliedGroup isEqual:group]){[self.layer setValue:group forKey:@"groupName"];_appliedGroup=group;}
                if(fabs(captureScale-_appliedScale)>.005){[self.layer setValue:@(captureScale) forKey:@"scale"];_appliedScale=captureScale;}
                if(!_matrixApplied || memcmp(&m,&_appliedMatrix,sizeof m)) {
                    id matrix=[(Class<WXGCAFilterFactory>)NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"];
                    [matrix setValue:WXGRim26MatrixValue(m) forKey:@"inputColorMatrix"];
                    self.layer.filters=matrix?@[matrix]:nil;
                    _appliedMatrix=m;_matrixApplied=YES;
                }
            }
        }
    } @catch(__unused NSException *error) {}
    [CATransaction commit];
}
@end
// FIX123: the iOS 26 rim over one glass (its body, or its lens): the rim's
// alpha (WXGRim26RingLayer) over the colour-matrix copy of what lies under it,
// and under it the optional inner shadow (the system has none; an image,
// clipped by the glass' own corner). With 系统混合滤镜 on (experimental): the
// system's own way instead, the white ring on a plain layer with
// vibrantColorMatrix (reads the pixels under it; no copy). Nothing of the
// three earlier styles is used but their two layer kinds.
@interface WXGRim26View : UIView
@property(nonatomic) CGFloat maximumCornerRadius;
@property(nonatomic,readonly) CALayer *strengthMask;
- (void)configureOn:(BOOL)on settings:(WXGRim26Settings)settings solid:(UIColor *)solid strength:(CGFloat)strength;
- (NSDictionary *)rim26Evidence;
@end
@implementation WXGRim26View {
    WXGRim26Paint *_paint;NSString *_group;
    WXGRim26Settings _settings;CGFloat _strength;BOOL _on;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.hidden=YES;
        _group=[NSString stringWithFormat:@"wxg.rim26.%p",self];
        _paint=[[WXGRim26Paint alloc]initWithFrame:CGRectZero];[self addSubview:_paint];
    }
    return self;
}
- (void)configureOn:(BOOL)on settings:(WXGRim26Settings)settings solid:(UIColor *)solid strength:(CGFloat)strength {
    strength=WXGClamp(strength,0,1);
    BOOL show=on && strength>.002 && settings.opacity>.002;
    BOOL wasOn=_on;
    _on=show;self.hidden=!show;
    if(!show){_paint.hidden=YES;return;}
    BOOL changed=!wasOn || memcmp(&settings,&_settings,sizeof settings);
    _settings=settings;_strength=strength;
    WXGRimMatrix m;WXGRim26Matrix(settings.gain,settings.chroma,settings.lift,m.m);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _paint.hidden=NO;
    [_paint configureGroup:_group matrix:m captureScale:settings.captureScale solid:solid];
    _paint.ring.opacity=(float)(strength*settings.opacity);
    [CATransaction commit];
    if(changed)[self setNeedsLayout];
}
- (CALayer *)strengthMask {return _paint.layer.mask;}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(!_on)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    CGRect b=(CGRect){CGPointZero,self.bounds.size};CGFloat r=MIN(b.size.width,b.size.height)*.5;
    if(_maximumCornerRadius>0)r=MIN(r,_maximumCornerRadius);
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    WXGRim26Settings s=_settings;
    WXGRim26Shape shape={s.height,s.curve,s.angle,s.key,s.fill,s.spread,s.ring,0,s.floor};
    _paint.frame=b;
    // FIX125: the rim on the glass' own corner, drawn by Core Animation (no
    // image, no clip of this view).
    [_paint.ring applyShape:shape bounds:b radius:r scale:scale];
    [CATransaction commit];
}
- (NSDictionary *)rim26Evidence {
    return @{@"on":@(_on),@"height":@(_settings.height),@"curve":@(_settings.curve),@"angle":@(_settings.angle),@"key":@(_settings.key),@"fill":@(_settings.fill),
             @"spread":@(_settings.spread),@"floor":@(_settings.floor),@"gain":@(_settings.gain),@"chroma":@(_settings.chroma),@"lift":@(_settings.lift),@"ring":@(_settings.ring),
             @"captureScale":@(_settings.captureScale),@"bands":@(_paint.ring.bandsShown),
             @"strength":@(_strength*_settings.opacity),
             @"size":@[@(round(self.bounds.size.width*10)/10),@(round(self.bounds.size.height*10)/10)]};
}
@end

UIView *WXGMakePureTravelLensRim(CGSize size,BOOL dark,CALayer **strengthLayer) {
    if(strengthLayer)*strengthLayer=nil;
    if(size.width<2 || size.height<2)return nil;
    WXGConfig *c=WXGConfig.shared;
    CGRect rect=(CGRect){CGPointZero,size};
    if([c rimStyleForScope:WXGGlassScopeLens]==WXGRimStyleGlow) {
        WXGRimView *rim=[[WXGRimView alloc] init];
        rim.frame=rect;
        WXGRimGlowShape shapes[WXGRimGlowCount];
        for (NSInteger i=0;i<WXGRimGlowCount;i++)
            shapes[i]=[c rimGlowForScope:WXGGlassScopeLens index:i dark:dark];
        [rim configureGlows:shapes count:WXGRimGlowCount];
        [rim layoutIfNeeded];
        if(strengthLayer)*strengthLayer=rim.layer;
        return rim;
    }
    WXGRim26View *rim=[[WXGRim26View alloc] initWithFrame:rect];
    [rim configureOn:YES settings:[c rim26ForScope:WXGGlassScopeLens dark:dark] solid:nil strength:1];
    [rim layoutIfNeeded];
    if(strengthLayer)*strengthLayer=rim.strengthMask;
    return rim;
}
#include "WXGMenuMorphMaterial.inc"

// Every iOS 27 rim at once, for the diagnostics export (any page).
NSDictionary *WXGRimSummary(void) {
    NSUInteger shown=0;NSMutableArray *samples=[NSMutableArray array];
    for(WXGRimView *view in WXGRimViews.allObjects) {
        NSDictionary *e=[view rimEvidence];
        if(![e[@"onScreen"] boolValue] || ![e[@"on"] boolValue])continue;
        ++shown;if(samples.count<8)[samples addObject:e];
    }
    WXGConfig *c=WXGConfig.shared;
    NSString *(^name)(WXGGlassScope)=^NSString *(WXGGlassScope scope){return [c rimStyleForScope:scope]==WXGRimStyleGlow?@"ios27":@"ios26";};
    return @{@"styles":@{@"dock":name(WXGGlassScopeDock),@"other":name(WXGGlassScopeOther),@"bubble":name(WXGGlassScopeBubble)},
             @"ios27OnScreen":@(shown),@"all":@(WXGRimViews.count),@"samples":samples};
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
@property(nonatomic,strong) CALayer *lensTint;   // FIX112: the whole lens's filter colour
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
@property(nonatomic,strong) id<MTLTexture> normalIcons, selectedIcons, dockTabIcons;
@property(nonatomic) WXGFloat4 dockTabCenters;
@property(nonatomic) CGSize dockTabTile;
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
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *pressedOpticsHistory;
@property(nonatomic) CFTimeInterval lastOpticsTrace;
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
            optics:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality mesh:(BOOL)mesh group:(NSString *)group plain:(BOOL)plain;
- (BOOL)lensSeesBarWanted;
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

// Where a glass' backdrops, veil and overlay are cut: the rect on Core
// Animation's continuous corner. FIX133 cut a capsule's to the plain stadium
// drawn in by 1.36 % of its radius (inside iOS 26's outline nearly all
// round, the border covering the rest); FIX134 (user: "better, but toward
// the middle it still wants a few faint pixels") takes that back: along the
// whole straight middle and round the tips the face then ended a third of a
// point short of the outline, under the border. The backdrops can only be
// cut to a corner radius (a mask over them would cut them off from what lies
// behind), and of the shapes that offers Core Animation's own capsule is
// the nearest to iOS 26's: exact along the middle and at the tips, at most
// 0.9 % of the radius (0.2 pt on a 44 pt capsule) outside it near the round
// ends, where the border (drawn on iOS 26's outline itself) lies just inside.
static void WXGClipToGlass(UIView *clip,CGRect rect,CGFloat radius) {
    clip.frame=rect;clip.bounds=(CGRect){CGPointZero,rect.size};
    clip.layer.cornerCurve=kCACornerCurveContinuous;
    clip.layer.cornerRadius=MAX(0,radius);
}
@implementation WXGGlassView {
    CALayer *_dropShadow;NSString *_dropShadowKey;   // FIX114 K
    CALayer *_dropShadowMask;NSString *_dropShadowMaskKey;   // R20/R24: boolean alpha mask punching out overlapping sibling glasses so shadows never paint over nearby glass
    NSHashTable<UIView *> *_shadowClips;              // FIX114 L: ancestors opened for the shadow
    CGRect _shadowNeed;BOOL _shadowNeedValid;         // FIX114 M: what of the shadow shows (this view's coordinates)
    BOOL _shadowParked;                               // FIX114 M (review): hidden: its views let go until it shows
    WXGBackdropTone _backdropTone;   // FIX114 J: this glass's range's, for its backdrops (applyStack)
    BOOL _tickPending;
    CFTimeInterval _pendingTickTime;
    NSInteger _syncMode;
    CALayer *_veilFallback;
    __weak UIView *_materialGlow;
    NSUInteger _veilRevision,_veilReorders;
    NSString *_syncGroup,*_lensGroup;   // FIX113 U: the lens' own capture (it sees the bar)
    NSString *_lensRimGroup;   // FIX113 X: the lens' 取自背景 border samples what the lens shows
    WXGRim26View *_body26,*_lens26;   // FIX123: the iOS 26 rims (body, lens)
    CGFloat _lensPad;   // FIX113 U: the lens backdrop's margin (the page beyond the smaller bar's edge)
    CFTimeInterval _lensMovedAt;BOOL _lensSettlePending;NSUInteger _lensMeshKept;   // FIX114 A
    BOOL _lensSeesBarApplied;   // FIX113 U: as applySyncMode last set it (the overlay and the tap animation follow it)
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
        _inFlight=dispatch_semaphore_create(2); _toneLevel=.8; _barScale=1; _pool=[NSMutableArray array]; _selectionWeight=-1;_glassScopeOverride=-1;_rimScopeOverride=-1;_selectionOverridePressedAlpha=-1;
        WXGRegisterBackdropView(self);
        _gpu=WXGSharedDevice();
        if(!_gpu) { _failure=@"此设备没有可用 Metal device"; WXGLog(@"%@",_failure); return self; }
        _queue=WXGSharedQueue();
        _normalIcons=_selectedIcons=WXGTransparentTexture();_needsDraw=YES; _textureLoader=[[MTKTextureLoader alloc] initWithDevice:_gpu];
        // FIX114 K: the drop shadow, under everything this glass draws.
        _dropShadow=[CALayer layer];_dropShadow.hidden=YES;
        _dropShadow.actions=@{@"contents":NSNull.null,@"contentsCenter":NSNull.null,@"bounds":NSNull.null,@"position":NSNull.null,
                              @"opacity":NSNull.null,@"hidden":NSNull.null,@"contentsScale":NSNull.null};
        [self.layer insertSublayer:_dropShadow atIndex:0];
        _bodyClip=[[UIView alloc] initWithFrame:CGRectZero]; _lensClip=[[UIView alloc] initWithFrame:CGRectZero];
        for(UIView *clip in @[_bodyClip,_lensClip]) {
            clip.userInteractionEnabled=NO; clip.opaque=NO; clip.backgroundColor=UIColor.clearColor;
            clip.clipsToBounds=YES; clip.layer.cornerCurve=kCACornerCurveContinuous;
            [self addSubview:clip];
        }
        _metal=[self makeMetalView]; _lensMetal=[self makeMetalView];
        [_bodyClip addSubview:_metal]; [_lensClip addSubview:_lensMetal];
        _syncGroup=[NSString stringWithFormat:@"wxg.glass.%p",self];_lensGroup=[NSString stringWithFormat:@"wxg.glass.lens.%p",self];
        _lensRimGroup=[NSString stringWithFormat:@"wxg.glass.lensrim.%p",self];
        // Bottom to top inside the body clip: body R,G,B, edge-ring R,G,B, Metal.
        NSMutableArray *bodyStack=[NSMutableArray array],*edgeStack=[NSMutableArray array],*lensStack=[NSMutableArray array],*masks=[NSMutableArray array];
        for(int i=0;i<WXG_KYANT_SPECTRAL_TAPS;i++) {
            WXGSyncBackdropView *l=[[WXGSyncBackdropView alloc] initWithFrame:CGRectZero];
            l.hidden=YES;
            [lensStack addObject:l];
            if(i<3) {
                WXGSyncBackdropView *b=[[WXGSyncBackdropView alloc] initWithFrame:CGRectZero],*e=[[WXGSyncBackdropView alloc] initWithFrame:CGRectZero];
                b.hidden=e.hidden=YES;
                [bodyStack addObject:b];[edgeStack addObject:e];
                CALayer *mask=[CALayer layer];mask.contentsGravity=kCAGravityResize;[masks addObject:mask];
            }
        }
        _bodyStack=bodyStack;_edgeStack=edgeStack;_lensStack=lensStack;_edgeMasks=masks;
        for(WXGSyncBackdropView *v in _bodyStack)[_bodyClip insertSubview:v belowSubview:_metal];
        for(WXGSyncBackdropView *v in _edgeStack)[_bodyClip insertSubview:v belowSubview:_metal];
        // FIX35: the material veil as a plain render-server layer, shown until
        // the first Metal overlay frame (cold start: target material at once).
        _veilFallback=[CALayer layer];_veilFallback.hidden=YES;
        [_bodyClip.layer insertSublayer:_veilFallback below:_metal.layer];
        for(WXGSyncBackdropView *v in _lensStack)[_lensClip insertSubview:v belowSubview:_lensMetal];
        _lensTint=[CALayer layer];_lensTint.hidden=YES;[_lensClip.layer insertSublayer:_lensTint above:_lensMetal.layer];   // FIX112 E: a filter over the whole lens
        _bodyBackdrop=_bodyStack[0];_edgeBackdrop=_edgeStack[0];_lensBackdrop=_lensStack[0];_edgeMask=_edgeMasks[0];
        _bodyRim=[WXGRimView new]; _lensRim=[WXGRimView new];
        [self insertSubview:_bodyRim belowSubview:_lensClip]; [self addSubview:_lensRim];
        // FIX95 drew the lens on circular corners to match the shader; FIX96
        // keeps Core Animation's continuous ones (the tester: circular corners
        // look like Android) and the shader's capsule follows them instead
        // (WXGContinuousCorrection, measured on the tester's phone).
        // The iOS 26 rims: the body's above the iOS 27 one, the lens' under its.
        _body26=[[WXGRim26View alloc] initWithFrame:CGRectZero];[self insertSubview:_body26 aboveSubview:_bodyRim];
        _lens26=[[WXGRim26View alloc] initWithFrame:CGRectZero];[self insertSubview:_lens26 belowSubview:_lensRim];
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
- (BOOL)attachDockMaterialGlow:(UIView *)glow {
    if(!_bodyClip)return NO;
    // The lens backdrop samples this face, including its light. Keep the glow
    // above the material veil and below _metal so unselected icons stay crisp.
    _materialGlow=glow;
    glow.frame=_bodyClip.bounds;
    if(_metal && _metal.superview==_bodyClip)[_bodyClip insertSubview:glow belowSubview:_metal];
    else [_bodyClip addSubview:glow];
    return YES;
}
- (void)setLensRect:(CGRect)rect {
    if(CGRectEqualToRect(_lensRect,rect)) return;
    if(fabs(_lensRect.size.width-rect.size.width)>.01 || fabs(_lensRect.size.height-rect.size.height)>.01 ||
       fabs(_lensRect.origin.x-rect.origin.x)>.01)_lensMovedAt=CACurrentMediaTime();   // FIX114 A
    _lensRect=rect; [self setNeedsLayout];
}
- (void)setLensRestHeight:(CGFloat)height { if(fabs(_lensRestHeight-height)<.01) return; _lensRestHeight=height; [self setNeedsLayout]; }
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
- (void)setPressAmount:(CGFloat)amount { if(fabs(_pressAmount-amount)<.0001)return;_pressAmount=amount;_lensMovedAt=CACurrentMediaTime();_needsDraw=YES;[self setNeedsLayout]; }
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
- (WXGGlassScope)glassScope {
    if(_glassScopeOverride>=0)return (WXGGlassScope)_glassScopeOverride;   // FIX113 O
    return _dockSurface?WXGGlassScopeDock:_bubbleSurface?WXGGlassScopeBubble:WXGGlassScopeOther;
}
- (BOOL)pureDockBodyStyle {
    WXGGlassScope sc=self.glassScope;
    return _mainDockOptics && _dockSurface && (sc==WXGGlassScopeDock || sc==WXGGlassScopeSegment) &&
        !_shapeAnimating && !_deferShapeField && WXGConfig.shared.dockPureGlassMode;
}
- (WXGGlassScope)effectiveBodyScope {
    return self.glassScope;
}
- (WXGScopeOptics)scopedOptics {
    WXGGlassScope scope=[self effectiveBodyScope];
    WXGScopeOptics o=[WXGConfig.shared opticsForScope:scope];
    // The system's blur goes by the glass' short side, over its whole face (FIX124).
    o.blur=[WXGConfig.shared glassBlurForScope:scope side:MIN(_glassRect.size.width,_glassRect.size.height)];o.blurCoverage=100;
    return o;
}
// FIX115 S: whose border range it draws (its own glass range unless set: 视频号).
- (WXGGlassScope)rimScope {return _rimScopeOverride>=0?(WXGGlassScope)_rimScopeOverride:[self effectiveBodyScope];}
- (void)setRimScopeOverride:(NSInteger)scope {
    if(_rimScopeOverride==scope)return;
    _rimScopeOverride=scope;_needsDraw=YES;[self setNeedsLayout];
}
- (void)setGlassScopeOverride:(NSInteger)scope {
    if(_glassScopeOverride==scope)return;
    _glassScopeOverride=scope;_bodyMask=nil;_needsDraw=YES;[self setNeedsLayout];[self invalidateBackdrop];
}
// FIX113 O: whose lens this is (the segment bar's own, else the dock's), its
// parameters, and the rim offset cancelled (when the served shader knows it).
- (WXGGlassScope)lensScope {return self.glassScope==WXGGlassScopeSegment?WXGGlassScopeSegment:WXGGlassScopeDock;}
// FIX114 C (user: the segment bar's lens border set apart from the dock's
// icons-and-titles lens): the 边框与渐隐 range of this glass's lens border.
- (WXGGlassScope)lensRimScope {
    return self.glassScope==WXGGlassScopeSegment?WXGGlassScopeSegmentLens:WXGGlassScopeLens;
}
- (WXGLensSettings)lensSettings {return [WXGConfig.shared lensSettingsForScope:[self lensScope] dark:[self darkAppearance] || _rimAlwaysDark];}
- (void)setSelectionOverride:(UIColor *)color {
    if(color==_selectionOverride || [color isEqual:_selectionOverride])return;
    _selectionOverride=color;_needsDraw=YES;
}
- (void)setSelectionOverridePressedAlpha:(CGFloat)alpha {
    if(fabs(alpha-_selectionOverridePressedAlpha)<.0005)return;
    _selectionOverridePressedAlpha=alpha;_needsDraw=YES;
}
- (void)setBubbleSurface:(BOOL)bubble {
    if(_bubbleSurface==bubble)return;
    _bubbleSurface=bubble;_needsDraw=YES;[self setNeedsLayout];[self invalidateBackdrop];
}
- (void)setVeilOverride:(UIColor *)color {
    if(color==_veilOverride || [color isEqual:_veilOverride])return;
    _veilOverride=color;_needsDraw=YES;[self setNeedsLayout];
}
- (NSString *)backdropGroupName {return WXGEffectiveRenderMode()>=2 && _bodyStack.count?[self bodyGroup]:nil;}
/* FIX119 B: a chat's bubbles (lightweight glass, one backdrop each) share one
   capture of what is behind them (the backdrop layers' groupName): the render
   server copies the screen once for all of them instead of once per bubble
   (fps_20261105_161128, XS Max chat: 11 bubbles, 23 backdrop layers, the
   screen missing far more frames than the main thread). Bubbles never lie
   over one another, so each still sees only what is behind it. Off
   (气泡共用一次背景采样): one capture per bubble, as before. */
- (NSString *)bodyGroup {
    if(_bubbleSurface && _lightweight && [WXGConfig.shared extraNumber:@"bubbleSharedBackdrop"]>.5)return @"wxg.glass.bubbles";
    return _syncGroup;
}
// FIX113 U (user: the lens should just refract what is under it, the bar's
// border included, not draw the bar again): the lens' backdrop captures what
// lies beneath it in its own group (page, the bar's blurred backdrop, veil,
// rim and icons) and its mesh refracts all of it alike.
// Only with the mesh refraction on: without it the lens would show an
// unbent copy (the shader no longer bends a bar of its own then).
- (BOOL)lensSeesBarWanted {
#ifdef WXG_MESH_OFF
    return NO;
#else
    WXGConfig *c=WXGConfig.shared;
    return c.syncMeshRefraction && WXGMeshTransformClass() && _lensStack.count && _lensStack[0].live;
#endif
}
- (BOOL)lensSeesBar {return _lensSeesBarApplied;}
- (BOOL)pureDockActive {
    return WXGShaderKyantOptics && [self pureDockBodyStyle] && WXGEffectiveRenderMode()>=2 && [self lensSeesBarWanted];
}
- (BOOL)kyantOpticsActive {
    if([self pureDockBodyStyle])return NO;
    return WXGShaderKyantOptics && _mainDockOptics && _dockSurface && self.glassScope==WXGGlassScopeDock &&
        !_shapeAnimating && !_deferShapeField && WXGEffectiveRenderMode()>=2 && [self lensSeesBarWanted] &&
        [WXGConfig.shared extraNumber:@"dockKyantOptics"]>.5;
}
- (WXGRimStyle)effectiveLensRimStyle {
    return [WXGConfig.shared rimStyleForScope:[self lensRimScope]];
}
- (UIColor *)veilColor {return _veilFallback.backgroundColor?[UIColor colorWithCGColor:_veilFallback.backgroundColor]:nil;}
- (NSArray<UIColor *> *)lensOutlineColors {return _lensOutlineColors?:@[];}
- (NSArray<NSNumber *> *)lensOutlineWidths {return _lensOutlineWidths?:@[];}
- (void)setRimAlwaysDark:(BOOL)always {
    if(_rimAlwaysDark==always)return;
    _rimAlwaysDark=always;_needsDraw=YES;[self setNeedsLayout];
}
- (BOOL)darkAppearance {return self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;}
- (void)setDropShadowOff:(BOOL)off {if(_dropShadowOff==off)return;_dropShadowOff=off;[self setNeedsLayout];}
// FIX114 K: the range's drop shadow (WXGDropShadow.h): one image of the
// resting shape (shared by every glass of that size and setting), its
// straight sides stretched in the middle (contentsCenter), following the
// drawn shape (a press grows it; transforms of this view carry it along).
static id WXGDropShadowImage(NSString *key,WXGShadowPlan plan,CGFloat scale,CGFloat radius,WXGDropShadowSettings s,int *pw,int *ph) {
    static NSCache *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=48;});
    WXGShadowPixels(plan,(float)scale,pw,ph);
    id cached=[cache objectForKey:key];
    if(cached)return cached;
    if(*pw<2 || *ph<2 || *pw>2048 || *ph>2048)return nil;
    float *alpha=malloc(sizeof(float)*(size_t)(*pw)*(size_t)(*ph)),*scratch=malloc(sizeof(float)*WXGShadowScratchFloats(*pw,*ph));
    CGImageRef image=NULL;
    if(alpha && scratch) {
        WXGShadowRender(alpha,*pw,*ph,(float)scale,plan,(float)radius,(float)s.blur,(float)s.offset,(float)s.spread,scratch);
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx=CGBitmapContextCreate(NULL,(size_t)*pw,(size_t)*ph,8,(size_t)*pw*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        if(ctx) {
            uint8_t *bytes=CGBitmapContextGetData(ctx);size_t stride=CGBitmapContextGetBytesPerRow(ctx);
            for(int j=0;j<*ph;j++)for(int i=0;i<*pw;i++) {
                uint8_t *px=bytes+(size_t)j*stride+(size_t)i*4;
                px[0]=px[1]=px[2]=0;px[3]=(uint8_t)lroundf(WXGShadowClampf(alpha[j*(*pw)+i],0.f,1.f)*255.f);   /* black, premultiplied */
            }
            image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);
        }
    }
    free(alpha);free(scratch);
    id object=image?(__bridge_transfer id)image:nil;
    if(object)[cache setObject:object forKey:key];
    return object;
}
/* FIX114 L (user: on the settings page's search field, the home title and
   the chat's back button the shadow ended in a straight edge): WeChat's bar
   and header views around the glass clip to their bounds. The ones between
   this glass and the page (bar-sized: under 220 pt high; never a scroll view,
   the window, an empty one) that cut what the shadow shows (its extent past
   2.5 sigma is invisible) are opened, restorably (one bag for every glass;
   a view closes again when no glass needs it: the glass left the window, its
   shadow went off or no longer reaches the edge). A list or page clipping it
   is left alone: content scrolling under a bar is cut there anyway. */
/* FIX114 M (user: on entering the settings page the shadows are whole; the
   moment any row is tapped and the next page pushed in they are cut again,
   still cut after coming back, whole again only when the page is opened
   anew; the same at the search fields and the chat's back button): L opened
   the clipping views when the glass was laid out, and only then. The views
   were clipped again afterwards while the glass was not laid out: WeChat's
   own layout of the bar, UIKit's push, or one of the plugin's other bags
   giving back a clip it had opened itself (the local glass behind a search
   field restores its bag when the field is laid out empty for a moment); L
   took a view that did not clip at that moment as one that never does.
   Now:
   - the views opened for a shadow are this file's own list, with what each
     was before; anyone setting one of them to clip again (a setter hook on
     CALayer.masksToBounds, main thread only) changes what it goes back to
     and it stays open;
   - before every commit (a run-loop observer just ahead of Core Animation's)
     the glasses with a shadow check their ancestors again when something
     clipped anywhere or a glass moved, and every 0.2 s regardless;
   - a page that leaves the window (pushed under, its window hidden) keeps
     its views open (nothing shows there; coming back is whole at once); only
     a glass taken out of those views gives them back. */
static NSMapTable<UIView *,NSHashTable *> *WXGShadowClipHolders;   // view -> the glasses that need it open
static NSMapTable<UIView *,NSNumber *> *WXGShadowClipOriginal;    // view -> whether it clips without them
static NSHashTable<CALayer *> *WXGShadowHeldLayers;               // their layers (the setter's quick test)
static NSHashTable<WXGGlassView *> *WXGShadowGlasses;             // glasses whose shadow shows
static NSHashTable<WXGGlassView *> *WXGAllLiveGlasses;            // R20: all mounted glasses (for shadow-under-glass cutouts)
static NSUInteger WXGShadowClipsOpened,WXGShadowReclips,WXGShadowRechecks;
static BOOL WXGShadowRecheckWanted,WXGShadowWriting;
static CFTimeInterval WXGShadowLastRecheck;
static void WXGShadowObserve(void);
static void (*WXGShadowSetMasksOriginal)(id,SEL,BOOL);
static void WXGShadowSetMasks(CALayer *layer,SEL cmd,BOOL masks) {
    if(!pthread_main_np() || WXGShadowWriting || ![WXGShadowHeldLayers containsObject:layer]) {
        WXGShadowSetMasksOriginal(layer,cmd,masks);
        if(masks && pthread_main_np() && WXGShadowGlasses.count)WXGShadowRecheckWanted=YES;
        return;
    }
    // A view a shadow holds open: what is set now is what it goes back to.
    UIView *view=(UIView *)layer.delegate;
    if([view isKindOfClass:UIView.class] && [WXGShadowClipHolders objectForKey:view])[WXGShadowClipOriginal setObject:@(masks) forKey:view];
    if(masks){++WXGShadowReclips;return;}
    WXGShadowSetMasksOriginal(layer,cmd,masks);
}
static void WXGShadowInstall(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        WXGShadowClipHolders=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
        WXGShadowClipOriginal=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
        WXGShadowHeldLayers=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];
        WXGShadowGlasses=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];
        WXGAllLiveGlasses=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];
        __block BOOL shadowsEnabled=WXGConfig.shared.glassShadowOn;
        [NSNotificationCenter.defaultCenter addObserverForName:WXGSettingsChanged object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) {
                BOOL enabled=WXGConfig.shared.glassShadowOn;
                if(enabled==shadowsEnabled)return;
                shadowsEnabled=enabled;
                for(WXGGlassView *glass in WXGAllLiveGlasses.allObjects)[glass setNeedsLayout];
            }];
        Method m=class_getInstanceMethod(CALayer.class,@selector(setMasksToBounds:));
        // The original is kept before the swap (another thread may set a layer meanwhile).
        if(m){WXGShadowSetMasksOriginal=(void (*)(id,SEL,BOOL))method_getImplementation(m);method_setImplementation(m,(IMP)WXGShadowSetMasks);}
    });
    WXGShadowObserve();
}
static void WXGShadowWrite(UIView *v,BOOL clips) {
    if(v.clipsToBounds==clips)return;
    WXGShadowWriting=YES;v.clipsToBounds=clips;WXGShadowWriting=NO;
}
static void WXGShadowHold(UIView *v,id glass) {   // FIX115 K: any holder (a glass; a title-bar glass's entry)
    NSHashTable *holders=[WXGShadowClipHolders objectForKey:v];
    if(!holders) {
        holders=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];
        [WXGShadowClipHolders setObject:holders forKey:v];[WXGShadowClipOriginal setObject:@(v.clipsToBounds) forKey:v];
        [WXGShadowHeldLayers addObject:v.layer];++WXGShadowClipsOpened;
    }
    [holders addObject:glass];WXGShadowWrite(v,NO);
}
// Views no glass needs any more go back to what they were (or were set to since).
static void WXGShadowClipSweep(void) {
    for(UIView *v in WXGShadowClipHolders.keyEnumerator.allObjects) {
        NSHashTable *holders=[WXGShadowClipHolders objectForKey:v];
        if(holders.allObjects.count)continue;
        BOOL clips=[[WXGShadowClipOriginal objectForKey:v] boolValue];
        [WXGShadowHeldLayers removeObject:v.layer];[WXGShadowClipHolders removeObjectForKey:v];[WXGShadowClipOriginal removeObjectForKey:v];
        WXGShadowWrite(v,clips);
    }
}
/* FIX115 K: a title-bar glass's containers held open the same way as a
   shadow's (WXGLocalGlass openClipsAbove:): one count of holders and the
   view's own value per view, whoever opened it first and whoever lets go
   last; what WeChat sets meanwhile is what it goes back to. A holder is kept
   weakly: one that goes away lets go by itself (the periodic sweep). */
void WXGHoldClipOpen(UIView *v,id holder) {
    if(!v || !holder || !pthread_main_np())return;
    WXGShadowInstall();WXGShadowHold(v,holder);
}
void WXGReleaseClipHolds(id holder) {
    if(!holder || !WXGShadowClipHolders || !pthread_main_np())return;
    BOOL any=NO;
    for(UIView *v in WXGShadowClipHolders.keyEnumerator.allObjects) {
        NSHashTable *holders=[WXGShadowClipHolders objectForKey:v];
        if([holders containsObject:holder]){[holders removeObject:holder];any=YES;}
    }
    if(any)WXGShadowClipSweep();
}
- (void)releaseShadowClips {
    [WXGShadowGlasses removeObject:self];_shadowNeedValid=NO;
    _dropShadow.mask=nil;_dropShadowMaskKey=nil;
    if(!_shadowClips.count)return;
    for(UIView *v in _shadowClips.allObjects)[[WXGShadowClipHolders objectForKey:v] removeObject:self];
    [_shadowClips removeAllObjects];
    WXGShadowClipSweep();
}
// The views this glass holds that it is no longer inside (taken out of them).
- (void)dropShadowClipsNotAbove {
    BOOL dropped=NO;
    for(UIView *v in _shadowClips.allObjects)if(![self isDescendantOfView:v]){[[WXGShadowClipHolders objectForKey:v] removeObject:self];[_shadowClips removeObject:v];dropped=YES;}
    if(dropped)WXGShadowClipSweep();
}
- (void)openShadowClipsFor:(CGRect)need {
    WXGShadowInstall();
    _shadowNeed=need;_shadowNeedValid=YES;[WXGShadowGlasses addObject:self];
    [self holdShadowClips];
}
// FIX114 M (review): another bag of the plugin's opening a view a shadow holds
// open (WXGStateBag allowOverflow:, e.g. the local glass behind a search field
// mounting again) is given the view's own value (the shadow's record, not the
// opened NO it would see); the shadow then counts it as open by someone else
// (lets it go, leaves it open: that bag gives it back itself).
BOOL WXGShadowAdoptOverflow(UIView *v,BOOL *clipsWithout) {
    if(!v || !pthread_main_np() || ![WXGShadowClipHolders objectForKey:v])return NO;
    if(clipsWithout)*clipsWithout=[[WXGShadowClipOriginal objectForKey:v] boolValue];
    [WXGShadowClipOriginal setObject:@NO forKey:v];
    WXGShadowRecheckWanted=YES;
    return YES;
}
// FIX114 M (review): a glass hidden (or faded out) where it is, by itself or
// a view above it: no shadow shows, the views it holds are let go (parked; it
// takes them again when it shows: looked at every turn while parked).
static BOOL WXGShadowGlassShown(UIView *glass) {
    UIWindow *w=glass.window;if(!w)return NO;
    for(UIView *v=glass;v && v!=w;v=v.superview)if(v.hidden || v.alpha<.01)return NO;
    return YES;
}
// FIX115 B: a menu fading in or out (its alpha) keeps its views open.
static BOOL WXGShadowGlassShownIgnoringAlpha(UIView *glass) {
    UIWindow *w=glass.window;if(!w)return NO;
    for(UIView *v=glass;v && v!=w;v=v.superview)if(v.hidden)return NO;
    return YES;
}
- (BOOL)shadowParkedNowShown {
    UIView *root=_shadowClipRoot;
    return _shadowParked && (root && [self isDescendantOfView:root]?WXGShadowGlassShownIgnoringAlpha(self):WXGShadowGlassShown(self));
}
- (void)holdShadowClips {
    if(!_shadowNeedValid)return;
    if(!self.window){[self dropShadowClipsNotAbove];return;}
    // FIX114 Y (user, 01:25: the message long-press menu and the home "+" menu
    // showed grey squares at their corners again, since FIX114 L/M): a glass
    // that keeps the clips above it opens none (and gives back any it held).
    UIView *root=_shadowClipRoot;
    if(root && ![self isDescendantOfView:root])root=nil;   // FIX115 B: only while inside it
    if(_keepsAncestorClips && !root) {
        if(_shadowClips.count){for(UIView *v in _shadowClips.allObjects)[[WXGShadowClipHolders objectForKey:v] removeObject:self];[_shadowClips removeAllObjects];WXGShadowClipSweep();}
        return;
    }
    if(root?!WXGShadowGlassShownIgnoringAlpha(self):!WXGShadowGlassShown(self)) {
        _shadowParked=YES;
        if(_shadowClips.count) {
            for(UIView *v in _shadowClips.allObjects)[[WXGShadowClipHolders objectForKey:v] removeObject:self];
            [_shadowClips removeAllObjects];WXGShadowClipSweep();
        }
        return;
    }
    _shadowParked=NO;
    CGRect need=_shadowNeed;
    NSHashTable<UIView *> *now=[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality];NSUInteger depth=0;
    for(UIView *v=self.superview;v && depth<10;v=v.superview,depth++) {
        if(root) {
            // FIX115 B: up to the root, whatever their size; the plugin's own views never stop it.
            if([v isKindOfClass:UIWindow.class])break;
            BOOL past=NO;for(UIView *u=self.superview;u!=v;u=u.superview)if(u==root){past=YES;break;}
            if(past)break;
        }else if([v isKindOfClass:UIScrollView.class] || [v isKindOfClass:UIWindow.class] || v.bounds.size.height>220)break;
        // A view held open clips without the shadow if it did, or was set to since.
        BOOL clips=v.clipsToBounds || [[WXGShadowClipOriginal objectForKey:v] boolValue];
        if(!clips || v.bounds.size.width<1 || v.bounds.size.height<1)continue;
        CGRect r=[self convertRect:need toView:v];
        if(CGRectContainsRect(CGRectInset(v.bounds,-.5,-.5),r))continue;
        [now addObject:v];
    }
    BOOL dropped=NO;
    for(UIView *v in _shadowClips.allObjects)if(![now containsObject:v]){[[WXGShadowClipHolders objectForKey:v] removeObject:self];dropped=YES;}
    for(UIView *v in now.allObjects)WXGShadowHold(v,self);
    _shadowClips=now;
    if(dropped)WXGShadowClipSweep();
}
static UIViewController *WXGShadowOwner(UIView *view) {
    for(UIResponder *r=view;r && ![r isKindOfClass:UIWindow.class];r=r.nextResponder)
        if([r isKindOfClass:UIViewController.class])return (UIViewController *)r;
    return nil;
}
// Presented controllers have a separate containment tree even for over-full-screen
// and page sheets, where the entire presenter can stay mounted in the same window.
static UIViewController *WXGShadowPageRoot(WXGGlassView *glass) {
    UIWindow *window=glass.window;
    UIViewController *owner=WXGShadowOwner(glass);
    if((!owner || owner==window.rootViewController) && glass.sourceView.window==window)
        owner=WXGShadowOwner(glass.sourceView)?:owner;
    for(UIViewController *c=owner?:window.rootViewController;c;c=c.parentViewController) {
        UIViewController *p=c.parentViewController;
        if(!p)return c;
        if([p isKindOfClass:UINavigationController.class]) {
            UIViewController *top=((UINavigationController *)p).topViewController;
            if(top && top!=c)return nil;
        }else if([p isKindOfClass:UITabBarController.class]) {
            UIViewController *sel=((UITabBarController *)p).selectedViewController;
            if(sel && sel!=c)return nil;
        }
    }
    return nil;
}
// R20/R24: keep every glass's drop shadow strictly below any nearby/lower glass in
// visual priority by punching out overlapping visible glass silhouettes via a true
// boolean alpha mask (kCGBlendModeClear). Never use kCAFillRuleEvenOdd, which
// inverts the intersection of two overlapping holes back into an opaque shadow.
- (void)updateShadowCutout {
    UIWindow *w=self.window;
    if(_dropShadow.hidden || !w || !WXGAllLiveGlasses.count || CGRectIsEmpty(_dropShadow.bounds)) {
        if(_dropShadow.mask){_dropShadow.mask=nil;_dropShadowMaskKey=nil;}
        return;
    }
    CGRect shadowWin=[self.layer convertRect:_dropShadow.frame toLayer:w.layer];
    UIViewController *pageRoot=WXGShadowPageRoot(self);
    if(CGRectIsEmpty(shadowWin) || !pageRoot){if(_dropShadow.mask){_dropShadow.mask=nil;_dropShadowMaskKey=nil;}return;}
    typedef struct { CGRect rect; CGFloat radius; } WXGShadowHole;
    WXGShadowHole holes[16];NSUInteger holeCount=0;
    NSMutableString *key=nil;
    for(WXGGlassView *other in WXGAllLiveGlasses.allObjects) {
        if(holeCount>=16)break;
        if(other==self || other.window!=w || !WXGShadowGlassShown(other))continue;
        CGRect otherLocal=[other drawnBarRect];
        if(otherLocal.size.width<2 || otherLocal.size.height<2)continue;
        CGRect otherWin=[other convertRect:otherLocal toView:w];
        if(!CGRectIntersectsRect(otherWin,w.bounds) || !CGRectIntersectsRect(shadowWin,otherWin))continue;
        if(WXGShadowPageRoot(other)!=pageRoot)continue;
        CGRect hole=[w.layer convertRect:otherWin toLayer:_dropShadow];
        if(CGRectIsEmpty(hole))continue;
        CGFloat rad=MIN([other radiusForRect:otherLocal scale:other.barScale],MIN(hole.size.width,hole.size.height)*.5);
        if(!key)key=[NSMutableString stringWithFormat:@"%.0fx%.0f",round(_dropShadow.bounds.size.width),round(_dropShadow.bounds.size.height)];
        holes[holeCount++]=(WXGShadowHole){hole,MAX(0.,rad)};
        [key appendFormat:@"|%.0f,%.0f,%.0f,%.0f,%.0f",round(hole.origin.x),round(hole.origin.y),round(hole.size.width),round(hole.size.height),round(rad)];
    }
    if(!holeCount) {
        if(_dropShadow.mask){_dropShadow.mask=nil;_dropShadowMaskKey=nil;}
        return;
    }
    if(!_dropShadowMask) {
        _dropShadowMask=[CALayer layer];
        _dropShadowMask.actions=@{@"contents":NSNull.null,@"bounds":NSNull.null,@"position":NSNull.null,@"contentsScale":NSNull.null};
    }
    if(![key isEqualToString:_dropShadowMaskKey]) {
        CGSize sz=_dropShadow.bounds.size;
        CGFloat scale=2.;
        if(sz.width*scale>1024. || sz.height*scale>1024.)scale=1.;
        size_t pw=(size_t)MAX(1.,ceil(sz.width*scale)),ph=(size_t)MAX(1.,ceil(sz.height*scale));
        CGContextRef ctx=CGBitmapContextCreate(NULL,pw,ph,8,pw,NULL,(CGBitmapInfo)kCGImageAlphaOnly);
        if(ctx) {
            CGContextTranslateCTM(ctx,0,(CGFloat)ph);
            CGContextScaleCTM(ctx,scale,-scale);
            CGContextSetAlpha(ctx,1.);
            CGContextFillRect(ctx,CGRectMake(0,0,sz.width,sz.height));
            CGContextSetBlendMode(ctx,kCGBlendModeClear);
            for(NSUInteger i=0;i<holeCount;i++) {
                CGRect hr=CGRectStandardize(holes[i].rect);
                if(hr.size.width<.5 || hr.size.height<.5)continue;
                CGFloat r=WXGClamp(holes[i].radius,0.,MIN(hr.size.width,hr.size.height)*.5);
                if(r>=.5) {
                    CGPathRef rp=CGPathCreateWithRoundedRect(hr,r,r,NULL);
                    CGContextAddPath(ctx,rp);CGContextFillPath(ctx);CGPathRelease(rp);
                }else {
                    CGContextFillRect(ctx,hr);
                }
            }
            CGImageRef img=CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            if(img) {
                _dropShadowMask.frame=_dropShadow.bounds;
                _dropShadowMask.contentsScale=scale;
                _dropShadowMask.contents=(__bridge id)img;
                CGImageRelease(img);
                _dropShadowMaskKey=key;
            }
        }
    }
    if(_dropShadow.mask!=_dropShadowMask)_dropShadow.mask=_dropShadowMask;
}
// Before Core Animation's commit (its observer runs at 2000000).
static void WXGShadowObserve(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        CFRunLoopObserverRef o=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999800,
            ^(__unused CFRunLoopObserverRef observer,__unused CFRunLoopActivity activity){
                if(!WXGShadowGlasses.count && !WXGShadowClipHolders.count)return;
                CFTimeInterval now=CACurrentMediaTime();
                BOOL periodic=now-WXGShadowLastRecheck>.2;
                if(!WXGShadowRecheckWanted && !periodic)
                    for(WXGGlassView *glass in WXGShadowGlasses.allObjects)if([glass shadowParkedNowShown]){WXGShadowRecheckWanted=YES;break;}
                if(!WXGShadowRecheckWanted && !periodic)return;
                WXGShadowRecheckWanted=NO;if(periodic)WXGShadowLastRecheck=now;++WXGShadowRechecks;
                for(WXGGlassView *glass in WXGShadowGlasses.allObjects){[glass holdShadowClips];[glass updateShadowCutout];}
                if(periodic)WXGShadowClipSweep();   // glasses gone without a word (their weak entries)
            });
        if(o){CFRunLoopAddObserver(CFRunLoopGetMain(),o,kCFRunLoopCommonModes);CFRelease(o);}
    });
}
// FIX114 M (diagnostics, exported from any page): the views held open now
// and the glasses whose shadow shows.
NSDictionary *WXGDropShadowEvidence(void) {
    NSMutableArray *held=[NSMutableArray array];
    for(UIView *v in WXGShadowClipHolders.keyEnumerator.allObjects) {
        if(held.count>=16)break;
        NSHashTable *holders=[WXGShadowClipHolders objectForKey:v];
        [held addObject:@{@"class":NSStringFromClass(v.class)?:@"?",@"clipsWithout":[WXGShadowClipOriginal objectForKey:v]?:@NO,
                          @"clipsNow":@(v.clipsToBounds),@"inWindow":@(v.window!=nil),@"glasses":@(holders.allObjects.count),
                          @"size":@[@(round(v.bounds.size.width)),@(round(v.bounds.size.height))]}];
    }
    NSUInteger shown=0,inWindow=0;
    for(WXGGlassView *g in WXGShadowGlasses.allObjects){++shown;if(g.window)++inWindow;}
    return @{@"held":held,@"glassesWithShadow":@(shown),@"inWindow":@(inWindow),@"openedEver":@(WXGShadowClipsOpened),
             @"reclipsKeptOpen":@(WXGShadowReclips),@"rechecks":@(WXGShadowRechecks),@"setterHooked":@(WXGShadowSetMasksOriginal!=NULL)};
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    WXGShadowRecheckWanted=YES;
    // FIX114 M: leaving the window keeps the views open (see above).
    if(!self.window){[WXGAllLiveGlasses removeObject:self];[self dropShadowClipsNotAbove];return;}
    WXGShadowInstall();[WXGAllLiveGlasses addObject:self];
    [self setNeedsLayout];
}
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if(_shadowClips.count)[self dropShadowClipsNotAbove];   // FIX114 M: moved out of the views it holds
    WXGShadowRecheckWanted=YES;
}
- (void)layoutDropShadow:(CGRect)drawn {
    WXGDropShadowSettings s=[WXGConfig.shared dropShadowForScope:[self effectiveBodyScope] dark:[self darkAppearance]];
    CGSize rest=_glassRect.size;
    if(_dropShadowOff || !(s.opacity>.002) || rest.width<2 || rest.height<2 || drawn.size.width<1 || drawn.size.height<1) {
        if(!_dropShadow.hidden)_dropShadow.hidden=YES;
        [self releaseShadowClips];
        return;
    }
    CGFloat radius=[self radiusForRect:(CGRect){CGPointZero,rest} scale:1];
    WXGShadowPlan plan=WXGShadowPlanFor((float)rest.width,(float)rest.height,(float)radius,(float)s.blur,(float)s.offset,(float)s.spread);
    CGFloat scale=s.blur<6?2:1;   /* a soft shadow needs few pixels; its cut-out edge stays at 1 px */
    NSString *key=[NSString stringWithFormat:@"%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.0f",plan.shapeW,plan.shapeH,radius,s.blur,s.offset,s.spread,scale];
    int pw=0,ph=0;id image=WXGDropShadowImage(key,plan,scale,radius,s,&pw,&ph);
    if(!image){_dropShadow.hidden=YES;[self releaseShadowClips];return;}
    if(![key isEqualToString:_dropShadowKey]) {
        _dropShadow.contents=image;_dropShadow.contentsScale=scale;_dropShadowKey=key;
    }
    CGFloat iw=pw/scale,ih=ph/scale,m=plan.margin;
    CGRect frame,center=CGRectMake(0,0,1,1);
    if(plan.stretchX) {
        frame.origin.x=drawn.origin.x-m;frame.size.width=iw+(drawn.size.width-plan.shapeW);
        center.origin.x=(floor((m+plan.shapeW*.5)*scale))/pw;center.size.width=1./pw;
    }else {
        CGFloat k=drawn.size.width/rest.width;frame.origin.x=drawn.origin.x-m*k;frame.size.width=iw*k;
    }
    if(plan.stretchY) {
        frame.origin.y=drawn.origin.y-m;frame.size.height=ih+(drawn.size.height-plan.shapeH);
        center.origin.y=(floor((m+plan.shapeH*.5)*scale))/ph;center.size.height=1./ph;
    }else {
        CGFloat k=drawn.size.height/rest.height;frame.origin.y=drawn.origin.y-m*k;frame.size.height=ih*k;
    }
    _dropShadow.frame=frame;_dropShadow.contentsCenter=center;
    _dropShadow.opacity=(float)s.opacity;
    if(_dropShadow.hidden)_dropShadow.hidden=NO;
    // FIX114 L: what of it shows (2.5 sigma past the grown shape, moved down).
    CGFloat reach=2.5*s.blur+MAX(0,s.spread);
    [self openShadowClipsFor:CGRectMake(drawn.origin.x-reach,drawn.origin.y-reach+s.offset,drawn.size.width+2*reach,drawn.size.height+2*reach)];
    [self updateShadowCutout];
}
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
    WXGClipToGlass(_bodyClip,drawnBar,[self radiusForRect:drawnBar scale:_barScale]);
    WXGClipToGlass(_lensClip,_lensRect,[self radiusForRect:_lensRect scale:_lensRect.size.height/MAX(1,_glassRect.size.height)]);   // FIX133
    _lensClip.hidden=_lensSuppressed;
    [self layoutDropShadow:drawnBar];   // FIX114 K
    {
        [CATransaction begin];[CATransaction setDisableActions:YES];   // a standalone layer: no implicit animations
        WXGConfig *v=WXGConfig.shared;BOOL darkVeil=[self darkAppearance];
        WXGGlassScope materialScope=[self effectiveBodyScope];   // FIX113 O: by range (R11 pureDock -> 其余玻璃)
        UIColor *veil=WXGColor([v materialHexForScope:materialScope dark:darkVeil]);
        CGFloat veilAlpha=[v materialOpacityForScope:materialScope dark:darkVeil];
        _veilFallback.frame=_bodyClip.bounds;
        // The same veil the shader draws (its "clear material" input is always 1: the opacity as set).
        CGFloat veilStrength=WXGClamp(CGColorGetAlpha(veil.CGColor)*veilAlpha,0,1);
        if(_veilOverride){veil=_veilOverride;veilStrength=WXGClamp(CGColorGetAlpha(veil.CGColor),0,1);}   // FIX82
        _veilFallback.backgroundColor=[veil colorWithAlphaComponent:veilStrength].CGColor;
        // FIX40: in render-server mode this layer IS the body veil, always
        // (the Metal body pass no longer draws one): identical at cold start,
        // before/after the first Metal frame and during the tap animation.
        _veilFallback.hidden=WXGEffectiveRenderMode()<2;
        // FIX42: the veil must sit right below the Metal overlay, above every
        // blur layer (an opaque backdrop above it would hide it completely).
        NSArray<CALayer *> *order=_bodyClip.layer.sublayers;
        CALayer *above=(_materialGlow && _materialGlow.superview==_bodyClip)?_materialGlow.layer:_metal.layer;
        NSUInteger veilAt=[order indexOfObjectIdenticalTo:_veilFallback],aboveAt=[order indexOfObjectIdenticalTo:above];
        if(aboveAt!=NSNotFound && veilAt+1!=aboveAt){[_bodyClip.layer insertSublayer:_veilFallback below:above];++_veilReorders;}
        [CATransaction commit];
    }
    // The borders (FIX130: two styles, each range its own): iOS 26's, a
    // highlight over the glass coloured by what lies under it (its own
    // layers: WXGRim26View), or iOS 27's, two highlights fading inward from
    // the outline (the rim view's glows). The lens' border is its own range
    // (the dock's lens and the segment bar's), shown as the lens lifts (the
    // segment pill's at rest too).
    BOOL dark=[self darkAppearance];
    // The rim's settings of this appearance, or always the dark ones (视频号's buttons over video).
    BOOL rimDark=dark || _rimAlwaysDark;
    WXGGlassScope scope=[self effectiveBodyScope],rimScope=[self rimScope];   // FIX115 S: the border of its own range (视频号)
    WXGLensSettings L=[self lensSettings];   // FIX113 O: the lens's own (the segment bar's or the dock's)
    _bodyRim.frame=drawnBar; _lensRim.frame=_lensRect;
    _lensRim.hidden=_lensSuppressed;
    _bodyRim.maximumCornerRadius=_maximumCornerRadius*_barScale;
    _lensRim.maximumCornerRadius=_maximumCornerRadius*_lensRect.size.height/MAX(1,_glassRect.size.height);
    [_bodyRim setNeedsLayout];[_lensRim setNeedsLayout];
    BOOL glow=[c rimStyleForScope:rimScope]==WXGRimStyleGlow,rim26=!glow;
    WXGRimGlowShape shapes[WXGRimGlowCount];
    for(NSInteger i=0;i<WXGRimGlowCount;i++)shapes[i]=[c rimGlowForScope:rimScope index:i dark:rimDark];
    [_bodyRim configureGlows:glow?shapes:NULL count:glow?WXGRimGlowCount:0];
    CGFloat lensLift=MAX(WXGPressedBorderAlpha(_pressAmount),[self pureDockBodyStyle]?0:L.rimAtRest);
    WXGGlassScope rimLens=[self lensRimScope];   // FIX114 C: 底栏透镜 / 分组透镜
    BOOL lensGlow=[self effectiveLensRimStyle]==WXGRimStyleGlow;
    {
        WXGRimGlowShape lensGlows[WXGRimGlowCount];
        for(NSInteger i=0;i<WXGRimGlowCount;i++){lensGlows[i]=[c rimGlowForScope:rimLens index:i dark:rimDark];lensGlows[i].alpha*=lensLift;}
        [_lensRim configureGlows:lensGlow?lensGlows:NULL count:lensGlow?WXGRimGlowCount:0];
    }
    // FIX112 E: the lens' filter colour (dock), only when switched on: over
    // the whole lifted lens, icons included (a filter), as it lifts. Off, the
    // lens shows what is under it exactly as before (no layer at all).
    {
        UIColor *tint=nil;CGFloat tintAlpha=0;
        if(_dockSurface && !_lensSuppressed && ![self pureDockBodyStyle] && L.tintOn) {
            tint=WXGColor([c lensTintHexForScope:[self lensScope] dark:dark]);
            tintAlpha=WXGClamp(CGColorGetAlpha(tint.CGColor)*L.tintOpacity*WXGClamp(_pressAmount/.90,0,1),0,1);
        }
        _lensTint.frame=_lensClip.bounds;
        _lensTint.hidden=tintAlpha<=.001;
        _lensTint.backgroundColor=_lensTint.hidden?nil:[tint colorWithAlphaComponent:tintAlpha].CGColor;
        CALayer *metalLayer=_lensMetal.layer;NSArray<CALayer *> *order=_lensClip.layer.sublayers;
        NSUInteger tintAt=[order indexOfObjectIdenticalTo:_lensTint],metalAt=[order indexOfObjectIdenticalTo:metalLayer];
        if(metalAt!=NSNotFound && tintAt!=metalAt+1)[_lensClip.layer insertSublayer:_lensTint above:metalLayer];
    }
    // FIX123: the iOS 26 rim: the colour of what lies under it (its own
    // low-resolution copy), or the veil for glass with no backdrop of its own.
    {
        BOOL live=WXGEffectiveRenderMode()>=2 && !_lightweight;   // each rim its own low-resolution copy
        UIColor *veil=live?nil:(_veilOverride?:WXGColor([c materialHexForScope:scope dark:dark]));
        _body26.frame=drawnBar;_body26.maximumCornerRadius=_bodyRim.maximumCornerRadius;
        [_body26 configureOn:rim26 settings:[c rim26ForScope:rimScope dark:rimDark] solid:veil strength:1];
        BOOL lens26=!lensGlow && !_lensSuppressed && !CGRectIsEmpty(_lensRect);
        _lens26.frame=_lensRect;_lens26.maximumCornerRadius=_maximumCornerRadius*_lensRect.size.height/MAX(1,_glassRect.size.height);
        [_lens26 configureOn:lens26 settings:[c rim26ForScope:rimLens dark:rimDark] solid:veil strength:lensLift];
    }
    [_bodyRim layoutIfNeeded]; [_lensRim layoutIfNeeded];
    // Each surface retains a fixed full-resolution canvas. Moving or growing the
    // lens moves only its native clipping view; it does not reallocate a drawable.
    for(WXGSyncBackdropView *v in _bodyStack)v.frame=_bodyClip.bounds;
    for(WXGSyncBackdropView *v in _edgeStack)v.frame=_bodyClip.bounds;
    for(WXGSyncBackdropView *v in _lensStack)v.frame=CGRectInset(_lensClip.bounds,-_lensPad,-_lensPad);   // FIX113 U: with the smaller bar's margin
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
        MTKTextureLoaderOptionAllocateMipmaps:@NO,MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode:@(MTLStorageModeShared)   // FIX113: patched in place (drawIconPatchAtPixels)
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
        MTKTextureLoaderOptionAllocateMipmaps:@NO,MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode:@(MTLStorageModeShared)   // FIX113: patched in place (drawIconPatchAtPixels)
    } error:NULL];
}
- (void)setNormalIconTexture:(id<MTLTexture>)normal selectedIconTexture:(id<MTLTexture>)selected {
    if(normal)_normalIcons=normal;if(selected)_selectedIcons=selected;_needsDraw=YES;
}
- (void)setDockTabAtlas:(UIImage *)atlas texture:(id<MTLTexture>)texture centers:(NSArray<NSNumber *> *)centers {
    if(!texture && atlas && _gpu) {
        id<MTLTexture> uploaded=[self iconTexture:atlas];
        if(uploaded!=WXGTransparentTexture())texture=uploaded;
    }
    _dockTabIcons=(atlas && texture && atlas.scale>0 && centers.count==4)?texture:nil;
    if(_dockTabIcons) {
        for(NSUInteger i=0;i<4;i++)_dockTabCenters[i]=(float)centers[i].doubleValue;
        _dockTabTile=CGSizeMake(texture.width/(4.*atlas.scale),texture.height/atlas.scale);
    }else _dockTabTile=CGSizeZero;
    _needsDraw=YES;
}
// FIX113: the dock's Telegram icon animation redraws one tab's icon box in
// the atlases, frame by frame, without a new atlas: the patch converted to
// the texture's own layout (premultiplied, top row first) and written over it.
- (BOOL)drawIconPatchAtPixels:(CGRect)pixels scale:(CGFloat)scale selected:(BOOL)selected drawing:(void (^)(void))draw {
    return [self drawIconPatchAtPixels:pixels scale:scale texture:selected?_selectedIcons:_normalIcons drawing:draw];
}
- (void)drawDockTabPatch:(NSInteger)tab pixels:(CGRect)pixels scale:(CGFloat)scale drawing:(void (^)(void))draw {
    if(!_dockTabIcons || tab<0 || tab>=4 || !draw || scale<=0 || _dockTabTile.width<=0)return;
    CGFloat shift=(tab+.5)*_dockTabTile.width-_dockTabCenters[tab];
    CGRect dest=CGRectIntegral(CGRectOffset(pixels,shift*scale,0));
    CGFloat width=_dockTabIcons.width/4.;
    dest=CGRectIntersection(dest,CGRectMake(tab*width,0,width,_dockTabIcons.height));
    if(CGRectIsEmpty(dest))return;
    [self drawIconPatchAtPixels:dest scale:scale texture:_dockTabIcons drawing:^{
        CGContextTranslateCTM(UIGraphicsGetCurrentContext(),shift,0);
        draw();
    }];
}
- (BOOL)drawIconPatchAtPixels:(CGRect)pixels scale:(CGFloat)scale texture:(id<MTLTexture>)texture drawing:(void (^)(void))draw {
    if(!draw || scale<=0 || !texture || texture.storageMode!=MTLStorageModeShared || texture==WXGTransparentTexture())return NO;
    MTLPixelFormat format=texture.pixelFormat;BOOL bgra=format==MTLPixelFormatBGRA8Unorm;
    if(!bgra && format!=MTLPixelFormatRGBA8Unorm)return NO;
    NSInteger x=(NSInteger)pixels.origin.x,y=(NSInteger)pixels.origin.y,w=(NSInteger)pixels.size.width,h=(NSInteger)pixels.size.height;
    if(x<0 || y<0 || w<1 || h<1 || x+w>(NSInteger)texture.width || y+h>(NSInteger)texture.height)return NO;
    // Exactly the region's pixels, in the texture's layout (premultiplied,
    // the top row first), drawn in the atlas's points with UIKit's flipped
    // coordinates: no intermediate image, no rounding of its size.
    NSMutableData *bytes=[NSMutableData dataWithLength:(NSUInteger)(w*h*4)];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info=bgra?(CGBitmapInfo)kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little:(CGBitmapInfo)kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big;
    CGContextRef context=CGBitmapContextCreate(bytes.mutableBytes,(size_t)w,(size_t)h,8,(size_t)w*4,space,info);
    CGColorSpaceRelease(space);
    if(!context)return NO;
    CGContextTranslateCTM(context,0,h);CGContextScaleCTM(context,scale,-scale);
    CGContextTranslateCTM(context,-x/scale,-y/scale);
    UIGraphicsPushContext(context);
    @try {draw();} @finally {UIGraphicsPopContext();CGContextRelease(context);}
    [texture replaceRegion:MTLRegionMake2D((NSUInteger)x,(NSUInteger)y,(NSUInteger)w,(NSUInteger)h) mipmapLevel:0 withBytes:bytes.bytes bytesPerRow:(NSUInteger)w*4];
    _needsDraw=YES;
    return YES;
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
    // FIX114 L: WeChat may clip a view we opened for the shadow again in its own layout.
    if(_shadowClips.count)for(UIView *v in _shadowClips.allObjects)if(v.clipsToBounds)WXGShadowWrite(v,NO);
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
    WXGScopeOptics scoped=[self scopedOptics];   // FIX58 (FIX85: by scope; FIX113 N: a groove's flat)
    WXGMeshOptics bodyOptics={(float)_glassRect.size.width,(float)_glassRect.size.height,1.f,(float)_maximumCornerRadius,(float)scoped.edgeWidth,
        (float)(scoped.refraction*(_buttonPressEffect?1+.35*press:1)),1.f,_buttonPressEffect?1.f+.04f*press:1.f,1.f,
        (float)(scoped.dispersion*.85),0.f,0.f,0.f};
    WXGGlassScope bodyScope=[self effectiveBodyScope];
    _backdropTone=[c backdropToneForScope:bodyScope dark:[self darkAppearance]];   // the range's, of this appearance
    // The body's refraction: iOS 26's curve (WXGLensCurve.h), its band and
    // depth as shares of the glass' short side (unscaled; the clip stretches
    // it with a press), the band at most its cap (pt) with the depth kept in
    // proportion; the colour split's strength. The button press' zoom stays.
    {
        WXGGlassCurve curve=[c glassCurveForScope:bodyScope];
        float sh=(float)MIN(_glassRect.size.width,_glassRect.size.height);
        float band=(float)curve.height*sh,cap=(float)curve.maxHeight,shift=(float)curve.amount*sh;
        if(band>cap && band>0.f){shift*=cap/band;band=cap;}
        float kh=roundf(band*4.f)/4.f,ka=roundf(shift*4.f)/4.f;
        bodyOptics.curveHeight=kh>.01f && ka>.01f?kh:0.f;bodyOptics.curveAmount=ka;bodyOptics.curveSqueeze=(float)curve.squeeze;
        bodyOptics.edgeWidth=WXG_MAX(kh,.5f);bodyOptics.refraction=0.f;bodyOptics.offsetScale=1.f;
        bodyOptics.dispersion=roundf((float)curve.dispersion*100.f)/100.f;
    }
    BOOL bodyMesh=mesh && body && bodyOptics.width>1 && bodyOptics.height>1;
    [self applyStack:_bodyStack visible:body split:split radius:scoped.blur*scale optics:bodyOptics quality:WXGMeshQualityBody mesh:bodyMesh group:[self bodyGroup] plain:NO];
    BOOL ring=bodyMesh && scoped.blurCoverage<99.5 && scoped.blur*scale>.01 && !lean;
    [self applyStack:_edgeStack visible:ring split:split radius:0 optics:bodyOptics quality:WXGMeshQualityBody mesh:ring group:[self bodyGroup] plain:NO];
    if(ring)[self updateEdgeMask:c];
    WXGMeshOptics lensOptics=bodyOptics;CGFloat lensBlur=0;BOOL lensMesh=NO;
    BOOL lensSplit=split;   // the lens' own colour split, in 流畅模式 too
    _lensSeesBarApplied=mode>=2 && [self lensSeesBarWanted];
    BOOL seesBar=lens && _lensSeesBarApplied;
    BOOL pureDock=[self pureDockActive];
    BOOL moving=CACurrentMediaTime()-_lensMovedAt<.08;
    _endReachLeft=_endReachRight=0.f;
    if(lens && pureDock) {
        CGSize size=_lensClip.bounds.size;
        size.width=moving?round(size.width):round(size.width*2)/2;
        size.height=moving?round(size.height):round(size.height*2)/2;
        float radius=(float)(_maximumCornerRadius*_lensRect.size.height/MAX(1,_glassRect.size.height));
        CGRect bar=[self drawnBarRect];
        CGFloat dockScale=self.glassScope==WXGGlassScopeSegment?WXGClamp(bar.size.height/62.,.35,1.):1.;
        lensBlur=0; lensMesh=mesh && size.width>1 && size.height>1; lensSplit=NO;
        CGFloat pad=0;
        lensOptics=WXGPureDockLensOptics(c,_lensRect,bar,size,radius,_lensRestHeight,press,dockScale,
                                         seesBar && _dockSurface && lensMesh,&pad);
        if(fabs(pad-_lensPad)>.01) {
            _lensPad=pad;
            [CATransaction begin];[CATransaction setDisableActions:YES];
            for(WXGSyncBackdropView *v in _lensStack)v.frame=CGRectInset(_lensClip.bounds,-pad,-pad);
            [CATransaction commit];
        }
    }else if(lens) {
        WXGLensSettings L=[self lensSettings];   // FIX113 O
        CGSize size=_lensClip.bounds.size;
        size.width=round(size.width*2)/2;size.height=round(size.height*2)/2;
        float radius=(float)(_maximumCornerRadius*_lensRect.size.height/MAX(1,_glassRect.size.height));
        // The lens' refraction: the same curve, its band and depth as shares
        // of the lens' short side, growing with the press; the colour split
        // toward its corners, in three channel layers whenever the RGB
        // switch is on (流畅模式 too: only the lens, only while pressed).
        float shortSide=(float)MIN(size.width,size.height);
        float band=roundf((float)L.band*shortSide*press*4.f)/4.f,depth=roundf((float)L.depth*shortSide*press*4.f)/4.f;
        float kd=roundf((float)L.split*100.f)/100.f;
        lensOptics=(WXGMeshOptics){(float)size.width,(float)size.height,1.f,radius,WXG_MAX(band,.5f),0.f,1.f,
            1.f,1.f+press*(float)(L.zoom-1),kd,0.f,0.f,0.f};
        lensOptics.curveHeight=band>.01f && depth>.01f?band:0.f;lensOptics.curveAmount=depth;lensOptics.curveSqueeze=(float)L.squeeze;
        // FIX113 U: seeing the bar, the lens captures it already blurred (and
        // the page around it as it is): only the lens' own blur, as it lifts.
        lensBlur=(seesBar?L.blur*press:scoped.blur+(L.blur-scoped.blur)*press)*scale;
        lensMesh=mesh && size.width>1 && size.height>1;
        lensSplit=mesh && kd>0.f && c.syncDispersion && WXGFilterFactoryAvailable() && !_lightweight;
        // FIX113 U: seeing the bar, the lens shows that bar made smaller (the
        // shader's inset), its own veil, edge ring and rim, then refracted. The
        // bar's far ends are pushed far out (only a near end shapes it).
        CGFloat pad=0;
        if(seesBar && _dockSurface && press>0.f && lensMesh) {
            CGRect bar=[self drawnBarRect];CGFloat reach=bar.size.height*.75+2;   // a bar end shapes the lens only within ~0.72 x its height
            CGFloat left=CGRectGetMinX(bar)-CGRectGetMinX(_lensRect),right=CGRectGetMaxX(bar)-CGRectGetMinX(_lensRect);
            lensOptics.sbLeft=left<-reach?-10000.f:(float)(round(left*2)/2);
            lensOptics.sbRight=right>size.width+reach?10000.f:(float)(round(right*2)/2);
            lensOptics.sbTop=(float)(round((CGRectGetMinY(bar)-CGRectGetMinY(_lensRect))*2)/2);
            lensOptics.sbBottom=(float)(round((CGRectGetMaxY(bar)-CGRectGetMinY(_lensRect))*2)/2);
            lensOptics.sbRadius=0;   // the dock and the segment bar are capsules (a rounded field's normals jump across its middle lines)
            lensOptics.shrinkPress=press;lensOptics.shrinkPinch=(float)(round(WXGClamp(L.pinch,0,.30)*1000)/1000);
            CGFloat barHalf=bar.size.height*.5;
            if([self kyantOpticsActive]) {
                // Keep the inner bar inset strictly fixed at bodyPinch during
                // fast elastic height deformation; pass only the positive
                // squash delta as depth padding so the inset ramp never
                // collapses when the lens flattens.
                CGFloat squash=_lensRestHeight>1?MAX(0.,(_lensRestHeight-_lensRect.size.height)*.5):0.;
                lensOptics.shrinkExtra=(float)(round(squash*4)/4);
            }else {
                // FIX113 Y: the drag-speed deformation must not open / close the
                // strip between the smaller bar and the rim: inset more / less by
                // what the lens lost / gained in half height (quarter points).
                // Capped so the smaller bar keeps at least a quarter of its height.
                CGFloat keep=WXGClamp(L.elasticKeepStrip,0,1);
                if(keep>0 && _lensRestHeight>1) {
                    CGFloat extra=keep*(_lensRestHeight-_lensRect.size.height)*.5;
                    extra=MIN(extra,MAX(0,barHalf*(.75-WXGClamp(L.pinch,0,.30)*press)));
                    lensOptics.shrinkExtra=(float)(round(extra*4)/4);
                }
            }
            // Outside the smaller bar the page beyond the bar's edge is shown,
            // the source pushed out by up to h(1 - 1/zoom) + inset/zoom: the
            // backdrop takes that margin (clipped to the lens), so the lens'
            // rim never shows the capture's clamped edge. Set for the whole
            // press (full zoom and inset), in 2 pt steps. FIX113 Y: with the
            // deformation on, its extra inset is budgeted for up front (the
            // lens squashes from ~growth x the bar's height to ~0.86 x it,
            // within the cap above), so the margin holds still as it
            // squashes and swells; never less than the extra in use.
            CGFloat pinch=WXGClamp(L.pinch,0,.30);
            CGFloat keep=[self kyantOpticsActive]?0:WXGClamp(L.elasticKeepStrip,0,1);
            CGFloat budget=keep>0 && L.elasticOn && !UIAccessibilityIsReduceMotionEnabled()?
                keep*MIN(MAX(0,L.growth-.86)*barHalf,barHalf*(.75-pinch)):0;
            CGFloat half=barHalf,zoom=MAX(1,L.zoom),full=half*pinch+([self kyantOpticsActive]?0:MAX(budget,MAX(0,lensOptics.shrinkExtra)));
            pad=MIN(40,ceil((half*(1-1/zoom)+full/zoom+2)/2)*2);
            if([self kyantOpticsActive]) {
                CGFloat spectral=c.syncDispersion && WXGFilterFactoryAvailable()?[c extraNumber:@"dockKyantDispersion"]:0;
                CGFloat depth=[c extraNumber:@"dockKyantLensRefractionAmount"];
                CGFloat ring=spectral>0?4.5*spectral/(1.+.25*spectral):0;
                CGFloat farSide=MAX(0.,1.55*depth-(CGFloat)shortSide);
                pad=MIN(64.,ceil((full+MAX(ring,farSide)+4.)/2.)*2.);
            }
            lensOptics.padX=lensOptics.padY=(float)pad;lensOptics.width+=(float)(2*pad);lensOptics.height+=(float)(2*pad);
            if(lensOptics.barRight>lensOptics.barLeft){lensOptics.barLeft+=(float)pad;lensOptics.barRight+=(float)pad;lensOptics.barTop+=(float)pad;lensOptics.barBottom+=(float)pad;}
            lensOptics.sbLeft+=(float)pad;lensOptics.sbRight+=(float)pad;lensOptics.sbTop+=(float)pad;lensOptics.sbBottom+=(float)pad;
        }
        if(fabs(pad-_lensPad)>.01) {
            _lensPad=pad;
            [CATransaction begin];[CATransaction setDisableActions:YES];
            for(WXGSyncBackdropView *v in _lensStack)v.frame=CGRectInset(_lensClip.bounds,-pad,-pad);
            [CATransaction commit];
        }
    }else if(_lensPad>.01) {
        _lensPad=0;
        for(WXGSyncBackdropView *v in _lensStack)v.frame=_lensClip.bounds;
    }
    // FIX113 U: seeing the bar, a resting lens (no press: no refraction, zoom
    // or blur) would only copy what is right beneath it; it is left out then
    // (the overlay's selection and icons stay), so a resting dock or segment
    // bar costs no second capture while the page scrolls under it.
    // FIX114 A: a near mesh while the lens moves; the exact one when it rests
    // (looked at again shortly after the last move).
    BOOL kept=NO;
    BOOL useR8=pureDock || [self kyantOpticsActive];
    if(!useR8) {
        kept=![self applyStack:_lensStack visible:lens && (!seesBar || press>0.f) split:lensSplit radius:lensBlur optics:lensOptics
             quality:WXGMeshShrinks(lensOptics)?WXGMeshQualityLensBar:WXGMeshQualityLens mesh:lensMesh group:seesBar?_lensGroup:[self bodyGroup] plain:seesBar loose:moving];
    }else {
        lensOptics.kyantMode=1.f;
        // Match iOS 26 glassBackground: keep the captured bar & touch glow at
        // 1x so brightness flows seamlessly across the lens silhouette; the
        // Metal glyph overlay still applies zoom to selected icons.
        lensOptics.zoomAfter=1.f;
        if(!pureDock) {
            lensOptics.kyantHeight=(float)[c extraNumber:@"dockKyantLensRefractionHeight"]*press;
            lensOptics.kyantAmount=(float)[c extraNumber:@"dockKyantLensRefractionAmount"]*press;
            lensOptics.edgeWidth=MAX(.5f,lensOptics.kyantHeight);
            lensOptics.dispersion=(float)[c extraNumber:@"dockKyantDispersion"];
        }
        BOOL spectral=lensMesh && lensOptics.dispersion>0.f && (pureDock || c.syncDispersion) && WXGFilterFactoryAvailable();
        WXGMeshQuality lensQuality=pureDock && moving?WXGMeshQualityLensMove:WXGMeshQualityLensBar;
        for(NSUInteger i=0;i<_lensStack.count;i++) {
            WXGSyncBackdropView *view=_lensStack[i];
            BOOL show=lens && press>0.f && (spectral || i==0);
            if(view.hidden==show)view.hidden=!show;
            if(!show){[view applyRefraction:lensOptics quality:lensQuality enabled:NO];continue;}
            if(spectral)[view configureSpectralGroup:_lensGroup tapIndex:(NSInteger)i radius:lensBlur];
            else [view configureGroup:_lensGroup radius:lensBlur channel:0 plain:YES tone:(WXGBackdropTone){1,0}];
            view.captureLimit=_lightweight || c.performanceMode?2:0;[view applyCaptureScale];
            WXGMeshOptics channelOptics=lensOptics;
            channelOptics.kyantChannel=spectral?WXGKyantSpectralOffset((int)i):0.f;
            if(!spectral)channelOptics.dispersion=0.f;
            if(![view applyRefraction:channelOptics quality:lensQuality enabled:lensMesh loose:moving])kept=YES;
        }
    }
    if(_mainDockOptics && lens && press>.05f && CACurrentMediaTime()-_lastOpticsTrace>.1) {
        _lastOpticsTrace=CACurrentMediaTime();
        if(!_pressedOpticsHistory)_pressedOpticsHistory=[NSMutableArray array];
        NSUInteger shown=0,accepted=0;for(WXGSyncBackdropView *v in _lensStack)if(!v.hidden){shown++;if(v.meshAccepted)accepted++;}
        [_pressedOpticsHistory addObject:@{@"t":@(_lastOpticsTrace),@"press":@(press),@"pureDock":@(pureDock),@"kyant":@([self kyantOpticsActive]),
            @"lensSeesBar":@(seesBar),@"shown":@(shown),@"accepted":@(accepted),@"vertices":@(_lensBackdrop.meshVertices),
            @"pinch":@(lensOptics.shrinkPinch),@"extraInset":@(lensOptics.shrinkExtra),@"pad":@(_lensPad),
            @"lensSize":@[@(lensOptics.width-2*_lensPad),@(lensOptics.height-2*_lensPad)],
            @"band":@(lensOptics.kyantHeight),@"depth":@(lensOptics.kyantAmount),@"dispersion":@(lensOptics.dispersion)}];
        if(_pressedOpticsHistory.count>24)[_pressedOpticsHistory removeObjectAtIndex:0];
    }
    if(kept)++_lensMeshKept;
    if((kept || (pureDock && moving && lens && press>0.f)) && !_lensSettlePending) {
        _lensSettlePending=YES;__weak WXGGlassView *weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            WXGGlassView *me=weakSelf;if(!me)return;me->_lensSettlePending=NO;
            // (review: layout reaches applySyncMode only in some states) applied
            // here directly when the lens has rested since, as runTick would.
            if(me->_active && !me.hidden && WXGPresentedVisible(me) && !CGRectIsEmpty(me->_glassRect) && WXGEffectiveRenderMode()>=2 &&
               CACurrentMediaTime()-me->_lensMovedAt>=.08)[me applySyncMode];
        });
    }
}
// One colour stack: [0] alone in full colour, or red/green/blue with the
// channel's own refraction (red samples outward, blue inward, as wxgRGB).
- (void)applyStack:(NSArray<WXGSyncBackdropView *> *)stack visible:(BOOL)visible split:(BOOL)split radius:(CGFloat)radius
            optics:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality mesh:(BOOL)mesh group:(NSString *)group plain:(BOOL)plain {
    [self applyStack:stack visible:visible split:split radius:radius optics:optics quality:quality mesh:mesh group:group plain:plain loose:NO];
}
// FIX114 A: NO when some channel kept a near mesh (loose).
- (BOOL)applyStack:(NSArray<WXGSyncBackdropView *> *)stack visible:(BOOL)visible split:(BOOL)split radius:(CGFloat)radius
            optics:(WXGMeshOptics)optics quality:(WXGMeshQuality)quality mesh:(BOOL)mesh group:(NSString *)group plain:(BOOL)plain loose:(BOOL)loose {
    BOOL exact=YES;
    for(NSUInteger i=0;i<stack.count;i++) {
        WXGSyncBackdropView *view=stack[i];
        BOOL show=visible && (i==0 || (split && i<3));
        if(view.hidden==show)view.hidden=!show;
        if(!show){[view applyRefraction:optics quality:quality enabled:NO];continue;}
        [view configureGroup:group radius:radius channel:split?(NSInteger)i+1:0 plain:plain tone:_backdropTone];   // FIX114 J: the range's
        view.captureLimit=_lightweight || WXGConfig.shared.performanceMode?2:0;[view applyCaptureScale];
        WXGMeshOptics channelOptics=optics;
        channelOptics.channel=split?(i==0?1.f:i==2?-1.f:0.f):0.f;
        if(!split)channelOptics.dispersion=0.f;
        if(![view applyRefraction:channelOptics quality:quality enabled:mesh loose:loose])exact=NO;
    }
    return exact;
}
// Exactly the shader's sharp weight, generated at the unscaled glass size and
// stretched with the clip (the field scales with the bar), so a press does
// not regenerate it. Rebuilt only when size, radius, edge or coverage change.
- (void)updateEdgeMask:(WXGConfig *)c {
    WXGScopeOptics scoped=[self scopedOptics];   // FIX58 (FIX85: by scope; FIX113 N)
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
    WXGConfig *c=WXGConfig.shared; WXGScopeOptics scoped=[self scopedOptics];   // FIX58 (FIX85: by scope; FIX113 N)
    BOOL rimDark=[self darkAppearance] || _rimAlwaysDark;                       // FIX86
    WXGLensSettings L=[self lensSettings];   // FIX113 O
    CGFloat sigma=scoped.blur*[self screenScale];
    CGFloat desiredLensSigma=L.blur*[self screenScale];
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
    CGFloat lensSigma=L.blur*[self screenScale];
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
    u.lensOptics=(WXGFloat4){(float)L.iconRefraction,(float)L.iconDispersion,(float)MAX(1,L.iconEdgeWidth),0.f};   // the icons and titles in the lens
    u.appearance=(WXGFloat4){[self darkAppearance]?1.f:0.f,1.f,_bodyMask?1.f:0.f,0};   // y: the veil at its own opacity
    BOOL darkStyle=[self darkAppearance];
    // FIX86: the iOS 27-like rim: the bar outline the shader draws (inside
    // the dock's lens) is the same light, over the rim's width. FIX89: its two
    // highlights: the first in glow / optics.y / borderColor, the second in
    // glow2 / extra.x / glowColor2.
    BOOL glowRim=[c rimStyleForScope:[self rimScope]]==WXGRimStyleGlow;
    WXGRimGlowShape glows[WXGRimGlowCount];
    for(NSInteger i=0;i<WXGRimGlowCount;i++)glows[i]=[c rimGlowForScope:[self rimScope] index:i dark:rimDark];
    // FIX87: x = 1 + the highlight's angle in radians (0 = off).
    WXGFloat4 (^glowParams)(WXGRimGlowShape)=^WXGFloat4(WXGRimGlowShape g){
        return (WXGFloat4){(float)(1+WXGClamp(g.angle,0,180)*M_PI/180),(float)g.endLevel,(float)g.sharpness,(float)g.falloff};
    };
    u.glow=glowRim?glowParams(glows[0]):(WXGFloat4){0,0,0,0};
    u.glow2=glowRim?glowParams(glows[1]):(WXGFloat4){0,0,0,0};
    u.glowColor2=glowRim?(WXGFloat4){(float)glows[1].red,(float)glows[1].green,(float)glows[1].blue,(float)glows[1].alpha}:(WXGFloat4){0,0,0,0};
    u.optics=(WXGFloat4){(float)L.zoom,(float)(glowRim?glows[0].width:0.),(float)L.pinch,(float)scoped.edgeWidth};
    // FIX88: y / z the lens's own dispersion range and its top / bottom ratio
    // (WXGLensDispersionWidth). FIX89: x the second highlight's width.
    // FIX94: w the margin of the bar following the lens' rim; FIX112: always
    // 0 (that effect is gone; the server's shader still reads the field).
    // FIX113 N: H's outward lens (w < 0) and M's flat bar (|w| = WXG_LENS_FLAT)
    // removed with their switches (the served shader still knows both).
    u.extra=(WXGFloat4){glowRim?(float)glows[1].width:0.f,0.f,0.f,0.f};
    // FIX97: the colour split of the bar seen through the dock's lens; z the
    // page behind it as the shader assumes it (black in dark mode, white in
    // light), for the channels CA's single alpha covers too much.
    // FIX98: w 1 + the selection colour's weight when the dock sets one.
    u.extra2=(WXGFloat4){0.f,0.f,[self darkAppearance]?0.f:1.f,
                         _selectionWeight>=0?(float)(1+_selectionWeight):0.f};
    CGFloat r=0,g=0,b=0,a=0;
    [WXGColor([self darkAppearance]?c.darkSelectionHex:c.selectionHex) getRed:&r green:&g blue:&b alpha:&a];
    CGFloat selectionAlpha=c.selectionOpacity+(c.pressedOpacity-c.selectionOpacity)*WXGClamp(_pressAmount,0,1);
    CGFloat sr=0,sg=0,sb=0,sa=0;
    if(_selectionOverride && [_selectionOverride getRed:&sr green:&sg blue:&sb alpha:&sa]) {   // FIX113 N: the segment bar's pill
        r=sr;g=sg;b=sb;a=sa;selectionAlpha=1;
        if(_selectionOverridePressedAlpha>=0)a=sa+(_selectionOverridePressedAlpha-sa)*WXGClamp(_pressAmount,0,1);   // FIX113 P: fading as the dock's
    }
    u.selectionColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*selectionAlpha)};
    // The bar's outline seen inside the lens, drawn by the shader: the iOS 27
    // border's first highlight; the iOS 26 border is its own layers (none here).
    u.borderColor=glowRim?(WXGFloat4){(float)glows[0].red,(float)glows[0].green,(float)glows[0].blue,(float)glows[0].alpha}:(WXGFloat4){0,0,0,0};
    // FIX88: the outline the dock's tap animation draws in its lens: the rim
    // as the shader draws it there. The shader's rim strength (its top /
    // bottom fades) at the top and the bottom, averaged. FIX89: the iOS
    // 27-like rim as one thin line per highlight, at its level on the top and
    // bottom edges (what the lens mostly shows of the bar).
    if(glowRim) {
        NSMutableArray *colors=[NSMutableArray array],*widths=[NSMutableArray array];
        for(NSInteger i=0;i<WXGRimGlowCount;i++) {
            WXGRimGlowShape gl=glows[i];
            CGFloat level=WXGRimGlowLevel(0,1,gl.angle,gl.endLevel,gl.sharpness);
            [colors addObject:[UIColor colorWithRed:gl.red green:gl.green blue:gl.blue alpha:WXGClamp(gl.alpha*level,0,1)]];
            [widths addObject:@(gl.width>.01?MAX(.75,MIN(gl.width*.5,2.)):0)];
        }
        _lensOutlineColors=colors;_lensOutlineWidths=widths;
    }else {_lensOutlineColors=@[];_lensOutlineWidths=@[];}
    // FIX29: the dock and the other glass each have a switch and a range for
    // the edge weakening; off (or a range of 0) = full coverage to the outline.
    // y: the veil's fade toward the outline, off (the system's face is even to the outline).
    u.motion=(WXGFloat4){(float)_barScale,0.f,(float)(scoped.blurCoverage*.01),(float)_lensAnchorX};
    // Opacity is per appearance now, so no extra dark gain (y = 1).
    u.rim=(WXGFloat4){0.f,1.f,.65f,(float)_maximumCornerRadius};
    BOOL dark=darkStyle;
    // FIX27: the dock has its own material veil; every other glass shares one.
    WXGGlassScope drawScope=[self effectiveBodyScope];
    NSString *materialHex=[c materialHexForScope:drawScope dark:dark];   // FIX113 O: by range (R11 pureDock -> 其余玻璃)
    CGFloat materialOpacity=[c materialOpacityForScope:drawScope dark:dark];
    [WXGColor(materialHex) getRed:&r green:&g blue:&b alpha:&a];
    u.tintColor=(WXGFloat4){(float)r,(float)g,(float)b,(float)(a*materialOpacity)};

    // FIX40: w = 1: the body veil is the render-server layer; the body pass
    // draws icons only (the lens pass keeps its own veil).
    u.sync=(WXGFloat4){(float)_syncMode,(float)WXGClamp(L.iconTopRatio,.1,1),(float)WXGClamp(L.iconSharpness,1,6),_syncMode>=2?1.f:0.f};
    u.style=(WXGFloat4){0.f,0.f,0.f,0.f};   // (the veil fade's range, the old rim's two fades, the lens' rim offset: none)
    NSUInteger canvasWidth=(pure || !f)?bodyDrawable.texture.width:f.width,canvasHeight=(pure || !f)?bodyDrawable.texture.height:f.height;
    // FIX113 L: the dock's lens pass without the bar's outline (and its second
    // highlight): only the lens' own rim borders it (N: always, the switch gone).
    WXGFloat4 barBorder=u.borderColor,barGlow2=u.glowColor2,barVeil=u.tintColor,barExtra2=u.extra2,barOptics=u.optics,barLensOptics=u.lensOptics,barSync=u.sync,barStyle=u.style;
    // FIX113 T: the bar seen in the lens: its outline only when switched on
    // (L / N: never), its background unless switched off.
    BOOL lensOutline=NO,lensVeil=YES;   // (the two switches are gone: never the outline, always the background)
    // FIX113 U: the lens' backdrop sees the bar itself (its veil, rim, edge
    // ring and icons, as drawn) and refracts it with the page: nothing of the
    // bar is drawn again here (no veil, outline, second highlight, the bar's
    // own split); only the resting selection (on the smaller bar the mesh
    // shows: the same inset) and the selected icons, which the body leaves
    // out under the lens.
    BOOL seesBar=_syncMode>=2 && _lensSeesBarApplied;
    for(NSUInteger surface=0;surface<(hasLens?2u:1u);surface++) {
        u.appearance.w=(!surface && _buttonPressEffect)?-1.f:(float)surface;
        u.borderColor=barBorder;u.glowColor2=barGlow2;u.tintColor=barVeil;u.extra2=barExtra2;u.optics=barOptics;u.lensOptics=barLensOptics;u.sync=barSync;u.style=barStyle;
        if(surface && seesBar) {
            u.borderColor.w=0;u.glowColor2.w=0;u.tintColor.w=0;
            u.extra2.x=0;u.extra2.y=0;
            // FIX113 X: the lens pass draws only the selection and the icons /
            // titles here: their own refraction strength and width (the bar and
            // the page around it, refracted by the lens' mesh, keep the lens').
            u.lensOptics.x=(float)L.iconRefraction;u.lensOptics.z=(float)MAX(1,L.iconEdgeWidth);
            u.sync.y=(float)WXGClamp(L.iconTopRatio,.1,1);u.sync.z=(float)WXGClamp(L.iconSharpness,1,6);   // FIX113 Y: their own top / bottom ratio and curve
        }else if(surface && _dockSurface) {
            if(!lensOutline){u.borderColor.w=0;u.glowColor2.w=0;}
            if(!lensVeil)u.tintColor.w=0;
        }
        u.extra.w=0.f;
        BOOL pureLens=surface && seesBar && [self pureDockActive];
        BOOL dockLens=surface && seesBar && !pureLens && [self kyantOpticsActive];
        if(pureLens) {
            u.style=_dockTabCenters;
            u.extra2.x=(float)_dockTabTile.width;u.extra2.y=(float)_dockTabTile.height;
            float press=roundf((float)WXGClamp(_pressAmount,0,1)*32.f)/32.f;
            CGFloat barH=MAX(1.,[self drawnBarRect].size.height);
            CGFloat dockScale=self.glassScope==WXGGlassScopeSegment?WXGClamp(barH/62.,.35,1.):1.;
            u.material.x=press;
            u.lensOptics.x=(float)([c pureDockR8Depth]*dockScale)*press;
            u.lensOptics.y=(float)[c pureDockR8Dispersion];
            u.lensOptics.z=(float)([c pureDockR8Band]*dockScale)*press;
            CGFloat heightDelta=_lensRestHeight>1?(_lensRestHeight-_lensRect.size.height)*.5:0.;
            u.lensOptics.w=(float)(round(heightDelta*4)/4);
            u.optics.x=(float)[c pureDockIconZoom];
            CGFloat pinch=WXGClamp([c pureDockInnerBarShrink],0.,.55);
            u.optics.z=(float)(round(pinch*1000.)/1000.);
            u.extra.w=[c pureDockInnerFlat]?WXG_LENS_KYANT_FLAT:WXG_LENS_KYANT;
        }else if(dockLens) {
            // Keep the uniform ABI shared with the fallback Metal source while
            // carrying per-tab stationary centers and tile dimensions.
            u.style=_dockTabCenters;
            u.extra2.x=(float)_dockTabTile.width;u.extra2.y=(float)_dockTabTile.height;
            // Do not overwrite body optics, tint, sync backend, or original pinch.
            float press=roundf((float)WXGClamp(_pressAmount,0,1)*32.f)/32.f;
            u.material.x=press;
            u.lensOptics.x=(float)[c extraNumber:@"dockKyantLensRefractionAmount"]*press;
            u.lensOptics.y=c.syncDispersion?(float)[c extraNumber:@"dockKyantDispersion"]:0.f;
            u.lensOptics.z=(float)[c extraNumber:@"dockKyantLensRefractionHeight"]*press;
            CGFloat heightDelta=_lensRestHeight>1?(_lensRestHeight-_lensRect.size.height)*.5:0.;
            u.lensOptics.w=(float)(round(heightDelta*4)/4);
            u.optics.z=(float)(round(WXGClamp(L.pinch,0,.30)*1000)/1000);
            u.extra.w=WXG_LENS_KYANT;
        }
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
        if((pureLens || dockLens) && !_lensSuppressed && _dockTabIcons)selectedIcons=_dockTabIcons;
        [encoder setFragmentTexture:raw atIndex:0]; [encoder setFragmentTexture:normalIcons atIndex:1];
        [encoder setFragmentTexture:selectedIcons atIndex:2]; [encoder setFragmentTexture:soft atIndex:3];
        [encoder setFragmentTexture:_bodyMask?:raw atIndex:4];
        [encoder setFragmentTexture:lensSoft?:raw atIndex:5];
        // Lens clips can move before the previous GPU drawable is displayed.
        // Render the complete lens canvas unless presenting synchronously in
        // the same CA transaction (pureLens scissors tightly around _lensRect).
        CGRect bounds=surface?(pureLens && withTransaction?CGRectIntersection(self.bounds,CGRectInset(_lensRect,-24,-24)):self.bounds):[self drawnBarRect]; CGFloat scale=[self screenScale];
        NSUInteger x=(NSUInteger)MAX(0,floor(bounds.origin.x*scale)),y=(NSUInteger)MAX(0,floor(bounds.origin.y*scale));
        NSUInteger right=(NSUInteger)MIN(canvasWidth,ceil(CGRectGetMaxX(bounds)*scale)),bottom=(NSUInteger)MIN(canvasHeight,ceil(CGRectGetMaxY(bounds)*scale));
        if(right>x && bottom>y) {
            [encoder setScissorRect:(MTLScissorRect){x,y,right-x,bottom-y}];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        }
        [encoder endEncoding];
    }
    NSUInteger generation=_activationGeneration,canvas=_canvasGeneration;_needsDraw=NO; ++f.busy; ++_draws; WXGPerfNoteGlassSubmit(); dispatch_semaphore_t semaphore=_inFlight; __weak WXGGlassView *weakSelf=self;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        dispatch_semaphore_signal(semaphore);
        dispatch_async(dispatch_get_main_queue(),^{
            if(f.busy) --f.busy;
            if(completed.status==MTLCommandBufferStatusCompleted) {
                ++weakSelf.completedFrames;
                weakSelf.lastGPUms=MAX(0,(completed.GPUEndTime-completed.GPUStartTime)*1000);
                WXGPerfNoteGPU(weakSelf.lastGPUms);   // FIX119 A
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
// FIX114 I: what 边界过渡 does on this glass: the value, TEST9's shift at the
// outline, the soft band (pt) and its shift at the outline, and how far in
// it may reach here.
// FIX114 K (diagnostics): ancestors that clip this glass's drop shadow (it
// would end in a straight edge there): class and how much is cut (pt).
- (NSArray *)shadowClipNames {
    NSMutableArray *out=[NSMutableArray array];
    for(UIView *v in _shadowClips.allObjects)[out addObject:NSStringFromClass(v.class)];
    return out;
}
- (NSArray *)dropShadowClippers {
    if(_dropShadow.hidden)return @[];
    NSMutableArray *out=[NSMutableArray array];
    CGRect frame=_dropShadow.frame;
    for(UIView *v=self.superview;v && out.count<4;v=v.superview) {
        if(!v.clipsToBounds && !v.layer.masksToBounds)continue;
        CGRect r=[self convertRect:frame toView:v],b=v.bounds;
        CGFloat cut=MAX(MAX(CGRectGetMinX(b)-CGRectGetMinX(r),CGRectGetMaxX(r)-CGRectGetMaxX(b)),MAX(CGRectGetMinY(b)-CGRectGetMinY(r),CGRectGetMaxY(r)-CGRectGetMaxY(b)));
        if(cut>.5)[out addObject:@{@"class":NSStringFromClass(v.class),@"cutPt":@(round(cut*10)/10)}];
    }
    return out;
}
// What the glass' body is drawn with (diagnostics): its curve as set and in points, its blur, tone and veil.
- (NSDictionary *)glassEvidence {
    WXGConfig *c=WXGConfig.shared;WXGGlassCurve curve=[c glassCurveForScope:self.glassScope];WXGScopeOptics scoped=[self scopedOptics];
    WXGBackdropTone tone=[c backdropToneForScope:self.glassScope dark:[self darkAppearance]];
    CGFloat side=MIN(_glassRect.size.width,_glassRect.size.height),band=MIN(curve.height*side,curve.maxHeight);
    return @{@"scope":@(self.glassScope),@"band":@(curve.height),@"depth":@(curve.amount),@"bandMax":@(curve.maxHeight),@"squeeze":@(curve.squeeze),@"split":@(curve.dispersion),
             @"bandPt":@(round(band*100)/100),@"depthPt":@(curve.height>0?round(band*curve.amount/curve.height*100)/100:0),@"blur":@(round(scoped.blur*100)/100),
             @"backdropSaturation":@(tone.saturation),@"backdropBrightness":@(tone.brightness),
             @"veil":@([c materialOpacityForScope:self.glassScope dark:[self darkAppearance]])};
}
- (NSDictionary *)layerEvidence {
    NSUInteger channelsShown=0;
    for(WXGSyncBackdropView *channel in _lensStack)if(!channel.hidden)channelsShown++;
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
        @"lensOffsetCancel":@{@"available":@(WXGLensCancelAvailable()),@"value":@(WXGLensCancel())},   // FIX113 I
        @"lensSeesBar":@{@"on":@([self lensSeesBar]),@"lensGroupOwn":@([_lensBackdrop.group isEqualToString:_lensGroup]),
                         @"lensBlur":@(_lensBackdrop.radius),@"lensShown":@(!_lensBackdrop.hidden),@"lensPad":@(_lensPad),
                         @"lensRestHeight":@(_lensRestHeight),@"lensHeight":@(_lensRect.size.height),@"meshKeptWhileMoving":@(_lensMeshKept)},   // FIX113 U / Y, FIX114 A
        @"lensCurve":@{@"band":@([self lensSettings].band),@"depth":@([self lensSettings].depth),@"split":@([self lensSettings].split),@"squeeze":@([self lensSettings].squeeze),
                       @"channelsShown":@(channelsShown)},
        @"meshTransformClass":@(WXGMeshTransformClass()!=nil),@"bodyMeshApplied":@(_bodyBackdrop.meshApplied),@"bodyMeshAccepted":@(_bodyBackdrop.meshAccepted),
        @"bodyMeshVertices":@(_bodyBackdrop.meshVertices),@"glass":[self glassEvidence],
        @"dropShadow":@{@"shown":@(!_dropShadow.hidden),@"opacity":@(_dropShadow.opacity),@"key":_dropShadowKey?:@"none",@"off":@(_dropShadowOff),
                        @"clippedBy":[self dropShadowClippers],@"opened":[self shadowClipNames],@"openedEver":@(WXGShadowClipsOpened),
                        @"reclipsKeptOpen":@(WXGShadowReclips),@"rechecks":@(WXGShadowRechecks),@"heldNow":@(WXGShadowClipHolders.count),@"inWindow":@(self.window!=nil),
                        @"frame":@[@(_dropShadow.frame.origin.x),@(_dropShadow.frame.origin.y),@(_dropShadow.frame.size.width),@(_dropShadow.frame.size.height)]},   // FIX114 K@"lensMeshAccepted":@(_lensBackdrop.meshAccepted),
        @"edgeRingLive":@(_edgeBackdrop.live && !_edgeBackdrop.hidden),@"edgeRingMeshAccepted":@(_edgeBackdrop.meshAccepted),
        @"syncDispersionLayers":@(!_bodyStack[1].hidden),@"greenMeshAccepted":@(_bodyStack[1].meshAccepted),@"blueMeshAccepted":@(_bodyStack[2].meshAccepted),
        @"pressedOpticsHistory":_pressedOpticsHistory?:@[],@"opticsBuild":@WXG_BUILD_DIAGNOSTIC_REVISION,@"pureDockActive":@([self pureDockActive]),@"kyantActive":@([self kyantOpticsActive]),
        @"shaderHasKyant":@(WXGShaderKyantOptics),@"referenceCompileError":WXGOpticsCompileError?:@"",
        @"bodyPipeline":[self pureDockBodyStyle]?@"pureDock_otherGlass":@"original_FIX135",@"samplingBackend":WXGEffectiveRenderMode()>=2?@"original_renderServerLive":@"original_sceneTexture",
        @"lensMapping":[self pureDockActive]?([WXGConfig.shared pureDockInnerFlat]?@"pureDock_R8_Kyant_7tap_flatShrink":@"pureDock_R8_Kyant_7tap"):@"Kyant_rays_original_FIX113_U_Y_shrink",@"lensPinch":@([self lensSettings].pinch),
        @"lensKyantBandPt":@([self pureDockActive]?[WXGConfig.shared pureDockR8Band]:[WXGConfig.shared extraNumber:@"dockKyantLensRefractionHeight"]),
        @"lensKyantDepthPt":@([self pureDockActive]?[WXGConfig.shared pureDockR8Depth]:[WXGConfig.shared extraNumber:@"dockKyantLensRefractionAmount"]),
        @"lensKyantDispersion":@([self pureDockActive]?[WXGConfig.shared pureDockR8Dispersion]:[WXGConfig.shared extraNumber:@"dockKyantDispersion"]),
        @"pureDockInnerFlat":@([WXGConfig.shared pureDockInnerFlat]),@"pureDockInnerBarShrink":@([WXGConfig.shared pureDockInnerBarShrink]),
        @"pureDockBarScale":@(_barScale),@"pureDockBarHeight":@([self drawnBarRect].size.height),
        @"pureDockInnerBarExpected":@([self drawnBarRect].size.height*(1.-[WXGConfig.shared pureDockInnerBarShrink])),
        @"lensMeshVertices":@(_lensBackdrop.meshVertices),@"endReach":@[@(_endReachLeft),@(_endReachRight)],@"meshBuilder":@"contour_zipper_FIX57",@"meshCacheHits":@(WXGMeshCacheHits),@"meshCacheMisses":@(WXGMeshCacheMisses),
        @"backdropDefaultScale":@(_bodyBackdrop.defaultCaptureScale),@"backdropAppliedScale":@(_bodyBackdrop.appliedCaptureScale),
        @"backdropRequestedScale":@(_bodyBackdrop.requestedCaptureScale),
        @"meshSubdivisionSteps":@(_bodyBackdrop.meshSubdivision),@"lensMeshSubdivisionSteps":@(_lensBackdrop.meshSubdivision),@"backdropRevision":@(_backdropRevision),@"maximumCornerRadius":@(_maximumCornerRadius),@"rim":[_bodyRim rimEvidence]?:@{},@"lensRim":[_lensRim rimEvidence]?:@{},@"rim26":[_body26 rim26Evidence]?:@{},@"lensRim26":[_lens26 rim26Evidence]?:@{},@"lensRimStyle":@([self effectiveLensRimStyle]),@"configuredLensRimStyle":@([WXGConfig.shared rimStyleForScope:[self lensRimScope]]),@"lensRimScope":@([self lensRimScope]),@"samplingRequested":@(WXGConfig.shared.captureFPS),@"samplingCap":@(WXGScreenCaptureFPS(self.window.screen)),@"screenMaximumFPS":@(self.window.screen.maximumFramesPerSecond),@"captureScale":@([self screenScale]),
        @"buttonPressEffect":@(_buttonPressEffect),@"lensBlur":@(WXGConfig.shared.lensBlur),@"fullLensCanvas":@YES,@"bodyMaskNative":@(_bodyMask!=nil),@"drawableWidth":@(_metal.drawableSize.width),@"drawableHeight":@(_metal.drawableSize.height)};
}
@end
