#include "../Sources/WXGPresentationMath.h"
#include <assert.h>
#include <stdio.h>
static void near(double a,double b){assert(fabs(a-b)<1e-7);}
int main(void){
    unsigned count=0;
    for(int direction=-1;direction<=1;direction+=2)for(int i=0;i<=100;i++)for(int scale=70;scale<=120;scale+=5){
        double p=i/100.0,k=scale/100.0,angle=p*.3,ca=cos(angle)*k,sa=sin(angle)*k;
        WXGPoint m={250,80},mx={251,80},my={250,81},g={242,82};
        WXGPoint shown={250+direction*p*430,80+p*22};
        WXGPoint sx={shown.x+ca,shown.y+sa},sy={shown.x-sa,shown.y+ca};
        WXGAffine t=WXGPresentationDelta(m,mx,my,shown,sx,sy,g);
        near(g.x+t.tx,shown.x+ca*(g.x-m.x)-sa*(g.y-m.y));
        near(g.y+t.ty,shown.y+sa*(g.x-m.x)+ca*(g.y-m.y));
        near(t.a,ca);near(t.b,sa);near(t.c,-sa);near(t.d,ca);++count;
    }
    /* Reversing the same native progress yields exactly the same glass state;
       no secondary easing, captured previous-page width or irreversible timer. */
    WXGPoint m={100,50},mx={101,50},my={100,51},g={108,50};
    for(int i=100;i>=0;i--){double p=i/100.0;WXGPoint v={100+p*414,50};
        WXGAffine t=WXGPresentationDelta(m,mx,my,v,(WXGPoint){v.x+1,v.y},(WXGPoint){v.x,v.y+1},g);near(t.tx,p*414);near(t.ty,0);}
    WXGAffine invalid=WXGPresentationDelta(m,m,m,m,m,m,g);near(invalid.a,1);near(invalid.tx,0);
    printf("PASS: %u native affine transition/corrected-centre cases, reversal to identity, degenerate layer basis.\n",count);
    return 0;
}
