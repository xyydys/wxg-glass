/* FIX122 F: iOS 26 边框's profiles as Core Animation band stacks (Sources/WXGRim26.h). */
#include "../Sources/WXGRim26.h"
#include <stdio.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    double fi[WXG_RIM_GLOW_MAX_BANDS],fw[WXG_RIM_GLOW_MAX_BANDS],fa[WXG_RIM_GLOW_MAX_BANDS];
    double ri[WXG_RIM_GLOW_MAX_BANDS],rw[WXG_RIM_GLOW_MAX_BANDS],ra[WXG_RIM_GLOW_MAX_BANDS];
    /* The measured line: peak .45 pt in, outer .25, inner .42; the pale,
       white and dark layers' shapes; the shadow. */
    WXGRim26Profile cases[]={{.45,.25,.42,1,0},{.30,.25,.15,.6,0},{.23,.16,.16,.1,0},{1.10,.35,.35,.1,0},{0,0,2.5,.06,1},{.45,.25,.42,.7,0}};
    double scales[]={2,3};
    for(size_t c=0;c<sizeof cases/sizeof *cases;c++)for(int s=0;s<2;s++) {
        WXGRim26Profile p=cases[c];double sc=scales[s];
        int nf=WXGRim26FallBands(p,sc,WXG_RIM_GLOW_MAX_BANDS,fi,fw,fa);
        int nr=WXGRim26RiseBands(p,sc,WXG_RIM_GLOW_MAX_BANDS,ri,rw,ra);
        CHECK(nf>=1 && nf<=WXG_RIM_GLOW_MAX_BANDS && nr>=1 && nr<=WXG_RIM_GLOW_MAX_BANDS,"%zu: counts %d %d",c,nf,nr);
        double reach=WXGRim26Reach(p);
        for(int k=0;k<nf;k++)CHECK(fi[k]==0 && fw[k]<=reach+1e-9 && fa[k]>=0 && fa[k]<=1,"%zu fall band %d",c,k);
        for(int k=0;k<nr;k++)CHECK(fabs(ri[k]+rw[k]-reach)<1e-9 && ra[k]>=0 && ra[k]<=1,"%zu rise band %d ends at the reach",c,k);
        /* The two stacks multiplied: the profile's light kept (each step
           its average), no point further off than a quarter-pixel step's
           share of the steepest slope allows. */
        double shownLight=0,wantLight=0,dev=0;
        for(double t=0.;t<reach+.1;t+=.001) {
            double shown=WXGRim26Cover(fi,fw,fa,nf,t)*WXGRim26Cover(ri,rw,ra,nr,t),want=WXGRim26Level(t,p);
            shownLight+=shown*.001;wantLight+=want*.001;if(fabs(shown-want)>dev)dev=fabs(shown-want);
        }
        CHECK(fabs(shownLight-wantLight)<=.01*wantLight+1e-6,"%zu @%gx: light kept (%.5f %.5f)",c,sc,shownLight,wantLight);
        CHECK(dev<=.25*(p.amplitude>0?p.amplitude:1)+.005,   /* a step is up to a sigma wide for the narrowest layers at 2x */"%zu @%gx: within a step (%.3f)",c,sc,dev);
        CHECK(WXGRim26Cover(fi,fw,fa,nf,reach+.01)==0,"%zu: nothing past the reach",c);
        CHECK(WXGRim26Cover(ri,rw,ra,nr,reach-.01)>.999,"%zu: the rise is solid inside",c);
    }
    /* The measured line's shape: peak at .45, the inner flank wider. */
    WXGRim26Profile m={.45,.25,.42,1,0};
    double best=0,at=0;for(double t=0;t<2;t+=.005){double v=WXGRim26Level(t,m);if(v>best){best=v;at=t;}}
    CHECK(fabs(at-.45)<.01 && fabs(best-1)<1e-9,"peak at .45 (%.3f)",at);
    double hiIn=0,hiOut=0;for(double t=.45;t<2;t+=.001)if(WXGRim26Level(t,m)>=.5)hiIn=t-.45;for(double t=.45;t>0;t-=.001)if(WXGRim26Level(t,m)>=.5)hiOut=.45-t;
    CHECK(hiIn/hiOut>1.5 && hiIn/hiOut<1.8,"inner half-width / outer = %.2f",hiIn/hiOut);
    CHECK(WXGRim26FallBands((WXGRim26Profile){.45,.25,.42,0,0},3,20,fi,fw,fa)==0,"amplitude 0: nothing");
    if(failures){printf("Rim26Tests: %d failure(s)\n",failures);return 1;}
    printf("PASS: iOS 26 rim (FIX122 F): falling stack nested from the outline, rising stack ending together, their product the asymmetric Gaussian (and the shadow's exponential) within a step, nothing past the reach, peak and flank ratio as measured.\n");
    return 0;
}
