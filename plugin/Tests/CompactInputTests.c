#include "../Sources/WXGCompactInputGeometry.h"
#include <assert.h>
#include <stdio.h>
static void same(double x,double y){assert(fabs(x-y)<.00001);}
int main(void) {
    /* The captured native row is 414pt wide, center x=48/w=278/h=40.
       The old 32pt left control with a 45pt material height made an ellipse. */
    WXGCompactInput observed=WXGCompactInputLayout(414,0,0,(WXGRect){48,814,278,40},45,26,28,2);
    same(observed.left.w,observed.left.h);
    assert(observed.center.w<278 && observed.center.w>240);
    same(observed.center.x-(observed.left.x+observed.left.w),8);
    same(observed.right.x-(observed.center.x+observed.center.w),8);
    same(observed.rightInkX[0]-13-observed.right.x,8);
    same(observed.rightInkX[1]-14-(observed.rightInkX[0]+13),8);
    same(observed.right.x+observed.right.w-(observed.rightInkX[1]+14),8);
    unsigned cases=0;
    double widths[]={320,375,390,414,440,667,844,1024};
    double heights[]={40,57,77,138,200};
    double scales[]={36,40,45,48,54};
    for(unsigned w=0;w<8;w++)for(unsigned h=0;h<5;h++)for(unsigned d=0;d<5;d++)
    for(unsigned safe=0;safe<2;safe++)for(int count=0;count<=2;count++) {
        WXGRect native={48,500-heights[h],278,heights[h]};
        WXGCompactInput g=WXGCompactInputLayout(widths[w],safe?20:0,safe?34:0,native,scales[d],24,28,count);
        same(g.left.w,g.left.h);assert(g.center.w>=100);
        same(g.center.x-(g.left.x+g.left.w),g.gap);
        same(g.sideMidY,g.left.y+g.left.h/2);
        same(g.center.y+g.center.h,g.left.y+g.left.h);
        same(g.center.h,scales[d]+heights[h]-40);
        same(g.center.y+g.center.h/2,native.y+native.h/2);
        if(count) {
            same(g.right.h,g.left.h);
            same(g.right.x-(g.center.x+g.center.w),g.gap);
            assert(g.right.x+g.right.w<=widths[w]-(safe?34:0)-8+.001);
            assert(g.rightInkX[0]-12>=g.right.x);
        }
        if(count==2) {
            same(g.rightInkX[0]-12-g.right.x,g.gap);
            same(g.rightInkX[1]-14-(g.rightInkX[0]+12),g.gap);
            same(g.right.x+g.right.w-(g.rightInkX[1]+14),g.gap);
        }
        cases++;
    }
    printf("PASS: captured compact three-segment row and %u circle/equal-ink-gap/multiline cases\n",cases);
}
