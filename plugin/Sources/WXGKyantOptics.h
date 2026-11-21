#ifndef WXG_KYANT_OPTICS_H
#define WXG_KYANT_OPTICS_H

#include "WXGLensOptics.h"

/* Kyant AndroidLiquidGlass (Backdrop, Apache-2.0, upstream eb4a0ea2) optics
   cleanly integrated for FIX135 main continuous dock (C + Metal shared). */
#define WXG_LENS_KYANT 2000.f
static inline int WXGLensKyantCode(float w) { return w >= 1500.f; }

#ifdef __METAL_VERSION__
#define WXG_K_OUT thread
#define WXG_K_NULL nullptr
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
#define WXG_K_NULL NULL
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

/* Real iOS 26 glassBackground quarter-circle map (eps = 0.004): sharp ethereal
   outer mirrored bevel without strict infinity at u = 1. */
static inline float WXGKyantSmoothCircleMap(float x) {
    x = WXG_K_SATURATE(x);
    return (1.f - WXG_K_SQRT(WXG_K_MAX(0.004f, 1.f - 0.996f * x * x))) * (1.f / (1.f - 0.06324555f));
}

/* Slightly softer quarter-circle map (eps = 0.025) for ContentLensingView icons
   so 15-tap pre-refraction rainbow stays silky smooth across both folded and
   direct sides even on thin CJK text strokes. */
static inline float WXGKyantIconCircleMap(float x) {
    x = WXG_K_SATURATE(x);
    return (1.f - WXG_K_SQRT(WXG_K_MAX(0.025f, 1.f - 0.975f * x * x))) * (1.f / (1.f - 0.15811388f));
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

/* CASDFElementLayer.gradientOvalization: gently blends the capsule SDF normal
   toward the elliptical radial direction from center, reproducing the convex
   droplet grid bending captured on iOS 26.6 (f00266 / f00357). */
static inline WXG_K_F2 WXGKyantOvalizedGrad(WXG_K_F2 centered, WXG_K_F2 halfSize, float radius, float oval) {
    WXG_K_F2 g = WXGKyantGradSdRoundedRect(centered, halfSize, radius);
    if (oval > 1e-4f) {
        float ex = centered.x / WXG_K_MAX(halfSize.x, 1.f);
        float ey = centered.y / WXG_K_MAX(halfSize.y, 1.f);
        float el = WXG_K_SQRT(ex * ex + ey * ey);
        if (el > 1e-5f) {
            g.x += oval * (ex / el);
            g.y += oval * (ey / el);
            float gl = WXG_K_LENGTH(g);
            if (gl > 1e-6f) { g.x /= gl; g.y /= gl; }
        }
    }
    return g;
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

/* Real iOS 26 ClearGlassView (glassBackground) uniform bevel proportions
   verified on iOS 26.6 GlassProbe 2 (f00224/f00241/f00266/f00337/f00357) &
   IMG_9424: ONE uniform ordinary liquid-glass bevel all around the capsule
   (band = 0.105 * shortSide = 7.35 pt, depth = 0.31 * shortSide = 21.7 pt on
   a 70 pt lifted lens), scaled proportionally with the user's refraction sliders.
   Eliminates Kyant's fat 18 pt fleshy neck bulge at the 4 corners so the inner
   bar stays razor-sharp until the short, crisp ~7 pt liquid-adhesion crossing. */
static inline void WXGKyantCrownTarget(
    float minHalf,
    float refractionHeight,
    float refractionAmount,
    WXG_K_OUT float *outH,
    WXG_K_OUT float *outA
) {
    float shortSide = 2.f * minHalf;
    float hScale = WXGOClamp(refractionHeight / 18.f, 0.f, 2.2f);
    float aScale = WXGOClamp(refractionAmount / 26.f, 0.f, 2.2f);
    float hBg = WXG_K_MIN(refractionHeight, 0.105f * shortSide * hScale);
    float aBg = WXG_K_MIN(refractionAmount, 0.31f * shortSide * aScale);
    if (outH) *outH = hBg;
    if (outA) *outA = aBg;
}

/* Real iOS 26 ContentLensingView (liftedContentWarpWrapper) target for selected
   icons and titles (dumped directly from CASDFGlassDisplacementEffect in
   GlassProbe 2: height = 0.20 * shortSide = 14 pt, depth = 0.26 * shortSide). */
static inline void WXGKyantIconTarget(
    float minHalf,
    float refractionHeight,
    float refractionAmount,
    WXG_K_OUT float *outH,
    WXG_K_OUT float *outA
) {
    float shortSide = 2.f * minHalf;
    float hScale = WXGOClamp(refractionHeight / 18.f, 0.f, 2.2f);
    float aScale = WXGOClamp(refractionAmount / 26.f, 0.f, 2.2f);
    float hIc = WXG_K_MIN(refractionHeight, 0.20f * shortSide * hScale);
    float aIc = WXG_K_MIN(refractionAmount, 0.26f * shortSide * aScale);
    if (outH) *outH = hIc;
    if (outA) *outA = aIc;
}

/* Uniform iOS 26 ClearGlassView band wrapper (retains signature for callers/tests). */
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
    (void)centered;
    (void)endLeft;
    (void)endRight;
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float hBg = 0.f, aBg = 0.f;
    WXGKyantCrownTarget(minHalf, refractionHeight, refractionAmount, &hBg, &aBg);
    if (outH) *outH = hBg;
    if (outA) *outA = aBg;
    if (outCrownW) *outCrownW = 1.f;
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
    float oval = depthEffect > 1e-4f ? depthEffect : 0.22f;
    WXG_K_F2 g = WXGKyantOvalizedGrad(centered, halfSize, r, oval);
    float hEff = 0.f, aEff = 0.f, crownW = 1.f;
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

/* Real iOS 26 ContentLensingView refraction for selected icons/titles/badges. */
static inline WXG_K_F2 WXGKyantIconRefractPoint(
    WXG_K_F2 coord,
    WXG_K_F2 center,
    WXG_K_F2 halfSize,
    float radius,
    float refractionHeight,
    float refractionAmount,
    WXG_K_OUT float *outD,
    WXG_K_OUT WXG_K_F2 *outG,
    WXG_K_OUT float *outSd
) {
    WXG_K_F2 centered = WXG_K_MAKE2(coord.x - center.x, coord.y - center.y);
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float r = WXGOClamp(radius, 0.f, minHalf);
    float sd = WXGKyantSdRoundedRect(centered, halfSize, r);
    WXG_K_F2 g = WXGKyantOvalizedGrad(centered, halfSize, r, 0.35f);
    float hEff = 0.f, aEff = 0.f;
    WXGKyantIconTarget(minHalf, refractionHeight, refractionAmount, &hEff, &aEff);
    if (outG) *outG = g;
    if (outSd) *outSd = sd;
    if (!(hEff > 1e-4f) || !(aEff > 1e-4f) || -sd >= hEff) {
        if (outD) *outD = 0.f;
        return coord;
    }
    float sdClamped = WXG_K_MIN(sd, 0.f);
    float d = WXGKyantIconCircleMap(1.f - (-sdClamped) / hEff) * (-aEff);
    if (outD) *outD = d;
    return WXG_K_MAKE2(coord.x + d * g.x, coord.y + d * g.y);
}

/* Real iOS 26 glassForeground dispersion over uniform glassBackground:
   - 100% 4-quadrant symmetric with ZERO blur on the inner bar or clear gap.
   - Steep ringU^2.5 envelope keeps the inner bar edge (d >= 7.5 pt) razor-sharp
     while fanning the outer ~7 pt bevel and short 4-corner crossing zone into
     a vivid, ethereal, translucent rainbow that scales linearly with the slider. */
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
    float shortSide = 2.f * minHalf;
    float hBg = 0.f, aBg = 0.f;
    WXGKyantCrownTarget(minHalf, refractionHeight, refractionAmount, &hBg, &aBg);
    float depth0 = WXG_K_MAX(-sd0, 0.f);
    float ringW = WXG_K_MAX(0.18f * shortSide, hBg * 1.35f);
    float ringU = WXG_K_SATURATE(1.f - depth0 / WXG_K_MAX(ringW, 1.f));
    if (!(ringU > 1e-4f)) return central;

    float pressScale = WXG_K_SATURATE(WXG_K_MIN(refractionHeight / 4.f, refractionAmount / 6.f));
    float env = ringU * ringU * WXG_K_SQRT(ringU);
    float shift = 0.48f * chromaticAberration * pressScale * env;
    WXG_K_F2 pShifted = WXG_K_MAKE2(
        coord.x + spectralT * shift * g0.x,
        coord.y + spectralT * shift * g0.y
    );

    float dTap = 0.f, crownTap = 0.f, sdTap = 0.f;
    WXG_K_F2 gTap = WXG_K_MAKE2(0.f, 0.f);
    WXG_K_F2 rayTap = WXGKyantRefractPoint(
        pShifted, center, halfSize, radius, refractionHeight, refractionAmount,
        depthEffect, endLeft, endRight, &dTap, &gTap, &crownTap, &sdTap);

    /* Constructive Cauchy refractive dispersion strictly inside the active bevel
       (zero outside hBg -> inner bar edge stays 100% untouched and crisp!). */
    float cauchy = (-dTap) * (0.065f * chromaticAberration * pressScale);
    cauchy = WXG_K_MIN(cauchy, 0.42f * WXG_K_ABS(dTap));
    return WXG_K_MAKE2(rayTap.x - gTap.x * cauchy * spectralT,
                       rayTap.y - gTap.y * cauchy * spectralT);
}

/* Pre-refraction 15-tap glassForeground over ContentLensingView: reproduces the
   vivid symmetric cyan + yellow/orange/red icon & text rainbow seen in real
   iOS 26 GlassProbe frames (f00241 / f00266 / f00357 / IMG_9388). */
static inline float WXGKyantGlyphPreShift(
    float sd0,
    WXG_K_F2 halfSize,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration
) {
    if (!(chromaticAberration > 1e-4f) || !(refractionHeight > 1e-4f) || !(refractionAmount > 1e-4f)) return 0.f;
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float hIcon = 0.f, aIcon = 0.f;
    WXGKyantIconTarget(minHalf, refractionHeight, refractionAmount, &hIcon, &aIcon);
    float depth0 = WXG_K_MAX(-sd0, 0.f);
    float ringW = WXG_K_MAX(hIcon * 1.15f, 3.f);
    float ringU = WXG_K_SATURATE(1.f - depth0 / ringW);
    if (!(ringU > 1e-4f)) return 0.f;
    float pressScale = WXG_K_SATURATE(WXG_K_MIN(refractionHeight / 4.f, refractionAmount / 6.f));
    return WXG_K_MIN(0.85f * chromaticAberration * pressScale * ringU * ringU, 3.6f);
}

static inline WXG_K_F2 WXGKyantGlyphSpectralRay(
    WXG_K_F2 coord,
    WXG_K_F2 center,
    WXG_K_F2 halfSize,
    float radius,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration,
    float spectralT,
    WXG_K_OUT WXG_K_F2 *outCentralRay
) {
    float d0 = 0.f, sd0 = 0.f;
    WXG_K_F2 g0 = WXG_K_MAKE2(0.f, 0.f);
    WXG_K_F2 central = WXGKyantIconRefractPoint(
        coord, center, halfSize, radius, refractionHeight, refractionAmount,
        &d0, &g0, &sd0);
    if (outCentralRay) *outCentralRay = central;
    if (!(WXG_K_ABS(spectralT) > 1e-6f)) return central;
    float shift = WXGKyantGlyphPreShift(sd0, halfSize, refractionHeight, refractionAmount, chromaticAberration);
    if (!(shift > 1e-4f)) return central;
    WXG_K_F2 pShifted = WXG_K_MAKE2(
        coord.x + spectralT * shift * g0.x,
        coord.y + spectralT * shift * g0.y
    );
    return WXGKyantIconRefractPoint(
        pShifted, center, halfSize, radius, refractionHeight, refractionAmount,
        WXG_K_NULL, WXG_K_NULL, WXG_K_NULL);
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

/* 11-wavelength unblurred spectral stack for the native backdrop:
   k = 0..10 -> +1.0 .. -1.0; smooth continuous rainbow with ZERO blur on the
   inner bar edge! Each RGB channel sums strictly to 1.0. */
#define WXG_KYANT_SPECTRAL_TAPS 11
static inline float WXGKyantSpectralOffset(int k) {
    return 1.f - (float)k * 0.2f;
}
static inline WXG_K_F3 WXGKyantSpectralRGBWeight(int k) {
    float t = 1.f - (float)k * 0.2f;
    float r = WXG_K_SATURATE(t * 1.4f + 0.3f) + 0.25f * WXG_K_SATURATE((-t - 0.55f) / 0.45f);
    float g = WXG_K_SATURATE(1.f - WXG_K_ABS(t * 1.35f));
    float b = WXG_K_SATURATE(-t * 1.4f + 0.3f);
    return WXG_K_MAKE3(r * (1.f / 5.1766667f), g * (1.f / 3.76f), b * (1.f / 4.76f));
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
