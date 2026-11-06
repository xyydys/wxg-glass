/* FIX114 K: writes the drop shadow image (WXGDropShadow.h, the plugin's own code) as a PGM.
   usage: shadow_dump w h radius blur offset spread scale out.pgm */
#include "../../Sources/WXGDropShadow.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char **argv) {
    if(argc<9){fprintf(stderr,"usage: %s w h radius blur offset spread scale out.pgm\n",argv[0]);return 2;}
    float w=(float)atof(argv[1]),h=(float)atof(argv[2]),r=(float)atof(argv[3]),b=(float)atof(argv[4]),o=(float)atof(argv[5]),s=(float)atof(argv[6]),sc=(float)atof(argv[7]);
    WXGShadowPlan p=WXGShadowPlanFor(w,h,r,b,o,s);p.shapeW=w;p.shapeH=h;p.stretchX=p.stretchY=0;   /* the whole shape */
    int pw,ph;WXGShadowPixels(p,sc,&pw,&ph);
    float *a=malloc(sizeof(float)*(size_t)pw*(size_t)ph),*t=malloc(sizeof(float)*WXGShadowScratchFloats(pw,ph));
    WXGShadowRender(a,pw,ph,sc,p,r,b,o,s,t);
    FILE *f=fopen(argv[8],"wb");if(!f)return 1;
    fprintf(f,"P5\n%d %d\n65535\n",pw,ph);
    for(int i=0;i<pw*ph;i++){unsigned v=(unsigned)(a[i]*65535.f+.5f);fputc((int)(v>>8),f);fputc((int)(v&255),f);}
    fclose(f);printf("%d %d %.1f\n",pw,ph,p.margin);return 0;
}
