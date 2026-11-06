/* Builds the body contour mesh for 3000 random optics with whatever
   WXGMeshRefraction.h is first on the include path (zero-initialised
   optics: FIX114 I's transition is 0) and prints an FNV-1a hash of every
   mesh's bytes. Compile once against FIX114 G's headers and once against
   FIX114 I's; the outputs must be identical. */
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "WXGMeshRefraction.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
enum { CAP=20000 };
static WXGMeshPoint P[CAP];static unsigned int F[CAP][4];
static uint32_t rs=114u;
static float fr(float a,float b){rs=rs*1664525u+1013904223u;return a+(b-a)*(float)(rs>>8)/16777216.f;}
static uint64_t fnv(const void *p,size_t n,uint64_t h){const unsigned char *c=p;for(size_t i=0;i<n;i++){h^=c[i];h*=1099511628211ull;}return h;}
int main(void) {
    const WXGMeshQuality qs[3]={{.06f,.10f,24.f},{.20f,.16f,24.f},{.12f,.08f,8.f}};
    uint64_t all=1469598103934665603ull;int built=0;
    for(int i=0;i<3000;i++) {
        WXGMeshOptics o;memset(&o,0,sizeof o);
        o.width=fr(20,420);o.height=fr(20,140);o.fieldScale=i%7?1.f:fr(.9f,1.2f);o.radius=i%2?fr(2,40):0.f;
        o.edgeWidth=fr(1,60);o.refraction=fr(0,20);o.offsetScale=i%5?1.f:fr(0,1);o.zoomBefore=1.f+(i%3?0.f:fr(0,.05f));o.zoomAfter=1.f+(i%4?0.f:fr(0,.2f));
        if(i%3==0){o.dispersion=fr(0,6);o.channel=(float)((i/3)%3-1);}
        if(i%6==0){o.topRatio=fr(.1f,1);o.sharpness=fr(1,6);}
        if(i%9==0)o.cancel=fr(0,1);
        int faces=0,n=WXGBuildContourMesh(o,qs[i%3],P,CAP,F,CAP,&faces);
        uint64_t h=fnv(&n,sizeof n,1469598103934665603ull);h=fnv(&faces,sizeof faces,h);
        if(n>0){h=fnv(P,sizeof(WXGMeshPoint)*(size_t)n,h);h=fnv(F,sizeof(unsigned int)*4*(size_t)faces,h);++built;}
        all=fnv(&h,sizeof h,all);
        printf("%d %d %d %016llx\n",i,n,faces,(unsigned long long)h);
    }
    printf("built %d all %016llx\n",built,(unsigned long long)all);
    return 0;
}
