#ifndef WXG_RIM_GLOW_H
#define WXG_RIM_GLOW_H
#include <math.h>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
/* FIX86: the iOS 27-like rim (边框样式 · iOS 27), pure C.
   FIX85 drew a line of varying width (widest at the ends), its inner edge
   computed from UIBezierPath's rounded rectangle while its outer edge was the
   glass's own Core Animation corners; the two curves differ, so rounded
   rectangles (multi-line bubbles, the settings cards) showed a dark crescent
   at each end and capsules a line thinner at the corners than along the top.
   The real rim is a light, not a line of varying width:
   - across the edge it fades inward from the outline over `width`, in steps
     of about 1 px (Core Animation borders on the glass's own continuous
     corners, so every step has exactly the glass's shape), the curve
     (1 - depth / width)^falloff at each step's middle;
   - along the outline it is brightest where the outline faces the highlight
     direction (either way) and fades to `endLevel` where it faces across it:
     a mask over the steps, endLevel + (1 - endLevel) * |n . d|^sharpness, d
     the direction at `angle` degrees: 0 the top and bottom brightest, 90 the
     two ends, 45 / 135 the diagonals (top-left and bottom-right / top-right
     and bottom-left); a larger sharpness dims sooner after the brightest
     part. FIX87: the angle is per appearance (light mode's default 90).
     FIX89: no longer per appearance: two highlights drawn together, each
     with its own colour, opacity, width, curve, angle, end level and
     sharpness (e.g. a white one on the top and bottom and a dark one at the
     ends, as iOS 27 has); each is this light on its own. */
#define WXG_RIM_GLOW_MAX_BANDS 20
/* (nx, ny): the outline's outward direction, y down (UIKit). */
static inline double WXGRimGlowLevel(double nx,double ny,double angle,double endLevel,double sharpness) {
    double r=(angle==angle?angle:0.)*M_PI/180.;
    double a=fabs(nx*sin(r)+ny*cos(r));
    if(!(a<=1.))a=1.;
    double e=endLevel<0.?0.:endLevel>1.?1.:endLevel;
    if(!(e==e))e=0.;
    double k=sharpness>.05?sharpness:.05;
    return e+(1.-e)*pow(a,k);
}
/* The light across the edge: n steps of about 1 px over `width` (1..max);
   at depth t in [j, j + 1) * width / n it is A_j = (1 - (j + .5) / n)^falloff,
   the curve at the step's middle (so the total light hardly changes with the
   screen scale, and the innermost step is not left at full width).
   The steps are drawn as nested bands, like the stepped line
   (WXGRimAlphaBands): band j runs from the outline over (j + 1) * width / n
   at alpha b_j, so every band shares the outline and no two band edges meet
   on a half pixel (abutting bands would leave a faint dark ring there). At
   step j the bands j..n-1 overlap, so 1 - prod(1 - b_k) = A_j, i.e.
   b_j = 1 - (1 - A_j) / (1 - A_{j+1}) (A_n = 0); one colour, so the order
   does not matter. Returns n (0 for no width); inset is 0 for every band. */
static inline int WXGRimGlowBands(double width,double falloff,double scale,int max,double *inset,double *bandWidth,double *alpha) {
    if(!(width>0.) || max<1 || !inset || !bandWidth || !alpha)return 0;
    if(!(scale>0.))scale=3.;
    double steps=ceil(width*scale-1e-9);
    int n=steps<1.?1:steps>(double)max?max:(int)steps;
    double step=width/n,f=falloff>.05?falloff:.05;
    for(int j=0;j<n;j++) {
        double level=pow(1.-(j+.5)/n,f),next=j+1<n?pow(1.-(j+1.5)/n,f):0.;
        inset[j]=0;bandWidth[j]=(j+1)*step;
        alpha[j]=next<1.?1.-(1.-level)/(1.-next):1.;
        if(alpha[j]<0.)alpha[j]=0.;
    }
    return n;
}
/* FIX109 B: the 普通 line with a soft glow on its inner side (边框 · 普通 ·
   柔和泛光). FIX109 A faded the light inward from the outline,
   (1 - depth / width)^curve: the user saw a gradient across the whole width
   however steep the curve, and on a short width no softening at all. What
   is wanted is the line itself, as solid as before (`core` pt from the
   outline at full level), and right inside it a short glow: from `level`
   down to nothing over `soft` pt, a Gaussian fall-off, level * exp(-4.6 x^2)
   with x = 0..1 across the glow (1 % left at its end): a soft shoulder, no
   kink, no long tail. The glow's steps are a quarter of a device pixel
   (Core Animation antialiases a border's fractional inner edge, so they
   blend into a smooth fade within a pixel or two); each step is the curve's
   average over it; past `max` steps the two neighbours whose levels differ
   least are joined (the line itself is one step; its edge to the glow is
   never merged unless the glow starts at the line's own level). Nested bands
   from the outline as WXGRimGlowBands; returns n. */
#define WXG_RIM_SOFT_MAX_STEPS 240
#define WXG_RIM_SOFT_FALLOFF 4.6
static inline double WXGRimSoftIntegral(double a,double b,double core,double soft,double level) {
    if(!(soft>0.) || !(b>a))return 0.;
    double k=sqrt(WXG_RIM_SOFT_FALLOFF),x1=(a-core)/soft,x2=(b-core)/soft;
    return level*soft*sqrt(M_PI)/(2.*k)*(erf(k*x2)-erf(k*x1));
}
/* The steps' merging and the nested bands' alphas, shared by
   WXGRimSoftBands and WXGRimBlurredBands: m steps from the outline, step k
   ending at hi[k] with light[k] (its level integrated over it); past `max`
   steps the two neighbours whose levels differ least are joined; then the
   nested bands from the outline whose composite is each step's average
   (b_k = 1 - (1 - L_k) / (1 - L_{k+1})). Returns the band count. */
static inline int WXGRimSolveSteps(double *hi,double *light,int m,int max,double *inset,double *bandWidth,double *alpha) {
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
static inline int WXGRimSoftBands(double core,double soft,double level,double scale,int max,double *inset,double *bandWidth,double *alpha) {
    if(max<1 || !inset || !bandWidth || !alpha)return 0;
    core=core>0.?core:0.;
    soft=soft>0.?soft:0.;
    level=level>1.?1.:level>0.?level:0.;
    if(level<=0.)soft=0.;
    if(core<=0. && soft<=0.)return 0;
    if(!(scale>0.))scale=3.;
    if(max>WXG_RIM_GLOW_MAX_BANDS)max=WXG_RIM_GLOW_MAX_BANDS;
    double hi[WXG_RIM_SOFT_MAX_STEPS+1],light[WXG_RIM_SOFT_MAX_STEPS+1];int m=0;
    if(core>0.){hi[m]=core;light[m]=core;++m;}
    if(soft>0.) {
        double steps=ceil(soft*scale*4.-1e-9);
        int n=steps<1.?1:steps>(double)WXG_RIM_SOFT_MAX_STEPS-1?WXG_RIM_SOFT_MAX_STEPS-1:(int)steps;
        for(int k=0;k<n;k++){double a=core+soft*k/n,b=k+1==n?core+soft:core+soft*(k+1)/n;hi[m]=b;light[m]=WXGRimSoftIntegral(a,b,core,soft,level);++m;}
    }
    return WXGRimSolveSteps(hi,light,m,max,inset,bandWidth,alpha);
}
/* FIX116 (user: 普通 / 取自背景 still end in a line edge that is too solid,
   however the glow is set): the line as a blurred stroke clipped by the
   glass, as Kyant's Backdrop draws its highlight (a stroke twice the width
   centred on the outline, a blur of half the width, clipped to the inside).
   The FIX109 B profile across the edge (the line `core` pt at full level,
   then the glow from `level`) is continued past the outline at its level
   there and convolved with a Gaussian of `blur` pt (its sigma); only the
   inside is drawn. So the outline stays as sharp as before (nothing is
   drawn outside it, the light there is still about the line's), while the
   line's inner edge becomes an erf roll-off centred on `core` (half the
   level there): no step between the line and the glow, no plateau ending in
   a hard edge. Closed form (the glow is a Gaussian too, so its blur is a
   Gaussian times a difference of normal CDFs). blur <= 0.001 pt: exactly
   WXGRimSoftBands. */
#define WXG_RIM_BLUR_REACH 3.
static inline double WXGRimNormalCDF(double x) {return .5*erfc(-x*.70710678118654752440);}
static inline double WXGRimBlurredLevel(double t,double core,double soft,double level,double blur) {
    core=core>0.?core:0.;soft=soft>0.?soft:0.;
    level=level>1.?1.:level>0.?level:0.;
    if(!(blur>0.))blur=1e-6;
    double v=core>0.?WXGRimNormalCDF((core-t)/blur):level*WXGRimNormalCDF(-t/blur);
    if(soft>0. && level>0.) {
        double a2=soft*soft/(2.*WXG_RIM_SOFT_FALLOFF),s2=blur*blur,sum=a2+s2;
        double mean=(core*s2+t*a2)/sum,dev=sqrt(a2*s2/sum),d=t-core;
        v+=level*sqrt(a2/sum)*exp(-d*d/(2.*sum))*(WXGRimNormalCDF((core+soft-mean)/dev)-WXGRimNormalCDF((core-mean)/dev));
    }
    return v<0.?0.:v>1.?1.:v;
}
/* The bands: quarter-device-pixel steps from the outline to where the light
   is gone (core + soft + 3 sigma, at most `limit` pt when > 0: half the
   glass's short side), each the level's average over it (Simpson), merged
   and solved as WXGRimSoftBands. */
static inline int WXGRimBlurredBands(double core,double soft,double level,double blur,double limit,double scale,int max,double *inset,double *bandWidth,double *alpha) {
    if(!(blur>.001))return WXGRimSoftBands(core,soft,level,scale,max,inset,bandWidth,alpha);
    if(max<1 || !inset || !bandWidth || !alpha)return 0;
    core=core>0.?core:0.;
    soft=soft>0.?soft:0.;
    level=level>1.?1.:level>0.?level:0.;
    if(level<=0.)soft=0.;
    if(core<=0. && (soft<=0. || level<=0.))return 0;
    if(!(scale>0.))scale=3.;
    if(max>WXG_RIM_GLOW_MAX_BANDS)max=WXG_RIM_GLOW_MAX_BANDS;
    double reach=core+soft+WXG_RIM_BLUR_REACH*blur;
    if(limit>0. && reach>limit)reach=limit;
    if(!(reach>0.))return 0;
    double hi[WXG_RIM_SOFT_MAX_STEPS+1],light[WXG_RIM_SOFT_MAX_STEPS+1];
    double steps=ceil(reach*scale*4.-1e-9);
    int n=steps<1.?1:steps>(double)WXG_RIM_SOFT_MAX_STEPS?WXG_RIM_SOFT_MAX_STEPS:(int)steps;
    for(int k=0;k<n;k++) {
        double a=reach*k/n,b=k+1==n?reach:reach*(k+1)/n,h=b-a;
        int q=(int)ceil(h/blur*8.);q=q<2?2:q>32?32:q;q+=q&1;
        double sum=WXGRimBlurredLevel(a,core,soft,level,blur)+WXGRimBlurredLevel(b,core,soft,level,blur);
        for(int i=1;i<q;i++)sum+=(i&1?4.:2.)*WXGRimBlurredLevel(a+h*i/q,core,soft,level,blur);
        hi[k]=b;light[k]=sum*h/(3.*q);
    }
    return WXGRimSolveSteps(hi,light,n,max,inset,bandWidth,alpha);
}
/* FIX109: nested one-colour bands at `opacity` without group opacity: every
   step's composite level multiplied by it, the alphas solved again
   (b_k = 1 - (1 - L_k) / (1 - L_{k+1})). */
static inline void WXGRimScaleBands(double *alpha,int n,double opacity) {
    if(n<1 || !alpha)return;
    opacity=opacity<0.?0.:opacity>1.?1.:opacity;
    double level[WXG_RIM_GLOW_MAX_BANDS+1];if(n>WXG_RIM_GLOW_MAX_BANDS)n=WXG_RIM_GLOW_MAX_BANDS;
    level[n]=0.;
    for(int k=n-1;k>=0;k--)level[k]=1.-(1.-alpha[k])*(1.-level[k+1]);
    for(int k=0;k<=n;k++)level[k]*=opacity;
    for(int k=0;k<n;k++) {
        double a=level[k+1]<1.?1.-(1.-level[k])/(1.-level[k+1]):1.;
        alpha[k]=a<0.?0.:a>1.?1.:a;
    }
}
/* The light at depth step j of what WXGRimGlowBands returned (the bands
   overlapping there, composited). */
static inline double WXGRimGlowComposite(const double *bandWidth,const double *alpha,int n,double depth) {
    double clear=1.;
    for(int k=0;k<n;k++)if(depth<bandWidth[k])clear*=1.-alpha[k];
    return 1.-clear;
}
#endif
