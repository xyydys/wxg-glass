#ifndef WXG_NATIVE_ICON_ANCHORS_H
#define WXG_NATIVE_ICON_ANCHORS_H
#include <math.h>
#include <stddef.h>

// Physical left-to-right order for four WeChat item containers. Centers
// use the tab bar's coordinate space; callers map physical order to RTL.
static inline int WXGOrderIconAnchors(const double *centers, size_t count, double width, unsigned order[4]) {
    if (count != 4 || !isfinite(width) || width <= 0) return 0;
    for (unsigned i = 0; i < 4; ++i) {
        if (!isfinite(centers[i]) || centers[i] < 0 || centers[i] >= width) return 0;
        unsigned position = i;
        while (position && centers[order[position - 1]] > centers[i]) {
            order[position] = order[position - 1];
            --position;
        }
        order[position] = i;
    }
    for (unsigned i = 1; i < 4; ++i)
        if (centers[order[i]] - centers[order[i - 1]] < width / 8.) return 0;
    return 1;
}
#endif
