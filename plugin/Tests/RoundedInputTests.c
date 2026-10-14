#include "../Sources/WXGOptics.h"
#include "../Sources/WXGGeometry.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    int cases=0;
    for(int height=40;height<=180;height++) {
        WXGShapeSample side=WXGRoundedOpticalField(150,0,300,height,22);
        WXGShapeSample top=WXGRoundedOpticalField(0,-height*.5f,300,height,22);
        assert(fabsf(side.distance)<1e-4 && side.nx>.99);
        assert(fabsf(top.distance)<1e-4 && top.ny<-.99);
        for(int x=-160;x<=160;x+=4)for(int y=-100;y<=100;y+=4) {
            WXGShapeSample a=WXGRoundedOpticalField(x,y,300,height,22),b=WXGRoundedOpticalField(-x,-y,300,height,22);
            assert(isfinite(a.distance) && isfinite(a.nx) && isfinite(a.ny));
            assert(fabsf(a.distance-b.distance)<1e-4);cases++;
        }
        WXGInputGeometry input=WXGInputLayout(414,0,0,520,height,height-10,1);
        assert(input.editor.y>=input.pill.y && input.editor.y+input.editor.h<=input.pill.y+input.pill.h+.001);
        assert(input.pill.h>=37 && input.editor.w>200);
    }
    // A tall text field has a straight side, rather than an endcap with radius h/2.
    assert(fabsf(WXGRoundedOpticalField(150,35,300,120,22).distance)<1e-4);
    assert(WXGCapsuleOpticalField(150,35,300,120).distance>5);
    printf("PASS: %d growing rounded-editor contour samples, finite normals and native-editor containment.\n",cases);
}
