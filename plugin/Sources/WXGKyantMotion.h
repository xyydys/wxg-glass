#ifndef WXG_KYANT_MOTION_H
#define WXG_KYANT_MOTION_H
#include <math.h>
/* FIX122 B Kyant 底栏 (user, 11-09: "the dock is perfect; now the whole dock
   his way too: how the lens moves and deforms, the bar growing, the bar
   shrinking inside the lens, his defaults; not my old settings"). Pure C:
   the motion of Kyant's catalog LiquidBottomTabs (components/
   LiquidBottomTabs.kt, utils/DampedDragAnimation.kt, utils/
   InteractiveHighlight.kt), in the dock's points.

   Compose's spring(dampingRatio, stiffness) on a unit mass is
   x'' = stiffness (target - x) - 2 ratio sqrt(stiffness) x' (WXGSpring's k
   and c). His springs:
     the lens' position (in tabs)         spring(1, 1000)
     the press                            spring(1, 1000)
     the lens' width / height scale       spring(.6, 250) / spring(.7, 250), 1 <-> 78 / 56
     the velocity (tabs per second / the tab range), as the deformation sees it
                                          spring(.5, 300)
     the bar's drift while dragged        none while dragged, spring(1, 300) back
     the press glow (InteractiveHighlight) and its position
                                          spring(.5, 300) each
   On release the lens is not set down until it is within 2.5% of the tab
   range of its tab (DampedDragAnimation.release()); a tap lifts it, moves
   it and sets it down the same way (animateToValue: press, move, release).

   Geometry, his on a 64 dp bar with 4 dp padding: the lens at rest is one
   tab slot by (bar height - 2 x inset), centred on its tab; pressed it is
   that times 78 / 56 both ways (its own springs), then the drag speed v
   (the velocity above / 10) makes it scaleX / (1 - clamp(.75 v, +-.2)) wide
   and scaleY x (1 - clamp(.25 v, +-.2)) tall, signed as his (moving right
   widens and flattens it, moving left narrows it and makes it taller). The
   bar grows by 16 dp across its width as it is pressed (1 + 16 / width, both
   ways); dragged, the bar and the lens drift 4 dp x EaseOut(|drag| / width)
   toward the drag. Nothing else of the dock's own geometry (growth, end
   wrap, elastic motion, scripts) is used. */
static inline double WXGKyantDamping(double ratio,double stiffness) {return 2.*ratio*sqrt(stiffness);}
static inline void WXGKyantSpring(double *x,double *v,double target,double ratio,double stiffness,double dt) {
    double k=stiffness,c=WXGKyantDamping(ratio,stiffness);
    if(!(dt>0.))return;
    if(dt>.064)dt=.064;
    int count=(int)ceil(dt/(1./240.));if(count<1)count=1;
    double h=dt/count;
    for(int i=0;i<count;i++){*v+=((target-*x)*k-*v*c)*h;*x+=*v*h;}
    if(fabs(target-*x)<1e-4 && fabs(*v)<1e-4){*x=target;*v=0;}
}
#define WXG_KYANT_PRESSED_SCALE (78./56.)
/* Compose's EaseOut, CubicBezier(0, 0, .58, 1): x(t) solved for f, y(t). */
static inline double WXGKyantEaseOut(double f) {
    f=f<0.?0.:f>1.?1.:f;
    double lo=0.,hi=1.,t=f;
    for(int i=0;i<40;i++){t=(lo+hi)*.5;double x=3.*(1.-t)*t*t*.58+t*t*t;if(x<f)lo=t;else hi=t;}
    return 3.*(1.-t)*t*t+t*t*t;
}
typedef struct {
    double scaleX,scaleXV,scaleY,scaleYV;   /* the lens' own scale (1 at rest) */
    double velocity,velocityV;              /* tab ranges per second, smoothed */
    double drift,driftV,drag;               /* the bar's drift (pt) and the drag so far (pt) */
    double glow,glowV,glowX,glowXV;         /* the press glow and its centre (pt) */
    int hold;                               /* released: the press holds until the lens arrives */
    int dragging;                           /* the finger is dragging (the drift follows it) */
    int started;
} WXGKyantMotion;
static inline void WXGKyantMotionReset(WXGKyantMotion *m) {
    WXGKyantMotion z={1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0};*m=z;
}
/* One frame. lensVelocity: the lens' speed (pt/s); tabRange: the distance
   between the first and last tab centres (pt); pressed: the press' target;
   glowOn / glowTarget: the glow's own target and centre; barWidth for the
   drift. */
static inline void WXGKyantMotionStep(WXGKyantMotion *m,double lensVelocity,double tabRange,int pressed,double pressedScale,
                                      int glowOn,double glowTarget,double barWidth,double dt) {
    if(!m->started){WXGKyantMotionReset(m);m->started=1;m->glowX=glowTarget;}
    double target=pressed?pressedScale:1.;
    WXGKyantSpring(&m->scaleX,&m->scaleXV,target,.6,250.,dt);
    WXGKyantSpring(&m->scaleY,&m->scaleYV,target,.7,250.,dt);
    double v=tabRange>1.?lensVelocity/tabRange:0.;
    WXGKyantSpring(&m->velocity,&m->velocityV,isfinite(v)?v:0.,.5,300.,dt);
    if(m->dragging && barWidth>1.) {
        double f=fabs(m->drag)/barWidth;f=f>1.?1.:f;
        m->drift=4.*(m->drag<0.?-1.:m->drag>0.?1.:0.)*WXGKyantEaseOut(f);m->driftV=0;
    }else WXGKyantSpring(&m->drift,&m->driftV,0.,1.,300.,dt);
    WXGKyantSpring(&m->glow,&m->glowV,glowOn?1.:0.,.5,300.,dt);
    WXGKyantSpring(&m->glowX,&m->glowXV,glowTarget,.5,300.,dt);
}
/* Released: true once the lens is close enough to set down. */
static inline int WXGKyantArrived(double lensX,double targetX,double tabRange) {
    double range=tabRange>1.?tabRange:1.;
    return fabs(lensX-targetX)<.025*range;
}
typedef struct { double width,height,barScale; } WXGKyantPose;
/* The lens' size and the bar's scale. slot: one tab's width; restHeight:
   bar height - 2 x inset; growth: what the bar grows across (pt). */
static inline WXGKyantPose WXGKyantLayout(WXGKyantMotion m,double slot,double restHeight,double barWidth,double press,double growth,int elastic) {
    double sx=m.scaleX,sy=m.scaleY;
    if(elastic) {
        double v=m.velocity/10.,a=.75*v,b=.25*v;
        a=a<-.2?-.2:a>.2?.2:a;b=b<-.2?-.2:b>.2?.2:b;
        sx/=1.-a;sy*=1.-b;
    }
    WXGKyantPose p;
    p.width=slot*sx;p.height=restHeight*sy;
    p.barScale=1.+(barWidth>1.?growth/barWidth:0.)*(press<0.?0.:press>1.?1.:press);
    return p;
}
/* The press glow (InteractiveHighlight): white over the whole bar at 8% and
   a round light at the lens at 15%, full within half its radius, gone at
   1.5 x the bar's short side (smoothstep); both times the glow. */
#define WXG_KYANT_GLOW_WASH .08
#define WXG_KYANT_GLOW_SPOT .15
static inline double WXGKyantGlowSpot(double distance,double radius) {
    if(!(radius>0.))return 0.;
    double t=(distance-radius)/(radius*.5-radius);t=t<0.?0.:t>1.?1.:t;
    return t*t*(3.-2.*t);
}
#endif
