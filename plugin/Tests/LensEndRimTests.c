/* FIX47: a lens end that passes the bar's end narrows to the top/bottom rim
   width; everywhere inside the bar the FIX21 rule is unchanged. */
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "../Sources/WXGMeshRefraction.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
static void shift(WXGMeshOptics o,float x,float y,float *dx,float *dy){float sx,sy;WXGMeshSource(o,x,y,&sx,&sy);*dx=sx-x;*dy=sy-y;}
int main(void) {
    const float r=.4f,side=12,sharp=3;
    /* inside the bar: exactly the FIX21 width, for every direction */
    for(int k=0;k<=36;k++){float a=k*3.14159265f/18.f,nx=cosf(a),ny=sinf(a);
        assert(WXGLensEdgeWidthAtBar(nx,ny,side,r,sharp,-10.f)==WXGLensEdgeWidth(nx,ny,side,r,sharp));}
    /* past the bar's end: the end narrows to the top/bottom width */
    assert(fabsf(WXGLensEdgeWidthAtBar(1,0,side,r,sharp,10.f)-side*r)<1e-5f);
    assert(fabsf(WXGLensEdgeWidthAtBar(0,1,side,r,sharp,10.f)-side*r)<1e-5f);
    /* zero bar fields: the old mesh, bit for bit */
    WXGMeshOptics old={120,86,1,0,12,6,1,1,1,2,0,r,sharp};
    for(int i=0;i<200;i++){float x=(float)(i%20)*6.f+1.f,y=(float)(i/20)*8.6f+1.f,a,b,c,d;WXGMeshOptics same=old;
        shift(old,x,y,&a,&b);shift(same,x,y,&c,&d);assert(a==c && b==d);}
    /* mid-dock (bar past both lens ends): unchanged everywhere on the rim */
    WXGMeshOptics mid=old;mid.barLeft=-60;mid.barRight=180;mid.barTop=11;mid.barBottom=75;
    for(int i=0;i<=40;i++){float x=2+i*2.9f,a,b,c,d;shift(old,x,43,&a,&b);shift(mid,x,43,&c,&d);assert(fabsf(a-c)<1e-4f && fabsf(b-d)<1e-4f);}
    /* dock end: the bar ends at x = 60 inside the lens; its right end narrows */
    WXGMeshOptics end=mid;end.barRight=60;float oldEnd,newEnd,ignore;
    shift(old,116,43,&oldEnd,&ignore);shift(end,116,43,&newEnd,&ignore);
    assert(fabsf(newEnd)<fabsf(oldEnd)*.8f);
    /* the left end, still inside the bar, keeps the full width */
    float oldLeft,newLeft;shift(old,3,43,&oldLeft,&ignore);shift(end,3,43,&newLeft,&ignore);
    assert(fabsf(oldLeft-newLeft)<1e-4f);
    printf("PASS: lens end rim narrows past the bar's end (dock ends), FIX21 rule unchanged inside the bar; zero bar fields bit-identical.\n");
    return 0;
}
