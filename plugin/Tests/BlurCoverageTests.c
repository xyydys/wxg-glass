#include "../Sources/WXGOptics.h"
#include <assert.h>
#include <stdio.h>

static void near(float a,float b) { assert(fabsf(a-b)<.0002f); }
int main(void) {
    unsigned profiles=0;
    for(int wi=1;wi<=60;wi++) for(int di=-10;di<=120;di++) {
        float width=(float)wi,distance=-width*di/100.f;
        float t=fminf(1,fmaxf(0,-distance/width));
        float oldEdge=1-t*t*(3-2*t);
        // Zero coverage must preserve the accepted raw/blur mix and clear ring.
        near(WXGBlurSharpWeight(distance,width,0),.88f*oldEdge*oldEdge);
        near(WXGLensRingBlurWeight(distance,width,0),0);
        float lastSharp=1,lastRing=0;
        for(int ci=0;ci<=100;ci++) {
            float coverage=ci/100.f;
            float sharp=WXGBlurSharpWeight(distance,width,coverage);
            float ring=WXGLensRingBlurWeight(distance,width,coverage);
            assert(isfinite(sharp) && sharp>=0 && sharp<=1);
            assert(isfinite(ring) && ring>=0 && ring<=1);
            assert(sharp<=lastSharp+.000001f && ring+.000001f>=lastRing);
            lastSharp=sharp; lastRing=ring;
        }
        // At maximum, no raw backdrop remains at any depth, including the edge.
        near(lastSharp,0); near(lastRing,1); ++profiles;
    }
    for(int wi=1;wi<=60;wi++) for(int di=0;di<=100;di++) {
        float w=(float)wi,d=-w*di/100.f,t=di/100.f;
        float edge=1-t*t*(3-2*t),previous=0;
        for(int si=0;si<=200;si++) {
            float s=si/10.f,value=WXGOpticalOffset(d,w,s);
            assert(isfinite(value) && value>=previous-.0001f);
            if(si<=80) near(value,w*(fminf(.32f*s,.40f)+.32f*fmaxf(0,s-2))*edge*edge);
            previous=value;
        }
        if(di<100) assert(WXGOpticalOffset(d,w,20)>WXGOpticalOffset(d,w,8));
    }
    assert(WXGOpticalOffset(-20,60,8)>WXGOpticalOffset(-20,14,8));
    near(WXGOpticalOffset(0,60,20),369.6f);
    near(WXGOpticalOffset(0,60,30),WXGOpticalOffset(0,60,20));
    printf("PASS: %u blur profiles; zero preserves TEST8, maximum fully blurred; refraction 0..20 and width 1..60.\n",profiles);
    return 0;
}
