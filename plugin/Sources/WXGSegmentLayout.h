#ifndef WXG_SEGMENT_LAYOUT_H
#define WXG_SEGMENT_LAYOUT_H

#include "WXGOptics.h"

#define WXG_SEGMENTS_MAX 6

typedef struct {
    int count;
    float edges[WXG_SEGMENTS_MAX+1];
    float fontScale;
} WXGSegmentSlots;

static inline float WXGTitlePreferredWidth(float height,float gap,const float advances[2]) {
    float padding=fmaxf(10.f,height*.35f);
    return 2.f*gap+advances[0]+advances[1]+4.f*padding;
}

// Only the two-item navigation title measures its labels. The list's
// user-defined segment bar continues to divide its available width equally.
static inline WXGSegmentSlots WXGMakeSegmentSlots(float width,float gap,int count,const float *advances) {
    WXGSegmentSlots slots={0};
    slots.count=count<1?1:(count>WXG_SEGMENTS_MAX?WXG_SEGMENTS_MAX:count);
    slots.fontScale=1.f;
    float inner=fmaxf(0.f,width-2.f*gap);
    for(int i=0;i<=slots.count;i++) slots.edges[i]=gap+inner*i/slots.count;
    if(slots.count==2 && advances) {
        float text=advances[0]+advances[1];
        // In a narrow navigation row, give up excess padding first. Below
        // 4 pt per side, fit both labels at the same scale within the budget.
        float minimumPadding=fminf(4.f,inner*.125f);
        if(text>0.f) slots.fontScale=fminf(1.f,(inner-4.f*minimumPadding)/text);
        float extraPerSlot=(inner-text*slots.fontScale)*.5f;
        slots.edges[1]=gap+extraPerSlot+advances[0]*slots.fontScale;
    }
    return slots;
}
static inline float WXGSegmentCenter(WXGSegmentSlots slots,int i) {
    if(!slots.count)return 0.f;
    i=i<0?0:(i>=slots.count?slots.count-1:i);
    return (slots.edges[i]+slots.edges[i+1])*.5f;
}
static inline int WXGSegmentAtX(WXGSegmentSlots slots,float x) {
    for(int i=1;i<slots.count;i++)if(x<slots.edges[i])return i-1;
    return slots.count>0?slots.count-1:0;
}
static inline float WXGSegmentStep(WXGSegmentSlots slots) {
    return slots.count?fmaxf(1.f,(slots.edges[slots.count]-slots.edges[0])/slots.count):1.f;
}
static inline float WXGSegmentProgress(WXGSegmentSlots slots,float x) {
    float first=WXGSegmentCenter(slots,0),last=WXGSegmentCenter(slots,slots.count-1);
    return last>first?WXGOClamp((x-first)/(last-first),0.f,1.f):0.f;
}
static inline WXGDockGeometry WXGSegmentGeometry(float width,float height,float gap,float anchor,float press,
                                                   float growth,float barGrowth,float wrap,WXGSegmentSlots slots) {
    WXGDockGeometry g={0};
    if(!slots.count)return g;
    press=WXGOClamp(press,0.f,1.f);
    g.scale=1.f+(barGrowth-1.f)*press;
    g.barWidth=width*g.scale;g.barHeight=height*g.scale;
    g.barX=(width-g.barWidth)*.5f;g.barY=(height-g.barHeight)*.5f;
    int last=slots.count-1;
    float t=WXGSegmentProgress(slots,anchor);
    g.anchorX=WXGSegmentCenter(slots,0)+t*(WXGSegmentCenter(slots,last)-WXGSegmentCenter(slots,0));
    float firstW=WXGLensWidth(slots.edges[1]-slots.edges[0],height,press,growth,0)*g.scale;
    float lastW=WXGLensWidth(slots.edges[last+1]-slots.edges[last],height,press,growth,0)*g.scale;
    g.lensWidth=firstW+t*(lastW-firstW);
    g.lensHeight=WXGLensHeight(height,gap,press,growth,0)*g.scale;
    float outside=gap*g.scale*(1.f-press)-wrap*press;
    // Interpolate both edges between their resting/pressed endpoints. A
    // variable-width pill then stays centered on its traveling text anchor.
    g.lensX=g.barX+outside+t*(g.barWidth-2.f*outside-lastW);
    g.lensY=(height-g.lensHeight)*.5f;
    return g;
}
#endif
