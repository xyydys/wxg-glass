#include "../Sources/WXGMotion.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // A dropped frame followed by rapid reversal must remain finite and settle.
    const double delays[]={1./60,1./120,.3,1./30,1./60};
    double x=45,v=0;
    for(int i=0;i<1200;i++) {
        double target=i<70?325:(i<150?45:220);
        WXGSpring(&x,&v,target,620,39,delays[i%5]);
        assert(isfinite(x) && isfinite(v)); assert(x>-50 && x<450);
    }
    assert(fabs(x-220)<.001);
    // An OS cancellation must let the pressed lens return without oscillating forever.
    double p=1,pv=8;
    for(int i=0;i<600;i++) WXGSpring(&p,&pv,0,420,31,1./60);
    assert(fabs(p)<.001 && fabs(pv)<.001);
    assert(WXGSlot(-500,18,320,4)==0);
    assert(WXGSlot(900,18,320,4)==3);
    assert(WXGSlot(178,18,320,4)==2);
    assert(WXGSlot(100,18,0,4)==0);
    puts("PASS: dropped-frame spring, reversal, release, slot bounds.");
    return 0;
}
