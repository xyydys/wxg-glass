#ifndef WXG_ICON_ALIGNMENT_H
#define WXG_ICON_ALIGNMENT_H
#include "WXGGeometry.h"
// Image alpha bounds are normalized in the original UIImageView, including
// transparent padding. Leave the native gesture host and its hit box in place.
static inline WXGRect WXGAlignedImageFrame(WXGRect original,WXGRect ink,double cx,double cy,double maximum) {
    double w=original.w*ink.w,h=original.h*ink.h;
    if(w<=0 || h<=0 || maximum<=0)return original;
    double scale=fmin(maximum/w,maximum/h);
    double width=original.w*scale,height=original.h*scale;
    return (WXGRect){cx-(ink.x+ink.w*.5)*width,cy-(ink.y+ink.h*.5)*height,width,height};
}
#endif
