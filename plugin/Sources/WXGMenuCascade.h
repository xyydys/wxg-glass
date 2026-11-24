#ifndef WXG_MENU_CASCADE_H
#define WXG_MENU_CASCADE_H
#include <math.h>

/* Home "+" floating menu — R20 Arc-Retract -> Dot-Flight -> Blur-Morph -> Icon
   motion engine (pure C geometry & timing, no UIKit):
   - Trigger button proportions matched to screenshot:
     * 270 deg solid arc (135 deg -> 45 deg CW) at radius ~0.34 * size (~15pt at 44pt)
     * 5 bottom dots with mathematically EQUAL clear spacing between adjacent dots
       AND between the outer dots and the arc's round caps (never touching/merging)
     * crisp center + / x (arm ~0.115 * size)
   - Expand (~540ms at 1x speed):
     1. 0..150ms: outer arc retracts CCW from right to left (strokeEnd 1 -> 0);
        dots detach sequentially as the arc clears; center + shrinks & fades to 0,
        swapping cleanly to shrunken x at 150ms.
     2. Dots fly directly from their 5 bottom-ring anchors along a gentle organic
        curve to each menu row's circular glass icon center while x scales smoothly
        up to 1.0 (150..360ms, zero overshoot).
     3. On arrival, each dot blurs (Gaussian radius 0 -> 10) and dissolves directly
        into the circular glass icon (unblurring 9 -> 0, scaling 0.62 -> 1.0,
        ZERO post-expand bounce!), followed by the left glass text capsule sliding
        horizontally out (dy = 0, zero bounce).
   - Collapse (~380ms at 1x speed): exact reverse playback — capsules retract first,
     icons blur-morph back into the dots, dots fly back along the exact reversed
     path into the 5 bottom-arc anchors, x shrinks & swaps back to +, and the
     270 deg arc grows CW back to full. */

typedef struct { double x,y,w,h; } WXGMenuBox;

/* ---- layout ------------------------------------------------------------ */
typedef struct { double icon,capsuleHeight,fontSize,gap,padding; } WXGMenuMetrics;
typedef struct { WXGMenuBox icon,capsule; } WXGMenuRowBoxes;

static inline double WXGMenuClamp(double x,double lo,double hi) { return x<lo?lo:x>hi?hi:x; }

/* The icon as asked (the "+" button's size), never so large that two rows touch
   (a row is `rowHeight` of WeChat's own layout, where the touch targets stay). */
static inline WXGMenuMetrics WXGMenuMetricsFor(double wantedIcon,double rowHeight) {
    double room=isfinite(rowHeight)&&rowHeight>0?rowHeight-6:wantedIcon;
    double icon=WXGMenuClamp(isfinite(wantedIcon)?wantedIcon:44,30,fmax(30,room));
    double height=round(icon*.78);
    return (WXGMenuMetrics){icon,height,floor(height*.45*2)/2,round(icon*.26),round(height*.45)};
}

/* One row: the icon's centre on `iconCentreX` (the "+"'s), both on the row's
   middle; the capsule ends `gap` before the icon and is as wide as its title
   needs (at least 1.7 heights), but never reaches left of `minX`. */
static inline WXGMenuRowBoxes WXGMenuRowBoxesFor(double rowMidY,double iconCentreX,double textWidth,WXGMenuMetrics m,double minX) {
    WXGMenuRowBoxes r;
    r.icon=(WXGMenuBox){iconCentreX-m.icon*.5,rowMidY-m.icon*.5,m.icon,m.icon};
    double right=r.icon.x-m.gap;
    double width=fmax(m.capsuleHeight*1.7,ceil(isfinite(textWidth)?textWidth:0)+2*m.padding);
    if(isfinite(minX) && right-width<minX)width=fmax(m.capsuleHeight*1.7,right-minX);
    r.capsule=(WXGMenuBox){right-width,rowMidY-m.capsuleHeight*.5,width,m.capsuleHeight};
    return r;
}

/* ---- cubic bezier & easing (strictly monotonic zero-overshoot curves) -- */
static inline double WXGMenuCubicSample(double t,double p1,double p2) {
    double u=1.-t;
    return 3.*u*u*t*p1+3.*u*t*t*p2+t*t*t;
}
static inline double WXGMenuCubicBezier(double x,double x1,double y1,double x2,double y2) {
    if(!(x>0.))return 0.;
    if(x>=1.)return 1.;
    double lo=0.,hi=1.,t=x;
    for(int i=0;i<14;i++) {
        t=.5*(lo+hi);
        if(WXGMenuCubicSample(t,x1,x2)<x)lo=t;else hi=t;
    }
    return WXGMenuCubicSample(t,y1,y2);
}
static inline double WXGMenuEaseOut(double u) {
    return WXGMenuCubicBezier(WXGMenuClamp(u,0.,1.),.22,1.,.36,1.);
}
static inline double WXGMenuEaseIn(double u) {
    return WXGMenuCubicBezier(WXGMenuClamp(u,0.,1.),.55,0.,1.,.45);
}
static inline double WXGMenuEaseInOut(double u) {
    u=WXGMenuClamp(u,0.,1.);
    return u*u*(3.-2.*u);
}

/* ---- Trigger button proportions & equal-gap 5-dot ring geometry -------- */
enum { WXGMenuParticleCount = 5 };

/* Outer ring radius (~15.0pt at 44pt button, matching screenshot proportion). */
static inline double WXGMenuRingRadius(double size) {
    double s=isfinite(size)&&size>0?size:44.;
    return WXGMenuClamp(s*.340,9.,22.);
}
static inline double WXGMenuRingLineWidth(double size) {
    double s=isfinite(size)&&size>0?size:44.;
    return WXGMenuClamp(s*.040,1.5,2.0);
}
static inline double WXGMenuRingDotDiameterFor(double size) {
    double s=isfinite(size)&&size>0?size:44.;
    return WXGMenuClamp(s*.060,2.2,2.9);
}
static inline double WXGMenuRingDotDiameter(void) { return WXGMenuRingDotDiameterFor(44.); }
static inline double WXGMenuSymbolArmLength(double size) {
    double s=isfinite(size)&&size>0?size:44.;
    return round(s*.115*2.)*.5;
}
static inline double WXGMenuSymbolLineWidth(double size) {
    double s=isfinite(size)&&size>0?size:44.;
    return WXGMenuClamp(s*.044,1.7,2.2);
}

/* Bottom 5 dot angles (radians, UIKit y-down where pi/2 = 6:00) inside the
   90-deg bottom opening (45..135 deg) with EXACTLY EQUAL clear edge-to-edge
   gaps between: (arc cap at 45 deg <-> dot 0), (dot i <-> dot i+1), and
   (dot 4 <-> arc cap at 135 deg). */
static inline double WXGMenuRingDotAngleForSize(int idx,double size) {
    const double pi=3.14159265358979323846;
    if(idx<0)idx=0;
    if(idx>=WXGMenuParticleCount)idx=WXGMenuParticleCount-1;
    double r=WXGMenuRingRadius(size);
    double capHalf=(WXGMenuRingLineWidth(size)*.5)/r;
    double dotHalf=(WXGMenuRingDotDiameterFor(size)*.5)/r;
    double clearSpan=(pi*.5)-2.*capHalf;
    double gap=(clearSpan-(double)WXGMenuParticleCount*2.*dotHalf)/(double)(WXGMenuParticleCount+1);
    if(gap<0.)gap=0.;
    return (pi*.25)+capHalf+gap+dotHalf+(double)idx*(2.*dotHalf+gap);
}
static inline double WXGMenuRingDotAngle(int idx) { return WXGMenuRingDotAngleForSize(idx,44.); }

/* Track 1 strokeEnd at `t` seconds:
   open:  1.0 -> 0.0 over 0..150ms (CCW from right 45 deg to left 135 deg)
   close: 0.0 -> 1.0 over 150..360ms (CW reverse as dots dock back into ring) */
static inline double WXGMenuRingStrokeAt(int open,double t,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double ts=t*v;
    if(open) {
        if(ts<=0.)return 1.;
        if(ts>=.150)return 0.;
        return 1.-WXGMenuCubicBezier(ts/.150,.38,0.,.85,1.);
    }
    if(ts<=.150)return 0.;
    if(ts>=.360)return 1.;
    return WXGMenuEaseOut((ts-.150)/.210);
}

/* Track 2 center glyph (+ <-> x) pose at `t` seconds (zero overshoot / no bounce):
   open:  0..150ms + shrinks 1.0 -> 0.05 & fades 1 -> 0; instant swap to x at 150ms;
          150..360ms x grows 0.05 -> 1.0 & fades 0 -> 1.
   close: 0..170ms x shrinks 1.0 -> 0.05 & fades 1 -> 0; instant swap to + at 170ms;
          170..360ms + grows 0.05 -> 1.0 & fades 0 -> 1. */
typedef struct { double scale,alpha,rotationRad; int isClose; } WXGMenuSymbolPose;
static inline WXGMenuSymbolPose WXGMenuSymbolPoseAt(int open,double t,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double ts=t*v;
    const double pi4=0.78539816339744830962;
    if(open) {
        if(ts<.150) {
            double u=WXGMenuCubicBezier(WXGMenuClamp(ts/.150,0.,1.),.4,0.,.8,1.);
            return (WXGMenuSymbolPose){1.-.95*u,WXGMenuClamp(1.-u,0.,1.),0.,0};
        }
        double u=WXGMenuEaseOut((ts-.150)/.210);
        return (WXGMenuSymbolPose){.05+.95*u,WXGMenuClamp(u,0.,1.),pi4,1};
    }
    if(ts<.170) {
        double u=WXGMenuCubicBezier(WXGMenuClamp(ts/.170,0.,1.),.4,0.,.8,1.);
        return (WXGMenuSymbolPose){1.-.95*u,WXGMenuClamp(1.-u,0.,1.),pi4,1};
    }
    double u=WXGMenuEaseOut((ts-.170)/.190);
    return (WXGMenuSymbolPose){.05+.95*u,WXGMenuClamp(u,0.,1.),0.,0};
}

/* ---- Dot-to-Icon Blur-Morph Particle Trajectory (Direct 1:1 per row) --- */
typedef struct { double x,y,diameter,alpha,blurRadius; } WXGMenuParticle;

/* Dot detach & arrival timings (unscaled seconds at speed=1.0).
   Row k (0..count-1) pairs with dot idx = k (mapped right-to-left along bottom arc
   as the arc sweeps CCW from 45 deg to 135 deg). All dots leave by ~150ms. */
static inline double WXGMenuDotDetachAt(int idx,int count,double stagger) {
    double g=WXGMenuClamp(isfinite(stagger)?stagger:.045,0.,.080);
    int n=count>0?count:1;
    double step=n>1?fmin(.028,.110/(double)(n-1)):0.;
    (void)g;
    return .035+step*(double)(idx<0?0:idx);
}
static inline double WXGMenuDotArriveAt(int idx,int count,double stagger) {
    double g=WXGMenuClamp(isfinite(stagger)?stagger:.045,0.,.080);
    double det=WXGMenuDotDetachAt(idx,count,stagger);
    double flight=.125+fmin(g*.55,.028)*(double)(idx<0?0:idx);
    return det+flight;
}

/* Evaluates dot `idx` flying between its static bottom-arc anchor and `targetX, targetY`
   (row `idx`'s circular glass icon centre) with Gaussian-blur morph at the icon end.
   Collapse (`open == 0`) is the exact time-reversed trajectory over `0..360ms`! */
static inline WXGMenuParticle WXGMenuDotMorphPoseAt(int idx,int count,int open,double t,double speed,double stagger,
    double plusMidX,double plusMidY,double buttonSize,double targetX,double targetY) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double ts=t*v;
    int dotSlot=idx<0?0:(idx>=WXGMenuParticleCount?WXGMenuParticleCount-1:idx);
    double ringR=WXGMenuRingRadius(buttonSize);
    double dotDiam=WXGMenuRingDotDiameterFor(buttonSize);
    double angle=WXGMenuRingDotAngleForSize(dotSlot,buttonSize);
    double anchorX=plusMidX+ringR*cos(angle);
    double anchorY=plusMidY+ringR*sin(angle);

    double tDetach=WXGMenuDotDetachAt(idx,count,stagger);
    double tArrive=WXGMenuDotArriveAt(idx,count,stagger);
    double tMorphEnd=tArrive+.095;
    double flightDur=fmax(tArrive-tDetach,.06);

    /* Gentle organic curve bowing slightly outward on the way from anchor to icon center. */
    double ctrlX=.5*(anchorX+targetX)+((dotSlot-2)*2.5-5.0);
    double ctrlY=.42*anchorY+.58*targetY;

    if(open) {
        if(ts<=tDetach) {
            return (WXGMenuParticle){anchorX,anchorY,dotDiam,1.,0.};
        }
        if(ts<tArrive) {
            double u=WXGMenuCubicBezier((ts-tDetach)/flightDur,.25,.05,.35,1.);
            double om=1.-u;
            double x=om*om*anchorX+2.*om*u*ctrlX+u*u*targetX;
            double y=om*om*anchorY+2.*om*u*ctrlY+u*u*targetY;
            double diam=dotDiam+(11.5-dotDiam)*WXGMenuEaseInOut(u);
            /* Begin softening slightly during the final 25% of flight into the morph. */
            double preBlur=u>.75?((u-.75)/.25)*3.5:0.;
            return (WXGMenuParticle){x,y,diam,1.,preBlur};
        }
        if(ts<tMorphEnd) {
            double m=WXGMenuEaseOut((ts-tArrive)/(tMorphEnd-tArrive));
            double diam=11.5+10.5*m;
            double blur=3.5+6.5*m;
            double alpha=WXGMenuClamp(1.-m,0.,1.);
            return (WXGMenuParticle){targetX,targetY,diam,alpha,blur};
        }
        return (WXGMenuParticle){targetX,targetY,0.,0.,10.};
    }

    /* Collapse (0..360ms): exact reversed morph + flight back to anchor!
       Bottom rows lift slightly earlier so they arrive back at the ring smoothly together. */
    int revOrd=(count>1?(count-1-idx):0);
    if(revOrd<0)revOrd=0;
    double cStart=.030+.014*(double)revOrd;
    double cUnblur=cStart+.085;
    double cDock=.275+.016*(double)(dotSlot);
    if(cDock>.355)cDock=.355;

    if(ts<=cStart) {
        return (WXGMenuParticle){targetX,targetY,0.,0.,10.};
    }
    if(ts<cUnblur) {
        /* Icon blurs & condenses back into the dot at icon center. */
        double m=WXGMenuEaseOut((ts-cStart)/(cUnblur-cStart));
        double diam=22.0-10.5*m;
        double blur=10.0-6.5*m;
        double alpha=WXGMenuClamp(m,0.,1.);
        return (WXGMenuParticle){targetX,targetY,diam,alpha,blur};
    }
    if(ts<cDock) {
        /* Exact reversed Bezier path back to the dot's bottom-arc anchor. */
        double u=WXGMenuCubicBezier((ts-cUnblur)/fmax(cDock-cUnblur,.06),.45,0.,.25,1.);
        double om=1.-u;
        double x=om*om*targetX+2.*om*u*ctrlX+u*u*anchorX;
        double y=om*om*targetY+2.*om*u*ctrlY+u*u*anchorY;
        double diam=11.5+(dotDiam-11.5)*WXGMenuEaseInOut(u);
        double blur=u<.25?3.5*(1.-u/.25):0.;
        return (WXGMenuParticle){x,y,diam,1.,blur};
    }
    return (WXGMenuParticle){anchorX,anchorY,dotDiam,1.,0.};
}

/* Backwards-compatible wrapper for legacy callers. */
static inline WXGMenuParticle WXGMenuParticlePoseAt(int idx,int open,double t,double speed,
    double plusMidX,double plusMidY,double ringRadius,double lastRowMidY) {
    double size=WXGMenuClamp(ringRadius/.340,30.,60.);
    double span=fmax(lastRowMidY-(plusMidY+ringRadius),48.);
    double rowY=plusMidY+ringRadius+span*((double)(idx+1)/(double)WXGMenuParticleCount);
    return WXGMenuDotMorphPoseAt(idx,WXGMenuParticleCount,open,t,speed,.045,plusMidX,plusMidY,size,plusMidX,rowY);
}

/* ---- Glass Icon Blur-Morph Reveal & Left Glass Capsule Reveal ---------- */
typedef struct { double stiffness,damping,mass; } WXGMenuSpring;
typedef struct {
    double iconDelay,capsuleDelay,textDelay;
    double iconDuration,capsuleDuration;
    double iconFade,capsuleFade,textFade;
    double iconBlurStart;                       /* Gaussian blur radius at morph handoff (pt) */
    WXGMenuSpring iconSpring,capsuleSpring;     /* ABI compat */
    double iconScale,capsuleScaleX,capsuleScaleY;
    double travel;                              /* subtle 10pt settle during blur-morph */
    double capsuleShift;                        /* +12pt horizontal slide from right -> 0 */
    double textShift;
} WXGMenuEntrance;

/* Row `index` (0 = top). Icon materializes directly where its dot arrives via
   Gaussian-blur morph (zero bounce!); capsule glides horizontally out beside it. */
static inline WXGMenuEntrance WXGMenuEntranceForCount(int index,int count,double slotDistance,double stagger,double speed) {
    (void)slotDistance;
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double gap=WXGMenuClamp(isfinite(stagger)?stagger:.045,0.,.080);
    int i=index<0?0:index;
    double arrive=WXGMenuDotArriveAt(i,count>0?count:5,gap);
    WXGMenuEntrance e;
    e.iconDelay=fmax(0.,arrive-.030)/v;
    e.iconDuration=.160/v;
    e.iconFade=.135/v;
    e.iconBlurStart=9.0;
    e.capsuleDelay=(arrive+.025)/v;
    e.textDelay=e.capsuleDelay;
    e.capsuleDuration=.150/v;
    e.capsuleFade=.140/v;
    e.textFade=.140/v;
    e.iconSpring=(WXGMenuSpring){400.*v*v,40.*v,1.};
    e.capsuleSpring=(WXGMenuSpring){480.*v*v,44.*v,1.};
    e.iconScale=.62;
    e.capsuleScaleX=.94;
    e.capsuleScaleY=.94;
    e.travel=10.;
    e.capsuleShift=12.;
    e.textShift=0.;
    return e;
}
static inline WXGMenuEntrance WXGMenuEntranceFor(int index,double slotDistance,double stagger,double speed) {
    return WXGMenuEntranceForCount(index,5,slotDistance,stagger,speed);
}

/* Kept for backwards compatibility with tools/tests. */
static inline double WXGMenuSpringProgress(WXGMenuSpring s,double t) {
    if(!(t>0.))return 0.;
    double m=fmax(s.mass,1e-6),k=fmax(s.stiffness,1e-6),c=fmax(s.damping,0.);
    double w0=sqrt(k/m),z=c/(2.*sqrt(k*m));
    if(z<1.) {
        double wd=w0*sqrt(1.-z*z);
        return 1.-exp(-z*w0*t)*(cos(wd*t)+z*w0/wd*sin(wd*t));
    }
    if(z==1.)return 1.-exp(-w0*t)*(1.+w0*t);
    double r=w0*sqrt(z*z-1.),a=-z*w0+r,b=-z*w0-r;
    return 1.-(a*exp(b*t)-b*exp(a*t))/(a-b);
}
static inline double WXGMenuSpringSettle(WXGMenuSpring s,double threshold) {
    double t=0.,last=0.;
    for(int k=1;k<=4000;k++) {
        t=k*.002;
        if(fabs(WXGMenuSpringProgress(s,t)-1.)>threshold)last=t;
    }
    return last+.002;
}

typedef struct { double alpha,scaleX,scaleY,dx,dy,textAlpha,textDx; } WXGMenuPose;

/* Icon pose at `t` seconds during expand: strictly monotonic ease-out, ZERO bounce! */
static inline WXGMenuPose WXGMenuIconPoseAt(const WXGMenuEntrance *e,double t) {
    double p=WXGMenuEaseOut((t-e->iconDelay)/fmax(e->iconDuration,1e-4));
    double a=WXGMenuEaseOut((t-e->iconDelay)/fmax(e->iconFade,1e-4));
    double s=e->iconScale+(1.-e->iconScale)*p;
    return (WXGMenuPose){a,s,s,0.,-e->travel*(1.-p),0.,0.};
}

/* Capsule pose at `t` seconds during expand: zero vertical travel, horizontal slide from right! */
static inline WXGMenuPose WXGMenuCapsulePoseAt(const WXGMenuEntrance *e,double t,double halfWidth) {
    double p=WXGMenuEaseOut((t-e->capsuleDelay)/fmax(e->capsuleDuration,1e-4));
    double a=WXGMenuEaseOut((t-e->capsuleDelay)/fmax(e->capsuleFade,1e-4));
    double s=e->capsuleScaleX+(1.-e->capsuleScaleX)*p;
    double dx=(1.-s)*halfWidth+e->capsuleShift*(1.-p);
    return (WXGMenuPose){a,s,s,dx,0.,a,0.};
}

/* Total expand duration across all tracks (~0.52s for 5 rows at default stagger/speed). */
static inline double WXGMenuTotalDuration(int count,double rowPitch,double stagger,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double end=.380/v;
    for(int i=0;i<count;i++) {
        WXGMenuEntrance e=WXGMenuEntranceForCount(i,count,(i+1)*rowPitch,stagger,speed);
        double a=e.iconDelay+e.iconDuration;
        double b=e.capsuleDelay+e.capsuleDuration;
        end=fmax(end,fmax(a,b));
    }
    return end;
}

/* ---- Collapse (380ms total — Exact Reverse of Expand) ------------------ */
typedef struct {
    double iconDelay,capsuleDelay,textDelay;
    double iconDuration,capsuleDuration,textDuration;
    double iconFade,capsuleFade;
    double iconBlurEnd;
    double iconScale,capsuleScaleX,capsuleScaleY;
    double travel;          /* subtle 10pt reverse lift as icon blur-morphs back into its dot */
    double capsuleShift;    /* +10pt right retract during 100ms fast vanish */
    double textShift;
} WXGMenuExit;

/* `order` 0 is the lowest row (starts blur-morphing back into its dot first). */
static inline WXGMenuExit WXGMenuExitFor(int order,double slotDistance,double stagger,double speed) {
    (void)slotDistance;
    (void)stagger;
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    int o=order<0?0:order;
    WXGMenuExit e;
    e.capsuleDelay=0.;
    e.textDelay=0.;
    e.capsuleDuration=.100/v;
    e.capsuleFade=.095/v;
    e.textDuration=.100/v;
    e.iconDelay=(.020+.014*(double)o)/v;
    e.iconDuration=.115/v;
    e.iconFade=.105/v;
    e.iconBlurEnd=9.0;
    e.iconScale=.62;
    e.capsuleScaleX=.94;
    e.capsuleScaleY=.94;
    e.travel=10.;
    e.capsuleShift=10.;
    e.textShift=0.;
    return e;
}

static inline WXGMenuPose WXGMenuExitIconPoseAt(const WXGMenuExit *e,double t) {
    double p=WXGMenuEaseIn((t-e->iconDelay)/fmax(e->iconDuration,1e-4));
    double f=WXGMenuEaseIn((t-e->iconDelay)/fmax(e->iconFade,1e-4));
    double s=1.+(e->iconScale-1.)*p;
    return (WXGMenuPose){1.-f,s,s,0.,-e->travel*p,0.,0.};
}

static inline WXGMenuPose WXGMenuExitCapsulePoseAt(const WXGMenuExit *e,double t,double halfWidth) {
    double p=WXGMenuEaseIn((t-e->capsuleDelay)/fmax(e->capsuleDuration,1e-4));
    double f=WXGMenuEaseIn((t-e->capsuleDelay)/fmax(e->capsuleFade,1e-4));
    double s=1.+(e->capsuleScaleX-1.)*p;
    double dx=(1.-s)*halfWidth+e->capsuleShift*p;
    return (WXGMenuPose){1.-f,s,s,dx,0.,1.-f,0.};
}

/* Total collapse duration across all tracks (0.36s at speed=1.0). */
static inline double WXGMenuExitDuration(int count,double rowPitch,double stagger,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double end=.360/v; /* arc close + + recovery + dot dock */
    for(int i=0;i<count;i++) {
        WXGMenuExit e=WXGMenuExitFor(i,(count-i)*rowPitch,stagger,speed);
        end=fmax(end,fmax(e.iconDelay+e.iconDuration,e.capsuleDelay+e.capsuleDuration));
    }
    return end;
}
#endif
