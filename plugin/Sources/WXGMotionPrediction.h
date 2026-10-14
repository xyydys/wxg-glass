#ifndef WXG_MOTION_PREDICTION_H
#define WXG_MOTION_PREDICTION_H
#include <math.h>
/* FIX17: display-time prediction for the background read.

   The glass reads the scene at time t, but its drawable is seen at a later
   display time D. Two kinds of motion reach the screen differently:

   - Core Animation animations (UIKit push/pop, keyboard, cross-fades) are
     evaluated by the render server at each display time. At D the screen
     shows the animation at D, so the read must be advanced by D - t.
     The model value is the animation's end state: the advance is only ever
     toward it and never past it.
   - Model-driven motion (scroll offsets, display-link-driven layout) is shown
     when its commit is displayed (about the frame's target time). Only the
     difference between the glass display and that time is compensated,
     and never by more than one observed step.

   A sample stores the PRESENTED and the MODEL translation of a view in the
   scene at the time it was evaluated. When presented == model at both ends
   the motion is model-driven; otherwise it is an animation in flight. */
typedef struct { double px,py,mx,my,t; } WXGMotionSample;
typedef struct { WXGMotionSample last,previous,older; int count; } WXGMotionTrack;

/* Re-evaluations inside one display frame (< 4 ms apart) keep the older
   sample as velocity base, so a second read in the same frame does not
   erase the measured velocity. */
static inline WXGMotionSample WXGMotionBase(WXGMotionTrack k,double t) {
    return (k.count>1 && t-k.last.t<.004)?k.previous:k.last;
}
static inline WXGMotionTrack WXGMotionRecord(WXGMotionTrack k,WXGMotionSample s) {
    if(k.count<1){k.last=s;k.count=1;return k;}
    if(s.t-k.last.t>=.004){k.older=k.previous;k.previous=k.last;k.last=s;k.count=k.count<3?k.count+1:3;}
    else k.last=s;
    return k;
}
/* The sample before the velocity base (for acceleration), or the base itself. */
static inline WXGMotionSample WXGMotionOlder(WXGMotionTrack k,double t) {
    if(k.count>1 && t-k.last.t<.004)return k.count>2?k.older:k.previous;
    return k.count>1?k.previous:k.last;
}
static inline double WXGMotionToward(double step,double remaining) {
    if(!(step*remaining>0))return 0;
    return fabs(step)<fabs(remaining)?step:remaining;
}
static inline double WXGMotionClamp(double v,double lo,double hi) {return v<lo?lo:v>hi?hi:v;}
/* FIX18: displacement over `lead` from two consecutive average velocities.
   v0 is the average over the interval ending `dt0` earlier, v1 the average
   over the latest interval `dt1`. UIKit transitions, keyboard curves and
   scroll deceleration all slow down exponentially-like at the end; a linear
   extrapolation there runs ahead and, clamped at the end state, makes the
   glass arrive early (the background inside appears to move less than the
   real one). A slowing component therefore uses exponential decay with the
   observed rate. A speeding-up component stays linear: an acceleration term
   overshoots at the velocity peak of spring curves (tested: worst case grew
   from 70 to 94-153 pt), so it is deliberately not used. */
static inline double WXGMotionDisplacement(double v0,double v1,double dt0,double dt1,double lead) {
    if(!(lead>0) || !isfinite(v1))return 0;
    if(!(dt0>0) || !isfinite(v0) || v0*v1<=0 || fabs(v0)<2)return v1*lead;
    double span=.5*(dt0+dt1);
    if(fabs(v1)<fabs(v0)) {
        double rate=log(fabs(v0)/fabs(v1))/span;
        if(rate<1e-6)return v1*lead;
        double now=v1*exp(-rate*.5*dt1);
        return now*(1-exp(-rate*lead))/rate;
    }
    return v1*lead;
}
/* Returns the displacement (points) to add to the presented translation. */
/* `o` is the sample before `a` (or `a` itself when unknown). */
static inline int WXGMotionPredict2(WXGMotionSample o,WXGMotionSample a,WXGMotionSample b,double leadAnimation,double leadModel,
                                    int interactive,double maxShift,double *dx,double *dy) {
    *dx=*dy=0;
    double dt=b.t-a.t;
    if(!(dt>=.002 && dt<=.15))return 0;
    if(!isfinite(a.px+a.py+a.mx+a.my+b.px+b.py+b.mx+b.my))return 0;
    double dt0=a.t-o.t;int history=dt0>=.002 && dt0<=.15 && isfinite(o.px+o.py);
    double lm=WXGMotionClamp(isfinite(leadModel)?leadModel:0,0,fmin(dt,.05));
    double la=interactive?lm:WXGMotionClamp(isfinite(leadAnimation)?leadAnimation:0,0,.10);
    double vx=(b.px-a.px)/dt,vy=(b.py-a.py)/dt,ex=0,ey=0;
    double ux=history?(a.px-o.px)/dt0:vx,uy=history?(a.py-o.py)/dt0:vy;
    int modelX=fabs(a.px-a.mx)<.5 && fabs(b.px-b.mx)<.5;
    int modelY=fabs(a.py-a.my)<.5 && fabs(b.py-b.my)<.5;
    if(fabs(vx)>=2) {
        if(modelX)ex=WXGMotionDisplacement(WXGMotionClamp(ux,-6000,6000),WXGMotionClamp(vx,-6000,6000),history?dt0:0,dt,lm);
        else ex=WXGMotionToward(WXGMotionDisplacement(ux,vx,history?dt0:0,dt,la),b.mx-b.px);
    }
    if(fabs(vy)>=2) {
        if(modelY)ey=WXGMotionDisplacement(WXGMotionClamp(uy,-6000,6000),WXGMotionClamp(vy,-6000,6000),history?dt0:0,dt,lm);
        else ey=WXGMotionToward(WXGMotionDisplacement(uy,vy,history?dt0:0,dt,la),b.my-b.py);
    }
    *dx=WXGMotionClamp(ex,-maxShift,maxShift);*dy=WXGMotionClamp(ey,-maxShift,maxShift);
    return *dx!=0 || *dy!=0;
}
/* FIX17 two-sample form, kept for the existing tests (no acceleration term). */
static inline int WXGMotionPredict(WXGMotionSample a,WXGMotionSample b,double leadAnimation,double leadModel,
                                   int interactive,double maxShift,double *dx,double *dy) {
    return WXGMotionPredict2(a,a,b,leadAnimation,leadModel,interactive,maxShift,dx,dy);
}
#endif
