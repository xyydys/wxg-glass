#include "../Sources/WXGElasticMotion.h"
#include <assert.h>
#include <stdio.h>
static double run(int fps) {
    WXGElasticMotion s={0};double dt=1./fps;
    WXGDockGeometry rest=WXGElasticLayout(380,68,6,190,1,1.28,0,s,1.025,4);
    for(int i=0;i<fps*2;i++)WXGElasticStep(&s,1500,dt);
    WXGDockGeometry fast=WXGElasticLayout(380,68,6,190,1,1.28,0,s,1.025,4);
    assert(fast.lensWidth>rest.lensWidth*1.25);
    // FIX37: sustained fast travel ends slightly thinner than the bar (iOS 26),
    // about 90% of its height, never collapsing further.
    assert(fast.lensHeight<rest.lensHeight && fast.lensHeight<fast.barHeight);
    assert(fast.lensHeight>fast.barHeight*.86);
    double minimum=0,highest=0;
    for(int i=0;i<fps*2;i++) {
        WXGElasticStep(&s,0,dt);minimum=fmin(minimum,s.stretch);
        WXGDockGeometry g=WXGElasticLayout(380,68,6,190,1,1.28,0,s,1.025,4);
        highest=fmax(highest,g.lensHeight);
    }
    assert(minimum<-.02 && highest>rest.lensHeight);
    for(int i=0;i<fps*2;i++)WXGElasticStep(&s,1200,dt);
    double before=s.stretch;WXGElasticStep(&s,-1200,dt);
    assert(fabs(s.stretch-before)<.001); // Direction reversal alone is not a speed spike.
    WXGElasticStep(&s,0,.25);assert(isfinite(s.stretch));
    for(int i=0;i<fps*5;i++)WXGElasticStep(&s,0,dt);
    assert(fabs(s.stretch)<1e-5 && fabs(s.velocity)<1e-4);
    return minimum;
}
int main(void) {
    double a=run(30),b=run(60),c=run(120),d=run(240);
    assert(fabs(b-c)<.035 && fabs(c-d)<.025);
    unsigned cases=0;
    for(int w=280;w<=600;w+=20)for(int h=54;h<=90;h+=4)for(int j=0;j<=100;j++)for(int k=0;k<5;k++) {
        float p=j*.01f,anchor=WXGSelectionCenter(w,6,0)+(WXGSelectionCenter(w,6,3)-WXGSelectionCenter(w,6,0))*k/4.f;
        WXGElasticMotion s={0};s.stretch=j%2?log(WXG_ELASTIC_MIN):log(WXG_ELASTIC_MAX);
        WXGDockGeometry g=WXGElasticLayout(w,h,6,anchor,p,1.28,0,s,1.08,10);
        WXGDockGeometry demo=WXGDockLayout(w,h,6,anchor,p,1.28,0,1.08,10);
        assert(g.barHeight==demo.barHeight && g.scale==demo.scale);
        assert(fabs(g.lensY+g.lensHeight*.5-h*.5)<1e-4);
        if(p<=.65f)assert(g.lensX==demo.lensX && g.lensY==demo.lensY && g.lensWidth==demo.lensWidth && g.lensHeight==demo.lensHeight);
        if(p<=.65f) {
            WXGDockGeometry movingDemo=WXGDockLayout(w,h,6,anchor,p,1.28,.1f*p,1.08,10);
            WXGDockGeometry hybrid=WXGElasticLayout(w,h,6,anchor,p,1.28,.1f*p,s,1.08,10);
            assert(hybrid.lensX==movingDemo.lensX && hybrid.lensWidth==movingDemo.lensWidth && hybrid.lensHeight==movingDemo.lensHeight);
        }
        s.stretch=0;WXGDockGeometry still=WXGElasticLayout(w,h,6,anchor,p,1.28,0,s,1.08,10);
        assert(still.lensX==demo.lensX && still.lensWidth==demo.lensWidth && still.lensHeight==demo.lensHeight);
        assert(g.lensX>=-WXGCanvasPaddingX && g.lensX+g.lensWidth<=w+WXGCanvasPaddingX);
        assert(g.lensY>=-WXGCanvasPaddingY && g.lensY+g.lensHeight<=h+WXGCanvasPaddingY);cases++;
        /* FIX113 Y: share 1 is the old layout exactly; 0 keeps the height of no
           deformation (the width still stretches); between, in between. */
        s.stretch=j%2?log(WXG_ELASTIC_MIN):log(WXG_ELASTIC_MAX);
        WXGDockGeometry one=WXGElasticLayoutLimited(w,h,6,anchor,p,1.28,0,s,1.08,10,1),none=WXGElasticLayoutLimited(w,h,6,anchor,p,1.28,0,s,1.08,10,0);
        WXGDockGeometry half=WXGElasticLayoutLimited(w,h,6,anchor,p,1.28,0,s,1.08,10,.5f);
        assert(one.lensHeight==g.lensHeight && one.lensWidth==g.lensWidth && one.lensX==g.lensX);
        assert(fabsf(none.lensHeight-WXG_MIN(demo.lensHeight,h+2*(WXGCanvasPaddingY-4)))<1e-3f && none.lensWidth==g.lensWidth);
        assert(half.lensHeight>=fminf(one.lensHeight,none.lensHeight)-1e-3f && half.lensHeight<=fmaxf(one.lensHeight,none.lensHeight)+1e-3f);
    }
    printf("PASS: %u hybrid geometries; exact demo reveal below 65%% and all zero-speed shapes; fast/brake/reversal/drop/settling at 30/60/120/240 Hz (strain %.3f/%.3f/%.3f/%.3f); FIX113 Y height share 1 / 0 / between.\n",cases,a,b,c,d);
}
