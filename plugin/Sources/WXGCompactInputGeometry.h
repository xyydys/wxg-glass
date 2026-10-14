#ifndef WXG_COMPACT_INPUT_GEOMETRY_H
#define WXG_COMPACT_INPUT_GEOMETRY_H
#include "WXGGeometry.h"
typedef struct { WXGRect left,center,right; double leftInkX,rightInkX[2],sideMidY,gap; } WXGCompactInput;
/* Input is the native content row and measured visible glyph sizes. Controls
   retain their bounds/actions; only their origins and the grow host width move. */
static inline WXGCompactInput WXGCompactInputLayout(double width,double safeLeft,double safeRight,
    WXGRect native,double diameter,double firstInk,double secondInk,int count) {
    WXGCompactInput o={0};double d=WXGBound(diameter,36,54),edge=8,gap=8;
    double rightWidth=count>1?firstInk+secondInk+3*gap:count==1?fmax(d,firstInk+2*gap):0;
    double rightX=width-safeRight-edge-rightWidth;
    double centerX=safeLeft+edge+d+gap;
    double end=count?rightX-gap:width-safeRight-edge;
    double extra=fmax(0,native.h-40),height=d+extra,mid=native.y+native.h*.5;
    o.center=(WXGRect){centerX,mid-height*.5,fmax(40,end-centerX),height};
    double y=o.center.y+height-d;
    o.left=(WXGRect){safeLeft+edge,y,d,d};o.leftInkX=o.left.x+d*.5;
    if(count)o.right=(WXGRect){rightX,y,rightWidth,d};
    o.rightInkX[0]=rightX+(count>1?gap+firstInk*.5:rightWidth*.5);
    o.rightInkX[1]=rightX+2*gap+firstInk+secondInk*.5;
    o.sideMidY=y+d*.5;o.gap=gap;return o;
}
#endif
