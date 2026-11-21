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
        assert(minApex<6.4f);
        /* Uniform iOS 26 ClearGlassView bevel: smooth zero-slope apex, NO fat
           18 pt fleshy corner neck bulge toward the shoulders (only the ~0.48 pt
           WXGCapsule26 shoulder dip). */
        assert(fabsf(w2-w0)<.08f);
        assert(w12>=1.8f && w12<=3.4f && w24>=1.8f && w24<=3.8f);
        /* Left-right symmetry of central ray. */
        float wL=outerLipWidth(o,o.width*.5f-24.f,bottom,7.5f,NULL);
        assert(fabsf(wL-w24)<.05f);
    }
    /* Works cleanly at deeper pinch (0.25 -> edge at ~11.7 pt) too. */
    float wDeep=outerLipWidth(o,o.width*.5f,0,11.7f,NULL);
    assert(wDeep>=.7f && wDeep<=2.2f);
}

static void checkCrownDispersionAndCenterCrispness(void) {
    WXGMeshOptics o=dock(124,70,1,18,26,2.4f);
    /* Top and bottom outer bevel have strong smooth spectral separation,
       inner bar edge (depth = 9.5 pt) stays crisp with minimal spread, and
       the central icon/text zone (depth >= 16 pt) is completely unsplit. */
    for(int bottom=0;bottom<=1;bottom++) {
        o.kyantChannel=1.f;  float sRed=sourceDepth(o,o.width*.5f,2.0f,bottom);
        o.kyantChannel=-1.f; float sBlue=sourceDepth(o,o.width*.5f,2.0f,bottom);
        assert(fabsf(sRed-sBlue)>1.5f);
        /* Inner bar edge stays razor-sharp (steep ringU^2.5 envelope). */
        o.kyantChannel=1.f;  float bRed=sourceDepth(o,o.width*.5f,9.5f,bottom);
        o.kyantChannel=-1.f; float bBlue=sourceDepth(o,o.width*.5f,9.5f,bottom);
        assert(fabsf(bRed-bBlue)<0.55f);
        /* Center stays razor-sharp (zero dispersion, identity mapping). */
        o.kyantChannel=1.f;  float cRed=sourceDepth(o,o.width*.5f,16.f,bottom);
        o.kyantChannel=-1.f; float cBlue=sourceDepth(o,o.width*.5f,16.f,bottom);
        assert(fabsf(cRed-16.f)<1e-4f && fabsf(cBlue-16.f)<1e-4f);
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
    /* Verify real iOS 26 ClearGlassView (0.105 / 0.31 * shortSide) and separate
       ContentLensingView (0.20 / 0.26 * shortSide) proportions. */
    float hBg=0,aBg=0,hIc=0,aIc=0;
    WXGKyantCrownTarget(35.f,18.f,26.f,&hBg,&aBg);
    WXGKyantIconTarget(35.f,18.f,26.f,&hIc,&aIc);
    assert(fabsf(hBg-7.35f)<.05f && fabsf(aBg-21.7f)<.1f);
    assert(fabsf(hIc-14.0f)<.05f && fabsf(aIc-18.2f)<.1f);
    /* Uniform glassBackground wraps naturally around 3/9 o'clock end tabs with
       both a crisp outer lip (>= 1.2 pt) and a clean dark crescent (< 10.5 pt). */
    float endMinS=1e9f,endLip=-1.f;
    wxg_kf2_t endHalf={54.f,35.f};
    for(int j=0;j<=600;j++) {
        float t=j*.025f;
        wxg_kf2_t ray=WXGKyantRefractPoint(WXG_K_MAKE2(108.f-t,35.f),endHalf,endHalf,35.f,18.f,26.f,0.f,0.f,1.f,NULL,NULL,NULL,NULL);
        float s=108.f-ray.x;
        if(s<endMinS)endMinS=s;
        if(endLip<0.f && s<12.5f)endLip=t;
    }
    assert(endLip>=0.9f && endLip<=3.5f && endMinS<10.5f);
    /* Zero horizontal seam across x = 0 when endRight == 1. */
    float hL=0,hC=0,hR=0;
    WXGKyantCrownBands((wxg_kf2_t){-.5f,-33},(wxg_kf2_t){62,35},18,26,0,1,&hL,NULL,NULL);
    WXGKyantCrownBands((wxg_kf2_t){0.f,-33},(wxg_kf2_t){62,35},18,26,0,1,&hC,NULL,NULL);
    WXGKyantCrownBands((wxg_kf2_t){.5f,-33},(wxg_kf2_t){62,35},18,26,0,1,&hR,NULL,NULL);
    assert(fabsf(hR-2.f*hC+hL)<.01f);
}

static void checkR9SymmetryNoPinchAndCapsule26(void) {
    wxg_kf2_t hs={62.f,35.f};
    /* 1. Strict 4-quadrant symmetry & zero Top-Right / Bottom-Left pinch knot
          at both low (ca = 1.0) and max (ca = 5.0) dispersion. */
    float xs[]={12.f,24.f,34.f,42.f,50.f};
    for(unsigned i=0;i<sizeof(xs)/sizeof(xs[0]);i++) {
        float dx=xs[i];
        float yEdge=-35.f;
        for(float y=-35.f;y<0.f;y+=.02f) {
            if(WXGKyantSdRoundedRect(WXG_K_MAKE2(dx,y),hs,35.f)<=0.f){yEdge=y;break;}
        }
        float spLo[4],spMid[4],spHi[4];
        float sx[4]={-1.f,1.f,1.f,-1.f},sy[4]={-1.f,-1.f,1.f,1.f};
        for(int q=0;q<4;q++) {
            wxg_kf2_t p=WXG_K_MAKE2(hs.x+sx[q]*dx,hs.y+sy[q]*(yEdge+2.f));
            wxg_kf2_t a1=WXGKyantSpectralRay(p,hs,hs,35.f,18.f,26.f,1.0f,0.f,0.f,0.f,1.f,NULL);
            wxg_kf2_t b1=WXGKyantSpectralRay(p,hs,hs,35.f,18.f,26.f,1.0f,0.f,0.f,0.f,-1.f,NULL);
            spLo[q]=hypotf(a1.x-b1.x,a1.y-b1.y);
            wxg_kf2_t a2=WXGKyantSpectralRay(p,hs,hs,35.f,18.f,26.f,2.4f,0.f,0.f,0.f,1.f,NULL);
            wxg_kf2_t b2=WXGKyantSpectralRay(p,hs,hs,35.f,18.f,26.f,2.4f,0.f,0.f,0.f,-1.f,NULL);
            spMid[q]=hypotf(a2.x-b2.x,a2.y-b2.y);
            wxg_kf2_t a3=WXGKyantSpectralRay(p,hs,hs,35.f,18.f,26.f,5.0f,0.f,0.f,0.f,1.f,NULL);
            wxg_kf2_t b3=WXGKyantSpectralRay(p,hs,hs,35.f,18.f,26.f,5.0f,0.f,0.f,0.f,-1.f,NULL);
            spHi[q]=hypotf(a3.x-b3.x,a3.y-b3.y);
            /* Never pinches to zero in Top-Right (q=1) or Bottom-Left (q=3),
               and widens strictly monotonically from ca=1.0 -> 2.4 -> 5.0. */
            assert(spLo[q]>1.5f);
            assert(spMid[q]>spLo[q]*1.8f);
            assert(spHi[q]>spMid[q]*1.4f);
            /* At 3.5 pt inside the perimeter glow band, ca=5.0 widens ~2x over ca=2.4. */
            wxg_kf2_t pIn=WXG_K_MAKE2(hs.x+sx[q]*dx,hs.y+sy[q]*(yEdge+3.5f));
            wxg_kf2_t i2a=WXGKyantSpectralRay(pIn,hs,hs,35.f,18.f,26.f,2.4f,0.f,0.f,0.f,1.f,NULL);
            wxg_kf2_t i2b=WXGKyantSpectralRay(pIn,hs,hs,35.f,18.f,26.f,2.4f,0.f,0.f,0.f,-1.f,NULL);
            wxg_kf2_t i3a=WXGKyantSpectralRay(pIn,hs,hs,35.f,18.f,26.f,5.0f,0.f,0.f,0.f,1.f,NULL);
            wxg_kf2_t i3b=WXGKyantSpectralRay(pIn,hs,hs,35.f,18.f,26.f,5.0f,0.f,0.f,0.f,-1.f,NULL);
            float inMid=hypotf(i2a.x-i2b.x,i2a.y-i2b.y),inHi=hypotf(i3a.x-i3b.x,i3a.y-i3b.y);
            assert(inHi>inMid*1.80f);
        }
        for(int q=1;q<4;q++) {
            assert(fabsf(spLo[q]-spLo[0])<1e-3f);
            assert(fabsf(spMid[q]-spMid[0])<1e-3f);
            assert(fabsf(spHi[q]-spHi[0])<1e-3f);
        }
    }
    /* 2. WXGCapsule26 continuous shoulder dip (~1.36% R at junction x = hx-R,
          0 at apex x = 0, 0 on plain circles and rounded rectangles). */
    float dipApex=WXGKyantCapsule26Offset(WXG_K_MAKE2(0.f,-35.f),hs,35.f);
    float dipJunc=WXGKyantCapsule26Offset(WXG_K_MAKE2(hs.x-35.f,-35.f),hs,35.f);
    float dipCirc=WXGKyantCapsule26Offset(WXG_K_MAKE2(0.f,-35.f),WXG_K_MAKE2(35.f,35.f),35.f);
    float dipRect=WXGKyantCapsule26Offset(WXG_K_MAKE2(hs.x-12.f,-35.f),hs,12.f);
    assert(fabsf(dipApex)<1e-5f && fabsf(dipCirc)<1e-5f && fabsf(dipRect)<1e-5f);
    assert(dipJunc>0.40f && dipJunc<0.55f); /* 0.0136 * 35 = 0.476 pt */
    /* 3. Both 11-tap backdrop and 15-tap glyph spectral weights sum strictly to (1, 1, 1). */
    float br=0.f,bg=0.f,bb=0.f;
    for(int k=0;k<WXG_KYANT_SPECTRAL_TAPS;k++) {
        wxg_kf3_t w=WXGKyantSpectralRGBWeight(k);
        br+=w.x; bg+=w.y; bb+=w.z;
    }
    assert(fabsf(br-1.f)<1e-4f && fabsf(bg-1.f)<1e-4f && fabsf(bb-1.f)<1e-4f);
    float sr=0.f,sg=0.f,sb=0.f;
    for(int k=0;k<WXG_KYANT_GLYPH_TAPS;k++) {
        wxg_kf3_t w=WXGKyantGlyphSpectralRGBWeight(k);
        sr+=w.x; sg+=w.y; sb+=w.z;
    }
    assert(fabsf(sr-1.f)<1e-4f && fabsf(sg-1.f)<1e-4f && fabsf(sb-1.f)<1e-4f);
    /* 4. ContentLensingView pre-refraction glyph ray is symmetric & vivid near rim, identity in center. */
    wxg_kf2_t gL1=WXGKyantGlyphSpectralRay(WXG_K_MAKE2(2.f,35.f),hs,hs,35.f,18.f,26.f,2.4f,1.f,NULL);
    wxg_kf2_t gL2=WXGKyantGlyphSpectralRay(WXG_K_MAKE2(2.f,35.f),hs,hs,35.f,18.f,26.f,2.4f,-1.f,NULL);
    wxg_kf2_t gR1=WXGKyantGlyphSpectralRay(WXG_K_MAKE2(122.f,35.f),hs,hs,35.f,18.f,26.f,2.4f,1.f,NULL);
    wxg_kf2_t gR2=WXGKyantGlyphSpectralRay(WXG_K_MAKE2(122.f,35.f),hs,hs,35.f,18.f,26.f,2.4f,-1.f,NULL);
    float gSpL=hypotf(gL1.x-gL2.x,gL1.y-gL2.y),gSpR=hypotf(gR1.x-gR2.x,gR1.y-gR2.y);
    assert(gSpL>4.f && fabsf(gSpL-gSpR)<1e-3f);
    wxg_kf2_t gMid=WXGKyantGlyphSpectralRay(hs,hs,hs,35.f,18.f,26.f,2.4f,1.f,NULL);
    assert(hypotf(gMid.x-hs.x,gMid.y-hs.y)<1e-4f);
    printf("PASS: R10 4-quadrant symmetry, zero TR/BL pinch, monotonic ca=1..5 widening, WXGCapsule26 dip (%.3f pt), 11/15-tap neutral weights.\n",dipJunc);
}

static void checkMeshes(void) {
    static WXGMeshPoint points[20000];
    static unsigned int faces[20000][4];
    float configs[][3]={{10,14,1},{18,26,2.4f},{8.643f,8.987f,1.57f},{40,50,5}};
    int worstVerts=0;
    for(unsigned c=0;c<4;c++)for(int step=1;step<=4;step++)for(int k=0;k<WXG_KYANT_SPECTRAL_TAPS;k++) {
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
    printf("PASS: R10 uniform iOS 26 ClearGlassView bevel, clean gap, unblurred 11-tap dispersion, end-tab wrap, and %d max mesh vertices.\n",worstVerts);
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
    checkR9SymmetryNoPinchAndCapsule26();
    checkMeshes();
    checkElasticFixedInnerBarHeight();
    return 0;
}
