#include "../Sources/WXGMenuMorph.h"
#include "../Sources/WXGMenuMorphField.h"
#include "../Sources/WXGMenuMorphRim.h"
#include "../Sources/WXGRim26.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

// The first dark face is the luminance of the reference screenshot just
// inside the rim. Include saturated wallpaper and an almost white list.
static const uint8_t scenes[][3] = {{30,30,30},{21,58,91},{225,225,225},{218,236,253}};
enum { SceneCount = sizeof(scenes) / sizeof(scenes[0]) };

typedef struct {
    const WXGMenuMorphField *field;
    int samples, w, h;
    WXGMenuMorphFieldBox box;
    float xs, ys;
    uint8_t *pixels[SceneCount], face[SceneCount][3];
    double squared[SceneCount], peak[SceneCount], fullContrast[SceneCount];
} RimFrame;

static double contrast(const uint8_t rgba[4], const uint8_t face[3]) {
    double sum = 0;
    for (int k=0; k<3; ++k) {
        assert(rgba[k] <= rgba[3]);
        double composited = rgba[k] + (1.0 - rgba[3]/255.0)*face[k];
        sum += (composited-face[k])*(composited-face[k]);
    }
    return sqrt(sum/3.0);
}

typedef struct { float minX,minY,maxX,maxY; } ContourBounds;

static void includePoint(WXGMenuMorphContourAction action, float x, float y, void *context) {
    if (action==WXGMenuMorphContourClose) return;
    ContourBounds *b=context;
    b->minX=fminf(b->minX,x); b->maxX=fmaxf(b->maxX,x);
    b->minY=fminf(b->minY,y); b->maxY=fmaxf(b->maxY,y);
}

static void sampleEdge(WXGMenuMorphContourAction action, float x, float y, void *context) {
    if (action == WXGMenuMorphContourClose) return;
    RimFrame *frame = context;
    WXGMenuMorphFieldSample normal = WXGMenuMorphFieldRead(frame->field,x,y);
    // Look for the rendered stripe in a 3-pixel square about this point on
    // the outline. Pixel alignment changes on every frame as the panel grows.
    int px=(int)floorf((x-.4f*normal.dx-frame->box.x)*frame->xs);
    int py=(int)floorf((y-.4f*normal.dy-frame->box.y)*frame->ys);
    double strongest[SceneCount]={0};
    for (int j=py-1; j<=py+1; ++j) for (int i=px-1; i<=px+1; ++i) {
        if (i<0 || i>=frame->w || j<0 || j>=frame->h) continue;
        WXGMenuMorphFieldSample p=WXGMenuMorphFieldRead(frame->field,
            frame->box.x+(i+.5f)/frame->xs,frame->box.y+(j+.5f)/frame->ys);
        // The raster has bleed past the contour for the material host's
        // animated shape mask. Approximate its coverage at the pixel center.
        double coverage=fmax(0.,fmin(1.,.5 - p.distance*fminf(frame->xs,frame->ys)));
        for (int s=0; s<SceneCount; ++s) {
            const uint8_t *rgba=frame->pixels[s]+4*(frame->w*j+i);
            if (p.distance< -1.01f) assert(rgba[3]==0);
            strongest[s]=fmax(strongest[s],coverage*contrast(rgba,frame->face[s]));
        }
    }
    for (int s=0; s<SceneCount; ++s) {
        // An outline visible at only one point still has a disappearing arc.
        assert(strongest[s] > 2.0);
        frame->squared[s] += strongest[s]*strongest[s];
        frame->peak[s]=fmax(frame->peak[s],strongest[s]);
    }
    for (int sign=-1; sign<=1; sign+=2) {
        int i=(int)floorf((x+4.f*sign*normal.dx-frame->box.x)*frame->xs);
        int j=(int)floorf((y+4.f*sign*normal.dy-frame->box.y)*frame->ys);
        if (i<0 || i>=frame->w || j<0 || j>=frame->h) continue;
        float d=WXGMenuMorphFieldRead(frame->field,frame->box.x+(i+.5f)/frame->xs,
            frame->box.y+(j+.5f)/frame->ys).distance;
        if (fabsf(d)<2.f) continue;
        for (int s=0; s<SceneCount; ++s) assert(frame->pixels[s][4*(frame->w*j+i)+3]==0);
    }
    ++frame->samples;
}

static void verifyFrame(WXGMenuMorphFrame motion, int scale) {
    WXGMenuMorphField field;
    WXGMenuMorphFieldBuild(&field,
        (WXGMenuMorphFieldBox){motion.bounds.x,motion.bounds.y,motion.bounds.w,motion.bounds.h,motion.radiusX},motion.radiusY,
        (WXGMenuMorphFieldBox){motion.sourceLobe.x,motion.sourceLobe.y,motion.sourceLobe.w,motion.sourceLobe.h,motion.sourceRadius},
        motion.smoothing,5.f);
    ContourBounds bounds={INFINITY,INFINITY,-INFINITY,-INFINITY};
    WXGMenuMorphFieldTrace(&field,includePoint,&bounds);
    RimFrame frame={.field=&field,.box={bounds.minX,bounds.minY,bounds.maxX-bounds.minX,bounds.maxY-bounds.minY,0}};
    frame.w=(int)ceilf(frame.box.width*scale); frame.h=(int)ceilf(frame.box.height*scale);
    assert(frame.w>0 && frame.h>0);
    frame.xs=frame.w/frame.box.width; frame.ys=frame.h/frame.box.height;
    const double clearVeil[4]={0,0,0,0};
    for (int dark=0; dark<2; ++dark) {
        // Exported Other glass in morph11: 1 pt, full strength, floor 0.3.
        WXGMorphRimLights lights={.opacity=1.,.shape={1.,.7,45.,1.05,1.,1.,dark?.04:.13,0.,.3}};
        WXGMenuMorphRimPrepareLights(&lights);
        float matrix[20];
        WXGRim26Matrix(dark?1.35:.174,dark?3.:1.51,dark?.15:.847,matrix);
        for(int s=0; s<SceneCount; ++s) if ((s<2)==dark) {
            double saturation=dark?1.67:1.34, brightness=dark?.00235778:.00589448;
            uint8_t edge[3];
            WXGMenuMorphRimColour(scenes[s],saturation,brightness,clearVeil,matrix,edge);
            double face[3],expected[3];
            double y=(.2126*scenes[s][0]+.7152*scenes[s][1]+.0722*scenes[s][2])/255.;
            for (int k=0; k<3; ++k) {
                face[k]=fmax(0.,fmin(1.,y+(scenes[s][k]/255.-y)*saturation+brightness));
                frame.face[s][k]=(uint8_t)lround(255.*face[k]);
            }
            WXGRim26Colour(matrix,face,1.,expected);
            for (int k=0; k<3; ++k) assert(fabs(edge[k]-255.*expected[k])<=1.);
            uint8_t full[4]={edge[0],edge[1],edge[2],255};
            frame.fullContrast[s]=contrast(full,frame.face[s]);
            size_t bytes=(size_t)frame.w*frame.h*4u;
            frame.pixels[s]=calloc(bytes,1);
            assert(frame.pixels[s]);
            WXGMorphRimColours palette={.rgb=edge,.width=1,.height=1};
            WXGMenuMorphRimDraw(&field,frame.box,frame.w,frame.h,frame.pixels[s],&lights,palette);
        }
    }
    WXGMenuMorphFieldTrace(&field,sampleEdge,&frame);
    assert(frame.samples>12);
    for (int s=0; s<SceneCount; ++s) {
        assert(sqrt(frame.squared[s]/frame.samples)>6.);
        // A near-white surface naturally has a smaller available highlight.
        // Even the worst subpixel alignment must retain most of that contrast.
        assert(frame.peak[s]>.65*frame.fullContrast[s]);
        free(frame.pixels[s]);
    }
}

static int verifyPhase(WXGMenuMorph *motion, bool open, int hz, int scale, int maxFrames) {
    WXGMenuMorphSetExpanded(motion,open);
    for (int f=1; f<=maxFrames; ++f) {
        bool settled=WXGMenuMorphAdvance(motion,1./hz);
        verifyFrame(motion->frame,scale);
        if (settled) return f;
    }
    return maxFrames;
}

static void verifyDisabled(void) {
    WXGMenuMorphField field;
    WXGMenuMorphFieldBox box={4,5,48,48,24};
    WXGMenuMorphFieldBuild(&field,box,24,box,0,5);
    const uint8_t white[3]={255,255,255};
    WXGMorphRimColours colours={.rgb=white,.width=1,.height=1};
    WXGMorphRimLights lights={.opacity=0.,.shape={1.,.7,45.,1.05,1.,1.,.13,0.,.3}};
    WXGMenuMorphRimPrepareLights(&lights);
    uint8_t pixels[48*48*4]={0};
    WXGMenuMorphRimDraw(&field,box,48,48,pixels,&lights,colours);
    for (size_t i=0; i<sizeof(pixels); ++i) assert(pixels[i]==0);
}

int main(void) {
    // A naturally clipped white edge over a white surface can equal its face.
    uint8_t white[3]={255,255,255},colour[3],rgba[4];
    double clearVeil[4]={0}; float lightMatrix[20];
    WXGRim26Matrix(.174,1.51,.847,lightMatrix);
    WXGMenuMorphRimColour(white,1.,0.,clearVeil,lightMatrix,colour);
    WXGMenuMorphRimPixel(rgba,colour,1.);
    assert(rgba[3]==255 && contrast(rgba,white)==0.);
    verifyDisabled();
    int frames=0;
    WXGMenuBox button={321.25,56.125,44,44},panel={139.7111,56.125,225.5389,161};
    for (int hz=60; hz<=120; hz+=60) for (int scale=2; scale<=3; ++scale) {
        WXGMenuMorph motion;
        WXGMenuMorphInitialize(&motion,button,panel,28.85235,button,false);
        WXGMenuMorphSetAbsorbDuration(&motion,.48);
        verifyFrame(motion.frame,scale);
        frames += 1 + verifyPhase(&motion,true,hz,scale,2*hz);
        frames += verifyPhase(&motion,false,hz,scale,2*hz);
        frames += verifyPhase(&motion,true,hz,scale,hz/8);
        frames += verifyPhase(&motion,false,hz,scale,hz/12);
        frames += verifyPhase(&motion,true,hz,scale,2*hz);
    }
    printf("MenuMorphRimTests: visible perimeter on 4 backdrops in each of %d opening, closing and interrupted frames at 2x/3x.\n",frames);
    return 0;
}
