#import "WXGMenuMorphView.h"
#import "WXGMenuMorphMask.h"
#import "WXGMenuMorphMaterial.h"
#import "WXGMenuMorphMetal.h"
#import "WXGBackdropSample.h"
#import "WXGCommon.h"
#import "WXGIntegration.h"
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>

typedef float WXGMenuFloat4 __attribute__((ext_vector_type(4)));
typedef struct {
    WXGMenuFloat4 viewport,menu,source,radii,optics,field;
    WXGMenuFloat4 rowsInk,triggerInk,foreground,rowsBlurBox,triggerBlurBox,highlightInk,plateLight;
} WXGMenuMorphUniforms;
_Static_assert(sizeof(WXGMenuMorphUniforms)==208,"Menu morph uniforms must match Metal");

typedef struct {
    WXGMenuFloat4 rect,region,params,kernelInfo;
} WXGMenuInkBlurUniforms;
_Static_assert(sizeof(WXGMenuInkBlurUniforms)==64,"Ink blur uniforms must match Metal");

static WXGMenuFloat4 WXGMenuFloatRect(CGRect rect) {
    return (WXGMenuFloat4){(float)rect.origin.x,(float)rect.origin.y,(float)rect.size.width,(float)rect.size.height};
}

static CGRect WXGMenuMorphCGRect(WXGMenuBox box) {return CGRectMake(box.x,box.y,box.w,box.h);}

static CGRect WXGMenuMorphZoomedRect(CGRect rect,CGFloat zoom) {
    return CGRectInset(rect,rect.size.width*(1.-zoom)*.5,rect.size.height*(1.-zoom)*.5);
}

static id<MTLTexture> WXGMenuPremultipliedTexture(UIImage *image,id<MTLDevice> device) {
    if(!image.CGImage || !device)return nil;
    size_t width=CGImageGetWidth(image.CGImage),height=CGImageGetHeight(image.CGImage);
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if(!space)return nil;
    CGContextRef bitmap=CGBitmapContextCreate(NULL,width,height,8,width*4,space,
        kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if(!bitmap)return nil;
    // Metal's row zero is the image's top row, as in UIKit. Rasterize only
    // on uploads and always in sRGB with premultiplied alpha.
    CGContextTranslateCTM(bitmap,0,height);CGContextScaleCTM(bitmap,1,-1);
    UIGraphicsPushContext(bitmap);
    [image drawInRect:CGRectMake(0,0,width,height) blendMode:kCGBlendModeCopy alpha:1.];
    UIGraphicsPopContext();
    MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:width height:height mipmapped:YES];
    descriptor.storageMode=MTLStorageModeShared;
    descriptor.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> texture=[device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0
                 withBytes:CGBitmapContextGetData(bitmap) bytesPerRow:CGBitmapContextGetBytesPerRow(bitmap)];
    CGContextRelease(bitmap);
    return texture;
}

static UIImage *WXGMenuLightDisc(BOOL gaussian);

typedef void (^WXGMenuMetalReadyBlock)(id<MTLRenderPipelineState>,id<MTLComputePipelineState>,
    id<MTLComputePipelineState>,id<MTLComputePipelineState>,id<MTLComputePipelineState>,id<MTLCommandQueue>);

static void WXGPrepareMenuMorphMetal(BOOL waitBriefly,WXGMenuMetalReadyBlock ready) {
    static dispatch_once_t once;
    static dispatch_group_t preparation;
    static id<MTLRenderPipelineState> pipeline;
    static id<MTLComputePipelineState> field,smooth,blurH,blurV;
    static id<MTLCommandQueue> queue;
    dispatch_once(&once,^{
        preparation=dispatch_group_create();
        dispatch_group_async(preparation,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            // Both immutable discs are shared by every menu session.
            (void)WXGMenuLightDisc(YES);
            id<MTLDevice> device=WXGSharedDevice();
            if(!device)return;
            MTLCompileOptions *options=[MTLCompileOptions new];
            options.languageVersion=MTLLanguageVersion2_1;
            NSError *error=nil;
            id<MTLLibrary> library=[device newLibraryWithSource:[NSString stringWithUTF8String:WXGMenuMorphMetal] options:options error:&error];
            if(!library){WXGLog(@"融展玻璃着色器编译失败：%@",error.localizedDescription);return;}
            MTLRenderPipelineDescriptor *descriptor=[MTLRenderPipelineDescriptor new];
            descriptor.vertexFunction=[library newFunctionWithName:@"wxgMenuMorphVertex"];
            descriptor.fragmentFunction=[library newFunctionWithName:@"wxgMenuMorphFragment"];
            descriptor.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
            pipeline=[device newRenderPipelineStateWithDescriptor:descriptor error:&error];
            if(!pipeline){WXGLog(@"融展玻璃渲染管线初始化失败：%@",error.localizedDescription);return;}
            id<MTLFunction> fieldFn=[library newFunctionWithName:@"wxgMenuMorphField"];
            id<MTLFunction> smoothFn=[library newFunctionWithName:@"wxgMenuMorphSmooth"];
            if(fieldFn && smoothFn) {
                field=[device newComputePipelineStateWithFunction:fieldFn error:nil];
                smooth=[device newComputePipelineStateWithFunction:smoothFn error:nil];
            }
            id<MTLFunction> blurHFn=[library newFunctionWithName:@"wxgMenuInkBlurH"];
            id<MTLFunction> blurVFn=[library newFunctionWithName:@"wxgMenuInkBlurV"];
            if(blurHFn && blurVFn) {
                blurH=[device newComputePipelineStateWithFunction:blurHFn error:nil];
                blurV=[device newComputePipelineStateWithFunction:blurVFn error:nil];
            }
            queue=[device newCommandQueue];
        });
    });
    if(!ready)return;
    dispatch_time_t timeout=waitBriefly?dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_MSEC):DISPATCH_TIME_NOW;
    if(dispatch_group_wait(preparation,timeout)==0)ready(pipeline,field,smooth,blurH,blurV,queue);
    else if(!waitBriefly)dispatch_group_notify(preparation,dispatch_get_main_queue(),^{
        ready(pipeline,field,smooth,blurH,blurV,queue);
    });
}

void WXGPrewarmMenuMorphRenderer(void) {WXGPrepareMenuMorphMetal(NO,nil);}

// Isotropic unit discs for the touch light and the plate's dark-mode shine.
// The texture moves with the finger. Its colours and radius are independent
// of the width/height of the underlying menu or its gradient direction.
static UIImage *WXGMenuLightDisc(BOOL gaussian) {
    static UIImage *pool,*plate;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
        format.scale=1;format.opaque=NO;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128,128) format:format];
        for(int kind=0;kind<2;kind++) {
            UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
                CGFloat stops[33],colours[33*4];
                for(int i=0;i<=32;i++) {
                    CGFloat t=i/32.;
                    stops[i]=t;colours[i*4]=colours[i*4+1]=colours[i*4+2]=1.;
                    colours[i*4+3]=kind?(i==32?0.:exp(-8.*t*t)):1.-t;
                }
                CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGGradientRef gradient=CGGradientCreateWithColorComponents(space,colours,stops,33);
                CGContextDrawRadialGradient(context.CGContext,gradient,CGPointMake(64,64),0,CGPointMake(64,64),64,0);
                CGGradientRelease(gradient);CGColorSpaceRelease(space);
            }];
            if(kind)pool=image;else plate=image;
        }
    });
    return gaussian?pool:plate;
}

@interface WXGMenuMorphSurface ()
- (void)placeTouchLight:(CGPoint)point strength:(CGFloat)strength;
@end

@implementation WXGMenuMorphSurface {
    WXGMenuMorphMaterial *_material;
    UIView *_bodyHost;
    CAShapeLayer *_bodyMask,*_rimClip,*_movingShadow,*_movingShadowMask;
    CGRect _lastMenu,_lastSource,_lastBounds;
    CGPoint _lastOpticalOrigin;
    CGFloat _lastRX,_lastRY,_lastRadius,_lastSmoothing,_lastScale;
    WXGMenuMorphSurfaceOptics _lastOptics;
    NSUInteger _revision;
    UIUserInterfaceStyle _appearance;
    CALayer *_touchFace,*_touchEdge,*_facePool,*_edgePool;
    CAShapeLayer *_edgeStrip;
    CGFloat _touchRimOpacity;
    NSUInteger _lightRevision;
    UIUserInterfaceStyle _lightAppearance;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.accessibilityElementsHidden=YES;
        self.layer.name=@"morph.surface";
        _movingShadow=[CAShapeLayer layer];_movingShadow.shadowColor=UIColor.blackColor.CGColor;
        _movingShadowMask=[CAShapeLayer layer];_movingShadowMask.fillRule=kCAFillRuleEvenOdd;
        _movingShadow.mask=_movingShadowMask;[self.layer addSublayer:_movingShadow];
        _bodyHost=[UIView new];[self addSubview:_bodyHost];
        _bodyMask=[CAShapeLayer layer];_bodyMask.name=@"morph.body.clip";
        _bodyMask.fillColor=UIColor.whiteColor.CGColor;_bodyHost.layer.mask=_bodyMask;
        _material=[[WXGMenuMorphMaterial alloc] initWithFrame:CGRectZero];[_bodyHost addSubview:_material];
        _inkHost=[UIView new];[_bodyHost addSubview:_inkHost];
        [self addSubview:_material.rimView];
        _rimClip=[CAShapeLayer layer];_rimClip.name=@"morph.rim.clip";_rimClip.fillColor=UIColor.whiteColor.CGColor;
        _material.rimView.layer.mask=_rimClip;
    }
    return self;
}
- (BOOL)needsRimBackdropImage {return _material.needsRimBackdropImage;}
- (void)setRimBackdropImage:(UIImage *)image inRect:(CGRect)rect {
    [_material setRimBackdropImage:image inRect:rect];
    _lastBounds=CGRectNull;
}
- (CGFloat)opticalSessionStep {return _material.opticalSessionStep;}
- (void)setOpticalSessionStep:(CGFloat)step {
    if(_material.opticalSessionStep==step)return;
    _material.opticalSessionStep=step;_lastBounds=CGRectNull;
}
- (void)stripAnimations {
    [self.layer removeAllAnimations];
    [_movingShadow removeAllAnimations];
    [_movingShadowMask removeAllAnimations];
    [_bodyHost.layer removeAllAnimations];
    [_bodyMask removeAllAnimations];
    [_inkHost.layer removeAllAnimations];
    [_rimClip removeAllAnimations];
    [_touchFace removeAllAnimations];
    [_touchEdge removeAllAnimations];
    [_edgeStrip removeAllAnimations];
    [_material stripAnimations];
}
- (void)placeButtonRect:(CGRect)button {
    CGFloat r=MIN(button.size.width,button.size.height)*.5,side=r*2.;
    [self placeMenuRect:button radiusX:r radiusY:r sourceRect:button radius:r smoothing:0
        optics:(WXGMenuMorphSurfaceOptics){0.,0.,0.,0.,side,side}];
}
- (void)placeMenuRect:(CGRect)menu radiusX:(CGFloat)rx radiusY:(CGFloat)ry
           sourceRect:(CGRect)source radius:(CGFloat)radius smoothing:(CGFloat)smoothing {
    CGFloat srcSide=MIN(source.size.width,source.size.height);
    CGFloat menuSide=MIN(menu.size.width,menu.size.height);
    [self placeMenuRect:menu radiusX:rx radiusY:ry sourceRect:source radius:radius smoothing:smoothing
        optics:(WXGMenuMorphSurfaceOptics){smoothing>0?.5:1.,0.,0.,0.,srcSide>0?srcSide:menuSide,menuSide}];
}
- (void)placeMenuRect:(CGRect)menu radiusX:(CGFloat)rx radiusY:(CGFloat)ry
           sourceRect:(CGRect)source radius:(CGFloat)radius smoothing:(CGFloat)smoothing
               optics:(WXGMenuMorphSurfaceOptics)optics {
    if(CGRectIsEmpty(menu) || CGRectIsEmpty(self.bounds))return;
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    NSUInteger revision=WXGConfigRevision();
    UIUserInterfaceStyle appearance=self.traitCollection.userInterfaceStyle;
    CGPoint opticalOrigin=(smoothing>0 && _material.opticalSessionStep>0 && self.window)?
        [self convertPoint:CGPointZero toView:self.window]:CGPointZero;
    BOOL sameOptics=fabs(optics.contentProgress-_lastOptics.contentProgress)<.0001 &&
        fabs(optics.lensHeight-_lastOptics.lensHeight)<.01 &&
        fabs(optics.lensAmount-_lastOptics.lensAmount)<.01 &&
        fabs(optics.portalBlur-_lastOptics.portalBlur)<.01 &&
        fabs(optics.triggerSide-_lastOptics.triggerSide)<.01 &&
        fabs(optics.menuSide-_lastOptics.menuSide)<.01;
    if(sameOptics && CGPointEqualToPoint(opticalOrigin,_lastOpticalOrigin) && CGRectEqualToRect(self.bounds,_lastBounds) &&
        CGRectEqualToRect(menu,_lastMenu) && CGRectEqualToRect(source,_lastSource) && rx==_lastRX && ry==_lastRY &&
        radius==_lastRadius && smoothing==_lastSmoothing && scale==_lastScale && revision==_revision && appearance==_appearance)return;
    _lastOptics=optics;_lastOpticalOrigin=opticalOrigin;_lastBounds=self.bounds;_lastMenu=menu;_lastSource=source;
    _lastRX=rx;_lastRY=ry;_lastRadius=radius;_lastSmoothing=smoothing;_lastScale=scale;_revision=revision;_appearance=appearance;
    // During active Gaussian smoothing, trace the fine contour directly from
    // the cubic B-spline of the window-anchored session field so the body/rim
    // silhouette matches Metal's foreground coverage without 16-tap truncation.
    BOOL hasSource=MIN(source.size.width,source.size.height)>=.01;
    CGRect extent=hasSource?CGRectUnion(menu,source):menu;
    CGFloat x=extent.origin.x,y=extent.origin.y;
    const WXGMenuMorphField *session=(smoothing>0 && _material.opticalSessionStep>0 && self.window)?
        [_material prepareSessionFieldForMenu:WXGMenuMorphFieldBoxFromRect(menu,rx) radiusY:(float)ry
            source:WXGMenuMorphFieldBoxFromRect(source,radius) smoothing:(float)smoothing windowOrigin:opticalOrigin]:NULL;
    WXGMenuMorphField field;
    if(session) {
        CGFloat step=MIN(2.5,MAX(1.25,MAX(extent.size.width,extent.size.height)/56.));
        WXGMenuMorphFieldSampleSession(&field,WXGMenuMorphFieldBoxFromRect(menu,rx),(float)ry,
            WXGMenuMorphFieldBoxFromRect(source,radius),(float)smoothing,(float)step,session);
    }else {
        CGFloat step=MIN(5.,MAX(1.25,MAX(extent.size.width,extent.size.height)/46.));
        WXGMenuMorphFieldBuildMode(&field,WXGMenuMorphFieldBoxFromRect(CGRectOffset(menu,-x,-y),rx),ry,
            WXGMenuMorphFieldBoxFromRect(CGRectOffset(source,-x,-y),radius),smoothing,step,WXGMorphFieldGeometry);
        WXGMenuMorphFieldTranslate(&field,x,y);
    }
    // At rest the union is exactly the trigger circle. Use its analytic
    // outline for both face and rim instead of a smoothed sampling grid.
    CGFloat half=menu.size.width*.5;
    BOOL circle=smoothing==0 && CGRectEqualToRect(menu,source) && menu.size.height==menu.size.width &&
                radius==half && rx==half && ry==half;
    _currentOutline=circle?[UIBezierPath bezierPathWithOvalInRect:menu]:WXGMenuMorphMaskPath(&field);
    CGRect material=CGPathGetPathBoundingBox(_currentOutline.CGPath);
    if(CGRectIsEmpty(material))return;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        _bodyHost.frame=self.bounds;_bodyMask.frame=_bodyHost.bounds;_bodyMask.contentsScale=scale;
        _inkHost.frame=_bodyHost.bounds;_bodyMask.path=_currentOutline.CGPath;
        _movingShadow.frame=self.bounds;_movingShadowMask.frame=self.bounds;
        [_material applyField:&field sessionField:session bounds:material outline:_currentOutline optics:optics];
        CGRect local=_material.rimView.bounds;_rimClip.frame=local;_rimClip.contentsScale=scale;
        CGAffineTransform shift=CGAffineTransformMakeTranslation(-material.origin.x,-material.origin.y);
        CGPathRef path=CGPathCreateCopyByTransformingPath(_currentOutline.CGPath,&shift);
        _rimClip.path=path;CGPathRelease(path);
        if(_edgeStrip)_edgeStrip.path=_rimClip.path;
        [self placeShadowAround:material];
        [CATransaction commit];
    }];
}
- (void)placeTouchLight:(CGPoint)point strength:(CGFloat)strength {
    if(strength<=.001) {
        _touchFace.hidden=YES;_touchEdge.hidden=YES;
        return;
    }
    if(!_touchFace) {
        _touchFace=[CALayer layer];_touchEdge=[CALayer layer];
        _touchFace.name=@"morph.press.face";_touchEdge.name=@"morph.press.edge";
        _touchFace.compositingFilter=@"plusL";_touchEdge.compositingFilter=@"plusL";
        _touchFace.backgroundColor=[UIColor colorWithWhite:1 alpha:.018].CGColor;
        _touchEdge.backgroundColor=[UIColor colorWithWhite:1 alpha:.12*.45].CGColor;
        _facePool=[CALayer layer];_edgePool=[CALayer layer];
        _facePool.contents=_edgePool.contents=(__bridge id)WXGMenuLightDisc(YES).CGImage;
        // Pool is exp(-r²/2sigma²), sigma = 80 points, out to four sigma.
        _facePool.bounds=_edgePool.bounds=CGRectMake(0,0,640,640);
        _facePool.opacity=.03/(1.-.018);
        _edgePool.opacity=.12*.55/(1.-.12*.45);
        [_touchFace addSublayer:_facePool];[_touchEdge addSublayer:_edgePool];
        [_bodyHost.layer insertSublayer:_touchFace below:_inkHost.layer];
        [_material.rimView.layer addSublayer:_touchEdge];
        _edgeStrip=[CAShapeLayer layer];_edgeStrip.fillColor=nil;
        _edgeStrip.strokeColor=UIColor.whiteColor.CGColor;_edgeStrip.lineJoin=kCALineJoinRound;
        _edgeStrip.lineWidth=1.5;_edgeStrip.path=_rimClip.path;_touchEdge.mask=_edgeStrip;
    }
    _touchFace.hidden=NO;_touchFace.frame=self.bounds;
    _touchFace.opacity=strength;_facePool.position=point;
    // Use the same contour and outside clip as the existing rim. Respect
    // surfaces whose saved material suppresses the rim.
    UIUserInterfaceStyle appearance=self.traitCollection.userInterfaceStyle;
    if(_lightRevision!=_revision || _lightAppearance!=appearance) {
        _lightRevision=_revision;_lightAppearance=appearance;
        WXGConfig *config=WXGConfig.shared;BOOL dark=appearance==UIUserInterfaceStyleDark;
        if([config rimStyleForScope:WXGGlassScopeOther]==WXGRimStyleGlow) {
            _touchRimOpacity=0;
            for(int k=0;k<WXGRimGlowCount;k++) {
                WXGRimGlowShape s=[config rimGlowForScope:WXGGlassScopeOther index:k dark:dark];
                if(s.width>0)_touchRimOpacity=MAX(_touchRimOpacity,s.alpha);
            }
        }else{
            WXGRim26Settings s=[config rim26ForScope:WXGGlassScopeOther dark:dark];
            _touchRimOpacity=s.height>0?s.opacity:0;
        }
    }
    _touchEdge.hidden=_touchRimOpacity<=.001;
    _touchEdge.frame=_material.rimView.bounds;_edgeStrip.frame=_touchEdge.bounds;
    _edgeStrip.contentsScale=_rimClip.contentsScale;
    _touchEdge.opacity=strength*_touchRimOpacity;
    _edgePool.position=[_material.rimView convertPoint:point fromView:self];
}
- (void)placeShadowAround:(CGRect)material {
    _movingShadow.hidden=YES;
    WXGDropShadowSettings style=[WXGConfig.shared dropShadowForScope:WXGGlassScopeOther dark:self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark];
    if(style.opacity<=.002)return;
    UIBezierPath *cutout=[UIBezierPath bezierPathWithRect:self.bounds];
    [cutout appendPath:_currentOutline];
    _movingShadowMask.path=cutout.CGPath;
    _movingShadow.shadowOpacity=style.opacity;
    _movingShadow.shadowRadius=style.blur;
    _movingShadow.shadowOffset=CGSizeMake(0,style.offset);
    CGAffineTransform scale=CGAffineTransformMakeTranslation(CGRectGetMidX(material),CGRectGetMidY(material));
    scale=CGAffineTransformScale(scale,MAX(.01,1.+2.*style.spread/material.size.width),MAX(.01,1.+2.*style.spread/material.size.height));
    scale=CGAffineTransformTranslate(scale,-CGRectGetMidX(material),-CGRectGetMidY(material));
    CGPathRef shadow=CGPathCreateCopyByTransformingPath(_currentOutline.CGPath,&scale);
    _movingShadow.shadowPath=shadow;
    CGPathRelease(shadow);
    _movingShadow.hidden=NO;
}

- (NSDictionary *)presentationEvidence {
    CALayer *rim=_material.rimView.layer,*shown=rim.presentationLayer;
    return @{@"surface":[NSString stringWithFormat:@"%p",self],@"body":[NSString stringWithFormat:@"%p",_material],
        @"rim":[NSString stringWithFormat:@"%p",rim],@"clip":[NSString stringWithFormat:@"%p",_rimClip],
        @"window":@(self.window!=nil),@"rimVisible":@(!rim.hidden && !self.hidden && rim.opacity>0),
        @"rimAboveInk":@([self.subviews indexOfObject:_material.rimView]>[self.subviews indexOfObject:_bodyHost]),
        @"maskAttached":@(rim.mask==_rimClip && _bodyHost.layer.mask==_bodyMask),
        @"rimFrame":NSStringFromCGRect(rim.frame),@"clipBounds":NSStringFromCGRect(_rimClip.bounds),
        @"pathBounds":NSStringFromCGRect(_rimClip.path?CGPathGetPathBoundingBox(_rimClip.path):CGRectZero),
        @"presentedRimFrame":NSStringFromCGRect(shown.frame),@"edge":_material.rimEvidence};
}
@end

@interface WXGMenuMorphView ()
- (BOOL)drawGlass;
@end

enum {WXGMenuMorphSurfaceRing=3};

@implementation WXGMenuMorphView {
    WXGMenuMorphSurface *_surface;
    __weak WXGSurface *_sourceButton;
    BOOL _sessionUsesUIKit;
    CALayer *_metal;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLComputePipelineState> _fieldPipeline,_smoothPipeline,_blurHPipeline,_blurVPipeline;
    id<MTLTexture> _texture,_rowsTexture,_triggerTexture;
    id<MTLTexture> _inkScratch,_inkRowsBlur,_inkTriggerBlur;
    CVMetalTextureCacheRef _surfaceCache;
    CVPixelBufferRef _surfaceBuffers[WXGMenuMorphSurfaceRing];
    CVMetalTextureRef _surfaceMetalRefs[WXGMenuMorphSurfaceRing];
    id<MTLTexture> _surfaceTextures[WXGMenuMorphSurfaceRing];
    BOOL _slotBusy[WXGMenuMorphSurfaceRing];
    NSLock *_slotLock;
    NSUInteger _nextSurfaceSlot;
    uint64_t _surfaceGeneration;
    CGSize _drawableSize;
    UIImage *_rowsImage,*_triggerImage;
    NSArray<id<MTLTexture>> *_fieldTextures;
    dispatch_semaphore_t _inFlight;
    CGRect _menu,_sourceLobe,_lastCommittedSurfaceBounds;
    CGRect _highlightRect,_cachedMenu;
    CGFloat _highlightOpacity,_lightStrength,_plateLightX,_triggerSide,_menuSide;
    CGPoint _lightPoint;
    CALayer *_plate,*_plateShine;
    BOOL _hasCachedInk,_needsOpenInk,_wantsOpenInk,_plateDark,_plateTintReady,_hasLastDrawnPose;
    NSUInteger _openInkReuses,_inkSubmissions;
    WXGMenuMorphFrame _frame;
    WXGMenuMorphUniforms _lastDrawnUniforms;
    CGSize _lastDrawnDrawableSize;
    CGPoint _lastDrawnWinOrigin;
    CGFloat _lastDrawnSessionStep;
    BOOL _hasFrame,_showsForeground,_drawableHasForeground,_rowsNeedMips,_triggerNeedsMips;
    BOOL _stableFrameMissed,_stableRetryPending;
    NSUInteger _stableRetryCount;
}

- (void)releaseSurfaceTargets {
    [_slotLock lock];
    ++_surfaceGeneration;
    memset(_slotBusy,0,sizeof(_slotBusy));
    _nextSurfaceSlot=0;
    [_slotLock unlock];
    for(int i=0;i<WXGMenuMorphSurfaceRing;i++) {
        _surfaceTextures[i]=nil;
        if(_surfaceMetalRefs[i]){CFRelease(_surfaceMetalRefs[i]);_surfaceMetalRefs[i]=NULL;}
        if(_surfaceBuffers[i]){CVPixelBufferRelease(_surfaceBuffers[i]);_surfaceBuffers[i]=NULL;}
    }
    if(_surfaceCache)CVMetalTextureCacheFlush(_surfaceCache,0);
}

- (void)dealloc {
    [self releaseSurfaceTargets];
    if(_surfaceCache){CFRelease(_surfaceCache);_surfaceCache=NULL;}
}

- (BOOL)ensureSurfaceTargetsForSize:(CGSize)size {
    NSUInteger width=(NSUInteger)size.width,height=(NSUInteger)size.height;
    if(width<1 || height<1 || !_device)return NO;
    if(_surfaceTextures[0].width==width && _surfaceTextures[0].height==height)return YES;
    [self releaseSurfaceTargets];
    if(!_surfaceCache && CVMetalTextureCacheCreate(kCFAllocatorDefault,NULL,_device,NULL,&_surfaceCache)!=kCVReturnSuccess)
        return NO;
    NSDictionary *attrs=@{
        (id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey:@(width),
        (id)kCVPixelBufferHeightKey:@(height),
        (id)kCVPixelBufferMetalCompatibilityKey:@YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey:@{}
    };
    CGColorSpaceRef srgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFDataRef icc=srgb?CGColorSpaceCopyICCData(srgb):NULL;
    if(srgb)CGColorSpaceRelease(srgb);
    BOOL ok=YES;
    for(int i=0;i<WXGMenuMorphSurfaceRing;i++) {
        CVPixelBufferRef pb=NULL;
        if(CVPixelBufferCreate(kCFAllocatorDefault,width,height,kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attrs,&pb)!=kCVReturnSuccess || !pb){ok=NO;break;}
        IOSurfaceRef ios=CVPixelBufferGetIOSurface(pb);
        if(!ios){CVPixelBufferRelease(pb);ok=NO;break;}
        if(icc)IOSurfaceSetValue(ios,CFSTR("IOSurfaceColorSpace"),icc);
        CVMetalTextureRef cvTex=NULL;
        if(CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,_surfaceCache,pb,NULL,
            MTLPixelFormatBGRA8Unorm,width,height,0,&cvTex)!=kCVReturnSuccess || !cvTex) {
            CVPixelBufferRelease(pb);ok=NO;break;
        }
        id<MTLTexture> mtlTex=CVMetalTextureGetTexture(cvTex);
        if(!mtlTex){CFRelease(cvTex);CVPixelBufferRelease(pb);ok=NO;break;}
        _surfaceBuffers[i]=pb;
        _surfaceMetalRefs[i]=cvTex;
        _surfaceTextures[i]=mtlTex;
    }
    if(icc)CFRelease(icc);
    if(!ok){[self releaseSurfaceTargets];return NO;}
    return YES;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO;
        self.accessibilityElementsHidden=YES;
        self.opaque=NO;
        _lastCommittedSurfaceBounds=CGRectNull;
        _device=WXGSharedDevice();
        _slotLock=[NSLock new];
        _inFlight=dispatch_semaphore_create(WXGMenuMorphSurfaceRing);
        _metal=[CALayer layer];
        _metal.name=@"morph.foreground.metal";
        _metal.anchorPoint=CGPointZero;
        _metal.opaque=NO;
        __weak typeof(self) weakSelf=self;
        WXGPrepareMenuMorphMetal(NO,^(id<MTLRenderPipelineState> state,id<MTLComputePipelineState> field,
            id<MTLComputePipelineState> smooth,id<MTLComputePipelineState> blurH,id<MTLComputePipelineState> blurV,
            id<MTLCommandQueue> commandQueue){
            WXGMenuMorphView *view=weakSelf;
            if(!view)return;
            view->_pipeline=state;
            view->_fieldPipeline=field;
            view->_smoothPipeline=smooth;
            view->_blurHPipeline=blurH;
            view->_blurVPipeline=blurV;
            view->_queue=commandQueue;
            if(!state || !commandQueue || !view->_hasFrame)return;
            if(view->_showsForeground) {
                if(view.requestFrame)view.requestFrame();
            }else [view drawGlass];
        });
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    CGSize size=CGSizeMake(ceil(self.bounds.size.width*scale),ceil(self.bounds.size.height*scale));
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(_surface.superview==self)_surface.frame=self.bounds;
        _fallbackForeground.frame=self.bounds;
        _metal.position=self.bounds.origin;
        _metal.bounds=(CGRect){CGPointZero,self.bounds.size};
        _metal.contentsScale=scale;
        if(!CGSizeEqualToSize(_drawableSize,size)) {
            _drawableSize=size;
            [self releaseSurfaceTargets];
            _fieldTextures=nil;
            _inkScratch=nil;_inkRowsBlur=nil;_inkTriggerBlur=nil;
            _stableRetryCount=0;
            _needsOpenInk=YES;
            _hasLastDrawnPose=NO;
        }
        [CATransaction commit];
    }];
}

- (UIBezierPath *)currentOutline {return _surface.currentOutline;}
- (void)useSurfaceFromButton:(WXGSurface *)button {
    if(_surface)return;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        WXGMenuMorphSurface *lent=[button borrowHomeMenuMorphSurface];
        _sourceButton=lent?button:nil;
        if(lent)_sourceAtPickup=lent.presentationEvidence;
        _surface=lent?:[[WXGMenuMorphSurface alloc] initWithFrame:self.bounds];
        [_surface stripAnimations];
        _surface.transform=CGAffineTransformIdentity;
        _surface.frame=self.bounds;
        [self insertSubview:_surface atIndex:0];
        _plate=[CALayer layer];_plate.name=@"morph.selection.plate";
        _plate.anchorPoint=CGPointZero;_plate.cornerCurve=kCACornerCurveContinuous;_plate.masksToBounds=YES;_plate.hidden=YES;
        [_surface.inkHost.layer addSublayer:_plate];
        [_metal removeAllAnimations];
        _metal.contents=nil;
        [_surface.inkHost.layer addSublayer:_metal];
        if(_fallbackForeground)[_surface.inkHost addSubview:_fallbackForeground];
        _hasLastDrawnPose=NO;
        [CATransaction commit];
    }];
}
- (void)setOpticalSessionBounds:(CGRect)windowBounds {
    // The original session fixes its Gaussian spacing at a 48pt margin on
    // each side of the union of the original button and destination menu.
    CGFloat longest=MAX(windowBounds.size.width,windowBounds.size.height);
    [_surface setOpticalSessionStep:MAX(5.,(longest+96.)/64.)];
}
- (void)setSessionTriggerSide:(CGFloat)triggerSide menuSide:(CGFloat)menuSide {
    _triggerSide=triggerSide;_menuSide=menuSide;
}
- (void)setFallbackForeground:(UIView *)fallbackForeground {
    [UIView performWithoutAnimation:^{
        if(_fallbackForeground!=fallbackForeground)[_fallbackForeground removeFromSuperview];
        _fallbackForeground=fallbackForeground;
        if(fallbackForeground && _surface && fallbackForeground.superview!=_surface.inkHost)
            [_surface.inkHost addSubview:fallbackForeground];
        _fallbackForeground.frame=self.bounds;
    }];
}
- (NSDictionary *)returnSurfaceToButton {
    if(!_surface)return nil;
    __block NSDictionary *returned=nil;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        [_surface placeTouchLight:CGPointZero strength:0];
        [_surface setOpticalSessionStep:0];
        [_plate removeFromSuperlayer];[_metal removeFromSuperlayer];[_fallbackForeground removeFromSuperview];
        [_metal removeAllAnimations];
        _metal.contents=nil;
        _plate=nil;_plateShine=nil;_plateTintReady=NO;_hasCachedInk=NO;_hasLastDrawnPose=NO;_drawableHasForeground=NO;
        _lastCommittedSurfaceBounds=CGRectNull;_triggerSide=0;_menuSide=0;
        _metal.affineTransform=CGAffineTransformIdentity;
        [_surface stripAnimations];
        if(_sourceButton)[_sourceButton returnHomeMenuMorphSurface:_surface];
        else [_surface removeFromSuperview];
        returned=_sourceButton && _surface.superview==_sourceButton?_surface.presentationEvidence:nil;
        _surface=nil;_sourceButton=nil;
        [CATransaction commit];
    }];
    return returned;
}
- (NSDictionary *)presentationEvidence {
    if(!_surface)return @{};
    NSMutableDictionary *e=[_surface.presentationEvidence mutableCopy];
    e[@"sourceBorrowed"]=@(_sourceButton!=nil);
    e[@"sourceMasked"]=@(_sourceButton.layer.mask!=nil);
    e[@"ink"]=_drawableHasForeground?@"metal":@"uikit";e[@"inkHostAttached"]=@(_metal.superlayer==_surface.inkHost.layer);
    e[@"cachedOpenInk"]=@(_hasCachedInk);e[@"openInkReuses"]=@(_openInkReuses);e[@"inkSubmissions"]=@(_inkSubmissions);
    e[@"selectionRect"]=NSStringFromCGRect(_highlightRect);e[@"selectionOpacity"]=@(_highlightOpacity);
    e[@"menuLightStrength"]=@(_lightStrength);
    return e;
}

// Only the software R26 colour fallback needs to read the page. Live glass,
// glow and Metal foreground use their own layers and textures.
- (BOOL)captureBackdropFromView:(UIView *)source excludingViews:(NSArray<UIView *> *)excluded {
    if(!_surface.needsRimBackdropImage)return YES;
    if(!source.window || source.window!=self.window || !self.superview || CGRectIsEmpty(self.bounds))return NO;
    CGRect sample=CGRectIntersection(CGRectInset(self.bounds,-24.,-24.),[self convertRect:source.bounds fromView:source]);
    if(CGRectIsEmpty(sample))return NO;
    CGPoint origin=[self convertPoint:CGPointZero fromView:source];
    CGPoint x=[self convertPoint:CGPointMake(1,0) fromView:source];
    CGPoint y=[self convertPoint:CGPointMake(0,1) fromView:source];
    CGAffineTransform mapping=CGAffineTransformMake(x.x-origin.x,x.y-origin.y,y.x-origin.x,y.y-origin.y,
        origin.x-sample.origin.x,origin.y-sample.origin.y);
    NSMutableArray<CALayer *> *temporarilyHidden=[NSMutableArray array];
    NSArray<UIView *> *views=[(excluded?:@[]) arrayByAddingObject:self];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=MIN(self.window.screen.scale,1.5);
    format.opaque=YES;
    format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    UIColor *base=[UIColor colorWithWhite:dark?.11:.96 alpha:1.];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:sample.size format:format];
    UIImage *image=nil;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        for(UIView *view in views) {
            CALayer *layer=view.layer;
            if(view!=source && [view isDescendantOfView:source] && !layer.hidden) {
                [temporarilyHidden addObject:layer];
                layer.hidden=YES;
            }
        }
        image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
            CGContextSetFillColorWithColor(context.CGContext,base.CGColor);
            CGContextFillRect(context.CGContext,(CGRect){CGPointZero,sample.size});
            CGContextConcatCTM(context.CGContext,mapping);
            CGContextTranslateCTM(context.CGContext,source.bounds.origin.x,source.bounds.origin.y);
            [source.layer renderInContext:context.CGContext];
        }];
    } @catch(__unused NSException *exception) {
        image=nil;
    } @finally {
        for(CALayer *layer in temporarilyHidden)layer.hidden=NO;
        [CATransaction commit];
    }
    if(!image.CGImage)return NO;
    [_surface setRimBackdropImage:image inRect:sample];
    return YES;
}

- (void)setForegroundRowsImage:(UIImage *)rowsImage triggerImage:(UIImage *)triggerImage {
    if(_rowsImage!=rowsImage) {
        _rowsImage=rowsImage;_rowsTexture=WXGMenuPremultipliedTexture(rowsImage,_device);
        _rowsNeedMips=_rowsTexture.mipmapLevelCount>1;
        _needsOpenInk=YES;
        _hasLastDrawnPose=NO;
    }
    if(_triggerImage!=triggerImage) {
        _triggerImage=triggerImage;_triggerTexture=WXGMenuPremultipliedTexture(triggerImage,_device);
        _triggerNeedsMips=_triggerTexture.mipmapLevelCount>1;
        _hasLastDrawnPose=NO;
    }
    // These shader bindings are sampled only when the corresponding ink or
    // smoothed-field flag is set. An existing texture fills unused slots.
    _texture=_rowsTexture?:_triggerTexture;
}

- (void)stageHighlightedRowRect:(CGRect)rect opacity:(CGFloat)opacity {
    _highlightRect=rect;
    _highlightOpacity=CGRectIsEmpty(rect)?0.:MAX(0.,MIN(1.,opacity));
}
- (void)stageMenuLightAtPoint:(CGPoint)point inParent:(UIView *)parent artworkX:(CGFloat)artworkX strength:(CGFloat)strength {
    _lightPoint=[self convertPoint:point fromView:parent];
    _plateLightX=artworkX;
    _lightStrength=MAX(0,MIN(1,strength));
}
- (void)setHighlightedRowRect:(CGRect)rect opacity:(CGFloat)opacity {
    [self stageHighlightedRowRect:rect opacity:opacity];
    if(_hasCachedInk) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        [self placeCachedOpenInk];
        [CATransaction commit];
    }
}

// At full expansion the foreground shader has zero warp and blur. Keep its
// actual, already-presented text and icon pixels. Move that same drawable
// and the continuous selection plate as independent compositor layers.
- (void)placeCachedOpenInk {
    if(!_hasCachedInk || CGRectIsEmpty(_cachedMenu))return;
    CGFloat sx=_menu.size.width/_cachedMenu.size.width,sy=_menu.size.height/_cachedMenu.size.height;
    _metal.affineTransform=CGAffineTransformMake(sx,0,0,sy,_menu.origin.x-sx*_cachedMenu.origin.x,
        _menu.origin.y-sy*_cachedMenu.origin.y);
    _plate.hidden=_highlightOpacity<=.001;
    if(_plate.hidden || !_rowsImage)return;
    CGFloat xScale=_menu.size.width/MAX(1.,_rowsImage.size.width),yScale=_menu.size.height/MAX(1.,_rowsImage.size.height);
    CGSize size=_highlightRect.size;
    _plate.bounds=(CGRect){CGPointZero,size};_plate.cornerRadius=MIN(size.width,size.height)*.5;
    _plate.position=CGPointMake(_menu.origin.x+_highlightRect.origin.x*xScale,_menu.origin.y+_highlightRect.origin.y*yScale);
    _plate.affineTransform=CGAffineTransformMakeScale(xScale,yScale);
    _plate.opacity=_highlightOpacity;
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    if(!_plateTintReady || _plateDark!=dark) {
        _plateTintReady=YES;_plateDark=dark;
        UIColor *tint=dark?[UIColor colorWithRed:235./255 green:235./255 blue:245./255 alpha:1]:
            [UIColor colorWithRed:60./255 green:60./255 blue:67./255 alpha:1];
        _plate.backgroundColor=[tint colorWithAlphaComponent:dark?.155:.09].CGColor;
        if(dark && !_plateShine) {
            _plateShine=[CALayer layer];_plateShine.backgroundColor=tint.CGColor;
            _plateShine.mask=[CALayer layer];_plateShine.mask.contents=(__bridge id)WXGMenuLightDisc(NO).CGImage;
            _plateShine.opacity=.03/(1.-.155);[_plate addSublayer:_plateShine];
        }
        _plateShine.hidden=!dark;
    }
    if(dark) {
        CGFloat radius=size.width*.62;
        CGFloat lightX=MAX(0.,MIN(size.width,_plateLightX-_highlightRect.origin.x));
        _plateShine.frame=CGRectMake(lightX-radius,size.height*.5-radius,2*radius,2*radius);
        _plateShine.mask.frame=_plateShine.bounds;
    }
}

// Blur the signed distance and gradient together on the same window-anchored
// lattice and Gaussian kernel cutoff as the glass material and reference app.
- (id<MTLTexture>)encodeSmoothedField:(id<MTLCommandBuffer>)command uniforms:(WXGMenuMorphUniforms *)uniforms {
    if(!_fieldPipeline || !_smoothPipeline || _frame.smoothing<=0)return nil;
    float sigma=(float)_frame.smoothing;
    float rx=fmaxf(uniforms->radii[0],.01f),ry=fmaxf(uniforms->radii[1],.01f);
    float ratio=fmaxf(rx,ry)/fminf(rx,ry);
    BOOL hasSource=MIN(_sourceLobe.size.width,_sourceLobe.size.height)>=.01;
    float grow=hasSource?sigma*.25f*ratio:0.f;
    CGPoint winOrigin=self.window?[self convertPoint:CGPointZero toView:self.window]:CGPointZero;
    CGRect unionRect=hasSource?CGRectUnion(_menu,_sourceLobe):_menu;
    float leftW=(float)(CGRectGetMinX(unionRect)+winOrigin.x)-grow;
    float topW=(float)(CGRectGetMinY(unionRect)+winOrigin.y)-grow;
    float rightW=(float)(CGRectGetMaxX(unionRect)+winOrigin.x)+grow;
    float bottomW=(float)(CGRectGetMaxY(unionRect)+winOrigin.y)+grow;
    float gridStep=_surface.opticalSessionStep>0?(float)_surface.opticalSessionStep:
        (float)MAX(5.,MAX(self.bounds.size.width,self.bounds.size.height)/64.);
    float step=fmaxf(gridStep,fmaxf(rightW-leftW,bottomW-topW)/64.f);
    float localSigma=sigma/step;
    float weights[WXGMenuMorphFieldKernel+1];
    int radius=WXGMenuMorphKernel(localSigma,WXGMorphFieldSessionTexture,weights);
    if(radius<=0)return nil;

    float originW=floorf(leftW/step)*step-(float)(radius+2)*step;
    float originTopW=floorf(topW/step)*step-(float)(radius+2)*step;
    NSUInteger neededW=(NSUInteger)MAX(16,(int)ceilf((rightW-originW)/step)+radius+3);
    NSUInteger neededH=(NSUInteger)MAX(16,(int)ceilf((bottomW-originTopW)/step)+radius+3);
    if(!_fieldTextures || _fieldTextures.firstObject.width<neededW || _fieldTextures.firstObject.height<neededH) {
        NSUInteger allocW=MAX(96u,(neededW+31u)&~31u),allocH=MAX(96u,(neededH+31u)&~31u);
        MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
            width:allocW height:allocH mipmapped:NO];
        descriptor.storageMode=MTLStorageModePrivate;
        descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        id<MTLTexture> raw=[_device newTextureWithDescriptor:descriptor];
        id<MTLTexture> horizontal=[_device newTextureWithDescriptor:descriptor];
        id<MTLTexture> gaussian=[_device newTextureWithDescriptor:descriptor];
        if(!raw || !horizontal || !gaussian)return nil;
        _fieldTextures=@[raw,horizontal,gaussian];
    }
    NSUInteger width=_fieldTextures.firstObject.width,height=_fieldTextures.firstObject.height;
    uniforms->optics[3]=(float)width;
    uniforms->field=(WXGMenuFloat4){(float)(originW-winOrigin.x),(float)(originTopW-winOrigin.y),step,(float)height};
    MTLSize groups=MTLSizeMake((width+7)/8,(height+7)/8,1),lanes=MTLSizeMake(8,8,1);
    id<MTLComputeCommandEncoder> compute=[command computeCommandEncoder];
    if(!compute){uniforms->field=(WXGMenuFloat4){0,0,0,0};uniforms->optics[3]=0.f;return nil;}
    [compute setComputePipelineState:_fieldPipeline];
    [compute setBytes:uniforms length:sizeof(*uniforms) atIndex:0];
    [compute setTexture:_fieldTextures[0] atIndex:0];
    [compute dispatchThreadgroups:groups threadsPerThreadgroup:lanes];
    [compute endEncoding];
    for(NSUInteger axis=0;axis<2;axis++) {
        compute=[command computeCommandEncoder];
        if(!compute){uniforms->field=(WXGMenuFloat4){0,0,0,0};uniforms->optics[3]=0.f;return nil;}
        WXGMenuFloat4 settings={(float)(axis==0),(float)(axis==1),localSigma,(float)radius};
        [compute setComputePipelineState:_smoothPipeline];
        [compute setBytes:&settings length:sizeof(settings) atIndex:0];
        [compute setTexture:_fieldTextures[axis] atIndex:0];
        [compute setTexture:_fieldTextures[axis+1] atIndex:1];
        [compute dispatchThreadgroups:groups threadsPerThreadgroup:lanes];
        [compute endEncoding];
    }
    return _fieldTextures.lastObject;
}

- (BOOL)ensureInkBlurTexturesForWidth:(NSUInteger)width height:(NSUInteger)height {
    if(_inkScratch.width==width && _inkScratch.height==height && _inkRowsBlur && _inkTriggerBlur)return YES;
    MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:width height:height mipmapped:NO];
    desc.storageMode=MTLStorageModePrivate;
    desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    _inkScratch=[_device newTextureWithDescriptor:desc];
    _inkRowsBlur=[_device newTextureWithDescriptor:desc];
    _inkTriggerBlur=[_device newTextureWithDescriptor:desc];
    return _inkScratch && _inkRowsBlur && _inkTriggerBlur;
}

- (WXGMenuFloat4)encodeInkBlur:(id<MTLCommandBuffer>)command source:(id<MTLTexture>)src destination:(id<MTLTexture>)dst
                          rect:(CGRect)inkRect sigmaX:(float)sigmaX sigmaY:(float)sigmaY pixelX:(float)pixelX pixelY:(float)pixelY {
    if(!_blurHPipeline || !_blurVPipeline || !src || !dst || !_inkScratch || CGRectIsEmpty(inkRect))
        return (WXGMenuFloat4){0,0,0,0};
    int texW=(int)dst.width,texH=(int)dst.height;
    float marginX=ceilf(3.4f*sigmaX+2.f),marginY=ceilf(3.4f*sigmaY+2.f);
    int hMinX=MAX(0,(int)floorf(((float)CGRectGetMinX(inkRect)-marginX)/pixelX));
    int hMaxX=MIN(texW,(int)ceilf(((float)CGRectGetMaxX(inkRect)+marginX)/pixelX));
    int hMinY=MAX(0,(int)floorf(((float)CGRectGetMinY(inkRect)-2.f)/pixelY));
    int hMaxY=MIN(texH,(int)ceilf(((float)CGRectGetMaxY(inkRect)+2.f)/pixelY));
    int vMinY=MAX(0,(int)floorf(((float)CGRectGetMinY(inkRect)-marginY)/pixelY));
    int vMaxY=MIN(texH,(int)ceilf(((float)CGRectGetMaxY(inkRect)+marginY)/pixelY));
    if(hMaxX<=hMinX || hMaxY<=hMinY || vMaxY<=vMinY)return (WXGMenuFloat4){0,0,0,0};

    const int maxRad=24;
    float stepPtX=sigmaX>.01f?fmaxf(pixelX,3.3f*sigmaX/(float)maxRad):pixelX;
    int radX=sigmaX>.01f?MIN(maxRad,(int)ceilf(3.3f*sigmaX/stepPtX)):0;
    float stepTex=stepPtX*((float)src.width/fmaxf(1.f,(float)inkRect.size.width));
    float lod=(src.mipmapLevelCount>1 && stepTex>1.35f)?
        fminf((float)(src.mipmapLevelCount-1),fminf(1.75f,log2f(stepTex*.65f))):0.f;
    float stepPtY=sigmaY>.01f?fmaxf(pixelY,3.3f*sigmaY/(float)maxRad):pixelY;
    int radY=sigmaY>.01f?MIN(maxRad,(int)ceilf(3.3f*sigmaY/stepPtY)):0;

    WXGMenuInkBlurUniforms hUni={
        WXGMenuFloatRect(inkRect),
        {(float)hMinX,(float)hMinY,(float)(hMaxX-hMinX),(float)(hMaxY-hMinY)},
        {pixelX,pixelY,sigmaX,1.f},
        {stepPtX,(float)radX,lod,0.f}
    };
    WXGMenuInkBlurUniforms vUni={
        WXGMenuFloatRect(inkRect),
        {(float)hMinX,(float)vMinY,(float)(hMaxX-hMinX),(float)(vMaxY-vMinY)},
        {pixelX,pixelY,sigmaY,1.f},
        {stepPtY,(float)radY,(float)hMinY,(float)hMaxY}
    };
    MTLSize lanes=MTLSizeMake(8,8,1);
    id<MTLComputeCommandEncoder> compute=[command computeCommandEncoder];
    if(!compute)return (WXGMenuFloat4){0,0,0,0};
    [compute setComputePipelineState:_blurHPipeline];
    [compute setBytes:&hUni length:sizeof(hUni) atIndex:0];
    [compute setTexture:src atIndex:0];
    [compute setTexture:_inkScratch atIndex:1];
    [compute dispatchThreadgroups:MTLSizeMake((NSUInteger)(hMaxX-hMinX+7)/8,(NSUInteger)(hMaxY-hMinY+7)/8,1)
            threadsPerThreadgroup:lanes];
    [compute endEncoding];

    compute=[command computeCommandEncoder];
    if(!compute)return (WXGMenuFloat4){0,0,0,0};
    [compute setComputePipelineState:_blurVPipeline];
    [compute setBytes:&vUni length:sizeof(vUni) atIndex:0];
    [compute setTexture:_inkScratch atIndex:0];
    [compute setTexture:dst atIndex:1];
    [compute dispatchThreadgroups:MTLSizeMake((NSUInteger)(hMaxX-hMinX+7)/8,(NSUInteger)(vMaxY-vMinY+7)/8,1)
            threadsPerThreadgroup:lanes];
    [compute endEncoding];
    return (WXGMenuFloat4){(float)hMinX,(float)vMinY,(float)hMaxX,(float)vMaxY};
}

- (BOOL)drawGlass {
    if(_sessionUsesUIKit || !_hasFrame || !self.window || self.hidden || CGRectIsEmpty(self.bounds))return NO;
    BOOL foreground=_showsForeground && (_rowsTexture || _triggerTexture) &&
        (!_rowsImage || _rowsTexture) && (!_triggerImage || _triggerTexture);
    CGSize drawSize=_drawableSize;
    if(!_texture || !_pipeline || !_queue || drawSize.width<1. || drawSize.height<1.)return NO;
    if(![self ensureSurfaceTargetsForSize:drawSize])return NO;
    float pixelX=(float)(self.bounds.size.width/drawSize.width),pixelY=(float)(self.bounds.size.height/drawSize.height);
    CGRect rowsInk=WXGMenuMorphZoomedRect(_menu,_frame.contentZoom),triggerInk=WXGMenuMorphZoomedRect(_sourceLobe,_frame.sourceZoom);
    CGFloat rowsScaleX=rowsInk.size.width/MAX(1.,_rowsImage.size.width),rowsScaleY=rowsInk.size.height/MAX(1.,_rowsImage.size.height);
    CGFloat rowsBlur=_frame.contentBlur/MAX(.25,MIN(rowsScaleX,rowsScaleY));
    CGFloat triggerScaleX=triggerInk.size.width/MAX(1.,_triggerImage.size.width),triggerScaleY=triggerInk.size.height/MAX(1.,_triggerImage.size.height);
    CGRect highlight=CGRectOffset(CGRectApplyAffineTransform(_highlightRect,CGAffineTransformMakeScale(rowsScaleX,rowsScaleY)),
        rowsInk.origin.x,rowsInk.origin.y);
    WXGGlassCurve curve=[WXGConfig.shared glassCurveForScope:WXGGlassScopeOther];
    float refractionScale=(float)WXGClamp(curve.amount/.8,0.,2.);
    float fgLensRamp=1.f;
    if(_frame.contentProgress<.28 && _frame.portalBlur<2.4) {
        float t=(float)WXGClamp(_frame.portalBlur/2.4,0.,1.);
        fgLensRamp=t*t*(3.f-2.f*t);
    }
    const float kBlurToSigma=0.57735027f;
    float portalSigma=kBlurToSigma*(float)_frame.portalBlur;
    float rowsSigmaX=hypotf(kBlurToSigma*(float)(rowsBlur*rowsScaleX),portalSigma);
    float rowsSigmaY=hypotf(kBlurToSigma*(float)(rowsBlur*rowsScaleY),portalSigma);
    float trigSigmaX=hypotf(kBlurToSigma*(float)(_frame.sourceBlur*triggerScaleX),portalSigma);
    float trigSigmaY=hypotf(kBlurToSigma*(float)(_frame.sourceBlur*triggerScaleY),portalSigma);

    WXGMenuMorphUniforms baseU={
        {pixelX,pixelY,MAX(pixelX,pixelY),(float)MAX(0.,MIN(1.,_frame.contentProgress))},
        WXGMenuFloatRect(_menu),WXGMenuFloatRect(_sourceLobe),
        {(float)_frame.radiusX,(float)_frame.radiusY,(float)_frame.sourceRadius,(float)_frame.smoothing},
        {(float)_frame.lensHeight*fgLensRamp,(float)(_frame.lensAmount*refractionScale)*fgLensRamp,
         self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?1.f:0.f,0.f},
        {0,0,0,0},
        WXGMenuFloatRect(rowsInk),WXGMenuFloatRect(triggerInk),
        {foreground && _rowsTexture?(float)_frame.rowsOpacity:0.f,
         foreground && _triggerTexture?(float)_frame.sourceOpacity:0.f,portalSigma,
         foreground && _rowsTexture && !_wantsOpenInk?(float)(_highlightOpacity*_frame.rowsOpacity):0.f},
        {0,0,0,0},
        {0,0,0,0},
        WXGMenuFloatRect(highlight),
        {(float)(_plateLightX-_highlightRect.origin.x),(float)rowsScaleX,(float)rowsScaleY,0}
    };
    BOOL generatingMips=foreground && (_rowsNeedMips || _triggerNeedsMips);
    CGPoint winOrigin=self.window?[self convertPoint:CGPointZero toView:self.window]:CGPointZero;
    CGFloat sessionStep=_surface.opticalSessionStep;
    BOOL wantsCached=foreground && _wantsOpenInk;
    if(_hasLastDrawnPose && !generatingMips && (!wantsCached || !_needsOpenInk) && !_metal.hidden && _metal.contents &&
       _drawableHasForeground==foreground && _hasCachedInk==wantsCached &&
       CGSizeEqualToSize(drawSize,_lastDrawnDrawableSize) &&
       CGPointEqualToPoint(winOrigin,_lastDrawnWinOrigin) &&
       fabs(sessionStep-_lastDrawnSessionStep)<.0001 &&
       memcmp(&baseU,&_lastDrawnUniforms,sizeof(baseU))==0) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(_hasCachedInk)[self placeCachedOpenInk];
        else{_metal.affineTransform=CGAffineTransformIdentity;_plate.hidden=YES;}
        [CATransaction commit];
        _stableFrameMissed=NO;_stableRetryCount=0;
        return YES;
    }

    if(dispatch_semaphore_wait(_inFlight,DISPATCH_TIME_NOW)!=0)return NO;
    NSInteger chosenSlot=-1;
    uint64_t chosenGen=0;
    id currentContents=_metal.contents;
    [_slotLock lock];
    chosenGen=_surfaceGeneration;
    for(NSUInteger k=0;k<WXGMenuMorphSurfaceRing;k++) {
        NSUInteger cand=(_nextSurfaceSlot+k)%WXGMenuMorphSurfaceRing;
        IOSurfaceRef candIOS=CVPixelBufferGetIOSurface(_surfaceBuffers[cand]);
        if(!_slotBusy[cand] && candIOS && (__bridge id)candIOS!=currentContents) {
            chosenSlot=(NSInteger)cand;
            _slotBusy[cand]=YES;
            _nextSurfaceSlot=(cand+1)%WXGMenuMorphSurfaceRing;
            break;
        }
    }
    if(chosenSlot<0) {
        for(NSUInteger k=0;k<WXGMenuMorphSurfaceRing;k++) {
            NSUInteger cand=(_nextSurfaceSlot+k)%WXGMenuMorphSurfaceRing;
            if(!_slotBusy[cand] && CVPixelBufferGetIOSurface(_surfaceBuffers[cand])) {
                chosenSlot=(NSInteger)cand;
                _slotBusy[cand]=YES;
                _nextSurfaceSlot=(cand+1)%WXGMenuMorphSurfaceRing;
                break;
            }
        }
    }
    [_slotLock unlock];
    if(chosenSlot<0){dispatch_semaphore_signal(_inFlight);return NO;}

    CVPixelBufferRef targetBuffer=CVPixelBufferRetain(_surfaceBuffers[chosenSlot]);
    IOSurfaceRef targetSurface=CVPixelBufferGetIOSurface(targetBuffer);
    id<MTLTexture> targetTexture=_surfaceTextures[chosenSlot];
    id<MTLCommandBuffer> command=[_queue commandBuffer];
    if(!targetSurface || !targetTexture || !command) {
        CVPixelBufferRelease(targetBuffer);
        [_slotLock lock];if(_surfaceGeneration==chosenGen)_slotBusy[chosenSlot]=NO;[_slotLock unlock];
        dispatch_semaphore_signal(_inFlight);
        return NO;
    }
    if(generatingMips) {
        id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
        if(!blit) {
            CVPixelBufferRelease(targetBuffer);
            [_slotLock lock];if(_surfaceGeneration==chosenGen)_slotBusy[chosenSlot]=NO;[_slotLock unlock];
            dispatch_semaphore_signal(_inFlight);
            return NO;
        }
        if(_rowsNeedMips)[blit generateMipmapsForTexture:_rowsTexture];
        if(_triggerNeedsMips)[blit generateMipmapsForTexture:_triggerTexture];
        [blit endEncoding];
    }
    WXGMenuMorphUniforms u=baseU;
    id<MTLTexture> field=[self encodeSmoothedField:command uniforms:&u];
    BOOL wantRowsBlur=foreground && _rowsTexture && _frame.rowsOpacity>.001 && fmaxf(rowsSigmaX,rowsSigmaY)>=.08f;
    BOOL wantTrigBlur=foreground && _triggerTexture && _frame.sourceOpacity>.001 && fmaxf(trigSigmaX,trigSigmaY)>=.08f;
    if((wantRowsBlur || wantTrigBlur) && [self ensureInkBlurTexturesForWidth:targetTexture.width height:targetTexture.height]) {
        if(wantRowsBlur)u.rowsBlurBox=[self encodeInkBlur:command source:_rowsTexture destination:_inkRowsBlur
            rect:rowsInk sigmaX:rowsSigmaX sigmaY:rowsSigmaY pixelX:pixelX pixelY:pixelY];
        if(wantTrigBlur)u.triggerBlurBox=[self encodeInkBlur:command source:_triggerTexture destination:_inkTriggerBlur
            rect:triggerInk sigmaX:trigSigmaX sigmaY:trigSigmaY pixelX:pixelX pixelY:pixelY];
    }
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=targetTexture;
    pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
    id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
    if(!encoder) {
        CVPixelBufferRelease(targetBuffer);
        [_slotLock lock];if(_surfaceGeneration==chosenGen)_slotBusy[chosenSlot]=NO;[_slotLock unlock];
        dispatch_semaphore_signal(_inFlight);
        return NO;
    }
    [encoder setRenderPipelineState:_pipeline];
    [encoder setFragmentBytes:&u length:sizeof(u) atIndex:0];
    [encoder setFragmentTexture:field?:_texture atIndex:0];
    [encoder setFragmentTexture:_rowsTexture?:_texture atIndex:1];
    [encoder setFragmentTexture:_triggerTexture?:_texture atIndex:2];
    [encoder setFragmentTexture:_inkRowsBlur?:_texture atIndex:3];
    [encoder setFragmentTexture:_inkTriggerBlur?:_texture atIndex:4];
    // The render pass clears the entire target. Only shade the ink inside
    // this frame's silhouette (also when the compute shader is unavailable).
    CGFloat rx=MAX(.01,_frame.radiusX),ry=MAX(.01,_frame.radiusY);
    CGFloat ratio=MAX(rx,ry)/MIN(rx,ry);
    CGFloat margin=MAX(4.,_frame.smoothing*(.25*ratio+.5)+4.);
    CGRect silhouette=CGRectInset(MIN(_sourceLobe.size.width,_sourceLobe.size.height)>=.01?
        CGRectUnion(_menu,_sourceLobe):_menu,-margin,-margin);
    CGRect pixels=CGRectIntegral(CGRectApplyAffineTransform(silhouette,CGAffineTransformMakeScale(1./pixelX,1./pixelY)));
    pixels=CGRectIntersection(pixels,CGRectMake(0,0,targetTexture.width,targetTexture.height));
    if(!CGRectIsEmpty(pixels)){
        [encoder setScissorRect:(MTLScissorRect){(NSUInteger)pixels.origin.x,(NSUInteger)pixels.origin.y,
            (NSUInteger)pixels.size.width,(NSUInteger)pixels.size.height}];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }
    [encoder endEncoding];
    dispatch_semaphore_t inFlight=_inFlight;
    NSLock *slotLock=_slotLock;
    __weak typeof(self) weakSelf=self;
    [command addCompletedHandler:^(__unused id<MTLCommandBuffer> done){
        CVPixelBufferRelease(targetBuffer);
        WXGMenuMorphView *strongSelf=weakSelf;
        if(strongSelf){
            [slotLock lock];
            if(strongSelf->_surfaceGeneration==chosenGen)strongSelf->_slotBusy[chosenSlot]=NO;
            [slotLock unlock];
        }
        dispatch_semaphore_signal(inFlight);
    }];
    // Commit, wait until scheduled on the GPU, and assign the IOSurface directly
    // to CALayer.contents inside the exact same CATransaction as _bodyMask and
    // _rimClip, eliminating CAImageQueue's 1-vsync FIFO lag completely.
    [command commit];
    [command waitUntilScheduled];
    if(command.status==MTLCommandBufferStatusError)return NO;
    if(generatingMips){_rowsNeedMips=NO;_triggerNeedsMips=NO;}
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _metal.affineTransform=CGAffineTransformIdentity;
    _metal.position=self.bounds.origin;
    _metal.bounds=(CGRect){CGPointZero,self.bounds.size};
    _metal.contentsScale=scale;
    _hasCachedInk=wantsCached;
    if(_hasCachedInk){
        _cachedMenu=_menu;_needsOpenInk=NO;
        [self placeCachedOpenInk];
    }else _plate.hidden=YES;
    _metal.hidden=NO;
    _metal.contents=(__bridge id)targetSurface;
    ++_inkSubmissions;
    [CATransaction commit];
    _lastDrawnUniforms=baseU;
    _lastDrawnDrawableSize=CGSizeMake(targetTexture.width,targetTexture.height);
    _lastDrawnWinOrigin=winOrigin;
    _lastDrawnSessionStep=sessionStep;
    _hasLastDrawnPose=YES;
    _drawableHasForeground=foreground;
    _stableFrameMissed=NO;_stableRetryCount=0;
    return YES;
}

- (void)retryStableFrame {
    if(_sessionUsesUIKit || !_stableFrameMissed || !_pipeline || !_queue || !_texture || !self.requestFrame ||
        _stableRetryPending || _stableRetryCount>=2)return;
    _stableRetryPending=YES;
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        WXGMenuMorphView *view=weakSelf;
        if(!view)return;
        view->_stableRetryPending=NO;
        if(view->_stableFrameMissed && view.window && view.requestFrame) {
            ++view->_stableRetryCount;
            view.requestFrame();
        }
    });
}

- (BOOL)applyMorphFrame:(WXGMenuMorphFrame)frame inParent:(UIView *)parent settledOpen:(BOOL)settled showsForeground:(BOOL)showsForeground {
    __block BOOL hasForeground=NO;
    [UIView performWithoutAnimation:^{
        CGRect menu=[self convertRect:WXGMenuMorphCGRect(frame.bounds) fromView:parent];
        CGRect source=[self convertRect:WXGMenuMorphCGRect(frame.sourceLobe) fromView:parent];
        _frame=frame; _menu=menu; _sourceLobe=source;
        _hasFrame=YES; _showsForeground=showsForeground;
        if(!_surface)[self useSurfaceFromButton:nil];
        [self layoutIfNeeded];
        if(showsForeground && !_sessionUsesUIKit && !_pipeline) {
            __weak typeof(self) weakSelf=self;
            WXGPrepareMenuMorphMetal(YES,^(id<MTLRenderPipelineState> state,id<MTLComputePipelineState> field,
                id<MTLComputePipelineState> smooth,id<MTLComputePipelineState> blurH,id<MTLComputePipelineState> blurV,
                id<MTLCommandQueue> commandQueue){
                WXGMenuMorphView *view=weakSelf;
                if(!view)return;
                view->_pipeline=state;
                view->_fieldPipeline=field;
                view->_smoothPipeline=smooth;
                view->_blurHPipeline=blurH;
                view->_blurVPipeline=blurV;
                view->_queue=commandQueue;
            });
        }
        // A near-settled spring may still have visible portal blur or refraction.
        // Cache only the exact final pose published when the motion has settled.
        _wantsOpenInk=settled && showsForeground && frame.rowsOpacity>=.999999 && frame.contentBlur<.0001 &&
            frame.sourceOpacity<.0001 && frame.portalBlur<.0001 && frame.lensHeight<.0001;
        BOOL reused=_hasCachedInk && _wantsOpenInk && !_needsOpenInk;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        BOOL rendered=reused || [self drawGlass];
        if(reused){[self placeCachedOpenInk];++_openInkReuses;}
        // Hold the last visible pair through a missed surface slot. If the final
        // static image cannot be obtained after retrying, settle both in UIKit.
        if(showsForeground && !rendered && (!_drawableHasForeground || (_wantsOpenInk && _stableRetryCount>=2))) {
            if(!_inkSubmissions)_sessionUsesUIKit=YES;
            _metal.hidden=YES;_plate.hidden=YES;
            _hasCachedInk=NO;_drawableHasForeground=NO;
        }
        if(rendered || !_drawableHasForeground || !CGRectEqualToRect(self.bounds,_lastCommittedSurfaceBounds)) {
            CGFloat trigSide=_triggerSide>1.?_triggerSide:MIN(source.size.width,source.size.height);
            CGFloat menuSide=_menuSide>1.?_menuSide:MIN(menu.size.width,menu.size.height);
            WXGMenuMorphSurfaceOptics optics={frame.contentProgress,frame.lensHeight,frame.lensAmount,frame.portalBlur,trigSide,menuSide};
            [_surface placeMenuRect:menu radiusX:frame.radiusX radiusY:frame.radiusY sourceRect:source
                radius:frame.sourceRadius smoothing:frame.smoothing optics:optics];
            [_surface placeTouchLight:_lightPoint strength:_lightStrength];
            _lastCommittedSurfaceBounds=self.bounds;
        }
        [CATransaction commit];
        BOOL stable=_wantsOpenInk;
        if(!stable)_stableRetryCount=0;
        _stableFrameMissed=stable && !rendered && !_sessionUsesUIKit;
        [self retryStableFrame];
        hasForeground=_drawableHasForeground;
    }];
    return hasForeground;
}

- (void)applyMorphFrame:(WXGMenuMorphFrame)frame inParent:(UIView *)parent {
    [self applyMorphFrame:frame inParent:parent settledOpen:NO showsForeground:NO];
}

@end
