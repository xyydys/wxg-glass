#ifndef WXG_RIM26_H
#define WXG_RIM26_H
#include <math.h>
#include "WXGRimGlow.h"
/* FIX122 F iOS 26 边框 (user, 11-09, with two zoomed screenshots of an iOS 26
   button): two new rim styles, standalone (the three earlier ones are left
   as they are), and a standalone inner shadow.

   Measured on the screenshots: across the edge the line is not flat but a
   peak about 0.45 pt inside the outline, rising over ~0.3 pt from outside
   and falling over ~0.5 pt inward (the inner side about 1.6x the outer);
   its colour is the background's own, brightened (x1.84) and more
   saturated (x1.29 over the glass, x1.55 over the page); at equal
   brightness the outer flank is paler and the inner deeper; along the
   outline the brightness follows |cos(angle - 135 deg)| (top-left and
   bottom-right brightest, none at top-right and bottom-left) at a constant
   width (it fades, it does not narrow). No inner shadow could be measured
   on that button (the shadow is its own switch).

   Every profile here is an asymmetric Gaussian across the edge: level
   exp(-((t - c) / s)^2 / 2) with s = `outer` before its centre c and
   `inner` after (t: points inward from the outline), or (the shadow) an
   exponential exp(-t / length). Drawn as the rims before it are: Core
   Animation borders on the glass' own continuous corners (exactly its
   shape at every size). A level that rises then falls is the product of
   two monotone stacks: the falling part (1 out to the centre, then down)
   as bands nested from the outline (WXGRimSolveSteps), masked by the rising
   part (0 at the outline up to 1 at the centre) as bands that all end at
   the same inner edge (WXGRim26RiseBands). */
typedef struct { double centre,outer,inner,amplitude; int exponential; } WXGRim26Profile;
static inline double WXGRim26Rise(double t,WXGRim26Profile p) {
    if(p.exponential || t>=p.centre)return 1.;
    double s=p.outer>1e-3?p.outer:1e-3,x=(t-p.centre)/s;
    return exp(-.5*x*x);
}
static inline double WXGRim26Fall(double t,WXGRim26Profile p) {
    double s=p.inner>1e-3?p.inner:1e-3;
    if(p.exponential)return exp(-(t>0.?t:0.)/s);
    if(t<=p.centre)return 1.;
    double x=(t-p.centre)/s;return exp(-.5*x*x);
}
/* The level at depth t, amplitude included (tests, the evidence). */
static inline double WXGRim26Level(double t,WXGRim26Profile p) {
    if(t<0.)return 0.;
    return (p.amplitude<0.?0.:p.amplitude>1.?1.:p.amplitude)*WXGRim26Rise(t,p)*WXGRim26Fall(t,p);
}
/* How far in anything is drawn: 3 sigmas past the centre (5 lengths). */
static inline double WXGRim26Reach(WXGRim26Profile p) {
    double s=p.inner>1e-3?p.inner:1e-3;
    return p.exponential?5.*s:(p.centre>0.?p.centre:0.)+3.*s;
}
/* The step levels (each the level's average over its quarter-pixel step,
   by Simpson) of a monotone part on [a, b): f(t) sampled. */
static inline double WXGRim26Average(double a,double b,WXGRim26Profile p,int rise) {
    double h=b-a,sum=0;const int q=8;
    for(int i=0;i<=q;i++){double t=a+h*i/q,w=(i==0 || i==q)?1.:(i&1?4.:2.);sum+=w*(rise?WXGRim26Rise(t,p):WXGRim26Fall(t,p));}
    return sum/(3.*q);
}
/* Merge and solve, as WXGRimSoftBands does inline: m steps from the
   outline (step k ends at hi[k], light[k] its level integrated over it);
   past `max` the two neighbours closest in level are joined; then nested
   bands from the outline whose composite is each step's average
   (b_k = 1 - (1 - L_k) / (1 - L_{k+1})). */
static inline int WXGRim26SolveSteps(double *hi,double *light,int m,int max,double *inset,double *bandWidth,double *alpha) {
    while(m>max) {
        int best=0;double bestGap=-1.;
        for(int i=0;i+1<m;i++) {
            double a0=i?hi[i-1]:0.,l0=light[i]/(hi[i]-a0),l1=light[i+1]/(hi[i+1]-hi[i]);
            double gap=fabs(l0-l1);
            if(bestGap<0. || gap<bestGap){bestGap=gap;best=i;}
        }
        hi[best]=hi[best+1];light[best]+=light[best+1];
        for(int i=best+1;i+1<m;i++){hi[i]=hi[i+1];light[i]=light[i+1];}
        --m;
    }
    double lv[WXG_RIM_GLOW_MAX_BANDS+1];
    for(int k=0;k<m;k++){double a=k?hi[k-1]:0.,b=hi[k],l=b>a?light[k]/(b-a):0.;lv[k]=l>1.?1.:l<0.?0.:l;}
    lv[m]=0.;
    for(int k=0;k<m;k++) {
        inset[k]=0;bandWidth[k]=hi[k];
        double a=lv[k+1]<1.?1.-(1.-lv[k])/(1.-lv[k+1]):1.;
        alpha[k]=a<0.?0.:a>1.?1.:a;
    }
    return m;
}
/* The falling part, nested from the outline: level `amplitude` out to the
   centre, then the fall in quarter-pixel steps to the reach (at most
   `max` bands; neighbours closest in level merged). */
static inline int WXGRim26FallBands(WXGRim26Profile p,double scale,int max,double *inset,double *bandWidth,double *alpha) {
    if(max<1 || !inset || !bandWidth || !alpha)return 0;
    double amp=p.amplitude<0.?0.:p.amplitude>1.?1.:p.amplitude;
    if(amp<=0.)return 0;
    if(!(scale>0.))scale=3.;
    if(max>WXG_RIM_GLOW_MAX_BANDS)max=WXG_RIM_GLOW_MAX_BANDS;
    double reach=WXGRim26Reach(p),centre=p.exponential?0.:(p.centre>0.?p.centre:0.);
    if(!(reach>centre))return 0;
    double hi[WXG_RIM_SOFT_MAX_STEPS+1],light[WXG_RIM_SOFT_MAX_STEPS+1];int m=0;
    if(centre>0.){hi[m]=centre;light[m]=amp*centre;++m;}
    double steps=ceil((reach-centre)*scale*4.-1e-9);
    int n=steps<1.?1:steps>(double)WXG_RIM_SOFT_MAX_STEPS-1?WXG_RIM_SOFT_MAX_STEPS-1:(int)steps;
    for(int k=0;k<n;k++) {
        double a=centre+(reach-centre)*k/n,b=k+1==n?reach:centre+(reach-centre)*(k+1)/n;
        hi[m]=b;light[m]=amp*WXGRim26Average(a,b,p,0)*(b-a);++m;
    }
    return WXGRim26SolveSteps(hi,light,m,max,inset,bandWidth,alpha);
}
/* The rising part: bands that all end at `reach`, band j from step j's
   start inward; where steps 0..j overlap the composite is the rise's
   average over step j (c_j = 1 - (1 - R_j) / (1 - R_{j-1})); from the
   centre on, 1 (the last band solid). Neighbours closest in level merged
   past `max`. A profile with no rise (exponential, or centre 0) gives one
   solid band. */
static inline int WXGRim26RiseBands(WXGRim26Profile p,double scale,int max,double *inset,double *bandWidth,double *alpha) {
    if(max<1 || !inset || !bandWidth || !alpha)return 0;
    if(!(scale>0.))scale=3.;
    if(max>WXG_RIM_GLOW_MAX_BANDS)max=WXG_RIM_GLOW_MAX_BANDS;
    double reach=WXGRim26Reach(p),centre=p.exponential?0.:(p.centre>0.?p.centre:0.);
    double lo[WXG_RIM_SOFT_MAX_STEPS+1],level[WXG_RIM_SOFT_MAX_STEPS+1],len[WXG_RIM_SOFT_MAX_STEPS+1];int m=0;
    if(centre>0.) {
        double steps=ceil(centre*scale*4.-1e-9);
        int n=steps<1.?1:steps>(double)WXG_RIM_SOFT_MAX_STEPS-1?WXG_RIM_SOFT_MAX_STEPS-1:(int)steps;
        for(int k=0;k<n;k++){double a=centre*k/n,b=k+1==n?centre:centre*(k+1)/n;lo[m]=a;len[m]=b-a;level[m]=WXGRim26Average(a,b,p,1);++m;}
    }
    lo[m]=centre;len[m]=reach-centre;level[m]=1.;++m;
    while(m>max) {   /* join the two neighbours closest in level (never the solid last one with a step below it unless needed) */
        int best=0;double gap=-1.;
        for(int i=0;i+1<m;i++){double g=fabs(level[i+1]-level[i]);if(gap<0. || g<gap){gap=g;best=i;}}
        double l=len[best]+len[best+1];
        level[best]=best+1==m-1?1.:(level[best]*len[best]+level[best+1]*len[best+1])/l;len[best]=l;
        if(best+1==m-1)level[best]=1.;
        for(int i=best+1;i+1<m;i++){lo[i]=lo[i+1];len[i]=len[i+1];level[i]=level[i+1];}
        --m;
    }
    double previous=0.;
    for(int k=0;k<m;k++) {
        double L=level[k]<previous?previous:level[k]>1.?1.:level[k];
        inset[k]=lo[k];bandWidth[k]=reach-lo[k];
        alpha[k]=previous<1.?1.-(1.-L)/(1.-previous):0.;
        alpha[k]=alpha[k]<0.?0.:alpha[k]>1.?1.:alpha[k];
        previous=L;
    }
    return m;
}
/* The composite of a band stack at depth t (tests): 1 - prod(1 - alpha) of
   the bands covering t. */
static inline double WXGRim26Cover(const double *inset,const double *bandWidth,const double *alpha,int n,double t) {
    double keep=1.;
    for(int k=0;k<n;k++)if(t>=inset[k] && t<inset[k]+bandWidth[k])keep*=1.-alpha[k];
    return 1.-keep;
}
#endif
