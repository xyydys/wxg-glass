#ifndef WXG_BACKDROP_TRAVERSAL_H
#define WXG_BACKDROP_TRAVERSAL_H
#include "WXGBackdropROI.h"
/* CA paints siblings in sublayers order, except for zPosition. Stable ties
   preserve that order (UIView.subviews can differ after native reordering). */
static inline int WXGBackdropCompareZ(double a,double b) {
    if(!isfinite(a))a=0;
    if(!isfinite(b))b=0;
    return a<b?-1:a>b?1:0;
}
/* Split spatial containers BEFORE asking UIKit to read pixels. A CGContext clip
   alone still asks the native compositor to snapshot the entire navigation tree.
   Atomic media/effect/custom-paint branches are never reconstructed. */
static inline int WXGBackdropNeedsSpatialSplit(WXGROIRect bounds,double coveredArea,double viewportArea,
                                              int hasChildren,int safeContainer,int scrollContainer,int navigationWrapper) {
    if(!hasChildren || !safeContainer || !WXGROIValid(bounds) || !isfinite(coveredArea+viewportArea))return 0;
    if(scrollContainer || navigationWrapper)return 1;
    double area=bounds.w*bounds.h;
    return viewportArea>0 && area>viewportArea*.18 && coveredArea<area*.72;
}
/* AABB is only an early conservative rejection. Actual descendant clipping is
   performed with the transformed native bounds/corner path in CGContext. */
static inline WXGROIRect WXGBackdropTransformedBounds(WXGROIRect bounds,WXGSourceTransform t) {
    double x[4]={bounds.x,bounds.x+bounds.w,bounds.x,bounds.x+bounds.w};
    double y[4]={bounds.y,bounds.y,bounds.y+bounds.h,bounds.y+bounds.h};
    double loX=INFINITY,loY=INFINITY,hiX=-INFINITY,hiY=-INFINITY;
    for(int i=0;i<4;i++){double xx=t.a*x[i]+t.c*y[i]+t.tx,yy=t.b*x[i]+t.d*y[i]+t.ty;
        loX=fmin(loX,xx);hiX=fmax(hiX,xx);loY=fmin(loY,yy);hiY=fmax(hiY,yy);}
    return (WXGROIRect){loX,loY,hiX-loX,hiY-loY};
}
#endif
