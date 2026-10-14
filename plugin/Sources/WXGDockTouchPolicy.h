#ifndef WXG_DOCK_TOUCH_POLICY_H
#define WXG_DOCK_TOUCH_POLICY_H
#include <math.h>

typedef struct { double x,y; int valid; } WXGDockTouchPoint;

static inline void WXGDockTouchRemember(WXGDockTouchPoint *point,double x,double y) {
    point->valid=isfinite(x) && isfinite(y);
    point->x=point->valid?x:0;point->y=point->valid?y:0;
}
static inline void WXGDockTouchForget(WXGDockTouchPoint *point) { point->valid=0; }

// A delayed UIKit completion can omit its touch. Use only the current gesture's
// saved location; an explicit invalid location must not reuse a prior good one.
static inline int WXGDockTouchResolve(WXGDockTouchPoint *point,int supplied,int cancelled,double x,double y) {
    if(cancelled){WXGDockTouchForget(point);return 0;}
    if(supplied)WXGDockTouchRemember(point,x,y);
    return point->valid;
}
#endif
