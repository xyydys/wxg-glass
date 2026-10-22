#include "../Sources/WXGDockDiscrete.h"
#include "../Sources/WXGMotion.h"
#include <assert.h>
#include <stdio.h>

static float rowWidth(WXGDiscreteMetrics m, const double *e, int align) {
    float x[4], w[4];
    WXGDiscreteLayout(m, e, align, x, w);
    return x[3] + w[3] - x[0];
}
static float rowLeft(WXGDiscreteMetrics m, const double *e, int align) {
    float x[4], w[4];
    WXGDiscreteLayout(m, e, align, x, w);
    return x[0];
}
static void target(int selected, double *t) { for (int i = 0; i < 4; i++) t[i] = i == selected ? 1. : 0.; }

int main(void) {
    // Fit: 354 x 62 material, balls 0.9 x height, 8 pt gaps, 2-cell selection.
    WXGDiscreteMetrics m = WXGDiscreteFit(354, 62, .9f, 8, 2, 0);
    assert(fabsf(m.cell - 55.8f) < .01f);
    assert(fabsf(m.total - (5 * m.cell + 4 * 8)) < .01f);
    assert(fabsf(m.originX - (354 - m.total) * .5f) < .01f && fabsf(m.originY - (62 - m.cell) * .5f) < .01f);
    // Too narrow: the cell shrinks so the row fills the width exactly.
    WXGDiscreteMetrics tight = WXGDiscreteFit(250, 62, 1, 8, 2, 0);
    assert(tight.cell < 62 && fabsf(tight.total - 250) < .01f && fabsf(tight.originX) < .01f);
    // FIX113 E: a little too narrow: the balls keep their height, the selected tab narrows.
    WXGDiscreteMetrics narrow = WXGDiscreteFit(330, 62, 1, 8, 2, 0);
    assert(fabsf(narrow.cell - 62) < .01f && narrow.wide < 2 && narrow.wide >= 1.6f && fabsf(narrow.gap - 8) < .01f && fabsf(narrow.total - 330) < .05f);
    // Narrower: the selected tab at its floor, then the gaps (not under half).
    WXGDiscreteMetrics squeezed = WXGDiscreteFit(300, 62, 1, 8, 2, 0);
    assert(fabsf(squeezed.cell - 62) < .01f && fabsf(squeezed.wide - 1.6f) < .001f && squeezed.gap < 8 && squeezed.gap >= 4 && fabsf(squeezed.total - 300) < .05f);
    // What the host widens the search row to: exactly enough for that.
    float need = WXGDiscreteNeededWidth(62, 1, 8, 2);
    WXGDiscreteMetrics enough = WXGDiscreteFit(need, 62, 1, 8, 2, 0);
    assert(fabsf(need - (4.6f * 62 + 3.6f * 8)) < .01f && fabsf(enough.cell - 62) < .01f && fabsf(enough.gap - 8) < .01f && fabsf(enough.wide - 1.6f) < .001f);
    // Alignment toward the search button.
    WXGDiscreteMetrics left = WXGDiscreteFit(354, 62, .9f, 8, 2, -1), right = WXGDiscreteFit(354, 62, .9f, 8, 2, 1);
    assert(left.originX == 0.f && fabsf(right.originX + right.total - 354) < .01f);

    // At rest: the selected tab is two cells and the gap between them; gaps exact.
    double e[4] = {0, 1, 0, 0};
    float x[4], w[4];
    WXGDiscreteLayout(m, e, 0, x, w);
    assert(fabsf(w[1] - (2 * m.cell + m.gap)) < .01f && fabsf(w[0] - m.cell) < .01f);
    for (int i = 0; i < 3; i++) assert(fabsf(x[i + 1] - (x[i] + w[i]) - m.gap) < .01f);
    assert(fabsf(x[3] + w[3] - x[0] - m.total) < .01f && fabsf(x[0] - m.originX) < .01f);

    // Switch 0 -> 2 on the springs (React's damping 20 / stiffness 230 / mass 1.2
    // is about zeta 0.6, 0.45 s): the expansions keep adding up to 1, so the row
    // keeps its width and place; the new tab overshoots, the old one squeezes.
    double k, c;
    WXGDiscreteSpringConstants(.6, .45, &k, &c);
    assert(fabs(k - 194.96) < .5 && fabs(c - 16.76) < .05);
    double v[4] = {0}, t[4];
    e[0] = 1; e[1] = 0; e[2] = 0; e[3] = 0;
    target(2, t);
    double peak = 0, dip = 1;
    float width0 = rowWidth(m, e, 0), left0 = rowLeft(m, e, 0);
    for (int f = 0; f < 120; f++) {
        for (int i = 0; i < 4; i++) WXGSpring(&e[i], &v[i], t[i], k, c, 1. / 60);
        double sum = e[0] + e[1] + e[2] + e[3];
        assert(fabs(sum - 1) < 1e-3);
        assert(fabsf(rowWidth(m, e, 0) - width0) < .05f && fabsf(rowLeft(m, e, 0) - left0) < .05f);
        if (e[2] > peak) peak = e[2];
        if (e[0] < dip) dip = e[0];
        // Interrupted half way: now to tab 3. Still conserved.
        if (f == 12) target(3, t);
    }
    assert(peak > .5 && fabs(e[3] - 1) < .002 && fabs(e[2]) < .002 && fabs(e[0]) < .002);
    // A plain switch overshoots (the bounce) but never down to the floor.
    e[0] = 1; e[1] = e[2] = e[3] = 0; v[0] = v[1] = v[2] = v[3] = 0;
    target(1, t);
    peak = 0; dip = 1;
    for (int f = 0; f < 120; f++) {
        for (int i = 0; i < 4; i++) WXGSpring(&e[i], &v[i], t[i], k, c, 1. / 60);
        if (e[1] > peak) peak = e[1];
        if (e[0] < dip) dip = e[0];
    }
    assert(peak > 1.05 && peak < 1.15 && dip < -.05);
    WXGDiscreteMetrics wide3 = WXGDiscreteFit(354, 62, .9f, 8, 3, 0);
    double stiff, fric;
    WXGDiscreteSpringConstants(.45, .2, &stiff, &fric);
    e[0] = 1; e[1] = e[2] = e[3] = 0; v[0] = v[1] = v[2] = v[3] = 0;
    target(3, t);
    for (int f = 0; f < 240; f++) {
        for (int i = 0; i < 4; i++) WXGSpring(&e[i], &v[i], t[i], stiff, fric, 1. / 120);
        for (int i = 0; i < 4; i++) assert(WXGDiscreteTabWidth(wide3, (float)e[i]) > wide3.cell * .45f + .01f);
    }

    // Drag across, the selection following the finger on the live layout:
    // exactly three changes, never back and forth.
    e[0] = 1; e[1] = e[2] = e[3] = 0; v[0] = v[1] = v[2] = v[3] = 0;
    int selected = 0, changes = 0;
    target(0, t);
    for (int f = 0; f <= 180; f++) {
        float px = m.originX + 4 + (m.total - 8) * (float)f / 180.f;
        WXGDiscreteLayout(m, e, 0, x, w);
        int under = WXGDiscreteTabAt(x, w, m.gap, px);
        assert(px >= x[under] - m.gap * .5f - .01f || under == 0);
        if (under != selected) { assert(under == selected + 1); selected = under; changes++; target(selected, t); }
        for (int i = 0; i < 4; i++) WXGSpring(&e[i], &v[i], t[i], k, c, 1. / 60);
    }
    assert(changes == 3 && selected == 3);
    // And back again.
    for (int f = 180; f >= 0; f--) {
        float px = m.originX + 4 + (m.total - 8) * (float)f / 180.f;
        WXGDiscreteLayout(m, e, 0, x, w);
        int under = WXGDiscreteTabAt(x, w, m.gap, px);
        if (under != selected) { assert(under == selected - 1); selected = under; changes++; target(selected, t); }
        for (int i = 0; i < 4; i++) WXGSpring(&e[i], &v[i], t[i], k, c, 1. / 60);
    }
    assert(changes == 6 && selected == 0);
    // Outside the row: the end tabs.
    WXGDiscreteLayout(m, e, 0, x, w);
    assert(WXGDiscreteTabAt(x, w, m.gap, -100) == 0 && WXGDiscreteTabAt(x, w, m.gap, 1000) == 3);

    // Capsules: separate -> four; connected with tab 2 selected -> [0 1] [2] [3].
    double rest2[4] = {0, 0, 1, 0}, open[3] = {0, 0, 0}, bridge[3];
    WXGDiscreteLayout(m, rest2, 0, x, w);
    WXGDiscreteRun runs[4];
    assert(WXGDiscreteRuns(x, w, open, m.gap, runs) == 4);
    for (int i = 0; i < 3; i++) bridge[i] = WXGDiscreteBridgeTarget(1, 2, i);
    assert(bridge[0] == 1 && bridge[1] == 0 && bridge[2] == 0);
    assert(WXGDiscreteBridgeTarget(0, 2, 0) == 0);
    int count = WXGDiscreteRuns(x, w, bridge, m.gap, runs);
    assert(count == 3 && runs[0].first == 0 && runs[0].last == 1 && runs[1].first == 2 && runs[2].first == 3);
    assert(fabsf(runs[0].x - x[0]) < .01f && fabsf(runs[0].w - (2 * m.cell + m.gap)) < .01f);
    // Half-built bridge: each side reaches a quarter of the gap (eased: 0.5 is
    // half way); nothing joined yet.
    double half[3] = {.5, 0, 0};
    count = WXGDiscreteRuns(x, w, half, m.gap, runs);
    assert(count == 4 && fabsf(runs[0].w - (w[0] + m.gap * .25f)) < .01f && fabsf(runs[1].x - (x[1] - m.gap * .25f)) < .01f);

    // FIX106 B: connected, switch 1 -> 3 (rest: [0] [1 wide] [2 3]). The old
    // selection starts joining its neighbours and the new one splitting off at
    // the very start, and the join is one capsule while the new tab is still
    // widening - not after the switch.
    {
        double ee[4] = {0, 1, 0, 0}, vv[4] = {0}, tt[4] = {0, 0, 0, 1}, bb[3];
        for (int i = 0; i < 3; i++) bb[i] = WXGDiscreteBridgeTarget(1, 1, i);
        assert(bb[0] == 0 && bb[1] == 0 && bb[2] == 1);
        double response = .45, duration = WXGDiscreteBridgeDuration(response), kk, cc;
        WXGDiscreteSpringConstants(.6, response, &kk, &cc);
        int joinedAt = -1, splitAt = -1, wideAt = -1;
        for (int f = 1; f <= 120; f++) {
            for (int i = 0; i < 4; i++) WXGSpring(&ee[i], &vv[i], tt[i], kk, cc, 1. / 60);
            for (int i = 0; i < 3; i++) bb[i] = WXGDiscreteBridgeStep(bb[i], WXGDiscreteBridgeTarget(1, 3, i), 1. / 60, duration);
            if (f == 1) assert(bb[0] > 0 && bb[1] > 0 && bb[2] < 1);   // all three move on the first frame
            WXGDiscreteLayout(m, ee, 0, x, w);
            int n = WXGDiscreteRuns(x, w, bb, m.gap, runs);
            if (joinedAt < 0 && n >= 1 && runs[0].first == 0 && runs[0].last == 2) joinedAt = f;
            if (splitAt < 0 && bb[2] <= 0) splitAt = f;
            if (wideAt < 0 && ee[3] > .98) wideAt = f;
        }
        assert(joinedAt > 0 && splitAt > 0 && wideAt > 0);
        assert(joinedAt <= (int)ceil(duration * 60) + 1 && splitAt <= (int)ceil(duration * 60) + 1);
        assert(joinedAt < wideAt);   // one capsule while the new tab is still widening
        // Rest: [0 1 2] [3 wide].
        WXGDiscreteLayout(m, ee, 0, x, w);
        assert(WXGDiscreteRuns(x, w, bb, m.gap, runs) == 2 && runs[0].last == 2 && runs[1].first == 3);
        // Steps: constant rate, clamped, never past the target.
        assert(fabs(WXGDiscreteBridgeStep(0, 1, .05, .1) - .5) < 1e-9 && WXGDiscreteBridgeStep(.9, 1, .05, .1) == 1 && WXGDiscreteBridgeStep(.1, 0, .05, .1) == 0);
    }

    // FIX106 C: connected, the icons in a run gather toward its middle, evenly
    // spaced (1 - gather) cells apart in a run of three or of two; none for the
    // selection, a lone ball, or separate balls.
    {
        double g[4];
        WXGDiscreteGatherTargets(1, 3, .22f, g);          // [0 1 2] [3]
        assert(fabs(g[0] - .22) < 1e-6 && fabs(g[1]) < 1e-6 && fabs(g[2] + .22) < 1e-6 && g[3] == 0);
        double s01 = 1 + g[1] - g[0], s12 = 1 + g[2] - g[1];
        assert(fabs(s01 - .78) < 1e-6 && fabs(s12 - .78) < 1e-6);
        WXGDiscreteGatherTargets(1, 1, .22f, g);          // [0] [1] [2 3]
        assert(g[0] == 0 && g[1] == 0 && fabs(g[2] - .11) < 1e-6 && fabs(g[3] + .11) < 1e-6);
        assert(fabs((1 + g[3] - g[2]) - .78) < 1e-6);
        WXGDiscreteGatherTargets(1, 0, .22f, g);          // [0] [1 2 3]
        assert(g[0] == 0 && fabs(g[1] - .22) < 1e-6 && fabs(g[2]) < 1e-6 && fabs(g[3] + .22) < 1e-6);
        WXGDiscreteGatherTargets(0, 3, .22f, g);
        assert(g[0] == 0 && g[1] == 0 && g[2] == 0 && g[3] == 0);
        WXGDiscreteGatherTargets(1, 3, 0, g);
        assert(g[0] == 0 && g[2] == 0);
    }

    // FIX106 H: the centred block, moved left by an offset when wide; none on a
    // ball; never past the icon on the left end cap's centre.
    {
        float h2 = 65, W = 2 * 65 + 8, tx0 = 0, tx = 0;
        float a = WXGDiscreteContent(0, W, 32, 7, 16, 1, &tx0);                     // A: 我 / Me centred
        float s = WXGDiscreteContentShifted(0, W, h2, 32, 7, 16, 1, 10, &tx);
        assert(fabsf((a - s) - 10) < .01f && fabsf((tx0 - tx) - 10) < .01f);        // 10 pt left, titles with it
        float ball = WXGDiscreteContentShifted(0, 65, h2, 32, 7, 16, 0, 10, &tx);
        assert(fabsf(ball - 32.5f) < .01f);                                          // a ball: centred, no offset
        float half = WXGDiscreteContentShifted(0, W, h2, 32, 7, 16, .5f, 10, &tx);
        float halfA = WXGDiscreteContent(0, W, 32, 7, 16, .5f, &tx0);
        assert(fabsf((halfA - half) - 5) < .01f);                                    // in step with the expansion
        float far = WXGDiscreteContentShifted(0, W, h2, 32, 7, 50, 1, 30, &tx);      // 通讯录 / Contacts, a big offset
        assert(fabsf(far - 32.5f) < .01f);                                           // stops at the left cap's centre
        float none = WXGDiscreteContentShifted(0, W, h2, 32, 7, 16, 1, 0, &tx);
        assert(fabsf(none - a) < .01f);                                              // 0 = A exactly
    }

    // Badges: on the end cap's top-right at 45 degrees - a ball's corner, and
    // the wide capsule's right end (clear of the icon at its left).
    {
        float bx, by;
        WXGDiscreteBadgeCentre(100, 10, 56, 56, &bx, &by);
        assert(fabsf(bx - (128 + 28 * .70710678f)) < .01f && fabsf(by - (38 - 28 * .70710678f)) < .01f);
        WXGDiscreteBadgeCentre(100, 10, 120, 56, &bx, &by);
        assert(fabsf(bx - (220 - 28 * (1 - .70710678f))) < .01f && fabsf(by - (10 + 28 * (1 - .70710678f))) < .01f);
        assert(bx > 100 + 120 - 28);   // inside the right end cap, far right of the icon
    }

    // Content: centred icon on a ball; icon + titles centred in the wide tab.
    float textX = 0;
    float icon0 = WXGDiscreteContent(100, 56, 26, 6, 40, 0, &textX);
    assert(fabsf(icon0 - 128) < .01f);
    float icon1 = WXGDiscreteContent(100, 120, 26, 6, 40, 1, &textX);
    float blockL = icon1 - 13, blockR = textX + 40;
    assert(fabsf((blockL + blockR) * .5f - 160) < .01f);
    assert(WXGDiscreteSmooth(.4f, 1, .2f) == 0 && WXGDiscreteSmooth(.4f, 1, 1.2f) == 1);

    puts("PASS: discrete dock (离散底栏): row fitted and aligned, wide tab = 2 cells + gap, expansions conserved through switches, interruptions and overshoot (row never moves), squeeze above the floor, drag selection never flickers, connected capsules join only between balls, content centred.");
    return 0;
}
