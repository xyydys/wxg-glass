#ifndef WXG_KYANT_OPTICS_H
#define WXG_KYANT_OPTICS_H

#include "WXGLensOptics.h"

/* Kyant AndroidLiquidGlass (Backdrop, Apache-2.0, upstream eb4a0ea2) optics
   cleanly integrated for FIX135 main continuous dock (C + Metal shared).
   R12 restores R8's tapered crown refraction and 7-tap continuous spectrum
   for direct control inside the standalone pureDock module. */
#define WXG_LENS_KYANT 2000.f
#define WXG_LENS_KYANT_FLAT 2100.f
#define WXG_LENS_PURE 3000.f
#define WXG_KYANT_SPECTRAL_TAPS 7
static inline int WXGLensPureCode(float w) { return w >= 2500.f; }
static inline int WXGLensKyantCode(float w) { return w >= 1500.f && w < 2500.f; }
static inline int WXGLensKyantFlatCode(float w) { return w >= 2050.f && w < 2500.f; }

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

static inline float WXGKyantCircleMap(float x) {
    x = WXG_K_SATURATE(x);
    return 1.f - WXG_K_SQRT(WXG_K_MAX(0.f, 1.f - x * x));
}

static inline float WXGKyantSdRoundedRect(WXG_K_F2 coord, WXG_K_F2 halfSize, float radius) {
    float r = WXGOClamp(radius, 0.f, WXG_K_MIN(halfSize.x, halfSize.y));
    float cx = WXG_K_ABS(coord.x) - (halfSize.x - r);
    float cy = WXG_K_ABS(coord.y) - (halfSize.y - r);
    float ox = WXG_K_MAX(cx, 0.f), oy = WXG_K_MAX(cy, 0.f);
    float outside = WXG_K_SQRT(ox * ox + oy * oy) - r;
    float inside = WXG_K_MIN(WXG_K_MAX(cx, cy), 0.f);
    return outside + inside;
}

static inline WXG_K_F2 WXGKyantGradSdRoundedRect(WXG_K_F2 coord, WXG_K_F2 halfSize, float radius) {
    float minH = WXG_K_MIN(halfSize.x, halfSize.y);
    float r = WXGOClamp(radius, 0.f, minH);
    float cx = WXG_K_ABS(coord.x) - (halfSize.x - r);
    float cy = WXG_K_ABS(coord.y) - (halfSize.y - r);
    WXG_K_F2 s = WXG_K_SIGN(coord);
    WXG_K_F2 g;
    if (cx >= 0.f || cy >= 0.f) {
        float mx = WXG_K_MAX(cx, 0.f), my = WXG_K_MAX(cy, 0.f);
        float len = WXG_K_SQRT(mx * mx + my * my);
        if (!(len > 1e-6f)) return WXG_K_MAKE2(0.f, 0.f);
        g = WXG_K_MAKE2(s.x * mx / len, s.y * my / len);
    } else {
        float gradX = cy <= cx ? 1.f : 0.f;
        g = WXG_K_MAKE2(s.x * gradX, s.y * (1.f - gradX));
    }
    /* Match Apple's kCACornerCurveContinuous capsule arch: start curving the
       normal 16 deg before the Euclidean circle join so the top and bottom
       transition smoothly into the rounded ends without a flat knee. */
    if (r >= minH - 1e-3f && halfSize.x > halfSize.y + 1.f) {
        float straight = halfSize.x - r;
        float ax = WXG_K_ABS(coord.x), ay = WXG_K_ABS(coord.y);
        if (ax < straight && ay > 0.35f * r) {
            float u = WXG_K_SATURATE((ax - straight * 0.35f) / WXG_K_MAX(straight * 0.65f, 1.f));
            float tilt = 0.085f * u * u * (3.f - 2.f * u) * s.x;
            g.x += tilt;
            float gl = WXG_K_LENGTH(g);
            if (gl > 1e-6f) g = WXG_K_MAKE2(g.x / gl, g.y / gl);
        }
    }
    return g;
}

static inline WXGShapeSample WXGKyantBarField(float dx, float dy, float bw, float bh, float br, float barHalf) {
    if (br > 0.f) return WXGRoundedOpticalField(dx, dy, bw, bh, br);
    /* Fast exact straight-middle path: inside the -24 deg straight-side cone where
       WXGContinuousCorrection returns 0 (along < -0.4452 * across), capsule distance
       and normal depend purely on dy with zero trig. */
    float ady = WXG_K_ABS(dy);
    if (bw >= bh && (WXG_K_ABS(dx) - (bw * .5f - barHalf)) < -.4453f * ady) {
        WXGShapeSample out = {ady - barHalf, 0.f, ady > .0001f ? (dy < 0.f ? -1.f : 1.f) : 0.f};
        return out;
    }
    return WXGCapsuleOpticalField(dx, dy, bw, bh);
}

/* Inner-bar inverse mapping for the native backdrop mesh and Metal selection
   coverage. Glyphs have their own source coordinates.
   `extra` offsets the target inset (0 keeps the fixed bodyPinch inset);
   `depthPad` offsets the lens SDF depth test so vertical elastic squash never
   collapses the inset ramp during fast horizontal drags;
   `flat > 0.5` skips the along-bar ramp for a strictly uniform inner bar;
   `flat < -0.5` preserves legacy R4 WXGMeshShrinkBar parity for KyantSceneMapTests. */
static inline WXG_K_F2 WXGKyantSceneSourceDepthFlat(WXG_K_F2 source,WXG_K_F2 centralRay,
    WXG_K_F2 lensCenter,WXG_K_F2 lensSize,float lensRadius,
    WXG_K_F2 barOrigin,WXG_K_F2 barSize,float barRadius,
    float press,float pinch,float extra,float depthPad,float zoom,float flat) {
    if(!(press>0.f) || !(barSize.x>2.f && barSize.y>2.f))return source;
    float barHalf=WXG_K_MIN(barSize.x,barSize.y)*.5f;
    float bx=barOrigin.x+barSize.x*.5f,by=barOrigin.y+barSize.y*.5f;
    WXGShapeSample b=WXGKyantBarField(centralRay.x-bx,centralRay.y-by,barSize.x,barSize.y,barRadius,barHalf);
    float ox=centralRay.x-b.nx*b.distance,oy=centralRay.y-b.ny*b.distance;
    float maxPinch=flat<-.5f?.30f:.58f;
    float full=barSize.y*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(pinch,0.f,maxPinch)+extra;
    float absFull=WXG_K_ABS(full);
    float inset=full;
    if(!(flat>.5f)) {
        WXGShapeSample l=lensRadius>0.f?WXGRoundedOpticalField(ox-lensCenter.x,oy-lensCenter.y,lensSize.x,lensSize.y,lensRadius)
            :WXGCapsuleOpticalField(ox-lensCenter.x,oy-lensCenter.y,lensSize.x,lensSize.y);
        float along=WXGLensDepthAlongBar(l.distance-depthPad,-b.ny,b.nx,l.nx,l.ny);
        if(flat<-.5f) {
            float u=absFull>1e-4f?WXGOClamp(along/(2.f*absFull),0.f,1.f):0.f;
            inset=full*u*(2.f-u);
        } else {
            /* C2-smooth cubic ramp over 1.80*full: slims down the solid refracted
               neck at the four crossings to open more translucent aurora space
               while remaining round, continuous, and hitting 1.000 at x = 0. */
            float u=absFull>1e-4f?WXGOClamp(along/(1.80f*absFull),0.f,1.f):0.f;
            float om=1.f-u;
            float ramp=1.f-om*om*(1.f-.35f*u);
            inset=full*ramp;
        }
    }
    /* When the lens wraps past the bar's left or right end (endWrap ~ 8.4 pt >
       vertical overhang ~ 4.0 pt), compensate the extra horizontal overhang
       along b.nx^2 so the shrunk inner bar's end cap stays concentric with the
       lens's continuous rounded corner at a uniform radial gap. */
    if(!(flat<-.5f) && WXG_K_ABS(b.nx)>.02f && absFull>1e-4f) {
        float overhangY=WXG_K_MAX(0.f,(lensSize.y-barSize.y)*.5f);
        float lensLeft=lensCenter.x-lensSize.x*.5f,lensRight=lensCenter.x+lensSize.x*.5f;
        float overEnd=b.nx<0.f?(barOrigin.x-lensLeft):(lensRight-(barOrigin.x+barSize.x));
        float extraEnd=WXGOClamp(overEnd-overhangY,0.f,absFull*.82f);
        if(extraEnd>0.f)inset-=extraEnd*(b.nx*b.nx)*(inset/full);
    }
    float h=(ox-lensCenter.x)*b.nx+(oy-lensCenter.y)*b.ny;
    float dz=WXGOClamp(h-(h-inset)/WXG_K_MAX(zoom,.01f),extra<0.f?-barHalf*.5f:0.f,barHalf*.9f);
    if(!(WXG_K_ABS(dz)>0.f))return source;
    WXGShapeSample q=WXGKyantBarField(source.x-bx,source.y-by,barSize.x,barSize.y,barRadius,barHalf);
    float t=q.distance,t2=t<-dz?-barHalf+(t+barHalf)*barHalf/(barHalf-dz):t+dz;
    if(t<-barHalf)t2=t;
    return WXG_K_MAKE2(source.x+q.nx*(t2-t),source.y+q.ny*(t2-t));
}
static inline WXG_K_F2 WXGKyantSceneSourceDepth(WXG_K_F2 source,WXG_K_F2 centralRay,
    WXG_K_F2 lensCenter,WXG_K_F2 lensSize,float lensRadius,
    WXG_K_F2 barOrigin,WXG_K_F2 barSize,float barRadius,
    float press,float pinch,float extra,float depthPad,float zoom) {
    return WXGKyantSceneSourceDepthFlat(source,centralRay,lensCenter,lensSize,lensRadius,
        barOrigin,barSize,barRadius,press,pinch,extra,depthPad,zoom,0.f);
}
static inline WXG_K_F2 WXGKyantSceneSource(WXG_K_F2 source,WXG_K_F2 centralRay,
    WXG_K_F2 lensCenter,WXG_K_F2 lensSize,float lensRadius,
    WXG_K_F2 barOrigin,WXG_K_F2 barSize,float barRadius,
    float press,float pinch,float extra,float zoom) {
    return WXGKyantSceneSourceDepthFlat(source,centralRay,lensCenter,lensSize,lensRadius,
        barOrigin,barSize,barRadius,press,pinch,extra,extra,zoom,-1.f);
}

static inline float WXGKyantEase(float x) {
    x=WXG_K_SATURATE(x);
    return x*x*(3.f-2.f*x);
}

/* iOS 26 measured crown target (band ~0.105*height, depth ~0.30*height),
   conservatively capped below the physical inner-bar gap (~9.5 pt) so even at
   extreme max refraction sliders (40 pt band / 50 pt depth) the outer lip and
   end wrap cleanly detach from the inner bar without bridging. */
static inline void WXGKyantCrownTarget(
    float minHalf,
    float refractionHeight,
    float refractionAmount,
    WXG_K_OUT float *outH,
    WXG_K_OUT float *outA
) {
    float hScale = WXGOClamp(refractionHeight / 18.f, 0.f, 1.20f);
    float aScale = WXGOClamp(refractionAmount / 26.f, 0.f, 1.35f);
    float hCrown = WXG_K_MIN(refractionHeight, 0.195f * minHalf * (0.60f + 0.40f * hScale));
    float aCrown = WXG_K_MIN(refractionAmount, 0.56f * minHalf * (0.58f + 0.42f * aScale));
    if (outH) *outH = hCrown;
    if (outA) *outA = aCrown;
}

/* Smooth elliptical taper from the four Kyant shoulders/ends (crownW -> 0)
   to the iOS 26 top/bottom apex (crownW -> 1, zero horizontal slope at x = 0),
   plus full end-tab wrap relaxation starting at sx = -0.08 so the top/bottom
   corners on the dock's end side never dip and bridge back to the bar. */
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
    float shoulder = ellipH * ellipH;
    float sx = centered.x / WXG_K_MAX(halfSize.x, 1.f);
    /* Reach crownW = 1.0 by |sx| = 0.24 on the wrapped end side so the
       top-right / bottom-right (or top-left / bottom-left) corners stay
       cleanly detached from the bar even at extreme refraction sliders. */
    float endW = WXG_K_MAX(endLeft * WXGKyantEase((-sx + 0.08f) / 0.32f),
                           endRight * WXGKyantEase((sx + 0.08f) / 0.32f));
    float crownW = WXG_K_MAX(elongated * (1.f - shoulder), endW);
    float hCrown = refractionHeight, aCrown = refractionAmount;
    WXGKyantCrownTarget(minHalf, refractionHeight, refractionAmount, &hCrown, &aCrown);
    if (outH) *outH = refractionHeight + crownW * (hCrown - refractionHeight);
    if (outA) *outA = refractionAmount + crownW * (aCrown - refractionAmount);
    if (outCrownW) *outCrownW = crownW;
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
    float d = WXGKyantCircleMap(1.f - (-sdClamped) / hEff) * (-aEff);
    if (outD) *outD = d;
    return WXG_K_MAKE2(coord.x + d * g.x, coord.y + d * g.y);
}

/* Compute the smooth, 4-quadrant-symmetric post-refraction aurora dispersion
   vector for a given point and central refraction sample:
   1. 100% 4-quadrant symmetry (|c0.x * c0.y| instead of signed c0.x * c0.y)
      eliminates the Top-Right / Bottom-Left zero-crossing pinch & disconnect.
   2. Post-refraction Cauchy + smooth cubic band envelope evaluated from the
      single lens surface (zero shifted sd=0 cusps, zero concentric rings).
   3. Strictly bounded within the active refraction band (-sd0 < hEff) so the
      shrunk inner bar's straight top/bottom borders remain 100% razor-sharp. */
static inline WXG_K_F2 WXGKyantAuroraDispersionVec(
    WXG_K_F2 centered,
    WXG_K_F2 halfSize,
    float refractionHeight,
    float refractionAmount,
    float chromaticAberration,
    float d0,
    WXG_K_F2 g0,
    float crown0,
    float sd0
) {
    if (!(chromaticAberration > 1e-4f) || !(refractionHeight > 1e-4f) ||
        !(refractionAmount > 1e-4f) || !(WXG_K_ABS(d0) > 1e-5f)) {
        return WXG_K_MAKE2(0.f, 0.f);
    }
    float minHalf = WXG_K_MIN(halfSize.x, halfSize.y);
    float hCrown = refractionHeight, aCrown = refractionAmount;
    WXGKyantCrownTarget(minHalf, refractionHeight, refractionAmount, &hCrown, &aCrown);
    float hEff = WXG_K_MAX(refractionHeight + crown0 * (hCrown - refractionHeight), 0.5f);
    float depth0 = WXG_K_MAX(-sd0, 0.f);
    if (depth0 >= hEff) return WXG_K_MAKE2(0.f, 0.f);

    float pressScale = WXG_K_SATURATE(WXG_K_MIN(refractionHeight / 4.f, refractionAmount / 6.f));
    float dispNorm = (chromaticAberration / (1.f + 0.14f * WXG_K_ABS(chromaticAberration))) * pressScale;
    float bandU = WXG_K_SATURATE(1.f - depth0 / hEff);
    float bandEnv = WXG_K_SQRT(bandU) * (0.55f + 0.45f * bandU);
    float denom = WXG_K_MAX(halfSize.x * halfSize.y, 1.f);
    float cornerMag = (WXG_K_ABS(centered.x) * WXG_K_ABS(centered.y)) / denom;
    float shoulderFactor = 1.f - crown0;

    float cauchyShift = (-d0) * (0.195f * dispNorm) * (0.50f + 0.70f * shoulderFactor + 0.65f * cornerMag);
    float ringShift = 1.25f * dispNorm * bandEnv * (0.70f + 0.50f * shoulderFactor + 1.05f * cornerMag);
    float totalShift = WXG_K_MIN(cauchyShift + ringShift, 0.56f * WXG_K_MAX(WXG_K_ABS(d0), 2.0f));
    return WXG_K_MAKE2(-g0.x * totalShift, -g0.y * totalShift);
}

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
    if (!(WXG_K_ABS(spectralT) > 1e-6f)) return central;
    WXG_K_F2 c0 = WXG_K_MAKE2(coord.x - center.x, coord.y - center.y);
    WXG_K_F2 disp = WXGKyantAuroraDispersionVec(
        c0, halfSize, refractionHeight, refractionAmount, chromaticAberration,
        d0, g0, crown0, sd0);
    return WXG_K_MAKE2(central.x + disp.x * spectralT,
                       central.y + disp.y * spectralT);
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

/* Smooth overlapping Gaussian-bell aurora RGB weights (sigma=0.32) for the 7-tap
   backdrop: richer translucent aurora hues without hard step-function band edges;
   each channel sums strictly to 1.0 so the un-dispersed interior stays neutral. */
static inline WXG_K_F3 WXGKyantSpectralRGBWeight(int k) {
    if (k == 0) return WXG_K_MAKE3(0.185904f, 0.003149f, 0.000001f); /* deep red */
    if (k == 1) return WXG_K_MAKE3(0.372290f, 0.047448f, 0.000133f); /* warm amber-gold */
    if (k == 2) return WXG_K_MAKE3(0.251905f, 0.241591f, 0.005100f); /* golden lime */
    if (k == 3) return WXG_K_MAKE3(0.057670f, 0.415624f, 0.066025f); /* aurora emerald-mint */
    if (k == 4) return WXG_K_MAKE3(0.007862f, 0.241591f, 0.288797f); /* turquoise-cyan */
    if (k == 5) return WXG_K_MAKE3(0.035493f, 0.047448f, 0.426814f); /* sapphire-blue */
    return WXG_K_MAKE3(0.088877f, 0.003149f, 0.213130f);             /* violet-magenta */
}

/* 15-wavelength continuous aurora tap offsets & neutral RGB weights for the
   Metal glyph/selection overlay (k = 0..14 -> +1 .. -1; each channel sums to 1.0). */
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
