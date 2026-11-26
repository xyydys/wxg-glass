#include "../Sources/WXGMenuScrub.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    // Golden values from GlassMenuSession/GlassJelly, using the dimensions
    // and speed in the morph13 device trace. Sample the *moving* plate.
    WXGMenuBox panel={195.8115321232,57.5988393333,225.3333333333,164.};
    WXGMenuScrub s=WXGMenuScrubInitial(1.);
    double dt=.840334177/120.;
    WXGMenuScrubDown(&s,250,84);
    WXGMenuScrubSelect(&s,10,36,true);
    assert(s.top.value==10. && s.height.value==36. && s.alpha.value==1.);
    WXGMenuScrubAdvance(&s,2.*dt,false);
    for(int i=0;i<3;i++)WXGMenuScrubAdvance(&s,dt,false);
    WXGMenuScrubMove(&s,263,120);WXGMenuScrubSelect(&s,46,36,false);
    WXGMenuScrubAdvance(&s,dt,false);
    WXGMenuBox shown=WXGMenuScrubBounds(panel,&s,true,false);
    assert(fabs(s.top.value-11.701752)<.0001);
    assert(fabs(shown.x-195.88943)<.0001 && fabs(shown.y-57.633034)<.0001);
    assert(fabs(shown.w-225.23389)<.0001 && fabs(shown.h-164.08759)<.0001);
    assert(fabs(s.lightY.value-85.174545)<.0001);

    double velocity=s.top.velocity;
    WXGMenuScrubMove(&s,240,84);WXGMenuScrubSelect(&s,10,36,false);
    assert(s.top.velocity==velocity);
    WXGMenuScrubClear(&s);
    WXGMenuScrubAdvance(&s,dt,false);
    assert(s.alpha.value>0. && s.alpha.value<1.);
    WXGMenuScrubSelect(&s,118,36,false);
    assert(s.top.value==118. && s.top.velocity==0.);
    WXGMenuScrubRelease(&s);WXGMenuScrubClear(&s);
    bool done=false;
    for(int i=0;i<240 && !done;i++)done=WXGMenuScrubAdvance(&s,dt,false);
    assert(done && !s.touching && s.alpha.value==0.);
    shown=WXGMenuScrubBounds(panel,&s,true,false);
    assert(fabs(shown.x-panel.x)<1e-12 && fabs(shown.y-panel.y)<1e-12);
    assert(shown.w==panel.w && shown.h==panel.h);
    puts("PASS: Expo scrub first contact, in-flight retarget, live bounds, fade, cancel and return.");
    return 0;
}
