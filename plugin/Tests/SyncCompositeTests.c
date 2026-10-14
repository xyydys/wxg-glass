#include <assert.h>
#include <math.h>
#include <stdio.h>
/* Mirrors wxgSyncBase / wxgOver in WXGGlass.metal (one channel). Core
   Animation composites a premultiplied layer over the backdrop B as
   out = c + B*(1-a). The hybrid band must give w*F + (1-w)*mix(B,tint,k). */
static void syncBase(double face,double w,double k,double tint,double *c,double *a){*c=face*w+(1-w)*k*tint;*a=1-(1-w)*(1-k);}
static double mixd(double x,double y,double t){return x+(y-x)*t;}
int main(void) {
    double worst=0;
    for(int i=0;i<=20;i++)for(int j=0;j<=20;j++)for(int m=0;m<=10;m++)for(int n=0;n<=10;n++) {
        double w=i/20.,k=j/20.,B=m/10.,F=n/10.,tint=.37,c,a;
        syncBase(F,w,k,tint,&c,&a);
        double shown=c+B*(1-a),want=w*F+(1-w)*mixd(B,tint,k);
        if(fabs(shown-want)>worst)worst=fabs(shown-want);
        assert(a>=0 && a<=1 && c>=-1e-12 && c<=a+1e-12);   /* valid premultiplied colour */
    }
    assert(worst<1e-12);
    /* Band ends: w=1 is exactly the readback face, w=0 exactly the tinted live backdrop. */
    {double c,a;syncBase(.8,1,.4,.2,&c,&a);assert(fabs(c-.8)<1e-12 && fabs(a-1)<1e-12);}
    {double c,a;syncBase(.8,0,.4,.2,&c,&a);assert(fabs(c+.5*(1-a)-mixd(.5,.2,.4))<1e-12);}
    /* Over-composition of rim/selection/icons equals sequential mix when the base is opaque (readback path). */
    {double base=.6,col=.9,s=.35,over=col*s+base*(1-s);assert(fabs(over-mixd(base,col,s))<1e-12);}
    puts("PASS: render-server overlay algebra: premultiplied veil + hybrid band over a live backdrop equals w*F+(1-w)*mix(B,tint,k) for all weights; rim/selection/icon over-composition matches the readback mix.");
    return 0;
}
