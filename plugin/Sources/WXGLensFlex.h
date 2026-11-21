#ifndef WXG_LENS_FLEX_H
#define WXG_LENS_FLEX_H
#include <math.h>
/* FIX126 iOS 26 的透镜形变 (user, 11-10: ran probe 2's tab bar recorder on
   iOS 26.6 and sent four takes: "left to right the lens turns into a long
   strip, right to left it is squeezed"). Pure C: how the system's tab bar
   lens (_UILiquidLensView under a _UIFlexInteraction) changes its width and
   height while it is dragged, fitted on the takes' frame records (the lens
   layer's transform every display frame, 60 to 120 a second).

   What the records show: the scale is signed (moving right
   wider and flatter, moving left narrower and taller), but it is not a
   function of the speed: at a steady speed it all but vanishes, it builds
   while the lens gets going, and when the lens stops it swings to the
   opposite shape and dies away without ringing. A spring on the speed
   cannot do that (best fit: rms .041 of a signal of
   .060). What does, to 95 % of the variance on the fast drags (rms .018 of
   .080 in width, .028 of .118 in height):

       e      = fast - slow        two followers of the lens' position:
                                   fast: a critically damped spring, omega 18
                                   slow: an under-damped one, omega 8, ratio .5
       scaleX = clamp(1 + gainX e, .80, 1.20)
       scaleY = clamp(1 - gainY e, .72, 1.20)

   e in tab pitches (the distance between two tabs' centres; the system's
   bar: 94.17 pt, its lifted lens 123.5 x 70): gainX .311, gainY .49 (per
   point: .0033 and .0052). While the lens speeds up the fast follower runs
   ahead of the slow one (e > 0 moving right: wider, flatter); when the lens
   stops the fast one arrives first and the slow one overshoots (e < 0: the
   opposite shape), then both rest.

   Not reproduced: on a tap that sends the lens to another tab the system
   adds a pulse over the first quarter of a second (narrow and tall for a tab
   to the right, wide and flat for one to the left, about .0014 per point of
   the distance), absent on some taps; its rule was not found. The followers
   alone give such a move its later two thirds.

   Only speeds are needed: each follower keeps how far it lags the lens. */
/* FIX133 (user: "too much, above all the squeezed landing"): `squeeze`
   scales the narrow-and-tall half alone (e < 0: what a move to the right
   lands in and a move to the left starts with); 1 is the system's (its
   recorded taps: 0.95 x 1.07 after one tab, 0.72 x 1.23 at the start of
   three tabs to the left), 0 none of it. */
/* FIX135 (user, a frame of the pill come down after a move to the left:
   "it is so flat here it cannot be looked at, pressing into the icon and
   the text; THIS is the squeeze I meant"): the other half. `flatten` scales
   the wide-and-flat half alone (e > 0: what a move to the left lands in and
   a move to the right starts with). And down, the pill is never flatter
   than `restFlattest` of its height (0.82: the flattest the system's own
   pill was recorded after it had come down, three tabs to the left, 1.13 x
   0.82; the model's lower bound of 0.72 is the lifted lens', which is 70 pt
   high and has room): WXGLensFlexScaleAt. */
typedef struct { int on; double gainX,gainY,minX,maxX,minY,maxY,fast,slow,slowDamping; int symmetric; double squeeze,flatten,restFlattest; } WXGLensFlexParams;
typedef struct { double lagFast,velFast,lagSlow,velSlow; } WXGLensFlex;
static inline WXGLensFlexParams WXGLensFlexDefaults(void) {
    WXGLensFlexParams p={0,.311,.49,.80,1.20,.72,1.20,18.,8.,.5,0,1.,1.,.82};return p;
}
/* One frame: lensVelocity in points per second, pitch the distance between
   two neighbouring tabs' centres (points). */
static inline void WXGLensFlexStep(WXGLensFlex *f,double lensVelocity,double pitch,WXGLensFlexParams p,double dt) {
    if(!(dt>0.))return;
    if(dt>.064)dt=.064;
    double v=pitch>1. && isfinite(lensVelocity)?lensVelocity/pitch:0.;
    double wf=p.fast>1.?p.fast:1.,ws=p.slow>.5?p.slow:.5,zs=p.slowDamping>.05?p.slowDamping:.05;
    int count=(int)ceil(dt/(1./240.));if(count<1)count=1;
    double h=dt/count;
    for(int i=0;i<count;i++) {
        f->velFast+=(wf*wf*f->lagFast-2.*wf*f->velFast)*h;f->lagFast+=(v-f->velFast)*h;
        f->velSlow+=(ws*ws*f->lagSlow-2.*zs*ws*f->velSlow)*h;f->lagSlow+=(v-f->velSlow)*h;
    }
    if(!isfinite(f->lagFast) || !isfinite(f->velFast) || !isfinite(f->lagSlow) || !isfinite(f->velSlow)){f->lagFast=f->velFast=f->lagSlow=f->velSlow=0;}
    if(v==0. && fabs(f->lagFast)<1e-5 && fabs(f->lagSlow)<1e-5 && fabs(f->velFast)<1e-5 && fabs(f->velSlow)<1e-5){f->lagFast=f->velFast=f->lagSlow=f->velSlow=0;}
}
static inline double WXGLensFlexClamp(double x,double lo,double hi) {return x<lo?lo:x>hi?hi:x;}
/* The width and height factors now, of a lens lifted by `press` (0 down ..
   1): lifted (0.5 and more) as the model has them; down, the wide-and-flat
   half no further than where the height is restFlattest (the width with it:
   0.82 goes with 1.11), easing between the two. */
static inline void WXGLensFlexScaleAt(WXGLensFlex f,WXGLensFlexParams p,double press,double *scaleX,double *scaleY) {
    double e=f.lagSlow-f.lagFast;   /* fast - slow */
    if(p.symmetric)e=fabs(e);
    else if(e<0.)e*=p.squeeze<0.?0.:p.squeeze;
    if(e>0.) {
        e*=p.flatten<0.?0.:p.flatten;
        double flattest=WXGLensFlexClamp(p.restFlattest,.3,1.),most=p.gainY>1e-6?(1.-flattest)/p.gainY:e;
        if(e>most) {
            double lifted=press<=0.?0.:press>=.5?1.:press/.5;
            e=most+(e-most)*lifted;
        }
    }
    *scaleX=WXGLensFlexClamp(1.+p.gainX*e,p.minX,p.maxX);
    *scaleY=WXGLensFlexClamp(1.-p.gainY*e,p.minY,p.maxY);
}
/* The same of a lifted lens (the model alone). */
static inline void WXGLensFlexScale(WXGLensFlex f,WXGLensFlexParams p,double *scaleX,double *scaleY) {
    WXGLensFlexScaleAt(f,p,1.,scaleX,scaleY);
}
/* FIX134 (user, a recording of a tap three tabs to the right: "resting, its
   top and bottom are cut, as if two pieces were missing"): the deformation's
   narrow-and-tall half makes the pill up to 1.2 x as high after it has come
   down; down, the pill is drawn inside the bar, whose outline then cut its
   top and bottom off flat (the system's lens lies over its bar and is not
   cut by it). So the pill at rest is never higher than the bar less
   `margin` a side; lifted (press 0.5 and more: drawn over the bar) it is
   free, and in between it eases from the one to the other. */
static inline double WXGLensFlexRestingHeight(double height,double barHeight,double press,double margin) {
    double room=barHeight-2.*margin;
    if(!(height>room) || !(room>0.))return height;
    double lifted=press<=0.?0.:press>=.5?1.:press/.5;
    return room+(height-room)*lifted;
}
/* Still: nothing left to show (the bar may stop its frames). */
static inline int WXGLensFlexStill(WXGLensFlex f) {
    return fabs(f.lagFast)<1e-3 && fabs(f.lagSlow)<1e-3 && fabs(f.velFast)<1e-2 && fabs(f.velSlow)<1e-2;
}
/* Amplitude-adaptive deformation timing: when the user reduces the flatten
   travel (e.g., raising restFlattest from 0.82 to 0.90, or lowering flatten /
   strength), shorten the follower settling duration in proportion to travel
   distance (t ~ r^0.55 => omega ~ r^-0.55) so shorter travels stay crisp and
   never feel sluggish, while remaining bit-identical at iOS 26 defaults. */
static inline double WXGLensFlexAdaptiveSpeedup(WXGLensFlexParams p) {
    double restFlat=WXGLensFlexClamp(p.restFlattest,.3,1.);
    double restRatio=WXGLensFlexClamp((1.-restFlat)/.18,0.,1.5);
    double strength=p.gainY>1e-6?p.gainY/.49:0.;
    double fl=p.flatten<0.?0.:p.flatten,sq=p.squeeze<0.?0.:p.squeeze;
    double flatAmp=restRatio*fl*strength,sqzAmp=sq*strength;
    if(!(flatAmp>1e-4) && !(sqzAmp>1e-4))return 1.;
    double effAmp=.70*flatAmp+.30*sqzAmp;
    if(effAmp<.05)effAmp=.05;
    double sp=pow(effAmp,-.55);
    return WXGLensFlexClamp(sp,.75,2.20);
}
static inline void WXGLensFlexAdaptiveStep(WXGLensFlex *f,double lensVelocity,double pitch,WXGLensFlexParams p,double dt) {
    double sp=WXGLensFlexAdaptiveSpeedup(p);
    WXGLensFlexParams q=p;
    q.fast=(p.fast>1.?p.fast:1.)*sp;
    q.slow=(p.slow>.5?p.slow:.5)*sp;
    WXGLensFlexStep(f,lensVelocity,pitch,q,dt);
}
/* Smooth-ceiling scale: eliminates the ~150 ms flat plateau freeze created by
   hard-clamping e > most when restFlattest > 0.82, proportionally scaling the
   resting flatten curve + C-infinity tanh soft knee so the bounce peaks cleanly
   and springs back continuously with matched speed. */
static inline void WXGLensFlexAdaptiveScaleAt(WXGLensFlex f,WXGLensFlexParams p,double press,double *scaleX,double *scaleY) {
    double sp=WXGLensFlexAdaptiveSpeedup(p);
    double bwComp=pow(sp,.45);
    double gx=p.gainX*bwComp,gy=p.gainY*bwComp;
    double e=f.lagSlow-f.lagFast;
    if(p.symmetric)e=fabs(e);
    else if(e<0.)e*=p.squeeze<0.?0.:p.squeeze;
    if(e>0.) {
        e*=p.flatten<0.?0.:p.flatten;
        double flattest=WXGLensFlexClamp(p.restFlattest,.3,1.);
        double restRatio=WXGLensFlexClamp((1.-flattest)/.18,0.,1.5);
        double most=gy>1e-6?(1.-flattest)/gy:e;
        double lifted=press<=0.?0.:press>=.5?1.:press/.5;
        double eRest=0.;
        if(most>1e-6) {
            double eScaled=e*(restRatio<1.?restRatio:1.);
            double knee=.75*most;
            if(eScaled<=knee)eRest=eScaled;
            else {
                double span=most-knee;
                eRest=knee+span*tanh((eScaled-knee)/span);
            }
        }
        double eLifted=restRatio<1.?e*(.45+.55*restRatio):e;
        e=eRest+(eLifted-eRest)*lifted;
    }
    *scaleX=WXGLensFlexClamp(1.+gx*e,p.minX,p.maxX);
    *scaleY=WXGLensFlexClamp(1.-gy*e,p.minY,p.maxY);
}
#endif
