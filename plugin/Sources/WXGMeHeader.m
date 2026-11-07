#import "WXGIntegration.h"
#import "WXGMeMetaball.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <PhotosUI/PhotosUI.h>

/* FIX118 A (user, 11-04: the 我 page as Telegram's profile: "将二维码作为一个左
   上方的按钮，其余的详细资料列一个单独的列表条，昵称微信号，状态那块居中放在头像下";
   the expo-scroll-metaball effect: scrolled up, the avatar melts into the
   Dynamic Island (into the notch on a notched phone, or only shrinks and fades,
   as the user chooses); "右上角 … 一个胶囊和设置两个字加入我们自己的设置"; a switch:
   off, only the avatar going up; on, pulling down opens the avatar into a
   banner whose lower edge moves as a liquid, in place of WeChat's own pull
   (its 状态, still reached from the status buttons).

   What is WeChat's stays WeChat's (FIX117 D's probe, diagnostics_16 on the XS
   Max: MoreViewController, its TextStateProfileTableView inside a 2-screen
   MMUIButton that WeChat's TextStateProfileDragAnimateHelper drags for its
   status page; the header a 144 pt MMUIButton whose action is showProfileView):
   - the avatar (MMHeadImageView), the name and ID labels, the QR button and
     the chevron are masked (WXGStateBag conceal, restorable); the QR button no
     longer takes touches where it was (it is a bar button now, which sends
     WeChat's QR button its own action);
   - WeChat's two status buttons are moved (their centres, before each commit
     and in their own layout) to a row under the name, still inside the header,
     so they take their own touches;
   - the list gets more room at its top (its inset) for the new header and, if
     it is too short to be scrolled that far, at its bottom;
   - the bar gets a QR button on the left and 设置 on the right (navigationItem;
     WeChat's own items, none on this page, are given back);
   - with the banner on: WeChat's drag recognizer is switched off and the list
     bounces (both given back).
   Drawn by the plugin, in a view above the list (no touches): the name and ID
   centred (FIX119 B: one name, collapsing into the bar's title as Telegram's;
   FIX120 H: no bar background of our own, the bar stays the plugin's glass over
   the list as on every other page), and the avatar, the
   cut-out and the banner in one Metal pass (the shader below, after
   expo-scroll-metaball's), its layer only as tall as what it draws. */

typedef struct {float size[2];float scale;float time;float island[4];float islandShape[4];float avatar[4];float effect[4];float drop[4];float image[4];float video[4];float fx[4];} WXGMBUniforms;

static const char *WXGMBShaderSource=
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct WXGMBOut{float4 position [[position]];float2 uv;};\n"
"struct WXGMBUniforms{float2 size;float scale;float time;float4 island;float4 islandShape;float4 avatar;float4 effect;float4 drop;float4 image;float4 video;float4 fx;};\n"
"vertex WXGMBOut wxgmb_vertex(uint vid [[vertex_id]]){float2 p=float2(float((vid<<1)&2),float(vid&2));WXGMBOut o;o.position=float4(p.x*2.0-1.0,1.0-p.y*2.0,0.0,1.0);o.uv=p;return o;}\n"
"static float sdBox(float2 p,float2 c,float2 h,float r){float2 q=abs(p-c)-h+float2(r);return length(max(q,float2(0.0)))+min(max(q.x,q.y),0.0)-r;}\n"
"static float smoothUnion(float a,float b,float k){if(k<=0.0001)return min(a,b);float h=max(k-abs(a-b),0.0)/k;return min(a,b)-h*h*h*k*(1.0/6.0);}\n"
"static float sdDrop(float2 p,float r1,float r2,float h){float2 q=float2(abs(p.x),p.y);float b=(r1-r2)/h;float a=sqrt(max(1.0-b*b,0.0));float k=dot(q,float2(-b,a));if(k<0.0)return length(q)-r1;if(k>a*h)return length(q-float2(0.0,h))-r2;return dot(q,float2(a,b))-r1;}\n"
"static float hash1(float n){return fract(sin(n*12.9898)*43758.5453);}\n"
"static float glossAt(float2 p,float2 c,float r){float d=length(p-c+float2(r*0.32,r*0.38));return 1.0-smoothstep(r*0.08,r*0.5+0.01,d);}\n"
"static float2 dripsAt(float2 p,float edge,float left,float width,float amount,float t,float room){\n"
"  float2 acc=float2(100000.0,0.0);\n"
"  for(int i=0;i<7;i++){\n"
"    float fi=float(i);float seed=hash1(fi*1.7+0.3);\n"
"    float neck=mix(3.5,6.5,hash1(fi*4.1+0.7))*amount;float bulb=neck+mix(2.5,5.0,hash1(fi*8.3+0.1))*amount;\n"
"    float x=left+(fi+0.5+(seed-0.5)*0.7)/7.0*width;\n"
"    if(abs(p.x-x)>bulb*1.3+14.0)continue;\n"
"    float on=hash1(fi*6.6+0.2)>=0.4?1.0:0.0;float period=mix(2.6,4.4,hash1(fi*11.9+0.5));\n"
"    float s=fract(t/period+seed*3.1);float form=smoothstep(0.0,0.45,s)*on;float fall=max(s-0.45,0.0)/0.55*on;\n"
"    float sway=0.9+0.1*sin(t*0.9+fi*1.9)+0.18*form*(1.0-smoothstep(0.45,0.75,s));\n"
"    float h=max(min(64.0*amount*mix(0.25,1.0,seed)*sway,room*0.45),bulb-neck+0.5);\n"
"    float root=edge-neck;float tip=root+h;\n"
"    float dDrip=sdDrop(p-float2(x,root),max(neck,0.01),max(bulb,0.01),h);\n"
"    float r=bulb*0.95*form*(1.0-smoothstep(0.6,1.0,fall));float stretch=1.0+0.3*smoothstep(0.0,0.3,fall);\n"
"    float2 c=float2(x,tip+r*0.9+fall*fall*max(room-(tip-edge)-12.0,0.0));float2 bead=float2(p.x,c.y+(p.y-c.y)/stretch);\n"
"    float dBead=100000.0;\n"
"    if(r>0.5){dBead=length(bead-c)-r;acc.y=max(acc.y,glossAt(bead,c,r));}\n"
"    acc.y=max(acc.y,glossAt(p,float2(x,tip),bulb));\n"
"    acc.x=min(acc.x,smoothUnion(dDrip,dBead,bulb*1.6));\n"
"  }\n"
"  return float2(acc.x,acc.y*amount);\n"
"}\n"
"// FIX118 E: a drip's colour: the banner mirrored at its lower edge (what is just above it), blurred the more the deeper\n"
"static float3 blurTap(texture2d<float> t,sampler smp,float2 uv,float2 rad,float2 lo,float2 hi){\n"
"  float3 acc=float3(0.0);\n"
"  for(int i=0;i<8;i++){float fi=float(i);float a=fi*2.39996323;float rr=sqrt((fi+0.5)/8.0);acc+=t.sample(smp,clamp(uv+float2(cos(a),sin(a))*rad*rr,lo,hi),level(0.0)).rgb;}\n"
"  return acc/8.0;\n"
"}\n"
"fragment float4 wxgmb_fragment(WXGMBOut in [[stage_in]],constant WXGMBUniforms &u [[buffer(0)]],texture2d<float> photo [[texture(0)]],texture2d<float> video [[texture(1)]],sampler smp [[sampler(0)]]){\n"
"  float2 pos=in.uv*u.size;float aa=1.0/u.scale;\n"
"  float presence=u.islandShape.z;float expand=u.drop.z;float flow=u.drop.w;float radius=u.avatar.z;\n"
"  float top=mix(u.avatar.y-radius,0.0,expand);float bottom=u.avatar.y+radius;\n"
"  float2 extent=float2(mix(radius,u.size.x*0.5,expand),max((bottom-top)*0.5,0.001));\n"
"  float2 center=float2(u.avatar.x,(top+bottom)*0.5);\n"
"  float2 local=pos-u.avatar.xy;\n"
"  float dIsland=100000.0;\n"
"  if(presence>0.001){\n"
"    float2 h=max(u.island.zw-float2(u.islandShape.w),float2(0.5));\n"
"    if(u.islandShape.y>1.5){dIsland=sdBox(pos,u.island.xy,h*presence,h.y*presence);}\n"
"    else{float bot=u.island.y+h.y;float2 hh=float2(h.x*presence,(bot+60.0)*0.5);float2 c=float2(u.island.x,bot-hh.y);dIsland=sdBox(pos,c,hh,min(u.islandShape.x*presence,hh.x));}\n"
"  }\n"
"  float dShape=sdBox(pos,center,extent,radius*(1.0-expand));\n"
"  float gloss=0.0;\n"
"  float mode=u.fx.x;\n"
"  if(mode<0.5&&flow>0.0&&pos.y>bottom-40.0){\n"
"    dShape-=flow*2.5*sin(pos.x*0.045+u.time*0.8)*smoothstep(bottom-40.0,bottom,pos.y);\n"
"    float2 d=dripsAt(pos,bottom,center.x-extent.x,2.0*extent.x,flow,u.time,u.fx.y);\n"
"    dShape=smoothUnion(dShape,d.x,12.0*flow);gloss=d.y;\n"
"  }\n"

"  float dAvatar=radius>0.5?dShape:100000.0;\n"
"  if(radius>0.5&&expand<0.001&&u.drop.x>radius-u.drop.y+0.01)dAvatar=sdDrop(float2(local.x,-local.y),radius,max(u.drop.y,0.01),u.drop.x);\n"
"  float d=smoothUnion(dIsland,dAvatar,u.effect.y);\n"
"  float coverage=clamp(0.5-d/aa,0.0,1.0);\n"
"  if(coverage<=0.0)return float4(0.0);\n"
"  float3 color=float3(0.0);\n"
"  if(radius>0.5&&u.avatar.w<1.0){\n"
"    float feather=max(aa,u.effect.x*0.6);float edge=clamp(0.5-dShape/feather,0.0,1.0);float melt=1.0;\n"
"    if(u.effect.w>0.0&&presence>0.001){float soft=max(radius*0.8,8.0);float reach=bottom-(u.island.y+u.island.w)+soft;float front=mix(-soft,reach,u.effect.w);melt=smoothstep(front-soft,front+soft,dIsland);}\n"
"    float weight=clamp(edge/coverage,0.0,1.0)*melt*(1.0-u.avatar.w);\n"
"    if(weight>0.0){\n"
"      float2 uvShape=(pos-center)/(2.0*extent)+0.5;\n"
"      float depth=max(pos.y-bottom,0.0);\n"
"      if(uvShape.y>1.0)uvShape.y=2.0-uvShape.y;\n"
"      uvShape=clamp(uvShape,0.0,1.0);\n"
"      float mirrorBlur=depth>0.0?clamp(depth*0.35+2.0,2.0,18.0):0.0;\n"
"      float aspect=extent.x/extent.y;float img=u.image.x/max(u.image.y,1.0);\n"
"      float2 lo=float2(0.0);float2 sz=float2(1.0);\n"
"      if(img>aspect){sz.x=aspect/img;lo.x=(1.0-sz.x)*0.5;}else{sz.y=img/aspect;lo.y=(1.0-sz.y)*u.image.z;}\n"
"      float texelsPerPt=sz.y*u.image.y/max(2.0*extent.y,1.0);\n"
"      float lod=log2(max(max(u.effect.x,mirrorBlur)*texelsPerPt*0.5,1.0));\n"
"      float3 c=photo.sample(smp,lo+uvShape*sz,level(min(lod,u.image.w))).rgb;\n"
"      if(u.video.w>0.0){\n"
"        float vimg=u.video.x/max(u.video.y,1.0);float2 vlo=float2(0.0);float2 vsz=float2(1.0);\n"
"        if(vimg>aspect){vsz.x=aspect/vimg;vlo.x=(1.0-vsz.x)*0.5;}else{vsz.y=vimg/aspect;vlo.y=(1.0-vsz.y)*u.video.z;}\n"
"        float2 vuv=vlo+uvShape*vsz;\n"
"        float3 f=mirrorBlur>0.0?blurTap(video,smp,vuv,mirrorBlur/(2.0*extent)*vsz,vlo,vlo+vsz):video.sample(smp,vuv,level(0.0)).rgb;\n"
"        c=mix(c,f,u.video.w);\n"
"      }\n"
"      color=min(c*weight+gloss*0.35*weight,float3(weight));\n"
"    }\n"
"  }\n"
"  float a=coverage*u.effect.z;\n"
"  if(mode>0.5&&mode<1.5){\n"   // FIX118 F: the banner's lower part fades into the page (no drips, no mirroring)
"    float fadeLen=max((bottom-top)*0.38,64.0);float g=1.0-smoothstep(bottom-fadeLen,bottom,pos.y);\n"
"    g=g*g*(3.0-2.0*g);\n"
"    a*=mix(1.0,g,smoothstep(0.3,1.0,expand));\n"
"  }\n"
"  return float4(color*a,a);\n"
"}\n";

FOUNDATION_EXPORT id<MTLDevice> WXGSharedDevice(void);

// FIX119 E (diagnostics_22's stall samples: WXGMetaballView setPhoto: on the main thread when coming to 我): the shader
// built once, off the main thread, a few seconds after launch (a first visit before that builds it there, as before);
// a new photo after the first made into a texture off the main thread.
static id<MTLRenderPipelineState> WXGMBSharedPipeline;static NSString *WXGMBSharedFailure;
static void WXGMBBuildPipeline(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        id<MTLDevice> device=WXGSharedDevice();if(!device){WXGMBSharedFailure=@"没有 GPU";return;}
        NSError *error=nil;
        id<MTLLibrary> library=[device newLibraryWithSource:@(WXGMBShaderSource) options:nil error:&error];
        if(!library){WXGMBSharedFailure=[@"着色器编译失败：" stringByAppendingString:error.localizedDescription?:@"?"];return;}
        MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
        d.vertexFunction=[library newFunctionWithName:@"wxgmb_vertex"];d.fragmentFunction=[library newFunctionWithName:@"wxgmb_fragment"];
        d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
        id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];
        if(!pipeline){WXGMBSharedFailure=[@"管线失败：" stringByAppendingString:error.localizedDescription?:@"?"];return;}
        WXGMBSharedPipeline=pipeline;
    });
}
// The photo as an 8-bit RGBA texture with mipmaps (FIX118 D: a greyscale picture would load as red only), at most 512 px.
static id<MTLTexture> WXGMBTextureFor(UIImage *photo,NSString **failure) {
    CGSize px=CGSizeMake(photo.size.width*photo.scale,photo.size.height*photo.scale);
    if(px.width<1 || px.height<1)return nil;
    CGFloat f=MIN(1,512/MAX(px.width,px.height));CGSize out=CGSizeMake(round(px.width*f),round(px.height*f));
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];format.scale=1;format.opaque=NO;
    if(@available(iOS 12.0,*))format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIImage *drawn=[[[UIGraphicsImageRenderer alloc]initWithSize:out format:format] imageWithActions:^(__unused UIGraphicsImageRendererContext *c){[photo drawInRect:CGRectMake(0,0,out.width,out.height)];}];
    CGImageRef image=drawn.CGImage;if(!image)return nil;
    MTKTextureLoader *loader=[[MTKTextureLoader alloc]initWithDevice:WXGSharedDevice()];
    NSError *error=nil;
    id<MTLTexture> texture=[loader newTextureWithCGImage:image options:@{MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionAllocateMipmaps:@YES,
        MTKTextureLoaderOptionSRGB:@NO,MTKTextureLoaderOptionTextureUsage:@(MTLTextureUsageShaderRead)} error:&error];
    if(!texture && failure)*failure=[@"头像纹理失败：" stringByAppendingString:error.localizedDescription?:@"?"];
    return texture;
}

@interface WXGMetaballView : UIView
@property(nonatomic) WXGMBUniforms uniforms;
@property(nonatomic,copy) void (^photoReady)(void);   // FIX119 E: a photo made off the main thread is in
@property(nonatomic,copy) NSString *failure;
@property(nonatomic) NSUInteger frames;
@property(nonatomic,strong) id<MTLTexture> videoTexture;   // FIX118 B: the banner's video frame (nil: none)
- (void)setPhoto:(UIImage *)photo;
- (BOOL)render;
@end
@implementation WXGMetaballView {
    id<MTLRenderPipelineState> _pipeline;
    id<MTLCommandQueue> _queue;
    id<MTLTexture> _photo,_placeholder;
    id<MTLSamplerState> _sampler;
    BOOL _tried;NSUInteger _photoToken;
}
+ (Class)layerClass {return CAMetalLayer.class;}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;
        CAMetalLayer *layer=(CAMetalLayer *)self.layer;
        layer.opaque=NO;layer.pixelFormat=MTLPixelFormatBGRA8Unorm;layer.framebufferOnly=YES;layer.presentsWithTransaction=YES;
        layer.contentsScale=UIScreen.mainScreen.scale;
        // FIX120 F (user: a little pull flickers the avatar, one frame squashed / stretched): the canvas changes
        // height as the banner opens and closes; a frame the new drawable was not up yet showed the last one scaled
        // to the new bounds (UIKit's default, scale to fill). Pinned to the top unscaled it stays where it was (the
        // canvas grows and shrinks only at its bottom); with the drawable the bounds' size, as always, no change.
        self.contentMode=UIViewContentModeTop;
    }
    return self;
}
- (BOOL)prepare {
    if(_pipeline)return YES;
    if(_tried)return NO;
    _tried=YES;
    id<MTLDevice> device=WXGSharedDevice();if(!device){_failure=@"没有 GPU";return NO;}
    ((CAMetalLayer *)self.layer).device=device;
    WXGMBBuildPipeline();   // (FIX119 E: built off the main thread after launch; here only if 我 comes first)
    _pipeline=WXGMBSharedPipeline;
    if(!_pipeline){_failure=WXGMBSharedFailure?:@"管线失败";WXGLog(@"我页头部：%@",_failure);return NO;}
    _queue=[device newCommandQueue];
    MTLSamplerDescriptor *s=[MTLSamplerDescriptor new];
    s.minFilter=s.magFilter=MTLSamplerMinMagFilterLinear;s.mipFilter=MTLSamplerMipFilterLinear;
    s.sAddressMode=s.tAddressMode=MTLSamplerAddressModeClampToEdge;
    _sampler=[device newSamplerStateWithDescriptor:s];
    MTLTextureDescriptor *t=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    _placeholder=[device newTextureWithDescriptor:t];
    uint8_t grey[4]={128,128,128,255};
    [_placeholder replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:grey bytesPerRow:4];
    return YES;
}
- (void)setPhoto:(UIImage *)photo {
    if(![self prepare])return;
    NSUInteger token=++_photoToken;
    if(!_photo) {   // the first: at once (the avatar is drawn with it in this very pass)
        NSString *failure=nil;id<MTLTexture> texture=WXGMBTextureFor(photo,&failure);
        if(texture)_photo=texture;else if(failure)_failure=failure;
        return;
    }
    // a newer one (the HD photo arriving): made off the main thread, the old one shown meanwhile
    __weak WXGMetaballView *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString *failure=nil;id<MTLTexture> texture=WXGMBTextureFor(photo,&failure);
        dispatch_async(dispatch_get_main_queue(),^{
            WXGMetaballView *me=weakSelf;if(!me || me->_photoToken!=token || !texture)return;
            me->_photo=texture;
            if(me.photoReady)me.photoReady();
        });
    });
}
- (BOOL)render {
    if(![self prepare] || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;   // (never from the background: FIX117 A's pink)
    CAMetalLayer *layer=(CAMetalLayer *)self.layer;
    CGFloat scale=layer.contentsScale;CGSize size=self.bounds.size;
    if(size.width<1 || size.height<1)return NO;
    CGSize pixels=CGSizeMake(round(size.width*scale),round(size.height*scale));
    if(!CGSizeEqualToSize(layer.drawableSize,pixels))layer.drawableSize=pixels;
    id<CAMetalDrawable> drawable=[layer nextDrawable];if(!drawable)return NO;
    WXGMBUniforms u=_uniforms;u.size[0]=size.width;u.size[1]=size.height;u.scale=scale;
    id<MTLTexture> photo=_photo?:_placeholder;
    u.image[0]=photo.width;u.image[1]=photo.height;u.image[3]=MAX((float)photo.mipmapLevelCount-1,0);
    id<MTLTexture> video=_videoTexture;
    if(video){u.video[0]=video.width;u.video[1]=video.height;}else u.video[3]=0;
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLCommandBuffer> buffer=[_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder=[buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:_pipeline];
    [encoder setFragmentBytes:&u length:sizeof u atIndex:0];
    [encoder setFragmentTexture:photo atIndex:0];[encoder setFragmentTexture:video?:_placeholder atIndex:1];[encoder setFragmentSamplerState:_sampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [buffer commit];[buffer waitUntilScheduled];[drawable present];   // (presentsWithTransaction: with this commit, in step with the list)
    ++_frames;
    return YES;
}
@end

static char WXGMeNativeCenterKey,WXGMeAppliedCenterKey,WXGMeFadedKey,WXGMeNativeAlphaKey;
/* FIX120 G (user, diagnostics_7 and the 11-06 recording: "灵动岛也闪，头像也闪，名字也闪 … 滑到顶部区域之后就会开始闪"):
   the host's page-top cleaning (WXGHost clearPageTopPaint, FIX29: WeChat paints the bar's background with a full-width
   view inside the page, exactly 0..navBottom, and a hairline at navBottom) took the header's own bar background for
   WeChat's: it is just that. Every quarter second while the page moved it was cleared (and the line under it hidden),
   and the header's next pass painted it again: the background behind the title, the avatar and the cut-out came and
   went, the status row and the list showing through under the island in between. Everything in the overlay is ours. */
static __weak UIView *WXGMeOverlay;
BOOL WXGMeHeaderOwnsView(UIView *view) {
    UIView *overlay=WXGMeOverlay;
    return overlay && view && (view==overlay || [view isDescendantOfView:overlay]);
}
// FIX120 G: the header's flight recorder (each pass's state, as it changed) in the debug build's diagnostics only
#if defined(WXG_RELEASE) && WXG_RELEASE
#define WXGME_TRACE 0
#else
#define WXGME_TRACE 1
#endif

@interface WXGMeHeader () <PHPickerViewControllerDelegate,UIGestureRecognizerDelegate>
- (void)update;
- (void)statusLaidOut:(UIView *)view;
@end

@implementation WXGMeHeader {
    __weak UIViewController *_page;
    __weak UITableView *_table;
    __weak UIControl *_header,*_qr;
    __weak UIView *_avatar,*_photoView,*_chevron;
    __weak UILabel *_name,*_wxid;
    NSHashTable<UIView *> *_status;       // WeChat's status buttons (weakly)
    __weak UIPanGestureRecognizer *_dragPan,*_tablePan;
    WXGStateBag *_states;
    UIView *_overlay,*_labels;
    UILabel *_bigName,*_bigID;UIFont *_bigFont,*_idFont;
    WXGMetaballView *_metal;
    // FIX119 B: Telegram's segments (the title locks in the bar, then the bar's background comes in as a step)
    CGFloat _titleCollapse,_collapseAll;WXGMeTitlePose _titlePose;
    // FIX119 B: a pass with nothing changed does nothing (diagnostics, 16 Pro Max: 3 ms on every pass, standing still)
    double _sig[28];BOOL _haveSig;CFTimeInterval _auditAt;NSUInteger _skips,_fullPasses;
    CGFloat _canvasHeight;
    UIImage *_shownPhoto;CFTimeInterval _photoAt,_findAt,_snapUntil,_start,_partsTriedAt,_renderedAt;
    UIEdgeInsets _baseInsets,_appliedInsets;BOOL _insetsApplied;
    BOOL _bouncesWas,_alwaysBounceWas,_bounceTouched,_dragWasEnabled,_dragTouched,_qrTouchWas,_qrTouched;
    UIBarButtonItem *_leftWas,*_rightWas,*_leftItem,*_rightItem;BOOL _itemsTouched;
    __weak UINavigationItem *_itemsOn;
    WXGMBUniforms _lastUniforms;BOOL _haveLast;
    CADisplayLink *_link;
    WXGMeLayout _layout;BOOL _haveLayout;
    // FIX118 B: the banner pull (WeChat keeps its list from going past its top, diagnostics_17: so the list's top inset grows by
    // the pull and its offset follows, which WeChat lets be; a spring of our own brings it back or to the open banner)
    UITapGestureRecognizer *_avatarTap;CGPoint _avatarWindowCenter;CGFloat _avatarWindowRadius;NSUInteger _avatarTaps;
    CGFloat _dripRoom,_contentPull;
    CGFloat _pull,_pullTarget,_pullVelocity,_pullBase,_pullAtBegin,_pullVisual;BOOL _pulling,_locked,_pullSpring,_pullPinned;CFTimeInterval _pullStepAt;NSUInteger _locks;
    // FIX118 B: the banner's video
    AVPlayer *_player;AVPlayerItemVideoOutput *_videoOut;CVMetalTextureCacheRef _textureCache;CVMetalTextureRef _videoRef,_videoRefOld;
    CVPixelBufferRef _videoBuffer,_videoBufferOld;BOOL _videoPlaying;NSUInteger _videoFrames;NSString *_videoNote;id _loopObserver;
    NSString *_status_;CGFloat _shift,_collapse,_travel;WXGCutout _cutout;BOOL _merge,_banner;NSUInteger _snaps,_renders,_passes;
    NSUInteger _statusMoves;CGFloat _statusMovedY;   // FIX120 F: WeChat moving its status row after us (diagnostics)
    // FIX120 G (user, diagnostics_7: "灵动岛也闪，头像也闪，名字也闪 … 滑到顶部区域之后就会开始闪"): what each pass did
    NSMutableArray<NSString *> *_trace;NSString *_traceLast,*_coveredBy;__weak UIView *_coveredView;NSUInteger _traceRepeat;char _renderNote;
    NSUInteger _restores,_insetRetakes,_overlayCovered,_gateSkips;double _worstRenderMS;
    // FIX120 I: WeChat's drag helper moving the list's container with the list's own pan (the lift: how far up, on the screen)
    CGFloat _tableHome,_tableYSeen,_lift,_maxLift,_shownTravel;CFTimeInterval _tableYSince;BOOL _haveTableHome;
    NSMapTable *_heldTargets;__weak UIPanGestureRecognizer *_heldPan;NSUInteger _targetHolds;NSString *_panTargetsSeen,*_helperMethods,*_tableObservers;
    // FIX120 J: the banner's video ready before it is needed; the layer not made taller in the middle of the pull
    BOOL _videoLoading,_pageShown,_canvasOpen;NSUInteger _videoToken,_canvasResizes;CFTimeInterval _visibleSince,_videoWantedAt,_videoFirstAt;
    CGSize _videoNatural,_videoOutSize;double _lastRenderMS;
}
+ (instancetype)shared {
    static WXGMeHeader *header;static dispatch_once_t once;
    dispatch_once(&once,^{
        header=[self new];header->_start=CACurrentMediaTime();header->_status=[NSHashTable weakObjectsHashTable];header->_states=[WXGStateBag new];
        // FIX119 E: the shader built off the main thread once things have settled after launch
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{WXGMBBuildPipeline();});
        __weak WXGMeHeader *weakHeader=header;
        // Before each commit (with WeChat's layout of this pass done): the header laid out and drawn in step with the list.
        CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,kCFRunLoopBeforeWaiting|kCFRunLoopExit,YES,1999750,
            ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a){WXGPerfTimePluginWorkAs("meHeader",^{[weakHeader update];});});   // FIX119 A: timed
        if(observer){CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);CFRelease(observer);}
        // WeChat's status buttons laying themselves out: put back in our row at once. (A frame WeChat lays its header out in
        // without their own layout running can still show them at its place for that one frame: rare, on a status change.)
        for(NSString *name in @[@"TextStatePublishEntryButton",@"TextStateFriendTopicButton"]) {
            Class cls=NSClassFromString(name);Method m=cls?class_getInstanceMethod(cls,@selector(layoutSubviews)):NULL;if(!m)continue;
            IMP old=method_getImplementation(m);
            IMP replacement=imp_implementationWithBlock(^(UIView *view){
                ((void (*)(id,SEL))old)(view,@selector(layoutSubviews));
                [weakHeader statusLaidOut:view];
            });
            WXGInstallOverride(cls,@selector(layoutSubviews),replacement,method_getTypeEncoding(m));
        }
    });
    return header;
}
// FIX118 F: the banner's lower edge: 0 drips, 1 fading into WeChat's page, 2 plain
static int WXGMeEdgeStyle(void) {return (int)lround(WXGMBLerp([WXGConfig.shared extraNumber:@"meBannerEdgeStyle"],0,2,0,2));}
static BOOL WXGMeOn(void) {return WXGPluginEnabled() && [WXGConfig.shared extraNumber:@"meHeader"]>.5;}

#pragma mark - Finding WeChat's page and parts

- (UIViewController *)findPage {
    UIViewController *page=_page;
    if(page)return page;
    CFTimeInterval now=CACurrentMediaTime();if(now-_findAt<1)return nil;_findAt=now;
    NSMutableArray<UIViewController *> *queue=[NSMutableArray array];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class])for(UIWindow *w in ((UIWindowScene *)scene).windows)if(w.rootViewController && !w.hidden)[queue addObject:w.rootViewController];
    Class more=NSClassFromString(@"MoreViewController");
    for(NSUInteger i=0;i<queue.count && i<200;i++) {
        UIViewController *vc=queue[i];
        if(more && [vc isKindOfClass:more]){_page=vc;return vc;}
        [queue addObjectsFromArray:vc.childViewControllers];
        if([vc isKindOfClass:UITabBarController.class])[queue addObjectsFromArray:((UITabBarController *)vc).viewControllers?:@[]];
        if([vc isKindOfClass:UINavigationController.class])[queue addObjectsFromArray:((UINavigationController *)vc).viewControllers];
        if(vc.presentedViewController)[queue addObject:vc.presentedViewController];
    }
    return nil;
}
- (NSArray<UIView *> *)statusViews {
    return _status.allObjects;
}
// The header's parts (looked up again when WeChat made a new header or they went away).
- (BOOL)findPartsOn:(UIViewController *)page {
    UITableView *table=_table;UIControl *header=_header;
    if(table && header && [header isDescendantOfView:table] && [table isDescendantOfView:page.view] && _name && _avatar)return YES;
    table=nil;header=nil;
    CFTimeInterval now=CACurrentMediaTime();if(now-_partsTriedAt<.5)return NO;_partsTriedAt=now;   // (a page without them is not searched on every pass)
    Class profileTable=NSClassFromString(@"TextStateProfileTableView");
    for(UIView *v in WXGViews(page.view,300))if([v isKindOfClass:UITableView.class] && !WXGIsPluginView(v) && (!profileTable || [v isKindOfClass:profileTable])){table=(id)v;break;}
    if(!table){_status_=@"没有找到“我”页的列表";return NO;}
    for(UIView *v in WXGViews(table,300))if([v isKindOfClass:UIControl.class] && v.bounds.size.width>200 && [WXGActionNames((id)v) containsObject:@"showProfileView"]){header=(id)v;break;}
    if(!header){_status_=@"列表里没有头部（showProfileView）";return NO;}
    UIView *avatar=nil,*photo=nil,*chevron=nil;UIControl *qr=nil;NSMutableArray<UILabel *> *labels=[NSMutableArray array];
    NSMutableArray *status=[NSMutableArray array];
    Class publish=NSClassFromString(@"TextStatePublishEntryButton"),topic=NSClassFromString(@"TextStateFriendTopicButton");
    NSArray<UIView *> *all=WXGViews(header,160);
    for(UIView *v in all)if((publish && [v isKindOfClass:publish]) || (topic && [v isKindOfClass:topic]))[status addObject:v];
    BOOL (^inStatus)(UIView *)=^BOOL(UIView *v){for(UIView *s in status)if([v isDescendantOfView:s])return YES;return NO;};
    for(UIView *v in all)if([v isKindOfClass:UIControl.class] && [WXGActionNames((id)v) containsObject:@"onShowMyQrCode"]){qr=(id)v;break;}
    for(UIView *v in all) {
        if(v==header || v==qr || WXGIsPluginView(v) || inStatus(v) || (qr && [v isDescendantOfView:qr]))continue;
        CGRect r=[v convertRect:v.bounds toView:header];
        if([NSStringFromClass(v.class) rangeOfString:@"HeadImageView"].location!=NSNotFound && r.size.width>=40 && r.size.width<=110 && fabs(r.size.width-r.size.height)<4) {
            if(!avatar || r.size.width>avatar.bounds.size.width)avatar=v;
        }else if([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length)[labels addObject:(id)v];
        else if([v isKindOfClass:UIImageView.class] && r.size.width<=16 && r.size.height>=16 && r.size.height<=32 && CGRectGetMidX(r)>header.bounds.size.width*.85)chevron=v;
    }
    if(avatar)for(UIView *v in WXGViews(avatar,20))if([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && !v.hidden){photo=v;break;}
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a,UILabel *b){return a.font.pointSize>b.font.pointSize?NSOrderedAscending:a.font.pointSize<b.font.pointSize?NSOrderedDescending:NSOrderedSame;}];
    UILabel *name=labels.firstObject,*wxid=nil;
    for(UILabel *l in labels)if(l!=name && ([l.text containsString:@"微信号"] || [l.text containsString:@"WeChat ID"])){wxid=l;break;}
    if(!wxid && labels.count>1)wxid=labels[1];
    if(!avatar || !name){_status_=@"头部里没有找到头像或昵称";return NO;}
    if(table!=_table || _dragPan)[self giveBackDragAndBounce];   // (what was switched off on the old ones goes back first)
    _table=table;_header=header;_avatar=avatar;_photoView=photo;_chevron=chevron;_qr=qr;_name=name;_wxid=wxid;
    [_status removeAllObjects];for(UIView *v in status)[_status addObject:v];
    if(_tablePan!=table.panGestureRecognizer){[_tablePan removeTarget:self action:@selector(panned:)];_tablePan=table.panGestureRecognizer;[_tablePan addTarget:self action:@selector(panned:)];}
    // FIX118 D: a tap on the avatar opens WeChat's profile page (the header button's own action); begins only on the avatar
    if(!_avatarTap){_avatarTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(avatarTapped:)];_avatarTap.cancelsTouchesInView=NO;_avatarTap.delaysTouchesEnded=NO;_avatarTap.delegate=self;}
    if(_avatarTap.view!=table){[_avatarTap.view removeGestureRecognizer:_avatarTap];[table addGestureRecognizer:_avatarTap];}
    // WeChat's drag of the page (its status page) on the list's container
    _dragPan=nil;
    for(UIView *v=table.superview;v && v!=page.view.superview && !_dragPan;v=v.superview)for(UIGestureRecognizer *g in v.gestureRecognizers)
        if([g isKindOfClass:UIPanGestureRecognizer.class] && [NSStringFromClass([(id)g.delegate class]) rangeOfString:@"DragAnimate"].location!=NSNotFound){_dragPan=(id)g;break;}
    return YES;
}

#pragma mark - Each pass

// FIX119 B: what a pass depends on. [0] is the scrolling, [1] and [2] where the list is on the screen; the rest is
// the page's make-up (a change there redoes the parts that only need doing then: masks, the status row, the bar's items).
// FIX119 C (user, 11-05 17:31, recording: "灵动岛或者刘海会飞下来 … 头像会抽搐错位闪一下"): B left out [1] and [2]. WeChat moves
// the list's container itself (its own drag of the page; the list's offset stays as it is): the passes were skipped, and the
// Metal layer, in the overlay in that container, went with it, the cut-out drawn in it with it (down the screen, until the
// half-second pass), the avatar in its old pose.
- (void)signature:(double *)sig table:(UITableView *)table header:(UIControl *)header window:(UIWindow *)window page:(UIViewController *)page {
    memset(sig,0,sizeof _sig);
    WXGConfig *c=WXGConfig.shared;
    CGRect h=[header convertRect:header.bounds toView:table];
    UINavigationBar *bar=page.navigationController.navigationBar;
    CGRect barRect=bar && !bar.hidden && bar.window?[bar convertRect:bar.bounds toView:nil]:CGRectZero;
    UIView *status=[self statusViews].firstObject;UIView *mover=status.superview && status.superview!=header?status.superview:status;
    UINavigationItem *item=page.navigationItem;
    CGRect onScreen=[table convertRect:table.bounds toView:nil];   // (the list's own frame in the window, whatever moved it)
    sig[0]=table.contentOffset.y;sig[1]=onScreen.origin.y;sig[2]=onScreen.origin.x;
    sig[25]=table.contentInset.top;sig[26]=table.contentInset.bottom;sig[3]=table.contentSize.height;
    sig[4]=table.bounds.size.width;sig[5]=table.bounds.size.height;
    sig[6]=h.origin.y;sig[7]=h.size.width;sig[8]=h.size.height;
    sig[9]=window.safeAreaInsets.top;sig[10]=window.bounds.size.height;sig[11]=CGRectGetMaxY(barRect);
    sig[12]=table.traitCollection.userInterfaceStyle;
    sig[13]=(double)(_name.text.hash&0xFFFFFFFFFFFF);sig[14]=(double)(_wxid.text.hash&0xFFFFFFFFFFFF);   // (by content: an attributed label hands out a new string each time)
    sig[15]=(double)(uintptr_t)(__bridge void *)item.leftBarButtonItem;sig[16]=(double)(uintptr_t)(__bridge void *)item.rightBarButtonItem;
    sig[17]=status.center.x+status.center.y*4096;sig[18]=mover.center.x+mover.center.y*4096;
    sig[19]=[c extraNumber:@"meBanner"];sig[20]=[c extraNumber:@"meBannerEdgeStyle"]+[c extraNumber:@"meNotchMerge"]*10;
    sig[21]=[c extraNumber:@"meAvatarSize"];sig[22]=[c extraNumber:@"meCutoutY"]*1000+[c extraNumber:@"meCutoutW"];
    sig[23]=_name.font.pointSize;
    sig[24]=(table.isTracking?1:0)+(table.isDragging?2:0)+(table.isDecelerating?4:0);   // (a scroll ending: the snap's pass)
    sig[27]=onScreen.size.height;
}
- (void)update {
    if(!NSThread.isMainThread)return;
    ++_passes;
    if(!WXGMeOn()){[self restoreBecause:@"开关关"];_status_=WXGPluginEnabled()?@"开关关着":@"插件未启用";return;}
    UIViewController *page=[self findPage];
    if(!page){_status_=@"还没找到“我”页";return;}
    if(!page.isViewLoaded || !page.view.window){[self pauseLink];[self pauseVideo];_pageShown=NO;return;}   // another tab: left as it is (FIX120 J: the video too)
    if(!_pageShown){_pageShown=YES;_visibleSince=CACurrentMediaTime();}
    UITableView *oldTable=_table;UIControl *oldHeader=_header;UILabel *oldName=_name;UIView *oldAvatar=_avatar;
    if(![self findPartsOn:page]){[self restoreBecause:[@"找部件：" stringByAppendingString:_status_?:@""]];return;}
    UITableView *table=_table;UIControl *header=_header;UIWindow *window=table.window;
    if(!window)return;
    BOOL newParts=table!=oldTable || header!=oldHeader || _name!=oldName || _avatar!=oldAvatar;
    if(newParts && oldHeader)[self traceEvent:[NSString stringWithFormat:@"部件换了：表%d 头%d 名%d 像%d",table!=oldTable,header!=oldHeader,_name!=oldName,_avatar!=oldAvatar]];
    // FIX119 B: nothing new since the last pass (no scrolling, nothing of WeChat's moved, no pull, no video): nothing to do
    // (but every half second all of it, against WeChat having changed something no signature sees).
    CFTimeInterval now=CACurrentMediaTime();
    double sig[28];[self signature:sig table:table header:header window:window page:page];
    BOOL sameMakeUp=_haveSig && !memcmp(sig+3,_sig+3,sizeof(double)*25),same=sameMakeUp && !memcmp(sig,_sig,sizeof(double)*3);
    memcpy(_sig,sig,sizeof _sig);_haveSig=YES;
    BOOL animating=_pulling || _pullSpring || _videoPlaying || (_link && !_link.paused);   // (an open banner standing still is no animation)
    BOOL audit=newParts || !_insetsApplied || !_overlay.superview || now-_auditAt>.5;
    if(same && !animating && !audit){++_skips;return;}
    if(audit)_auditAt=now;
    BOOL slow=audit || !sameMakeUp;   // (the masks, the status row and the bar's items: only when the page's make-up changed)
    ++_fullPasses;
    WXGConfig *c=WXGConfig.shared;
    _merge=YES;_banner=[c extraNumber:@"meBanner"]>.5;
    CGFloat W=header.bounds.size.width,H=header.bounds.size.height;
    CGFloat safeTop=window.safeAreaInsets.top;
    // The cut-out (Telegram's table), as the user has nudged it.
    struct utsname u;uname(&u);
    WXGCutout cut=WXGCutoutFor(u.machine,window.bounds.size.width,safeTop);
    cut.y+=[c extraNumber:@"meCutoutY"];CGFloat dw=[c extraNumber:@"meCutoutW"];cut.x-=dw*.5;cut.w+=dw;
    if(cut.kind==WXGCutoutNotch && [c extraNumber:@"meNotchMerge"]<.5)_merge=NO;
    if(cut.kind==WXGCutoutNone)_merge=NO;
    _cutout=cut;_status_=@"正常";
    // The insets: WeChat's own (whatever it sets) plus the room of the new header.
    UIEdgeInsets cur=table.contentInset;
    if(_insetsApplied && !UIEdgeInsetsEqualToEdgeInsets(cur,_appliedInsets)) {   // FIX120 G (diagnostics)
        ++_insetRetakes;[self traceEvent:[NSString stringWithFormat:@"微信改了 inset：%@ → %@（偏移 %.1f）",NSStringFromUIEdgeInsets(_appliedInsets),NSStringFromUIEdgeInsets(cur),table.contentOffset.y]];
    }
    if(!_insetsApplied || !UIEdgeInsetsEqualToEdgeInsets(cur,_appliedInsets))_baseInsets=cur;
    CGFloat headerTop=[header convertRect:header.bounds toView:table].origin.y;   // in the list's content
    WXGMeLayout L=WXGMeLayoutFor(H,safeTop,_baseInsets.top+headerTop,[c extraNumber:@"meAvatarSize"]);
    L.shift=round(L.shift);   // (whole points: WeChat keeps the offset at the top inset cut to whole points, diagnostics_17/18)
    if(_haveLayout && (fabs(L.statusTop-_layout.statusTop)>.01 || fabs(L.shift-_layout.shift)>.01))slow=YES;
    _shift=L.shift;_layout=L;_haveLayout=YES;
    // FIX120 I (user: "还是有点抖"; diagnostics_8's trace, "表y"): WeChat's drag helper moves the list's container along with the
    // list's own pan (about half the finger) and springs it back when let go, the list's offset not knowing. What is ours goes
    // by where the header is on the screen: the container moved up by the lift is that much more travel. (It went by the offset
    // alone: the name and the avatar went one way while the page went the other, and back.) Down is WeChat's status page,
    // which the header goes along with as before. Home: where the list is whenever nothing has moved it for a moment.
    CGFloat tableY=[table.superview convertPoint:table.frame.origin toView:nil].y;
    BOOL busy=table.isTracking || table.isDragging || table.isDecelerating;
    if(fabs(tableY-_tableYSeen)>=.01){_tableYSeen=tableY;_tableYSince=now;}
    if(!_haveTableHome || (!busy && now-_tableYSince>.15)){_tableHome=tableY;_haveTableHome=YES;}
    _lift=MIN(tableY-_tableHome,0);_maxLift=MIN(_maxLift,_lift);
    CGFloat t0=table.contentOffset.y+table.contentInset.top-_lift;
    CGFloat restCenter=[header convertPoint:CGPointMake(W*.5,L.avatarCenterY) toView:nil].y+t0+(_insetsApplied?0:L.shift);   // the avatar's centre in the window at rest
    CGFloat target=cut.kind!=WXGCutoutNone?cut.y+cut.h*.5:_baseInsets.top-22;
    _collapse=MAX(restCenter-target,20);
    // FIX119 B: the name's way up to the bar's centre (Telegram's titleCollapseOffset); the page snaps to the end of both
    UINavigationBar *bar=page.navigationController.navigationBar;
    CGFloat barMid=bar && !bar.hidden && bar.window?CGRectGetMidY([bar convertRect:bar.bounds toView:nil]):safeTop+22;
    _titleCollapse=MAX(restCenter+(L.nameCenterY-L.avatarCenterY)-barMid,1);
    _collapseAll=MAX(_collapse,_titleCollapse);
    UIEdgeInsets want=_baseInsets;want.top+=L.shift;
    CGFloat needed=_collapseAll+60;   // (the list can always be scrolled until the title is in the bar)
    CGFloat range=table.contentSize.height+want.top+want.bottom-table.bounds.size.height;
    if(range<needed)want.bottom+=needed-range;
    [self stepPull];
    if(!_banner && _pull>0 && !_pulling){_pull=_pullTarget=0;_pullVelocity=0;_locked=NO;}
    // FIX118 B: the pull (whole points, as the shift). FIX118 E (user: "给名字位置那部分的液体腾开，不要挡住"): as the
    // banner opens, the page goes a little further down than the banner, so the drips hang in a gap of their own.
    {double e=WXGMBLerp(_pull,0,140,0,1);_dripRoom=_banner && WXGMeEdgeStyle()==0?72*e*e*(3-2*e):0;}
    _contentPull=round(_pull+_dripRoom);
    want.top+=_contentPull;
    if(!UIEdgeInsetsEqualToEdgeInsets(cur,want)) {
        CGFloat rel=table.contentOffset.y+cur.top;
        table.contentInset=want;
        // (only when first applied: WeChat setting its own insets again does not move the content, and neither does putting ours back)
        if(!_insetsApplied && want.top!=cur.top)table.contentOffset=CGPointMake(table.contentOffset.x,rel-want.top);
    }
    if(_pull>.01 || _pullPinned || _pullSpring) {   // pulled: the list at its (grown) top, not carried on by its own deceleration
        [self stopDecelerating:table];
        if(fabs(table.contentOffset.y+want.top)>.6)table.contentOffset=CGPointMake(table.contentOffset.x,-want.top);
        _pullPinned=_pull>.01;
    }
    _appliedInsets=want;_insetsApplied=YES;
    CGFloat t=table.contentOffset.y+want.top;_travel=t;
    _shownTravel=t-_lift;t=_shownTravel;   // FIX120 I: on the screen (the list's own travel, _travel, is what the snap moves)
    // The banner: WeChat's drag off (given back when off). FIX118 B: the pull moves the list down (its transform)
    // instead of scrolling it past its top, which WeChat's own code undoes on every pass (diagnostics_17).
    UIPanGestureRecognizer *drag=_dragPan;
    if(_banner) {
        if(drag && !_dragTouched){_dragWasEnabled=drag.enabled;_dragTouched=YES;}
        if(drag.enabled)drag.enabled=NO;
        if(slow && !busy)[self holdDragTargetsOn:table];   // FIX120 I (never in the middle of a drag: WeChat would miss its end)
    }else [self giveBackDragAndBounce];
    _pullVisual=_pull;
    if(_pull>.25)t=-_pull;else if(fabs(t)<1)t=0;
    if(slow) {
        // WeChat's parts: masked, the QR button out of the way of touches.
        for(UIView *v in @[_name?:NSNull.null,_wxid?:NSNull.null,_chevron?:NSNull.null,_qr?:NSNull.null])
            if(v!=(id)NSNull.null)[_states conceal:v];
        // WeChat's avatar only while ours can be drawn (a shader that failed to build: WeChat's stays)
        if(_avatar){if(_metal.failure)[_states unconceal:_avatar];else [_states conceal:_avatar];}
        [_states reapply];
        UIControl *qr=_qr;
        if(qr){if(!_qrTouched){_qrTouchWas=qr.userInteractionEnabled;_qrTouched=YES;}if(qr.userInteractionEnabled)qr.userInteractionEnabled=NO;}
        [self placeStatusWith:L];
        [self ensureBarItemsOn:page];
        // FIX120 J: the banner's video made ready (loaded off the main thread, its first frame decoded) once the page has been
        // up a moment, not on the first pull (the player made on the main thread right as the avatar turned into the banner)
        if(_banner && !busy && now-_visibleSince>.6)[self prepareVideo];
    }
    [self layoutOverlayFor:table header:header layout:L travel:t width:W];
    [self snapIfResting:table];
#if WXGME_TRACE
    {UIView *container=table.superview,*top=container.subviews.lastObject,*mover=[self statusMoversIn:header].firstObject;
     [self tracePass:[NSString stringWithFormat:@"t%.1f 抬%.1f o%.1f in%.1f/%.1f tc%.1f end%.1f 名y%.1f %@ 表y%.1f 层y%.1f 画布%.0f %c%.1f 状%.2f%@%@",
         t,_lift,table.contentOffset.y,table.contentInset.top,_baseInsets.top,_titleCollapse,_collapseAll,_titlePose.titleY,
         top==_overlay?@"顶":NSStringFromClass(top.class),[container convertPoint:table.frame.origin toView:nil].y,[_overlay convertPoint:CGPointZero toView:nil].y,
         _metal.bounds.size.height,_renderNote?:'?',_renderNote=='R'?_lastRenderMS:0,mover?mover.alpha:-1,slow?@" 慢":@"",table.isTracking?@" 按":table.isDecelerating?@" 惯":@""]];}
#endif
}
// FIX120 G: the flight recorder (a line per pass that differs from the last; events as they happen)
- (void)traceEvent:(NSString *)line {
#if WXGME_TRACE
    if(!_trace)_trace=[NSMutableArray array];
    [_trace addObject:[NSString stringWithFormat:@"%.3f %@",CACurrentMediaTime()-_start,line]];
    if(_trace.count>1500)[_trace removeObjectsInRange:NSMakeRange(0,_trace.count-1500)];
#else
    (void)line;
#endif
}
- (void)tracePass:(NSString *)state {
    if(_traceLast && [state isEqualToString:_traceLast]){++_traceRepeat;return;}
    if(_traceRepeat)[self traceEvent:[NSString stringWithFormat:@"（同上 ×%lu）",(unsigned long)_traceRepeat]];
    _traceRepeat=0;_traceLast=state;[self traceEvent:state];
}
// WeChat's status buttons: their row centred under the ID, its top at L.statusTop (both still inside the header).
// (in a container of their own inside the header: the container is what moves, so they stay inside its bounds and take touches)
- (NSArray<UIView *> *)statusMoversIn:(UIControl *)header {
    NSArray<UIView *> *views=[self statusViews];
    UIView *common=views.firstObject.superview;
    for(UIView *v in views)if(v.superview!=common)common=nil;
    if(common && common!=header && [common isDescendantOfView:header] && common.bounds.size.height<header.bounds.size.height*.6)views=@[common];
    return views;
}
- (void)placeStatusWith:(WXGMeLayout)L {
    UIControl *header=_header;if(!header)return;
    NSArray<UIView *> *views=[self statusMoversIn:header];
    // where WeChat has put each (a centre not ours is WeChat's: its place)
    for(UIView *v in views) {
        NSValue *applied=objc_getAssociatedObject(v,&WXGMeAppliedCenterKey);
        if(!applied || !CGPointEqualToPoint(applied.CGPointValue,v.center)) {
            if(applied && v.superview){++_statusMoves;_statusMovedY=[v.superview convertPoint:v.center toView:nil].y;}   // FIX120 F
            objc_setAssociatedObject(v,&WXGMeNativeCenterKey,[NSValue valueWithCGPoint:v.center],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    // the row's extent there, in the header
    CGFloat minX=CGFLOAT_MAX,maxX=-CGFLOAT_MAX,minY=CGFLOAT_MAX;
    for(UIView *v in views) {
        NSValue *n=objc_getAssociatedObject(v,&WXGMeNativeCenterKey);if(!n || !v.superview)continue;
        CGPoint p=[v.superview convertPoint:n.CGPointValue toView:header];CGSize sz=v.bounds.size;
        minX=MIN(minX,p.x-sz.width*.5);maxX=MAX(maxX,p.x+sz.width*.5);minY=MIN(minY,p.y-sz.height*.5);
    }
    if(minX==CGFLOAT_MAX)return;
    CGFloat dx=header.bounds.size.width*.5-(minX+maxX)*.5,dy=L.statusTop-minY;
    for(UIView *v in views) {
        UIView *superview=v.superview;NSValue *n=objc_getAssociatedObject(v,&WXGMeNativeCenterKey);if(!superview || !n)continue;
        CGPoint inHeader=[superview convertPoint:n.CGPointValue toView:header];
        CGPoint want=[header convertPoint:CGPointMake(inHeader.x+dx,inHeader.y+dy) toView:superview];
        want.x=round(want.x*6)/6;want.y=round(want.y*6)/6;
        if(!CGPointEqualToPoint(v.center,want))v.center=want;
        objc_setAssociatedObject(v,&WXGMeAppliedCenterKey,[NSValue valueWithCGPoint:v.center],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self fadeStatus:views header:header layout:L];
}
// FIX120 F (user: "往上滑到状态靠近屏幕顶部的时候，那片区域整个在闪"): WeChat's status row fades out over its own height as it
// goes under the bar, and stays out up there, so a frame in which WeChat has put it back somewhere of its own (its layout
// before ours) shows nothing under the island. (WeChat's own alpha is kept: ours is that times the fade.)
- (void)fadeStatus:(NSArray<UIView *> *)views header:(UIControl *)header layout:(WXGMeLayout)L {
    UIWindow *window=header.window;if(!window || !views.count)return;
    UINavigationBar *bar=_page.navigationController.navigationBar;
    CGRect barRect=bar && !bar.hidden && bar.window?[bar convertRect:bar.bounds toView:nil]:CGRectMake(0,window.safeAreaInsets.top,window.bounds.size.width,44);
    CGFloat rowH=1;for(UIView *v in views)rowH=MAX(rowH,v.bounds.size.height);
    CGFloat top=[header convertPoint:CGPointMake(0,L.statusTop) toView:nil].y;
    CGFloat fade=MIN(MAX((top+rowH-CGRectGetMaxY(barRect))/rowH,0),1);fade=round(fade*64)/64;
    for(UIView *v in views) {
        NSNumber *applied=objc_getAssociatedObject(v,&WXGMeFadedKey),*native=objc_getAssociatedObject(v,&WXGMeNativeAlphaKey);
        if(!native || !applied || fabs(applied.doubleValue-v.alpha)>.001)   // (an alpha not ours is WeChat's)
            objc_setAssociatedObject(v,&WXGMeNativeAlphaKey,native=@(v.alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGFloat want=native.doubleValue*fade;
        if(fabs(v.alpha-want)>.001)v.alpha=want;
        objc_setAssociatedObject(v,&WXGMeFadedKey,@(v.alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
- (void)statusLaidOut:(UIView *)view {
    if(!_insetsApplied || !_haveLayout || !_header || ![view isDescendantOfView:_header] || !WXGMeOn())return;
    if(![_status containsObject:view])[_status addObject:view];   // (one WeChat made anew)
    [self placeStatusWith:_layout];
}
- (void)restoreStatus {
    NSMutableArray<UIView *> *movers=[[self statusViews] mutableCopy];
    UIView *common=movers.firstObject.superview;if(common && ![movers containsObject:common])[movers addObject:common];
    for(UIView *v in movers) {
        NSValue *native=objc_getAssociatedObject(v,&WXGMeNativeCenterKey),*applied=objc_getAssociatedObject(v,&WXGMeAppliedCenterKey);
        if(native && applied && CGPointEqualToPoint(v.center,applied.CGPointValue))v.center=native.CGPointValue;
        objc_setAssociatedObject(v,&WXGMeNativeCenterKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v,&WXGMeAppliedCenterKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSNumber *faded=objc_getAssociatedObject(v,&WXGMeFadedKey),*alpha=objc_getAssociatedObject(v,&WXGMeNativeAlphaKey);   // FIX120 F
        if(faded && alpha && fabs(v.alpha-faded.doubleValue)<.001)v.alpha=alpha.doubleValue;
        objc_setAssociatedObject(v,&WXGMeFadedKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v,&WXGMeNativeAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
// The bar: QR on the left, 设置 on the right.
- (void)ensureBarItemsOn:(UIViewController *)page {
    UINavigationItem *item=page.navigationItem;
    if(!_leftItem) {
        UIButton *qr=[UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *image=[UIImage systemImageNamed:@"qrcode"];
        [qr setImage:image forState:UIControlStateNormal];qr.frame=CGRectMake(0,0,36,36);
        [qr addTarget:self action:@selector(openQR) forControlEvents:UIControlEventTouchUpInside];
        qr.accessibilityLabel=@"我的二维码";
        _leftItem=[[UIBarButtonItem alloc]initWithCustomView:qr];
        UIButton *settings=[UIButton buttonWithType:UIButtonTypeSystem];
        [settings setTitle:@"设置" forState:UIControlStateNormal];settings.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        [settings sizeToFit];CGRect f=settings.frame;f.size.width=MAX(f.size.width+16,52);f.size.height=36;settings.frame=f;
        [settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
        _rightItem=[[UIBarButtonItem alloc]initWithCustomView:settings];
    }
    UIColor *ink=_name.textColor?:UIColor.labelColor;
    for(UIView *v in @[_leftItem.customView?:NSNull.null,_rightItem.customView?:NSNull.null])   // (FIX119 B: only when it changed: a tint set
        if(v!=(id)NSNull.null && ![v.tintColor isEqual:ink])v.tintColor=ink;                     //  again redraws the buttons and their glass)
    if(_itemsOn!=item){_leftWas=item.leftBarButtonItem;_rightWas=item.rightBarButtonItem;_itemsOn=item;}
    if(item.leftBarButtonItem!=_leftItem){if(item.leftBarButtonItem!=nil && item.leftBarButtonItem!=_leftWas)_leftWas=item.leftBarButtonItem;item.leftBarButtonItem=_leftItem;}
    if(item.rightBarButtonItem!=_rightItem){if(item.rightBarButtonItem!=nil && item.rightBarButtonItem!=_rightWas)_rightWas=item.rightBarButtonItem;item.rightBarButtonItem=_rightItem;}
    _itemsTouched=YES;
}
- (void)openQR {
    UIControl *qr=_qr;
    if(qr)[qr sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)openSettings {
    UIViewController *page=_page;if(page)[WXGIntegrationHost.shared openSettingsFrom:page];
}

#pragma mark - Drawing

- (void)ensureOverlayOver:(UITableView *)table {
    UIView *container=table.superview;if(!container)return;
    if(!_overlay) {
        _overlay=[UIView new];_overlay.userInteractionEnabled=NO;_overlay.backgroundColor=UIColor.clearColor;
        _labels=[UIView new];_labels.userInteractionEnabled=NO;[_overlay addSubview:_labels];
        _bigName=[UILabel new];_bigName.textAlignment=NSTextAlignmentCenter;_bigName.lineBreakMode=NSLineBreakByTruncatingTail;
        _bigID=[UILabel new];_bigID.textAlignment=NSTextAlignmentCenter;_idFont=[UIFont systemFontOfSize:15];_bigID.font=_idFont;
        for(UIView *v in @[_bigName,_bigID])[_labels addSubview:v];
        _metal=[WXGMetaballView new];[_overlay addSubview:_metal];
        WXGMeOverlay=_overlay;   // FIX120 G: the host's page-top paint cleaning leaves all of it alone
        __weak WXGMeHeader *weakSelf=self;
        _metal.photoReady=^{WXGMeHeader *me=weakSelf;if(!me)return;me->_haveLast=NO;[me runLink];};   // (drawn again on the next pass)
    }
    if(_overlay.superview!=container || container.subviews.lastObject!=_overlay) {
        if(_overlay.superview!=container){[container addSubview:_overlay];[self traceEvent:@"层加回容器"];}
        else {
            UIView *top=container.subviews.lastObject;   // FIX120 G (diagnostics: counted once per view put on top)
            if(top!=_coveredView){++_overlayCovered;_coveredView=top;_coveredBy=NSStringFromClass(top.class);[self traceEvent:[_coveredBy stringByAppendingString:@" 盖到了层上面，已移回"]];}
            [container bringSubviewToFront:_overlay];
        }
    }
    if(!CGRectEqualToRect(_overlay.frame,table.frame))_overlay.frame=table.frame;   // (the list is never transformed by us)
}
// FIX119 B: set only what changed (the same text, font or colour set again on every pass redraws a label)
static void WXGMeSetText(UILabel *l,NSString *text) {if(l.text!=text && ![l.text isEqualToString:text?:@""])l.text=text;}
static void WXGMeSetInk(UILabel *l,UIColor *color) {if(l.textColor!=color && ![l.textColor isEqual:color])l.textColor=color;}
static void WXGMeSetFont(UILabel *l,UIFont *font) {if(l.font!=font && ![l.font isEqual:font])l.font=font;}
static void WXGMeSetAlpha(UIView *v,CGFloat alpha) {if(fabs(v.alpha-alpha)>.002)v.alpha=alpha;}
static void WXGMeSetHidden(UIView *v,BOOL hidden) {if(v.hidden!=hidden)v.hidden=hidden;}
static void WXGMeSetFrame(UIView *v,CGRect frame) {if(!CGRectEqualToRect(v.frame,frame))v.frame=frame;}   // (views without a transform)
static void WXGMeSetBounds(UIView *v,CGRect bounds) {if(!CGRectEqualToRect(v.bounds,bounds))v.bounds=bounds;}
static void WXGMeSetCenter(UIView *v,CGPoint center) {if(!CGPointEqualToPoint(v.center,center))v.center=center;}
static void WXGMeSetScale(UIView *v,CGFloat scale) {
    CGAffineTransform t=CGAffineTransformMakeScale(scale,scale);
    if(!CGAffineTransformEqualToTransform(v.transform,t))v.transform=t;
}
- (void)layoutOverlayFor:(UITableView *)table header:(UIControl *)header layout:(WXGMeLayout)L travel:(CGFloat)t width:(CGFloat)W {
    [self ensureOverlayOver:table];
    UIView *o=_overlay;UIWindow *window=table.window;
    // colours from WeChat: its name's
    UIColor *ink=_name.textColor?:UIColor.labelColor,*grey=_wxid.textColor?:UIColor.secondaryLabelColor;
    CGFloat px=window.screen.scale?:UIScreen.mainScreen.scale;
    CGFloat up=MAX(t,0);
    [UIView performWithoutAnimation:^{
        [CATransaction begin];[CATransaction setDisableActions:YES];
        WXGMeSetFrame(self->_labels,o.bounds);
        CGPoint (^at)(CGFloat)=^CGPoint(CGFloat y){return [header convertPoint:CGPointMake(W*.5,y) toView:o];};
        // the bar: its centre (where the name stops)
        UINavigationBar *bar=self->_page.navigationController.navigationBar;
        CGRect barRect=bar && !bar.hidden && bar.window?[bar convertRect:bar.bounds toView:nil]:CGRectMake(0,window.safeAreaInsets.top,W,44);
        CGFloat lockY=[o convertPoint:CGPointMake(0,CGRectGetMidY(barRect)) fromView:nil].y;
        // FIX119 B (user: "两个昵称同时存在 … Telegram … 分了段，不会乱跳"): one name. It goes up with the page, shrinking to
        // the bar title's size (17 pt) on the way, until its centre is the bar's, and stays there; the ID under it shrinks
        // a little, follows it and is gone before it stops (Telegram's PeerInfoHeaderNode).
        CGFloat nameSize=MAX(self->_name.font.pointSize+6,26);
        UIFont *bigFont=self->_bigFont;
        if(!bigFont || fabs(bigFont.pointSize-nameSize)>.01)self->_bigFont=bigFont=[UIFont systemFontOfSize:nameSize weight:UIFontWeightSemibold];
        WXGMeSetText(self->_bigName,self->_name.text);WXGMeSetInk(self->_bigName,ink);WXGMeSetFont(self->_bigName,bigFont);
        WXGMeSetText(self->_bigID,self->_wxid.text);WXGMeSetInk(self->_bigID,grey);
        CGPoint natural=at(L.nameCenterY);
        CGFloat lockScale=17/nameSize;
        WXGMeTitlePose tp=WXGMeTitlePoseAt(natural.y,up,lockY,L.idCenterY-L.nameCenterY,lockScale);
        self->_titlePose=tp;
        CGFloat x=round(natural.x*px)/px;
        // (as wide as fits between the bar's buttons once it is small)
        WXGMeSetBounds(self->_bigName,CGRectMake(0,0,round(MIN(W-48,(W-150)/lockScale)),ceil(bigFont.lineHeight)+4));
        WXGMeSetCenter(self->_bigName,CGPointMake(x,round(tp.titleY*px)/px));
        WXGMeSetScale(self->_bigName,tp.titleScale);
        WXGMeSetBounds(self->_bigID,CGRectMake(0,0,W-48,22));
        WXGMeSetCenter(self->_bigID,CGPointMake(x,round(tp.idY*px)/px));
        WXGMeSetScale(self->_bigID,tp.idScale);
        WXGMeSetAlpha(self->_bigID,tp.idAlpha);
        WXGMeSetHidden(self->_bigID,!self->_wxid || tp.idAlpha<.004);
        // FIX120 H (user, 11-06 screenshot: "你挡住还有条黑线这不是自欺欺人吗"): no bar background of our own. FIX119 B's (an
        // opaque block of the cells' colour over 0..the bar's bottom, a separator under it) hid the page under the bar instead
        // of letting it pass under the plugin's glass bar as everywhere else; the host's page-top cleaning had been clearing
        // it every quarter second (the flashing at the top). What goes under the bar now: the list, as on every other page;
        // the status row fading out first (FIX120 F); the name and the avatar drawn over it.
        [CATransaction commit];
    }];
    if(_insetsApplied)[self fadeStatus:[self statusMoversIn:header] header:header layout:L];   // FIX120 F (every pass: it follows the list)
    [self drawAvatarIn:o header:header layout:L travel:t width:W];
}
- (void)drawAvatarIn:(UIView *)o header:(UIControl *)header layout:(WXGMeLayout)L travel:(CGFloat)t width:(CGFloat)W {
    WXGMetaballView *metal=_metal;_renderNote='-';
    UIWindow *window=o.window;if(!window)return;
    // (the layer's top is the window's: the shader's coordinates are the window's)
    CGRect windowInOverlay=[o convertRect:window.bounds fromView:nil];
    if(fabs(metal.frame.origin.y-windowInOverlay.origin.y)>.01 || fabs(metal.frame.size.width-W)>.01 || metal.frame.origin.x!=0) {
        CGFloat h=_canvasHeight>0?_canvasHeight:windowInOverlay.size.height;
        [CATransaction begin];[CATransaction setDisableActions:YES];metal.frame=CGRectMake(0,windowInOverlay.origin.y,W,h);[CATransaction commit];
    }
    // the photo: WeChat's HD one when it is there, else the one on the page
    CFTimeInterval now=CACurrentMediaTime();
    if(!_shownPhoto || (now-_photoAt>1 && _shownPhoto.size.width*_shownPhoto.scale<300)) {
        _photoAt=now;
        UIImage *photo=[WXGIntegrationHost.shared selfAvatarPhoto];
        UIImageView *native=(UIImageView *)_photoView;
        if(!photo && [native isKindOfClass:UIImageView.class])photo=native.image;
        if(photo && photo!=_shownPhoto){_shownPhoto=photo;[metal setPhoto:photo];_haveLast=NO;}
    }
    // the avatar's centre at rest moves with the page (scrolled, or WeChat dragging it); the cut-out is the screen's
    CGPoint restCenter=[header convertPoint:CGPointMake(W*.5,L.avatarCenterY) toView:metal];
    CGFloat restY=restCenter.y+MAX(_shownTravel,0)-_contentPull;   // (FIX120 I: the travel on the screen)   // where it is when the list is at rest (not scrolled, not pulled)
    CGRect cut=[metal convertRect:CGRectMake(_cutout.x,_cutout.y,_cutout.w,_cutout.h) fromView:nil];
    WXGMetaballPose p=WXGMetaballPoseAt(t,_collapse,restY,L.avatarRadius,CGRectGetMaxY(cut),_merge,_banner?140:0);
    WXGMBUniforms u;memset(&u,0,sizeof u);
    u.time=(float)(now-_start);
    u.island[0]=CGRectGetMidX(cut);u.island[1]=CGRectGetMidY(cut);u.island[2]=cut.size.width*.5;u.island[3]=cut.size.height*.5;
    // the drawn cut-out a little inside the real one; a notch's corners
    u.islandShape[0]=_cutout.kind==WXGCutoutNotch?20:cut.size.height*.5;u.islandShape[1]=_cutout.kind;
    u.islandShape[2]=_merge?p.presence:0;u.islandShape[3]=_cutout.kind==WXGCutoutNotch?9:1.5;
    if(_cutout.kind==WXGCutoutNotch){u.island[2]-=0;}   // (a notch's ears are left out by the inset above: 223 pt is its width at the top)
    u.avatar[0]=restCenter.x;u.avatar[1]=p.centerY;u.avatar[2]=p.radius;u.avatar[3]=p.darkness;
    _avatarWindowCenter=[metal convertPoint:CGPointMake(restCenter.x,p.centerY) toView:nil];_avatarWindowRadius=p.expand>.05?0:p.radius*p.fade;
    u.effect[0]=p.blur;u.effect[1]=p.goo;u.effect[2]=p.fade;u.effect[3]=p.blend;
    u.drop[0]=p.stretch;u.drop[1]=p.tip;u.drop[2]=p.expand;u.drop[3]=p.flow;
    u.image[2]=.3f;
    u.fx[0]=WXGMeEdgeStyle();   // FIX118 F: 0 drips, 1 fading into the page, 2 a plain edge
    // (the drips' room: from the banner's edge down to the name, which the page has moved out of their way)
    {CGFloat nameTop=[_bigName convertPoint:CGPointMake(0,0) toView:metal].y+(_bigName.bounds.size.height-_bigName.font.lineHeight)*.5;
     u.fx[1]=(float)MAX(nameTop-(p.centerY+p.radius)-4,0);}
    // FIX119 B: the layer only as tall as what it draws (it was the whole window: a full-screen layer blended over the
    // page on every frame, and every pixel of it shaded): the avatar or the banner, the drips under it, the cut-out.
    BOOL resized=NO;
    {CGFloat maxY=MAX(p.centerY+p.radius,CGRectGetMaxY(cut))+6;
     if(p.expand>0)maxY=MAX(maxY,p.centerY+L.avatarRadius+6);
     if(p.flow>0 && u.fx[0]<.5)maxY+=u.fx[1]+30;
     // FIX120 J (user: "头像和展开的视频切换的时候会有点掉帧"): with the banner on and the avatar near its rest, as tall as the
     // banner pulled as far as it goes needs, from the start. Made taller step by step in the middle of the pull, the layer's
     // drawables were made anew right as the avatar turned into the banner (a frame dropped at each step). Smaller only when
     // two steps smaller (well up the page), not on every step back.
     if(!_banner || t>_collapse*.7)_canvasOpen=NO;else if(t<_collapse*.4)_canvasOpen=YES;   // (apart, so it does not go back and forth)
     if(_canvasOpen) {
         WXGMetaballPose open=WXGMetaballPoseAt(-210,_collapse,restY,L.avatarRadius,CGRectGetMaxY(cut),_merge,140);
         CGFloat openY=open.centerY+L.avatarRadius+6;
         if(u.fx[0]<.5)openY+=130;   // (the drips under it)
         maxY=MAX(maxY,openY);
     }
     CGFloat h=WXGMeCanvasHeight(maxY,windowInOverlay.size.height),shown=metal.bounds.size.height;
     if(h>shown+.5 || h<shown-150) {
         _canvasHeight=h;_haveLast=NO;resized=YES;++_canvasResizes;
         [CATransaction begin];[CATransaction setDisableActions:YES];metal.frame=CGRectMake(0,windowInOverlay.origin.y,W,h);[CATransaction commit];
     }}
    u.size[0]=metal.bounds.size.width;u.size[1]=metal.bounds.size.height;u.scale=metal.layer.contentsScale;
    // FIX118 B: the video fades in as the banner opens (playing only then)
    float videoMix=(float)WXGMBLerp(p.expand,.35,1,0,1);
    // FIX120 J: the player runs from the first moment of the pull (it started at 35 % open, its decoder starting then: the
    // banner held a still and jumped) and stops half a second after the banner has closed (not on every small pull).
    BOOL videoOn=_banner && (p.expand>0 || _pulling) && [self prepareVideo];
    if(videoOn)_videoWantedAt=now;
    if(videoOn || (_videoPlaying && now-_videoWantedAt<.5)) {
        [self playVideo];
        BOOL had=_videoRef!=NULL;
        if([self pullVideoFrame]){metal.videoTexture=CVMetalTextureGetTexture(_videoRef);if(!had)_videoFirstAt=now;}
    }else [self pauseVideo];
    BOOL wantVideo=videoOn && videoMix>0;
    // (the very first frame comes in over a sixth of a second, not at once at whatever the mix is by then)
    if(metal.videoTexture && wantVideo){u.video[2]=.5f;u.video[3]=videoMix*(float)MIN(MAX((now-_videoFirstAt)/.16,0),1);}
    BOOL moving=(p.flow>0 && u.fx[0]<.5) || wantVideo || _pulling || _pullSpring;   // (FIX119 B: only the drips change with time)
    WXGMBUniforms a=u,b=_lastUniforms;a.time=b.time=0;
    BOOL same=_haveLast && !memcmp(&a,&b,sizeof a);   // (nothing but the clock differs from what is on the screen)
    if(!moving && same){_renderNote='s';[self pauseLink];return;}
    if(moving && !wantVideo && p.flow<=0 && _haveLast && !memcmp(&u.avatar,&_lastUniforms.avatar,sizeof u.avatar) && !memcmp(&u.drop,&_lastUniforms.drop,sizeof u.drop)){_renderNote='m';[self runLink];return;}   // (still: nothing new to draw)
    // at most one frame per refresh (several run-loop passes in one frame would wait for drawables). FIX119 C: 1/130 s
    // dropped real frames on 120 Hz whenever a pass came a little early (the avatar a frame behind the page); and a layer
    // just made taller is always drawn at once (else its old picture shows stretched to the new height for a frame).
    // FIX120 G: only a frame that is new in its clock alone (the drips, the video) waits. One whose pose changed (the page
    // scrolled, the avatar or the cut-out moved) is drawn in this pass: skipped, the avatar and the cut-out stayed where the
    // last pass had put them for a frame while the page and the name had moved on (a second pass early in a frame).
    if(!resized && same && now-_renderedAt<1./200){_renderNote='g';++_gateSkips;[self runLink];return;}   // (the link brings the pass that draws it)
    if(moving)[self runLink];else [self pauseLink];
    metal.uniforms=u;
    CFTimeInterval began=CACurrentMediaTime();
    if([metal render]){_lastUniforms=u;_haveLast=YES;++_renders;_renderedAt=now;_renderNote='R';}else _renderNote='f';
    _lastRenderMS=(CACurrentMediaTime()-began)*1000;_worstRenderMS=MAX(_worstRenderMS,_lastRenderMS);
}
- (void)runLink {
    if(!_link) {
        _link=[CADisplayLink displayLinkWithTarget:self selector:@selector(linkTick:)];
        WXGConfigureDisplayLink(_link,UIScreen.mainScreen);   // (FIX119 B: the screen's full rate on ProMotion, as the rest of the glass)
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    _link.paused=NO;
}
- (void)pauseLink {_link.paused=YES;}
- (void)linkTick:(__unused CADisplayLink *)link {}   // (only wakes the run loop: the observer draws)

#pragma mark - The avatar's tap (FIX118 D)

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if(g!=_avatarTap)return YES;
    if(_avatarWindowRadius<16 || !WXGMeOn())return NO;
    CGPoint p=[g locationInView:nil];
    return hypot(p.x-_avatarWindowCenter.x,p.y-_avatarWindowCenter.y)<=_avatarWindowRadius+4;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(__unused UIGestureRecognizer *)other {return g==_avatarTap;}
- (void)avatarTapped:(UITapGestureRecognizer *)tap {
    if(tap.state!=UIGestureRecognizerStateRecognized)return;
    UIControl *header=_header;if(!header)return;
    ++_avatarTaps;[header sendActionsForControlEvents:UIControlEventTouchUpInside];
}
// The list's own deceleration stopped (a push up closing the banner would otherwise carry on scrolling it, diagnostics_19).
- (void)stopDecelerating:(UITableView *)table {
    if(table.isDecelerating)[table setContentOffset:table.contentOffset animated:NO];
}

#pragma mark - WeChat's drag on the list's own pan (FIX120 I)

// The targets of a gesture recognizer: [target, action name] (UIGestureRecognizerTarget's _target and _action, read only when
// they are an object and a selector).
static NSArray<NSArray *> *WXGMePanTargets(UIGestureRecognizer *g) {
    NSMutableArray<NSArray *> *out=[NSMutableArray array];
    id targets=nil;
    @try{targets=[g valueForKey:@"_targets"];}@catch(__unused NSException *e){return out;}
    if(![targets isKindOfClass:NSArray.class])return out;
    for(id entry in targets) {
        Class cls=object_getClass(entry);
        Ivar ti=class_getInstanceVariable(cls,"_target"),ai=class_getInstanceVariable(cls,"_action");
        const char *tt=ti?ivar_getTypeEncoding(ti):NULL,*at=ai?ivar_getTypeEncoding(ai):NULL;
        if(!tt || !at || tt[0]!='@' || at[0]!=':')continue;
        id target=object_getIvar(entry,ti);
        SEL action=*(SEL *)((uint8_t *)(__bridge void *)entry+ivar_getOffset(ai));
        if(target && action)[out addObject:@[target,NSStringFromSelector(action)]];
    }
    return out;
}
// With the banner on, WeChat's drag of the page is off (its own recognizer, above) and the pull is ours; its helper's targets on
// the list's own pan come off too (they moved the container with every scroll), put back with the drag.
- (void)holdDragTargetsOn:(UITableView *)table {
    UIPanGestureRecognizer *pan=table.panGestureRecognizer;if(!pan)return;
    NSMutableArray<NSString *> *seen=[NSMutableArray array];
    for(NSArray *pair in WXGMePanTargets(pan)) {
        id target=pair[0];NSString *action=pair[1],*name=NSStringFromClass([target class]);
        [seen addObject:[NSString stringWithFormat:@"%@ %@",name,action]];
        if(target==self || [name rangeOfString:@"DragAnimate"].location==NSNotFound)continue;
        [pan removeTarget:target action:NSSelectorFromString(action)];
        if(!_heldTargets)_heldTargets=[NSMapTable weakToStrongObjectsMapTable];
        NSMutableSet<NSString *> *actions=[_heldTargets objectForKey:target];
        if(!actions){actions=[NSMutableSet set];[_heldTargets setObject:actions forKey:target];}
        [actions addObject:action];_heldPan=pan;++_targetHolds;
        [self traceEvent:[NSString stringWithFormat:@"拿下微信拖动：%@ %@",name,action]];
    }
    _panTargetsSeen=[seen componentsJoinedByString:@"；"];
#if WXGME_TRACE
    // (diagnostics: what else could be moving it, if not a target of the pan)
    id helper=_dragPan.delegate;
    if(helper && !_helperMethods) {
        unsigned n=0;Method *methods=class_copyMethodList(object_getClass(helper),&n);NSMutableArray<NSString *> *names=[NSMutableArray array];
        for(unsigned i=0;i<n && i<120;i++)[names addObject:NSStringFromSelector(method_getName(methods[i]))];
        free(methods);
        _helperMethods=[NSString stringWithFormat:@"%@: %@",NSStringFromClass([helper class]),[names componentsJoinedByString:@" "]];
    }
    if(!_tableObservers) {
        id info=(__bridge id)table.observationInfo;NSString *text=info?[info description]:@"";
        _tableObservers=text.length>1500?[text substringToIndex:1500]:text;
    }
#endif
}
- (void)giveBackDragTargets {
    UIPanGestureRecognizer *pan=_heldPan;
    if(pan)for(id target in _heldTargets.keyEnumerator.allObjects)for(NSString *action in [_heldTargets objectForKey:target])
        [pan addTarget:target action:NSSelectorFromString(action)];
    [_heldTargets removeAllObjects];_heldPan=nil;
}

#pragma mark - Snapping

// Released between the avatar at rest and in the cut-out: to the nearer of the two.
- (void)panned:(UIPanGestureRecognizer *)pan {
    UITableView *table=_table;if(!table || !_insetsApplied || !WXGMeOn())return;
    if(_banner && [self pulled:pan table:table])return;
    if(pan.state!=UIGestureRecognizerStateEnded && pan.state!=UIGestureRecognizerStateCancelled)return;
    CGFloat rel=table.contentOffset.y+table.contentInset.top,v=[pan velocityInView:table].y;
    CGFloat predicted=rel-v*.5;   // (UIKit's deceleration, rate .998: about v/2 points further)
    CGFloat end=_collapseAll>0?_collapseAll:_collapse;   // FIX119 B: the end of both: the avatar in, the name in the bar
    if(predicted<=0 || predicted>=end)return;
    CGFloat target=predicted<end*.5?0:end;
    __weak UITableView *weakTable=table;CGFloat top=table.contentInset.top;
    dispatch_async(dispatch_get_main_queue(),^{
        UITableView *list=weakTable;if(!list)return;
        self->_snapUntil=CACurrentMediaTime()+.45;++self->_snaps;
        [list setContentOffset:CGPointMake(list.contentOffset.x,target-top) animated:YES];
    });
}
// FIX118 B: the banner pull. At the list's top, pulling down moves WeChat's list down (its transform: WeChat's
// own code keeps its offset from going past the top) and opens the avatar into the banner; let go past 100 pt
// (or flicked past 40) it stays open (locked at 140), else it springs back; open, pushing up closes it.
// YES: the gesture is the pull's (no snapping for it).
- (BOOL)pulled:(UIPanGestureRecognizer *)pan table:(UITableView *)table {
    UIGestureRecognizerState state=pan.state;
    CGFloat rel=table.contentOffset.y+table.contentInset.top,ty=[pan translationInView:table.superview].y;
    if(state==UIGestureRecognizerStateBegan){_pullBase=ty;_pullAtBegin=_pull;_pulling=_pull>.5;return _pulling;}
    if(state==UIGestureRecognizerStateChanged) {
        if(!_pulling && rel<=1 && ty-_pullBase>0){_pulling=YES;_pullBase=ty;_pullAtBegin=0;}   // the top reached going down: the pull starts here
        if(!_pulling){_pullBase=ty;return NO;}
        CGFloat d=ty-_pullBase,p=_pullAtBegin+(d>0?d*.6:d);
        if(p>140)p=140+70*(1-exp(-(p-140)/70));   // past the open banner: harder and harder
        // (FIX118 C: B stopped here at once: the pull starts with d=0, so p=0 ended it on its first move; diagnostics_18)
        if(p<0 || (d<0 && p<=0)){p=0;_pulling=NO;_pullBase=ty;}
        _pull=_pullTarget=p;_pullVelocity=0;_pullSpring=NO;[self runLink];   // (the next pass sets the list's top to it)
        return YES;
    }
    if(state==UIGestureRecognizerStateEnded || state==UIGestureRecognizerStateCancelled) {
        if(!_pulling && _pull<=.5)return NO;
        CGFloat v=[pan velocityInView:table.superview].y;
        BOOL open=_locked?(_pull>90 && v>-600):(_pull>100 || (v>800 && _pull>40));
        if(open && !_locked)++_locks;
        _locked=open;_pulling=NO;
        [self setPull:open?140:0 animated:YES table:table];
        __weak UITableView *weakTable=table;
        dispatch_async(dispatch_get_main_queue(),^{UITableView *list=weakTable;if(list)[self stopDecelerating:list];});   // (after UIKit has started it)
        return YES;
    }
    return NO;
}
- (void)setPull:(CGFloat)p animated:(BOOL)animated table:(__unused UITableView *)table {
    _pullTarget=p;
    if(!animated){_pull=p;_pullVelocity=0;_pullSpring=NO;return;}
    _pullSpring=YES;_pullStepAt=CACurrentMediaTime();[self runLink];
}
// The spring towards the pull's target (stiffness 170, damping ratio .86: about half a second, no overshoot to speak of).
- (void)stepPull {
    if(!_pullSpring)return;
    CFTimeInterval now=CACurrentMediaTime();double dt=MIN(now-_pullStepAt,.05);_pullStepAt=now;
    const double k=170,c=2*sqrt(k)*.86,h=1./240;
    for(double left=dt;left>1e-6;left-=h) {
        double step=MIN(h,left);
        double a=-k*(_pull-_pullTarget)-c*_pullVelocity;
        _pullVelocity+=a*step;_pull+=_pullVelocity*step;
    }
    if(fabs(_pull-_pullTarget)<.2 && fabs(_pullVelocity)<2){_pull=_pullTarget;_pullVelocity=0;_pullSpring=NO;}
    if(_pull<0)_pull=0;
}
- (void)snapIfResting:(UITableView *)table {
    if(_pull>.5 || _pulling)return;
    if(table.isTracking || table.isDragging || table.isDecelerating || CACurrentMediaTime()<_snapUntil)return;
    if(_lift<-.5)return;   // FIX120 I: WeChat's container still on its way back
    CGFloat rel=_travel,end=_collapseAll>0?_collapseAll:_collapse;
    if(rel<=1 || rel>=end-1)return;
    _snapUntil=CACurrentMediaTime()+.45;++_snaps;
    [table setContentOffset:CGPointMake(table.contentOffset.x,(rel<end*.5?0:end)-table.contentInset.top) animated:YES];
}

#pragma mark - Giving back

- (void)giveBackDragAndBounce {
    UIPanGestureRecognizer *drag=_dragPan;UITableView *table=_table;
    (void)table;_locked=NO;_pulling=NO;
    [self pauseVideo];
    if(_dragTouched){if(drag)drag.enabled=_dragWasEnabled;_dragTouched=NO;}
    [self giveBackDragTargets];   // FIX120 I
    if(_bounceTouched) {
        if(table) {
            table.bounces=_bouncesWas;table.alwaysBounceVertical=_alwaysBounceWas;
            if(table.contentOffset.y<-table.contentInset.top)[table setContentOffset:CGPointMake(table.contentOffset.x,-table.contentInset.top) animated:YES];   // (left pulled down: back to the top)
        }
        _bounceTouched=NO;
    }
}
- (void)restoreBecause:(NSString *)why {   // FIX120 G (diagnostics)
    if(_insetsApplied || _overlay.superview) {
        ++_restores;UITableView *table=_table;UIControl *header=_header;
        [self traceEvent:[NSString stringWithFormat:@"还原（%@）：表%d 头%d 头在表里%d 名%d 像%d",why,table!=nil,header!=nil,
                          (int)(header && table && [header isDescendantOfView:table]),_name!=nil,_avatar!=nil]];
    }
    [self restore];
}
- (void)restore {
    BOOL any=_insetsApplied || _overlay.superview || _itemsTouched || _qrTouched || _dragTouched || _bounceTouched;
    if(!any)return;
    UITableView *table=_table;
    if(_insetsApplied && table) {
        UIEdgeInsets cur=table.contentInset;
        if(UIEdgeInsetsEqualToEdgeInsets(cur,_appliedInsets)) {
            CGFloat rel=table.contentOffset.y+cur.top;
            table.contentInset=_baseInsets;
            table.contentOffset=CGPointMake(table.contentOffset.x,MAX(rel-_shift,0)-_baseInsets.top);
        }
    }
    _haveTableHome=NO;_lift=0;   // FIX120 I
    _insetsApplied=NO;_haveLayout=NO;_pull=_pullTarget=_pullVelocity=0;_pullSpring=_pulling=_locked=_pullPinned=NO;
    [self giveBackDragAndBounce];
    UIControl *qr=_qr;if(_qrTouched){qr.userInteractionEnabled=_qrTouchWas;_qrTouched=NO;}
    [_states restore];
    [self restoreStatus];
    UINavigationItem *item=_itemsOn;
    if(_itemsTouched && item) {
        if(item.leftBarButtonItem==_leftItem)item.leftBarButtonItem=_leftWas;
        if(item.rightBarButtonItem==_rightItem)item.rightBarButtonItem=_rightWas;
    }
    _itemsTouched=NO;_itemsOn=nil;_leftWas=_rightWas=nil;
    [self dropVideo];
    [_avatarTap.view removeGestureRecognizer:_avatarTap];
    [_overlay removeFromSuperview];[self pauseLink];_haveLast=NO;
    _haveSig=NO;
}

#pragma mark - The banner's video (FIX118 B)

static NSString *WXGMeVideoPath(void) {
    NSString *dir=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"WeChatLiquidGlass"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:@"meBanner.mov"];
}
- (NSString *)bannerVideoName {
    NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:WXGMeVideoPath() error:NULL];
    return a?[NSString stringWithFormat:@"已选（%.1f MB）",a.fileSize/1048576.0]:@"未选";
}
// FIX120 J: the asset's tracks loaded off the main thread (YES once the player is there; NO while it is being made). The
// frames asked for no larger than cover the screen's width both ways (a 4K clip was decoded and converted at full size for a
// banner 1320 px wide); the first frame decoded at once (paused at the start), so the pull has a picture from its first moment.
- (BOOL)prepareVideo {
    if(_videoOut)return YES;
    if(_videoLoading)return NO;
    NSString *path=WXGMeVideoPath();
    if(![NSFileManager.defaultManager fileExistsAtPath:path])return NO;
    if(!_textureCache && CVMetalTextureCacheCreate(kCFAllocatorDefault,NULL,WXGSharedDevice(),NULL,&_textureCache)!=kCVReturnSuccess){_videoNote=@"纹理缓存失败";return NO;}
    _videoLoading=YES;_videoNote=@"载入中";
    NSUInteger token=_videoToken;
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    __weak WXGMeHeader *weakSelf=self;
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        CGSize natural=CGSizeZero;
        if([asset statusOfValueForKey:@"tracks" error:NULL]==AVKeyValueStatusLoaded)natural=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject.naturalSize;
        dispatch_async(dispatch_get_main_queue(),^{
            WXGMeHeader *me=weakSelf;if(!me || me->_videoToken!=token)return;
            me->_videoLoading=NO;[me makePlayerFor:asset natural:natural];
        });
    }];
    return NO;
}
- (void)makePlayerFor:(AVURLAsset *)asset natural:(CGSize)natural {
    if(_videoOut)return;
    NSMutableDictionary *attributes=[@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferMetalCompatibilityKey:@YES} mutableCopy];
    CGFloat box=MAX(UIScreen.mainScreen.nativeBounds.size.width,320);
    _videoNatural=natural;_videoOutSize=natural;
    if(natural.width>1 && natural.height>1) {
        CGFloat f=MIN(1,MAX(box/natural.width,box/natural.height));   // (still covering the width both ways: aspect fill)
        if(f<.98) {
            _videoOutSize=CGSizeMake(round(natural.width*f/2)*2,round(natural.height*f/2)*2);
            attributes[(id)kCVPixelBufferWidthKey]=@((NSInteger)_videoOutSize.width);attributes[(id)kCVPixelBufferHeightKey]=@((NSInteger)_videoOutSize.height);
        }
    }
    AVPlayerItem *item=[AVPlayerItem playerItemWithAsset:asset];
    _videoOut=[[AVPlayerItemVideoOutput alloc]initWithPixelBufferAttributes:attributes];
    [item addOutput:_videoOut];
    _player=[AVPlayer playerWithPlayerItem:item];_player.muted=YES;_player.actionAtItemEnd=AVPlayerActionAtItemEndNone;
    if(@available(iOS 12.0,*))_player.preventsDisplaySleepDuringVideoPlayback=NO;
    __weak AVPlayer *weakPlayer=_player;
    _loopObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue
        usingBlock:^(__unused NSNotification *n){[weakPlayer seekToTime:kCMTimeZero];[weakPlayer play];}];
    [_player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];   // (the first frame decoded now)
    _videoNote=@"已载入";
}
- (void)playVideo {if(!_videoPlaying && _player){[_player play];_videoPlaying=YES;}}
- (void)pauseVideo {if(_videoPlaying){[_player pause];_videoPlaying=NO;}}
- (BOOL)pullVideoFrame {
    AVPlayerItemVideoOutput *out=_videoOut;if(!out || !_textureCache)return _videoRef!=NULL;
    CMTime time=[out itemTimeForHostTime:CACurrentMediaTime()];
    if(![out hasNewPixelBufferForItemTime:time])return _videoRef!=NULL;
    CVPixelBufferRef buffer=[out copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];if(!buffer)return _videoRef!=NULL;
    CVMetalTextureRef texture=NULL;
    CVReturn r=CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,_textureCache,buffer,NULL,MTLPixelFormatBGRA8Unorm,
        CVPixelBufferGetWidth(buffer),CVPixelBufferGetHeight(buffer),0,&texture);
    if(r!=kCVReturnSuccess || !texture){CVPixelBufferRelease(buffer);return _videoRef!=NULL;}
    // (the frame before kept one frame longer: the GPU may still be reading it)
    if(_videoRefOld)CFRelease(_videoRefOld);
    if(_videoBufferOld)CVPixelBufferRelease(_videoBufferOld);
    _videoRefOld=_videoRef;_videoBufferOld=_videoBuffer;_videoRef=texture;_videoBuffer=buffer;++_videoFrames;
    if(_videoFrames%120==0)CVMetalTextureCacheFlush(_textureCache,0);
    return YES;
}
- (void)dropVideo {
    [self pauseVideo];
    ++_videoToken;_videoLoading=NO;   // FIX120 J (one being loaded is not used)
    if(_loopObserver){[NSNotificationCenter.defaultCenter removeObserver:_loopObserver];_loopObserver=nil;}
    _player=nil;_videoOut=nil;_metal.videoTexture=nil;
    if(_videoRef){CFRelease(_videoRef);_videoRef=NULL;}
    if(_videoRefOld){CFRelease(_videoRefOld);_videoRefOld=NULL;}
    if(_videoBuffer){CVPixelBufferRelease(_videoBuffer);_videoBuffer=NULL;}
    if(_videoBufferOld){CVPixelBufferRelease(_videoBufferOld);_videoBufferOld=NULL;}
}
- (void)pickBannerVideoFrom:(UIViewController *)controller {
    PHPickerConfiguration *configuration=[PHPickerConfiguration new];
    configuration.filter=PHPickerFilter.videosFilter;configuration.selectionLimit=1;
    configuration.preferredAssetRepresentationMode=PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker=[[PHPickerViewController alloc]initWithConfiguration:configuration];picker.delegate=self;
    [controller presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider=results.firstObject.itemProvider;if(!provider)return;
    __weak WXGMeHeader *weakSelf=self;
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url,NSError *error){
        NSString *path=WXGMeVideoPath(),*note=nil;
        if(url) {
            NSString *temp=[path stringByAppendingString:@".tmp"];
            [NSFileManager.defaultManager removeItemAtPath:temp error:NULL];
            NSError *copyError=nil;
            if([NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:temp] error:&copyError]) {
                [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
                [NSFileManager.defaultManager moveItemAtPath:temp toPath:path error:NULL];
                note=@"横幅视频已更新";
            }else note=[@"复制视频失败：" stringByAppendingString:copyError.localizedDescription?:@"?"];
        }else note=[@"读取视频失败：" stringByAppendingString:error.localizedDescription?:@"?"];
        dispatch_async(dispatch_get_main_queue(),^{
            WXGMeHeader *me=weakSelf;[me dropVideo];me->_videoNote=note;WXGLog(@"我页横幅：%@",note);
            [NSNotificationCenter.defaultCenter postNotificationName:WXGSettingsChanged object:nil];
        });
    }];
}
- (void)clearBannerVideo {
    [self dropVideo];[NSFileManager.defaultManager removeItemAtPath:WXGMeVideoPath() error:NULL];_videoNote=@"已清除";
}

- (NSDictionary *)evidence {
    UITableView *table=_table;
    return @{@"on":@(WXGMeOn()),@"status":_status_?:@"",@"page":_page?NSStringFromClass(_page.class):@"",@"table":table?NSStringFromClass(table.class):@"",
             @"parts":@{@"header":@(_header!=nil),@"avatar":@(_avatar!=nil),@"photo":@(_photoView!=nil),@"name":@(_name!=nil),@"id":@(_wxid!=nil),@"qr":@(_qr!=nil),
                        @"chevron":@(_chevron!=nil),@"status":@([self statusViews].count),@"weChatDrag":@(_dragPan!=nil)},
             @"cutout":@{@"kind":@(_cutout.kind),@"fromTable":@(_cutout.known),@"rect":NSStringFromCGRect(CGRectMake(_cutout.x,_cutout.y,_cutout.w,_cutout.h)),@"merge":@(_merge)},
             @"banner":@(_banner),@"shift":@(_shift),@"collapse":@(_collapse),@"travel":@(round(_travel*10)/10),
             @"insets":@{@"wechat":NSStringFromUIEdgeInsets(_baseInsets),@"applied":_insetsApplied?NSStringFromUIEdgeInsets(_appliedInsets):@""},
             @"photo":_shownPhoto?[NSString stringWithFormat:@"%.0fx%.0f",_shownPhoto.size.width*_shownPhoto.scale,_shownPhoto.size.height*_shownPhoto.scale]:@"",
             @"metal":@{@"frames":@(_metal.frames),@"failure":_metal.failure?:@""},
             @"pull":@{@"pull":@(round(_pull)),@"locked":@(_locked),@"locks":@(_locks),@"visual":@(round(_pullVisual))},
             @"video":@{@"file":[self bannerVideoName],@"note":_videoNote?:@"",@"frames":@(_videoFrames),@"playing":@(_videoPlaying),
                        @"natural":NSStringFromCGSize(_videoNatural),@"decodedAt":NSStringFromCGSize(_videoOutSize)},   // FIX120 J
             @"canvasResizes":@(_canvasResizes),
             @"photoSource":WXGSelfAvatarState(),@"avatarTaps":@(_avatarTaps),@"edgeStyle":@(WXGMeEdgeStyle()),@"dripRoom":@(round(_dripRoom)),@"renders":@(_renders),@"snaps":@(_snaps),@"passes":@(_passes),
             @"fullPasses":@(_fullPasses),@"skippedPasses":@(_skips),@"canvasHeight":@(round(_canvasHeight)),   // FIX119 B
             @"statusMovedByWeChat":@(_statusMoves),@"statusMovedToY":@(round(_statusMovedY)),   // FIX120 F
             @"flicker":@{@"restores":@(_restores),@"insetRetakes":@(_insetRetakes),@"overlayCovered":@(_overlayCovered),@"coveredBy":_coveredBy?:@"",
                          @"gateSkips":@(_gateSkips),@"worstRenderMS":@(round(_worstRenderMS*10)/10),
                          @"traceKey":@"t 屏幕上的行程 抬 微信把列表容器抬起的距离 o 偏移 in 当前/微信 inset.top tc 标题收起点 end 终点 名y 名字中心 顶=层在最上 表y/层y 窗口坐标 画布高 R画了 g闸门跳过 s没变 m静止 f失败 -没画 状 状态行 alpha 慢=整套 按/惯"},
             @"trace":[_trace copy]?:@[],   // FIX120 G
             @"weChatDrag":@{@"targetHolds":@(_targetHolds),@"held":@(_heldTargets.count),@"panTargets":_panTargetsSeen?:@"",@"helperMethods":_helperMethods?:@"",
                             @"tableObservers":_tableObservers?:@"",@"lift":@(round(_lift*10)/10),@"maxLift":@(round(_maxLift)),@"home":@(round(_tableHome*10)/10)},   // FIX120 I
             @"title":@{@"collapse":@(round(_titleCollapse*10)/10),@"end":@(round(_collapseAll*10)/10),@"fraction":@(round(_titlePose.fraction*100)/100),
                        @"locked":@(_titlePose.locked)}};
}
@end
