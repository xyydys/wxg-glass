#ifndef WXG_RIM26_H
#define WXG_RIM26_H
#include <math.h>
#include "WXGOptics.h"
#include "WXGRimGlow.h"
/* FIX122 F / G iOS 26 边框 (user, 11-09, with two zoomed screenshots of an
   iOS 26 button): two rim styles and an inner shadow, standalone (the three
   earlier styles are left as they are).

   Measured on the screenshots: across the edge the line is a peak about
   0.45 pt inside the outline, rising over ~0.25 pt (sigma) from outside
   and falling over ~0.42 pt inward; its colour is what lies under it,
   brightened (x1.84) and more saturated (x1.29); along the outline the
   brightness follows |cos(angle - 135 deg)| at a constant width.

   FIX122 G (user, on the phone: far worse than the sketches, "叠浅叠深
   should be that colour made lighter and deeper, not white and black", and
   the phone ran hot): F drew each profile as dozens of nested Core
   Animation borders under nested masks, two full-resolution blurred
   backdrops per glass. Now every part is one image computed per pixel with
   exactly the sketch's formulas (and cached), stretched along straight
   edges (nine-part stretch): the line's mask over one low-resolution,
   blurred, brightened and saturated sample of what lies under the rim;
   the lighter / deeper flanks and the shadow as plain white / black
   images whose alpha is the line's own profile times their share, so they
   only ever lighten or deepen the line's colour where the line is. */
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
/* The level at depth t (points inward from the outline), amplitude included. */
static inline double WXGRim26Level(double t,WXGRim26Profile p) {
    if(t<0.)return 0.;
    return (p.amplitude<0.?0.:p.amplitude>1.?1.:p.amplitude)*WXGRim26Rise(t,p)*WXGRim26Fall(t,p);
}
/* How far in anything is drawn: 3 sigmas past the centre (5 lengths). */
static inline double WXGRim26Reach(WXGRim26Profile p) {
    double s=p.inner>1e-3?p.inner:1e-3;
    return p.exponential?5.*s:(p.centre>0.?p.centre:0.)+3.*s;
}

/* The parts and their shares across the edge (no strength). */
typedef enum { WXGRim26PartLine=0,WXGRim26PartPale=1,WXGRim26PartLighter=2,WXGRim26PartDeeper=3,WXGRim26PartShadow=4 } WXGRim26Part;
typedef struct {
    double peak,outer,inner;            /* the line */
    double angle,endLevel,sharpness;    /* along the outline (WXGRimGlowLevel) */
    double paleShift,paleInner;         /* 自身色: the paler copy's centre (from the peak) and inner fall */
    double split,splitWidth;            /* 叠浅叠深: where the lighter outer flank turns into the deeper inner one (from the peak), over how much */
    double shadowLength;
} WXGRim26Shape;
static inline double WXGRim26Smooth(double x) {x=x<0.?0.:x>1.?1.:x;return x*x*(3.-2.*x);}
static inline double WXGRim26Share(WXGRim26Part part,double d,WXGRim26Shape s) {
    if(d<0.)return 0.;
    WXGRim26Profile line={s.peak,s.outer,s.inner,1,0};
    switch(part) {
        case WXGRim26PartLine:return WXGRim26Level(d,line);
        case WXGRim26PartPale:{WXGRim26Profile p={s.peak+s.paleShift>0.?s.peak+s.paleShift:0.,s.outer,s.paleInner,1,0};return WXGRim26Level(d,p);}
        case WXGRim26PartLighter:
        case WXGRim26PartDeeper: {
            double c=s.peak+s.split,w=s.splitWidth>.01?s.splitWidth:.01;
            double outer=1.-WXGRim26Smooth((d-(c-w))/(2.*w));
            return WXGRim26Level(d,line)*(part==WXGRim26PartLighter?outer:1.-outer);
        }
        case WXGRim26PartShadow:{WXGRim26Profile p={0,0,s.shadowLength,1,1};return WXGRim26Level(d,p);}
    }
    return 0.;
}
static inline double WXGRim26PartReach(WXGRim26Part part,WXGRim26Shape s) {
    WXGRim26Profile line={s.peak,s.outer,s.inner,1,0};
    if(part==WXGRim26PartShadow){WXGRim26Profile p={0,0,s.shadowLength,1,1};return WXGRim26Reach(p);}
    if(part==WXGRim26PartPale){WXGRim26Profile p={s.peak+s.paleShift>0.?s.peak+s.paleShift:0.,s.outer,s.paleInner,1,0};
        double a=WXGRim26Reach(p),b=WXGRim26Reach(line);return a>b?a:b;}
    return WXGRim26Reach(line);
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
/* Fills one byte per pixel (0..255): coverage of the outline (anti-aliased),
   times the level along the outline (unless levelOff), times the part's
   share across the edge, times `strength`; 2 x 2 samples per pixel. */
static inline void WXGRim26Fill(unsigned char *bytes,int stride,WXGRim26Canvas c,double r,double scale,WXGRim26Part part,WXGRim26Shape s,
                                int levelOff,double strength) {
    strength=strength<0.?0.:strength>1.?1.:strength;
    for(int j=0;j<c.rows;j++)for(int i=0;i<c.columns;i++) {
        double sum=0;
        for(int sy=0;sy<2;sy++)for(int sx=0;sx<2;sx++) {
            double x=(i+.25+.5*sx)/scale-c.width*.5,y=(j+.25+.5*sy)/scale-c.height*.5;
            WXGShapeSample f=WXGRim26Field(x,y,c,r);
            double cover=.5-f.distance*scale;cover=cover<0.?0.:cover>1.?1.:cover;
            if(cover<=0.)continue;
            double d=-f.distance;
            double level=levelOff?1.:WXGRimGlowLevel(f.nx,f.ny,s.angle,s.endLevel,s.sharpness);
            sum+=cover*level*WXGRim26Share(part,d<0.?0.:d,s);
        }
        double v=sum*.25*strength;
        bytes[j*stride+i]=(unsigned char)lround((v<0.?0.:v>1.?1.:v)*255.);
    }
}
#endif
