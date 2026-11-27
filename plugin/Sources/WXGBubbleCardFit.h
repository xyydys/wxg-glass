#ifndef WXG_BUBBLE_CARD_FIT_H
#define WXG_BUBBLE_CARD_FIT_H

typedef struct {
    double widthCoverage, heightCoverage, area, score;
    int overhang, stretchable;
} WXGCardImageFit;

// Rank only background-shaped images. A map, icon or preview can be the
// largest image in the cell; it must not disappear when the glass is enabled.
static inline WXGCardImageFit WXGBubbleCardImageFit(double widthCoverage, double heightCoverage,
                                                    double area, int overhang, int stretchable) {
    WXGCardImageFit fit = {widthCoverage, heightCoverage, area, 0, overhang, stretchable};
    int full = widthCoverage >= .82 && heightCoverage >= .82;
    if (area > 0 && widthCoverage > 0 && heightCoverage > 0 && (full || stretchable))
        fit.score = area + (full ? 10000000 : 0) + (stretchable ? 6000000 : 0) + (overhang ? 1500000 : 0);
    return fit;
}
static inline int WXGBubbleCardAcceptFit(WXGCardImageFit fit, int insetCard) {
    return fit.score > 0 && (!insetCard || fit.stretchable ||
        (fit.widthCoverage >= .90 && fit.heightCoverage >= .90) ||
        (fit.widthCoverage >= .82 && fit.heightCoverage >= .82 && fit.overhang));
}
static inline int WXGBubbleCardStandbyFit(WXGCardImageFit fit, int insetCard, double primaryArea) {
    return WXGBubbleCardAcceptFit(fit, insetCard) && fit.area >= .88*primaryArea &&
        fit.widthCoverage >= .82 && fit.heightCoverage >= .82;
}

// A voice row can grow vertically and horizontally before its compact audio
// skin is replaced. Only admit a compact upper-edge skin in that interim.
static inline int WXGBubbleCompactVoiceSkin(WXGCardImageFit fit, double top, double height) {
    return fit.area > 0 && fit.widthCoverage > 0 && fit.heightCoverage > 0 &&
        top >= -8 && top <= 8 && height >= 20 && height <= 64;
}

// A compact standby may be offset during the transition. Compare its upper
// strip and occupied area against the actual primary rather than exact frames.
static inline int WXGBubbleAlternateVoiceSkin(WXGCardImageFit fit,double primaryArea,double top,double height) {
    return primaryArea>0 && fit.area>=.88*primaryArea && WXGBubbleCompactVoiceSkin(fit,top,height);
}

static inline int WXGBubbleVoicePlate(double top, double width, double height,
                                      double textWidth, double textHeight, int directLoadingPlate) {
    if (top < 22) return 0;
    int containsText = textWidth >= 16 && textHeight >= 12 &&
        width >= textWidth * .60 && height >= textHeight * .60;
    int loading = directLoadingPlate && width >= 32 && width <= 96 && height >= 28 && height <= 56;
    return containsText || loading;
}
#endif
