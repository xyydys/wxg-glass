#ifndef WXG_LENS_OPTICS_H
#define WXG_LENS_OPTICS_H
#include "WXGOptics.h"
typedef struct {float refraction,dispersion,edgeWidth;} WXGOpticalValues;
// Resting selection belongs to the ordinary bar. Its pressed optical profile
// fades in using the original demo press spring, independently of motion strain.
static inline WXGOpticalValues WXGPressedOptics(WXGOpticalValues body,WXGOpticalValues lens,float press) {
    float p=WXGOClamp(press,0,1);
    return (WXGOpticalValues){body.refraction+(lens.refraction-body.refraction)*p,
        body.dispersion+(lens.dispersion-body.dispersion)*p,
        body.edgeWidth+(lens.edgeWidth-body.edgeWidth)*p};
}
// Selection is a resting-state cue, not another layer inside the raised lens.
// Withdraw it as the lens rises, keep it absent while it is lifted (dragging),
// bring it back as it settles. Smooth endpoints avoid a flash.
// FIX98 (user: the pill went clear at once and coloured at once): over press
// 0.05..0.45 (was 0..0.12, a frame or two of the press spring), so the
// touch-down bump (0.10) keeps it (0.96) and the colour follows the lift and
// the release. A tap's scripted lens has its own colour track (WXGDockScript.h).
static inline float WXGRestingSelectionWeight(float press) {
    float p=WXGOClamp((press-.05f)/.40f,0.f,1.f);
    return 1.f-p*p*(3.f-2.f*p);
}
/* FIX21: iOS 26-style lens rim. The refraction band keeps the full width
   where the lens normal is horizontal (its rounded ends) and narrows to
   `topRatio` of it where the normal is vertical (the parts that stand above
   and below the bar). pow(|nx|, sharpness): leaving an end the band narrows
   quickly, then approaches the top/bottom width slowly. topRatio 1 returns
   exactly `side`, i.e. the previous isotropic lens. */
/* FIX47: the FIX21 rule (widest at the lens ends, topRatio above/below), but a
   lens end that has passed the bar's end narrows quickly to the top/bottom
   width (barDistance < 0 inside the bar, 4 pt blend): at the dock's ends only
   the inset bar and a narrow rim remain. Inside the bar it equals the FIX21 rule. */
static inline float WXGLensEdgeWidthAtBar(float nx,float ny,float side,float topRatio,float sharpness,float barDistance) {
    float r=WXGOClamp(topRatio,.05f,1.f);
    if(r>=1.f)return side;
    float len=WXG_SQRT(nx*nx+ny*ny);
    float h=len>1e-4f?WXG_ABS(nx)/len:1.f;
    float t=WXGOClamp((barDistance+4.f)/8.f,0.f,1.f);t=t*t*(3.f-2.f*t);
    return side*(r+(1.f-r)*WXG_POW(h,WXGOClamp(sharpness,.5f,8.f))*(1.f-t));
}
static inline float WXGLensEdgeWidth(float nx,float ny,float side,float topRatio,float sharpness) {
    float r=WXGOClamp(topRatio,.05f,1.f);
    if(r>=1.f)return side;
    float len=WXG_SQRT(nx*nx+ny*ny);
    float h=len>1e-4f?WXG_ABS(nx)/len:1.f;
    return side*(r+(1.f-r)*WXG_POW(h,WXGOClamp(sharpness,.5f,8.f)));
}

/* ---- FIX57: the dock's ends ------------------------------------------------
   With FIX47's band a lens resting on the first / last tab still pulled the
   bar's end cap into its rim: points just inside the bar's end kept the wide
   end band, so the inner bar stuck to the lens edge. Now, as a lens end
   reaches the bar's end, the band that bends the bar seen through the lens
   (and the page behind it) relaxes toward the top / bottom width: from
   WXG_END_START pt before the bar's end to WXG_END_DONE pt past it, smoothly.
   Everywhere else it is FIX47's band; icons and titles always keep FIX47's. */
#define WXG_END_START 10.f
#define WXG_END_DONE 2.f
/* How far one end (side < 0 left, else right) has relaxed, 0..1, from the
   bar's and the lens's horizontal extent (same space). */
static inline float WXGLensEndReach(float barX0,float barX1,float lensX0,float lensX1,int side) {
    float over=side<0?barX0-lensX0:lensX1-barX1;
    float t=WXGOClamp((over+WXG_END_START)/(WXG_END_START+WXG_END_DONE),0.f,1.f);
    return t*t*(3.f-2.f*t);
}
/* `width` with each half of the lens pulled toward the top / bottom width by
   its end's reach (0..1). Both 0 returns `width` exactly. */
static inline float WXGLensEndRelax(float width,float nx,float side,float topRatio,float reachLeft,float reachRight) {
    float c=WXGOClamp(nx<0.f?reachLeft:reachRight,0.f,1.f);
    if(c<=0.f)return width;
    float top=side*WXGOClamp(topRatio,.05f,1.f);
    return top+(width-top)*(1.f-c);
}
/* ---- FIX94: the bar seen through the lens follows the lens' rim ------------
   With the refraction band narrowed above and below (lensTopEdgeRatio < 1),
   the lens' flat middle showed the bar as it is: the lens stands above and
   below the bar (plus the inset), so a dark slot appeared at the top and the
   bottom, thickest in the middle and gone at the rounded corners, the
   opposite of the band. Now the bar is magnified vertically about its centre,
   column by column, so that its (inset) top / bottom edge comes to `margin`
   times the band's width (at the rim above that column) from the lens' rim:
   the dark border is then thinnest at the top / bottom and grows toward the
   corners, the bar inside the lens nearly an ellipse. Where the rim lies
   inside the bar (the lens' ends, the joins) the scale is 1 (smoothly), so
   the 45-degree join stays. A bar end cap inside the lens takes the scale of
   its straight part's end (x clamped), so it detaches as before (vertically
   stretched by that scale), but never more than its own column allows: with
   the lens' end over the cap (dragging onto / off an end tab) the cap's edge
   stays margin x band inside the rim there too. Everything in the bar's
   screen space (scaled by the press); the lens a capsule centred lx, ly.
   margin <= 0: off (returns 1). */
/* The scale that puts the bar's top edge at column x (the outline there hb
   above the bar's centre by, its tangent tx, ty) margin x band inside the
   lens' rim; 0 outside the lens. */
static inline float WXGLensBarColumnZoom(float x,float hb,float halfH,float tx,float ty,float by,float lx,float ly,float lw,float lh,
                                         float insetHeight,float press,float pinch,float side,float ratio,float sharpness,float margin) {
    float r=WXG_MIN(lw,lh)*.5f,a=WXG_MAX(0.f,lw*.5f-r),ah=WXG_MAX(0.f,lh*.5f-r);
    float dx=WXG_ABS(x-lx)-a;
    if(dx>=r)return 0.f;
    float lhalf=ah+r,nx=0.f,ny=1.f;
    if(dx>0.f){float c=WXG_SQRT(WXG_MAX(0.f,r*r-dx*dx));lhalf=ah+c;nx=dx/r;ny=c/r;}
    float e=margin*WXGLensEdgeWidth(nx,ny,side,ratio,sharpness);
    // The inset (FIX88, 45 degrees from the join) at the bar's top edge here,
    // its vertical part (the outline's normal is hb / halfH upward).
    WXGShapeSample l=WXGCapsuleOpticalField(x-lx,by-hb-ly,lw,lh);
    float inset=WXGInnerInsetAlong(insetHeight,press,pinch,WXGLensDepthAlongBar(l.distance,tx,ty,l.nx,l.ny));
    return (lhalf-(by-ly>0.f?by-ly:ly-by)-e)/WXG_MAX(hb-inset*hb/WXG_MAX(halfH,.5f),1.f);
}
static inline float WXGLensBarZoom(float x,float bx,float by,float bw,float bh,float lx,float ly,float lw,float lh,
                                   float insetHeight,float press,float pinch,float side,float ratio,float sharpness,float margin) {
    if(!(margin>0.f) || !(bw>1.f) || !(bh>1.f) || !(lw>1.f) || !(lh>1.f))return 1.f;
    float halfH=bh*.5f,straight=WXG_MAX(0.f,bw*.5f-halfH),over=WXG_ABS(x-bx)-straight;
    float xc=bx+WXGOClamp(x-bx,-straight,straight);
    float z=WXGLensBarColumnZoom(xc,halfH,halfH,1.f,0.f,by,lx,ly,lw,lh,insetHeight,press,pinch,side,ratio,sharpness,margin);
    if(over>0.f) {   // over an end cap: also what this column itself allows
        float c=WXG_MIN(over,halfH),hb=WXG_SQRT(WXG_MAX(0.f,halfH*halfH-c*c)),s=x<bx?-1.f:1.f;
        z=WXG_MIN(z,WXGLensBarColumnZoom(x,hb,halfH,hb/halfH,s*c/halfH,by,lx,ly,lw,lh,insetHeight,press,pinch,side,ratio,sharpness,margin));
    }
    if(!(z>0.f))return 1.f;
    float k=(z-1.f)/.04f;   // a smooth max(1, z)
    return k>20.f?z:1.f+.04f*WXG_LOG(1.f+WXG_EXP(k));
}
/* ---- FIX113 M (WXG_LENS_FLAT): the bar in the lens, small and flat ---------
   User: take away the slanted line that joins the inner outline to the outer
   one; cut it off from the magnified outside, small and flat inside. The bar
   seen through the dock's lens is then not bent by the lens' refraction and
   is inset by its full amount everywhere (no FIX47 / FIX88 45-degree join to
   the bar outside): where it meets the lens' rim it just ends there, a step.
   The plugin asks for it with |extra.w| = WXG_LENS_FLAT (the sign is still
   FIX113 H's direction). Older shaders read +WXG_LENS_FLAT as FIX94's
   margin, which that far from the rim leaves the bar unbent (only the join's
   slope stays), and -WXG_LENS_FLAT as outward. */
#define WXG_LENS_FLAT 1000.f
static inline int WXGLensFlatCode(float w) {return WXG_ABS(w)>=WXG_LENS_FLAT*.5f;}
static inline float WXGLensFullInset(float barHeight,float press,float reduction) {
    return WXGInnerInsetAlong(barHeight,press,reduction,1e6f);
}
#endif
