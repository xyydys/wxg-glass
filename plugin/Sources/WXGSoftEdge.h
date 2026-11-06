#ifndef WXG_SOFT_EDGE_H
#define WXG_SOFT_EDGE_H
#include "WXGOptics.h"
/* FIX114 I 边界过渡 (user: the original refraction is fine, only where it
   stops is too obvious: the refracting ring parts from the glass inside it;
   widening it only turns it to streaks; on iOS 26 it fades in).

   TEST9's shift (WXGOpticalOffset, edge width x amplitude x edge^2) is flat
   at the outline and steepest a third into the band. Past strength ~2.3 it
   turns back there: the band shows a mirrored copy of what lies deeper (which
   shows again, upright, inside), ending in a crease. That ring and its crease
   are the border the user sees.

   The soft shift: rim x (1 - d / band)^2. Steepest at the outline, easing to
   nothing at the band's inner end with zero slope, so nothing marks where it
   stops, and it never turns back. The rim keeps TEST9's (edge width x
   amplitude) where it can: the band reaches as far in as that needs (rim /
   0.3, never less than the edge width), within the shape (half its short
   side; a rounded rectangle's corner radius, past which its field's normals
   meet), and the rim is at most 0.3 x the band, so the picture at the outline
   is magnified at most 2.5x (slope >= 0.4): a wide band never streaks.

   边界过渡 t mixes the two shifts: 0 is TEST9's exactly, 1 the soft one.

   FIX114 J (user: more to adjust): the soft shift's shape, each zero = FIX114
   I's. stretch: the most the outline's picture is magnified (1.05..8; 2.5);
   power: rim x (1 - d / band)^power (1.5..4; 2): larger keeps the bending
   near the outline, smaller spreads it inward; width: the band (pt; 0 =
   automatic as above). The rim's share of the band is then
   (1 - 1 / stretch) / power, so the slope at the outline is exactly
   1 / stretch and never less anywhere (power >= 1). */
#define WXG_SOFT_RIM_SHARE .3f
typedef struct { float stretch,power,width; } WXGSoftShape;
static inline float WXGSoftStretch(WXGSoftShape s) {return s.stretch>0.f?WXGOClamp(s.stretch,1.05f,8.f):2.5f;}
static inline float WXGSoftPower(WXGSoftShape s) {return s.power>0.f?WXGOClamp(s.power,1.5f,4.f):2.f;}
static inline float WXGSoftShare(WXGSoftShape s) {
    if(!(s.stretch>0.f) && !(s.power>0.f))return WXG_SOFT_RIM_SHARE;   /* FIX114 I's, bit for bit */
    return (1.f-1.f/WXGSoftStretch(s))/WXGSoftPower(s);
}
/* TEST9's shift at the outline (edge width x amplitude). */
static inline float WXGSoftTarget(float edgeWidth,float strength) {return WXGOpticalOffset(0.f,edgeWidth,strength);}
static inline float WXGSoftBandShaped(float edgeWidth,float strength,float limit,WXGSoftShape s) {
    float band=s.width>0.f?s.width:WXG_MAX(edgeWidth,WXGSoftTarget(edgeWidth,strength)/WXGSoftShare(s));
    return WXG_MAX(WXG_MIN(band,limit),.5f);
}
static inline float WXGSoftRimShaped(float edgeWidth,float strength,float band,WXGSoftShape s) {
    return WXG_MIN(WXGSoftTarget(edgeWidth,strength),WXGSoftShare(s)*band);
}
/* distance: the field's (negative inside), as WXGOpticalOffset. */
static inline float WXGSoftOffsetShaped(float distance,float band,float rim,WXGSoftShape s) {
    float w=1.f-WXGOClamp(-distance/WXG_MAX(band,.5f),0.f,1.f),p=WXGSoftPower(s);
    return p==2.f?rim*w*w:rim*powf(w,p);
}
static inline float WXGTransitionOffsetShaped(float distance,float edgeWidth,float strength,float cancel,float transition,float limit,WXGSoftShape s) {
    float full=WXGLensRefractionOffset(distance,edgeWidth,strength,cancel);
    float t=WXGOClamp(transition,0.f,1.f);
    if(!(t>0.f))return full;
    float band=WXGSoftBandShaped(edgeWidth,strength,limit,s);
    return full*(1.f-t)+WXGSoftOffsetShaped(distance,band,WXGSoftRimShaped(edgeWidth,strength,band,s),s)*t;   /* at 1 exactly the soft one */
}
/* FIX114 I's (the default shape). */
static inline WXGSoftShape WXGSoftDefault(void) {WXGSoftShape s={0.f,0.f,0.f};return s;}
static inline float WXGSoftBand(float edgeWidth,float strength,float limit) {return WXGSoftBandShaped(edgeWidth,strength,limit,WXGSoftDefault());}
static inline float WXGSoftRim(float edgeWidth,float strength,float band) {return WXGSoftRimShaped(edgeWidth,strength,band,WXGSoftDefault());}
static inline float WXGSoftOffset(float distance,float band,float rim) {return WXGSoftOffsetShaped(distance,band,rim,WXGSoftDefault());}
static inline float WXGTransitionOffset(float distance,float edgeWidth,float strength,float cancel,float transition,float limit) {
    return WXGTransitionOffsetShaped(distance,edgeWidth,strength,cancel,transition,limit,WXGSoftDefault());
}
#endif
