#ifndef WXG_RIM26_CONTOUR_H
#define WXG_RIM26_CONTOUR_H
#include "WXGCapsule26.h"

/* Clockwise vector outline in local points. The two shoulders at each
   corner follow the measured long-edge profile independently. An edge with
   no straight run has no shoulder: a square round button is a circle. */
enum { WXGRimMove, WXGRimLine, WXGRimCubic, WXGRimClose };
typedef void (*WXGRim26Emit)(void *,int,double,double,double,double,double,double);
typedef struct { double x,y; } WXGRim26Point;
typedef struct {
    WXGRim26Emit emit;
    void *context;
    double width,height;
    int corner;
} WXGRim26Pen;
static inline WXGRim26Point WXGRim26Map(WXGRim26Pen p,WXGRim26Point v) {
    switch(p.corner) {
        case 0:return (WXGRim26Point){p.width+v.x,v.y};
        case 1:return (WXGRim26Point){p.width-v.y,p.height+v.x};
        case 2:return (WXGRim26Point){-v.x,p.height-v.y};
        default:return (WXGRim26Point){v.y,-v.x};
    }
}
static inline void WXGRim26Segment(WXGRim26Pen p,int op,WXGRim26Point a,WXGRim26Point b,WXGRim26Point end) {
    a=WXGRim26Map(p,a);b=WXGRim26Map(p,b);end=WXGRim26Map(p,end);
    p.emit(p.context,op,a.x,a.y,b.x,b.y,end.x,end.y);
}
/* A short capsule has less room for the run-in. Scaling the dip with
   the square of its run keeps the curvature bounded as it becomes round. */
static inline double WXGRim26ShoulderDepth(int i,double r,double share) {
    double u=(WXG_CAPSULE26_LEAD-.05*i)*share;
    return (WXGCapsule26Table(WXG_CAPSULE26_STEPS-1-i)*share*share+
            (u<0.?1.-sqrt(1.-u*u):0.))*r;
}
static inline void WXGRim26Shoulder(WXGRim26Pen pen,double r,double share,int exitSide) {
    if(share<=0.)return;
    const int last=WXG_CAPSULE26_STEPS-1;
    // Uniform cubic B-spline converted to Beziers. Its first three controls
    // share the straight edge; the last three fix value, slope and curvature
    // to those of the circular portion. Adjacent spans share two derivatives.
    double q[WXG_CAPSULE26_STEPS+2]={0};
    double run=.05*r*share,tail=WXG_CAPSULE26_TAIL*share,c=sqrt(1.-tail*tail);
    double a=WXGRim26ShoulderDepth(1,r,share),b=WXGRim26ShoulderDepth(2,r,share);
    for(int i=2;i<last-1;i++) {
        double d=WXGRim26ShoulderDepth(i+1,r,share);
        q[i+1]=fmax(0.,b-(a-2*b+d)/6.);
        a=b;b=d;
    }
    double y=r*(1.-c),slope=run*tail/c,accel=run*run/(r*c*c*c);
    q[last]=y+accel/3.-slope;q[last+1]=y-accel/6.;q[last+2]=y+accel/3.+slope;
    double startX=-r*(1.+WXG_CAPSULE26_LEAD*share);
    for(int k=0;k<last;k++) {
        int i=exitSide?last-1-k:k;
        double x=startX+i*run;
        WXGRim26Point a={x+run/3.,(2*q[i+1]+q[i+2])/3.};
        WXGRim26Point b={x+2*run/3.,(q[i+1]+2*q[i+2])/3.};
        WXGRim26Point end={x+run,(q[i+1]+4*q[i+2]+q[i+3])/6.};
        if(exitSide) {
            WXGRim26Point prev={x,(q[i]+4*q[i+1]+q[i+2])/6.};
            WXGRim26Segment(pen,WXGRimCubic,(WXGRim26Point){-b.y,-b.x},
                            (WXGRim26Point){-a.y,-a.x},(WXGRim26Point){-prev.y,-prev.x});
        }else WXGRim26Segment(pen,WXGRimCubic,a,b,end);
    }
}
static inline void WXGRim26Contour(double w,double h,double radius,void *ctx,WXGRim26Emit emit) {
    if(!(w>0. && h>0.) || !emit)return;
    double r=fmax(0.,fmin(radius,.5*fmin(w,h)));
    double sx=r>0.?fmin(1.,fmax(0.,w/r-2.)):0.,sy=r>0.?fmin(1.,fmax(0.,h/r-2.)):0.;
    for(int corner=0;corner<4;corner++) {
        WXGRim26Pen pen={emit,ctx,w,h,corner};
        double entry=corner%2?sy:sx,exit=corner%2?sx:sy;
        WXGRim26Point start={-r*(1.+WXG_CAPSULE26_LEAD*entry),0.};
        WXGRim26Segment(pen,corner?WXGRimLine:WXGRimMove,start,start,start);
        if(!r)continue;
        WXGRim26Shoulder(pen,r,entry,0);
        double first=asin(WXG_CAPSULE26_TAIL*entry),last=WXG_CAPSULE26_PI*.5-asin(WXG_CAPSULE26_TAIL*exit);
        for(int k=0;k<2;k++) {
            double t=first+(last-first)*.5*k,v=t+(last-first)*.5;
            double c=r*4./3.*tan((v-t)*.25);
            WXGRim26Point end={r*(sin(v)-1.),r*(1.-cos(v))};
            WXGRim26Point a={r*(sin(t)-1.)+c*cos(t),r*(1.-cos(t))+c*sin(t)};
            WXGRim26Point b={end.x-c*cos(v),end.y-c*sin(v)};
            WXGRim26Segment(pen,WXGRimCubic,a,b,end);
        }
        WXGRim26Shoulder(pen,r,exit,1);
    }
    emit(ctx,WXGRimClose,0,0,0,0,0,0);
}
#endif
