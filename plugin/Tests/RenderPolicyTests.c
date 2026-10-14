#include "../Sources/WXGRenderPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(WXGEffectiveFPS(120,120)==120 && WXGEffectiveFPS(120,60)==60);
    assert(WXGEffectiveFPS(60,120)==60 && WXGEffectiveFPS(120,0)==60);
    assert(WXGEffectiveFPS(500,240)==120 && WXGEffectiveFPS(120,90)==90);
    assert(WXGBackdropInitialScale(3,60)==1 && WXGBackdropInitialScale(3,120)==2);
    for(int display=60;display<=120;display+=60)for(int n=1;n<=4;n*=2) {
        double last[4]={0};int count[4]={0};
        for(int frame=0;frame<display*10;frame++) {
            double timestamp=10.+(double)frame/display;
            for(int page=0;page<n;page++) {
                assert(WXGBackdropDue(timestamp,last[page],display,count[page]>0));
                count[page]++;last[page]=timestamp;
                assert(!WXGBackdropDue(timestamp,last[page],display,1));
            }
        }
        for(int page=0;page<n;page++)assert(count[page]==display*10);
    }
    // A requested 60 Hz capture on a 120 Hz screen samples every second tick,
    // with no additional reduction from the number of pages or consumers.
    double last=0;int count=0;
    for(int f=0;f<1200;f++)if(WXGBackdropDue(10+f/120.,last,60,count>0)){last=10+f/120.;++count;}
    assert(count==600);
    double scale=2;
    for(int i=0;i<100;i++){scale=WXGBackdropNextScale(scale,80,120,3,i+1);assert(scale>=1);}
    assert(scale==1);
    assert(WXGBackdropNextScale(1,1,120,3,120)==1.25);
    assert(WXGBackdropNextScale(1,1,120,3,119)==1);
    assert(WXGBackdropNextScale(2,1,120,3,120)==2);
    assert(WXGBackdropNextScale(1,1,120,1,120)==1);
    puts("PASS: no temporal round-robin, all 1/2/4 pages eligible at 60/120 Hz, user cap and duplicate callback respected; spatial cost adaptation bounded to 1–2x. Numerical policy only, not measured FPS.");
}
