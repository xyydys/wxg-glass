#import "WXGMenuMorphView.h"
#import "WXGMenuMorphMask.h"
#import "WXGMenuMorphMaterial.h"
#import "WXGMenuMorphMetal.h"
#import "WXGBackdropSample.h"
#import "WXGCommon.h"
#import "WXGIntegration.h"
#import <QuartzCore/CAMetalLayer.h>

typedef float WXGMenuFloat4 __attribute__((ext_vector_type(4)));
typedef struct {
    WXGMenuFloat4 viewport,menu,source,radii,optics,field;
    WXGMenuFloat4 rowsInk,triggerInk,foreground,inkBlur,highlightInk,plateLight;
} WXGMenuMorphUniforms;
_Static_assert(sizeof(WXGMenuMorphUniforms)==192,"Menu morph uniforms must match Metal");

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

static void WXGPrepareMenuMorphMetal(void (^ready)(id<MTLRenderPipelineState>,id<MTLComputePipelineState>,id<MTLComputePipelineState>,id<MTLCommandQueue>)) {
    static dispatch_once_t once;
    static dispatch_group_t preparation;
    static id<MTLRenderPipelineState> pipeline;
    static id<MTLComputePipelineState> field,smooth;
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
            queue=[device newCommandQueue];
        });
    });
    if(!ready)return;
    if(dispatch_group_wait(preparation,DISPATCH_TIME_NOW)==0)ready(pipeline,field,smooth,queue);
    else dispatch_group_notify(preparation,dispatch_get_main_queue(),^{ready(pipeline,field,smooth,queue);});
}

void WXGPrewarmMenuMorphRenderer(void) {WXGPrepareMenuMorphMetal(nil);}

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
- (void)setOpticalSessionStep:(CGFloat)step {
    if(_material.opticalSessionStep==step)return;
    _material.opticalSessionStep=step;_lastBounds=CGRectNull;
}
- (void)placeButtonRect:(CGRect)button {
    CGFloat r=MIN(button.size.width,button.size.height)*.5;
    [self placeMenuRect:button radiusX:r radiusY:r sourceRect:button radius:r smoothing:0];
}
- (void)placeMenuRect:(CGRect)menu radiusX:(CGFloat)rx radiusY:(CGFloat)ry
           sourceRect:(CGRect)source radius:(CGFloat)radius smoothing:(CGFloat)smoothing {
    if(CGRectIsEmpty(menu) || CGRectIsEmpty(self.bounds))return;
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    NSUInteger revision=WXGConfigRevision();
    UIUserInterfaceStyle appearance=self.traitCollection.userInterfaceStyle;
    CGPoint opticalOrigin=(smoothing>0 && _material.opticalSessionStep>0 && self.window)?
        [self convertPoint:CGPointZero toView:self.window]:CGPointZero;
    if(CGPointEqualToPoint(opticalOrigin,_lastOpticalOrigin) && CGRectEqualToRect(self.bounds,_lastBounds) && CGRectEqualToRect(menu,_lastMenu) &&
        CGRectEqualToRect(source,_lastSource) && rx==_lastRX && ry==_lastRY && radius==_lastRadius &&
        smoothing==_lastSmoothing && scale==_lastScale && revision==_revision && appearance==_appearance)return;
    _lastOpticalOrigin=opticalOrigin;_lastBounds=self.bounds;_lastMenu=menu;_lastSource=source;_lastRX=rx;_lastRY=ry;_lastRadius=radius;
    _lastSmoothing=smoothing;_lastScale=scale;_revision=revision;_appearance=appearance;
    // Anchor the sample grid to the shape, not to its button/window parent.
    // Reparenting across a fractional window origin must preserve the contour.
    CGRect extent=CGRectUnion(menu,source);
    CGFloat x=extent.origin.x,y=extent.origin.y;
    WXGMenuMorphField field;
    CGFloat step=MIN(5.,MAX(1.25,MAX(extent.size.width,extent.size.height)/46.));
    WXGMenuMorphFieldBuildMode(&field,WXGMenuMorphFieldBoxFromRect(CGRectOffset(menu,-x,-y),rx),ry,
        WXGMenuMorphFieldBoxFromRect(CGRectOffset(source,-x,-y),radius),smoothing,step,WXGMorphFieldGeometry);
    WXGMenuMorphFieldTranslate(&field,x,y);
    _currentOutline=WXGMenuMorphMaskPath(&field);
    CGRect material=CGPathGetPathBoundingBox(_currentOutline.CGPath);
    if(CGRectIsEmpty(material))return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _bodyHost.frame=self.bounds;_bodyMask.frame=_bodyHost.bounds;_bodyMask.contentsScale=scale;
    _inkHost.frame=_bodyHost.bounds;_bodyMask.path=_currentOutline.CGPath;
    _movingShadow.frame=self.bounds;_movingShadowMask.frame=self.bounds;
    [_material applyField:&field bounds:material outline:_currentOutline];
    CGRect local=_material.rimView.bounds;_rimClip.frame=local;_rimClip.contentsScale=scale;
    CGAffineTransform shift=CGAffineTransformMakeTranslation(-material.origin.x,-material.origin.y);
    CGPathRef path=CGPathCreateCopyByTransformingPath(_currentOutline.CGPath,&shift);
    _rimClip.path=path;CGPathRelease(path);
    if(_edgeStrip)_edgeStrip.path=_rimClip.path;
    [self placeShadowAround:material];
    [CATransaction commit];
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

@implementation WXGMenuMorphView {
    WXGMenuMorphSurface *_surface;
    __weak WXGSurface *_sourceButton;
    BOOL _sessionUsesUIKit;
    CAMetalLayer *_metal;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLComputePipelineState> _fieldPipeline,_smoothPipeline;
    id<MTLTexture> _texture,_rowsTexture,_triggerTexture;
    UIImage *_rowsImage,*_triggerImage;
    NSArray<id<MTLTexture>> *_fieldTextures;
    dispatch_semaphore_t _inFlight;
    CGRect _menu,_sourceLobe;
    CGRect _highlightRect,_cachedMenu;
    CGFloat _highlightOpacity,_lightStrength,_plateLightX;
    CGPoint _lightPoint;
    CALayer *_plate,*_plateShine;
    BOOL _hasCachedInk,_needsOpenInk,_wantsOpenInk,_plateDark,_plateTintReady;
    NSUInteger _openInkReuses,_inkSubmissions;
    WXGMenuMorphFrame _frame;
    BOOL _hasFrame,_showsForeground,_drawableHasForeground,_rowsNeedMips,_triggerNeedsMips;
    BOOL _stableFrameMissed,_stableRetryPending;
    NSUInteger _stableRetryCount;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO;
        self.accessibilityElementsHidden=YES;
        self.opaque=NO;
        _inFlight=dispatch_semaphore_create(2);
        _metal=[CAMetalLayer layer];
        _metal.name=@"morph.foreground.metal";
        _metal.anchorPoint=CGPointZero;
        _metal.opaque=NO;
        _metal.device=WXGSharedDevice();
        _metal.pixelFormat=MTLPixelFormatBGRA8Unorm;
        _metal.framebufferOnly=YES;
        _metal.allowsNextDrawableTimeout=YES;
        _metal.presentsWithTransaction=YES;
        CGColorSpaceRef colorSpace=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        if(colorSpace){_metal.colorspace=colorSpace;CGColorSpaceRelease(colorSpace);}
        __weak typeof(self) weakSelf=self;
        WXGPrepareMenuMorphMetal(^(id<MTLRenderPipelineState> state,id<MTLComputePipelineState> field,id<MTLComputePipelineState> smooth,id<MTLCommandQueue> commandQueue){
            WXGMenuMorphView *view=weakSelf;
            if(!view)return;
            view->_pipeline=state;
            view->_fieldPipeline=field;
            view->_smoothPipeline=smooth;
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
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(_surface.superview==self)_surface.frame=self.bounds;
    _fallbackForeground.frame=self.bounds;
    _metal.position=self.bounds.origin;
    _metal.bounds=(CGRect){CGPointZero,self.bounds.size};
    _metal.contentsScale=scale;
    if(!CGSizeEqualToSize(_metal.drawableSize,size)) {
        _metal.drawableSize=size;
        _fieldTextures=nil;
        _stableRetryCount=0;
        _needsOpenInk=YES;
    }
    [CATransaction commit];
}

- (UIBezierPath *)currentOutline {return _surface.currentOutline;}
- (void)useSurfaceFromButton:(WXGSurface *)button {
    if(_surface)return;
    WXGMenuMorphSurface *lent=[button borrowHomeMenuMorphSurface];
    _sourceButton=lent?button:nil;
    if(lent)_sourceAtPickup=lent.presentationEvidence;
    _surface=lent?:[[WXGMenuMorphSurface alloc] initWithFrame:self.bounds];
    _surface.transform=CGAffineTransformIdentity;
    _surface.frame=self.bounds;
    [self insertSubview:_surface atIndex:0];
    _plate=[CALayer layer];_plate.name=@"morph.selection.plate";
    _plate.anchorPoint=CGPointZero;_plate.cornerCurve=kCACornerCurveContinuous;_plate.masksToBounds=YES;_plate.hidden=YES;
    [_surface.inkHost.layer addSublayer:_plate];
    [_surface.inkHost.layer addSublayer:_metal];
    if(_fallbackForeground)[_surface.inkHost addSubview:_fallbackForeground];
}
- (void)setOpticalSessionBounds:(CGRect)windowBounds {
    // The original session fixes its Gaussian spacing at a 48pt margin on
    // each side of the union of the original button and destination menu.
    CGFloat longest=MAX(windowBounds.size.width,windowBounds.size.height);
    [_surface setOpticalSessionStep:MAX(5.,(longest+96.)/64.)];
}
- (void)setFallbackForeground:(UIView *)fallbackForeground {
    if(_fallbackForeground!=fallbackForeground)[_fallbackForeground removeFromSuperview];
    _fallbackForeground=fallbackForeground;
    if(fallbackForeground && _surface && fallbackForeground.superview!=_surface.inkHost)
        [_surface.inkHost addSubview:fallbackForeground];
    _fallbackForeground.frame=self.bounds;
}
- (NSDictionary *)returnSurfaceToButton {
    if(!_surface)return nil;
    [_surface placeTouchLight:CGPointZero strength:0];
    [_surface setOpticalSessionStep:0];
    [_plate removeFromSuperlayer];[_metal removeFromSuperlayer];[_fallbackForeground removeFromSuperview];
    _plate=nil;_plateShine=nil;_plateTintReady=NO;_hasCachedInk=NO;
    _metal.affineTransform=CGAffineTransformIdentity;
    if(_sourceButton)[_sourceButton returnHomeMenuMorphSurface:_surface];
    else [_surface removeFromSuperview];
    NSDictionary *returned=_sourceButton && _surface.superview==_sourceButton?_surface.presentationEvidence:nil;
    _surface=nil;_sourceButton=nil;
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
        _rowsImage=rowsImage;_rowsTexture=WXGMenuPremultipliedTexture(rowsImage,_metal.device);
        _rowsNeedMips=_rowsTexture.mipmapLevelCount>1;
        _needsOpenInk=YES;
    }
    if(_triggerImage!=triggerImage) {
        _triggerImage=triggerImage;_triggerTexture=WXGMenuPremultipliedTexture(triggerImage,_metal.device);
        _triggerNeedsMips=_triggerTexture.mipmapLevelCount>1;
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

// Blur the signed distance and gradient together on a small padded grid, as
// the Android renderer does. Pixel-resolution shading samples the result.
- (id<MTLTexture>)encodeSmoothedField:(id<MTLCommandBuffer>)command uniforms:(WXGMenuMorphUniforms *)uniforms {
    if(!_fieldPipeline || !_smoothPipeline || _frame.smoothing<.6)return nil;
    double step=MAX(5.,MAX(self.bounds.size.width,self.bounds.size.height)/64.);
    double sigma=_frame.smoothing/step;
    if(sigma<.30)return nil;
    NSUInteger width=(NSUInteger)ceil(self.bounds.size.width/step)+33;
    NSUInteger height=(NSUInteger)ceil(self.bounds.size.height/step)+33;
    if(!_fieldTextures) {
        MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
            width:width height:height mipmapped:NO];
        descriptor.storageMode=MTLStorageModePrivate;
        descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        id<MTLTexture> raw=[_metal.device newTextureWithDescriptor:descriptor];
        id<MTLTexture> horizontal=[_metal.device newTextureWithDescriptor:descriptor];
        id<MTLTexture> gaussian=[_metal.device newTextureWithDescriptor:descriptor];
        if(!raw || !horizontal || !gaussian)return nil;
        _fieldTextures=@[raw,horizontal,gaussian];
    }
    uniforms->field=(WXGMenuFloat4){(float)(-16.*step),(float)(-16.*step),(float)step,1.f};
    MTLSize groups=MTLSizeMake((width+7)/8,(height+7)/8,1),lanes=MTLSizeMake(8,8,1);
    id<MTLComputeCommandEncoder> compute=[command computeCommandEncoder];
    if(!compute){uniforms->field[3]=0;return nil;}
    [compute setComputePipelineState:_fieldPipeline];
    [compute setBytes:uniforms length:sizeof(*uniforms) atIndex:0];
    [compute setTexture:_fieldTextures[0] atIndex:0];
    [compute dispatchThreadgroups:groups threadsPerThreadgroup:lanes];
    [compute endEncoding];
    for(NSUInteger axis=0;axis<2;axis++) {
        compute=[command computeCommandEncoder];
        if(!compute){uniforms->field[3]=0;return nil;}
        WXGMenuFloat4 settings={(float)(axis==0),(float)(axis==1),(float)sigma,(float)MIN(16.,ceil(sigma*3.2))};
        [compute setComputePipelineState:_smoothPipeline];
        [compute setBytes:&settings length:sizeof(settings) atIndex:0];
        [compute setTexture:_fieldTextures[axis] atIndex:0];
        [compute setTexture:_fieldTextures[axis+1] atIndex:1];
        [compute dispatchThreadgroups:groups threadsPerThreadgroup:lanes];
        [compute endEncoding];
    }
    return _fieldTextures.lastObject;
}

- (BOOL)drawGlass {
    if(_sessionUsesUIKit || !_hasFrame || !self.window || self.hidden || CGRectIsEmpty(self.bounds))return NO;
    BOOL foreground=_showsForeground && (_rowsTexture || _triggerTexture) &&
        (!_rowsImage || _rowsTexture) && (!_triggerImage || _triggerTexture);
    if(!_texture || !_pipeline || !_queue || _metal.drawableSize.width<1. || _metal.drawableSize.height<1. ||
        dispatch_semaphore_wait(_inFlight,DISPATCH_TIME_NOW)!=0)return NO;
    id<CAMetalDrawable> drawable=[_metal nextDrawable];
    id<MTLCommandBuffer> command=[_queue commandBuffer];
    if(!drawable || !command){dispatch_semaphore_signal(_inFlight);return NO;}
    BOOL generatingMips=foreground && (_rowsNeedMips || _triggerNeedsMips);
    if(generatingMips) {
        id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
        if(!blit){dispatch_semaphore_signal(_inFlight);return NO;}
        if(_rowsNeedMips)[blit generateMipmapsForTexture:_rowsTexture];
        if(_triggerNeedsMips)[blit generateMipmapsForTexture:_triggerTexture];
        [blit endEncoding];
    }
    float pixelX=self.bounds.size.width/drawable.texture.width,pixelY=self.bounds.size.height/drawable.texture.height;
    CGRect rowsInk=WXGMenuMorphZoomedRect(_menu,_frame.contentZoom),triggerInk=WXGMenuMorphZoomedRect(_sourceLobe,_frame.sourceZoom);
    CGFloat rowsScaleX=rowsInk.size.width/MAX(1.,_rowsImage.size.width),rowsScaleY=rowsInk.size.height/MAX(1.,_rowsImage.size.height);
    CGFloat rowsBlur=_frame.contentBlur/MAX(.25,MIN(rowsScaleX,rowsScaleY));
    CGFloat triggerScaleX=triggerInk.size.width/MAX(1.,_triggerImage.size.width),triggerScaleY=triggerInk.size.height/MAX(1.,_triggerImage.size.height);
    CGRect highlight=CGRectOffset(CGRectApplyAffineTransform(_highlightRect,CGAffineTransformMakeScale(rowsScaleX,rowsScaleY)),
        rowsInk.origin.x,rowsInk.origin.y);
    WXGMenuMorphUniforms u={
        {pixelX,pixelY,MAX(pixelX,pixelY),(float)MAX(0.,MIN(1.,_frame.contentProgress))},
        WXGMenuFloatRect(_menu),WXGMenuFloatRect(_sourceLobe),
        {(float)_frame.radiusX,(float)_frame.radiusY,(float)_frame.sourceRadius,(float)_frame.smoothing},
        {(float)_frame.lensHeight,(float)_frame.lensAmount,self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?1.f:0.f,1.f},
        {0,0,0,0},
        WXGMenuFloatRect(rowsInk),WXGMenuFloatRect(triggerInk),
        {foreground && _rowsTexture?(float)_frame.rowsOpacity:0.f,
         foreground && _triggerTexture?(float)_frame.sourceOpacity:0.f,(float)_frame.portalBlur,
         foreground && _rowsTexture && !_wantsOpenInk?(float)(_highlightOpacity*_frame.rowsOpacity):0.f},
        {(float)(rowsBlur*rowsScaleX),(float)(rowsBlur*rowsScaleY),
         (float)(_frame.sourceBlur*triggerScaleX),(float)(_frame.sourceBlur*triggerScaleY)},
        WXGMenuFloatRect(highlight),
        {(float)(_plateLightX-_highlightRect.origin.x),(float)rowsScaleX,(float)rowsScaleY,0}
    };
    id<MTLTexture> field=[self encodeSmoothedField:command uniforms:&u];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=drawable.texture;
    pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
    id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
    if(!encoder){dispatch_semaphore_signal(_inFlight);return NO;}
    [encoder setRenderPipelineState:_pipeline];
    [encoder setFragmentBytes:&u length:sizeof(u) atIndex:0];
    [encoder setFragmentTexture:field?:_texture atIndex:0];
    [encoder setFragmentTexture:_rowsTexture?:_texture atIndex:1];
    [encoder setFragmentTexture:_triggerTexture?:_texture atIndex:2];
    // The render pass clears the entire drawable. Only shade the ink inside
    // this frame's silhouette (also when the compute shader is unavailable).
    CGRect pixels=CGRectIntegral(CGRectApplyAffineTransform(CGRectInset(self.currentOutline.bounds,-1.,-1.),
        CGAffineTransformMakeScale(1./pixelX,1./pixelY)));
    pixels=CGRectIntersection(pixels,CGRectMake(0,0,drawable.texture.width,drawable.texture.height));
    if(!CGRectIsEmpty(pixels)){
        [encoder setScissorRect:(MTLScissorRect){(NSUInteger)pixels.origin.x,(NSUInteger)pixels.origin.y,
            (NSUInteger)pixels.size.width,(NSUInteger)pixels.size.height}];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }
    [encoder endEncoding];
    dispatch_semaphore_t inFlight=_inFlight;
    [command addCompletedHandler:^(__unused id<MTLCommandBuffer> done){dispatch_semaphore_signal(inFlight);}];
    // Publish with the caller's layer updates, so neither a plain UIKit copy
    // nor the previous frame's tint remains visible across the handoff.
    [command commit];
    [command waitUntilScheduled];
    if(command.status==MTLCommandBufferStatusError)return NO;
    if(generatingMips){_rowsNeedMips=NO;_triggerNeedsMips=NO;}
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _metal.affineTransform=CGAffineTransformIdentity;
    _hasCachedInk=foreground && _wantsOpenInk;
    if(_hasCachedInk){
        _cachedMenu=_menu;_needsOpenInk=NO;
        [self placeCachedOpenInk];
    }else _plate.hidden=YES;
    _metal.hidden=NO;[drawable present];++_inkSubmissions;
    [CATransaction commit];
    _drawableHasForeground=foreground;
    _stableFrameMissed=NO;_stableRetryCount=0;
    return YES;
}

- (void)retryStableFrame {
    if(_sessionUsesUIKit || !_stableFrameMissed || !_pipeline || !_queue || !_texture || !self.requestFrame ||
        _stableRetryPending || _stableRetryCount>=2)return;
    _stableRetryPending=YES;
    ++_stableRetryCount;
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        WXGMenuMorphView *view=weakSelf;
        if(!view)return;
        view->_stableRetryPending=NO;
        if(view->_stableFrameMissed && view.window && view.requestFrame)view.requestFrame();
    });
}

- (BOOL)applyMorphFrame:(WXGMenuMorphFrame)frame inParent:(UIView *)parent settledOpen:(BOOL)settled showsForeground:(BOOL)showsForeground {
    CGRect menu=[self convertRect:WXGMenuMorphCGRect(frame.bounds) fromView:parent];
    CGRect source=[self convertRect:WXGMenuMorphCGRect(frame.sourceLobe) fromView:parent];
    _frame=frame; _menu=menu; _sourceLobe=source;
    _hasFrame=YES; _showsForeground=showsForeground;
    if(!_surface)[self useSurfaceFromButton:nil];
    [self layoutIfNeeded];
    [_surface placeMenuRect:menu radiusX:frame.radiusX radiusY:frame.radiusY sourceRect:source
        radius:frame.sourceRadius smoothing:frame.smoothing];
    [_surface placeTouchLight:_lightPoint strength:_lightStrength];
    // A near-settled spring may still have visible portal blur or refraction.
    // Cache only the exact final pose published when the motion has settled.
    _wantsOpenInk=settled && showsForeground && frame.rowsOpacity>=.999999 && frame.contentBlur<.0001 &&
        frame.sourceOpacity<.0001 && frame.portalBlur<.0001 && frame.lensHeight<.0001;
    BOOL reused=_hasCachedInk && _wantsOpenInk && !_needsOpenInk;
    BOOL rendered=reused || [self drawGlass];
    if(reused){[self placeCachedOpenInk];++_openInkReuses;}
    // Select one ink backend at first presentation. A late Metal completion
    // must not replace the visible UIKit labels midway through a session.
    if(showsForeground && !rendered && !_drawableHasForeground){_sessionUsesUIKit=YES;_metal.hidden=YES;}
    BOOL stable=_wantsOpenInk;
    if(!stable)_stableRetryCount=0;
    _stableFrameMissed=stable && !rendered;
    [self retryStableFrame];
    return _drawableHasForeground;
}

- (void)applyMorphFrame:(WXGMenuMorphFrame)frame inParent:(UIView *)parent {
    [self applyMorphFrame:frame inParent:parent settledOpen:NO showsForeground:NO];
}

@end
