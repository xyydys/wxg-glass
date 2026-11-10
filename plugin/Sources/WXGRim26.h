#ifndef WXG_RIM26_H
#define WXG_RIM26_H
#include <math.h>
#include <stddef.h>
#include "WXGOptics.h"
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
/* FIX123 iOS 26 边框, the system's own recipe (user, 11-10: "彻底抛开这两种
   尝试", then ran the GlassProbe of probe/ on iOS 26.6 and sent its captures
   and structure dump). FIX122 F / G guessed the rim from two screenshots;
   both are gone. What the system draws, read from the dump and checked on
   the 8x captures (24 px per point):

   The rim is one layer over the glass (CASDFLayer + CASDFKeyFillHighlight-
   Effect): key light at -45 deg, fill light at 135 deg, each spread 90 deg,
   height 1 pt, curvature 0.7. In pixels that is

       alpha(d, n) = (key * max(0, n.k)^p + fill * max(0, -n.k)^p) * (1 - curve * d / height),   0 <= d <= height

   d the depth inward from the outline, n its outward direction, k the
   lower right at 45 deg; brightest AT the outline, falling in a straight
   line to 30 % at 1 pt, and cut hard there (nothing beyond; no inner
   shadow). Fitted: |cos|^1.00, slope 0.70 to 0.75, rms 0.014; with the
   dumped matrix the lower right reads 1.05, the upper left 1.00 (key, fill). All round there is also a faint
   line (full to height / 3, gone by 2 height / 3), seen where the lights
   are out: `ring`.

   Its colour is not white: the layer carries the filter vibrantColorMatrix,
   so each pixel is the glass under it turned by a colour matrix, mixed by
   alpha:   out = face + alpha * (clamp(M face) - face),
   M face = lift + gain * Y + chroma * (face - Y)   (Y its Rec. 709 luma, on
   the display's encoded values). Dark glass (dumped): gain 1.35, chroma 3.0,
   lift 0.15 (fitted back from the captures: 1.37, 2.95, 0.147). Light glass
   (not in the dump; fitted the same way on eight backdrops, rms 0.003):
   gain 0.174, chroma 1.51, lift 0.847: nearly white, tinted by what is
   under it.

   Here: that alpha as the mask of a colour-matrix copy of what lies under
   the rim (WXGGlassView.m); no blur. FIX125: the mask is Core Animation
   borders on the glass' own corner (WXGRim26BandsFor, at the end of this
   file), not an image of an outline computed here. */
typedef struct {
    double height,curve;        /* across the edge: how far in (pt), how much it has fallen there (0..1) */
    double angle,key,fill,spread; /* along the outline: the key light's direction (deg; 45 = lower right, 0 = bottom, 90 = right), the two lights' levels, the lobes' exponent */
    double ring;                /* the faint line all round */
    double shadowLength;        /* the optional inner shadow (not the system's) */
    double floor;               /* FIX132: the lights never below this share of their level, all round (0: the system's, out at two points) */
} WXGRim26Shape;
static inline double WXGRim26Clamp(double v,double lo,double hi) {return !(v==v)?lo:v<lo?lo:v>hi?hi:v;}
/* The two lights along the outline; (nx, ny) the outward direction, y down.
   FIX130 (user: "an obvious sharp point where the lights close in, lower
   left and upper right; I only saw it after turning 收拢 down"): with the
   exponent below 1 the lobes were |c|^p, which leaves the dark point
   between the two lights exactly as dark but ever narrower: the glass shows
   through the rim in a sharp nick there. Below 1 the lights now stay on
   across that point instead (the lower the exponent, the brighter: 0.85 x
   (1 - p) of a light's level) and turn round it in a curve, the two
   lights' levels running into each other. At 1 and above nothing changes
   (1 is the system's |cos|, which fades out over a wide arc).
   FIX132 (user, on the phone, a round button over a blue wallpaper in dark
   mode: "the corner at the lower left and the upper right is still there,
   as if the inside came out through it; not round any more"): that is the
   system's own rim (its 44 pt button, 8 x: 91 at its brightest, 43 where
   the lights are out, on a face of 41), but where the lights are out the
   dark face then reaches the outline, a point further out than where the
   rim covers it, and against a brighter page that reads as a bulge. `floor`
   keeps the lights on all round at that share of their level (the rim's
   whole depth, so the face ends at one radius everywhere), turning round
   the dark point in a curve as below 1; 0 is the system's. */
static inline double WXGRim26Along(double nx,double ny,WXGRim26Shape s) {
    double r=WXGRim26Clamp(s.angle,-360,360)*M_PI/180.,c=nx*sin(r)+ny*cos(r);
    c=WXGRim26Clamp(c,-1,1);
    double p=s.spread>.05?s.spread:.05,keep=WXGRim26Clamp(s.floor,0,1);
    if(p>=1.-1e-9 && !(keep>0.)) {
        double v=c>0.?s.key*pow(c,p):s.fill*pow(-c,p);
        return WXGRim26Clamp(v,0,1);
    }
    double w=p<1.?1.-p:0.,k=.5*(w>keep?w:keep),a=fabs(c);
    double rounded=(sqrt(a*a+k*k)-k)/(sqrt(1.+k*k)-k);
    if(p>1.)rounded=pow(rounded,p);
    double low=.85*w>keep?.85*w:keep,f=low+(1.-low)*rounded;
    double t=WXGRim26Clamp(c/(2.*k)+.5,0,1);t=t*t*(3.-2.*t);
    return WXGRim26Clamp((s.fill+(s.key-s.fill)*t)*f,0,1);
}
/* Across the edge at depth d (pt): a straight line from 1 at the outline to
   1 - curve at `height`, nothing outside [0, height]. */
static inline double WXGRim26Across(double d,WXGRim26Shape s) {
    double h=s.height>.05?s.height:.05;
    if(d<0. || d>h)return 0.;
    return 1.-WXGRim26Clamp(s.curve,0,1)*d/h;
}
/* The faint line all round: full to height / 3, gone by 2 height / 3. */
static inline double WXGRim26Ring(double d,WXGRim26Shape s) {
    double h=s.height>.05?s.height:.05;
    if(d<0. || d>h)return 0.;
    return WXGRim26Clamp(s.ring,0,1)*WXGRim26Clamp(2.-3.*d/h,0,1);
}
/* The two together: the faint line laid over the lights as one layer over
   another (it shows where they do not; the captures: 0.15 of the full rim
   where the lights are out, 0.03 at the sides, none at their brightest). */
static inline double WXGRim26Alpha(double d,double nx,double ny,WXGRim26Shape s) {
    double lights=WXGRim26Clamp(WXGRim26Along(nx,ny,s)*WXGRim26Across(d,s),0,1);
    return WXGRim26Clamp(lights+WXGRim26Ring(d,s)*(1.-lights),0,1);
}
/* The optional inner shadow: the same all round, falling exponentially. */
static inline double WXGRim26Shadow(double d,WXGRim26Shape s) {
    if(d<0.)return 0.;
    return exp(-d/(s.shadowLength>1e-3?s.shadowLength:1e-3));
}
typedef enum { WXGRim26PartLine=0,WXGRim26PartShadow=1 } WXGRim26Part;
static inline double WXGRim26PartReach(WXGRim26Part part,WXGRim26Shape s) {
    return part==WXGRim26PartShadow?5.*(s.shadowLength>1e-3?s.shadowLength:1e-3):(s.height>.05?s.height:.05);
}

/* The system's colour matrix: lift + gain * Y + chroma * (c - Y) per channel
   (rows R, G, B, A of r, g, b, a, offset, as QuartzCore's). */
static inline void WXGRim26Matrix(double gain,double chroma,double lift,float m[20]) {
    static const double luma[3]={.2126,.7152,.0722};
    for(int i=0;i<20;i++)m[i]=0.f;
    for(int row=0;row<3;row++) {
        for(int column=0;column<3;column++)m[row*5+column]=(float)((gain-chroma)*luma[column]+(row==column?chroma:0.));
        m[row*5+4]=(float)lift;
    }
    m[18]=1.f;
}
/* What a pixel of the rim shows over `face` (0..1 each) at `alpha`. */
static inline void WXGRim26Colour(const float m[20],const double face[3],double alpha,double out[3]) {
    for(int row=0;row<3;row++) {
        double t=m[row*5]*face[0]+m[row*5+1]*face[1]+m[row*5+2]*face[2]+m[row*5+4];
        t=WXGRim26Clamp(t,0,1);
        out[row]=face[row]+WXGRim26Clamp(alpha,0,1)*(t-face[row]);
    }
}

/* A part's image for a glass of w x h points with corner radius r (a
   capsule when r reaches half the short side): the corners plus 2 pt of
   each straight edge, which the layer stretches (nine-part) to any longer
   size, so a glass growing along its straight edges needs no new image.
   `ext`: how far a corner's area reaches along an edge. FIX124: 1.6 r, not
   r: Core Animation's continuous corner leaves the straight edge well
   before the circle's would (1.53 r for a rounded rectangle, 1.45 r for a
   capsule's end), and the canvas keeps the glass' real size in mind
   (realWidth / realHeight): FIX123 took the field of the canvas itself, a
   nearly round shape for a capsule, whose ends are then a circle's: up to
   1.2 % of the radius off the glass' own outline (user, on the phone: "not
   the continuous corner any more, and thinner than iOS 26's": the clip by
   the real outline cut the rim's brightest part away near the joins). */
typedef struct { double width,height;int columns,rows;int stretchX,stretchY;double edgeX,edgeY;double realWidth,realHeight; } WXGRim26Canvas;
static inline WXGRim26Canvas WXGRim26CanvasFor(double w,double h,double r,double reach,double scale) {
    WXGRim26Canvas c;
    double ext=(1.6*r>reach?1.6*r:reach)+1.;
    c.stretchX=w>2.*ext+2.;c.stretchY=h>2.*ext+2.;
    c.width=c.stretchX?2.*ext+2.:w;c.height=c.stretchY?2.*ext+2.:h;
    c.edgeX=c.stretchX?ext:0.;c.edgeY=c.stretchY?ext:0.;
    c.columns=(int)ceil(c.width*scale-1e-9);c.rows=(int)ceil(c.height*scale-1e-9);
    c.columns=c.columns<1?1:c.columns;c.rows=c.rows<1?1:c.rows;
    c.realWidth=w;c.realHeight=h;
    return c;
}
/* The glass' own field at the canvas' (x, y) from its centre: each half of
   the canvas is that end of the real shape (a capsule as the glass'
   continuous outline, WXGCapsuleOpticalField, else a rounded rectangle). */
static inline WXGShapeSample WXGRim26Field(double x,double y,WXGRim26Canvas c,double r) {
    double w=c.realWidth>c.width?c.realWidth:c.width,h=c.realHeight>c.height?c.realHeight:c.height;
    double rx=x+(x<0.?-1.:1.)*(w-c.width)*.5,ry=y+(y<0.?-1.:1.)*(h-c.height)*.5;
    double half=(w<h?w:h)*.5;
    return r>=half-1e-3?WXGCapsuleOpticalField((float)rx,(float)ry,(float)w,(float)h)
                       :WXGRoundedOpticalField((float)rx,(float)ry,(float)w,(float)h,(float)r);
}

/* Fills one byte per pixel (0..255): the part's alpha, the mean of 4 x 4
   samples per pixel. `bleed` (pixels): that far outside the outline counts
   as the outline itself, for a layer that is then clipped by the glass' own
   continuous corner; 0: the outline anti-aliased here. FIX125: only the
   optional inner shadow is still an image (soft, and clipped by Core
   Animation); the rim itself is Core Animation borders (below). */
#define WXG_RIM26_SAMPLES 4
static inline void WXGRim26Fill(unsigned char *bytes,int stride,WXGRim26Canvas c,double r,double scale,WXGRim26Part part,WXGRim26Shape s,double bleed) {
    const int n=WXG_RIM26_SAMPLES;
    double reach=WXGRim26PartReach(part,s),out=(bleed>0.?bleed:0.)/scale;
    for(int j=0;j<c.rows;j++)for(int i=0;i<c.columns;i++) {
        double sum=0;
        /* the pixel's centre first: far outside or far inside, nothing to add up */
        WXGShapeSample mid=WXGRim26Field((i+.5)/scale-c.width*.5,(j+.5)/scale-c.height*.5,c,r);
        if(mid.distance>out+1./scale || -mid.distance>reach+1./scale){bytes[j*stride+i]=0;continue;}
        for(int sy=0;sy<n;sy++)for(int sx=0;sx<n;sx++) {
            double x=(i+(sx+.5)/n)/scale-c.width*.5,y=(j+(sy+.5)/n)/scale-c.height*.5;
            WXGShapeSample f=WXGRim26Field(x,y,c,r);
            double d=-f.distance;
            if(d<-out)continue;
            if(d<0.)d=0.;
            sum+=part==WXGRim26PartShadow?WXGRim26Shadow(d,s):WXGRim26Alpha(d,f.nx,f.ny,s);
        }
        double v=sum/(n*n);
        bytes[j*stride+i]=(unsigned char)lround((v<0.?0.:v>1.?1.:v)*255.);
    }
}

/* FIX125 (user, on the phone, with a screenshot: at the four outermost points
   the rim and the glass "poke out" in a little tip): the rim was an image
   computed from an outline of this file's own (the analytic field, FIX124
   corrected by a CPU rendering of the layer), under a clip by the glass'
   real one. Neither is the outline the render server draws on screen to the
   fraction of a pixel a 3-pixel rim needs: the rim sat up to half a pixel
   inside the glass' edge along the shoulders of a round end and reached it
   only where both touch the bounding box: the tips. No outline of our own
   any more: the rim is Core Animation borders on the glass' own continuous
   corner (as the three earlier styles' lines are), one pixel wider each,
   all starting at the outline, their opacities chosen so that the rings
   between their inner edges show the profile:

       ring m (m = 0 outermost), one pixel deep: the level L_m, the mean of
       the profile over that pixel; band j (m + 1 pixels wide) lies over
       rings 0..j, so ring m shows 1 - prod_{j >= m} (1 - a_j) = L_m, i.e.
       a_m = 1 - (1 - L_m) / (1 - L_{m+1})   (levels never rise inward).

   Two such sets: the lights' (across the edge, WXGRim26Across; under a mask
   of the level along the outline, WXGRim26Along) and the faint line's
   (WXGRim26Ring, no mask), one over the other: exactly WXGRim26Alpha. */
#define WXG_RIM26_MAX_BANDS 20
typedef struct { int count; double width[WXG_RIM26_MAX_BANDS],alpha[WXG_RIM26_MAX_BANDS],level[WXG_RIM26_MAX_BANDS]; } WXGRim26Bands;
/* which: 0 the lights' profile, 1 the faint line's. */
static inline double WXGRim26Profile(int which,double d,WXGRim26Shape s) {
    return which?WXGRim26Ring(d,s):WXGRim26Across(d,s);
}
static inline WXGRim26Bands WXGRim26BandsFor(int which,WXGRim26Shape s,double scale) {
    WXGRim26Bands b;b.count=0;
    double h=s.height>.05?s.height:.05,px=1./(scale>0.?scale:1.);
    int n=(int)ceil(h/px-1e-6);
    n=n<1?1:n>WXG_RIM26_MAX_BANDS?WXG_RIM26_MAX_BANDS:n;
    double depth=n*px>h?n*px:h,step=depth/n;   /* more than the bands can hold: wider rings */
    for(int m=0;m<n;m++) {
        double sum=0;const int k=16;
        for(int i=0;i<k;i++)sum+=WXGRim26Profile(which,(m+(i+.5)/k)*step,s);   /* 0 past the height: the last ring's share of it */
        b.level[m]=sum/k;
    }
    for(int m=n-2;m>=0;m--)if(b.level[m]<b.level[m+1])b.level[m]=b.level[m+1];
    for(int m=0;m<n;m++) {
        double inner=m+1<n?b.level[m+1]:0.,a=inner>=1.?0.:1.-(1.-b.level[m])/(1.-inner);
        b.width[m]=(m+1)*step;b.alpha[m]=a<0.?0.:a>1.?1.:a;
    }
    b.count=n;
    return b;
}
/* What ring m shows under those bands (for the tests). */
static inline double WXGRim26BandsShown(WXGRim26Bands b,int m) {
    double through=1.;
    for(int j=m;j<b.count;j++)through*=1.-b.alpha[j];
    return 1.-through;
}
#endif
