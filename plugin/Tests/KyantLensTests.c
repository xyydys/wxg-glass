/* FIX122: Kyant 透镜模式 (Sources/WXGKyantLens.h, its branch in
   Sources/WXGMeshRefraction.h). */
#include "../Sources/WXGMeshRefraction.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

/* The lens of the catalog at full press, in a 160 x 70 pt capsule (long
   enough for its top middle to be straight: no continuous-corner correction). */
static WXGMeshOptics kyant(float dispersion,float channel) {
    WXGMeshOptics o;memset(&o,0,sizeof o);
    o.width=160;o.height=70;o.fieldScale=1;o.offsetScale=1;o.zoomBefore=1;o.zoomAfter=1;
    o.edgeWidth=12.5f;o.kyHeight=12.5f;o.kyAmount=17.5f;o.dispersion=dispersion;o.channel=channel;
    return o;
}


/* Kyant's shader (RoundedRectRefractionWithDispersionShaderString), line for
   line, for one channel's mean tap: the reference. */
static float kSd(float px,float py,float hx,float hy,float r){float cx=fabsf(px)-(hx-r),cy=fabsf(py)-(hy-r);float ox=fmaxf(cx,0),oy=fmaxf(cy,0);return sqrtf(ox*ox+oy*oy)-r+fminf(fmaxf(cx,cy),0);}
static void kGrad(float px,float py,float hx,float hy,float r,float *gx,float *gy){
    float cx=fabsf(px)-(hx-r),cy=fabsf(py)-(hy-r);float sx=px<0?-1.f:px>0?1.f:0.f,sy=py<0?-1.f:py>0?1.f:0.f;
    if(cx>=0 || cy>=0){float ox=fmaxf(cx,0),oy=fmaxf(cy,0),l=sqrtf(ox*ox+oy*oy);*gx=sx*ox/l;*gy=sy*oy/l;}
    else{float g=cy<=cx?1.f:0.f;*gx=sx*g;*gy=sy*(1-g);}
}
static void kyantShaderD(float w,float h,float height,float amount,float channel,float depth,float x,float y,float *ox,float *oy);
static void kyantShader(float w,float h,float height,float amount,float channel,float x,float y,float *ox,float *oy){kyantShaderD(w,h,height,amount,channel,0,x,y,ox,oy);}
static void kyantShaderD(float w,float h,float height,float amount,float channel,float depth,float x,float y,float *ox,float *oy){
    float hx=w*.5f,hy=h*.5f,r=fminf(hx,hy),cx=x-hx,cy=y-hy;
    float sd=kSd(cx,cy,hx,hy,r);*ox=x;*oy=y;
    if(-sd>=height)return;
    sd=fminf(sd,0);
    float u=1-(-sd/height),d=(1-sqrtf(1-u*u))*-amount,gx,gy;
    kGrad(cx,cy,hx,hy,fminf(r*1.5f,fminf(hx,hy)),&gx,&gy);
    float cl=sqrtf(cx*cx+cy*cy);if(depth>0 && cl>0){gx+=depth*cx/cl;gy+=depth*cy/cl;}
    float l=sqrtf(gx*gx+gy*gy);gx/=l;gy/=l;
    float I=(cx*cy)/(hx*hy),k=channel>.5f?3.f/7.f:channel<-.5f?-2.f/3.f:2.f/21.f;
    *ox=x+d*gx+d*gx*I*k;*oy=y+d*gy+d*gy*I*k;
}

int main(void) {
    /* The curve: the whole amount at the outline, nothing at the band's end,
       reached with zero slope, never negative, monotonic; held outside. */
    CHECK(fabsf(WXGKyantOffset(0,10,14)-14)<1e-5f,"the whole amount at the outline");
    CHECK(WXGKyantOffset(10,10,14)==0 && WXGKyantOffset(25,10,14)==0,"nothing at and past the band");
    CHECK(fabsf(WXGKyantOffset(-3,10,14)-14)<1e-5f,"outside: held at the outline's");
    CHECK(WXGKyantOffset(5,0,14)==0 && WXGKyantOffset(5,10,0)==0,"off");
    float previous=1e9f;
    for(float t=0;t<=10;t+=.05f){float v=WXGKyantOffset(t,10,14);CHECK(v>=0 && v<=previous+1e-5f,"monotonic at %.2f",t);previous=v;}
    CHECK((WXGKyantOffset(9.9f,10,14)-WXGKyantOffset(9.95f,10,14))/.05f<.2f,"zero slope at the band's end");
    CHECK(fabsf(WXGKyantOffset(5,10,14)-14*(1-sqrtf(.75f)))<1e-5f,"a quarter circle");
    /* The edge mirrors: the source depth t + offset first falls (from the
       amount at the outline) then rises back to the band's end. */
    float s0=0+WXGKyantOffset(0,10,14),s4=4.2f+WXGKyantOffset(4.2f,10,14),s10=10+WXGKyantOffset(10,10,14);
    CHECK(s4<s0 && s4<s10 && fabsf(s10-10)<1e-5f,"the rounded edge's mirror (%.2f %.2f %.2f)",s0,s4,s10);

    /* The channel weights are the shader's 7 taps averaged per channel. */
    const float at[7]={1,2.f/3,1.f/3,0,-1.f/3,-2.f/3,-1};
    const float wr[7]={1/3.5f,1/3.5f,1/3.5f,0,0,0,1/7.f},wg[7]={0,1/7.f,1/3.5f,1/3.5f,1/3.5f,0,0},wb[7]={0,0,0,0,1/3.f,1/3.f,1/3.f};
    const float *ws[3]={wr,wg,wb};
    for(int c=0;c<3;c++) {
        float sum=0,mean=0;for(int k=0;k<7;k++){sum+=ws[c][k];mean+=ws[c][k]*at[k];}
        CHECK(fabsf(sum-1)<1e-5f,"channel %d weights add up to 1 (%.5f)",c,sum);
        CHECK(fabsf(mean-WXGKyantChannelWeight(c==0?1.f:c==1?0.f:-1.f))<1e-5f,"channel %d mean %.5f",c,mean);
    }
    CHECK(fabsf(WXG_KYANT_CHANNEL_SPAN-fabsf(WXGKyantChannelWeight(-1)))<1e-6f,"the span is blue's");
    /* The intensity: 0 on the middle lines, opposite quarters opposite. */
    CHECK(WXGKyantDispersionIntensity(0,-30,50,35)==0 && WXGKyantDispersionIntensity(40,0,50,35)==0,"0 on the middle lines");
    CHECK(WXGKyantDispersionIntensity(-40,-30,50,35)>0 && WXGKyantDispersionIntensity(40,30,50,35)>0 &&
          WXGKyantDispersionIntensity(40,-30,50,35)<0 && WXGKyantDispersionIntensity(-40,30,50,35)<0,"quarters");

    /* The mesh source. Top middle on the outline: straight in by the amount,
       every channel alike (I = 0 there). Centre: unmoved. */
    float sx,sy,gx,gy,rx,ry,bx,by;
    WXGMeshSource(kyant(0,0),80,0,&sx,&sy);
    CHECK(fabsf(sx-80)<1e-3f && fabsf(sy-17.5f)<1e-3f,"top middle: %.3f %.3f",sx,sy);
    WXGMeshSource(kyant(1,1),80,0,&rx,&ry);WXGMeshSource(kyant(1,-1),80,0,&bx,&by);
    CHECK(fabsf(rx-sx)<1e-3f && fabsf(ry-sy)<1e-3f && fabsf(bx-sx)<1e-3f && fabsf(by-sy)<1e-3f,"no split on the middle line");
    WXGMeshSource(kyant(1,1),80,35,&rx,&ry);
    CHECK(fabsf(rx-80)<1e-4f && fabsf(ry-35)<1e-4f,"centre unmoved");
    /* Deeper than the band: unmoved. */
    WXGMeshSource(kyant(1,1),80,14,&rx,&ry);
    CHECK(fabsf(rx-80)<1e-4f && fabsf(ry-14)<1e-4f,"past the band unmoved");
    /* In the top-left and top-right ends (on the round end, 2 pt in): red
       further in than green, blue less, and the other way in the other end. */
    float a=2.3561945f,ex=35+35*cosf(a)*.94f,ey=35-35*sinf(a)*.94f;   /* left end, upper half */
    WXGMeshOptics g=kyant(1,0),r=kyant(1,1),b=kyant(1,-1);
    WXGMeshSource(g,ex,ey,&gx,&gy);WXGMeshSource(r,ex,ey,&rx,&ry);WXGMeshSource(b,ex,ey,&bx,&by);
    float dg=hypotf(gx-ex,gy-ey),dr=hypotf(rx-ex,ry-ey),db=hypotf(bx-ex,by-ey);
    CHECK(dr>dg && db<dg && dg>0,"top-left: red further in (%.3f %.3f %.3f)",dr,dg,db);
    float fx=160-ex;
    WXGMeshSource(g,fx,ey,&gx,&gy);WXGMeshSource(r,fx,ey,&rx,&ry);WXGMeshSource(b,fx,ey,&bx,&by);
    dg=hypotf(gx-fx,gy-ey);dr=hypotf(rx-fx,ry-ey);db=hypotf(bx-fx,by-ey);
    CHECK(dr<dg && db>dg,"top-right: the other way (%.3f %.3f %.3f)",dr,dg,db);
    /* Split off (dispersion 0): the channel does nothing. */
    WXGMeshSource(kyant(0,1),ex,ey,&rx,&ry);WXGMeshSource(kyant(0,0),ex,ey,&gx,&gy);
    CHECK(rx==gx && ry==gy,"no split without dispersion");
    /* Zoom after the shift, about the centre, as the band path. */
    WXGMeshOptics z=kyant(0,0);z.zoomAfter=1.25f;
    WXGMeshSource(z,80,0,&sx,&sy);
    CHECK(fabsf(sx-80)<1e-3f && fabsf(sy-(35+(17.5f-35)/1.25f))<1e-3f,"zoom after");
    /* kyHeight 0: exactly the band path (the old lens). */
    WXGMeshOptics old;memset(&old,0,sizeof old);
    old.width=100;old.height=70;old.fieldScale=1;old.edgeWidth=10;old.refraction=6;old.offsetScale=1;old.zoomBefore=1;old.zoomAfter=1.2f;
    old.dispersion=1.5f;old.channel=1;old.topRatio=.6f;old.sharpness=3;
    WXGMeshOptics same=old;same.kyAmount=17.5f;   /* height 0: off */
    for(float px=0;px<=100;px+=7)for(float py=0;py<=70;py+=5) {
        float ax,ay,cx2,cy2;WXGMeshSource(old,px,py,&ax,&ay);WXGMeshSource(same,px,py,&cx2,&cy2);
        CHECK(ax==cx2 && ay==cy2,"off: the old lens at %.0f %.0f",px,py);
    }


    /* Against the shader itself. Where the outline is straight (the
       plugin's capsule follows iOS's continuous corners, which reach about
       0.45 x the height along the top past the round end; his is a circle):
       his sample exactly. On the round ends the outline differs by that
       correction and the curve is infinitely steep at the outline, so there
       the shift's direction (same sense) and each channel's order around
       green are compared, 1 pt or more inside. */
    {
        int worstAt=0;float worstStraight=0;int ends=0,endBad=0;
        for(int c=-1;c<=1;c++)for(float x=1;x<160;x+=1.5f)for(float y=.25f;y<70;y+=.75f) {
            WXGMeshOptics m=kyant(1,(float)c);
            float ax,ay,bx2,by2;WXGMeshSource(m,x,y,&ax,&ay);kyantShader(160,70,12.5f,17.5f,(float)c,x,y,&bx2,&by2);
            if(x>52 && x<108){float e=hypotf(ax-bx2,ay-by2);if(e>worstStraight){worstStraight=e;worstAt=(int)x;}continue;}
            WXGShapeSample f=WXGCapsuleOpticalField(x-80,y-35,160,70);
            if(-f.distance<1.f || -f.distance>11.5f)continue;
            float gx,gy,hx2,hy2;WXGMeshSource(kyant(1,0),x,y,&gx,&gy);kyantShader(160,70,12.5f,17.5f,0,x,y,&hx2,&hy2);
            float pdx=ax-x,pdy=ay-y,sdx=bx2-x,sdy=by2-y;
            float dot=pdx*sdx+pdy*sdy,np=hypotf(pdx,pdy),ns=hypotf(sdx,sdy);
            float order=((ax-gx)*(bx2-hx2)+(ay-gy)*(by2-hy2));
            ++ends;
            if((np>.05f && ns>.05f && dot<.9f*np*ns) || order<-1e-4f)++endBad;
        }
        CHECK(worstStraight<1e-3f,"straight part: the shader's own sample (%.5f at x %d)",worstStraight,worstAt);
        CHECK(ends>100 && endBad*50<ends,"round ends: the shader's direction and channel order (%d of %d off)",endBad,ends);
        printf("vs shader: straight %.5f pt; round ends %d of %d samples off\n",worstStraight,endBad,ends);
    }
    /* FIX122 D: depthEffect (his normalize(normal + normalize(p - centre)))
       on the straight part exactly his; zoom before (a button's press) about
       the centre, then the shift. */
    {
        float worst=0;
        for(int c=-1;c<=1;c++)for(float x=53;x<108;x+=1.5f)for(float y=.25f;y<70;y+=.75f) {
            WXGMeshOptics m=kyant(1,(float)c);m.kyDepth=1;
            float ax,ay,bx2,by2;WXGMeshSource(m,x,y,&ax,&ay);kyantShaderD(160,70,12.5f,17.5f,(float)c,1,x,y,&bx2,&by2);
            float e=hypotf(ax-bx2,ay-by2);if(e>worst)worst=e;
        }
        CHECK(worst<1e-3f,"depthEffect: his sample on the straight part (%.5f)",worst);
        WXGMeshOptics d=kyant(0,0);d.kyDepth=1;float dx,dy;WXGMeshSource(d,60,1,&dx,&dy);
        CHECK(dx>60.5f,"depthEffect bends toward the centre (%.3f)",dx);
        WXGMeshOptics z=kyant(0,0);z.zoomBefore=1.04f;float zx,zy;
        WXGMeshSource(z,100,35,&zx,&zy);
        CHECK(fabsf(zx-(80+20/1.04f))<1e-3f && fabsf(zy-35)<1e-3f,"zoom before about the centre (%.4f)",zx);
    }

    /* FIX122 E: the thin outermost ring capped. Cap 0: his curve exactly;
       capped: his curve deeper than the tangent point, C1 there, the squeeze
       |d(t + offset)/dt| never above the cap, less shift at the outline. */
    {
        for(float t=0;t<=10;t+=.01f)CHECK(WXGKyantOffsetCapped(t,10,20,0)==WXGKyantOffset(t,10,20),"cap 0 is his at %.2f",t);
        float K=3,H=10,A=20,c=(1+K)*H/A,u0=c/sqrtf(1+c*c),t0=(1-u0)*H;
        for(float t=t0+.01f;t<=H;t+=.05f)CHECK(fabsf(WXGKyantOffsetCapped(t,H,A,K)-WXGKyantOffset(t,H,A))<1e-4f,"his curve past the tangent point (%.2f)",t);
        float h=1e-3f,l=WXGKyantOffsetCapped(t0-h,H,A,K),m=WXGKyantOffsetCapped(t0,H,A,K),r=WXGKyantOffsetCapped(t0+h,H,A,K);
        CHECK(fabsf((m-l)/h-(r-m)/h)<.05f,"C1 at the tangent point (%.4f %.4f)",(m-l)/h,(r-m)/h);
        float worst=0;
        for(float t=0;t<H;t+=.001f){float d=fabsf(1.f+(WXGKyantOffsetCapped(t+.001f,H,A,K)-WXGKyantOffsetCapped(t,H,A,K))/.001f);if(d>worst)worst=d;}
        CHECK(worst<=K+.05f,"the squeeze at most the cap (%.3f)",worst);
        float hisWorst=0;
        for(float t=0;t<H;t+=.001f){float d=fabsf(1.f+(WXGKyantOffset(t+.001f,H,A)-WXGKyantOffset(t,H,A))/.001f);if(d>hisWorst)hisWorst=d;}
        CHECK(hisWorst>20,"his squeezes far more at the outline (%.1f)",hisWorst);
        float rim=WXGKyantOffsetCapped(0,H,A,K)/A;
        CHECK(rim>.7f && rim<.8f,"3x: about three quarters of the shift at the outline (%.3f)",rim);
        CHECK(WXGKyantOffsetCapped(-2,H,A,K)==WXGKyantOffsetCapped(0,H,A,K),"outside: held");
        WXGMeshOptics m2=kyant(1,1);m2.kyRimMax=3;
        static WXGMeshPoint P2[20000];static unsigned int F2[20000][4];int f2=0;
        CHECK(WXGBuildContourMesh(m2,(WXGMeshQuality){.20f,.16f,24.f},P2,20000,F2,20000,&f2)>0 && f2>0,"capped mesh builds");
    }

    /* The contour mesh builds, within the capacity, for every channel and
       with the smaller bar; every vertex is the source of its point. */
    enum { CAP=20000 };
    static WXGMeshPoint P[CAP];static unsigned int F[CAP][4];
    WXGMeshQuality lensBar={.12f,.08f,8.f};
    for(int c=-1;c<=1;c++) {
        WXGMeshOptics m=kyant(1,(float)c);
        m.sbLeft=-10000;m.sbRight=10000;m.sbTop=6;m.sbBottom=64;m.shrinkPress=1;m.shrinkPinch=.18f;
        int faces=0,n=WXGBuildContourMesh(m,lensBar,P,CAP,F,CAP,&faces);
        CHECK(n>0 && faces>0,"channel %d: mesh built (%d vertices)",c,n);
        int bad=0;
        for(int k=0;k<n;k++) {
            float qx,qy;WXGMeshSource(m,P[k].toX*m.width,P[k].toY*m.height,&qx,&qy);
            if(fabsf(WXGMeshUnit(qx,m.width)-P[k].fromX)>1e-4f || fabsf(WXGMeshUnit(qy,m.height)-P[k].fromY)>1e-4f)++bad;
        }
        CHECK(bad==0,"channel %d: %d vertices off their source",c,bad);
        WXGMeshOptics plain=kyant(1,(float)c);
        n=WXGBuildContourMesh(plain,(WXGMeshQuality){.20f,.16f,24.f},P,CAP,F,CAP,&faces);
        CHECK(n>0 && faces>0,"channel %d: plain lens mesh built",c);
    }

    if(failures){printf("KyantLensTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: Kyant lens (FIX122): circleMap shift (whole amount at the outline, zero slope at the band's end, mirrored rim), 7-tap channel means, x*y split by quarter, mesh source (zoom, smaller bar), off = the old lens bit for bit, contour meshes built and exact; FIX122 D depthEffect as his, zoom before; FIX122 E thin ring capped (his past the tangent, C1, squeeze <= cap).\n");
    return 0;
}
