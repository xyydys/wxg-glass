#include "../Sources/WXGInputSettledGeometry.h"
#include <assert.h>
#include <stdio.h>
static void near(double a,double b){assert(fabs(a-b)<1e-7);}
int main(void) {
    // WGP4 session 2: tool bottom 601; grow bottom 593.3333. Height grows
    // 38.3333 -> 55 -> 74 -> 93 -> 112 while that bottom remains stationary.
    double heights[]={38.3333,55,74,93,112};
    for(int device=0;device<3;device++)for(int i=0;i<5;i++) {
        double width=375+device*32.5,bottom=593.3333,h=heights[i];
        WXGRect native={73.4144,bottom-h,259.3303,h};
        WXGInputGeometry out=WXGInputBottomAnchoredLayout(width,0,0,native,heights[0],24,1);
        WXGInputGeometry old=WXGInputLayout(width,0,0,native.y+h*.5,fmax(40,h),24,1);
        near(out.plus.y+out.plus.h*.5,bottom-heights[0]*.5);
        near(out.mic.y+out.mic.h*.5,bottom-heights[0]*.5);
        near(out.pill.x,old.pill.x);near(out.pill.y,old.pill.y);
        near(out.pill.w,old.pill.w);near(out.pill.h,old.pill.h);
        near(out.plus.x,old.plus.x);near(out.mic.x,old.mic.x);
    }
    puts("PASS: captured single/multiline heights at 3 device widths; side actions stay on the last native row and TEST9 capsule geometry is preserved.");
}
