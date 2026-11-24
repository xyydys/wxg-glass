#include "../Sources/WXGMenuCascade.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failCount = 0;
#define CHECK(cond, msg, ...) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL: " msg "\n", ##__VA_ARGS__); \
        failCount++; \
    } \
} while (0)

static void testLayoutMetrics(void) {
    WXGMenuMetrics m = WXGMenuMetricsFor(44.0, 56.0);
    CHECK(fabs(m.icon - 44.0) < 1e-6, "icon=44 expected, got %.3f", m.icon);
    CHECK(m.capsuleHeight >= 32.0 && m.capsuleHeight <= 36.0, "capsuleHeight %.1f out of spec [32..36]", m.capsuleHeight);
    CHECK(m.gap >= 10.0 && m.gap <= 14.0, "gap %.1f out of spec [10..14]", m.gap);
    CHECK(m.padding >= 14.0 && m.padding <= 16.0, "padding %.1f out of spec [14..16]", m.padding);
    WXGMenuRowBoxes b = WXGMenuRowBoxesFor(180.0, 350.0, 60.0, m, 16.0);
    CHECK(fabs((b.icon.x + b.icon.w * 0.5) - 350.0) < 1e-6, "icon not centered on plus");
    CHECK(fabs((b.capsule.x + b.capsule.w) - (b.icon.x - m.gap)) < 1e-6, "capsule right edge mismatch");
}

static const double kPi = 3.14159265358979323846;
static const double kPi4 = 0.78539816339744830962;

static void testTrack1RingAndDots(void) {
    double r = WXGMenuRingRadius(44.0);
    CHECK(r >= 17.5 && r <= 19.5, "ring radius %.2f out of spec [17.5..19.5]", r);
    CHECK(fabs(WXGMenuRingDotDiameter() - 2.5) < 1e-6, "dot diameter must be 2.5pt");
    double deg45 = 45.0 * kPi / 180.0;
    double deg135 = 135.0 * kPi / 180.0;
    for (int i = 0; i < WXGMenuParticleCount; i++) {
        double a = WXGMenuRingDotAngle(i);
        CHECK(a > deg45 && a < deg135, "dot %d angle %.3f outside (45,135) deg gap", i, a);
        if (i > 0) CHECK(a > WXGMenuRingDotAngle(i - 1), "dot angles not increasing");
    }
    CHECK(fabs(WXGMenuRingDotAngle(2) - kPi * 0.5) < 1e-9, "center dot must be at 90 deg (6:00)");
    CHECK(fabs((WXGMenuRingDotAngle(0) + WXGMenuRingDotAngle(4)) * 0.5 - kPi * 0.5) < 1e-9, "dots not symmetric around 6:00");

    // Expand strokeEnd: 1.0 -> 0.0 over 0..150ms monotonically.
    CHECK(fabs(WXGMenuRingStrokeAt(1, 0.0, 1.0) - 1.0) < 1e-6, "open stroke(0) != 1");
    CHECK(fabs(WXGMenuRingStrokeAt(1, 0.150, 1.0) - 0.0) < 1e-6, "open stroke(150ms) != 0");
    double prev = 1.0;
    for (int ms = 1; ms <= 150; ms++) {
        double s = WXGMenuRingStrokeAt(1, ms * 0.001, 1.0);
        CHECK(s <= prev + 1e-9 && s >= -1e-9, "open stroke not monotonic at %dms: %.5f > %.5f", ms, s, prev);
        prev = s;
    }

    // Collapse strokeEnd: holds 0 through 30ms, grows monotonically 0 -> 1 over 30..250ms.
    CHECK(fabs(WXGMenuRingStrokeAt(0, 0.0, 1.0) - 0.0) < 1e-6, "close stroke(0) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(0, 0.030, 1.0) - 0.0) < 1e-6, "close stroke(30ms) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(0, 0.250, 1.0) - 1.0) < 1e-6, "close stroke(250ms) != 1");
    prev = 0.0;
    for (int ms = 30; ms <= 250; ms++) {
        double s = WXGMenuRingStrokeAt(0, ms * 0.001, 1.0);
        CHECK(s >= prev - 1e-9 && s <= 1.0 + 1e-9, "close stroke not monotonic at %dms", ms);
        prev = s;
    }
}

static void testTrack2SymbolSwapZeroBounce(void) {
    // Expand: 0..250ms '+' shrinks 1.0 -> 0.45; swaps to 'x' at 250ms; 250..400ms grows 0.45 -> 1.0 with ZERO overshoot.
    WXGMenuSymbolPose s0 = WXGMenuSymbolPoseAt(1, 0.0, 1.0);
    WXGMenuSymbolPose sPre = WXGMenuSymbolPoseAt(1, 0.249, 1.0);
    WXGMenuSymbolPose sPost = WXGMenuSymbolPoseAt(1, 0.250, 1.0);
    WXGMenuSymbolPose sEnd = WXGMenuSymbolPoseAt(1, 0.400, 1.0);
    CHECK(!s0.isClose && fabs(s0.scale - 1.0) < 1e-6 && fabs(s0.rotationRad) < 1e-6, "open symbol(0) wrong");
    CHECK(!sPre.isClose && fabs(sPre.scale - 0.45) < 0.02, "open symbol pre-trough wrong: scale=%.3f", sPre.scale);
    CHECK(sPost.isClose && fabs(sPost.rotationRad - kPi4) < 1e-6 && fabs(sPost.scale - 0.45) < 1e-6, "open symbol swap at 250ms wrong");
    CHECK(sEnd.isClose && fabs(sEnd.scale - 1.0) < 1e-6, "open symbol(400ms) wrong");
    for (int ms = 0; ms <= 450; ms++) {
        WXGMenuSymbolPose p = WXGMenuSymbolPoseAt(1, ms * 0.001, 1.0);
        CHECK(p.scale <= 1.0 + 1e-9 && p.scale >= 0.45 - 1e-6, "open symbol scale overshoot/undershoot at %dms: %.5f", ms, p.scale);
    }

    // Collapse: 0..180ms 'x' shrinks 1.0 -> 0.45; swaps to '+' at 180ms; 180..350ms grows 0.45 -> 1.0 with ZERO overshoot.
    WXGMenuSymbolPose c0 = WXGMenuSymbolPoseAt(0, 0.0, 1.0);
    WXGMenuSymbolPose cPre = WXGMenuSymbolPoseAt(0, 0.179, 1.0);
    WXGMenuSymbolPose cPost = WXGMenuSymbolPoseAt(0, 0.180, 1.0);
    WXGMenuSymbolPose cEnd = WXGMenuSymbolPoseAt(0, 0.350, 1.0);
    CHECK(c0.isClose && fabs(c0.scale - 1.0) < 1e-6, "close symbol(0) wrong");
    CHECK(cPre.isClose && fabs(cPre.scale - 0.45) < 0.02, "close symbol pre-trough wrong");
    CHECK(!cPost.isClose && fabs(cPost.rotationRad) < 1e-6 && fabs(cPost.scale - 0.45) < 1e-6, "close symbol swap at 180ms wrong");
    CHECK(!cEnd.isClose && fabs(cEnd.scale - 1.0) < 1e-6, "close symbol(350ms) wrong");
    for (int ms = 0; ms <= 400; ms++) {
        WXGMenuSymbolPose p = WXGMenuSymbolPoseAt(0, ms * 0.001, 1.0);
        CHECK(p.scale <= 1.0 + 1e-9 && p.scale >= 0.45 - 1e-6, "close symbol overshoot at %dms: %.5f", ms, p.scale);
    }
}

static void testTrack3InkParticles(void) {
    const double plusX = 350.0, plusY = 80.0, ringR = WXGMenuRingRadius(44.0), lastY = 360.0;
    double maxLeadDiam = 0.0, maxLeadWiggle = 0.0, maxLeadY = 0.0;

    for (int i = 0; i < WXGMenuParticleCount; i++) {
        double a = WXGMenuRingDotAngle(i);
        double dotX = plusX + ringR * cos(a);
        double dotY = plusY + ringR * sin(a);

        // Expand t=0: exact match to static bottom dot anchor.
        WXGMenuParticle p0 = WXGMenuParticlePoseAt(i, 1, 0.0, 1.0, plusX, plusY, ringR, lastY);
        CHECK(fabs(p0.x - dotX) < 1e-6 && fabs(p0.y - dotY) < 1e-6, "open p%d(0) anchor mismatch", i);
        CHECK(fabs(p0.diameter - 2.5) < 1e-6 && fabs(p0.alpha - 1.0) < 1e-6, "open p%d(0) size/alpha mismatch", i);

        // Expand t=550ms: completely vanished.
        WXGMenuParticle pEnd = WXGMenuParticlePoseAt(i, 1, 0.550, 1.0, plusX, plusY, ringR, lastY);
        CHECK(pEnd.diameter <= 1e-6 && pEnd.alpha <= 1e-6, "open p%d(550ms) did not vanish (d=%.3f a=%.3f)", i, pEnd.diameter, pEnd.alpha);

        // Collapse t=0: invisible; t=350ms: docks precisely back to static bottom dot anchor.
        WXGMenuParticle c0 = WXGMenuParticlePoseAt(i, 0, 0.0, 1.0, plusX, plusY, ringR, lastY);
        CHECK(c0.diameter <= 1e-6 && c0.alpha <= 1e-6, "close p%d(0) should be hidden", i);
        WXGMenuParticle cDock = WXGMenuParticlePoseAt(i, 0, 0.350, 1.0, plusX, plusY, ringR, lastY);
        CHECK(fabs(cDock.x - dotX) < 1e-6 && fabs(cDock.y - dotY) < 1e-6, "close p%d(350ms) dock position mismatch", i);
        CHECK(fabs(cDock.diameter - 2.5) < 1e-6 && fabs(cDock.alpha - 1.0) < 1e-6, "close p%d(350ms) dock size/alpha mismatch", i);

        // Continuity across t=250ms handoff (sweep up -> fan along bottom arc).
        WXGMenuParticle cPre = WXGMenuParticlePoseAt(i, 0, 0.2499, 1.0, plusX, plusY, ringR, lastY);
        WXGMenuParticle cPost = WXGMenuParticlePoseAt(i, 0, 0.2501, 1.0, plusX, plusY, ringR, lastY);
        CHECK(hypot(cPre.x - cPost.x, cPre.y - cPost.y) < 1.0, "close p%d discontinuous at 250ms", i);
        CHECK(fabs(cPre.diameter - cPost.diameter) < 0.25, "close p%d diameter jump at 250ms", i);
    }

    // Lead particle (center dot idx=2) swells to 8..11pt, wiggles horizontally, and reaches bottom icon.
    for (int ms = 0; ms <= 550; ms += 2) {
        WXGMenuParticle p = WXGMenuParticlePoseAt(2, 1, ms * 0.001, 1.0, plusX, plusY, ringR, lastY);
        if (p.diameter > maxLeadDiam) maxLeadDiam = p.diameter;
        if (p.alpha > 0.05 && fabs(p.x - plusX) > maxLeadWiggle) maxLeadWiggle = fabs(p.x - plusX);
        if (p.alpha > 0.05 && p.y > maxLeadY) maxLeadY = p.y;
    }
    CHECK(maxLeadDiam >= 8.0 && maxLeadDiam <= 11.0, "lead particle peak diam %.2f out of spec [8..11]", maxLeadDiam);
    CHECK(maxLeadWiggle >= 4.0 && maxLeadWiggle <= 11.0, "lead particle wiggle %.2f out of spec [4..11]", maxLeadWiggle);
    CHECK(maxLeadY >= lastY - 25.0, "lead particle did not descend near last icon (maxY=%.1f, lastY=%.1f)", maxLeadY, lastY);
}

static void testTrack4And5ZeroBounceAndTiming(void) {
    const double pitch = 56.0, halfW = 55.0, stagger = 0.045, speed = 1.0;

    for (int k = 0; k < 5; k++) {
        double slotDist = (k + 1) * pitch;
        WXGMenuEntrance e = WXGMenuEntranceFor(k, slotDist, stagger, speed);
        CHECK(fabs(e.iconDelay - (0.130 + 0.045 * k)) < 1e-6, "row %d iconDelay=%.4f", k, e.iconDelay);
        CHECK(fabs(e.capsuleDelay - (0.230 + 0.050 * k)) < 1e-6, "row %d capsuleDelay=%.4f", k, e.capsuleDelay);
        CHECK(e.capsuleDelay - e.iconDelay >= 0.100 - 1e-6, "row %d capsule must trail icon by >=100ms", k);

        // Verify strictly monotonic ZERO-BOUNCE expand for both icon and capsule.
        double prevIconScale = 0.40, prevIconDy = -45.0, prevIconAlpha = 0.0;
        double prevCapScale = 0.92, prevCapDx = (1.0 - 0.92) * halfW + 14.0, prevCapAlpha = 0.0;
        for (int ms = 0; ms <= 650; ms++) {
            double t = ms * 0.001;
            WXGMenuPose ip = WXGMenuIconPoseAt(&e, t);
            CHECK(ip.scaleX >= prevIconScale - 1e-9 && ip.scaleX <= 1.0 + 1e-9,
                  "row %d icon scale bounced/overshot at %dms: %.5f (prev %.5f)", k, ms, ip.scaleX, prevIconScale);
            CHECK(ip.dy >= prevIconDy - 1e-9 && ip.dy <= 1e-9,
                  "row %d icon dy bounced/overshot at %dms: %.4f (prev %.4f)", k, ms, ip.dy, prevIconDy);
            CHECK(ip.alpha >= prevIconAlpha - 1e-9 && ip.alpha <= 1.0 + 1e-9,
                  "row %d icon alpha non-monotonic at %dms", k, ms);
            prevIconScale = ip.scaleX; prevIconDy = ip.dy; prevIconAlpha = ip.alpha;

            WXGMenuPose cp = WXGMenuCapsulePoseAt(&e, t, halfW);
            CHECK(fabs(cp.dy) < 1e-9, "row %d capsule must have ZERO vertical travel on open (dy=%.4f)", k, cp.dy);
            CHECK(cp.scaleX >= prevCapScale - 1e-9 && cp.scaleX <= 1.0 + 1e-9,
                  "row %d capsule scale bounced/overshot at %dms: %.5f", k, ms, cp.scaleX);
            CHECK(cp.dx <= prevCapDx + 1e-9 && cp.dx >= -1e-9,
                  "row %d capsule dx bounced/overshot at %dms: %.4f", k, ms, cp.dx);
            CHECK(cp.alpha >= prevCapAlpha - 1e-9 && cp.alpha <= 1.0 + 1e-9,
                  "row %d capsule alpha non-monotonic at %dms", k, ms);
            prevCapScale = cp.scaleX; prevCapDx = cp.dx; prevCapAlpha = cp.alpha;
        }
        // Final settled poses.
        WXGMenuPose iEnd = WXGMenuIconPoseAt(&e, 0.600);
        WXGMenuPose cEnd = WXGMenuCapsulePoseAt(&e, 0.600, halfW);
        CHECK(fabs(iEnd.scaleX - 1.0) < 1e-6 && fabs(iEnd.dy) < 1e-6 && fabs(iEnd.alpha - 1.0) < 1e-6, "row %d icon not settled at 600ms", k);
        CHECK(fabs(cEnd.scaleX - 1.0) < 1e-6 && fabs(cEnd.dx) < 1e-6 && fabs(cEnd.alpha - 1.0) < 1e-6, "row %d capsule not settled at 600ms", k);

        // Collapse: synchronous 100ms capsule vanish at t=0; icons accelerate straight to + center (-slotDistance).
        WXGMenuExit x = WXGMenuExitFor(4 - k, slotDist, stagger, speed);
        CHECK(fabs(x.capsuleDelay) < 1e-9 && fabs(x.capsuleDuration - 0.100) < 1e-6,
              "row %d capsule must exit synchronously at t=0 in 100ms", k);
        WXGMenuPose cxEnd = WXGMenuExitCapsulePoseAt(&x, 0.100, halfW);
        CHECK(fabs(cxEnd.alpha) < 1e-6 && fabs(cxEnd.dy) < 1e-9, "row %d capsule not vanished at 100ms", k);

        WXGMenuPose ixMid = WXGMenuExitIconPoseAt(&x, 0.120);
        CHECK(ixMid.dy < 0.0 && ixMid.dy > -slotDist, "row %d icon not moving up mid-collapse", k);
        WXGMenuPose ixEnd = WXGMenuExitIconPoseAt(&x, x.iconDelay + x.iconDuration);
        CHECK(fabs(ixEnd.dy + slotDist) < 1e-5, "row %d icon did not reach + center (-%.1f vs %.2f)", k, slotDist, ixEnd.dy);
        CHECK(fabs(ixEnd.scaleX - 0.35) < 1e-6 && fabs(ixEnd.alpha) < 1e-6, "row %d icon collapse end pose wrong", k);
    }

    double totalOpen = WXGMenuTotalDuration(5, pitch, stagger, 1.0);
    double totalClose = WXGMenuExitDuration(5, pitch, stagger, 1.0);
    CHECK(totalOpen >= 0.550 && totalOpen <= 0.610, "totalOpen %.3fs out of ~0.60s spec", totalOpen);
    CHECK(fabs(totalClose - 0.350) < 1e-6, "totalClose %.3fs must be 0.350s", totalClose);
    CHECK(fabs(WXGMenuExitDuration(5, pitch, stagger, 2.0) - 0.175) < 1e-6, "2x speed close duration must be 0.175s");
}

int main(void) {
    testLayoutMetrics();
    testTrack1RingAndDots();
    testTrack2SymbolSwapZeroBounce();
    testTrack3InkParticles();
    testTrack4And5ZeroBounceAndTiming();
    if (failCount) {
        fprintf(stderr, "MenuCascadeTests: %d failure(s)\n", failCount);
        return 1;
    }
    printf("MenuCascadeTests: ALL PASSED\n");
    return 0;
}
