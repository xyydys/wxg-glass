#include "../Sources/WXGOptics.h"
#include <assert.h>
#include <stdio.h>

static void near(float a,float b) { assert(fabsf(a-b)<.0002f); }
int main(void) {
    unsigned cases=0;
    const float heights[]={54,68,90},screens[]={320,375,390,430,768};
    const float gaps[]={2,6,14},barScales[]={1,1.025f,1.08f},wraps[]={2,4,10};
    for(unsigned sh=0;sh<5;sh++) for(unsigned hi=0;hi<3;hi++)
    for(unsigned gi=0;gi<3;gi++) for(unsigned bi=0;bi<3;bi++) for(unsigned wi=0;wi<3;wi++)
    for(int grow=108;grow<=150;grow+=7) {
        float screen=screens[sh],h=heights[hi],b=barScales[bi],wrap=wraps[wi];
        float w=WXGFitMaterialWidth(screen,.98f,b,wrap),gap=WXGSelectionGap(gaps[gi],h);
        for(int endpoint=0;endpoint<2;endpoint++) {
            float anchor=WXGSelectionCenter(w,gap,endpoint?3:0);
            WXGDockGeometry g=WXGDockLayout(w,h,gap,anchor,1,grow/100.f,.10f,b,wrap);
            near(g.lensY+g.lensHeight*.5f,h*.5f);
            near(g.barY+g.barHeight*.5f,h*.5f);
            assert(g.lensHeight>g.barHeight);
            if(endpoint) near(g.lensX+g.lensWidth-g.barX-g.barWidth,wrap);
            else near(g.barX-g.lensX,wrap);
            // Validate the whole original end cap, not only its cardinal endpoint.
            // A compressed cap lies still further inside; no icon zoom participates.
            float r=g.barHeight*.5f,cx=g.barX+(endpoint?g.barWidth-r:r);
            for(int i=0;i<=180;i++) {
                float angle=(90+i)*3.14159265359f/180.f;
                float dx=r*cosf(angle)*(endpoint?-1.f:1.f),dy=r*sinf(angle);
                float x=cx+dx-(g.lensX+g.lensWidth*.5f),y=dy;
                assert(WXGCapsuleOpticalField(x,y,g.lensWidth,g.lensHeight).distance<-.1f);
            }
            // Padding/canvas remain fixed throughout press and dragging.
            assert(g.lensX>-WXGCanvasPaddingX && g.lensX+g.lensWidth<w+WXGCanvasPaddingX);
            assert(g.lensY>-WXGCanvasPaddingY && g.lensY+g.lensHeight<h+WXGCanvasPaddingY);
            float globalX=(screen-w)*.5f+g.lensX;
            assert(globalX>=3.999f && globalX+g.lensWidth<=screen-3.999f);
            ++cases;
        }
        float previousH=0,previousScale=0;
        for(int pi=0;pi<=100;pi++) {
            float press=pi/100.f;
            for(int ai=0;ai<=4;ai++) {
                float anchor=-20+(w+40)*ai/4.f;
                WXGDockGeometry a=WXGDockLayout(w,h,gap,anchor,press,grow/100.f,0,b,wrap);
                WXGDockGeometry stretched=WXGDockLayout(w,h,gap,anchor,press,grow/100.f,.1f*press,b,wrap);
                near(a.lensY+a.lensHeight*.5f,h*.5f);
                near(a.lensHeight,stretched.lensHeight); near(a.lensY,stretched.lensY);
                if(ai==0) { assert(a.lensHeight>=previousH && a.scale>=previousScale); previousH=a.lensHeight; previousScale=a.scale; }
            }
        }
    }
    // Default ratios: whole bar < icons; outer lens > bar > inner compressed body.
    WXGDockGeometry g=WXGDockLayout(360,68,6,310,1,1.28f,0,1.025f,4);
    near(g.barHeight,69.7f); near(g.lensHeight,89.216f);
    assert(g.scale<g.scale*1.20f);
    assert(g.lensHeight>g.barHeight && g.barHeight>g.barHeight-2*WXGInnerInset(g.barHeight,1,.18f,-10));
    printf("PASS: %u pressed endpoint cases; complete cap containment; constant y; growth order; no vertical velocity squash; screen/canvas margins.\n",cases);
    return 0;
}
