#include "../Sources/WXGNativeIconAnchors.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // 440 pt bar: WeChat item frames measured on iOS 26.6, presented in
    // arbitrary hierarchy order. Both UIKit button copies are outside these roots.
    const double centers[] = {267.33, 78.33, 361.67, 172.67};
    const unsigned logical[] = {2, 0, 3, 1};
    unsigned order[4] = {0};
    assert(WXGOrderIconAnchors(centers, 4, 440, order));
    for (unsigned i=0; i<4; ++i) {
        assert(logical[order[i]] == i);
        assert(logical[order[3-i]] == 3-i);
    }
    assert(!WXGOrderIconAnchors(centers, 3, 440, order));
    assert(!WXGOrderIconAnchors(centers, 8, 440, order));
    assert(!WXGOrderIconAnchors((double[]){0, 0, 0, 0}, 4, 440, order));
    assert(!WXGOrderIconAnchors((double[]){78, 79, 267, 362}, 4, 440, order));
    assert(!WXGOrderIconAnchors((double[]){78, 172, 267, 440}, 4, 440, order));
    assert(!WXGOrderIconAnchors((double[]){78, 172, NAN, 362}, 4, 440, order));
    assert(!WXGOrderIconAnchors(centers, 4, 0, order));
    puts("PASS: WeChat icon ownership order and unmeasured / ambiguous anchors");
}
