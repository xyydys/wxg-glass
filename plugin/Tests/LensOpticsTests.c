#include "../Sources/WXGLensOptics.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    unsigned count=0;
    for(int s=0;s<=20;s++)for(int w=1;w<=60;w++)for(int d=0;d<=8;d++)for(int i=0;i<=100;i++) {
        WXGOpticalValues body={s,d,w},lens={20-s,8-d,61-w};
        float p=i*.01f;WXGOpticalValues out=WXGPressedOptics(body,lens,p);
        assert(out.refraction>=0 && out.refraction<=20 && out.dispersion>=0 && out.dispersion<=8 && out.edgeWidth>=1 && out.edgeWidth<=60);
        if(i==0)assert(out.refraction==body.refraction && out.dispersion==body.dispersion && out.edgeWidth==body.edgeWidth);
        if(i==100)assert(out.refraction==lens.refraction && out.dispersion==lens.dispersion && out.edgeWidth==lens.edgeWidth);
        WXGOpticalValues mirrored=WXGPressedOptics(body,body,p);
        assert(mirrored.refraction==body.refraction && mirrored.dispersion==body.dispersion && mirrored.edgeWidth==body.edgeWidth);
        // Identical settings must recover TEST9 displacement at every press amount.
        assert(WXGOpticalOffset(-5,mirrored.edgeWidth,mirrored.refraction)==WXGOpticalOffset(-5,w,s));count++;
    }
    assert(fabsf(WXGOpticalOffset(0,10,1.15f)-3.68f)<1e-5);
    assert(fabsf(WXGOpticalOffset(-5,10,1.15f)-.92f)<1e-5);
    assert(WXGOpticalOffset(-10,10,1.15f)==0);
    printf("PASS: %u independent lens profiles; resting/body isolation, mirrored TEST9 optics, endpoints and legacy 10pt range.\n",count);
}
