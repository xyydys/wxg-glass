#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "../Sources/WXGMeshRefraction.h"

static WXGMeshOptics dock(float width,float height,float press,float band,float amount,float dispersion) {
    WXGMeshOptics o={0};
    o.padX=o.padY=64;
    o.width=width+2*o.padX; o.height=height+2*o.padY;
    o.kyantMode=1; o.kyantHeight=press*band; o.kyantAmount=press*amount;
    o.edgeWidth=WXG_MAX(.5f,o.kyantHeight); o.dispersion=dispersion;
    o.fieldScale=o.zoomAfter=1;
    return o;
}

static float sourceDepth(WXGMeshOptics o,float x,float outputDepth,int bottom) {
    float y=bottom?o.height-o.padY-outputDepth:o.padY+outputDepth;
    float sx,sy;
    WXGMeshSource(o,x,y,&sx,&sy);
    return bottom?o.height-o.padY-sy:sy-o.padY;
}

/* Measure the outer mirrored lip thickness (first downward crossing of t_edge)
   and verify a clean page gap exists before the direct inner bar. */
static float outerLipWidth(WXGMeshOptics o,float x,int bottom,float edgeDepth,float *outMinDepth) {
    float minS=1e9f,lipEnd=-1.f;
    int sawGap=0,sawDirect=0;
    for(int j=0;j<=600;j++) {
        float t=j*.025f;
        float s=sourceDepth(o,x,t,bottom);
        assert(isfinite(s));
        if(s<minS)minS=s;
        if(lipEnd<0.f && s<edgeDepth)lipEnd=t;
        if(lipEnd>=0.f && s<edgeDepth)sawGap=1;
        if(sawGap && s>=edgeDepth){sawDirect=1;break;}
    }
    if(outMinDepth)*outMinDepth=minS;
    assert(lipEnd>0.f && sawGap && sawDirect);
    return lipEnd;
}

static void checkCrownTaper(void) {
    WXGMeshOptics o=dock(124,70,1,18,26,2.4f);
    o.kyantChannel=0.f; /* green / central ray */
    for(int bottom=0;bottom<=1;bottom++) {
        float minApex=0.f;
        float w0=outerLipWidth(o,o.width*.5f,bottom,7.5f,&minApex);
        float w2=outerLipWidth(o,o.width*.5f+2.f,bottom,7.5f,NULL);
        float w12=outerLipWidth(o,o.width*.5f+12.f,bottom,7.5f,NULL);
        float w24=outerLipWidth(o,o.width*.5f+24.f,bottom,7.5f,NULL);
        /* Crisp ~2..3 pt mirrored outer lip at apex, clean gap below 7.5 pt. */
        assert(w0>=1.8f && w0<=3.2f);
        assert(minApex<6.8f);
        /* Smooth zero-slope minimum at apex, gently widening toward the necks. */
        assert(fabsf(w2-w0)<.08f);
        assert(w12>=w0 && w24>w12+.10f);
        /* Left-right symmetry of central ray. */
        float wL=outerLipWidth(o,o.width*.5f-24.f,bottom,7.5f,NULL);
        assert(fabsf(wL-w24)<.06f);
    }
    /* Works cleanly at deeper pinch (0.25 -> edge at ~11.7 pt) too. */
    float wDeep=outerLipWidth(o,o.width*.5f,0,11.7f,NULL);
    assert(wDeep>=.7f && wDeep<=2.5f);
}

static void checkCrownDispersionAndCenterCrispness(void) {
    WXGMeshOptics o=dock(124,70,1,18,26,2.4f);
    /* Top and bottom center have non-zero smooth spectral separation on the rim,
       while the central icon/text zone (depth >= 16 pt) is completely unsplit. */
    for(int bottom=0;bottom<=1;bottom++) {
        o.kyantChannel=1.f;  float sRed=sourceDepth(o,o.width*.5f,2.0f,bottom);
        o.kyantChannel=-1.f; float sBlue=sourceDepth(o,o.width*.5f,2.0f,bottom);
        assert(fabsf(sRed-sBlue)>1.5f);
        /* Center stays razor-sharp (zero dispersion, identity mapping). */
        o.kyantChannel=1.f;  float cRed=sourceDepth(o,o.width*.5f,20.f,bottom);
        o.kyantChannel=-1.f; float cBlue=sourceDepth(o,o.width*.5f,20.f,bottom);
        assert(fabsf(cRed-20.f)<1e-4f && fabsf(cBlue-20.f)<1e-4f);
    }
    /* Smoothly vanishes as press -> 0 or dispersion -> 0. */
    WXGMeshOptics zeroD=dock(124,70,1,18,26,0.f);
    zeroD.kyantChannel=1.f;  float a=sourceDepth(zeroD,zeroD.width*.5f,2.f,0);
    zeroD.kyantChannel=-1.f; float b=sourceDepth(zeroD,zeroD.width*.5f,2.f,0);
    assert(fabsf(a-b)<1e-5f);
    WXGMeshOptics rest=dock(124,70,0,18,26,2.4f);
    rest.kyantChannel=1.f;
    assert(fabsf(sourceDepth(rest,rest.width*.5f,2.f,0)-2.f)<1e-5f);
}

static void checkRoundAndEndRelaxation(void) {
    /* Round capsule limit is continuous (no discontinuity at width == height). */
    wxg_kf2_t half1={35.f,35.f},half2={35.001f,35.f};
    wxg_kf2_t p1={35.f,2.f},p2={35.001f,2.f};
    wxg_kf2_t r1=WXGKyantSpectralRay(p1,half1,half1,35.f,18,26,2.4f,0,0,0,1.f,NULL);
    wxg_kf2_t r2=WXGKyantSpectralRay(p2,half2,half2,35.f,18,26,2.4f,0,0,0,1.f,NULL);
    assert(hypotf(r1.x-r2.x,r1.y-r2.y)<.02f);
    /* End-tab relaxation narrows the wrapping end cap to the crisp crown band
       while leaving the opposite inner end full width and x=0 C1-smooth. */
    float hMid=0,aMid=0,cMid=0,hWrap=0,aWrap=0,cWrap=0,hInner=0,aInner=0,cInner=0;
    WXGKyantCrownBands((wxg_kf2_t){60,0},(wxg_kf2_t){62,35},18,26,0,0,&hMid,&aMid,&cMid);
    WXGKyantCrownBands((wxg_kf2_t){60,0},(wxg_kf2_t){62,35},18,26,0,1,&hWrap,&aWrap,&cWrap);
    WXGKyantCrownBands((wxg_kf2_t){-60,0},(wxg_kf2_t){62,35},18,26,0,1,&hInner,&aInner,&cInner);
    assert(fabsf(hMid-18.f)<.05f && fabsf(hInner-18.f)<.05f);
    assert(hWrap<9.f && aWrap<24.f && cWrap>.99f);
    /* Zero horizontal seam across x = 0 when endRight == 1. */
    float hL=0,hC=0,hR=0;
    WXGKyantCrownBands((wxg_kf2_t){-.5f,-33},(wxg_kf2_t){62,35},18,26,0,1,&hL,NULL,NULL);
    WXGKyantCrownBands((wxg_kf2_t){0.f,-33},(wxg_kf2_t){62,35},18,26,0,1,&hC,NULL,NULL);
    WXGKyantCrownBands((wxg_kf2_t){.5f,-33},(wxg_kf2_t){62,35},18,26,0,1,&hR,NULL,NULL);
    assert(fabsf(hR-2.f*hC+hL)<.05f);
}

static void checkMeshes(void) {
    static WXGMeshPoint points[20000];
    static unsigned int faces[20000][4];
    float configs[][3]={{10,14,1},{18,26,2.4f},{8.643f,8.987f,1.57f},{40,50,5}};
    int worstVerts=0;
    for(unsigned c=0;c<4;c++)for(int step=1;step<=4;step++)for(int k=0;k<7;k++) {
        float press=step*.25f;
        WXGMeshOptics o=dock(108+20*press,66+4*press,press,configs[c][0],configs[c][1],configs[c][2]);
        o.sbLeft=o.padX-80; o.sbRight=o.sbLeft+398;
        o.sbTop=o.padY+4; o.sbBottom=o.height-o.padY-4;
        o.shrinkPress=press; o.shrinkPinch=.12f;
        o.kyantChannel=WXGKyantSpectralOffset(k);
        int nf=0;
        int n=WXGBuildContourMesh(o,(WXGMeshQuality){.12f,.08f,8},points,20000,faces,20000,&nf);
        assert(n>0 && nf>0 && n<12000);
        if(n>worstVerts)worstVerts=n;
        for(int i=0;i<n;i++) {
            assert(isfinite(points[i].fromX)&&isfinite(points[i].fromY));
            assert(points[i].fromX>=0.f&&points[i].fromX<=1.f&&points[i].fromY>=0.f&&points[i].fromY<=1.f);
        }
    }
    printf("PASS: iOS 26 tapered crown lip, clean gap, continuous 7-tap dispersion, end-tab wrap, and %d max mesh vertices.\n",worstVerts);
}

static void checkElasticFixedInnerBarHeight(void) {
    /* Fast horizontal sliding elastically squashes/swells the lens height while
       the inner bar inside the lens must stay strictly at the fixed bodyPinch
       inset (never collapsing inset -> 0 when squashed nor expanding when swollen). */
    const float barH=62.f,restH=75.f,pinch=.18f;
    const float expectedHalf=barH*.5f*(1.f-pinch);
    const float scales[]={.85f,.90f,.95f,1.00f,1.10f,1.20f};
    for(unsigned i=0;i<sizeof(scales)/sizeof(scales[0]);i++) {
        float lensH=restH*scales[i];
        float lensW=124.f/scales[i];
        WXGMeshOptics o=dock(lensW,lensH,1.f,18.f,26.f,2.4f);
        o.kyantChannel=0.f;
        o.sbLeft=o.padX-80.f; o.sbRight=o.sbLeft+398.f;
        o.sbTop=(o.height-barH)*.5f; o.sbBottom=(o.height+barH)*.5f;
        o.shrinkPress=1.f; o.shrinkPinch=pinch;
        /* Pass rest-height squash pad as WXGGlassView does; also verify negative
           or positive shrinkExtra never shifts the fixed bodyPinch target. */
        o.shrinkExtra=fmaxf(0.f,(restH-lensH)*.5f);
        float cy=o.height*.5f,cx=o.width*.5f;
        /* Binary-search screen row where source hits the real bar top edge. */
        float lo=o.padY+6.5f,hi=cy;
        for(int it=0;it<50;it++) {
            float m=.5f*(lo+hi),sx,sy;
            WXGMeshSource(o,cx,m,&sx,&sy);
            if(sy<o.sbTop)lo=m; else hi=m;
        }
        float topEdgeDist=cy-hi;
        assert(fabsf(topEdgeDist-expectedHalf)<.15f);
        /* Verify bottom symmetry. */
        lo=cy; hi=o.height-o.padY-6.5f;
        for(int it=0;it<50;it++) {
            float m=.5f*(lo+hi),sx,sy;
            WXGMeshSource(o,cx,m,&sx,&sy);
            if(sy>o.sbBottom)hi=m; else lo=m;
        }
        float botEdgeDist=lo-cy;
        assert(fabsf(botEdgeDist-expectedHalf)<.15f);
    }
    /* Even at extreme squash (lens shorter than real bar: 54 pt < 62 pt),
       WXGKyantSceneSourceDepth keeps full fixed inset with zero collapse. */
    float squashPad=(restH-54.f)*.5f;
    wxg_kf2_t center={100.f,100.f},lensSz={148.f,54.f},barOrg={-40.f,100.f-barH*.5f},barSz={398.f,barH};
    wxg_kf2_t edgePt={100.f,100.f-expectedHalf};
    wxg_kf2_t mapped=WXGKyantSceneSourceDepth(edgePt,edgePt,center,lensSz,0.f,barOrg,barSz,0.f,1.f,pinch,0.f,squashPad,1.f);
    assert(fabsf(mapped.y-barOrg.y)<1e-3f);
    printf("PASS: elastic fast-slide inner bar height locked to fixed bodyPinch (%.2f pt half-height across 0.85x..1.20x and extreme squash).\n",expectedHalf);
}

int main(void) {
    checkCrownTaper();
    checkCrownDispersionAndCenterCrispness();
    checkRoundAndEndRelaxation();
    checkMeshes();
    checkElasticFixedInnerBarHeight();
    return 0;
}
