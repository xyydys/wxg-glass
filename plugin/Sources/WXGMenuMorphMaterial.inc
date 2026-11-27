// This implementation lives alongside the shared render-server backdrop and
// rim paint. Only the shape supplied to their optics changes during a morph.
#import "WXGMenuMorphRim.h"

#import "WXGMenuMorphOptics.h"

@implementation WXGMenuMorphMaterial {
    WXGSyncBackdropView *_backdrops[3];
    UIVisualEffectView *_fallback;
    CALayer *_veil,*_rimLayer,*_directional,*_plainBands;
    WXGRim26Paint *_livePaint;
    CALayer *_directionField;
    WXGMorphRimLights _directionLights;
    CALayer *_edgeMask;
    NSString *_rimGroup;
    BOOL _usesLivePaint,_paintConfigured;
    NSUInteger _bandCount,_directionRevision;
    BOOL _directionReady,_directionDark;
    NSString *_group;
    NSData *_scenePixels;
    NSMutableData *_edgeColours;
    CGRect _sampleRect;
    size_t _sampleWidth, _sampleHeight;
    NSUInteger _colourRevision;
    BOOL _colourDark;
    NSMutableData *_meshData[3];
    WXGMorphOpticalMesh _optics;
    WXGMenuMorphField *_sessionField;
    CGRect _captureRect;
    NSUInteger _channels;
    CGFloat _meshMS;
    BOOL _meshAccepted,_opticsGaussian;
    WXGMorphRimLights _lights;
    NSUInteger _rimRevision;
    BOOL _levelsReady,_rimDark;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.opaque=NO;
        _group=[NSString stringWithFormat:@"wxg.morph.%p",self];
        _backdrops[0]=[[WXGSyncBackdropView alloc] initWithFrame:self.bounds];
        [self addSubview:_backdrops[0]];
        _veil=[CALayer layer]; _veil.zPosition=1; [self.layer addSublayer:_veil];
        _backdrops[0].layer.name=@"morph.body.backdrop";
        _rimView=[[UIView alloc] initWithFrame:CGRectZero];
        _rimView.userInteractionEnabled=NO; _rimView.opaque=NO;
        _rimView.layer.name=@"morph.rim";
        _rimLayer=[CALayer layer]; [_rimView.layer addSublayer:_rimLayer];
        _rimGroup=[NSString stringWithFormat:@"wxg.morph.rim.%p",self];
        _livePaint=[[WXGRim26Paint alloc] initWithFrame:CGRectZero];
        _livePaint.layer.name=@"morph.rim.paint";
        [_rimView addSubview:_livePaint];
        _edgeMask=[CALayer layer]; _livePaint.layer.mask=_edgeMask;
        _plainBands=[CALayer layer]; [_edgeMask addSublayer:_plainBands];
        _directional=[CALayer layer]; [_edgeMask addSublayer:_directional];
        _directionField=[CALayer layer];_directionField.name=@"morph.rim.lightField"; _directional.mask=_directionField;
        if(!_backdrops[0].live || !WXGFilterFactoryAvailable()) {
            _backdrops[0].hidden=YES;
            _fallback=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
            [self insertSubview:_fallback atIndex:0];
        }
    }
    return self;
}

- (void)dealloc { free(_sessionField);WXGMorphOpticalFree(&_optics); }

// Each layer's UVs refer to its live capture, including the margin actually
// needed by the local optical rays. The mask and rim still use the face bounds.
- (id)opticalTransformForChannel:(NSUInteger)channel split:(BOOL)split {
    unsigned count=_optics.vertexCount,faces=_optics.faceCount;
    NSMutableData *data=[NSMutableData dataWithLength:count*sizeof(WXGMeshVertex)+faces*sizeof(WXGMeshFace)];
    WXGMeshVertex *vertices=data.mutableBytes;
    WXGMeshFace *quads=(WXGMeshFace *)(vertices+count);
    float w=_captureRect.size.width,h=_captureRect.size.height,left=_captureRect.origin.x,top=_captureRect.origin.y;
    float weight=split?WXGLensSplitWeight(1.f-(float)channel):0.f;
    for(unsigned i=0;i<count;i++){
        WXGMorphOpticalVertex v=_optics.vertices[i];
        float x=v.x-left,y=v.y-top;
        CGPoint source=CGPointMake((x+v.offsetX+v.splitX*weight)/w,(y+v.offsetY+v.splitY*weight)/h);
        vertices[i]=(WXGMeshVertex){source,{x/w,y/h,0}};
    }
    for(unsigned i=0;i<faces;i++){
        const unsigned *q=_optics.faces[i].index;
        quads[i]=(WXGMeshFace){{q[0],q[1],q[2],q[3]},{0,0,0,0}};
    }
    id mesh=WXGCreateMesh(WXGMeshTransformClass(),count,vertices,faces,quads,NULL);
    if(mesh)_meshData[channel]=data;
    return mesh;
}
- (void)updateCaptureBoundsForBlur:(CGFloat)blur split:(BOOL)split {
    CGRect face=self.bounds;
    CGFloat left=0,top=0,right=face.size.width,bottom=face.size.height;
    // The extreme channels enclose all intermediate samples. Piecewise
    // linear UVs stay within the extent of the vertices of their triangle.
    float red=split?WXGLensSplitWeight(1):0,blue=split?WXGLensSplitWeight(-1):0;
    for(unsigned i=0;i<_optics.vertexCount;i++) {
        WXGMorphOpticalVertex v=_optics.vertices[i];
        float x=v.x+v.offsetX,y=v.y+v.offsetY;
        left=fminf(left,x+fminf(v.splitX*red,v.splitX*blue));
        right=fmaxf(right,x+fmaxf(v.splitX*red,v.splitX*blue));
        top=fminf(top,y+fminf(v.splitY*red,v.splitY*blue));
        bottom=fmaxf(bottom,y+fmaxf(v.splitY*red,v.splitY*blue));
    }
    CGFloat margin=ceil(3*blur);
    _captureRect=CGRectMake(-ceil(-left)-margin,-ceil(-top)-margin,
        face.size.width+ceil(-left)+ceil(MAX(0,right-face.size.width))+2*margin,
        face.size.height+ceil(-top)+ceil(MAX(0,bottom-face.size.height))+2*margin);
}

// Use the portal's already captured scene as the colour source during motion.
// Keep it in portal coordinates so growing the contour reveals new scene
// colours instead of stretching a small button-sized image across the menu.
- (BOOL)needsRimBackdropImage {
    return [WXGConfig.shared rimStyleForScope:WXGGlassScopeOther]!=WXGRimStyleGlow &&
        (_paintConfigured?!_usesLivePaint:!([_livePaint live] && WXGFilterFactoryAvailable()));
}
- (void)setRimBackdropImage:(UIImage *)image inRect:(CGRect)rect {
    if(!image.CGImage || CGRectIsEmpty(rect))return;
    WXGConfig *c=WXGConfig.shared;
    CGFloat capture=[c rim26ForScope:WXGGlassScopeOther dark:self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark].captureScale;
    CGFloat scale=MIN(MAX(.25,capture),384./MAX(rect.size.width,rect.size.height));
    size_t w=MAX(1,ceil(rect.size.width*scale)),h=MAX(1,ceil(rect.size.height*scale));
    NSMutableData *pixels=[NSMutableData dataWithLength:w*h*4];
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx=CGBitmapContextCreate(pixels.mutableBytes,w,h,8,w*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if(!ctx)return;
    CGContextSetInterpolationQuality(ctx,kCGInterpolationMedium);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),image.CGImage);
    CGContextRelease(ctx);
    _scenePixels=pixels;_sampleWidth=w;_sampleHeight=h;_sampleRect=rect;
    _edgeColours=nil;
}

- (void)prepareRimColours:(WXGConfig *)c settings:(WXGRim26Settings)s dark:(BOOL)dark {
    NSUInteger revision=WXGConfigRevision();
    if(_edgeColours && revision==_colourRevision && dark==_colourDark)return;
    _colourRevision=revision;_colourDark=dark;
    WXGBackdropTone tone=[c backdropToneForScope:WXGGlassScopeOther dark:dark];
    UIColor *tint=WXGColor([c materialHexForScope:WXGGlassScopeOther dark:dark]);
    CGFloat red=0,green=0,blue=0,alpha=0;
    [tint getRed:&red green:&green blue:&blue alpha:&alpha];
    double veil[4]={red,green,blue,alpha*[c materialOpacityForScope:WXGGlassScopeOther dark:dark]};
    float matrix[20]; WXGRim26Matrix(s.gain,s.chroma,s.lift,matrix);
    // The same neutral base used by the existing capture if a scene image
    // is not yet available. Its coloured rim is ready on this very frame.
    uint8_t gray=dark?28:245,neutral[4]={gray,gray,gray,255};
    const uint8_t *source=_scenePixels?_scenePixels.bytes:neutral;
    size_t count=_scenePixels?_sampleWidth*_sampleHeight:1;
    _edgeColours=[NSMutableData dataWithLength:count*3];
    uint8_t *edge=_edgeColours.mutableBytes;
    for(size_t i=0;i<count;i++)WXGMenuMorphRimColour(source+i*4,tone.saturation,tone.brightness,veil,matrix,edge+i*3);
}

// Only cells touching the rim need a raster sample. Both appearances use
// the measured angular key/fill profile, depth falloff and colour matrix.
// The parent's one path clips the outer edge, including the outer half-pixel.
- (void)updateRimForField:(const WXGMenuMorphField *)field bounds:(CGRect)b config:(WXGConfig *)c dark:(BOOL)dark {
    WXGRim26Settings s=[c rim26ForScope:WXGGlassScopeOther dark:dark];
    NSUInteger revision=WXGConfigRevision();
    if(!_levelsReady || _rimRevision!=revision || _rimDark!=dark) {
        _levelsReady=YES; _rimRevision=revision; _rimDark=dark;
        _lights.glow=[c rimStyleForScope:WXGGlassScopeOther]==WXGRimStyleGlow;
        _lights.shape=(WXGRim26Shape){s.height,s.curve,s.angle,s.key,s.fill,s.spread,s.ring,0,s.floor};
        _lights.opacity=s.opacity;
        if(_lights.glow)for(int k=0;k<WXGRimGlowCount;k++)_lights.lights[k]=[c rimGlowForScope:WXGGlassScopeOther index:k dark:dark];
        WXGMenuMorphRimPrepareLights(&_lights);
    }
    _rimLayer.hidden=WXGMenuMorphRimReach(&_lights)<=0;
    if(_rimLayer.hidden)return;
    if(!_lights.glow)[self prepareRimColours:c settings:s dark:dark];
    CGFloat screen=self.window.screen.scale?:UIScreen.mainScreen.scale;
    CGFloat scale=MIN(screen,1024./MAX(1.,MAX(b.size.width,b.size.height)));
    NSUInteger w=MAX(1,ceil(b.size.width*scale)),h=MAX(1,ceil(b.size.height*scale)),stride=w*4;
    NSMutableData *data=[NSMutableData dataWithLength:stride*h];
    WXGMorphRimColours colours={_edgeColours.bytes,_scenePixels?_sampleWidth:1,_scenePixels?_sampleHeight:1,
        _sampleRect.origin.x,_sampleRect.origin.y,
        _scenePixels?_sampleWidth/_sampleRect.size.width:0,_scenePixels?_sampleHeight/_sampleRect.size.height:0};
    WXGMenuMorphRimDraw(field,(WXGMenuMorphFieldBox){b.origin.x,b.origin.y,b.size.width,b.size.height,0},
        (int)w,(int)h,data.mutableBytes,&_lights,colours);
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image=CGImageCreate(w,h,8,32,stride,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    _rimLayer.frame=b;_rimLayer.contentsScale=scale;_rimLayer.contents=(__bridge id)image;
    if(image)CGImageRelease(image);
}

// Each band starts on the same zero contour as the face. Its outer half
// is clipped by the surface's matching path. Keep the layers between frames.
static NSUInteger WXGPlaceMorphBands(CALayer *holder,WXGRim26Bands recipe,CGPathRef path,CGRect bounds,CGFloat scale) {
    NSUInteger used=0;
    for(int i=0;i<recipe.count;i++) {
        if(recipe.width[i]<.001 || recipe.alpha[i]<.001)continue;
        CAShapeLayer *band;
        if(used<holder.sublayers.count)band=(CAShapeLayer *)holder.sublayers[used];
        else {
            band=[CAShapeLayer layer];band.name=@"morph.rim.band";
            band.fillColor=nil;band.strokeColor=UIColor.whiteColor.CGColor;
            band.lineJoin=kCALineJoinRound;[holder addSublayer:band];
        }
        band.frame=bounds;band.contentsScale=scale;band.path=path;
        band.lineWidth=2*recipe.width[i];band.opacity=recipe.alpha[i];band.hidden=NO;
        ++used;
    }
    for(NSUInteger i=used;i<holder.sublayers.count;i++)holder.sublayers[i].hidden=YES;
    return used;
}

// The lights follow the outward normal of the union. Sampling at the cell
// centres matches the same interpolated field that generated the outline;
// in particular the tiny incoming menu cannot alter the resting button's
// angular highlight before it actually reaches its circumference.
- (void)placeDirectionalLightForField:(const WXGMenuMorphField *)field inRect:(CGRect)b {
    int width=field->width-1,height=field->height-1;
    NSMutableData *data=[NSMutableData dataWithLength:(size_t)width*height*sizeof(uint32_t)];
    uint32_t *pixels=data.mutableBytes;
    for(int y=0;y<height;y++)for(int x=0;x<width;x++) {
        const float *p=&field->values[y*field->width+x];
        float dx=(p[1]-p[0])+(p[field->width+1]-p[field->width]);
        float dy=(p[field->width]-p[0])+(p[field->width+1]-p[1]);
        float length=fmaxf(hypotf(dx,dy),.001f);
        WXGMenuMorphFieldSample normal={0,dx/length,dy/length};
        float level=WXGMorphAngularValue(&_directionLights,0,normal);
        uint32_t alpha=(uint32_t)lroundf(255*level);
        pixels[y*width+x]=alpha*0x01010101u;
    }
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(width,height,8,32,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,
        provider,NULL,true,kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);CGDataProviderRelease(provider);
    if(image) {
        _directionField.frame=CGRectMake(field->x-b.origin.x,field->y-b.origin.y,width*field->step,height*field->step);
        _directionField.contents=(__bridge id)image;
        CGImageRelease(image);
    }
}

- (void)placeRimForField:(const WXGMenuMorphField *)field bounds:(CGRect)b outline:(UIBezierPath *)outline
                  config:(WXGConfig *)c dark:(BOOL)dark {
    _rimView.frame=b;
    CGRect local=_rimView.bounds;
    BOOL ios26=[c rimStyleForScope:WXGGlassScopeOther]!=WXGRimStyleGlow;
    WXGRim26Settings s=[c rim26ForScope:WXGGlassScopeOther dark:dark];
    _usesLivePaint=ios26 && [_livePaint live] && WXGFilterFactoryAvailable();
    CGFloat scale=self.window.screen.scale?:UIScreen.mainScreen.scale;
    CGFloat pad=1./(MAX(1.,scale)*MAX(.1,s.captureScale));
    if(_usesLivePaint) {
        WXGRimMatrix matrix;WXGRim26Matrix(s.gain,s.chroma,s.lift,matrix.m);
        _livePaint.frame=CGRectInset(local,-pad,-pad);
        [_livePaint configureGroup:_rimGroup matrix:matrix captureScale:s.captureScale solid:nil];
        _usesLivePaint=_livePaint.layer.filters.count>0;
    }
    _paintConfigured=YES;
    _livePaint.hidden=!_usesLivePaint;
    if(!_usesLivePaint) {
        [self updateRimForField:field bounds:b config:c dark:dark];
        _rimLayer.frame=local;
        return;
    }
    _rimLayer.hidden=YES;
    _edgeMask.frame=CGRectOffset(local,pad,pad);_edgeMask.opacity=s.opacity;
    _plainBands.frame=local;_directional.frame=local;
    WXGRim26Shape shape={s.height,s.curve,s.angle,s.key,s.fill,s.spread,s.ring,0,s.floor};
    CGAffineTransform shift=CGAffineTransformMakeTranslation(-b.origin.x,-b.origin.y);
    CGPathRef path=CGPathCreateCopyByTransformingPath(outline.CGPath,&shift);
    _bandCount=WXGPlaceMorphBands(_plainBands,WXGRim26BandsFor(1,shape,scale),path,local,scale);
    _bandCount+=WXGPlaceMorphBands(_directional,WXGRim26BandsFor(0,shape,scale),path,local,scale);
    CGPathRelease(path);
    NSUInteger revision=WXGConfigRevision();
    if(!_directionReady || _directionRevision!=revision || _directionDark!=dark) {
        _directionReady=YES;_directionRevision=revision;_directionDark=dark;
        _directionLights.shape=shape;WXGMenuMorphRimPrepareLights(&_directionLights);
    }
    [self placeDirectionalLightForField:field inRect:b];
}

- (NSDictionary *)rimEvidence {
    CALayer *paint=_usesLivePaint?_livePaint.layer:_rimLayer;
    CALayer *visible=paint.presentationLayer;
    return @{@"paint":[NSString stringWithFormat:@"%p",paint],@"type":_usesLivePaint?@"livePostGlassMatrix":@"raster",
        @"paintAttached":@(paint.superlayer==_rimView.layer),@"hidden":@(paint.hidden),
        @"opacity":@(paint.opacity),@"presentationAvailable":@(visible!=nil),
        @"presentationOpacity":@(visible.opacity),@"bands":@(_usesLivePaint?_bandCount:0),
        @"coverage":@(_usesLivePaint?_edgeMask.opacity:!_rimLayer.hidden),
        @"opticalMesh":@{@"accepted":@(_meshAccepted),@"vertices":@(_meshAccepted?_optics.vertexCount:0),
            @"faces":@(_meshAccepted?_optics.faceCount:0),@"channels":@(_channels),@"setupMS":@(_meshMS),
            @"captureRect":NSStringFromCGRect(_captureRect),@"sessionStep":@(_opticalSessionStep),@"field":_meshAccepted?(_opticsGaussian?@"gaussianVector":@"analytic"):@"none"},
        @"paintBounds":NSStringFromCGRect(paint.bounds),@"presentationBounds":NSStringFromCGRect(visible.bounds)};
}
static BOOL WXGInstallMorphMesh(CALayer *layer,id mesh) {
    if(![layer respondsToSelector:NSSelectorFromString(@"setMeshTransform:")])return !mesh;
    @try {
        [layer setValue:mesh forKey:@"meshTransform"];
        return !mesh || [layer valueForKey:@"meshTransform"]!=nil;
    } @catch(__unused NSException *error) {return NO;}
}

- (void)stripAnimations {
    [self.layer removeAllAnimations];
    [_veil removeAllAnimations];
    [_rimView.layer removeAllAnimations];
    [_rimLayer removeAllAnimations];
    [_livePaint.layer removeAllAnimations];
    [_edgeMask removeAllAnimations];
    [_directionField removeAllAnimations];
    [_fallback.layer removeAllAnimations];
    for(NSUInteger k=0;k<3;k++)[_backdrops[k].layer removeAllAnimations];
}

- (const WXGMenuMorphField *)prepareSessionFieldForMenu:(WXGMenuMorphFieldBox)menu radiusY:(float)ry
                                                 source:(WXGMenuMorphFieldBox)source smoothing:(float)smoothing
                                           windowOrigin:(CGPoint)origin {
    float step=(float)_opticalSessionStep;
    float weights[WXGMenuMorphFieldKernel+1];
    if(step<=0.f || smoothing<=0.f || WXGMenuMorphKernel(smoothing/step,WXGMorphFieldSessionTexture,weights)<=0)return NULL;
    if(!_sessionField)_sessionField=malloc(sizeof(*_sessionField));
    if(!_sessionField)return NULL;
    WXGMenuMorphFieldBox winMenu={menu.x+(float)origin.x,menu.y+(float)origin.y,menu.width,menu.height,menu.radius};
    WXGMenuMorphFieldBox winSource={source.x+(float)origin.x,source.y+(float)origin.y,source.width,source.height,source.radius};
    WXGMenuMorphFieldBuildMode(_sessionField,winMenu,ry,winSource,smoothing,step,WXGMorphFieldSessionTexture);
    WXGMenuMorphFieldTranslate(_sessionField,-(float)origin.x,-(float)origin.y);
    return _sessionField->gaussian?_sessionField:NULL;
}

- (void)applyField:(const WXGMenuMorphField *)field bounds:(CGRect)b outline:(UIBezierPath *)outline {
    CGFloat side=MIN(b.size.width,b.size.height);
    [self applyField:field sessionField:NULL bounds:b outline:outline optics:(WXGMenuMorphSurfaceOptics){0.,0.,0.,0.,side,side}];
}

- (void)applyField:(const WXGMenuMorphField *)field bounds:(CGRect)b outline:(UIBezierPath *)outline optics:(WXGMenuMorphSurfaceOptics)optics {
    [self applyField:field sessionField:NULL bounds:b outline:outline optics:optics];
}

- (void)applyField:(const WXGMenuMorphField *)field sessionField:(const WXGMenuMorphField *)session
            bounds:(CGRect)b outline:(UIBezierPath *)outline optics:(WXGMenuMorphSurfaceOptics)optics {
    [UIView performWithoutAnimation:^{
    self.frame=b;
    WXGConfig *c=WXGConfig.shared;
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    CGFloat side=MIN(b.size.width,b.size.height);
    CGFloat t=WXGClamp(optics.contentProgress,0.,1.);
    CGFloat smallSide=optics.triggerSide>1.?optics.triggerSide:side;
    CGFloat largeSide=optics.menuSide>1.?optics.menuSide:side;
    CGFloat smallBlur=[c glassBlurForScope:WXGGlassScopeOther side:smallSide]*c.syncBlurScale;
    CGFloat largeBlur=[c glassBlurForScope:WXGGlassScopeOther side:largeSide]*c.syncBlurScale;
    CGFloat morphBlur=MIN(smallBlur,1.2*c.syncBlurScale);
    CGFloat clearing=MIN(t*6.,1.);
    CGFloat baseBlur=smallBlur+(morphBlur-smallBlur)*clearing;
    CGFloat blur=MAX(0.,baseBlur+(largeBlur-baseBlur)*t*t*t);
    WXGBackdropTone tone=[c backdropToneForScope:WXGGlassScopeOther dark:dark];
    WXGGlassCurve curve=[c glassCurveForScope:WXGGlassScopeOther];
    BOOL split=!_fallback && curve.dispersion>.001 && c.syncMeshRefraction && c.syncDispersion && !c.performanceMode && WXGMeshTransformClass();
    CFTimeInterval begin=CACurrentMediaTime();
    _captureRect=self.bounds;_opticsGaussian=field->gaussian;
    id meshes[3]={nil,nil,nil};
    BOOL enabled=!_fallback && c.syncMeshRefraction && curve.height>0 && curve.amount>0 &&
        WXGMeshTransformClass() && [_backdrops[0].layer respondsToSelector:NSSelectorFromString(@"setMeshTransform:")];
#ifdef WXG_MESH_OFF
    enabled=NO;
#endif
    float restBand=MIN(curve.height*side,curve.maxHeight);
    float rawRestAmount=curve.height>0?restBand*curve.amount/curve.height:0.f;
    float morphAmountCap=(float)(.52*side);
    float morphGate=(float)WXGClamp(optics.portalBlur/3.0,0.,1.);
    float restAmount=rawRestAmount>morphAmountCap?rawRestAmount+(morphAmountCap-rawRestAmount)*morphGate:rawRestAmount;
    float refractionScale=(float)WXGClamp(curve.amount/.8,0.,2.);
    float morphBand=refractionScale>.001f?(float)MAX(0.,optics.lensHeight):0.f;
    float morphAmount=(float)fabs(optics.lensAmount)*refractionScale;
    float band=fmaxf(restBand,morphBand);
    float amount=fmaxf(restAmount,morphAmount);
    float squeeze=curve.squeeze;
    WXGMenuMorphFieldBox box={(float)b.origin.x,(float)b.origin.y,(float)b.size.width,(float)b.size.height,0};
    const WXGMenuMorphField *opticalField=field;
    // Reuse the window-anchored Gaussian session field already sampled for the
    // contour when present; otherwise build it on demand for direct callers.
    if(enabled && session && session->gaussian) {
        opticalField=session;
    }else {
        float step=_opticalSessionStep>0?(float)_opticalSessionStep:field->step;
        float weights[WXGMenuMorphFieldKernel+1];
        if(enabled && field->smoothing>0 && WXGMenuMorphKernel(field->smoothing/step,WXGMorphFieldSessionTexture,weights)>0){
            if(!_sessionField)_sessionField=malloc(sizeof(*_sessionField));
            if(_sessionField){
                CGPoint origin=self.window?[self.superview convertPoint:CGPointZero toView:self.window]:CGPointZero;
                WXGMenuMorphBuildSessionField(_sessionField,field,(float)origin.x,(float)origin.y,step);
                opticalField=_sessionField;
            }
        }
    }
    _opticsGaussian=opticalField->gaussian;
    _meshAccepted=enabled && WXGMorphOpticalBuild(&_optics,opticalField,box,band,amount,
        squeeze,split?curve.dispersion:0);
    split=split && _meshAccepted;
    if(_meshAccepted){
        [self updateCaptureBoundsForBlur:blur split:split];
        for(NSUInteger k=0;k<(split?3u:1u);k++){
            meshes[k]=[self opticalTransformForChannel:k split:split];
            if(!meshes[k]){_meshAccepted=NO;break;}
        }
        if(!_meshAccepted && split){
            split=NO;meshes[0]=[self opticalTransformForChannel:0 split:NO];_meshAccepted=meshes[0]!=nil;
        }
    }
    _optics.field=NULL; // The per-frame distance field is stack-owned.
    for(NSUInteger k=0;k<(split?3u:1u);k++){
        if(!_backdrops[k]){
            _backdrops[k]=[[WXGSyncBackdropView alloc] initWithFrame:self.bounds];
            [self insertSubview:_backdrops[k] aboveSubview:_backdrops[k-1]];
        }
        _backdrops[k].frame=_captureRect;
        if(!WXGInstallMorphMesh(_backdrops[k].layer,meshes[k]))_meshAccepted=NO;
    }
    // A system may expose the transform selector yet reject a channel
    // mesh. Reconfigure as one full-colour capture in the same transaction.
    if(split && !_meshAccepted){
        split=NO;id central=[self opticalTransformForChannel:0 split:NO];
        _meshAccepted=central && WXGInstallMorphMesh(_backdrops[0].layer,central);
    }
    if(!_meshAccepted)WXGInstallMorphMesh(_backdrops[0].layer,nil);
    _channels=split?3:1;
    for(NSUInteger k=0;k<3;k++){
        WXGSyncBackdropView *backdrop=_backdrops[k];
        if(k>=_channels || _fallback){backdrop.hidden=YES;continue;}
        backdrop.hidden=NO;
        [backdrop configureGroup:_group radius:blur channel:split?k+1:0 plain:NO tone:tone];
        [backdrop applyCaptureScale];
    }
    if(_fallback){_fallback.frame=self.bounds;_fallback.hidden=blur<.2;}
    _meshMS=(CACurrentMediaTime()-begin)*1000;
    UIColor *tint=WXGColor([c materialHexForScope:WXGGlassScopeOther dark:dark]);
    CGFloat baseAlpha=CGColorGetAlpha(tint.CGColor)*[c materialOpacityForScope:WXGGlassScopeOther dark:dark];
    CGFloat morphActivity=WXGClamp(MAX((band-restBand)/28.,optics.portalBlur/4.0),0.,1.);
    CGFloat alpha=baseAlpha*(1.-(dark?.42:.28)*morphActivity);
    _veil.frame=self.bounds;_veil.backgroundColor=[tint colorWithAlphaComponent:WXGClamp(alpha,0,1)].CGColor;
    [self placeRimForField:field bounds:b outline:outline config:c dark:dark];
    }];
}
@end
