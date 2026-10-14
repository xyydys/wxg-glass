#ifndef WXG_SOURCE_MAPPING_H
#define WXG_SOURCE_MAPPING_H
#include <math.h>
typedef struct { double a,b,c,d,tx,ty; } WXGSourceTransform;
/* Source-space basis of local (0,0), (1,0), (0,1). Copy pixels through
   the inverse, so deforming a button does not slide its backdrop sideways. */
static inline int WXGSourceInverse(double ox,double oy,double xx,double xy,double yx,double yy,
                                  WXGSourceTransform *out) {
    double a=xx-ox,b=xy-oy,c=yx-ox,d=yy-oy,det=a*d-b*c;
    if(!out || !isfinite(ox+oy+a+b+c+d+det) || fabs(det)<1e-8)return 0;
    *out=(WXGSourceTransform){d/det,-b/det,-c/det,a/det,(c*oy-d*ox)/det,(b*ox-a*oy)/det};
    return 1;
}
typedef struct {float x[4],y[4],origin[4];} WXGCopyUniforms;
/* Shared page texture -> local full-resolution canvas, in pixel-centre UVs.
   Presentation translation/scale must be supplied, not animation endpoints. */
static inline int WXGMakeCopyUniforms(WXGSourceTransform t,double scale,
                                     double rx,double ry,double rw,double rh,WXGCopyUniforms *u) {
    if(!u || !isfinite(t.a+t.b+t.c+t.d+t.tx+t.ty+scale+rx+ry+rw+rh) || scale<=0 || rw<=0 || rh<=0)return 0;
    *u=(WXGCopyUniforms){{t.a/(scale*rw),t.b/(scale*rh),0,0},
        {t.c/(scale*rw),t.d/(scale*rh),0,0},{(t.tx-rx)/rw,(t.ty-ry)/rh,0,0}};
    return 1;
}
#endif
