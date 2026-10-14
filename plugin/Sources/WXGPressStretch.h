#ifndef WXG_PRESS_STRETCH_H
#define WXG_PRESS_STRETCH_H
#include <math.h>
#include "WXGMotion.h"
#include "WXGButtonPress.h"
/* FIX68: iOS 26 hold-and-drag stretch.

   Glass buttons: while the finger is down the pull (the finger's distance
   from where it touched down, rubber-banded: never more than `limit`, ever
   harder the further) stretches the glass along it: `amount` x the pull
   longer along it, half that shorter across (in points, the same feel on a
   round button and on a wide capsule). FIX70: the glass hardly moves: its
   far side stays almost where it was, the near side reaches out (the centre
   moves by 0.45 of the lengthening). FIX80: plus a share of the pull with
   the finger; the lengthening eases into a maximum; glass that is not round
   stretches less and only along x / y. Glass, icon and text take the same
   transform. Let go, a bouncy spring brings it home (about a quarter
   overshoot, which swings the stretch the other way once, settled in about
   0.6 s).

   The dock: a lens pushed past the last tab pushes the bar's end out (the
   other end stays), the bar slightly thinner; same springs. */
typedef struct { double a,b,c,d,tx,ty; } WXGStretchPose;            /* CGAffineTransform order */
typedef struct { double x,y,vx,vy,targetX,targetY; int tracking; } WXGStretchState;

static inline double WXGRubberBand(double distance,double limit) {
    if(!(limit>0) || !(distance>0))return 0;
    return limit*(1-1/(1+distance*.8/limit));
}
/* The target offset for a finger `dx, dy` away from where it touched down. */
static inline void WXGStretchTarget(WXGStretchState *s,double dx,double dy,double limit) {
    double len=hypot(dx,dy),r=WXGRubberBand(len,limit);
    s->targetX=len>1e-9?dx/len*r:0;s->targetY=len>1e-9?dy/len*r:0;
}
#define WXG_STRETCH_FOLLOW_K 600.
#define WXG_STRETCH_FOLLOW_C 41.
#define WXG_STRETCH_RELEASE_K 300.
#define WXG_STRETCH_RELEASE_C 14.
/* One step; returns whether the offset moved. */
static inline int WXGStretchStep(WXGStretchState *s,double dt) {
    double ox=s->x,oy=s->y,k=s->tracking?WXG_STRETCH_FOLLOW_K:WXG_STRETCH_RELEASE_K,c=s->tracking?WXG_STRETCH_FOLLOW_C:WXG_STRETCH_RELEASE_C;
    WXGSpring(&s->x,&s->vx,s->targetX,k,c,dt);
    WXGSpring(&s->y,&s->vy,s->targetY,k,c,dt);
    return fabs(ox-s->x)>1e-4 || fabs(oy-s->y)>1e-4;
}
static inline int WXGStretchResting(const WXGStretchState *s) {
    return s->x==0 && s->y==0 && s->vx==0 && s->vy==0 && s->targetX==0 && s->targetY==0;
}
/* The share of the lengthening the centre moves by (0.5 = far side fixed). */
#define WXG_STRETCH_SHIFT .45
/* FIX80: the user's stretch settings.
   amount   pt of lengthening per pt of pull (narrower across by half that);
   capsule  share of that for glass that is not round (a capsule / rounded
            rectangle): it only stretches along x and y, never along a
            diagonal (no shear);
   maximum  the most it can lengthen (pt): the lengthening eases into it
            (maximum x tanh(x / maximum)); 0 = no cap;
   follow   share of the (rubber-banded) pull the glass moves by with the
            finger, on top of the reach of the stretch. */
typedef struct { double amount,capsule,maximum,follow; } WXGStretchStyle;
static inline double WXGStretchEase(double x,double maximum) {return maximum>0?maximum*tanh(x/maximum):x;}
/* Round: no more than 10% wider than tall. */
static inline int WXGStretchRound(double w,double h) {return fmax(w,h)<=1.1*fmin(w,h);}
/* The body's transform about its centre: the press pose, then the stretch for
   pull `ox, oy` of a `w` x `h` body, moved by the press offset, a little
   towards the pull (the stretch's reach) and by `follow` x the pull. The
   spring's overshoot (a pull the other way) mirrors it. */
static inline WXGStretchPose WXGStretchPoseMake(WXGButtonPressPose press,double ox,double oy,double w,double h,WXGStretchStyle style) {
    double m00=1,m01=0,m11=1,len=hypot(ox,oy),shiftX=0,shiftY=0,amount=fmax(0,style.amount);
    if(len>1e-6 && amount>0 && w>0 && h>0) {
        if(WXGStretchRound(w,h)) {
            double ux=ox/len,uy=oy/len,along=fabs(ux)*w+fabs(uy)*h,across=fabs(uy)*w+fabs(ux)*h,e=WXGStretchEase(amount*len,style.maximum);
            double s=1+e/along,p=fmax(.6,1-.5*e/across);
            m00=s*ux*ux+p*uy*uy;m11=s*uy*uy+p*ux*ux;m01=(s-p)*ux*uy;
            shiftX=ux*e*WXG_STRETCH_SHIFT;shiftY=uy*e*WXG_STRETCH_SHIFT;
        }else {
            /* Each axis by its own part of the pull: longer along it, the
               other axis narrower by half that. */
            double k=amount*fmax(0,style.capsule),ex=WXGStretchEase(k*fabs(ox),style.maximum),ey=WXGStretchEase(k*fabs(oy),style.maximum);
            m00=fmax(.6,1+(ex-.5*ey)/w);m11=fmax(.6,1+(ey-.5*ex)/h);
            shiftX=(ox<0?-ex:ex)*WXG_STRETCH_SHIFT;shiftY=(oy<0?-ey:ey)*WXG_STRETCH_SHIFT;
        }
    }
    double follow=fmax(0,style.follow);
    shiftX+=follow*ox;shiftY+=follow*oy;
    WXGStretchPose m={m00*press.scaleX,m01*press.scaleX,m01*press.scaleY,m11*press.scaleY,press.offsetX+shiftX,press.offsetY+shiftY};
    return m;
}
/* A child centred `rx, ry` from the body's centre turns about its own centre:
   its translation so that it moves with the body. */
static inline void WXGStretchChildOffset(WXGStretchPose m,double rx,double ry,double *tx,double *ty) {
    *tx=m.tx+(m.a-1)*rx+m.c*ry;
    *ty=m.ty+m.b*rx+(m.d-1)*ry;
}
/* FIX73: half the extent along x and y of a `w` x `h` body with corners of
   radius `r` under the pose (about its centre, translation not included):
   the support function of a rounded rectangle, exact for the posed shape. */
static inline void WXGStretchReach(WXGStretchPose m,double w,double h,double r,double *rx,double *ry) {
    r=fmax(0,fmin(r,fmin(w,h)*.5));
    double hw=fmax(0,w*.5-r),hh=fmax(0,h*.5-r);
    *rx=fabs(m.a)*hw+fabs(m.c)*hh+r*hypot(m.a,m.c);
    *ry=fabs(m.b)*hw+fabs(m.d)*hh+r*hypot(m.b,m.d);
}
static inline int WXGStretchInside(WXGStretchPose m,double w,double h,double r,double x0,double y0,double x1,double y1) {
    double rx=0,ry=0;WXGStretchReach(m,w,h,r,&rx,&ry);
    const double slack=1e-6;
    return m.tx-rx>=x0-slack && m.tx+rx<=x1+slack && m.ty-ry>=y0-slack && m.ty+ry<=y1+slack;
}
/* FIX73: the largest share (0..1) of the pull `ox, oy` whose pose keeps the
   body inside the box x0..x1, y0..y1 (relative to the body's resting centre):
   what still shows inside a view that clips (the chat input bar's glass sits
   in WeChat's input panel; pulled past it, the glass was cut off). The box
   first takes in whatever the body covers unpulled (with the press). Reach
   grows with the pull, so the share is found by bisection. */
static inline double WXGStretchFit(WXGButtonPressPose press,double ox,double oy,double w,double h,double r,WXGStretchStyle style,
                                   double x0,double y0,double x1,double y1) {
    if(!(w>0) || !(h>0) || (ox==0 && oy==0))return 1;
    WXGStretchPose rest=WXGStretchPoseMake(press,0,0,w,h,style);
    double rx=0,ry=0;WXGStretchReach(rest,w,h,r,&rx,&ry);
    x0=fmin(x0,rest.tx-rx);x1=fmax(x1,rest.tx+rx);y0=fmin(y0,rest.ty-ry);y1=fmax(y1,rest.ty+ry);
    if(WXGStretchInside(WXGStretchPoseMake(press,ox,oy,w,h,style),w,h,r,x0,y0,x1,y1))return 1;
    double lo=0,hi=1;
    for(int i=0;i<16;i++) {
        double mid=(lo+hi)*.5;
        if(WXGStretchInside(WXGStretchPoseMake(press,ox*mid,oy*mid,w,h,style),w,h,r,x0,y0,x1,y1))lo=mid;else hi=mid;
    }
    return lo;
}
/* The dock pushed `o` past its end on `side` (+1 right, -1 left; o < 0 in the
   spring's overshoot squeezes it): the bar from x0 to x1, `h` tall, in a view
   centred at cx. The far end stays. */
static inline WXGStretchPose WXGDockEndStretchPose(double o,int side,double x0,double x1,double cx,double h) {
    double w=x1-x0;
    if(!(w>1) || !(h>1) || o==0){WXGStretchPose identity={1,0,0,1,0,0};return identity;}
    double sx=fmax(.85,1+o/w),sy=WXGClamp(1-.2*o/h,.85,1.1),anchor=side>0?x0:x1;
    WXGStretchPose m={sx,0,0,sy,(sx-1)*(cx-anchor),0};
    return m;
}
#endif
