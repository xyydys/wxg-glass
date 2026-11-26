#ifndef WXG_BUBBLE_QUOTE_RULES_H
#define WXG_BUBBLE_QUOTE_RULES_H
#include "WXGBubbleRules.h"

// MixBubble 2.9.4.6 uses the nearest nonoverlapping section with 4pt of clearance.
static inline double WXGBubbleQuoteDividerY(WXGBubbleSpan main, WXGBubbleSpan visual, WXGBubbleSpan root) {
    if (!isfinite(main.min) || !isfinite(main.max) || main.max - main.min <= 1. ||
        !isfinite(visual.min) || !isfinite(visual.max) || visual.max <= visual.min) return NAN;
    WXGBubbleSpan candidates[] = {visual, root};
    double best = INFINITY, y = NAN;
    for (unsigned i = 0; i < 2; i++) {
        WXGBubbleSpan quote = candidates[i];
        if (!isfinite(quote.min) || !isfinite(quote.max) || quote.max <= quote.min) continue;
        double top = fmin(main.max, quote.max);
        double bottom = fmax(main.min, quote.min);
        double gap = bottom - top;
        if (gap >= 4. && gap < best) {
            best = gap;
            y = (top + bottom) * .5;
        }
    }
    return y;
}

static inline int WXGBubbleQuoteDividerDistinct(double last, double y) {
    return isfinite(y) && (!isfinite(last) || fabs(y-last) >= 3.);
}

static inline WXGBubbleBox WXGBubbleQuoteDividerFrame(double width, double height, double y, double scale) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(y) || width - 24. < 20. ||
        y <= 8. || y >= height - 8.) return (WXGBubbleBox){0};
    scale = fmax(1., scale);
    double pixel = 1. / scale;
    return (WXGBubbleBox){12., round(y * scale) / scale - pixel * .5, width - 24., pixel};
}

#endif
