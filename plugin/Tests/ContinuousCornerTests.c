/* FIX96: the capsule's optical field follows Core Animation's continuous
   corners (Sources/WXGOptics.h WXGContinuousDeviation / WXGContinuousCorrection),
   as measured on the tester's phone (FIX93 screenshot, 3x): the dock's lens
   (93.8 x 74.5 pt) and the dock (321 x 63 pt) gave the same curve. */
#include "../Sources/WXGOptics.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
static float deg(float d){return d*3.14159265f/180.f;}
int main(void) {
    /* The measured curve (deviation / R by angle, the dock's end, bins of 4 degrees). */
    const float phi[]={-20,-12,-4,0,4,8,12,16,20,24,28,32,36,40,44,48,56,64,72,80,88};
    const float meas[]={-.0003f,-.0018f,-.0068f,-.0102f,-.0121f,-.0117f,-.0099f,-.0068f,-.0032f,.0006f,.0038f,.0063f,.0075f,.0087f,.0083f,.0072f,.0054f,.0044f,.0034f,.0025f,.0001f};
    float worst=0;
    for(unsigned i=0;i<sizeof phi/sizeof *phi;i++){float e=fabsf(WXGContinuousDeviation(deg(phi[i]+2))-meas[i]);if(e>worst)worst=e;}
    CHECK(worst<.0025f,"model vs measured: worst %.4f R",worst);
    CHECK(WXGContinuousDeviation(deg(-30))==0.f && WXGContinuousDeviation(deg(90))==0.f && WXGContinuousDeviation(deg(95))==0.f,"zero outside -24..90");
    /* The field: the circle's for a round shape, continuous for a capsule. */
    WXGShapeSample round=WXGCapsuleOpticalField(20,20,60,60);
    float c=sqrtf(800.f)-30.f;
    CHECK(fabsf(round.distance-c)<1e-4f,"aspect 1: the circle (%.4f vs %.4f)",round.distance,c);
    float w=93.8f,h=74.5f,r=h*.5f,join=w*.5f-r;
    /* Just inside the join the outline runs about 1.2% R lower than the circle's. */
    WXGShapeSample top=WXGCapsuleOpticalField(join+r*sinf(deg(6)),r*cosf(deg(6)),w,h);
    CHECK(top.distance>.009f*r && top.distance<.014f*r,"join: the circle's point is outside by %.3f pt",top.distance);
    /* Near 42 degrees fuller: the circle's point lies inside by ~0.9% R. */
    WXGShapeSample diag=WXGCapsuleOpticalField(join+r*sinf(deg(42)),r*cosf(deg(42)),w,h);
    CHECK(diag.distance<-.007f*r && diag.distance>-.011f*r,"42 deg: %.3f pt",diag.distance);
    /* The very end and the top centre stay on the bounds. */
    CHECK(fabsf(WXGCapsuleOpticalField(w*.5f,0,w,h).distance)<1e-3f && fabsf(WXGCapsuleOpticalField(0,31.5f,321,63).distance)<1e-3f &&
          fabsf(WXGCapsuleOpticalField(0,r,w,h).distance)<.002f*r,"bounds");
    /* Continuous: no step between neighbouring points anywhere in the shape. */
    float jump=0;
    for(float y=-r;y<=r;y+=.25f)for(float x=-w*.5f;x<w*.5f;x+=.25f){
        float a=WXGCapsuleOpticalField(x,y,w,h).distance,b=WXGCapsuleOpticalField(x+.25f,y,w,h).distance;
        if(fabsf(a-b)>jump)jump=fabsf(a-b);
    }
    CHECK(jump<.30f,"largest change over 0.25 pt: %.3f",jump);
    /* Mirror symmetric, and a vertical capsule is the horizontal one turned. */
    CHECK(fabsf(WXGCapsuleOpticalField(30,20,w,h).distance-WXGCapsuleOpticalField(-30,-20,w,h).distance)<1e-5f,"symmetric");
    CHECK(fabsf(WXGCapsuleOpticalField(30,20,w,h).distance-WXGCapsuleOpticalField(20,30,h,w).distance)<1e-4f,"turned");
    /* Blend: aspect 1.15 circle, 1.25 continuous. */
    CHECK(WXGContinuousCorrection(10,10,57.5f,50)==0.f && WXGContinuousCorrection(join+r*sinf(deg(6)),r*cosf(deg(6)),w,h)<0.f,"blend");
    if(failures){printf("ContinuousCornerTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: continuous corners (FIX96): the measured curve within %.4f R, circle for round shapes, join 1.2%% R inside, 42 deg fuller, bounds kept, no steps, symmetric.\n",worst);
    return 0;
}
