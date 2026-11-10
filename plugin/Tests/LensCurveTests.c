/* The glass' refraction curve and colour split (Sources/WXGLensCurve.h, its
   branch in Sources/WXGMeshRefraction.h). */
#include "../Sources/WXGMeshRefraction.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

/* The lens of the catalog at full press, in a 160 x 70 pt capsule (long
   enough for its top middle to be straight: no continuous-corner correction). */
static WXGMeshOptics lens(float dispersion,float channel) {
    WXGMeshOptics o;memset(&o,0,sizeof o);
    o.width=160;o.height=70;o.fieldScale=1;o.offsetScale=1;o.zoomBefore=1;o.zoomAfter=1;
    o.edgeWidth=12.5f;o.curveHeight=12.5f;o.curveAmount=17.5f;o.dispersion=dispersion;o.channel=channel;
    return o;
}


int main(void) {
    /* The curve: the whole amount at the outline, nothing at the band's end,
       reached with zero slope, never negative, monotonic; held outside. */
    CHECK(fabsf(WXGLensCurveOffset(0,10,14)-14)<1e-5f,"the whole amount at the outline");
    CHECK(WXGLensCurveOffset(10,10,14)==0 && WXGLensCurveOffset(25,10,14)==0,"nothing at and past the band");
    CHECK(fabsf(WXGLensCurveOffset(-3,10,14)-14)<1e-5f,"outside: held at the outline's");
    CHECK(WXGLensCurveOffset(5,0,14)==0 && WXGLensCurveOffset(5,10,0)==0,"off");
    float previous=1e9f;
    for(float t=0;t<=10;t+=.05f){float v=WXGLensCurveOffset(t,10,14);CHECK(v>=0 && v<=previous+1e-5f,"monotonic at %.2f",t);previous=v;}
    CHECK((WXGLensCurveOffset(9.9f,10,14)-WXGLensCurveOffset(9.95f,10,14))/.05f<.2f,"zero slope at the band's end");
    CHECK(fabsf(WXGLensCurveOffset(5,10,14)-14*(1-sqrtf(.75f)))<1e-5f,"a quarter circle");
    /* The edge mirrors: the source depth t + offset first falls (from the
       amount at the outline) then rises back to the band's end. */
    float s0=0+WXGLensCurveOffset(0,10,14),s4=4.2f+WXGLensCurveOffset(4.2f,10,14),s10=10+WXGLensCurveOffset(10,10,14);
    CHECK(s4<s0 && s4<s10 && fabsf(s10-10)<1e-5f,"the rounded edge's mirror (%.2f %.2f %.2f)",s0,s4,s10);

    /* The channel weights: seven samples along the spectrum, averaged per channel. */
    const float at[7]={1,2.f/3,1.f/3,0,-1.f/3,-2.f/3,-1};
    const float wr[7]={1/3.5f,1/3.5f,1/3.5f,0,0,0,1/7.f},wg[7]={0,1/7.f,1/3.5f,1/3.5f,1/3.5f,0,0},wb[7]={0,0,0,0,1/3.f,1/3.f,1/3.f};
    const float *ws[3]={wr,wg,wb};
    for(int c=0;c<3;c++) {
        float sum=0,mean=0;for(int k=0;k<7;k++){sum+=ws[c][k];mean+=ws[c][k]*at[k];}
        CHECK(fabsf(sum-1)<1e-5f,"channel %d weights add up to 1 (%.5f)",c,sum);
        CHECK(fabsf(mean-WXGLensSplitWeight(c==0?1.f:c==1?0.f:-1.f))<1e-5f,"channel %d mean %.5f",c,mean);
    }
    CHECK(fabsf(WXG_LENS_SPLIT_SPAN-fabsf(WXGLensSplitWeight(-1)))<1e-6f,"the span is blue's");
    /* The intensity: 0 on the middle lines, opposite quarters opposite. */
    CHECK(WXGLensSplitIntensity(0,-30,50,35)==0 && WXGLensSplitIntensity(40,0,50,35)==0,"0 on the middle lines");
    CHECK(WXGLensSplitIntensity(-40,-30,50,35)>0 && WXGLensSplitIntensity(40,30,50,35)>0 &&
          WXGLensSplitIntensity(40,-30,50,35)<0 && WXGLensSplitIntensity(-40,30,50,35)<0,"quarters");

    /* The mesh source. Top middle on the outline: straight in by the amount,
       every channel alike (I = 0 there). Centre: unmoved. */
    float sx,sy,gx,gy,rx,ry,bx,by;
    WXGMeshSource(lens(0,0),80,0,&sx,&sy);
    CHECK(fabsf(sx-80)<1e-3f && fabsf(sy-17.5f)<1e-3f,"top middle: %.3f %.3f",sx,sy);
    WXGMeshSource(lens(1,1),80,0,&rx,&ry);WXGMeshSource(lens(1,-1),80,0,&bx,&by);
    CHECK(fabsf(rx-sx)<1e-3f && fabsf(ry-sy)<1e-3f && fabsf(bx-sx)<1e-3f && fabsf(by-sy)<1e-3f,"no split on the middle line");
    WXGMeshSource(lens(1,1),80,35,&rx,&ry);
    CHECK(fabsf(rx-80)<1e-4f && fabsf(ry-35)<1e-4f,"centre unmoved");
    /* Deeper than the band: unmoved. */
    WXGMeshSource(lens(1,1),80,14,&rx,&ry);
    CHECK(fabsf(rx-80)<1e-4f && fabsf(ry-14)<1e-4f,"past the band unmoved");
    /* In the top-left and top-right ends (on the round end, 2 pt in): red
       further in than green, blue less, and the other way in the other end. */
    float a=2.3561945f,ex=35+35*cosf(a)*.94f,ey=35-35*sinf(a)*.94f;   /* left end, upper half */
    WXGMeshOptics g=lens(1,0),r=lens(1,1),b=lens(1,-1);
    WXGMeshSource(g,ex,ey,&gx,&gy);WXGMeshSource(r,ex,ey,&rx,&ry);WXGMeshSource(b,ex,ey,&bx,&by);
    float dg=hypotf(gx-ex,gy-ey),dr=hypotf(rx-ex,ry-ey),db=hypotf(bx-ex,by-ey);
    CHECK(dr>dg && db<dg && dg>0,"top-left: red further in (%.3f %.3f %.3f)",dr,dg,db);
    float fx=160-ex;
    WXGMeshSource(g,fx,ey,&gx,&gy);WXGMeshSource(r,fx,ey,&rx,&ry);WXGMeshSource(b,fx,ey,&bx,&by);
    dg=hypotf(gx-fx,gy-ey);dr=hypotf(rx-fx,ry-ey);db=hypotf(bx-fx,by-ey);
    CHECK(dr<dg && db>dg,"top-right: the other way (%.3f %.3f %.3f)",dr,dg,db);
    /* Split off (dispersion 0): the channel does nothing. */
    WXGMeshSource(lens(0,1),ex,ey,&rx,&ry);WXGMeshSource(lens(0,0),ex,ey,&gx,&gy);
    CHECK(rx==gx && ry==gy,"no split without dispersion");
    /* Zoom after the shift, about the centre, as the band path. */
    WXGMeshOptics z=lens(0,0);z.zoomAfter=1.25f;
    WXGMeshSource(z,80,0,&sx,&sy);
    CHECK(fabsf(sx-80)<1e-3f && fabsf(sy-(35+(17.5f-35)/1.25f))<1e-3f,"zoom after");
    /* curveHeight 0: exactly the band path. */
    WXGMeshOptics old;memset(&old,0,sizeof old);
    old.width=100;old.height=70;old.fieldScale=1;old.edgeWidth=10;old.refraction=6;old.offsetScale=1;old.zoomBefore=1;old.zoomAfter=1.2f;
    old.dispersion=1.5f;old.channel=1;old.topRatio=.6f;old.sharpness=3;
    WXGMeshOptics same=old;same.curveAmount=17.5f;   /* height 0: off */
    for(float px=0;px<=100;px+=7)for(float py=0;py<=70;py+=5) {
        float ax,ay,cx2,cy2;WXGMeshSource(old,px,py,&ax,&ay);WXGMeshSource(same,px,py,&cx2,&cy2);
        CHECK(ax==cx2 && ay==cy2,"off: the band path at %.0f %.0f",px,py);
    }


    /* Where the outline is straight (the top and the bottom of the capsule's
       middle) the source is the formula itself: the point moved along the
       normal by d (1 + I k), d the curve's shift at its depth, I = x y over
       the half sides (from the centre), k the channel's weight. */
    {
        float worst=0;int worstAt=0;
        for(int c=-1;c<=1;c++)for(float x=53;x<108;x+=1.5f)for(float y=.25f;y<70;y+=.75f) {
            WXGMeshOptics m=lens(1,(float)c);
            float ax,ay;WXGMeshSource(m,x,y,&ax,&ay);
            float depth=y<35?y:70-y,d=WXGLensCurveOffset(depth,12.5f,17.5f),I=((x-80)/80)*((y-35)/35);
            float want=y+(y<35?1.f:-1.f)*d*(1+I*WXGLensSplitWeight((float)c));
            float e=hypotf(ax-x,ay-want);if(e>worst){worst=e;worstAt=(int)x;}
        }
        CHECK(worst<1e-3f,"straight part: the formula's own sample (%.5f at x %d)",worst,worstAt);
        /* Zoom before (a button's press) about the centre, then the shift. */
        WXGMeshOptics z=lens(0,0);z.zoomBefore=1.04f;float zx,zy;
        WXGMeshSource(z,100,35,&zx,&zy);
        CHECK(fabsf(zx-(80+20/1.04f))<1e-3f && fabsf(zy-35)<1e-3f,"zoom before about the centre (%.4f)",zx);
    }

    /* FIX122 E: the thin outermost ring capped. Cap 0: the curve exactly;
       capped: the curve deeper than the tangent point, C1 there, the squeeze
       |d(t + offset)/dt| never above the cap, less shift at the outline. */
    {
        for(float t=0;t<=10;t+=.01f)CHECK(WXGLensCurveOffsetCapped(t,10,20,0)==WXGLensCurveOffset(t,10,20),"cap 0 is the curve at %.2f",t);
        float K=3,H=10,A=20,c=(1+K)*H/A,u0=c/sqrtf(1+c*c),t0=(1-u0)*H;
        for(float t=t0+.01f;t<=H;t+=.05f)CHECK(fabsf(WXGLensCurveOffsetCapped(t,H,A,K)-WXGLensCurveOffset(t,H,A))<1e-4f,"the curve past the tangent point (%.2f)",t);
        float h=1e-3f,l=WXGLensCurveOffsetCapped(t0-h,H,A,K),m=WXGLensCurveOffsetCapped(t0,H,A,K),r=WXGLensCurveOffsetCapped(t0+h,H,A,K);
        CHECK(fabsf((m-l)/h-(r-m)/h)<.05f,"C1 at the tangent point (%.4f %.4f)",(m-l)/h,(r-m)/h);
        float worst=0;
        for(float t=0;t<H;t+=.001f){float d=fabsf(1.f+(WXGLensCurveOffsetCapped(t+.001f,H,A,K)-WXGLensCurveOffsetCapped(t,H,A,K))/.001f);if(d>worst)worst=d;}
        CHECK(worst<=K+.05f,"the squeeze at most the cap (%.3f)",worst);
        float plainWorst=0;
        for(float t=0;t<H;t+=.001f){float d=fabsf(1.f+(WXGLensCurveOffset(t+.001f,H,A)-WXGLensCurveOffset(t,H,A))/.001f);if(d>plainWorst)plainWorst=d;}
        CHECK(plainWorst>20,"uncapped it squeezes far more at the outline (%.1f)",plainWorst);
        float rim=WXGLensCurveOffsetCapped(0,H,A,K)/A;
        CHECK(rim>.7f && rim<.8f,"3x: about three quarters of the shift at the outline (%.3f)",rim);
        CHECK(WXGLensCurveOffsetCapped(-2,H,A,K)==WXGLensCurveOffsetCapped(0,H,A,K),"outside: held");
        WXGMeshOptics m2=lens(1,1);m2.curveSqueeze=3;
        static WXGMeshPoint P2[20000];static unsigned int F2[20000][4];int f2=0;
        CHECK(WXGBuildContourMesh(m2,(WXGMeshQuality){.20f,.16f,24.f},P2,20000,F2,20000,&f2)>0 && f2>0,"capped mesh builds");
    }

    /* The contour mesh builds, within the capacity, for every channel and
       with the smaller bar; every vertex is the source of its point. */
    enum { CAP=20000 };
    static WXGMeshPoint P[CAP];static unsigned int F[CAP][4];
    WXGMeshQuality lensBar={.12f,.08f,8.f};
    for(int c=-1;c<=1;c++) {
        WXGMeshOptics m=lens(1,(float)c);
        m.sbLeft=-10000;m.sbRight=10000;m.sbTop=6;m.sbBottom=64;m.shrinkPress=1;m.shrinkPinch=.18f;
        int faces=0,n=WXGBuildContourMesh(m,lensBar,P,CAP,F,CAP,&faces);
        CHECK(n>0 && faces>0,"channel %d: mesh built (%d vertices)",c,n);
        int bad=0;
        for(int k=0;k<n;k++) {
            float qx,qy;WXGMeshSource(m,P[k].toX*m.width,P[k].toY*m.height,&qx,&qy);
            if(fabsf(WXGMeshUnit(qx,m.width)-P[k].fromX)>1e-4f || fabsf(WXGMeshUnit(qy,m.height)-P[k].fromY)>1e-4f)++bad;
        }
        CHECK(bad==0,"channel %d: %d vertices off their source",c,bad);
        WXGMeshOptics plain=lens(1,(float)c);
        n=WXGBuildContourMesh(plain,(WXGMeshQuality){.20f,.16f,24.f},P,CAP,F,CAP,&faces);
        CHECK(n>0 && faces>0,"channel %d: plain lens mesh built",c);
    }

    if(failures){printf("LensCurveTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: lens curve: quarter-circle shift (whole amount at the outline, zero slope at the band's end, mirrored rim), capped squeeze, channel means, x*y split by quarter, mesh source (zoom, smaller bar), contour mesh\n");
    return 0;
}
