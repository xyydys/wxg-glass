#include "../Sources/WXGGeometry.h"
#include <assert.h>
#include <stdio.h>
static int near(double a,double b) {return fabs(a-b)<1e-7;}
int main(void) {
    const double widths[]={320,375,390,393,414,430,440};
    const double scales[]={.85,1,1.20};
    const double glyphs[][2]={{20,20},{9,17.333333},{18,4},{22,18},{18,18}};
    int cases=0;
    for(unsigned wi=0;wi<sizeof(widths)/sizeof(widths[0]);wi++)for(unsigned si=0;si<3;si++) {
        double w=widths[wi],scale=scales[si];WXGMetrics m=WXGMeasure(w,scale);
        /* Two circular top actions must have equal edge distances/heights and
           nonoverlapping 44 pt hit regions, including the 320 pt screen. */
        double right=w-m.edge-m.button,leftOfRight=right-m.gap-m.button;
        assert(near(w-(right+m.button),m.edge));assert(leftOfRight>w/2);
        assert(m.button+m.gap>=44);assert(m.button>=36);
        for(unsigned g=0;g<5;g++) {
            WXGRect ink=WXGCenteredInk(m.button,m.button,glyphs[g][0],glyphs[g][1],m.button*.5);
            assert(near(ink.x+ink.w*.5,m.button*.5));assert(near(ink.y+ink.h*.5,m.button*.5));
            assert(near(ink.w/ink.h,glyphs[g][0]/glyphs[g][1]));++cases;
        }
        for(unsigned state=0;state<3;state++) {
            double centerY=state==0?834:state==1?513:468;
            double grow=state==2?100:40,nativeText=state==2?90:30;
            WXGInputGeometry in=WXGInputLayout(w,0,0,centerY,grow,nativeText,scale);
            assert(near(in.plus.x,w-(in.pill.x+in.pill.w)));
            assert(near(in.plus.y+in.plus.h*.5,in.pill.y+in.pill.h*.5));
            assert(near(in.mic.y+in.mic.h*.5,centerY));
            assert(in.plus.x+in.plus.w<in.pill.x);assert(in.editor.x+in.editor.w<=in.mic.x);
            assert(in.editor.h>=24);assert(in.editor.y>=in.pill.y);assert(in.editor.y+in.editor.h<=in.pill.y+in.pill.h+.001);
            assert(in.pill.x+in.pill.w<=w);++cases;
        }
        /* One- and multi-word text, unread count widths and very long titles
           grow smoothly but remain bounded by the available navigation gap. */
        double previous=0;
        for(int text=0;text<1200;text+=7) {
            double width=WXGCapsuleWidth(text,0,m.button,14*m.scale,w*.38);
            assert(width>=m.button);assert(width<=w*.38);assert(width>=previous);previous=width;++cases;
        }
    }
    /* Landscape safe areas must not skew the input margins. */
    WXGInputGeometry rotated=WXGInputLayout(896,44,44,360,40,30,1);
    assert(near(rotated.plus.x-44,896-44-(rotated.pill.x+rotated.pill.w)));
    printf("Integration geometry: %d scenarios passed\n",cases);return 0;
}
