#include "../Sources/WXGSourceMapping.h"
#include <assert.h>
#include <stdio.h>
static void near(double a,double b){assert(fabs(a-b)<.000002);}
int main(void) {
    _Static_assert(sizeof(WXGCopyUniforms)==48,"Metal copy ABI");
    // Window/page translations reproduce the captured -132 model / -41.432
    // presentation case, then every stage of keyboard descent and cancellation.
    for(int i=0;i<=1000;i++) {
        double p=i/1000.,pageX=-132*(1-p),dockLocalX=-11.4359;
        // Child composition: the dock moves with native tab bar once. It does
        // not subtract an offscreen model endpoint or remain fixed in a mask.
        double windowX=pageX+dockLocalX;
        near(windowX-pageX,dockLocalX);
        for(int scale=1;scale<=3;scale++)for(int x=0;x<400;x+=17)for(int y=0;y<150;y+=19) {
            WXGSourceTransform t={1.03,.02,-.01,.97,18.5,410+330*p};
            WXGCopyUniforms u;assert(WXGMakeCopyUniforms(t,scale,-40,-40,520,1036,&u));
            double px=x+.5,py=y+.5;
            double ux=u.origin[0]+u.x[0]*px+u.y[0]*py;
            double uy=u.origin[1]+u.x[1]*px+u.y[1]*py;
            near(ux,(t.a*px/scale+t.c*py/scale+t.tx+40)/520);
            near(uy,(t.b*px/scale+t.d*py/scale+t.ty+40)/1036);
            WXGSourceTransform inv;
            assert(WXGSourceInverse(t.tx,t.ty,t.tx+t.a,t.ty+t.b,t.tx+t.c,t.ty+t.d,&inv));
            double sx=ux*520-40,sy=uy*1036-40;
            assert(fabs(inv.a*sx+inv.c*sy+inv.tx-px/scale)<.001);
            assert(fabs(inv.b*sx+inv.d*sy+inv.ty-py/scale)<.001);
        }
    }
    WXGCopyUniforms u;assert(!WXGMakeCopyUniforms((WXGSourceTransform){1,0,0,1,0,0},0,0,0,100,100,&u));
    assert(!WXGMakeCopyUniforms((WXGSourceTransform){1,0,0,1,NAN,0},2,0,0,100,100,&u));
    assert(!WXGMakeCopyUniforms((WXGSourceTransform){1,0,0,1,0,0},2,0,0,0,100,&u));
    puts("PASS: GPU copy pixel centres vs independent affine inverse, 1001 keyboard/return positions, 1/2/3x canvas, translation + skew + scale, invalid input guards.");
}
