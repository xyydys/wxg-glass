/* FIX47: WXGMeshOptics has trailing bar fields (zero = off). */
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "../Sources/WXGMeshRefraction.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
static WXGMeshPoint pts[96*96];
/* Bilinear lookup of the mesh at a point, in the same grid the render server uses. */
static void meshAt(int cols,int rows,float w,float h,float px,float py,float *sx,float *sy) {
    int i=0,j=0;
    while(i<cols-2 && pts[i+1].toX*w<px)i++;
    while(j<rows-2 && pts[(j+1)*cols].toY*h<py)j++;
    WXGMeshPoint a=pts[j*cols+i],b=pts[j*cols+i+1],c=pts[(j+1)*cols+i],d=pts[(j+1)*cols+i+1];
    float u=(px-a.toX*w)/((b.toX-a.toX)*w),v=(py-a.toY*h)/((c.toY-a.toY)*h);
    *sx=((a.fromX*(1-u)+b.fromX*u)*(1-v)+(c.fromX*(1-u)+d.fromX*u)*v)*w;
    *sy=((a.fromY*(1-u)+b.fromY*u)*(1-v)+(c.fromY*(1-u)+d.fromY*u)*v)*h;
}
static double worstError(WXGMeshOptics o,int *vertices) {
    int cols,rows,n=WXGBuildRefractionMesh(o,pts,96*96,&cols,&rows);assert(n==cols*rows && n>0);*vertices=n;
    /* Axes are increasing, unit range, edges included. */
    for(int i=1;i<cols;i++)assert(pts[i].toX>pts[i-1].toX);
    for(int j=1;j<rows;j++)assert(pts[j*cols].toY>pts[(j-1)*cols].toY);
    assert(pts[0].toX==0 && pts[cols-1].toX==1 && pts[0].toY==0 && pts[(rows-1)*cols].toY==1);
    for(int k=0;k<n;k++)assert(pts[k].fromX>=0 && pts[k].fromX<=1 && pts[k].fromY>=0 && pts[k].fromY<=1);
    double worst=0;
    for(float py=.25f;py<o.height;py+=.5f)for(float px=.25f;px<o.width;px+=.5f) {
        float ex,ey;WXGMeshSource(o,px,py,&ex,&ey);
        float x=(px-o.width*.5f)/o.fieldScale,y=(py-o.height*.5f)/o.fieldScale;
        WXGShapeSample f=o.radius>0?WXGRoundedOpticalField(x,y,o.width/o.fieldScale,o.height/o.fieldScale,o.radius)
                                    :WXGCapsuleOpticalField(x,y,o.width/o.fieldScale,o.height/o.fieldScale);
        if(f.distance>-.5f)continue;                       /* outside the native clip */
        if(ex<0||ey<0||ex>o.width||ey>o.height)continue;   /* clamped samples */
        float mx,my;meshAt(cols,rows,o.width,o.height,px,py,&mx,&my);
        double e=hypot(mx-ex,my-ey);if(e>worst)worst=e;
    }
    return worst;
}
int main(void) {
    /* Identity without optics. */
    {WXGMeshOptics o={120,44,1,0,10,0,1,1,1,0,0,0,0};int c,r,n=WXGBuildRefractionMesh(o,pts,96*96,&c,&r);
     for(int k=0;k<n;k++)assert(fabsf(pts[k].fromX-pts[k].toX)<1e-6f && fabsf(pts[k].fromY-pts[k].toY)<1e-6f);}
    /* Refraction pulls edge samples inward and leaves the interior alone. */
    {WXGMeshOptics o={200,64,1,0,10,1.15f,1,1,1,0,0,0,0};int c,r,n=WXGBuildRefractionMesh(o,pts,96*96,&c,&r);
     int inward=0,interior=0;
     for(int k=0;k<n;k++){float x=pts[k].toX*200-100,y=pts[k].toY*64-32,fx=pts[k].fromX*200-100,fy=pts[k].fromY*64-32;
        WXGShapeSample f=WXGCapsuleOpticalField(x,y,200,64);
        if(f.distance<-10.5f){assert(fabsf(fx-x)<1e-3f && fabsf(fy-y)<1e-3f);++interior;}
        else if(f.distance<0 && f.distance>-9){assert(fx*fx+fy*fy<=x*x+y*y+1e-3f);++inward;}}
     assert(inward>10 && interior>0);}
    const char *names[]={"nav button 44x44","input capsule 300x40","dock 390x64","dock pressed x1.08","lens zoom 1.2"};
    WXGMeshOptics cases[]={{44,44,1,0,10,1.15f,1,1,1,0,0,0,0},{300,40,1,0,10,1.15f,1,1,1,0,0,0,0},{390,64,1,0,10,1.15f,1,1,1,0,0,0,0},
                           {421.2f,69.12f,1.08f,0,10,1.15f,1.08f,1,1,0,0,0,0},{110,74,1,0,10,1.15f,1,1,1.2f,0,0,0,0}};
    for(int c=0;c<5;c++) {
        int v;double e=worstError(cases[c],&v);
        printf("%-22s vertices %4d  worst deviation from per-pixel TEST9 %.2f pt\n",names[c],v,e);
        assert(v<=96*96 && e<1.0);
    }
    /* Stronger refraction: still bounded, reported for reference. */
    {WXGMeshOptics o={390,64,1,0,20,4,1,1,1,0,0,0,0};int v;double e=worstError(o,&v);
     printf("%-22s vertices %4d  worst deviation from per-pixel TEST9 %.2f pt\n","dock refraction 4, 20pt",v,e);assert(e<3.0);}
    /* Sharp ring mask: TEST8 coverage 0 peaks at .88 on the contour, zero past the band and at coverage 100. */
    {float edge=WXGSharpRingAlpha(150,.25f,300,40,0,10,0),mid=WXGSharpRingAlpha(150,20,300,40,0,10,0);
     assert(edge>.8f && edge<=.881f && mid==0.f);
     assert(WXGSharpRingAlpha(150,.25f,300,40,0,10,1)==0.f);
     float half=WXGSharpRingAlpha(150,.25f,300,40,0,10,.5f);assert(half>0 && half<edge);}
    puts("PASS: render-server mesh reproduces the TEST9 refraction field (same field and offset functions) within the reported interpolation error; identity without optics; interior untouched; samples stay inside the layer.");
    return 0;
}
