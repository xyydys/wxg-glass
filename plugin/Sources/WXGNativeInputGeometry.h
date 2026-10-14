#ifndef WXG_NATIVE_INPUT_GEOMETRY_H
#define WXG_NATIVE_INPUT_GEOMETRY_H
#include "WXGGeometry.h"
typedef struct {WXGRect left,center,right;} WXGNativeInputGeometry;
static inline int WXGInputRectValid(WXGRect r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.w) && isfinite(r.h) && r.w>1 && r.h>1;
}
/* Glass-only geometry. Native text and touch rectangles are immutable inputs.
   Blank/single-line rows share one height. Multiline sides stay on the bottom
   native row while the center grows, instead of stretching action glyphs. */
static inline WXGNativeInputGeometry WXGNativeInputLayout(WXGRect center,WXGRect left,WXGRect right,double base) {
    WXGNativeInputGeometry out={0};out.center=center;
    if(!WXGInputRectValid(center) || !isfinite(base) || base<=0)return (WXGNativeInputGeometry){0};
    double h=fmax(base,center.h),mid=center.y+center.h*.5;
    out.center.y=mid-h*.5;out.center.h=h;
    double sideY=out.center.y+out.center.h-base;
    if(WXGInputRectValid(left)){out.left=left;out.left.y=sideY;out.left.h=base;}
    if(WXGInputRectValid(right)){out.right=right;out.right.y=sideY;out.right.h=base;}
    return out;
}
#endif
