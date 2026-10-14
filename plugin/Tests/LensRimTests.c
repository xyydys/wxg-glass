#include "../Sources/WXGLensOptics.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
int main(void) {
    /* Ratio 1 is exactly the previous isotropic lens, for every normal. */
    for(int a=0;a<360;a+=5){float t=a*3.14159265f/180.f;assert(WXGLensEdgeWidth(cosf(t),sinf(t),12.35f,1,3)==12.35f);}
    /* Ends keep the full width, top/bottom get the ratio. */
    assert(fabsf(WXGLensEdgeWidth(1,0,12,.3f,3)-12)<1e-5f && fabsf(WXGLensEdgeWidth(-1,0,12,.3f,3)-12)<1e-5f);
    assert(fabsf(WXGLensEdgeWidth(0,1,12,.3f,3)-3.6f)<1e-5f && fabsf(WXGLensEdgeWidth(0,-1,12,.3f,3)-3.6f)<1e-5f);
    /* Monotonic from end to top; narrows fast leaving the end, slowly near the top. */
    float prev=1e9f;
    for(int a=0;a<=90;a++){float t=a*3.14159265f/180.f,w=WXGLensEdgeWidth(cosf(t),sinf(t),12,.3f,3);assert(w<=prev+1e-5f);prev=w;}
    float nearEnd=WXGLensEdgeWidth(1,0,12,.3f,3)-WXGLensEdgeWidth(cosf(.45f),sinf(.45f),12,.3f,3);
    float nearTop=WXGLensEdgeWidth(cosf(1.12f),sinf(1.12f),12,.3f,3)-WXGLensEdgeWidth(cosf(1.57f),sinf(1.57f),12,.3f,3);
    assert(nearEnd>nearTop*3);
    /* Degenerate normal (deep interior) and out-of-range input stay finite. */
    assert(WXGLensEdgeWidth(0,0,12,.3f,3)==12);
    assert(isfinite(WXGLensEdgeWidth(.5f,.5f,12,-4,99)));
    printf("lens rim 12 pt, top ratio 0.3, curve 3: end 12.0, 30deg %.1f, 60deg %.1f, top %.1f pt\n",
           WXGLensEdgeWidth(cosf(.5236f),sinf(.5236f),12,.3f,3),WXGLensEdgeWidth(cosf(1.0472f),sinf(1.0472f),12,.3f,3),WXGLensEdgeWidth(0,1,12,.3f,3));
    puts("PASS: lens rim width is the previous isotropic width at ratio 1, full at the ends, the ratio above/below the bar, monotonic, narrowing fast then slowly.");
    return 0;
}
