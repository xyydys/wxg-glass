#include <assert.h>
#include <stdio.h>
#include "../Sources/WXGBackdropROI.h"

static int contains(WXGROIRect r,double x,double y) {
    return x>=r.x-1e-9 && y>=r.y-1e-9 && x<=r.x+r.w+1e-9 && y<=r.y+r.h+1e-9;
}
static double clamp(double v,double hi) {return fmax(0,fmin(hi,v));}
static void copy_coverage(void) {
    WXGROIRect atlas={-40,-40,494,976};
    WXGSourceTransform transforms[]={
        {1,0,0,1,-24,6},{1.17,.16,-.25,.9,290,740},
        {.3,1.1,-.8,.2,440,-25},{-1,.2,.15,-1,480,990},
        {1,0,0,1,-1200,-1100},{1,0,0,1,1100,2100}
    };
    double scales[]={1,1.25,2,3};
    for(size_t t=0;t<sizeof(transforms)/sizeof(*transforms);t++)for(size_t s=0;s<4;s++)for(size_t a=0;a<4;a++) {
        WXGROIRect canvas,roi;double scale=scales[s],atlasScale=scales[a];
        const unsigned width=137,height=83;
        assert(WXGROICanvas(transforms[t],width,height,scale,atlas,atlasScale,&canvas,&roi));
        unsigned aw=(unsigned)ceil(atlas.w*atlasScale),ah=(unsigned)ceil(atlas.h*atlasScale);
        WXGCopyUniforms uniforms;
        assert(WXGMakeCopyUniforms(transforms[t],scale,atlas.x,atlas.y,atlas.w,atlas.h,&uniforms));
        // Independent oracle: the actual float copy uniforms and the texture
        // sampler's four clamped bilinear texels, across the entire drawable.
        for(unsigned y=0;y<height;y++)for(unsigned x=0;x<width;x++) {
            double u=uniforms.origin[0]+uniforms.x[0]*(x+.5)+uniforms.y[0]*(y+.5);
            double v=uniforms.origin[1]+uniforms.x[1]*(x+.5)+uniforms.y[1]*(y+.5);
            double ix=floor(u*aw-.5),iy=floor(v*ah-.5);
            for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++) {
                double sx=atlas.x+(clamp(ix+dx,aw-1)+.5)*atlas.w/aw;
                double sy=atlas.y+(clamp(iy+dy,ah-1)+.5)*atlas.h/ah;
                assert(contains(roi,sx,sy));
            }
        }
    }
    WXGROIRect canvas,roi;
    assert(!WXGROICanvas((WXGSourceTransform){1,0,0,1,0,0},10,10,0,atlas,1,&canvas,&roi));
    assert(!WXGROICanvas((WXGSourceTransform){NAN,0,0,1,0,0},10,10,1,atlas,1,&canvas,&roi));
}
static unsigned seed=417;
static unsigned next(void){seed=seed*1664525u+1013904223u;return seed;}
static void union_oracle(void) {
    WXGROIRect atlas={0,0,16,16};
    for(int trial=0;trial<120;trial++) {
        WXGROISet set={0};unsigned char filled[16][16]={0};
        for(int n=0;n<12;n++) {
            int x=next()%16,y=next()%16,w=1+next()%(16-x),h=1+next()%(16-y);
            WXGROIAdd(&set,(WXGROIRect){x,y,w,h},atlas);
            for(int iy=y;iy<y+h;iy++)for(int ix=x;ix<x+w;ix++)filled[iy][ix]=1;
        }
        double area=0;for(int y=0;y<16;y++)for(int x=0;x<16;x++)area+=filled[y][x];
        assert(fabs(WXGROIArea(&set,atlas)-area)<1e-9);
        for(int n=0;n<20;n++) {
            int x=next()%16,y=next()%16,w=1+next()%(16-x),h=1+next()%(16-y),covered=1;
            for(int iy=y;iy<y+h;iy++)for(int ix=x;ix<x+w;ix++)covered&=filled[iy][ix];
            assert(WXGROICovers(&set,(WXGROIRect){x,y,w,h})==covered);
        }
    }
}
static void disconnected_and_new_consumer(void) {
    WXGROIRect atlas={0,0,500,1000};WXGROISet set={0};
    WXGROIAdd(&set,(WXGROIRect){0,0,100,100},atlas);
    WXGROIAdd(&set,(WXGROIRect){400,0,100,100},atlas);
    WXGROIAdd(&set,(WXGROIRect){0,850,500,150},atlas);
    assert(WXGROIArea(&set,atlas)==95000);
    assert(!WXGROICovers(&set,(WXGROIRect){0,0,500,1000}));
    assert(!WXGROICovers(&set,(WXGROIRect){0,600,500,150})); // keyboard travel
    assert(!WXGROIIntersects(&set,(WXGROIRect){150,100,200,700}));
    assert(WXGROICovers(&set,(WXGROIRect){0,850,500,150}));
    WXGROISet adjacent={0};
    WXGROIAdd(&adjacent,(WXGROIRect){0,0,50,100},atlas);
    WXGROIAdd(&adjacent,(WXGROIRect){50,0,50,100},atlas);
    assert(WXGROICovers(&adjacent,(WXGROIRect){0,0,100,100}));
    adjacent.rects[1].x+=.001;
    assert(!WXGROICovers(&adjacent,(WXGROIRect){0,0,100,100}));
    WXGROISet many={0};
    for(size_t i=0;i<=WXG_ROI_CAPACITY;i++)WXGROIAdd(&many,(WXGROIRect){(double)i*2,0,1,1},atlas);
    assert(many.count==1 && WXGROICovers(&many,atlas));
}
int main(void) {
    copy_coverage();union_oracle();disconnected_and_new_consumer();
    puts("Backdrop ROI: full affine canvas, bilinear/clamped texels, disjoint union and coverage checks passed.");
    return 0;
}
