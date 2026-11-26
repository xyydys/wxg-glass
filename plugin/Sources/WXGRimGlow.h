#ifndef WXG_RIM_GLOW_H
#define WXG_RIM_GLOW_H
#include <math.h>

typedef struct { double width,falloff,endLevel,sharpness,angle,red,green,blue,alpha; } WXGRimGlowShape;
enum { WXGRimGlowCount=2 };
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
   (nested Core Animation borders): band j runs from the outline over (j + 1) * width / n
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
/* The light at depth step j of what WXGRimGlowBands returned (the bands
   overlapping there, composited). */
static inline double WXGRimGlowComposite(const double *bandWidth,const double *alpha,int n,double depth) {
    double clear=1.;
    for(int k=0;k<n;k++)if(depth<bandWidth[k])clear*=1.-alpha[k];
    return 1.-clear;
}
#endif
