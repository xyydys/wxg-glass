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

static const double kPi = 3.14159265358979323846;
static const double kPi4 = 0.78539816339744830962;

static void testProportionsAndEqualDotGaps(void) {
    double size = 44.0;
    double r = WXGMenuRingRadius(size);
    double lw = WXGMenuRingLineWidth(size);
    double dd = WXGMenuRingDotDiameterFor(size);
    double arm = WXGMenuSymbolArmLength(size);
    CHECK(r >= 14.0 && r <= 16.0, "ring radius %.2f should match screenshot (~15pt at 44pt)", r);
    CHECK(arm >= 4.5 && arm <= 5.5, "symbol arm %.2f should match screenshot (~5pt at 44pt)", arm);

    // Clear edge-to-edge gap between arc round cap and outer dots MUST equal clear gap between adjacent dots for 4, 5, and 6 dots!
    double capHalf = (lw * 0.5) / r;
    double dotHalf = (dd * 0.5) / r;
    int counts[3] = { 4, 5, 6 };
    for (int ci = 0; ci < 3; ci++) {
        int n = counts[ci];
        double a0 = WXGMenuRingDotAngleForCount(0, n, size);
        double aLast = WXGMenuRingDotAngleForCount(n - 1, n, size);
        double gapArcLeft = (a0 - dotHalf) - (kPi * 0.25 + capHalf);
        double gapArcRight = (kPi * 0.75 - capHalf) - (aLast + dotHalf);
        CHECK(gapArcLeft > 0.04, "count %d arc-to-dot0 gap too small: %.4f rad", n, gapArcLeft);
        CHECK(fabs(gapArcLeft - gapArcRight) < 1e-9, "count %d arc gaps asymmetric", n);
        for (int i = 0; i < n - 1; i++) {
            double ai = WXGMenuRingDotAngleForCount(i, n, size);
            double aj = WXGMenuRingDotAngleForCount(i + 1, n, size);
            double gapDot = (aj - dotHalf) - (ai + dotHalf);
            CHECK(fabs(gapDot - gapArcLeft) < 1e-9,
                  "count %d dot gap %d (%.5f) != arc-to-dot gap (%.5f)", n, i, gapDot, gapArcLeft);
        }
    }
    CHECK(fabs(WXGMenuRingDotAngleForCount(2, 5, size) - kPi * 0.5) < 1e-9, "5-dot center dot not at 6:00");
    CHECK(fabs(WXGMenuRingDotAngleForCount(0, 4, size) + WXGMenuRingDotAngleForCount(3, 4, size) - kPi) < 1e-9, "4-dot outer pair asymmetric");
    CHECK(fabs(WXGMenuRingDotAngleForCount(1, 4, size) + WXGMenuRingDotAngleForCount(2, 4, size) - kPi) < 1e-9, "4-dot inner pair asymmetric");
}

static void testArcAndSymbolSwap(void) {
    // Arc: 1 -> 0 over 0..150ms on open; 0 -> 1 over 150..360ms on close.
    CHECK(fabs(WXGMenuRingStrokeAt(1, 0.0, 1.0) - 1.0) < 1e-6, "open arc(0) != 1");
    CHECK(fabs(WXGMenuRingStrokeAt(1, 0.150, 1.0) - 0.0) < 1e-6, "open arc(150ms) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(0, 0.150, 1.0) - 0.0) < 1e-6, "close arc(150ms) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(0, 0.360, 1.0) - 1.0) < 1e-6, "close arc(360ms) != 1");

    // Symbol: shrinks to 0.05 & fades to 0 right at 150ms (when arc finishes & dots detach), swaps to x, grows smoothly to 1.0 with ZERO overshoot.
    WXGMenuSymbolPose s0 = WXGMenuSymbolPoseAt(1, 0.0, 1.0);
    WXGMenuSymbolPose sMid = WXGMenuSymbolPoseAt(1, 0.150, 1.0);
    WXGMenuSymbolPose sEnd = WXGMenuSymbolPoseAt(1, 0.360, 1.0);
    CHECK(!s0.isClose && fabs(s0.scale - 1.0) < 1e-6 && fabs(s0.alpha - 1.0) < 1e-6, "open sym(0) wrong");
    CHECK(sMid.isClose && fabs(sMid.rotationRad - kPi4) < 1e-6 && fabs(sMid.scale - 0.05) < 1e-6 && fabs(sMid.alpha) < 1e-6, "open sym swap at 150ms wrong");
    CHECK(sEnd.isClose && fabs(sEnd.scale - 1.0) < 1e-6 && fabs(sEnd.alpha - 1.0) < 1e-6, "open sym(360ms) wrong");
    for (int ms = 0; ms <= 400; ms++) {
        WXGMenuSymbolPose p = WXGMenuSymbolPoseAt(1, ms * 0.001, 1.0);
        CHECK(p.scale <= 1.0 + 1e-9 && p.scale >= 0.05 - 1e-6, "open sym overshoot at %dms: %.4f", ms, p.scale);
    }

    // Reverse collapse symbol swap at 170ms -> settled '+' at 360ms.
    WXGMenuSymbolPose cMid = WXGMenuSymbolPoseAt(0, 0.170, 1.0);
    WXGMenuSymbolPose cEnd = WXGMenuSymbolPoseAt(0, 0.360, 1.0);
    CHECK(!cMid.isClose && fabs(cMid.rotationRad) < 1e-6 && fabs(cMid.scale - 0.05) < 1e-6, "close sym swap wrong");
    CHECK(!cEnd.isClose && fabs(cEnd.scale - 1.0) < 1e-6 && fabs(cEnd.alpha - 1.0) < 1e-6, "close sym end wrong");
}

static void testDotBlurMorphAndReverse(void) {
    const double plusX = 350.0, plusY = 80.0, size = 44.0, r = WXGMenuRingRadius(size);
    const double dd = WXGMenuRingDotDiameterFor(size);
    int n = 4;
    for (int i = 0; i < n; i++) {
        double ty = plusY + 56.0 * (i + 1);
        double a = WXGMenuRingDotAngleForCount(i, n, size);
        double ax = plusX + r * cos(a), ay = plusY + r * sin(a);

        // Detach finishes by 150ms (right when arc finishes).
        double tDet = WXGMenuDotDetachAt(i, n, 0.045);
        double tArr = WXGMenuDotArriveAt(i, n, 0.045);
        CHECK(tDet <= 0.150 + 1e-6, "dot %d detached after arc finished (%.3f)", i, tDet);

        // Open t=0: at exact bottom-ring anchor with 0 blur.
        WXGMenuParticle p0 = WXGMenuDotMorphPoseAt(i, n, 1, 0.0, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(fabs(p0.x - ax) < 1e-6 && fabs(p0.y - ay) < 1e-6 && fabs(p0.diameter - dd) < 1e-6 && fabs(p0.blurRadius) < 1e-6,
              "open dot %d start wrong", i);

        // Open at arrival: reaches exact icon center and enters Gaussian blur morph!
        WXGMenuParticle pArr = WXGMenuDotMorphPoseAt(i, n, 1, tArr, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(fabs(pArr.x - plusX) < 1e-5 && fabs(pArr.y - ty) < 1e-5 && pArr.blurRadius >= 3.0,
              "open dot %d arrival morph wrong (pos=%.1f,%.1f blur=%.2f)", i, pArr.x, pArr.y, pArr.blurRadius);

        // Open after morph: cleanly dissolved into icon.
        WXGMenuParticle pEnd = WXGMenuDotMorphPoseAt(i, n, 1, tArr + 0.100, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(pEnd.alpha <= 1e-6 && pEnd.diameter <= 1e-6, "open dot %d did not finish dissolve", i);

        // Collapse: starts hidden at icon center, blurs/condenses back into dot, docks precisely at anchor at 360ms with 0 blur!
        WXGMenuParticle c0 = WXGMenuDotMorphPoseAt(i, n, 0, 0.0, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(c0.alpha <= 1e-6, "close dot %d should start hidden", i);
        WXGMenuParticle cDock = WXGMenuDotMorphPoseAt(i, n, 0, 0.360, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(fabs(cDock.x - ax) < 1e-6 && fabs(cDock.y - ay) < 1e-6 && fabs(cDock.diameter - dd) < 1e-6 && fabs(cDock.alpha - 1.0) < 1e-6 && fabs(cDock.blurRadius) < 1e-6,
              "close dot %d dock mismatch", i);
    }
}

static void testZeroBounceIconsAndCapsules(void) {
    const double pitch = 56.0, halfW = 55.0, stagger = 0.045;
    for (int k = 0; k < 4; k++) {
        WXGMenuEntrance e = WXGMenuEntranceForCount(k, 4, (k + 1) * pitch, stagger, 1.0);
        double prevS = 0.0, prevDy = -100.0, prevA = 0.0;
        double prevCs = 0.0, prevCdx = 1e6, prevCa = 0.0;
        for (int ms = 0; ms <= 600; ms++) {
            double t = ms * 0.001;
            WXGMenuPose ip = WXGMenuIconPoseAt(&e, t);
            CHECK(ip.scaleX >= prevS - 1e-9 && ip.scaleX <= 1.0 + 1e-9, "row %d icon scale bounced at %dms", k, ms);
            CHECK(ip.dy >= prevDy - 1e-9 && ip.dy <= 1e-9, "row %d icon dy bounced at %dms", k, ms);
            CHECK(ip.alpha >= prevA - 1e-9 && ip.alpha <= 1.0 + 1e-9, "row %d icon alpha non-monotonic", k);
            prevS = ip.scaleX; prevDy = ip.dy; prevA = ip.alpha;

            WXGMenuPose cp = WXGMenuCapsulePoseAt(&e, t, halfW);
            CHECK(fabs(cp.dy) < 1e-9, "row %d capsule must have zero vertical travel", k);
            CHECK(cp.scaleX >= prevCs - 1e-9 && cp.scaleX <= 1.0 + 1e-9, "row %d capsule bounced", k);
            CHECK(cp.dx <= prevCdx + 1e-9 && cp.dx >= -1e-9, "row %d capsule dx bounced", k);
            CHECK(cp.alpha >= prevCa - 1e-9 && cp.alpha <= 1.0 + 1e-9, "row %d capsule alpha non-monotonic", k);
            prevCs = cp.scaleX; prevCdx = cp.dx; prevCa = cp.alpha;
        }
        WXGMenuExit x = WXGMenuExitFor(3 - k, (k + 1) * pitch, stagger, 1.0);
        CHECK(fabs(x.capsuleDelay) < 1e-9 && fabs(x.capsuleDuration - 0.100) < 1e-6, "capsule exit not synchronous 100ms");
    }
}

int main(void) {
    testProportionsAndEqualDotGaps();
    testArcAndSymbolSwap();
    testDotBlurMorphAndReverse();
    testZeroBounceIconsAndCapsules();
    if (failCount) {
        fprintf(stderr, "MenuCascadeTests: %d failure(s)\n", failCount);
        return 1;
    }
    printf("MenuCascadeTests: ALL PASSED\n");
    return 0;
}
