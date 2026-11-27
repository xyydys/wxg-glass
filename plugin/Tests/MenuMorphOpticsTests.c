#include "../Sources/WXGMenuMorphOptics.h"
#include <assert.h>
#include <stdio.h>

static WXGMenuMorphFieldSample rounded(WXGMenuMorphFieldBox b,float x,float y) {
    return WXGMenuMorphFieldAt(WXGMenuMorphFieldShapeForBox(b),x,y);
}

static void inspect(const WXGMorphOpticalMesh *m,const WXGMenuMorphField *field,bool analytic,float channel) {
    double area=0,error2=0,weightedSamples=0;
    float peak=0;
    for(unsigned i=0;i<m->faceCount;i++){
        unsigned const *q=m->faces[i].index;
        WXGMorphOpticalVertex v[4];
        for(int j=0;j<4;j++){assert(q[j]<m->vertexCount);v[j]=m->vertices[q[j]];}
        // Every submitted CA quad is rectangular and owns a positive region;
        // the entire sheet must be covered, including between unlike levels.
        assert(v[1].x>v[0].x && v[2].y>v[1].y);
        assert(v[0].y==v[1].y && v[1].x==v[2].x && v[2].y==v[3].y && v[3].x==v[0].x);
        float faceArea=(v[1].x-v[0].x)*(v[2].y-v[1].y);
        area+=faceArea;
        for(int py=0;py<3;py++)for(int px=0;px<3;px++){
            float u=(px+.37f)/3,vv=(py+.45f)/3;
            float x=v[0].x+(v[1].x-v[0].x)*u,y=v[0].y+(v[3].y-v[0].y)*vv;
            WXGMenuMorphFieldSample ref=analytic?rounded(m->box,x+m->box.x,y+m->box.y):
                WXGMenuMorphOpticalRead(field,x+m->box.x,y+m->box.y);
            if(ref.distance>-.06f || ref.distance<=-m->band)continue;
            float shift=WXGLensCurveOffsetCapped(-ref.distance,m->band,m->amount,m->squeeze);
            float split=m->dispersion*WXGLensSplitWeight(channel)*(2*x/m->box.width-1)*(2*y/m->box.height-1);
            float w[4]={1-fmaxf(u,vv),fmaxf(u-vv,0),fminf(u,vv),fmaxf(vv-u,0)};
            float errX=ref.dx*shift*(1+split),errY=ref.dy*shift*(1+split);
            for(int j=0;j<4;j++){
                errX+=w[j]*(v[j].offsetX+v[j].splitX*WXGLensSplitWeight(channel));
                errY+=w[j]*(v[j].offsetY+v[j].splitY*WXGLensSplitWeight(channel));
            }
            float err=hypotf(errX,errY);
            peak=fmaxf(peak,err);error2+=err*err*faceArea;weightedSamples+=faceArea;
        }
    }
    assert(fabs(area-m->box.width*m->box.height)<.01);
    assert(weightedSamples>0 && sqrt(error2/weightedSamples)<.38);
    printf("Menu optical mesh: %u vertices, %u quads, RMS %.3f pt, peak %.3f pt\n",
           m->vertexCount,m->faceCount,sqrt(error2/weightedSamples),(double)peak);
}
int main(void) {
    WXGMenuMorphField f; WXGMorphOpticalMesh m={0};
    WXGMenuMorphFieldBox box={0,0,225.33333f,164,30.85235f},none={0};
    WXGMenuMorphFieldBuild(&f,box,box.radius,none,0,4.9f);
    WXGMenuMorphFieldTranslate(&f,22.375f,69.125f);box.x+=22.375f;box.y+=69.125f;
    // The reported Other configuration has zero blur and a 20pt band.
    assert(WXGMorphOpticalBuild(&m,&f,box,20,64,3,0));inspect(&m,&f,true,0);
    // A non-square moving panel and its source lobe use the Gaussian vector
    // texture. Colour-split source coordinates must be continuous as well.
    WXGMenuMorphFieldBox a={9,-2,161,112,27},b={3,65,35,35,17.5f};
    WXGMenuMorphFieldBuild(&f,a,24,b,5,3);
    WXGMenuMorphFieldBox cover={3,-2,167,112,0};
    assert(WXGMorphOpticalBuild(&m,&f,cover,14,42,3,2));
    inspect(&m,&f,false,-1);inspect(&m,&f,false,1);
    // The field must address the same window pixels after a portal changes
    // its local origin. Use a smoothed, anisotropic union and the real 225pt
    // session spacing. The same glass/rim mask stays on its shape-local grid.
    WXGMenuMorphField aWindow,bWindow;
    float step=(225.33333f+96.f)/64.f;
    WXGMenuMorphFieldBuildMode(&f,a,24,b,8,3,WXGMorphFieldGeometry);
    WXGMenuMorphBuildSessionField(&aWindow,&f,198.375f,56.8125f,step);
    WXGMenuMorphFieldTranslate(&f,9.125f,-14.75f);
    WXGMenuMorphBuildSessionField(&bWindow,&f,189.25f,71.5625f,step);
    assert(aWindow.gaussian && bWindow.gaussian && aWindow.step==step);
    assert(aWindow.width==bWindow.width && aWindow.height==bWindow.height);
    for(float y=4;y<102;y+=1.4f)for(float x=6;x<151;x+=1.1f){
        WXGMenuMorphFieldSample one=WXGMenuMorphOpticalRead(&aWindow,x,y);
        WXGMenuMorphFieldSample two=WXGMenuMorphOpticalRead(&bWindow,x+9.125f,y-14.75f);
        assert(fabsf(one.distance-two.distance)<.0001f);
        assert(hypotf(one.dx-two.dx,one.dy-two.dy)<.0001f);
    }
    // High-sigma collapse (IMG_0046): fine contour grid sampled from the session
    // field must match the session zero-contour instead of truncating at 16 taps.
    WXGMenuMorphField collapseShape,collapseSession,collapseFine;
    WXGMenuMorphFieldBox cMenu={28,12,68,68,34},cPlus={54,12,41.5f,41.5f,20.75f};
    WXGMenuMorphFieldBuildMode(&collapseShape,cMenu,34,cPlus,14.5f,1.5f,WXGMorphFieldGeometry);
    WXGMenuMorphBuildSessionField(&collapseSession,&collapseShape,180.25f,45.5f,step);
    WXGMenuMorphFieldSampleSession(&collapseFine,cMenu,34,cPlus,14.5f,1.5f,&collapseSession);
    assert(collapseSession.gaussian && !collapseFine.gaussian);
    float midX=cPlus.x+cPlus.width*.5f;
    for(float y=2;y<90;y+=.25f){
        float dSession=WXGMenuMorphOpticalRead(&collapseSession,midX,y).distance;
        float dFine=WXGMenuMorphFieldRead(&collapseFine,midX,y).distance;
        if(fabsf(dSession)<.2f)assert(fabsf(dFine-dSession)<.06f);
    }
    WXGMorphOpticalFree(&m);
    return 0;
}
