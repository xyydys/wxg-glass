#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGRim26Mask.h"

// A stationary striped backdrop with an analytical box integral. Crop and
// full-window samples always share the same backdrop, mask and capture grid.
static double colour(double x) {return .5+.4*sin(.83*x+.41);}

static double texel(double centre,double density,double low,double high) {
    double left=centre-.5/density,right=centre+.5/density;
    double a=fmax(left,low),b=fmin(right,high);
    // Clamp to the edge for the part of a source texel outside the capture.
    double integral=(a-left)*colour(a)+(right-b)*colour(b)
                   +.5*(b-a)+.4/.83*(cos(.83*a+.41)-cos(.83*b+.41));
    return integral*density;
}

static double sample(double x,double density,double phase,double low,double high) {
    double grid=x*density-phase;
    int i=(int)floor(grid);
    int first=(int)ceil(low*density-phase),last=(int)floor(high*density-phase);
    assert(first<=last);
    double a=texel((fmin(last,fmax(first,i))+phase)/density,density,low,high);
    double b=texel((fmin(last,fmax(first,i+1))+phase)/density,density,low,high);
    return a+(grid-i)*(b-a);
}

static double *axisErrors(int pixels,double start,double screen,double capture,double padding) {
    double *errors=calloc((size_t)pixels,sizeof *errors);
    assert(errors);
    double low=start-padding,high=start+pixels/screen+padding;
    for(int i=0;i<pixels;i++) {
        double x=start+(i+.5)/screen;
        for(int p=0;p<32;p++) {
            double phase=p/32.;
            double reference=sample(x,capture,phase,-10000.,10000.);
            double cropped=sample(x,capture,phase,low,high);
            errors[i]=fmax(errors[i],fabs(cropped-reference));
        }
    }
    return errors;
}

static void composite(double w,double h,double screen,double capture,double ox,double oy,
                      double padding,double tips[4],double *peak) {
    double r=.5*fmin(w,h);
    WXGRim26Shape shape={1.005,.7,45.,1.05,1.,1.,.04,0.,.1886};
    WXGRim26MaskAxis x=WXGRim26MaskAxisFor(ox,w,r,shape.height,screen);
    WXGRim26MaskAxis y=WXGRim26MaskAxisFor(oy,h,r,shape.height,screen);
    uint8_t *alpha=malloc((size_t)x.pixels*y.pixels);
    assert(alpha && WXGRim26DrawMask(alpha,x,y,r,screen,shape));
    int width=(int)lround((w+x.leading+x.trailing)*screen);
    int height=(int)lround((h+y.leading+y.trailing)*screen);
    double *ex=axisErrors(width,ox-x.leading,screen,capture,padding);
    double *ey=axisErrors(height,oy-y.leading,screen,capture,padding);
    for(int j=0;j<height;j++)for(int i=0;i<width;i++) {
        int tx=x.cap && i>=x.cap?(int)fmax(x.cap,i-(width-x.pixels)):i;
        int ty=y.cap && j>=y.cap?(int)fmax(y.cap,j-(height-y.pixels)):j;
        double coverage=alpha[(size_t)ty*x.pixels+tx]/255.;
        double delta=coverage*fmax(ex[i],ey[j]); // horizontal and vertical colour channels
        *peak=fmax(*peak,delta);
        double dx=(i+.5)/screen-x.leading-w*.5,dy=(j+.5)/screen-y.leading-h*.5;
        if(fabs(dy)<h*.08 && fabs(dx)>w*.4) {
            int side=dx<0.?0:1;
            tips[side]=fmax(tips[side],delta);
        }
        if(fabs(dx)<w*.08 && fabs(dy)>h*.4) {
            int side=dy<0.?2:3;
            tips[side]=fmax(tips[side],delta);
        }
    }
    free(alpha);free(ex);free(ey);
}

int main(void) {
    double rates[]={.1,.25,.37,.5,.75,1.};
    double widths[]={41.468988,53.,201.25};
    double tips[4]={0},peak=0.;
    for(int screen=1;screen<=3;screen++)for(unsigned k=0;k<sizeof rates/sizeof rates[0];k++) {
        double capture=rates[k],padding=WXGRim26CapturePadding(capture,screen);
        assert(fabs(padding*screen-round(padding*screen))<1e-10);
        for(unsigned i=0;i<sizeof widths/sizeof widths[0];i++)for(int p=0;p<3;p++) {
            composite(widths[i],41.468988,screen,capture,19.8+p*.25,-11.3-p*.27,padding,tips,&peak);
        }
    }
    assert(peak<1e-10 && WXGRim26CapturePadding(0.,3.)==0.);
    // Negative control using UI30's actual guard on the reported round button.
    double old[4]={0},oldPeak=0.,diameter=41.468988;
    double ox=118.78/3.-diameter*.5,oy=113.99/3.-diameter*.5;
    composite(diameter,diameter,3.,.5,ox,oy,ceil(1./.5)/3.,old,&oldPeak);
    for(int i=0;i<4;i++)assert(old[i]>1./255.);
    printf("PASS: live rim against full backdrop (1/2/3x, 0.1–1 capture px/pt), max error %.2g; "
           "old guard at 3x, 0.5 px/pt, L/R/T/B errors %.3f/%.3f/%.3f/%.3f.\n",
           peak,old[0],old[1],old[2],old[3]);
    return 0;
}
