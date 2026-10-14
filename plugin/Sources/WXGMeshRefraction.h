#ifndef WXG_MESH_REFRACTION_H
#define WXG_MESH_REFRACTION_H
#include "WXGOptics.h"
#include "WXGLensOptics.h"
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
} WXGMeshOptics;
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
static inline void WXGMeshSource(WXGMeshOptics o,float px,float py,float *sx,float *sy) {
    float cx=o.width*.5f,cy=o.height*.5f,s=o.fieldScale>0.f?o.fieldScale:1.f;
    float zb=o.zoomBefore>0.f?o.zoomBefore:1.f,za=o.zoomAfter>0.f?o.zoomAfter:1.f;
    float x=(px-cx)/s,y=(py-cy)/s,w=o.width/s,h=o.height/s;
    WXGShapeSample f=o.radius>0.f?WXGRoundedOpticalField(x,y,w,h,o.radius):WXGCapsuleOpticalField(x,y,w,h);
    float width=WXGMeshBandWidth(o,f,px,py,o.edgeWidth,o.topRatio);
    float off=WXGOpticalOffset(f.distance,width,o.refraction)*o.offsetScale;
    /* Channel shift exactly as wxgRGB: red at source+chroma, blue at source-chroma.
       FIX88: over the colour split's own band. */
    float dwidth=o.dispersionWidth>0.f || o.dispersionTopRatio>0.f?WXGMeshBandWidth(o,f,px,py,WXGMeshDispersionSide(o),WXGMeshDispersionRatio(o)):width;
    float shift=o.channel*o.dispersion*wxgEdgeC(f.distance,dwidth);
    float rx=cx+(px-cx)/zb-f.nx*off+f.nx*shift,ry=cy+(py-cy)/zb-f.ny*off+f.ny*shift;
    *sx=cx+(rx-cx)/za;*sy=cy+(ry-cy)/za;
}
/* Returns the vertex count (columns*rows), 0 when it does not fit. */
static inline int WXGBuildRefractionMesh(WXGMeshOptics o,WXGMeshPoint *points,int capacity,int *columns,int *rows) {
    enum { WXGMeshAxisCapacity=96 };
    float xs[WXGMeshAxisCapacity],ys[WXGMeshAxisCapacity];
    float s=o.fieldScale>0.f?o.fieldScale:1.f;
    float edge=WXG_MAX(WXG_MAX(o.edgeWidth,WXGMeshDispersionSide(o)),1.f)*s,radius=(o.radius>0.f?o.radius:WXG_MIN(o.width,o.height)*.5f/s)*s;
    /* Curved ends need resolution over the whole corner, straight sides over the band. */
    int cx=WXGMeshAxis(o.width,WXG_MAX(edge,radius)+2.f,8,24.f,xs,WXGMeshAxisCapacity);
    int cy=WXGMeshAxis(o.height,WXG_MAX(edge,WXG_MIN(radius,o.height*.5f))+2.f,8,24.f,ys,WXGMeshAxisCapacity);
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
    float d=-t;
    float off=WXGOpticalOffset(d,width,o.refraction)*o.offsetScale;
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
    float band=WXG_MIN(WXG_MAX(side,dside)+.75f,limit),err=WXG_MAX(q.ringError,.01f);
    int n=0;rings[n++]=-pad;
    float t=0.f;
    while(t<band && n<capacity-2) {
        rings[n++]=t;
        /* Worst curvature over the next 1.5 pt, so no bend is stepped over. */
        float k=0.f;
        for(float probe=0.f;probe<=1.5f;probe+=.25f)
            k=WXG_MAX(k,WXG_MAX(WXGMeshCurvature(o,side,dside,t+probe),WXGMeshCurvature(o,top,dtop,t+probe)));
        float dt=WXG_SQRT(8.f*err/WXG_MAX(k,1e-4f));
        t+=WXGOClamp(dt,.12f,1.5f);
    }
    if(t>=band && n<capacity-1) {
        /* Beyond the band the mapping is linear (identity or zoom): coarse. */
        float step=WXG_MAX(4.f,(limit-band)/4.f);
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
    if(!(o.width>1.f) || !(o.height>1.f))return 0;
    enum { WXGMeshMaxContour=512,WXGMeshMaxRings=160 };
    WXGContourSample contour[WXGMeshMaxContour];float rings[WXGMeshMaxRings];
    float innerX[WXGMeshMaxContour],innerY[WXGMeshMaxContour];int top[WXGMeshMaxContour],bottom[WXGMeshMaxContour];
    float hx=o.width*.5f,hy=o.height*.5f,limit=WXG_MIN(hx,hy);
    float R=o.radius>0.f?WXG_MIN(o.radius,limit):limit;
    float pad=R*.4143f+1.5f;
    /* Rings end 1.25 pt past the band (plain mapping there), never at the
       centre; a tiny shape stops 0.5 pt short of collapsing. */
    float band=WXG_MIN(WXG_MAX(WXG_MAX(o.edgeWidth,WXGMeshDispersionSide(o)),.5f)+.75f,limit);   // FIX88: and the colour split's band
    float stop=WXG_MIN(band+1.25f,limit-.5f);
    if(stop<.25f)stop=WXG_MAX(limit*.5f,.1f);
    int n=WXGMeshContour(hx,hy,R,q,contour,WXGMeshMaxContour);
    int m=WXGMeshRings(o,stop,pad,q,rings,WXGMeshMaxRings);
    if(n<4 || m<2 || n*m>pointCapacity)return 0;
    int capsule=!(o.radius>0.f);
    for(int i=0;i<n;i++)WXGMeshContourPointC(contour[i],hx,hy,R,rings[m-1],capsule,&innerX[i],&innerY[i]);
    int chain=WXGMeshZipperChains(innerX,innerY,n,top,bottom,WXGMeshMaxContour);
    if(chain<2 || n*(m-1)+chain-1>faceCapacity)return 0;
    int k=0;
    for(int r=0;r<m;r++)for(int i=0;i<n;i++) {
        float x,y,sx,sy;WXGMeshContourPointC(contour[i],hx,hy,R,rings[r],capsule,&x,&y);
        WXGMeshSource(o,x+hx,y+hy,&sx,&sy);
        points[k++]=(WXGMeshPoint){WXGMeshUnit(sx,o.width),WXGMeshUnit(sy,o.height),(x+hx)/o.width,(y+hy)/o.height};
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
