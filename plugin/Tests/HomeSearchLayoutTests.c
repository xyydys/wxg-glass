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
    WXGHomeGroupLayout both=WXGHomeRows(true,field,52,search,group.h,8);
    WXGHomeGroupLayout single=WXGHomeRows(false,field,52,search,group.h,8);
    assert(both.groupY==68 && both.headerHeight==102 && both.bottomGap==8);
    assert(single.groupY==12 && single.headerHeight==46 && single.bottomGap==8);
    search.h=64;
    assert(WXGHomeRows(false,field,52,search,group.h,32).headerHeight==single.headerHeight);
    assert(WXGHomeRows(true,field,52,search,group.h,0).groupY==76);

    // Exact fractional row sizes in the 3x diagnostic, including the measured 3 pt leading.
    search=WXGHomeRowRect(field,440,88.47332,45.76948547,-1);
    both=WXGHomeRows(true,field,52,search,45.76948547,8);
    assert(fabs(both.headerHeight+3-118.53897094)<1e-7);
    assert(fabs(WXGHomePixel(both.headerHeight+3,3)-(118.+2./3.))<1e-9);
    assert(WXGHomeOffsetAtDepth(560,118,118,88,34,3000,844)==472);
    assert(WXGHomeOffsetAtDepth(560,118,142,88,34,3000,844)==496);
    assert(WXGHomeOffsetAtDepth(40,118,142,88,34,3000,844)==-48);
    assert(WXGHomeOffsetAtDepth(90,118,64,88,34,3000,844)==-24);
    assert(WXGHomeOffsetAtDepth(560,118,118,96,34,3000,844)==464);
    assert(WXGHomeOffsetAtDepth(0,118,142,88,34,3000,844)==-88);
    assert(WXGHomeOffsetAtDepth(1000,118,118,88,34,1000,844)==190);
    assert(WXGHomeOffsetAtDepth(1000,118,118,88,34,600,844)==-88);
    // The ui20 trace alternated 108.67 and 52 on successive header assignments.
    assert(WXGHomeKeepsReservation(true,true,false,false,false,52,52));
    assert(WXGHomeKeepsReservation(true,false,true,false,false,55,52));
    assert(WXGHomeKeepsReservation(true,false,false,true,false,52,52));
    assert(!WXGHomeKeepsReservation(true,false,false,true,false,250,52));
    assert(!WXGHomeKeepsReservation(true,false,false,false,false,52,52));
    assert(WXGHomeKeepsReservation(false,false,false,false,true,0,52));
    assert(!WXGHomeKeepsReservation(false,false,false,false,false,0,52));
    WXGHomeGroupLayout ui20=WXGHomeRows(true,field,52,field,45.76948547,8);
    double reserved=WXGHomePixel(3.+ui20.headerHeight,3);
    assert(fabs(reserved-(108.+2./3.))<1e-7);
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
