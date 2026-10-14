#include <assert.h>
#include <stdio.h>
#include "../Sources/WXGBackdropTraversal.h"
int main(void) {
    WXGROIRect full={0,0,440,956},cell={0,780,440,96};
    double screen=440.*956;
    /* Actual slow node: clipping 18.8% of its area must split the full-screen
       navigation wrapper instead of issuing the same 35ms UIKit read. */
    assert(WXGBackdropNeedsSpatialSplit(full,screen*.188,screen,1,1,0,1));
    assert(WXGBackdropNeedsSpatialSplit(full,screen*.188,screen,1,1,1,0));
    assert(WXGBackdropNeedsSpatialSplit(full,screen*.188,screen,1,1,0,0));
    assert(!WXGBackdropNeedsSpatialSplit(cell,440.*50,screen,1,1,0,0));
    /* Video, custom layer effects, masks, and independently painted containers
       retain the original native read even when they cover the whole screen. */
    assert(!WXGBackdropNeedsSpatialSplit(full,screen*.1,screen,1,0,1,1));
    assert(!WXGBackdropNeedsSpatialSplit(full,screen*.1,screen,0,1,1,1));
    assert(!WXGBackdropNeedsSpatialSplit(full,NAN,screen,1,1,1,1));
    /* Bounds.origin is contentOffset, not zero; validate translated, scaled,
       and rotated wrappers before source-space ROI culling. */
    WXGROIRect scrolled={3,700,440,956};
    WXGROIRect a=WXGBackdropTransformedBounds(scrolled,(WXGSourceTransform){1,0,0,1,-3,-700});
    assert(fabs(a.x)<1e-9&&fabs(a.y)<1e-9&&fabs(a.w-440)<1e-9&&fabs(a.h-956)<1e-9);
    WXGROIRect b=WXGBackdropTransformedBounds((WXGROIRect){0,0,40,80},(WXGSourceTransform){0,1,-1,0,100,200});
    assert(b.x==20&&b.y==200&&b.w==80&&b.h==40);
    WXGROISet coverage={.rects={{0,0,440,90},{0,820,440,136}},.count=2};
    assert(!WXGROIIntersects(&coverage,(WXGROIRect){0,300,440,80}));
    assert(WXGROIIntersects(&coverage,(WXGROIRect){0,790,440,80}));
    puts("Backdrop traversal policy: spatial pruning, atomic media, scrolling and rotated bounds PASS");
}
