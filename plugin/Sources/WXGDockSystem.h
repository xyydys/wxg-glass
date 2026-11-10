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
#define WXG_DOCK26_LENS_AMOUNT .25       /* InnerRefractionAmount 17.5 */
#endif
