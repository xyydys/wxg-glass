#ifndef WXG_PRESENTATION_MATH_H
#define WXG_PRESENTATION_MATH_H
#include <math.h>
typedef struct { double x,y; } WXGPoint;
typedef struct { double a,b,c,d,tx,ty; } WXGAffine;
/* Map a corrected glass centre through the native model -> presentation map.
   UIKit still owns the animation clock and interactive cancellation. */
static inline WXGAffine WXGPresentationDelta(WXGPoint model,WXGPoint mx,WXGPoint my,
                                             WXGPoint shown,WXGPoint sx,WXGPoint sy,WXGPoint glass) {
    double ax=mx.x-model.x,ay=mx.y-model.y,bx=my.x-model.x,by=my.y-model.y;
    double cx=sx.x-shown.x,cy=sx.y-shown.y,dx=sy.x-shown.x,dy=sy.y-shown.y;
    double det=ax*by-ay*bx;
    if(!isfinite(det)||fabs(det)<1e-8)return (WXGAffine){1,0,0,1,0,0};
    WXGAffine t={(cx*by-dx*ay)/det,(cy*by-dy*ay)/det,
                 (-cx*bx+dx*ax)/det,(-cy*bx+dy*ax)/det,0,0};
    double x=glass.x-model.x,y=glass.y-model.y;
    t.tx=shown.x-model.x+(t.a-1)*x+t.c*y;
    t.ty=shown.y-model.y+t.b*x+(t.d-1)*y;
    if(!isfinite(t.a+t.b+t.c+t.d+t.tx+t.ty))return (WXGAffine){1,0,0,1,0,0};
    return t;
}
#endif
