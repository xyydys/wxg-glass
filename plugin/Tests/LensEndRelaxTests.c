/* FIX57: at the dock's ends the band that bends the bar seen through the lens
   (and the page behind it) relaxes toward the top / bottom width
   (WXGLensOptics.h), checked with the user's FIX54 screenshot geometry: drawn
   bar 18.00..395.83 x 67.17 pt, lens 110 x 79.83 pt, band 20.26 pt at the
   ends, top/bottom ratio 0.305, curve 3, refraction 4.21, inset 0.131 (the
   FIX49 settings). Everything else is FIX47's lens. */
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "../Sources/WXGMeshRefraction.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
static const float BX0=18.f,BX1=395.83f,BH=67.17f,LW=110.f,LH=79.83f;
static const float SIDE=20.26f,RATIO=.305f,SHARP=3.f,REFR=4.21f,PINCH=.131f;
static float reachR(float cx,float lw){return WXGLensEndReach(BX0,BX1,cx-lw*.5f,cx+lw*.5f,1);}
static float reachL(float cx,float lw){return WXGLensEndReach(BX0,BX1,cx-lw*.5f,cx+lw*.5f,-1);}
/* The shader's inner bar (WXGGlass.metal, render-server lens path) at a screen
   point, bar scale 1: < 0 where the inner bar covers it. `relax` 0 = FIX47. */
static float innerBar(float px,float py,float cx,int relax) {
    WXGShapeSample lens=WXGCapsuleOpticalField(px-cx,py,LW,LH);
    float barDistance=WXGCapsuleOpticalField(px-(BX0+BX1)*.5f,py,BX1-BX0,BH).distance;
    float lensWidth=WXGLensEdgeWidthAtBar(lens.nx,lens.ny,SIDE,RATIO,SHARP,barDistance);
    float band=lensWidth;
    if(relax)band=WXGLensEndRelax(lensWidth,lens.nx,SIDE,RATIO,reachL(cx,LW),reachR(cx,LW));
    float off=WXGOpticalOffset(lens.distance,band,REFR);
    float bx=px-lens.nx*off,by=py-lens.ny*off;
    return WXGCapsuleOpticalField(bx-(BX0+BX1)*.5f,by,BX1-BX0,BH).distance+WXGInnerInset(BH,1,PINCH,lens.distance);
}
/* FIX47's WXGMeshSource, written out for comparison. */
static void fix47Source(WXGMeshOptics o,float px,float py,float *sx,float *sy) {
    float cx=o.width*.5f,cy=o.height*.5f;
    WXGShapeSample f=WXGCapsuleOpticalField(px-cx,py-cy,o.width,o.height);
    float bw=o.barRight-o.barLeft,bh=o.barBottom-o.barTop;
    WXGShapeSample b=WXGCapsuleOpticalField(px-(o.barLeft+bw*.5f),py-(o.barTop+bh*.5f),bw,bh);
    float width=WXGLensEdgeWidthAtBar(f.nx,f.ny,o.edgeWidth,o.topRatio,o.sharpness,b.distance);
    float off=WXGOpticalOffset(f.distance,width,o.refraction)*o.offsetScale;
    float shift=o.channel*o.dispersion*wxgEdgeC(f.distance,width);
    float rx=cx+(px-cx)-f.nx*off+f.nx*shift,ry=cy+(py-cy)-f.ny*off+f.ny*shift;
    *sx=cx+(rx-cx)/o.zoomAfter;*sy=cy+(ry-cy)/o.zoomAfter;
}
int main(void) {
    unsigned checks=0;
    const float top=SIDE*RATIO;
    /* 1. Relax: reach 0 returns the width exactly; reach 1 is the top / bottom
          width on that half and leaves the other half alone; monotonic, never
          below the top width or above the width it starts from. */
    for(int a=0;a<720;a++){float t=a*3.14159265f/360.f,nx=cosf(t),ny=sinf(t);
        for(int bd=-12;bd<=12;bd+=3){float w=WXGLensEdgeWidthAtBar(nx,ny,SIDE,RATIO,SHARP,(float)bd);
            assert(WXGLensEndRelax(w,nx,SIDE,RATIO,0,0)==w);
            float r=WXGLensEndRelax(w,nx,SIDE,RATIO,0,1),l=WXGLensEndRelax(w,nx,SIDE,RATIO,1,0);
            if(nx>=0)assert(fabsf(r-top)<1e-4f); else assert(r==w);
            if(nx<0)assert(fabsf(l-top)<1e-4f); else assert(l==w);
            float prev=1e9f;
            for(int k=0;k<=20;k++){float v=WXGLensEndRelax(w,nx,SIDE,RATIO,k/20.f,k/20.f);
                assert(v<=prev+1e-5f && v>=top-1e-4f && v<=w+1e-5f);prev=v;++checks;}}}
    assert(WXGLensEndRelax(SIDE,1,SIDE,1,1,1)==SIDE);   /* isotropic lens: nothing to relax */
    /* 2. Reach: 0 until the lens's outer edge is 10 pt short of the bar's end
          (lens centre 330.83), a smooth rise, 1 once it is 2 pt past it (342.83).
          The lens resting on the last tab wraps the end by endWrap, 2..10 pt
          (default 4, centre 344.83): always fully relaxed there. Mirrored on the
          left end; the other end never relaxes. */
    float start=BX1-WXG_END_START-LW*.5f,done=BX1+WXG_END_DONE-LW*.5f;
    assert(fabsf(start-330.83f)<.01f && fabsf(done-342.83f)<.01f);
    float prev=0.f,prevCX=start-10.01f,steepest=0.f;
    for(int k=-1000;k<=2500;k++){float cx=start+k*.01f,v=reachR(cx,LW);
        assert(v>=0.f && v<=1.f);
        if(k<0)assert(v==0.f);
        if(cx>done+.02f)assert(v>.9999f);
        assert(v>=prev-1e-6f);
        steepest=WXG_MAX(steepest,(v-prev)/(cx-prevCX));prev=v;prevCX=cx;
        float mirror=BX0+BX1-cx;
        assert(fabsf(reachL(mirror,LW)-v)<2e-3f && reachR(mirror,LW)==0.f && reachL(cx,LW)==0.f);
        ++checks;}
    assert(steepest<=1.5f/12.f*1.03f);                  /* smoothstep over 12 pt */
    for(float wrap=2.f;wrap<=10.f;wrap+=.5f)assert(reachR(BX1+wrap-LW*.5f,LW)>.9999f && reachL(BX0-wrap+LW*.5f,LW)>.9999f);
    /* screenshots 1 and 2 untouched, screenshot 4 about halfway */
    assert(reachR(321.17f,LW)==0.f && reachR(329.67f,LW)==0.f);
    {float v=reachR(337.67f,LW);assert(v>.4f && v<.8f);}
    /* the whole middle of the dock: FIX47 exactly */
    for(float cx=BX0+WXG_END_START+LW*.5f+.01f;cx<=start-.01f;cx+=.25f){assert(reachL(cx,LW)==0.f && reachR(cx,LW)==0.f);++checks;}
    /* a stretched or squeezed lens (elastic drag): only its outer edge counts */
    for(float lw=77.f;lw<=176.f;lw+=11.f)for(float edge=-15.f;edge<=5.f;edge+=.5f){
        float cx=BX1+edge-lw*.5f;assert(fabsf(reachR(cx,lw)-reachR(BX1+edge-LW*.5f,LW))<1e-4f);++checks;}
    /* 3. The user's picture: the lens resting on the last tab (centre 344.83).
          FIX47: along the middle row the inner bar runs right up to the lens
          edge (it sticks). FIX57: it ends inside, with a gap of at least 4 pt
          before a thin rim (under 2.5 pt). In the middle of the dock and at
          screenshot 1, FIX57 is FIX47 point for point. */
    {float cx=344.83f,x1=cx+LW*.5f;
        for(float x=x1-6.f;x<x1-.05f;x+=.05f)assert(innerBar(x,0,cx,0)<0.f);
        int rim=1;float rimEnd=0.f,gapStart=-1.f,gapEnd=-1.f;
        for(float d=.02f;d<16.f;d+=.02f){int covered=innerBar(x1-d,0,cx,1)<0.f;
            if(rim){if(!covered){rim=0;rimEnd=d;gapStart=d;}}
            else if(covered && gapEnd<0.f)gapEnd=d;}
        assert(rimEnd<2.5f && gapEnd-gapStart>=4.f);
        printf("end stop: FIX47 inner bar reaches the lens edge; FIX57 rim %.2f pt, gap %.2f pt\n",rimEnd,gapEnd-gapStart);}
    for(int i=0;i<2;i++){float cx=i?321.17f:250.f;
        for(float y=-LH*.5f;y<=LH*.5f;y+=1.f)for(float x=cx-LW*.5f;x<=cx+LW*.5f;x+=1.f){
            assert(innerBar(x,y,cx,1)==innerBar(x,y,cx,0));++checks;}}
    /* 4. The page seen through the lens (contour mesh): with the end fields 0
          it is FIX47's mesh value for value (bar fields as at the dock's end,
          all colour channels); a relaxed end refracts only inside the top /
          bottom width, the other end is FIX47's; same vertices, same count. */
    for(int c=-1;c<=1;c++){
        WXGMeshOptics none={LW,LH,1.f,0.f,SIDE,REFR,1.f,1.f,1.2f,c?1.5f:0.f,(float)c,RATIO,SHARP,-52.5f,(LH-BH)*.5f,106.f,(LH+BH)*.5f,0.f,0.f};
        WXGMeshOptics right=none;right.endRight=1.f;
        for(float y=.25f;y<LH;y+=.5f)for(float x=.25f;x<LW;x+=.5f){
            float ax,ay,bx,by,fx,fy;
            WXGMeshSource(none,x,y,&ax,&ay);fix47Source(none,x,y,&fx,&fy);
            assert(fabsf(ax-fx)<1e-5f && fabsf(ay-fy)<1e-5f);
            WXGMeshSource(right,x,y,&bx,&by);
            WXGShapeSample f=WXGCapsuleOpticalField(x-LW*.5f,y-LH*.5f,LW,LH);
            if(f.nx<0.f)assert(bx==ax && by==ay);
            else {
                float off=WXGOpticalOffset(f.distance,top,REFR),shift=(float)c*(c?1.5f:0.f)*wxgEdgeC(f.distance,top);
                float ex=LW*.5f+((x-LW*.5f)-f.nx*off+f.nx*shift)/1.2f,ey=LH*.5f+((y-LH*.5f)-f.ny*off+f.ny*shift)/1.2f;
                assert(fabsf(bx-ex)<1e-4f && fabsf(by-ey)<1e-4f);
            }
            ++checks;}
        static WXGMeshPoint pa[20000],pb[20000];static unsigned int fa[20000][4],fb[20000][4];int na=0,nb=0;
        int va=WXGBuildContourMesh(none,(WXGMeshQuality){.20f,.16f,24.f},pa,20000,fa,20000,&na);
        int vb=WXGBuildContourMesh(right,(WXGMeshQuality){.20f,.16f,24.f},pb,20000,fb,20000,&nb);
        assert(va>0 && va==vb && na==nb);
        for(int k=0;k<va;k++){assert(pa[k].toX==pb[k].toX && pa[k].toY==pb[k].toY);
            if(pa[k].toX<.5f)assert(pa[k].fromX==pb[k].fromX && pa[k].fromY==pb[k].fromY);}
    }
    printf("PASS: %u lens end checks; FIX47 band in the middle (and at screenshots 1-2), relaxed to the top width as a lens end reaches the bar's end (10 pt before .. 2 pt past), mirrored, smooth; page mesh FIX47 elsewhere.\n",checks);
    return 0;
}
