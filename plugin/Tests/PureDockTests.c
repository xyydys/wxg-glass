#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGMeshRefraction.h"
#include "../Sources/WXGLensFlex.h"
#include "../Sources/WXGDockSystem.h"

static WXGMeshOptics pureLensOptics(float w, float h, float barH, float innerH,
                                    float bandFrac, float depthFrac, float disp, float channel, float pad, int atEnd) {
    WXGMeshOptics o = {0};
    float shortSide = w < h ? w : h;
    float band = bandFrac * shortSide, depth = depthFrac * shortSide;
    o.width = w + 2.f * pad;
    o.height = h + 2.f * pad;
    o.fieldScale = 1.f;
    o.edgeWidth = band > .5f ? band : .5f;
    o.offsetScale = 1.f;
    o.zoomBefore = 1.f;
    o.zoomAfter = 1.f;
    o.dispersion = disp;
    o.channel = channel;
    o.padX = pad;
    o.padY = pad;
    o.sbLeft = atEnd ? (pad - 200.f) : (-10000.f + pad);
    o.sbRight = atEnd ? (pad + w - 8.4f) : (10000.f + pad);
    o.sbTop = pad + (h - barH) * .5f;
    o.sbBottom = pad + (h + barH) * .5f;
    o.shrinkPress = 1.f;
    o.shrinkPinch = (barH - innerH) / barH;
    o.curveHeight = (band > .01f && depth > .01f) ? band : 0.f;
    o.curveAmount = depth;
    o.curveSqueeze = 3.f;
    o.shrinkFlat = 1.f;
    return o;
}

static void testFlatInnerBarZeroRefraction(void) {
    float w = 123.5f, h = 70.f, barH = 62.f, innerH = 52.f, pad = 16.f;
    float cy = pad + h * .5f;
    WXGMeshOptics flat = pureLensOptics(w, h, barH, innerH, 0.f, 0.f, 0.f, 0.f, pad, 0);
    // Find the exact y where sy lands on the real bar's top edge (cy - barH/2)
    // across the whole lens width: must be strictly flat (zero 45-deg connector).
    float maxErr = 0.f;
    for (float x = pad + 4.f; x <= pad + w - 4.f; x += 2.f) {
        float sx = 0.f, sy = 0.f;
        WXGMeshSource(flat, x, cy - innerH * .5f, &sx, &sy);
        float err = fabsf(sy - (cy - barH * .5f));
        if (err > maxErr) maxErr = err;
        // Outside the shrunk bar, source must sample the real page outside the bar.
        WXGMeshSource(flat, x, cy - innerH * .5f - 2.f, &sx, &sy);
        assert(sy < cy - barH * .5f - 1.5f);
        // Inside the shrunk bar, source must stay inside the real bar.
        WXGMeshSource(flat, x, cy - innerH * .5f + 2.f, &sx, &sy);
        assert(sy > cy - barH * .5f + 1.5f);
        // Center line untouched.
        WXGMeshSource(flat, x, cy, &sx, &sy);
        assert(fabsf(sy - cy) < 1e-4f);
    }
    assert(maxErr < 1e-3f);

    // Compare against legacy shrinkFlat=0: near the lens ends, legacy ramps inward (nonzero deviation).
    WXGMeshOptics legacy = flat;
    legacy.shrinkFlat = 0.f;
    float sx = 0.f, sy = 0.f;
    WXGMeshSource(legacy, pad + 6.f, cy - innerH * .5f, &sx, &sy);
    assert(fabsf(sy - (cy - barH * .5f)) > 1.f);

    // Deep flat shrink down to 26 pt inside 62 pt bar (pinch ~ 0.58 > legacy 0.30 cap).
    WXGMeshOptics deep = pureLensOptics(w, h, barH, 26.f, 0.f, 0.f, 0.f, 0.f, pad, 0);
    WXGMeshSource(deep, pad + w * .5f, cy - 13.f, &sx, &sy);
    assert(fabsf(sy - (cy - barH * .5f)) < 1e-3f);
    printf("PASS: pureDock shrinkFlat zero-refraction flat bar (maxErr=%.5f pt, deep 26pt exact).\n", maxErr);
}

static void testPureGlassRGBAndMeshBudget(void) {
    float w = 123.5f, h = 70.f, barH = 62.f, innerH = 52.f, pad = 16.f;
    WXGMeshOptics r = pureLensOptics(w, h, barH, innerH, .12f, .35f, 1.2f, 1.f, pad, 0);
    WXGMeshOptics g = pureLensOptics(w, h, barH, innerH, .12f, .35f, 1.2f, 0.f, pad, 0);
    WXGMeshOptics b = pureLensOptics(w, h, barH, innerH, .12f, .35f, 1.2f, -1.f, pad, 0);

    // Check vivid 3-channel corner RGB split and center-axis neutrality.
    float rx, ry, gx, gy, bx, by;
    float cornerX = pad + w - 11.f, cornerY = pad + 11.f;
    WXGMeshSource(r, cornerX, cornerY, &rx, &ry);
    WXGMeshSource(g, cornerX, cornerY, &gx, &gy);
    WXGMeshSource(b, cornerX, cornerY, &bx, &by);
    float cornerSplit = hypotf(rx - bx, ry - by);
    assert(cornerSplit > 2.f);

    // On horizontal middle line (y = cy), I = 0 so R/G/B coincide.
    WXGMeshSource(r, pad + w - 2.f, pad + h * .5f, &rx, &ry);
    WXGMeshSource(b, pad + w - 2.f, pad + h * .5f, &bx, &by);
    assert(hypotf(rx - bx, ry - by) < 1e-4f);

    // Verify mesh vertex budgets (both settled and motion tiers) and finite [0,1] bounds.
    static WXGMeshPoint pts[20000];
    static unsigned int quads[20000][4];
    WXGMeshQuality barQ = {.12f, .08f, 8.f};
    WXGMeshQuality moveQ = {.20f, .12f, 16.f};
    int faces = 0;
    int barVerts = WXGBuildContourMesh(r, barQ, pts, 20000, quads, 20000, &faces);
    assert(barVerts > 100 && barVerts < 2500 && faces > 50);
    for (int i = 0; i < barVerts; i++) {
        assert(isfinite(pts[i].fromX) && isfinite(pts[i].fromY));
        assert(pts[i].fromX >= 0.f && pts[i].fromX <= 1.f);
        assert(pts[i].fromY >= 0.f && pts[i].fromY <= 1.f);
    }
    int moveVerts = WXGBuildContourMesh(r, moveQ, pts, 20000, quads, 20000, &faces);
    assert(moveVerts > 80 && moveVerts < barVerts && moveVerts < 1500);

    // End-tab configuration with bar end cap inside lens.
    WXGMeshOptics endR = pureLensOptics(108.f, h, barH, innerH, .18f, .50f, 1.2f, 1.f, pad, 1);
    int endVerts = WXGBuildContourMesh(endR, barQ, pts, 20000, quads, 20000, &faces);
    assert(endVerts > 100 && endVerts < 2600);
    printf("PASS: pureDock 3-RGB split (corner=%.2f pt) and compact mesh (move=%d, settled=%d, end=%d verts).\n",
           cornerSplit, moveVerts, barVerts, endVerts);
}

typedef struct {
    double minSy;
    double freezeSec;
    double flatDurSec;
} FlexSimResult;

static FlexSimResult simulateSpringFlex(WXGLensFlexParams p, int adaptive, double hz) {
    WXGLensFlex f = {0};
    double dt = 1.0 / hz;
    double resp = 0.40, damp = 0.86;
    double dur = WXGDockSpringDuration(resp, damp);
    // 3-tab move to the left: deceleration overshoot lands in the wide-and-flat half (e > 0).
    double pitch = 94.17, dist = -3.0 * pitch;
    double minSy = 1.0, freezeSec = 0.0, flatDurSec = 0.0;
    double prevX = 0.0;
    for (int step = 0; step < (int)(1.8 * hz); step++) {
        double t = step * dt;
        double u = t / dur;
        double x = (u < 1.0 ? WXGDockSpringEase(u, resp, damp) : 1.0) * dist;
        double v = step > 0 ? (x - prevX) / dt : 0.0;
        prevX = x;
        if (adaptive) WXGLensFlexAdaptiveStep(&f, v, pitch, p, dt);
        else WXGLensFlexStep(&f, v, pitch, p, dt);
        double sx = 1.0, sy = 1.0;
        if (adaptive) WXGLensFlexAdaptiveScaleAt(f, p, 0.0, &sx, &sy);
        else WXGLensFlexScaleAt(f, p, 0.0, &sx, &sy);
        if (sy < minSy) minSy = sy;
        if (sy <= p.restFlattest + 0.002) freezeSec += dt;
        if (sy < 0.990) flatDurSec += dt;
    }
    FlexSimResult r = {minSy, freezeSec, flatDurSec};
    return r;
}

static void testAdaptiveFlexTiming(void) {
    WXGLensFlexParams p82 = WXGLensFlexDefaults();
    WXGLensFlexParams p90 = p82; p90.restFlattest = 0.90;
    WXGLensFlexParams p94 = p82; p94.restFlattest = 0.94;
    WXGLensFlexParams p98 = p82; p98.restFlattest = 0.98;

    // Default 0.82 speedup is exactly 1.00.
    assert(fabs(WXGLensFlexAdaptiveSpeedup(p82) - 1.0) < 1e-6);
    // Shallower restFlattest monotonically increases speedup.
    double s90 = WXGLensFlexAdaptiveSpeedup(p90);
    double s94 = WXGLensFlexAdaptiveSpeedup(p94);
    double s98 = WXGLensFlexAdaptiveSpeedup(p98);
    assert(s90 > 1.15 && s94 > s90 && s98 > s94 && s98 <= 2.201);

    FlexSimResult leg90 = simulateSpringFlex(p90, 0, 120.0);
    FlexSimResult ad82 = simulateSpringFlex(p82, 1, 120.0);
    FlexSimResult ad90 = simulateSpringFlex(p90, 1, 120.0);
    FlexSimResult ad94 = simulateSpringFlex(p94, 1, 120.0);

    // Legacy 0.90 suffered a long flat-clamp freeze (>80ms); adaptive removes the freeze (<20ms)
    // and proportionally shortens settling time as travel shortens (0.82 -> 0.90 -> 0.94).
    assert(leg90.freezeSec > 0.08);
    assert(ad90.freezeSec < 0.02);
    assert(ad90.minSy >= p90.restFlattest - 1e-6);
    assert(ad94.minSy >= p94.restFlattest - 1e-6);
    assert(ad90.flatDurSec < ad82.flatDurSec - 0.04);
    assert(ad94.flatDurSec < ad90.flatDurSec - 0.02);

    // Frame-rate independence across 60 / 120 / 240 Hz.
    FlexSimResult ad90_60 = simulateSpringFlex(p90, 1, 60.0);
    FlexSimResult ad90_240 = simulateSpringFlex(p90, 1, 240.0);
    assert(fabs(ad90_60.minSy - ad90.minSy) < 0.004);
    assert(fabs(ad90_240.minSy - ad90.minSy) < 0.004);

    printf("PASS: adaptive flex (speedup 0.90=%.2fx, 0.94=%.2fx; freeze %.0fms->%.0fms; flatDur 0.82=%.0fms 0.90=%.0fms 0.94=%.0fms).\n",
           s90, s94, leg90.freezeSec * 1000.0, ad90.freezeSec * 1000.0,
           ad82.flatDurSec * 1000.0, ad90.flatDurSec * 1000.0, ad94.flatDurSec * 1000.0);
}

static void testR8PureDockModelAndMotionTier(void) {
    float w = 123.5f, h = 70.f, barH = 62.f, innerH = 51.f, pad = 20.f;
    WXGMeshOptics r8 = {0};
    r8.width = w + 2.f * pad;
    r8.height = h + 2.f * pad;
    r8.fieldScale = 1.f;
    r8.edgeWidth = 18.f;
    r8.offsetScale = 1.f;
    r8.zoomBefore = 1.f;
    r8.zoomAfter = 1.f;
    r8.dispersion = 2.4f;
    r8.padX = pad;
    r8.padY = pad;
    r8.sbLeft = -10000.f + pad;
    r8.sbRight = 10000.f + pad;
    r8.sbTop = pad + (h - barH) * .5f;
    r8.sbBottom = pad + (h + barH) * .5f;
    r8.shrinkPress = 1.f;
    r8.shrinkPinch = (barH - innerH) / barH;
    r8.kyantMode = 1.f;
    r8.kyantHeight = 18.f;
    r8.kyantAmount = 26.f;
    r8.shrinkFlat = 0.f;

    /* 1. R8 7-tap shoulder dispersion is strong and center stays neutral. */
    WXGMeshOptics tapRed = r8, tapViolet = r8;
    tapRed.kyantChannel = WXGKyantSpectralOffset(0);
    tapViolet.kyantChannel = WXGKyantSpectralOffset(WXG_KYANT_SPECTRAL_TAPS - 1);
    float rx = 0.f, ry = 0.f, vx = 0.f, vy = 0.f;
    WXGMeshSource(tapRed, pad + w - 10.f, pad + 10.f, &rx, &ry);
    WXGMeshSource(tapViolet, pad + w - 10.f, pad + 10.f, &vx, &vy);
    float shoulderSpread = hypotf(rx - vx, ry - vy);
    assert(shoulderSpread > 3.f);
    WXGMeshSource(tapRed, pad + w * .5f, pad + h * .5f, &rx, &ry);
    WXGMeshSource(tapViolet, pad + w * .5f, pad + h * .5f, &vx, &vy);
    assert(hypotf(rx - vx, ry - vy) < 1e-4f);

    /* 2. shrinkFlat=1 under kyantMode gives strictly flat inner bar when refraction=0. */
    WXGMeshOptics flatZero = r8;
    flatZero.kyantHeight = 0.f;
    flatZero.kyantAmount = 0.f;
    flatZero.dispersion = 0.f;
    flatZero.shrinkFlat = 1.f;
    float cy = pad + h * .5f;
    for (float x = pad + 4.f; x <= pad + w - 4.f; x += 4.f) {
        float sx = 0.f, sy = 0.f;
        WXGMeshSource(flatZero, x, cy - innerH * .5f, &sx, &sy);
        assert(fabsf(sy - (cy - barH * .5f)) < 1e-3f);
    }

    /* 3. Two-tier motion vs settled mesh quality under R8 kyantMode. */
    static WXGMeshPoint pts[20000];
    static unsigned int quads[20000][4];
    WXGMeshQuality settledQ = {.12f, .08f, 8.f};
    WXGMeshQuality moveQ = {.20f, .12f, 16.f};
    int faces = 0;
    int settledVerts = WXGBuildContourMesh(tapRed, settledQ, pts, 20000, quads, 20000, &faces);
    assert(settledVerts > 200 && settledVerts < 12000 && faces > 100);
    for (int i = 0; i < settledVerts; i++) {
        assert(isfinite(pts[i].fromX) && isfinite(pts[i].fromY));
        assert(pts[i].fromX >= 0.f && pts[i].fromX <= 1.f);
        assert(pts[i].fromY >= 0.f && pts[i].fromY <= 1.f);
    }
    int moveVerts = WXGBuildContourMesh(tapRed, moveQ, pts, 20000, quads, 20000, &faces);
    assert(moveVerts > 100 && moveVerts < settledVerts * 0.70f);
    WXGMeshOptics flatRed = tapRed;
    flatRed.shrinkFlat = 1.f;
    int flatVerts = WXGBuildContourMesh(flatRed, settledQ, pts, 20000, quads, 20000, &faces);
    assert(flatVerts > 200 && flatVerts < 12000);
    printf("PASS: R12 pureDock R8 7-tap (shoulder=%.2f pt, move=%d < settled=%d verts, flat=%d verts).\n",
           shoulderSpread, moveVerts, settledVerts, flatVerts);
}

static void testR13AuroraSymmetryAndEndRoundness(void) {
    /* 1. 4-quadrant symmetry & zero Top-Right / Bottom-Left pinch across x = 4..44 pt. */
    wxg_kf2_t hs = WXG_K_MAKE2(62.f, 35.f);
    wxg_kf2_t a1 = WXGKyantSpectralRay(WXG_K_MAKE2(hs.x, 1.5f), hs, hs, 35.f, 18.f, 26.f, 2.4f, 0.f, 0.f, 0.f, 1.f, NULL);
    wxg_kf2_t a2 = WXGKyantSpectralRay(WXG_K_MAKE2(hs.x, 1.5f), hs, hs, 35.f, 18.f, 26.f, 2.4f, 0.f, 0.f, 0.f, -1.f, NULL);
    float apexSpread = hypotf(a1.x - a2.x, a1.y - a2.y);
    assert(apexSpread > 2.f);
    for (int ix = 4; ix <= 44; ix += 4) {
        float x = (float)ix;
        float cx = fmaxf(0.f, x - (hs.x - 35.f));
        float yEdge = 35.f - sqrtf(fmaxf(0.f, 35.f * 35.f - cx * cx));
        float sp[4] = {0};
        float sx[4] = {-1.f, 1.f, -1.f, 1.f};
        float sy[4] = {-1.f, -1.f, 1.f, 1.f};
        for (int q = 0; q < 4; q++) {
            wxg_kf2_t p = WXG_K_MAKE2(hs.x + sx[q] * x, hs.y + sy[q] * (35.f - yEdge - 1.5f));
            wxg_kf2_t r1 = WXGKyantSpectralRay(p, hs, hs, 35.f, 18.f, 26.f, 2.4f, 0.f, 0.f, 0.f, 1.f, NULL);
            wxg_kf2_t r2 = WXGKyantSpectralRay(p, hs, hs, 35.f, 18.f, 26.f, 2.4f, 0.f, 0.f, 0.f, -1.f, NULL);
            sp[q] = hypotf(r1.x - r2.x, r1.y - r2.y);
            assert(sp[q] >= apexSpread * 0.95f);
        }
        assert(fabsf(sp[0] - sp[1]) < 1e-4f && fabsf(sp[0] - sp[2]) < 1e-4f && fabsf(sp[0] - sp[3]) < 1e-4f);
    }

    /* 2. Both 7-tap backdrop and 15-tap glyph aurora weights sum strictly to (1, 1, 1). */
    float sr7 = 0.f, sg7 = 0.f, sb7 = 0.f;
    for (int k = 0; k < WXG_KYANT_SPECTRAL_TAPS; k++) {
        wxg_kf3_t w = WXGKyantSpectralRGBWeight(k);
        sr7 += w.x; sg7 += w.y; sb7 += w.z;
    }
    assert(fabsf(sr7 - 1.f) < 1e-4f && fabsf(sg7 - 1.f) < 1e-4f && fabsf(sb7 - 1.f) < 1e-4f);
    float sr15 = 0.f, sg15 = 0.f, sb15 = 0.f;
    for (int k = 0; k < WXG_KYANT_GLYPH_TAPS; k++) {
        wxg_kf3_t w = WXGKyantGlyphSpectralRGBWeight(k);
        sr15 += w.x; sg15 += w.y; sb15 += w.z;
    }
    assert(fabsf(sr15 - 1.f) < 1e-4f && fabsf(sg15 - 1.f) < 1e-4f && fabsf(sb15 - 1.f) < 1e-4f);

    /* 3. Concentric end-cap alignment at dock right end (endWrap = 8.4 pt vs 4.0 pt vertical overhang). */
    float pad = 20.f, w = 115.f, h = 70.f, barH = 62.f, innerH = 51.f;
    WXGMeshOptics endO = {0};
    endO.width = w + 2.f * pad; endO.height = h + 2.f * pad;
    endO.fieldScale = 1.f; endO.edgeWidth = 18.f; endO.zoomBefore = 1.f; endO.zoomAfter = 1.f;
    endO.padX = pad; endO.padY = pad;
    endO.sbLeft = pad - 280.f; endO.sbRight = pad + w - 8.4f;
    endO.sbTop = pad + (h - barH) * .5f; endO.sbBottom = pad + (h + barH) * .5f;
    endO.shrinkPress = 1.f; endO.shrinkPinch = (barH - innerH) / barH;
    endO.kyantMode = 1.f; endO.kyantHeight = 0.f; endO.kyantAmount = 0.f;
    /* Find where the shrunk inner bar's right tip lands along y = cy. */
    float cy = pad + h * .5f;
    float lo = pad + w * .5f, hi = pad + w;
    for (int it = 0; it < 40; it++) {
        float mid = .5f * (lo + hi), sx = 0.f, sy = 0.f;
        WXGMeshSource(endO, mid, cy, &sx, &sy);
        if (sx < endO.sbRight) lo = mid; else hi = mid;
    }
    float rightGap = (pad + w) - .5f * (lo + hi);
    float topGap = (h - innerH) * .5f; /* 9.5 pt */
    assert(fabsf(rightGap - topGap) < 1.2f);

    /* 4. R15: even at extreme max sliders (band=40pt, depth=50pt) on the right
       dock end (endRight=1), top-right and bottom-right corners stay cleanly
       detached (crownW == 1.0, hEff < 7.5 pt < 9.5 pt inner-bar gap). */
    wxg_kf2_t endHalf = WXG_K_MAKE2(w * .5f, h * .5f);
    float trHEff = 0.f, trAEff = 0.f, trCrown = 0.f;
    WXGKyantCrownBands(WXG_K_MAKE2(0.35f * endHalf.x, -0.75f * endHalf.y), endHalf, 40.f, 50.f, 0.f, 1.f,
                       &trHEff, &trAEff, &trCrown);
    assert(trCrown > 0.999f && trHEff < 7.5f);
    printf("PASS: R15 4-quadrant aurora symmetry, concentric end-cap gap (right=%.2f vs top=%.2f pt), extreme-slider end detach (hEff=%.2f pt).\n",
           rightGap, topGap, trHEff);
}

int main(void) {
    testFlatInnerBarZeroRefraction();
    testPureGlassRGBAndMeshBudget();
    testAdaptiveFlexTiming();
    testR8PureDockModelAndMotionTier();
    testR13AuroraSymmetryAndEndRoundness();
    return 0;
}
