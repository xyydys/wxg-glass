/* FIX114 I: prints the render-server body mesh (WXGBuildContourMesh, the
   exact code the plugin runs) for one glass, so render.py can draw it.
   Usage: dump_mesh width height radius edgeWidth refraction transition [stretch power width]
   (FIX114 J: the soft shape; 0 = FIX114 I's)
   Output: "V n" then n lines "fromX fromY toX toY" (unit), "F m" then m lines of 4 indices. */
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#include "../../Sources/WXGMeshRefraction.h"
#include <stdio.h>
#include <stdlib.h>
enum { CAP=20000 };
static WXGMeshPoint P[CAP];
static unsigned int F[CAP][4];
int main(int argc,char **argv) {
    if(argc<7){fprintf(stderr,"usage: %s w h radius edgeWidth refraction transition [stretch power width]\n",argv[0]);return 2;}
    WXGMeshOptics o={0};
    o.width=(float)atof(argv[1]);o.height=(float)atof(argv[2]);o.fieldScale=1;o.radius=(float)atof(argv[3]);
    o.edgeWidth=(float)atof(argv[4]);o.refraction=(float)atof(argv[5]);o.offsetScale=1;o.zoomBefore=1;o.zoomAfter=1;
    o.transition=(float)atof(argv[6]);
    if(argc>9){o.softStretch=(float)atof(argv[7]);o.softPower=(float)atof(argv[8]);o.softWidth=(float)atof(argv[9]);}
    const WXGMeshQuality body={.06f,.10f,24.f};   /* WXGMeshQualityBody */
    int faces=0,n=WXGBuildContourMesh(o,body,P,CAP,F,CAP,&faces);
    if(n<4){fprintf(stderr,"mesh did not fit\n");return 1;}
    printf("V %d\n",n);
    for(int i=0;i<n;i++)printf("%.7f %.7f %.7f %.7f\n",P[i].fromX,P[i].fromY,P[i].toX,P[i].toY);
    printf("F %d\n",faces);
    for(int i=0;i<faces;i++)printf("%u %u %u %u\n",F[i][0],F[i][1],F[i][2],F[i][3]);
    return 0;
}
