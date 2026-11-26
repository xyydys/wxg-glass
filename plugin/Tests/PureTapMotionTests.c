#include "../Sources/WXGPureTapMotion.h"
#include <assert.h>
#include <stdio.h>

static double center(WXGPureTapPose pose) {
    return pose.geometry.lensX+pose.geometry.lensWidth*.5;
}

/* The first Me tab emitted no main-thread frame for 227 ms. On the first
   Discover switch the 74 ms gap was followed by a 118 ms gap. Start at the
   measured bar dimensions, and advance only the pre-submitted track. */
static void replayGap(int from,int to,double gapStart,double gapEnd) {
    WXGPureTapLayout layout={356.18f,66.5535f,3.260844f,10,12,1.13f,1.035f,7.055f,19.4891f,
                             WXGLensFlexDefaults(),1};
    layout.flex.on=1;layout.flex.gainX*=1.0629;layout.flex.gainY*=1.0629;
    layout.flex.restFlattest=.8983;layout.flex.flatten=1.0005;layout.flex.squeeze=.8001;
    double x0=layout.originX+WXGDockCellCenter(layout.width,layout.gap,layout.extra,from);
    double x1=layout.originX+WXGDockCellCenter(layout.width,layout.gap,layout.extra,to);
    double duration=WXGDockSpringDuration(.4,.86);
    WXGDockScript script=WXGScriptGlide(0,x0,x1,duration,0,1,to,.4);
    WXGScriptUseSpring(&script,.4,.86);
    int count=(int)ceil(duration*120)+1,inside=0;
    double dt=duration/(count-1),lastInside=0,firstInside=0;
    WXGLensFlex flex={0};
    WXGPureTapPose shown={0};
    for(int i=0;i<count;i++){
        double t=i*dt;
        shown=WXGPureTapSample(&script,layout,flex,t,i?dt:0);
        flex=shown.flex;
        if(t>=gapStart && t<=gapEnd) {
            if(!inside)firstInside=center(shown);
            lastInside=center(shown);++inside;
        }
        if(t+dt>=gapEnd)break;
    }
    assert(inside>=12 && fabs(lastInside-firstInside)>10);
    /* Touch-up arrives after the gap; use the same wall-clock instant and
       flex state for the new release segment. It must not snap backwards. */
    WXGPureTapPose before=WXGPureTapSample(&script,layout,flex,gapEnd,0);
    WXGScriptDrop(&script,gapEnd,.23);WXGScriptHang(&script,gapEnd,.18);
    WXGPureTapPose after=WXGPureTapSample(&script,layout,flex,gapEnd,0);
    assert(fabs(center(before)-center(after))<.0001);
    assert(fabs(before.press-after.press)<.0001 && fabs(before.selection-after.selection)<.0001);
    for(double t=gapEnd+dt;t<script.end;t+=dt)flex=WXGPureTapSample(&script,layout,flex,t,dt).flex;
    WXGPureTapPose rest=WXGPureTapSample(&script,layout,flex,script.end,dt);
    assert(rest.press==0 && rest.selection==1);
    assert(fabs(WXGScriptMoveValue(&script,script.end)-x1)<.0001);
    printf("R8 switch %d to %d: %d submitted samples inside the %.0f ms main-thread gap\n",
           from+1,to+1,inside,(gapEnd-gapStart)*1000);
}
int main(void) {
    replayGap(0,3,-.004,.223);
    replayGap(1,2,.074,.192);
    return 0;
}
