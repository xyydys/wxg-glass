#ifndef WXG_RIM26_MASK_H
#define WXG_RIM26_MASK_H

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "WXGRim26.h"
#include "WXGRim26Contour.h"

// Alpha is an integral over a pixel. Source-over of several already antialiased
// bands with the same outside edge counts partial coverage more than once.
// Partition the existing vector contours into disjoint strips and resolve their
// light into a single mask before the live backdrop colour is composited.
typedef struct {
    int pixels,cap;                 // cap == 0: the entire axis is drawn at native size
    double material,leading,trailing; // points in the cached tile
} WXGRim26MaskAxis;

static inline WXGRim26MaskAxis WXGRim26MaskAxisFor(double origin,double length,double radius,double reach,double scale) {
    WXGRim26MaskAxis a={0};
    if(!(length>0. && scale>=1.) || !(length*scale<INT_MAX/4.) || !isfinite(origin))return a;
    // Align the backing, never the material. Preserve the actual fractional
    // tips inside it. A stationary button then needs no second texture filter.
    double phase=origin*scale-floor(origin*scale);
    double end=phase+length*scale;
    a.leading=(1.+phase)/scale;
    a.trailing=(1.+ceil(end)-end)/scale;
    a.material=length;
    a.pixels=(int)ceil(end)+2;
    // Every inset shoulder is contained in the outer 1.5 radii. Preserve the
    // whole turn, the lighting field, and linear filtering's neighbouring texel.
    int cap=(int)ceil(fmax((1.+WXG_CAPSULE26_LEAD)*radius,reach)*scale)+3;
    if(a.pixels>2*cap+1) {
        a.cap=cap;a.pixels=2*cap+1;
        a.material=a.pixels/scale-a.leading-a.trailing;
    }
    return a;
}

enum { WXGRim26Subrows=32 };
typedef struct {
    float *halfWidths;
    int rows;
    double halfWidth,top,x,y;       // contour and intersections in physical pixels
} WXGRim26Scan;

// Every horizontal slice of this convex, symmetric contour is one interval.
// Only the descending (right) branch is needed; its reflection is the left.
static inline void WXGRim26ScanLine(WXGRim26Scan *s,double x0,double y0,double x1,double y1) {
    if(y1<=y0)return;
    int first=(int)ceil((y0+s->top)*WXGRim26Subrows-.5);
    int end=(int)ceil((y1+s->top)*WXGRim26Subrows-.5);
    if(first<0)first=0;
    if(end>s->rows)end=s->rows;
    double dxdy=(x1-x0)/(y1-y0);
    for(int row=first;row<end;row++) {
        double y=(row+.5)/WXGRim26Subrows-s->top;
        s->halfWidths[row]=(float)fmax(0.,x0+(y-y0)*dxdy-s->halfWidth);
    }
}

static inline void WXGRim26ScanPath(void *ctx,int op,double x1,double y1,double x2,double y2,double x,double y) {
    WXGRim26Scan *s=ctx;
    double x0=s->x,y0=s->y;
    s->x=x;s->y=y;
    // The closing edge is horizontal and the move has no length.
    if(op==WXGRimMove || op==WXGRimClose || y<=y0)return;
    if(op!=WXGRimCubic){WXGRim26ScanLine(s,x0,y0,x,y);return;}
    // A cubic's chord error is <= max|B''| / (8*n*n). Keep it below
    // 1/128 physical pixel, independent of radius and display scale.
    double second=6.*fmax(hypot(x0-2*x1+x2,y0-2*y1+y2),hypot(x1-2*x2+x,y1-2*y2+y));
    int steps=(int)fmax(1.,ceil(sqrt(16.*second)));
    double previousX=x0,previousY=y0;
    for(int i=1;i<=steps;i++) {
        double t=(double)i/steps,u=1.-t;
        double px=u*u*u*x0+3*u*u*t*x1+3*u*t*t*x2+t*t*t*x;
        double py=u*u*u*y0+3*u*u*t*y1+3*u*t*t*y2+t*t*t*y;
        WXGRim26ScanLine(s,previousX,previousY,px,py);
        previousX=px;previousY=py;
    }
}

typedef struct { float plain,directional; } WXGRim26Weights;
static inline void WXGRim26CoverSpan(WXGRim26Weights *row,int width,double left,double right,WXGRim26Weights level) {
    left=fmax(0.,left);right=fmin(width,right);
    if(right<=left)return;
    int first=(int)left,last=(int)ceil(right)-1;
    float t=(float)(first==last?right-left:first+1.-left);
    row[first].plain+=t*level.plain;
    row[first].directional+=t*level.directional;
    if(first==last)return;
    for(int x=first+1;x<last;x++) {
        row[x].plain+=level.plain;
        row[x].directional+=level.directional;
    }
    t=(float)(right-last);
    row[last].plain+=t*level.plain;
    row[last].directional+=t*level.directional;
}

static inline int WXGRim26DepthCount(const WXGRim26Bands *light,const WXGRim26Bands *plain) {
    int bands=light->count;
    while(bands>0 && !(light->level[bands-1]>0. || plain->level[bands-1]>0.))--bands;
    return bands;
}

// bytes is one row-major alpha byte per pixel. The mask's transparent gutter
// belongs to its texture; it cannot expose a repeated edge texel at a tip.
static inline int WXGRim26DrawMask(uint8_t *bytes,WXGRim26MaskAxis horizontal,WXGRim26MaskAxis vertical,
                                   double radius,double scale,WXGRim26Shape shape) {
    int width=horizontal.pixels,height=vertical.pixels;
    if(!bytes || width<=0 || height<=0 || height>INT_MAX/WXGRim26Subrows)return 0;
    WXGRim26Bands light=WXGRim26BandsFor(0,shape,scale),plain=WXGRim26BandsFor(1,shape,scale);
    int bands=WXGRim26DepthCount(&light,&plain);
    int subrows=height*WXGRim26Subrows;
    size_t edgesCount=(size_t)(bands+1)*subrows;
    float *edges=calloc(edgesCount,sizeof *edges);
    WXGRim26Weights *row=calloc((size_t)width,sizeof *row);
    if(!edges || !row){free(row);free(edges);return 0;}
    double w=horizontal.material*scale,h=vertical.material*scale,r=radius*scale;
    double cx=horizontal.leading*scale+w*.5,cy=vertical.leading*scale+h*.5;
    WXGRim26Weights levels[WXG_RIM26_MAX_BANDS];
    for(int i=0;i<=bands;i++) {
        double d=i?light.width[i-1]*scale:0.;
        WXGRim26Scan scan={edges+(size_t)i*subrows,subrows,w*.5-d,vertical.leading*scale+d,0.,0.};
        WXGRim26Contour(w-2*d,h-2*d,fmax(0.,r-d),&scan,WXGRim26ScanPath);
        if(i<bands) {
            levels[i].plain=(float)(plain.level[i]/WXGRim26Subrows);
            levels[i].directional=(float)(light.level[i]*(1.-plain.level[i])/WXGRim26Subrows);
        }
    }
    double fieldRadius=fmax(r,fmin(shape.height*scale,fmin(w,h)*.5));
    for(int y=0;y<height;y++) {
        memset(row,0,(size_t)width*sizeof *row);
        for(int i=0;i<bands;i++) {
            const float *outer=edges+(size_t)i*subrows+y*WXGRim26Subrows;
            const float *inner=outer+subrows;
            for(int j=0;j<WXGRim26Subrows;j++) {
                if(outer[j]<=inner[j])continue;
                WXGRim26CoverSpan(row,width,cx-outer[j],cx-inner[j],levels[i]);
                WXGRim26CoverSpan(row,width,cx+inner[j],cx+outer[j],levels[i]);
            }
        }
        for(int x=0;x<width;x++) {
            double a=row[x].plain;
            if(row[x].directional>0.) {
                WXGShapeSample f=WXGRoundedOpticalField((float)(x+.5-cx),(float)(y+.5-cy),(float)w,(float)h,(float)fieldRadius);
                a+=row[x].directional*WXGRim26Along(f.nx,f.ny,shape);
            }
            bytes[(size_t)y*width+x]=(uint8_t)lround(255.*WXGRim26Clamp(a,0.,1.));
        }
    }
    free(row);free(edges);
    return bands;
}
#endif
