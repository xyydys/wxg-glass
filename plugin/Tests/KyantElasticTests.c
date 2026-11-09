/* FIX122 C: Kyant's drag-speed deformation (Sources/WXGKyantElastic.h). */
#include "../Sources/WXGKyantElastic.h"
#include <stdio.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    WXGKyantElasticParams p=WXGKyantElasticDefaults();
    CHECK(p.width==.75 && p.height==.25 && p.limit==.2 && p.sensitivity==1 && p.damping==.5 && p.stiffness==300 && !p.symmetric,"his defaults");
    /* At rest: no deformation. */
    WXGKyantElastic e={0,0};double sx,sy;
    WXGKyantElasticScale(e,p,&sx,&sy);
    CHECK(sx==1 && sy==1,"rest");
    /* His formula: velocity 1 range/s -> v .1 -> width / (1 - .075), height x (1 - .025). */
    e.velocity=1;WXGKyantElasticScale(e,p,&sx,&sy);
    CHECK(fabs(sx-1/(1-.075))<1e-12 && fabs(sy-(1-.025))<1e-12,"right: %.5f %.5f",sx,sy);
    e.velocity=-1;WXGKyantElasticScale(e,p,&sx,&sy);
    CHECK(fabs(sx-1/(1+.075))<1e-12 && fabs(sy-(1+.025))<1e-12,"left (signed as his): %.5f %.5f",sx,sy);
    /* Capped at the limit. */
    e.velocity=50;WXGKyantElasticScale(e,p,&sx,&sy);
    CHECK(fabs(sx-1/.8)<1e-12 && fabs(sy-.8)<1e-12,"capped at .2");
    /* Symmetric: either way wider and flatter. */
    WXGKyantElasticParams q=p;q.symmetric=1;e.velocity=-1;WXGKyantElasticScale(e,q,&sx,&sy);
    CHECK(sx>1 && sy<1,"symmetric left: %.4f %.4f",sx,sy);
    /* Sensitivity and factors scale it; 0 turns it off. */
    q=p;q.sensitivity=2;e.velocity=1;WXGKyantElasticScale(e,q,&sx,&sy);
    CHECK(fabs(sx-1/(1-.15))<1e-12,"sensitivity 2");
    q=p;q.width=0;q.height=0;WXGKyantElasticScale(e,q,&sx,&sy);
    CHECK(sx==1 && sy==1,"factors 0: off");
    /* The velocity follows the lens' speed per tab range with spring(.5, 300):
       it overshoots (damping .5) and settles. */
    WXGKyantElastic f={0,0};double peak=0;
    for(int i=0;i<600;i++){WXGKyantElasticStep(&f,480,240,p,1./120);if(f.velocity>peak)peak=f.velocity;}
    CHECK(fabs(f.velocity-2)<1e-3 && peak>2.1,"480 pt/s over 240 pt: 2 ranges/s (peak %.3f)",peak);
    for(int i=0;i<600;i++)WXGKyantElasticStep(&f,0,240,p,1./120);
    CHECK(WXGKyantElasticStill(f),"stops");
    /* A stiffer, critically damped spring follows without overshoot. */
    WXGKyantElasticParams c=p;c.damping=1;c.stiffness=1000;WXGKyantElastic g={0,0};peak=0;
    for(int i=0;i<600;i++){WXGKyantElasticStep(&g,480,240,c,1./120);if(g.velocity>peak)peak=g.velocity;}
    CHECK(peak<=2+1e-6,"damping 1: no overshoot (%.4f)",peak);
    /* Nothing bad from a zero range or a non-finite speed. */
    WXGKyantElastic h={0,0};WXGKyantElasticStep(&h,NAN,0,p,1./60);
    CHECK(h.velocity==0 && h.velocityV==0,"guarded");

    if(failures){printf("KyantElasticTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: Kyant drag-speed deformation (FIX122 C): his defaults and formula, signed, capped, symmetric option, sensitivity / factors, velocity spring (.5, 300) overshoot and settle, guards.\n");
    return 0;
}
