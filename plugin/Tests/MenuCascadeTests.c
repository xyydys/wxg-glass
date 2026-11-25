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
    double h = WXGMenuHandoffProgress();
    double openDur = WXGMenuOpenDuration(1.0);
    double closeDur = WXGMenuCloseDuration(1.0);
    CHECK(openDur >= 0.55 && closeDur >= 0.50, "menu durations too fast: open=%.3f close=%.3f", openDur, closeDur);
    // Arc sweeps over 0..h*openDur (~273ms at 1x) on open, slower & smoother than 150ms.
    CHECK(h * openDur >= 0.24, "arc retract %.3fs should be >= 0.24s", h * openDur);
    CHECK(fabs(WXGMenuArcStrokeForProgress(0.0) - 1.0) < 1e-6, "arc(0) != 1");
    CHECK(fabs(WXGMenuArcStrokeForProgress(h) - 0.0) < 1e-6, "arc(h) != 0");
    CHECK(fabs(WXGMenuArcStrokeForProgress(1.0) - 0.0) < 1e-6, "arc(1) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(1, 0.0, 1.0) - 1.0) < 1e-6, "open arc(0) != 1");
    CHECK(fabs(WXGMenuRingStrokeAt(1, h * openDur, 1.0) - 0.0) < 1e-6, "open arc(h) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(0, (1.0 - h) * closeDur, 1.0) - 0.0) < 1e-6, "close arc(1-h) != 0");
    CHECK(fabs(WXGMenuRingStrokeAt(0, closeDur, 1.0) - 1.0) < 1e-6, "close arc(end) != 1");

    // Symbol: shrinks to 0.05 & fades to 0 right at handoff `h`, swaps to x, grows smoothly to 1.0 with ZERO overshoot.
    WXGMenuSymbolPose s0 = WXGMenuSymbolForProgress(0.0);
    WXGMenuSymbolPose sMid = WXGMenuSymbolForProgress(h);
    WXGMenuSymbolPose sEnd = WXGMenuSymbolForProgress(1.0);
    CHECK(!s0.isClose && fabs(s0.scale - 1.0) < 1e-6 && fabs(s0.alpha - 1.0) < 1e-6, "sym(0) wrong");
    CHECK(sMid.isClose && fabs(sMid.rotationRad - kPi4) < 1e-6 && fabs(sMid.scale - 0.05) < 1e-6 && fabs(sMid.alpha) < 1e-6, "sym swap at h wrong");
    CHECK(sEnd.isClose && fabs(sEnd.scale - 1.0) < 1e-6 && fabs(sEnd.alpha - 1.0) < 1e-6, "sym(1) wrong");
    for (int step = 0; step <= 200; step++) {
        WXGMenuSymbolPose p = WXGMenuSymbolForProgress(step / 200.0);
        CHECK(p.scale <= 1.0 + 1e-9 && p.scale >= 0.05 - 1e-6, "sym overshoot at step %d: %.4f", step, p.scale);
    }

    // Exact reverse symmetry: close(t) == open(1 - t/closeDur).
    WXGMenuSymbolPose cEnd = WXGMenuSymbolPoseAt(0, closeDur, 1.0);
    CHECK(!cEnd.isClose && fabs(cEnd.scale - 1.0) < 1e-6 && fabs(cEnd.alpha - 1.0) < 1e-6, "close sym end wrong");
}

static void testDotBlurMorphAndReverse(void) {
    const double plusX = 350.0, plusY = 80.0, size = 44.0, r = WXGMenuRingRadius(size);
    const double dd = WXGMenuRingDotDiameterFor(size);
    const double h = WXGMenuHandoffProgress();
    int n = 4;
    for (int i = 0; i < n; i++) {
        double ty = plusY + 56.0 * (i + 1);
        double a = WXGMenuRingDotAngleForCount(i, n, size);
        double ax = plusX + r * cos(a), ay = plusY + r * sin(a);

        // Detach finishes strictly before handoff `h` (right as arc finishes).
        double pDet = WXGMenuDotDetachProgress(i, n);
        double pArr = WXGMenuDotArriveProgress(i, n, 0.045);
        CHECK(pDet < h, "dot %d detached after handoff (%.3f >= %.3f)", i, pDet, h);

        // p=0: at exact bottom-ring anchor with 0 blur.
        WXGMenuParticle p0 = WXGMenuDotForProgress(i, n, 0.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(fabs(p0.x - ax) < 1e-6 && fabs(p0.y - ay) < 1e-6 && fabs(p0.diameter - dd) < 1e-6 && fabs(p0.blurRadius) < 1e-6,
              "dot %d start wrong", i);

        // At arrival: reaches exact icon center and enters Gaussian blur morph!
        WXGMenuParticle pAtArr = WXGMenuDotForProgress(i, n, pArr, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(fabs(pAtArr.x - plusX) < 1e-5 && fabs(pAtArr.y - ty) < 1e-5 && pAtArr.blurRadius >= 3.0,
              "dot %d arrival morph wrong (pos=%.1f,%.1f blur=%.2f)", i, pAtArr.x, pAtArr.y, pAtArr.blurRadius);

        // At p=1: cleanly dissolved into icon.
        WXGMenuParticle pEnd = WXGMenuDotForProgress(i, n, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(pEnd.alpha <= 1e-6 && pEnd.diameter <= 1e-6, "dot %d did not finish dissolve", i);

        // Reverse collapse: t=0 starts hidden; t=closeDur docks precisely at anchor with 0 blur!
        double closeDur = WXGMenuCloseDuration(1.0);
        WXGMenuParticle c0 = WXGMenuDotMorphPoseAt(i, n, 0, 0.0, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(c0.alpha <= 1e-6, "close dot %d should start hidden", i);
        WXGMenuParticle cDock = WXGMenuDotMorphPoseAt(i, n, 0, closeDur, 1.0, 0.045, plusX, plusY, size, plusX, ty);
        CHECK(fabs(cDock.x - ax) < 1e-6 && fabs(cDock.y - ay) < 1e-6 && fabs(cDock.diameter - dd) < 1e-6 && fabs(cDock.alpha - 1.0) < 1e-6 && fabs(cDock.blurRadius) < 1e-6,
              "close dot %d dock mismatch", i);
    }
}

static void testZeroBounceIconsAndCapsules(void) {
    const double pitch = 56.0, halfW = 55.0, stagger = 0.045;
    for (int k = 0; k < 4; k++) {
        // Test unified progress row poses (monotonic 0 -> 1, ZERO bounce!).
        double prevS = 0.0, prevA = 0.0, prevBlur = 10.0;
        double prevCs = 0.0, prevCdx = 1e6, prevCa = 0.0;
        for (int step = 0; step <= 200; step++) {
            double p = step / 200.0;
            WXGMenuRowPose ip = WXGMenuRowIconForProgress(k, 4, p, stagger);
            CHECK(ip.scaleX >= prevS - 1e-9 && ip.scaleX <= 1.0 + 1e-9, "row %d icon scale bounced at p=%.3f", k, p);
            CHECK(ip.alpha >= prevA - 1e-9 && ip.alpha <= 1.0 + 1e-9, "row %d icon alpha non-monotonic", k);
            CHECK(ip.blurRadius <= prevBlur + 1e-9 && ip.blurRadius >= -1e-9, "row %d icon blur non-monotonic", k);
            prevS = ip.scaleX; prevA = ip.alpha; prevBlur = ip.blurRadius;

            WXGMenuRowPose cp = WXGMenuRowCapsuleForProgress(k, 4, p, stagger, halfW);
            CHECK(fabs(cp.dy) < 1e-9, "row %d capsule must have zero vertical travel", k);
            CHECK(cp.scaleX >= prevCs - 1e-9 && cp.scaleX <= 1.0 + 1e-9, "row %d capsule bounced", k);
            CHECK(cp.dx <= prevCdx + 1e-9 && cp.dx >= -1e-9, "row %d capsule dx bounced", k);
            CHECK(cp.alpha >= prevCa - 1e-9 && cp.alpha <= 1.0 + 1e-9, "row %d capsule alpha non-monotonic", k);
            prevCs = cp.scaleX; prevCdx = cp.dx; prevCa = cp.alpha;
        }
        // Verify settled p=1 is crisp identity with 0 blur.
        WXGMenuRowPose ipEnd = WXGMenuRowIconForProgress(k, 4, 1.0, stagger);
        WXGMenuRowPose cpEnd = WXGMenuRowCapsuleForProgress(k, 4, 1.0, stagger, halfW);
        CHECK(fabs(ipEnd.alpha - 1.0) < 1e-6 && fabs(ipEnd.scaleX - 1.0) < 1e-6 && ipEnd.blurRadius < 1e-6, "row %d icon not settled at p=1", k);
        CHECK(fabs(cpEnd.alpha - 1.0) < 1e-6 && fabs(cpEnd.scaleX - 1.0) < 1e-6 && fabs(cpEnd.dx) < 1e-6, "row %d capsule not settled at p=1", k);

        // Also check legacy wrapper compatibility for dump.c.
        WXGMenuEntrance e = WXGMenuEntranceForCount(k, 4, (k + 1) * pitch, stagger, 1.0);
        WXGMenuPose legacyEnd = WXGMenuIconPoseAt(&e, WXGMenuOpenDuration(1.0));
        CHECK(fabs(legacyEnd.alpha - 1.0) < 1e-6 && fabs(legacyEnd.scaleX - 1.0) < 1e-6, "legacy icon end wrong");
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
