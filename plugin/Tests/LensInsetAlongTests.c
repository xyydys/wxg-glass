/* FIX88: the bar inside the dock's lens joins the bar outside at 45 degrees
   (WXGInnerInsetAlong / WXGLensDepthAlongBar), and the lens's colour split has
   its own band (WXGMeshOptics.dispersionWidth / dispersionTopRatio). */
#include "../Sources/WXGMeshRefraction.h"
#include <stdio.h>
static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)
/* The contour of the bar seen through the lens (no refraction): the top edge
   y(x) where barDistance + inset = 0, found by bisection. Bar 359 x 68 and a
   103 x 87 lens, both centred at the origin. */
static float insetAt(float x,float y) {
    WXGShapeSample b=WXGCapsuleOpticalField(x,y,359,68);
    float qx=x-b.nx*b.distance,qy=y-b.ny*b.distance;
    WXGShapeSample l=WXGCapsuleOpticalField(qx,qy,103,87);
    return WXGInnerInsetAlong(68,1,.18f,WXGLensDepthAlongBar(l.distance,-b.ny,b.nx,l.nx,l.ny));
}
static float contourY(float x) {
    float lo=-34.f,hi=0.f;   /* covered below, uncovered above */
    for(int i=0;i<60;i++){float m=(lo+hi)*.5f;float d=WXGCapsuleOpticalField(x,m,359,68).distance+insetAt(x,m);if(d<0)hi=m;else lo=m;}
    return hi;
}
int main(void) {
    float full=68*.5f*.18f;
    CHECK(WXGInnerInsetAlong(68,1,.18f,0)==0,"0 at the join");
    CHECK(fabsf(WXGInnerInsetAlong(68,1,.18f,.01f)/.01f-1)<.01f,"45 degrees at the join");
    CHECK(fabsf(WXGInnerInsetAlong(68,1,.18f,2*full)-full)<1e-5f && fabsf(WXGInnerInsetAlong(68,1,.18f,100)-full)<1e-5f,"full inset");
    for(float a=0;a<30;a+=.1f)CHECK(WXGInnerInsetAlong(68,1,.18f,a)<=WXGInnerInsetAlong(68,1,.18f,a+.1f)+1e-6f,"monotonic (%.1f)",a);
    CHECK(WXGInnerInsetAlong(68,0,.18f,10)==0 && WXGInnerInsetAlong(68,1,0,10)==0,"no press / no reduction: none");
    CHECK(fabsf(WXGInnerInsetAlong(68,1,.9f,100)-68*.5f*.3f)<1e-4f,"reduction clamped to .3");
    CHECK(WXGLensDepthAlongBar(2,1,0,1,0)==0 && fabsf(WXGLensDepthAlongBar(-3,1,0,.6f,.8f)-5)<1e-5f && fabsf(WXGLensDepthAlongBar(-3,1,0,0,1)-10)<1e-5f,
          "depth along the outline: outside 0, over |t.n|, at least .3");
    /* The contour along the top edge: at the lens edge on the bar's top line,
       never steeper than 45 degrees (+5%), reaching the full inset inside. */
    float join=-(51.5f-43.5f)-sqrtf(43.5f*43.5f-34.f*34.f);   /* the lens outline on y = -34, left side */
    float prev=contourY(join-1);
    CHECK(fabsf(prev+34)<.05f,"outside the lens: the bar's edge (%.3f)",prev);
    float steepest=0;
    for(float x=join-1+.25f;x<0;x+=.25f){float y=contourY(x);float s=fabsf(y-prev)/.25f;if(s>steepest)steepest=s;prev=y;}
    CHECK(steepest<1.05f,"no step steeper than 45 degrees (%.3f)",steepest);
    CHECK(fabsf(contourY(0)-(-34+full))<.05f,"full inset in the middle (%.3f)",contourY(0));
    /* Colour split band: zero fields are exactly the refraction band. */
    WXGMeshOptics o={103,87,1,0,10,1.15f,1,1,1.2f,1.5f,1,.4f,3,-128,9.5f,231,77.5f,0,0,0,0};
    WXGMeshOptics same=o;same.dispersionWidth=10;same.dispersionTopRatio=.4f;
    WXGMeshOptics wide=o;wide.dispersionWidth=24;
    for(float y=1;y<43;y+=2.5f)for(float x=1;x<102;x+=3.5f) {
        float ax,ay,bx,by;WXGMeshSource(o,x,y,&ax,&ay);WXGMeshSource(same,x,y,&bx,&by);
        if(fabsf(ax-bx)>1e-4f || fabsf(ay-by)>1e-4f){CHECK(0,"same band, same mapping (%.1f, %.1f)",x,y);x=999;y=999;}
    }
    /* 15 pt in from the left end on the centre line: past the refraction band,
       inside the wider colour split. */
    float rx,ry,gx,gy;WXGMeshSource(o,15,43.5f,&rx,&ry);WXGMeshSource(wide,15,43.5f,&gx,&gy);
    WXGMeshOptics green=wide;green.channel=0;float zx,zy;WXGMeshSource(green,15,43.5f,&zx,&zy);
    CHECK(fabsf(gx-zx)>.05f,"wider colour split reaches further in (%.4f)",gx-zx);
    WXGMeshOptics green0=o;green0.channel=0;float z0x,z0y;WXGMeshSource(green0,15,43.5f,&z0x,&z0y);
    CHECK(fabsf(rx-z0x)<1e-5f,"refraction band only: no split there");
    if(failures){printf("LensInsetAlongTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: lens inset along the bar (FIX88): 45 degrees at the join, flattening to the full inset, never a vertical step on the lens' side; the colour split's own band (unchanged when equal, reaching further when wider).\n");
    return 0;
}
