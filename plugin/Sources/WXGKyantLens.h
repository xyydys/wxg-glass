#ifndef WXG_KYANT_LENS_H
#define WXG_KYANT_LENS_H
#include <math.h>
/* FIX122 Kyant 透镜模式 (user, 11-09: "use his way for a new dock lens mode;
   my lens' refraction inside and the colour split in the hollow strips above
   and below are wrong however I set it"). Pure C, the lens() effect of
   Kyant's AndroidLiquidGlass / Backdrop (RoundedRectRefraction(WithDispersion)
   ShaderString in backdrop/.../internal/Shaders.kt) as its catalog's bottom
   tabs use it on the pressed indicator: lens(10dp x press, 14dp x press,
   chromaticAberration = true) on a 56 dp tall capsule.

   Refraction: only within `height` of the outline. At inward depth t the
   pixel shows what lies amount x circleMap(1 - t / height) further in along
   the outline's normal, circleMap(x) = 1 - sqrt(1 - x^2): a quarter circle,
   the whole amount at the outline (an infinitely steep start, so the
   outermost sliver mirrors what lies deeper: the rounded glass edge),
   nothing at `height`, reached with zero slope (no visible inner edge).
   Outside the outline it is held at the outline's (the shader's min(sd, 0)).

   Colour split: the same shift d along the normal, scaled per colour by the
   intensity I = (x / halfWidth) x (y / halfHeight) (x, y from the centre):
   0 along the two middle lines (the top's and bottom's middle, the two ends'
   middle), largest toward the corners, opposite in the top-left /
   bottom-right and the top-right / bottom-left quarters. The shader takes 7
   samples (red, orange, yellow, green, cyan, blue, purple at +1, +2/3, +1/3,
   0, -1/3, -2/3, -1 times d x I) and sums them per channel; each channel's
   weights add up to 1, so a channel shows on average the sample at
   red +3/7, green +2/21, blue -2/3 of d x I (WXGKyantChannelWeight). The
   render server has three channel layers, so each takes its channel's mean
   offset (the 7-tap smear within a channel is not reproduced). */
static inline float WXGKyantCircleMap(float x) {
    x=x<0.f?0.f:x>1.f?1.f:x;
    return 1.f-sqrtf(1.f-x*x);
}
/* The inward shift (points) at inward depth `depth` (< 0 outside). */
static inline float WXGKyantOffset(float depth,float height,float amount) {
    if(!(height>0.f) || !(amount>0.f))return 0.f;
    float t=depth>0.f?depth:0.f;
    if(t>=height)return 0.f;
    return amount*WXGKyantCircleMap(1.f-t/height);
}
/* A channel's mean share of d x I: +1 red, 0 green, -1 blue. */
static inline float WXGKyantChannelWeight(float channel) {
    return channel>.5f?3.f/7.f:channel<-.5f?-2.f/3.f:2.f/21.f;
}
/* The largest |weight| (blue): how far a channel can differ from green. */
#define WXG_KYANT_CHANNEL_SPAN (2.f/3.f)
static inline float WXGKyantDispersionIntensity(float x,float y,float halfWidth,float halfHeight) {
    if(!(halfWidth>0.f) || !(halfHeight>0.f))return 0.f;
    float v=(x/halfWidth)*(y/halfHeight);
    return v<-1.f?-1.f:v>1.f?1.f:v;
}
/* The catalog's indicator: 10 dp and 14 dp on its 56 dp height. The plugin
   takes these shares of the lens' short side (scaled as the lens grows, as
   the catalog's layer scale scales its effect), times the press. */
#define WXG_KYANT_DEFAULT_HEIGHT (10.f/56.f)
#define WXG_KYANT_DEFAULT_AMOUNT (14.f/56.f)
#endif
