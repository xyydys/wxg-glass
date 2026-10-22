#ifndef WXG_DOCK_DISCRETE_H
#define WXG_DOCK_DISCRETE_H
#include <math.h>

/* 离散底栏 (discrete dock): every tab is its own glass capsule. The selected
   tab is `wide` cells wide (those cells plus the gaps between them), the
   others one cell: a ball, its diameter the pieces' height.

   Each tab's expansion e (0 ball .. 1 wide) is a spring. All of them share
   one stiffness and damping and their targets always add up to 1 (only the
   selected tab is 1), so - the springs being linear - the expansions keep
   adding up to 1 through every switch, interrupted or not: the row's total
   width never changes and nothing has to recentre. An overshoot only lends
   width from one tab to another (the old one squeezes a little narrower
   than a ball while the new one swells past its width).

   Connected (相连): the gap between two balls is filled by glass. A bridge b
   (0 open .. 1 joined, its own spring) grows each side into the gap by
   b x gap / 2; at 1 the two capsules are one. The tabs never move for it:
   connected and separate rows have the same positions. */

enum { WXGDiscreteTabs = 4 };

typedef struct {
    float cell;      // ball diameter = height of every piece (pt)
    float gap;       // between two capsules (pt)
    float wide;      // the selected tab's width in cells (1..3)
    float originX;   // the row's left edge, from the material's left
    float originY;   // the pieces' top, from the material's top
    float total;     // the row's width at rest
} WXGDiscreteMetrics;

typedef struct {
    int first, last;   // tabs in this capsule
    float x, w;        // its span (material space)
} WXGDiscreteRun;

static inline float WXGDiscreteClampf(float x, float lo, float hi) {
    return x < lo ? lo : (x > hi ? hi : x);
}

/* The row inside a material `width` x `height`: balls `ballRatio` x the
   height. align: -1 left, 0 centre, 1 right (the side of the search button,
   so the row stays beside it).
   FIX113 E: too narrow for those balls (the search button takes its share
   of the row), the balls keep the height asked for as long as they can: the
   selected tab narrows first (down to WXGDiscreteWideFloor cells), then the
   gaps (down to half, never under 3 pt), and only then the balls shrink
   (before, they shrank at once: past about 0.7 of the bar with the search
   button the setting did nothing). */
static inline float WXGDiscreteWideFloor(float wide) {return wide < 1.6f ? wide : 1.6f;}
static inline WXGDiscreteMetrics WXGDiscreteFit(float width, float height, float ballRatio,
                                                float gap, float wide, int align) {
    WXGDiscreteMetrics m;
    const int n = WXGDiscreteTabs;
    wide = (wide == wide) ? WXGDiscreteClampf(wide, 1.f, 3.f) : 2.f;
    gap = (gap == gap) ? WXGDiscreteClampf(gap, 0.f, 40.f) : 8.f;
    if (!(ballRatio > 0.f)) ballRatio = 1.f;
    if (!(width > 0.f)) width = 1.f;
    if (!(height > 0.f)) height = 1.f;
    float want = height * ballRatio;
    if (want < 8.f) want = 8.f;
    if ((float)(n - 1 + wide) * want + (float)(n - 2 + wide) * gap > width) {
        float floorWide = WXGDiscreteWideFloor(wide);
        float fitWide = (width - (float)(n - 1) * want - (float)(n - 2) * gap) / (want + gap);
        if (fitWide >= floorWide) wide = fitWide < wide ? fitWide : wide;
        else {
            wide = floorWide;
            float floorGap = gap < 3.f ? gap : (gap * .5f > 3.f ? gap * .5f : 3.f);
            float fitGap = (width - (float)(n - 1 + wide) * want) / (float)(n - 2 + wide);
            gap = fitGap > floorGap ? (fitGap < gap ? fitGap : gap) : floorGap;
        }
    }
    float cells = (float)(n - 1) + wide;          // 5 cells with a 2-cell selection
    float gaps = (float)(n - 1) + (wide - 1.f);   // 4 gaps: 3 between, 1 inside the wide tab
    float fit = (width - gaps * gap) / cells;
    float cell = fminf(want, fit);
    if (cell < 8.f) cell = 8.f;
    m.cell = cell; m.gap = gap; m.wide = wide;
    m.total = cells * cell + gaps * gap;
    float spare = width - m.total;
    m.originX = align < 0 ? 0.f : (align > 0 ? spare : spare * .5f);
    m.originY = (height - cell) * .5f;
    return m;
}
/* FIX113 E: the material width the row needs for balls `ballRatio` x the
   height with the selected tab at its floor and the gaps as set (the host
   widens the dock's row with the search button up to this). */
static inline float WXGDiscreteNeededWidth(float height, float ballRatio, float gap, float wide) {
    const int n = WXGDiscreteTabs;
    wide = (wide == wide) ? WXGDiscreteClampf(wide, 1.f, 3.f) : 2.f;
    gap = (gap == gap) ? WXGDiscreteClampf(gap, 0.f, 40.f) : 8.f;
    if (!(ballRatio > 0.f)) ballRatio = 1.f;
    float want = height * ballRatio, w = WXGDiscreteWideFloor(wide);
    if (want < 8.f) want = 8.f;
    return (float)(n - 1 + w) * want + (float)(n - 2 + w) * gap;
}

/* A tab's width at expansion e. An overshoot below a ball is floored at
   45% of one (springs damped >= 0.45 never get there in practice). */
static inline float WXGDiscreteTabWidth(WXGDiscreteMetrics m, float e) {
    float w = m.cell + (m.wide - 1.f) * (m.cell + m.gap) * e;
    float lo = m.cell * .45f;
    return w < lo ? lo : w;
}

/* Every tab's left edge and width (material space), laid from the row's
   alignment edge; e[] need not add up to exactly 1. */
static inline void WXGDiscreteLayout(WXGDiscreteMetrics m, const double *e, int align, float *x, float *w) {
    const int n = WXGDiscreteTabs;
    float sum = 0.f;
    for (int i = 0; i < n; i++) { w[i] = WXGDiscreteTabWidth(m, (float)e[i]); sum += w[i]; }
    sum += m.gap * (float)(n - 1);
    float start = m.originX + (align < 0 ? 0.f : (align > 0 ? m.total - sum : (m.total - sum) * .5f));
    for (int i = 0; i < n; i++) { x[i] = start; start += w[i] + m.gap; }
}

/* The tab under px (material space): inside a capsule, or the nearer half of
   a gap. The selected tab being the wide one, a finger that has selected a
   tab stays inside it while the row re-lays itself (it grows toward the
   finger), so dragging across never flickers between two tabs. */
static inline int WXGDiscreteTabAt(const float *x, const float *w, float gap, float px) {
    const int n = WXGDiscreteTabs;
    for (int i = 0; i < n; i++) {
        float lo = x[i] - (i > 0 ? gap * .5f : 1e6f), hi = x[i] + w[i] + (i < n - 1 ? gap * .5f : 1e6f);
        if (px >= lo && px < hi) return i;
    }
    return px < x[0] ? 0 : n - 1;
}

/* The glass capsules: maximal runs of tabs whose bridges are joined (>= 1);
   an unjoined side reaches b x gap / 2 into its gap. Returns the count. */
static inline int WXGDiscreteRuns(const float *x, const float *w, const double *bridge, float gap, WXGDiscreteRun *out) {
    const int n = WXGDiscreteTabs;
    int count = 0, i = 0;
    while (i < n) {
        int first = i;
        while (i < n - 1 && bridge[i] >= .999) i++;
        int last = i;
        // Eased: the two ends ease toward each other and meet softly.
        float bl = first > 0 ? WXGDiscreteClampf((float)bridge[first - 1], 0.f, 1.f) : 0.f;
        float br = last < n - 1 ? WXGDiscreteClampf((float)bridge[last], 0.f, 1.f) : 0.f;
        float reachL = bl * bl * (3.f - 2.f * bl) * gap * .5f;
        float reachR = br * br * (3.f - 2.f * br) * gap * .5f;
        float left = x[first] - reachL, right = x[last] + w[last] + reachR;
        out[count].first = first; out[count].last = last;
        out[count].x = left; out[count].w = right - left;
        count++;
        i++;
    }
    return count;
}

/* A bridge's target: joined between two tabs neither of which is the
   selection. FIX106 B (user: the joining lagged, the joined capsule only
   formed once the switch was over): from the moment of the switch, so the
   old selection joins its neighbours while it shrinks and the new one splits
   off while it widens - together with the expansion, not after it. */
static inline float WXGDiscreteBridgeTarget(int connected, int selected, int i) {
    return (!connected || selected == i || selected == i + 1) ? 0.f : 1.f;
}

/* A bridge moves at a constant rate toward its target, `duration` s end to
   end (eased where it is drawn, WXGDiscreteRuns), so a join is complete -
   one capsule - a fixed, short time into the switch rather than at an
   asymptote's tail. */
static inline double WXGDiscreteBridgeStep(double b, double target, double dt, double duration) {
    double step = duration > 1e-3 ? dt / duration : 1.;
    if (!(step > 0.)) return b;
    if (b < target) { b += step; if (b > target) b = target; }
    else if (b > target) { b -= step; if (b < target) b = target; }
    return b < 0. ? 0. : (b > 1. ? 1. : b);
}
/* How long a bridge takes: a share of the spring's response (the switch). */
static inline double WXGDiscreteBridgeDuration(double response) {
    double d = response * .35;
    return d < .06 ? .06 : d;
}

/* FIX106 C (user: connected, the icons at the run's ends sat too far out,
   unbalanced): where each tab's icon rests, as a share of one cell + gap
   from its own cell's centre. Within a run of joined balls the icons gather
   toward the run's middle by `gather`, so they stay evenly spaced at
   (1 - gather) x (cell + gap) - the same spacing in a run of two or three -
   with more room left at the round ends. None for the selection, a lone
   ball, or when not connected. */
static inline void WXGDiscreteGatherTargets(int connected, int selected, float gather, double *out) {
    const int n = WXGDiscreteTabs;
    for (int i = 0; i < n; i++) out[i] = 0.;
    if (!connected || !(gather > 0.f)) return;
    int i = 0;
    while (i < n) {
        if (i == selected) { i++; continue; }
        int first = i;
        while (i + 1 < n && i + 1 != selected) i++;
        int last = i;
        double mid = (first + last) * .5;
        for (int k = first; k <= last; k++) out[k] = gather * (mid - k);
        i++;
    }
}

/* Where an unread badge sits: centred on the capsule's right end cap at 45
   degrees up - the top-right corner of a ball and of the wide capsule alike,
   clear of the icon and the titles, gliding with the capsule's width. */
static inline void WXGDiscreteBadgeCentre(float x, float y, float w, float h, float *cx, float *cy) {
    float r = (w < h ? w : h) * .5f, k = 1.f - .70710678f;
    *cx = x + w - r * k;
    *cy = y + r * k;
}

/* Spring constants (unit mass) from a damping ratio and a response (the
   undamped period, s): stiffness (2 pi / T)^2, damping 2 zeta omega. */
static inline void WXGDiscreteSpringConstants(double damping, double response, double *stiffness, double *friction) {
    if (!(response > .05)) response = .05;
    if (!(damping > .05)) damping = .05;
    double omega = 2. * 3.14159265358979323846 / response;
    *stiffness = omega * omega;
    *friction = 2. * damping * omega;
}

/* 0..1 with an eased start and end between lo and hi. */
static inline float WXGDiscreteSmooth(float lo, float hi, float x) {
    float t = hi > lo ? WXGDiscreteClampf((x - lo) / (hi - lo), 0.f, 1.f) : (x >= hi ? 1.f : 0.f);
    return t * t * (3.f - 2.f * t);
}

/* The wide tab's content (icon, then the two titles) as one block centred
   in the capsule: the block widens with the expansion so the icon slides
   from the ball's centre to the left of the titles. Returns the icon's
   centre x; *textX is where the titles begin. */
static inline float WXGDiscreteContent(float x, float w, float iconW, float spacing, float textW, float e, float *textX) {
    float t = WXGDiscreteClampf(e, 0.f, 1.f);
    float block = iconW + (spacing + textW) * t;
    float iconX = x + w * .5f - block * .5f + iconW * .5f;
    if (textX) *textX = iconX + iconW * .5f + spacing;
    return iconX;
}

/* FIX106 H (user: the centred block - icon and titles together - is right,
   but looks off: it needs an offset): the same block moved `shiftLeft` pt to
   the left when the tab is wide (in step with the expansion, none for a
   ball), never past the icon sitting on the left end cap's centre. */
static inline float WXGDiscreteContentShifted(float x, float w, float h, float iconW, float spacing, float textW,
                                              float e, float shiftLeft, float *textX) {
    float tx = 0.f;
    float iconX = WXGDiscreteContent(x, w, iconW, spacing, textW, e, &tx);
    float limit = iconX - (x + (w < h ? w : h) * .5f);
    float s = shiftLeft > 0.f ? (shiftLeft < limit ? shiftLeft : (limit > 0.f ? limit : 0.f)) : 0.f;
    s *= WXGDiscreteClampf(e, 0.f, 1.f);
    if (textX) *textX = tx - s;
    return iconX - s;
}

#endif
