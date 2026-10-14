#include "../Sources/WXGDockTouchPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    WXGDockTouchPoint point={0};
    assert(!WXGDockTouchResolve(&point,0,0,0,0));
    WXGDockTouchRemember(&point,268,838);
    assert(WXGDockTouchResolve(&point,0,0,0,0));
    assert(point.x==268 && point.y==838);

    // Dragging outside before a nil completion retains the outside location.
    WXGDockTouchRemember(&point,-100,-200);
    assert(WXGDockTouchResolve(&point,0,0,0,0));
    assert(point.x==-100 && point.y==-200);

    // Cancellation/long press and completed gestures invalidate saved input.
    WXGDockTouchForget(&point);
    assert(!WXGDockTouchResolve(&point,0,0,0,0));
    WXGDockTouchRemember(&point,100,200);
    assert(WXGDockTouchResolve(&point,1,0,300,400));
    assert(point.x==300 && point.y==400);
    WXGDockTouchForget(&point);
    assert(!WXGDockTouchResolve(&point,0,0,0,0));

    WXGDockTouchRemember(&point,100,200);
    assert(!WXGDockTouchResolve(&point,0,1,0,0));
    assert(!WXGDockTouchResolve(&point,0,0,0,0));
    WXGDockTouchRemember(&point,100,200);
    assert(!WXGDockTouchResolve(&point,1,1,300,400));
    assert(!WXGDockTouchResolve(&point,0,0,0,0));

    WXGDockTouchRemember(&point,100,200);
    assert(!WXGDockTouchResolve(&point,1,0,NAN,200));
    assert(!WXGDockTouchResolve(&point,0,0,0,0));
    WXGDockTouchRemember(&point,INFINITY,200);
    assert(!WXGDockTouchResolve(&point,0,0,0,0));
    WXGDockTouchRemember(&point,30,40);
    assert(WXGDockTouchResolve(&point,0,0,0,0));
    assert(point.x==30 && point.y==40);
    puts("PASS: delayed nil completion retains current touch; outside, canceled, completed and nonfinite locations never revive stale input.");
    return 0;
}
