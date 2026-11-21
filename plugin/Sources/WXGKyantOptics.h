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
    float r = WXGOClamp(radius, 0.f, WXG_K_MIN(halfSize.x, halfSize.y));
    float cx = WXG_K_ABS(coord.x) - (halfSize.x - r);
    float cy = WXG_K_ABS(coord.y) - (halfSize.y - r);
    WXG_K_F2 s = WXG_K_SIGN(coord);
    if (cx >= 0.f || cy >= 0.f) {
        float mx=WXG_K_MAX(cx,0.f),my=WXG_K_MAX(cy,0.f);
        float len=WXG_K_SQRT(mx*mx+my*my);
        if(!(len>1e-6f))return WXG_K_MAKE2(0.f,0.f);
        return WXG_K_MAKE2(s.x*mx/len,s.y*my/len);
    } else {
        float gradX = cy <= cx ? 1.f : 0.f;
        return WXG_K_MAKE2(s.x * gradX, s.y * (1.f - gradX));
    }
}


/* Inner-bar inverse mapping for the native backdrop mesh and Metal selection
   coverage. Glyphs have their own source coordinates. */
static inline WXGShapeSample WXGKyantBarField(WXG_K_F2 p,WXG_K_F2 origin,WXG_K_F2 size,float radius) {
    float x=p.x-(origin.x+size.x*.5f),y=p.y-(origin.y+size.y*.5f);
    if(radius>0.f) return WXGRoundedOpticalField(x,y,size.x,size.y,radius);
    // Exact straight segment of WXGCapsuleOpticalField. The continuous
    // corner starts 24 degrees before the circular join (WXGContinuousCorrection).
    float ay=WXG_K_ABS(y);
    if(size.x>=size.y && WXG_K_ABS(x)-(size.x-size.y)*.5f < -.4452f*ay) {
        WXGShapeSample flat;
        flat.distance=ay-size.y*.5f; flat.nx=0.f; flat.ny=y/WXG_K_MAX(ay,.0001f);
        return flat;
    }
    return WXGCapsuleOpticalField(x,y,size.x,size.y);
}

static inline float WXGKyantSceneInset(WXG_K_F2 centralRay,WXG_K_F2 lensCenter,WXG_K_F2 lensSize,
    float lensRadius,WXG_K_F2 barOrigin,WXG_K_F2 barSize,float barRadius,
    float press,float pinch,float extra,float zoom) {
    if(!(press>0.f) || !(barSize.x>2.f && barSize.y>2.f)) return 0.f;
    float barHalf=WXG_K_MIN(barSize.x,barSize.y)*.5f;
    WXGShapeSample b=WXGKyantBarField(centralRay,barOrigin,barSize,barRadius);
    float ox=centralRay.x-b.nx*b.distance,oy=centralRay.y-b.ny*b.distance;
    WXGShapeSample l=lensRadius>0.f?WXGRoundedOpticalField(ox-lensCenter.x,oy-lensCenter.y,lensSize.x,lensSize.y,lensRadius)
        :WXGCapsuleOpticalField(ox-lensCenter.x,oy-lensCenter.y,lensSize.x,lensSize.y);
    float full=barSize.y*.5f*WXGOClamp(press,0.f,1.f)*WXGOClamp(pinch,0.f,.30f)+extra;
    float along=WXGLensDepthAlongBar(l.distance-extra,-b.ny,b.nx,l.nx,l.ny);
    float absFull=WXG_K_ABS(full),ramp=absFull>1e-4f?WXGOClamp(along/(2.f*absFull),0.f,1.f):0.f;
    float inset=full*ramp*(2.f-ramp);
    float h=(ox-lensCenter.x)*b.nx+(oy-lensCenter.y)*b.ny;
    return WXGOClamp(h-(h-inset)/WXG_K_MAX(zoom,.01f),extra<0.f?-barHalf*.5f:0.f,barHalf*.9f);
}

static inline WXG_K_F2 WXGKyantInsetSource(WXG_K_F2 source,WXG_K_F2 origin,WXG_K_F2 size,float radius,float dz) {
    if(!(WXG_K_ABS(dz)>0.f))return source;
    WXGShapeSample q=WXGKyantBarField(source,origin,size,radius);
    float barHalf=WXG_K_MIN(size.x,size.y)*.5f;
    float t=q.distance,t2=t<-dz?-barHalf+(t+barHalf)*barHalf/(barHalf-dz):t+dz;
    if(t<-barHalf)t2=t;
    return WXG_K_MAKE2(source.x+q.nx*(t2-t),source.y+q.ny*(t2-t));
}

static inline WXG_K_F2 WXGKyantSceneSource(WXG_K_F2 source,WXG_K_F2 centralRay,
    WXG_K_F2 lensCenter,WXG_K_F2 lensSize,float lensRadius,WXG_K_F2 barOrigin,WXG_K_F2 barSize,
    float barRadius,float press,float pinch,float extra,float zoom) {
    float dz=WXGKyantSceneInset(centralRay,lensCenter,lensSize,lensRadius,barOrigin,barSize,barRadius,press,pinch,extra,zoom);
    return WXGKyantInsetSource(source,barOrigin,barSize,barRadius,dz);
}

static inline float WXGKyantEase(float x) {
    x=WXG_K_SATURATE(x);
    return x*x*(3.f-2.f*x);
}

/* The outer lens and the inset bar have different outlines. Evaluate this
   second interface in the source image, after zoom and the inverse inset.
   Every wavelength sees the same surface and bends along its one normal. */
typedef struct {
    WXG_K_F2 center,normal;
    float weight,bend,spread;
} WXGKyantMaterialBand;

static inline WXGKyantMaterialBand WXGKyantMaterialProfile(WXG_K_F2 center,WXG_K_F2 lensSize,
    WXG_K_F2 barOrigin,WXG_K_F2 barSize,float radius,float height,float amount,float dispersion) {
    WXGKyantMaterialBand band;
    band.center=center; band.normal=WXG_K_MAKE2(0.f,0.f);
    band.weight=0.f; band.bend=0.f; band.spread=0.f;
    if (!(height>0.f && amount>0.f && barSize.x>2.f && barSize.y>2.f)) return band;
    float halfHeight=lensSize.y*.5f;
    float elongated=WXGKyantEase((lensSize.x-lensSize.y)/WXG_K_MAX(.15f*lensSize.y,1e-4f));
    if (!(halfHeight>0.f && elongated>0.f)) return band;
    WXGShapeSample field=WXGKyantBarField(center,barOrigin,barSize,radius);
    float reach=.8f*height*halfHeight/(halfHeight+.5f*height);
    float t=WXG_K_ABS(field.distance)/reach;
    if (t>=1.f) return band;
    // A C1 strip follows the actual top/bottom material edge. The bound
    // 1.5 * .50 < 1 leaves room for the outer lens mapping across a straight edge.
    band.weight=elongated*field.ny*field.ny*(1.f-WXGKyantEase(t));
    band.normal=WXG_K_MAKE2(field.nx,field.ny);
    float amplitude=.50f*reach*amount/(amount+.55f*halfHeight);
    band.bend=.28f*amplitude;
    band.spread=.72f*amplitude*WXG_K_SATURATE(1.8f*dispersion/(4.f+WXG_K_MAX(0.f,dispersion)));
    return band;
}

static inline WXG_K_F2 WXGKyantMaterialSample(WXG_K_F2 source,WXGKyantMaterialBand band,float wave) {
    if (!(band.weight>0.f)) return source;
    // Transition the normal component of the old spectral ray to the material
    // interface's ray. Its tangential component still follows the shoulder.
    float previous=(source.x-band.center.x)*band.normal.x+(source.y-band.center.y)*band.normal.y;
    float shift=band.weight*(band.bend+wave*band.spread-previous);
    return WXG_K_MAKE2(source.x+shift*band.normal.x,source.y+shift*band.normal.y);
}

/* Upstream Lens.kt + Shaders.kt refraction on the shoulders. On a wide dock
   lens the short top/bottom band should show each source row only once. */
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
    float sd = WXGKyantSdRoundedRect(centered, halfSize, r);
    if (outSd) *outSd = sd;
    if (!(refractionHeight > 1e-4f) || !(refractionAmount > 1e-4f) || -sd >= refractionHeight) {
        if (outRefracted) *outRefracted = coord;
        if (outDispersed) *outDispersed = WXG_K_MAKE2(0.f, 0.f);
        return;
    }
    float sdClamped = WXG_K_MIN(sd, 0.f);
    float d = WXGKyantCircleMap(1.f - (-sdClamped) / refractionHeight) * (-refractionAmount);
    float gradRadius = WXG_K_MIN(r * 1.5f, minHalf);
    WXG_K_F2 g = WXGKyantGradSdRoundedRect(centered, halfSize, gradRadius);
    if (depthEffect > 1e-4f) {
        WXG_K_F2 cn = WXG_K_NORMALIZE(centered);
        g = WXG_K_MAKE2(g.x + depthEffect * cn.x, g.y + depthEffect * cn.y);
    }
    float gl=WXG_K_LENGTH(g);
    g=gl>1e-6f?WXG_K_MAKE2(g.x/gl,g.y/gl):WXG_K_MAKE2(0.f,0.f);
    float denom = WXG_K_MAX(halfSize.x * halfSize.y, 1.f);
    float quadrant = (centered.x * centered.y) / denom;
    float spectralShift = d * chromaticAberration;
    // Fade out the specialisation as a squeezed capsule becomes round. Both
    // the press band and its thickness scale in the caller's units (pt / px).
    float elongated = WXGKyantEase((halfSize.x-halfSize.y)/WXG_K_MAX(.15f*halfSize.y,1e-4f));
    float crown = elongated * (1.f-WXGKyantEase((WXG_K_ABS(g.x)-.12f)/.58f));
    if (crown > 0.f) {
        float band = WXG_K_MIN(.25f*refractionHeight,.10f*minHalf);
        float u = WXG_K_SATURATE(1.f+sdClamped/WXG_K_MAX(band,1e-6f));
        // s(t)=t+m*(1-t/band)^2. Even at maximum dispersion the spectral
        // displacement slope stays below one throughout the straight band.
        float magnitude = .20f*band*refractionAmount/(refractionAmount+.20f*refractionHeight);
        float crownShift = -magnitude*u*u;
        float crownDispersion = chromaticAberration / (1.f+WXG_K_ABS(chromaticAberration));
        d=(1.f-crown)*d+crown*crownShift;
        spectralShift=(1.f-crown)*spectralShift+crown*crownShift*crownDispersion;
    }
    WXG_K_F2 shift = WXG_K_MAKE2(d * g.x, d * g.y);
    if (outRefracted) *outRefracted = WXG_K_MAKE2(coord.x + shift.x, coord.y + shift.y);
    if (outDispersed) {
        *outDispersed = WXG_K_MAKE2(g.x*spectralShift*quadrant,g.y*spectralShift*quadrant);
    }
}

/* 7-wavelength spectral tap offsets: k = 0..6 -> +1, +2/3, +1/3, 0, -1/3, -2/3, -1 */
static inline float WXGKyantSpectralOffset(int k) {
    return 1.f - (float)k / 3.f;
}

/* Color-neutral RGB spectral weights (each channel sums strictly to 1.0). */
static inline WXG_K_F3 WXGKyantSpectralRGBWeight(int k) {
    if (k == 0) return WXG_K_MAKE3(1.f / 3.5f, 0.f, 0.f);          /* red */
    if (k == 1) return WXG_K_MAKE3(1.f / 3.5f, 1.f / 7.f, 0.f);    /* orange */
    if (k == 2) return WXG_K_MAKE3(1.f / 3.5f, 1.f / 3.5f, 0.f);   /* yellow */
    if (k == 3) return WXG_K_MAKE3(0.f, 1.f / 3.5f, 0.f);          /* green */
    if (k == 4) return WXG_K_MAKE3(0.f, 1.f / 3.5f, 1.f / 3.f);    /* cyan */
    if (k == 5) return WXG_K_MAKE3(0.f, 0.f, 1.f / 3.f);           /* blue */
    return WXG_K_MAKE3(1.f / 7.f, 0.f, 1.f / 3.f);                 /* purple */
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
    WXG_K_F2 refracted, dispersed;
    WXGKyantLensDisplace(
        WXG_K_MAKE2(px, py),
        halfSize,
        halfSize,
        r,
        refractionHeight,
        refractionAmount,
        chromaticAberration,
        0.f,
        &refracted,
        &dispersed,
        NULL
    );
    *sx = refracted.x + dispersed.x * spectralT;
    *sy = refracted.y + dispersed.y * spectralT;
}
#endif

#endif /* WXG_KYANT_OPTICS_H */
