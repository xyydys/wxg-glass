#include <metal_stdlib>
using namespace metal;
#include "WXGLensOptics.h"

struct WXGUniforms {
    float4 viewport;   // width/height in points, drawable scale, time
    float4 bar;
    float4 lens;
    float4 material;   // press, refraction, dispersion, Gaussian sigma in points
    float4 appearance; // dark, clear, native distance field available, surface (0 body / 1 lens)
    float4 optics;     // content zoom, body border width, body pinch, edge width
    float4 lensOptics; // independent pressed refraction, RGB dispersion, edge width, lens blur coverage
    float4 selectionColor;
    float4 borderColor;
    float4 motion;     // whole-bar scale, fade material at edge, blur coverage, icon anchor x
    float4 rim;        // directional fade, dark gain, lens stroke width, optional maximum corner radius
    float4 tintColor;  // independent material veil, including opacity
    float4 sync;       // FIX18 x: 0 readback optics, 1 hybrid edge band, 2 render-server body; FIX21 y: lens top/bottom width ratio, z: narrowing sharpness
    float4 style;      // FIX27 x: material veil fade width in pt (0 = refraction width), y: rim top-left fade, z: rim bottom-right fade
    float4 glow;       // FIX86 x: iOS 27-like rim on (optics.y is then its width; FIX87: x = 1 + the highlight's angle in radians), y: end level, z: sharpness, w: inward curve
    float4 extra;      // FIX88 y: lens dispersion range (pt), z: its top / bottom ratio; FIX89 x: the second highlight's width; FIX94 w: the bar-follows-the-rim margin (0 off)
    float4 glow2;      // FIX89: the iOS 27-like rim's second highlight, as glow
    float4 glowColor2; // FIX89: its colour, alpha = opacity (the first's is borderColor)
    float4 extra2;     // FIX97 x: the colour split of the bar seen through the lens (pt), y: its share of the lens' own split, z: the page behind (0 black .. 1 white); FIX98 w: 1 + the selection colour's weight (0: by the press)
};
// FIX86: the bar outline drawn by the shader (inside the dock's lens) as the
// iOS 27-like rim of the CA rim view (WXGRimGlow.h): full at the outline,
// fading inward over `width` (depth = points inside the outline), and along
// the outline 1 where it faces the highlight's direction (FIX87: at an
// angle, 0 = up / down), the end level where it faces across it.
// FIX89: two of these, each its own colour, drawn one over the other.
float wxgGlowStroke(float coverage,float depth,float width,float nx,float ny,float4 g) {
    float inward=pow(saturate(1.-max(depth,0.)/max(width,.01)),max(g.w,.05));
    float a=g.x-1.,k=max(g.z,.05);
    float facing=min(abs(nx*sin(a)+ny*cos(a)),1.);
    float along=saturate(g.y)+(1.-saturate(g.y))*pow(facing,k);
    return coverage*inward*along;
}
// FIX27: the distance from the contour over which the material veil weakens.
float wxgVeilWidth(float refractionWidth,constant WXGUniforms &u) { return u.style.x>0.?u.style.x:refractionWidth; }
struct WXGOut { float4 position [[position]]; float2 uv; };
vertex WXGOut wxgVertex(uint vid [[vertex_id]]) {
    const float2 vertices[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
    WXGOut out; out.position=float4(vertices[vid],0,1);
    out.uv=float2(vertices[vid].x*.5+.5,.5-vertices[vid].y*.5); return out;
}
constexpr sampler wxgSampler(coord::normalized,address::clamp_to_edge,filter::linear);
// Full-resolution separable Gaussian with paired adjacent taps, no mipmap blur.
kernel void wxgBlur(texture2d<float,access::sample> input [[texture(0)]],
                    texture2d<float,access::write> output [[texture(1)]],
                    constant float4 &params [[buffer(0)]],
                    constant WXGGaussianKernel &weights [[buffer(1)]],uint2 pos [[thread_position_in_grid]]) {
    if(pos.x>=output.get_width() || pos.y>=output.get_height()) return;
    float2 uv=(float2(pos)+.5)/float2(output.get_width(),output.get_height());
    float4 sum=input.sample(wxgSampler,uv)*weights.center;
    for(int i=0;i<weights.count;i++) {
        float2 offset=params.xy*weights.offsets[i];
        sum+=(input.sample(wxgSampler,uv+offset)+input.sample(wxgSampler,uv-offset))*weights.weights[i];
    }
    output.write(sum,pos);
}
WXGShapeSample wxgShape(float2 p,float4 rect,float radius) {
    float2 q=p-(rect.xy+rect.zw*.5);
    return radius>0.?WXGRoundedOpticalField(q.x,q.y,rect.z,rect.w,radius):WXGCapsuleOpticalField(q.x,q.y,rect.z,rect.w);
}
float wxgMask(float d,float aa) { return 1.-smoothstep(-aa,aa,d); }
// FIX88: the bar's inset in the lens at a point of the bar's (base) space:
// from the nearest point of the bar's outline, how far inside the lens it
// lies along that outline (WXGLensDepthAlongBar), through WXGInnerInsetAlong.
// The lens pass evaluates it where the bar is sampled (after refraction), so
// the slope itself is refracted.
float wxgLensInset(float2 basePt,float press,constant WXGUniforms &u) {
    WXGShapeSample b=wxgShape(basePt,u.bar,u.rim.w);
    float2 c=u.bar.xy+u.bar.zw*.5;
    float2 q=basePt-float2(b.nx,b.ny)*b.distance;
    float2 qs=c+(q-c)*u.motion.x;
    WXGShapeSample l=wxgShape(qs,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));
    float along=WXGLensDepthAlongBar(l.distance,-b.ny,b.nx,l.nx,l.ny);
    return WXGInnerInsetAlong(u.bar.w*u.motion.x,press,u.optics.z,along);
}
float wxgEdge(float d,float width) { return 1.-smoothstep(0.,width,max(-d,0.)); }
float3 wxgRGB(texture2d<float> tex,float2 p,float2 chroma,constant WXGUniforms &u) {
    return float3(tex.sample(wxgSampler,(p+chroma)/u.viewport.xy).r,
                  tex.sample(wxgSampler,p/u.viewport.xy).g,
                  tex.sample(wxgSampler,(p-chroma)/u.viewport.xy).b);
}
float2 wxgBasePoint(float2 p,constant WXGUniforms &u) {
    float2 c=u.bar.xy+u.bar.zw*.5;
    return c+(p-c)/u.motion.x;
}
float3 wxgBody(texture2d<float> raw,texture2d<float> soft,texture2d<float> lensSoft,float blurBlend,float blurCoverage,float2 geometry,
               float inset,float2 ray,float2 extraChroma,WXGOpticalValues optical,constant WXGUniforms &u) {
    WXGShapeSample shape=wxgShape(geometry,u.bar,u.rim.w); float2 n=float2(shape.nx,shape.ny);
    shape.distance+=inset;
    float edge=wxgEdge(shape.distance,optical.edgeWidth);
    float offset=WXGOpticalOffset(shape.distance,optical.edgeWidth,optical.refraction)*u.motion.x;
    float2 source=ray-n*offset;
    float2 chroma=n*(optical.dispersion*edge*.85)+extraChroma;
    float3 sharp=wxgRGB(raw,source,chroma,u),blurred=wxgRGB(soft,source,chroma,u);
    if(blurBlend>0.)blurred=mix(blurred,wxgRGB(lensSoft,source,chroma,u),blurBlend);
    float3 face=mix(blurred,sharp,WXGBlurSharpWeight(shape.distance,optical.edgeWidth,blurCoverage));
    float luma=dot(face,float3(.2126,.7152,.0722)); face=mix(float3(luma),face,1.05);
    // Default is the original TEST6 edge attenuation; disabling it keeps the
    // same user-selected opacity throughout the material.
    float opacity=WXGMaterialOpacity(u.tintColor.a,u.appearance.y,wxgEdge(shape.distance,wxgVeilWidth(optical.edgeWidth,u)),u.motion.y);
    return saturate(mix(face,u.tintColor.rgb,opacity));
}
float3 wxgIcons(texture2d<float> icons,float2 source,float2 chroma,float3 face,
                 constant WXGUniforms &u) {
    float4 r=icons.sample(wxgSampler,(source+chroma)/u.viewport.xy);
    float4 g=icons.sample(wxgSampler,source/u.viewport.xy);
    float4 b=icons.sample(wxgSampler,(source-chroma)/u.viewport.xy);
    // Images contain premultiplied alpha; each refracted colour uses its own alpha.
    return float3(r.r+face.r*(1.-r.a),g.g+face.g*(1.-g.a),b.b+face.b*(1.-b.a));
}
// FIX18 render-server modes. This layer is composited by Core Animation over
// a CABackdropLayer that the render server captures and blurs at DISPLAY time,
// so that part never lags. Output is premultiplied. With tint opacity k and
// hybrid edge-band weight w, compositing over the live backdrop B gives
//   w*F + (1-w)*(k*tint + (1-k)*B)
// i.e. the readback face F only inside the refraction band, and the same
// tint veil as the readback path everywhere else.
float4 wxgSyncBase(float3 face,float w,float k,constant WXGUniforms &u) {
    return float4(face*w+(1.-w)*k*u.tintColor.rgb,1.-(1.-w)*(1.-k));
}
float4 wxgOver(float4 src,float4 dst) { return src+dst*(1.-src.a); }
float4 wxgIconsOver(texture2d<float> icons,float2 source,float2 chroma,float4 acc,constant WXGUniforms &u) {
    float4 r=icons.sample(wxgSampler,(source+chroma)/u.viewport.xy);
    float4 g=icons.sample(wxgSampler,source/u.viewport.xy);
    float4 b=icons.sample(wxgSampler,(source-chroma)/u.viewport.xy);
    return float4(r.r+acc.r*(1.-r.a),g.g+acc.g*(1.-g.a),b.b+acc.b*(1.-b.a),g.a+acc.a*(1.-g.a));
}
// FIX97: the bar seen through the render-server lens at screen point p: its
// signed distance on screen (inset contour; < 0 inside), the bent sample and
// inset (FIX44 / FIX46 / FIX57 / FIX88 / FIX94, as the lens pass had them
// inline), so it can be asked again at a channel's shifted point.
struct WXGLensBar { float dd; WXGShapeSample s; float insetBent; float rim; float2 n; };
WXGLensBar wxgLensBar(float2 p,float press,WXGOpticalValues optical,constant WXGUniforms &u) {
    WXGShapeSample lens=wxgShape(p,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));
    float2 n=float2(lens.nx,lens.ny),center=u.lens.xy+u.lens.zw*.5;
    float lensWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,optical.edgeWidth,u.sync.y,u.sync.z,wxgShape(wxgBasePoint(p,u),u.bar,u.rim.w).distance*u.motion.x);
    float2 barMid=u.bar.xy+u.bar.zw*.5;
    float barHalf=u.bar.z*u.motion.x*.5;
    float endLeft=WXGLensEndReach(barMid.x-barHalf,barMid.x+barHalf,u.lens.x,u.lens.x+u.lens.z,-1);
    float endRight=WXGLensEndReach(barMid.x-barHalf,barMid.x+barHalf,u.lens.x,u.lens.x+u.lens.z,1);
    float barBand=WXGLensEndRelax(lensWidth,lens.nx,optical.edgeWidth,u.sync.y,endLeft,endRight);
    float2 bend=wxgBasePoint(p-n*(WXGOpticalOffset(lens.distance,barBand,optical.refraction)*press),u);
    // FIX94 (extra.w = the margin, 0 off): the bar follows the lens' rim,
    // magnified vertically per column (WXGLensBarZoom), not bent.
    float zf=1.;
    if(u.extra.w>0.) {
        zf=WXGLensBarZoom(p.x,barMid.x,barMid.y,u.bar.z*u.motion.x,u.bar.w*u.motion.x,center.x,center.y,u.lens.z,u.lens.w,
                          u.bar.w*u.motion.x,press,u.optics.z,optical.edgeWidth,u.sync.y,u.sync.z,u.extra.w);
        bend=wxgBasePoint(float2(p.x,barMid.y+(p.y-barMid.y)/zf),u);
    }
    WXGLensBar r;
    // FIX97: how strongly the lens refracts the bar here: deep in its band, and
    // the band's width against the ends' (1 at the ends, the top / bottom
    // ratio above and below); the direction.
    r.rim=wxgEdge(lens.distance,barBand)*clamp(barBand/max(optical.edgeWidth,1.),0.,1.);r.n=n;
    r.s=wxgShape(bend,u.bar,u.rim.w);
    r.insetBent=wxgLensInset(bend,press,u);   // FIX88: the slope first, then refracted
    // The magnified bar's distance on screen: vertical stretch only, so by its
    // normal (the top / bottom zf times, the ends' sides 1).
    r.dd=(r.s.distance*u.motion.x+r.insetBent)/max(length(float2(r.s.nx,r.s.ny/zf)),1./zf);
    return r;
}
// The bar's outline stroke in the lens for one channel's coverage / distance.
float wxgLensStroke(float cv,float dd,float soft,WXGShapeSample s,constant WXGUniforms &u) {
    return u.glow.x>.5?wxgGlowStroke(cv,-dd,u.optics.y,s.nx,s.ny,u.glow):max(0.,cv-(1.-smoothstep(-soft,soft,dd+u.optics.y)));
}
// FIX98: how much of the resting selection colour shows: the dock's own
// (extra2.w = 1 + weight: a tap's scripted fade), else by the press.
float wxgSelectionWeight(float press,constant WXGUniforms &u) {return u.extra2.w>.5?saturate(u.extra2.w-1.):WXGRestingSelectionWeight(press);}
// FIX97: the bar's layers in the lens (veil, outline stroke, second
// highlight, resting selection) for one distance; premultiplied. With the
// colour split off this is exactly the FIX46..FIX96 lens pass.
float4 wxgLensBarLayers(float dd,float soft,float em,float rimStrength,float selW,WXGShapeSample s,constant WXGUniforms &u) {
    float cv=1.-smoothstep(-soft,soft,dd);
    float4 acc=float4(u.tintColor.rgb,1.)*(WXGMaterialOpacity(u.tintColor.a,u.appearance.y,em,u.motion.y)*cv);
    acc=wxgOver(float4(u.borderColor.rgb,1.)*(wxgLensStroke(cv,dd,soft,s,u)*u.borderColor.a*rimStrength),acc);
    if(u.glow.x>.5) acc=wxgOver(float4(u.glowColor2.rgb,1.)*(wxgGlowStroke(cv,-dd,u.extra.x,s.nx,s.ny,u.glow2)*u.glowColor2.a),acc);   // FIX89
    return wxgOver(float4(u.selectionColor.rgb,1.)*(u.selectionColor.a*cv*selW),acc);
}
// FIX97: the same layers over a continuous spectrum, blue (t = -1, the bar at
// p - split) to red (t = +1, p + split), seven wavelengths with the distance
// quadratic through the three asked for; red / green / blue weigh them by
// tents peaking at t = 1 / 0 / -1. A thin highlight fans into a soft rainbow,
// not three separate coloured lines; with no split it is wxgLensBarLayers.
// Core Animation lays this layer over the live page with ONE alpha (the most
// covered channel's), so a channel covered less would show too little of the
// page: that share of the page behind (extra2.z, its brightness: black in
// dark mode, white in light) is added back, exact over that page.
float4 wxgLensBarSpectrum(float dd,float ddR,float ddB,float soft,float em,float rimStrength,float selW,WXGShapeSample s,constant WXGUniforms &u) {
    float a1=(ddR-ddB)*.5,a2=(ddR+ddB)*.5-dd;
    float wide=max(soft,abs(a1)*.25+abs(a2)*.4);   // each wavelength covers its step (the largest, t 2/3..1)
    float3 rgb=float3(0.),alpha=float3(0.);
    for(int k=0;k<7;k++) {
        float t=float(k)/3.-1.;
        float3 w=float3(saturate(t),1.-abs(t),saturate(-t));
        float4 l=wxgLensBarLayers(dd+t*(a1+t*a2),wide,em,rimStrength,selW,s,u);
        rgb+=w*l.rgb;alpha+=w*l.a;
    }
    rgb/=float3(2.,3.,2.);alpha/=float3(2.,3.,2.);
    float most=max(alpha.x,max(alpha.y,alpha.z));
    return float4(rgb+saturate(u.extra2.z)*(float3(most)-alpha),most);
}
fragment float4 wxgFragment(WXGOut in [[stage_in]],constant WXGUniforms &u [[buffer(0)]],
                            texture2d<float> raw [[texture(0)]],
                            texture2d<float> normalIcons [[texture(1)]],
                            texture2d<float> selectedIcons [[texture(2)]],
                            texture2d<float> soft [[texture(3)]],
                            texture2d<float> bodyField [[texture(4)]],
                            texture2d<float> lensSoft [[texture(5)]]) {
    float2 p=in.uv*u.viewport.xy;
    // Native continuous clipping and separate native-width directional rims
    // own the final silhouette. No second analytical alpha mask cuts it again.
    float2 base=wxgBasePoint(p,u);
    WXGOpticalValues bodyOptics={u.material.y,u.material.z,u.optics.w};
    if(u.appearance.w<.5) {
        // Ordinary buttons deform one body. This path has no selection tint,
        // inner capsule, second silhouette or lens rim; dock optics stay intact.
        float2 bodyRay=p;
        if(u.appearance.w<-.5) {
            float buttonPress=clamp(u.material.x,0.,1.);
            bodyOptics.refraction*=1.+.35*buttonPress;
            bodyOptics.dispersion*=1.+.20*buttonPress;
            float2 bodyCenter=u.bar.xy+u.bar.zw*.5;
            bodyRay=bodyCenter+(p-bodyCenter)/(1.+.04*buttonPress);
        }
        float3 face=wxgBody(raw,soft,soft,0.,u.motion.z,base,0.,bodyRay,float2(0),bodyOptics,u);
        if(u.sync.x>.5) {
            WXGShapeSample shape=wxgShape(base,u.bar,u.rim.w);
            float e=wxgEdge(shape.distance,bodyOptics.edgeWidth);
            // FIX40: sync.w = 1: the veil is a render-server layer under this
            // pass (always present, cold start included); draw icons only.
            float k=u.sync.w>.5?0.:WXGMaterialOpacity(u.tintColor.a,u.appearance.y,wxgEdge(shape.distance,wxgVeilWidth(bodyOptics.edgeWidth,u)),u.motion.y);
            float4 veil=wxgSyncBase(face,u.sync.x>1.5?0.:e,k,u);
            float4 withIcons=wxgIconsOver(normalIcons,base,float2(0),veil,u);
            // FIX37: inside the dock's lens the lens pass draws the selected
            // (filled) icons; the body must not draw the unselected ones there
            // too, or both show (refracted, slightly offset) as a ghost.
            if(u.sync.x>1.5 && u.lens.z>.5 && u.lens.w>.5) {
                WXGShapeSample inLens=wxgShape(p,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));
                withIcons=mix(withIcons,veil,1.-smoothstep(-.5,.5,inLens.distance));
            }
            return withIcons;
        }
        return float4(wxgIcons(normalIcons,base,float2(0),face,u),1);
    }
    float aa=.8/u.viewport.z,press=clamp(u.material.x,0.,1.);
    WXGOpticalValues independent={u.lensOptics.x,u.lensOptics.y,u.lensOptics.z};
    WXGOpticalValues optical=WXGPressedOptics(bodyOptics,independent,press);
    WXGShapeSample lens=wxgShape(p,u.lens,u.rim.w*u.lens.w/max(1.,u.bar.w));
    float2 center=u.lens.xy+u.lens.zw*.5,n=float2(lens.nx,lens.ny);
    float zoom=1.+press*(u.optics.x-1.);
    // FIX21: the lens rim is widest at its rounded ends and thin above/below the bar.
    // FIX47: a lens end past the bar's end narrows to the top/bottom width.
    float lensWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,optical.edgeWidth,u.sync.y,u.sync.z,wxgShape(base,u.bar,u.rim.w).distance*u.motion.x);
    float offset=WXGOpticalOffset(lens.distance,lensWidth,optical.refraction)*press;
    float2 refracted=p-n*offset;
    float2 ray=center+(refracted-center)/zoom;
    // FIX88: the colour split over its own band (u.extra.y, its own top /
    // bottom ratio u.extra.z), blended from the glass's band as it lifts.
    float dispSide=u.extra.y>0.?mix(bodyOptics.edgeWidth,u.extra.y,press):optical.edgeWidth;
    float dispWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,dispSide,u.extra.z>0.?u.extra.z:u.sync.y,u.sync.z,wxgShape(base,u.bar,u.rim.w).distance*u.motion.x);
    float2 chroma=n*(optical.dispersion*wxgEdge(lens.distance,dispWidth)*(1.55*press));
    float2 iconCenter=float2(u.motion.w,u.bar.y+u.bar.w*.5);
    // FIX21: icons are magnified about their own anchor in the bar's unscaled
    // space, so an elastically stretched lens (whose centre shifts) cannot move them.
    float2 barCentre=u.bar.xy+u.bar.zw*.5;
    float2 iconRay=iconCenter+((barCentre+(refracted-barCentre)/u.motion.x)-iconCenter)/zoom;
    // Change only the geometric contour: regular parallel inset at top, bottom
    // and both ends. Optical sampling never displaces this contour.
    WXGShapeSample body=wxgShape(base,u.bar,u.rim.w);
    float nativeDistance=body.distance;
    if(u.appearance.z>.5) nativeDistance=bodyField.sample(wxgSampler,base/u.viewport.xy).r;
    float inset=wxgLensInset(base,press,u);   // FIX88 (was WXGInnerInset by the lens distance)
    float d=nativeDistance*u.motion.x+inset;
    float coverage=wxgMask(d,aa),stroke=max(0.,coverage-wxgMask(d+u.optics.y,aa));
    if(u.sync.x>1.5) {
        // Render-server lens: the shared backdrop is live underneath. Draw the
        // same veil, rim stroke, resting selection and zoomed icons only.
        // FIX44: the bar under the lens is bent by the lens' refraction.
        // FIX46: by the refraction band only (no zoom), so the inset smaller
        // inner bar stays; analytic outline antialiased over its actual
        // screen-space gradient (no stair steps or torn slivers).
        // FIX57: as a lens end reaches the bar's end, the bar seen through it
        // uses the band relaxed toward the top/bottom width (no more sticking
        // to the rim at the first / last tab); icons keep lensWidth.
        // (All of it in wxgLensBar, FIX97.)
        WXGLensBar g=wxgLensBar(p,press,optical,u);
        WXGShapeSample s=g.s;
        float dd=g.dd;
        // FIX97 (extra2.x: the split everywhere in the lens, growing from its
        // centre to its rim like a dome's; extra2.y: the share of the lens' own
        // colour split where the lens refracts the bar (its ends' wide band,
        // thin above and below); both 0 = off, as FIX46..FIX96): the bar seen
        // through the lens splits its colours too, across all of its edges
        // (the slots' "brackets", its outline highlights): red from that far
        // out, blue from that far in, over a continuous spectrum (FIX46's
        // removed split had three separate lines and no switch).
        float soft=max(aa,fwidth(dd)*.75);
        float em=wxgEdge(s.distance+g.insetBent/u.motion.x,wxgVeilWidth(optical.edgeWidth,u));
        float rimStrength=WXGRimStrengthTLBR(s.nx,s.ny,u.rim.x,u.style.y,u.style.z)*mix(1.,u.rim.y,u.appearance.x);
        float selW=wxgSelectionWeight(press,u);
        float4 acc=wxgLensBarLayers(dd,soft,em,rimStrength,selW,s,u);
        if(u.extra2.x>0. || u.extra2.y>0.) {
            float2 dome=(p-center)/max(u.lens.zw*.5,float2(1.));
            float2 split=dome*(u.extra2.x*press)+g.n*(u.extra2.y*optical.dispersion*1.55*press*g.rim);
            if(lens.distance<1. && dot(split,split)>1e-6)   // the lens canvas is the whole view: only in the lens
                acc=wxgLensBarSpectrum(dd,wxgLensBar(p+split,press,optical,u).dd,wxgLensBar(p-split,press,optical,u).dd,soft,em,rimStrength,selW,s,u);
        }
        return wxgIconsOver(selectedIcons,iconRay,chroma/(u.motion.x*zoom),acc,u);
    }
    float3 clear=wxgRGB(raw,ray,chroma,u);
    float blurCoverage=mix(u.motion.z,u.lensOptics.w,press);
    float3 ringSoft=mix(wxgRGB(soft,ray,chroma,u),wxgRGB(lensSoft,ray,chroma,u),press);
    clear=mix(clear,ringSoft,WXGLensRingBlurWeight(lens.distance,lensWidth,blurCoverage));
    // Coverage zero preserves the TEST8 clear ring. Disabling material
    // attenuation applies the same tint veil over the whole lens ring.
    if(u.motion.y<.5) clear=mix(clear,u.tintColor.rgb,WXGMaterialOpacity(u.tintColor.a,u.appearance.y,0.,0.));
    float3 material=wxgBody(raw,soft,lensSoft,press,blurCoverage,base,inset/u.motion.x,ray,chroma,optical,u);
    float3 face=mix(clear,material,coverage);
    float rimStrength=WXGRimStrengthTLBR(body.nx,body.ny,u.rim.x,u.style.y,u.style.z)*mix(1.,u.rim.y,u.appearance.x);
    if(u.glow.x>.5) stroke=wxgGlowStroke(coverage,-d,u.optics.y,body.nx,body.ny,u.glow);   // FIX86
    face=mix(face,u.borderColor.rgb,stroke*u.borderColor.a*rimStrength);
    if(u.glow.x>.5) face=mix(face,u.glowColor2.rgb,wxgGlowStroke(coverage,-d,u.extra.x,body.nx,body.ny,u.glow2)*u.glowColor2.a);   // FIX89
    // Withdraw the resting selection as the lens rises. It must not leave a
    // selected-colour patch where the raised lens overlaps the ordinary bar.
    face=mix(face,u.selectionColor.rgb,u.selectionColor.a*coverage*wxgSelectionWeight(press,u));
    return float4(wxgIcons(selectedIcons,iconRay,chroma/(u.motion.x*zoom),face,u),1);
}
