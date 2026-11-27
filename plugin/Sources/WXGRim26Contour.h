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
/* Each shoulder is a convex cubic spline from the top to the common point
   on the circle at sin(angle) = TAIL. x is linear in t (0..1). Store y''(t)
   at uniform knots, in radii. Integrating each linear interval gives a cubic
   with shared position, tangent and curvature. The circle and full-shoulder
   controls were fitted to the circle and WXGCapsule26Table respectively.
   All controls are nonnegative: fitting the noisy measured ordinates exactly
   made the curvature reverse sign, especially as a short title's run shrank.

   In the quadratic blend the run L varies from TAIL to TAIL+LEAD. The knots
   integrate to the same end depth, an end slope proportional to L, and end
   with L²/(1-TAIL²)^(3/2), including at intermediate aspect ratios. */
enum { WXGRim26Spans=8 };
static inline void WXGRim26Shoulder(WXGRim26Pen pen,double r,double share,int exitSide) {
    if(share<=0.)return;
    static const double curvature[3][WXGRim26Spans+1]={
        {.3025,.3038993761700,.3112950239428,.3219176907790,.3404796082610,.3632556724510,.4011005765353,.4447897949867,.5192889258122},
        {.15125,.2844557745290,.1582928860170,.2398293322208,.3751865712107,.4107493971817,.7564393709525,1.4184745383869,.9913697674596},
        {0.,.2687333433788,.0064729715192,.1298279494709,.4146169682555,.5664608082832,1.1076412475237,2.0917825086910,1.8926150106047}
    };
    double run=r*(WXG_CAPSULE26_TAIL+WXG_CAPSULE26_LEAD*share)/WXGRim26Spans;
    double start=-r*(1.+WXG_CAPSULE26_LEAD*share),other=1.-share;
    double y[WXGRim26Spans+1]={0},slope[WXGRim26Spans+1]={0},previous=0.;
    for(int i=0;i<=WXGRim26Spans;i++) {
        double second=(other*other*curvature[0][i]+2.*other*share*curvature[1][i]+share*share*curvature[2][i])*
                      r/(WXGRim26Spans*WXGRim26Spans);
        if(i) {
            y[i]=y[i-1]+slope[i-1]+(2.*previous+second)/6.;
            slope[i]=slope[i-1]+(previous+second)*.5;
        }
        previous=second;
    }
    for(int k=0;k<WXGRim26Spans;k++) {
        int i=exitSide?WXGRim26Spans-1-k:k;
        double x=start+i*run;
        WXGRim26Point a={x+run/3.,y[i]+slope[i]/3.};
        WXGRim26Point b={x+2.*run/3.,y[i+1]-slope[i+1]/3.};
        if(exitSide) {
            WXGRim26Segment(pen,WXGRimCubic,(WXGRim26Point){-b.y,-b.x},
                            (WXGRim26Point){-a.y,-a.x},(WXGRim26Point){-y[i],-x});
        }else WXGRim26Segment(pen,WXGRimCubic,a,b,(WXGRim26Point){x+run,y[i+1]});
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
        double join=asin(WXG_CAPSULE26_TAIL);
        double first=entry>0.?join:0.,last=WXG_CAPSULE26_PI*.5-(exit>0.?join:0.);
        int arcs=(int)ceil((last-first)/(WXG_CAPSULE26_PI/8.));
        double step=(last-first)/arcs;
        for(int k=0;k<arcs;k++) {
            double t=first+step*k,v=t+step;
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
