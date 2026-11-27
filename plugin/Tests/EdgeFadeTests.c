#include "../Sources/WXGEdgeFadeMath.h"
#include <assert.h>
#include <stdio.h>

static int near(float a,float b) {return fabsf(a-b)<1e-4f;}

int main(void) {
    /* Fade: transparent at both edges, opaque past the bands, smoothstep in between. */
    const float h=700.f,top=96.f,bottom=112.f;
    assert(near(WXGEdgeFadeAlpha(0.f,h,top,bottom),0.f));
    assert(near(WXGEdgeFadeAlpha(h,h,top,bottom),0.f));
    assert(near(WXGEdgeFadeAlpha(top,h,top,bottom),1.f) && near(WXGEdgeFadeAlpha(h-bottom,h,top,bottom),1.f));
    assert(near(WXGEdgeFadeAlpha(48.f,h,top,bottom),.5f) && near(WXGEdgeFadeAlpha(h-56.f,h,top,bottom),.5f));
    float previous=-1.f;
    for(int i=0;i<=96;i++) {
        float a=WXGEdgeFadeAlpha((float)i,h,top,bottom);
        assert(a>=previous);previous=a;
    }
    /* Off below half a point; a band longer than the list is the list. */
    assert(near(WXGEdgeFadeAlpha(0.f,h,0.f,0.f),1.f) && near(WXGEdgeFadeAlpha(0.f,h,.4f,0.f),1.f));
    assert(near(WXGEdgeFadeAlpha(150.f,300.f,320.f,0.f),WXGEdgeFadeSmooth(.5f)));
    /* Overlapping bands: the smaller alpha (never above either). */
    for(int i=0;i<=200;i++) {
        float y=(float)i,a=WXGEdgeFadeAlpha(y,200.f,150.f,150.f);
        assert(a<=WXGEdgeFadeSmooth(y/150.f)+1e-6f && a<=WXGEdgeFadeSmooth((200.f-y)/150.f)+1e-6f);
    }
    for(int y=0;y<=(int)h;y++) {
        assert(near(WXGEdgeCoverAlpha(y,h,top,bottom,0)+WXGEdgeFadeAlpha(y,h,top,bottom),1));
        assert(near(WXGEdgeCoverAlpha(y,h,top,bottom,1)+WXGEdgeFadeAlpha(y,h,0,bottom),1));
    }
    assert(WXGEdgeCoverAlpha(-1,h,top,bottom,0)==0 && WXGEdgeCoverAlpha(h+1,h,top,bottom,0)==0);
    /* Blur strength: 1 at the edge, 0 at the inner end, never rising, the
       table's own values at its stops. */
    assert(WXGEdgeBlurStrength(0.f)==1.f && WXGEdgeBlurStrength(-1.f)==1.f && WXGEdgeBlurStrength(1.f)==0.f);
    assert(near(WXGEdgeBlurStrength(6.f/287.f),215.f/216.f));
    assert(near(WXGEdgeBlurStrength(209.f/287.f),23.f/216.f));
    assert(near(WXGEdgeBlurStrength(257.f/287.f),6.f/216.f));
    previous=2.f;
    for(int i=0;i<=1000;i++) {
        float s=WXGEdgeBlurStrength(i/1000.f);
        assert(s<=previous+1e-6f && s>=0.f && s<=1.f);previous=s;
    }
    /* Band extents. */
    assert(WXGEdgeBand(0.f,700.f)==0.f && WXGEdgeBand(.4f,700.f)==0.f && WXGEdgeBand(96.f,700.f)==96.f && WXGEdgeBand(900.f,700.f)==700.f);
    assert(WXGEdgeBand(96.f,0.f)==0.f);
    /* FIX67: the mini-program panel: closed at rest (88 / 896) and for a small
       pull, open near the bottom, never decreasing in between. */
    assert(WXGHomePanelProgress(88.f/896.f)==0.f && WXGHomePanelProgress((88.f+70.f)/896.f)==0.f);
    assert(WXGHomePanelProgress(830.f/896.f)==1.f && WXGHomePanelProgress(.42f)==1.f);
    previous=-1.f;
    for(int i=0;i<=100;i++){float k=WXGHomePanelProgress(i/100.f);assert(k>=previous && k>=0.f && k<=1.f);previous=k;}
    puts("PASS: edge fade (FIX64): smoothstep fade both edges (129-stop mask math), bands clamped, overlap takes the smaller; edge blur table 1 -> 0 monotonic at its exact stops; mini-program panel progress.");
    return 0;
}
