#include "../Sources/WXGTelegramInk.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(sizeof(WXGTelegramPixel)==4);
    for(int a=0;a<256;a++)for(int coverage=0;coverage<256;coverage++) {
        WXGTelegramPixel p=WXGTelegramCoveredInk((WXGTelegramPixel){255,128,0,a},coverage);
        assert(p.a==(a*coverage+127)/255);
        assert(p.r==p.a && p.g==(128*p.a+127)/255 && p.b==0);
        WXGTelegramPixel white=WXGTelegramCoveredInk((WXGTelegramPixel){255,255,255,255},coverage);
        assert(white.a==coverage && white.r==coverage && white.g==coverage && white.b==coverage);
    }
    puts("PASS: Telegram foreground retains source coverage, edge alpha and premultiplied tint.");
    return 0;
}
