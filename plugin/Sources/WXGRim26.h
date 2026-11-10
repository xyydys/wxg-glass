#ifndef WXG_RIM26_H
#define WXG_RIM26_H
#include <math.h>
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

   Here: alpha as one cached image per shape (computed per pixel, 4 x 4
   samples), as the mask of a colour-matrix copy of what lies under the rim
   (WXGGlassView.m). No blur, no bands, nothing per frame. */
typedef struct {
    double height,curve;        /* across the edge: how far in (pt), how much it has fallen there (0..1) */
    double angle,key,fill,spread; /* along the outline: the key light's direction (deg; 45 = lower right, 0 = bottom, 90 = right), the two lights' levels, the lobes' exponent */
    double ring;                /* the faint line all round */
    double shadowLength;        /* the optional inner shadow (not the system's) */
} WXGRim26Shape;
static inline double WXGRim26Clamp(double v,double lo,double hi) {return !(v==v)?lo:v<lo?lo:v>hi?hi:v;}
/* The two lights along the outline; (nx, ny) the outward direction, y down. */
static inline double WXGRim26Along(double nx,double ny,WXGRim26Shape s) {
    double r=WXGRim26Clamp(s.angle,-360,360)*M_PI/180.,c=nx*sin(r)+ny*cos(r);
    c=WXGRim26Clamp(c,-1,1);
    double p=s.spread>.05?s.spread:.05;
    double v=c>0.?s.key*pow(c,p):s.fill*pow(-c,p);
    return WXGRim26Clamp(v,0,1);
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
   `ext`: how far the corners' area reaches (the corner, or the part if it
   reaches further), within half the side. */
typedef struct { double width,height;int columns,rows;int stretchX,stretchY;double edgeX,edgeY; } WXGRim26Canvas;
static inline WXGRim26Canvas WXGRim26CanvasFor(double w,double h,double r,double reach,double scale) {
    WXGRim26Canvas c;
    double ext=(r>reach?r:reach)+1.;
    c.stretchX=w>2.*ext+2.;c.stretchY=h>2.*ext+2.;
    c.width=c.stretchX?2.*ext+2.:w;c.height=c.stretchY?2.*ext+2.:h;
    c.edgeX=c.stretchX?ext:0.;c.edgeY=c.stretchY?ext:0.;
    c.columns=(int)ceil(c.width*scale-1e-9);c.rows=(int)ceil(c.height*scale-1e-9);
    c.columns=c.columns<1?1:c.columns;c.rows=c.rows<1?1:c.rows;
    return c;
}
/* The field of the canvas' shape at (x, y) from its centre: a capsule as
   the glass' continuous outline (WXGCapsuleOpticalField), else a rounded
   rectangle. */
static inline WXGShapeSample WXGRim26Field(double x,double y,WXGRim26Canvas c,double r) {
    double half=(c.width<c.height?c.width:c.height)*.5;
    return r>=half-1e-3?WXGCapsuleOpticalField((float)x,(float)y,(float)c.width,(float)c.height)
                       :WXGRoundedOpticalField((float)x,(float)y,(float)c.width,(float)c.height,(float)r);
}
/* Fills one byte per pixel (0..255): the part's alpha, the mean of 4 x 4
   samples per pixel (so the hard inner cut is anti-aliased by coverage
   alone, as the system's own at the screen's scale). `bleed` (pixels): that
   far outside the outline counts as the outline itself, for a layer that is
   then clipped by the glass' own continuous corner (Core Animation's, the
   same clip as the body: the rim's outer edge is exactly the body's, also
   where this field's corner is a few tenths of a point off it); 0: the
   outline anti-aliased here. */
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
#endif
