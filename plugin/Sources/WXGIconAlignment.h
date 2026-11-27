#ifndef WXG_ICON_ALIGNMENT_H
#define WXG_ICON_ALIGNMENT_H
#include "WXGGeometry.h"
#include <stdint.h>
#include <stddef.h>
// The caller selects the byte that carries alpha in the 32-bit raster.
static inline WXGRect WXGIconInkBounds(const uint8_t *alpha,size_t width,size_t height,size_t stride,uint8_t threshold) {
    size_t left=width,top=height,right=0,bottom=0;
    for(size_t y=0;y<height;y++)for(size_t x=0;x<width;x++) {
        if(alpha[y*stride+4*x]<threshold)continue;
        if(x<left)left=x;
        if(y<top)top=y;
        if(x>right)right=x;
        bottom=y;
    }
    if(left==width)return (WXGRect){0,0,0,0};
    return (WXGRect){left,top,right-left+1,bottom-top+1};
}
// Image alpha bounds are normalized in the original UIImageView, including
// transparent padding. Leave the native gesture host and its hit box in place.
static inline WXGRect WXGAlignedImageFrame(WXGRect original,WXGRect ink,double cx,double cy,double maximum) {
    double w=original.w*ink.w,h=original.h*ink.h;
    if(w<=0 || h<=0 || maximum<=0)return original;
    double scale=fmin(maximum/w,maximum/h);
    double width=original.w*scale,height=original.h*scale;
    return (WXGRect){cx-(ink.x+ink.w*.5)*width,cy-(ink.y+ink.h*.5)*height,width,height};
}
// Preserve the ink's size/center while allowing bilinear filtering to sample
// transparent pixels beyond the artwork instead of clamping to its last texel.
static inline WXGRect WXGIconTextureFrame(WXGRect inkFrame,double sourceInkWidth,double gutter) {
    double pad=sourceInkWidth>0 ? inkFrame.w*gutter/sourceInkWidth : 0;
    return (WXGRect){inkFrame.x-pad,inkFrame.y-pad,inkFrame.w+2*pad,inkFrame.h+2*pad};
}
#endif
