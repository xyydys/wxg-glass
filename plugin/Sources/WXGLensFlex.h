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
typedef struct { int on; double gainX,gainY,minX,maxX,minY,maxY,fast,slow,slowDamping; int symmetric; double squeeze; } WXGLensFlexParams;
typedef struct { double lagFast,velFast,lagSlow,velSlow; } WXGLensFlex;
static inline WXGLensFlexParams WXGLensFlexDefaults(void) {
    WXGLensFlexParams p={0,.311,.49,.80,1.20,.72,1.20,18.,8.,.5,0,1.};return p;
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
/* The width and height factors now. */
static inline void WXGLensFlexScale(WXGLensFlex f,WXGLensFlexParams p,double *scaleX,double *scaleY) {
    double e=f.lagSlow-f.lagFast;   /* fast - slow */
    if(p.symmetric)e=fabs(e);
    else if(e<0.)e*=p.squeeze<0.?0.:p.squeeze;
    *scaleX=WXGLensFlexClamp(1.+p.gainX*e,p.minX,p.maxX);
    *scaleY=WXGLensFlexClamp(1.-p.gainY*e,p.minY,p.maxY);
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
#endif
