#include "../Sources/WXGNativeInputGeometry.h"
#include <assert.h>
#include <stdio.h>
static void near(double a,double b){assert(fabs(a-b)<1e-7);}
int main(void) {
    unsigned n=0;
    for(int base=36;base<=58;base+=2)for(int extra=0;extra<=140;extra+=5)for(int offset=-200;offset<=600;offset+=40) {
        WXGRect native={62,offset,252,base+extra},left={12,offset+extra+3,36,base-6},right={323,offset+extra+7,76,base-14};
        WXGNativeInputGeometry g=WXGNativeInputLayout(native,left,right,base);
        near(g.center.x,native.x);near(g.center.w,native.w);near(g.center.y,native.y);near(g.center.h,native.h);
        near(g.left.h,base);near(g.right.h,base);near(g.left.y+g.left.h,g.center.y+g.center.h);near(g.right.y,g.left.y);
        near(g.left.x,left.x);near(g.right.w,right.w);
        if(extra==0){near(g.left.h,g.center.h);near(g.right.y,g.center.y);}
        ++n;
    }
    WXGNativeInputGeometry g=WXGNativeInputLayout((WXGRect){50,10,260,30},(WXGRect){0},(WXGRect){INFINITY,0,0,0},40);
    near(g.center.h,40);near(g.center.y,5);assert(!WXGInputRectValid(g.left)&&!WXGInputRectValid(g.right));
    puts("PASS: native-input immutable width/caret host; same-height single rows, bottom-aligned multiline actions; 7308 row cases plus missing actions.");
    assert(n==7308);return 0;
}
