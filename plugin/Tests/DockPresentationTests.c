#include "../Sources/WXGDockPresentation.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(WXGDockPresentationForState(1,1,0,0)==WXGDockSettled);
    assert(WXGDockPresentationForState(1,0,0,0)==WXGDockHidden);
    /* Chat and Finder return: show immediately, but no tap dispatch until done. */
    for(int finder=0;finder<2;finder++) {
        (void)finder;
        assert(WXGDockPresentationForState(1,0,1,1)==WXGDockReturning);
        assert(WXGDockPresentationAfterTransition(1,0,1,0)==WXGDockSettled);
        assert(WXGDockPresentationAfterTransition(1,0,1,1)==WXGDockHidden);
    }
    /* A cancelled root push restores the same dock. A completed push hides it. */
    assert(WXGDockPresentationForState(1,1,1,0)==WXGDockHidden);
    assert(WXGDockPresentationAfterTransition(1,1,0,1)==WXGDockSettled);
    assert(WXGDockPresentationAfterTransition(1,1,0,0)==WXGDockHidden);
    /* Chat/settings is never a tab root. */
    for(int cancel=0;cancel<2;cancel++)assert(WXGDockPresentationAfterTransition(1,0,0,cancel)==WXGDockHidden);
    for(int root=0;root<2;root++)for(int transition=0;transition<2;transition++)for(int to=0;to<2;to++)
        assert(WXGDockPresentationForState(0,root,transition,to)==WXGDockHidden);
    puts("PASS: front dock return/commit/cancel, root push, non-root navigation and disabled/covered states.");
}
