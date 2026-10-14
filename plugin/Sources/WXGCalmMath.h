#ifndef WXG_CALM_MATH_H
#define WXG_CALM_MATH_H
#include <math.h>
#include <stddef.h>
#include <stdint.h>
/* FIX85: 平稳背景时加强材质 (WXGCalmBackdrop.m), pure C.
   How much the background behind a glass varies: the area behind the glass
   (plus a margin) is rendered small (about 4 pt per pixel, which already
   averages away text strokes and fine texture), and its colour spread is
   measured as the standard deviation of R, G and B, averaged, on a 0..1
   scale. A plain page is about 0, a page of text a few hundredths, a photo
   or a wallpaper 0.1-0.3.
   Calm (0..1) = 1 below `threshold`, 0 above threshold + range, a smoothstep
   between. The glass's material coverage moves toward the calm value by
   that much, eased over successive measurements. */
static inline double WXGCalmSigma(const uint8_t *rgba,size_t stride,int x0,int y0,int x1,int y1) {
    if(!rgba || x1<=x0 || y1<=y0)return 0;
    double s[3]={0,0,0},q[3]={0,0,0};double n=0;
    for(int y=y0;y<y1;y++) {
        const uint8_t *row=rgba+(size_t)y*stride;
        for(int x=x0;x<x1;x++) {
            const uint8_t *p=row+(size_t)x*4;
            for(int c=0;c<3;c++){double v=p[c]/255.;s[c]+=v;q[c]+=v*v;}
            n+=1;
        }
    }
    if(n<1)return 0;
    double total=0;
    for(int c=0;c<3;c++){double m=s[c]/n,var=q[c]/n-m*m;total+=var>0?var:0;}
    return sqrt(total/3.);
}
static inline double WXGCalmTarget(double sigma,double threshold,double range) {
    if(!isfinite(sigma))return 0;
    if(!(range>1e-6))range=1e-6;
    double t=(sigma-threshold)/range;
    t=t<0?0:t>1?1:t;
    return 1.-t*t*(3.-2.*t);
}
/* One measurement's step toward the new target; a glass measured for the
   first time takes it at once (no fade-in on a page that just appeared). */
static inline double WXGCalmStep(double current,double target,int fresh,double rate) {
    if(fresh || !isfinite(current))return target;
    if(!(rate>0))rate=0;
    if(rate>1)rate=1;
    return current+(target-current)*rate;
}
#endif
