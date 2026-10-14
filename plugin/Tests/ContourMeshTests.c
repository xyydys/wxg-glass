/* FIX47: WXGMeshOptics has trailing bar fields (zero = off). */
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "../Sources/WXGMeshRefraction.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define CAP 20000
static WXGMeshPoint P[CAP];static unsigned int F[CAP][4];
/* Barycentric lookup in "to" space, like the render server's triangles. */
static int lookup(int faces,float w,float h,float px,float py,float *sx,float *sy) {
    for(int f=0;f<faces;f++)for(int t=0;t<2;t++) {
        WXGMeshPoint a=P[F[f][0]],b=P[F[f][t?2:1]],c=P[F[f][t?3:2]];
        float ax=a.toX*w,ay=a.toY*h,bx=b.toX*w,by=b.toY*h,cx=c.toX*w,cy=c.toY*h;
        float det=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy);if(fabsf(det)<1e-9f)continue;
        float l1=((by-cy)*(px-cx)+(cx-bx)*(py-cy))/det,l2=((cy-ay)*(px-cx)+(ax-cx)*(py-cy))/det,l3=1-l1-l2;
        if(l1<-1e-4f||l2<-1e-4f||l3<-1e-4f)continue;
        *sx=(l1*a.fromX+l2*b.fromX+l3*c.fromX)*w;*sy=(l1*a.fromY+l2*b.fromY+l3*c.fromY)*h;return 1;
    }
    return 0;
}
typedef struct {double mean,worst,over1;int vertices,holes;} Q;
static Q measure(WXGMeshOptics o,WXGMeshQuality q) {
    Q r={0};int faces=0;r.vertices=WXGBuildContourMesh(o,q,P,CAP,F,CAP,&faces);assert(r.vertices>0 && faces>0);
    int k=0;
    for(float py=.3f;py<o.height;py+=.6f)for(float px=.3f;px<o.width;px+=.6f) {
        float x=px-o.width*.5f,y=py-o.height*.5f;
        WXGShapeSample f=o.radius>0?WXGRoundedOpticalField(x,y,o.width,o.height,o.radius):WXGCapsuleOpticalField(x,y,o.width,o.height);
        if(f.distance>0.f)continue;                         /* outside the shape: clipped */
        float ex,ey,mx,my;WXGMeshSource(o,px,py,&ex,&ey);
        if(!lookup(faces,o.width,o.height,px,py,&mx,&my)){++r.holes;continue;}
        if(f.distance<-o.edgeWidth*1.6f-1.f)continue;          /* interior: linear, exact */
        if(ex<0||ey<0||ex>o.width||ey>o.height)continue;     /* clamped samples */
        double e=hypot(mx-ex,my-ey);r.mean+=e;if(e>r.worst)r.worst=e;if(e>1)r.over1+=1;++k;
    }
    r.mean/=k;r.over1=100*r.over1/k;return r;
}
int main(void) {
    WXGMeshQuality body={.06f,.10f,24},lens={.20f,.16f,24};
    struct {const char *name;WXGMeshOptics o;WXGMeshQuality q;double worstLimit;} cases[]={
        {"dock default 1.15/10",      {358,64,1,0,10,1.15f,1,1,1,0,0,0,0},body,.35},
        {"dock YOURS 8.97/7.7",       {358,64,1,0,7.73f,8.97f,1,1,1,0,0,0,0},body,.6},
        {"dock YOURS red channel",    {358,64,1,0,7.73f,8.97f,1,1,1,2.22f*.85f,1,0,0},body,.6},
        {"dock YOURS blue channel",   {358,64,1,0,7.73f,8.97f,1,1,1,2.22f*.85f,-1,0,0},body,.6},
        {"nav button YOURS",          {39.5f,39.5f,1,0,7.73f,8.97f,1,1,1,2.22f*.85f,1,0,0},body,.6},
        {"lens YOURS 2.82/12.35 z1.09",{110,80,1,0,12.35f,2.82f,1,1,1.09f,1.44f*1.55f,1,.3f,3},lens,.8},
    };
    for(unsigned c=0;c<sizeof cases/sizeof *cases;c++) {
        Q r=measure(cases[c].o,cases[c].q);
        printf("%-28s %5d vertices  band mean %.3f pt  worst %.2f pt  >1pt %.1f%%  holes %d\n",
               cases[c].name,r.vertices,r.mean,r.worst,r.over1,r.holes);
        assert(r.holes==0 && r.worst<=cases[c].worstLimit && r.over1==0);
    }
    /* Identity when there is no optics, for the whole layer. */
    {WXGMeshOptics o={120,44,1,0,10,0,1,1,1,0,0,0,0};int faces;int n=WXGBuildContourMesh(o,body,P,CAP,F,CAP,&faces);
     for(int i=0;i<n;i++)if(P[i].toX>=0&&P[i].toX<=1&&P[i].toY>=0&&P[i].toY<=1)
        assert(fabsf(P[i].fromX-P[i].toX)<1e-5f && fabsf(P[i].fromY-P[i].toY)<1e-5f);}
    /* Rounded rectangle (button with a corner radius smaller than half its height). */
    {Q r=measure((WXGMeshOptics){120,60,1,14,7.73f,8.97f,1,1,1,0,0,0,0},body);
     printf("%-28s %5d vertices  band mean %.3f pt  worst %.2f pt  holes %d\n","rounded rect r14 YOURS",r.vertices,r.mean,r.worst,r.holes);
     assert(r.holes==0 && r.worst<.8);}
    /* FIX25: no collapse points, no degenerate faces, exact interior. */
    {
        WXGMeshOptics shapes[]={{358,64,1,0,7.73f,8.97f,1,1,1,0,0,0,0},{39.5f,39.5f,1,0,7.73f,8.97f,1,1,1,0,0,0,0},
                                {300,40,1,0,10,1.15f,1,1,1,0,0,0,0},{110,80,1,0,12.35f,2.82f,1,1,1.09f,0,0,.3f,3},
                                {120,60,1,14,7.73f,8.97f,1,1,1,0,0,0,0}};
        for(unsigned c=0;c<sizeof shapes/sizeof *shapes;c++) {
            WXGMeshOptics o=shapes[c];int faces;int n=WXGBuildContourMesh(o,body,P,CAP,F,CAP,&faces);
            int worstShare=0;
            for(int i=0;i<n;i+=3){int same=0;for(int j=0;j<n;j++)if(fabsf(P[i].toX-P[j].toX)*o.width<1e-3f && fabsf(P[i].toY-P[j].toY)*o.height<1e-3f)++same;if(same>worstShare)worstShare=same;}
            int degenerate=0;
            for(int f=0;f<faces;f++)for(int t=0;t<2;t++) {
                WXGMeshPoint a=P[F[f][0]],b=P[F[f][t?2:1]],d=P[F[f][t?3:2]];
                float area=fabsf((b.toX-a.toX)*o.width*(d.toY-a.toY)*o.height-(d.toX-a.toX)*o.width*(b.toY-a.toY)*o.height)*.5f;
                if(area<1e-4f)++degenerate;
            }
            double interior=0;int samples=0;
            for(float py=.3f;py<o.height;py+=.6f)for(float px=.3f;px<o.width;px+=.6f) {
                float x=px-o.width*.5f,y=py-o.height*.5f;
                WXGShapeSample sf=o.radius>0?WXGRoundedOpticalField(x,y,o.width,o.height,o.radius):WXGCapsuleOpticalField(x,y,o.width,o.height);
                if(sf.distance>-(o.edgeWidth+2.f))continue;
                float ex,ey,mx,my;WXGMeshSource(o,px,py,&ex,&ey);
                assert(lookup(faces,o.width,o.height,px,py,&mx,&my));
                double e=hypot(mx-ex,my-ey);if(e>interior)interior=e;++samples;
            }
            /* FIX26: no point inside two faces; the dispersion layers add, so any
               overlap is drawn as a coloured line. */
            int overlaps=0,probes=0;
            for(float py=.37f;py<o.height;py+=.7f)for(float px=.37f;px<o.width;px+=.7f) {
                int inside=0;
                for(int f=0;f<faces && inside<2;f++)for(int t=0;t<2;t++) {
                    WXGMeshPoint a=P[F[f][0]],b=P[F[f][t?2:1]],d=P[F[f][t?3:2]];
                    float ax=a.toX*o.width,ay=a.toY*o.height,bx=b.toX*o.width,by=b.toY*o.height,cx=d.toX*o.width,cy=d.toY*o.height;
                    float det=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy);if(fabsf(det)<1e-9f)continue;
                    float l1=((by-cy)*(px-cx)+(cx-bx)*(py-cy))/det,l2=((cy-ay)*(px-cx)+(ax-cx)*(py-cy))/det,l3=1-l1-l2;
                    if(l1>1e-3f && l2>1e-3f && l3>1e-3f)++inside;
                }
                ++probes;if(inside>1)++overlaps;
            }
            printf("shape %u: max vertices at one point %d, degenerate triangles %d, overlapping points %d/%d, interior max error %.4f pt\n",
                   c,worstShare,degenerate,overlaps,probes,interior);
            assert(worstShare<=1 && degenerate==0 && overlaps==0 && interior<.01 && samples>0);
        }
    }
    puts("PASS: contour mesh follows the TEST9 field incl. RGB channel shifts and the lens rim: no holes, no overlap, no collapse point, no degenerate face, exact interior, no edge-band pixel off by 1 pt, at your settings.");
    return 0;
}
