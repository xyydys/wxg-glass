/* FIX122 B: Kyant 底栏's motion (Sources/WXGKyantMotion.h). */
#include "../Sources/WXGKyantMotion.h"
#include <stdio.h>

static int failures;
#define CHECK(cond,...) do{if(!(cond)){++failures;printf("FAIL %s:%d: ",__FILE__,__LINE__);printf(__VA_ARGS__);printf("\n");}}while(0)

int main(void) {
    /* Compose's spring(ratio, stiffness): critically damped never overshoots,
       .6 does; both settle. */
    double x=0,v=0,peak=0;
    for(int i=0;i<240;i++){WXGKyantSpring(&x,&v,1,1,1000,1./120);if(x>peak)peak=x;}
    CHECK(fabs(x-1)<1e-3 && peak<=1+1e-6,"spring(1,1000): settles, no overshoot (%.5f %.5f)",x,peak);
    x=1;v=0;peak=0;
    for(int i=0;i<480;i++){WXGKyantSpring(&x,&v,WXG_KYANT_PRESSED_SCALE,.6,250,1./120);if(x>peak)peak=x;}
    CHECK(peak>WXG_KYANT_PRESSED_SCALE+.01 && fabs(x-WXG_KYANT_PRESSED_SCALE)<1e-3,"spring(.6,250): overshoots then settles (%.4f)",peak);
    CHECK(fabs(WXGKyantDamping(.6,250)-2*.6*sqrt(250.))<1e-12,"damping 2 zeta sqrt(k)");
    /* 90% of spring(1,1000) at omega t = 3.89, omega = sqrt(1000): 0.123 s. */
    x=0;v=0;double t=0;while(x<.9 && t<1){WXGKyantSpring(&x,&v,1,1,1000,1./240);t+=1./240;}
    CHECK(t>.11 && t<.14,"spring(1,1000) reaches 90%% in %.3f s (critically damped: omega t = 3.89)",t);

    /* EaseOut: 0, 1, above the diagonal. */
    CHECK(fabs(WXGKyantEaseOut(0))<1e-9 && fabs(WXGKyantEaseOut(1)-1)<1e-9,"ease ends");
    for(double f=.05;f<1;f+=.05)CHECK(WXGKyantEaseOut(f)>f,"ease out above the diagonal at %.2f",f);

    /* Pressed: the lens grows to 78 / 56 both ways; released, back to 1. */
    WXGKyantMotion m;WXGKyantMotionReset(&m);m.started=1;
    for(int i=0;i<360;i++)WXGKyantMotionStep(&m,0,240,1,WXG_KYANT_PRESSED_SCALE,1,100,330,1./120);
    CHECK(fabs(m.scaleX-WXG_KYANT_PRESSED_SCALE)<1e-3 && fabs(m.scaleY-WXG_KYANT_PRESSED_SCALE)<1e-3,"pressed scale %.4f %.4f",m.scaleX,m.scaleY);
    CHECK(fabs(m.glow-1)<1e-3 && fabs(m.glowX-100)<1e-2,"glow on, at the lens");
    WXGKyantPose p=WXGKyantLayout(m,80,56,330,1,16,0);
    CHECK(fabs(p.width-80*78./56.)<.1 && fabs(p.height-78)<.1,"lens %.1f x %.1f",p.width,p.height);
    CHECK(fabs(p.barScale-(1+16./330.))<1e-9,"bar grows by 16 pt across its width");
    CHECK(fabs(WXGKyantLayout(m,80,56,330,0,16,0).barScale-1)<1e-12,"no growth at rest");
    for(int i=0;i<480;i++)WXGKyantMotionStep(&m,0,240,0,WXG_KYANT_PRESSED_SCALE,0,100,330,1./120);
    CHECK(fabs(m.scaleX-1)<1e-3 && fabs(m.scaleY-1)<1e-3 && fabs(m.glow)<1e-3,"released: back to rest");

    /* Velocity deformation, signed as his: moving right widens / flattens,
       moving left narrows / heightens; capped at 20%. */
    WXGKyantMotion r=m;r.velocity=1;   /* a whole tab range per second: v = .1 */
    WXGKyantPose pr=WXGKyantLayout(r,80,56,330,1,16,1);
    CHECK(fabs(pr.width-80/(1-.075))<1e-6 && fabs(pr.height-56*(1-.025))<1e-6,"right: %.3f x %.3f",pr.width,pr.height);
    WXGKyantMotion l=m;l.velocity=-1;
    WXGKyantPose pl=WXGKyantLayout(l,80,56,330,1,16,1);
    CHECK(pl.width<80 && pl.height>56,"left: narrower and taller (%.3f x %.3f)",pl.width,pl.height);
    WXGKyantMotion fast=m;fast.velocity=40;
    WXGKyantPose pf=WXGKyantLayout(fast,80,56,330,1,16,1);
    CHECK(fabs(pf.width-80/.8)<1e-6 && fabs(pf.height-56*.8)<1e-6,"capped at 20%%");
    CHECK(fabs(WXGKyantLayout(fast,80,56,330,1,16,0).width-80)<1e-9,"elastic off: no deformation");
    /* The velocity it sees follows the lens' speed per tab range. */
    WXGKyantMotion vm;WXGKyantMotionReset(&vm);vm.started=1;
    for(int i=0;i<240;i++)WXGKyantMotionStep(&vm,480,240,1,WXG_KYANT_PRESSED_SCALE,0,0,330,1./120);
    CHECK(fabs(vm.velocity-2)<1e-2,"velocity 480 pt/s over a 240 pt range = 2 (%.4f)",vm.velocity);

    /* Drift: 4 pt at most, toward the drag, eased; springs back released. */
    WXGKyantMotion d;WXGKyantMotionReset(&d);d.started=1;d.dragging=1;d.drag=-330;
    WXGKyantMotionStep(&d,0,240,1,WXG_KYANT_PRESSED_SCALE,0,0,330,1./120);
    CHECK(fabs(d.drift+4)<1e-6,"a full-width drag left: -4 pt (%.4f)",d.drift);
    d.drag=33;WXGKyantMotionStep(&d,0,240,1,WXG_KYANT_PRESSED_SCALE,0,0,330,1./120);
    CHECK(d.drift>.4 && d.drift<4*.25,"a tenth: eased (%.4f)",d.drift);
    d.dragging=0;for(int i=0;i<240;i++)WXGKyantMotionStep(&d,0,240,0,WXG_KYANT_PRESSED_SCALE,0,0,330,1./120);
    CHECK(fabs(d.drift)<1e-3,"released: back");

    /* Set down within 2.5% of the range. */
    CHECK(WXGKyantArrived(100,105.9,240) && !WXGKyantArrived(100,106.1,240),"arrival at 2.5%% of the range");
    /* The glow: full within half the radius, none past it, smooth. */
    CHECK(WXGKyantGlowSpot(0,96)==1 && WXGKyantGlowSpot(48,96)==1 && WXGKyantGlowSpot(96,96)==0 && WXGKyantGlowSpot(150,96)==0,"glow spot");
    CHECK(fabs(WXGKyantGlowSpot(72,96)-.5)<1e-9,"glow spot half way");

    if(failures){printf("KyantMotionTests: %d failure(s)\n",failures);return 1;}
    printf("PASS: Kyant motion (FIX122 B): Compose springs (critically damped, .6 overshoot, timing), EaseOut, pressed scale 78/56 and back, bar growth 16 pt, signed velocity deformation capped at 20%%, velocity per tab range, 4 pt eased drift, 2.5%% arrival, glow spot.\n");
    return 0;
}
