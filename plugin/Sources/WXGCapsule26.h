#ifndef WXG_CAPSULE26_H
#define WXG_CAPSULE26_H
#include <math.h>
#define WXG_CAPSULE26_PI 3.14159265358979323846
/* FIX133 (user, three times: "most capsules look as if a little of their
   width were missing along the top and the bottom, like not Apple's
   continuous corner"; with a screenshot of the back capsule: "on the
   straight stretch the top and the bottom look as if a part had been
   chopped off"): the outline of iOS 26's glass capsule. Pure C.

   Measured on the system's 120 x 44 pt capsule (probe 1, 8 x captures, 24
   px / pt; three backdrops agree to 0.05 % of the radius): against the plain
   stadium (two half circles of radius R = half the height and two straight
   edges) its long edges leave their line half a radius before the round end
   begins and sink toward it, 1.36 % of R at the point where the half circle
   would begin, at most 1.70 % a tenth of a radius into the round end, and
   are back on the circle 0.55 R into it (33 degrees round); from there to
   the tip it is the circle exactly. So a long edge is straight only over
   its middle and bends ever so slightly long before the end: no place where
   a line stops and an arc starts.

   Core Animation's continuous capsule of iOS 13-18 (what the plugin's glass
   was cut to) does that far less: it leaves the line only 0.1 R before the
   end (measured on the user's phone: 1.0 % in at 5-10 degrees, then 0.4 %
   outside the circle at 40-60), so its long edges stay dead straight almost
   up to the round ends, which reads as a rounder shape with its top and
   bottom sliced flat.

   u: the place along a long edge, in radii from where the half circle would
   begin; + toward the middle, - into the round end. The dip (in radii, into
   the glass, measured across the long edge) at steps of 0.05 from -0.55. */
#define WXG_CAPSULE26_LEAD .50      /* the edge leaves its line this many radii before the round end */
#define WXG_CAPSULE26_TAIL .55      /* and is back on the circle this many radii into it */
#define WXG_CAPSULE26_STEPS 22
static inline double WXGCapsule26Table(int i) {
    static const double v[WXG_CAPSULE26_STEPS]={0.,.0008,.0025,.0047,.0074,.0104,.0132,.0155,.0168,.0170,.0160,
                                                .0136,.0111,.0090,.0073,.0058,.0046,.0036,.0025,.0016,.0006,0.};
    return i<0 || i>=WXG_CAPSULE26_STEPS?0.:v[i];
}
/* The dip at u (radii): the table, a cubic through its points (Catmull-Rom),
   0 outside [-0.55, 0.5] and never negative. */
static inline double WXGCapsule26Dip(double u) {
    if(!(u>-WXG_CAPSULE26_TAIL) || !(u<WXG_CAPSULE26_LEAD))return 0.;
    double f=(u+WXG_CAPSULE26_TAIL)/.05;int i=(int)floor(f);double t=f-i;
    double p0=WXGCapsule26Table(i-1),p1=WXGCapsule26Table(i),p2=WXGCapsule26Table(i+1),p3=WXGCapsule26Table(i+2);
    double v=.5*((2.*p1)+(-p0+p2)*t+(2.*p0-5.*p1+4.*p2-p3)*t*t+(-p0+3.*p1-3.*p2+p3)*t*t*t);
    return v>0.?v:0.;
}
#define WXG_CAPSULE26_JUNCTION .0136   /* the dip where the half circle would begin */
#define WXG_CAPSULE26_DEEPEST .0170
/* How much of the shape a capsule w x h has: 1 when each long edge has at
   least half a radius of straight line at each end (the measured capsule),
   falling to 0 for a circle (a round button stays a circle): the dip and
   the stretch it takes both shrink with it. */
static inline double WXGCapsule26Share(double w,double h) {
    double longSide=w>h?w:h,shortSide=w>h?h:w,r=shortSide*.5;
    if(!(r>0.))return 0.;
    double s=(longSide-shortSide)*.5/(WXG_CAPSULE26_LEAD*r);
    return s<0.?0.:s>1.?1.:s;
}
/* Whether a glass of this size and corner radius is drawn on this outline:
   a capsule (its radius half its short side) that is longer than it is high. */
static inline int WXGCapsule26Applies(double w,double h,double radius) {
    double longSide=w>h?w:h,shortSide=w>h?h:w;
    return shortSide>4. && radius>=shortSide*.5-.3 && longSide-shortSide>2.;
}
/* One quarter of a lying capsule (w >= h), as points from the long edge's
   last straight point to the tip: x from the tip's side (0 = the end of the
   capsule), y from the long edge (0) to the middle (R). Returns the count
   (at most capacity; at least 2). */
static inline int WXGCapsule26Quarter(double w,double h,double *xs,double *ys,int capacity) {
    double r=h*.5,s=WXGCapsule26Share(w,h);
    int n=0;
    if(capacity<2 || !(r>0.))return 0;
    double lead=WXG_CAPSULE26_LEAD*s,tail=WXG_CAPSULE26_TAIL*s;
    /* the stretch that bends: a point about every 0.4 pt (8 .. 72) */
    int bend=s>0.?(int)ceil((lead+tail)*r/.4):0;
    if(bend<8)bend=s>0.?8:0;
    if(bend>72)bend=72;
    /* then the circle to the tip: a point every 2.5 degrees */
    double from=asin(tail>1.?1.:tail),span=WXG_CAPSULE26_PI*.5-from;
    int arc=(int)ceil(span/(2.5*WXG_CAPSULE26_PI/180.));
    if(arc<2)arc=2;
    if(bend+arc+1>capacity) {   /* less room: fewer points, the same shape */
        double k=(double)(capacity-1)/(bend+arc);
        bend=(int)floor(bend*k);arc=capacity-1-bend;
        if(arc<1){arc=1;bend=capacity-2;}
    }
    for(int i=0;i<bend;i++) {
        double u=lead-(lead+tail)*(double)i/bend;            /* from the straight edge into the round end */
        double ideal=u<0.?r-sqrt(r*r-u*u*r*r):0.;
        xs[n]=r+u*r;ys[n]=ideal+s*WXGCapsule26Dip(u/s)*r;++n;
    }
    for(int i=0;i<=arc;i++) {
        double a=from+span*(double)i/arc;                     /* 0 = where the half circle begins, 90 degrees = the tip */
        xs[n]=r-r*sin(a);ys[n]=r-r*cos(a);++n;
    }
    return n;
}
#define WXG_CAPSULE26_QUARTER_MAX 128
/* The whole outline of a capsule w x h (lying or standing), clockwise on a
   screen (y down) from the top edge, as points in its own box (0,0)-(w,h).
   Returns the count (at most 4 x WXG_CAPSULE26_QUARTER_MAX). */
static inline int WXGCapsule26Outline(double w,double h,double *xs,double *ys,int capacity) {
    int standing=h>w;
    double W=standing?h:w,H=standing?w:h;
    double qx[WXG_CAPSULE26_QUARTER_MAX],qy[WXG_CAPSULE26_QUARTER_MAX];
    int q=WXGCapsule26Quarter(W,H,qx,qy,capacity/4<WXG_CAPSULE26_QUARTER_MAX?capacity/4:WXG_CAPSULE26_QUARTER_MAX),n=0;
    if(q<2)return 0;
    /* lying: top right (from the edge to the tip), bottom right (back), bottom left, top left */
    for(int i=0;i<q;i++){xs[n]=W-qx[i];ys[n]=qy[i];++n;}
    for(int i=q-1;i>=0;i--){xs[n]=W-qx[i];ys[n]=H-qy[i];++n;}
    for(int i=0;i<q;i++){xs[n]=qx[i];ys[n]=H-qy[i];++n;}
    for(int i=q-1;i>=0;i--){xs[n]=qx[i];ys[n]=qy[i];++n;}
    if(standing)for(int i=0;i<n;i++){double t=xs[i];xs[i]=H-ys[i];ys[i]=t;}   /* a quarter turn: still clockwise */
    return n;
}
#endif
