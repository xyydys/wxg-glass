#include <assert.h>
#include <stdio.h>
#include "../Sources/WXGHomePagingMath.h"

int main(void) {
    // All and unread are independent title modes. Neither occupies a category tab.
    assert(WXGHomeNeighbor(-1,5,1)==0 && WXGHomeNeighbor(-2,5,-1)==4);
    assert(WXGHomeNeighbor(4,5,1)==0 && WXGHomeNeighbor(0,5,-1)==4);
    assert(WXGHomeNeighbor(2,5,-1)==1 && WXGHomeNeighbor(2,5,1)==3);
    // A device action replaces enterprise and does not participate in paging.
    assert(WXGHomeNeighbor(3,4,1)==0 && WXGHomeNeighbor(0,4,-1)==3);
    assert(WXGHomeNeighbor(0,0,1)==-1);
    assert(!WXGHomePageHorizontal(0,-190) && !WXGHomePageHorizontal(95,100));
    assert(WXGHomePageHorizontal(-180,30));
    assert(!WXGHomePageCommits(48,0,440,true));
    assert(WXGHomePageCommits(155,0,440,true));
    assert(WXGHomePageCommits(-20,-161,440,true));
    assert(!WXGHomePageCommits(-240,180,440,true)); // threw back toward the starting page
    assert(!WXGHomePageCommits(47,12,440,false) && WXGHomePageCommits(48,12,440,false));
    assert(WXGHomePageCommits(30,-165,440,false) && !WXGHomePageCommits(240,0,0,true));
    assert(WXGHomePageSettle(0)==.20 && fabs(WXGHomePageSettle(1)-.34)<1e-9);
    puts("HomeGroupPagingTests: category order, gesture arbitration and settling passed.");
    return 0;
}
