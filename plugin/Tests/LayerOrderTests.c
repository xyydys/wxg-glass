#include <assert.h>
#include <stdio.h>
#include "../Sources/WXGBackdropTraversal.h"
typedef struct { int identity; double z; } Layer;
/* Stable insertion uses the production comparison; identity is a UIView index,
   deliberately in a different order from the native CALayer array. */
static void order(Layer *v,size_t n) {
    for(size_t i=1;i<n;i++) {
        Layer next=v[i];size_t j=i;
        while(j && WXGBackdropCompareZ(next.z,v[j-1].z)<0){v[j]=v[j-1];--j;}
        v[j]=next;
    }
}
int main(void) {
    Layer reordered[]={{2,0},{0,0},{3,0},{1,0}};
    order(reordered,4);
    assert(reordered[0].identity==2 && reordered[1].identity==0 && reordered[2].identity==3 && reordered[3].identity==1);
    Layer raised[]={{2,1},{0,0},{3,-1},{1,0}};
    order(raised,4);
    assert(raised[0].identity==3 && raised[1].identity==0 && raised[2].identity==1 && raised[3].identity==2);
    /* Presentation z can change without changing UIView.subviews. */
    raised[3].z=-2;order(raised,4);assert(raised[0].identity==2);
    assert(WXGBackdropCompareZ(NAN,0)==0 && WXGBackdropCompareZ(INFINITY,0)==0);
    for(int a=-10;a<=10;a++)for(int b=-10;b<=10;b++) {
        assert(WXGBackdropCompareZ(a,b)==-WXGBackdropCompareZ(b,a));
        for(int c=-10;c<=10;c++)if(WXGBackdropCompareZ(a,b)<=0 && WXGBackdropCompareZ(b,c)<=0)
            assert(WXGBackdropCompareZ(a,c)<=0);
    }
    puts("PASS: native layer order, stable z ties, changing presentation z and ordering invariants; no UIKit pixel claim.");
}
