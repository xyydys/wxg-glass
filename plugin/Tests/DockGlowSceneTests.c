/* Pixel fixture for the two lens paths over an opaque page. Each ray reads
   a two-tone scene with an independently defined capsule and broad pointer glow.
   Verifies:
   1) Clear top/bottom pockets receive zero touch glow (unlike late screen-space glow);
   2) Touch glow flows smoothly across the left/right lens boundaries without a cliff;
   3) Broad iOS 26 reach illuminates adjacent tabs and fades cleanly to zero on release. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../Sources/WXGMeshRefraction.h"
#include "../Sources/WXGDockSystem.h"

enum { LensW=124, LensH=70, BarW=398, BarH=62 };
static const float cx=LensW/2.f,cy=LensH/2.f;
enum { MeshCapacity=20000 };
typedef struct {
    WXGMeshOptics optics;
    WXGMeshPoint vertex[MeshCapacity];
    unsigned int quad[MeshCapacity][4];
    int faces;
} SourceMesh;
static SourceMesh channels[WXG_KYANT_SPECTRAL_TAPS];

static int materialAt(float x,float y) {
    float cap=fmaxf(0.f,fabsf(x-cx)-(BarW-BarH)*.5f);
    return hypotf(cap,y-cy)<BarH*.5f;
}
static float lightAt(float x,float y,float sx,float sy,float phase,float spotScale) {
    if(!materialAt(x,y))return 0.f;
    float spot=WXGDockGlowBroadWeight(hypotf(x-sx,y-sy)/fmaxf(spotScale,.01f));
    return 1.f-(1.f-phase*(float)WXG_DOCK26_GLOW_BAR)*(1.f-phase*(float)WXG_DOCK26_GLOW_SPOT*spot);
}
static WXGMeshOptics fixtureMesh(int travel) {
    WXGMeshOptics m={0};float press=travel?.90f:1.f;
    m.width=LensW;m.height=LensH;m.fieldScale=m.zoomBefore=m.offsetScale=1.f;
    /* Native Kyant lens keeps the captured bar/glow unzoomed (1x) like iOS 26 glassBackground. */
    m.zoomAfter=travel?1.f+press*((float)WXG_DOCK26_ZOOM-1.f):1.f;
    m.shrinkPress=press;m.shrinkPinch=.12f;
    m.sbLeft=travel?-10000.f:cx-BarW*.5f;m.sbRight=travel?10000.f:cx+BarW*.5f;
    m.sbTop=cy-BarH*.5f;m.sbBottom=cy+BarH*.5f;
    m.kyantMode=!travel;m.kyantHeight=18.f*press;m.kyantAmount=26.f*press;
    m.curveHeight=roundf((float)WXG_DOCK26_LENS_BAND*LensH*press*4.f)*.25f;
    m.curveAmount=roundf((float)WXG_DOCK26_LENS_AMOUNT*LensH*press*4.f)*.25f;
    m.edgeWidth=travel?m.curveHeight:m.kyantHeight;m.dispersion=travel?1.f:2.4f;
    return m;
}
static void buildLayers(int travel) {
    for(int k=0;k<(travel?3:WXG_KYANT_SPECTRAL_TAPS);k++) {
        SourceMesh *s=&channels[k];
        WXGMeshOptics m=fixtureMesh(travel);
        if(travel)m.channel=1.f-k;
        else {
            m.padX=m.padY=32.f;m.width+=2*m.padX;m.height+=2*m.padY;
            m.sbLeft+=m.padX;m.sbRight+=m.padX;m.sbTop+=m.padY;m.sbBottom+=m.padY;
            m.kyantChannel=WXGKyantSpectralOffset(k);
        }
        s->optics=m;
        int count=WXGBuildContourMesh(m,(WXGMeshQuality){.12f,.08f,8.f},s->vertex,MeshCapacity,s->quad,MeshCapacity,&s->faces);
        assert(count>0 && s->faces>0);
    }
}
static void sampleMesh(int tap,float x,float y,float *sx,float *sy) {
    const SourceMesh *s=&channels[tap];WXGMeshOptics m=s->optics;
    float u=(x+m.padX)/m.width,v=(y+m.padY)/m.height;
    for(int f=0;f<s->faces;f++)for(int j=0;j<2;j++) {
        WXGMeshPoint a=s->vertex[s->quad[f][0]],b=s->vertex[s->quad[f][1+j]],c=s->vertex[s->quad[f][2+j]];
        float ux=b.toX-a.toX,uy=b.toY-a.toY,vx=c.toX-a.toX,vy=c.toY-a.toY;
        float det=ux*vy-uy*vx;
        if(fabsf(det)<1e-10f)continue;
        float wb=((u-a.toX)*vy-(v-a.toY)*vx)/det,wc=(ux*(v-a.toY)-uy*(u-a.toX))/det,wa=1.f-wb-wc;
        if(wa < -1e-5f || wb < -1e-5f || wc < -1e-5f)continue;
        *sx=(wa*a.fromX+wb*b.fromX+wc*c.fromX)*m.width-m.padX;
        *sy=(wa*a.fromY+wb*b.fromY+wc*c.fromY)*m.height-m.padY;
        return;
    }
    assert(0 && "Lens pixel missing from emitted geometry");
}
static float pixel(int travel,float x,float y,float pointerX,float phase,float spotScale,int late) {
    float cap=fmaxf(0.f,fabsf(x-cx)-(LensW-LensH)*.5f);
    int inLens=hypotf(cap,y-cy)<LensH*.5f;
    int taps=inLens?(travel?3:WXG_KYANT_SPECTRAL_TAPS):1;
    float luminance=0.f;
    for(int k=0;k<taps;k++) {
        float sx=x,sy=y,w=1.f;
        if(inLens) {
            if(travel) {
                const float channelLuma[]={.2126f,.7152f,.0722f};w=channelLuma[k];
            }else {
                wxg_kf3_t weights=WXGKyantSpectralRGBWeight(k);
                w=weights.x*.2126f+weights.y*.7152f+weights.z*.0722f;
            }
            sampleMesh(k,x,y,&sx,&sy);
        }
        float base=materialAt(sx,sy)?25.f:17.f;
        float light=lightAt(late?x:sx,late?y:sy,pointerX,cy,phase,spotScale);
        luminance+=w*(base+(255.f-base)*light);
    }
    return luminance;
}
int main(void) {
    for(int travel=0;travel<2;travel++) {
        buildLayers(travel);
        /* Inside the clear top/bottom pockets (y=5 and LensH-5): zero glow leak,
           whereas a late screen-space overlay would light them brightly. */
        const float y[]={5.f,LensH-5.f};float worst=0,lateDelta=0;
        for(int i=0;i<2;i++)for(int j=-2;j<=2;j++) {
            float x=cx+j;
            float off=pixel(travel,x,y[i],cx,0.f,1.f,0);
            float lit=pixel(travel,x,y[i],cx,1.f,1.f,0);
            float late=pixel(travel,x,y[i],cx,1.f,1.f,1);
            worst=fmaxf(worst,fabsf(lit-off));lateDelta=fmaxf(lateDelta,late-off);
        }
        assert(worst<1.f && lateDelta>15.f);
        const float core=pixel(travel,cx,cy,cx,1.f,1.f,0)-pixel(travel,cx,cy,cx,0.f,1.f,0);
        const float outerX=cx+100.f;
        const float outerOff=pixel(travel,outerX,cy,cx,0.f,1.f,0);
        const float outer=pixel(travel,outerX,cy,cx,1.f,1.f,0)-outerOff;
        /* Broad iOS 26 glow still reaches adjacent tabs (dx=100 pt -> bar + broad spot). */
        assert(core>35.f && outer>13.f && outer<22.f);
        /* Seamless continuity across left/right lens boundaries (no R7 zoom/cutoff cliff):
           immediately outside (dx=64) vs inside past the rim (dx=48) differs smoothly. */
        if(!travel) {
            float outL=pixel(0,cx-64.f,cy,cx,1.f,1.f,0);
            float inL=pixel(0,cx-48.f,cy,cx,1.f,1.f,0);
            float outR=pixel(0,cx+64.f,cy,cx,1.f,1.f,0);
            float inR=pixel(0,cx+48.f,cy,cx,1.f,1.f,0);
            /* Smooth monotonic rise inward, bounded to the natural broad Gaussian slope (~5 levels over 16 pt). */
            assert(inL>outL && inL-outL<7.f);
            assert(inR>outR && inR-outR<7.f);
            printf("Native lens-edge continuity: L %.2f -> %.2f (step %.2f), R %.2f -> %.2f (step %.2f)\n",
                   outL,inL,inL-outL,outR,inR,inR-outR);
        }
        assert(pixel(travel,outerX,cy,outerX,1.f,1.f,0)-outerOff>35.f);
        assert(pixel(travel,cx,cy,outerX,1.f,1.f,0)<pixel(travel,cx,cy,cx,1.f,1.f,0)-15.f);
        float mid=pixel(travel,cx,cy,cx,.5f,2.5f,0)-25.f;
        assert(mid>0.f && mid<core && fabsf(pixel(travel,cx,cy,cx,0.f,4.f,0)-25.f)<.01f);
        assert(fabsf(pixel(travel,outerX,cy,cx,0.f,4.f,0)-outerOff)<.01f);
        printf("Dock glow %s luma deltas (0..255): gap %.2f, R5 late glow %.2f, core %.2f, adjacent %.2f, mid-release %.2f, final 0\n",
               travel?"CA travel":"native",worst,lateDelta,core,outer,mid);
    }
}
