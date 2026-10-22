#ifndef WXG_OPTICS_H
#define WXG_OPTICS_H
// The exact same geometry functions are compiled by the Metal renderer and C tests.
#ifdef __METAL_VERSION__
#define WXG_POW pow
#define WXG_SQRT sqrt
#define WXG_ABS fabs
#define WXG_MIN min
#define WXG_MAX max
#define WXG_LOG log
#define WXG_EXP exp
#define WXG_ATAN2 atan2
#define WXG_SIN sin
#define WXG_COS cos
#else
#include <math.h>
#define WXG_POW powf
#define WXG_SQRT sqrtf
#define WXG_ABS fabsf
#define WXG_MIN fminf
#define WXG_MAX fmaxf
#define WXG_LOG logf
#define WXG_EXP expf
#define WXG_ATAN2 atan2f
#define WXG_SIN sinf
#define WXG_COS cosf
#endif
static inline float WXGOClamp(float x,float lo,float hi) { return WXG_MIN(hi,WXG_MAX(lo,x)); }
typedef struct { float distance,nx,ny; } WXGShapeSample;
/* FIX96: Core Animation's continuous capsule (cornerCurve continuous, corner
   radius half the short side), measured on the tester's phone at 3x: the
   dock's lens (aspect 1.26) and the dock itself (5.3) in FIX93's screenshot
   give the same curve to 0.2% of the radius. About each end's centre, at the
   angle phi (radians) from the straight side's normal (0 where a circle would
   leave the straight side, pi/2 the very end, negative over the straight
   side), its outline lies R * this outside the circular capsule (inside where
   negative): it leaves the straight side some 16 degrees early, runs up to
   1.2% R inside around the join, crosses at 23 degrees and is up to 0.9% R
   fuller near 42 degrees (a squircle's end). A 5-term sine series over -24..90
   degrees (rms 0.16% R, 0.06 pt on the lens). */
static inline float WXGContinuousDeviation(float phi) {
    float t=(phi+.41887902f)/1.98967535f;   // -24 .. 90 degrees
    if(!(t>0.f && t<1.f))return 0.f;
    float th=3.14159265f*t,s1=WXG_SIN(th),c1=WXG_COS(th);
    float s2=2.f*s1*c1,c2=c1*c1-s1*s1;
    float s3=s2*c1+c2*s1,c3=c2*c1-s2*s1;
    float s4=s3*c1+c3*s1,c4=c3*c1-s3*s1;
    float s5=s4*c1+c4*s1;
    return .000865f*s1-.007454f*s2-.002456f*s3+.002256f*s4+.002806f*s5;
}
// FIX96: how far a capsule's continuous outline lies outside the circular
// one at a point (centred coordinates): what the capsule's distance loses. A
// nearly round shape (aspect below 1.25) blends back to the circle by 1.15;
// the correction fades out toward each end's centre, far inside every band.
static inline float WXGContinuousCorrection(float x,float y,float width,float height) {
    float r=WXG_MAX(.5f,WXG_MIN(width,height)*.5f);
    float longSide=WXG_MAX(width,height),shortSide=WXG_MAX(WXG_MIN(width,height),1.f);
    float k=WXGOClamp((longSide/shortSide-1.15f)/.10f,0.f,1.f);
    if(!(k>0.f) || !(r>1.f))return 0.f;
    int horizontal=width>=height;
    float along=horizontal?WXG_ABS(x)-(width*.5f-r):WXG_ABS(y)-(height*.5f-r),across=horizontal?WXG_ABS(y):WXG_ABS(x);
    if(along<-.4452f*across)return 0.f;   // over the straight side, before -24 degrees (most of a long capsule)
    float rho=WXG_SQRT(along*along+across*across);
    if(rho<.15f*r)return 0.f;
    float phi=WXG_ATAN2(along,across);
    float f=WXGOClamp((rho-.15f*r)/(.25f*r),0.f,1.f);f=f*f*(3.f-2.f*f);
    return k*f*r*WXGContinuousDeviation(phi)*(phi<0.f?WXG_COS(phi):1.f);
}
// An optical distance/normal for a capsule. The visible contour and strokes
// are Core Animation's continuous corners; FIX96: the distance follows that
// contour (WXGContinuousCorrection). The normal stays the circle's.
static inline WXGShapeSample WXGCapsuleOpticalField(float x,float y,float width,float height) {
    float r=WXG_MAX(.5f,WXG_MIN(width,height)*.5f);
    float qx=WXG_ABS(x)-(width*.5f-r),qy=WXG_ABS(y)-(height*.5f-r);
    float ox=WXG_MAX(0.f,qx),oy=WXG_MAX(0.f,qy),length=WXG_SQRT(ox*ox+oy*oy);
    WXGShapeSample out;
    out.distance=length+WXG_MIN(WXG_MAX(qx,qy),0.f)-r-WXGContinuousCorrection(x,y,width,height);
    out.nx=(x<0.f?-ox:ox)/WXG_MAX(length,.0001f);
    out.ny=(y<0.f?-oy:oy)/WXG_MAX(length,.0001f);
    return out;
}
// Multiline editors grow as continuous rounded rectangles, without stretching
// a capsule texture. A zero radius keeps the exact TEST9 capsule branch.
static inline WXGShapeSample WXGRoundedOpticalField(float x,float y,float width,float height,float radius) {
    float r=WXGOClamp(radius,.5f,WXG_MIN(width,height)*.5f);
    float qx=WXG_ABS(x)-(width*.5f-r),qy=WXG_ABS(y)-(height*.5f-r);
    float ox=WXG_MAX(0.f,qx),oy=WXG_MAX(0.f,qy),len=WXG_SQRT(ox*ox+oy*oy);
    WXGShapeSample out;
    out.distance=len+WXG_MIN(WXG_MAX(qx,qy),0.f)-r;
    if(len>.0001f){out.nx=(x<0?-ox:ox)/len;out.ny=(y<0?-oy:oy)/len;}
    else if(qx>qy){out.nx=x<0?-1.f:1.f;out.ny=0;}
    else{out.nx=0;out.ny=y<0?-1.f:1.f;}
    return out;
}
static inline float WXGSelectionGap(float requested,float height) {
    return WXGOClamp(requested,2.f,WXG_MIN(14.f,height*.3f));
}
static inline float WXGSelectionWidth(float width,float gap) { return WXG_MAX(1.f,(width-2.f*gap)/4.f); }
static inline float WXGSelectionCenter(float width,float gap,int index) {
    if(index<0) index=0;
    if(index>3) index=3;
    return gap+WXGSelectionWidth(width,gap)*(index+.5f);
}
static inline float WXGLensHeight(float barHeight,float gap,float press,float growth,float stretch) {
    (void)stretch; // Horizontal motion must not alter height or the vertical centre.
    float rest=barHeight-2.f*gap;
    return rest+(barHeight*growth-rest)*WXGOClamp(press,0.f,1.f);
}
static inline float WXGLensWidth(float slot,float barHeight,float press,float growth,float stretch) {
    float expanded=WXG_MAX(barHeight*growth,slot*1.20f);
    return (slot+(expanded-slot)*WXGOClamp(press,0.f,1.f))*(1.f+stretch);
}
enum { WXGCanvasPaddingX=40, WXGCanvasPaddingY=40 };
typedef struct {
    float barX,barY,barWidth,barHeight;
    float lensX,lensY,lensWidth,lensHeight;
    float scale,anchorX;
} WXGDockGeometry;
static inline WXGDockGeometry WXGDockLayout(float width,float height,float gap,float anchor,
                                           float press,float growth,float stretch,float barGrowth,float wrap) {
    press=WXGOClamp(press,0.f,1.f);
    WXGDockGeometry g;
    g.scale=1.f+(barGrowth-1.f)*press;
    g.barWidth=width*g.scale; g.barHeight=height*g.scale;
    g.barX=(width-g.barWidth)*.5f; g.barY=(height-g.barHeight)*.5f;
    float first=WXGSelectionCenter(width,gap,0),last=WXGSelectionCenter(width,gap,3);
    float t=WXGOClamp((anchor-first)/WXG_MAX(1.f,last-first),0.f,1.f);
    g.anchorX=first+(last-first)*t;
    g.lensWidth=WXGLensWidth(WXGSelectionWidth(width,gap),height,press,growth,stretch)*g.scale;
    g.lensHeight=WXGLensHeight(height,gap,press,growth,stretch)*g.scale;
    // Preserve equal resting gaps; at full press extend OUTSIDE the grown bar.
    // The bar's geometry in the shader has no horizontal lens magnification.
    float outside=gap*g.scale*(1.f-press)-wrap*press;
    g.lensX=g.barX+outside+t*(g.barWidth-2.f*outside-g.lensWidth);
    g.lensY=(height-g.lensHeight)*.5f;
    return g;
}
static inline float WXGFitMaterialWidth(float screenWidth,float fraction,float barGrowth,float wrap) {
    return WXG_MAX(1.f,WXG_MIN(screenWidth*fraction,(screenWidth-2.f*(wrap+4.f))/barGrowth));
}
static inline float WXGRimStrength(float nx,float ny,float fade) {
    float t=WXGOClamp((WXG_ABS(nx+ny)*.70710678f-.05f)/.60f,0.f,1.f);
    float highlight=t*t*(3.f-2.f*t);
    return 1.f-WXGOClamp(fade,0.f,1.f)*(1.f-(.015f+.985f*highlight));
}
/* FIX27: the rim with its two bright diagonals faded separately. fadeTopLeft
   and fadeBottomRight dim the top/left and bottom/right halves (0 = full);
   `fade` still dims the two side diagonals. With both new fades at 0 this is
   exactly WXGRimStrength. */
static inline float WXGRimStrengthTLBR(float nx,float ny,float fade,float fadeTopLeft,float fadeBottomRight) {
    float t=WXGOClamp((WXG_ABS(nx+ny)*.70710678f-.05f)/.60f,0.f,1.f);
    float highlight=t*t*(3.f-2.f*t);
    float side=1.f-.985f*WXGOClamp(fade,0.f,1.f);
    float diagonal=1.f-WXGOClamp(nx+ny<0.f?fadeTopLeft:fadeBottomRight,0.f,1.f);
    return side+(diagonal-side)*highlight;
}
static inline float WXGPressedBorderAlpha(float press) {
    return press<.005f?0.f:WXGOClamp(press,0.f,1.f);
}
// Constant inset over the whole inner contour; only the tiny contact band
// joins it back to the bar outside the lens. Never pinch by horizontal position.
static inline float WXGInnerInset(float barHeight,float press,float reduction,float lensDistance) {
    float full=barHeight*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(reduction,0.f,.30f);
    // FIX47: the outer border joins the inset inner border at about 45 degrees:
    // the inset grows over as many points inward from the lens edge as it is
    // deep (was a 1.25 pt step, which read as a broken bracket).
    float t=WXGOClamp(-lensDistance/WXG_MAX(1.25f,full),0.f,1.f);
    return full*t*t*(3.f-2.f*t);
}
/* FIX88: the bar seen in the lens, inset by `full`, joins the bar's edge
   outside at 45 degrees and flattens toward the full inset (1 - (1 - u)^2
   over 2 * full: slope 1 at the join, 0 at the full inset). `along` is how far
   inside the lens the nearest point of the bar's outline lies, measured
   ALONG that outline (WXGLensDepthAlongBar). WXGInnerInset measured it by the
   distance from the lens outline, whose sides are steep where the bar's edge
   crosses them: the join ran down along the lens' side, a vertical step that
   refraction turned into a flat-bottomed cap. iOS 26 enters on a slope. */
static inline float WXGInnerInsetAlong(float barHeight,float press,float reduction,float along) {
    float full=barHeight*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(reduction,0.f,.30f);
    if(!(full>0.f))return 0.f;
    float u=WXGOClamp(along/(2.f*full),0.f,1.f);
    return full*u*(2.f-u);
}
/* How far a point of the bar's outline (tangent tx, ty) lies inside the
   lens along that outline: the lens distance there over how fast it changes
   along the outline (|t . n|, the lens normal; at least .3, so a lens edge
   running alongside the bar never jumps straight to the full inset). */
static inline float WXGLensDepthAlongBar(float lensDistance,float tx,float ty,float lnx,float lny) {
    float rate=WXG_MAX(WXG_ABS(tx*lnx+ty*lny),.3f);
    return WXG_MAX(0.f,-lensDistance)/rate;
}
static inline float WXGOpticalOffset(float distance,float edgeWidth,float strength) {
    float t=WXGOClamp(-distance/WXG_MAX(edgeWidth,1.f),0.f,1.f);
    float edge=1.f-t*t*(3.f-2.f*t);
    // Exactly preserve TEST6's ordinary curve throughout its old 0..2 range.
    // Above 2, extend the amplitude instead of leaving the old .40 cap in place.
    strength=WXGOClamp(strength,0.f,20.f);
    float amplitude=WXG_MIN(.32f*strength,.40f)+.32f*WXG_MAX(0.f,strength-2.f);
    return edgeWidth*amplitude*edge*edge;
}
/* FIX113 I (WXG_LENS_CANCEL; user: an offset that cancels the refraction
   width): the lens' refraction with `cancel` (0..1) of its rim offset taken
   away. 0 is WXGOpticalOffset: the rim shows what lies edge width x
   amplitude further in, so whatever is under the rim (an icon) is skipped,
   more the wider / stronger it is. 1: no offset at the rim nor at the
   band's inner edge, the push in between (edge^2 x t: compressed at the rim
   up to 2.55x, stretched past the middle of the band), capped at 1.55 so the
   mapping never folds back (the slope stays >= 0.2): what is under the band
   stays in the band, however wide it is, at most 0.29 band widths from where
   it is. Between: a straight mix. */
static inline float WXGLensRefractionOffset(float distance,float edgeWidth,float strength,float cancel) {
    float full=WXGOpticalOffset(distance,edgeWidth,strength);
    cancel=WXGOClamp(cancel,0.f,1.f);
    if(!(cancel>0.f))return full;
    float t=WXGOClamp(-distance/WXG_MAX(edgeWidth,1.f),0.f,1.f);
    float edge=1.f-t*t*(3.f-2.f*t);
    strength=WXGOClamp(strength,0.f,20.f);
    float amplitude=WXG_MIN(.32f*strength,.40f)+.32f*WXG_MAX(0.f,strength-2.f);
    float bump=edgeWidth*WXG_MIN(amplitude,1.55f)*edge*edge*t;
    return full*(1.f-cancel)+bump*cancel;
}
static inline float WXGMaterialOpacity(float alpha,float clearMaterial,float edge,float fadeAtEdge) {
    float opacity=WXGOClamp(alpha*(1.22f-.22f*WXGOClamp(clearMaterial,0.f,1.f)),0.f,1.f);
    return opacity*(1.f-.82f*edge*edge*WXGOClamp(fadeAtEdge,0.f,1.f));
}
// Shrink the clear rim toward the outside as coverage grows. Coverage zero is
// exactly TEST8; one removes the sharp component everywhere, including d=0.
static inline float WXGBlurSharpWeight(float distance,float edgeWidth,float coverage) {
    coverage=WXGOClamp(coverage,0.f,1.f);
    if(coverage>=1.f) return 0.f;
    float width=WXG_MAX(.001f,edgeWidth*(1.f-coverage));
    float t=WXGOClamp(-distance/width,0.f,1.f);
    float edge=1.f-t*t*(3.f-2.f*t);
    return .88f*edge*edge*(1.f-coverage);
}
static inline float WXGLensRingBlurWeight(float distance,float edgeWidth,float coverage) {
    coverage=WXGOClamp(coverage,0.f,1.f);
    return coverage*(1.f-WXGBlurSharpWeight(distance,edgeWidth,coverage));
}
static inline float WXGCaptureScale(float screenScale) { return WXGOClamp(screenScale,1.f,3.f); }
typedef struct {
    int count;
    float center;
    float offsets[54];
    float weights[54];
} WXGGaussianKernel;
#ifndef __METAL_VERSION__
// Pair neighbouring Gaussian taps using bilinear filtering. This preserves a
// dense kernel; widely spaced fixed taps would recreate ghosting at large blur.
static inline WXGGaussianKernel WXGMakeGaussian(float sigma) {
    WXGGaussianKernel k={0}; k.center=1;
    if(sigma<.05f) return k;
    sigma=WXGOClamp(sigma,.05f,36.f);
    int radius=(int)ceilf(3.f*sigma); float total=1;
    for(int i=1;i<=radius;i+=2) {
        float a=expf(-.5f*(float)(i*i)/(sigma*sigma));
        float b=i+1<=radius?expf(-.5f*(float)((i+1)*(i+1))/(sigma*sigma)):0;
        float weight=a+b;
        if(weight<1e-12f) continue;
        k.offsets[k.count]=i+b/weight; k.weights[k.count]=weight; ++k.count;
        total+=2*weight;
    }
    k.center=1/total;
    for(int i=0;i<k.count;i++) k.weights[i]/=total;
    return k;
}
#endif
#endif
