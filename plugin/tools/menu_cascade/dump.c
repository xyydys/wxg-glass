/* FIX116 A: the entrance's numbers (Sources/WXGMenuCascade.h) as CSV for
   tools/menu_cascade/preview.py:
   dump <rows> <pitch> <stagger s> <speed> <step s> <until s> <capsule half width> [exit]
   FIX116 B: with `exit` the exit's numbers instead (the lowest row leaves first). */
#include "../../Sources/WXGMenuCascade.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv) {
    if(argc<8){fprintf(stderr,"usage: dump rows pitch stagger speed step until halfWidth\n");return 2;}
    int rows=atoi(argv[1]);double pitch=atof(argv[2]),stagger=atof(argv[3]),speed=atof(argv[4]),step=atof(argv[5]),until=atof(argv[6]),half=atof(argv[7]);
    int leaving=argc>8 && !strcmp(argv[8],"exit");
    puts("row,t,iconAlpha,iconScale,iconDy,capAlpha,capScaleX,capScaleY,capDx,capDy,textAlpha,textDx");
    for(int i=0;i<rows;i++) {
        WXGMenuEntrance e=WXGMenuEntranceFor(i,(i+1)*pitch,stagger,speed);
        WXGMenuExit x=WXGMenuExitFor(rows-1-i,(i+1)*pitch,stagger,speed);
        for(double t=0;t<=until+1e-9;t+=step) {
            WXGMenuPose p=leaving?WXGMenuExitIconPoseAt(&x,t):WXGMenuIconPoseAt(&e,t),c=leaving?WXGMenuExitCapsulePoseAt(&x,t,half):WXGMenuCapsulePoseAt(&e,t,half);
            printf("%d,%.4f,%.5f,%.5f,%.4f,%.5f,%.5f,%.5f,%.4f,%.4f,%.5f,%.4f\n",i,t,p.alpha,p.scaleX,p.dy,c.alpha,c.scaleX,c.scaleY,c.dx,c.dy,c.textAlpha,c.textDx);
        }
    }
    return 0;
}
