#include "../Sources/WXGOptics.h"
#include <assert.h>
#include <stdio.h>

static void near(float a,float b) { assert(fabsf(a-b)<.0001f); }

int main(void) {
    const float widths[]={208,280,360,420}, heights[]={54,68,90}, insets[]={2,6,14};
    unsigned cases=0;
    for(unsigned wi=0;wi<4;wi++) for(unsigned hi=0;hi<3;hi++) for(unsigned gi=0;gi<3;gi++) {
        float w=widths[wi],h=heights[hi],gap=WXGSelectionGap(insets[gi],h);
        float slot=WXGSelectionWidth(w,gap);
        float restH=WXGLensHeight(h,gap,0,1.28f,0);
        float restW=WXGLensWidth(slot,h,0,1.28f,0);
        float top=(h-restH)*.5f,bottom=h-(top+restH);
        float left=WXGSelectionCenter(w,gap,0)-restW*.5f;
        float right=w-(WXGSelectionCenter(w,gap,3)+restW*.5f);
        near(left,top); near(right,top); near(bottom,top); near(top,gap);
        for(int index=0;index<4;index++) {
            float center=WXGSelectionCenter(w,gap,index);
            assert(center-restW*.5f>=gap-.0001f);
            assert(center+restW*.5f<=w-gap+.0001f);
            if(index) near(center-WXGSelectionCenter(w,gap,index-1),restW);
            // The native radius must fit both axes, including tall/narrow settings.
            float radius=WXG_MIN(restW,restH)*.5f;
            assert(radius>0 && radius*2<=restH && radius*2<=restW);
            ++cases;
        }
        near(WXGSelectionCenter(w,gap,-1),WXGSelectionCenter(w,gap,0));
        near(WXGSelectionCenter(w,gap,4),WXGSelectionCenter(w,gap,3));
        for(int grow=108;grow<=150;grow++) {
            float pressedH=WXGLensHeight(h,gap,1,grow/100.f,.10f);
            float pressedW=WXGLensWidth(slot,h,1,grow/100.f,.10f);
            assert(pressedH>h && pressedW>restW);
            assert((pressedH-h)*.5f+6+3.1f<32);
        }
    }
    near(WXGSelectionGap(-100,68),2); near(WXGSelectionGap(100,68),14);
    near(WXGPressedBorderAlpha(-1),0); near(WXGPressedBorderAlpha(0),0);
    near(WXGPressedBorderAlpha(.004f),0); near(WXGPressedBorderAlpha(.5f),.5f);
    near(WXGPressedBorderAlpha(1),1); near(WXGPressedBorderAlpha(2),1);
    printf("PASS: %u resting layouts with equal cardinal gaps; radius bounds; pressed growth, margins and border visibility.\n",cases);
    return 0;
}
