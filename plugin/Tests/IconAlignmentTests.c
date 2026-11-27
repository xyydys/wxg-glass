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
    // BGRA image, including row padding. A 1/255 fringe belongs to the
    // source artwork but remains below the diagnostic display threshold.
    uint8_t pixels[5*32]={0};
    pixels[1*32+1*4+3]=1; pixels[2*32+2*4+3]=255; pixels[3*32+4*4+3]=2;
    WXGRect all=WXGIconInkBounds(pixels+3,6,5,32,1);
    WXGRect strong=WXGIconInkBounds(pixels+3,6,5,32,16);
    assert(all.x==1 && all.y==1 && all.w==4 && all.h==3);
    assert(strong.x==2 && strong.y==2 && strong.w==1 && strong.h==1);
    assert(WXGIconInkBounds(pixels,6,5,32,1).w==0);
    // The 20pt Home plus is drawn at 20 2/3pt. With a two-source-pixel
    // transparent gutter its optical diameter and center must stay the same.
    WXGRect tight=WXGCenteredInk(41.5,41.5,20,20,62./3.);
    WXGRect padded=WXGIconTextureFrame(tight,20,2./3.);
    assert(fabs(padded.x+padded.w*.5-20.75)<1e-9);
    assert(fabs(padded.y+padded.h*.5-20.75)<1e-9);
    assert(fabs(padded.w*60./64.-tight.w)<1e-9);
    assert(padded.x<tight.x && padded.y<tight.y);
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
