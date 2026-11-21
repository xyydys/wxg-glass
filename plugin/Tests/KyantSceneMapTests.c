
#include <assert.h>
#include <stdio.h>
#include <math.h>
#include "../Sources/WXGMeshRefraction.h"
int main(void) {
    int n=0;float worst=0;
    for(int pos=0;pos<3;pos++)for(int pr=1;pr<=4;pr++)for(int pin=0;pin<=3;pin++)for(int ext=-1;ext<=1;ext++) {
        WXGMeshOptics o={0};o.width=160;o.height=110;o.padX=o.padY=20;
        o.sbLeft=-100+pos*80;o.sbRight=o.sbLeft+300;o.sbTop=25;o.sbBottom=85;
        o.shrinkPress=pr*.25f;o.shrinkPinch=pin*.1f;o.shrinkExtra=ext*3.f;
        float zoom=1+o.shrinkPress*.16f;
        for(int y=20;y<=90;y+=5)for(int x=20;x<=140;x+=5) {
            float sx=80+(x-80)/zoom,sy=55+(y-55)/zoom;
            wxg_kf2_t p=WXGKyantSceneSource(WXG_K_MAKE2(sx,sy),WXG_K_MAKE2(x,y),WXG_K_MAKE2(80,55),WXG_K_MAKE2(120,70),0,
                WXG_K_MAKE2(o.sbLeft,o.sbTop),WXG_K_MAKE2(300,60),0,o.shrinkPress,o.shrinkPinch,o.shrinkExtra,zoom);
            WXGMeshShrinkBar(o,x,y,zoom,&sx,&sy);
            float err=fmaxf(fabsf(p.x-sx),fabsf(p.y-sy));worst=fmaxf(worst,err);assert(err<.0001f);n++;
        }
    }
    // Reference mesh remains finite and changes both background channels and inset.
    WXGMeshOptics o={0};o.width=160;o.height=110;o.padX=o.padY=20;
    o.zoomAfter=1.16f;o.kyantMode=1;o.kyantHeight=18;o.kyantAmount=26;o.dispersion=2.4;
    o.sbLeft=-80;o.sbRight=240;o.sbTop=25;o.sbBottom=85;o.shrinkPress=1;o.shrinkPinch=.25;
    int split=0,shrink=0;
    for(int y=21;y<90;y+=3)for(int x=21;x<140;x+=3) {
        float a,b,c,d,e,f;o.kyantChannel=1;WXGMeshSource(o,x,y,&a,&b);
        o.kyantChannel=-1;WXGMeshSource(o,x,y,&c,&d);
        o.shrinkPinch=0;WXGMeshSource(o,x,y,&e,&f);o.shrinkPinch=.25;
        assert(isfinite(a)&&isfinite(b)&&isfinite(c)&&isfinite(d));
        if(fabsf(a-c)+fabsf(b-d)>.01)split++;
        if(fabsf(c-e)+fabsf(d-f)>.01)shrink++;
    }
    assert(split>0&&shrink>0);
    printf("R4 original shrink parity: %d samples, worst %.8f pt; native spectral/shrink pixels %d/%d\n",n,worst,split,shrink);
    static WXGMeshPoint points[20000];static unsigned int faces[20000][4];
    int meshes=0,maxVertices=0;
    for(int size=0;size<3;size++)for(int pr=1;pr<=4;pr++)for(int k=0;k<7;k++) {
        WXGMeshOptics m={0};float pad=60,press=pr*.25f;
        m.width=100+size*20+2*pad;m.height=60+size*10+2*pad;m.padX=m.padY=pad;
        m.fieldScale=1;m.zoomAfter=1+press*.16f;m.kyantMode=1;m.kyantHeight=18*press;m.edgeWidth=m.kyantHeight;
        m.kyantAmount=26*press;m.dispersion=2.4f;m.kyantChannel=WXGKyantSpectralOffset(k);
        m.sbLeft=-80+pad;m.sbRight=240+pad;m.sbTop=pad+5;m.sbBottom=pad+65;
        m.shrinkPress=press;m.shrinkPinch=.2558f;
        int count=0;int verts=WXGBuildContourMesh(m,(WXGMeshQuality){.12f,.08f,8.f},points,20000,faces,20000,&count);
        assert(verts>3 && count>0);if(verts>maxVertices)maxVertices=verts;
        for(int i=0;i<verts;i++)assert(isfinite(points[i].fromX)&&isfinite(points[i].fromY));
        meshes++;
    }
    printf("R4 adaptive spectral meshes: %d builds within native capacity; max %d vertices.\n",meshes,maxVertices);

}
