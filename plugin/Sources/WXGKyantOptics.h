#ifndef WXG_KYANT_OPTICS_H
#define WXG_KYANT_OPTICS_H

#include "WXGLensOptics.h"

/* Kyant AndroidLiquidGlass (Backdrop, Apache-2.0, upstream eb4a0ea2) optics
   cleanly integrated for FIX135 main continuous dock (C + Metal shared). */
#define WXG_LENS_KYANT 2000.f
static inline int WXGLensKyantCode(float w) { return w >= 1500.f; }

#ifdef __METAL_VERSION__
#define WXG_K_OUT thread
#define WXG_K_F2 float2
#define WXG_K_F3 float3
#define WXG_K_F4 float4
#define WXG_K_MAKE2(x, y) float2((x), (y))
#define WXG_K_MAKE3(x, y, z) float3((x), (y), (z))
#define WXG_K_MAKE4(x, y, z, w) float4((x), (y), (z), (w))
#define WXG_K_ABS fabs
#define WXG_K_MAX max
#define WXG_K_MIN min
#define WXG_K_SQRT sqrt
#define WXG_K_LENGTH length
#define WXG_K_NORMALIZE normalize
#define WXG_K_SIGN sign
#define WXG_K_SATURATE saturate
#define WXG_K_FLOOR floor
#define WXG_K_DOT dot
#define WXG_K_MIX mix
#else
#define WXG_K_OUT
#include <math.h>
#include <stddef.h>
typedef struct { float x, y; } wxg_kf2_t;
typedef struct { float x, y, z; } wxg_kf3_t;
typedef struct { float x, y, z, w; } wxg_kf4_t;
#define WXG_K_F2 wxg_kf2_t
#define WXG_K_F3 wxg_kf3_t
#define WXG_K_F4 wxg_kf4_t
static inline wxg_kf2_t WXG_K_MAKE2(float x, float y) { wxg_kf2_t v = {x, y}; return v; }
static inline wxg_kf3_t WXG_K_MAKE3(float x, float y, float z) { wxg_kf3_t v = {x, y, z}; return v; }
static inline wxg_kf4_t WXG_K_MAKE4(float x, float y, float z, float w) { wxg_kf4_t v = {x, y, z, w}; return v; }
#define WXG_K_ABS fabsf
#define WXG_K_MAX fmaxf
#define WXG_K_MIN fminf
#define WXG_K_SQRT sqrtf
#define WXG_K_FLOOR floorf
static inline float WXG_K_LENGTH(wxg_kf2_t v) { return sqrtf(v.x * v.x + v.y * v.y); }
static inline wxg_kf2_t WXG_K_NORMALIZE(wxg_kf2_t v) {
    float l = WXG_K_LENGTH(v);
    return l > 1e-6f ? WXG_K_MAKE2(v.x / l, v.y / l) : WXG_K_MAKE2(0.f, 0.f);
}
static inline wxg_kf2_t WXG_K_SIGN(wxg_kf2_t v) {
    return WXG_K_MAKE2(v.x > 0.f ? 1.f : (v.x < 0.f ? -1.f : 0.f),
                       v.y > 0.f ? 1.f : (v.y < 0.f ? -1.f : 0.f));
}
static inline float WXG_K_SATURATE(float x) { return x < 0.f ? 0.f : (x > 1.f ? 1.f : x); }
static inline float WXG_K_DOT(wxg_kf2_t a, wxg_kf2_t b) { return a.x * b.x + a.y * b.y; }
#endif

static inline float WXGKyantEase(float x) {
    x = WXG_K_SATURATE(x);
    return x * x * (3.f - 2.f * x);
}

/* Smooth finite-slope quarter-circle lens map: preserves full rim amplitude
   (g(0)=0, g'(0)=0, g(1)=1) while eliminating the infinite vertical slope at
   sd=0 that exploded spectral taps into discrete concentric steps. */
static inline float WXGKyantSmoothCircleMap(float x) {
    x = WXG_K_SATURATE(x);
    return (1.f - WXG_K_SQRT(WXG_K_MAX(0.04f, 1.f - 0.96f * x * x))) * 1.25f;
}

static inline float WXGKyantCircleMap(float x) {
    return WXGKyantSmoothCircleMap(x);
}

/* iOS 26 continuous capsule dip (exact WXGCapsule26.h table, C + Metal shared).
   Bends the top/bottom straight edges inward starting 0.50R before the round
   ends so refraction contours follow _lens26 smoothly without flattened corners. */
#ifdef __METAL_VERSION__
constant float WXG_KYANT_CAPSULE26_V[22] = {
    0.f, .0008f, .0025f, .0047f, .0074f, .0104f, .0132f, .0155f, .0168f, .0170f, .0160f,
    .0136f, .0111f, .0090f, .0073f, .0058f, .0046f, .0036f, .0025f, .0016f, .0006f, 0.f
};
static inline float WXGKyantCapsule26Table(int i) {
    return (i < 0 || i >= 22) ? 0.f : WXG_KYANT_CAPSULE26_V[i];
}
#else
static inline float WXGKyantCapsule26Table(int i) {
    static const float v[22] = {
        0.f, .0008f, .0025f, .0047f, .0074f, .0104f, .0132f, .0155f, .0168f, .0170f, .0160f,
        .0136f, .0111f, .0090f, .0073f, .0058f, .0046f, .0036f, .0025f, .0016f, .0006f, 0.f
    };
    return (i < 0 || i >= 22) ? 0.f : v[i];
}
#endif

static inline float WXGKyantCapsule26DipRaw(float u) {
    if (!(u > -0.55f) || !(u < 0.50f)) return 0.f;
    float f = (u + 0.55f) / 0.05f;
    int i = (int)WXG_K_FLOOR(f);
    float t = f - (float)i;
    float p0 = WXGKyantCapsule26Table(i - 1);
    float p1 = WXGKyantCapsule26Table(i);
    float p2 = WXGKyantCapsule26Table(i + 1);
    float p3 = WXGKyantCapsule26Table(i + 2);
    float v = 0.5f * ((2.f * p1) + (-p0 + p2) * t
        + (2.f * p0 - 5.f * p1 + 4.f * p2 - p3) * t * t
        + (-p0 + 3.f * p1 - 3.f * p2 + p3) * t * t * t);
    return v > 0.f ? v : 0.f;
}

static inline float WXGKyantCapsule26Offset(WXG_K_F2 coord, WXG_K_F2 halfSize, float radius) {
    float minH = WXG_K_MIN(halfSize.x, halfSize.y);
    float maxH = WXG_K_MAX(halfSize.x, halfSize.y);
    if (!(minH > 2.f) || radius < minH - 0.5f || (maxH - minH) <= 1.f) return 0.f;
    float s = WXG_K_SATURATE((maxH - minH) / (0.50f * minH));
    if (!(s > 1e-4f)) return 0.f;
    int horiz = halfSize.x >= halfSize.y;
    float along = horiz ? ((halfSize.x - minH) - WXG_K_ABS(coord.x))
                        : ((halfSize.y - minH) - WXG_K_ABS(coord.y));
    float across = horiz ? WXG_K_ABS(coord.y) : WXG_K_ABS(coord.x);
    float u = along / minH;
    float dip = s * WXGKyantCapsule26DipRaw(u / s) * minH;
    if (!(dip > 0.f)) return 0.f;
    float fade = WXGKyantEase((across / minH - 0.15f) / 0.35f);
    float proj = u < 0.f ? WXG_K_SQRT(WXG_K_MAX(0.f, 1.f - u * u)) : 1.f;
    return dip * proj * fade;
}

static inline float WXGKyantSdRoundedRect(WXG_K_F2 coord, WXG_K_F2 halfSize, float radius) {
    float r = WXGOClamp(radius, 0.f, WXG_K_MIN(halfSize.x, halfSize.y));
    float cx = WXG_K_ABS(coord.x) - (halfSize.x - r);
    float cy = WXG_K_ABS(coord.y) - (halfSize.y - r);
    float ox = WXG_K_MAX(cx, 0.f), oy = WXG_K_MAX(cy, 0.f);
    float outside = WXG_K_SQRT(ox * ox + oy * oy) - r;
    float inside = WXG_K_MIN(WXG_K_MAX(cx, cy), 0.f);
    return outside + inside + WXGKyantCapsule26Offset(coord, halfSize, r);
}

static inline WXG_K_F2 WXGKyantGradSdRoundedRect(WXG_K_F2 coord, WXG_K_F2 halfSize, float radius) {
    float minH = WXG_K_MIN(halfSize.x, halfSize.y);
    float maxH = WXG_K_MAX(halfSize.x, halfSize.y);
    float r = WXGOClamp(radius, 0.f, minH);
    if (minH > 2.f && r >= minH - 0.5f && (maxH - minH) > 1.f) {
        const float eps = 0.20f;
        float gx = WXGKyantSdRoundedRect(WXG_K_MAKE2(coord.x + eps, coord.y), halfSize, r)
                 - WXGKyantSdRoundedRect(WXG_K_MAKE2(coord.x - eps, coord.y), halfSize, r);
        float gy = WXGKyantSdRoundedRect(WXG_K_MAKE2(coord.x, coord.y + eps), halfSize, r)
                 - WXGKyantSdRoundedRect(WXG_K_MAKE2(coord.x, coord.y - eps), halfSize, r);
        float len = WXG_K_SQRT(gx * gx + gy * gy);
        return len > 1e-6f ? WXG_K_MAKE2(gx / len, gy / len) : WXG_K_MAKE2(0.f, 0.f);
    }
    float cx = WXG_K_ABS(coord.x) - (halfSize.x - r);
    float cy = WXG_K_ABS(coord.y) - (halfSize.y - r);
    WXG_K_F2 s = WXG_K_SIGN(coord);
    if (cx >= 0.f || cy >= 0.f) {
        float mx = WXG_K_MAX(cx, 0.f), my = WXG_K_MAX(cy, 0.f);
        float len = WXG_K_SQRT(mx * mx + my * my);
        if (!(len > 1e-6f)) return WXG_K_MAKE2(0.f, 0.f);
        return WXG_K_MAKE2(s.x * mx / len, s.y * my / len);
    } else {
        float gradX = cy <= cx ? 1.f : 0.f;
        return WXG_K_MAKE2(s.x * gradX, s.y * (1.f - gradX));
    }
}


/* Inner-bar inverse mapping for the native backdrop mesh and Metal selection
   coverage. Glyphs have their own source coordinates.
   `extra` offsets the target inset (0 keeps the fixed bodyPinch inset);
   `depthPad` offsets the lens SDF depth test so vertical elastic squash never
   collapses the inset ramp during fast horizontal drags. */
static inline WXG_K_F2 WXGKyantSceneSourceDepth(WXG_K_F2 source,WXG_K_F2 centralRay,
    WXG_K_F2 lensCenter,WXG_K_F2 lensSize,float lensRadius,
    WXG_K_F2 barOrigin,WXG_K_F2 barSize,float barRadius,
    float press,float pinch,float extra,float depthPad,float zoom) {
    if(!(press>0.f) || !(barSize.x>2.f && barSize.y>2.f))return source;
    float barHalf=WXG_K_MIN(barSize.x,barSize.y)*.5f;
    float bx=barOrigin.x+barSize.x*.5f,by=barOrigin.y+barSize.y*.5f;
    WXGShapeSample b=barRadius>0.f?WXGRoundedOpticalField(centralRay.x-bx,centralRay.y-by,barSize.x,barSize.y,barRadius)
        :WXGCapsuleOpticalField(centralRay.x-bx,centralRay.y-by,barSize.x,barSize.y);
    float ox=centralRay.x-b.nx*b.distance,oy=centralRay.y-b.ny*b.distance;
    WXGShapeSample l=lensRadius>0.f?WXGRoundedOpticalField(ox-lensCenter.x,oy-lensCenter.y,lensSize.x,lensSize.y,lensRadius)
        :WXGCapsuleOpticalField(ox-lensCenter.x,oy-lensCenter.y,lensSize.x,lensSize.y);
    float full=barSize.y*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(pinch,0.f,.30f)+extra;
    float along=WXGLensDepthAlongBar(l.distance-depthPad,-b.ny,b.nx,l.nx,l.ny);
    float absFull=WXG_K_ABS(full),ramp=absFull>1e-4f?WXGOClamp(along/(2.f*absFull),0.f,1.f):0.f;
    float inset=full*ramp*(2.f-ramp);
    float h=(ox-lensCenter.x)*b.nx+(oy-lensCenter.y)*b.ny;
    float dz=WXGOClamp(h-(h-inset)/WXG_K_MAX(zoom,.01f),extra<0.f?-barHalf*.5f:0.f,barHalf*.9f);
    if(!(WXG_K_ABS(dz)>0.f))return source;
    WXGShapeSample q=barRadius>0.f?WXGRoundedOpticalField(source.x-bx,source.y-by,barSize.x,barSize.y,barRadius)
        :WXGCapsuleOpticalField(source.x-bx,source.y-by,barSize.x,barSize.y);
    float t=q.distance,t2=t<-dz?-barHalf+(t+barHalf)*barHalf/(barHalf-dz):t+dz;
    if(t<-barHalf)t2=t;
    return WXG_K_MAKE2(source.x+q.nx*(t2-t),source.y+q.ny*(t2-t));
}
static inline WXG_K_F2 WXGKyantSceneSource(WXG_K_F2 source,WXG_K_F2 centralRay,
    WXG_K_F2 lensCenter,WXG_K_F2 lensSize,float lensRadius,
    WXG_K_F2 barOrigin,WXG_K_F2 barSize,float barRadius,
    float press,float pinch,float extra,float zoom) {
    return WXGKyantSceneSourceDepth(source,centralRay,lensCenter,lensSize,lensRadius,
        barOrigin,barSize,barRadius,press,pinch,extra,extra,zoom);
}

/* iOS 26 measured crown target (golden invariant f_min = h + a - sqrt(h^2 + a^2)
   stays < 6.2 pt < 6.75..7.5 pt gap so the dark pocket stays clean while keeping
   a solid ~2.4..2.7 pt mirrored outer lip). */
static inline void WXGKyantCrownTarget(
    float minHalf,
    float refractionHeight,
    float refractionAmount,
    WXG_K_OUT float *outH,
    WXG_K_OUT float *outA
) {
    float hScale = WXGOClamp(refractionHeight / 18.f, 0.f, 2.0f);
    float aScale = WXGOClamp(refractionAmount / 26.f, 0.f, 2.0f);
    float hCrown = WXG_K_MIN(refractionHeight, 0.20f * minHalf * (0.55f + 0.45f * hScale));
    float aCrown = WXG_K_MIN(refractionAmount, 0.56f * minHalf * (0.55f + 0.45f * aScale));
    if (outH) *outH = hCrown;
    if (outA) *outA = aCrown;
}

/* Wrapping end-cap target at the dock's left/right ends: slightly deeper than
   the flat top/bottom crown (f_min ~ 7.7 pt < 12.5 pt endWrap+inset gap) so
   the luminous rainbow outer lip wraps smoothly all the way around 3/9 o'clock
   without vanishing and flattening the capsule ends. */
static inline void WXGKyantEndTarget(
    float minHalf,
    float refractionHeight,
    float refractionAmount,
    WXG_K_OUT float *outH,
    WXG_K_OUT float *outA
) {
    float hScale = WXGOClamp(refractionHeight / 18.f, 0.f, 2.0f);
    float aScale = WXGOClamp(refractionAmount / 26.f, 0.f, 2.0f);
    float hEnd = WXG_K_MIN(refractionHeight, 0.255f * minHalf * (0.55f + 0.45f * hScale));
    float aEnd = WXG_K_MIN(refractionAmount, 0.78f * minHalf * (0.55f + 0.45f * aScale));
    if (outH) *outH = hEnd;
    if (outA) *outA = aEnd;
}

/* Smooth elliptical taper (ellipH^4 keeps the top/bottom dark pocket wide and
   graceful before opening into the four necks), plus continuous end-tab
   blending to WXGKyantEndTarget at the wrapping left/right ends. */
static inline void WXGKyantCrownBands(
    WXG_K_F2 centered,
    WXG_K_F2 halfSize,
    float refractionHeight,
    float refractionAmount,
    float endLeft,
    float endRight,
    WXG_K_OUT float *outH,
    WXG_K_OUT float *outA,
    WXG_K_OUT float *outCrownW
) {
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float elongated = WXGKyantEase((halfSize.x - halfSize.y) / WXG_K_MAX(0.15f * halfSize.y, 1e-4f));
    float ex = WXG_K_ABS(centered.x) / WXG_K_MAX(halfSize.x, 1.f);
    float ey = WXG_K_ABS(centered.y) / WXG_K_MAX(halfSize.y, 1.f);
    float ellipH = ex / WXG_K_MAX(WXG_K_SQRT(ex * ex + ey * ey), 1e-4f);
    float e2 = ellipH * ellipH;
    float shoulder = e2 * ellipH;
    float sx = centered.x / WXG_K_MAX(halfSize.x, 1.f);
    float endW = WXG_K_MAX(endLeft * WXGKyantEase((-sx) / 0.35f),
                           endRight * WXGKyantEase(sx / 0.35f));

    float hCrown = refractionHeight, aCrown = refractionAmount;
    float hEnd = refractionHeight, aEnd = refractionAmount;
    WXGKyantCrownTarget(minHalf, refractionHeight, refractionAmount, &hCrown, &aCrown);
    WXGKyantEndTarget(minHalf, refractionHeight, refractionAmount, &hEnd, &aEnd);

    float topW = elongated * (1.f - shoulder);
    float hBase = refractionHeight + topW * (hCrown - refractionHeight);
    float aBase = refractionAmount + topW * (aCrown - refractionAmount);
    float hTargetEnd = hEnd + topW * (hCrown - hEnd);
    float aTargetEnd = aEnd + topW * (aCrown - aEnd);
    if (outH) *outH = hBase + endW * (hTargetEnd - hBase);
    if (outA) *outA = aBase + endW * (aTargetEnd - aBase);
    if (outCrownW) *outCrownW = WXG_K_MAX(topW, endW * 0.65f);
}

static inline WXG_K_F2 WXGKyantRefractPoint(
    WXG_K_F2 coord,
    WXG_K_F2 center,
    WXG_K_F2 halfSize,
    float radius,
    float refractionHeight,
    float refractionAmount,
    float depthEffect,
    float endLeft,
    float endRight,
    WXG_K_OUT float *outD,
    WXG_K_OUT WXG_K_F2 *outG,
    WXG_K_OUT float *outCrownW,
    WXG_K_OUT float *outSd
) {
    WXG_K_F2 centered = WXG_K_MAKE2(coord.x - center.x, coord.y - center.y);
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float r = WXGOClamp(radius, 0.f, minHalf);
    float sd = WXGKyantSdRoundedRect(centered, halfSize, r);
    float gradRadius = WXG_K_MIN(r * 1.5f, minHalf);
    WXG_K_F2 g = WXGKyantGradSdRoundedRect(centered, halfSize, gradRadius);
    if (depthEffect > 1e-4f) {
        WXG_K_F2 cn = WXG_K_NORMALIZE(centered);
        g = WXG_K_MAKE2(g.x + depthEffect * cn.x, g.y + depthEffect * cn.y);
    }
    float gl = WXG_K_LENGTH(g);
    g = gl > 1e-6f ? WXG_K_MAKE2(g.x / gl, g.y / gl) : WXG_K_MAKE2(0.f, 0.f);
    float hEff = refractionHeight, aEff = refractionAmount, crownW = 0.f;
    WXGKyantCrownBands(centered, halfSize, refractionHeight, refractionAmount,
                       endLeft, endRight, &hEff, &aEff, &crownW);
    if (outG) *outG = g;
    if (outCrownW) *outCrownW = crownW;
    if (outSd) *outSd = sd;
    if (!(hEff > 1e-4f) || !(aEff > 1e-4f) || -sd >= hEff) {
        if (outD) *outD = 0.f;
        return coord;
    }
    float sdClamped = WXG_K_MIN(sd, 0.f);
    float d = WXGKyantSmoothCircleMap(1.f - (-sdClamped) / hEff) * (-aEff);
    if (outD) *outD = d;
    return WXG_K_MAKE2(coord.x + d * g.x, coord.y + d * g.y);
}

/* Symmetric 7-wavelength backdrop optical ray (iOS 26 glassForeground):
   - 100% left-right and top-bottom symmetric with ZERO quadrant zero-crossings
     (eliminates both left-side concentric stepping and top-right/bottom-left
     opaque-overlap / near-disconnect pinch knots).
   - Responsive slider curve (ca / (1 + 0.08*|ca|)) over a wider 0.55*minHalf
     perimeter halo that blooms smoothly at the four shoulders while keeping
     the central icon/text zone (depth >= 20 pt) completely crisp and neutral. */
static inline WXG_K_F2 WXGKyantSpectralRay(
    WXG_K_F2 coord,
    WXG_K_F2 center,
    WXG_K_F2 halfSize,
    float radius,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration,
    float depthEffect,
    float endLeft,
    float endRight,
    float spectralT,
    WXG_K_OUT WXG_K_F2 *outCentralRay
) {
    float d0 = 0.f, crown0 = 0.f, sd0 = 0.f;
    WXG_K_F2 g0 = WXG_K_MAKE2(0.f, 0.f);
    WXG_K_F2 central = WXGKyantRefractPoint(
        coord, center, halfSize, radius, refractionHeight, refractionAmount,
        depthEffect, endLeft, endRight, &d0, &g0, &crown0, &sd0);
    if (outCentralRay) *outCentralRay = central;
    if (!(WXG_K_ABS(spectralT) > 1e-6f) || !(chromaticAberration > 1e-4f) ||
        !(refractionHeight > 1e-4f) || !(refractionAmount > 1e-4f)) {
        return central;
    }
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float depth0 = WXG_K_MAX(-sd0, 0.f);
    float pressScale = WXG_K_SATURATE(WXG_K_MIN(refractionHeight / 4.f, refractionAmount / 6.f));
    float dispScale = (chromaticAberration / (1.f + 0.08f * WXG_K_ABS(chromaticAberration))) * pressScale;

    float ringW = WXG_K_MAX(0.55f * minHalf, 3.f);
    float ringU = WXG_K_SATURATE(1.f - depth0 / ringW);
    float ringEnv = ringU * (0.42f + 0.58f * ringU);
    float shoulderW = 1.f - crown0;
    float ringAmt = 0.78f * dispScale * ringEnv * (1.f + 0.50f * shoulderW);
    WXG_K_F2 pShifted = WXG_K_MAKE2(
        coord.x + spectralT * ringAmt * g0.x,
        coord.y + spectralT * ringAmt * g0.y
    );

    float dTap = 0.f, crownTap = 0.f, sdTap = 0.f;
    WXG_K_F2 gTap = WXG_K_MAKE2(0.f, 0.f);
    WXG_K_F2 rayTap = WXGKyantRefractPoint(
        pShifted, center, halfSize, radius, refractionHeight, refractionAmount,
        depthEffect, endLeft, endRight, &dTap, &gTap, &crownTap, &sdTap);

    /* Constructive Cauchy refractive dispersion (-gTap for +st) widens the
       translucent rainbow bloom across the rim & four shoulders monotonically
       with dispersion while keeping top/bottom inner-bar cool-blue edge intact. */
    float shoulderFactor = 1.f - crownTap;
    float endDisp = (-dTap) * (0.095f * dispScale) * (0.20f + 0.80f * shoulderFactor);
    endDisp = WXG_K_MIN(endDisp, 0.40f * WXG_K_MAX(WXG_K_ABS(dTap), 1.f));
    return WXG_K_MAKE2(rayTap.x - gTap.x * endDisp * spectralT,
                       rayTap.y - gTap.y * endDisp * spectralT);
}

/* Post-refraction bounded dispersion shift for crisp selected icons/labels in
   the Metal overlay: strictly 1.0x derivative (never amplified by rim slope)
   and 100% left-right symmetric, paired with 15 spectral taps for butter-smooth
   continuous prism transitions even on thin text strokes and badges at max ca. */
static inline float WXGKyantGlyphSpectralShift(
    float sd0,
    float d0,
    WXG_K_F2 halfSize,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration
) {
    if (!(chromaticAberration > 1e-4f) || !(refractionHeight > 1e-4f) || !(refractionAmount > 1e-4f))
        return 0.f;
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float depth0 = WXG_K_MAX(-sd0, 0.f);
    float pressScale = WXG_K_SATURATE(WXG_K_MIN(refractionHeight / 4.f, refractionAmount / 6.f));
    float dispScale = (chromaticAberration / (1.f + 0.08f * WXG_K_ABS(chromaticAberration))) * pressScale;
    float ringW = WXG_K_MAX(0.55f * minHalf, 3.f);
    float ringU = WXG_K_SATURATE(1.f - depth0 / ringW);
    float ringEnv = ringU * (0.42f + 0.58f * ringU);
    float baseShift = 1.05f * dispScale * ringEnv;
    float refractShift = (-d0) * (0.095f * dispScale);
    return WXG_K_MIN(baseShift + refractShift, 5.2f);
}

/* Compatibility wrapper returning the central ray and +1 spectral offset. */
static inline void WXGKyantLensDisplace(
    WXG_K_F2 coord,
    WXG_K_F2 center,
    WXG_K_F2 halfSize,
    float radius,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration,
    float depthEffect,
    WXG_K_OUT WXG_K_F2 *outRefracted,
    WXG_K_OUT WXG_K_F2 *outDispersed,
    WXG_K_OUT float *outSd
) {
    WXG_K_F2 centered = WXG_K_MAKE2(coord.x - center.x, coord.y - center.y);
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float r = WXGOClamp(radius, 0.f, minHalf);
    if (outSd) *outSd = WXGKyantSdRoundedRect(centered, halfSize, r);
    WXG_K_F2 central = coord;
    WXG_K_F2 redRay = WXGKyantSpectralRay(
        coord, center, halfSize, r, refractionHeight, refractionAmount,
        chromaticAberration, depthEffect, 0.f, 0.f, 1.f, &central);
    if (outRefracted) *outRefracted = central;
    if (outDispersed) *outDispersed = WXG_K_MAKE2(redRay.x - central.x, redRay.y - central.y);
}

/* 7-wavelength spectral tap offsets: k = 0..6 -> +1, +2/3, +1/3, 0, -1/3, -2/3, -1 */
static inline float WXGKyantSpectralOffset(int k) {
    return 1.f - (float)k / 3.f;
}

/* Color-neutral RGB spectral weights for 7-tap native backdrop (sum strictly to 1.0). */
static inline WXG_K_F3 WXGKyantSpectralRGBWeight(int k) {
    if (k == 0) return WXG_K_MAKE3(1.f / 3.5f, 0.f, 0.f);          /* red */
    if (k == 1) return WXG_K_MAKE3(1.f / 3.5f, 1.f / 7.f, 0.f);    /* orange */
    if (k == 2) return WXG_K_MAKE3(1.f / 3.5f, 1.f / 3.5f, 0.f);   /* yellow */
    if (k == 3) return WXG_K_MAKE3(0.f, 1.f / 3.5f, 0.f);          /* green */
    if (k == 4) return WXG_K_MAKE3(0.f, 1.f / 3.5f, 1.f / 3.f);    /* cyan */
    if (k == 5) return WXG_K_MAKE3(0.f, 0.f, 1.f / 3.f);           /* blue */
    return WXG_K_MAKE3(1.f / 7.f, 0.f, 1.f / 3.f);                 /* purple */
}

/* 15-wavelength spectral tap offsets & neutral RGB weights for the Metal glyph
   overlay (k = 0..14 -> +1 .. -1; each RGB channel sums strictly to 1.0). */
#define WXG_KYANT_GLYPH_TAPS 15
static inline float WXGKyantGlyphSpectralOffset(int k) {
    return 1.f - (float)k / 7.f;
}
static inline WXG_K_F3 WXGKyantGlyphSpectralRGBWeight(int k) {
    float t = 1.f - (float)k / 7.f;
    float r = WXG_K_SATURATE(t * 1.4f + 0.3f) + 0.25f * WXG_K_SATURATE((-t - 0.55f) / 0.45f);
    float g = WXG_K_SATURATE(1.f - WXG_K_ABS(t * 1.35f));
    float b = WXG_K_SATURATE(-t * 1.4f + 0.3f);
    return WXG_K_MAKE3(r * (1.f / 7.0238095f), g * (1.f / 5.2142857f), b * (1.f / 6.5f));
}

#ifndef __METAL_VERSION__
static inline void WXGKyantMeshSource(
    float px, float py,
    float width, float height,
    float radius,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration,
    float spectralT,
    float *sx, float *sy
) {
    WXG_K_F2 halfSize = WXG_K_MAKE2(width * 0.5f, height * 0.5f);
    float r = radius > 0.f ? radius : WXG_K_MIN(halfSize.x, halfSize.y);
    WXG_K_F2 ray = WXGKyantSpectralRay(
        WXG_K_MAKE2(px, py),
        halfSize,
        halfSize,
        r,
        refractionHeight,
        refractionAmount,
        chromaticAberration,
        0.f,
        0.f,
        0.f,
        spectralT,
        NULL
    );
    *sx = ray.x;
    *sy = ray.y;
}
#endif

#endif /* WXG_KYANT_OPTICS_H */
