#include <assert.h>
#include <stdio.h>
#include "../Sources/WXGHomeSearchLayout.h"

int main(void) {
    // The static nav copy at y=78 survives throughout a Home pull on 26.6.
    assert(!WXGHomeUsesPullControls(1.,-1.,true));
    assert(WXGHomeUsesPullControls(-1.,1.,false));
    assert(!WXGHomeUsesPullControls(1.,0.,true));
    assert(WXGHomeUsesPullControls(0.,1.,false));
    assert(WXGHomeUsesPullControls(.03,.97,false));
    assert(!WXGHomeUsesPullControls(.97,.03,true));
    assert(WXGHomeUsesPullControls(.5,.5,true));
    assert(!WXGHomeUsesPullControls(.5,.5,false));
    assert(WXGHomeUsesPullControls(0.,0.,true));
    assert(!WXGHomeUsesPullControls(0.,0.,false));
    // Diagnostic 15: both copies are visible during the last layout of the
    // bounce. The taskbar parks its 44 pt button at y=22 1/3 for one frame.
    double navCenter=56.+1./3.+22.,parkedCenter=22.+1./3.+22.;
    assert(WXGHomePlusPullCenter(navCenter+47.,navCenter,46.)==navCenter+47.);
    assert(WXGHomePlusPullCenter(parkedCenter,navCenter,1.)==navCenter+1.);
    assert(WXGHomePlusPullCenter(parkedCenter,navCenter,0.)==navCenter);
    assert(WXGHomePlusPullCenter(navCenter,navCenter,0.)==navCenter);
    // An empty replacement may lay out behind the existing WCSearchBar.
    // A drawn replacement, genuine UIKit placeholder or active editor takes over.
    assert(WXGHomeWaitsForSearchArtwork(true,false,false,false));
    assert(!WXGHomeWaitsForSearchArtwork(true,true,false,false));
    assert(!WXGHomeWaitsForSearchArtwork(true,false,true,false));
    assert(!WXGHomeWaitsForSearchArtwork(true,false,false,true));
    assert(!WXGHomeWaitsForSearchArtwork(false,false,false,false));
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
    // ui22 capture 11: the return callback was already at -100 1/3 before
    // restoring the bookmark. Both inset sources then reported the same top.
    const double nav=100.+1./3., panel=956., panelRaw=panel-nav;
    // Capture 19: during an ordinary release the list reaches -100 1/3.
    // Its two native title/button copies can still lay out at different Y's.
    // Finishing the return to Home at the same offset must give the same row.
    const double rest=78.+1./3., offsets[]={-152.-1./3.,-141.-2./3.,-136.-1./3.,
        -129.-1./3.,-115.-2./3.,-108.-2./3.,-100.-2./3.,-nav,-nav,-nav,42.};
    double previous=INFINITY;
    for(unsigned i=0;i<sizeof(offsets)/sizeof(*offsets);i++) {
        double y=WXGHomeTitleRowCenter(rest,offsets[i],nav,3.,NAN);
        assert(fabs(y-(rest+fmax(0.,-offsets[i]-nav)))<1e-8 && y<=previous);
        previous=y;
    }
    assert(previous==rest && WXGHomeTitleRowCenter(rest,0.,0.,3.,NAN)==rest);
    assert(WXGHomeTitleRowCenter(rest,-panel,nav,3.,900.+2./3.)==900.+2./3.);
    assert(WXGHomeRestInset(nav,0,nav,3)==nav);
    assert(WXGHomeRestInset(nav,nav,2*nav,3)==nav);
    assert(WXGHomeRestInset(nav,nav+24,nav+24,3)==0);
    assert(WXGHomeRestInset(0,0,0,3)==0);
    assert(WXGHomeHasTwoNavigationInsets(nav,nav,2*nav,3));
    assert(!WXGHomeHasTwoNavigationInsets(nav,0,2*nav,3));
    assert(!WXGHomeHasTwoNavigationInsets(nav,2*nav,2*nav,3));
    assert(!WXGHomeHasTwoNavigationInsets(nav,nav+1,2*nav,3));
    assert(!WXGHomeHasTwoNavigationInsets(nav,panelRaw,panel,3));
    assert(!WXGHomeHasTwoNavigationInsets(nav,nav,2*nav+.4,3));
    assert(WXGHomeEffectiveTop(nav,0,nav,3)==nav);
    assert(WXGHomeEffectiveTop(nav,nav,2*nav,3)==nav);
    assert(WXGHomeEffectiveTop(nav,nav,nav,3)==nav);
    assert(WXGHomeEffectiveTop(nav,panelRaw,panel,3)==panel);
    assert(WXGHomeEffectiveTop(nav,24,nav+24,3)==nav+24);
    // UIKit can initially ignore a write or report the old policy for a layout.
    // A bookmark must never convert that transient duplicate into a scroll target.
    for(int i=0;i<3;i++) {
        double adjusted=i==2?nav:2*nav;
        double top=WXGHomeEffectiveTop(nav,nav,adjusted,3);
        assert(WXGHomeOffsetAtDepth(0,108,108,top,34,1600,panel)==-nav);
        assert(fabs(WXGHomeOffsetAtDepth(300,108,105,top,34,1600,panel)-(297-nav))<1e-7);
        assert(fabs(WXGHomePullTranslation(-nav-18,top,3)-18)<1e-7);
    }
    // Capture 13: the native open changed the inset before moving the list.
    // All three failed animations stopped here with every gesture flag clear.
    const double stops[]={-304.-2./3.,-206.-1./3.,-259.-1./3.};
    for(unsigned i=0;i<sizeof(stops)/sizeof(stops[0]);i++) {
        assert(WXGHomeNativePull(nav,0,nav,stops[i],panel,3));          // drag or closing
        assert(WXGHomeNativePull(nav,panelRaw,panel,stops[i],panel,3)); // native open
        assert(WXGHomePullTranslation(stops[i],nav,3)>100);
    }
    assert(WXGHomeNativePull(nav,panelRaw,panel,-nav,panel,3));
    assert(WXGHomeNativePull(nav,panelRaw,panel,-panel,panel,3));
    assert(WXGHomeNativePull(0,panel,panel,-panel,panel,3));
    assert(!WXGHomeNativePull(nav,0,nav,-nav,panel,3));
    assert(!WXGHomeNativePull(nav,0,nav,-nav-.1,panel,3));
    assert(!WXGHomeNativePull(nav,nav,2*nav,-nav,panel,3));
    assert(!WXGHomeNativePull(nav,0,nav,400,panel,3));
    // Title, search and groups follow the same pull across the change of
    // range. At full height the Home controls have moved below the screen.
    assert(fabs(WXGHomePullTranslation(-panel,nav,3)-(panel-nav))<1e-7);
    assert(3.+WXGHomePinnedContentShift(-panel,nav)+panel==panel+3);
    // The storage shim only removes a navigation inset duplicated on a
    // zero request. Preserve real native opens, refresh and app-owned insets.
    assert(WXGHomeDuplicatesZeroRequest(0,nav,nav,nav,3));
    assert(!WXGHomeDuplicatesZeroRequest(panelRaw,panelRaw,nav,nav,3));
    assert(!WXGHomeDuplicatesZeroRequest(nav,nav,nav,nav,3));
    assert(!WXGHomeDuplicatesZeroRequest(24,nav,nav,nav,3));
    assert(!WXGHomeDuplicatesZeroRequest(0,0,nav,nav,3));
    assert(!WXGHomeDuplicatesZeroRequest(0,nav,0,nav,3));
    assert(!WXGHomeDuplicatesZeroRequest(0,nav,nav,0,3));
    assert(WXGHomeAtDuplicatedRest(nav,nav,2*nav,-2*nav,3));
    assert(!WXGHomeAtDuplicatedRest(nav,nav,2*nav,-2*nav-1,3));
    assert(!WXGHomeAtDuplicatedRest(nav,panelRaw,panel,-panel,3));
    assert(WXGHomeInitialConversationTop(nav,nav,panel,3)==nav);
    assert(WXGHomeInitialConversationTop(nav,2*nav,panel,3)==nav);
    assert(fabs(WXGHomeInitialConversationTop(panelRaw,panel,panel,3)-nav)<1e-7);
    assert(WXGHomeInitialConversationTop(24,nav+24,panel,3)==nav+24);
    assert(!WXGHomeNativePull(nav+24,24,nav+24,-nav-24,panel,3));
    assert(WXGHomeInitialConversationTop(0,0,panel,3)==0);
    // Diagnostics 16/17: the taskbar briefly supplies all 956 pt as raw inset;
    // closing it at -100 1/3 must keep the search at its original header row.
    assert(WXGHomeRememberedConversationTop(nav,panel,panel,panel,3)==nav);
    assert(WXGHomeRememberedConversationTop(0.,panel,panel,panel,3)==0.);
    assert(fabs(WXGHomeRememberedConversationTop(NAN,panel-nav,panel,panel,3)-nav)<1.e-8);
    assert(WXGHomeRememberedConversationTop(nav,0.,nav+10,panel,3)==nav+10);
    assert(WXGHomePinnedContentShift(-panel,nav)==0.);
    assert(WXGHomePinnedContentShift(-nav-.2,nav)==0.);
    assert(WXGHomePinnedContentShift(-nav,nav)==0.);
    assert(WXGHomePinnedContentShift(40.,nav)==nav+40.);

    assert(WXGHomeNativePull(0,0,0,-12,panel,3));
    assert(!WXGHomeNativePull(0,0,0,0,panel,3));
    puts("HomeSearchLayoutTests: native row handoff, field readiness and header reservation passed.");
    return 0;
}
