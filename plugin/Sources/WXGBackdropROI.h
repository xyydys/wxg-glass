#ifndef WXG_BACKDROP_ROI_H
#define WXG_BACKDROP_ROI_H
#include <math.h>
#include <stddef.h>
#include "WXGSourceMapping.h"

/* Small, bounded geometry only: no UIKit state or optical parameters. */
#define WXG_ROI_CAPACITY 64
typedef struct { double x,y,w,h; } WXGROIRect;
typedef struct { WXGROIRect rects[WXG_ROI_CAPACITY]; size_t count; } WXGROISet;
static inline int WXGROIValid(WXGROIRect r) {
    return isfinite(r.x+r.y+r.w+r.h) && r.w>0 && r.h>0;
}
static inline WXGROIRect WXGROIIntersection(WXGROIRect a,WXGROIRect b) {
    double x=fmax(a.x,b.x),y=fmax(a.y,b.y);
    return (WXGROIRect){x,y,fmax(0,fmin(a.x+a.w,b.x+b.w)-x),fmax(0,fmin(a.y+a.h,b.y+b.h)-y)};
}
static inline int WXGROIIntersects(const WXGROISet *set,WXGROIRect r) {
    for(size_t i=0;i<set->count;i++)if(WXGROIValid(WXGROIIntersection(set->rects[i],r)))return 1;
    return 0;
}
static inline void WXGROIAdd(WXGROISet *set,WXGROIRect r,WXGROIRect atlas) {
    if(!WXGROIValid(r))return;
    for(size_t i=0;i<set->count;i++) {
        WXGROIRect a=set->rects[i];
        if(a.x<=r.x && a.y<=r.y && a.x+a.w>=r.x+r.w && a.y+a.h>=r.y+r.h)return;
    }
    if(set->count==WXG_ROI_CAPACITY){set->count=1;set->rects[0]=atlas;return;}
    set->rects[set->count++]=r;
}
static inline void WXGROISort(double *values,size_t n) {
    for(size_t i=1;i<n;i++){double v=values[i];size_t j=i;while(j && values[j-1]>v){values[j]=values[j-1];--j;}values[j]=v;}
}
/* Integrate vertical interval unions across rectangle edges. Overlapping ROIs
   are counted once; a gap between top controls and dock remains a gap. */
static inline double WXGROIArea(const WXGROISet *set,WXGROIRect clip) {
    double xs[WXG_ROI_CAPACITY*2],area=0;size_t nx=0;
    for(size_t i=0;i<set->count;i++) {
        WXGROIRect r=WXGROIIntersection(set->rects[i],clip);if(!WXGROIValid(r))continue;
        xs[nx++]=r.x;xs[nx++]=r.x+r.w;
    }
    WXGROISort(xs,nx);
    for(size_t x=1;x<nx;x++) {
        if(xs[x]<=xs[x-1])continue;
        double starts[WXG_ROI_CAPACITY],ends[WXG_ROI_CAPACITY];size_t n=0;
        for(size_t i=0;i<set->count;i++) {
            WXGROIRect r=WXGROIIntersection(set->rects[i],clip);
            if(!WXGROIValid(r) || r.x>=xs[x] || r.x+r.w<=xs[x-1])continue;
            size_t j=n++;while(j && starts[j-1]>r.y){starts[j]=starts[j-1];ends[j]=ends[j-1];--j;}
            starts[j]=r.y;ends[j]=r.y+r.h;
        }
        double height=0,lo=0,hi=0;
        for(size_t i=0;i<n;i++) {
            if(!i){lo=starts[i];hi=ends[i];}
            else if(starts[i]<=hi)hi=fmax(hi,ends[i]);
            else{height+=hi-lo;lo=starts[i];hi=ends[i];}
        }
        if(n)height+=hi-lo;
        area+=(xs[x]-xs[x-1])*height;
    }
    return area;
}
static inline int WXGROICovers(const WXGROISet *set,WXGROIRect r) {
    if(!WXGROIValid(r))return 0;
    for(size_t i=0;i<set->count;i++) {
        WXGROIRect a=set->rects[i];
        if(a.x<=r.x && a.y<=r.y && a.x+a.w>=r.x+r.w && a.y+a.h>=r.y+r.h)return 1;
    }
    return WXGROIArea(set,r)>=r.w*r.h-1e-8;
}
/* The copy kernel starts at local (0,0), independent of UIView.bounds.origin.
   Its full rounded drawable extent must be present before Gaussian/refraction.
   Clamp before padding because the copy sampler clamps off-atlas reads. */
static inline int WXGROICanvas(WXGSourceTransform t,double width,double height,double copyScale,
                              WXGROIRect atlas,double atlasScale,WXGROIRect *canvas,WXGROIRect *roi) {
    if(!canvas || !roi || !WXGROIValid(atlas) || width<=0 || height<=0 || copyScale<=0 || atlasScale<=0 ||
       !isfinite(t.a+t.b+t.c+t.d+t.tx+t.ty+width+height+copyScale+atlasScale))return 0;
    double w=width/copyScale,h=height/copyScale;
    double xs[4]={t.tx,t.tx+t.a*w,t.tx+t.c*h,t.tx+t.a*w+t.c*h};
    double ys[4]={t.ty,t.ty+t.b*w,t.ty+t.d*h,t.ty+t.b*w+t.d*h};
    double x0=xs[0],x1=xs[0],y0=ys[0],y1=ys[0];
    for(size_t i=1;i<4;i++){x0=fmin(x0,xs[i]);x1=fmax(x1,xs[i]);y0=fmin(y0,ys[i]);y1=fmax(y1,ys[i]);}
    *canvas=(WXGROIRect){x0,y0,x1-x0,y1-y0};if(!WXGROIValid(*canvas))return 0;
    double px=fmin(.5/atlasScale,atlas.w*.5),py=fmin(.5/atlasScale,atlas.h*.5),guard=2./atlasScale;
    x0=fmax(atlas.x+px,fmin(atlas.x+atlas.w-px,x0));x1=fmax(atlas.x+px,fmin(atlas.x+atlas.w-px,x1));
    y0=fmax(atlas.y+py,fmin(atlas.y+atlas.h-py,y0));y1=fmax(atlas.y+py,fmin(atlas.y+atlas.h-py,y1));
    *roi=WXGROIIntersection((WXGROIRect){x0-guard,y0-guard,x1-x0+2*guard,y1-y0+2*guard},atlas);
    return WXGROIValid(*roi);
}
#endif
