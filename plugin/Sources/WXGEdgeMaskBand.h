#ifndef WXG_EDGE_MASK_BAND_H
#define WXG_EDGE_MASK_BAND_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "WXGMeshRefraction.h"
/* FIX58: the clear-ring mask of a glass (WXGGlassView updateEdgeMask) holds
   WXGSharpRingAlpha for every pixel, but only a band along the outline can be
   non-zero. With dx / dy the distances to the nearest vertical / horizontal
   side and r the field's corner radius, the rounded field (and the capsule's,
   r = half the short side) is -min(dx,dy) where dx >= r and dy >= r, -dx where
   only dy >= r, -dy where only dx >= r; only the four r x r corner squares
   are curved. So a pixel outside the corner squares and at least the edge
   width from both sides lies at least the edge width deep, where the sharp
   weight is exactly 0. Such pixels (with a 1 pt margin) are written as 0
   without evaluating the field, every other pixel exactly as before: the bytes
   are identical (Tests/EdgeMaskBandTests.c), and large glass (the settings
   cards) builds its mask several times faster. */
static inline float WXGRingFieldRadius(float width,float height,float radius) {
    float half=WXG_MIN(width,height)*.5f;
    /* The radius WXGSharpRingAlpha's field uses (rounded / capsule). */
    return radius>0.f?WXGOClamp(radius,.5f,half):WXG_MAX(.5f,half);
}
static inline int WXGRingMaskSkips(float x,float y,float width,float height,float corner,float clear) {
    float dx=WXG_MIN(x,width-x),dy=WXG_MIN(y,height-y);
    return (dx>=corner || dy>=corner) && dx>=clear && dy>=clear;
}
/* key: width, height, corner radius (0 = capsule), edge width, coverage 0..1,
   all in points; `scale` pixels per point. Same bytes as evaluating
   WXGSharpRingAlpha at every pixel centre. */
static inline uint8_t WXGRingMaskByte(float x,float y,const float key[5]) {
    return (uint8_t)lroundf(255.f*WXGSharpRingAlpha(x,y,key[0],key[1],key[2],key[3],key[4]));
}
static inline void WXGFillRingMask(uint8_t *bytes,size_t w,size_t h,size_t stride,float scale,const float key[5]) {
    float corner=WXGRingFieldRadius(key[0],key[1],key[2])+1.f,clear=key[3]+1.f;
    for(size_t j=0;j<h;j++) {
        float y=((float)j+.5f)/scale;
        uint8_t *row=bytes+j*stride;
        /* Along a row the skipped pixels are one run (min(x, width - x) rises,
           then falls): evaluate inwards from both ends up to it, zero the run. */
        size_t i=0,k=w;
        for(;i<w;i++) {
            float x=((float)i+.5f)/scale;
            if(WXGRingMaskSkips(x,y,key[0],key[1],corner,clear))break;
            row[i]=WXGRingMaskByte(x,y,key);
        }
        for(;k>i;k--) {
            float x=((float)(k-1)+.5f)/scale;
            if(WXGRingMaskSkips(x,y,key[0],key[1],corner,clear))break;
            row[k-1]=WXGRingMaskByte(x,y,key);
        }
        if(k>i)memset(row+i,0,k-i);
    }
}
#endif
