#include "../Sources/WXGOptics.h"
#include <assert.h>
#include <stdio.h>

// Frozen TEST6 ordinary offset, with its optional mirror completely absent.
static float test6Offset(float d,float w,float strength) {
    float t=fminf(1,fmaxf(0,-d/fmaxf(w,1)));
    float edge=1-t*t*(3-2*t);
    return w*fminf(.32f*strength,.40f)*edge*edge;
}
static void near(float a,float b) { assert(fabsf(a-b)<.00005f); }
int main(void) {
    unsigned oldCases=0;
    for(int w=3;w<=14;w++) for(int di=0;di<=100;di++) for(int si=0;si<=200;si++) {
        float d=-w*di/100.f,s=si/100.f;
        near(WXGOpticalOffset(d,w,s),test6Offset(d,w,s)); ++oldCases;
    }
    near(WXGOpticalOffset(0,10,1.15f),3.68f);
    near(WXGOpticalOffset(-5,10,1.15f),.92f);
    near(WXGOpticalOffset(0,10,2),4);
    near(WXGOpticalOffset(0,10,4),10.4f);
    near(WXGOpticalOffset(0,10,8),23.2f);
    for(int w=3;w<=14;w++) for(int di=0;di<100;di++) {
        float last=WXGOpticalOffset(-w*di/100.f,w,2);
        for(int si=201;si<=800;si++) {
            float value=WXGOpticalOffset(-w*di/100.f,w,si/100.f);
            assert(isfinite(value) && value>=last); last=value;
        }
    }
    for(int a=0;a<=95;a++) for(int c=0;c<=1;c++) for(int e=0;e<=100;e++) {
        float alpha=a/100.f,edge=e/100.f;
        float center=fminf(1,alpha*(c?1:1.22f));
        near(WXGMaterialOpacity(alpha,c,edge,0),center);
        near(WXGMaterialOpacity(alpha,c,edge,1),center*(1-.82f*edge*edge));
    }
    // A fixed inward distance yields flat top/bottom and matching regular caps.
    const float w=300,h=68,press=1,reduction=.18f;
    // FIX47: the inset ramps over its own depth (~45 degrees); use the full one.
    float inset=WXGInnerInset(h,press,reduction,-200),radius=h*.5f-inset;
    for(int x=-100;x<=100;x++) {
        near(WXGCapsuleOpticalField(x,radius,w,h).distance+inset,0);
        near(WXGCapsuleOpticalField(x,-radius,w,h).distance+inset,0);
    }
    // FIX96: around the ends the capsule's distance is the circle's less the
    // continuous corners' correction (Tests/ContinuousCornerTests.c).
    for(int angle=-90;angle<=90;angle++) {
        float a=angle*3.14159265359f/180.f;
        float x=w*.5f-h*.5f+radius*cosf(a),y=radius*sinf(a);
        near(WXGCapsuleOpticalField(x,y,w,h).distance+inset+WXGContinuousCorrection(x,y,w,h),0);
        near(WXGCapsuleOpticalField(-x,y,w,h).distance+inset+WXGContinuousCorrection(-x,y,w,h),0);
    }
    for(int i=0;i<=1000;i++) near(WXGInnerInset(h,press,reduction,-(inset+i/100.f)),inset);
    near(WXGInnerInset(h,0,reduction,-8),0);
    near(WXGInnerInset(h,press,reduction,0),0);
    near(WXGRimStrength(1,0,0),1);
    assert(WXGPressedBorderAlpha(0)==0);
    printf("PASS: %u TEST6 ordinary samples preserved; 2..8 amplitude grows; edge-fade/full-coverage toggle; regular parallel inner contour.\n",oldCases);
    return 0;
}
