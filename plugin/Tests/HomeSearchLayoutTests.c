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
    puts("HomeSearchLayoutTests: native field readiness and vertical header reservation passed.");
    return 0;
}
