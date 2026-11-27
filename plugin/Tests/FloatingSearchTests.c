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
    // Captured 440 pt list. Pull, reversal, return and deep scrolling all use the
    // same pixel displacement, even if the native title host changes between calls.
    const double inset=100.+1./3., offsets[]={437.+2./3.,10.3,-20.3,-100.-1./3.,-100.5,-105.67,-173.67,-104.,-100.-1./3.};
    for(int scale=1;scale<=3;scale++) {
        double titleRest=WXGHomePixel(58.,scale);
        double searchRest=WXGHomeFloatingRowY(0,inset,0,11,-inset,scale);
        double groupRest=WXGHomeFloatingRowY(0,inset,0,55,-inset,scale);
        for(unsigned i=0;i<sizeof(offsets)/sizeof(offsets[0]);i++) {
            double pull=WXGHomePullTranslation(offsets[i],inset,scale);
            double searchY=WXGHomeFloatingRowY(0,inset,0,11,offsets[i],scale);
            double groupY=WXGHomeFloatingRowY(0,inset,0,55,offsets[i],scale);
            assert(fabs((searchY-(titleRest+pull))-(searchRest-titleRest))<1e-6);
            assert(fabs((groupY-searchY)-(groupRest-searchRest))<1e-6);
            if(offsets[i]>=-inset)assert(pull==0);
        }
    }
    puts("FloatingSearchTests: cold navigation, live header scroll, pull-down and native tap geometry passed.");
    return 0;
}
