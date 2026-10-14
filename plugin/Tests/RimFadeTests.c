#include "../Sources/WXGOptics.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    /* Both new fades at 0: exactly the FIX26 rim for every direction and side fade. */
    for(int a=0;a<360;a+=3)for(int f=0;f<=10;f++) {
        float t=a*3.14159265f/180.f,fade=f/10.f;
        assert(fabsf(WXGRimStrengthTLBR(cosf(t),sinf(t),fade,0,0)-WXGRimStrength(cosf(t),sinf(t),fade))<1e-6f);
    }
    /* Top and left edges follow the top-left fade, bottom and right the bottom-right fade (y down). */
    assert(fabsf(WXGRimStrengthTLBR(0,-1,1,.7f,0)-.3f)<1e-5f && fabsf(WXGRimStrengthTLBR(-1,0,1,.7f,0)-.3f)<1e-5f);
    assert(fabsf(WXGRimStrengthTLBR(0,1,1,.7f,.2f)-.8f)<1e-5f && fabsf(WXGRimStrengthTLBR(1,0,1,.7f,.2f)-.8f)<1e-5f);
    /* The side diagonals keep the side fade whatever the corner fades are. */
    float side=WXGRimStrengthTLBR(.70710678f,-.70710678f,1,.9f,.9f);
    assert(fabsf(side-WXGRimStrength(.70710678f,-.70710678f,1))<1e-5f);
    /* Continuous: no jump across the two side diagonals. */
    float before=WXGRimStrengthTLBR(cosf(-.7854f-1e-3f),sinf(-.7854f-1e-3f),1,.6f,.1f),after=WXGRimStrengthTLBR(cosf(-.7854f+1e-3f),sinf(-.7854f+1e-3f),1,.6f,.1f);
    assert(fabsf(before-after)<.02f);
    puts("PASS: rim top-left / bottom-right fades: identical to the previous rim at 0, per-side strengths, unchanged side diagonals, continuous.");
    return 0;
}
