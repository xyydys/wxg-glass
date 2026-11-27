#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGRim26Contour.h"

typedef struct {
    double w,h,r,x,y,firstX,firstY,tx,ty,area;
    double loX,loY,hiX,hiY,deepest;
    int segments,closed;
} Trace;

static void tangent(Trace *t,double dx,double dy) {
    double d=hypot(dx,dy);
    if(d<1e-9)return;
    dx/=d;dy/=d;
    if(t->r>0. && (t->tx || t->ty))assert(dx*t->tx+dy*t->ty>.9999999);
    t->tx=dx;t->ty=dy;
}
static void point(Trace *t,double x,double y) {
    t->loX=fmin(t->loX,x);t->loY=fmin(t->loY,y);
    t->hiX=fmax(t->hiX,x);t->hiY=fmax(t->hiY,y);
    t->area+=t->x*y-t->y*x;t->x=x;t->y=y;
    double qx=fmax(0.,fabs(x-t->w*.5)-(t->w*.5-t->r));
    double qy=fmax(0.,fabs(y-t->h*.5)-(t->h*.5-t->r));
    t->deepest=fmax(t->deepest,t->r-hypot(qx,qy));
}
static void sample(void *ctx,int op,double x1,double y1,double x2,double y2,double x,double y) {
    Trace *t=ctx;
    if(op==WXGRimMove){t->firstX=t->x=x;t->firstY=t->y=y;return;}
    if(op==WXGRimClose){x=t->firstX;y=t->firstY;t->closed++;}
    if(op!=WXGRimCubic){tangent(t,x-t->x,y-t->y);point(t,x,y);return;}
    tangent(t,x1-t->x,y1-t->y);
    double x0=t->x,y0=t->y;
    for(int i=1;i<=16;i++) {
        double u=i/16.,v=1.-u;
        point(t,v*v*v*x0+3*v*v*u*x1+3*v*u*u*x2+u*u*u*x,
                v*v*v*y0+3*v*v*u*y1+3*v*u*u*y2+u*u*u*y);
    }
    t->tx=t->ty=0;tangent(t,x-x2,y-y2);t->segments++;
}
static Trace outline(double w,double h,double r) {
    Trace t={.w=w,.h=h,.r=r,.loX=w,.loY=h};
    WXGRim26Contour(w,h,r,&t,sample);
    assert(t.closed==1 && t.area>0);
    assert(fabs(t.loX)<1e-7 && fabs(t.loY)<1e-7);
    assert(fabs(t.hiX-w)<1e-7 && fabs(t.hiY-h)<1e-7);
    if(r>0.)assert(t.segments>=8);
    return t;
}
int main(void) {
    double button=41.468988;
    Trace circle=outline(button,button,button*.5);
    assert(circle.deepest<.0001);
    Trace capsule=outline(120,44,22);
    assert(fabs(capsule.deepest-22*.017)<.03);
    Trace inner=outline(120-2/3.,44-2/3.,22-1/3.);
    assert(inner.area<capsule.area);
    Trace vertical=outline(44,120,22);
    assert(fabs(vertical.area-capsule.area)<1e-7);
    outline(76.197,button,16.33);
    outline(90,44,0.);
    outline(button+.033,button,button*.5);
    puts("PASS: actual-sized iOS 26 vector contours, tangency through all shoulders, measured dip, inner ring, vertical capsule and fractional circle");
    return 0;
}
