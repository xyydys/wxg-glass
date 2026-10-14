#include "../Sources/WXGSourceMapping.h"
#include <assert.h>
#include <stdio.h>
static void check(double a,double b,double c,double d,double tx,double ty) {
    WXGSourceTransform t;
    assert(WXGSourceInverse(tx,ty,tx+a,ty+b,tx+c,ty+d,&t));
    for(int x=-40;x<500;x+=19)for(int y=-30;y<300;y+=13) {
        double sx=a*x+c*y+tx,sy=b*x+d*y+ty;
        assert(fabs(t.a*sx+t.c*sy+t.tx-x)<1e-7);
        assert(fabs(t.b*sx+t.d*sy+t.ty-y)<1e-7);
    }
}
int main(void) {
    check(1,0,0,1,32,54);check(1.078,0,0,1.036,-3,896);
    check(.866,.5,-.5,.866,200,-50);check(-1,0,0,1,440,0);
    check(1,.15,.2,.8,-200,25);
    WXGSourceTransform t;
    assert(!WXGSourceInverse(0,0,1,1,2,2,&t));
    assert(!WXGSourceInverse(NAN,0,1,0,0,1,&t));
    puts("PASS: backdrop source-to-local mapping under translation, elastic press, rotation, reflection and shear; singular transforms rejected.");
}
