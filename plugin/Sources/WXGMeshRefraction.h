#ifndef WXG_MESH_REFRACTION_H
#define WXG_MESH_REFRACTION_H
#include "WXGOptics.h"
#include "WXGLensOptics.h"
#include "WXGSoftEdge.h"
#include "WXGLensCurve.h"
#include "WXGKyantOptics.h"
/* FIX20: TEST9 refraction as a Core Animation mesh for render-server glass.

   A mesh transform on the backdrop layer is evaluated by the render server
   while it composites each displayed frame, so it can never lag the content.
   Each vertex says: the pixel shown at `to` comes from `from` (both in the
   layer's unit coordinates). This builds `from` with the SAME optical field
   (WXGRoundedOpticalField / WXGCapsuleOpticalField) and the SAME offset curve
   (WXGOpticalOffset) as the Metal shader; between vertices the render server
   interpolates, which is the only approximation (no per-pixel dispersion).

   Body:  source = c + (p-c)/zoomBefore - n*offset          (wxgBody, button press)
   Lens:  source = c + ((p - n*offset) - c)/zoomAfter        (lens path)        */
typedef struct { float fromX,fromY,toX,toY; } WXGMeshPoint;
typedef struct {
    float width,height;      /* layer size in points */
    float fieldScale;        /* optical field evaluated at (p-c)/fieldScale (bar scale) */
    float radius;            /* optical corner radius, 0 = capsule (shader rim.w) */
    float edgeWidth,refraction,offsetScale;
    float zoomBefore,zoomAfter;
    /* FIX23 (zero = off): chroma magnitude in points per unit edge weight
       (body: dispersion*.85, lens: dispersion*1.55*press), the colour channel
       this mesh draws (+1 red samples outward, 0 green, -1 blue inward), and the
       FIX21 lens rim ratio/sharpness (0 ratio = isotropic). */
    float dispersion,channel,topRatio,sharpness;
    /* FIX47 (all zero = off): the bar in this layer's points (left, top,
       right, bottom), a capsule; with it the lens rim uses WXGLensEdgeWidthAtBar. */
    float barLeft,barTop,barRight,barBottom;
    /* FIX57 (zero = off): how far the lens's left / right end has relaxed
       toward the top / bottom width at the bar's ends (WXGLensEndReach). */
    float endLeft,endRight;
    /* FIX88 (zero = as the refraction band): the colour split's own range and
       top / bottom ratio (iOS 26's lens disperses over its own band, which
       also narrows above and below, not only inside the refraction band). */
    float dispersionWidth,dispersionTopRatio;
    /* FIX113 H (zero = off): the layer is the shape plus this margin on each
       side (width / height include it), so an outward refraction (negative
       offsetScale: the lens rim gathering what lies just outside it) samples
       real content instead of the layer's clamped edge. The optical field is
       the shape's; bar* above are in the layer's points. */
    float padX,padY;
    /* FIX113 I (zero = off): the share of the rim offset cancelled
       (WXGLensRefractionOffset, as the shader's lens). */
    float cancel;
    /* FIX113 U (zero = off; user: the lens refracts the shrunk bar, its
       background and its own border, nothing drawn again): the lens' backdrop
       captures the bar itself, and the bar seen through the lens is that bar
       made smaller. The bar in this layer's points (an end far from the lens
       pushed far out), its corner radius (0 = capsule, as the shader's bar),
       and the press and pinch of its inset (WXGInnerInsetAlong, exactly the
       inset the shader's lens gave the bar it drew). */
    float sbLeft,sbTop,sbRight,sbBottom,sbRadius,shrinkPress,shrinkPinch;
    /* FIX113 Y (zero = none): added to the full inset (display points, may be
       negative), ramped in the same way: the lens' elastic squash / stretch
       otherwise widens / closes the strip between the smaller bar and the
       lens' rim (the plugin passes keep x (resting half height - half height)). */
    float shrinkExtra;
    /* FIX114 I (zero = off): 边界过渡, TEST9's shift mixed toward the soft
       one (WXGSoftEdge.h); the glass body only. */
    float transition;
    /* FIX114 J (each zero = FIX114 I's): the soft shift's shape
       (WXGSoftShape: the most the outline is magnified, the curve's power,
       the band in points). */
    float softStretch,softPower,softWidth;
    /* The glass' refraction as iOS 26's (WXGLensCurve.h; every glass and
       lens since FIX130; zero = the old band above, kept for the tests): the
       band and the shift at the outline (points, field units). With it the
       topRatio / sharpness / bar* / end* / cancel / dispersionWidth rules are
       not used; `dispersion` is the colour split's strength, `channel` picks
       the channel's mean weight. */
    float curveHeight,curveAmount;
    /* FIX122 E (zero = none): the most the outermost ring may squeeze the
       picture (WXGLensCurveOffsetCapped). */
    float curveSqueeze;
    /* Kyant Backdrop refraction mode (zero = off; trailing fields keep positional init ABI). */
    float kyantMode,kyantHeight,kyantAmount,kyantChannel;
    /* Pure-glass flat inner-bar shrink (zero = legacy 45-deg along-bar ramp; 1 = pure uniform flat inset). */
    float shrinkFlat;
} WXGMeshOptics;
/* The full inset of the smaller bar, and the inset ramped by `along` (as
   WXGInnerInsetAlong, either sign). */
static inline float WXGMeshShrinkFull(WXGMeshOptics o) {
    float maxPinch=o.shrinkFlat>.5f?.60f:.30f;
    return (o.sbBottom-o.sbTop)*.5f*WXGOClamp(o.shrinkPress,0.f,1.f)*WXGOClamp(o.shrinkPinch,0.f,maxPinch)+o.shrinkExtra;
}
static inline float WXGMeshShrinkAlong(float full,float along) {
    float f=WXG_ABS(full);if(!(f>1e-4f))return 0.f;
    float u=WXGOClamp(along/(2.f*f),0.f,1.f);
    return full*u*(2.f-u);
}
static inline float WXGMeshShapeWidth(WXGMeshOptics o) {float w=o.width-2.f*(o.padX>0.f?o.padX:0.f);return w>1.f?w:1.f;}
static inline float WXGMeshShapeHeight(WXGMeshOptics o) {float h=o.height-2.f*(o.padY>0.f?o.padY:0.f);return h>1.f?h:1.f;}
/* FIX88: the band width at a point for a side width and top / bottom ratio
   (FIX21 / FIX47 / FIX57 rules; ratio 0 = isotropic). */
static inline float WXGMeshBandWidth(WXGMeshOptics o,WXGShapeSample f,float px,float py,float side,float topRatio) {
    float width=topRatio>0.f?WXGLensEdgeWidth(f.nx,f.ny,side,topRatio,o.sharpness):side;
    if(topRatio>0.f && o.barRight>o.barLeft && o.barBottom>o.barTop) {
        float bw=o.barRight-o.barLeft,bh=o.barBottom-o.barTop;
        WXGShapeSample b=WXGCapsuleOpticalField(px-(o.barLeft+bw*.5f),py-(o.barTop+bh*.5f),bw,bh);
        width=WXGLensEdgeWidthAtBar(f.nx,f.ny,side,topRatio,o.sharpness,b.distance);
    }
    if(topRatio>0.f)width=WXGLensEndRelax(width,f.nx,side,topRatio,o.endLeft,o.endRight);
    return width;
}
static inline float WXGMeshDispersionSide(WXGMeshOptics o) {return o.dispersionWidth>0.f?o.dispersionWidth:o.edgeWidth;}
static inline float WXGMeshDispersionRatio(WXGMeshOptics o) {return o.dispersionTopRatio>0.f?o.dispersionTopRatio:o.topRatio;}
/* FIX114 I: how far in the soft shift may reach (field units): half the
   shape's short side (a capsule's middle line, where the shift from both
   sides is 0) and a rounded rectangle's corner radius (deeper, its field's
   normals meet on the diagonals, where no shift stays continuous). */
static inline float WXGMeshSoftLimit(WXGMeshOptics o) {
    float s=o.fieldScale>0.f?o.fieldScale:1.f;
    float half=WXG_MIN(WXGMeshShapeWidth(o),WXGMeshShapeHeight(o))*.5f/s;
    if(o.radius>0.f)half=WXG_MIN(half,WXG_MAX(o.radius,.5f));
    return half;
}
static inline WXGSoftShape WXGMeshSoftShape(WXGMeshOptics o) {WXGSoftShape s={o.softStretch,o.softPower,o.softWidth};return s;}
/* The soft shift's band for a side width (0 with 边界过渡 off). */
static inline float WXGMeshSoftBand(WXGMeshOptics o,float width) {
    return o.transition>0.f?WXGSoftBandShaped(width,o.refraction,WXGMeshSoftLimit(o),WXGMeshSoftShape(o)):0.f;
}
/* The inward shift at a signed distance for band `width`: TEST9's (FIX113
   I's cancel), mixed toward the soft one by 边界过渡. Off, exactly as before. */
static inline float WXGMeshOffset(WXGMeshOptics o,float distance,float width) {
    if(!(o.transition>0.f))return WXGLensRefractionOffset(distance,width,o.refraction,o.cancel)*o.offsetScale;
    return WXGTransitionOffsetShaped(distance,width,o.refraction,o.cancel,o.transition,WXGMeshSoftLimit(o),WXGMeshSoftShape(o))*o.offsetScale;
}

/* Dense, uniform samples across both edge bands; sparse interior. */
static inline int WXGMeshAxis(float length,float band,int edgeSamples,float interiorStep,float *out,int capacity) {
    if(!(length>0) || capacity<2)return 0;
    if(edgeSamples<1)edgeSamples=1;
    band=WXG_MIN(WXG_MAX(band,0.f),length*.5f);
    int n=0;
    float interior=length-2.f*band;
    int steps=interior>.001f?(int)ceilf(interior/WXG_MAX(interiorStep,1.f)):0;
    for(int i=0;i<=edgeSamples && n<capacity;i++)out[n++]=band*(float)i/(float)edgeSamples;
    for(int i=1;i<steps && n<capacity;i++)out[n++]=band+interior*(float)i/(float)steps;
    for(int i=0;i<=edgeSamples && n<capacity;i++) {
        float v=length-band+band*(float)i/(float)edgeSamples;
        if(v>out[n-1]+1e-3f)out[n++]=v;
    }
    if(out[n-1]<length)out[n-1]=length;
    return n;
}
/* The shader's wxgEdge: 1 on the contour, 0 at `width` inside. */
static inline float wxgEdgeC(float distance,float width) {
    float t=WXGOClamp(-distance/WXG_MAX(width,1e-3f),0.f,1.f);
    return 1.f-t*t*(3.f-2.f*t);
}
static inline float WXGMeshUnit(float v,float length) {
    float u=v/WXG_MAX(length,1e-3f);return u<0.f?0.f:u>1.f?1.f:u;
}
/* On with a press and a bar, whatever the pinch: with no inset the bar's edge
   still shows where it lies (the zoom does not magnify it, as the shader's
   bar), so a pinch going to 0 never jumps. */
static inline int WXGMeshShrinks(WXGMeshOptics o) {
    return o.shrinkPress>0.f && o.sbRight-o.sbLeft>2.f && o.sbBottom-o.sbTop>2.f;
}
static inline WXGShapeSample WXGMeshBarField(WXGMeshOptics o,float x,float y) {
    float bw=o.sbRight-o.sbLeft,bh=o.sbBottom-o.sbTop,dx=x-(o.sbLeft+bw*.5f),dy=y-(o.sbTop+bh*.5f);
    return o.sbRadius>0.f?WXGRoundedOpticalField(dx,dy,bw,bh,o.sbRadius):WXGCapsuleOpticalField(dx,dy,bw,bh);
}
/* FIX113 U: the smaller bar. (yx, yy) is the displayed point bent by the
   lens' band but not yet zoomed: there the shader's lens drew its bar inset
   by d (WXGInnerInsetAlong at the nearest point of the bar's outline, by how
   deep inside the lens that lies, so it still joins the bar outside at the
   lens' ends). (sx, sy) is the source after the zoom. Along the bar's normal
   the source is moved so that the zoomed image of that inset outline lands
   on the bar's real edge: inside, the bar from its middle line out to its
   edge (its veil, edge ring, rim: everything the bar draws) fills the smaller
   bar; outside, the page beyond the bar's edge. Continuous (no move on the
   middle line, the same move on both sides of the inset outline). */
static inline void WXGMeshShrinkBar(WXGMeshOptics o,float yx,float yy,float za,float *sx,float *sy) {
    float bw=o.sbRight-o.sbLeft,bh=o.sbBottom-o.sbTop,half=WXG_MIN(bw,bh)*.5f;
    float cx=o.width*.5f,cy=o.height*.5f,s=o.fieldScale>0.f?o.fieldScale:1.f;
    WXGShapeSample b=WXGMeshBarField(o,yx,yy);
    float ox=yx-b.nx*b.distance,oy=yy-b.ny*b.distance;
    WXGShapeSample l=o.radius>0.f?WXGRoundedOpticalField((ox-cx)/s,(oy-cy)/s,WXGMeshShapeWidth(o)/s,WXGMeshShapeHeight(o)/s,o.radius)
                                 :WXGCapsuleOpticalField((ox-cx)/s,(oy-cy)/s,WXGMeshShapeWidth(o)/s,WXGMeshShapeHeight(o)/s);
    /* FIX113 Y: with the extra (the lens squashed / swollen by the drag
       speed), the depth is measured against the lens at rest (its rim that
       much further out / in): measured against the squashed lens the ramp
       never reached the full inset, and nothing once the lens was shorter
       than the bar. The join at the lens' ends lies in its refraction band. */
    float d=o.shrinkFlat>.5f?WXGMeshShrinkFull(o)
        :WXGMeshShrinkAlong(WXGMeshShrinkFull(o),WXGLensDepthAlongBar(l.distance*s-o.shrinkExtra,-b.ny,b.nx,l.nx,l.ny));
    /* The zoom (about the layer's centre) moves that outline: before it,
       the inset is h - (h - d) / zoom, h the centre's distance to the
       outline along its normal. Swollen (a negative extra), the smaller
       bar may come out past the real one (up to half its half height). */
    float h=(ox-cx)*b.nx+(oy-cy)*b.ny;
    float dz=WXGOClamp(h-(h-d)/WXG_MAX(za,.01f),o.shrinkExtra<0.f?-half*.5f:0.f,half*.9f);
    if(!(WXG_ABS(dz)>0.f))return;
    WXGShapeSample q=WXGMeshBarField(o,*sx,*sy);
    float t=q.distance,t2=t<-dz?-half+(t+half)*half/(half-dz):t+dz;
    if(t<-half)t2=t;
    *sx+=q.nx*(t2-t);*sy+=q.ny*(t2-t);
}
/* The curve: the shape's field (its normals, for a rounded rectangle, from
   1.5x its radius), the shift along the normal, each channel's share of the
   colour split, then the zoom and the smaller bar exactly as the band path. */
static inline void WXGMeshCurveSource(WXGMeshOptics o,float px,float py,float *sx,float *sy) {
    float cx=o.width*.5f,cy=o.height*.5f,s=o.fieldScale>0.f?o.fieldScale:1.f;
    float zb=o.zoomBefore>0.f?o.zoomBefore:1.f,za=o.zoomAfter>0.f?o.zoomAfter:1.f;
    float x=(px-cx)/s,y=(py-cy)/s,w=WXGMeshShapeWidth(o)/s,h=WXGMeshShapeHeight(o)/s;
    WXGShapeSample f=o.radius>0.f?WXGRoundedOpticalField(x,y,w,h,o.radius):WXGCapsuleOpticalField(x,y,w,h);
    if(o.radius>0.f) {
        float half=WXG_MIN(w,h)*.5f,gr=WXG_MIN(o.radius*1.5f,half);
        if(gr>o.radius+1e-3f) {
            WXGShapeSample g=gr>=half-1e-3f?WXGCapsuleOpticalField(x,y,w,h):WXGRoundedOpticalField(x,y,w,h,gr);
            if(g.nx!=0.f || g.ny!=0.f){f.nx=g.nx;f.ny=g.ny;}
        }
    }
    float off=WXGLensCurveOffsetCapped(-f.distance,o.curveHeight,o.curveAmount,o.curveSqueeze)*s;
    float spread=o.dispersion>0.f?o.dispersion*WXGLensSplitWeight(o.channel)*WXGLensSplitIntensity(x,y,w*.5f,h*.5f):0.f;
    float bx=cx+(px-cx)/zb,by=cy+(py-cy)/zb;   /* a button's press zoom before (1 for a lens) */
    float rx=bx-f.nx*off*(1.f+spread),ry=by-f.ny*off*(1.f+spread);
    *sx=cx+(rx-cx)/za;*sy=cy+(ry-cy)/za;
    if(WXGMeshShrinks(o))WXGMeshShrinkBar(o,bx-f.nx*off,by-f.ny*off,za,sx,sy);   /* FIX113 U, as the band path */
}
static inline void WXGMeshSource(WXGMeshOptics o,float px,float py,float *sx,float *sy) {
    if(o.kyantMode>0.5f) {
        float padX=WXG_MAX(o.padX,0.f),padY=WXG_MAX(o.padY,0.f);
        float shapeW=WXGMeshShapeWidth(o),shapeH=WXGMeshShapeHeight(o);
        WXG_K_F2 halfSize=WXG_K_MAKE2(shapeW*.5f,shapeH*.5f),central;
        float endLeft=0.f,endRight=0.f;
        if(WXGMeshShrinks(o)) {
            endLeft=WXGLensEndReach(o.sbLeft,o.sbRight,padX,padX+shapeW,-1);
            endRight=WXGLensEndReach(o.sbLeft,o.sbRight,padX,padX+shapeW,1);
        }
        WXG_K_F2 ray=WXGKyantSpectralRay(WXG_K_MAKE2(px-padX,py-padY),halfSize,halfSize,
            o.radius>0.f?o.radius:WXG_K_MIN(halfSize.x,halfSize.y),
            o.kyantHeight,o.kyantAmount,o.dispersion,0.f,endLeft,endRight,o.kyantChannel,&central);
        ray.x+=padX;ray.y+=padY;central.x+=padX;central.y+=padY;
        WXG_K_F2 center=WXG_K_MAKE2(o.width*.5f,o.height*.5f);
        float zoom=o.zoomAfter>0.f?o.zoomAfter:1.f;
        WXG_K_F2 src=WXG_K_MAKE2(center.x+(ray.x-center.x)/zoom,
                                 center.y+(ray.y-center.y)/zoom);
        src=WXGKyantSceneSourceDepthFlat(src,central,center,WXG_K_MAKE2(shapeW,shapeH),o.radius,
            WXG_K_MAKE2(o.sbLeft,o.sbTop),WXG_K_MAKE2(o.sbRight-o.sbLeft,o.sbBottom-o.sbTop),o.sbRadius,
            o.shrinkPress,o.shrinkPinch,0.f,WXG_K_MAX(0.f,o.shrinkExtra),zoom,o.shrinkFlat);
        *sx=src.x;*sy=src.y;return;
    }
    if(o.curveHeight>0.f || o.shrinkFlat>.5f){WXGMeshCurveSource(o,px,py,sx,sy);return;}
    float cx=o.width*.5f,cy=o.height*.5f,s=o.fieldScale>0.f?o.fieldScale:1.f;
    float zb=o.zoomBefore>0.f?o.zoomBefore:1.f,za=o.zoomAfter>0.f?o.zoomAfter:1.f;
    float x=(px-cx)/s,y=(py-cy)/s,w=WXGMeshShapeWidth(o)/s,h=WXGMeshShapeHeight(o)/s;
    WXGShapeSample f=o.radius>0.f?WXGRoundedOpticalField(x,y,w,h,o.radius):WXGCapsuleOpticalField(x,y,w,h);
    float width=WXGMeshBandWidth(o,f,px,py,o.edgeWidth,o.topRatio);
    float off=WXGMeshOffset(o,f.distance,width);   /* FIX113 I, FIX114 I */
    /* Channel shift exactly as wxgRGB: red at source+chroma, blue at source-chroma.
       FIX88: over the colour split's own band. */
    float dwidth=o.dispersionWidth>0.f || o.dispersionTopRatio>0.f?WXGMeshBandWidth(o,f,px,py,WXGMeshDispersionSide(o),WXGMeshDispersionRatio(o)):width;
    float shift=o.channel*o.dispersion*wxgEdgeC(f.distance,dwidth);
    float rx=cx+(px-cx)/zb-f.nx*off+f.nx*shift,ry=cy+(py-cy)/zb-f.ny*off+f.ny*shift;
    *sx=cx+(rx-cx)/za;*sy=cy+(ry-cy)/za;
    if(WXGMeshShrinks(o))WXGMeshShrinkBar(o,cx+(px-cx)/zb-f.nx*off,cy+(py-cy)/zb-f.ny*off,za,sx,sy);   /* FIX113 U */
}
/* Returns the vertex count (columns*rows), 0 when it does not fit. */
static inline int WXGBuildRefractionMesh(WXGMeshOptics o,WXGMeshPoint *points,int capacity,int *columns,int *rows) {
    enum { WXGMeshAxisCapacity=96 };
    float xs[WXGMeshAxisCapacity],ys[WXGMeshAxisCapacity];
    float s=o.fieldScale>0.f?o.fieldScale:1.f;
    float edge=WXG_MAX(WXG_MAX(WXG_MAX(o.edgeWidth,WXGMeshDispersionSide(o)),WXGMeshSoftBand(o,o.edgeWidth)),1.f)*s,radius=(o.radius>0.f?o.radius:WXG_MIN(WXGMeshShapeWidth(o),WXGMeshShapeHeight(o))*.5f/s)*s;
    /* Curved ends need resolution over the whole corner, straight sides over the band. */
    float px=o.padX>0.f?o.padX:0.f,py=o.padY>0.f?o.padY:0.f;   /* FIX113 H: the shape's edges lie that far in */
    int cx=WXGMeshAxis(o.width,px+WXG_MAX(edge,radius)+2.f,8,24.f,xs,WXGMeshAxisCapacity);
    int cy=WXGMeshAxis(o.height,py+WXG_MAX(edge,WXG_MIN(radius,WXGMeshShapeHeight(o)*.5f))+2.f,8,24.f,ys,WXGMeshAxisCapacity);
    if(cx<2 || cy<2 || cx*cy>capacity)return 0;
    int k=0;
    for(int j=0;j<cy;j++)for(int i=0;i<cx;i++) {
        float sx,sy;WXGMeshSource(o,xs[i],ys[j],&sx,&sy);
        points[k++]=(WXGMeshPoint){WXGMeshUnit(sx,o.width),WXGMeshUnit(sy,o.height),xs[i]/o.width,ys[j]/o.height};
    }
    *columns=cx;*rows=cy;return k;
}
/* FIX20: TEST9's clear refracted ring (blur coverage below 100%) in the render
   server: an unblurred backdrop with the same mesh, masked by exactly the
   shader's sharp weight at the displayed point (unscaled field coordinates). */
static inline float WXGSharpRingAlpha(float x,float y,float width,float height,float radius,float edgeWidth,float coverage) {
    WXGShapeSample f=radius>0.f?WXGRoundedOpticalField(x-width*.5f,y-height*.5f,width,height,radius)
                               :WXGCapsuleOpticalField(x-width*.5f,y-height*.5f,width,height);
    return WXGOClamp(WXGBlurSharpWeight(f.distance,edgeWidth,coverage),0.f,1.f);
}
/* FIX23: contour-following refraction mesh.

   A tensor grid cannot follow a steep refraction curve: with refraction 8.97
   over a 7.7 pt band, 57% of a dock's edge-band pixels were placed more than
   1 pt wrong (worst 4 pt), which reads as a smeared edge. Here vertices lie on
   rings parallel to the glass outline. Ring depths are chosen from the
   curvature of the actual source mapping (all three colour channels), so the
   piecewise-linear error stays below `ringError` points; along the outline the
   rounded parts are sampled every `arcStep` radians (straight parts need only
   their ends, the mapping is linear there). An outer ring covers the layer's
   corners and the continuous-corner clip. Faces are quads between rings. */
typedef struct { float ringError,arcStep,straightStep; } WXGMeshQuality;
typedef struct { float cx,cy,nx,ny,u; int kind; } WXGContourSample; /* kind 0 straight, 1 arc */

/* Inward depth of the source point along the normal, for depth t (outside < 0).
   FIX88: the colour split over its own band width `dwidth`. */
static inline float WXGMeshDepthSource(WXGMeshOptics o,float width,float dwidth,float t,float channel) {
    /* The curve; a channel at most WXG_LENS_SPLIT_SPAN of the
       shift from green (|I| <= 1), so the rings follow the steepest one. */
    if(o.kyantMode>.5f)return t+WXGLensCurveOffset(t,o.kyantHeight,o.kyantAmount)*(1.f+channel*WXG_MAX(o.dispersion,0.f));
    if(o.curveHeight>0.f || o.shrinkFlat>.5f)return t+WXGLensCurveOffsetCapped(t,o.curveHeight,o.curveAmount,o.curveSqueeze)*(1.f+channel*(o.dispersion>0.f?o.dispersion*WXG_LENS_SPLIT_SPAN:0.f));
    float d=-t;
    float off=WXGMeshOffset(o,d,width);   /* FIX113 I, FIX114 I */
    return t+off-channel*o.dispersion*wxgEdgeC(d,dwidth);
}
static inline float WXGMeshCurvature(WXGMeshOptics o,float width,float dwidth,float t) {
    const float h=.04f;float worst=0.f;
    for(int c=-1;c<=1;c++) {
        if(c!=0 && !(o.dispersion>0.f))continue;
        float a=WXGMeshDepthSource(o,width,dwidth,t-h,(float)c),b=WXGMeshDepthSource(o,width,dwidth,t,(float)c),e=WXGMeshDepthSource(o,width,dwidth,t+h,(float)c);
        float k=WXG_ABS(a-2.f*b+e)/(h*h);if(k>worst)worst=k;
    }
    return worst;
}
/* Ring depths: outer pad, the curvature-adaptive band, then coarse interior. */
static inline int WXGMeshRings(WXGMeshOptics o,float limit,float pad,WXGMeshQuality q,float *rings,int capacity) {
    float side=WXG_MAX(o.edgeWidth,.5f),top=o.topRatio>0.f?side*WXGOClamp(o.topRatio,.05f,1.f):side;
    float dside=WXG_MAX(WXGMeshDispersionSide(o),.5f),dratio=WXGMeshDispersionRatio(o),dtop=dratio>0.f?dside*WXGOClamp(dratio,.05f,1.f):dside;
    float band=WXG_MIN(WXG_MAX(WXG_MAX(side,dside),WXGMeshSoftBand(o,side))+.75f,limit),err=WXG_MAX(q.ringError,.01f);   // FIX114 I: and the soft band
    float hCrown=0.f,aCrown=0.f;
    WXGMeshOptics crownOptics=o;
    if(o.kyantMode>.5f) {
        float shapeMinHalf=WXG_MIN(WXGMeshShapeWidth(o),WXGMeshShapeHeight(o))*.5f;
        WXGKyantCrownTarget(shapeMinHalf,o.kyantHeight,o.kyantAmount,&hCrown,&aCrown);
        crownOptics.kyantHeight=hCrown;crownOptics.kyantAmount=aCrown;
        if(o.dispersion>0.f)band=WXG_MIN(WXG_MAX(band,.40f*shapeMinHalf+.75f),limit);
    }
    int n=0;rings[n++]=-pad;
    float t=0.f;
    int moveTier=o.kyantMode>.5f && q.ringError>.12f;
    while(t<band && n<capacity-2) {
        rings[n++]=t;
        /* Worst curvature over the next 1.5 pt, so no bend is stepped over. */
        float k=0.f;
        for(float probe=0.f;probe<=1.5f;probe+=.25f) {
            k=WXG_MAX(k,WXG_MAX(WXGMeshCurvature(o,side,dside,t+probe),WXGMeshCurvature(o,top,dtop,t+probe)));
            if(o.kyantMode>.5f && hCrown>1e-4f && aCrown>1e-4f)
                k=WXG_MAX(k,WXGMeshCurvature(crownOptics,hCrown,hCrown,t+probe));
        }
        float dt=WXG_SQRT(8.f*err/WXG_MAX(k,1e-4f));
        float minStep=o.kyantMode>.5f?(moveTier?.10f:.04f):.12f;
        float maxStep=(o.kyantMode>.5f && hCrown>1e-4f && t<hCrown+2.f)?(moveTier?.90f:.45f):1.5f;
        t+=WXGOClamp(dt,minStep,maxStep);
    }
    if(t>=band && n<capacity-1) {
        /* Beyond the band the mapping is linear (identity or zoom): coarse.
           FIX113 U: not with the smaller bar, whose outline lies out there. */
        float step=WXGMeshShrinks(o)?1.f:WXG_MAX(4.f,(limit-band)/4.f);
        for(t=band;t<limit-.01f && n<capacity-1;t+=step)rings[n++]=t;
    }
    if(n<capacity)rings[n++]=limit;
    return n;
}
/* FIX26: arcs are sampled half a step off their ends and straight edges keep
   both ends; vertical edges use an odd number of segments. No vertex lies
   exactly on a tip (y = 0 on the left/right extremes) and the sampling is
   mirror-symmetric about y = 0, so the interior can be closed by pairing
   each top vertex with its mirror (the "zipper"). */
static inline int WXGMeshContour(float hx,float hy,float R,WXGMeshQuality q,WXGContourSample *out,int capacity) {
    int n=0;float sx[4]={-1.f,1.f,1.f,-1.f},sy[4]={-1.f,-1.f,1.f,1.f};
    float a0[4]={-1.5707963f,0.f,1.5707963f,3.1415927f};
    float straightX=hx-R,straightY=hy-R;
    float astep=WXG_MAX(q.arcStep,.02f),lstep=WXG_MAX(q.straightStep,1.f);
    /* FIX96: a capsule's continuous outline leaves its straight sides about
       0.3 R before the circle would: those ends are sampled every 0.1 R. */
    int capsule=R>=WXG_MIN(hx,hy)-1e-3f;
    for(int c=0;c<4;c++) {
        /* Straight edge leading into corner c: top, right, bottom, left. */
        float length=(c%2==0?2.f*straightX:2.f*straightY);
        int segments=length>.01f?(int)ceilf(length/lstep):0;
        if(c%2==1 && segments>0 && segments%2==0)++segments;
        float dense=capsule?WXG_MIN(.40f*R,length*.5f):0.f,fine=WXG_MAX(.10f*R,.5f);
        if(segments>0 && dense>fine) {
            /* dense ends, the middle as before; symmetric about the middle */
            int ends=(int)ceilf(dense/fine);float middle=length-2.f*dense;
            int mid=middle>.01f?(int)ceilf(middle/lstep):0;
            for(int i=0;i<=ends && n<capacity;i++)
                out[n++]=(WXGContourSample){0.f,0.f,c==0?0.f:c==1?1.f:c==2?0.f:-1.f,c==0?-1.f:c==1?0.f:c==2?1.f:0.f,dense*(float)i/(float)ends/length,c};
            for(int i=1;i<mid && n<capacity;i++)
                out[n++]=(WXGContourSample){0.f,0.f,c==0?0.f:c==1?1.f:c==2?0.f:-1.f,c==0?-1.f:c==1?0.f:c==2?1.f:0.f,(dense+middle*(float)i/(float)mid)/length,c};
            for(int i=mid>0 || middle>.01f?0:1;i<=ends && n<capacity;i++)
                out[n++]=(WXGContourSample){0.f,0.f,c==0?0.f:c==1?1.f:c==2?0.f:-1.f,c==0?-1.f:c==1?0.f:c==2?1.f:0.f,(length-dense+dense*(float)i/(float)ends)/length,c};
        }else
        for(int i=0;i<=segments && segments>0 && n<capacity;i++)
            out[n++]=(WXGContourSample){0.f,0.f,c==0?0.f:c==1?1.f:c==2?0.f:-1.f,c==0?-1.f:c==1?0.f:c==2?1.f:0.f,(float)i/(float)segments,c};
        int steps=(int)ceilf(1.5707963f/astep);
        for(int i=0;i<steps && n<capacity;i++) {
            float a=a0[c]+1.5707963f*((float)i+.5f)/(float)steps;
            out[n++]=(WXGContourSample){sx[(c+1)%4]*straightX,sy[(c+1)%4]*straightY,cosf(a),sinf(a),0.f,4+((c+1)%4)};
        }
    }
    return n;
}
/* Position of contour sample s at inward depth t (t<0 outside). */
static inline void WXGMeshContourPoint(WXGContourSample s,float hx,float hy,float R,float t,float *x,float *y) {
    if(s.kind>=4) {
        int c=s.kind-4;float sxs[4]={-1.f,1.f,1.f,-1.f},sys[4]={-1.f,-1.f,1.f,1.f};
        if(t<=R){*x=s.cx+(R-t)*s.nx;*y=s.cy+(R-t)*s.ny;}
        else{*x=s.cx+(R-t)*sxs[c];*y=s.cy+(R-t)*sys[c];}
        return;
    }
    float m=WXG_MAX(R,t);
    if(s.kind==0){*x=-(hx-m)+2.f*(hx-m)*s.u;*y=-hy+t;}
    else if(s.kind==1){*x=hx-t;*y=-(hy-m)+2.f*(hy-m)*s.u;}
    else if(s.kind==2){*x=(hx-m)-2.f*(hx-m)*s.u;*y=hy-t;}
    else{*x=-hx+t;*y=(hy-m)-2.f*(hy-m)*s.u;}
}
/* FIX96: a capsule's rings follow its continuous outline (the field's
   depth is the ring's depth again): moved out along the circle's normal by
   WXGContinuousCorrection. Rounded rectangles are unchanged. */
static inline void WXGMeshContourPointC(WXGContourSample s,float hx,float hy,float R,float t,int capsule,float *x,float *y) {
    WXGMeshContourPoint(s,hx,hy,R,t,x,y);
    if(!capsule)return;
    WXGShapeSample c=WXGCapsuleOpticalField(*x,*y,2.f*hx,2.f*hy);
    float corr=WXGContinuousCorrection(*x,*y,2.f*hx,2.f*hy);
    *x+=c.nx*corr;*y+=c.ny*corr;
}
/* FIX26: interior "zipper". FIX25's separate fill overlapped the last ring
   by 1 pt; harmless for normal compositing, but the green and blue
   dispersion layers ADD (plus-lighter), so the overlap was counted twice and
   drew a cyan line. Now the interior is closed with quads between each
   vertex of the innermost ring's top half and its mirror on the bottom half,
   sharing the ring's own vertices: exact coverage, no overlap, no point
   shared by several vertices (FIX23/24's collapse points were not drawn at
   all) and no degenerate face. */
static inline int WXGMeshZipperChains(const float *xs,const float *ys,int n,int *top,int *bottom,int capacity) {
    int left=-1,right=-1;float leftX=1e9f,rightX=-1e9f;
    for(int i=0;i<n;i++) {
        int j=(i+1)%n;
        if(ys[i]>0.f && ys[j]<0.f && xs[i]+xs[j]<leftX){leftX=xs[i]+xs[j];left=i;}    /* up the left side */
        if(ys[i]<0.f && ys[j]>0.f && xs[i]+xs[j]>rightX){rightX=xs[i]+xs[j];right=i;} /* down the right side */
    }
    if(left<0 || right<0)return 0;
    int lt=0,lb=0;
    for(int i=(left+1)%n;lt<capacity;i=(i+1)%n){top[lt++]=i;if(i==right)break;}
    for(int i=left;lb<capacity;i=(i-1+n)%n){bottom[lb++]=i;if(i==(right+1)%n)break;}
    return lt==lb?lt:0;
}
/* Fills unit-coordinate vertices and quad faces. Returns the vertex count,
   or 0 if it does not fit the capacities. */
static inline int WXGBuildContourMesh(WXGMeshOptics o,WXGMeshQuality q,WXGMeshPoint *points,int pointCapacity,
                                      unsigned int (*faces)[4],int faceCapacity,int *faceCount) {
    *faceCount=0;
    if(o.kyantMode>.5f) {
        if(q.ringError>.14f){q.ringError=WXG_MIN(q.ringError,.16f);q.arcStep=WXG_MIN(q.arcStep,.10f);q.straightStep=WXG_MIN(q.straightStep,8.f);}
        else{q.ringError=WXG_MIN(q.ringError,.08f);q.arcStep=WXG_MIN(q.arcStep,o.dispersion>0.f?.06f:.10f);q.straightStep=WXG_MIN(q.straightStep,4.f);}
    }
    if(!(o.width>1.f) || !(o.height>1.f))return 0;
    enum { WXGMeshMaxContour=512,WXGMeshMaxRings=160 };
    WXGContourSample contour[WXGMeshMaxContour];float rings[WXGMeshMaxRings];
    float innerX[WXGMeshMaxContour],innerY[WXGMeshMaxContour];int top[WXGMeshMaxContour],bottom[WXGMeshMaxContour];
    float hx=WXGMeshShapeWidth(o)*.5f,hy=WXGMeshShapeHeight(o)*.5f,limit=WXG_MIN(hx,hy);
    float lx=o.width*.5f,ly=o.height*.5f;   /* FIX113 H: the layer's centre (the shape's, with a margin) */
    float R=o.radius>0.f?WXG_MIN(o.radius,limit):limit;
    float pad=R*.4143f+1.5f;
    /* Rings end 1.25 pt past the band (plain mapping there), never at the
       centre; a tiny shape stops 0.5 pt short of collapsing. */
    float band=WXG_MIN(WXG_MAX(WXG_MAX(o.edgeWidth,WXGMeshDispersionSide(o)),.5f)+.75f,limit);   // FIX88: and the colour split's band
    if(o.kyantMode>.5f && o.dispersion>0.f)band=WXG_MIN(WXG_MAX(band,.40f*limit+.75f),limit);
    if(o.transition>0.f)band=WXG_MIN(WXG_MAX(band,WXGMeshSoftBand(o,o.edgeWidth)+.75f),limit);   // FIX114 I: and the soft band
    float stop=WXG_MIN(band+1.25f,limit-.5f);
    /* FIX113 U: rings down past the smaller bar's outline (the bar's top /
       bottom from the shape's edge, plus its full inset), so the straight
       interior span never smooths that outline away. */
    if(WXGMeshShrinks(o)) {
        float py0=o.padY>0.f?o.padY:0.f,deep=WXG_MAX(o.sbTop-py0,(o.height-py0)-o.sbBottom);
        float full=WXG_MAX(0.f,WXGMeshShrinkFull(o));
        stop=WXG_MIN(WXG_MAX(stop,deep+full+2.f),limit-.5f);
    }
    if(stop<.25f)stop=WXG_MAX(limit*.5f,.1f);
    int n=WXGMeshContour(hx,hy,R,q,contour,WXGMeshMaxContour);
    int m=WXGMeshRings(o,stop,pad,q,rings,WXGMeshMaxRings);
    if(n<4 || m<2 || n*m>pointCapacity)return 0;
    int capsule=!(o.radius>0.f) && !(o.kyantMode>.5f);
    for(int i=0;i<n;i++)WXGMeshContourPointC(contour[i],hx,hy,R,rings[m-1],capsule,&innerX[i],&innerY[i]);
    int chain=WXGMeshZipperChains(innerX,innerY,n,top,bottom,WXGMeshMaxContour);
    if(chain<2 || n*(m-1)+chain-1>faceCapacity)return 0;
    int k=0;
    for(int r=0;r<m;r++)for(int i=0;i<n;i++) {
        float x,y,sx,sy;WXGMeshContourPointC(contour[i],hx,hy,R,rings[r],capsule,&x,&y);
        WXGMeshSource(o,x+lx,y+ly,&sx,&sy);
        points[k++]=(WXGMeshPoint){WXGMeshUnit(sx,o.width),WXGMeshUnit(sy,o.height),(x+lx)/o.width,(y+ly)/o.height};
    }
    int f=0;
    for(int r=0;r<m-1;r++)for(int i=0;i<n;i++) {
        unsigned int a=(unsigned int)(r*n+i),b=(unsigned int)(r*n+(i+1)%n);
        faces[f][0]=a;faces[f][1]=b;faces[f][2]=b+(unsigned int)n;faces[f][3]=a+(unsigned int)n;++f;
    }
    unsigned int base=(unsigned int)((m-1)*n);
    for(int j=0;j<chain-1;j++) {
        /* Quads with all four corners on a straight vertical side have no area. */
        int a=top[j],b=top[j+1],c=bottom[j+1],d=bottom[j];
        float area=(innerX[b]-innerX[a])*(innerY[c]-innerY[a])-(innerX[c]-innerX[a])*(innerY[b]-innerY[a])
                  +(innerX[c]-innerX[a])*(innerY[d]-innerY[a])-(innerX[d]-innerX[a])*(innerY[c]-innerY[a]);
        if(WXG_ABS(area)<1e-4f)continue;
        faces[f][0]=base+(unsigned int)a;faces[f][1]=base+(unsigned int)b;
        faces[f][2]=base+(unsigned int)c;faces[f][3]=base+(unsigned int)d;++f;
    }
    *faceCount=f;
    return k;
}
#endif
