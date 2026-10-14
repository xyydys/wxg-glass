#ifndef WXG_INPUT_SETTLED_GEOMETRY_H
#define WXG_INPUT_SETTLED_GEOMETRY_H
#include "WXGGeometry.h"
/* Preserve the TEST9 center capsule. Side actions stay on the last native row,
   so growing the text upwards never raises the attachment/emoji/mic column. */
static inline WXGInputGeometry WXGInputBottomAnchoredLayout(double width,double safeLeft,double safeRight,
    WXGRect native,double baseHeight,double nativeTextHeight,double multiplier) {
    WXGInputGeometry out=WXGInputLayout(width,safeLeft,safeRight,native.y+native.h*.5,
        fmax(40,native.h),nativeTextHeight,multiplier);
    double sideMid=native.y+native.h-fmin(native.h,fmax(24,baseHeight))*.5;
    out.plus.y=sideMid-out.plus.h*.5;out.mic.y=sideMid-out.mic.h*.5;
    return out;
}
#endif
