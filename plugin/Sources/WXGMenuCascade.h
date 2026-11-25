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

/* ---- Trigger button proportions & dynamic N-dot equal-gap ring geometry - */
enum { WXGMenuMaxParticles = 6, WXGMenuParticleCount = 4 };

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
    return WXGMenuClamp(s*.066,2.4,3.1);
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

static inline int WXGMenuClampCount(int count) {
    if(count<1)return WXGMenuParticleCount;
    if(count>WXGMenuMaxParticles)return WXGMenuMaxParticles;
    return count;
}

/* Bottom N dot angles (radians, UIKit y-down where pi/2 = 6:00) inside the
   90-deg bottom opening (45..135 deg) with EXACTLY EQUAL clear edge-to-edge
   gaps between: (arc cap at 45 deg <-> dot 0), (dot i <-> dot i+1), and
   (dot N-1 <-> arc cap at 135 deg). */
static inline double WXGMenuRingDotAngleForCount(int idx,int count,double size) {
    const double pi=3.14159265358979323846;
    int n=WXGMenuClampCount(count);
    if(idx<0)idx=0;
    if(idx>=n)idx=n-1;
    double r=WXGMenuRingRadius(size);
    double capHalf=(WXGMenuRingLineWidth(size)*.5)/r;
    double dotHalf=(WXGMenuRingDotDiameterFor(size)*.5)/r;
    double clearSpan=(pi*.5)-2.*capHalf;
    double gap=(clearSpan-(double)n*2.*dotHalf)/(double)(n+1);
    if(gap<0.)gap=0.;
    return (pi*.25)+capHalf+gap+dotHalf+(double)idx*(2.*dotHalf+gap);
}
static inline double WXGMenuRingDotAngleForSize(int idx,double size) {
    return WXGMenuRingDotAngleForCount(idx,WXGMenuParticleCount,size);
}
static inline double WXGMenuRingDotAngle(int idx) { return WXGMenuRingDotAngleForCount(idx,WXGMenuParticleCount,44.); }

/* ---- Unified Normalized-Progress (0.0 -> 1.0) Choreography Engine -------
   Every track (arc, +/x symbol, N flying dots, N circular glass icons, and
   N text capsules) is a pure deterministic function of a single progress `p`
   in [0.0, 1.0]. Expanding drives p: 0 -> 1; collapsing drives p: current -> 0.
   This guarantees exact reverse playback, seamless mid-flight reversal, and
   makes it structurally impossible for the trigger button or menu icons to
   desync or freeze. */

static inline double WXGMenuOpenDuration(double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    return .620/v;
}
static inline double WXGMenuCloseDuration(double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    return .560/v;
}

/* Split point where the arc finishes retracting, all dots have detached from
   the button, and the center + reaches 0 and swaps cleanly to x. */
static inline double WXGMenuHandoffProgress(void) { return .44; }

/* Track 1: 270-deg arc strokeEnd as a function of p in [0, 1].
   p = 0.00 -> 0.44 (~273ms at 1x open, ~246ms at 1x close): smooth CCW sweep 1 -> 0. */
static inline double WXGMenuArcStrokeForProgress(double p) {
    double h=WXGMenuHandoffProgress();
    if(p<=0.)return 1.;
    if(p>=h)return 0.;
    return 1.-WXGMenuEaseInOut(p/h);
}

/* Track 2: center glyph (+ <-> x) as a function of p in [0, 1] (zero bounce). */
typedef struct { double scale,alpha,rotationRad; int isClose; } WXGMenuSymbolPose;
static inline WXGMenuSymbolPose WXGMenuSymbolForProgress(double p) {
    const double pi4=0.78539816339744830962;
    double h=WXGMenuHandoffProgress();
    p=WXGMenuClamp(p,0.,1.);
    if(p<h) {
        double u=WXGMenuEaseInOut(p/h);
        return (WXGMenuSymbolPose){1.-.95*u,WXGMenuClamp(1.-u,0.,1.),0.,0};
    }
    double u=WXGMenuEaseOut(WXGMenuClamp((p-h)/(.92-h),0.,1.));
    return (WXGMenuSymbolPose){.05+.95*u,WXGMenuClamp(u,0.,1.),pi4,1};
}

/* Dot detach & arrival points in normalized progress p in [0, 1].
   All dots detach sequentially as the arc sweeps past them (0.06..0.36 < 0.44). */
static inline double WXGMenuDotDetachProgress(int idx,int count) {
    int n=WXGMenuClampCount(count);
    int i=idx<0?0:(idx>=n?n-1:idx);
    double step=n>1?fmin(.095,.30/(double)(n-1)):0.;
    return .06+step*(double)i;
}
static inline double WXGMenuDotArriveProgress(int idx,int count,double stagger) {
    int n=WXGMenuClampCount(count);
    int i=idx<0?0:(idx>=n?n-1:idx);
    double g=WXGMenuClamp(isfinite(stagger)?stagger:.045,0.,.080);
    double det=WXGMenuDotDetachProgress(i,n);
    double extra=n>1?fmin(g*.55,.040)*(double)i:0.;
    double arr=det+.26+extra;
    return arr>.72?.72:arr;
}

typedef struct { double x,y,diameter,alpha,blurRadius; } WXGMenuParticle;

/* Track 3: dot `idx` pose at normalized progress `p` in [0, 1].
   p <= pDetach: resting at bottom-arc anchor (0 blur).
   pDetach..pArrive: curved flight to icon center, softly pre-blurring near arrival.
   pArrive..pArrive+0.16: Gaussian-blur morph (3.5 -> 10pt) dissolving into icon.
   Reverse (p: 1 -> 0): exact reverse playback! */
static inline WXGMenuParticle WXGMenuDotForProgress(int idx,int count,double p,double stagger,
    double plusMidX,double plusMidY,double buttonSize,double targetX,double targetY) {
    p=WXGMenuClamp(p,0.,1.);
    int n=WXGMenuClampCount(count);
    int dotSlot=idx<0?0:(idx>=n?n-1:idx);
    double ringR=WXGMenuRingRadius(buttonSize);
    double dotDiam=WXGMenuRingDotDiameterFor(buttonSize);
    double angle=WXGMenuRingDotAngleForCount(dotSlot,n,buttonSize);
    double anchorX=plusMidX+ringR*cos(angle);
    double anchorY=plusMidY+ringR*sin(angle);

    double pDet=WXGMenuDotDetachProgress(dotSlot,n);
    double pArr=WXGMenuDotArriveProgress(dotSlot,n,stagger);
    double pMorphEnd=fmin(.90,pArr+.16);
    double flightSpan=fmax(pArr-pDet,.08);

    double ctrlX=.5*(anchorX+targetX)+((dotSlot-(n-1)*.5)*2.5-4.0);
    double ctrlY=.42*anchorY+.58*targetY;

    if(p<=pDet) {
        return (WXGMenuParticle){anchorX,anchorY,dotDiam,1.,0.};
    }
    if(p<pArr) {
        double u=WXGMenuCubicBezier((p-pDet)/flightSpan,.25,.05,.35,1.);
        double om=1.-u;
        double x=om*om*anchorX+2.*om*u*ctrlX+u*u*targetX;
        double y=om*om*anchorY+2.*om*u*ctrlY+u*u*targetY;
        double diam=dotDiam+(12.0-dotDiam)*WXGMenuEaseInOut(u);
        double preBlur=u>.75?((u-.75)/.25)*3.5:0.;
        return (WXGMenuParticle){x,y,diam,1.,preBlur};
    }
    if(p<pMorphEnd) {
        double m=WXGMenuEaseOut((p-pArr)/fmax(pMorphEnd-pArr,.04));
        double diam=12.0+10.0*m;
        double blur=3.5+6.5*m;
        double alpha=WXGMenuClamp(1.-m,0.,1.);
        return (WXGMenuParticle){targetX,targetY,diam,alpha,blur};
    }
    return (WXGMenuParticle){targetX,targetY,0.,0.,10.};
}

typedef struct { double alpha,scaleX,scaleY,dx,dy,blurRadius; } WXGMenuRowPose;

/* Track 4: circular glass icon pose at normalized progress `p` in [0, 1].
   Materializes via Gaussian-blur unblur directly at dot arrival (zero bounce!). */
static inline WXGMenuRowPose WXGMenuRowIconForProgress(int idx,int count,double p,double stagger) {
    p=WXGMenuClamp(p,0.,1.);
    double pArr=WXGMenuDotArriveProgress(idx,count,stagger);
    double pStart=fmax(0.,pArr-.04);
    double pDur=.22;
    if(p<=pStart)return (WXGMenuRowPose){0.,.62,.62,0.,0.,9.0};
    double u=WXGMenuEaseOut(WXGMenuClamp((p-pStart)/pDur,0.,1.));
    double s=.62+.38*u;
    return (WXGMenuRowPose){u,s,s,0.,0.,9.0*(1.-u)};
}

/* Track 5: left text glass capsule pose at normalized progress `p` in [0, 1].
   Pure horizontal slide from right (dy = 0, zero bounce!). On collapse (p: 1->0),
   capsules naturally retract first before icons blur back into dots. */
static inline WXGMenuRowPose WXGMenuRowCapsuleForProgress(int idx,int count,double p,double stagger,double halfWidth) {
    p=WXGMenuClamp(p,0.,1.);
    double pArr=WXGMenuDotArriveProgress(idx,count,stagger);
    double pStart=fmin(.76,pArr+.06);
    double pDur=.22;
    if(p<=pStart) {
        double s=.94;
        return (WXGMenuRowPose){0.,s,s,(1.-s)*halfWidth+12.0,0.,0.};
    }
    double u=WXGMenuEaseOut(WXGMenuClamp((p-pStart)/pDur,0.,1.));
    double s=.94+.06*u;
    double dx=(1.-s)*halfWidth+12.0*(1.-u);
    return (WXGMenuRowPose){u,s,s,dx,0.,0.};
}

/* ---- Legacy Time-Based Wrappers (synced to the unified progress engine) - */
static inline double WXGMenuRingStrokeAt(int open,double t,double speed) {
    double dur=open?WXGMenuOpenDuration(speed):WXGMenuCloseDuration(speed);
    double p=WXGMenuClamp(t/fmax(dur,1e-4),0.,1.);
    return WXGMenuArcStrokeForProgress(open?p:(1.-p));
}
static inline WXGMenuSymbolPose WXGMenuSymbolPoseAt(int open,double t,double speed) {
    double dur=open?WXGMenuOpenDuration(speed):WXGMenuCloseDuration(speed);
    double p=WXGMenuClamp(t/fmax(dur,1e-4),0.,1.);
    return WXGMenuSymbolForProgress(open?p:(1.-p));
}
static inline double WXGMenuDotDetachAt(int idx,int count,double stagger) {
    (void)stagger;
    return WXGMenuDotDetachProgress(idx,count)*WXGMenuOpenDuration(1.);
}
static inline double WXGMenuDotArriveAt(int idx,int count,double stagger) {
    return WXGMenuDotArriveProgress(idx,count,stagger)*WXGMenuOpenDuration(1.);
}
static inline WXGMenuParticle WXGMenuDotMorphPoseAt(int idx,int count,int open,double t,double speed,double stagger,
    double plusMidX,double plusMidY,double buttonSize,double targetX,double targetY) {
    double dur=open?WXGMenuOpenDuration(speed):WXGMenuCloseDuration(speed);
    double p=WXGMenuClamp(t/fmax(dur,1e-4),0.,1.);
    return WXGMenuDotForProgress(idx,count,open?p:(1.-p),stagger,plusMidX,plusMidY,buttonSize,targetX,targetY);
}
static inline WXGMenuParticle WXGMenuParticlePoseAt(int idx,int open,double t,double speed,
    double plusMidX,double plusMidY,double ringRadius,double lastRowMidY) {
    double size=WXGMenuClamp(ringRadius/.340,30.,60.);
    double span=fmax(lastRowMidY-(plusMidY+ringRadius),48.);
    double rowY=plusMidY+ringRadius+span*((double)(idx+1)/(double)WXGMenuParticleCount);
    return WXGMenuDotMorphPoseAt(idx,WXGMenuParticleCount,open,t,speed,.045,plusMidX,plusMidY,size,plusMidX,rowY);
}

/* ---- Legacy Entrance/Exit Structs (for dump.c / tools compatibility) ---- */
typedef struct { double stiffness,damping,mass; } WXGMenuSpring;
typedef struct {
    double iconDelay,capsuleDelay,textDelay;
    double iconDuration,capsuleDuration;
    double iconFade,capsuleFade,textFade;
    double iconBlurStart;
    WXGMenuSpring iconSpring,capsuleSpring;
    double iconScale,capsuleScaleX,capsuleScaleY;
    double travel;
    double capsuleShift;
    double textShift;
} WXGMenuEntrance;

static inline WXGMenuEntrance WXGMenuEntranceForCount(int index,int count,double slotDistance,double stagger,double speed) {
    (void)slotDistance;
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double dur=WXGMenuOpenDuration(v);
    double pArr=WXGMenuDotArriveProgress(index,count>0?count:WXGMenuParticleCount,stagger);
    WXGMenuEntrance e;
    e.iconDelay=fmax(0.,pArr-.04)*dur;
    e.iconDuration=.22*dur;
    e.iconFade=e.iconDuration;
    e.iconBlurStart=9.0;
    e.capsuleDelay=fmin(.76,pArr+.06)*dur;
    e.textDelay=e.capsuleDelay;
    e.capsuleDuration=.22*dur;
    e.capsuleFade=e.capsuleDuration;
    e.textFade=e.capsuleDuration;
    e.iconSpring=(WXGMenuSpring){400.*v*v,40.*v,1.};
    e.capsuleSpring=(WXGMenuSpring){480.*v*v,44.*v,1.};
    e.iconScale=.62;
    e.capsuleScaleX=.94;
    e.capsuleScaleY=.94;
    e.travel=0.;
    e.capsuleShift=12.;
    e.textShift=0.;
    return e;
}
static inline WXGMenuEntrance WXGMenuEntranceFor(int index,double slotDistance,double stagger,double speed) {
    return WXGMenuEntranceForCount(index,WXGMenuParticleCount,slotDistance,stagger,speed);
}

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

static inline WXGMenuPose WXGMenuIconPoseAt(const WXGMenuEntrance *e,double t) {
    double p=WXGMenuEaseOut((t-e->iconDelay)/fmax(e->iconDuration,1e-4));
    double a=WXGMenuEaseOut((t-e->iconDelay)/fmax(e->iconFade,1e-4));
    double s=e->iconScale+(1.-e->iconScale)*p;
    return (WXGMenuPose){a,s,s,0.,-e->travel*(1.-p),0.,0.};
}

static inline WXGMenuPose WXGMenuCapsulePoseAt(const WXGMenuEntrance *e,double t,double halfWidth) {
    double p=WXGMenuEaseOut((t-e->capsuleDelay)/fmax(e->capsuleDuration,1e-4));
    double a=WXGMenuEaseOut((t-e->capsuleDelay)/fmax(e->capsuleFade,1e-4));
    double s=e->capsuleScaleX+(1.-e->capsuleScaleX)*p;
    double dx=(1.-s)*halfWidth+e->capsuleShift*(1.-p);
    return (WXGMenuPose){a,s,s,dx,0.,a,0.};
}

static inline double WXGMenuTotalDuration(int count,double rowPitch,double stagger,double speed) {
    (void)count;(void)rowPitch;(void)stagger;
    return WXGMenuOpenDuration(speed);
}

typedef struct {
    double iconDelay,capsuleDelay,textDelay;
    double iconDuration,capsuleDuration,textDuration;
    double iconFade,capsuleFade;
    double iconBlurEnd;
    double iconScale,capsuleScaleX,capsuleScaleY;
    double travel;
    double capsuleShift;
    double textShift;
} WXGMenuExit;

static inline WXGMenuExit WXGMenuExitFor(int order,double slotDistance,double stagger,double speed) {
    (void)slotDistance;(void)stagger;
    double dur=WXGMenuCloseDuration(speed);
    int o=order<0?0:order;
    WXGMenuExit e;
    e.capsuleDelay=0.;
    e.textDelay=0.;
    e.capsuleDuration=.22*dur;
    e.capsuleFade=e.capsuleDuration;
    e.textDuration=e.capsuleDuration;
    e.iconDelay=(.06+.04*(double)o)*dur;
    e.iconDuration=.22*dur;
    e.iconFade=e.iconDuration;
    e.iconBlurEnd=9.0;
    e.iconScale=.62;
    e.capsuleScaleX=.94;
    e.capsuleScaleY=.94;
    e.travel=0.;
    e.capsuleShift=12.;
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

static inline double WXGMenuExitDuration(int count,double rowPitch,double stagger,double speed) {
    (void)count;(void)rowPitch;(void)stagger;
    return WXGMenuCloseDuration(speed);
}
#endif
