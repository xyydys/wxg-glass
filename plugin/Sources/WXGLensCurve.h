#ifndef WXG_LENS_CURVE_H
#define WXG_LENS_CURVE_H
#include <math.h>
/* The glass' refraction, as iOS 26 draws it (FIX124: measured on iOS 26.6
   with the probe of probe/, on its 44 pt and 48 pt buttons, the 120 x 44
   capsule and the 140 x 90 panel; FIX126: the tab bar's lens). Pure C.

   Refraction: only within `height` of the outline. At inward depth t a
   point shows what lies amount x curve(1 - t / height) further in along the
   outline's normal, curve(x) = 1 - sqrt(1 - x^2): a quarter circle, the
   whole amount at the outline (an infinitely steep start, so the outermost
   sliver mirrors what lies deeper: the rounded glass edge), nothing at
   `height`, reached with zero slope (no visible inner edge). Outside the
   outline it is held at the outline's. The system's numbers: height a
   quarter of the glass' short side (at most 20 pt), amount 0.8 of it; the
   tab bar's lens 0.10 and 0.25 of its height (0.30 by its recording).

   Colour split (the system's buttons have none; its lens has one all round
   the outline, measured in FIX128 and found hard to read on the phone): the
   same shift d along the normal, scaled per colour by the intensity
   I = (x / halfWidth) x (y / halfHeight) (x, y from the centre): nothing
   along the two middle lines, largest toward the corners, opposite in the
   top-left / bottom-right and the top-right / bottom-left quarters. A
   channel shows the sample at red +3/7, green +2/21, blue -2/3 of d x I
   (the means of seven samples along the spectrum, each channel's weights
   adding up to 1). This split, the quarter-circle form it scales and the
   three weights follow the lens() effect of the Backdrop library of
   Kyant's AndroidLiquidGlass (Apache License 2.0; THIRD_PARTY_NOTICES.md at
   the repository's root),
   from which FIX122 first took the curve before it was found, point for
   point, on the system's own glass. */
static inline float WXGLensCurveMap(float x) {
    x=x<0.f?0.f:x>1.f?1.f:x;
    return 1.f-sqrtf(1.f-x*x);
}
/* The inward shift (points) at inward depth `depth` (< 0 outside). */
static inline float WXGLensCurveOffset(float depth,float height,float amount) {
    if(!(height>0.f) || !(amount>0.f))return 0.f;
    float t=depth>0.f?depth:0.f;
    if(t>=height)return 0.f;
    return amount*WXGLensCurveMap(1.f-t/height);
}
/* FIX122 E (user: "the very thin ring it draws at the outermost edge makes
   bad jaggies; can it be turned off?"): the curve starts infinitely steep,
   so the outermost fraction of a point shows a wide strip of what lies
   further in, squeezed (the source depth t + offset changes ever faster
   toward the outline): a hair-thin ring the render server's mesh cannot
   filter. Capped: where the squeeze would pass `squeeze` (how many points
   of the picture one point shows), the curve goes on as its tangent to the
   outline (C1, no kink), so the squeeze never exceeds it; deeper the curve
   is exact. 0 = no cap.
   The squeeze is |d(t + offset)/dt| = (amount / height) g'(u) - 1 on the
   folded side, g(u) the curve, g'(u) = u / sqrt(1 - u^2), u = 1 - t /
   height; capped where (amount / height) g'(u0) = 1 + squeeze, i.e.
   u0 = c / sqrt(1 + c^2) with c = (1 + squeeze) height / amount. */
static inline float WXGLensCurveOffsetCapped(float depth,float height,float amount,float squeeze) {
    if(!(squeeze>0.f))return WXGLensCurveOffset(depth,height,amount);
    if(!(height>0.f) || !(amount>0.f))return 0.f;
    float t=depth>0.f?depth:0.f;
    if(t>=height)return 0.f;
    float u=1.f-t/height,c=(1.f+squeeze)*height/amount,u0=c/sqrtf(1.f+c*c);
    if(u<=u0)return amount*WXGLensCurveMap(u);
    float g0=1.f-sqrtf(1.f-u0*u0),slope=u0/sqrtf(1.f-u0*u0);
    return amount*(g0+slope*(u-u0));
}
/* A channel's mean share of d x I: +1 red, 0 green, -1 blue. */
static inline float WXGLensSplitWeight(float channel) {
    return channel>.5f?3.f/7.f:channel<-.5f?-2.f/3.f:2.f/21.f;
}
/* The largest |weight| (blue): how far a channel can differ from green. */
#define WXG_LENS_SPLIT_SPAN (2.f/3.f)
static inline float WXGLensSplitIntensity(float x,float y,float halfWidth,float halfHeight) {
    if(!(halfWidth>0.f) || !(halfHeight>0.f))return 0.f;
    float v=(x/halfWidth)*(y/halfHeight);
    return v<-1.f?-1.f:v>1.f?1.f:v;
}
#endif
