#ifndef WXG_DOCK_SYSTEM_H
#define WXG_DOCK_SYSTEM_H
#include "WXGOptics.h"
#include <math.h>
/* FIX127 (user: "wire the table's system values into the dock too, the whole
   thing replaced, so I can try it"): what the dock's own layout and motion
   could not express of iOS 26's tab bar, as measured with probe 2 on
   iOS 26.6 (an iPhone 440 pt wide, four tabs; FIX126 in the handoff). Pure C,
   and with every new value at 0 exactly the dock as it was (the callers
   then call the old functions themselves; the tests compare bit for bit).

   The system's bar: a 398 x 62 platter, the selection 4 pt inside it. Its
   four cells are 107.5 pt wide, 10 pt wider than a quarter of the inside
   (390 / 4 = 97.5): they overlap, the first and the last still 4 pt from the
   ends, so the tabs sit 94.17 pt apart instead of 97.5 and the resting pill
   is one cell, 107.5 x 54. Lifted, the lens is 16 pt wider and taller
   (123.5 x 70), whatever the cell: not the dock's "at least 1.2 cells". */

/* One tab's cell: a quarter of the inside plus `extra` (>= 0, at most half
   a quarter). */
static inline float WXGDockCellWidth(float width,float gap,float extra) {
    float slot=WXGSelectionWidth(width,gap);
    if(!(extra>0.f))return slot;
    return slot+WXG_MIN(extra,slot*.5f);
}
/* Its centre: the first and the last cell `gap` from the ends, the others
   evenly between. */
static inline float WXGDockCellCenter(float width,float gap,float extra,int index) {
    if(!(extra>0.f))return WXGSelectionCenter(width,gap,index);
    if(index<0)index=0;
    if(index>3)index=3;
    float cell=WXGDockCellWidth(width,gap,extra),first=gap+cell*.5f,last=width-gap-cell*.5f;
    return first+(last-first)*(float)index/3.f;
}
/* The distance between two tabs. */
static inline float WXGDockCellPitch(float width,float gap,float extra) {
    return (WXGDockCellCenter(width,gap,extra,3)-WXGDockCellCenter(width,gap,extra,0))/3.f;
}
/* The lifted lens' width: the dock's own rule (liftWidth 0), or its cell plus
   `liftWidth` points at full press. */
static inline float WXGDockCellLensWidth(float cell,float barHeight,float press,float growth,float stretch,float liftWidth) {
    if(!(liftWidth>0.f))return WXGLensWidth(cell,barHeight,press,growth,stretch);
    return (cell+liftWidth*WXGOClamp(press,0.f,1.f))*(1.f+stretch);
}
/* WXGDockLayout with the cells above. cellExtra 0 and liftWidth 0: the
   same numbers as WXGDockLayout. */
static inline WXGDockGeometry WXGDockLayoutCells(float width,float height,float gap,float anchor,float press,float growth,float stretch,
                                                float barGrowth,float wrap,float cellExtra,float liftWidth) {
    if(!(cellExtra>0.f) && !(liftWidth>0.f))return WXGDockLayout(width,height,gap,anchor,press,growth,stretch,barGrowth,wrap);
    press=WXGOClamp(press,0.f,1.f);
    WXGDockGeometry g;
    g.scale=1.f+(barGrowth-1.f)*press;
    g.barWidth=width*g.scale; g.barHeight=height*g.scale;
    g.barX=(width-g.barWidth)*.5f; g.barY=(height-g.barHeight)*.5f;
    float first=WXGDockCellCenter(width,gap,cellExtra,0),last=WXGDockCellCenter(width,gap,cellExtra,3);
    float t=WXGOClamp((anchor-first)/WXG_MAX(1.f,last-first),0.f,1.f);
    g.anchorX=first+(last-first)*t;
    g.lensWidth=WXGDockCellLensWidth(WXGDockCellWidth(width,gap,cellExtra),height,press,growth,stretch,liftWidth)*g.scale;
    g.lensHeight=WXGLensHeight(height,gap,press,growth,stretch)*g.scale;
    float outside=gap*g.scale*(1.f-press)-wrap*press;
    g.lensX=g.barX+outside+t*(g.barWidth-2.f*outside-g.lensWidth);
    g.lensY=(height-g.lensHeight)*.5f;
    return g;
}

/* The system's position spring (the lens going to another tab, by a tap or
   set by the app: the same on every recorded move): response 0.4 s (its
   natural frequency 2 pi / 0.4 = 15.7 rad/s), damping ratio 0.86: it starts
   at once, arrives softly and passes the tab by 0.5%.
   The unit step response at `time` (0 before 0). */
static inline double WXGDockSpringOmega(double response) {
    return 6.283185307179586/(response>.05?response:.05);
}
static inline double WXGDockSpringStep(double time,double response,double damping) {
    if(!(time>0))return 0;
    double w=WXGDockSpringOmega(response),z=damping<.05?.05:damping;
    if(fabs(z-1)<1e-4)return 1-exp(-w*time)*(1+w*time);
    if(z<1) {
        double wd=w*sqrt(1-z*z);
        return 1-exp(-z*w*time)*(cos(wd*time)+z*w/wd*sin(wd*time));
    }
    double s=sqrt(z*z-1),r1=-w*(z-s),r2=-w*(z+s);
    return 1-(r2*exp(r1*time)-r1*exp(r2*time))/(r2-r1);
}
/* How long a scripted move on that spring lasts: to its first peak (where
   it stands still, 0.5% past the tab at 0.86), so the move ends at rest; a
   spring that never passes (damping >= 1, or nearly) until 0.1% is left. At
   most 1.2 s. */
static inline double WXGDockSpringDuration(double response,double damping) {
    double w=WXGDockSpringOmega(response),z=damping<.05?.05:damping,settle=6.9/(z*w);
    if(z>=1)settle=6.9/(w*(z-sqrt(z*z-1)));
    double t=settle;
    if(z<.999) {
        double peak=3.141592653589793/(w*sqrt(1-z*z));
        if(peak<t)t=peak;
    }
    return t>1.2?1.2:t;
}
/* The move's progress (0..1) at the share u (0..1) of that duration: the
   step response, scaled so that it is exactly 1 at the end. */
static inline double WXGDockSpringEase(double u,double response,double damping) {
    if(!(u>0))return 0;
    if(u>=1)return 1;
    double T=WXGDockSpringDuration(response,damping),end=WXGDockSpringStep(T,response,damping);
    if(!(end>1e-6))return u;
    return WXGDockSpringStep(u*T,response,damping)/end;
}
/* The dock's frame-by-frame spring (WXGSpring: stiffness, damping, mass 1)
   with that response and damping ratio. */
static inline void WXGDockSpringConstants(double response,double damping,double *stiffness,double *friction) {
    double w=WXGDockSpringOmega(response);
    if(stiffness)*stiffness=w*w;
    if(friction)*friction=2*(damping<.05?.05:damping)*w;
}

/* What probe 2 measured (points, at any bar width: the system's own numbers
   on a 440 pt wide phone; the bar's width is the screen less 21 pt a side). */
#define WXG_DOCK26_SIDE_MARGIN 21.
#define WXG_DOCK26_HEIGHT 62.
#define WXG_DOCK26_INSET 4.
#define WXG_DOCK26_CELL_EXTRA 10.
#define WXG_DOCK26_LIFT 16.              /* the lifted lens: wider and taller by this */
#define WXG_DOCK26_BAR_GROWTH 1.0355     /* the platter while held */
#define WXG_DOCK26_END_WRAP 8.4          /* the lifted lens past the grown platter's end (8.15 pt x 1.0355) */
#define WXG_DOCK26_ZOOM 1.16             /* the selected tab's content in the lens */
#define WXG_DOCK26_HANG .18              /* lifted this long after the finger leaves */
#define WXG_DOCK26_RESPONSE .40
#define WXG_DOCK26_DAMPING .86
#define WXG_DOCK26_LENS_BAND .10         /* InnerRefractionHeight 7 on the 70 pt lens */
/* FIX129: the filter's InnerRefractionAmount is 17.5 (0.25 of the height),
   but with 0.25 the bar's edge mirrored in the lens' outer sliver shows at
   1.9 pt under the lens' top and the recording has it at 2.5 pt (the bright
   band inside the outline is that much wider); 0.30 puts it there. */
#define WXG_DOCK26_LENS_AMOUNT .30
/* FIX128 / FIX129, from the lifted lens over the probe's grid (hold
   screenshots, 3x): the bar's edge shows 3.5 pt further in than it lies
   (7.5 pt under the lens' top against 4). (The system's colour split was
   measured and tried there too, all round the outline and soft: the user
   found it hard to read on the phone and it is gone again; FIX130.) */
/* FIX129: 0.12, by the softened picture: the bar's edge then reads 7.6 pt
   under the lens' top on screen, as recorded (0.113 by the edge alone). */
#define WXG_DOCK26_PINCH .12
#define WXG_DOCK26_LENS_RIM_CURVE .8     /* the lens' highlight rim: curvature 0.8 (buttons 0.7) */
/* FIX131: the bar's own glass, from twelve screenshots of the resting bar
   (six backdrops, light and dark; 2.7 px / pt) and two recordings of taps.
   Its refraction is the buttons' law (fitted: a band of 0.248 and a depth of
   0.79 of its 62 pt, rms 0.08 pt, against 0.25 and 0.8) and so is its blur
   (sigma 3.15 pt from the stripes' harmonics; the law gives 3.03 at 62 pt).
   Dark, its face is the buttons' too (black 19, slate 41 against 18 and 42).
   Light it is a little clearer: slate (luma 61) shows as 174 and white as
   254, a white veil of 0.585 with nothing added (the buttons: 0.65, -0.03).
   Its shadow is much fainter than a button's: 4.3 % under it and 1.6 % above
   on white (0.065 of the shape blurred with sigma 15 pt, 8 pt down). */
#define WXG_DOCK26_BODY_VEIL .585
#define WXG_DOCK26_BODY_BRIGHTNESS 0.
#define WXG_DOCK26_SHADOW .065
#define WXG_DOCK26_SHADOW_BLUR 15.
/* The resting selection: 33 levels lighter than the face in dark (white at
   0.14), 18 darker on white (black at 0.07). */
#define WXG_DOCK26_PILL_LIGHT .07
#define WXG_DOCK26_PILL_DARK .14
/* The light under a finger (_UIFlexInteraction's two glows, in the bar's own
   outline): the whole bar a little brighter (a white layer at up to 0.81
   through a colour matrix adding 0.05: about +0.04) and a soft spot under the
   finger, a 93 pt disc blurred by half its size, which follows the finger;
   it multiplies what is under it (x 2.4 at its centre in dark, x 1.2 in
   light: on WeChat's pages about a white of 0.15). Both come in over about
   0.1 s; at the release the spot grows to 4 x and both fade in about 0.45 s. */
#define WXG_DOCK26_GLOW_SPOT .15
#define WXG_DOCK26_GLOW_BAR .04
#define WXG_DOCK26_GLOW_DISC 93.
#define WXG_DOCK26_GLOW_GROW 4.
#define WXG_DOCK_GLOW_STOPS 9
/* The spot's alpha by distance from its centre, at k / 8 of its reach (the
   disc's diameter): a disc of that diameter blurred with a Gaussian of a
   quarter of it (a layer shadow of radius = the disc's). */
static inline float WXGDockGlowProfile(int k) {
    static const float v[WXG_DOCK_GLOW_STOPS]={.864f,.834f,.733f,.589f,.404f,.233f,.119f,.047f,0.f};
    return v[k<0?0:(k>=WXG_DOCK_GLOW_STOPS?WXG_DOCK_GLOW_STOPS-1:k)];
}
#endif
