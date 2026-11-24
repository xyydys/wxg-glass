#ifndef WXG_MENU_CASCADE_H
#define WXG_MENU_CASCADE_H
#include <math.h>

/* Home "+" floating menu — 5-track ink-drop particle disintegration / aggregation
   motion engine (pure C geometry & timing, no UIKit):
     Track 1 (Trigger Ring):  270 deg solid arc (135 deg -> 45 deg CW) + 5 bottom
                              dots (54..126 deg); retracts CCW in 150ms on open,
                              grows CW in 30..250ms on close.
     Track 2 (Center Glyph):  Two-stage scale swap (+ <-> x) with zero bounce:
                              shrinks to 0.45, swaps instantaneously at trough
                              (250ms open / 180ms close), recovers smoothly to 1.0.
     Track 3 (Ink Particles): 5 organic ink drops bound 1:1 to the 5 bottom dots;
                              gather at 6:00 and fall along sine-wiggle trail
                              (50..550ms open), respawn at bottom and sweep up to
                              dock precisely back into the 5 ring dots (0..350ms close).
     Track 4 (Glass Icons):   Staggered vertical release (130 + stagger*k ms, 220ms)
                              with strictly monotonic zero-overshoot ease-out
                              (no post-expand bounce!); collective acceleration
                              straight into the "+" centre on close (20..230ms).
     Track 5 (Glass Capsules):Delayed horizontal reveal (+100ms after icon, 150ms,
                              zero vertical travel, right-middle anchored); priority
                              synchronous 100ms exit at t=0 on close. */

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

/* ---- cubic bezier & easing (zero-overshoot monotonic curves) ----------- */
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

/* ---- Track 1 & Track 2: trigger button ring, 5 bottom dots & +/x swap -- */
enum { WXGMenuParticleCount = 5 };

/* Outer ring radius for a circular glass trigger button of diameter `size` (~18.3pt at 44pt). */
static inline double WXGMenuRingRadius(double size) {
    return WXGMenuClamp(size*.415,10.,26.);
}
/* 5 bottom gap dots symmetrically placed in the 90-deg bottom opening (45..135 deg):
   58, 74, 90, 106, 122 deg (radians, UIKit y-down where pi/2 = 6:00), giving
   visually even clear spacing between the round arc caps and adjacent dots. */
static inline double WXGMenuRingDotAngle(int idx) {
    if(idx<0)idx=0;
    if(idx>=WXGMenuParticleCount)idx=WXGMenuParticleCount-1;
    return (58.+16.*(double)idx)*(3.14159265358979323846/180.);
}
static inline double WXGMenuRingDotDiameter(void) { return 2.5; }

/* Track 1 strokeEnd at `t` seconds:
   open:  1.0 -> 0.0 over 0..150ms (cubic-bezier 0.4, 0, 1, 1)
   close: 0.0 -> 1.0 over 30..250ms (cubic-bezier 0.22, 1, 0.36, 1) */
static inline double WXGMenuRingStrokeAt(int open,double t,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double ts=t*v;
    if(open) {
        if(ts<=0.)return 1.;
        if(ts>=.150)return 0.;
        return 1.-WXGMenuCubicBezier(ts/.150,.4,0.,1.,1.);
    }
    if(ts<=.030)return 0.;
    if(ts>=.250)return 1.;
    return WXGMenuCubicBezier((ts-.030)/.220,.22,1.,.36,1.);
}

/* Track 2 center glyph (+ <-> x) pose at `t` seconds (zero overshoot / no bounce):
   open:  0..250ms + scales 1.0->0.45, instant swap to x (pi/4) at 250ms, 250..400ms scales 0.45->1.0
   close: 0..180ms x scales 1.0->0.45, instant swap to + (0) at 180ms, 180..350ms scales 0.45->1.0 */
typedef struct { double scale,rotationRad; int isClose; } WXGMenuSymbolPose;
static inline WXGMenuSymbolPose WXGMenuSymbolPoseAt(int open,double t,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double ts=t*v;
    const double pi4=0.78539816339744830962;
    if(open) {
        if(ts<.250) {
            double u=WXGMenuCubicBezier(WXGMenuClamp(ts/.250,0.,1.),.4,0.,.6,1.);
            return (WXGMenuSymbolPose){1.-.55*u,0.,0};
        }
        double u=WXGMenuEaseOut((ts-.250)/.150);
        return (WXGMenuSymbolPose){.45+.55*u,pi4,1};
    }
    if(ts<.180) {
        double u=WXGMenuCubicBezier(WXGMenuClamp(ts/.180,0.,1.),.4,0.,.6,1.);
        return (WXGMenuSymbolPose){1.-.55*u,pi4,1};
    }
    double u=WXGMenuEaseOut((ts-.180)/.170);
    return (WXGMenuSymbolPose){.45+.55*u,0.,0};
}

/* ---- Track 3: 5 ink-drop particles bound 1:1 to bottom dots ------------ */
typedef struct { double x,y,diameter,alpha; } WXGMenuParticle;

/* Evaluates particle `idx` (0..4, matching bottom dots 54..126 deg) at `t` seconds.
   `plusMidX, plusMidY` is the trigger button's centre; `ringRadius` is its outer
   arc radius; `lastRowMidY` is the bottom-most menu icon's vertical centre. */
static inline WXGMenuParticle WXGMenuParticlePoseAt(int idx,int open,double t,double speed,
    double plusMidX,double plusMidY,double ringRadius,double lastRowMidY) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double ts=t*v;
    if(idx<0)idx=0;
    if(idx>=WXGMenuParticleCount)idx=WXGMenuParticleCount-1;
    const double twoPi=6.28318530717958647692;
    const double halfPi=1.57079632679489661923;
    double angle=WXGMenuRingDotAngle(idx);
    double dotX=plusMidX+ringRadius*cos(angle);
    double dotY=plusMidY+ringRadius*sin(angle);
    double gatherY=plusMidY+ringRadius;
    double dotDiam=WXGMenuRingDotDiameter();
    double dropSpan=fmax(lastRowMidY-gatherY,48.);

    /* Departure order: centre dot (2) leads with largest drop, flanked by 1,3 then 0,4. */
    static const int orderMap[5]={3,1,0,2,4};
    static const double peakDiams[5]={5.2,8.2,10.5,7.0,3.8};
    static const double peakAlphas[5]={0.52,0.78,0.92,0.68,0.38};
    static const double ampX[5]={7.2,8.5,9.5,6.8,6.0};
    static const double phaseX[5]={0.65,0.25,0.0,-0.35,-0.80};
    static const double reachScale[5]={0.88,0.96,1.02,0.93,0.82};
    int ord=orderMap[idx];

    if(open) {
        if(ts<=0.)return (WXGMenuParticle){dotX,dotY,dotDiam,1.};
        /* 0..50ms: gather along bottom arc toward 6:00 (pi/2). */
        double depart=.050+.028*(double)ord;
        if(ts<depart) {
            double g=WXGMenuEaseInOut(ts/fmax(depart,.01));
            double a=angle+(halfPi-angle)*g;
            return (WXGMenuParticle){plusMidX+ringRadius*cos(a),plusMidY+ringRadius*sin(a),dotDiam+.5*g,1.};
        }
        /* 50..550ms: organic sine-wiggle vertical fall, swell mid-flight, shrink & fade after p=0.72. */
        double dur=.385;
        double p=(ts-depart)/dur;
        if(p>=1.)return (WXGMenuParticle){plusMidX,gatherY+dropSpan*reachScale[idx],0.,0.};
        double py=WXGMenuCubicBezier(p,.32,.08,.62,1.);
        double y=gatherY+dropSpan*reachScale[idx]*py;
        /* Negative lead sign gives the characteristic initial slight-left sway past #1/#2. */
        double env=sin(3.14159265358979323846*p);
        double x=plusMidX-ampX[idx]*sin(twoPi*p+phaseX[idx])*env;
        double diam,alpha;
        if(p<.22) {
            double u=WXGMenuEaseOut(p/.22);
            diam=dotDiam+.5+(peakDiams[idx]-(dotDiam+.5))*u;
            alpha=1.+(peakAlphas[idx]-1.)*u;
        }else if(p<.72) {
            double u=(p-.22)/.50;
            diam=peakDiams[idx]*(1.-.18*u);
            alpha=peakAlphas[idx]*(1.-.10*u);
        }else {
            double u=(p-.72)/.28;
            double fade=1.-u;
            diam=peakDiams[idx]*.82*fade;
            alpha=peakAlphas[idx]*.90*fade;
        }
        return (WXGMenuParticle){x,y,diam,WXGMenuClamp(alpha,0.,1.)};
    }

    /* Collapse (0..350ms): respawn below last icon, sweep rapidly up into 6:00 by 250ms,
       then dock smoothly along the bottom arc into exact static 5 dot anchors (250..350ms). */
    if(ts<=0.)return (WXGMenuParticle){plusMidX,lastRowMidY+16.,0.,0.};
    if(ts>=.350)return (WXGMenuParticle){dotX,dotY,dotDiam,1.};

    double arrive=.250;
    if(ts<arrive) {
        double spawn=.012*(double)ord;
        if(ts<=spawn)return (WXGMenuParticle){plusMidX,lastRowMidY+16.,0.,0.};
        double p=(ts-spawn)/(arrive-spawn);
        double py=WXGMenuCubicBezier(p,.45,0.,.82,1.);
        double startY=lastRowMidY+16.-6.*(double)ord;
        double y=startY+(gatherY-startY)*py;
        double env=sin(3.14159265358979323846*p);
        double x=plusMidX-ampX[idx]*.85*sin(twoPi*p+phaseX[idx])*env;
        double diam,alpha;
        if(p<.18) {
            double u=WXGMenuEaseOut(p/.18);
            diam=peakDiams[idx]*u;
            alpha=peakAlphas[idx]*u;
        }else {
            double u=(p-.18)/.82;
            diam=peakDiams[idx]+(3.2-peakDiams[idx])*u*u;
            alpha=peakAlphas[idx]+(0.95-peakAlphas[idx])*u;
        }
        return (WXGMenuParticle){x,y,diam,WXGMenuClamp(alpha,0.,1.)};
    }

    /* 250..350ms: fan out from 6:00 along the bottom arc into each dot's exact anchor. */
    double u=WXGMenuEaseOut((ts-arrive)/.100);
    double a=halfPi+(angle-halfPi)*u;
    double x=plusMidX+ringRadius*cos(a);
    double y=plusMidY+ringRadius*sin(a);
    double diam=3.2+(dotDiam-3.2)*u;
    double alpha=0.95+(1.-0.95)*u;
    return (WXGMenuParticle){x,y,diam,alpha};
}

/* ---- Track 4 & Track 5: zero-bounce icon cascade & capsule reveal ------ */
typedef struct { double stiffness,damping,mass; } WXGMenuSpring;
typedef struct {
    double iconDelay,capsuleDelay,textDelay;    /* seconds after the menu is shown */
    double iconDuration,capsuleDuration;        /* zero-overshoot motion durations */
    double iconFade,capsuleFade,textFade;       /* opacity 0 -> 1, ease out */
    WXGMenuSpring iconSpring,capsuleSpring;     /* kept for ABI compat with preview tools */
    double iconScale,capsuleScaleX,capsuleScaleY;
    double travel;                              /* pt an icon starts above its slot (45pt) */
    double capsuleShift;                        /* pt a capsule slides horizontally (+14pt -> 0) */
    double textShift;                           /* 0 (capsule moves text cleanly together) */
} WXGMenuEntrance;

/* Row `index` (0 = top). Spec timing:
   Track 4 (icon):    t_start = 130 + stagger*k (ms), dur = 220ms, ty: -45 -> 0, scale: 0.4 -> 1.0, NO bounce.
   Track 5 (capsule): t_label = 230 + (stagger+5)*k (ms), dur = 150ms, dy: 0, tx: +14 -> 0, scale: 0.92 -> 1.0. */
static inline WXGMenuEntrance WXGMenuEntranceFor(int index,double slotDistance,double stagger,double speed) {
    (void)slotDistance;
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double gap=WXGMenuClamp(isfinite(stagger)?stagger:.045,0.,.080);
    int i=index<0?0:index;
    WXGMenuEntrance e;
    e.iconDelay=(.130+gap*(double)i)/v;
    e.capsuleDelay=(.230+(gap+.005)*(double)i)/v;
    e.textDelay=e.capsuleDelay;
    e.iconDuration=.220/v;
    e.capsuleDuration=.150/v;
    e.iconFade=.180/v;
    e.capsuleFade=.150/v;
    e.textFade=.150/v;
    /* Critically damped values retained only for tool struct compatibility. */
    e.iconSpring=(WXGMenuSpring){400.*v*v,40.*v,1.};
    e.capsuleSpring=(WXGMenuSpring){480.*v*v,44.*v,1.};
    e.iconScale=.40;
    e.capsuleScaleX=.92;
    e.capsuleScaleY=.92;
    e.travel=45.;
    e.capsuleShift=14.;
    e.textShift=0.;
    return e;
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

/* Track 4 icon pose at `t` seconds during expand: strictly monotonic ease-out, ZERO bounce! */
static inline WXGMenuPose WXGMenuIconPoseAt(const WXGMenuEntrance *e,double t) {
    double p=WXGMenuEaseOut((t-e->iconDelay)/fmax(e->iconDuration,1e-4));
    double a=WXGMenuEaseOut((t-e->iconDelay)/fmax(e->iconFade,1e-4));
    double s=e->iconScale+(1.-e->iconScale)*p;
    return (WXGMenuPose){a,s,s,0.,-e->travel*(1.-p),0.,0.};
}

/* Track 5 capsule pose at `t` seconds during expand: zero vertical travel, horizontal slide from right! */
static inline WXGMenuPose WXGMenuCapsulePoseAt(const WXGMenuEntrance *e,double t,double halfWidth) {
    double p=WXGMenuEaseOut((t-e->capsuleDelay)/fmax(e->capsuleDuration,1e-4));
    double a=WXGMenuEaseOut((t-e->capsuleDelay)/fmax(e->capsuleFade,1e-4));
    double s=e->capsuleScaleX+(1.-e->capsuleScaleX)*p;
    double dx=(1.-s)*halfWidth+e->capsuleShift*(1.-p);
    return (WXGMenuPose){a,s,s,dx,0.,a,0.};
}

/* Total expand duration across all 5 tracks (about 0.60s for 5 rows at default stagger/speed). */
static inline double WXGMenuTotalDuration(int count,double rowPitch,double stagger,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double end=.550/v; /* Track 3 particle fade-out */
    for(int i=0;i<count;i++) {
        WXGMenuEntrance e=WXGMenuEntranceFor(i,(i+1)*rowPitch,stagger,speed);
        double a=e.iconDelay+e.iconDuration;
        double b=e.capsuleDelay+e.capsuleDuration;
        end=fmax(end,fmax(a,b));
    }
    return end;
}

/* ---- Collapse (350ms total) --------------------------------------------
   Track 5 (capsules): ALL rows vanish synchronously at t=0 over 100ms (ease-in)
                       before icons begin compressing upward.
   Track 4 (icons):    Collective upward suction starting at t=20ms (+ tiny 4ms
                       reverse offset from bottom) over 210ms straight into the
                       "+" button's centre (dy -> -slotDistance, scale -> 0.35).
   Track 1 & Track 3:  Arc closes 30..250ms; 5 ink drops sweep up and dock at 350ms. */
typedef struct {
    double iconDelay,capsuleDelay,textDelay;
    double iconDuration,capsuleDuration,textDuration;
    double iconFade,capsuleFade;
    double iconScale,capsuleScaleX,capsuleScaleY;
    double travel;          /* full slotDistance straight back into "+" centre */
    double capsuleShift;    /* +8pt right nudge during 100ms fast vanish */
    double textShift;
} WXGMenuExit;

/* `order` 0 is the lowest row (first to start tiny reverse stagger on icon suction). */
static inline WXGMenuExit WXGMenuExitFor(int order,double slotDistance,double stagger,double speed) {
    (void)stagger;
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    int o=order<0?0:order;
    WXGMenuExit e;
    e.capsuleDelay=0.;
    e.textDelay=0.;
    e.capsuleDuration=.100/v;
    e.capsuleFade=.100/v;
    e.textDuration=.100/v;
    e.iconDelay=(.020+.005*(double)o)/v;
    e.iconDuration=.210/v;
    e.iconFade=.185/v;
    e.iconScale=.35;
    e.capsuleScaleX=.95;
    e.capsuleScaleY=.95;
    e.travel=WXGMenuClamp(isfinite(slotDistance)?slotDistance:48.,20.,600.);
    e.capsuleShift=8.;
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

/* Total collapse duration across all 5 tracks (0.35s at speed=1.0). */
static inline double WXGMenuExitDuration(int count,double rowPitch,double stagger,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1.,.5,2.);
    double end=.350/v; /* Track 2 & Track 3 completion */
    for(int i=0;i<count;i++) {
        WXGMenuExit e=WXGMenuExitFor(i,(count-i)*rowPitch,stagger,speed);
        end=fmax(end,fmax(e.iconDelay+e.iconDuration,e.capsuleDelay+e.capsuleDuration));
    }
    return end;
}
#endif
