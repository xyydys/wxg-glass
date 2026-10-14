#include "../Sources/WXGDistanceField.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    enum { w=29,h=17 };uint8_t a[w*h];float out[w*h];
    for(int pattern=0;pattern<3;pattern++) {
        for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
            int inside=pattern==0?(x>=4 && x<=24 && y>=3 && y<=13):
                pattern==1?((x-14)*(x-14)+(y-8)*(y-8)<36):((x*3+y*7)%11<5);
            a[y*w+x]=inside?255:0;
        }
        for(int scale=1;scale<=3;scale++) {
            assert(WXGMakeNativeDistance(a,w,h,scale,out));
            for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
                float best=1e20f;
                for(int yy=0;yy<h;yy++) for(int xx=0;xx<w;xx++) if(a[yy*w+xx]!=a[y*w+x]) {
                    float squared=(x-xx)*(x-xx)+(y-yy)*(y-yy); if(squared<best)best=squared;
                }
                float expected=(sqrtf(best)-.5f)/scale*(a[y*w+x]?-1:1);
                assert(fabsf(out[y*w+x]-expected)<.00001f);
            }
        }
    }
    a[0]=64;assert(WXGMakeNativeDistance(a,w,h,2,out));assert(fabsf(out[0]-(.5f-64.f/255)/2)<.00001f);
    for(int i=0;i<w*h;i++) a[i]=0;
    assert(!WXGMakeNativeDistance(a,w,h,1,out));
    puts("PASS: native-alpha distance transform vs exhaustive nearest-pixel oracle, at 1x/2x/3x; antialias coverage and empty mask failure.");
    return 0;
}
