#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "../Sources/WXGMeshRefraction.h"

// A cross-section through the real bar, inside a 120 x 70 pt pressed lens.
// The source is a 17/255 page and a 25/255 bar, like the dark appearance.
// Its one-point antialiased boundary is the only source of colour gradients.
enum { Columns=97, Rows=281 };
static float columnX(int index) { return (float)(index-Columns/2); }
typedef struct { float rgb[3]; } Pixel;
typedef Pixel Image[Columns][Rows];
static Image exact,native,comparison;
static WXGMeshPoint points[20000];
static unsigned int faces[20000][4];

static WXGMeshOptics dock(float h,float a,float dispersion) {
    WXGMeshOptics o={0};
    o.padX=o.padY=64;
    o.width=120+2*o.padX; o.height=70+2*o.padY;
    o.edgeWidth=o.kyantHeight=h; o.kyantAmount=a; o.dispersion=dispersion;
    o.kyantMode=o.fieldScale=o.shrinkPress=1;
    o.zoomAfter=1.16f; o.shrinkPinch=.25f;
    o.sbLeft=o.padX-120; o.sbRight=o.padX+240;
    o.sbTop=o.padY+4; o.sbBottom=o.padY+66;
    return o;
}

static void accumulate(Pixel *p,int wave,float intensity) {
    wxg_kf3_t w=WXGKyantSpectralRGBWeight(wave);
    p->rgb[0]+=w.x*intensity;
    p->rgb[1]+=w.y*intensity;
    p->rgb[2]+=w.z*intensity;
}

static float sampleMaterial(WXGMeshOptics o,float sourceY,int uniform) {
    if(uniform)return 93.f;
    float depth=fminf(sourceY-o.sbTop,o.sbBottom-sourceY);
    return 17+8*WXGOClamp(depth+.5f,0,1);
}

static void renderExact(Image out,WXGMeshOptics o,int uniform) {
    memset(out,0,sizeof(Image));
    for(int k=0;k<7;k++) {
        o.kyantChannel=WXGKyantSpectralOffset(k);
        for(int x=0;x<Columns;x++)for(int y=0;y<Rows;y++) {
            float sx,sy;
            WXGMeshSource(o,o.width*.5f+columnX(x),o.padY+y*.25f,&sx,&sy);
            accumulate(&out[x][y],k,sampleMaterial(o,sy,uniform));
        }
    }
}

static void meshTriangle(float rays[Columns][Rows],WXGMeshOptics o,
                         WXGMeshPoint a,WXGMeshPoint b,WXGMeshPoint c) {
    float ax=a.toX*o.width,ay=a.toY*o.height;
    float bx=b.toX*o.width,by=b.toY*o.height;
    float cx=c.toX*o.width,cy=c.toY*o.height;
    float det=(bx-ax)*(cy-ay)-(cx-ax)*(by-ay);
    if(fabsf(det)<1e-8f)return;
    int start=(int)fmaxf(0,ceilf(4*(fminf(ay,fminf(by,cy))-o.padY)-.001f));
    int end=(int)fminf(Rows-1,floorf(4*(fmaxf(ay,fmaxf(by,cy))-o.padY)+.001f));
    for(int x=0;x<Columns;x++) {
        float px=o.width*.5f+columnX(x);
        if(px<fminf(ax,fminf(bx,cx))-.0001f || px>fmaxf(ax,fmaxf(bx,cx))+.0001f)continue;
        for(int y=start;y<=end;y++) {
            float py=o.padY+y*.25f;
            float wb=((px-ax)*(cy-ay)-(py-ay)*(cx-ax))/det;
            float wc=((bx-ax)*(py-ay)-(by-ay)*(px-ax))/det;
            if(wb>=-.0001f && wc>=-.0001f && wb+wc<=1.0001f)
                rays[x][y]=((1-wb-wc)*a.fromY+wb*b.fromY+wc*c.fromY)*o.height;
        }
    }
}

static void renderNative(Image out,WXGMeshOptics o) {
    float rays[Columns][Rows];
    memset(out,0,sizeof(Image));
    for(int k=0;k<7;k++) {
        o.kyantChannel=WXGKyantSpectralOffset(k);
        for(int x=0;x<Columns;x++)for(int y=0;y<Rows;y++)rays[x][y]=NAN;
        int nf=0,n=WXGBuildContourMesh(o,(WXGMeshQuality){.12f,.08f,8},
                                       points,20000,faces,20000,&nf);
        assert(n>0 && nf>0);
        for(int i=0;i<nf;i++) {
            unsigned int *f=faces[i];
            meshTriangle(rays,o,points[f[0]],points[f[1]],points[f[2]]);
            meshTriangle(rays,o,points[f[0]],points[f[2]],points[f[3]]);
        }
        for(int x=0;x<Columns;x++)for(int y=0;y<Rows;y++) {
            assert(isfinite(rays[x][y]));
            accumulate(&out[x][y],k,sampleMaterial(o,rays[x][y],0));
        }
    }
}

static float chroma(Pixel p) {
    float *rgb=p.rgb;
    return fmaxf(rgb[0],fmaxf(rgb[1],rgb[2]))-fminf(rgb[0],fminf(rgb[1],rgb[2]));
}

// Ignore pixels outside the visible capsule. Report the highest RGB spread
// in digital levels on each half, including the inward-displaced source edge.
static int visible(int x,int row) {
    wxg_kf2_t p={columnX(x),row*.25f-35},size={60,35};
    return WXGKyantSdRoundedRect(p,size,35)<=-.125f;
}

static int crossesMaterialEdge(Image neutral,int x,int half) {
    float lo=25,hi=17;
    for(int i=0;i<=Rows/2;i++) {
        int row=half?Rows-1-i:i;
        if(!visible(x,row))continue;
        float value=neutral[x][row].rgb[1];
        lo=fminf(lo,value);
        hi=fmaxf(hi,value);
    }
    return lo<21 && hi>21;
}

static float peakChroma(Image image,int x,int half) {
    float result=0;
    for(int i=1;i<=Rows/2;i++) {
        int row=half?Rows-1-i:i;
        if(visible(x,row))result=fmaxf(result,chroma(image[x][row]));
    }
    return result;
}

static float profileDifference(Image a,Image b,int x) {
    float peak=0;
    for(int y=0;y<Rows;y++)for(int c=0;c<3;c++)
        peak=fmaxf(peak,fabsf(a[x][y].rgb[c]-b[x][y].rgb[c]));
    return peak;
}

int main(void) {
    WXGMeshOptics full=dock(18,26,2.4f);
    renderExact(exact,full,0);
    renderNative(native,full);
    printf("Dark material edge peak RGB spread / 255, centre and shoulders: ");
    for(int x=Columns/2-40;x<=Columns/2+40;x+=10)printf(" %.2f",peakChroma(native,x,0));
    puts(""); fflush(stdout);
    // The inner bar's inset tapers at the shoulders. Once its physical edge
    // exits the capsule an untextured source need not show a coloured band.
    renderExact(comparison,dock(0,0,0),0);
    for(int x=0;x<Columns;x++)for(int half=0;half<2;half++) {
        if(!crossesMaterialEdge(comparison,x,half))continue;
        float peak=peakChroma(exact,x,half);
        assert(peak>1);
        assert(peakChroma(native,x,half)>.7f*peak);
        assert(fabsf(peakChroma(native,x,half)-peak)<2.f);
    }

    // Across the central straight segment each edge must form one narrow band.
    // Count bright runs so two detached fringes cannot pass on peak alone.
    for(int x=Columns/2-20;x<=Columns/2+20;x++)for(int half=0;half<2;half++) {
        float threshold=.5f*peakChroma(native,x,half);
        int runs=0,pixels=0,inside=0;
        for(int i=0;i<Rows/2;i++) {
            int bright=chroma(native[x][half?Rows-1-i:i])>=threshold;
            if(bright && !inside)runs++;
            pixels+=bright;
            inside=bright;
        }
        assert(runs==1 && pixels*.25f<5);
    }

    double squaredError=0;
    int measured=0;
    for(int x=0;x<Columns;x++)for(int y=0;y<Rows;y++) {
        if(!visible(x,y))continue;
        for(int c=0;c<3;c++) {
            float delta=native[x][y].rgb[c]-exact[x][y].rgb[c];
            squaredError+=delta*delta;
            measured++;
        }
    }
    float rms=(float)sqrt(squaredError/measured);
    printf("Native vs. analytic dark material RGB, RMS %.3f/255\n",rms);
    assert(rms<.65f);

    WXGMeshOptics zero[]={dock(0,26,2.4f),dock(18,0,2.4f),dock(18,26,0)};
    for(unsigned i=0;i<sizeof(zero)/sizeof(*zero);i++) {
        renderExact(comparison,zero[i],0);
        for(int x=0;x<Columns;x++)for(int half=0;half<2;half++)
            assert(peakChroma(comparison,x,half)<.001f);
    }
    renderExact(comparison,full,1);
    for(int x=0;x<Columns;x++)for(int y=0;y<Rows;y++)for(int c=0;c<3;c++)
        assert(fabsf(comparison[x][y].rgb[c]-93)<.001f);

    renderExact(comparison,dock(6,26,2.4f),0);
    float heightEffect=profileDifference(exact,comparison,Columns/2);
    renderExact(comparison,dock(18,5,2.4f),0);
    float amountEffect=profileDifference(exact,comparison,Columns/2);
    printf("Central material edge RGB change / 255: height %.2f, amount %.2f\n",heightEffect,amountEffect);
    assert(heightEffect>1 && amountEffect>1);
    renderExact(exact,dock(18,26,0),0);
    renderExact(comparison,dock(6,26,0),0);
    assert(profileDifference(exact,comparison,Columns/2)>1);
    renderExact(comparison,dock(18,5,0),0);
    assert(profileDifference(exact,comparison,Columns/2)>1);
    puts("PASS: seven spectral samples of a physical material edge; native meshes, dark RGB contrast, neutral controls and slider response.");
}
