#include "../Sources/WXGButtonPress.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for(int k=0;k<=100;k++)for(int ix=-10;ix<=10;ix++)for(int iy=-10;iy<=10;iy++) {
        double p=k*.01,x=ix*.1,y=iy*.1;
        WXGButtonPressPose r=WXGButtonPress(p,x,y,0);
        assert(r.scaleX>=1 && r.scaleX<=1.08);
        assert(r.scaleY>=1 && r.scaleY<=1.06);
        assert(fabs(r.offsetX)<=1.8 && fabs(r.offsetY)<=1.8);
        double a=-14,b=12;
        double movedA=a+WXGButtonChildOffset(r.scaleX,a,r.offsetX);
        double movedB=b+WXGButtonChildOffset(r.scaleX,b,r.offsetX);
        assert(fabs((movedB-movedA)-(b-a)*r.scaleX)<1e-12);
        if(!k)assert(r.scaleX==1 && r.scaleY==1 && r.offsetX==0 && r.offsetY==0);
    }
    WXGButtonPressPose r=WXGButtonPress(1,1,-1,1);
    assert(r.scaleX==1 && r.scaleY==1 && r.offsetX==0 && r.offsetY==0);
    r=WXGButtonPress(NAN,INFINITY,NAN,0);
    assert(r.scaleX==1 && r.scaleY==1 && r.offsetX==0 && r.offsetY==0);
    puts("ButtonPressTests: PASS (bounded single-body pose, shared artwork centre, rest/reduced-motion)");
    return 0;
}
