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
    o.edgeWidth=o.kyantHeight; o.dispersion=dispersion;
    o.fieldScale=o.zoomAfter=1;
    return o;
}

static float sourceDepth(WXGMeshOptics o,float x,float outputDepth,int bottom) {
    float y=bottom?o.height-o.padY-outputDepth:o.padY+outputDepth;
    float sx,sy;
    WXGMeshSource(o,x,y,&sx,&sy);
    return bottom?o.height-o.padY-sy:sy-o.padY;
}

static void checkStripe(WXGMeshOptics o) {
    float halfStraight=(WXGMeshShapeWidth(o)-WXGMeshShapeHeight(o))*.5f;
    for(int bottom=0;bottom<=1;bottom++)for(int col=-1;col<=1;col++)for(int k=0;k<7;k++) {
        o.kyantChannel=WXGKyantSpectralOffset(k);
        float x=o.width*.5f+.8f*col*halfStraight;
        float prev=sourceDepth(o,x,0,bottom);
        int crossings=0;
        for(int j=1;j<=800;j++) {
            float t=j*.025f,value=sourceDepth(o,x,t,bottom);
            assert(value>prev+.001f);
            if(prev<8 && value>=8)crossings++;
            prev=value;
        }
        assert(crossings==1);
    }
}

static wxg_kf2_t angularSample(float width,float height,float nx,float depth,float wave) {
    float ny=sqrtf(1-nx*nx),r=height*.5f;
    wxg_kf2_t half=WXG_K_MAKE2(width*.5f,r),ray,spread;
    wxg_kf2_t p=WXG_K_MAKE2(2*half.x-r+(r-depth)*nx,r-(r-depth)*ny);
    WXGKyantLensDisplace(p,half,half,r,18,26,2.4f,0,&ray,&spread,NULL);
    return WXG_K_MAKE2(ray.x+wave*spread.x,ray.y+wave*spread.y);
}

static void checkShoulders(void) {
    const float r=35,depth=2,t=1-depth/18,shift=-26*(1-sqrtf(1-t*t));
    for(int circle=0;circle<=1;circle++)for(int k=0;k<7;k++)for(int i=0;i<9;i++) {
        float width=circle?70:120,wave=WXGKyantSpectralOffset(k);
        float nx=(circle?0:.70f)+(circle?.10f:.03f)*i,ny=-sqrtf(1-nx*nx);
        wxg_kf2_t p={width-r+(r-depth)*nx,r+(r-depth)*ny};
        float quadrant=(p.x-width*.5f)*(p.y-r)/(width*.5f*r);
        float expected=shift*(1+wave*2.4f*quadrant);
        wxg_kf2_t got=angularSample(width,2*r,nx,depth,wave);
        assert(hypotf(got.x-p.x-nx*expected,got.y-p.y-ny*expected)<.0002f);
    }
    for(int k=0;k<7;k++)for(int edge=0;edge<2;edge++) {
        float at=edge?.70f:.12f,wave=WXGKyantSpectralOffset(k);
        wxg_kf2_t left=angularSample(120,70,at-.001f,2,wave);
        wxg_kf2_t mid=angularSample(120,70,at,2,wave);
        wxg_kf2_t right=angularSample(120,70,at+.001f,2,wave);
        assert(hypotf(right.x-2*mid.x+left.x,right.y-2*mid.y+left.y)<.002f);
    }
    wxg_kf2_t circle=angularSample(70,70,0,2,1);
    wxg_kf2_t almost=angularSample(70.0001f,70,0,2,1);
    assert(hypotf(circle.x-almost.x,circle.y-almost.y)<.0003f);
}

typedef struct { float y,sourceY; } Intersection;
static int byY(const void *l,const void *r) {
    float a=((const Intersection *)l)->y,b=((const Intersection *)r)->y;
    return (a>b)-(a<b);
}

static void checkNativeMesh(WXGMeshOptics o) {
    static WXGMeshPoint points[20000];
    static unsigned int faces[20000][4];
    static Intersection crossings[4096];
    int nf=0;
    int n=WXGBuildContourMesh(o,(WXGMeshQuality){.12f,.08f,8},points,20000,faces,20000,&nf);
    assert(n>0 && nf>0);
    // Intersect an off-axis column with the production quad edges and both
    // possible diagonals. Both triangulations must preserve row order.
    float x=o.width*.5f+.37f*(WXGMeshShapeWidth(o)-WXGMeshShapeHeight(o))+.03125f;
    for(int diag=0;diag<2;diag++) {
        int count=0;
        for(int i=0;i<nf;i++)for(int e=0;e<5;e++) {
            WXGMeshPoint a=points[faces[i][e==4?diag:e]],b=points[faces[i][e==4?diag+2:(e+1)%4]];
            float ax=a.toX*o.width,bx=b.toX*o.width;
            if((ax<x)==(bx<x))continue;
            float u=(x-ax)/(bx-ax);
            float y=(a.toY+u*(b.toY-a.toY))*o.height;
            if(y<o.padY || y>o.height-o.padY)continue;
            assert(count<(int)(sizeof(crossings)/sizeof(*crossings)));
            crossings[count++]=(Intersection){y,(a.fromY+u*(b.fromY-a.fromY))*o.height};
        }
        qsort(crossings,count,sizeof(*crossings),byY);
        assert(count>30);
        for(int i=1;i<count;i++) {
            float dy=crossings[i].y-crossings[i-1].y;
            float ds=crossings[i].sourceY-crossings[i-1].sourceY;
            assert(ds>=.05f*dy-.001f);
        }
    }
}

int main(void) {
    float configs[][3]={{10,14,1},{18,26,2.4f},{8.643f,8.987f,1.57f},{40,50,5}};
    for(unsigned c=0;c<4;c++)for(int step=0;step<=4;step++) {
        float press=step*.25f;
        WXGMeshOptics o=dock(108+20*press,66-6*press,press,configs[c][0],configs[c][1],configs[c][2]);
        checkStripe(o);
        // Dragged/magnified backdrop including the inset bar. The full map
        // must also keep a thin source line single-valued along the top/bottom.
        o.zoomAfter=1+press*.16f;
        o.sbLeft=o.padX-80; o.sbRight=o.sbLeft+340;
        o.sbTop=o.padY+3; o.sbBottom=o.height-o.padY-3;
        o.shrinkPress=press; o.shrinkPinch=.2558f; o.shrinkExtra=2*press;
        checkStripe(o);
        if(c==1 && step>0)for(int k=0;k<7;k++) {
            o.kyantChannel=WXGKyantSpectralOffset(k);
            checkNativeMesh(o);
        }
    }
    WXGMeshOptics o=dock(120,70,1,18,26,2.4f);
    assert(sourceDepth(o,o.width*.5f,0,0)>.1f);
    assert(fabsf(sourceDepth(o,o.width*.5f,4,0)-4)<.0001f);
    checkShoulders();
    puts("PASS: crown stripe is single-valued for seven wavelengths, upper/lower edges, press and drag; native mesh row order, original shoulders and round limit.");
}
