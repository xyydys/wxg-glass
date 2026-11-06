#ifndef WXG_MENU_CASCADE_H
#define WXG_MENU_CASCADE_H
#include <math.h>

/* FIX116 A (user, 10-29: the home page's "+" menu as in his reference video
   (a glass capsule with the title on the left, a round glass icon on the right
   in line with the "+"), but "the flip is ugly, design the entrance again").

   Pure geometry and timing, no UIKit: WXGDecorations.m builds the Core
   Animation springs from these numbers, Tests/MenuCascadeTests.c checks them,
   and tools/menu_cascade_preview.py draws the same curves.

   The entrance (nothing turns over; every row only appears and settles):
     * rows start top to bottom, each a little sooner after the one before
       (a quick, slowing cascade, not a metronome);
     * the round icon leads: it fades in while it grows from 0.56 and drops
       into its slot from a little above it (further for the lower rows, as
       if the list unfolded out of the "+");
     * the capsule follows 35 ms later and opens out of the icon: its right
       edge (the side next to the icon) stays put while it widens from 0.38,
       so it looks pulled out of the bubble;
     * the title fades in last, once the capsule is wide enough not to squash
       it, sliding the last few points out from the icon. */

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
    return (WXGMenuMetrics){icon,height,floor(height*.47*2)/2,round(icon*.2),round(height*.5)};
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

/* ---- timing ------------------------------------------------------------ */
typedef struct { double stiffness,damping,mass; } WXGMenuSpring;
typedef struct {
    double iconDelay,capsuleDelay,textDelay;    /* seconds after the menu is shown */
    double iconFade,capsuleFade,textFade;       /* opacity 0 -> 1, ease out */
    WXGMenuSpring iconSpring,capsuleSpring;
    double iconScale,capsuleScaleX,capsuleScaleY;   /* where the springs start (they end at 1) */
    double travel;                                  /* pt a row starts above its slot */
    double textShift;                               /* pt the title starts toward the icon */
} WXGMenuEntrance;

/* Row `index` of `count`. `stagger` is the first gap in seconds (each later one
   is 0.9 of the one before); `speed` scales every time (1 = as designed, springs
   keep their damping ratio). `slotDistance` is how far the row's slot is below
   the "+" (the lower rows start further above theirs, up to 54 pt). */
static inline WXGMenuEntrance WXGMenuEntranceFor(int index,double slotDistance,double stagger,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1,.5,2);
    double gap=WXGMenuClamp(isfinite(stagger)?stagger:.034,0,.12);
    int i=index<0?0:index;
    double rowDelay=gap*(1-pow(.9,i))/.1/v;
    WXGMenuEntrance e;
    e.iconDelay=rowDelay;e.capsuleDelay=rowDelay+.035/v;e.textDelay=e.capsuleDelay+.085/v;
    e.iconFade=.22/v;e.capsuleFade=.26/v;e.textFade=.20/v;
    e.iconSpring=(WXGMenuSpring){380*v*v,29*v,1};
    e.capsuleSpring=(WXGMenuSpring){330*v*v,27*v,1};
    e.iconScale=.56;e.capsuleScaleX=.38;e.capsuleScaleY=.80;
    e.travel=WXGMenuClamp((isfinite(slotDistance)?slotDistance:0)*.32,10,54);
    e.textShift=10;
    return e;
}

/* A spring started at rest from 0 toward 1 (the closed form Core Animation's
   CASpringAnimation follows with initialVelocity 0): 1 = arrived. It may pass 1. */
static inline double WXGMenuSpringProgress(WXGMenuSpring s,double t) {
    if(!(t>0))return 0;
    double m=fmax(s.mass,1e-6),k=fmax(s.stiffness,1e-6),c=fmax(s.damping,0);
    double w0=sqrt(k/m),z=c/(2*sqrt(k*m));
    if(z<1) {
        double wd=w0*sqrt(1-z*z);
        return 1-exp(-z*w0*t)*(cos(wd*t)+z*w0/wd*sin(wd*t));
    }
    if(z==1)return 1-exp(-w0*t)*(1+w0*t);
    double r=w0*sqrt(z*z-1),a=-z*w0+r,b=-z*w0-r;   /* a, b < 0 */
    return 1-(a*exp(b*t)-b*exp(a*t))/(a-b);
}
/* Seconds until the spring stays within `threshold` of 1. */
static inline double WXGMenuSpringSettle(WXGMenuSpring s,double threshold) {
    double t=0,last=0;
    for(int k=1;k<=4000;k++) {
        t=k*.002;
        if(fabs(WXGMenuSpringProgress(s,t)-1)>threshold)last=t;
    }
    return last+.002;
}
static inline double WXGMenuEaseOut(double u) {
    u=WXGMenuClamp(u,0,1);double v=1-u;return 1-v*v*v;
}

typedef struct { double alpha,scaleX,scaleY,dx,dy,textAlpha,textDx; } WXGMenuPose;
/* The icon at `t` seconds after the menu is shown (the pose before the end is
   relative to its slot; at rest: alpha 1, scale 1, no offset). */
static inline WXGMenuPose WXGMenuIconPoseAt(const WXGMenuEntrance *e,double t) {
    double p=WXGMenuSpringProgress(e->iconSpring,t-e->iconDelay);
    double s=e->iconScale+(1-e->iconScale)*p;
    return (WXGMenuPose){WXGMenuEaseOut((t-e->iconDelay)/e->iconFade),s,s,0,-e->travel*(1-p),0,0};
}
/* The capsule, `halfWidth` being half its width: its right edge stays where it
   will end, so it opens toward the left. */
static inline WXGMenuPose WXGMenuCapsulePoseAt(const WXGMenuEntrance *e,double t,double halfWidth) {
    double p=WXGMenuSpringProgress(e->capsuleSpring,t-e->capsuleDelay);
    double sx=e->capsuleScaleX+(1-e->capsuleScaleX)*p,sy=e->capsuleScaleY+(1-e->capsuleScaleY)*p;
    double q=WXGMenuEaseOut((t-e->textDelay)/e->textFade);
    return (WXGMenuPose){WXGMenuEaseOut((t-e->capsuleDelay)/e->capsuleFade),sx,sy,(1-sx)*halfWidth,-e->travel*(1-p),q,e->textShift*(1-q)};
}
/* When everything of `count` rows has arrived (springs within 0.5 %). */
static inline double WXGMenuTotalDuration(int count,double rowPitch,double stagger,double speed) {
    double end=0;
    for(int i=0;i<count;i++) {
        WXGMenuEntrance e=WXGMenuEntranceFor(i,(i+1)*rowPitch,stagger,speed);
        double a=e.iconDelay+WXGMenuSpringSettle(e.iconSpring,.005);
        double b=e.capsuleDelay+WXGMenuSpringSettle(e.capsuleSpring,.005);
        double c=e.textDelay+e.textFade;
        end=fmax(end,fmax(a,fmax(b,c)));
    }
    return end;
}
/* ---- the exit (FIX116 B) ---------------------------------------------------
   User, 10-29: closing by the "+" again made the menu jump down and vanish; it
   should leave the way it came ("a reversed entrance"), by tapping elsewhere
   too. It leaves in the entrance's order reversed and quicker, ease-in (a
   leaving thing speeds up, it does not settle):
     * the lowest row starts, each row above it a little later;
     * a row's title fades first, the capsule folds back into its icon (right
       edge fixed, narrower and a little flatter, fading), then the icon
       shrinks and rises toward the "+" (the lower the row the further);
     * no springs, nothing overshoots, nothing turns over.
   About 0.3 s for 4-6 rows (the entrance's 0.57 s is the opening's: closing is
   what the person already decided, it must not make them wait). */
typedef struct {
    double iconDelay,capsuleDelay,textDelay;
    double iconDuration,capsuleDuration,textDuration;   /* motion; the fades are within them */
    double iconFade,capsuleFade;                        /* opacity 1 -> 0 (the title's is its duration) */
    double iconScale,capsuleScaleX,capsuleScaleY;       /* where the motion ends (it starts at the pose it is in) */
    double travel;                                      /* pt the icon and capsule rise */
    double textShift;                                   /* pt the title slides toward the icon */
} WXGMenuExit;

/* `order` 0 is the first row to leave (the lowest). */
static inline WXGMenuExit WXGMenuExitFor(int order,double slotDistance,double stagger,double speed) {
    double v=WXGMenuClamp(isfinite(speed)?speed:1,.5,2);
    double gap=WXGMenuClamp(isfinite(stagger)?stagger:.034,0,.12)*.55;
    int o=order<0?0:order;
    double rowDelay=gap*o/v;
    WXGMenuExit e;
    e.textDelay=rowDelay;e.capsuleDelay=rowDelay+.015/v;e.iconDelay=rowDelay+.04/v;
    e.textDuration=.10/v;e.capsuleDuration=.20/v;e.iconDuration=.20/v;
    e.capsuleFade=.17/v;e.iconFade=.16/v;
    e.iconScale=.60;e.capsuleScaleX=.42;e.capsuleScaleY=.84;
    e.travel=WXGMenuClamp((isfinite(slotDistance)?slotDistance:0)*.22,8,38);
    e.textShift=6;
    return e;
}
/* Ease-in: slow start, fast end (cubic). */
static inline double WXGMenuEaseIn(double u) { u=WXGMenuClamp(u,0,1);return u*u*u; }

/* The poses `t` seconds after the exit begins, from rest (alpha 1, scale 1, no
   offset); `halfWidth` is half the capsule's width. */
static inline WXGMenuPose WXGMenuExitIconPoseAt(const WXGMenuExit *e,double t) {
    double p=WXGMenuEaseIn((t-e->iconDelay)/e->iconDuration),f=WXGMenuEaseIn((t-e->iconDelay)/e->iconFade);
    double s=1+(e->iconScale-1)*p;
    return (WXGMenuPose){1-f,s,s,0,-e->travel*p,0,0};
}
static inline WXGMenuPose WXGMenuExitCapsulePoseAt(const WXGMenuExit *e,double t,double halfWidth) {
    double p=WXGMenuEaseIn((t-e->capsuleDelay)/e->capsuleDuration),f=WXGMenuEaseIn((t-e->capsuleDelay)/e->capsuleFade);
    double q=WXGMenuEaseIn((t-e->textDelay)/e->textDuration);
    double sx=1+(e->capsuleScaleX-1)*p,sy=1+(e->capsuleScaleY-1)*p;
    return (WXGMenuPose){1-f,sx,sy,(1-sx)*halfWidth,-e->travel*p,1-q,e->textShift*q};
}
/* When the last of `count` rows is gone. */
static inline double WXGMenuExitDuration(int count,double rowPitch,double stagger,double speed) {
    double end=0;
    for(int i=0;i<count;i++) {
        WXGMenuExit e=WXGMenuExitFor(i,(count-i)*rowPitch,stagger,speed);
        end=fmax(end,fmax(e.iconDelay+e.iconDuration,fmax(e.capsuleDelay+e.capsuleDuration,e.textDelay+e.textDuration)));
    }
    return end;
}
#endif
