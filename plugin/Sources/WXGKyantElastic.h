#ifndef WXG_KYANT_ELASTIC_H
#define WXG_KYANT_ELASTIC_H
#include <math.h>
/* FIX122 C (user, 11-09: "back to FIX122; only Kyant's 跟随滑动速度形变 in
   place of mine, with its parameters adjustable"). Pure C: the drag-speed
   deformation of Kyant's catalog LiquidBottomTabs (the indicator's
   layerBlock, DampedDragAnimation's velocity):

     velocity  = the lens' speed in tab ranges per second (his value is in
                 tabs; the tracker's velocity / the range), followed by
                 spring(dampingRatio .5, stiffness 300)
     v         = velocity / 10
     scaleX   /= 1 - clamp(v x .75, -.2, .2)
     scaleY   *= 1 - clamp(v x .25, -.2, .2)

   It is signed as he wrote it: moving right makes the lens wider and
   flatter, moving left narrower and taller. Adjustable here: the two
   factors (.75, .25), the cap (.2), a sensitivity on v (1 = his / 10), the
   velocity spring's damping and stiffness (.5, 300), and 左右对称 (|v|:
   wider and flatter both ways). The lens' own size, position and press are
   the dock's; only its width and height are scaled about its centre. */
typedef struct { double width,height,limit,sensitivity,damping,stiffness; int symmetric; } WXGKyantElasticParams;
typedef struct { double velocity,velocityV; } WXGKyantElastic;
static inline WXGKyantElasticParams WXGKyantElasticDefaults(void) {
    WXGKyantElasticParams p={.75,.25,.2,1,.5,300,0};return p;
}
/* Compose's spring(dampingRatio, stiffness) on a unit mass. */
static inline void WXGKyantElasticSpring(double *x,double *v,double target,double ratio,double stiffness,double dt) {
    if(!(dt>0.))return;
    if(dt>.064)dt=.064;
    if(!(stiffness>0.))stiffness=300.;
    if(!(ratio>0.))ratio=.5;
    double c=2.*ratio*sqrt(stiffness);
    int count=(int)ceil(dt/(1./240.));if(count<1)count=1;
    double h=dt/count;
    for(int i=0;i<count;i++){*v+=((target-*x)*stiffness-*v*c)*h;*x+=*v*h;}
    if(fabs(target-*x)<1e-5 && fabs(*v)<1e-5){*x=target;*v=0;}
}
/* One frame: lensVelocity in points per second, tabRange the distance
   between the first and last tab centres (points). */
static inline void WXGKyantElasticStep(WXGKyantElastic *e,double lensVelocity,double tabRange,WXGKyantElasticParams p,double dt) {
    double target=tabRange>1. && isfinite(lensVelocity)?lensVelocity/tabRange:0.;
    WXGKyantElasticSpring(&e->velocity,&e->velocityV,target,p.damping,p.stiffness,dt);
    if(!isfinite(e->velocity) || !isfinite(e->velocityV)){e->velocity=0;e->velocityV=0;}
}
static inline double WXGKyantElasticClamp(double x,double limit) {return x<-limit?-limit:x>limit?limit:x;}
/* The width and height factors for the current velocity. */
static inline void WXGKyantElasticScale(WXGKyantElastic e,WXGKyantElasticParams p,double *scaleX,double *scaleY) {
    double limit=p.limit<0.?0.:p.limit>.9?.9:p.limit;
    double v=e.velocity/10.*(p.sensitivity>0.?p.sensitivity:0.);
    if(p.symmetric)v=fabs(v);
    double a=WXGKyantElasticClamp(v*p.width,limit),b=WXGKyantElasticClamp(v*p.height,limit);
    *scaleX=1./(1.-a);*scaleY=1.-b;
}
/* Still: nothing left to show (the bar may stop its frames). */
static inline int WXGKyantElasticStill(WXGKyantElastic e) {return fabs(e.velocity)<1e-3 && fabs(e.velocityV)<1e-2;}
#endif
