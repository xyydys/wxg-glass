#include "../Sources/WXGHomeSearchLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // Exported 440pt home page: 52pt native header, 8pt field gap, 100 1/3pt navigation bottom.
    const double navBottom=100.+1./3., fieldTop=navBottom+8.;
    bool passThrough=false;
    for(int offset=0;offset<=80;offset+=40) {
        double y=WXGFloatSearchPlacement(fieldTop-offset,8.,0.,navBottom,true,navBottom,62.,&passThrough);
        assert(fabs(y-fieldTop)<1e-6);
        assert(passThrough==(offset==0));
    }
    // Cold table inset initially zero. Wait for the navigation row; a valid
    // row already gives the correct pin position before the inset catches up.
    assert(isnan(WXGFloatSearchPlacement(8.,8.,0.,0.,true,NAN,62.,&passThrough)));
    assert(isnan(WXGFloatSearchPlacement(8.,8.,0.,0.,true,44.,62.,&passThrough)));
    assert(fabs(WXGFloatSearchPlacement(8.,8.,0.,0.,true,navBottom,62.,&passThrough)-fieldTop)<1e-6);
    assert(!passThrough);
    // The natural field moves down with a pull and can receive the original tap.
    assert(fabs(WXGFloatSearchPlacement(fieldTop+40.,8.,0.,navBottom,true,navBottom,62.,&passThrough)-(fieldTop+40.))<1e-6);
    assert(passThrough);
    assert(WXGFloatSearchPlacement(-25.,8.,62.,12.,false,NAN,62.,&passThrough)==82.);
    assert(!passThrough);
    // On a shallow pull the table and the selected native title host can step
    // on different frames. The gap to the drawn title stays exact in pixels.
    static const double titles[]={78.,78.33,78.68,79.66,79.66,78.9,78.};
    static const double search[]={108.33,110.,110.1,111.9,112.6,110.,108.33};
    for(int scale=2;scale<=3;scale++) {
        double titleAtRest=WXGHomePixel(titles[0],scale);
        double gap=WXGHomePixel(search[0],scale)-titleAtRest;
        for(unsigned i=0;i<sizeof(titles)/sizeof(titles[0]);i++) {
            double title=WXGHomePixel(titles[i],scale);
            double attached=WXGHomePulledSearchY(search[i],title,gap,0.);
            assert(fabs((WXGHomePixel(attached,scale)-title)-gap)<1e-6);
            assert(fabs(WXGHomePulledSearchY(search[i],title,gap,1.)-search[i])<1e-6);
            assert(fabs(WXGHomePulledSearchY(search[i],title,gap,.5)-(attached+search[i])*.5)<1e-6);
        }
    }
    puts("FloatingSearchTests: cold navigation, live header scroll, pull-down and native tap geometry passed.");
    return 0;
}
