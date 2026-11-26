#include "../Sources/WXGMenuMorph.h"
#include <assert.h>
#include <stdio.h>

static const WXGMenuBox source = {340., 64., 44., 44.};
static const WXGMenuBox menu = {164., 64., 220., 230.};

static void near(double actual, double expected) {
    if (!(fabs(actual - expected) <= .002)) {
        fprintf(stderr, "MenuMorphTests: expected %.6f, got %.6f\n", expected, actual);
        assert(false);
    }
}

static void boxNear(WXGMenuBox actual, WXGMenuBox expected) {
    near(actual.x, expected.x);
    near(actual.y, expected.y);
    near(actual.w, expected.w);
    near(actual.h, expected.h);
}

static void stepFrames(WXGMenuMorph *motion, int count) {
    for (int i = 0; i < count; ++i) WXGMenuMorphAdvance(motion, 1. / 120.);
}

static WXGMenuMorph makeMotion(void) {
    WXGMenuMorph motion;
    WXGMenuMorphInitialize(&motion, source, menu, 34., source, true);
    WXGMenuMorphSetAbsorbDuration(&motion, .48);
    return motion;
}

/* Sampled at 120 Hz from GlassMotion.kt at 0021efd8ab0d, at density 1. */
static void testReferenceFrames(void) {
    WXGMenuMorph motion = makeMotion();
    WXGMenuMorphSetExpanded(&motion, true);
    boxNear(motion.frame.bounds, (WXGMenuBox){351.47827, 75.47826, 21.04346, 21.04347});
    boxNear(motion.frame.sourceLobe, source);
    near(motion.frame.sourceOpacity, 1.);

    stepFrames(&motion, 8);
    WXGMenuMorphFrame frame = motion.frame;
    boxNear(frame.bounds, (WXGMenuBox){291.78864, 59.71498, 107.32355, 109.43915});
    boxNear(frame.sourceLobe, (WXGMenuBox){337.61484, 81.12970, 29.68915, 29.68912});
    near(frame.radiusX, 76.93293);
    near(frame.smoothing, 11.85095);
    near(frame.sourceOpacity, .56634);
    near(frame.rowsOpacity, .40688);
    near(frame.contentZoom, 1.37204);
    near(frame.contentBlur, 10.67622);
    near(frame.lensHeight, 32.19707);
    near(frame.portalBlur, 3.55528);

    stepFrames(&motion, 27);
    frame = motion.frame;
    boxNear(frame.bounds, (WXGMenuBox){158.40063, 65.59113, 224.01807, 234.40637});
    near(frame.radiusX, 32.02417);
    near(frame.smoothing, 13.08663);

    stepFrames(&motion, 25);
    WXGMenuMorphSetExpanded(&motion, false);
    stepFrames(&motion, 14);
    frame = motion.frame;
    boxNear(frame.bounds, (WXGMenuBox){286.25742, 53.70419, 109.04816, 121.36331});
    boxNear(frame.sourceLobe, (WXGMenuBox){337.29422, 65.62873, 27.80005, 27.80002});
    near(frame.smoothing, 17.13997);
    near(frame.sourceOpacity, .50883);
    near(frame.rowsOpacity, .04441);
    near(frame.contentBlur, 17.20054);
    near(frame.lensHeight, 22.56960);
}

static void testInterruptAndSettle(void) {
    WXGMenuMorph motion = makeMotion();
    WXGMenuMorphSetExpanded(&motion, true);
    stepFrames(&motion, 16);
    WXGMenuMorphFrame before = motion.frame;
    WXGMenuMorphSetExpanded(&motion, false);
    boxNear(motion.frame.bounds, before.bounds);
    boxNear(motion.frame.sourceLobe, before.sourceLobe);
    near(motion.frame.rowsOpacity, before.rowsOpacity);

    stepFrames(&motion, 11);
    before = motion.frame;
    WXGMenuMorphSetExpanded(&motion, true);
    boxNear(motion.frame.bounds, before.bounds);
    boxNear(motion.frame.sourceLobe, before.sourceLobe);
    near(motion.frame.sourceOpacity, before.sourceOpacity);
    assert(WXGMenuMorphAdvance(&motion, 2.));
    boxNear(motion.frame.bounds, menu);
    near(motion.frame.radiusX, 34.);
    near(motion.frame.smoothing, 0.);
    near(motion.frame.rowsOpacity, 1.);
    near(motion.frame.sourceOpacity, 0.);
    near(motion.frame.contentZoom, 1.);

    WXGMenuMorphSetExpanded(&motion, false);
    assert(WXGMenuMorphAdvance(&motion, 2.));
    boxNear(motion.frame.sourceLobe, source);
    near(motion.frame.smoothing, 0.);
    near(motion.frame.rowsOpacity, 0.);
    near(motion.frame.sourceOpacity, 1.);
    assert(WXGMenuMorphVisuallyCollapsed(&motion));
}

static void testTargetChangeAndFrameRate(void) {
    WXGMenuMorph pose60 = makeMotion();
    WXGMenuMorphSetExpanded(&pose60, true);
    WXGMenuMorph pose120 = pose60;
    for (int i = 0; i < 10; ++i) WXGMenuMorphAdvance(&pose60, 1. / 60.);
    stepFrames(&pose120, 20);
    boxNear(pose60.frame.bounds, pose120.frame.bounds);
    boxNear(pose60.frame.sourceLobe, pose120.frame.sourceLobe);
    near(pose60.frame.smoothing, pose120.frame.smoothing);

    WXGMenuBox target = {176., 74., 198., 185.};
    WXGMenuMorphUpdateTarget(&pose60, target, 25.);
    assert(WXGMenuMorphAdvance(&pose60, 2.));
    boxNear(pose60.frame.bounds, target);
    near(pose60.frame.radiusX, 25.);

    WXGMenuBox moved = {330., 75., 42., 42.};
    WXGMenuMorphSetExpanded(&pose60, false);
    WXGMenuMorphUpdateSource(&pose60, moved, moved);
    assert(WXGMenuMorphAdvance(&pose60, 2.));
    boxNear(pose60.frame.sourceLobe, moved);
}

// Reported 440 x 956 phone: the original UIImageView is 132 x 217 at
// (300, 100); the first row of the expanded menu lies outside its parent.
static void testWindowMenuPlacement(void) {
    WXGMenuBox plus={379.676,57.599,41.469,41.469};
    WXGMenuBox screen={0.,0.,440.,956.};
    WXGMenuBox viewport={0.,62.,440.,860.};
    WXGMenuBox target=WXGMenuMorphPlacePanel(plus,screen,viewport,200.,164.);
    boxNear(target,(WXGMenuBox){221.145,57.599,200.,164.});
    for(int width=160;width<=320;width+=40) {
        WXGMenuBox panel=WXGMenuMorphPlacePanel(plus,screen,viewport,width,164.);
        near(panel.x+panel.w,plus.x+plus.w);
        near(panel.y,plus.y);
    }
    assert(target.x+10.<300. && target.y+10.+18.<100.);
    WXGMenuBox native={300.,105.,132.,212.};
    for(int i=0;i<4;i++) {
        double x=target.x+20.,y=target.y+10.+(i+.5)*36.;
        assert(WXGMenuMorphHitZoneAt(target,x,y,WXGMenuMorphPointInBox(native,x,y))==WXGMenuMorphInsidePanel);
        for(int j=0;j<4;j++) {
            WXGMenuBox row={10.,10.+36.*j,target.w-20.,36.};
            assert(WXGMenuMorphPointInBox(row,x-target.x,y-target.y)==(i==j));
        }
    }
    assert(WXGMenuMorphHitZoneAt(target,320.,260.,true)==WXGMenuMorphNativeBackdrop);
    assert(WXGMenuMorphHitZoneAt(target,250.,260.,false)==WXGMenuMorphPassThrough);
    assert(WXGMenuMorphHitZoneAt(target,250.,64.,false)==WXGMenuMorphInsidePanel); // top padding
    WXGMenuMorph motion;
    WXGMenuMorphInitialize(&motion,plus,target,32.,plus,false);
    WXGMenuMorphSetExpanded(&motion,true);
    assert(!WXGMenuMorphAdvance(&motion,1./120.));
    assert(motion.frame.bounds.w<target.w);
    assert(WXGMenuMorphAdvance(&motion,2.));
    boxNear(motion.frame.bounds,target);
    assert(WXGMenuMorphPlacePanel(plus,screen,viewport,441.,164.).w==0.);
    boxNear(WXGMenuMorphPlacePanel((WXGMenuBox){0.,895.,40.,40.},screen,viewport,200.,164.),
            (WXGMenuBox){0.,758.,200.,164.});
    boxNear(WXGMenuMorphPlacePanel((WXGMenuBox){412.,-3.,40.,40.},screen,viewport,200.,164.),
            (WXGMenuBox){240.,0.,200.,164.});
}

static void testSelectionDuringExpansion(void) {
    const WXGMenuBox plus={379.676,57.599,41.469,41.469},panel={221.145,57.599,200.,164.};
    const double openingTimes[]={0.,.05,.15,.32,1.2};
    const double speeds[]={.5,1.,2.};
    const unsigned rates[]={60,120};
    for(size_t i=0;i<sizeof(openingTimes)/sizeof(*openingTimes);++i) {
        for(size_t j=0;j<sizeof(speeds)/sizeof(*speeds);++j) {
            for(size_t k=0;k<sizeof(rates)/sizeof(*rates);++k) {
                WXGMenuMorph motion;
                WXGMenuMorphInitialize(&motion,plus,panel,32.,plus,false);
                WXGMenuMorphSetAbsorbDuration(&motion,.48);
                WXGMenuMorphSetExpanded(&motion,true);
                WXGMenuMorphAdvance(&motion,openingTimes[i]);
                WXGMenuMorphSetExpanded(&motion,false);
                unsigned ticks=0;
                while(!WXGMenuMorphAdvance(&motion,speeds[j]/rates[k])) {
                    ++ticks;
                    assert(ticks<2*rates[k]);
                }
                // The completion used to dispatch the row's action cannot
                // leave a visible menu shell over the destination screen.
                assert(WXGMenuMorphVisuallyCollapsed(&motion));
            }
        }
    }
}

int main(void) {
    testWindowMenuPlacement();
    testSelectionDuringExpansion();
    testReferenceFrames();
    testInterruptAndSettle();
    testTargetChangeAndFrameRate();
    puts("MenuMorphTests: Kotlin reference frames, interrupt, settling and 60/120 Hz parity passed.");
}
