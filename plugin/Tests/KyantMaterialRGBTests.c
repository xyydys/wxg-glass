#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGMeshRefraction.h"

// Test two separate scenes. A thin gray stroke reveals unwanted refraction
// of the inset bar rim. Smooth gray page texture reveals shoulder dispersion
// independently of the stroke. Rasterize the meshes sent to Core Animation.
static const float columns[]={-40,-16,0,16,40};
enum { ColumnCount=5, RowCount=281, Capacity=20000 };
typedef struct { float rgb[3]; } Pixel;
static Pixel rim[ColumnCount][RowCount],page[ColumnCount][RowCount];
static WXGMeshPoint points[Capacity];
static unsigned int faces[Capacity][4];

static void accumulate(Pixel *p,wxg_kf3_t weight,float value) {
    p->rgb[0]+=weight.x*value;
    p->rgb[1]+=weight.y*value;
    p->rgb[2]+=weight.z*value;
}

static float chroma(Pixel p) {
    return fmaxf(p.rgb[0],fmaxf(p.rgb[1],p.rgb[2]))-
           fminf(p.rgb[0],fminf(p.rgb[1],p.rgb[2]));
}

static int sampleTriangle(float x,float y,WXGMeshPoint a,WXGMeshPoint b,
                          WXGMeshPoint c,float *sx,float *sy) {
    float ux=b.toX-a.toX,uy=b.toY-a.toY,vx=c.toX-a.toX,vy=c.toY-a.toY;
    float det=ux*vy-uy*vx;
    if(fabsf(det)<1.e-10f)return 0;
    float dx=x-a.toX,dy=y-a.toY,u=(dx*vy-dy*vx)/det,v=(ux*dy-uy*dx)/det;
    if(u<-.00001f || v<-.00001f || u+v>1.00001f)return 0;
    *sx=a.fromX+u*(b.fromX-a.fromX)+v*(c.fromX-a.fromX);
    *sy=a.fromY+u*(b.fromY-a.fromY)+v*(c.fromY-a.fromY);
    return 1;
}

static void renderProfiles(WXGMeshOptics o,int k) {
    o.kyantChannel=WXGKyantSpectralOffset(k);
    int count=0;
    int vertices=WXGBuildContourMesh(o,(WXGMeshQuality){.12f,.08f,8},points,Capacity,faces,Capacity,&count);
    assert(vertices>0 && count>0);
    wxg_kf3_t weight=WXGKyantSpectralRGBWeight(k);
    for(int col=0;col<ColumnCount;col++)for(int row=0;row<RowCount;row++) {
        float t=row*.25f,y=(o.padY+t)/o.height,x=.5f+columns[col]/o.width;
        if(WXGKyantSdRoundedRect((wxg_kf2_t){columns[col],t-35},(wxg_kf2_t){60,35},35)>-.125f)continue;
        float sx=0,sy=0;
        int covered=0;
        for(int i=0;i<count && !covered;i++) {
            const unsigned int *f=faces[i];
            covered=sampleTriangle(x,y,points[f[0]],points[f[1]],points[f[2]],&sx,&sy) ||
                    sampleTriangle(x,y,points[f[0]],points[f[2]],points[f[3]],&sx,&sy);
        }
        assert(covered);
        sx*=o.width; sy*=o.height;
        float depth=fminf(sy-o.sbTop,o.sbBottom-sy);
        float stroke=fmaxf(0.f,1.f-fabsf(depth-.4f)/.7f);
        accumulate(&rim[col][row],weight,25.f+40.f*stroke);
        accumulate(&page[col][row],weight,60.f+20.f*sinf((sy-o.padY)/5.f)+10.f*cosf((sx-o.width*.5f)/11.f));
    }
}

int main(void) {
    WXGMeshOptics o={0};
    o.padX=o.padY=64; o.width=120+2*o.padX; o.height=70+2*o.padY;
    o.kyantMode=o.shrinkPress=o.fieldScale=1; o.kyantHeight=o.edgeWidth=18;
    o.kyantAmount=26; o.dispersion=2.4f; o.zoomAfter=1.16f; o.shrinkPinch=.25f;
    o.sbLeft=o.padX-120; o.sbRight=o.padX+240; o.sbTop=o.padY+4; o.sbBottom=o.padY+66;
    for(int k=0;k<7;k++)renderProfiles(o,k);

    for(int col=0;col<ColumnCount;col++)for(int bottom=0;bottom<=1;bottom++) {
        float rimChroma=0,rimBrightness=0,pageChroma=0;
        unsigned int run=0,longest=0;
        for(int depth=0;depth<RowCount/2;depth++) {
            int row=bottom?RowCount-1-depth:depth;
            Pixel r=rim[col][row];
            rimChroma=fmaxf(rimChroma,chroma(r));
            rimBrightness=fmaxf(rimBrightness,r.rgb[1]);
            float spread=chroma(page[col][row]);
            pageChroma=fmaxf(pageChroma,spread);
            if(spread>2.f) {
                run++;
                if(run>longest)longest=run;
            } else {
                run=0;
            }
        }
        if(fabsf(columns[col])<20.f) {
            // A missing stroke would also be neutral. It must still be bright.
            if(rimChroma>=.1f)fprintf(stderr,"Inner rim at x=%g, %s: RGB spread %.3f/255\n",
                                      columns[col],bottom?"bottom":"top",rimChroma);
            assert(rimChroma<.1f);
            assert(rimBrightness>45.f);
        } else {
            printf("Shoulder x=%g, %s: peak %.2f/255 over a contiguous %.2f pt of textured page\n",
                   columns[col],bottom?"bottom":"top",pageChroma,.25f*longest);
            assert(pageChroma>5.f && longest>=16);
        }
    }
    puts("PASS: inset rim stays bright and neutral across the crown; both shoulders still disperse page texture.");
}
