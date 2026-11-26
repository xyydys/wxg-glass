#ifndef WXG_MENU_SCRUB_H
#define WXG_MENU_SCRUB_H

#include "WXGMenuMorph.h"

/* GlassMenuSession.kt and GlassJelly.kt, xyydys/expo-glass-custom-menu
 * 0021efd8ab0d; MIT notice in WXGMenuMorph.h. Distances here are points.
 * Touch destinations stay in the resting menu's coordinate system. */
typedef struct {
    WXGMenuMorphSpring top,height,alpha,dragX,dragY,lightX,lightY,glow;
    double startX,startY;
    bool touching,selected;
} WXGMenuScrub;

static inline WXGMenuScrub WXGMenuScrubInitial(double displayScale) {
    // Android's absolute position/velocity tolerances are in device pixels.
    double scale=fmax(1.,displayScale);
    WXGMenuMorphSpring position={.valueTolerance=.25/scale,.velocityTolerance=8./scale};
    WXGMenuMorphSpring follow={.valueTolerance=.3/scale,.velocityTolerance=6./scale};
    return (WXGMenuScrub){.top=position,.height=position,.alpha={.valueTolerance=.004,.velocityTolerance=.05},
        .dragX=follow,.dragY=follow,.lightX=follow,.lightY=follow,.glow={.valueTolerance=.002,.velocityTolerance=.02}};
}

static inline void WXGMenuScrubResetSpring(WXGMenuMorphSpring *s,double value) {
    s->target=value;
    WXGMenuMorphSpringFinish(s);
}

static inline void WXGMenuScrubDown(WXGMenuScrub *s,double x,double y) {
    s->touching=true;s->startX=x;s->startY=y;
    if(s->glow.value<.02) {
        WXGMenuScrubResetSpring(&s->lightX,x);
        WXGMenuScrubResetSpring(&s->lightY,y);
    }else {
        WXGMenuMorphSpringTarget(&s->lightX,x,(WXGMenuMorphSpec){.8,.16});
        WXGMenuMorphSpringTarget(&s->lightY,y,(WXGMenuMorphSpec){.8,.16});
    }
    WXGMenuMorphSpringTarget(&s->glow,1.,(WXGMenuMorphSpec){1.,.1});
}

static inline void WXGMenuScrubMove(WXGMenuScrub *s,double x,double y) {
    if(!s->touching)return;
    WXGMenuMorphSpringTarget(&s->dragX,x-s->startX,(WXGMenuMorphSpec){.65,.18});
    WXGMenuMorphSpringTarget(&s->dragY,y-s->startY,(WXGMenuMorphSpec){.65,.18});
    WXGMenuMorphSpringTarget(&s->lightX,x,(WXGMenuMorphSpec){.8,.16});
    WXGMenuMorphSpringTarget(&s->lightY,y,(WXGMenuMorphSpec){.8,.16});
}

static inline void WXGMenuScrubRelease(WXGMenuScrub *s) {
    s->touching=false;
    WXGMenuMorphSpringTarget(&s->dragX,0.,(WXGMenuMorphSpec){.5,.45});
    WXGMenuMorphSpringTarget(&s->dragY,0.,(WXGMenuMorphSpec){.5,.45});
    WXGMenuMorphSpringTarget(&s->glow,0.,(WXGMenuMorphSpec){1.,.5});
}

/* Call on a change of row; the first down snaps, crossing retargets while
 * preserving velocity, and re-entering after leaving starts at the new row. */
static inline void WXGMenuScrubSelect(WXGMenuScrub *s,double top,double height,bool immediate) {
    if(!s->selected) {
        WXGMenuScrubResetSpring(&s->top,top);
        WXGMenuScrubResetSpring(&s->height,height);
    }else {
        WXGMenuMorphSpringTarget(&s->top,top,(WXGMenuMorphSpec){.85,.13});
        WXGMenuMorphSpringTarget(&s->height,height,(WXGMenuMorphSpec){.85,.13});
    }
    s->selected=true;
    if(immediate)WXGMenuScrubResetSpring(&s->alpha,1.);
    else WXGMenuMorphSpringTarget(&s->alpha,1.,(WXGMenuMorphSpec){1.,.14});
}

static inline void WXGMenuScrubClear(WXGMenuScrub *s) {
    s->selected=false;
    WXGMenuMorphSpringTarget(&s->alpha,0.,(WXGMenuMorphSpec){1.,.14});
}

static inline bool WXGMenuScrubAdvance(WXGMenuScrub *s,double dt,bool reduceMotion) {
    WXGMenuMorphSpring *const springs[]={&s->top,&s->height,&s->alpha,&s->dragX,&s->dragY,&s->lightX,&s->lightY,&s->glow};
    bool settled=true;
    for(unsigned i=0;i<sizeof springs/sizeof springs[0];i++) {
        if(reduceMotion)WXGMenuMorphSpringFinish(springs[i]);
        else WXGMenuMorphSpringAdvance(springs[i],dt);
        if(!WXGMenuMorphSpringSettled(springs[i]))settled=false;
    }
    return settled;
}

static inline WXGMenuBox WXGMenuScrubBounds(WXGMenuBox bounds,const WXGMenuScrub *s,bool fromRight,bool above) {
    double x=tanh(s->dragX.value/260.),y=tanh(s->dragY.value/260.);
    double awayX=fromRight?-x:x,awayY=above?-y:y;
    double width=fmax(1.,bounds.w+16.*awayX-21.*awayY);
    double height=fmax(1.,bounds.h+16.*awayY-21.*awayX);
    return WXGMenuMorphCenteredBox(WXGMenuMorphCenterX(bounds)+21.*x,WXGMenuMorphCenterY(bounds)+21.*y,width,height);
}

#endif
