/* FIX128: iOS 26's colour split all round the lens' outline (the ring*
   fields of Sources/WXGMeshRefraction.h), against what was measured on the
   system tab bar's lifted lens (probe 2, the grid under it; WXGDockSystem.h). */
#include "../Sources/WXGMeshRefraction.h"
#include "../Sources/WXGDockSystem.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

/* The system's lifted lens: 123.5 x 70 pt, the band 7 pt and the shift 17.5 pt
   (0.10 and 0.25 of its height), at full press. */
static WXGMeshOptics lens(float channel) {
    WXGMeshOptics o;memset(&o,0,sizeof o);
    o.width=123.5f;o.height=70;o.fieldScale=1;o.offsetScale=1;o.zoomBefore=1;o.zoomAfter=1;
    o.edgeWidth=7;o.kyHeight=7;o.kyAmount=17.5f;o.channel=channel;
    return o;
}
static WXGMeshOptics ring(float channel,float degrees) {
    WXGMeshOptics o=lens(channel);
    o.ringAmount=(float)WXG_DOCK26_SPLIT;o.ringWidth=(float)WXG_DOCK26_SPLIT_WIDTH;o.ringAngle=degrees*3.14159265f/180.f;
    return o;
}
/* The depth under the top's middle that a point `t` under it shows. */
static float shown(WXGMeshOptics o,float t) {
    float sx,sy;WXGMeshSource(o,o.width*.5f,t,&sx,&sy);return sy;
}
/* Where (depth, searched from `from` to `to`) the picture's depth `edge` shows. */
static float where(WXGMeshOptics o,float edge,float from,float to) {
    float step=(to-from)/4000.f,previous=shown(o,from)-edge;
    for(int i=1;i<=4000;i++) {
        float t=from+step*(float)i,now=shown(o,t)-edge;
        if((previous<=0.f)!=(now<=0.f))return t-step*now/(now-previous);
        previous=now;
    }
    return -1;
}
int main(void) {
    /* Off: nothing of it (whatever its width and angle say). */
    for(int c=-1;c<=1;c++) {
        WXGMeshOptics plain=lens((float)c),off=ring((float)c,15);off.ringAmount=0;
        for(float y=-2;y<=72;y+=.37f)for(float x=-2;x<=125.5f;x+=1.9f) {
            float ax,ay,bx,by;WXGMeshSource(plain,x,y,&ax,&ay);WXGMeshSource(off,x,y,&bx,&by);
            if(memcmp(&ax,&bx,sizeof ax) || memcmp(&ay,&by,sizeof ay)){CHECK(0,"off: channel %d differs at %.2f, %.2f",c,x,y);y=100;break;}
        }
        for(float t=-1;t<20;t+=.13f)CHECK(WXGMeshDepthSource(plain,7,7,t,(float)c)==WXGMeshDepthSource(off,7,7,t,(float)c),"off: ring depths");
    }
    /* The move: 0.8 pt at the outline, (1 - depth / 14)^2 inward, none past 14 pt. */
    WXGMeshOptics r=ring(1,0);
    CHECK(fabsf(WXGMeshRingShift(r,0)-.8f)<1e-6f && fabsf(WXGMeshRingShift(r,-3)-.8f)<1e-6f,"at and outside the outline");
    CHECK(fabsf(WXGMeshRingShift(r,7)-.2f)<1e-6f,"half way in: a quarter (%.4f)",WXGMeshRingShift(r,7));
    CHECK(WXGMeshRingShift(r,14)==0.f && WXGMeshRingShift(r,30)==0.f,"none from its width on");
    CHECK(WXGMeshRingBand(r)==14.f && WXGMeshRingBand(lens(1))==0.f,"the band the mesh needs");
    /* Green is where it was; red shows what green shows further out, blue further in
       (straight on: no turn), under the top's middle and beside an end. */
    for(float t=.05f;t<20;t+=.21f) {
        float a=WXGMeshRingShift(r,t);
        CHECK(shown(ring(0,0),t)==shown(lens(0),t),"green unchanged at %.2f",t);
        CHECK(fabsf(shown(ring(1,0),t)-shown(lens(1),t-a))<2e-4f,"red at %.2f is the picture %.3f further out",t,a);
        CHECK(fabsf(shown(ring(-1,0),t)-shown(lens(-1),t+a))<2e-4f,"blue at %.2f is the picture %.3f further in",t,a);
        float gx,gy,rx,ry;   /* the left end's middle: the normal points left */
        WXGMeshSource(lens(1),t-a,35,&gx,&gy);WXGMeshSource(ring(1,0),t,35,&rx,&ry);
        CHECK(fabsf(rx-gx)<2e-4f && fabsf(ry-gy)<2e-4f,"the end at %.2f: red is the picture further out",t);
    }
    /* What probe 2 saw (lens points): the bar's edge lies 7.49 pt under the
       lens' top in the picture the lens refracts; it shows twice, mirrored
       in the outer sliver and again past the band. Per colour: red deeper,
       blue nearer the outline, both times. */
    {
        const float edge=7.49f;
        float g1=where(ring(0,15),edge,.3f,5),g2=where(ring(0,15),edge,5,12);
        float r1=where(ring(1,15),edge,.3f,5),r2=where(ring(1,15),edge,5,12);
        float b1=where(ring(-1,15),edge,.3f,5),b2=where(ring(-1,15),edge,5,12);
        CHECK(g1>1.5f && g1<2.6f,"green's mirrored edge (%.2f; recorded 2.45)",g1);
        CHECK(fabsf(g2-7.49f)<.01f,"green's edge past the band (%.2f)",g2);
        /* recorded gaps to green: outer 0.55 / 0.60 (top), 0.61 / 0.51 (bottom); inner 0.22 / 0.27 and 0.05 / 0.19 */
        CHECK(fabsf((r1-g1)-.57f)<.12f && fabsf((g1-b1)-.56f)<.12f,"the mirrored edge splits by about 0.57 pt (red +%.2f, blue -%.2f)",r1-g1,g1-b1);
        CHECK(fabsf((r2-g2)-.18f)<.08f && fabsf((g2-b2)-.18f)<.08f,"the edge past the band by about 0.18 pt (red +%.2f, blue -%.2f)",r2-g2,g2-b2);
        CHECK(r1>g1 && g1>b1 && r2>g2 && g2>b2,"red deeper, blue nearer the outline, both times");
        /* Kyant's own split has none here (the top's middle), whatever its strength. */
        WXGMeshOptics kr=lens(1),kb=lens(-1);kr.dispersion=kb.dispersion=3;
        CHECK(fabsf(where(kr,edge,.3f,5)-where(kb,edge,.3f,5))<1e-3f,"his split: none at the top's middle");
        /* Other depths recorded with the lens taller / flatter: 0.50 at 2.7, 0.27 at 6.45, 0.10 at 9 pt. */
        const float depths[3]={2.7f,6.45f,9.f},gaps[3]={.50f,.27f,.10f};
        for(int i=0;i<3;i++)CHECK(fabsf(WXGMeshRingShift(r,depths[i])-gaps[i])<.07f,"at %.2f pt: %.2f (recorded %.2f)",depths[i],WXGMeshRingShift(r,depths[i]),gaps[i]);
    }
    /* The turn (15 degrees): a line crossing the outline splits sideways,
       opposite ways above and below: above, red's copy to the right of
       green's and blue's to the left (recorded: about 0.13 pt at 5 pt). A
       copy lies to the right when its colour reads the picture further left. */
    {
        float gx,gy,rx,ry,bx,by,t=5.05f,x=60;
        WXGMeshSource(ring(0,15),x,t,&gx,&gy);WXGMeshSource(ring(1,15),x,t,&rx,&ry);WXGMeshSource(ring(-1,15),x,t,&bx,&by);
        CHECK(rx<gx && bx>gx,"above: red reads left of green, blue right (%.3f, %.3f)",rx-gx,bx-gx);
        CHECK(fabsf((gx-rx)-.085f)<.03f,"by sin 15 of the move there (%.3f)",gx-rx);
        WXGMeshSource(ring(0,15),x,70-t,&gx,&gy);WXGMeshSource(ring(1,15),x,70-t,&rx,&ry);WXGMeshSource(ring(-1,15),x,70-t,&bx,&by);
        CHECK(rx>gx && bx<gx,"below: the other way (%.3f, %.3f)",rx-gx,bx-gx);
        WXGMeshSource(ring(0,0),x,t,&gx,&gy);WXGMeshSource(ring(1,0),x,t,&rx,&ry);
        CHECK(fabsf(rx-gx)<1e-5f,"no turn: no sideways split");
    }
    /* The contour mesh builds for every colour, each vertex the source of
       its point; red's and blue's differ in the ring and agree with green's
       deeper than the ring and the band. */
    {
        enum { CAP=20000 };
        static WXGMeshPoint P[CAP];static unsigned int F[CAP][4];
        WXGMeshQuality quality={.20f,.16f,24.f};
        for(int c=-1;c<=1;c++) {
            WXGMeshOptics m=ring((float)c,15);
            int faces=0,n=WXGBuildContourMesh(m,quality,P,CAP,F,CAP,&faces);
            CHECK(n>0 && faces>0,"channel %d: mesh built (%d vertices)",c,n);
            int bad=0;
            for(int k=0;k<n;k++) {
                float qx,qy;WXGMeshSource(m,P[k].toX*m.width,P[k].toY*m.height,&qx,&qy);
                if(fabsf(WXGMeshUnit(qx,m.width)-P[k].fromX)>1e-4f || fabsf(WXGMeshUnit(qy,m.height)-P[k].fromY)>1e-4f)++bad;
            }
            CHECK(bad==0,"channel %d: %d vertices off their source",c,bad);
            /* rings all through the split's band (a ring every 1.5 pt at most) */
            float rings[256];int count=WXGMeshRings(m,35,2,quality,rings,256),within=0;
            for(int i=0;i<count;i++)if(rings[i]>7.5f && rings[i]<14.f)++within;
            CHECK(within>=4,"channel %d: %d rings between the band and the split's end",c,within);
        }
        float ax,ay,bx,by;
        WXGMeshSource(ring(1,15),61,3,&ax,&ay);WXGMeshSource(ring(-1,15),61,3,&bx,&by);
        CHECK(fabsf(ay-by)>.3f,"red and blue apart in the ring (%.3f)",ay-by);
        WXGMeshSource(ring(1,15),61,20,&ax,&ay);WXGMeshSource(ring(-1,15),61,20,&bx,&by);
        CHECK(ax==bx && ay==by,"and together deeper in");
    }
    if(failures){printf("%d FAILED\n",failures);return 1;}
    puts("PASS: the lens' ring colour split (FIX128): off = unchanged; 0.8 pt x (1 - depth / 14)^2 along the turned normal, red out and blue in; the recorded edges' gaps (0.57 / 0.18 pt) and sideways split; meshes build.");
    return 0;
}
