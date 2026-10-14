#include "../Sources/WXGLensOptics.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static float composite(float glass,float selection,float alpha,float coverage,float press) {
    float fill=alpha*coverage*WXGRestingSelectionWeight(press);
    return glass+(selection-glass)*fill;
}

int main(void) {
    // Resting selection is unchanged, including spring undershoot at rest.
    assert(WXGRestingSelectionWeight(-.1f)==1.f);
    assert(WXGRestingSelectionWeight(0.f)==1.f);
    assert(WXGRestingSelectionWeight(.05f)==1.f);
    // FIX98: the touch-down bump (0.10) keeps nearly all of it; half at 0.25;
    // gone by 0.45 (was 0.12).
    assert(WXGRestingSelectionWeight(.10f)>.95f);
    assert(fabsf(WXGRestingSelectionWeight(.25f)-.5f)<1e-6f);
    assert(WXGRestingSelectionWeight(.45f)==0.f);
    float previous=1.f,worst=0.f;
    for(int i=0;i<=1200;i++) {
        float press=(float)i/1000.f;
        float weight=WXGRestingSelectionWeight(press);
        assert(weight>=0.f && weight<=1.f && weight<=previous);
        if(previous-weight>worst)worst=previous-weight;
        previous=weight;
        if(i>=450)assert(weight==0.f);
    }
    // Gradual: no step of 0.001 in press changes it by more than 0.004.
    assert(worst<.004f);
    // Once raised, coverage of the dock must never change the lens colour.
    // The old alpha*coverage rule gave these two lens pixels different fills.
    for(int i=45;i<=120;i++)for(int a=0;a<=100;a++)for(int c=0;c<=100;c++) {
        float press=i*.01f,alpha=a*.01f,coverage=c*.01f;
        assert(composite(.25f,.9f,alpha,coverage,press)==.25f);
    }
    assert(fabsf(composite(.25f,.9f,.3f,1.f,0.f)-.445f)<1e-6f);
    assert(composite(.25f,.9f,1.f,0.f,0.f)==.25f);
    // Smoothstep gives continuous, flat endpoints for reveal and restoration.
    float epsilon=.0001f;
    assert(fabsf(1.f-WXGRestingSelectionWeight(.05f+epsilon))<.00001f);
    assert(fabsf(WXGRestingSelectionWeight(.45f-epsilon))<.00001f);
    puts("PASS: resting selection preserved; fades over press 0.05..0.45 (FIX98, was 0..0.12), gradual; raised lens independent of selection colour/opacity and dock overlap; continuous endpoints.");
}
