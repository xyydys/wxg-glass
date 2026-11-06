#ifndef WXG_RIM_DETAIL_H
#define WXG_RIM_DETAIL_H
#include <math.h>
/* Details on the classic rim (FIX75 / FIX79). The rim stays a Core
   Animation border (exact continuous corners, round buttons stay round)
   with its colour / opacity / width and the old diagonal fade mask; the
   details only shade its two sides and add an inner shadow. */
static inline double WXGRimDetailClamp(double x,double lo,double hi) {return x<lo?lo:x>hi?hi:x;}
/* FIX79: the line's two sides fade over their own widths (outer: from the
   outline inward, inner: from the line's inner edge outward), in steps of
   0.1 pt, down to `edge` at the very sides (1 = no fade). Every step is a
   Core Animation border on the rim's own continuous corners, so the shape
   is exactly the rim's.

   Fading the opacity: nested bands, band j from t = outer*j/N to
   w - inner*j/N (t measured from the outline inward), all drawn over each
   other; band j's opacity is chosen so that where bands 0..j overlap the
   opacity is L_j = edge + (1 - edge) j / N (the middle, every band, is 1).

   Darkening instead: the full line at full opacity, with black bands on top
   that start at the outline (outer side) or at the inner edge (inner side):
   band m covers m/N of that side's fade width, so the outermost step has
   the most of them; their opacities make the step darken to 1 - L_q. */
#define WXG_RIM_MAX_STEPS 10
typedef struct { int count; double inset[2*WXG_RIM_MAX_STEPS+1],width[2*WXG_RIM_MAX_STEPS+1],alpha[2*WXG_RIM_MAX_STEPS+1]; } WXGRimBands;
static inline void WXGRimFitFades(double w,double *outer,double *inner) {
    double o=WXGRimDetailClamp(*outer,0,fmax(w,0)),i=WXGRimDetailClamp(*inner,0,fmax(w,0));
    if(o+i>w && o+i>0){double k=w/(o+i);o*=k;i*=k;}
    *outer=o;*inner=i;
}
static inline int WXGRimSteps(double outer,double inner) {
    double m=fmax(outer,inner);
    if(!(m>=.05))return 0;
    int n=(int)ceil(m/.1-1e-6);
    return n<1?1:n>WXG_RIM_MAX_STEPS?WXG_RIM_MAX_STEPS:n;
}
/* Whether the sides are shaded at all (otherwise the line is one plain band). */
static inline int WXGRimStepped(double w,double outer,double inner,double edge) {
    if(!(w>0) || !(edge<.999))return 0;
    WXGRimFitFades(w,&outer,&inner);
    return WXGRimSteps(outer,inner)>0;
}
static inline double WXGRimStepLevel(double edge,int j,int n) {return n>0?edge+(1-edge)*(double)j/n:1;}
static inline WXGRimBands WXGRimAlphaBands(double w,double outer,double inner,double edge) {
    WXGRimBands b;b.count=0;
    if(!(w>0))return b;
    edge=WXGRimDetailClamp(edge,0,1);WXGRimFitFades(w,&outer,&inner);
    int n=WXGRimSteps(outer,inner);
    if(n==0 || edge>=.999){b.inset[0]=0;b.width[0]=w;b.alpha[0]=1;b.count=1;return b;}
    double previous=0;
    for(int j=0;j<=n;j++) {
        double level=WXGRimStepLevel(edge,j,n);
        b.inset[j]=outer*j/n;b.width[j]=w-(outer+inner)*j/n;
        b.alpha[j]=j==0?level:(previous>=1?0:1-(1-level)/(1-previous));
        previous=level;
    }
    b.count=n+1;
    return b;
}
static inline WXGRimBands WXGRimDimBands(double w,double outer,double inner,double edge) {
    WXGRimBands b;b.count=0;
    if(!(w>0))return b;
    edge=WXGRimDetailClamp(edge,0,1);WXGRimFitFades(w,&outer,&inner);
    int n=WXGRimSteps(outer,inner);
    if(n==0 || edge>=.999)return b;
    for(int m=1;m<=n;m++) {
        /* band m covers steps q = 0..m-1 of a side; step q darkens to D_q */
        double dq=1-WXGRimStepLevel(edge,m-1,n),dnext=m<n?1-WXGRimStepLevel(edge,m,n):0;
        double alpha=dnext>=1?0:1-(1-dq)/(1-dnext);
        if(outer>1e-6){b.inset[b.count]=0;b.width[b.count]=outer*m/n;b.alpha[b.count]=alpha;++b.count;}
        if(inner>1e-6){b.inset[b.count]=w-inner*m/n;b.width[b.count]=inner*m/n;b.alpha[b.count]=alpha;++b.count;}
    }
    return b;
}
/* The level a stack produces at depth t (tests): 1 - prod(1 - alpha) of
   the bands covering t. */
static inline double WXGRimBandsCover(WXGRimBands b,double t) {
    double keep=1;
    for(int k=0;k<b.count;k++)if(t>b.inset[k] && t<b.inset[k]+b.width[k])keep*=1-b.alpha[k];
    return 1-keep;
}
/* FIX76: the line coloured from what is behind the glass (the glass's own
   backdrop capture, blurred): saturation (around the luma), contrast (around
   mid grey), gain, lift, then the rim's brightness setting (b <= 1 darkens,
   b > 1 mixes toward white), as one QuartzCore colour matrix (rows R,G,B,A
   of r,g,b,a,offset). Alpha is kept; the line's opacity is the mask's. */
typedef struct { float m[20]; } WXGRimMatrix;
static inline WXGRimMatrix WXGRimSampleMatrix(double saturation,double contrast,double gain,double lift,double brightness) {
    static const double luma[3]={.2126,.7152,.0722};
    double p=brightness<=1?WXGRimDetailClamp(brightness,0,1):2-WXGRimDetailClamp(brightness,1,2),q=brightness<=1?0:WXGRimDetailClamp(brightness,1,2)-1;
    WXGRimMatrix out;
    for(int i=0;i<20;i++)out.m[i]=0;
    for(int row=0;row<3;row++) {
        for(int column=0;column<3;column++)
            out.m[row*5+column]=(float)(p*gain*contrast*((1-saturation)*luma[column]+(row==column?saturation:0)));
        out.m[row*5+4]=(float)(p*(gain*.5*(1-contrast)+lift)+q);
    }
    out.m[18]=1.f;
    return out;
}
/* FIX114 J (user: the 取自背景 border with a colour laid over it, as the
   bubbles have): the colour taken from the background first mixed toward
   (r, g, b) by a (0 = as before, 1 = that colour alone), then m: one matrix
   again (m's colour part x (1 - a), plus a x m's colour part of (r, g, b) on
   the offsets). */
static inline WXGRimMatrix WXGRimOverlayMatrix(WXGRimMatrix m,double r,double g,double b,double a) {
    a=WXGRimDetailClamp(a,0,1);
    if(!(a>0))return m;
    const double c[3]={r,g,b};
    WXGRimMatrix out=m;
    for(int row=0;row<3;row++) {
        double add=0;
        for(int column=0;column<3;column++){add+=m.m[row*5+column]*c[column];out.m[row*5+column]=(float)(m.m[row*5+column]*(1-a));}
        out.m[row*5+4]=(float)(m.m[row*5+4]+a*add);
    }
    return out;
}
static inline void WXGRimApplyMatrix(WXGRimMatrix m,const double in[3],double out[3]) {
    for(int row=0;row<3;row++)out[row]=m.m[row*5]*in[0]+m.m[row*5+1]*in[1]+m.m[row*5+2]*in[2]+m.m[row*5+4];
}
#endif
