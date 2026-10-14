/* FIX88: the tap animation's veil (Sources/WXGTravelVeil.h). */
#include "../Sources/WXGTravelVeil.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
int main(void) {
    enum {N=64};float pts[4*N];
    /* Bar 359 x 68 at (0, 0), lens 103 x 87 at (40, 0): outside the lens the
       outline itself, inside it the shader's contour (barDistance + inset = 0). */
    float H=68,full=H*.5f*.18f;
    WXGTravelVeilOutline(0,0,359,68,40,0,103,87,H,1,.18f,0,-40,120,N,pts,NULL);
    for(int i=0;i<2*N;i++) {
        float x=pts[2*i],y=pts[2*i+1];
        WXGShapeSample b=WXGCapsuleOpticalField(x,y,359,68);
        WXGShapeSample l=WXGCapsuleOpticalField(x-40,y,103,87);
        if(l.distance>2.f)CHECK(fabsf(b.distance)<1e-3f,"outside the lens: on the outline (%d %.4f)",i,b.distance);
    }
    /* The middle of the lens: full inset at top and bottom. */
    float top=0,bottom=0;
    for(int i=0;i<N;i++)if(fabsf(pts[2*i]-40)<1.3f)top=pts[2*i+1];
    for(int i=N;i<2*N;i++)if(fabsf(pts[2*i]-40)<1.3f)bottom=pts[2*i+1];
    CHECK(fabsf(top-(-34+full))<.01f && fabsf(bottom-(34-full))<.01f,"full inset under the lens (%.3f %.3f)",top,bottom);
    /* extra moves every point inward by that much more along the normal. */
    float more[4*N];WXGTravelVeilOutline(0,0,359,68,40,0,103,87,H,1,.18f,2,-40,120,N,more,NULL);
    CHECK(fabsf(more[1]-(pts[1]+2))<1e-4f && fabsf(more[2*N+1]-(pts[2*N+1]-2))<1e-4f,"extra inward");
    /* Past the bar's end the samples stay on the end; the end cap inside a lens
       is inset (the bar detaches from the lens). */
    WXGTravelVeilOutline(0,0,359,68,170,0,103,87,H,1,.18f,0,100,230,N,pts,NULL);
    float maxX=-1e9f;for(int i=0;i<2*N;i++)if(pts[2*i]>maxX)maxX=pts[2*i];
    CHECK(maxX<179.5f-full+.05f && maxX>179.5f-full-.05f,"end cap inset inside the lens (%.3f)",maxX);
    /* No press: the outline itself everywhere. */
    WXGTravelVeilOutline(0,0,359,68,40,0,103,87,H,0,.18f,0,-40,120,N,pts,NULL);
    for(int i=0;i<2*N;i++)CHECK(fabsf(WXGCapsuleOpticalField(pts[2*i],pts[2*i+1],359,68).distance)<1e-3f,"no press, no inset (%d)",i);
    /* A band deeper than half the bar: top and bottom stop short of the middle, never cross. */
    WXGTravelVeilOutline(0,0,359,68,40,0,103,87,H,1,.18f,40,-40,120,N,pts,NULL);
    for(int i=0;i<N;i++)CHECK(pts[2*i+1]<0.f && pts[2*(2*N-1-i)+1]>0.f && pts[2*i+1]<pts[2*(2*N-1-i)+1],"deep band: no crossing (%d %.3f %.3f)",i,pts[2*i+1],pts[2*(2*N-1-i)+1]);
    /* Fade bands: composited, each band's middle shows alpha * (1 - .82 edge^2); the last the full alpha. */
    float depth[8],band[8];int k=WXGTravelVeilBands(.6f,10,8,depth,band);
    CHECK(k==8 && depth[0]==0 && fabsf(depth[7]-10)<1e-5f,"8 bands over the width");
    float clear=1;
    for(int j=0;j<k;j++) {
        clear*=1-band[j];
        float shown=1-clear,level=1;
        if(j<k-1){float t=(j+.5f)/7.f,e=1-t*t*(3-2*t);level=1-.82f*e*e;}
        CHECK(fabsf(shown-.6f*level)<1e-5f,"band %d composited %.4f",j,shown);
        CHECK(band[j]>=0 && band[j]<=1,"band alpha in range");
    }
    CHECK(WXGTravelVeilBands(.6f,0,8,depth,band)==1 && band[0]==.6f && WXGTravelVeilBands(.6f,10,1,depth,band)==1,"no fade: one band");
    if(failures){printf("TravelVeilTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: tap animation veil (FIX88): the outline outside the lens, the shader's inset under it, the end cap detached inside it, extra inward offset, deep bands never crossing the middle, edge-fade bands composited to the shader's fade.\n");
    return 0;
}
