#ifndef WXG_INPUT_SETTLED_GEOMETRY_H
#define WXG_INPUT_SETTLED_GEOMETRY_H
#include "WXGGeometry.h"
/* Preserve the TEST9 center capsule. Side actions stay on the last native row,
   so growing the text upwards never raises the attachment/emoji/mic column. */
static inline WXGInputGeometry WXGInputBottomAnchoredLayoutSized(double width,double safeLeft,double safeRight,
    WXGRect native,double baseHeight,double nativeTextHeight,double multiplier,WXGInputSize size) {
    WXGInputGeometry out=WXGInputLayoutSized(width,safeLeft,safeRight,native.y+native.h*.5,
        fmax(40,native.h),nativeTextHeight,multiplier,size);
    double sideMid=native.y+native.h-fmin(native.h,fmax(24,baseHeight))*.5;
    out.plus.y=sideMid-out.plus.h*.5;out.mic.y=sideMid-out.mic.h*.5;
    // FIX115 J (review): a set height never makes the capsule lower than
    // WeChat's own text box (a low setting, a narrow screen, more lines): the
    // caret and the first / last lines stay inside it. (TEST9's as it was.)
    if(size.height>0 && out.pill.h<native.h){out.pill.h=native.h;out.pill.y=native.y;}
    return out;
}
static inline WXGInputGeometry WXGInputBottomAnchoredLayout(double width,double safeLeft,double safeRight,
    WXGRect native,double baseHeight,double nativeTextHeight,double multiplier) {
    return WXGInputBottomAnchoredLayoutSized(width,safeLeft,safeRight,native,baseHeight,nativeTextHeight,multiplier,WXGInputSizeTEST9());
}
#endif
