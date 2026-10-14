#include "../Sources/WXGIconAlignment.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    // Supplied probe: native frame=(0,8,24,24) in a 40pt gesture host;
    // alpha box=(6,7,60,57) in the 72px image. Native glyph center x=12, not 20.
    WXGRect original={0,8,24,24},ink={6./72,7./72,60./72,57./72};
    WXGRect aligned=WXGAlignedImageFrame(original,ink,20,20,20.7);
    assert(fabs(aligned.x+(ink.x+ink.w*.5)*aligned.w-20)<1e-9);
    assert(fabs(aligned.y+(ink.y+ink.h*.5)*aligned.h-20)<1e-9);
    assert(fabs(aligned.w*ink.w-20.7)<1e-9);
    unsigned count=0;
    for(int h=32;h<=64;h++)for(int mx=12;mx<=30;mx++)for(int pad=0;pad<8;pad++) {
        WXGRect n={pad/24.,(pad+1)/24.,(24-2*pad)/24.,(22-2*pad)/24.};
        WXGRect result=WXGAlignedImageFrame(original,n,h*.5,h*.5,mx);
        assert(isfinite(result.x) && isfinite(result.y));
        assert(fabs(result.x+(n.x+n.w*.5)*result.w-h*.5)<1e-9);
        assert(fabs(result.y+(n.y+n.h*.5)*result.h-h*.5)<1e-9);
        assert(result.w*n.w<=mx+1e-9 && result.h*n.h<=mx+1e-9);count++;
    }
    printf("PASS: supplied star alpha box centered; %u padded icon/host/size combinations; gesture host geometry is an untouched input.\n",count);
}
