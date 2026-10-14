#include "../Sources/WXGMonochrome.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void){
    uint8_t p[256*4];memset(p,0,sizeof p);assert(!WXGMonochromeRGBA(p,256));
    for(unsigned color=0;color<=255;color++){
        for(unsigned i=0;i<256;i++){unsigned a=i;p[i*4]=p[i*4+1]=p[i*4+2]=(uint8_t)(color*a/255);p[i*4+3]=(uint8_t)a;}
        assert(WXGMonochromeRGBA(p,256));
    }
    for(unsigned i=0;i<256;i++){p[i*4]=0;p[i*4+1]=160;p[i*4+2]=40;p[i*4+3]=255;}
    assert(!WXGMonochromeRGBA(p,256));
    for(unsigned i=0;i<256;i++){p[i*4]=p[i*4+1]=p[i*4+2]=(uint8_t)i;p[i*4+3]=255;}
    assert(!WXGMonochromeRGBA(p,256));
    puts("PASS: 256 antialiased single-ink palettes; transparent, colored and shaded artwork remain distinct.");return 0;
}
