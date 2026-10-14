/* FIX85: the calm-background measure (Sources/WXGCalmMath.h). */
#include "../Sources/WXGCalmMath.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    enum {W=40,H=20};
    static uint8_t img[W*H*4];
    /* A plain colour: 0. */
    for(int i=0;i<W*H;i++){img[4*i]=240;img[4*i+1]=241;img[4*i+2]=242;img[4*i+3]=255;}
    CHECK(WXGCalmSigma(img,W*4,0,0,W,H)<1e-9,"plain");
    /* Black / white checkerboard: 0.5 in every channel. */
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){uint8_t v=((x+y)&1)?255:0;uint8_t *p=img+(y*W+x)*4;p[0]=p[1]=p[2]=v;p[3]=255;}
    CHECK(fabs(WXGCalmSigma(img,W*4,0,0,W,H)-.5)<1e-9,"checkerboard %f",WXGCalmSigma(img,W*4,0,0,W,H));
    /* Only red varies 0 / 255: sqrt(0.25 / 3). */
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){uint8_t *p=img+(y*W+x)*4;p[0]=(x&1)?255:0;p[1]=p[2]=128;p[3]=255;}
    CHECK(fabs(WXGCalmSigma(img,W*4,0,0,W,H)-sqrt(.25/3))<1e-9,"one channel");
    /* A sub-rectangle sees only its own pixels: a plain left half. */
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){uint8_t *p=img+(y*W+x)*4;uint8_t v=x<W/2?200:(uint8_t)((x*37+y*11)&255);p[0]=p[1]=p[2]=v;p[3]=255;}
    CHECK(WXGCalmSigma(img,W*4,0,0,W/2,H)<1e-9 && WXGCalmSigma(img,W*4,W/2,0,W,H)>.1,"sub-rectangle");
    CHECK(WXGCalmSigma(img,W*4,5,5,5,9)==0 && WXGCalmSigma(NULL,0,0,0,1,1)==0,"empty");

    /* Target: 1 below the threshold, 0 above threshold + range, monotonic. */
    CHECK(WXGCalmTarget(0,.06,.05)==1 && WXGCalmTarget(.06,.06,.05)==1 && WXGCalmTarget(.11,.06,.05)==0 && WXGCalmTarget(.5,.06,.05)==0,"ends");
    CHECK(fabs(WXGCalmTarget(.085,.06,.05)-.5)<1e-12,"midpoint");
    for(double x=0;x<.3;x+=.001)CHECK(WXGCalmTarget(x,.06,.05)>=WXGCalmTarget(x+.001,.06,.05)-1e-12,"monotonic at %f",x);
    CHECK(WXGCalmTarget(NAN,.06,.05)==0 && WXGCalmTarget(.06,.06,0)==1 && WXGCalmTarget(.0601,.06,0)==0,"degenerate");

    /* Step: fresh takes the target, otherwise eases; clamps the rate. */
    CHECK(WXGCalmStep(0,1,1,.4)==1 && fabs(WXGCalmStep(0,1,0,.4)-.4)<1e-12 && WXGCalmStep(.3,1,0,5)==1 && WXGCalmStep(.3,1,0,-1)==.3 && WXGCalmStep(NAN,.7,0,.4)==.7,"step");
    double f=0;int steps=0;while(f<.95 && steps<100){f=WXGCalmStep(f,1,0,.45);++steps;}
    CHECK(steps==6,"0.45 per step reaches 95%% in 6 steps (%d)",steps);

    if(failures){printf("CalmMathTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: calm background (FIX85): colour spread 0 for a plain colour, 0.5 for black / white, per sub-rectangle; calm target ends, midpoint, monotonic; eased steps (fresh glass at once).\n");
    return 0;
}
