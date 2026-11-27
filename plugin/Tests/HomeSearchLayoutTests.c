#include <assert.h>
#include <stdio.h>
#include "../Sources/WXGHomeSearchLayout.h"

int main(void) {
    WXGRect field={8,8,424,36}; /* Native field reported on the 440 pt home page. */
    assert(WXGHomeSearchFieldReady(field,440,52));
    assert(!WXGHomeSearchFieldReady((WXGRect){8,-10,424,36},440,52));
    assert(!WXGHomeSearchFieldReady((WXGRect){8,48,424,36},440,52));
    assert(!WXGHomeSearchFieldReady(field,0,52));
    assert(!WXGHomeSearchFieldReady(field,440,0));
    assert(!WXGHomeSearchFieldReady((WXGRect){8,8,NAN,36},440,52));
    assert(WXGHomeSearchRequiredHeaderHeight(field,52,0,-1)==52);
    // A custom width alone must never grow a header with zero bottom padding.
    assert(WXGHomeSearchRequiredHeaderHeight(field,44,0,-1)==44);
    assert(WXGHomeSearchRequiredHeaderHeight(field,52,48,-1)==64);
    assert(WXGHomeSearchRequiredHeaderHeight(field,52,0,20)==64);
    WXGHomeGroupLayout rows=WXGHomeGroupBelowSearch(52,44,44,36,8);
    assert(rows.groupY==52 && rows.headerHeight==96 && rows.bottomGap==8);
    rows=WXGHomeGroupBelowSearch(44,44,70,48,0);
    assert(rows.groupY==70 && rows.headerHeight==118 && rows.bottomGap==0);
    rows=WXGHomeGroupBelowSearch(52,44,64,48,32);
    assert(rows.groupY==96 && rows.headerHeight==152 && rows.bottomGap==8);
    WXGRect search=WXGHomeRowRect(field,440,90,48,12);
    WXGRect group=WXGHomeRowRect(field,440,75,26,-1);
    assert(search.x==22 && search.w==396 && search.h==48 && search.y==12);
    assert(group.x==55 && group.w==330 && group.h==26);
    assert(WXGHomeRowRect(field,440,0,0,-1).w==424);
    assert(WXGHomeRowRect(field,440,0,0,-1).h==36);
    assert(WXGHomeHeaderLeading(0,0,0,88)==88);
    assert(WXGHomeHeaderLeading(0,88,0,88)==0);
    assert(WXGHomeHeaderLeading(88,0,0,88)==0);
    assert(WXGHomeShouldReveal(-36,-88,96,false));
    assert(!WXGHomeShouldReveal(-88,-88,96,false));
    assert(!WXGHomeShouldReveal(-36,-88,96,true));
    assert(!WXGHomeShouldReveal(240,-88,96,false));
    assert(WXGHomeShouldReveal(0,-88,64,false));
    assert(!WXGHomeShouldReveal(0,-88,64,true));
    puts("HomeSearchLayoutTests: native field readiness and vertical header reservation passed.");
    return 0;
}
